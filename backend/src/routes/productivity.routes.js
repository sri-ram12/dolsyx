import { Router } from "express";
import { getNotes, createNote, updateNote, deleteNote, getTasks, createTask, updateTaskStatus, } from "../controllers/productivity.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";
const router = Router();
router.use(authenticateToken);
// Notes routes
router.get("/notes", getNotes);
router.post("/notes", createNote);
router.put("/notes/:noteId", updateNote);
router.delete("/notes/:noteId", deleteNote);
// Tasks routes
router.get("/tasks", getTasks);
router.post("/tasks", createTask);
router.put("/tasks/:taskId", updateTaskStatus);
export default router;
//# sourceMappingURL=productivity.routes.js.map