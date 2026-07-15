import jwt from "jsonwebtoken";
import { prisma } from "../config/db.js";
export const authenticateToken = async (req, res, next) => {
    const authHeader = req.headers["authorization"];
    const token = authHeader && authHeader.split(" ")[1];
    if (!token) {
        res.status(401).json({ message: "Access token required" });
        return;
    }
    try {
        const secret = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";
        const decoded = jwt.verify(token, secret);
        const user = await prisma.user.findUnique({
            where: { id: decoded.id },
            select: {
                id: true,
                username: true,
                email: true,
                phoneNumber: true,
                avatarUrl: true,
                bio: true,
            },
        });
        if (!user) {
            res.status(404).json({ message: "User not found" });
            return;
        }
        req.user = user;
        next();
    }
    catch (error) {
        res.status(403).json({ message: "Invalid or expired token" });
    }
};
//# sourceMappingURL=auth.middleware.js.map