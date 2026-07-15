import type { Request, Response } from "express";
import type { AuthRequest } from "../middleware/auth.middleware.js";
export declare const sendOtp: (req: Request, res: Response) => Promise<void>;
export declare const resendOtp: (req: Request, res: Response) => Promise<void>;
export declare const verifyOtp: (req: Request, res: Response) => Promise<void>;
export declare const getMe: (req: AuthRequest, res: Response) => Promise<void>;
export declare const logout: (req: AuthRequest, res: Response) => Promise<void>;
export declare const updateProfile: (req: AuthRequest, res: Response) => Promise<void>;
export declare const login: (req: Request, res: Response) => Promise<void>;
export declare const register: (req: Request, res: Response) => Promise<void>;
//# sourceMappingURL=auth.controller.d.ts.map