import { Router } from "express";
import multer from "multer";
import path from "path";
import {
  getChats,
  getMessages,
  createOrGetDirectChat,
  searchUsers,
  deleteConversation,
  clearChatMessages,
  getCallHistory,
  updateParticipantSettings,
  clearCallLogs,
} from "../controllers/chat.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configure multer storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, path.join(__dirname, "../../uploads"));
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  },
});

const fileFilter = (req: any, file: any, cb: any) => {
  const allowed = [
    "image/", "video/", "audio/",
    "application/pdf",
    "application/zip",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/",
    "application/octet-stream",
  ];
  if (allowed.some((type) => file.mimetype.startsWith(type))) {
    cb(null, true);
  } else {
    cb(new Error("File type not allowed"), false);
  }
};

const upload = multer({ storage, fileFilter, limits: { fileSize: 50 * 1024 * 1024 } }); // 50 MB limit

const router = Router();

// Secure all chat routes
router.use(authenticateToken as any);

router.get("/", getChats as any);
router.get("/calls", getCallHistory as any);
router.get("/search", searchUsers as any);
router.get("/:conversationId/messages", getMessages as any);
router.post("/direct", createOrGetDirectChat as any);
router.delete("/:conversationId", deleteConversation as any);
router.delete("/:conversationId/messages", clearChatMessages as any);
router.patch("/:conversationId/participant", updateParticipantSettings as any);
router.delete("/calls/clear", clearCallLogs as any);

// Upload endpoint
router.post("/upload", (req: any, res: any) => {
  upload.single("file")(req, res, (err: any) => {
    if (err) {
      console.error("[Multer Error]", err);
      return res.status(400).json({ message: err.message || "File upload error" });
    }

    try {
      if (!req.file) {
        res.status(400).json({ message: "No file uploaded" });
        return;
      }

      // Build relative file URL with timestamp to prevent caching
      const fileUrl = `/uploads/${req.file.filename}?v=${Date.now()}`;

      res.json({
        fileUrl,
        fileName: req.file.originalname,
        fileType: req.file.mimetype,
        size: req.file.size,
      });
    } catch (error) {
      console.error("Upload handler error:", error);
      res.status(500).json({ message: "File upload processing failed" });
    }
  });
});

export default router;
