import { Router } from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import { authenticateToken } from "../middleware/auth.middleware.js";
import { uploadRateLimiter } from "../middleware/rateLimit.middleware.js";

const router = Router();

// Configure storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = "uploads/";
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  },
});

const upload = multer({ 
  storage,
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB max file size
});

router.post("/", uploadRateLimiter, authenticateToken, (req, res) => {
  upload.any()(req, res, (err: any) => {
    if (err) {
      return res.status(400).json({ message: err.message || "Upload error" });
    }
    const files = req.files as Express.Multer.File[] | undefined;
    if (!files || files.length === 0) {
      return res.status(400).json({ message: "No file uploaded" });
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

    const uploadedFiles = files.map(f => {
      const cleanUrl = getCleanUrl(f);
      return {
        url: cleanUrl,
        fileUrl: cleanUrl,
        filename: f.originalname,
        size: f.size,
        mimetype: f.mimetype
      };
    });

    const first = uploadedFiles[0]!;
    return res.status(200).json({
      url: first.url,
      fileUrl: first.fileUrl,
      files: uploadedFiles
    });
  });
});

export default router;
