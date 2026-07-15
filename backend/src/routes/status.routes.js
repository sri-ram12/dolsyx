import { Router } from "express";
import multer from "multer";
import path from "path";
import { createStatus, getStatuses, viewStatus, deleteStatus, } from "../controllers/status.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";
const storage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, "uploads/"); },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
        cb(null, uniqueSuffix + path.extname(file.originalname));
    },
});
const upload = multer({
    storage,
    limits: { fileSize: 50 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        if (file.mimetype.startsWith("image/") || file.mimetype.startsWith("video/")) {
            cb(null, true);
        }
        else {
            cb(new Error("Only image and video files allowed for status"));
        }
    },
});
const router = Router();
router.use(authenticateToken);
router.get("/", getStatuses);
router.post("/", createStatus);
router.post("/:statusId/view", viewStatus);
router.delete("/:statusId", deleteStatus);
// Upload status media (image/video from device)
router.post("/upload", upload.single("file"), (req, res) => {
    try {
        if (!req.file) {
            res.status(400).json({ message: "No file uploaded" });
            return;
        }
        const host = req.get("host");
        const protocol = req.protocol;
        const fileUrl = `${protocol}://${host}/uploads/${req.file.filename}`;
        res.json({ fileUrl, fileType: req.file.mimetype, fileName: req.file.originalname });
    }
    catch (error) {
        console.error("Status upload error:", error);
        res.status(500).json({ message: "Upload failed" });
    }
});
export default router;
//# sourceMappingURL=status.routes.js.map