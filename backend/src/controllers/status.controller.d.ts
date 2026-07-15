import type { Response } from "express";
import type { AuthRequest } from "../middleware/auth.middleware.js";
export declare const createStatus: (req: AuthRequest, res: Response) => Promise<void>;
export declare const getStatuses: (req: AuthRequest, res: Response) => Promise<void>;
export declare const viewStatus: (req: AuthRequest, res: Response) => Promise<void>;
export declare const deleteStatus: (req: AuthRequest, res: Response) => Promise<void>;
//# sourceMappingURL=status.controller.d.ts.map