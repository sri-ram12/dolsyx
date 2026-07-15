import express from "express";
import http from "http";
import { Server } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";
import authRoutes from "./routes/auth.routes.js";
import chatRoutes from "./routes/chat.routes.js";
import groupRoutes from "./routes/group.routes.js";
import productivityRoutes from "./routes/productivity.routes.js";
import statusRoutes from "./routes/status.routes.js";
import { initChatSocket } from "./sockets/chat.socket.js";

dotenv.config();

const app = express();
const server = http.createServer(app);

const PORT = process.env.PORT || 4000;

// Support multiple comma-separated frontend origins (e.g., for tunnels + localhost)
const FRONTEND_URLS = (process.env.FRONTEND_URL || "http://localhost:3000")
  .split(",")
  .map((u) => u.trim())
  .filter(Boolean);

const corsOriginFn = (origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) => {
  // Allow requests with no origin (e.g., mobile apps, curl)
  if (!origin) return callback(null, true);
  if (FRONTEND_URLS.includes(origin) || FRONTEND_URLS.includes("*")) {
    return callback(null, true);
  }
  callback(new Error(`CORS: origin ${origin} not allowed`));
};

// Middleware
app.use(
  cors({
    origin: corsOriginFn,
    credentials: true,
  })
);
app.use(express.json());
app.use("/uploads", express.static("uploads"));

// Routes
app.use("/api/auth", authRoutes);
app.use("/api/chats", chatRoutes);
app.use("/api/groups", groupRoutes);
app.use("/api/productivity", productivityRoutes);
app.use("/api/status", statusRoutes);

// Health Check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", timestamp: new Date() });
});

// Socket.io initialization
const io = new Server(server, {
  cors: {
    origin: corsOriginFn,
    methods: ["GET", "POST"],
    credentials: true,
  },
});

app.set("io", io);

initChatSocket(io);

server.listen(PORT, () => {
  console.log(`DOLSYX Backend server running on port ${PORT}`);
});
