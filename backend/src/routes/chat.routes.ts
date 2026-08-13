import { Router } from "express";
import multer from "multer";
import path from "path";
import {
  getChats,
  getMessages,
  getMediaMessages,
  createOrGetDirectChat,
  searchUsers,
  deleteConversation,
  clearChatMessages,
  getCallHistory,
  updateParticipantSettings,
  clearCallLogs,
  deleteSingleCallLog,
  deleteBulkCallLogs,
  starMessage,
  pinMessage,
  deleteMessage,
  uploadChunk,
} from "../controllers/chat.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

import { getCloudinaryStorage } from "../config/cloudinary.config.js";

const storage = getCloudinaryStorage("dolsyx_chats");

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
router.delete("/calls/clear", clearCallLogs as any);
router.delete("/calls/bulk", deleteBulkCallLogs as any);
router.delete("/calls/:callId", deleteSingleCallLog as any);
router.get("/search", searchUsers as any);
router.get("/:conversationId/media", getMediaMessages as any);
router.get("/:conversationId/messages", getMessages as any);
router.post("/direct", createOrGetDirectChat as any);
router.delete("/:conversationId", deleteConversation as any);
router.delete("/:conversationId/messages", clearChatMessages as any);
router.patch("/:conversationId/participant", updateParticipantSettings as any);

// Message management routes
router.post("/messages/:messageId/star", starMessage as any);
router.delete("/messages/:messageId", deleteMessage as any);
router.post("/:conversationId/messages/:messageId/pin", pinMessage as any);

// Upload endpoints
router.post("/upload-chunk", upload.single("file"), uploadChunk as any);
router.post("/upload", (req: any, res: any) => {
  upload.any()(req, res, (err: any) => {
    if (err) {
      console.error("[Multer Error]", err);
      return res.status(400).json({ message: err.message || "File upload error" });
    }

    try {
      const files = req.files as Express.Multer.File[] | undefined;
      if (!files || files.length === 0) {
        res.status(400).json({ message: "No file uploaded" });
        return;
      }

      const getCleanUrl = (f: Express.Multer.File) => {
        if (f.path && (f.path.startsWith("http://") || f.path.startsWith("https://"))) {
          return f.path;
        }
        return `/uploads/${f.filename}`;
      };

      const uploadedFiles = files.map((f) => ({
        fileUrl: getCleanUrl(f),
        url: getCleanUrl(f),
        fileName: f.originalname,
        fileType: f.mimetype,
        size: f.size,
      }));

      const first = uploadedFiles[0]!;
      res.json({
        fileUrl: first.fileUrl,
        url: first.url,
        fileName: first.fileName,
        fileType: first.fileType,
        size: first.size,
        files: uploadedFiles,
      });
    } catch (error) {
      console.error("Upload handler error:", error);
      res.status(500).json({ message: "File upload processing failed" });
    }
  });
});

export default router;
