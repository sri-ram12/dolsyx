import { Router } from "express";
import {
  searchUser,
  addContact,
  addContactById,
  getContacts,
  updateContact,
  deleteContact,
  checkIsContact,
} from "../controllers/contact.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

// Secure all contact routes
router.use(authenticateToken as any);

router.get("/search", searchUser as any);         // GET /api/contacts/search?query=...
router.get("/", getContacts as any);              // GET /api/contacts
router.post("/", addContact as any);              // POST /api/contacts (by email/username)
router.post("/by-id", addContactById as any);     // POST /api/contacts/by-id (by userId)
router.get("/check/:targetUserId", checkIsContact as any); // GET /api/contacts/check/:userId
router.put("/:contactId", updateContact as any);  // PUT /api/contacts/:id
router.delete("/:contactId", deleteContact as any); // DELETE /api/contacts/:id

export default router;
