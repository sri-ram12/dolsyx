import { Router } from "express";
import { createGroup, updateGroup, addMember, removeMember, changeMemberRole, } from "../controllers/group.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";
const router = Router();
router.use(authenticateToken);
router.post("/", createGroup);
router.put("/:conversationId", updateGroup);
router.post("/:conversationId/members", addMember);
router.delete("/:conversationId/members/:targetUserId", removeMember);
router.put("/:conversationId/role", changeMemberRole);
export default router;
//# sourceMappingURL=group.routes.js.map