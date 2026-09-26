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
  editMessage,
  uploadChunk,
} from "../controllers/chat.controller.js";
import {
  createBroadcastList,
  getBroadcastLists,
  sendBroadcastMessage,
  updateBroadcastRecipients,
  deleteBroadcastList,
} from "../controllers/broadcast.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

import fs from "fs";
import cloudinary, { getCloudinaryStorage } from "../config/cloudinary.config.js";

const cloudinaryStorage = getCloudinaryStorage("dolsyx_chats");

const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = "uploads/";
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname || ""));
  },
});

const fileFilter = (_req: any, _file: any, cb: any) => {
  cb(null, true);
};

const upload = multer({ storage: cloudinaryStorage, fileFilter, limits: { fileSize: 200 * 1024 * 1024 } }); // 200 MB limit
const diskUpload = multer({ storage: diskStorage, fileFilter, limits: { fileSize: 200 * 1024 * 1024 } });

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

// ── Phase 18: Broadcast List routes ─────────────────────────────────────────
router.get("/broadcasts", getBroadcastLists as any);
router.post("/broadcasts", createBroadcastList as any);
router.post("/broadcasts/:broadcastId/send", sendBroadcastMessage as any);
router.patch("/broadcasts/:broadcastId/recipients", updateBroadcastRecipients as any);
router.delete("/broadcasts/:broadcastId", deleteBroadcastList as any);

// Message management routes
router.put("/messages/:messageId", editMessage as any);
router.post("/messages/:messageId/star", starMessage as any);
router.delete("/messages/:messageId", deleteMessage as any);
router.post("/:conversationId/messages/:messageId/pin", pinMessage as any);

// Upload endpoints
router.get("/upload/sign", (req: any, res: any) => {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;

  if (!cloudName || !apiKey || !apiSecret) {
    return res.status(200).json({
      directUploadAvailable: false,
      message: "Cloud storage direct upload not configured, use /api/chats/upload",
    });
  }

  const timestamp = Math.round(Date.now() / 1000);
  const folder = (req.query.folder as string) || "dolsyx_chats";
  const signature = cloudinary.utils.api_sign_request(
    { timestamp, folder },
    apiSecret
  );

  return res.status(200).json({
    directUploadAvailable: true,
    signature,
    timestamp,
    apiKey,
    cloudName,
    folder,
    uploadUrl: `https://api.cloudinary.com/v1_1/${cloudName}/auto/upload`,
  });
});

router.post("/upload-chunk", upload.single("file"), uploadChunk as any);

const handleFilesResponse = (req: any, res: any) => {
  try {
    const files = req.files as Express.Multer.File[] | undefined;
    if (!files || files.length === 0) {
      res.status(400).json({ message: "No file uploaded" });
      return;
    }

    const getCleanUrl = (f: any): string => {
      if (f.path && (f.path.startsWith("http://") || f.path.startsWith("https://"))) {
        return f.path;
      }
      if (f.secure_url) return f.secure_url;
      if (f.url && typeof f.url === "string" && (f.url.startsWith("http://") || f.url.startsWith("https://") || f.url.startsWith("/uploads/"))) {
        return f.url;
      }
      if (f.filename && f.filename !== "undefined") {
        return `/uploads/${f.filename}`;
      }
      if (f.path) {
        const norm = f.path.replace(/\\/g, "/");
        const idx = norm.indexOf("uploads/");
        if (idx !== -1) return `/${norm.substring(idx)}`;
        return f.path;
      }
      return "";
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
};

router.post("/upload", (req: any, res: any) => {
  upload.any()(req, res, (err: any) => {
    if (err) {
      console.warn("[Multer Cloudinary Error, falling back to local disk storage]:", err.message || err);
      return diskUpload.any()(req, res, (diskErr: any) => {
        if (diskErr) {
          console.error("[Multer Disk Fallback Error]:", diskErr);
          return res.status(400).json({ message: diskErr.message || "File upload error" });
        }
        return handleFilesResponse(req, res);
      });
    }

    return handleFilesResponse(req, res);
  });
});

export default router;
