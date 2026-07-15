import { Router } from "express";
import { register, login, getMe, sendOtp, verifyOtp, resendOtp, logout, updateProfile } from "../controllers/auth.controller.js";
import { authenticateToken } from "../middleware/auth.middleware.js";
const router = Router();
router.post("/register", register);
router.post("/login", login);
router.post("/send-otp", sendOtp);
router.post("/verify-otp", verifyOtp);
router.post("/resend-otp", resendOtp);
router.post("/logout", authenticateToken, logout);
router.get("/me", authenticateToken, getMe);
router.put("/profile", authenticateToken, updateProfile);
export default router;
//# sourceMappingURL=auth.routes.js.map