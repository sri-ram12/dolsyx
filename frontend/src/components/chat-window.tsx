"use client";

import React, { useState, useEffect, useRef } from "react";
import TwemojiText from "./twemoji-text";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { useToast } from "@/context/toast-context";
import { Chat } from "./chat-sidebar";
import {
  Send,
  Smile,
  Info,
  MoreVertical,
  ArrowLeft,
  CheckSquare,
  CornerUpLeft,
  Edit3,
  Trash2,
  X,
  Paperclip,
  Download,
  FileIcon,
  Loader2,
  Play,
  Volume2,
  User,
  Phone,
  Video,
  Mail,
  Camera,
  Mic,
  Square,
  Image as ImageIcon,
  Ban,
  RefreshCw,
  Star,
  Share2,
} from "lucide-react";
import { Socket } from "socket.io-client";
import EmojiPicker, { EmojiClickData, Theme } from "emoji-picker-react";
import { getDefaultAvatar, getAvatarUrl, resolveMediaUrl } from "@/utils/avatar";
import { SoundEngine } from "@/utils/sound";

interface Message {
  id: string;
  content: string;
  senderId: string;
  conversationId: string;
  createdAt: string;
  isEdited?: boolean;
  isDeleted?: boolean;
  mediaUrl?: string | null;
  mediaType?: "TEXT" | "IMAGE" | "VIDEO" | "FILE" | "AUDIO" | "CODE_SNIPPET" | "STICKER" | "CALL_LOG" | null;
  sender: {
    id: string;
    username: string;
    avatarUrl: string | null;
    bio?: string | null;
  };
  receipts?: any[];
  parentMessage?: {
    id: string;
    content: string;
    sender: {
      id: string;
      username: string;
    };
  } | null;
}

interface ChatWindowProps {
  chat: Chat | null;
  socket: Socket | null;
  onlineUsers: string[];
  onBack: () => void;
  onToggleProductivity: () => void;
  isProductivityOpen: boolean;
  onChatDeleted?: (conversationId: string) => void;
  onStartCall?: (type: "audio" | "video") => void;
}

// Chat wallpaper backgrounds — classic & AI-generated
const WALLPAPER_CATEGORIES = [
  { id: "doodle", name: "Doodles" },
  { id: "gradient", name: "Gradients" },
  { id: "nature", name: "Nature" },
  { id: "abstract", name: "Abstract" },
  { id: "minimal", name: "Minimal" },
  { id: "texture", name: "Textures" },
  { id: "geometric", name: "Geometric" },
  { id: "dark", name: "Dark Mode" },
  { id: "artistic", name: "Artistic" }
];

const generateWallpapers = () => {
  const list = [
    { id: "default", name: "Default Doodle", type: "css" as const, value: "", category: "doodle" },
    { id: "light-doodle", name: "Light Doodle", type: "image" as const, value: "/chat-backgrounds/wa-light-doodle.svg", category: "doodle" },
    { id: "dark-doodle", name: "Dark Doodle", type: "image" as const, value: "/chat-backgrounds/wa-dark-doodle-ai.png", category: "doodle" },
    { id: "doodle-black", name: "Black Doodle", type: "image" as const, value: "/chat-backgrounds/wa-custom-doodle-black.png", category: "doodle" },
    { id: "doodle-blue", name: "Blue Doodle", type: "image" as const, value: "/chat-backgrounds/wa-custom-doodle-blue.png", category: "doodle" },
    { id: "doodle-neon", name: "Neon Doodle", type: "image" as const, value: "/chat-backgrounds/wa-custom-doodle-neon.png", category: "doodle" },
    { id: "doodle-green", name: "Green Doodle", type: "image" as const, value: "/chat-backgrounds/wa-custom-doodle-green.jpg", category: "doodle" },
    { id: "doodle-purple", name: "Purple Doodle", type: "image" as const, value: "/chat-backgrounds/wa-custom-doodle-purple.jpg", category: "doodle" },
  ];

  // Gradients (25 variants)
  const gradientColors = [
    ["#ff9a9e", "#fecfef"], ["#a1c4fd", "#c2e9fb"], ["#130cb7", "#52e5e7"], ["#30cfd0", "#330867"],
    ["#16a085", "#f4d03f"], ["#e74c3c", "#9b59b6"], ["#34495e", "#2c3e50"], ["#2980b9", "#2c3e50"],
    ["#1e3c72", "#2a5298"], ["#00c6ff", "#0072ff"], ["#7028e4", "#e20b8c"], ["#ff0844", "#ffb199"],
    ["#f12711", "#f5af19"], ["#0575e6", "#00f260"], ["#43c6ac", "#191654"], ["#833ab4", "#fd1d1d"],
    ["#3a7bd5", "#3a6073"], ["#000000", "#434343"], ["#11998e", "#38ef7d"], ["#3f2b96", "#a8c0ff"],
    ["#00dbde", "#fc00ff"], ["#1f4037", "#99f2c8"], ["#d53369", "#cbad6d"], ["#ff7e5f", "#feb47b"],
    ["#2c3e50", "#000000"]
  ];
  gradientColors.forEach((colors, i) => {
    list.push({
      id: `gradient-${i}`,
      name: `Gradient ${i + 1}`,
      type: "css" as const,
      value: `linear-gradient(135deg, ${colors[0]} 0%, ${colors[1]} 100%)`,
      category: "gradient"
    });
  });

  const idsMap: Record<string, string[]> = {
    nature: [
      "1507525428034-b723cf961d3e", "1470071459604-3b5ec3a7fe05", "1447752875215-b2761acb3c5d",
      "1472214222541-d510753a4907", "1469474968028-56623f02e42e", "1501854140801-50d01698950b",
      "1441974231531-c6227db76b6e", "1433086966358-54859d0ed716", "1506744038136-46273834b3fb",
      "1465146344425-f00d5f5c8f07", "1513836279014-a89f7a76ae86", "1475924156734-496f6cac6ec1",
      "1518173946687-a4c8a383392e", "1446776811953-b23d57bd21aa", "1486515394018-8097d627b054",
      "1500485035595-cbe6f645feb1", "1509042239860-f550ce710b93", "1532274402911-5a369e4c4bb5",
      "1434725039720-abb26e22ebe8", "1418065460487-3e41a6c84dc5", "1426604966848-d7adac402bff",
      "1534447677768-be436bb09401", "1510784722466-f2aa9c52faa6", "1482862549707-f63cb32c5fd9",
      "1470240731273-7821a6eeb6bd", "1421930866200-c1e1f8a410f1", "1486916856992-e4db22c8df33",
      "1473448912268-2022ce9509d8", "1464822759023-fed622ff2c3b", "1502082553048-f009c37129b9",
      "1511497584788-876760111969", "1470813740244-df37b8c1edcb", "1504198453319-5ce911bafcde",
      "1497436072909-60f360e1d4b1", "1504198266287-1659872e6590", "1502481851512-e9e2529beff9",
      "1490730141103-6cac27aaab94", "1519681393784-d120267933ba", "1538964173428-2d09137be857",
      "1546182990-d4afbe10a68d", "1511884642898-ac39277f84fa", "1523712999610-f97f502d4890",
      "1516026672322-bc02d64a7c21", "1508739773434-c26b3d09e071", "1501785888041-af3ef285b470",
      "1500530855612-4a0b407bb79e", "1505118380757-91f5f5632de0", "1520201164808-f2b4b25904ac",
      "1503614472447-f62f1275322b"
    ],
    abstract: [
      "1541701494587-cb58502866ab", "1618005182384-a83a8bd57fbe", "1508898578281-774ac4893c0c",
      "1557672172-298e090bd0f1", "1604871000636-074fa5117945", "1618005198140-e3a77ad597b9",
      "1607604276583-eef5d076aa5f", "1574169207511-94412959cc3e", "1579783900882-c0d3dad7b119",
      "1618005182243-7f7f90c37f43", "1618005150383-a4e797a78377", "1567095761369-048e7523d820",
      "1608501078906-c8e4f501f7ec", "1617791160536-598ffb415a7b", "1550684841-db53b27b14d8",
      "1605721911514-ee92ff48855f", "1580136579312-e2d7e30f4007", "1578301978697-f07092b64ab3",
      "1589330694653-ffdf95034c5b", "1589271303984-7a32933fd430", "1597500508605-7f154ff452bb",
      "1614850523456-11f8e5f2cf2f", "1608228085671-dc535a60e045"
    ],
    minimal: [
      "1507525428034-b723cf961d3e", "1494253109121-17748443907e", "1518531933037-a8b1d3d24af5",
      "1475640355171-460d3d57f2e1", "1515256448408-01d51a61a6b0", "1489058535096-73f13f1ee60a",
      "1528459801416-a9e53bbf4e17", "1531315630201-d71b4b60974b", "1513542789038-f9b4ac666ff2",
      "1538370965046-dec292478436", "1488190211420-11a910be253a", "1495908389139-64157b4b39b7",
      "1522048540838-89c0a6b7d23d", "1533035353-8385e50529e8", "1543322139-40b3b9b47e2a",
      "1468165026-64673b063548"
    ],
    texture: [
      "1518640467496-0f81d114002e", "1533035353-8385e50529e8", "1528459801416-a9e53bbf4e17",
      "1522048540838-89c0a6b7d23d", "1518156677181-124b6f123456", "1543322139-40b3b9b47e2a",
      "1468165026-64673b063548", "1531315630201-d71b4b60974b", "1488190211420-11a910be253a"
    ],
    geometric: [
      "1614850523456-11f8e5f2cf2f", "1608228085671-dc535a60e045", "1618005182243-7f7f90c37f43",
      "1618005150383-a4e797a78377", "1604871000636-074fa5117945", "1567095761369-048e7523d820",
      "1608501078906-c8e4f501f7ec", "1617791160536-598ffb415a7b"
    ],
    dark: [
      "1507525428034-b723cf961d3e", "1489058535096-73f13f1ee60a", "1528459801416-a9e53bbf4e17",
      "1533035353-8385e50529e8", "1543322139-40b3b9b47e2a", "1468165026-64673b063548",
      "1501854140801-50d01698950b", "1531315630201-d71b4b60974b"
    ],
    artistic: [
      "1579783900882-c0d3dad7b119", "1550684841-db53b27b14d8", "1605721911514-ee92ff48855f",
      "1580136579312-e2d7e30f4007", "1578301978697-f07092b64ab3", "1589330694653-ffdf95034c5b"
    ]
  };

  const addCategoryImages = (cat: string, name: string, count: number) => {
    const ids = idsMap[cat] || [];
    for (let i = 0; i < count; i++) {
      const id = ids[i % ids.length];
      list.push({
        id: `${cat}-${i}`,
        name: `${name} ${i + 1}`,
        type: "image" as const,
        value: `https://images.unsplash.com/photo-${id}?w=600&auto=format&fit=crop&q=80`,
        category: cat
      });
    }
  };

  addCategoryImages("nature", "Nature", 52);
  addCategoryImages("abstract", "Abstract", 30);
  addCategoryImages("minimal", "Minimal", 20);
  addCategoryImages("texture", "Texture", 15);
  addCategoryImages("geometric", "Geometric", 15);
  addCategoryImages("dark", "Dark Mode", 20);
  addCategoryImages("artistic", "Artistic", 20);

  return list;
};

const CHAT_WALLPAPERS = generateWallpapers();




// Utility: detect if a string is only emojis
function isOnlyEmojis(str: string): boolean {
  const emojiRegex =
    /^[\p{Emoji_Presentation}\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{1F9B0}-\u{1F9B3}\uFE0F\u200D\s]+$/u;
  return emojiRegex.test(str.trim()) && str.trim().length > 0 && str.trim().length <= 16;
}

function getEmojiAnimationClass(str: string) {
  if (/❤️|💖|💗|💓|🔥|🥰/.test(str)) return "animate-emoji-pulse";
  if (/✨|⭐|🌟|💫/.test(str)) return "animate-emoji-spin";
  return "animate-emoji-bounce";
}

function CallLogMessage({ msg, isMe }: { msg: Message; isMe: boolean }) {
  const callType = msg.mediaUrl === "video" ? "Video" : "Voice";
  const logStatus = msg.content; // "missed", "declined", "connected:duration"
  
  const isMissed = logStatus === "missed" || logStatus === "declined";
  const isConnected = logStatus.startsWith("connected:");
  
  let durationStr = "";
  if (isConnected) {
    const durationSeconds = parseInt(logStatus.split(":")[1] || "0", 10);
    const mins = Math.floor(durationSeconds / 60);
    const secs = durationSeconds % 60;
    durationStr = ` (${mins}:${secs.toString().padStart(2, "0")})`;
  }

  let label = "";
  const Icon = msg.mediaUrl === "video" ? Video : Phone;

  if (isMe) {
    if (isConnected) {
      label = `Outgoing ${callType} Call${durationStr}`;
    } else if (logStatus === "declined") {
      label = `Declined ${callType} Call`;
    } else {
      label = `Cancelled ${callType} Call`;
    }
  } else {
    if (isConnected) {
      label = `Incoming ${callType} Call${durationStr}`;
    } else {
      label = `Missed ${callType} Call`;
    }
  }

  return (
    <div
      className={`flex items-center gap-3 rounded-2xl border px-3.5 py-2.5 shadow-md select-none min-w-[220px] transition-all hover:brightness-110 ${
        isMe 
          ? "bg-[var(--theme-bubble-sent)] text-[var(--theme-bubble-sent-text)] border-transparent" 
          : "bg-[var(--theme-bubble-received)] text-[var(--theme-bubble-received-text)] border-[var(--theme-border-color)]"
      }`}
    >
      <div
        className={`h-9 w-9 rounded-full flex items-center justify-center shrink-0 ${
          isMissed
            ? "bg-red-500/20 text-red-500"
            : "bg-emerald-500/20 text-emerald-500"
        }`}
      >
        <Icon className="h-4.5 w-4.5" />
      </div>
      <div className="flex-1 flex flex-col text-left">
        <span className="text-xs font-semibold">{label}</span>
        <span className="text-[9px] opacity-80 mt-0.5">
          {isConnected ? "Connected" : isMissed ? (logStatus === "declined" ? "Declined" : "No Answer") : "Calling"}
        </span>
      </div>
    </div>
  );
}

function AudioMessage({ msg, isMe, theme }: { msg: Message; isMe: boolean; theme: string }) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateProgress = () => {
      setProgress((audio.currentTime / audio.duration) * 100 || 0);
      setCurrentTime(audio.currentTime);
    };

    const handleLoadedMetadata = () => setDuration(audio.duration);
    const handleEnded = () => {
      setIsPlaying(false);
      setProgress(0);
      setCurrentTime(0);
    };

    audio.addEventListener("timeupdate", updateProgress);
    audio.addEventListener("loadedmetadata", handleLoadedMetadata);
    audio.addEventListener("ended", handleEnded);

    return () => {
      audio.removeEventListener("timeupdate", updateProgress);
      audio.removeEventListener("loadedmetadata", handleLoadedMetadata);
      audio.removeEventListener("ended", handleEnded);
    };
  }, []);

  const togglePlay = () => {
    if (audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause();
      } else {
        audioRef.current.play();
      }
      setIsPlaying(!isPlaying);
    }
  };

  const formatTime = (time: number) => {
    if (isNaN(time)) return "0:00";
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  return (
    <div
      className={`flex items-center gap-3 rounded-2xl border px-3 py-2.5 shadow-md cursor-pointer hover:opacity-90 transition-opacity min-w-[200px] ${
        isMe
          ? "bg-[var(--theme-bubble-sent)] text-[var(--theme-bubble-sent-text)] border-transparent"
          : "bg-[var(--theme-bubble-received)] text-[var(--theme-bubble-received-text)] border-[var(--theme-border-color)]"
      }`}
      onClick={togglePlay}
    >
      <div className={`h-10 w-10 rounded-full flex items-center justify-center shrink-0 ${isMe ? "bg-[var(--theme-bubble-sent-text)]/20 text-[var(--theme-bubble-sent-text)]" : "bg-[var(--theme-bubble-received-text)]/20 text-[var(--theme-bubble-received-text)]"}`}>
        {isPlaying ? (
          <Square className="h-4 w-4" fill="currentColor" />
        ) : (
          <Play className="h-5 w-5 translate-x-[1px]" fill="currentColor" />
        )}
      </div>
      <div className="flex-1 flex flex-col gap-1">
        <div className={`h-1 w-full rounded-full overflow-hidden ${isMe ? "bg-[var(--theme-bubble-sent-text)]/20" : "bg-[var(--theme-bubble-received-text)]/20"}`}>
          <div 
            className={`h-full rounded-full transition-all duration-100 ease-linear ${isMe ? "bg-[var(--theme-bubble-sent-text)]" : "bg-[var(--theme-bubble-received-text)]"}`} 
            style={{ width: `${progress}%` }} 
          />
        </div>
        <div className={`flex justify-between items-center text-[10px] font-semibold opacity-80 ${isMe ? "text-[var(--theme-bubble-sent-text)]" : "text-[var(--theme-bubble-received-text)]"}`}>
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>
      <audio ref={audioRef} src={resolveMediaUrl(msg.mediaUrl) || ""} className="hidden" preload="metadata" />
    </div>
  );
}

export default function ChatWindow({
  chat,
  socket,
  onlineUsers,
  onBack,
  onToggleProductivity,
  isProductivityOpen,
  onChatDeleted,
  onStartCall,
}: ChatWindowProps) {
  const { user, token } = useAuth();
  const { theme } = useTheme();
  const { toast } = useToast();

  // Blocked and Block list states
  const [blockedIds, setBlockedIds] = useState<string[]>([]);

  // Camera preview states
  const [showCameraPreview, setShowCameraPreview] = useState(false);
  const [capturedBlob, setCapturedBlob] = useState<Blob | null>(null);
  const [capturedPreviewUrl, setCapturedPreviewUrl] = useState("");

  // Clear Chat status
  const [isClearingChat, setIsClearingChat] = useState(false);

  // Custom confirm modals (replaces native browser confirm())
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [showDeleteChatConfirm, setShowDeleteChatConfirm] = useState(false);

  // ── Audio notification ────────────────────────────────────────────────────
  // AudioContext must be created AND resumed inside a user-gesture handler.
  // We pre-unlock it on the very first click/keydown so it is already in
  // "running" state when a socket message arrives later.
  const audioCtxRef = useRef<AudioContext | null>(null);

  // Unlock AudioContext on first user interaction
  useEffect(() => {
    const unlock = () => {
      try {
        const AudioCtxClass = window.AudioContext || (window as any).webkitAudioContext;
        if (!AudioCtxClass) return;
        if (!audioCtxRef.current || audioCtxRef.current.state === "closed") {
          audioCtxRef.current = new AudioCtxClass();
        }
        if (audioCtxRef.current.state === "suspended") {
          audioCtxRef.current.resume();
        }
      } catch (_) {}
      // Remove listeners after first unlock
      document.removeEventListener("click", unlock);
      document.removeEventListener("keydown", unlock);
    };
    document.addEventListener("click", unlock);
    document.addEventListener("keydown", unlock);
    return () => {
      document.removeEventListener("click", unlock);
      document.removeEventListener("keydown", unlock);
    };
  }, []);

  const playNotificationSound = () => {
    SoundEngine.playNotification();
  };


  const [messages, setMessages] = useState<Message[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [isRecipientTyping, setIsRecipientTyping] = useState(false);
  const [typingUsername, setTypingUsername] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // File Upload State
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isUploadingFile, setIsUploadingFile] = useState(false);

  // Emoji Picker State
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);
  const emojiPickerRef = useRef<HTMLDivElement>(null);

  // Message Actions state
  const [replyingToMessage, setReplyingToMessage] = useState<Message | null>(null);
  const [editingMessage, setEditingMessage] = useState<Message | null>(null);
  const [hoveredMessageId, setHoveredMessageId] = useState<string | null>(null);
  const [deleteConfirmMessage, setDeleteConfirmMessage] = useState<Message | null>(null);
  const [localDeletedMsgIds, setLocalDeletedMsgIds] = useState<string[]>([]);
  const visibleMessages = messages.filter(m => !localDeletedMsgIds.includes(m.id));

  // Star & Forward States
  const [starredMessageIds, setStarredMessageIds] = useState<Set<string>>(new Set());
  const [forwardingMessage, setForwardingMessage] = useState<Message | null>(null);
  const [availableChatsForForwarding, setAvailableChatsForForwarding] = useState<any[]>([]);
  const [showForwardModal, setShowForwardModal] = useState(false);

  useEffect(() => {
    if (typeof window !== "undefined") {
      setLocalDeletedMsgIds(JSON.parse(localStorage.getItem("dolsyx_deleted_msgs") || "[]"));
      setStarredMessageIds(new Set(JSON.parse(localStorage.getItem("dolsyx_starred_messages") || "[]")));
    }
  }, []);

  const toggleStarMessage = (msgId: string) => {
    if (!chat) return;
    const newStarred = new Set(starredMessageIds);
    const list = JSON.parse(localStorage.getItem("dolsyx_starred_messages_list") || "[]");
    if (newStarred.has(msgId)) {
      newStarred.delete(msgId);
      const index = list.findIndex((item: any) => item.id === msgId);
      if (index > -1) list.splice(index, 1);
      toast("Message unstarred.", "success");
    } else {
      newStarred.add(msgId);
      const msgObj = messages.find(m => m.id === msgId);
      if (msgObj && !list.some((item: any) => item.id === msgId)) {
        list.push({
          id: msgObj.id,
          content: msgObj.content,
          createdAt: msgObj.createdAt,
          mediaUrl: msgObj.mediaUrl,
          mediaType: msgObj.mediaType,
          sender: msgObj.sender,
          chatId: chat.id
        });
      }
      toast("Message starred.", "success");
    }
    setStarredMessageIds(newStarred);
    localStorage.setItem("dolsyx_starred_messages", JSON.stringify(Array.from(newStarred)));
    localStorage.setItem("dolsyx_starred_messages_list", JSON.stringify(list));
  };

  const openForwardModal = async (msg: Message) => {
    setForwardingMessage(msg);
    setShowForwardModal(true);
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/conversations`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      if (res.ok) {
        const data = await res.json();
        setAvailableChatsForForwarding(data);
      }
    } catch (e) {
      console.error("Failed to load conversations for forward", e);
    }
  };

  const handleForwardMessage = async (chatId: string) => {
    if (!forwardingMessage || !token || !socket) return;
    try {
      socket.emit("send_message", {
        conversationId: chatId,
        content: forwardingMessage.content,
        mediaUrl: forwardingMessage.mediaUrl,
        mediaType: forwardingMessage.mediaType,
        parentMessageId: null
      });
      toast("Message forwarded.", "success");
      setShowForwardModal(false);
      setForwardingMessage(null);
    } catch (e) {
      console.error("Forward error:", e);
      toast("Failed to forward message.", "error");
    }
  };

  // Message Selection State
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [selectedMessageIds, setSelectedMessageIds] = useState<Set<string>>(new Set());

  // Header options dropdown & deletion
  const [showHeaderMenu, setShowHeaderMenu] = useState(false);
  const [isDeletingChat, setIsDeletingChat] = useState(false);
  const headerMenuRef = useRef<HTMLDivElement>(null);

  // Profile View Modal
  const [profileUser, setProfileUser] = useState<any | null>(null);

  // Camera Capture State
  const [showCamera, setShowCamera] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const [cameraFacingMode, setCameraFacingMode] = useState<"user" | "environment">("user");

  // Voice Recording State
  const [isRecording, setIsRecording] = useState(false);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const recordingTimerRef = useRef<NodeJS.Timeout | null>(null);

  // Wallpaper Background Picker
  const [showWallpaperPicker, setShowWallpaperPicker] = useState(false);
  const [selectedWallpaper, setSelectedWallpaper] = useState("default");
  const [customWallpapers, setCustomWallpapers] = useState<{ id: string; name: string; type: "image"; value: string }[]>([]);
  const [activeWallpaperCat, setActiveWallpaperCat] = useState("doodle");

  useEffect(() => {
    if (typeof window !== "undefined") {
      try {
        const storedWp = localStorage.getItem("dolsyx_chat_wallpaper");
        if (storedWp) {
          setSelectedWallpaper(storedWp);
        }
        const stored = localStorage.getItem("dolsyx_custom_wallpapers");
        if (stored) {
          setCustomWallpapers(JSON.parse(stored));
        }
      } catch (e) {
        console.error(e);
      }
    }
  }, []);

  // Camera stream attachment effect to fix the camera render race condition
  useEffect(() => {
    if (showCamera && cameraStreamRef.current && videoRef.current) {
      videoRef.current.srcObject = cameraStreamRef.current;
    }
  }, [showCamera]);

  const wallpaperUploadRef = useRef<HTMLInputElement>(null);

  const handleWallpaperUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      const dataUrl = ev.target?.result as string;
      const id = `custom-${Date.now()}`;
      const name = file.name.replace(/\.[^/.]+$/, "") || "My Wallpaper";
      const newWp = { id, name, type: "image" as const, value: dataUrl };
      setCustomWallpapers((prev) => {
        const updated = [...prev, newWp];
        if (typeof window !== "undefined") {
          localStorage.setItem("dolsyx_custom_wallpapers", JSON.stringify(updated));
        }
        return updated;
      });
      setSelectedWallpaper(id);
      if (typeof window !== "undefined") {
        localStorage.setItem("dolsyx_chat_wallpaper", id);
      }
    };
    reader.readAsDataURL(file);
    if (wallpaperUploadRef.current) wallpaperUploadRef.current.value = "";
  };

  const handleDeleteCustomWallpaper = (id: string) => {
    setCustomWallpapers((prev) => {
      const updated = prev.filter((w) => w.id !== id);
      if (typeof window !== "undefined") {
        localStorage.setItem("dolsyx_custom_wallpapers", JSON.stringify(updated));
      }
      return updated;
    });
    if (selectedWallpaper === id) {
      setSelectedWallpaper("default");
      if (typeof window !== "undefined") {
        localStorage.setItem("dolsyx_chat_wallpaper", "default");
      }
    }
  };

  // Fetch message history on chat select
  useEffect(() => {
    if (!chat || !token) return;

    const fetchMessages = async () => {
      try {
        const res = await fetch(`${API_URL}/api/chats/${chat.id}/messages`, {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });

        if (res.ok) {
          const data = await res.json();
          setMessages(data);
          if (socket) {
            socket.emit("mark_read", { conversationId: chat.id });
          }
        }
      } catch (err) {
        console.error("Error loading message history:", err);
      }
    };

    const fetchBlocks = async () => {
      try {
        const res = await fetch(`${API_URL}/api/auth/blocks`, {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });
        if (res.ok) {
          const data = await res.json();
          setBlockedIds(data.blockedIds || []);
        }
      } catch (e) {
        console.error(e);
      }
    };

    fetchMessages();
    fetchBlocks();
    setIsRecipientTyping(false);
    setReplyingToMessage(null);
    setEditingMessage(null);
    setInputValue("");
    setShowEmojiPicker(false);
    setDeleteConfirmMessage(null);
    setProfileUser(null);

    // Join conversation socket channel
    if (socket) {
      socket.emit("join_conversation", chat.id);
    }

    return () => {
      // Leave conversation socket channel on unmount
      if (socket && chat) {
        socket.emit("leave_conversation", chat.id);
      }
    };
  }, [chat, token, socket]);

  // Scroll to bottom helper
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isRecipientTyping]);

  // Close emoji picker when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (emojiPickerRef.current && !emojiPickerRef.current.contains(e.target as Node)) {
        setShowEmojiPicker(false);
      }
    };
    if (showEmojiPicker) {
      document.addEventListener("mousedown", handleClickOutside);
    }
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [showEmojiPicker]);

  // Close header options menu when clicking outside
  useEffect(() => {
    const handleHeaderClickOutside = (e: MouseEvent) => {
      if (headerMenuRef.current && !headerMenuRef.current.contains(e.target as Node)) {
        setShowHeaderMenu(false);
      }
    };
    if (showHeaderMenu) {
      document.addEventListener("mousedown", handleHeaderClickOutside);
    }
    return () => document.removeEventListener("mousedown", handleHeaderClickOutside);
  }, [showHeaderMenu]);

  const handleDeleteChat = async () => {
    if (!chat || !token) return;
    setIsDeletingChat(true);
    try {
      const res = await fetch(`${API_URL}/api/chats/${chat.id}`, {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (res.ok) {
        setShowHeaderMenu(false);
        if (onChatDeleted) {
          onChatDeleted(chat.id);
        }
        onBack();
      } else {
        toast("Failed to delete overall chat", "error");
      }
    } catch (err) {
      console.error(err);
      toast("Error deleting conversation", "error");
    } finally {
      setIsDeletingChat(false);
      setShowDeleteChatConfirm(false);
    }
  };
  const handleClearChat = async () => {
    if (!chat || !token) return;
    setIsClearingChat(true);
    try {
      const res = await fetch(`${API_URL}/api/chats/${chat.id}/messages`, {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (res.ok) {
        setShowHeaderMenu(false);
        setMessages([]);
        toast("Chat messages cleared", "success");
      } else {
        toast("Failed to clear chat messages", "error");
      }
    } catch (err) {
      console.error(err);
      toast("Error clearing messages", "error");
    } finally {
      setIsClearingChat(false);
      setShowClearConfirm(false);
    }
  };
  // Listen to live message and typing events
  useEffect(() => {
    if (!socket || !chat) return;

    const handleNewMessage = (data: { message: Message; conversationId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) => {
          if (prev.some(m => m.id === data.message.id)) return prev;
          
          if (data.message.senderId === user?.id) {
            const tempIndex = prev.findIndex(m => 
              m.id.startsWith("temp-") && 
              m.content === data.message.content && 
              m.mediaUrl === data.message.mediaUrl
            );
            if (tempIndex !== -1) {
              const newMessages = [...prev];
              newMessages[tempIndex] = data.message;
              return newMessages;
            }
          }
          return [...prev, data.message];
        });
        setIsRecipientTyping(false);
        socket.emit("mark_read", { conversationId: chat.id });
        // Play notification sound only for incoming messages (not our own)
        if (data.message.senderId !== user?.id) {
          playNotificationSound();
        }
      }
    };

    const handleMessagesRead = (data: { conversationId: string; userId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) =>
          prev.map((msg) => {
            if (msg.senderId === user?.id && data.userId !== user?.id) {
              const updatedReceipts = msg.receipts
                ? msg.receipts.map((r: any) =>
                    r.userId === data.userId ? { ...r, status: "READ" } : r
                  )
                : [{ userId: data.userId, status: "READ" }];

              const hasReadReceipt = updatedReceipts.some(
                (r: any) => r.userId === data.userId && r.status === "READ"
              );
              if (!hasReadReceipt) {
                updatedReceipts.push({ userId: data.userId, status: "READ" });
              }

              return { ...msg, receipts: updatedReceipts };
            }
            return msg;
          })
        );
      }
    };

    const handleUserTyping = (data: {
      conversationId: string;
      userId: string;
      username: string;
      isTyping: boolean;
    }) => {
      if (data.conversationId === chat.id && data.userId !== user?.id) {
        setTypingUsername(data.username);
        setIsRecipientTyping(data.isTyping);
      }
    };

    const handleMessageEdited = (data: { message: Message; conversationId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) =>
          prev.map((msg) => (msg.id === data.message.id ? data.message : msg))
        );
      }
    };

    const handleMessageDeleted = (data: { messageId: string; conversationId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) => prev.filter((msg) => msg.id !== data.messageId));
      }
    };

    const handleMessageDeletedForMe = (data: { messageId: string; conversationId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) => prev.filter((msg) => msg.id !== data.messageId));
      }
    };

    const handleChatCleared = (data: { conversationId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages([]);
      }
    };

    socket.on("new_message", handleNewMessage);
    socket.on("messages_read", handleMessagesRead);
    socket.on("user_typing", handleUserTyping);
    socket.on("message_edited", handleMessageEdited);
    socket.on("message_deleted", handleMessageDeleted);
    socket.on("message_deleted_for_me", handleMessageDeletedForMe);
    socket.on("chat_cleared", handleChatCleared);

    return () => {
      socket.off("new_message", handleNewMessage);
      socket.off("messages_read", handleMessagesRead);
      socket.off("user_typing", handleUserTyping);
      socket.off("message_edited", handleMessageEdited);
      socket.off("message_deleted", handleMessageDeleted);
      socket.off("message_deleted_for_me", handleMessageDeletedForMe);
      socket.off("chat_cleared", handleChatCleared);
    };
  }, [socket, chat, user]);

  const toggleMessageSelection = (messageId: string) => {
    setSelectedMessageIds((prev) => {
      const next = new Set(prev);
      if (next.has(messageId)) {
        next.delete(messageId);
      } else {
        next.add(messageId);
      }
      return next;
    });
  };

  const handleDeleteSelected = async () => {
    if (!socket || !chat || selectedMessageIds.size === 0) return;
    
    // We will delete for me for all selected messages
    for (const msgId of selectedMessageIds) {
      socket.emit("delete_message", {
        messageId: msgId,
        deleteType: "me",
      });
    }

    setIsSelectionMode(false);
    setSelectedMessageIds(new Set());
    toast("Selected messages deleted.", "success");
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.target.value);

    if (!socket || !chat) return;

    // Emit typing status
    socket.emit("typing", { conversationId: chat.id, isTyping: true });

    // Debounce to emit isTyping: false
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    typingTimeoutRef.current = setTimeout(() => {
      socket.emit("typing", { conversationId: chat.id, isTyping: false });
    }, 1500);
  };

  const handleSendMessage = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputValue.trim() || !socket || !chat) return;

    if (editingMessage) {
      // Send Edit event
      socket.emit("edit_message", {
        messageId: editingMessage.id,
        content: inputValue.trim(),
      });
      setEditingMessage(null);
    } else {
      const newMsgContent = inputValue.trim();
      const tempId = `temp-${Date.now()}`;
      
      const optimisticMsg: any = {
        id: tempId,
        content: newMsgContent,
        senderId: user?.id || "",
        conversationId: chat.id,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        parentMessageId: replyingToMessage?.id || null,
        parentMessage: replyingToMessage || null,
        mediaUrl: null,
        mediaType: "TEXT",
        sender: user ? {
          id: user.id,
          username: user.username,
          avatarUrl: user.avatarUrl
        } : null,
        receipts: []
      };
      
      setMessages(prev => [...prev, optimisticMsg]);

      // Send regular message or reply
      socket.emit("send_message", {
        conversationId: chat.id,
        content: newMsgContent,
        parentMessageId: replyingToMessage?.id || undefined,
      });
      setReplyingToMessage(null);
    }

    // Clear typing timeout and emit stopped typing
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }
    socket.emit("typing", { conversationId: chat.id, isTyping: false });

    setInputValue("");
  };

  const handleEditClick = (msg: Message) => {
    setEditingMessage(msg);
    setReplyingToMessage(null);
    setInputValue(msg.content);
  };

  const handleDeleteClick = (msg: Message) => {
    setDeleteConfirmMessage(msg);
  };

  const deleteMessageForMe = () => {
    if (!deleteConfirmMessage) return;
    const deletedList = JSON.parse(localStorage.getItem("dolsyx_deleted_msgs") || "[]");
    deletedList.push(deleteConfirmMessage.id);
    localStorage.setItem("dolsyx_deleted_msgs", JSON.stringify(deletedList));
    setLocalDeletedMsgIds(prev => [...prev, deleteConfirmMessage.id]);
    setDeleteConfirmMessage(null);
    toast("Message deleted locally.", "success");
  };

  const deleteMessageForEveryone = () => {
    if (!deleteConfirmMessage || !socket) return;
    socket.emit("delete_message", {
      messageId: deleteConfirmMessage.id,
      deleteType: "everyone"
    });
    setDeleteConfirmMessage(null);
    toast("Message deleted for everyone.", "success");
  };

  const handleToggleBlock = async (targetUserId: string) => {
    if (!token) return;
    const isBlocked = blockedIds.includes(targetUserId);
    const method = isBlocked ? "DELETE" : "POST";
    try {
      const res = await fetch(`${API_URL}/api/auth/block/${targetUserId}`, {
        method,
        headers: {
          Authorization: `Bearer ${token}`
        }
      });
      if (res.ok) {
        if (isBlocked) {
          setBlockedIds(prev => prev.filter(id => id !== targetUserId));
          toast("User unblocked", "success");
        } else {
          setBlockedIds(prev => [...prev, targetUserId]);
          toast("User blocked", "success");
        }
      } else {
        toast("Failed to update block status", "error");
      }
    } catch (e) {
      console.error(e);
      toast("Error blocking/unblocking user", "error");
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (!selectedFile || !socket || !chat || !token) return;

    setIsUploadingFile(true);

    const formData = new FormData();
    formData.append("file", selectedFile);

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
        let mediaType: "IMAGE" | "VIDEO" | "FILE" | "AUDIO" = "FILE";
        if (data.fileType.startsWith("image/")) mediaType = "IMAGE";
        else if (data.fileType.startsWith("video/")) mediaType = "VIDEO";
        else if (data.fileType.startsWith("audio/")) mediaType = "AUDIO";

        const tempId = `temp-${Date.now()}`;
        const optimisticMsg: any = {
          id: tempId,
          content: "",
          senderId: user?.id || "",
          conversationId: chat.id,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          parentMessageId: null,
          parentMessage: null,
          mediaUrl: data.fileUrl,
          mediaType: mediaType,
          sender: user ? {
            id: user.id,
            username: user.username,
            avatarUrl: user.avatarUrl
          } : null,
          receipts: []
        };
        
        setMessages(prev => [...prev, optimisticMsg]);

        // Store relative path instead of absolute URL
        socket.emit("send_message", {
          conversationId: chat.id,
          content: "",
          mediaUrl: data.fileUrl,
          mediaType,
        });
      } else {
        toast("File upload failed. Please try again.", "error");
      }
    } catch (err) {
      console.error("Upload error:", err);
      toast("Error uploading file.", "error");
    } finally {
      setIsUploadingFile(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const uploadMediaData = async (blob: Blob, fileType: "IMAGE" | "AUDIO") => {
    if (!socket || !chat || !token) return;
    const formData = new FormData();
    const ext = fileType === "IMAGE" ? "png" : "webm";
    const filename = `capture_${Date.now()}.${ext}`;
    formData.append("file", blob, filename);

    try {
      const res = await fetch(`${API_URL}/api/chats/upload`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });

      if (res.ok) {
        const data = await res.json();
        // Store relative path instead of absolute URL
        socket.emit("send_message", {
          conversationId: chat.id,
          content: "",
          mediaUrl: data.fileUrl,
          mediaType: fileType,
        });
      } else {
        toast(`${fileType} upload failed.`, "error");
      }
    } catch (err) {
      console.error(`${fileType} upload error:`, err);
      toast(`Error uploading ${fileType.toLowerCase()}.`, "error");
    }
  };

  // Camera Handlers
  const startCamera = async (mode: "user" | "environment" = cameraFacingMode) => {
    try {
      if (cameraStreamRef.current) {
        cameraStreamRef.current.getTracks().forEach(track => track.stop());
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: mode, width: { ideal: 1280 }, height: { ideal: 720 } }
      });
      cameraStreamRef.current = stream;
      setShowCamera(true);
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
      }
    } catch (err) {
      console.error("Camera access denied:", err);
      toast("Could not access camera. Please check permissions.", "error");
    }
  };

  const stopCamera = () => {
    if (cameraStreamRef.current) {
      cameraStreamRef.current.getTracks().forEach(track => track.stop());
      cameraStreamRef.current = null;
    }
    setShowCamera(false);
  };

  const toggleCaptureCamera = () => {
    const nextMode = cameraFacingMode === "user" ? "environment" : "user";
    setCameraFacingMode(nextMode);
    startCamera(nextMode);
  };

  const capturePhoto = () => {
    if (videoRef.current) {
      const video = videoRef.current;
      
      if (video.videoWidth === 0) {
        toast("Camera not ready. Please wait a second and try again.", "warning");
        return;
      }
      
      const canvas = document.createElement("canvas");
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext("2d");
      if (ctx) {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        canvas.toBlob((blob) => {
          if (blob) {
            setCapturedBlob(blob);
            setCapturedPreviewUrl(URL.createObjectURL(blob));
            setShowCameraPreview(true);
            stopCamera();
          } else {
            toast("Failed to capture image. Please try again.", "error");
          }
        }, "image/png");
      }
    }
  };

  // Voice Recording Handlers
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;
      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          audioChunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: "audio/webm" });
        uploadMediaData(audioBlob, "AUDIO");
        stream.getTracks().forEach(track => track.stop());
      };

      mediaRecorder.start();
      setIsRecording(true);
      setRecordingDuration(0);
      
      recordingTimerRef.current = setInterval(() => {
        setRecordingDuration((prev) => prev + 1);
      }, 1000);
    } catch (err) {
      console.error("Microphone access denied:", err);
      toast("Could not access microphone. Please check permissions.", "error");
    }
  };

  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
      if (recordingTimerRef.current) {
        clearInterval(recordingTimerRef.current);
      }
    }
  };

  const onEmojiClick = (emojiData: EmojiClickData) => {
    setInputValue((prev) => prev + emojiData.emoji);
  };

  const formatMessageTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  const formatLastSeen = (dateString: string) => {
    try {
      const date = new Date(dateString);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      const isToday = date.toDateString() === now.toDateString();
      const yesterday = new Date(now);
      yesterday.setDate(yesterday.getDate() - 1);
      const isYesterday = date.toDateString() === yesterday.toDateString();

      const timeStr = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      if (isToday) return `today at ${timeStr}`;
      if (isYesterday) return `yesterday at ${timeStr}`;

      return (
        date.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" }) +
        " at " +
        timeStr
      );
    } catch (e) {
      return "offline";
    }
  };

  if (!chat) {
    return (
      <div className="hidden flex-1 flex-col items-center justify-center bg-[var(--theme-bg-chat)] p-8 text-center sm:flex transition-all duration-300">
        <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-[var(--theme-bg-sidebar-search)] border border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] shadow-inner mb-6 animate-pulse">
          <Send className="h-8 w-8" />
        </div>
        <h3 className="text-xl font-bold text-[var(--theme-text-primary)] mb-2">
          {theme.startsWith("aqua") ? "DOLSYX Chat" : "DOLSYX Messenger"}
        </h3>
        <p className="text-[var(--theme-text-secondary)] max-w-sm text-sm">
          Select an active chat from the sidebar or search for users to start a new real-time
          conversation.
        </p>
      </div>
    );
  }

  const isOnline = chat.recipient ? onlineUsers.includes(chat.recipient.id) : false;

  return (
    <div className="flex h-full flex-col bg-[var(--theme-bg-app)] relative w-full overflow-hidden">
      {/* Wallpaper rendering logic */}
      {(() => {
        const wp = CHAT_WALLPAPERS.find(w => w.id === selectedWallpaper) || customWallpapers.find(w => w.id === selectedWallpaper);
        if (!wp || wp.id === "default") {
          return <div className="whatsapp-wallpaper z-0" />;
        }
        if (wp.type === "image") {
          return (
            <div 
              className="absolute inset-0 pointer-events-none opacity-50 z-0"
              style={{ 
                backgroundImage: `url(${wp.value})`, 
                backgroundSize: "cover",
                backgroundPosition: "center",
                backgroundAttachment: "fixed" 
              }} 
            />
          );
        }
        if (wp.type === "css") {
          return (
            <div 
              className="absolute inset-0 pointer-events-none opacity-40 z-0"
              style={{ background: wp.value }} 
            />
          );
        }
      })()}

      {/* Header */}
      <div className="flex h-[72px] shrink-0 items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)]/80 backdrop-blur-md px-4 sm:px-6 relative z-30">
        <div className="flex items-center gap-4 min-w-0">
          <button
            onClick={onBack}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] sm:hidden transition-all duration-200 cursor-pointer"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>

          {/* Clickable avatar + name → opens profile */}
          <button
            onClick={() => !chat.isGroup && setProfileUser(chat.recipient)}
            className={`flex items-center gap-3 min-w-0 text-left ${!chat.isGroup ? "cursor-pointer hover:opacity-80 transition-opacity" : "cursor-default"}`}
            title={chat.isGroup ? undefined : "View profile"}
          >
            <div className="relative shrink-0">
            <img
                src={getAvatarUrl(chat.avatarUrl, chat.name)}
                alt={chat.name}
                className="h-10 w-10 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)]"
              />
              {isOnline && (
                <span className="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-[var(--theme-bg-container)] bg-green-500 shadow-md animate-pulse" />
              )}
            </div>

            <div className="min-w-0">
              <h4 className="text-[18px] font-semibold truncate text-[var(--theme-text-primary)]">{chat.name}</h4>
              <p className="text-[13px] text-[var(--theme-text-secondary)] font-normal flex items-center gap-1">
                {isRecipientTyping ? (
                  <span className="text-[var(--theme-accent)] font-semibold animate-pulse text-[12px]">
                    {chat.isGroup ? `${typingUsername} is typing...` : "typing..."}
                  </span>
                ) : chat.isGroup ? (
                  <span>{chat.participants?.length || 2} members</span>
                ) : isOnline ? (
                  <span className="text-green-400 font-normal flex items-center gap-1">
                    Online
                  </span>
                ) : chat.recipient && chat.recipient.lastSeen ? (
                  <span>Last seen {formatLastSeen(chat.recipient.lastSeen)}</span>
                ) : (
                  <span>Offline</span>
                )}
              </p>
            </div>
          </button>
        </div>

        <div className="flex items-center gap-2">
          {/* Audio Call button - always visible for direct chats */}
          {chat && !chat.isGroup && onStartCall && (
            <>
              <button
                onClick={() => onStartCall("audio")}
                className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                title="Voice Call"
              >
                <Phone className="h-4 w-4" />
              </button>
              <button
                onClick={() => onStartCall("video")}
                className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                title="Video Call"
              >
                <Video className="h-4 w-4" />
              </button>
            </>
          )}
          
          {/* 3-dots menu — contains all other options */}
          <div className="relative" ref={headerMenuRef}>
            <button
              onClick={() => setShowHeaderMenu((v) => !v)}
              className={`flex h-9 w-9 items-center justify-center rounded-xl border transition-all cursor-pointer ${
                showHeaderMenu
                  ? "border-[var(--theme-accent)] bg-[var(--theme-accent)]/10 text-[var(--theme-accent)]"
                  : "border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
              }`}
              title="More Options"
            >
              <MoreVertical className="h-4 w-4" />
            </button>

            {showHeaderMenu && (
              <div className="absolute right-0 top-11 z-50 w-52 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] p-1.5 shadow-2xl animate-fade-in text-left">
                {!chat.isGroup && (
                  <button
                    onMouseDown={(e) => {
                      e.preventDefault();
                      setProfileUser(chat.recipient);
                      setShowHeaderMenu(false);
                    }}
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                  >
                    <User className="h-3.5 w-3.5" />
                    View Profile
                  </button>
                )}
                {/* Productivity toggle */}
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setShowHeaderMenu(false);
                    onToggleProductivity();
                  }}
                  className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold transition-colors cursor-pointer ${
                    isProductivityOpen
                      ? "text-[var(--theme-accent)] bg-[var(--theme-accent)]/10"
                      : "text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)]"
                  }`}
                >
                  <CheckSquare className="h-3.5 w-3.5" />
                  {isProductivityOpen ? "Close Workspace" : "Open Workspace"}
                </button>
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setIsSelectionMode(true);
                    setSelectedMessageIds(new Set());
                    setShowHeaderMenu(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                >
                  <CheckSquare className="h-3.5 w-3.5" />
                  Select Messages
                </button>
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setShowWallpaperPicker(true);
                    setShowHeaderMenu(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                >
                  <ImageIcon className="h-3.5 w-3.5" />
                  Chat Wallpaper
                </button>
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setShowHeaderMenu(false);
                    setShowClearConfirm(true);
                  }}
                  disabled={isClearingChat}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-amber-500 hover:bg-amber-500/10 hover:text-amber-400 transition-colors cursor-pointer disabled:opacity-50"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  {isClearingChat ? "Clearing..." : "Clear Chat"}
                </button>
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setShowHeaderMenu(false);
                    setShowDeleteChatConfirm(true);
                  }}
                  disabled={isDeletingChat}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors cursor-pointer disabled:opacity-50"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  {isDeletingChat ? "Deleting..." : "Delete Chat"}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Messages Scroll Area */}
      <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4 relative z-10">
        {visibleMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center text-center h-full py-12 px-4 space-y-3 relative z-10">
            <Smile className="h-8 w-8 text-[var(--theme-text-secondary)]/50 animate-bounce" />
            <p className="text-sm text-[var(--theme-text-primary)]">Say hello!</p>
            <p className="text-xs text-[var(--theme-text-secondary)]/60">
              Start the conversation by sending a message below.
            </p>
          </div>
        ) : (
          visibleMessages.map((msg, index) => {
            const isMe = msg.senderId === user?.id;
            const isMsgDeleted = !!msg.isDeleted;
            const isMsgEdited = !!msg.isEdited;
            const emojiOnly = !msg.mediaUrl && !isMsgDeleted && isOnlyEmojis(msg.content);

            const isSelected = selectedMessageIds.has(msg.id);

            // Date separator calculation
            const msgDate = new Date(msg.createdAt).toDateString();
            const prevMsg = index > 0 ? messages[index - 1] : null;
            const prevMsgDate = prevMsg ? new Date(prevMsg.createdAt).toDateString() : null;
            const showDateSeparator = msgDate !== prevMsgDate;

            const formatDateSeparator = (dateStr: string) => {
              const d = new Date(dateStr);
              const today = new Date().toDateString();
              const yesterday = new Date(Date.now() - 86400000).toDateString();
              if (d.toDateString() === today) return "Today";
              if (d.toDateString() === yesterday) return "Yesterday";
              return d.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric', year: 'numeric' });
            };

            // Dynamic margin spacing: 4px between same sender, 12px between different senders
            const nextMsg = messages[index + 1];
            const isDifferentSender = nextMsg ? nextMsg.senderId !== msg.senderId : true;
            const spacingClass = isDifferentSender ? "mb-3.5" : "mb-1";

            return (
              <React.Fragment key={msg.id}>
                {showDateSeparator && (
                  <div className="flex justify-center my-4 w-full select-none">
                    <span className="bg-[var(--theme-bg-sidebar-search)]/80 text-[12px] font-medium text-[var(--theme-text-secondary)] px-4 py-1.5 rounded-full border border-[var(--theme-border-color)]/20 shadow-xs uppercase tracking-wider text-center">
                      {formatDateSeparator(msg.createdAt)}
                    </span>
                  </div>
                )}

                <div
                  onMouseEnter={() => !isMsgDeleted && setHoveredMessageId(msg.id)}
                  onMouseLeave={() => setHoveredMessageId(null)}
                  onClick={() => isSelectionMode && toggleMessageSelection(msg.id)}
                  className={`group flex items-end gap-2 max-w-[78%] relative z-10 transition-all duration-200 ${spacingClass} ${
                    isSelectionMode ? "cursor-pointer hover:bg-white/5 p-1 rounded-xl" : ""
                  } ${
                    isMe ? "ml-auto flex-row-reverse" : "mr-auto"
                  }`}
                >
                  {isSelectionMode && (
                    <div className="shrink-0 flex items-center justify-center h-8 w-8">
                      <input
                        type="checkbox"
                        checked={isSelected}
                        readOnly
                        className="h-4.5 w-4.5 rounded-md border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-accent)] focus:ring-[var(--theme-accent)] transition-all cursor-pointer"
                      />
                    </div>
                  )}
                  {!isMe && (
                    <button
                      onClick={() => setProfileUser(msg.sender)}
                      className="shrink-0 rounded-full cursor-pointer hover:opacity-80 transition-opacity"
                      title={`View ${msg.sender.username}'s profile`}
                    >
                      <img
                        src={getAvatarUrl(msg.sender.avatarUrl, msg.sender.username)}
                        alt={msg.sender.username}
                        className="h-10 w-10 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] object-cover"
                      />
                    </button>
                  )}
                  <div className="flex flex-col relative">
                    {/* Group Chat Sender Username: 13sp (13px), Medium (500), Top-left */}
                    {chat.isGroup && !isMe && !isMsgDeleted && (
                      <span className="text-[13px] font-[500] text-[var(--theme-accent)] mb-0.5 text-left block pl-1 select-none">
                        {msg.sender.username}
                      </span>
                    )}

                    {/* Quoted parent message (replies) */}
                    {msg.parentMessage && !isMsgDeleted && (
                      <div className="rounded-lg bg-[var(--theme-bg-sidebar-search)]/80 border-l-2 border-[var(--theme-accent)] px-3 py-1.5 text-[11px] text-[var(--theme-text-secondary)] mb-1 select-none pointer-events-none max-w-sm truncate">
                        <span className="font-bold text-[var(--theme-accent)] text-[9px] block">
                          {msg.parentMessage.sender.username}
                        </span>
                        {msg.parentMessage.content}
                      </div>
                    )}

                    {/* Message bubble depending on mediaType */}
                    {isMsgDeleted ? (
                      <div
                        className={`rounded-2xl px-4 py-2 text-[16px] italic opacity-60 bg-zinc-900 border border-zinc-800 text-zinc-500 relative`}
                      >
                        <TwemojiText text="This message was deleted" />
                      </div>
                    ) : msg.mediaType === "STICKER" ? (
                      <div className="relative py-1 select-none">
                        <img
                          src={resolveMediaUrl(msg.mediaUrl) || ""}
                          alt="Sticker"
                          className="w-28 h-28 object-contain transition-transform duration-200 hover:scale-110"
                        />
                      </div>
                    ) : msg.mediaType === "CALL_LOG" ? (
                      <CallLogMessage msg={msg} isMe={isMe} />
                    ) : msg.mediaType === "IMAGE" ? (
                      <div className="flex flex-col space-y-1">
                        <div className="max-w-md rounded-2xl overflow-hidden border border-zinc-800 bg-zinc-900 shadow-md">
                          <img
                            src={resolveMediaUrl(msg.mediaUrl) || ""}
                            alt={msg.content || "Image attachment"}
                            className="w-full max-h-96 object-cover cursor-pointer hover:opacity-90 transition-opacity"
                            onClick={() => window.open(resolveMediaUrl(msg.mediaUrl) || "", "_blank")}
                          />
                        </div>
                        {msg.content && msg.content !== msg.id && (
                          <div
                            className={`rounded-2xl px-4 py-2 text-[16px] shadow-md ${
                              isMe
                                ? "rounded-br-none bg-gradient-to-tr from-violet-600 to-indigo-600 text-white"
                                : "rounded-bl-none bg-zinc-900 border border-zinc-800/80 text-zinc-100"
                            }`}
                          >
                            {msg.content}
                          </div>
                        )}
                      </div>
                    ) : msg.mediaType === "VIDEO" ? (
                      <div className="flex flex-col space-y-1">
                        <div className="max-w-xs rounded-2xl overflow-hidden border border-zinc-800 bg-black shadow-md">
                          <video
                            src={resolveMediaUrl(msg.mediaUrl) || ""}
                            controls
                            preload="metadata"
                            playsInline
                            className="w-full max-h-72 object-contain bg-black rounded-2xl"
                            style={{ display: "block" }}
                            onError={(e) => {
                              console.error("Video error:", e);
                            }}
                          >
                            <source src={resolveMediaUrl(msg.mediaUrl) || ""} />
                            Your browser does not support video playback.
                          </video>
                        </div>
                        {msg.content && msg.content !== msg.id && (
                          <div
                            className={`rounded-2xl px-4 py-2 text-[16px] shadow-md ${
                              isMe
                                ? "rounded-br-none bg-gradient-to-tr from-violet-600 to-indigo-600 text-white"
                                : "rounded-bl-none bg-zinc-900 border border-zinc-800/80 text-zinc-100"
                            }`}
                          >
                            {msg.content}
                          </div>
                        )}
                      </div>
                    ) : msg.mediaType === "AUDIO" ? (
                      <div className={`flex flex-col space-y-1 max-w-xs`}>
                        <AudioMessage msg={msg} isMe={isMe} theme={theme} />
                        {msg.content && msg.content !== msg.id && (
                          <div className={`text-[11px] ${isMe ? "text-right text-white/60" : "text-zinc-500"} truncate`}>
                            {msg.content}
                          </div>
                        )}
                      </div>
                    ) : msg.mediaType === "FILE" ? (
                      <div className="flex items-center gap-3 max-w-xs rounded-2xl border border-zinc-800 bg-zinc-900/60 p-3 shadow-md">
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-zinc-850 text-violet-400">
                          <FileIcon className="h-4.5 w-4.5" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="text-[14px] font-semibold text-white truncate">
                            {msg.content || "Attachment"}
                          </p>
                          <p className="text-[11px] text-zinc-550">File Attachment</p>
                        </div>
                        <a
                          href={resolveMediaUrl(msg.mediaUrl) || ""}
                          download={msg.content}
                          target="_blank"
                          rel="noreferrer"
                          className="flex h-8 w-8 items-center justify-center rounded-lg border border-zinc-800 text-zinc-400 hover:text-white hover:bg-zinc-800 transition-colors"
                        >
                          <Download className="h-3.5 w-3.5" />
                        </a>
                      </div>
                    ) : emojiOnly ? (
                      /* Big emoji-only messages */
                      <div
                        className={`select-none leading-none py-1 ${getEmojiAnimationClass(msg.content)}`}
                        style={{ fontSize: msg.content.trim().length <= 2 ? "2rem" : msg.content.trim().length <= 5 ? "1.6rem" : "1.25rem" }}
                      >
                        <TwemojiText text={msg.content} />
                      </div>
                    ) : (
                      <div
                        className={`rounded-2xl px-4 py-2 text-[16px] transition-all relative premium-chat-bubble ${
                          isMe
                            ? theme.startsWith("aqua")
                              ? "bubble-tail-me border border-[var(--theme-border-color)]/10"
                              : "rounded-br-none border border-white/5"
                            : theme.startsWith("aqua")
                              ? "bubble-tail-them border border-black/5"
                              : "rounded-bl-none border border-[var(--theme-border-color)]/60"
                        }`}
                        style={{
                          background: isMe
                            ? typeof (window as any) !== 'undefined'
                              ? `var(--theme-bubble-sent)`
                              : undefined
                            : `var(--theme-bubble-received)`,
                          color: isMe ? `var(--theme-bubble-sent-text)` : `var(--theme-bubble-received-text)`,
                        }}
                      >
                        <TwemojiText text={msg.content} />
                      </div>
                    )}

                    {/* Footer status text - Timestamp: 11sp (11px), Regular */}
                    <div
                      className={`flex items-center gap-1 mt-1 text-[11px] text-[var(--theme-text-secondary)]/70 font-normal ${
                        isMe ? "justify-end mr-1" : "justify-start ml-1"
                      }`}
                    >
                      <span>{formatMessageTime(msg.createdAt)}</span>
                      {starredMessageIds.has(msg.id) && (
                        <Star className="h-3 w-3 text-amber-400 fill-amber-400 ml-1 shrink-0" />
                      )}
                    {isMsgEdited && !isMsgDeleted && <span className="opacity-60">(edited)</span>}
                    {isMe && !isMsgDeleted && (() => {
                      const status = (() => {
                        if (!msg.receipts || msg.receipts.length === 0) return "SENT";
                        const otherReceipts = msg.receipts.filter((r: any) => r.userId !== user?.id);
                        if (otherReceipts.length === 0) return "SENT";
                        if (otherReceipts.some((r: any) => r.status === "READ")) return "READ";
                        if (otherReceipts.some((r: any) => r.status === "DELIVERED")) return "DELIVERED";
                        return "SENT";
                      })();

                      if (status === "READ") {
                        return (
                          <span className="ml-1 shrink-0 inline-flex items-center" title="Read">
                            {/* Double blue ticks */}
                            <svg width="18" height="11" viewBox="0 0 18 11" style={{ color: "#34b7f1" }}>
                              <path d="M1 6l3.5 3.5L12 1" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                              <path d="M6 6l3.5 3.5L17 1" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                            </svg>
                          </span>
                        );
                      } else if (status === "DELIVERED") {
                        return (
                          <span className="ml-1 shrink-0 inline-flex items-center" title="Delivered">
                            {/* Double grey ticks */}
                            <svg width="18" height="11" viewBox="0 0 18 11" className="text-[var(--theme-text-secondary)]/50">
                              <path d="M1 6l3.5 3.5L12 1" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                              <path d="M6 6l3.5 3.5L17 1" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                            </svg>
                          </span>
                        );
                      } else {
                        return (
                          <span className="ml-1 shrink-0 inline-flex items-center" title="Sent">
                            {/* Single grey tick */}
                            <svg width="12" height="11" viewBox="0 0 12 11" className="text-[var(--theme-text-secondary)]/50">
                              <path d="M1 6l3.5 3.5L11 1" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                            </svg>
                          </span>
                        );
                      }
                    })()}
                  </div>
                </div>

                {/* Hover Message Actions Overlay */}
                {hoveredMessageId === msg.id && !isMsgDeleted && (
                  <div
                    className={`absolute bottom-8 flex gap-1 bg-zinc-950/90 border border-zinc-850 px-1.5 py-1 rounded-xl shadow-xl z-20 transition-all ${
                      isMe ? "right-0" : "left-0"
                    }`}
                  >
                    <button
                      onClick={() => setReplyingToMessage(msg)}
                      className="p-1 text-zinc-400 hover:text-white hover:bg-zinc-900 rounded-lg transition-colors cursor-pointer"
                      title="Reply"
                    >
                      <CornerUpLeft className="h-3.5 w-3.5" />
                    </button>
                    {isMe && !msg.mediaUrl && (new Date().getTime() - new Date(msg.createdAt).getTime() < 30 * 60 * 1000) && (
                      <button
                        onClick={() => handleEditClick(msg)}
                        className="p-1 text-zinc-400 hover:text-white hover:bg-zinc-900 rounded-lg transition-colors cursor-pointer"
                        title="Edit"
                      >
                        <Edit3 className="h-3.5 w-3.5" />
                      </button>
                    )}
                    <button
                      onClick={() => toggleStarMessage(msg.id)}
                      className="p-1 text-zinc-400 hover:text-amber-400 hover:bg-zinc-900 rounded-lg transition-colors cursor-pointer"
                      title={starredMessageIds.has(msg.id) ? "Unstar" : "Star"}
                    >
                      <Star className={`h-3.5 w-3.5 ${starredMessageIds.has(msg.id) ? "text-amber-400 fill-amber-400" : ""}`} />
                    </button>
                    <button
                      onClick={() => openForwardModal(msg)}
                      className="p-1 text-zinc-400 hover:text-white hover:bg-zinc-900 rounded-lg transition-colors cursor-pointer"
                      title="Forward"
                    >
                      <Share2 className="h-3.5 w-3.5" />
                    </button>
                    <button
                      onClick={() => handleDeleteClick(msg)}
                      className="p-1 text-zinc-400 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-colors cursor-pointer"
                      title="Delete"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )}
              </div>
            </React.Fragment>
          );
        })
      )}

        {/* Typing Indicator Bubble */}
        {isRecipientTyping && (
          <div className="flex items-end gap-3 mr-auto animate-fade-in">
            <div className="shrink-0 h-8 w-8 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] flex items-center justify-center">
              <img
                src={getAvatarUrl(chat.avatarUrl, chat.name)}
                alt={chat.name}
                className="h-8 w-8 rounded-full object-cover"
              />
            </div>
            <div className="flex flex-col gap-1">
              {chat.isGroup && (
                <span className="text-[12px] text-[var(--theme-text-secondary)] pl-1 font-normal">{typingUsername}</span>
              )}
              <div className="flex items-center gap-1.5 rounded-2xl rounded-bl-sm bg-[var(--theme-bg-sidebar)] border border-[var(--theme-border-color)] px-4 py-3 shadow-sm">
                <span className="h-2 w-2 rounded-full bg-[var(--theme-accent)] animate-bounce" style={{ animationDelay: "0ms" }} />
                <span className="h-2 w-2 rounded-full bg-[var(--theme-accent)] animate-bounce" style={{ animationDelay: "150ms" }} />
                <span className="h-2 w-2 rounded-full bg-[var(--theme-accent)] animate-bounce" style={{ animationDelay: "300ms" }} />
              </div>
            </div>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Input Message Area */}
      <div className="border-t border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input)] transition-colors duration-300 relative z-10">
        {isSelectionMode ? (
          <div className="flex items-center justify-between p-4 bg-[var(--theme-bg-chat-input)] border-t border-[var(--theme-border-color)] animate-fade-in">
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => {
                  setIsSelectionMode(false);
                  setSelectedMessageIds(new Set());
                }}
                className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/50 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                title="Cancel selection"
              >
                <X className="h-4.5 w-4.5" />
              </button>
              <span className="text-sm font-bold text-[var(--theme-text-primary)]">
                {selectedMessageIds.size} messages selected
              </span>
            </div>
            <button
              type="button"
              disabled={selectedMessageIds.size === 0}
              onClick={handleDeleteSelected}
              className="flex items-center gap-2 rounded-xl bg-red-500 hover:bg-red-600 disabled:opacity-50 disabled:cursor-not-allowed px-4 py-2 text-xs font-bold text-white transition-all cursor-pointer"
            >
              <Trash2 className="h-4 w-4" />
              Delete for Me
            </button>
          </div>
        ) : (
          <>
            {/* Reply Preview */}
            {replyingToMessage && (
              <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)]/50 px-5 py-2.5 text-xs">
                <div className="flex-1 min-w-0 border-l-2 border-[var(--theme-accent)] pl-3">
                  <span className="font-semibold text-[var(--theme-accent)] text-[10px] block">
                    Replying to {replyingToMessage.sender.username}
                  </span>
                  <p className="text-[var(--theme-text-primary)] truncate">{replyingToMessage.content}</p>
                </div>
                <button
                  onClick={() => setReplyingToMessage(null)}
                  className="rounded-lg p-1 text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
            )}

            {/* Edit Preview */}
            {editingMessage && (
              <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)]/50 px-5 py-2.5 text-xs">
                <div className="flex-1 min-w-0 border-l-2 border-amber-500 pl-3">
                  <span className="font-semibold text-amber-500 text-[10px] block">
                    Editing message
                  </span>
                  <p className="text-[var(--theme-text-primary)] truncate">{editingMessage.content}</p>
                </div>
                <button
                  onClick={() => {
                    setEditingMessage(null);
                    setInputValue("");
                  }}
                  className="rounded-lg p-1 text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
            )}

            {/* Hidden File Input - accepts images, videos, audio and documents */}
            <input
              type="file"
              ref={fileInputRef}
              onChange={handleFileUpload}
              className="hidden"
              accept="image/*,video/*,audio/*,application/pdf,text/*,application/zip,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            />

            {/* Form Input */}
            {chat.recipient && blockedIds.includes(chat.recipient.id) ? (
              <div className="p-4 text-center bg-red-950/10 border border-red-500/20 text-red-400 text-xs font-semibold rounded-xl flex items-center justify-center gap-2 m-2 sm:m-4">
                <Ban className="h-4.5 w-4.5" />
                <span>You have blocked this contact.</span>
                <button
                  type="button"
                  onClick={() => handleToggleBlock(chat.recipient!.id)}
                  className="underline font-bold text-[var(--theme-accent)] hover:opacity-80 transition-opacity ml-1 cursor-pointer"
                >
                  Unblock User
                </button>
              </div>
            ) : (
              <form onSubmit={handleSendMessage} className="p-2 sm:px-4 sm:py-3 relative animate-fade-in border-t border-[var(--theme-border-color)]/20 bg-[var(--theme-bg-chat-input)]">
                <div className="flex items-center gap-2 sm:gap-3 h-14 min-h-[56px]">
                  {/* File Upload Button */}
                  <button
                    type="button"
                    disabled={isUploadingFile || isRecording}
                    onClick={() => fileInputRef.current?.click()}
                    className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all duration-200 cursor-pointer disabled:opacity-50"
                    title="Attach File"
                  >
                    {isUploadingFile ? (
                      <Loader2 className="h-5 w-5 animate-spin text-[var(--theme-accent)]" />
                    ) : (
                      <Paperclip className="h-6 w-6" />
                    )}
                  </button>
                  
                  {/* Camera Button */}
                  <button
                    type="button"
                    disabled={isRecording}
                    onClick={() => startCamera()}
                    className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all duration-200 cursor-pointer disabled:opacity-50"
                    title="Camera"
                  >
                    <Camera className="h-6 w-6" />
                  </button>

                  {/* Emoji Picker Button */}
                  <div className="relative hidden sm:block" ref={emojiPickerRef}>
                    <button
                      type="button"
                      disabled={isRecording}
                      onClick={() => setShowEmojiPicker((v) => !v)}
                      className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border transition-all duration-200 cursor-pointer ${
                        showEmojiPicker
                          ? "border-[var(--theme-accent)] text-[var(--theme-accent)] bg-[var(--theme-accent)]/10"
                          : "border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
                      }`}
                      title="Emoji"
                    >
                      <Smile className="h-6 w-6" />
                    </button>

                    {showEmojiPicker && (
                      <div className="absolute bottom-16 left-0 z-50 shadow-2xl rounded-2xl overflow-hidden animate-fade-in">
                        <EmojiPicker
                          onEmojiClick={(emojiData) => {
                            onEmojiClick(emojiData);
                          }}
                          theme={(theme === "aqua-light" ? "light" : "dark") as Theme}
                          width={320}
                          height={420}
                          searchPlaceholder="Search emoji..."
                          previewConfig={{ showPreview: false }}
                        />
                      </div>
                    )}
                  </div>

                  {isRecording ? (
                    <div className="flex-1 flex items-center justify-between rounded-xl border border-red-500/50 bg-red-500/10 px-4 py-2.5 h-11">
                      <div className="flex items-center gap-2 text-red-500 animate-pulse">
                        <Mic className="h-5 w-5" />
                        <span className="text-[16px] font-semibold text-red-400">
                          {Math.floor(recordingDuration / 60)}:{(recordingDuration % 60).toString().padStart(2, '0')}
                        </span>
                      </div>
                      <button
                        type="button"
                        onClick={stopRecording}
                        className="rounded-lg bg-red-500 p-1 text-white hover:bg-red-650 cursor-pointer"
                      >
                        <Square className="h-4 w-4" fill="currentColor" />
                      </button>
                    </div>
                  ) : (
                    <input
                      type="text"
                      value={inputValue}
                      onChange={handleInputChange}
                      placeholder={editingMessage ? "Edit your message..." : "Type a message..."}
                      className="flex-1 min-w-0 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-chat-input-field)] px-4 py-2.5 text-[16px] text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all duration-200 h-11"
                    />
                  )}

                  {!inputValue.trim() && !isRecording ? (
                    <button
                      type="button"
                      onClick={startRecording}
                      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-[var(--theme-bg-sidebar-search)] border border-[var(--theme-border-color)] text-[var(--theme-accent)] hover:text-white hover:bg-[var(--theme-accent)] shadow-lg transition-all duration-200 cursor-pointer"
                      title="Hold or Click to Record"
                    >
                      <Mic className="h-6 w-6" />
                    </button>
                  ) : (
                    <button
                      type="submit"
                      disabled={isRecording || !inputValue.trim()}
                      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-[var(--theme-accent-text)] shadow-lg hover:opacity-95 transition-all duration-200 cursor-pointer disabled:opacity-50 animate-fade-in"
                      style={{
                        background: "linear-gradient(to top right, #0097a7, #00d4ff)"
                      }}
                    >
                      <Send className="h-6 w-6" />
                    </button>
                  )}
                </div>
              </form>
            )}
          </>
        )}
      </div>

      {/* Camera Modal - Full Viewport Layout */}
      {showCamera && (
        <div className="fixed inset-0 z-[100] flex flex-col bg-black animate-fade-in">
          {/* Header Controls Overlay */}
          <div className="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
            <button
              onClick={stopCamera}
              className="p-3 rounded-full bg-black/50 hover:bg-black/70 text-white transition-colors cursor-pointer"
              title="Close"
            >
              <X className="h-6 w-6" />
            </button>
            <span className="text-white text-xs font-bold tracking-widest bg-black/30 px-3.5 py-1.5 rounded-full select-none uppercase">
              Camera Viewport
            </span>
            <button
              onClick={toggleCaptureCamera}
              className="p-3 rounded-full bg-black/50 hover:bg-black/70 text-white transition-colors cursor-pointer"
              title="Switch Camera"
            >
              <RefreshCw className="h-6 w-6 animate-pulse" />
            </button>
          </div>

          {/* Full Screen Video Stream */}
          <div className="flex-1 w-full h-full relative">
            <video
              ref={videoRef}
              autoPlay
              playsInline
              className="w-full h-full object-cover"
              style={cameraFacingMode === "user" ? { transform: "scaleX(-1)" } : undefined}
            />
            <canvas ref={canvasRef} className="absolute inset-0 opacity-0 pointer-events-none" />
          </div>

          {/* Bottom Capturing Control Area Overlay */}
          <div className="absolute bottom-10 left-0 right-0 flex justify-center z-10">
            <button
              type="button"
              onClick={capturePhoto}
              className="h-20 w-20 rounded-full border-4 border-white bg-white/10 hover:bg-white/30 flex items-center justify-center cursor-pointer transition-transform hover:scale-105 active:scale-95 shadow-2xl"
            >
              <div className="h-14 w-14 rounded-full bg-white border border-black/10" />
            </button>
          </div>
        </div>
      )}

      {/* Camera Capture Image Preview Modal */}
      {showCameraPreview && (
        <div className="fixed inset-0 z-[101] flex items-center justify-center bg-black/95 backdrop-blur-md p-4 animate-fade-in">
          <div className="w-full max-w-2xl bg-[#020b16] rounded-2xl border border-[var(--theme-border-color)] overflow-hidden shadow-2xl">
            <div className="p-4 border-b border-[var(--theme-border-color)] flex justify-between items-center bg-[#001428]">
              <h3 className="text-white font-semibold">Preview Captured Photo</h3>
              <button
                onClick={() => {
                  setShowCameraPreview(false);
                  setCapturedBlob(null);
                  setCapturedPreviewUrl("");
                }}
                className="text-gray-400 hover:text-white bg-white/10 p-1.5 rounded-lg cursor-pointer"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="relative aspect-video bg-black flex items-center justify-center">
              <img src={capturedPreviewUrl} alt="Preview Captured" className="w-full h-full object-contain" />
            </div>
            <div className="p-4 flex gap-3 bg-[var(--theme-bg-chat-input)]">
              <button
                onClick={() => {
                  setShowCameraPreview(false);
                  setCapturedBlob(null);
                  setCapturedPreviewUrl("");
                  startCamera();
                }}
                className="flex-1 py-3 rounded-xl border border-[var(--theme-border-color)] hover:bg-[var(--theme-bg-sidebar-item-hover)] text-xs font-bold text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
              >
                Retake
              </button>
              <button
                onClick={() => {
                  if (capturedBlob) {
                    uploadMediaData(capturedBlob, "IMAGE");
                  }
                  setShowCameraPreview(false);
                  setCapturedBlob(null);
                  setCapturedPreviewUrl("");
                }}
                className="flex-1 py-3 rounded-xl bg-[var(--theme-accent)] text-black text-xs font-bold transition-all cursor-pointer hover:opacity-90"
              >
                Send Photo
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Hidden wallpaper upload input */}
      <input
        type="file"
        ref={wallpaperUploadRef}
        onChange={handleWallpaperUpload}
        accept="image/*"
        className="hidden"
      />

      {/* Wallpaper Picker Modal */}
      {showWallpaperPicker && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4 animate-fade-in">
          <div className="w-full max-w-2xl max-h-[85vh] flex flex-col rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl overflow-hidden animate-scale-up">
            <div className="p-4 border-b border-[var(--theme-border-color)] flex justify-between items-center shrink-0">
              <h3 className="text-[var(--theme-text-primary)] font-bold flex items-center gap-2">
                <ImageIcon className="h-5 w-5 text-[var(--theme-accent)]" />
                Chat Wallpaper Customization
              </h3>
              <button onClick={() => setShowWallpaperPicker(false)} className="text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] bg-[var(--theme-bg-sidebar-item-hover)] p-1.5 rounded-lg cursor-pointer">
                <X className="h-5 w-5" />
              </button>
            </div>
            
            {/* Category Filter Tabs */}
            <div className="flex gap-2 px-4 py-2.5 border-b border-[var(--theme-border-color)] overflow-x-auto bg-[var(--theme-bg-sidebar-search)]/30 shrink-0 select-none scrollbar-none">
              {[
                { id: "doodle", name: "Doodle" },
                { id: "gradient", name: "Gradients" },
                { id: "nature", name: "Nature" },
                { id: "abstract", name: "Abstract" },
                { id: "minimal", name: "Minimal" },
                { id: "texture", name: "Textures" },
                { id: "geometric", name: "Geometric" },
                { id: "dark", name: "Dark Mode" },
                { id: "artistic", name: "Artistic" },
              ].map(cat => (
                <button
                  key={cat.id}
                  onClick={() => setActiveWallpaperCat(cat.id)}
                  className={`px-3 py-1.5 text-xs font-bold rounded-lg transition-all whitespace-nowrap cursor-pointer ${
                    activeWallpaperCat === cat.id
                      ? "bg-[var(--theme-accent)] text-black font-extrabold"
                      : "text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)]"
                  }`}
                >
                  {cat.name}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
              {/* My Uploads section only visible on Doodle category */}
              {activeWallpaperCat === "doodle" && (
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <span className="text-xs font-bold text-[var(--theme-text-secondary)] uppercase tracking-wider">My Uploads</span>
                    <button
                      onClick={() => wallpaperUploadRef.current?.click()}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--theme-accent)]/15 border border-[var(--theme-accent)]/40 text-[var(--theme-accent)] text-xs font-semibold hover:bg-[var(--theme-accent)]/25 transition-all cursor-pointer"
                    >
                      <ImageIcon className="h-3.5 w-3.5" />
                      Upload Image
                    </button>
                  </div>
                  {customWallpapers.length === 0 ? (
                    <button
                      onClick={() => wallpaperUploadRef.current?.click()}
                      className="w-full flex flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 p-8 text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] transition-all cursor-pointer"
                    >
                      <ImageIcon className="h-8 w-8 opacity-50" />
                      <span className="text-xs font-medium">Click to upload your own background</span>
                      <span className="text-[10px] opacity-60">Supports JPG, PNG, WEBP, GIF</span>
                    </button>
                  ) : (
                    <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
                      {customWallpapers.map((wp) => (
                        <div key={wp.id} className="relative group">
                          <button
                            onClick={() => {
                              setSelectedWallpaper(wp.id);
                              if (typeof window !== "undefined") {
                                localStorage.setItem("dolsyx_chat_wallpaper", wp.id);
                              }
                            }}
                            className={`relative flex flex-col items-center gap-2 w-full cursor-pointer transition-all hover:scale-105 ${selectedWallpaper === wp.id ? 'ring-2 ring-[var(--theme-accent)] ring-offset-2 ring-offset-[var(--theme-bg-sidebar)] rounded-xl' : ''}`}
                          >
                            <div
                              className="w-full aspect-[9/16] rounded-xl border border-[var(--theme-border-color)] shadow-md overflow-hidden relative"
                              style={{
                                backgroundImage: `url(${wp.value})`,
                                backgroundSize: 'cover',
                                backgroundPosition: 'center'
                              }}
                            >
                              {selectedWallpaper === wp.id && (
                                <div className="absolute top-2 right-2 h-6 w-6 rounded-full bg-[var(--theme-accent)] flex items-center justify-center text-black shadow-lg">
                                  <CheckSquare className="h-4 w-4" />
                                </div>
                              )}
                            </div>
                            <span className="text-xs font-medium text-[var(--theme-text-primary)] truncate w-full text-center px-1">{wp.name}</span>
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleDeleteCustomWallpaper(wp.id); }}
                            className="absolute top-1 left-1 h-6 w-6 rounded-full bg-red-500/80 hover:bg-red-500 flex items-center justify-center text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-lg cursor-pointer"
                            title="Remove"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {/* Built-in Wallpapers section (filtered by category) */}
              <div>
                <span className="text-xs font-bold text-[var(--theme-text-secondary)] uppercase tracking-wider block mb-3">
                  {WALLPAPER_CATEGORIES.find(c => c.id === activeWallpaperCat)?.name || "Wallpapers"}
                </span>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
                  {CHAT_WALLPAPERS.filter(wp => wp.category === activeWallpaperCat).map((wp) => (
                    <button
                      key={wp.id}
                      onClick={() => {
                        setSelectedWallpaper(wp.id);
                        if (typeof window !== "undefined") {
                          localStorage.setItem("dolsyx_chat_wallpaper", wp.id);
                        }
                      }}
                      className={`relative flex flex-col items-center gap-2 cursor-pointer transition-all hover:scale-105 ${selectedWallpaper === wp.id ? 'ring-2 ring-[var(--theme-accent)] ring-offset-2 ring-offset-[var(--theme-bg-sidebar)] rounded-xl' : ''}`}
                    >
                      <div 
                        className="w-full aspect-[9/16] rounded-xl border border-[var(--theme-border-color)] shadow-md overflow-hidden relative"
                        style={{
                          background: wp.type === 'css' ? wp.value || 'var(--theme-bg-app)' : 'var(--theme-bg-app)',
                          backgroundImage: wp.type === 'image' ? `url(${wp.value})` : 'none',
                          backgroundSize: 'cover',
                          backgroundPosition: 'center'
                        }}
                      >
                        {wp.id === 'default' && (
                          <div className="aqua-wallpaper" />
                        )}
                        {selectedWallpaper === wp.id && (
                          <div className="absolute top-2 right-2 h-6 w-6 rounded-full bg-[var(--theme-accent)] flex items-center justify-center text-black shadow-lg">
                            <CheckSquare className="h-4 w-4" />
                          </div>
                        )}
                      </div>
                      <span className="text-xs font-medium text-[var(--theme-text-primary)]">{wp.name}</span>
                    </button>
                  ))}
                </div>
              </div>
            </div>
            
            <div className="p-4 border-t border-[var(--theme-border-color)] shrink-0 flex justify-end">
              <button onClick={() => setShowWallpaperPicker(false)} className="px-6 py-2 rounded-xl bg-[var(--theme-accent)] text-black font-bold cursor-pointer">
                Done
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Generic Profile View Drawer */}
      {profileUser && (
        <div className="fixed inset-0 z-[9999] flex justify-end bg-black/60 backdrop-blur-xs animate-fade-in">
          <div className="h-full w-full sm:w-[380px] bg-[var(--theme-bg-sidebar)] border-l border-[var(--theme-border-color)] flex flex-col shadow-2xl relative animate-slide-left overflow-y-auto">
            {/* Header */}
            <div className="flex items-center gap-4 px-6 py-5 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)]">
              <button
                onClick={() => setProfileUser(null)}
                className="p-1 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] cursor-pointer"
              >
                <X className="h-5 w-5" />
              </button>
              <span className="font-bold text-sm text-[var(--theme-text-primary)]">Contact Details</span>
            </div>

            {/* Profile Avatar Area */}
            <div className="flex flex-col items-center py-8 px-6 bg-[var(--theme-bg-sidebar-search)]/30 border-b border-[var(--theme-border-color)] space-y-4">
              <div className="relative group cursor-pointer" onClick={() => window.open(getAvatarUrl(profileUser.avatarUrl, profileUser.username), "_blank")}>
                <img
                  src={getAvatarUrl(profileUser.avatarUrl, profileUser.username)}
                  alt={profileUser.username}
                  className="h-44 w-44 rounded-full border-4 border-[var(--theme-bg-sidebar)] object-cover shadow-2xl transition-transform hover:scale-105"
                />
                {onlineUsers.includes(profileUser.id) && (
                  <span className="absolute bottom-2 right-2 h-5 w-5 rounded-full border-4 border-[var(--theme-bg-sidebar)] bg-green-500 shadow-lg" />
                )}
              </div>

              <div className="text-center">
                <h3 className="text-xl font-black tracking-tight text-[var(--theme-text-primary)]">
                  {profileUser.username}
                </h3>
                <p className="text-xs mt-1">
                  {onlineUsers.includes(profileUser.id) ? (
                    <span className="text-green-400 font-semibold flex items-center justify-center gap-1">
                      <span className="h-1.5 w-1.5 rounded-full bg-green-400 animate-pulse inline-block" />
                      Online
                    </span>
                  ) : profileUser.lastSeen ? (
                    <span className="text-[var(--theme-text-secondary)] font-medium">
                      Last seen {formatLastSeen(profileUser.lastSeen)}
                    </span>
                  ) : (
                    <span className="text-[var(--theme-text-secondary)]">Offline</span>
                  )}
                </p>
              </div>
            </div>

            {/* Profile Info Details List */}
            <div className="p-6 space-y-6">
              {/* Bio Section */}
              <div className="space-y-2">
                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">About / Status</span>
                <p className="text-sm text-[var(--theme-text-primary)] bg-[var(--theme-bg-sidebar-search)] p-3.5 rounded-xl border border-[var(--theme-border-color)] leading-relaxed">
                  {profileUser.bio || "Hey there! I am using DOLSYX."}
                </p>
              </div>

              {/* Contact Info */}
              <div className="space-y-3">
                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Contact Info</span>
                {profileUser.email && (
                  <div className="flex items-center gap-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3.5 py-3">
                    <Mail className="h-4.5 w-4.5 text-[var(--theme-accent)] shrink-0" />
                    <span className="text-xs text-[var(--theme-text-primary)] truncate selection:bg-[var(--theme-accent)]/20">{profileUser.email}</span>
                  </div>
                )}
                {profileUser.phoneNumber && (
                  <div className="flex items-center gap-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3.5 py-3">
                    <Phone className="h-4.5 w-4.5 text-[var(--theme-accent)] shrink-0" />
                    <span className="text-xs text-[var(--theme-text-primary)]">{profileUser.phoneNumber}</span>
                  </div>
                )}
              </div>

              {/* Settings / Actions */}
              <div className="pt-2">
                {user?.id !== profileUser.id && (
                  <button
                    type="button"
                    onClick={() => handleToggleBlock(profileUser.id)}
                    className={`w-full flex items-center justify-center gap-2 rounded-xl py-3 text-xs font-bold transition-all cursor-pointer border ${
                      blockedIds.includes(profileUser.id)
                        ? "border-emerald-500/30 hover:bg-emerald-500/10 text-emerald-400"
                        : "border-red-500/30 hover:bg-red-500/10 text-red-400"
                    }`}
                  >
                    <Ban className="h-4 w-4" />
                    {blockedIds.includes(profileUser.id) ? "Unblock User" : "Block User"}
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Clear Chat Confirmation Modal ──────────────────────────────── */}
      {showClearConfirm && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-amber-500/20 bg-[var(--theme-bg-sidebar)] shadow-2xl shadow-amber-900/20 overflow-hidden">
            {/* Icon header */}
            <div className="flex flex-col items-center gap-3 px-6 pt-8 pb-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-amber-500/10 border border-amber-500/20">
                <Trash2 className="h-7 w-7 text-amber-400" />
              </div>
              <h3 className="text-base font-bold text-[var(--theme-text-primary)] text-center">Clear All Messages?</h3>
              <p className="text-xs text-[var(--theme-text-secondary)] text-center leading-relaxed">
                This will permanently delete all messages in this chat. This action <span className="font-bold text-amber-400">cannot be undone</span>.
              </p>
            </div>
            {/* Divider */}
            <div className="h-px bg-[var(--theme-border-color)] mx-6" />
            {/* Actions */}
            <div className="flex gap-3 p-5">
              <button
                onClick={() => setShowClearConfirm(false)}
                className="flex-1 rounded-xl border border-[var(--theme-border-color)] py-2.5 text-sm font-semibold text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
              >
                Cancel
              </button>
              <button
                onClick={handleClearChat}
                disabled={isClearingChat}
                className="flex-1 rounded-xl bg-amber-500 hover:bg-amber-400 disabled:opacity-60 py-2.5 text-sm font-bold text-black transition-all cursor-pointer flex items-center justify-center gap-2"
              >
                {isClearingChat ? (
                  <><Loader2 className="h-4 w-4 animate-spin" />Clearing...</>
                ) : (
                  <><Trash2 className="h-4 w-4" />Clear Chat</>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Delete Chat Confirmation Modal ─────────────────────────────── */}
      {showDeleteChatConfirm && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-red-500/20 bg-[var(--theme-bg-sidebar)] shadow-2xl shadow-red-900/20 overflow-hidden">
            {/* Icon header */}
            <div className="flex flex-col items-center gap-3 px-6 pt-8 pb-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-red-500/10 border border-red-500/20">
                <Trash2 className="h-7 w-7 text-red-400" />
              </div>
              <h3 className="text-base font-bold text-[var(--theme-text-primary)] text-center">Delete Conversation?</h3>
              <p className="text-xs text-[var(--theme-text-secondary)] text-center leading-relaxed">
                This will permanently delete this entire conversation including all messages. This action <span className="font-bold text-red-400">cannot be undone</span>.
              </p>
            </div>
            {/* Divider */}
            <div className="h-px bg-[var(--theme-border-color)] mx-6" />
            {/* Actions */}
            <div className="flex gap-3 p-5">
              <button
                onClick={() => setShowDeleteChatConfirm(false)}
                className="flex-1 rounded-xl border border-[var(--theme-border-color)] py-2.5 text-sm font-semibold text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
              >
                Cancel
              </button>
              <button
                onClick={handleDeleteChat}
                disabled={isDeletingChat}
                className="flex-1 rounded-xl bg-red-500 hover:bg-red-600 disabled:opacity-60 py-2.5 text-sm font-bold text-white transition-all cursor-pointer flex items-center justify-center gap-2"
              >
                {isDeletingChat ? (
                  <><Loader2 className="h-4 w-4 animate-spin" />Deleting...</>
                ) : (
                  <><Trash2 className="h-4 w-4" />Delete Chat</>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Single Message Deletion Modal ─────────────────────────────── */}
      {deleteConfirmMessage && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-red-500/20 bg-[var(--theme-bg-sidebar)] shadow-2xl shadow-red-900/20 overflow-hidden">
            {/* Icon header */}
            <div className="flex flex-col items-center gap-3 px-6 pt-8 pb-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-red-500/10 border border-red-500/20">
                <Trash2 className="h-7 w-7 text-red-400" />
              </div>
              <h3 className="text-base font-bold text-[var(--theme-text-primary)] text-center">Delete Message?</h3>
              <p className="text-xs text-[var(--theme-text-secondary)] text-center leading-relaxed">
                Choose how you want to delete this message.
              </p>
            </div>
            {/* Divider */}
            <div className="h-px bg-[var(--theme-border-color)] mx-6" />
            {/* Actions */}
            <div className="flex flex-col gap-2 p-5">
              <button
                onClick={deleteMessageForMe}
                className="w-full rounded-xl bg-red-500/10 hover:bg-red-500/20 border border-red-500/25 py-2.5 text-sm font-semibold text-red-400 transition-all cursor-pointer text-center"
              >
                Delete for Me
              </button>
              {deleteConfirmMessage.senderId === user?.id && (
                <button
                  onClick={deleteMessageForEveryone}
                  className="w-full rounded-xl bg-red-500 hover:bg-red-600 py-2.5 text-sm font-bold text-white transition-all cursor-pointer text-center"
                >
                  Delete for Everyone
                </button>
              )}
              <button
                onClick={() => setDeleteConfirmMessage(null)}
                className="w-full rounded-xl border border-[var(--theme-border-color)] py-2.5 text-sm font-semibold text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer text-center"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
      {/* ── Forward Message Modal ─────────────────────────────── */}
      {showForwardModal && forwardingMessage && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl overflow-hidden flex flex-col max-h-[80vh]">
            <div className="px-6 pt-6 pb-4 flex items-center justify-between border-b border-[var(--theme-border-color)]">
              <h3 className="text-base font-bold text-[var(--theme-text-primary)]">Forward Message</h3>
              <button
                onClick={() => { setShowForwardModal(false); setForwardingMessage(null); }}
                className="p-1.5 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
              >
                <X className="h-4.5 w-4.5" />
              </button>
            </div>
            
            {/* Preview of forwarding content */}
            <div className="px-6 py-3 bg-[var(--theme-bg-sidebar-search)] border-b border-[var(--theme-border-color)] text-xs text-[var(--theme-text-secondary)] italic truncate">
              {forwardingMessage.content || "[Media Attachment]"}
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-2">
              <p className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase tracking-wider mb-2">Select conversation</p>
              {availableChatsForForwarding.length === 0 ? (
                <p className="text-xs text-[var(--theme-text-secondary)] text-center py-6">No conversations available</p>
              ) : (
                availableChatsForForwarding.map((c: any) => {
                  const targetName = c.isGroup ? c.name : c.recipient?.username || "Unknown";
                  return (
                    <div key={c.id} className="flex items-center justify-between p-2 rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors">
                      <div className="flex items-center gap-3 min-w-0">
                        <img
                          src={getAvatarUrl(c.isGroup ? null : c.recipient?.avatarUrl, targetName)}
                          alt={targetName}
                          className="h-8 w-8 rounded-full object-cover border border-[var(--theme-border-color)] bg-zinc-800"
                        />
                        <span className="text-xs font-bold text-[var(--theme-text-primary)] truncate">{targetName}</span>
                      </div>
                      <button
                        onClick={() => handleForwardMessage(c.id)}
                        className="px-3 py-1 bg-[var(--theme-accent)] text-black rounded-lg text-[10px] font-bold hover:opacity-90 transition-opacity cursor-pointer"
                      >
                        Send
                      </button>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
