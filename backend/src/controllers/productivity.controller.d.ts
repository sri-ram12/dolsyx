import type { Response } from "express";
import type { AuthRequest } from "../middleware/auth.middleware.js";
export declare const getNotes: (req: AuthRequest, res: Response) => Promise<void>;
export declare const createNote: (req: AuthRequest, res: Response) => Promise<void>;
export declare const updateNote: (req: AuthRequest, res: Response) => Promise<void>;
export declare const deleteNote: (req: AuthRequest, res: Response) => Promise<void>;
export declare const getTasks: (req: AuthRequest, res: Response) => Promise<void>;
export declare const createTask: (req: AuthRequest, res: Response) => Promise<void>;
export declare const updateTaskStatus: (req: AuthRequest, res: Response) => Promise<void>;
//# sourceMappingURL=productivity.controller.d.ts.map