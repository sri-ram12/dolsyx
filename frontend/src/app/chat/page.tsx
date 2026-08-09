"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useSocket } from "@/hooks/use-socket";
import { useRouter } from "next/navigation";
import ChatSidebar, { Chat } from "@/components/chat-sidebar";
import ChatWindow from "@/components/chat-window";
import ProductivityPanel from "@/components/productivity-panel";
import StatusPanel from "@/components/status-panel";
import CallModal from "@/components/call-modal";
import AppLock from "@/components/app-lock";
import { useWebRTC } from "@/hooks/use-webrtc";
import { SoundEngine } from "@/utils/sound";
import { MessageSquare, Phone, Circle, Settings as SettingsIcon } from "lucide-react";
import SettingsPanel from "@/components/settings-panel";
import CallsSidebar from "@/components/calls-sidebar";
import { usePushNotifications } from "@/hooks/use-push-notifications";
import { useE2EEInit } from "@/hooks/use-e2ee-init";

export default function ChatPage() {
  const { user, token, isAuthenticated, isLoading: authLoading, updateUser } = useAuth();
  const router = useRouter();
  const { socket } = useSocket(token);
  usePushNotifications();
  const { isInitialized: e2eeReady } = useE2EEInit();

  const [chats, setChats] = useState<Chat[]>([]);
  const [selectedChat, setSelectedChat] = useState<Chat | null>(null);
  const selectedChatRef = useRef<Chat | null>(null);
  const [onlineUsers, setOnlineUsers] = useState<string[]>([]);
  const [isChatsLoading, setIsChatsLoading] = useState(true);
  const [isProductivityOpen, setIsProductivityOpen] = useState(false);
  const [isLocked, setIsLocked] = useState(false); // starts false; useEffect below sets it if PIN exists
  const [activeRailTab, setActiveRailTab] = useState<"chats" | "calls">("chats");
  const [showSettingsPanel, setShowSettingsPanel] = useState(false);

  useEffect(() => {
    if (typeof window !== "undefined") {
      const hasPin = !!localStorage.getItem("dolsyx_pin_hash");
      const unlocked = sessionStorage.getItem("dolsyx_unlocked") === "true";
      setIsLocked(hasPin && !unlocked);
    }
  }, []);

  // ── Lock Timeout Logic ───────────────────────────────────────────────────
  useEffect(() => {
    if (typeof window === "undefined") return;

    let inactivityTimer: NodeJS.Timeout;
    
    const lockApp = () => {
      sessionStorage.removeItem("dolsyx_unlocked");
      setIsLocked(true);
    };

    const resetTimer = () => {
      const timeoutSetting = localStorage.getItem("dolsyx_lock_timeout") || "immediately";
      const hasPin = !!localStorage.getItem("dolsyx_pin_hash");
      const unlocked = sessionStorage.getItem("dolsyx_unlocked") === "true";
      
      clearTimeout(inactivityTimer);
      
      if (!hasPin || timeoutSetting === "off" || !unlocked) {
        return;
      }
      
      if (timeoutSetting === "immediately") {
        return;
      }

      const mins = parseInt(timeoutSetting, 10);
      if (!isNaN(mins) && mins > 0) {
        inactivityTimer = setTimeout(lockApp, mins * 60 * 1000);
      }
    };

    const handleVisibilityChange = () => {
      const hasPin = !!localStorage.getItem("dolsyx_pin_hash");
      const timeoutSetting = localStorage.getItem("dolsyx_lock_timeout") || "immediately";
      const unlocked = sessionStorage.getItem("dolsyx_unlocked") === "true";
      
      if (!hasPin || timeoutSetting === "off" || !unlocked) return;

      if (document.hidden) {
        if (timeoutSetting === "immediately") {
          lockApp();
        }
      } else {
        resetTimer();
      }
    };

    const activityEvents = ["mousedown", "keypress", "scroll", "touchstart"];
    activityEvents.forEach(e => document.addEventListener(e, resetTimer));
    document.addEventListener("visibilitychange", handleVisibilityChange);

    resetTimer();

    return () => {
      clearTimeout(inactivityTimer);
      activityEvents.forEach(e => document.removeEventListener(e, resetTimer));
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, []);

  // ── Audio unlock on first user interaction ────────────────────────────────
  useEffect(() => {
    const unlock = () => { SoundEngine.unlock(); };
    document.addEventListener("click", unlock, { once: true });
    document.addEventListener("touchstart", unlock, { once: true });
    return () => {
      document.removeEventListener("click", unlock);
      document.removeEventListener("touchstart", unlock);
    };
  }, []);

  // ── Mobile browser back button → go to chat list, not login page ─────────
  useEffect(() => {
    const onPopState = () => {
      if (selectedChatRef.current) {
        // Push a new state to preserve history stack
        window.history.pushState(null, "", window.location.href);
        setSelectedChat(null);
      }
    };
    // Push an initial state so we can intercept the first back press
    window.history.pushState(null, "", window.location.href);
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  // Unread message counts
  const [unreadCounts, setUnreadCounts] = useState<Record<string, number>>({});

  // Status panel
  const [showStatusPanel, setShowStatusPanel] = useState(false);

  // ── Call States ──────────────────────────────────────────────────────────
  const [callState, setCallState] = useState<{
    isOpen: boolean;
    type: "audio" | "video";
    status: "incoming" | "outgoing" | "connected" | "disconnected";
    peerId: string;
    peerName: string;
    peerAvatar: string | null;
    conversationId: string;
    offer: any | null;
    callerId: string;
  }>({
    isOpen: false,
    type: "audio",
    status: "disconnected",
    peerId: "",
    peerName: "",
    peerAvatar: null,
    conversationId: "",
    offer: null,
    callerId: "",
  });

  const callStateRef = useRef(callState);
  useEffect(() => {
    callStateRef.current = callState;
  }, [callState]);

  const [callDuration, setCallDuration] = useState(0);

  // Call timer duration
  useEffect(() => {
    let timer: any;
    if (callState.status === "connected") {
      setCallDuration(0);
      timer = setInterval(() => {
        setCallDuration((prev) => prev + 1);
      }, 1000);
    } else {
      setCallDuration(0);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [callState.status]);

  const {
    localStream,
    remoteStream,
    isMuted,
    isCameraOff,
    isSpeakerOff,
    createOffer,
    handleOffer,
    handleAnswer,
    addIceCandidate,
    hangup,
    toggleMute,
    toggleCamera,
    toggleSpeaker,
    switchCallCamera,
    isScreenSharing,
    toggleScreenShare,
  } = useWebRTC({
    onIceCandidate: (candidate) => {
      if (socket && callStateRef.current.peerId) {
        socket.emit("ice_candidate", {
          targetUserId: callStateRef.current.peerId,
          candidate,
        });
      }
    },
  });

  const handleStartCall = async (type: "audio" | "video", targetChat?: Chat) => {
    const currentChat = targetChat || selectedChat;
    if (!currentChat || !currentChat.recipient) return;
    const peer = currentChat.recipient;

    setCallState({
      isOpen: true,
      type,
      status: "outgoing",
      peerId: peer.id,
      peerName: peer.username,
      peerAvatar: peer.avatarUrl,
      conversationId: currentChat.id,
      offer: null,
      callerId: user?.id || "",
    });

    try {
      const offer = await createOffer(type);
      socket?.emit("call_offer", {
        targetUserId: peer.id,
        offer,
        callType: type,
        conversationId: currentChat.id,
        callerName: user?.username || "Someone",
        callerAvatar: user?.avatarUrl || null,
      });
    } catch (e) {
      console.error("Failed to start call:", e);
      setCallState((prev) => ({ ...prev, status: "disconnected" }));
      hangup();
      setTimeout(() => {
        setCallState((prev) => ({ ...prev, isOpen: false }));
      }, 1500);
    }
  };

  const handleAcceptCall = async () => {
    if (!callState.peerId) return;
    setCallState((prev) => ({ ...prev, status: "connected" }));
    try {
      if (callState.offer) {
        const answer = await handleOffer(callState.offer, callState.type);
        socket?.emit("call_answer", {
          callerId: callState.peerId,
          answer,
        });
      } else {
        socket?.emit("request_call_offer", {
          callerId: callState.peerId,
          conversationId: callState.conversationId,
        });
      }
    } catch (e) {
      console.error("Failed to accept call:", e);
      handleDeclineCall();
    }
  };

  const handleDeclineCall = () => {
    if (callState.peerId) {
      socket?.emit("call_reject", {
        callerId: callState.peerId,
        conversationId: callState.conversationId,
        callType: callState.type,
      });
    }
    setCallState((prev) => ({ ...prev, status: "disconnected" }));
    hangup();
    setTimeout(() => {
      setCallState((prev) => ({ ...prev, isOpen: false }));
    }, 1500);
  };

  const handleHangupCall = () => {
    if (callState.peerId) {
      const isConnected = callState.status === "connected";
      socket?.emit("call_end", {
        peerId: callState.peerId,
        conversationId: callState.conversationId,
        callType: callState.type,
        status: isConnected ? "connected" : "missed",
        duration: isConnected ? callDuration : undefined,
        callerId: callState.callerId,
      });
    }
    setCallState((prev) => ({ ...prev, status: "disconnected" }));
    hangup();
    setTimeout(() => {
      setCallState((prev) => ({ ...prev, isOpen: false }));
    }, 1500);
  };

  // Keep selectedChatRef in sync
  useEffect(() => {
    selectedChatRef.current = selectedChat;
  }, [selectedChat]);

  // Request browser notification permission on mount
  useEffect(() => {
    if (typeof window !== "undefined" && "Notification" in window && Notification.permission === "default") {
      Notification.requestPermission();
    }
  }, []);

  // Redirect if not authenticated
  useEffect(() => {
    if (!authLoading && !isAuthenticated) {
      router.push("/login");
    }
  }, [isAuthenticated, authLoading, router]);

  // Fetch conversations list
  const fetchChats = useCallback(async () => {
    if (!token) return;

    // Load offline chats immediately if available
    try {
      const cached = localStorage.getItem("dolsyx_offline_chats");
      if (cached) {
        const data = JSON.parse(cached);
        setChats(data);
        const initialUnreads: Record<string, number> = {};
        data.forEach((c: any) => {
          if (c.unreadCount > 0) {
            initialUnreads[c.id] = c.unreadCount;
          }
        });
        setUnreadCounts(initialUnreads);
      }
    } catch (e) {
      console.warn("Could not load offline chats", e);
    }

    // Safety timeout – if the request hangs for >10s, release the loading spinner
    const timeoutId = setTimeout(() => setIsChatsLoading(false), 10000);
    try {
      const res = await fetch(`${API_URL}/api/chats`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (res.ok) {
        const data = await res.json();
        setChats(data);

        // Cache for offline
        localStorage.setItem("dolsyx_offline_chats", JSON.stringify(data));

        // Populate initial unread counts from persistent database state
        const initialUnreads: Record<string, number> = {};
        data.forEach((c: any) => {
          if (c.unreadCount > 0) {
            initialUnreads[c.id] = c.unreadCount;
          }
        });
        setUnreadCounts(initialUnreads);
      }
    } catch (err) {
      console.error("Error fetching chats:", err);
      // If network fails and we have no cached chats, we still stop loading
    } finally {
      clearTimeout(timeoutId);
      setIsChatsLoading(false);
    }
  }, [token]);

  useEffect(() => {
    if (token) {
      fetchChats();
    }
  }, [token, fetchChats]);

  // Clear unread when selecting a chat
  const handleSelectChat = useCallback((chat: Chat | null) => {
    setSelectedChat(chat);
    if (!chat) return;
    setUnreadCounts((prev) => {
      const next = { ...prev };
      delete next[chat.id];
      return next;
    });
  }, []);

  // Fire a browser notification
  const fireNotification = useCallback((title: string, body: string, iconUrl?: string, conversationId?: string) => {
    if (typeof window === "undefined") return;
    
    // Only skip notification if document is visible AND the user has the SPECIFIC conversation open
    if (document.visibilityState === "visible" && selectedChatRef.current && selectedChatRef.current.id === conversationId) {
      return;
    }

    if ("Notification" in window && Notification.permission === "granted") {
      try {
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then((registration) => {
            registration.showNotification(title, {
              body,
              icon: iconUrl || "/dolsyx-logo.png",
              badge: "/dolsyx-logo.png",
              tag: conversationId || "new-message",
              data: { url: "/chat" },
              vibrate: [200, 100, 200]
            } as any);
          }).catch(e => console.error("SW notification error", e));
        } else {
          const notif = new Notification(title, {
            body,
            icon: iconUrl || "/dolsyx-logo.png",
            silent: false,
          });
          notif.onclick = () => {
            window.focus();
            notif.close();
          };
        }
      } catch (e) {
        console.error("Failed to show notification:", e);
      }
    }
  }, []);

  // Set up socket listeners for online status and real-time sidebar updates
  useEffect(() => {
    if (!socket) return;

    socket.on("online_users_list", (usersList: string[]) => {
      setOnlineUsers(usersList);
    });

    socket.on(
      "user_status_change",
      (data: { userId: string; status: "online" | "offline"; lastSeen?: string; onlineUsers?: string[] }) => {
        setOnlineUsers((prev) => {
          if (data.status === "online") {
            return Array.from(new Set([...prev, data.userId]));
          } else {
            return prev.filter(id => id !== data.userId);
          }
        });

        setChats((prev) =>
          prev.map((c) => {
            if (c.recipient && c.recipient.id === data.userId) {
              return {
                ...c,
                recipient: {
                  ...c.recipient,
                  lastSeen: data.status === "offline" && data.lastSeen ? data.lastSeen : c.recipient.lastSeen,
                },
              };
            }
            return c;
          })
        );

        setSelectedChat((prev) => {
          if (prev && prev.recipient && prev.recipient.id === data.userId) {
            return {
              ...prev,
              recipient: {
                ...prev.recipient,
                lastSeen: data.status === "offline" && data.lastSeen ? data.lastSeen : prev.recipient.lastSeen,
              },
            };
          }
          return prev;
        });
      }
    );

    // Listen for conversation deleted events
    socket.on("conversation_deleted", (data: { conversationId: string }) => {
      setChats((prev) => prev.filter((c) => c.id !== data.conversationId));
      setSelectedChat((prev) => {
        if (prev && prev.id === data.conversationId) {
          return null;
        }
        return prev;
      });
      // Also clear unread for this conversation
      setUnreadCounts((prev) => {
        const next = { ...prev };
        delete next[data.conversationId];
        return next;
      });
    });

    // Listen for new conversations (like newly created groups)
    socket.on("new_conversation", (data: { chat: Chat }) => {
      setChats((prevChats) => {
        const exactExists = prevChats.some((c) => c.id === data.chat.id);
        if (exactExists) return prevChats;

        if (!data.chat.isGroup && data.chat.recipient) {
          const existingDirectIndex = prevChats.findIndex(
            (c) => !c.isGroup && c.recipient && c.recipient.id === data.chat.recipient!.id
          );
          if (existingDirectIndex !== -1) {
            const updated = [...prevChats];
            updated[existingDirectIndex] = data.chat;
            return updated;
          }
        }

        return [data.chat, ...prevChats];
      });
    });

    // Listen for incoming messages to update the sidebar's preview state and sorting order
    socket.on("new_message", (data: { message: any; conversationId: string }) => {
      setChats((prevChats) => {
        const updated = prevChats.map((c) => {
          if (c.id === data.conversationId) {
            return {
              ...c,
              lastMessage: data.message,
              updatedAt: data.message.createdAt,
            };
          }
          return c;
        });

        // If the conversation doesn't exist in the list yet, pull fresh list
        const exists = prevChats.some((c) => c.id === data.conversationId);
        if (!exists) {
          fetchChats();
          return prevChats;
        }

        // Re-sort chats so the most recently updated one is on top
        return [...updated].sort(
          (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
        );
      });

      // Increment unread count if this message is NOT for the currently viewed chat
      // and it's not sent by the current user
      const currentChat = selectedChatRef.current;
      if (data.message.senderId !== user?.id) {
        if (!currentChat || currentChat.id !== data.conversationId) {
          setUnreadCounts((prev) => ({
            ...prev,
            [data.conversationId]: (prev[data.conversationId] || 0) + 1,
          }));
        }

        // Fire browser notification
        const senderName = data.message.sender?.username || "Someone";
        
        // Use a function to safely get chat name from current state
        setChats(currentChats => {
          const chatName = currentChats.find((c) => c.id === data.conversationId)?.name || senderName;
          let body = data.message.content || "";
          if (data.message.mediaType === "IMAGE") body = "📷 Image";
          if (data.message.mediaType === "VIDEO") body = "🎬 Video";
          if (data.message.mediaType === "AUDIO") body = "🎵 Audio";
          if (data.message.mediaType === "FILE") body = "📎 File";
          
          fireNotification(chatName, `${senderName}: ${body}`, data.message.sender?.avatarUrl, data.conversationId);
          return currentChats; // Don't actually change chats here
        });
      }
    });

    // Listen for profile updates
    socket.on("profile_updated", (data: { user: any }) => {
      // If it's my own profile that was updated (e.g. from another tab or mobile)
      if (data.user.id === user?.id) {
        updateUser(data.user);
      }
      
      // Update chat list if the updated user is a participant/recipient
      setChats((prevChats) =>
        prevChats.map((chat) => {
          if (chat.isGroup) {
             const updatedParticipants = chat.participants?.map((p) => {
               if (p.user.id === data.user.id) {
                 return { ...p, user: { ...p.user, ...data.user } };
               }
               return p;
             });
             return { ...chat, participants: updatedParticipants };
          } else {
             if (chat.recipient?.id === data.user.id) {
               return {
                 ...chat,
                 recipient: { ...chat.recipient, ...data.user },
                 name: data.user.username,
                 avatarUrl: data.user.avatarUrl,
               };
             }
             return chat;
          }
        })
      );
    });

    // Listen for new status updates
    socket.on("new_status", () => {
      // The status panel will refresh its own data when opened
    });

    // Call Signaling listeners
    socket.on("call_incoming", (data: {
      callerId: string;
      callerName: string;
      callerAvatar: string | null;
      offer: any;
      callType: "audio" | "video";
      conversationId: string;
    }) => {
      setCallState({
        isOpen: true,
        type: data.callType,
        status: "incoming",
        peerId: data.callerId,
        peerName: data.callerName,
        peerAvatar: data.callerAvatar,
        conversationId: data.conversationId,
        offer: data.offer,
        callerId: data.callerId,
      });
    });

    socket.on("request_call_offer", async (data: { requesterId: string; conversationId: string }) => {
      try {
        const type = callStateRef.current.type || "video";
        const offer = await createOffer(type);
        socket.emit("call_offer", {
          targetUserId: data.requesterId,
          offer,
          callType: type,
          conversationId: data.conversationId,
          callerName: user?.username || "Someone",
          callerAvatar: user?.avatarUrl || null,
        });
      } catch (e) {
        console.error("Failed to re-send offer on request:", e);
      }
    });

    socket.on("call_answered", async (data: { answer: any; answererId: string }) => {
      setCallState((prev) => ({ ...prev, status: "connected" }));
      await handleAnswer(data.answer);
    });

    socket.on("call_rejected", (data: { rejecterId: string }) => {
      setCallState((prev) => ({ ...prev, status: "disconnected" }));
      hangup();
      setTimeout(() => {
        setCallState((prev) => ({ ...prev, isOpen: false }));
      }, 1500);
    });

    socket.on("call_ended", (data: { endedBy: string }) => {
      setCallState((prev) => ({ ...prev, status: "disconnected" }));
      hangup();
      setTimeout(() => {
        setCallState((prev) => ({ ...prev, isOpen: false }));
      }, 1500);
    });

    socket.on("ice_candidate", async (data: { candidate: any; fromUserId: string }) => {
      await addIceCandidate(data.candidate);
    });

    socket.on("poll_updated", (data: { conversationId: string; messageId: string; content: string }) => {
      setMessages((prevMessages: any[]) =>
        prevMessages.map((msg) => (msg.id === data.messageId ? { ...msg, content: data.content } : msg))
      );
      setChats((prevChats) =>
        prevChats.map((c) => {
          if (c.id === data.conversationId && c.lastMessage?.id === data.messageId) {
            return {
              ...c,
              lastMessage: { ...c.lastMessage, content: data.content },
            };
          }
          return c;
        })
      );
    });

    return () => {
      socket.off("online_users_list");
      socket.off("user_status_change");
      socket.off("conversation_deleted");
      socket.off("new_conversation");
      socket.off("new_message");
      socket.off("poll_updated");
      socket.off("new_status");
      socket.off("call_incoming");
      socket.off("request_call_offer");
      socket.off("call_answered");
      socket.off("call_rejected");
      socket.off("call_ended");
      socket.off("ice_candidate");
    };
  }, [socket, user, fetchChats, fireNotification]);

  const handleChatCreated = (newChat: Chat) => {
    setChats((prev) => {
      // Avoid duplication by exact chat ID
      const exactExists = prev.some((c) => c.id === newChat.id);
      if (exactExists) return prev;

      // Avoid duplication by recipient ID for direct chats
      if (!newChat.isGroup && newChat.recipient) {
        const existingDirectIndex = prev.findIndex(
          (c) => !c.isGroup && c.recipient && c.recipient.id === newChat.recipient!.id
        );
        if (existingDirectIndex !== -1) {
          // If we found an older version of this direct chat, replace it instead of duplicating
          const updated = [...prev];
          updated[existingDirectIndex] = newChat;
          return updated;
        }
      }

      return [newChat, ...prev];
    });
    setSelectedChat(newChat);
  };



  return (
    <div className="flex h-screen w-screen overflow-hidden" style={{ background: "var(--theme-bg-app)" }}>
      <div className="flex flex-col-reverse sm:flex-row h-full w-full overflow-hidden border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] backdrop-blur-xl shadow-2xl relative">
        
        {/* Navigation Rail (Bottom on Mobile, Left on Desktop) */}
        <div className={`
          ${selectedChat ? "hidden sm:flex" : "flex"} 
          flex-row sm:flex-col 
          items-center justify-around sm:justify-between 
          w-full sm:w-16 
          h-[60px] sm:h-full 
          bg-[var(--theme-bg-sidebar-header)] 
          border-t sm:border-t-0 sm:border-r border-[var(--theme-border-color)] 
          py-1 sm:py-4 
          shrink-0 transition-colors duration-300 z-10
        `}>
          <div className="flex flex-row sm:flex-col items-center justify-around sm:justify-start gap-1 sm:gap-4 w-full h-full sm:h-auto px-2 sm:px-0">
            <button
              onClick={() => { setActiveRailTab("chats"); setShowSettingsPanel(false); setSelectedChat(null); }}
              className={`flex flex-col sm:flex-row items-center justify-center p-2 sm:p-3 rounded-xl transition-all cursor-pointer flex-1 sm:flex-none ${activeRailTab === "chats" && !showSettingsPanel ? "text-[var(--theme-accent)] sm:bg-[var(--theme-accent)]/20" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"}`}
              title="Chats"
            >
              <MessageSquare className="h-6 w-6 sm:h-6 sm:w-6 mb-1 sm:mb-0" />
              <span className="text-[10px] font-medium sm:hidden">Chats</span>
            </button>
            <button
              onClick={() => setShowStatusPanel(true)}
              className="flex flex-col sm:flex-row items-center justify-center p-2 sm:p-3 rounded-xl text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer flex-1 sm:flex-none"
              title="Status Updates"
            >
              <Circle className="h-6 w-6 sm:h-6 sm:w-6 mb-1 sm:mb-0" />
              <span className="text-[10px] font-medium sm:hidden">Status</span>
            </button>
            <button
              onClick={() => { setActiveRailTab("calls"); setShowSettingsPanel(false); setSelectedChat(null); }}
              className={`flex flex-col sm:flex-row items-center justify-center p-2 sm:p-3 rounded-xl transition-all cursor-pointer flex-1 sm:flex-none ${activeRailTab === "calls" && !showSettingsPanel ? "text-[var(--theme-accent)] sm:bg-[var(--theme-accent)]/20" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"}`}
              title="Calls"
            >
              <Phone className="h-6 w-6 sm:h-6 sm:w-6 mb-1 sm:mb-0" />
              <span className="text-[10px] font-medium sm:hidden">Calls</span>
            </button>
            {/* Settings button on mobile */}
            <button
              onClick={() => setShowSettingsPanel(true)}
              className={`flex sm:hidden flex-col items-center justify-center p-2 rounded-xl transition-all cursor-pointer flex-1 ${showSettingsPanel ? "text-[var(--theme-accent)]" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"}`}
              title="Settings"
            >
              <SettingsIcon className="h-6 w-6 mb-1" />
              <span className="text-[10px] font-medium">Settings</span>
            </button>
          </div>
          
          <div className="hidden sm:flex flex-col items-center gap-4 w-full">
            <button
              onClick={() => setShowSettingsPanel(true)}
              className={`p-3 rounded-xl transition-all cursor-pointer ${showSettingsPanel ? "bg-[var(--theme-accent)]/20 text-[var(--theme-accent)]" : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"}`}
              title="Settings"
            >
              <SettingsIcon className="h-6 w-6" />
            </button>
            {user && (
              <div 
                className="p-1 cursor-pointer hover:opacity-80 transition-opacity" 
                onClick={() => setShowSettingsPanel(true)}
                title="Profile"
              >
                <img 
                  src={user.avatarUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(user.username)}&background=0D8ABC&color=fff`} 
                  alt="Profile" 
                  className="h-8 w-8 rounded-full border border-[var(--theme-border-color)] object-cover" 
                />
              </div>
            )}
          </div>
        </div>

        {/* Content Area */}
        <div className="flex flex-row flex-1 overflow-hidden w-full relative">
          {/* On mobile, show sidebar only if no chat is selected */}
          <div
            className={`${selectedChat ? "hidden sm:flex" : "flex"} h-full w-full sm:w-auto shrink-0`}
          >
            {showSettingsPanel ? (
              <div className="w-full sm:w-80 h-full">
                <SettingsPanel
                  onClose={() => setShowSettingsPanel(false)}
                  onSelectChat={handleSelectChat as any}
                />
              </div>
            ) : activeRailTab === "calls" ? (
              <div className="h-full w-full sm:w-80 border-r border-[var(--theme-border-color)]">
                <CallsSidebar onStartCall={(chatId, type) => {
                  const chat = chats.find(c => c.id === chatId);
                  if (chat) {
                    setSelectedChat(chat);
                    handleStartCall(type, chat);
                  }
                }} />
              </div>
            ) : (
              <ChatSidebar
                chats={chats}
                selectedChatId={selectedChat?.id || null}
                onSelectChat={handleSelectChat}
                onlineUsers={onlineUsers}
                onChatCreated={handleChatCreated}
                unreadCounts={unreadCounts}
                onOpenStatus={() => setShowStatusPanel(true)}
              />
            )}
          </div>

          {/* On mobile, show chat window only if a chat is selected */}
          <div className={`${selectedChat ? "flex" : "hidden sm:flex"} h-full flex-1 w-full relative`}>
            <ChatWindow
              chat={selectedChat}
              socket={socket}
              onlineUsers={onlineUsers}
              onBack={() => setSelectedChat(null)}
              onToggleProductivity={() => setIsProductivityOpen(!isProductivityOpen)}
              isProductivityOpen={isProductivityOpen}
              onChatDeleted={(conversationId) => {
                setChats((prev) => prev.filter((c) => c.id !== conversationId));
                setSelectedChat(null);
              }}
              onStartCall={handleStartCall}
            />
          </div>

          {/* Productivity Workspace slide-out panel */}
          {isProductivityOpen && (
            <ProductivityPanel
              activeConversationId={selectedChat?.id || null}
              activeConversationName={selectedChat?.name || null}
              isGroupChat={selectedChat?.isGroup || false}
              participants={(selectedChat as any)?.participants || []}
              onClose={() => setIsProductivityOpen(false)}
            />
          )}
        </div>
      </div>

      {/* Status Panel */}
      {showStatusPanel && (
        <StatusPanel onClose={() => setShowStatusPanel(false)} />
      )}

      {/* Call Modal */}
      <CallModal
        isOpen={callState.isOpen}
        callType={callState.type}
        status={callState.status}
        callerName={callState.peerName}
        callerAvatar={callState.peerAvatar}
        localStream={localStream}
        remoteStream={remoteStream}
        isMuted={isMuted}
        isCameraOff={isCameraOff}
        isSpeakerOff={isSpeakerOff}
        onAccept={handleAcceptCall}
        onDecline={handleDeclineCall}
        onHangup={handleHangupCall}
        onToggleMute={toggleMute}
        onToggleCamera={toggleCamera}
        onToggleSpeaker={toggleSpeaker}
        onSwitchCamera={switchCallCamera}
        isScreenSharing={isScreenSharing}
        onToggleScreenShare={toggleScreenShare}
        duration={callDuration}
      />

      {isLocked && (
        <AppLock onUnlock={() => setIsLocked(false)} />
      )}
    </div>
  );
}
