import { prisma } from "../config/db.js";
// ================= NOTE HANDLERS =================
// Get all notes for the authenticated user
export const getNotes = async (req, res) => {
    try {
        const userId = req.user.id;
        const notes = await prisma.note.findMany({
            where: { userId },
            orderBy: { updatedAt: "desc" },
        });
        res.json(notes);
    }
    catch (error) {
        console.error("GetNotes error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Create a new note
export const createNote = async (req, res) => {
    try {
        const { title, content } = req.body;
        const userId = req.user.id;
        if (!title || !title.trim()) {
            res.status(400).json({ message: "Note title is required" });
            return;
        }
        const note = await prisma.note.create({
            data: {
                title: title.trim(),
                content: content || "",
                userId,
            },
        });
        res.status(201).json(note);
    }
    catch (error) {
        console.error("CreateNote error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Update an existing note
export const updateNote = async (req, res) => {
    try {
        const noteId = req.params.noteId;
        const { title, content } = req.body;
        const userId = req.user.id;
        if (!noteId) {
            res.status(400).json({ message: "Note ID is required" });
            return;
        }
        const existing = await prisma.note.findUnique({
            where: { id: noteId },
        });
        if (!existing) {
            res.status(404).json({ message: "Note not found" });
            return;
        }
        if (existing.userId !== userId) {
            res.status(403).json({ message: "Unauthorized to update this note" });
            return;
        }
        const updated = await prisma.note.update({
            where: { id: noteId },
            data: {
                title: title?.trim() || undefined,
                content: content !== undefined ? content : undefined,
            },
        });
        res.json(updated);
    }
    catch (error) {
        console.error("UpdateNote error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Delete a note
export const deleteNote = async (req, res) => {
    try {
        const noteId = req.params.noteId;
        const userId = req.user.id;
        if (!noteId) {
            res.status(400).json({ message: "Note ID is required" });
            return;
        }
        const existing = await prisma.note.findUnique({
            where: { id: noteId },
        });
        if (!existing) {
            res.status(404).json({ message: "Note not found" });
            return;
        }
        if (existing.userId !== userId) {
            res.status(403).json({ message: "Unauthorized to delete this note" });
            return;
        }
        await prisma.note.delete({
            where: { id: noteId },
        });
        res.json({ message: "Note deleted successfully" });
    }
    catch (error) {
        console.error("DeleteNote error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// ================= TASK HANDLERS =================
// Get tasks (optionally filtered by conversationId, or get user personal ones)
export const getTasks = async (req, res) => {
    try {
        const userId = req.user.id;
        const conversationId = req.query.conversationId;
        let whereClause = {};
        if (conversationId) {
            // Fetch group tasks. Caller must be in the conversation
            const isParticipant = await prisma.participant.findFirst({
                where: { conversationId, userId },
            });
            if (!isParticipant) {
                res.status(403).json({ message: "Unauthorized to access these tasks" });
                return;
            }
            whereClause.conversationId = conversationId;
        }
        else {
            // Personal tasks: either created by or assigned to current user, and NOT bound to a conversation
            whereClause.AND = [
                { conversationId: null },
                {
                    OR: [
                        { userId },
                        { assignments: { some: { userId } } },
                    ],
                },
            ];
        }
        const tasks = await prisma.task.findMany({
            where: whereClause,
            include: {
                creator: {
                    select: { id: true, username: true, avatarUrl: true },
                },
                assignments: {
                    include: {
                        user: {
                            select: { id: true, username: true, avatarUrl: true },
                        },
                    },
                },
            },
            orderBy: { createdAt: "desc" },
        });
        res.json(tasks);
    }
    catch (error) {
        console.error("GetTasks error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Create a task
export const createTask = async (req, res) => {
    try {
        const { title, description, dueDate, conversationId, assignedUserIds } = req.body;
        const userId = req.user.id;
        if (!title || !title.trim()) {
            res.status(400).json({ message: "Task title is required" });
            return;
        }
        // Verify conversation participant if task is group-wide
        if (conversationId) {
            const isParticipant = await prisma.participant.findFirst({
                where: { conversationId: conversationId, userId },
            });
            if (!isParticipant) {
                res.status(403).json({ message: "Unauthorized to create tasks in this conversation" });
                return;
            }
        }
        const task = await prisma.task.create({
            data: {
                title: title.trim(),
                description: description?.trim() || null,
                dueDate: dueDate ? new Date(dueDate) : null,
                userId,
                conversationId: conversationId || null,
                assignments: {
                    create: Array.isArray(assignedUserIds)
                        ? assignedUserIds.map((uId) => ({ userId: uId }))
                        : [],
                },
            },
            include: {
                creator: {
                    select: { id: true, username: true, avatarUrl: true },
                },
                assignments: {
                    include: {
                        user: {
                            select: { id: true, username: true, avatarUrl: true },
                        },
                    },
                },
            },
        });
        res.status(201).json(task);
    }
    catch (error) {
        console.error("CreateTask error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Update task status
export const updateTaskStatus = async (req, res) => {
    try {
        const taskId = req.params.taskId;
        const { status } = req.body;
        const userId = req.user.id;
        if (!taskId) {
            res.status(400).json({ message: "Task ID is required" });
            return;
        }
        if (!status || !["PENDING", "IN_PROGRESS", "COMPLETED"].includes(status)) {
            res.status(400).json({ message: "Invalid status value" });
            return;
        }
        // Access control: creator or assignee or conversation participant
        const task = await prisma.task.findUnique({
            where: { id: taskId },
            include: { assignments: true },
        });
        if (!task) {
            res.status(404).json({ message: "Task not found" });
            return;
        }
        const isAssigned = task.assignments.some((a) => a.userId === userId);
        const isCreator = task.userId === userId;
        let isGroupParticipant = false;
        if (task.conversationId) {
            const p = await prisma.participant.findFirst({
                where: { conversationId: task.conversationId, userId },
            });
            isGroupParticipant = !!p;
        }
        if (!isCreator && !isAssigned && !isGroupParticipant) {
            res.status(403).json({ message: "Unauthorized to update this task" });
            return;
        }
        const updated = await prisma.task.update({
            where: { id: taskId },
            data: { status },
            include: {
                creator: {
                    select: { id: true, username: true, avatarUrl: true },
                },
                assignments: {
                    include: {
                        user: {
                            select: { id: true, username: true, avatarUrl: true },
                        },
                    },
                },
            },
        });
        res.json(updated);
    }
    catch (error) {
        console.error("UpdateTask error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
//# sourceMappingURL=productivity.controller.js.map