"use client";

import React, { useState, useEffect } from "react";
import { useAuth, API_URL, User } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { Search, LogOut, MessageSquare, Circle, Users, Camera, Loader2, X, Settings, Radio } from "lucide-react";
import GroupDialog from "./group-dialog";
import SettingsPanel from "./settings-panel";
import { getDefaultAvatar, getAvatarUrl } from "@/utils/avatar";

export interface Chat {
  id: string;
  isGroup: boolean;
  name: string;
  avatarUrl: string | null;
  recipient: User | null;
  lastMessage: {
    id: string;
    content: string;
    senderId: string;
    createdAt: string;
    mediaType?: string | null;
    mediaUrl?: string | null;
    sender?: {
      id: string;
      username: string;
      avatarUrl: string | null;
    } | null;
  } | null;
  updatedAt: string;
  participants?: any[];
}

interface ChatSidebarProps {
  chats: Chat[];
  selectedChatId: string | null;
  onSelectChat: (chat: Chat) => void;
  onlineUsers: string[];
  onChatCreated: (chat: Chat) => void;
  unreadCounts?: Record<string, number>;
  onOpenStatus?: () => void;
}

export default function ChatSidebar({
  chats,
  selectedChatId,
  onSelectChat,
  onlineUsers,
  onChatCreated,
  unreadCounts = {},
  onOpenStatus,
}: ChatSidebarProps) {
  const { user, token, logout, updateUser } = useAuth();
  const { theme, setTheme } = useTheme();
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<User[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchError, setSearchError] = useState("");
  const [showGroupDialog, setShowGroupDialog] = useState(false);
  const [showSettings, setShowSettings] = useState(false);

  // Profile modal state
  const [showProfileModal, setShowProfileModal] = useState(false);
  const [editUsername, setEditUsername] = useState(user?.username || "");
  const [editBio, setEditBio] = useState(user?.bio || "");
  const [editAvatar, setEditAvatar] = useState(user?.avatarUrl || "");
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [isSavingProfile, setIsSavingProfile] = useState(false);
  const [profileError, setProfileError] = useState("");
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  // Sync profile editing status with user changes
  useEffect(() => {
    if (user) {
      setEditUsername(user.username);
      setEditBio(user.bio || "");
      setEditAvatar(user.avatarUrl || "");
    }
  }, [user, showProfileModal]);

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !token) return;

    setIsUploadingAvatar(true);
    setProfileError("");

    const formData = new FormData();
    formData.append("file", file);

    try {
      const res = await fetch(`${API_URL}/api/chats/upload`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
        },
        body: formData,
      });

      if (res.ok) {
        const data = await res.json();
        setEditAvatar(data.fileUrl);
      } else {
        setProfileError("Failed to upload avatar");
      }
    } catch (err) {
      console.error(err);
      setProfileError("Error uploading avatar");
    } finally {
      setIsUploadingAvatar(false);
    }
  };

  const handleSaveProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !editUsername.trim()) return;

    setIsSavingProfile(true);
    setProfileError("");

    try {
      const res = await fetch(`${API_URL}/api/auth/profile`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          username: editUsername.trim(),
          bio: editBio.trim(),
          avatarUrl: editAvatar,
        }),
      });

      if (res.ok) {
        const data = await res.json();
        updateUser(data.user);
        setShowProfileModal(false);
      } else {
        const data = await res.json();
        setProfileError(data.message || "Failed to update profile");
      }
    } catch (err) {
      console.error(err);
      setProfileError("Error saving profile");
    } finally {
      setIsSavingProfile(false);
    }
  };

  // Search users API query
  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (searchQuery.trim().length < 2) {
        setSearchResults([]);
        setIsSearching(false);
        return;
      }

      setIsSearching(true);
      setSearchError("");

      try {
        const res = await fetch(
          `${API_URL}/api/chats/search?query=${encodeURIComponent(searchQuery)}`,
          {
            headers: {
              Authorization: `Bearer ${token}`,
            },
          }
        );

        if (res.ok) {
          const data = await res.json();
          setSearchResults(data);
        } else {
          setSearchError("Failed to fetch users");
        }
      } catch (err) {
        console.error("Search error:", err);
        setSearchError("Network error");
      } finally {
        setIsSearching(false);
      }
    }, 400);

    return () => clearTimeout(delayDebounceFn);
  }, [searchQuery, token]);

  const handleStartChat = async (targetUser: User) => {
    setSearchQuery("");
    setSearchResults([]);

    try {
      const res = await fetch(`${API_URL}/api/chats/direct`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ targetUserId: targetUser.id }),
      });

      if (res.ok) {
        const chatData = await res.json();
        onChatCreated(chatData);
        onSelectChat(chatData);
      }
    } catch (err) {
      console.error("Error creating chat:", err);
    }
  };

  const formatTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  if (showSettings) {
    return (
      <SettingsPanel
        onClose={() => setShowSettings(false)}
        onSelectChat={onSelectChat as any}
      />
    );
  }

  return (
    <div className="flex h-full w-full flex-col border-r border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] backdrop-blur-md sm:w-80 shrink-0 transition-all duration-300">
      {/* Brand Header */}
      <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] px-6 py-5 transition-colors duration-300">
        <span className={`text-xl font-black tracking-wider transition-all duration-300 text-transparent bg-clip-text bg-gradient-to-r from-cyan-300 to-teal-400`}>
          DOLSYX
        </span>
        <div className="flex items-center gap-2">
          {onOpenStatus && (
            <button
              onClick={onOpenStatus}
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] transition-all cursor-pointer bg-[var(--theme-bg-sidebar-search)]"
              title="Status Updates"
            >
              <Radio className="h-4 w-4" />
            </button>
          )}
          <span className="rounded-full bg-[var(--theme-accent)]/10 px-2.5 py-0.5 text-xs font-semibold text-[var(--theme-accent)] transition-all duration-300">
            {theme === "aqua-light" ? "Aqua Light" : theme === "aqua-dark" ? "Aqua Dark" : "Aqua"}
          </span>
        </div>
      </div>

      {/* Search Section */}
      <div className="p-4 relative flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-3 h-4 w-4 text-[var(--theme-text-secondary)]/50" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search users..."
            className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-9 py-2.5 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all duration-200"
          />
        </div>
        <button
          onClick={() => setShowGroupDialog(true)}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/50 hover:bg-[var(--theme-accent)]/10 text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] transition-all duration-200 cursor-pointer"
          title="Create Group space"
        >
          <Users className="h-4.5 w-4.5" />
        </button>

        {/* Search Dropdown Dialog */}
        {searchQuery.trim().length >= 2 && (
          <div className="absolute left-4 right-4 top-16 z-50 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] p-2 shadow-2xl transition-colors duration-300">
            {isSearching ? (
              <div className="flex items-center justify-center py-4 text-sm text-[var(--theme-text-secondary)]">
                <div className="mr-2 h-4 w-4 animate-spin rounded-full border-2 border-[var(--theme-accent)] border-t-transparent" />
                Searching...
              </div>
            ) : searchError ? (
              <div className="py-2 text-center text-xs text-red-400">{searchError}</div>
            ) : searchResults.length === 0 ? (
              <div className="py-4 text-center text-sm text-[var(--theme-text-secondary)]">No users found</div>
            ) : (
              <div className="max-h-60 overflow-y-auto space-y-1">
                {searchResults.map((userResult) => (
                  <button
                    key={userResult.id}
                    onClick={() => handleStartChat(userResult)}
                    className="flex w-full items-center gap-4 rounded-xl px-3 py-3 text-left hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:shadow-sm transition-all cursor-pointer border border-transparent hover:border-[var(--theme-border-color)]/30"
                  >
                    <img
                      src={getAvatarUrl(userResult.avatarUrl, userResult.username)}
                      alt={userResult.username}
                      className="h-10 w-10 shrink-0 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] object-cover shadow-sm"
                    />
                    <div className="flex-1 min-w-0 flex flex-col justify-center">
                      <p className="text-sm font-bold truncate text-[var(--theme-text-primary)] leading-tight mb-0.5">{userResult.username}</p>
                      <p className="text-xs text-[var(--theme-text-secondary)] truncate font-medium">{userResult.email || "Phone user"}</p>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

  {/* Chat List */ }
  < div className = "flex-1 overflow-y-auto px-2 py-1 space-y-1" >
  {
    chats.length === 0 ? (
      <div className="flex flex-col items-center justify-center text-center py-12 px-4 space-y-3">
        <MessageSquare className="h-8 w-8 text-[var(--theme-text-secondary)]/30 animate-pulse" />
        <p className="text-sm text-[var(--theme-text-secondary)]">No active conversations</p>
        <p className="text-xs text-[var(--theme-text-secondary)]/60">Search users above to start a chat</p>
      </div>
    ) : (
      chats.map((chat) => {
        const isSelected = selectedChatId === chat.id;
        const isOnline = chat.recipient ? onlineUsers.includes(chat.recipient.id) : false;
        const unread = unreadCounts[chat.id] || 0;

        return (
          <button
            key={chat.id}
            onClick={() => onSelectChat(chat)}
            className={`flex w-full items-center gap-3 rounded-xl px-4 py-3.5 text-left transition-all duration-200 cursor-pointer border-l-4 ${isSelected
                ? "bg-[var(--theme-bg-sidebar-item-active)] border-[var(--theme-accent)]"
                : "hover:bg-[var(--theme-bg-sidebar-item-hover)] border-transparent"
              }`}
          >
            <div className="relative shrink-0">
              <img
                src={getAvatarUrl(chat.avatarUrl, chat.name)}
                alt={chat.name}
                className="h-10 w-10 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)]"
              />
              {isOnline && (
                <span className="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-[var(--theme-bg-container)] bg-green-500 shadow-md shadow-green-500/50" />
              )}
            </div>

            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between mb-0.5">
                <p className="font-semibold text-sm truncate text-[var(--theme-text-primary)]">{chat.name}</p>
                <div className="flex items-center gap-1.5 shrink-0">
                  {chat.lastMessage && (
                    <span className={`text-[10px] ${unread > 0 ? 'text-[var(--theme-accent)] font-bold' : 'text-[var(--theme-text-secondary)]'}`}>
                      {formatTime(chat.lastMessage.createdAt)}
                    </span>
                  )}
                </div>
              </div>
              <div className="flex items-center justify-between">
                <p className="text-xs text-[var(--theme-text-secondary)] truncate flex-1 min-w-0">
                  {chat.lastMessage
                    ? (() => {
                      const m = chat.lastMessage;
                      const isMe = m.senderId === user?.id;
                      // For group chats, show sender's real name; for 1-on-1, show "You"
                      const senderLabel = isMe
                        ? "You"
                        : (chat.isGroup ? (m.sender?.username || "") : "");
                      const prefix = senderLabel ? `${senderLabel}: ` : "";
                      if (m.mediaType === "CALL_LOG") {
                        const isVideo = m.mediaUrl === "video";
                        const icon = isVideo ? "📹" : "📞";
                        if (m.content === "missed") return `${prefix}${icon} Missed Call`;
                        if (m.content === "declined") return `${prefix}${icon} Declined Call`;
                        if (m.content?.startsWith("connected:")) return `${prefix}${icon} Call`;
                        return `${prefix}${icon} Call`;
                      }
                      if (m.mediaType === "IMAGE") return `${prefix}📷 Image`;
                      if (m.mediaType === "VIDEO") return `${prefix}🎬 Video`;
                      if (m.mediaType === "AUDIO") return `${prefix}🎵 Voice message`;
                      if (m.mediaType === "FILE") return `${prefix}📎 File`;
                      return prefix + m.content;
                    })()
                    : "No messages yet"}
                </p>
                {unread > 0 && (
                  <span className="ml-2 flex h-5 min-w-5 items-center justify-center rounded-full bg-[var(--theme-accent)] px-1.5 text-[10px] font-bold text-white shrink-0">
                    {unread > 99 ? "99+" : unread}
                  </span>
                )}
              </div>
            </div>
          </button>
        );
      })
    )
  }
      </div >

  {/* Footer Profile Section */ }
{
  user && (
    <div className="flex items-center justify-between border-t border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] p-4 transition-colors duration-300">
      <div
        onClick={() => setShowSettings(true)}
        className="flex items-center gap-3 min-w-0 cursor-pointer hover:opacity-80 transition-opacity w-full"
        title="Settings"
      >
        <img
          src={getAvatarUrl(user.avatarUrl, user.username)}
          alt={user.username}
          className="h-9 w-9 rounded-full border-2 border-[var(--theme-accent)]/40 bg-[var(--theme-bg-sidebar-search)] shrink-0 object-cover"
        />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold truncate text-[var(--theme-text-primary)]">{user.username}</p>
          <span className="flex items-center text-[10px] text-green-400 font-medium">
            <Circle className="fill-green-400 h-1.5 w-1.5 mr-1 animate-pulse" />
            Active
          </span>
        </div>
        <Settings className="h-4 w-4 text-[var(--theme-text-secondary)] hover:text-white transition-colors" />
      </div>
    </div>
  )
}
{
  showGroupDialog && (
    <GroupDialog
      onClose={() => setShowGroupDialog(false)}
      onGroupCreated={onChatCreated}
    />
  )
}


    </div >
  );
}
