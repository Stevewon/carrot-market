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

  io.on('connection', (socket) => {
    console.log(`[chat] + ${socket.nickname} (${socket.userId}) connected`);

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

    socket.on('disconnect', () => {
      console.log(`[chat] - ${socket.nickname} disconnected`);
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
