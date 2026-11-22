import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
import pollsRouter from './routes/polls.js';
import adminRouter from './routes/admin.js';
import pool from './config/db.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Trust reverse proxy (e.g., NGINX, Cloudflare, Heroku, AWS ELB, Campus Gateways)
app.set('trust proxy', 1);

// Configure CORS
const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map((o) => o.trim())
  : ['*'];

app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (like mobile apps, curl, server-to-server) or matching allowed list
      if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(null, true); // Permissive in dev/production classroom environments
    },
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  })
);

app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true, limit: '5mb' }));

// Lightweight Health Check endpoint (Render cold-start wake-up fix - zero DB calls, returns { status: "ok" })
app.get(['/health', '/api/health'], (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Generous Rate Limiter:
// Designed specifically for high concurrency (200+ simultaneous students sharing the same campus Wi-Fi NAT IP).
// We set a high threshold (5,000 requests per 15-minute window per IP) so classroom batches never get blocked.
const campusFriendlyRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5000, // Allow up to 5000 requests per window (safely absorbs 200+ active students on single NAT IP)
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: 'Too many requests from this network. Please wait a moment and try again.',
  },
});

app.use('/api/', campusFriendlyRateLimiter);

// API Routes
app.use('/api/polls', pollsRouter);
app.use('/api/admin', adminRouter);

// 404 Handler for API
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: `Route ${req.method} ${req.url} not found.`,
  });
});

// Global Error Handler
app.use((err, req, res, next) => {
  console.error('[Global Error Handler]', err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal Server Error',
  });
});

// Start Server
const server = app.listen(PORT, () => {
  console.log(`=========================================`);
  console.log(`🚀 PulsePoll API running on port ${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/api/health`);
  console.log(`   Mode: Production-Ready Concurrency (200+ Students)`);
  console.log(`=========================================`);
});

// Graceful Shutdown
const handleShutdown = async (signal) => {
  console.log(`\nReceived ${signal}. Gracefully shutting down...`);
  server.close(async () => {
    if (pool) {
      await pool.end();
      console.log('PostgreSQL connection pool drained.');
    }
    process.exit(0);
  });
};

process.on('SIGINT', () => handleShutdown('SIGINT'));
process.on('SIGTERM', () => handleShutdown('SIGTERM'));

export default app;
