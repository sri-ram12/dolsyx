import { Router } from "express";
import {
  createPairing,
  scanPairing,
  approvePairing,
  rejectPairing,
  consumePairing,
  getPairingStatus,
  getLinkedDevices,
  revokeLinkedDevice,
  logoutAllOtherDevices,
} from "../controllers/device.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

// Pairing lifecycle routes
router.post("/pair/create", createPairing as any);
router.post("/pair/scan", authenticateToken as any, scanPairing as any);
router.post("/pair/approve", authenticateToken as any, approvePairing as any);
router.post("/pair/reject", authenticateToken as any, rejectPairing as any);
router.post("/pair/consume", consumePairing as any);
router.get("/pair/status/:pairingId", getPairingStatus as any);

// Multi-device management routes
router.get("/", authenticateToken as any, getLinkedDevices as any);
router.delete("/:sessionId", authenticateToken as any, revokeLinkedDevice as any);
router.post("/logout-all", authenticateToken as any, logoutAllOtherDevices as any);

export default router;
