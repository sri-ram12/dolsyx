import "dotenv/config";
import express from "express";
import http from "http";
import dns from "dns";

dns.setDefaultResultOrder("ipv4first");
import { Server } from "socket.io";
import cors from "cors";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import { spawn } from "child_process";
import net from "net";
import { createProxyMiddleware } from "http-proxy-middleware";
import authRoutes from "./routes/auth.routes.js";
import chatRoutes from "./routes/chat.routes.js";
import groupRoutes from "./routes/group.routes.js";
import productivityRoutes from "./routes/productivity.routes.js";
import statusRoutes from "./routes/status.routes.js";
import contactRoutes from "./routes/contact.routes.js";
import uploadRoutes from "./routes/upload.routes.js";
import keyRoutes from "./routes/key.routes.js";
import messageRoutes from "./routes/message.routes.js";
import backupRoutes from "./routes/backup.routes.js";
import aiRoutes from "./routes/ai.routes.js";
import deviceRoutes from "./routes/device.routes.js";
import { initChatSocket } from "./sockets/chat.socket.js";
import { initCronJobs } from "./utils/cron.jobs.js";
import { initFirebase } from "./config/firebase.config.js";
import { prisma } from "./config/db.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

const PORT = process.env.PORT || 4000;
const IS_PRODUCTION = process.env.NODE_ENV === "production";

const DEFAULT_ALLOWED_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:3001",
  "http://localhost:4000",
  "http://localhost:5173",
  "https://dolsyx-app.onrender.com",
];

const FRONTEND_URLS = [
  ...DEFAULT_ALLOWED_ORIGINS,
  ...(process.env.FRONTEND_URL ? process.env.FRONTEND_URL.split(",").map((u) => u.trim()) : []),
].filter(Boolean);

const isAllowedOrigin = (origin: string): boolean => {
  const clean = origin.replace(/\/+$/, "");
  if (FRONTEND_URLS.some((u) => u === "*" || u.replace(/\/+$/, "") === clean)) {
    return true;
  }
  // Allow onrender, vercel, localhost, and local network IPs
  if (
    clean.endsWith(".onrender.com") ||
    clean.endsWith(".vercel.app") ||
    clean.startsWith("http://localhost:") ||
    clean.startsWith("http://127.0.0.1:") ||
    clean.startsWith("http://192.168.") ||
    clean.startsWith("http://10.0.")
  ) {
    return true;
  }
  return false;
};

const corsOriginFn = (
  origin: string | undefined,
  callback: (err: Error | null, allow?: boolean) => void
) => {
  if (!origin) return callback(null, true); // Allow non-browser requests (mobile apps, curl, etc.)
  
  // Allow all origins in local development for LAN and multi-device testing
  if (!IS_PRODUCTION) return callback(null, true);

  if (isAllowedOrigin(origin)) {
    return callback(null, true);
  }

  console.warn(`[CORS] Rejected unlisted origin: ${origin}`);
  return callback(null, false); // Deny CORS headers without crashing Express pipeline with 500 error
};

import compression from "compression";
import cookieParser from "cookie-parser";

// ── Middleware ───────────────────────────────────────────────────────────────
// Trust proxy headers (for tunnels like serveo/ngrok where X-Forwarded-Proto is https)
app.set("trust proxy", 1);
app.use(compression());
app.use(cookieParser());
app.use(cors({ origin: corsOriginFn, credentials: true }));
app.use(express.json({ limit: "10mb" }));

const staticOptions = {
  maxAge: "30d",
  etag: true,
  acceptRanges: true,
  setHeaders: (res: express.Response) => {
    res.setHeader("Cache-Control", "public, max-age=2592000, immutable");
  },
};

app.use("/uploads", express.static(path.join(process.cwd(), "uploads"), staticOptions));
const uploadsDir = path.join(__dirname, "../uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
app.use("/uploads", express.static(uploadsDir, staticOptions));

// ── API Routes ───────────────────────────────────────────────────────────────
app.use("/api/auth", authRoutes);
app.use("/api/chats", chatRoutes);
app.use("/api/groups", groupRoutes);
app.use("/api/productivity", productivityRoutes);
app.use("/api/status", statusRoutes);
app.use("/api/contacts", contactRoutes);
app.use("/api/uploads", uploadRoutes);
app.use("/api/keys", keyRoutes);
app.use("/api/messages", messageRoutes);
app.use("/api/backups", backupRoutes);
app.use("/api/ai", aiRoutes);
app.use("/api/devices", deviceRoutes);
// ── Initialize Background Jobs & SDKs ──────────────────────────────────────────
initFirebase();
initCronJobs();

// ── Deep Health & Readiness Checks ──────────────────────────────────────────
app.get("/health/live", (_req, res) => {
  res.status(200).json({ status: "alive", uptimeSeconds: Math.floor(process.uptime()) });
});

app.get("/health/ready", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.status(200).json({ status: "ready", database: "connected" });
  } catch (err: any) {
    res.status(503).json({ status: "unready", database: "disconnected", error: err.message });
  }
});

app.get("/health", async (_req, res) => {
  const startTime = Date.now();
  let dbStatus = "connected";
  let dbLatencyMs = 0;
  try {
    await prisma.$queryRaw`SELECT 1`;
    dbLatencyMs = Date.now() - startTime;
  } catch (_e) {
    dbStatus = "disconnected";
  }

  const mem = process.memoryUsage();
  const healthData = {
    status: dbStatus === "connected" ? "healthy" : "degraded",
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(process.uptime()),
    database: {
      status: dbStatus,
      latencyMs: dbLatencyMs,
    },
    memory: {
      heapUsedMB: Math.round(mem.heapUsed / 1024 / 1024),
      rssMB: Math.round(mem.rss / 1024 / 1024),
    },
    environment: process.env.NODE_ENV || "development",
  };

  const statusCode = dbStatus === "connected" ? 200 : 503;
  res.status(statusCode).json(healthData);
});

// ── Socket.io ────────────────────────────────────────────────────────────────
const io = new Server(server, {
  cors: {
    origin: corsOriginFn,
    methods: ["GET", "POST"],
    credentials: true,
  },
  perMessageDeflate: {
    threshold: 1024, // Compress WebSocket frames > 1KB
  },
  pingInterval: 10000, // 10s heartbeat for quick drop detection
  pingTimeout: 5000,   // 5s timeout to trigger fast reconnect
  maxHttpBufferSize: 1e7, // 10MB limit for efficient streaming
});
app.set("io", io);
initChatSocket(io);

// ── Serve Next.js Frontend (Monolith & Dev Proxy) ────────────────────────────
const NEXT_PORT = IS_PRODUCTION ? 3001 : 3000;

if (IS_PRODUCTION) {
  const nextStandalonePath = path.join(__dirname, "../../frontend/.next/standalone");

  // Helper to find server.js recursively (handles nested OneDrive paths)
  const findNextServerJs = (dir: string): string | null => {
    try {
      const files = fs.readdirSync(dir);
      for (const file of files) {
        const fullPath = path.join(dir, file);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          if (file === "node_modules") continue;
          const found = findNextServerJs(fullPath);
          if (found) return found;
        } else if (file === "server.js") {
          return fullPath;
        }
      }
    } catch (_e) { /* ignore */ }
    return null;
  };

  const serverJsPath = findNextServerJs(nextStandalonePath);
  if (!serverJsPath) {
    console.error(`[Monolith] Cannot find server.js under ${nextStandalonePath}`);
  } else {
    const serverDir = path.dirname(serverJsPath);
    
    // Self-healing Next.js standalone process supervisor with exponential backoff
    let nextProcess: any = null;
    let nextRestartCount = 0;
    const MAX_NEXT_RESTARTS = 10;

    const spawnNextJsServer = () => {
      console.log(`[Monolith Supervisor] Spawning Next.js standalone server from: ${serverDir}`);
      nextProcess = spawn(process.execPath, [serverJsPath], {
        cwd: serverDir,
        env: { ...process.env, PORT: String(NEXT_PORT), HOSTNAME: "127.0.0.1", NODE_ENV: "production" },
        stdio: "inherit",
      });

      nextProcess.on("error", (err: Error) => {
        console.error("[Monolith Supervisor] Next.js process error:", err);
      });

      nextProcess.on("exit", (code: number, signal: string) => {
        console.warn(`[Monolith Supervisor] Next.js process exited with code ${code}, signal: ${signal}`);
        nextJsReady = false;
        if (nextRestartCount < MAX_NEXT_RESTARTS) {
          nextRestartCount++;
          const delay = Math.min(1000 * Math.pow(2, nextRestartCount), 30000);
          console.log(`[Monolith Supervisor] Auto-restarting Next.js in ${delay}ms (attempt ${nextRestartCount}/${MAX_NEXT_RESTARTS})...`);
          setTimeout(() => {
            spawnNextJsServer();
            waitForNextJs();
          }, delay);
        } else {
          console.error("[Monolith Supervisor] Maximum restart limit reached for Next.js process.");
        }
      });
    };

    spawnNextJsServer();

    // Serve Next.js public/static files directly
    const nextStaticPath = path.join(__dirname, "../../frontend/.next/static");
    const nextPublicPath = path.join(__dirname, "../../frontend/public");
    app.use("/_next/static", express.static(nextStaticPath));
    app.use("/", express.static(nextPublicPath));
  }
}

// Track whether Next.js is ready to accept connections
let nextJsReady = false;

// Poll until the Next.js port is open, then mark ready
const waitForNextJs = () => {
  const check = () => {
    const sock = new net.Socket();
    sock.setTimeout(500);
    sock
      .on("connect", () => {
        sock.destroy();
        if (!nextJsReady) {
          nextJsReady = true;
          console.log(`[Monolith] Next.js is ready on port ${NEXT_PORT}`);
        }
      })
      .on("error", () => { sock.destroy(); setTimeout(check, 500); })
      .on("timeout", () => { sock.destroy(); setTimeout(check, 500); })
      .connect(NEXT_PORT, "127.0.0.1");
  };
  check();
};

if (IS_PRODUCTION) waitForNextJs();
else nextJsReady = true; // In dev the Next.js dev server manages itself

const nextProxy = createProxyMiddleware({
  target: `http://127.0.0.1:${NEXT_PORT}`,
  changeOrigin: true,
  ws: true, // MUST be true for Next.js Hot Reloading (HMR) to work via /_next/webpack-hmr
  on: {
    error: (err: Error, req: any, res: any) => {
      // Suppress noisy ECONNREFUSED logs during startup window
      if (!nextJsReady) return;
      console.error("[Monolith Proxy] Error forwarding request:", (err as any).message);
      // res may be a Socket for WS errors - only call writeHead on real HTTP responses
      if (res && typeof res.writeHead === "function" && !res.headersSent) {
        res.writeHead(502, { "Content-Type": "text/plain" });
        res.end("Frontend is starting up or unavailable. Please reload in a moment.");
      } else if (res && typeof res.end === "function") {
        try { res.end(); } catch (_) {}
      }
    },
  },
} as any);

// Only proxy non-API, non-socket, non-static routes to Next.js
app.use((req, res, next) => {
  const p = req.path;
  if (
    p.startsWith("/api") ||
    p.startsWith("/socket.io") ||
    p.startsWith("/health") ||
    p.startsWith("/uploads")
  ) {
    return next();
  }
  // If Next.js isn't up yet, return 503 with retry header instead of logging an error
  if (!nextJsReady) {
    res.setHeader("Retry-After", "3");
    res.status(503).send("Server is starting up. Please refresh in a moment.");
    return;
  }
  return (nextProxy as any)(req, res, next);
});

// ── Centralized Express Error Handling Middleware ─────────────────────────────
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  const status = err.status || err.statusCode || 500;
  console.error(`[Global Error Handler] [${req.method} ${req.url}]:`, err.message || err);

  if (res.headersSent) {
    return next(err);
  }

  res.status(status).json({
    error: true,
    message: IS_PRODUCTION && status === 500 ? "Internal server error" : (err.message || "An unexpected error occurred"),
    timestamp: new Date().toISOString(),
  });
});

// ── Process-Level Safety Traps ────────────────────────────────────────────────
process.on("uncaughtException", (err: Error) => {
  console.error("[CRITICAL] Uncaught Exception trapped:", err);
});

process.on("unhandledRejection", (reason: any) => {
  console.error("[CRITICAL] Unhandled Promise Rejection trapped:", reason);
});

// ── Graceful Shutdown ─────────────────────────────────────────────────────────
const gracefulShutdown = async (signal: string) => {
  console.log(`[Lifecycle] Received ${signal}. Initiating graceful shutdown...`);
  server.close(async () => {
    console.log("[Lifecycle] HTTP server stopped accepting new connections.");
    try {
      await prisma.$disconnect();
      console.log("[Lifecycle] Prisma database connection closed.");
      process.exit(0);
    } catch (e) {
      console.error("[Lifecycle] Error disconnecting Prisma during shutdown:", e);
      process.exit(1);
    }
  });

  // Force close after 10 seconds if graceful drain stalls
  setTimeout(() => {
    console.error("[Lifecycle] Shutdown timed out. Forcing process exit.");
    process.exit(1);
  }, 10000).unref();
};

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(
    `DOLSYX server running on port ${PORT} [${IS_PRODUCTION ? "production monolith" : "dev API only"}]`
  );
});
