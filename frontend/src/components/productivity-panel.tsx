"use client";

import React, { useState, useEffect } from "react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { FileText, CheckSquare, Plus, Trash2, Calendar, User, Clock, Check, Loader2, X } from "lucide-react";

interface Note {
  id: string;
  title: string;
  content: string;
  updatedAt: string;
}

interface Task {
  id: string;
  title: string;
  description: string | null;
  status: "PENDING" | "IN_PROGRESS" | "COMPLETED";
  dueDate: string | null;
  userId: string;
  creator: {
    id: string;
    username: string;
  };
  assignments: {
    userId: string;
    user: {
      id: string;
      username: string;
      avatarUrl: string | null;
    };
  }[];
}

interface ProductivityPanelProps {
  activeConversationId: string | null;
  activeConversationName: string | null;
  isGroupChat: boolean;
  participants: any[]; // User objects representing group members
  onClose: () => void;
}

export default function ProductivityPanel({
  activeConversationId,
  activeConversationName,
  isGroupChat,
  participants,
  onClose,
}: ProductivityPanelProps) {
  const { token, user } = useAuth();
  const { theme } = useTheme();
  const [activeTab, setActiveTab] = useState<"notes" | "tasks">("notes");

  // Notes state
  const [notes, setNotes] = useState<Note[]>([]);
  const [selectedNote, setSelectedNote] = useState<Note | null>(null);
  const [noteTitle, setNoteTitle] = useState("");
  const [noteContent, setNoteContent] = useState("");
  const [isNotesLoading, setIsNotesLoading] = useState(false);
  const [isSavingNote, setIsSavingNote] = useState(false);

  // Tasks state
  const [tasks, setTasks] = useState<Task[]>([]);
  const [taskFilter, setTaskFilter] = useState<"personal" | "group">("personal");
  const [isTasksLoading, setIsTasksLoading] = useState(false);
  const [isCreatingTask, setIsCreatingTask] = useState(false);

  // New task form state
  const [newTaskTitle, setNewTaskTitle] = useState("");
  const [newTaskDesc, setNewTaskDesc] = useState("");
  const [newTaskDueDate, setNewTaskDueDate] = useState("");
  const [selectedAssignees, setSelectedAssignees] = useState<string[]>([]);
  const [showTaskForm, setShowTaskForm] = useState(false);

  // Auto-switch task view based on chat type
  useEffect(() => {
    if (isGroupChat && activeConversationId) {
      setTaskFilter("group");
    } else {
      setTaskFilter("personal");
    }
  }, [activeConversationId, isGroupChat]);

  // Fetch Notes
  const fetchNotes = async () => {
    if (!token) return;
    setIsNotesLoading(true);
    try {
      const res = await fetch(`${API_URL}/api/productivity/notes`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setNotes(data);
      }
    } catch (err) {
      console.error("Fetch notes error:", err);
    } finally {
      setIsNotesLoading(false);
    }
  };

  // Fetch Tasks
  const fetchTasks = async () => {
    if (!token) return;
    setIsTasksLoading(true);
    try {
      const queryParam = taskFilter === "group" && activeConversationId
        ? `?conversationId=${activeConversationId}`
        : "";
      const res = await fetch(`${API_URL}/api/productivity/tasks${queryParam}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setTasks(data);
      }
    } catch (err) {
      console.error("Fetch tasks error:", err);
    } finally {
      setIsTasksLoading(false);
    }
  };

  useEffect(() => {
    if (activeTab === "notes") {
      fetchNotes();
    } else {
      fetchTasks();
    }
  }, [activeTab, taskFilter, activeConversationId]);

  // Create or Update Note
  const handleSaveNote = async () => {
    if (!token || !noteTitle.trim()) return;
    setIsSavingNote(true);
    try {
      const isEdit = !!selectedNote;
      const url = isEdit
        ? `${API_URL}/api/productivity/notes/${selectedNote.id}`
        : `${API_URL}/api/productivity/notes`;
      const method = isEdit ? "PUT" : "POST";

      const res = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ title: noteTitle, content: noteContent }),
      });

      if (res.ok) {
        const data = await res.json();
        if (isEdit) {
          setNotes((prev) => prev.map((n) => (n.id === data.id ? data : n)));
        } else {
          setNotes((prev) => [data, ...prev]);
        }
        setSelectedNote(null);
        setNoteTitle("");
        setNoteContent("");
      }
    } catch (err) {
      console.error("Save note error:", err);
    } finally {
      setIsSavingNote(false);
    }
  };

  // Select Note for editing
  const handleSelectNote = (note: Note) => {
    setSelectedNote(note);
    setNoteTitle(note.title);
    setNoteContent(note.content);
  };

  // Cancel editing note
  const handleCancelNote = () => {
    setSelectedNote(null);
    setNoteTitle("");
    setNoteContent("");
  };

  // Delete Note
  const handleDeleteNote = async (noteId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!token || !confirm("Are you sure you want to delete this note?")) return;
    try {
      const res = await fetch(`${API_URL}/api/productivity/notes/${noteId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setNotes((prev) => prev.filter((n) => n.id !== noteId));
        if (selectedNote?.id === noteId) {
          handleCancelNote();
        }
      }
    } catch (err) {
      console.error("Delete note error:", err);
    }
  };

  // Create Task
  const handleCreateTask = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !newTaskTitle.trim()) return;
    setIsCreatingTask(true);
    try {
      const isGroup = taskFilter === "group" && activeConversationId;
      const res = await fetch(`${API_URL}/api/productivity/tasks`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          title: newTaskTitle.trim(),
          description: newTaskDesc.trim() || undefined,
          dueDate: newTaskDueDate || undefined,
          conversationId: isGroup ? activeConversationId : undefined,
          assignedUserIds: isGroup ? selectedAssignees : [user?.id],
        }),
      });

      if (res.ok) {
        const data = await res.json();
        setTasks((prev) => [data, ...prev]);
        setNewTaskTitle("");
        setNewTaskDesc("");
        setNewTaskDueDate("");
        setSelectedAssignees([]);
        setShowTaskForm(false);
      }
    } catch (err) {
      console.error("Create task error:", err);
    } finally {
      setIsCreatingTask(false);
    }
  };

  // Toggle Task Completion
  const handleToggleTask = async (task: Task) => {
    if (!token) return;
    const nextStatus = task.status === "COMPLETED" ? "PENDING" : "COMPLETED";
    try {
      const res = await fetch(`${API_URL}/api/productivity/tasks/${task.id}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ status: nextStatus }),
      });

      if (res.ok) {
        const data = await res.json();
        setTasks((prev) => prev.map((t) => (t.id === task.id ? data : t)));
      }
    } catch (err) {
      console.error("Toggle task error:", err);
    }
  };

  const toggleAssignee = (userId: string) => {
    setSelectedAssignees((prev) =>
      prev.includes(userId) ? prev.filter((id) => id !== userId) : [...prev, userId]
    );
  };

  const formatDate = (dateString: string) => {
    const d = new Date(dateString);
    return d.toLocaleDateString([], { month: "short", day: "numeric" });
  };

  return (
    <div className="flex h-full w-80 flex-col border-l border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] backdrop-blur-xl shrink-0 shadow-2xl transition-all duration-300">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] px-5 py-4">
        <h3 className="text-sm font-bold tracking-wider text-[var(--theme-text-primary)] flex items-center gap-2">
          {activeTab === "notes" ? (
            <FileText className="h-4 w-4 text-[var(--theme-accent)]" />
          ) : (
            <CheckSquare className="h-4 w-4 text-[var(--theme-accent)]" />
          )}
          Productivity Workspace
        </h3>
        <button
          onClick={onClose}
          className="rounded-lg p-1 text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer bg-[var(--theme-bg-sidebar-search)] border border-[var(--theme-border-color)]"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-[var(--theme-border-color)] p-2 gap-1">
        <button
          onClick={() => setActiveTab("notes")}
          className={`flex-1 rounded-lg py-1.5 text-xs font-semibold transition-all cursor-pointer ${
            activeTab === "notes"
              ? "bg-[var(--theme-accent)]/20 text-[var(--theme-text-primary)] border border-[var(--theme-accent)]/30"
              : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"
          }`}
        >
          Notes
        </button>
        <button
          onClick={() => setActiveTab("tasks")}
          className={`flex-1 rounded-lg py-1.5 text-xs font-semibold transition-all cursor-pointer ${
            activeTab === "tasks"
              ? "bg-[var(--theme-accent)]/20 text-[var(--theme-text-primary)] border border-[var(--theme-accent)]/30"
              : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"
          }`}
        >
          Tasks
        </button>
      </div>

      {/* Workspace Panel View */}
      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar">
        {activeTab === "notes" ? (
          // ================= NOTES TAB =================
          selectedNote || notes.length === 0 && !isNotesLoading && noteTitle === "" ? (
            /* Note Editor or Blank State Editor */
            <div className="flex h-full flex-col space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-[10px] uppercase font-bold text-[var(--theme-accent)]">
                  {selectedNote ? "Edit Note" : "New Note"}
                </span>
                {selectedNote && (
                  <button
                    onClick={handleCancelNote}
                    className="text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
                  >
                    Back to List
                  </button>
                )}
              </div>
              <input
                type="text"
                value={noteTitle}
                onChange={(e) => setNoteTitle(e.target.value)}
                placeholder="Note Title"
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-2 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/50 focus:border-[var(--theme-accent)] focus:outline-none"
              />
              <textarea
                value={noteContent}
                onChange={(e) => setNoteContent(e.target.value)}
                placeholder="Write your note in Markdown here..."
                rows={12}
                className="w-full flex-1 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-2 text-xs text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/50 focus:border-[var(--theme-accent)] focus:outline-none resize-none font-mono"
              />
              <div className="flex gap-2">
                <button
                  onClick={handleSaveNote}
                  disabled={isSavingNote || !noteTitle.trim()}
                  className="flex-1 flex items-center justify-center gap-2 rounded-xl text-[var(--theme-accent-text)] text-xs font-semibold py-2.5 transition-all cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed shadow-md hover:opacity-95"
                  style={{ backgroundColor: "var(--theme-accent)" }}
                >
                  {isSavingNote && <Loader2 className="h-3 w-3 animate-spin text-current" />}
                  Save Note
                </button>
                {selectedNote && (
                  <button
                    onClick={handleCancelNote}
                    className="rounded-xl border border-[var(--theme-border-color)] px-3 py-2 text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] bg-[var(--theme-bg-sidebar-search)] transition-all cursor-pointer"
                  >
                    Cancel
                  </button>
                )}
              </div>
            </div>
          ) : (
            /* Notes List */
            <div className="space-y-3">
              <button
                onClick={() => {
                  setSelectedNote(null);
                  setNoteTitle("");
                  setNoteContent("");
                }}
                className="w-full flex items-center justify-center gap-2 rounded-xl border border-dashed border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] hover:bg-[var(--theme-accent)]/5 text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] py-3 transition-all cursor-pointer font-medium"
              >
                <Plus className="h-4 w-4" />
                Add New Note
              </button>

              {isNotesLoading ? (
                <div className="flex justify-center items-center py-10">
                  <Loader2 className="h-5 w-5 animate-spin text-[var(--theme-accent)]" />
                </div>
              ) : (
                <div className="space-y-2">
                  {notes.map((note) => (
                    <div
                      key={note.id}
                      onClick={() => handleSelectNote(note)}
                      className="group flex flex-col p-3 rounded-xl border border-[var(--theme-border-color)]/60 bg-[var(--theme-bg-chat-input-field)]/30 hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:border-[var(--theme-border-color)] transition-all cursor-pointer relative"
                    >
                      <h4 className="font-semibold text-xs text-[var(--theme-text-primary)] truncate pr-6">
                        {note.title}
                      </h4>
                      <p className="text-[10px] text-[var(--theme-text-secondary)] mt-1 truncate">
                        {note.content || "Empty content"}
                      </p>
                      <span className="text-[9px] text-[var(--theme-text-secondary)]/50 mt-2">
                        {formatDate(note.updatedAt)}
                      </span>
                      <button
                        onClick={(e) => handleDeleteNote(note.id, e)}
                        className="absolute right-3 top-3 opacity-0 group-hover:opacity-100 text-[var(--theme-text-secondary)] hover:text-red-400 p-1 rounded transition-all cursor-pointer"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )
        ) : (
          // ================= TASKS TAB =================
          <div className="space-y-4">
            {/* Filter Toggle (only if isGroupChat is active) */}
            {isGroupChat && activeConversationId && (
              <div className="flex rounded-lg bg-[var(--theme-bg-chat-input-field)] p-1 border border-[var(--theme-border-color)]">
                <button
                  onClick={() => setTaskFilter("personal")}
                  className={`flex-1 rounded-md py-1 text-[10px] font-bold uppercase tracking-wider transition-all cursor-pointer ${
                    taskFilter === "personal" ? "bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)]" : "text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
                  }`}
                >
                  Personal
                </button>
                <button
                  onClick={() => setTaskFilter("group")}
                  className={`flex-1 rounded-md py-1 text-[10px] font-bold uppercase tracking-wider transition-all cursor-pointer ${
                    taskFilter === "group" ? "bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)]" : "text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
                  }`}
                >
                  {activeConversationName || "Group"} Tasks
                </button>
              </div>
            )}

            {/* Task Add Trigger */}
            {!showTaskForm ? (
              <button
                onClick={() => setShowTaskForm(true)}
                className="w-full flex items-center justify-center gap-2 rounded-xl border border-dashed border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] hover:bg-[var(--theme-accent)]/5 text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] py-3 transition-all cursor-pointer font-medium"
              >
                <Plus className="h-4 w-4" />
                Add New Task
              </button>
            ) : (
              /* New Task Form */
              <form onSubmit={handleCreateTask} className="p-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)]/30 space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-[10px] font-bold uppercase text-[var(--theme-accent)]">
                    Create New Task
                  </span>
                  <button
                    type="button"
                    onClick={() => {
                      setShowTaskForm(false);
                      setSelectedAssignees([]);
                    }}
                    className="text-[10px] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
                  >
                    Cancel
                  </button>
                </div>
                <input
                  type="text"
                  required
                  value={newTaskTitle}
                  onChange={(e) => setNewTaskTitle(e.target.value)}
                  placeholder="Task title"
                  className="w-full rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-1.5 text-xs text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/50 focus:border-[var(--theme-accent)] focus:outline-none"
                />
                <textarea
                  value={newTaskDesc}
                  onChange={(e) => setNewTaskDesc(e.target.value)}
                  placeholder="Description (optional)"
                  rows={2}
                  className="w-full rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-1.5 text-xs text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/50 focus:border-[var(--theme-accent)] focus:outline-none resize-none"
                />
                <div className="space-y-1">
                  <label className="text-[9px] font-bold text-[var(--theme-text-secondary)] uppercase flex items-center gap-1">
                    <Calendar className="h-3 w-3" /> Due Date
                  </label>
                  <input
                    type="date"
                    value={newTaskDueDate}
                    onChange={(e) => setNewTaskDueDate(e.target.value)}
                    className="w-full rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-1.5 text-xs text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none"
                  />
                </div>

                {/* Group Assignees selector */}
                {taskFilter === "group" && participants.length > 0 && (
                  <div className="space-y-1">
                    <label className="text-[9px] font-bold text-[var(--theme-text-secondary)] uppercase flex items-center gap-1">
                      <User className="h-3 w-3" /> Assign Members
                    </label>
                    <div className="max-h-24 overflow-y-auto border border-[var(--theme-border-color)] rounded-lg bg-[var(--theme-bg-chat-input-field)] p-1 space-y-0.5">
                      {participants.map((p) => {
                        const isAssigned = selectedAssignees.includes(p.user.id);
                        return (
                          <button
                            type="button"
                            key={p.user.id}
                            onClick={() => toggleAssignee(p.user.id)}
                            className={`flex w-full items-center justify-between rounded px-2 py-1 text-left text-[11px] transition-colors cursor-pointer ${
                              isAssigned ? "bg-[var(--theme-accent)]/25 text-[var(--theme-text-primary)]" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)]"
                            }`}
                          >
                            <span>{p.user.username}</span>
                            {isAssigned && <Check className="h-3 w-3 text-[var(--theme-accent)]" />}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                )}

                <button
                  type="submit"
                  disabled={isCreatingTask || !newTaskTitle.trim()}
                  className="w-full flex items-center justify-center gap-2 rounded-lg text-[var(--theme-accent-text)] text-xs font-semibold py-1.5 transition-all cursor-pointer disabled:opacity-50 shadow-md hover:opacity-95"
                  style={{ backgroundColor: "var(--theme-accent)" }}
                >
                  {isCreatingTask && <Loader2 className="h-3 w-3 animate-spin text-current" />}
                  Add Task
                </button>
              </form>
            )}

            {/* Tasks List */}
            {isTasksLoading ? (
              <div className="flex justify-center items-center py-10">
                <Loader2 className="h-5 w-5 animate-spin text-[var(--theme-accent)]" />
              </div>
            ) : tasks.length === 0 ? (
              <div className="text-center py-8">
                <p className="text-xs text-[var(--theme-text-secondary)]">No active tasks found.</p>
              </div>
            ) : (
              <div className="space-y-2.5">
                {tasks.map((task) => {
                  const isCompleted = task.status === "COMPLETED";
                  return (
                    <div
                      key={task.id}
                      className={`flex items-start gap-3 p-3 rounded-xl border transition-all ${
                        isCompleted
                          ? "border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)]/10 opacity-60"
                          : "border-[var(--theme-border-color)]/60 bg-[var(--theme-bg-chat-input-field)]/30"
                      }`}
                    >
                      {/* Checkbox */}
                      <button
                        onClick={() => handleToggleTask(task)}
                        className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors cursor-pointer ${
                          isCompleted
                            ? "border-green-500 bg-green-500 text-black"
                            : "border-zinc-700 hover:border-[var(--theme-accent)]"
                        }`}
                      >
                        {isCompleted && <Check className="h-3 w-3 stroke-[3]" />}
                      </button>

                      {/* Content */}
                      <div className="flex-1 min-w-0 space-y-1">
                        <h4
                          className={`font-semibold text-xs truncate transition-all ${
                            isCompleted ? "line-through text-[var(--theme-text-secondary)]" : "text-[var(--theme-text-primary)]"
                          }`}
                        >
                          {task.title}
                        </h4>
                        {task.description && (
                          <p className="text-[10px] text-[var(--theme-text-secondary)] line-clamp-2 leading-relaxed">
                            {task.description}
                          </p>
                        )}

                        {/* Badges / Meta */}
                        <div className="flex flex-wrap items-center gap-2 pt-1">
                          {task.dueDate && (
                            <span className="flex items-center gap-1 text-[9px] text-[var(--theme-text-secondary)]">
                              <Clock className="h-2.5 w-2.5" />
                              {formatDate(task.dueDate)}
                            </span>
                          )}
                          
                          {/* Assignees initials/avatars */}
                          {task.assignments.length > 0 && (
                            <div className="flex -space-x-1 overflow-hidden">
                              {task.assignments.map((assignment) => (
                                <span
                                  key={assignment.userId}
                                  className="inline-flex items-center justify-center h-4.5 w-4.5 rounded-full border border-zinc-950 bg-[var(--theme-accent)] text-[8px] font-bold text-[var(--theme-accent-text)] uppercase"
                                  title={assignment.user.username}
                                >
                                  {assignment.user.username.slice(0, 2)}
                                </span>
                              ))}
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
