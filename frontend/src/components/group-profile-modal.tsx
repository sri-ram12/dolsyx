"use client";

import React, { useState, useEffect } from "react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useToast } from "@/context/toast-context";
import { X, UserPlus, Trash2, Shield, User, Loader2, ArrowLeft } from "lucide-react";
import { getAvatarUrl } from "@/utils/avatar";

interface GroupProfileModalProps {
  chat: any;
  onClose: () => void;
  onlineUsers: string[];
}

export default function GroupProfileModal({ chat, onClose, onlineUsers }: GroupProfileModalProps) {
  const { token, user } = useAuth();
  const { toast } = useToast();
  
  const [participants, setParticipants] = useState<any[]>(chat.participants || []);
  const [isEditing, setIsEditing] = useState(false);
  const [groupName, setGroupName] = useState(chat.name);
  const [groupDesc, setGroupDesc] = useState(chat.description || "");
  const [isSaving, setIsSaving] = useState(false);
  
  const [showAddMember, setShowAddMember] = useState(false);
  const [newMemberEmail, setNewMemberEmail] = useState("");
  const [isAdding, setIsAdding] = useState(false);
  
  const currentUserRole = participants.find(p => p.userId === user?.id)?.role;
  const isAdmin = currentUserRole === "OWNER" || currentUserRole === "ADMIN";

  const handleUpdateGroup = async () => {
    if (!token) return;
    setIsSaving(true);
    try {
      const res = await fetch(`${API_URL}/api/groups/${chat.id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ name: groupName, description: groupDesc })
      });
      if (res.ok) {
        toast("Group updated successfully", "success");
        setIsEditing(false);
        chat.name = groupName;
        chat.description = groupDesc;
      } else {
        toast("Failed to update group", "error");
      }
    } catch (e) {
      toast("Error updating group", "error");
    } finally {
      setIsSaving(false);
    }
  };

  const handleAddMember = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !newMemberEmail.trim()) return;
    setIsAdding(true);
    
    try {
      // First, get user by email to get their ID
      const resUsers = await fetch(`${API_URL}/api/users/search?q=${newMemberEmail}`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      const users = await resUsers.json();
      const targetUser = users.find((u: any) => u.email === newMemberEmail || u.username === newMemberEmail);
      
      if (!targetUser) {
        toast("User not found", "error");
        setIsAdding(false);
        return;
      }

      const res = await fetch(`${API_URL}/api/groups/${chat.id}/members`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ targetUserId: targetUser.id })
      });

      if (res.ok) {
        const newParticipant = await res.json();
        setParticipants([...participants, newParticipant]);
        toast("Member added", "success");
        setShowAddMember(false);
        setNewMemberEmail("");
      } else {
        toast("Failed to add member", "error");
      }
    } catch (e) {
      toast("Error adding member", "error");
    } finally {
      setIsAdding(false);
    }
  };

  const handleRemoveMember = async (targetUserId: string) => {
    if (!token || !confirm("Are you sure you want to remove this member?")) return;
    try {
      const res = await fetch(`${API_URL}/api/groups/${chat.id}/members/${targetUserId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      });
      if (res.ok) {
        setParticipants(participants.filter(p => p.userId !== targetUserId));
        toast("Member removed", "success");
      } else {
        toast("Failed to remove member", "error");
      }
    } catch (e) {
      toast("Error removing member", "error");
    }
  };

  const handleChangeRole = async (targetUserId: string, newRole: string) => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/groups/${chat.id}/role`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ targetUserId, role: newRole })
      });
      if (res.ok) {
        setParticipants(participants.map(p => p.userId === targetUserId ? { ...p, role: newRole } : p));
        toast(`Role changed to ${newRole}`, "success");
      } else {
        toast("Failed to change role", "error");
      }
    } catch (e) {
      toast("Error changing role", "error");
    }
  };

  return (
    <div className="fixed inset-0 z-[9999] flex flex-col bg-black animate-fade-in overflow-y-auto">
      <div className="flex items-center justify-between px-4 py-4 shrink-0 bg-[var(--theme-bg-sidebar)]/80 backdrop-blur-md border-b border-[var(--theme-border-color)]">
        <button
          onClick={onClose}
          className="flex items-center gap-2 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
        >
          <ArrowLeft className="h-5 w-5" />
          <span className="text-sm font-semibold">Back</span>
        </button>
        <span className="text-sm font-bold text-[var(--theme-text-primary)]">Group Info</span>
        <div className="w-16" />
      </div>

      <div className="relative flex flex-col items-center justify-center py-8 px-6 bg-[var(--theme-bg-sidebar)]">
        <div className="relative z-10 flex flex-col items-center gap-4">
          <img
            src={getAvatarUrl(chat.avatarUrl, chat.name)}
            alt={chat.name}
            className="h-32 w-32 rounded-full border-4 border-white/20 object-cover shadow-2xl"
          />
          {isEditing ? (
            <div className="flex flex-col gap-2 w-64 items-center">
              <input
                type="text"
                value={groupName}
                onChange={(e) => setGroupName(e.target.value)}
                className="w-full text-center text-xl font-bold rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-2 text-[var(--theme-text-primary)]"
                placeholder="Group Name"
              />
              <textarea
                value={groupDesc}
                onChange={(e) => setGroupDesc(e.target.value)}
                className="w-full text-sm rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-3 py-2 text-[var(--theme-text-primary)]"
                placeholder="Group Description"
                rows={3}
              />
              <div className="flex gap-2 mt-2 w-full">
                <button onClick={() => setIsEditing(false)} className="flex-1 py-2 rounded-lg bg-[var(--theme-bg-sidebar-search)] text-white text-xs font-bold cursor-pointer hover:opacity-80">Cancel</button>
                <button onClick={handleUpdateGroup} disabled={isSaving} className="flex-1 py-2 rounded-lg bg-[var(--theme-accent)] text-black text-xs font-bold cursor-pointer hover:opacity-80 flex justify-center items-center">
                  {isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
                </button>
              </div>
            </div>
          ) : (
            <div className="text-center">
              <h2 className="text-2xl font-black text-[var(--theme-text-primary)]">{chat.name}</h2>
              <p className="text-sm text-[var(--theme-text-secondary)] mt-1 max-w-sm whitespace-pre-wrap">
                {chat.description || "No description set"}
              </p>
              {isAdmin && (
                <button onClick={() => setIsEditing(true)} className="mt-4 text-xs font-bold text-[var(--theme-accent)] hover:underline cursor-pointer">
                  Edit Group Details
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      <div className="flex flex-col gap-4 px-4 py-8 max-w-lg w-full mx-auto">
        <div className="flex justify-between items-center mb-2">
          <h3 className="text-sm font-bold text-[var(--theme-text-primary)] uppercase tracking-wider">
            {participants.length} Members
          </h3>
          {isAdmin && (
            <button
              onClick={() => setShowAddMember(!showAddMember)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--theme-accent)]/10 text-[var(--theme-accent)] text-xs font-bold hover:bg-[var(--theme-accent)]/20 transition-colors cursor-pointer"
            >
              <UserPlus className="h-4 w-4" /> Add Member
            </button>
          )}
        </div>

        {showAddMember && isAdmin && (
          <form onSubmit={handleAddMember} className="flex gap-2 mb-4">
            <input
              type="text"
              value={newMemberEmail}
              onChange={(e) => setNewMemberEmail(e.target.value)}
              placeholder="Username or Email"
              className="flex-1 rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] px-3 py-2 text-sm text-[var(--theme-text-primary)]"
            />
            <button
              type="submit"
              disabled={isAdding || !newMemberEmail.trim()}
              className="px-4 py-2 rounded-lg bg-[var(--theme-accent)] text-black text-xs font-bold disabled:opacity-50 flex items-center justify-center cursor-pointer min-w-[80px]"
            >
              {isAdding ? <Loader2 className="h-4 w-4 animate-spin" /> : "Add"}
            </button>
          </form>
        )}

        <div className="rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] overflow-hidden">
          <div className="flex flex-col">
            {participants.map((p, idx) => {
              const isMe = p.userId === user?.id;
              const roleColor = p.role === "OWNER" ? "text-amber-500" : p.role === "ADMIN" ? "text-[var(--theme-accent)]" : "text-[var(--theme-text-secondary)]";
              
              return (
                <div key={p.userId} className={`flex items-center justify-between p-4 ${idx !== participants.length - 1 ? "border-b border-[var(--theme-border-color)]" : ""}`}>
                  <div className="flex items-center gap-3">
                    <img
                      src={getAvatarUrl(p.user?.avatarUrl, p.user?.username)}
                      alt={p.user?.username}
                      className="h-10 w-10 rounded-full bg-[var(--theme-bg-sidebar-search)] object-cover"
                    />
                    <div className="flex flex-col">
                      <span className="text-sm font-semibold text-[var(--theme-text-primary)] flex items-center gap-2">
                        {p.user?.username || "Unknown"}
                        {isMe && <span className="text-[10px] bg-[var(--theme-bg-sidebar-search)] px-2 py-0.5 rounded text-[var(--theme-text-secondary)]">You</span>}
                      </span>
                      <span className={`text-xs font-bold mt-0.5 flex items-center gap-1 ${roleColor}`}>
                        <Shield className="h-3 w-3" /> {p.role}
                      </span>
                    </div>
                  </div>
                  
                  {isAdmin && p.role !== "OWNER" && !isMe && (
                    <div className="flex items-center gap-2">
                      {p.role === "MEMBER" && (
                        <button
                          onClick={() => handleChangeRole(p.userId, "ADMIN")}
                          className="px-2 py-1 rounded border border-[var(--theme-border-color)] text-[10px] text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer"
                        >
                          Make Admin
                        </button>
                      )}
                      {p.role === "ADMIN" && (
                        <button
                          onClick={() => handleChangeRole(p.userId, "MEMBER")}
                          className="px-2 py-1 rounded border border-[var(--theme-border-color)] text-[10px] text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer"
                        >
                          Dismiss Admin
                        </button>
                      )}
                      <button
                        onClick={() => handleRemoveMember(p.userId)}
                        className="p-1.5 rounded-lg text-red-400 hover:bg-red-500/10 transition-colors cursor-pointer"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  )}
                  {isMe && p.role !== "OWNER" && (
                    <button
                      onClick={() => handleRemoveMember(p.userId)}
                      className="px-3 py-1 rounded-lg border border-red-500/30 text-red-400 text-xs font-bold hover:bg-red-500/10 transition-colors cursor-pointer"
                    >
                      Leave Group
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
