import { Router } from "express";
import {
  register,
  login,
  getMe,
  sendOtp,
  verifyOtp,
  resendOtp,
  logout,
  updateProfile,
  blockUser,
  unblockUser,
  getBlockedUsers,
  loginWithoutOtp,
  deleteAccount,
  requestAccountDeletion,
  initiateGoogleAuth,
  handleGoogleCallback,
  verifyNativeGoogleToken,
  setupUsername,
  getUserSessions,
  revokeSession,
  logoutAllSessions,
  linkGoogleAccount,
  unlinkGoogleAccount,
} from "../controllers/auth.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

// Standard Password & OTP Auth Routes
router.post("/register", register);
router.post("/login", login);
router.post("/login-without-otp", loginWithoutOtp);
router.post("/send-otp", sendOtp as any);
router.post("/verify-otp", verifyOtp as any);
router.post("/resend-otp", resendOtp as any);
router.post("/logout", authenticateToken as any, logout as any);
router.get("/me", authenticateToken as any, getMe as any);
router.put("/profile", authenticateToken as any, updateProfile as any);

// Google OAuth 2.0 / OpenID Connect Routes
router.get("/google", initiateGoogleAuth as any);
router.post("/google", verifyNativeGoogleToken as any);
router.get("/google/callback", handleGoogleCallback as any);
router.post("/google/verify-token", verifyNativeGoogleToken as any);
router.post("/username/setup", authenticateToken as any, setupUsername as any);

// Multi-Device Session Management Routes
router.get("/sessions", authenticateToken as any, getUserSessions as any);
router.delete("/sessions/:sessionId", authenticateToken as any, revokeSession as any);
router.post("/logout-all", authenticateToken as any, logoutAllSessions as any);

// Account Linking & Unlinking Routes
router.post("/link-google", authenticateToken as any, linkGoogleAccount as any);
router.post("/unlink-google", authenticateToken as any, unlinkGoogleAccount as any);

// Account Deletion Routes (Google Play & Privacy Compliance)
router.delete("/account", authenticateToken as any, deleteAccount as any);
router.post("/request-account-deletion", requestAccountDeletion as any);



// Block management
router.post("/block/:targetUserId", authenticateToken as any, blockUser as any);
router.delete("/block/:targetUserId", authenticateToken as any, unblockUser as any);
router.get("/users/:id", authenticateToken as any, (req: any, res: any) => {
  import("../controllers/auth.controller.js")
    .then((m) => m.getUserById(req, res))
    .catch(() => res.status(500).json({ message: "Server error" }));
});
router.get("/blocks", authenticateToken as any, getBlockedUsers as any);

export default router;
