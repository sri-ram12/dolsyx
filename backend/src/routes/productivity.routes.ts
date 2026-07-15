import { Router } from "express";
import {
  getNotes,
  createNote,
  updateNote,
  deleteNote,
  getTasks,
  createTask,
  updateTaskStatus,
} from "../controllers/productivity.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

router.use(authenticateToken as any);

// Notes routes
router.get("/notes", getNotes as any);
router.post("/notes", createNote as any);
router.put("/notes/:noteId", updateNote as any);
router.delete("/notes/:noteId", deleteNote as any);

// Tasks routes
router.get("/tasks", getTasks as any);
router.post("/tasks", createTask as any);
router.put("/tasks/:taskId", updateTaskStatus as any);

export default router;
