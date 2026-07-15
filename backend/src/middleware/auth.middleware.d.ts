import type { Request, Response, NextFunction } from "express";
export interface AuthRequest extends Request {
    user?: {
        id: string;
        username: string;
        email?: string | null;
        phoneNumber?: string | null;
        avatarUrl: string | null;
        bio?: string | null;
    };
}
export declare const authenticateToken: (req: AuthRequest, res: Response, next: NextFunction) => Promise<void>;
//# sourceMappingURL=auth.middleware.d.ts.map