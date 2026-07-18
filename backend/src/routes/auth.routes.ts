import { Router } from "express";
import { register, login, getMe, sendOtp, verifyOtp, resendOtp, logout, updateProfile, blockUser, unblockUser, getBlockedUsers, loginWithoutOtp } from "../controllers/auth.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";

const router = Router();

router.post("/register", register);
router.post("/login", login);
router.post("/login-without-otp", loginWithoutOtp);
router.post("/send-otp", sendOtp as any);
router.post("/verify-otp", verifyOtp as any);
router.post("/resend-otp", resendOtp as any);
router.post("/logout", authenticateToken as any, logout as any);
router.get("/me", authenticateToken as any, getMe as any);
router.put("/profile", authenticateToken as any, updateProfile as any);
// Block management
router.post("/block/:targetUserId", authenticateToken as any, blockUser as any);
router.delete("/block/:targetUserId", authenticateToken as any, unblockUser as any);
router.get("/blocks", authenticateToken as any, getBlockedUsers as any);

export default router;
