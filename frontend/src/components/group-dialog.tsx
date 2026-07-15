"use client";

import React, { useState, useEffect } from "react";
import { useAuth, API_URL, User } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { Users, X, Search, Check, Loader2 } from "lucide-react";
import { getAvatarUrl } from "@/utils/avatar";

interface GroupDialogProps {
  onClose: () => void;
  onGroupCreated: (group: any) => void;
}

export default function GroupDialog({ onClose, onGroupCreated }: GroupDialogProps) {
  const { token } = useAuth();
  const { theme } = useTheme();
  const [groupName, setGroupName] = useState("");
  const [description, setDescription] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<User[]>([]);
  const [selectedUsers, setSelectedUsers] = useState<User[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Debounce query search
  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (searchQuery.trim().length < 2) {
        setSearchResults([]);
        setIsSearching(false);
        return;
      }
      setIsSearching(true);
      try {
        const res = await fetch(
          `${API_URL}/api/chats/search?query=${encodeURIComponent(searchQuery)}`,
          {
            headers: { Authorization: `Bearer ${token}` },
          }
        );
        if (res.ok) {
          const data = await res.json();
          setSearchResults(data);
        }
      } catch (err) {
        console.error("Search error in group dialog:", err);
      } finally {
        setIsSearching(false);
      }
    }, 300);

    return () => clearTimeout(delayDebounceFn);
  }, [searchQuery, token]);

  const handleSelectUser = (user: User) => {
    if (selectedUsers.some((u) => u.id === user.id)) {
      setSelectedUsers((prev) => prev.filter((u) => u.id !== user.id));
    } else {
      setSelectedUsers((prev) => [...prev, user]);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !groupName.trim()) return;

    setIsSubmitting(true);
    try {
      const userIds = selectedUsers.map((u) => u.id);
      const res = await fetch(`${API_URL}/api/groups`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          name: groupName.trim(),
          description: description.trim() || undefined,
          userIds,
        }),
      });

      if (res.ok) {
        const newGroup = await res.json();
        onGroupCreated(newGroup);
        onClose();
      }
    } catch (err) {
      console.error("Group creation error:", err);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-fade-in">
      <div className="w-full max-w-md overflow-hidden rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] p-6 shadow-2xl space-y-4">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] pb-3">
          <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
            <Users className="h-5 w-5 text-[var(--theme-accent)]" />
            <h3 className="font-bold text-base">Create Group Space</h3>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1 text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1">
            <label className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase">Group Name</label>
            <input
              type="text"
              required
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              placeholder="e.g. Design Sync, Study Hub"
              className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none"
            />
          </div>

          <div className="space-y-1">
            <label className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase">Description</label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What is this group about?"
              className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none"
            />
          </div>

          {/* Members Search Selector */}
          <div className="space-y-2">
            <label className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase">Add Group Members</label>
            
            {/* Selected Members Chips */}
            {selectedUsers.length > 0 && (
              <div className="flex flex-wrap gap-1.5 max-h-20 overflow-y-auto p-1 border border-[var(--theme-border-color)] rounded-xl bg-[var(--theme-bg-chat-input-field)]/30">
                {selectedUsers.map((u) => (
                  <span
                    key={u.id}
                    className="inline-flex items-center gap-1 rounded-lg bg-[var(--theme-accent)]/10 border border-[var(--theme-accent)]/30 px-2 py-0.5 text-xs text-[var(--theme-accent)]"
                  >
                    {u.username}
                    <button
                      type="button"
                      onClick={() => handleSelectUser(u)}
                      className="text-[var(--theme-accent)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}

            {/* Search Input */}
            <div className="relative">
              <Search className="absolute left-3 top-3 h-4 w-4 text-[var(--theme-text-secondary)]/50" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search users to add..."
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-9 py-2.5 text-xs text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none"
              />
            </div>

            {/* Search Results */}
            {searchQuery.trim().length >= 2 && (
              <div className="max-h-40 overflow-y-auto rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)]/50 p-1 space-y-0.5">
                {isSearching ? (
                  <div className="flex items-center justify-center py-4 text-xs text-[var(--theme-text-secondary)]">
                    <Loader2 className="mr-2 h-3.5 w-3.5 animate-spin text-[var(--theme-accent)]" />
                    Searching...
                  </div>
                ) : searchResults.length === 0 ? (
                  <div className="py-3 text-center text-xs text-[var(--theme-text-secondary)]">No users found</div>
                ) : (
                  searchResults.map((su) => {
                    const isChecked = selectedUsers.some((u) => u.id === su.id);
                    return (
                      <button
                        type="button"
                        key={su.id}
                        onClick={() => handleSelectUser(su)}
                        className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-xs transition-colors cursor-pointer border border-transparent ${
                          isChecked ? "bg-[var(--theme-accent)]/15 border-[var(--theme-accent)]/30 text-[var(--theme-text-primary)]" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:border-[var(--theme-border-color)]/30"
                        }`}
                      >
                        <div className="flex items-center gap-3 min-w-0 flex-1">
                          <img
                            src={getAvatarUrl(su.avatarUrl, su.username)}
                            alt={su.username}
                            className="h-8 w-8 shrink-0 rounded-full border border-[var(--theme-border-color)] object-cover shadow-sm"
                          />
                          <div className="flex flex-col justify-center min-w-0">
                            <span className="font-bold text-[var(--theme-text-primary)] truncate text-sm leading-tight mb-0.5">{su.username}</span>
                            <span className="truncate text-[10px] font-medium">{su.email || "Phone user"}</span>
                          </div>
                        </div>
                        {isChecked && <Check className="h-4 w-4 shrink-0 text-[var(--theme-accent)] ml-2" />}
                      </button>
                    );
                  })
                )}
              </div>
            )}
          </div>

          {/* Submit Actions */}
          <div className="flex gap-2 pt-2 border-t border-[var(--theme-border-color)]">
            <button
              type="submit"
              disabled={isSubmitting || !groupName.trim()}
              className="flex-1 flex items-center justify-center gap-2 rounded-xl text-[var(--theme-accent-text)] text-xs font-semibold py-2.5 transition-all cursor-pointer disabled:opacity-50 hover:opacity-95 shadow-md"
              style={{ backgroundColor: "var(--theme-accent)" }}
            >
              {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin text-current" />}
              Create Group Space
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl border border-[var(--theme-border-color)] px-4 py-2.5 text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] bg-[var(--theme-bg-sidebar-search)] transition-all cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
