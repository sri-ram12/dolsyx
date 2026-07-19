"use client";

import React, { useState, useEffect, useRef } from "react";
import { useAuth, API_URL, User } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { useToast } from "@/context/toast-context";
import { Search, LogOut, MessageSquare, Circle, Users, Camera, Loader2, X, Settings, Radio, MoreVertical, Pin, Trash2, Archive, Star, CheckSquare, User as UserIcon } from "lucide-react";
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
  const { toast } = useToast();
  
  // Search & Navigation
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<User[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchError, setSearchError] = useState("");
  const [showGroupDialog, setShowGroupDialog] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [settingsTab, setSettingsTab] = useState<"profile"|"display"|"audio"|"privacy"|"lock">("profile");

  // Top header 3-dots menu
  const [showHeaderMenu, setShowHeaderMenu] = useState(false);
  const headerMenuRef = useRef<HTMLDivElement>(null);

  // Long press & Multi-select states
  const [selectedChats, setSelectedChats] = useState<Set<string>>(new Set());
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [showSelectionMenu, setShowSelectionMenu] = useState(false);
  const selectionMenuRef = useRef<HTMLDivElement>(null);

  // Local storage lists for Pin, Archive, Favorite
  const [pinnedChats, setPinnedChats] = useState<string[]>([]);
  const [archivedChats, setArchivedChats] = useState<string[]>([]);
  const [favoriteChats, setFavoriteChats] = useState<string[]>([]);
  const [statusGroups, setStatusGroups] = useState<any[]>([]);

  // Chat locking states
  const [lockedChats, setLockedChats] = useState<Record<string, { secretKey?: string; useFingerprint?: boolean }>>({});
  const [showLockConfigModal, setShowLockConfigModal] = useState(false);
  const [lockSecretKey, setLockSecretKey] = useState("");
  const [lockFingerprint, setLockFingerprint] = useState(false);
  const [lockingChatId, setLockingChatId] = useState<string | null>(null);

  const [showLockAuthModal, setShowLockAuthModal] = useState(false);
  const [authSecretKeyInput, setAuthSecretKeyInput] = useState("");
  const [authenticatingChat, setAuthenticatingChat] = useState<Chat | null>(null);

  const [showStarredModal, setShowStarredModal] = useState(false);
  const [starredMessagesList, setStarredMessagesList] = useState<any[]>([]);

  const [globalUnlockedKey, setGlobalUnlockedKey] = useState<string>("");

  useEffect(() => {
    if (typeof window !== "undefined") {
      setLockedChats(JSON.parse(localStorage.getItem("dolsyx_locked_chats") || "{}"));
      setGlobalUnlockedKey(localStorage.getItem("dolsyx_locked_chat_key") || "");

      const handleKeyUpdate = () => {
        setGlobalUnlockedKey(localStorage.getItem("dolsyx_locked_chat_key") || "");
      };
      window.addEventListener("dolsyx_locked_chat_key_updated", handleKeyUpdate);
      return () => window.removeEventListener("dolsyx_locked_chat_key_updated", handleKeyUpdate);
    }
  }, []);
  
  // Long press timer ref
  const pressTimerRef = useRef<NodeJS.Timeout | null>(null);

  // Load active statuses to show status rings
  useEffect(() => {
    if (!token) return;
    const fetchSidebarStatuses = async () => {
      try {
        const res = await fetch(`${API_URL}/api/status`, {
          headers: { Authorization: `Bearer ${token}` }
        });
        if (res.ok) {
          const data = await res.json();
          setStatusGroups(data);
        }
      } catch (e) {
        console.error(e);
      }
    };
    fetchSidebarStatuses();
    const interval = setInterval(fetchSidebarStatuses, 45000);
    return () => clearInterval(interval);
  }, [token]);

  // Close menus when clicking outside
  useEffect(() => {
    const clickOutside = (e: MouseEvent) => {
      if (headerMenuRef.current && !headerMenuRef.current.contains(e.target as Node)) {
        setShowHeaderMenu(false);
      }
      if (selectionMenuRef.current && !selectionMenuRef.current.contains(e.target as Node)) {
        setShowSelectionMenu(false);
      }
    };
    document.addEventListener("mousedown", clickOutside);
    return () => document.removeEventListener("mousedown", clickOutside);
  }, []);

  // Load pinned/archived/favorite lists
  useEffect(() => {
    if (typeof window !== "undefined") {
      setPinnedChats(JSON.parse(localStorage.getItem("dolsyx_pinned_chats") || "[]"));
      setArchivedChats(JSON.parse(localStorage.getItem("dolsyx_archived_chats") || "[]"));
      setFavoriteChats(JSON.parse(localStorage.getItem("dolsyx_favorite_chats") || "[]"));
    }
  }, []);

  const saveList = (key: string, list: string[], setter: Function) => {
    localStorage.setItem(key, JSON.stringify(list));
    setter(list);
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
          { headers: { Authorization: `Bearer ${token}` } }
        );
        if (res.ok) {
          const data = await res.json();
          setSearchResults(data);
        } else {
          setSearchError("Failed to fetch users");
        }
      } catch (err) {
        console.error(err);
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
      console.error(err);
    }
  };

  // Long press events handler
  const startPress = (chatId: string) => {
    if (isSelectionMode) return;
    pressTimerRef.current = setTimeout(() => {
      setIsSelectionMode(true);
      setSelectedChats(new Set([chatId]));
    }, 600); // 600ms long press threshold
  };

  const endPress = () => {
    if (pressTimerRef.current) clearTimeout(pressTimerRef.current);
  };

  const handleChatClick = (chat: Chat) => {
    if (isSelectionMode) {
      const newSelected = new Set(selectedChats);
      if (newSelected.has(chat.id)) {
        newSelected.delete(chat.id);
        if (newSelected.size === 0) {
          setIsSelectionMode(false);
        }
      } else {
        newSelected.add(chat.id);
      }
      setSelectedChats(newSelected);
    } else {
      const lock = lockedChats[chat.id];
      if (lock) {
        setAuthenticatingChat(chat);
        setAuthSecretKeyInput("");
        setShowLockAuthModal(true);
      } else {
        onSelectChat(chat);
      }
    }
  };

  // Action: Pin / Unpin
  const togglePin = () => {
    let newPinned = [...pinnedChats];
    selectedChats.forEach(id => {
      if (newPinned.includes(id)) {
        newPinned = newPinned.filter(x => x !== id);
      } else {
        newPinned.push(id);
      }
    });
    saveList("dolsyx_pinned_chats", newPinned, setPinnedChats);
    exitSelectionMode();
  };

  // Action: Archive / Unarchive
  const toggleArchive = () => {
    let newArchived = [...archivedChats];
    selectedChats.forEach(id => {
      if (newArchived.includes(id)) {
        newArchived = newArchived.filter(x => x !== id);
      } else {
        newArchived.push(id);
      }
    });
    saveList("dolsyx_archived_chats", newArchived, setArchivedChats);
    exitSelectionMode();
  };

  // Action: Add/Remove Favorites
  const toggleFavorite = () => {
    let newFav = [...favoriteChats];
    selectedChats.forEach(id => {
      if (newFav.includes(id)) {
        newFav = newFav.filter(x => x !== id);
      } else {
        newFav.push(id);
      }
    });
    saveList("dolsyx_favorite_chats", newFav, setFavoriteChats);
    exitSelectionMode();
  };

  // Action: Delete Selected Chats
  const deleteSelectedChats = async () => {
    if (!token) return;
    try {
      for (const id of selectedChats) {
        await fetch(`${API_URL}/api/chats/${id}`, {
          method: "DELETE",
          headers: { Authorization: `Bearer ${token}` }
        });
      }
    } catch (e) {
      console.error(e);
    }
    exitSelectionMode();
    window.location.reload();
  };

  // Action: Block Selected Users
  const blockSelectedUsers = async () => {
    if (!token) return;
    try {
      for (const id of selectedChats) {
        const chat = chats.find(c => c.id === id);
        if (chat && chat.recipient) {
          await fetch(`${API_URL}/api/auth/block/${chat.recipient.id}`, {
            method: "POST",
            headers: { Authorization: `Bearer ${token}` }
          });
        }
      }
    } catch (e) {
      console.error(e);
    }
    exitSelectionMode();
  };

  const exitSelectionMode = () => {
    setIsSelectionMode(false);
    setSelectedChats(new Set());
    setShowSelectionMenu(false);
  };

  const handleSaveLockConfig = () => {
    if (!lockingChatId) return;
    const newLocked = { ...lockedChats };
    if (!lockSecretKey && !lockFingerprint) {
      delete newLocked[lockingChatId];
    } else {
      newLocked[lockingChatId] = {
        secretKey: lockSecretKey || undefined,
        useFingerprint: lockFingerprint
      };
    }
    localStorage.setItem("dolsyx_locked_chats", JSON.stringify(newLocked));
    setLockedChats(newLocked);
    setShowLockConfigModal(false);
    setLockingChatId(null);
    exitSelectionMode();
  };

  const handleRemoveLock = () => {
    if (!lockingChatId) return;
    const newLocked = { ...lockedChats };
    delete newLocked[lockingChatId];
    localStorage.setItem("dolsyx_locked_chats", JSON.stringify(newLocked));
    setLockedChats(newLocked);
    setShowLockConfigModal(false);
    setLockingChatId(null);
    exitSelectionMode();
  };

  const handleVerifySecretKey = () => {
    if (!authenticatingChat) return;
    const lock = lockedChats[authenticatingChat.id];
    if (lock && lock.secretKey === authSecretKeyInput) {
      onSelectChat(authenticatingChat);
      setShowLockAuthModal(false);
      setAuthenticatingChat(null);
      setAuthSecretKeyInput("");
    } else {
      alert("Invalid secret key.");
    }
  };

  const handleVerifyFingerprint = async () => {
    if (!authenticatingChat) return;
    try {
      const credential = await navigator.credentials.get({
        publicKey: {
          challenge: new Uint8Array([1, 2, 3, 4]),
          rpId: window.location.hostname,
          userVerification: "required",
          timeout: 60000
        }
      });
      if (credential) {
        onSelectChat(authenticatingChat);
        setShowLockAuthModal(false);
        setAuthenticatingChat(null);
        setAuthSecretKeyInput("");
      }
    } catch (e) {
      console.error(e);
      alert("Biometric verification failed.");
    }
  };

  const formatTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  // Sort & Filter chats: hide locked chats unless the search query matches the secret key
  // OR the global secret key has been entered in Settings.
  const sortedChats = [...chats]
    .filter(chat => {
      const lock = lockedChats[chat.id];
      if (lock) {
        if (lock.secretKey) {
          if (searchQuery.trim().toLowerCase() === lock.secretKey.toLowerCase()) return true;
          if (globalUnlockedKey === lock.secretKey) return true;
        }
        return false;
      }
      return true;
    })
    .sort((a, b) => {
      const aArchived = archivedChats.includes(a.id) ? 1 : 0;
      const bArchived = archivedChats.includes(b.id) ? 1 : 0;
      if (aArchived !== bArchived) return aArchived - bArchived;

      const aPinned = pinnedChats.includes(a.id) ? 1 : 0;
      const bPinned = pinnedChats.includes(b.id) ? 1 : 0;
      if (aPinned !== bPinned) return bPinned - aPinned;
      
      const aTime = a.lastMessage ? new Date(a.lastMessage.createdAt).getTime() : 0;
      const bTime = b.lastMessage ? new Date(b.lastMessage.createdAt).getTime() : 0;
      return bTime - aTime;
    });

  if (showSettings) {
    return (
      <SettingsPanel
        onClose={() => setShowSettings(false)}
        onSelectChat={onSelectChat as any}
        initialTab={settingsTab}
      />
    );
  }

  return (
    <div className="flex h-full w-full flex-col border-r border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] backdrop-blur-md sm:w-80 shrink-0 transition-all duration-300">
      
      {/* ── HEADER BLOCK ────────────────────────────────────────── */}
      {isSelectionMode ? (
        // Selection Mode Header
        <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-accent)]/10 px-4 py-4 text-[var(--theme-text-primary)]">
          <div className="flex items-center gap-3">
            <button onClick={exitSelectionMode} className="p-1 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl cursor-pointer">
              <X className="h-5 w-5" />
            </button>
            <span className="font-bold text-sm">{selectedChats.size} selected</span>
          </div>

          <div className="flex items-center gap-2 relative">
            <button onClick={togglePin} className="p-2 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl cursor-pointer" title="Pin / Unpin">
              <Pin className="h-4.5 w-4.5" />
            </button>
            <button
              onClick={toggleArchive}
              className="p-2 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl cursor-pointer"
              title={Array.from(selectedChats).some(id => archivedChats.includes(id)) ? "Unarchive" : "Archive"}
            >
              <Archive className="h-4.5 w-4.5" />
            </button>
            <button onClick={deleteSelectedChats} className="p-2 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl cursor-pointer text-red-400" title="Delete">
              <Trash2 className="h-4.5 w-4.5" />
            </button>
            
            {/* Selection Options Dropdown */}
            <button onClick={() => setShowSelectionMenu(!showSelectionMenu)} className="p-2 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl cursor-pointer">
              <MoreVertical className="h-4.5 w-4.5" />
            </button>

            {showSelectionMenu && (
              <div ref={selectionMenuRef} className="absolute right-0 top-12 z-50 w-44 rounded-xl border border-[var(--theme-border-color)] bg-[#111b21] p-1 shadow-2xl text-left">
                <button onClick={deleteSelectedChats} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs text-red-400 hover:bg-red-500/10 cursor-pointer">
                  <Trash2 className="h-3.5 w-3.5" /> Delete Chat
                </button>
                <button onClick={blockSelectedUsers} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer">
                  <X className="h-3.5 w-3.5 text-slate-400" /> Block User
                </button>
                <button onClick={toggleFavorite} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer">
                  <Star className="h-3.5 w-3.5 text-amber-400" fill="currentColor" /> Favorite
                </button>
                <button
                  onClick={() => {
                    const firstSelected = Array.from(selectedChats)[0];
                    if (firstSelected) {
                      const existing = lockedChats[firstSelected];
                      if (existing) {
                        const newLocked = { ...lockedChats };
                        delete newLocked[firstSelected];
                        localStorage.setItem("dolsyx_locked_chats", JSON.stringify(newLocked));
                        setLockedChats(newLocked);
                        toast("Chat unlocked.", "success");
                        setSelectedChats(new Set());
                        setIsSelectionMode(false);
                      } else {
                        setLockingChatId(firstSelected);
                        setLockSecretKey("");
                        setLockFingerprint(false);
                        setShowLockConfigModal(true);
                      }
                    }
                    setShowSelectionMenu(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-cyan-400 font-bold"
                >
                  <CheckSquare className="h-3.5 w-3.5" /> {Array.from(selectedChats)[0] && lockedChats[Array.from(selectedChats)[0]] ? "Unlock Chat" : "Lock Chat"}
                </button>
              </div>
            )}
          </div>
        </div>
      ) : (
        // Normal Mode Header
        <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] px-6 py-5">
          <div className="flex items-center gap-3">
            <button
              onClick={() => { setSettingsTab("profile"); setShowSettings(true); }}
              className="relative rounded-full p-0.5 border-2 border-emerald-500 transition-transform hover:scale-105 cursor-pointer flex items-center justify-center"
              title="View Profile Status"
            >
              <img
                src={getAvatarUrl(user?.avatarUrl, user?.username || "")}
                alt={user?.username || "Profile"}
                className="h-8 w-8 rounded-full border border-black object-cover"
              />
            </button>
            <span className="text-xl font-black tracking-wider text-transparent bg-clip-text bg-gradient-to-r from-cyan-300 to-teal-400">
              DOLSYX
            </span>
          </div>
          <div className="relative">
            <button onClick={() => setShowHeaderMenu(!showHeaderMenu)} className="p-1.5 hover:bg-[var(--theme-bg-sidebar-item-hover)] rounded-xl text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer">
              <MoreVertical className="h-5 w-5" />
            </button>
            {showHeaderMenu && (
              <div ref={headerMenuRef} className="absolute right-0 top-10 z-50 w-48 rounded-xl border border-[var(--theme-border-color)] bg-[#111b21] p-1 shadow-2xl text-left">
                <button onClick={() => { setShowGroupDialog(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <Users className="h-3.5 w-3.5 text-[var(--theme-accent)]" /> New Group
                </button>
                <button
                  onClick={() => {
                    const list = JSON.parse(localStorage.getItem("dolsyx_starred_messages_list") || "[]");
                    setStarredMessagesList(list);
                    setShowStarredModal(true);
                    setShowHeaderMenu(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]"
                >
                  <Star className="h-3.5 w-3.5 text-amber-500" /> Starred Chats & Media
                </button>
                <button onClick={() => { setSettingsTab("profile"); setShowSettings(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <UserIcon className="h-3.5 w-3.5 text-slate-400" /> Profile Settings
                </button>
                <button onClick={() => { setSettingsTab("display"); setShowSettings(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <Settings className="h-3.5 w-3.5 text-slate-400" /> Display Settings
                </button>
                <button onClick={() => { setSettingsTab("privacy"); setShowSettings(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <Settings className="h-3.5 w-3.5 text-slate-400" /> Privacy Settings
                </button>
                <button onClick={() => { setSettingsTab("audio"); setShowSettings(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <Settings className="h-3.5 w-3.5 text-slate-400" /> Audio Settings
                </button>
                <button onClick={() => { setSettingsTab("lock"); setShowSettings(true); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-[var(--theme-text-primary)]">
                  <Settings className="h-3.5 w-3.5 text-slate-400" /> App Lock Settings
                </button>
                <button onClick={() => { logout(); setShowHeaderMenu(false); }} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer text-red-400">
                  <LogOut className="h-3.5 w-3.5" /> Switch Account
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Search Section */}
      <div className="p-4 relative flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-3 h-4 w-4 text-[var(--theme-text-secondary)]/50" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search users..."
            className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-9 py-2.5 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
          />
        </div>
        <button
          onClick={() => setShowGroupDialog(true)}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/50 hover:bg-[var(--theme-accent)]/10 text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] transition-all cursor-pointer"
          title="Create Group space"
        >
          <Users className="h-4.5 w-4.5" />
        </button>

        {/* Search Results Dropdown */}
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
                    className="flex w-full items-center gap-4 rounded-xl px-3 py-3 text-left hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer border border-transparent hover:border-[var(--theme-border-color)]/30"
                  >
                    <img
                      src={getAvatarUrl(userResult.avatarUrl, userResult.username)}
                      alt={userResult.username}
                      className="h-10 w-10 shrink-0 rounded-full border border-[var(--theme-border-color)] object-cover shadow-sm bg-zinc-800"
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

      {/* Chat List */}
      <div className="flex-1 overflow-y-auto px-2 py-1 space-y-1">
        {searchQuery.trim().length >= 2 ? (
          <div className="flex flex-col items-center justify-center text-center py-16 px-4 space-y-3">
            <Search className="h-8 w-8 text-[var(--theme-text-secondary)]/20 animate-pulse" />
            <p className="text-xs text-[var(--theme-text-secondary)]/60">Searching for users...</p>
          </div>
        ) : sortedChats.length === 0 ? (
          <div className="flex flex-col items-center justify-center text-center py-12 px-4 space-y-3">
            <MessageSquare className="h-8 w-8 text-[var(--theme-text-secondary)]/30 animate-pulse" />
            <p className="text-sm text-[var(--theme-text-secondary)]">No active conversations</p>
          </div>
        ) : (
          sortedChats.map((chat, index) => {
            const isSelected = selectedChatId === chat.id;
            const isOnline = chat.recipient ? onlineUsers.includes(chat.recipient.id) : false;
            const unread = unreadCounts[chat.id] || 0;
            const isPinned = pinnedChats.includes(chat.id);
            const isFavorite = favoriteChats.includes(chat.id);
            const isSelect = selectedChats.has(chat.id);
            const isArchived = archivedChats.includes(chat.id);
            
            const isFirstArchived = isArchived && sortedChats.findIndex(c => archivedChats.includes(c.id)) === index;

            return (
              <div
                key={chat.id}
                onMouseDown={() => startPress(chat.id)}
                onMouseUp={endPress}
                onTouchStart={() => startPress(chat.id)}
                onTouchEnd={endPress}
                className="relative"
              >
                {isFirstArchived && (
                  <div className="flex items-center gap-2 px-4 py-3 text-[10px] font-bold text-slate-500 uppercase tracking-widest border-t border-[var(--theme-border-color)]/30 mt-3 mb-1">
                    <Archive className="h-3.5 w-3.5" />
                    <span>Archived Chats</span>
                  </div>
                )}
                <button
                  onClick={() => handleChatClick(chat)}
                  className={`flex w-full items-center gap-3 rounded-xl px-4 py-3.5 text-left transition-all duration-200 cursor-pointer border-l-4 ${
                    isSelect
                      ? "bg-[var(--theme-accent)]/10 border-[var(--theme-accent)]"
                      : isSelected
                      ? "bg-[var(--theme-bg-sidebar-item-active)] border-[var(--theme-accent)]"
                      : "hover:bg-[var(--theme-bg-sidebar-item-hover)] border-transparent"
                  }`}
                >
                  <div className="relative shrink-0">
                    {(() => {
                      const recipientId = chat.recipient?.id;
                      const hasStatus = recipientId ? statusGroups.some(g => g.user.id === recipientId && g.statuses.length > 0) : false;
                      const hasUnreadStatus = recipientId ? statusGroups.some(g => g.user.id === recipientId && g.hasUnread) : false;
                      return (
                        <div className={`rounded-full p-[2px] transition-all ${
                          hasStatus
                            ? hasUnreadStatus
                              ? "ring-2 ring-[var(--theme-accent)] ring-offset-1 ring-offset-[var(--theme-bg-sidebar)] animate-pulse"
                              : "ring-2 ring-slate-600/70 ring-offset-1 ring-offset-[var(--theme-bg-sidebar)]"
                            : ""
                        }`}>
                          <img
                            src={getAvatarUrl(chat.avatarUrl, chat.name)}
                            alt={chat.name}
                            className="h-10 w-10 rounded-full border border-[var(--theme-border-color)] bg-zinc-800 object-cover"
                          />
                        </div>
                      );
                    })()}
                    {isOnline && (
                      <span className="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-[var(--theme-bg-container)] bg-green-500" />
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-0.5">
                      <div className="flex items-center gap-1.5 min-w-0">
                        <p className="font-semibold text-[16px] truncate text-[var(--theme-text-primary)]">{chat.name}</p>
                        {isPinned && <Pin className="h-3 w-3 text-[var(--theme-accent)]" />}
                        {isFavorite && <Star className="h-3 w-3 text-amber-500" fill="currentColor" />}
                      </div>
                      {chat.lastMessage && (
                        <span className={`text-[12px] font-normal ${unread > 0 ? 'text-[var(--theme-accent)] font-semibold' : 'text-[var(--theme-text-secondary)]'}`}>
                          {formatTime(chat.lastMessage.createdAt)}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center justify-between">
                      <p className="text-[14px] text-[var(--theme-text-secondary)] truncate flex-1 min-w-0 font-normal">
                        {chat.lastMessage
                          ? (() => {
                              const m = chat.lastMessage;
                              const isMe = m.senderId === user?.id;
                              const senderLabel = isMe ? "You" : (chat.isGroup ? (m.sender?.username || "") : "");
                              const prefix = senderLabel ? `${senderLabel}: ` : "";
                              if (m.mediaType === "CALL_LOG") {
                                const isVideo = m.mediaUrl === "video";
                                const icon = isVideo ? "📹" : "📞";
                                if (m.content === "missed") return `${prefix}${icon} Missed Call`;
                                if (m.content === "declined") return `${prefix}${icon} Declined Call`;
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
                        <span className="ml-2 flex h-5 min-w-5 items-center justify-center rounded-full bg-[var(--theme-accent)] px-1.5 text-[12px] font-bold text-white shrink-0">
                          {unread > 99 ? "99+" : unread}
                        </span>
                      )}
                    </div>
                  </div>
                </button>
              </div>
            );
          })
        )}
      </div>

      {showGroupDialog && (
        <GroupDialog
          onClose={() => setShowGroupDialog(false)}
          onGroupCreated={onChatCreated}
        />
      )}

      {/* ── Lock Config Modal ─────────────────────────────────────────── */}
      {showLockConfigModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl p-6 space-y-4">
            <h3 className="text-base font-bold text-[var(--theme-text-primary)]">Configure Chat Lock</h3>
            
            <div className="space-y-3">
              <div className="space-y-1">
                <label className="text-xs font-bold text-[var(--theme-text-secondary)]">Secret Key / Passcode</label>
                <input
                  type="password"
                  value={lockSecretKey}
                  onChange={(e) => setLockSecretKey(e.target.value)}
                  placeholder="Enter a secret passcode"
                  className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3 py-2 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
                />
              </div>

              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--theme-text-secondary)]">Enable Fingerprint Lock</span>
                <input
                  type="checkbox"
                  checked={lockFingerprint}
                  onChange={(e) => setLockFingerprint(e.target.checked)}
                  className="h-4 w-4 rounded border-gray-300 text-teal-600 focus:ring-teal-500 cursor-pointer"
                />
              </div>
            </div>

            <div className="flex gap-2 pt-2">
              <button
                onClick={handleRemoveLock}
                className="flex-1 rounded-xl border border-red-500/30 text-red-400 py-2.5 text-xs font-bold hover:bg-red-500/10 transition-all cursor-pointer"
              >
                Remove Lock
              </button>
              <button
                onClick={handleSaveLockConfig}
                className="flex-1 rounded-xl bg-[var(--theme-accent)] text-black py-2.5 text-xs font-bold hover:opacity-90 transition-all cursor-pointer"
              >
                Save Lock
              </button>
            </div>
            
            <button
              onClick={() => { setShowLockConfigModal(false); setLockingChatId(null); }}
              className="w-full text-center text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all pt-1 cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* ── Lock Authentication Modal ───────────────────────────────────── */}
      {showLockAuthModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl p-6 space-y-4 text-center">
            <h3 className="text-base font-bold text-[var(--theme-text-primary)]">Locked Chat</h3>
            <p className="text-xs text-[var(--theme-text-secondary)]">
              This conversation is secure. Verify identity to view messages.
            </p>

            <div className="space-y-3">
              <input
                type="password"
                value={authSecretKeyInput}
                onChange={(e) => setAuthSecretKeyInput(e.target.value)}
                placeholder="Enter Secret Key"
                className="w-full text-center rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
              />

              {authenticatingChat && lockedChats[authenticatingChat.id]?.useFingerprint && (
                <button
                  type="button"
                  onClick={handleVerifyFingerprint}
                  className="w-full flex items-center justify-center gap-2 rounded-xl bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 py-2.5 text-xs font-bold text-teal-400 transition-all cursor-pointer"
                >
                  Verify Fingerprint
                </button>
              )}
            </div>

            <div className="flex gap-2 pt-2">
              <button
                onClick={() => { setShowLockAuthModal(false); setAuthenticatingChat(null); setAuthSecretKeyInput(""); }}
                className="flex-1 rounded-xl border border-[var(--theme-border-color)] py-2.5 text-xs font-semibold text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer"
              >
                Cancel
              </button>
              <button
                onClick={handleVerifySecretKey}
                className="flex-1 rounded-xl bg-[var(--theme-accent)] text-black py-2.5 text-xs font-bold hover:opacity-90 transition-all cursor-pointer"
              >
                Unlock
              </button>
            </div>
          </div>
        </div>
      )}
      {/* ── Starred Chats & Media Modal ─────────────────────────────── */}
      {showStarredModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl overflow-hidden flex flex-col max-h-[80vh]">
            <div className="px-6 pt-6 pb-4 flex items-center justify-between border-b border-[var(--theme-border-color)]">
              <div className="flex items-center gap-2">
                <Star className="h-5 w-5 text-amber-500 fill-amber-500" />
                <h3 className="text-base font-bold text-[var(--theme-text-primary)]">Starred Messages</h3>
              </div>
              <button
                onClick={() => setShowStarredModal(false)}
                className="p-1.5 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
              >
                <X className="h-4.5 w-4.5" />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-3">
              {starredMessagesList.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-center text-xs text-[var(--theme-text-secondary)]/50">
                  <Star className="h-8 w-8 text-zinc-600 mb-2" />
                  <p>No starred messages yet</p>
                  <p className="mt-1">Long press a message bubble and select Star to save here.</p>
                </div>
              ) : (
                starredMessagesList.map((m: any) => (
                  <div key={m.id} className="p-3 rounded-xl border border-[var(--theme-border-color)]/60 bg-[var(--theme-bg-sidebar-search)]/50 space-y-1.5 text-left">
                    <div className="flex items-center justify-between text-[10px] text-[var(--theme-text-secondary)]">
                      <span className="font-semibold text-[var(--theme-accent)]">{m.sender?.username || "Sender"}</span>
                      <span>{new Date(m.createdAt).toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
                    </div>
                    <p className="text-xs text-[var(--theme-text-primary)] whitespace-pre-wrap">{m.content}</p>
                    {m.mediaUrl && (
                      <span className="inline-block text-[9px] bg-[var(--theme-bg-sidebar-item-hover)] px-2 py-0.5 rounded text-[var(--theme-text-secondary)]">
                        {m.mediaType || "Attachment"}
                      </span>
                    )}
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
