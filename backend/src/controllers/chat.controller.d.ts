import type { Response } from "express";
import type { AuthRequest } from "../middleware/auth.middleware.js";
export declare const getChats: (req: AuthRequest, res: Response) => Promise<void>;
export declare const getMessages: (req: AuthRequest, res: Response) => Promise<void>;
export declare const createOrGetDirectChat: (req: AuthRequest, res: Response) => Promise<void>;
export declare const searchUsers: (req: AuthRequest, res: Response) => Promise<void>;
export declare const deleteConversation: (req: AuthRequest, res: Response) => Promise<void>;
export declare const clearChatMessages: (req: AuthRequest, res: Response) => Promise<void>;
//# sourceMappingURL=chat.controller.d.ts.map