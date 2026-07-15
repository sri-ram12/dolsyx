import { Router } from "express";
import multer from "multer";
import path from "path";
import { getChats, getMessages, createOrGetDirectChat, searchUsers, deleteConversation, clearChatMessages, } from "../controllers/chat.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";
// Configure multer storage
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, "uploads/");
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
        cb(null, uniqueSuffix + path.extname(file.originalname));
    },
});
const fileFilter = (req, file, cb) => {
    const allowed = [
        "image/", "video/", "audio/",
        "application/pdf",
        "application/zip",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "text/",
    ];
    if (allowed.some((type) => file.mimetype.startsWith(type))) {
        cb(null, true);
    }
    else {
        cb(new Error("File type not allowed"), false);
    }
};
const upload = multer({ storage, fileFilter, limits: { fileSize: 50 * 1024 * 1024 } }); // 50 MB limit
const router = Router();
// Secure all chat routes
router.use(authenticateToken);
router.get("/", getChats);
router.get("/search", searchUsers);
router.get("/:conversationId/messages", getMessages);
router.post("/direct", createOrGetDirectChat);
router.delete("/:conversationId", deleteConversation);
router.delete("/:conversationId/messages", clearChatMessages);
// Upload endpoint
router.post("/upload", upload.single("file"), (req, res) => {
    try {
        if (!req.file) {
            res.status(400).json({ message: "No file uploaded" });
            return;
        }
        const host = req.get("host");
        const protocol = req.protocol;
        // Build file URL
        const fileUrl = `${protocol}://${host}/uploads/${req.file.filename}`;
        res.json({
            fileUrl,
            fileName: req.file.originalname,
            fileType: req.file.mimetype,
            size: req.file.size,
        });
    }
    catch (error) {
        console.error("Upload error:", error);
        res.status(500).json({ message: "File upload failed" });
    }
});
export default router;
//# sourceMappingURL=chat.routes.js.map