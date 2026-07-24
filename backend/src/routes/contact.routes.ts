import { Router } from "express";
import { addContact, getContacts, deleteContact } from "../controllers/contact.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

// Secure all contact routes
router.use(authenticateToken as any);

router.post("/add", addContact as any);
router.get("/", getContacts as any);
router.delete("/:contactId", deleteContact as any);

export default router;
