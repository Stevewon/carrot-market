import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import http from 'http';
import path from 'path';
import { fileURLToPath } from 'url';

import './db.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import productRoutes from './routes/products.js';
import { attachChat } from './chat.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ======================================================================
// Process-level crash handlers. Without these, any uncaught exception
// silently kills Node so the client sees "Connection closed before full
// header was received". We log and keep the process alive.
// ======================================================================
process.on('uncaughtException', (err) => {
  console.error('[FATAL] uncaughtException:', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] unhandledRejection:', reason);
});

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// Request logger so we can see every call in the server console.
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    console.log(`[${res.statusCode}] ${req.method} ${req.originalUrl} - ${ms}ms`);
  });
  res.on('close', () => {
    if (!res.writableEnded) {
      console.warn(`[ABORTED] ${req.method} ${req.originalUrl}`);
    }
  });
  next();
});

// Static uploads
app.use('/uploads', express.static(path.join(__dirname, 'uploads'), {
  maxAge: '7d',
}));

// Health check
app.get('/', (req, res) => {
  res.json({
    name: 'Eggplant API',
    version: '0.1.0',
    status: '🍆 online',
    endpoints: {
      auth: '/api/auth/*',
      users: '/api/users/*',
      products: '/api/products/*',
      chat: 'ws (socket.io)',
    },
  });
});

app.get('/api', (req, res) => {
  res.json({
    name: 'Eggplant API',
    version: '0.1.0',
    status: 'online',
    endpoints: {
      auth: '/api/auth/*',
      users: '/api/users/*',
      products: '/api/products/*',
      chat: 'WebSocket (socket.io)',
    },
  });
});

app.get('/health', (req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/products', productRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.originalUrl });
});

// Error handler (last)
app.use((err, req, res, next) => {
  console.error('[error]', req.method, req.originalUrl, '→', err);
  if (res.headersSent) return next(err);
  res.status(500).json({ error: err.message || 'Internal error' });
});

const PORT = process.env.PORT || 3001;
const server = http.createServer(app);

// Avoid keep-alive hangs with certain HTTP clients (Dio on Android).
server.keepAliveTimeout = 60_000;
server.headersTimeout = 65_000;

attachChat(server);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🍆 Eggplant server listening on http://0.0.0.0:${PORT}`);
  console.log(`   API:    http://0.0.0.0:${PORT}/api`);
  console.log(`   Socket: ws://0.0.0.0:${PORT}\n`);
});
