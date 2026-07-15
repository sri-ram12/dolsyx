import { Router } from "express";
import {
  createGroup,
  updateGroup,
  addMember,
  removeMember,
  changeMemberRole,
} from "../controllers/group.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

router.use(authenticateToken as any);

router.post("/", createGroup as any);
router.put("/:conversationId", updateGroup as any);
router.post("/:conversationId/members", addMember as any);
router.delete("/:conversationId/members/:targetUserId", removeMember as any);
router.put("/:conversationId/role", changeMemberRole as any);

export default router;
