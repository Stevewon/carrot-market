import { Server } from 'socket.io';
import { verifyToken } from './auth.js';
import db from './db.js';

/**
 * Ephemeral chat relay.
 * - NO messages are persisted (no DB, no file).
 * - Server only forwards messages to connected peers in the same room.
 * - Room rosters live in memory; cleared on disconnect.
 */
export function attachChat(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: '*' },
    maxHttpBufferSize: 2e6, // 2MB
  });

  // JWT auth on handshake
  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Unauthorized'));
    const payload = verifyToken(token);
    if (!payload) return next(new Error('Invalid token'));
    socket.userId = payload.id;
    socket.nickname = payload.nickname;
    next();
  });

  // Map<roomId, Set<socketId>>
  const rooms = new Map();
  // Map<userId, socketId> - for direct user addressing (calls)
  const userSockets = new Map();

  io.on('connection', (socket) => {
    console.log(`[chat] + ${socket.nickname} (${socket.userId}) connected`);
    userSockets.set(socket.userId, socket.id);

    socket.on('join_room', ({ room_id, peer_nickname, product_id }) => {
      if (!room_id) return;
      socket.join(room_id);
      rooms.set(room_id, rooms.get(room_id) || new Set());
      rooms.get(room_id).add(socket.id);

      // Bump chat_count on first join (per socket session)
      if (product_id) {
        try {
          db.prepare('UPDATE products SET chat_count = chat_count + 1 WHERE id = ?').run(product_id);
        } catch {}
      }

      socket.to(room_id).emit('system', {
        text: `${socket.nickname} 님이 대화에 참여했어요`,
      });
    });

    socket.on('leave_room', ({ room_id }) => {
      if (!room_id) return;
      socket.leave(room_id);
      rooms.get(room_id)?.delete(socket.id);
      socket.to(room_id).emit('system', {
        text: `${socket.nickname} 님이 대화를 떠났어요`,
      });
    });

    socket.on('message', ({ room_id, text, sender_nickname }) => {
      if (!room_id || typeof text !== 'string' || text.trim() === '') return;

      const msg = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        room_id,
        sender_id: socket.userId,
        sender_nickname: sender_nickname || socket.nickname || '익명',
        text: text.slice(0, 2000),
        type: 'text',
        sent_at: new Date().toISOString(),
      };

      // Broadcast to everyone in the room INCLUDING sender (so sender sees own msg)
      io.to(room_id).emit('message', msg);
    });

    // ========================================================
    // 📞 VOICE CALL SIGNALING (WebRTC)
    // - Server only relays SDP offers/answers and ICE candidates.
    // - No audio data passes through the server (pure P2P).
    // - Caller sends 'call_invite' → server forwards to callee
    //   via their userId → callee's app shows incoming call UI.
    // ========================================================

    /** Incoming call request: caller → server → callee */
    socket.on('call_invite', ({ to_user_id, call_id, caller_nickname }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) {
        // Callee offline
        socket.emit('call_failed', {
          call_id,
          reason: 'offline',
          message: '상대방이 접속 중이 아니에요',
        });
        return;
      }
      io.to(targetSocketId).emit('call_incoming', {
        call_id,
        from_user_id: socket.userId,
        caller_nickname: caller_nickname || socket.nickname,
      });
    });

    /** Callee answers (accept/reject) */
    socket.on('call_response', ({ to_user_id, call_id, accepted }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) return;
      io.to(targetSocketId).emit('call_response', {
        call_id,
        accepted,
        from_user_id: socket.userId,
      });
    });

    /** WebRTC offer (from caller to callee) */
    socket.on('webrtc_offer', ({ to_user_id, call_id, sdp }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) return;
      io.to(targetSocketId).emit('webrtc_offer', {
        call_id,
        from_user_id: socket.userId,
        sdp,
      });
    });

    /** WebRTC answer (from callee to caller) */
    socket.on('webrtc_answer', ({ to_user_id, call_id, sdp }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) return;
      io.to(targetSocketId).emit('webrtc_answer', {
        call_id,
        from_user_id: socket.userId,
        sdp,
      });
    });

    /** ICE candidate exchange */
    socket.on('webrtc_ice', ({ to_user_id, call_id, candidate }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) return;
      io.to(targetSocketId).emit('webrtc_ice', {
        call_id,
        from_user_id: socket.userId,
        candidate,
      });
    });

    /** Either side ends the call */
    socket.on('call_end', ({ to_user_id, call_id }) => {
      const targetSocketId = userSockets.get(to_user_id);
      if (!targetSocketId) return;
      io.to(targetSocketId).emit('call_end', {
        call_id,
        from_user_id: socket.userId,
      });
    });

    socket.on('disconnect', () => {
      console.log(`[chat] - ${socket.nickname} disconnected`);
      userSockets.delete(socket.userId);
      // Cleanup rosters
      for (const [roomId, set] of rooms) {
        if (set.delete(socket.id)) {
          socket.to(roomId).emit('system', {
            text: `${socket.nickname} 님이 연결을 종료했어요`,
          });
        }
        if (set.size === 0) rooms.delete(roomId);
      }
    });
  });

  return io;
}
