"use client";

import React, { useState, useEffect } from "react";
import { useAuth, API_URL } from "@/context/auth-context";
import { getAvatarUrl } from "@/utils/avatar";
import { useSocket } from "@/hooks/use-socket";
import { Phone, Video, PhoneIncoming, PhoneOutgoing, PhoneMissed, Trash2, X, MoreVertical, CheckSquare, MessageSquare } from "lucide-react";
interface CallLog {
  id: string;
  createdAt: string;
  content: string; // "missed", "declined", "connected:duration"
  mediaUrl: string; // "video" or "audio"
  sender: {
    id: string;
    username: string;
    avatarUrl: string | null;
  };
  conversation: {
    id: string;
    participants: {
      userId: string;
      user: {
        id: string;
        username: string;
        avatarUrl: string | null;
      };
    }[];
  };
}

export default function CallsSidebar({ onStartCall }: { onStartCall?: (chatId: string, type: "audio" | "video") => void }) {
  const { token, user } = useAuth();
  const [calls, setCalls] = useState<CallLog[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedCalls, setSelectedCalls] = useState<Set<string>>(new Set());
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [localDeletedMsgIds, setLocalDeletedMsgIds] = useState<string[]>([]);
  const [showMenu, setShowMenu] = useState(false);
  const pressTimerRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (typeof window !== "undefined") {
      setLocalDeletedMsgIds(JSON.parse(localStorage.getItem("dolsyx_deleted_msgs") || "[]"));
    }
  }, []);

  useEffect(() => {
    const fetchCalls = async () => {
      if (!token) return;
      try {
        const res = await fetch(`${API_URL}/api/chats/calls`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res.ok) {
          const data = await res.json();
          setCalls(data);
        }
      } catch (e) {
        console.error("Error fetching calls:", e);
      } finally {
        setIsLoading(false);
      }
    };
    fetchCalls();
  }, [token]);

  const { socket } = useSocket(token);
  useEffect(() => {
    if (!socket) return;
    const handleProfileUpdated = (data: { user: any }) => {
      setCalls(prev => prev.map(call => {
        let updated = false;
        const newCall = { ...call };
        
        if (newCall.sender.id === data.user.id) {
          newCall.sender = { ...newCall.sender, ...data.user };
          updated = true;
        }
        
        if (newCall.conversation.participants) {
          newCall.conversation.participants = newCall.conversation.participants.map(p => {
            if (p.user.id === data.user.id) {
              updated = true;
              return { ...p, user: { ...p.user, ...data.user } };
            }
            return p;
          });
        }
        
        return updated ? newCall : call;
      }));
    };
    socket.on("profile_updated", handleProfileUpdated);
    return () => {
      socket.off("profile_updated", handleProfileUpdated);
    };
  }, [socket]);

  const startPress = (callId: string) => {
    if (isSelectionMode) return;
    pressTimerRef.current = setTimeout(() => {
      setIsSelectionMode(true);
      setSelectedCalls(new Set([callId]));
    }, 600);
  };

  const endPress = () => {
    if (pressTimerRef.current) clearTimeout(pressTimerRef.current);
  };

  const handleCallClick = (callId: string, e: React.MouseEvent) => {
    if (isSelectionMode) {
      e.stopPropagation();
      const newSelected = new Set(selectedCalls);
      if (newSelected.has(callId)) {
        newSelected.delete(callId);
        if (newSelected.size === 0) setIsSelectionMode(false);
      } else {
        newSelected.add(callId);
      }
      setSelectedCalls(newSelected);
    }
  };

  const exitSelectionMode = () => {
    setIsSelectionMode(false);
    setSelectedCalls(new Set());
  };

  const deleteSelectedCalls = () => {
    const deletedList = JSON.parse(localStorage.getItem("dolsyx_deleted_msgs") || "[]");
    const newDeleted = [...deletedList, ...Array.from(selectedCalls)];
    localStorage.setItem("dolsyx_deleted_msgs", JSON.stringify(newDeleted));
    setLocalDeletedMsgIds(newDeleted);
    exitSelectionMode();
  };

  const clearAllCalls = () => {
    const deletedList = JSON.parse(localStorage.getItem("dolsyx_deleted_msgs") || "[]");
    const newDeleted = [...deletedList, ...calls.map(c => c.id)];
    localStorage.setItem("dolsyx_deleted_msgs", JSON.stringify(newDeleted));
    setLocalDeletedMsgIds(newDeleted);
    setShowMenu(false);
  };

  const visibleCalls = calls.filter(c => !localDeletedMsgIds.includes(c.id));

  const formatTimeAgo = (dateStr: string) => {
    const d = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return "Just now";
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays === 1) return "Yesterday";
    return d.toLocaleDateString();
  };

  return (
    <div className="flex flex-col h-full w-full sm:w-80 border-r border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] backdrop-blur-md relative">
      {isSelectionMode ? (
        <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] px-4 py-3 shadow-md z-10">
          <div className="flex items-center gap-4">
            <button onClick={exitSelectionMode} className="hover:bg-[var(--theme-bg-sidebar-item-hover)] p-1.5 rounded-full cursor-pointer text-[var(--theme-text-primary)] transition-colors">
              <X className="h-5 w-5" />
            </button>
            <span className="font-semibold text-[var(--theme-text-primary)]">{selectedCalls.size}</span>
          </div>
          <button onClick={deleteSelectedCalls} className="p-2 text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-red-500 rounded-full cursor-pointer transition-colors" title="Delete">
            <Trash2 className="h-5 w-5" />
          </button>
        </div>
      ) : (
        <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] px-6 py-5">
          <span className="text-xl font-black tracking-wider text-[var(--theme-text-primary)]">
            Calls
          </span>
          <div className="flex items-center gap-2 relative">
            <button className="p-2 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] rounded-full transition-colors cursor-pointer" title="New Call">
              <MessageSquare className="h-5 w-5" />
            </button>
            <button onClick={() => setShowMenu(!showMenu)} className="p-2 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] rounded-full transition-colors cursor-pointer">
              <MoreVertical className="h-5 w-5" />
            </button>
            {showMenu && (
              <div className="absolute right-0 top-10 z-50 w-48 rounded-lg border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] py-1 shadow-xl animate-fade-in text-left">
                <button
                  onClick={clearAllCalls}
                  className="w-full text-left px-4 py-2 text-sm text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] cursor-pointer"
                >
                  Clear call log
                </button>
              </div>
            )}
          </div>
        </div>
      )}
      <div className="flex-1 overflow-y-auto overflow-x-hidden custom-scrollbar">
        {isLoading ? (
          <div className="flex flex-col gap-3 p-4">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="flex items-center gap-3 w-full animate-pulse">
                <div className="h-12 w-12 rounded-full bg-[var(--theme-border-color)]" />
                <div className="flex-1 flex flex-col gap-2">
                  <div className="h-4 w-24 bg-[var(--theme-border-color)] rounded" />
                  <div className="h-3 w-16 bg-[var(--theme-border-color)] rounded" />
                </div>
              </div>
            ))}
          </div>
        ) : visibleCalls.length === 0 ? (
          <div className="flex-1 flex flex-col items-center justify-center p-6 text-center mt-20">
            <div className="h-16 w-16 rounded-full bg-[var(--theme-accent)]/10 flex items-center justify-center mb-4 text-[var(--theme-accent)]">
              <Phone className="h-8 w-8" />
            </div>
            <h3 className="text-lg font-semibold text-[var(--theme-text-primary)] mb-2">No recent calls</h3>
            <p className="text-sm text-[var(--theme-text-secondary)]">Your recent voice and video calls will appear here.</p>
          </div>
        ) : (
          <div className="p-2 space-y-1">
            {visibleCalls.map((call) => {
              const isOutgoing = call.sender.id === user?.id;
              
              // Find the peer user
              const peer = call.conversation.participants.find(p => p.user.id !== user?.id)?.user;
              const peerName = peer?.username || "Unknown";
              const peerAvatar = peer?.avatarUrl || null;
              
              const isMissed = !isOutgoing && (call.content === "missed" || call.content === "declined");
              
              const CallIcon = call.mediaUrl === "video" ? Video : Phone;
              
              let StatusIcon = PhoneIncoming;
              let statusColor = "text-emerald-500";
              if (isOutgoing) {
                StatusIcon = PhoneOutgoing;
                statusColor = "text-emerald-500";
              } else if (isMissed) {
                StatusIcon = PhoneMissed;
                statusColor = "text-red-500";
              }
              
              return (
                <div 
                  key={call.id} 
                  className={`flex items-center gap-3 w-full rounded-xl px-3 py-2.5 transition-colors text-left cursor-pointer ${
                    selectedCalls.has(call.id) ? "bg-[var(--theme-bg-sidebar-item-hover)]" : "hover:bg-[var(--theme-bg-sidebar-item-hover)]"
                  }`}
                  onMouseDown={() => startPress(call.id)}
                  onMouseUp={endPress}
                  onMouseLeave={endPress}
                  onTouchStart={() => startPress(call.id)}
                  onTouchEnd={endPress}
                  onClick={(e) => handleCallClick(call.id, e)}
                >
                  <div className="relative shrink-0">
                    {isSelectionMode && (
                      <div className="absolute -bottom-1 -right-1 z-10 rounded-full bg-white shadow-md">
                        {selectedCalls.has(call.id) ? (
                          <CheckSquare className="h-5 w-5 text-[#00a884]" fill="currentColor" stroke="white" />
                        ) : (
                          <div className="h-4 w-4 rounded border-2 border-gray-400 bg-white" />
                        )}
                      </div>
                    )}
                    <img
                      src={getAvatarUrl(peerAvatar, peerName)}
                      alt={peerName}
                      className="h-12 w-12 rounded-full object-cover border border-[var(--theme-border-color)] bg-zinc-800"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`text-sm font-semibold truncate ${isMissed ? "text-red-500" : "text-[var(--theme-text-primary)]"}`}>
                      {peerName}
                    </p>
                    <div className="flex items-center gap-1.5 mt-0.5">
                      <StatusIcon className={`h-3 w-3 ${statusColor}`} />
                      <p className="text-xs text-[var(--theme-text-secondary)] truncate">
                        {formatTimeAgo(call.createdAt)}
                      </p>
                    </div>
                  </div>
                  <div className="shrink-0 flex items-center gap-2">
                    {onStartCall && peer && (
                      <button 
                        className="p-2 text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] hover:bg-[var(--theme-bg-sidebar-search)] rounded-full transition-colors cursor-pointer"
                        onClick={(e) => { e.stopPropagation(); onStartCall(call.conversation.id, call.mediaUrl as "audio" | "video"); }}
                        title={`Call ${peerName}`}
                      >
                        <CallIcon className="h-5 w-5" />
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
