import express from "express";
import http from "http";
import { Server } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import { spawn } from "child_process";
import { createProxyMiddleware } from "http-proxy-middleware";
import authRoutes from "./routes/auth.routes.js";
import chatRoutes from "./routes/chat.routes.js";
import groupRoutes from "./routes/group.routes.js";
import productivityRoutes from "./routes/productivity.routes.js";
import statusRoutes from "./routes/status.routes.js";
import { initChatSocket } from "./sockets/chat.socket.js";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

const PORT = process.env.PORT || 4000;
const IS_PRODUCTION = process.env.NODE_ENV === "production";

// In production (monolith), CORS is not needed as frontend is served from same origin.
// In dev, allow localhost:3000 + any comma-separated FRONTEND_URL entries.
const FRONTEND_URLS = (process.env.FRONTEND_URL || "http://localhost:3000")
  .split(",")
  .map((u) => u.trim())
  .filter(Boolean);

const corsOriginFn = (
  origin: string | undefined,
  callback: (err: Error | null, allow?: boolean) => void
) => {
  if (!origin) return callback(null, true); // Allow non-browser requests
  if (IS_PRODUCTION) return callback(null, true); // Same-origin in production
  if (FRONTEND_URLS.includes(origin) || FRONTEND_URLS.includes("*")) {
    return callback(null, true);
  }
  callback(new Error(`CORS: origin ${origin} not allowed`));
};

// ── Middleware ───────────────────────────────────────────────────────────────
// Trust proxy headers (for tunnels like serveo/ngrok where X-Forwarded-Proto is https)
app.set("trust proxy", 1);
app.use(cors({ origin: corsOriginFn, credentials: true }));
app.use(express.json({ limit: "10mb" }));
const uploadsDir = path.join(__dirname, "../uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
app.use("/uploads", express.static(uploadsDir));

// ── API Routes ───────────────────────────────────────────────────────────────
app.use("/api/auth", authRoutes);
app.use("/api/chats", chatRoutes);
app.use("/api/groups", groupRoutes);
app.use("/api/productivity", productivityRoutes);
app.use("/api/status", statusRoutes);

// ── Health Check ─────────────────────────────────────────────────────────────
app.get("/health", (_req, res) => {
  res.json({ status: "healthy", timestamp: new Date() });
});

// ── Socket.io ────────────────────────────────────────────────────────────────
const io = new Server(server, {
  cors: {
    origin: corsOriginFn,
    methods: ["GET", "POST"],
    credentials: true,
  },
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
    console.log(`[Monolith] Spawning Next.js standalone server from: ${serverDir}`);

    // Spawn the Next.js standalone server on its own port
    const nextProcess = spawn(process.execPath, [serverJsPath], {
      cwd: serverDir,
      env: { ...process.env, PORT: String(NEXT_PORT), HOSTNAME: "127.0.0.1", NODE_ENV: "production" },
      stdio: "inherit",
    });
    nextProcess.on("error", (err: Error) => console.error("[Monolith] Next.js process error:", err));
    nextProcess.on("exit", (code: number) => console.warn(`[Monolith] Next.js process exited with code ${code}`));

    // Serve Next.js public/static files directly
    const nextStaticPath = path.join(__dirname, "../../frontend/.next/static");
    const nextPublicPath = path.join(__dirname, "../../frontend/public");
    app.use("/_next/static", express.static(nextStaticPath));
    // Serve Next.js public files at root level (so /default-male.svg etc. work)
    app.use("/", express.static(nextPublicPath));
  }
}

const nextProxy = createProxyMiddleware({
  target: `http://127.0.0.1:${NEXT_PORT}`,
  changeOrigin: true,
  ws: true, // MUST be true for Next.js Hot Reloading (HMR) to work via /_next/webpack-hmr
  on: {
    error: (err: Error, req: any, res: any) => {
      console.error("[Monolith Proxy] Error forwarding request:", err.message);
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
  return (nextProxy as any)(req, res, next);
});

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(
    `DOLSYX server running on port ${PORT} [${IS_PRODUCTION ? "production monolith" : "dev API only"}]`
  );
});
