import { Router } from "express";
import multer from "multer";
import path from "path";
import {
  createStatus,
  getStatuses,
  getStatusById,
  viewStatus,
  deleteStatus,
  muteStatus,
  unmuteStatus,
} from "../controllers/status.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

import { getCloudinaryStorage } from "../config/cloudinary.config.js";

const storage = getCloudinaryStorage("dolsyx_status");

const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith("image/") || file.mimetype.startsWith("video/") || file.mimetype === "application/octet-stream") {
      cb(null, true);
    } else {
      cb(new Error("Only image and video files allowed for status"));
    }
  },
});

const router = Router();
router.use(authenticateToken as any);

router.get("/", getStatuses as any);
router.post("/", createStatus as any);
router.get("/:statusId", getStatusById as any);
router.post("/:statusId/view", viewStatus as any);
router.delete("/:statusId", deleteStatus as any);
router.post("/mute", muteStatus as any);
router.post("/unmute", unmuteStatus as any);

// Upload status media (image/video from device)
router.post("/upload", (req: any, res: any) => {
  upload.single("file")(req, res, (err: any) => {
    if (err) {
      console.error("[Multer Error Status]", err);
      return res.status(400).json({ message: err.message || "File upload error" });
    }
    try {
      if (!req.file) { res.status(400).json({ message: "No file uploaded" }); return; }
      const fileUrl = req.file.path; // Cloudinary full URL
      res.json({ fileUrl, fileType: req.file.mimetype, fileName: req.file.originalname });
    } catch (error) {
      console.error("Status upload error:", error);
      res.status(500).json({ message: "Upload failed" });
    }
  });
});

export default router;
