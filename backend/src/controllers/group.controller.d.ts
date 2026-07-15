import type { Response } from "express";
import type { AuthRequest } from "../middleware/auth.middleware.js";
export declare const createGroup: (req: AuthRequest, res: Response) => Promise<void>;
export declare const updateGroup: (req: AuthRequest, res: Response) => Promise<void>;
export declare const addMember: (req: AuthRequest, res: Response) => Promise<void>;
export declare const removeMember: (req: AuthRequest, res: Response) => Promise<void>;
export declare const changeMemberRole: (req: AuthRequest, res: Response) => Promise<void>;
//# sourceMappingURL=group.controller.d.ts.map