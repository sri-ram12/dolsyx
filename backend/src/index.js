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
const FRONTEND_URL = process.env.FRONTEND_URL || "http://localhost:3000";
// Middleware
app.use(cors({
    origin: FRONTEND_URL,
    credentials: true,
}));
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
        origin: FRONTEND_URL,
        methods: ["GET", "POST"],
        credentials: true,
    },
});
app.set("io", io);
initChatSocket(io);
server.listen(PORT, () => {
    console.log(`DOLSYX Backend server running on port ${PORT}`);
});
//# sourceMappingURL=index.js.map