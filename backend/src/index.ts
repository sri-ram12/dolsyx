import express from "express";
import http from "http";
import { Server } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";
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
app.use(cors({ origin: corsOriginFn, credentials: true }));
app.use(express.json({ limit: "10mb" }));
app.use("/uploads", express.static(path.join(__dirname, "../../backend/uploads")));

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

// ── Serve Next.js Frontend in Production ─────────────────────────────────────
if (IS_PRODUCTION) {
  // Path to the Next.js standalone server output
  const nextStandalonePath = path.join(__dirname, "../../frontend/.next/standalone");
  const nextStaticPath = path.join(__dirname, "../../frontend/.next/static");
  const nextPublicPath = path.join(__dirname, "../../frontend/public");

  // Serve Next.js static assets
  app.use("/_next/static", express.static(nextStaticPath));
  app.use("/public", express.static(nextPublicPath));

  // Serve all other routes via Next.js standalone server
  app.all("*", async (req, res) => {
    try {
      const { default: nextServer } = await import(
        path.join(nextStandalonePath, "server.js")
      ) as { default: (req: express.Request, res: express.Response) => void };
      nextServer(req, res);
    } catch {
      res.status(500).send("Frontend server error");
    }
  });
}

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(
    `DOLSYX server running on port ${PORT} [${IS_PRODUCTION ? "production monolith" : "dev API only"}]`
  );
});
