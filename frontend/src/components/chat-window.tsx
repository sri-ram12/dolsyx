"use client";

import React, { useState, useEffect, useRef } from "react";
import TwemojiText from "./twemoji-text";
import AnimatedEmoji from "./animated-emoji";
import { useAuth, API_URL } from "@/context/auth-context";
import { useE2EE } from "@/context/e2ee-context";
import { encryptConversationPayload, decryptIncomingContent, encryptFileBytes, decryptFileBytes } from "@/utils/e2ee/cryptoService";
import { useTheme } from "@/context/theme-context";
import { useToast } from "@/context/toast-context";
import { Chat } from "./chat-sidebar";
import GroupProfileModal from "./group-profile-modal";
import WallpaperModal from "./wallpaper-modal";
import { ReactionPopup } from "./reaction-popup";
import { DecryptedImage, DecryptedVideo } from "./decrypted-media";
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
  Forward,
  Ban,
  RefreshCw,
  Star,
  MapPin,
  Share2,
  Lock,
  IndianRupee,
  Users,
} from "lucide-react";
import { Socket } from "socket.io-client";
import EmojiPicker, { EmojiClickData, Theme } from "emoji-picker-react";
import { getDefaultAvatar, getAvatarUrl, resolveMediaUrl } from "@/utils/avatar";
import { SoundEngine } from "@/utils/sound";

function getQuotedParentPreviewText(parent: any) {
  if (!parent) return "Message";
  if (parent.isDeleted || parent.content === "This message was deleted") {
    return "This message was deleted";
  }
  const mediaType = parent.mediaType || "TEXT";
  const mediaUrl = parent.mediaUrl;
  const content = String(parent.content || "");

  if (mediaType === "CALL_LOG") {
    if (content.toLowerCase().includes("missed")) return "📞 Missed call";
    if (content.toLowerCase().includes("declined")) return "📞 Declined call";
    if (mediaUrl === "VIDEO_CALL" || content.toLowerCase().includes("video")) return "🎥 Video call";
    return "📞 Voice call";
  }
  if (mediaType === "IMAGE") return "📷 Photo";
  if (mediaType === "VIDEO") return "🎥 Video";
  if (mediaType === "AUDIO") return "🎵 Voice message";
  if (mediaType === "LOCATION") return "📍 Location";
  if (mediaType === "POLL") return "📊 Poll";
  if (mediaType === "DOCUMENT" || mediaType === "FILE") return "📄 Document";
  if (mediaType === "STICKER") return "😊 Sticker";

  return content || "Message";
}

function formatMediaBytes(bytes?: number): string {
  if (!bytes || bytes <= 0) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) {
    const mb = bytes / (1024 * 1024);
    return mb >= 10 ? `${mb.toFixed(0)} MB` : `${mb.toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

interface Message {
  id: string;
  content: string;
  senderId: string;
  conversationId: string;
  createdAt: string;
  isEdited?: boolean;
  isDeleted?: boolean;
  mediaUrl?: string | null;
  mediaType?: "TEXT" | "IMAGE" | "VIDEO" | "FILE" | "AUDIO" | "CODE_SNIPPET" | "STICKER" | "CALL_LOG" | "POLL" | "LOCATION" | null;
  fileSize?: number;
  fileName?: string;
  sender: {
    id: string;
    username: string;
    avatarUrl: string | null;
    bio?: string | null;
  };
  receipts?: any[];
  reactions?: any[];
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

function getEmojiCount(str: string): number {
  if (typeof Intl !== 'undefined' && Intl.Segmenter) {
    const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });
    return Array.from(segmenter.segment(str.trim().replace(/\s/g, ''))).length;
  }
  return Array.from(str.trim().replace(/\s/g, '')).length;
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

function PollMessage({ msg, isMe, socket, user }: { msg: Message; isMe: boolean; socket: any; user: any }) {
  let pollData: any = {};
  try {
    pollData = typeof msg.content === "string" && msg.content.startsWith("{") ? JSON.parse(msg.content) : {};
  } catch (_) {}

  const question = pollData.question || "Poll";
  const options: any[] = pollData.options || [];
  const myUserId = user?.id || "user";
  const totalVotes = options.reduce((sum, opt) => sum + (opt.votes?.length || 0), 0);

  const handleVote = (optionId: number) => {
    const opt = options.find((o) => o.id === optionId);
    if (!opt) return;
    if (!opt.votes) opt.votes = [];

    const userVoted = opt.votes.includes(myUserId);
    if (userVoted) {
      opt.votes = opt.votes.filter((id: string) => id !== myUserId);
    } else {
      opt.votes.push(myUserId);
    }

    if (socket && socket.connected) {
      socket.emit("vote_poll", {
        conversationId: msg.conversationId,
        messageId: msg.id,
        optionId: optionId,
      });
    }
  };

  return (
    <div className="w-[270px] rounded-2xl p-4 bg-[#005C4B] text-white shadow-lg text-left select-none">
      <h4 className="font-bold text-[16px] text-white leading-tight mb-3">{question}</h4>
      <div className="space-y-3">
        {options.map((opt) => {
          const votes: string[] = opt.votes || [];
          const userVoted = votes.includes(myUserId);
          const pct = totalVotes > 0 ? Math.round((votes.length / totalVotes) * 100) : 0;

          return (
            <div
              key={opt.id}
              onClick={() => handleVote(opt.id)}
              className="cursor-pointer group flex flex-col space-y-1.5"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2 min-w-0">
                  <div
                    className={`w-5 h-5 rounded-full flex items-center justify-center border ${
                      userVoted ? "border-sky-400 bg-sky-400/20 text-sky-400" : "border-white/40 text-transparent"
                    }`}
                  >
                    <div className={`w-2.5 h-2.5 rounded-full ${userVoted ? "bg-sky-400" : "bg-transparent"}`} />
                  </div>
                  <span className="text-[14px] font-medium text-white truncate">{opt.text}</span>
                </div>
                {votes.length > 0 && <span className="text-[12px] text-white/70 ml-2">{votes.length}</span>}
              </div>
              <div className="w-full bg-white/20 h-1.5 rounded-full overflow-hidden">
                <div className="bg-white h-full transition-all duration-300" style={{ width: `${pct}%` }} />
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-3 text-[11px] text-white/70 italic">{totalVotes} total votes</div>
    </div>
  );
}

function LocationMessage({ msg, isMe }: { msg: Message; isMe: boolean }) {
  let lat = (msg as any).latitude;
  let lng = (msg as any).longitude;
  let locTitle = (msg as any).locationTitle || ((msg as any).isLiveLocation ? "Sharing live location" : "Current Location");
  let isLive = (msg as any).isLiveLocation;
  let liveExpiresAt = (msg as any).liveExpiresAt;

  if ((!lat || !lng) && typeof msg.content === "string" && msg.content.startsWith("{") && msg.content.endsWith("}")) {
    try {
      const decoded = JSON.parse(msg.content);
      lat = decoded.latitude || 12.9716;
      lng = decoded.longitude || 77.5946;
      locTitle = decoded.locationTitle || (decoded.isLiveLocation ? "Sharing live location" : "Current Location");
      isLive = decoded.isLiveLocation || false;
      liveExpiresAt = decoded.liveExpiresAt || null;
    } catch (_) {}
  }

  const safeLat = lat || 12.9716;
  const safeLng = lng || 77.5946;

  const openMap = () => {
    window.open(`https://www.google.com/maps/search/?api=1&query=${safeLat},${safeLng}`, "_blank");
  };

  return (
    <div
      className={`rounded-2xl p-3 shadow-md max-w-xs text-left ${
        isMe
          ? "bg-[var(--theme-bubble-sent)] text-[var(--theme-bubble-sent-text)]"
          : "bg-[var(--theme-bubble-received)] text-[var(--theme-bubble-received-text)]"
      }`}
    >
      <div className="flex items-center space-x-2 mb-2">
        <MapPin className={`w-5 h-5 ${isLive ? "text-emerald-400 animate-pulse" : "text-rose-500"}`} />
        <span className="font-bold text-[14px] truncate">{locTitle}</span>
      </div>
      <div
        onClick={openMap}
        className="relative w-[220px] h-[130px] rounded-xl overflow-hidden cursor-pointer group bg-zinc-900 border border-white/10"
      >
        <img
          src={`https://static-maps.yandex.ru/1.x/?lang=en_US&ll=${safeLng},${safeLat}&z=14&l=map&pt=${safeLng},${safeLat},pm2rdm`}
          alt="Map Location"
          className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
          onError={(e: any) => {
            e.target.style.display = "none";
          }}
        />
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/40 group-hover:bg-black/20 transition-colors">
          <div className="bg-violet-600 hover:bg-violet-500 text-white text-[12px] font-bold px-3 py-1.5 rounded-full shadow-lg flex items-center space-x-1.5 transition-transform group-hover:scale-105">
            <MapPin className="w-3.5 h-3.5" />
            <span>Open Map</span>
          </div>
        </div>
      </div>
      {isLive && liveExpiresAt && (
        <div className="mt-2 text-[11px] opacity-75 italic">
          Expires: {new Date(liveExpiresAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
        </div>
      )}
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

// High-performance Stale-While-Revalidate message and block cache
const conversationMessageCache = new Map<string, any[]>();
let cachedBlockedIds: string[] | null = null;

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
  const { encryptAndSend, decryptIncoming } = useE2EE();
  const { theme, getWallpaperForChat } = useTheme();
  const { toast } = useToast();

  // Blocked and Block list states
  const [blockedIds, setBlockedIds] = useState<string[]>([]);

  // Camera preview states
  const [showCameraPreview, setShowCameraPreview] = useState(false);
  const [capturedBlob, setCapturedBlob] = useState<Blob | null>(null);
  const [capturedPreviewUrl, setCapturedPreviewUrl] = useState("");

  // Clear Chat status
  const [isClearingChat, setIsClearingChat] = useState(false);

  // Group Profile state
  const [showGroupProfile, setShowGroupProfile] = useState(false);

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
  const inputRef = useRef<HTMLInputElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // File Upload State
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isUploadingFile, setIsUploadingFile] = useState(false);

  // Emoji Picker State
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);
  const emojiPickerRef = useRef<HTMLDivElement>(null);
  const [activeReactionMessageId, setActiveReactionMessageId] = useState<string | null>(null);

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
      let forwardContent = forwardingMessage.content;
      if (forwardContent) {
        try {
          forwardContent = await encryptConversationPayload(chatId, forwardContent);
        } catch (_) {}
      }
      socket.emit("send_message", {
        conversationId: chatId,
        content: forwardContent,
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
  const [isLocked, setIsLocked] = useState(false);
  const headerMenuRef = useRef<HTMLDivElement>(null);

  // Check if chat is locked
  useEffect(() => {
    if (typeof window !== "undefined" && chat) {
      const checkLocked = () => {
        const lockedChats = JSON.parse(localStorage.getItem("dolsyx_locked_chats") || "{}");
        setIsLocked(!!lockedChats[chat.id]);
      };
      
      checkLocked();
      
      window.addEventListener("dolsyx_locked_chats_updated", checkLocked);
      return () => {
        window.removeEventListener("dolsyx_locked_chats_updated", checkLocked);
      };
    }
  }, [chat]);

  // Profile View Modal
  const [showDeleteModal, setShowDeleteModal] = useState(false);
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
        const res = await fetch(`${API_URL}/api/chats/${chat.id}/messages?limit=50`, {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });

        if (res.ok) {
          const data = await res.json();
          
          const finalMessages = await Promise.all(data.map(async (msg: any) => {
            if (msg.content && msg.content.startsWith("{")) {
              try {
                const plaintext = await decryptIncomingContent(msg.content, msg.senderId, chat.id, user?.id);
                // Check if decrypted message is an encrypted media descriptor
                if (plaintext.startsWith("{") && plaintext.endsWith("}")) {
                  try {
                    const parsedMedia = JSON.parse(plaintext);
                    if (parsedMedia.encryptedMedia) {
                      return {
                        ...msg,
                        content: parsedMedia.caption || "",
                        mediaUrl: parsedMedia.mediaUrl || msg.mediaUrl,
                        mediaType: parsedMedia.mediaType || msg.mediaType,
                        mediaKey: parsedMedia.mediaKey,
                        nonce: parsedMedia.nonce,
                        isE2EEMedia: true,
                      };
                    }
                  } catch (_) {}
                }
                return { ...msg, content: plaintext };
              } catch (e) {
                console.warn("Could not decrypt message", e);
              }
            }
            return msg;
          }));

          setMessages(finalMessages);
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

    const handleEncryptedMessage = async (data: { message: any; conversationId: string }) => {
      if (data.conversationId === chat.id && user) {
        try {
          const payload = JSON.parse(data.message.content);
          const plaintext = await decryptIncoming(user.id, payload);
          const decryptedMsg = { ...data.message, content: plaintext };
          
          setMessages((prev) => {
            if (prev.some(m => m.id === decryptedMsg.id)) return prev;
            return [...prev, decryptedMsg];
          });
          
          setIsRecipientTyping(false);
          socket.emit("mark_read", { conversationId: chat.id });
          if (decryptedMsg.senderId !== user?.id) {
            playNotificationSound();
          }
        } catch (err) {
          console.error("Failed to decrypt incoming message:", err);
        }
      }
    };

    const handleNewMessage = async (data: { message: Message; conversationId: string }) => {
      if (data.conversationId === chat.id) {
        let msg = data.message;
        // Avoid duplicate decryption if message ID already exists
        if (msg.id && messages.some(m => m.id === msg.id)) {
          return;
        }

        if (msg.content && msg.content.startsWith("{")) {
          try {
            const plaintext = await decryptIncomingContent(msg.content, msg.senderId, chat.id, user?.id);
            if (plaintext.startsWith("{") && plaintext.endsWith("}")) {
              try {
                const parsedMedia = JSON.parse(plaintext);
                if (parsedMedia.encryptedMedia) {
                  msg = {
                    ...msg,
                    content: parsedMedia.caption || "",
                    mediaUrl: parsedMedia.mediaUrl || msg.mediaUrl,
                    mediaType: parsedMedia.mediaType || msg.mediaType,
                    mediaKey: parsedMedia.mediaKey,
                    nonce: parsedMedia.nonce,
                    isE2EEMedia: true,
                  } as any;
                } else {
                  msg = { ...msg, content: plaintext };
                }
              } catch (_) {
                msg = { ...msg, content: plaintext };
              }
            } else {
              msg = { ...msg, content: plaintext };
            }
          } catch (_) {}
        }

        setMessages((prev) => {
          if (prev.some(m => m.id === msg.id)) return prev;
          
          if (msg.senderId === user?.id) {
            const tempIndex = prev.findIndex(m => 
              m.id.startsWith("temp-") && 
              m.content === msg.content && 
              m.mediaUrl === msg.mediaUrl
            );
            if (tempIndex !== -1) {
              const newMessages = [...prev];
              newMessages[tempIndex] = msg;
              return newMessages;
            }
          }
          return [...prev, msg];
        });
        setIsRecipientTyping(false);
        socket.emit("mark_read", { conversationId: chat.id });
        if (msg.senderId !== user?.id) {
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

    const handleMessageDeleted = (data: { messageId: string; conversationId: string; isDeleted?: boolean; content?: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === data.messageId
              ? {
                  ...msg,
                  isDeleted: true,
                  content: data.content || "This message was deleted",
                  mediaUrl: undefined,
                  mediaType: undefined,
                }
              : msg
          )
        );
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

    const handleReactionAdded = (data: { messageId: string; conversationId: string; userId: string; emoji: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) => prev.map((msg) => {
          if (msg.id === data.messageId) {
            const reactions = msg.reactions || [];
            const existing = reactions.find((r: any) => r.userId === data.userId);
            if (existing) {
              return { ...msg, reactions: reactions.map((r: any) => r.userId === data.userId ? { ...r, emoji: data.emoji } : r) };
            } else {
              return { ...msg, reactions: [...reactions, { userId: data.userId, emoji: data.emoji }] };
            }
          }
          return msg;
        }));
      }
    };

    const handleReactionRemoved = (data: { messageId: string; conversationId: string; userId: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) => prev.map((msg) => {
          if (msg.id === data.messageId) {
            const reactions = msg.reactions || [];
            return { ...msg, reactions: reactions.filter((r: any) => r.userId !== data.userId) };
          }
          return msg;
        }));
      }
    };

    const handlePollUpdated = (data: { conversationId: string; messageId: string; content: string }) => {
      if (data.conversationId === chat.id) {
        setMessages((prev) =>
          prev.map((msg) => (msg.id === data.messageId ? { ...msg, content: data.content } : msg))
        );
      }
    };

    socket.on("receive_encrypted_message", handleEncryptedMessage);
    socket.on("new_message", handleNewMessage);
    socket.on("messages_read", handleMessagesRead);
    socket.on("user_typing", handleUserTyping);
    socket.on("message_edited", handleMessageEdited);
    socket.on("message_deleted", handleMessageDeleted);
    socket.on("message_deleted_for_me", handleMessageDeletedForMe);
    socket.on("chat_cleared", handleChatCleared);
    socket.on("reaction_added", handleReactionAdded);
    socket.on("reaction_removed", handleReactionRemoved);
    socket.on("poll_updated", handlePollUpdated);

    return () => {
      socket.off("receive_encrypted_message", handleEncryptedMessage);
      socket.off("new_message", handleNewMessage);
      socket.off("messages_read", handleMessagesRead);
      socket.off("user_typing", handleUserTyping);
      socket.off("message_edited", handleMessageEdited);
      socket.off("message_deleted", handleMessageDeleted);
      socket.off("message_deleted_for_me", handleMessageDeletedForMe);
      socket.off("chat_cleared", handleChatCleared);
      socket.off("reaction_added", handleReactionAdded);
      socket.off("reaction_removed", handleReactionRemoved);
      socket.off("poll_updated", handlePollUpdated);
    };
  }, [socket, chat, user]);

  const toggleReaction = (messageId: string, emoji: string) => {
    if (!socket || !chat) return;
    
    const message = messages.find(m => m.id === messageId);
    if (!message) return;

    const existingReaction = (message.reactions || []).find((r: any) => r.userId === user?.id);
    
    if (existingReaction && existingReaction.emoji === emoji) {
      socket.emit("remove_reaction", { messageId, conversationId: chat.id });
      // Optimistic update
      setMessages(prev => prev.map(msg => {
        if (msg.id === messageId) {
          return { ...msg, reactions: (msg.reactions || []).filter((r: any) => r.userId !== user?.id) };
        }
        return msg;
      }));
    } else {
      socket.emit("add_reaction", { messageId, conversationId: chat.id, emoji });
      // Optimistic update
      setMessages(prev => prev.map(msg => {
        if (msg.id === messageId) {
          const reactions = msg.reactions || [];
          const filtered = reactions.filter((r: any) => r.userId !== user?.id);
          return { ...msg, reactions: [...filtered, { userId: user?.id, emoji }] };
        }
        return msg;
      }));
    }
  };

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

  const executeDelete = async (deleteType: "me" | "everyone") => {
    if (!socket || !chat || selectedMessageIds.size === 0) return;
    
    for (const msgId of selectedMessageIds) {
      socket.emit("delete_message", {
        messageId: msgId,
        deleteType,
      });
    }

    setShowDeleteModal(false);
    setIsSelectionMode(false);
    setSelectedMessageIds(new Set());
    toast(`Selected messages deleted.`, "success");
  };

  const handleDeleteSelected = () => {
    if (selectedMessageIds.size === 0) return;
    setShowDeleteModal(true);
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.target.value);

    if (!socket || !chat) return;

    if (e.target.value === "") {
      socket.emit("typing", { conversationId: chat.id, isTyping: false });
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
      }
      return;
    }

    // Emit typing status
    socket.emit("typing", { conversationId: chat.id, isTyping: true });

    // Debounce to emit isTyping: false
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    typingTimeoutRef.current = setTimeout(() => {
      socket.emit("typing", { conversationId: chat.id, isTyping: false });
    }, 1000);
  };

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputValue.trim() || !socket || !chat) return;

    if (editingMessage) {
      let encryptedContent = inputValue.trim();
      try {
        encryptedContent = await encryptConversationPayload(chat.id, inputValue.trim());
      } catch (err) {
        console.warn("Conversation E2EE edit encryption error:", err);
      }
      // Send Edit event
      socket.emit("edit_message", {
        messageId: editingMessage.id,
        content: encryptedContent,
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

      // 100% E2EE: Pre-encrypt outgoing message with zero-knowledge ratchet
      let encryptedContent = newMsgContent;
      try {
        encryptedContent = await encryptConversationPayload(chat.id, newMsgContent);
      } catch (err) {
        console.warn("Conversation E2EE encryption error:", err);
      }

      if (socket) {
        socket.emit("send_message", {
          conversationId: chat.id,
          content: encryptedContent,
          parentMessageId: replyingToMessage?.id || undefined,
        });
      }
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
      let stream: MediaStream | null = null;
      try {
        // Try with preferred facing mode first
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: mode }, width: { ideal: 1280 }, height: { ideal: 720 } }
        });
      } catch {
        // Fallback: request any available camera without facing constraint
        stream = await navigator.mediaDevices.getUserMedia({ video: true });
      }
      cameraStreamRef.current = stream;
      setShowCamera(true);
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
      }
    } catch (err: any) {
      console.error("Camera access denied:", err);
      if (err?.name === "NotAllowedError") {
        toast("Camera permission denied. Please allow camera access in your browser settings.", "error");
      } else {
        toast("Could not access camera. Please check permissions.", "error");
      }
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
        if (cameraFacingMode === "user") {
          ctx.translate(canvas.width, 0);
          ctx.scale(-1, 1);
        }
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        
        // Reset transform if needed before extracting data, though not strictly required
        if (cameraFacingMode === "user") {
          ctx.setTransform(1, 0, 0, 1, 0, 0);
        }

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
    return date.toLocaleDateString([], { month: "short", day: "numeric" }) + ", " + date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  const formatLastSeen = (dateString: string) => {
    try {
      const date = new Date(dateString);
      const now = new Date();
      
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      
      const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate());
      const timeStr = date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      
      const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));

      if (dateDay.getTime() === today.getTime()) {
        return `today at ${timeStr}`;
      } else if (dateDay.getTime() === yesterday.getTime()) {
        return `yesterday at ${timeStr}`;
      } else if (diffDays < 7) {
        const weekday = date.toLocaleDateString('en-US', { weekday: 'long' });
        return `${weekday} at ${timeStr}`;
      } else if (now.getFullYear() === date.getFullYear()) {
        const dateStr = date.toLocaleDateString('en-US', { day: 'numeric', month: 'long' });
        return `${dateStr} at ${timeStr}`;
      } else {
        const dateStr = date.toLocaleDateString('en-US', { day: 'numeric', month: 'long', year: 'numeric' });
        return `${dateStr} at ${timeStr}`;
      }
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


  const handleEditSelected = () => {
    if (selectedMessageIds.size !== 1) return;
    const msg = messages.find(m => m.id === Array.from(selectedMessageIds)[0]);
    if (msg && msg.senderId === user?.id) {
      setEditingMessage(msg);
      setInputValue(msg.content);
      setIsSelectionMode(false);
      setSelectedMessageIds(new Set());
    }
  };

  const handleForwardSelected = () => {
    if (selectedMessageIds.size === 0) return;
    const msg = messages.find(m => m.id === Array.from(selectedMessageIds)[0]);
    if (msg) {
      openForwardModal(msg);
      setIsSelectionMode(false);
      setSelectedMessageIds(new Set());
    }
  };

  const handleStarSelected = () => {
    selectedMessageIds.forEach(id => toggleStarMessage(id));
    setIsSelectionMode(false);
    setSelectedMessageIds(new Set());
  };

  const handleShareSelected = () => {
    toast("Share is not supported on this device yet.", "info");
    setIsSelectionMode(false);
    setSelectedMessageIds(new Set());
  };

  return (
    <div className="flex h-full flex-col bg-[#0b141a] relative w-full overflow-hidden">
      {/* Wallpaper rendering logic */}
      {(() => {
        const chatWp = chat ? getWallpaperForChat(chat.id) : null;
        if (chatWp && chatWp.type !== "default") {
          const bgStyle: React.CSSProperties = {
            opacity: chatWp.opacity ?? 0.85,
            filter: (chatWp.blur ?? 0) > 0 ? `blur(${chatWp.blur}px)` : undefined,
          };
          if (chatWp.type === "solid") {
            return (
              <div
                className="absolute inset-0 pointer-events-none z-0 transition-all duration-300"
                style={{ ...bgStyle, backgroundColor: chatWp.value }}
              />
            );
          }
          if (chatWp.type === "pattern") {
            return (
              <div
                className="absolute inset-0 pointer-events-none z-0 transition-all duration-300"
                style={{ ...bgStyle, backgroundImage: chatWp.value }}
              />
            );
          }
          if (chatWp.type === "custom") {
            return (
              <div
                className="absolute inset-0 pointer-events-none z-0 bg-cover bg-center transition-all duration-300"
                style={{ ...bgStyle, backgroundImage: `url(${chatWp.value})` }}
              />
            );
          }
        }

        const wp = CHAT_WALLPAPERS.find(w => w.id === selectedWallpaper) || customWallpapers.find(w => w.id === selectedWallpaper);
        if (!wp || wp.id === "default") {
          return <div className="whatsapp-wallpaper z-0" />;
        }
        if (wp.type === "image") {
          return (
            <div 
              className="absolute inset-0 pointer-events-none opacity-40 z-0 bg-cover bg-center"
              style={{ backgroundImage: `url(${wp.value})` }}
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
        return <div className="whatsapp-wallpaper z-0" />;
      })()}

      {/* Header */}
      {isSelectionMode ? (
        <div className="flex h-[72px] shrink-0 items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-accent)]/10 px-4 sm:px-6 relative z-30">
          <div className="flex items-center gap-3">
            <button
              onClick={() => {
                setIsSelectionMode(false);
                setSelectedMessageIds(new Set());
              }}
              className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)] transition-all cursor-pointer"
            >
              <X className="h-5 w-5" />
            </button>
            <span className="font-bold text-sm text-[var(--theme-text-primary)]">
              {selectedMessageIds.size} selected
            </span>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={handleDeleteSelected} className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-red-400 cursor-pointer" title="Delete">
              <Trash2 className="h-4.5 w-4.5" />
            </button>
            <button onClick={handleForwardSelected} className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)] cursor-pointer" title="Forward">
              <Forward className="h-4.5 w-4.5" />
            </button>
            {selectedMessageIds.size === 1 && (
              <button onClick={handleEditSelected} className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)] cursor-pointer" title="Edit">
                <Edit3 className="h-4.5 w-4.5" />
              </button>
            )}
            <button onClick={handleStarSelected} className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)] cursor-pointer" title="Star">
              <Star className="h-4.5 w-4.5" />
            </button>
            <button onClick={handleShareSelected} className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)] cursor-pointer" title="Share">
              <Share2 className="h-4.5 w-4.5" />
            </button>
          </div>
        </div>
      ) : (
        <div className="flex h-[72px] shrink-0 items-center justify-between border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)]/80 backdrop-blur-md px-4 sm:px-6 relative z-30 select-none">
        <div className="flex items-center gap-4 min-w-0">
          <button
            onClick={onBack}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)]/55 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] sm:hidden transition-all duration-200 cursor-pointer"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>

          {/* Clickable avatar + name → opens profile */}
          <button
            onClick={() => {
              if (chat.isGroup) {
                setShowGroupProfile(true);
              } else {
                setProfileUser(chat.recipient);
              }
            }}
            className={`flex items-center gap-3 min-w-0 text-left cursor-pointer hover:opacity-80 transition-opacity`}
            title={chat.isGroup ? "Group Info" : "View profile"}
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

            <div className="flex flex-col justify-center min-w-0">
              <span className="text-[16px] font-semibold truncate text-[var(--theme-text-primary)] leading-tight">{chat.name}</span>
              <span className="text-[12px] text-[var(--theme-text-secondary)] font-normal leading-tight mt-0.5 truncate flex items-center gap-1">
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
              </span>
            </div>
          </button>
        </div>

        <div className="flex items-center gap-2">
          {/* Audio Call button - always visible for direct chats */}
          {chat && !chat.isGroup && onStartCall && (
            <>
              <button
                onClick={() => onStartCall("audio")}
                className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                title="Voice Call"
              >
                <Phone className="h-5 w-5" />
              </button>
              <button
                onClick={() => onStartCall("video")}
                className="flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
                title="Video Call"
              >
                <Video className="h-5 w-5" />
              </button>
            </>
          )}
          
          {/* 3-dots menu — contains all other options */}
          <div className="relative" ref={headerMenuRef}>
            <button
              onClick={() => setShowHeaderMenu((v) => !v)}
              className={`flex h-9 w-9 items-center justify-center rounded-xl transition-all cursor-pointer ${
                showHeaderMenu
                  ? "bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)]"
                  : "text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:text-[var(--theme-text-primary)]"
              }`}
              title="More Options"
            >
              <MoreVertical className="h-4 w-4" />
            </button>

            {showHeaderMenu && (
              <div className="absolute right-0 top-11 z-50 w-52 rounded-xl border border-[var(--theme-border-color)] bg-[#111b21] p-1.5 shadow-2xl animate-fade-in text-left">
                {!chat.isGroup && (
                  <button
                    onMouseDown={(e) => {
                      e.preventDefault();
                      setProfileUser(chat.recipient);
                      setShowHeaderMenu(false);
                    }}
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-slate-200 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                  >
                    <User className="h-3.5 w-3.5" />
                    View Profile
                  </button>
                )}
                {chat.isGroup && (
                  <button
                    onMouseDown={(e) => {
                      e.preventDefault();
                      setShowGroupProfile(true);
                      setShowHeaderMenu(false);
                    }}
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-slate-200 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                  >
                    <Users className="h-3.5 w-3.5" />
                    Group Info
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
                      : "text-slate-200 hover:bg-[var(--theme-bg-sidebar-item-hover)]"
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
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-slate-200 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
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
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-slate-200 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors cursor-pointer"
                >
                  <ImageIcon className="h-3.5 w-3.5" />
                  Chat Wallpaper
                </button>
                <button
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setShowHeaderMenu(false);
                    if (isLocked) {
                      window.dispatchEvent(new CustomEvent("dolsyx_unlock_chat", { detail: { chatId: chat.id } }));
                    } else {
                      window.dispatchEvent(new CustomEvent("dolsyx_open_lock_modal", { detail: { chatId: chat.id } }));
                    }
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs font-semibold text-cyan-400 hover:bg-cyan-400/10 transition-colors cursor-pointer"
                >
                  <Lock className="h-3.5 w-3.5" />
                  {isLocked ? "Unlock Chat" : "Lock Chat"}
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
      )}

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
                  onContextMenu={(e) => {
                    e.preventDefault();
                    if (!isSelectionMode && !isMsgDeleted) {
                      setIsSelectionMode(true);
                      setSelectedMessageIds(new Set([msg.id]));
                    }
                  }}
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
                          {msg.parentMessage.sender?.username || (msg.parentMessage.sender as any)?.name || "User"}
                        </span>
                        {getQuotedParentPreviewText(msg.parentMessage)}
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
                    ) : msg.mediaType === "POLL" || (typeof msg.content === "string" && (msg.content.includes('"question":') || msg.content.includes('"mediaType":"POLL"'))) ? (
                      <PollMessage msg={msg} isMe={isMe} socket={socket} user={user} />
                    ) : msg.mediaType === "LOCATION" || (typeof msg.content === "string" && (msg.content.includes('"latitude":') || msg.content.includes('"mediaType":"LOCATION"'))) ? (
                      <LocationMessage msg={msg} isMe={isMe} />
                    ) : msg.mediaType === "IMAGE" ? (
                      <div className="flex flex-col space-y-1">
                        <div className="relative max-w-md rounded-2xl overflow-hidden border border-zinc-800 bg-zinc-900 shadow-md">
                          <DecryptedImage
                            mediaUrl={msg.mediaUrl || ""}
                            mediaKey={(msg as any).mediaKey}
                            nonce={(msg as any).nonce}
                            isE2EEMedia={(msg as any).isE2EEMedia}
                            alt={msg.content || "Image attachment"}
                            className="w-full max-h-96 object-cover cursor-pointer hover:opacity-90 transition-opacity"
                          />
                          {formatMediaBytes((msg as any).fileSize || (msg as any).size) && (
                            <div className="absolute bottom-2 left-2 flex items-center gap-1.5 px-3 py-1 rounded-full bg-black/60 backdrop-blur-sm text-[12px] font-bold text-white shadow">
                              <Download className="h-3.5 w-3.5 text-white" />
                              <span>{formatMediaBytes((msg as any).fileSize || (msg as any).size)}</span>
                            </div>
                          )}
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
                        <div className="relative max-w-xs rounded-2xl overflow-hidden border border-zinc-800 bg-black shadow-md">
                          <DecryptedVideo
                            mediaUrl={msg.mediaUrl || ""}
                            mediaKey={(msg as any).mediaKey}
                            nonce={(msg as any).nonce}
                            isE2EEMedia={(msg as any).isE2EEMedia}
                            fileName={msg.fileName || "video.mp4"}
                            className="w-full max-h-72 object-contain bg-black rounded-2xl"
                          />
                          {formatMediaBytes((msg as any).fileSize || (msg as any).size) && (
                            <div className="absolute top-2 right-2 flex items-center gap-1.5 px-3 py-1 rounded-full bg-black/60 backdrop-blur-sm text-[12px] font-bold text-white shadow pointer-events-none">
                              <Download className="h-3.5 w-3.5 text-white" />
                              <span>{formatMediaBytes((msg as any).fileSize || (msg as any).size)}</span>
                            </div>
                          )}
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
                            {msg.fileName || msg.content || "Attachment"}
                          </p>
                          <p className="text-[11px] text-zinc-400">
                            {formatMediaBytes((msg as any).fileSize || (msg as any).size)
                              ? `${formatMediaBytes((msg as any).fileSize || (msg as any).size)} • Document`
                              : "File Attachment"}
                          </p>
                        </div>
                        <a
                          href={resolveMediaUrl(msg.mediaUrl) || ""}
                          download={msg.fileName || msg.content || "download"}
                          target="_blank"
                          rel="noreferrer"
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700 transition-colors text-[12px] font-bold"
                        >
                          <Download className="h-3.5 w-3.5" />
                          {formatMediaBytes((msg as any).fileSize || (msg as any).size) && (
                            <span>{formatMediaBytes((msg as any).fileSize || (msg as any).size)}</span>
                          )}
                        </a>
                      </div>
                    ) : emojiOnly ? (
                      /* Big interactive emoji-only messages */
                      <div className="select-none py-1 flex items-center gap-1.5 flex-wrap">
                        {(() => {
                          const count = getEmojiCount(msg.content);
                          const size = count === 1 ? "large" : count <= 3 ? "medium" : "inline";
                          let emojis: string[] = [];
                          if (typeof Intl !== 'undefined' && Intl.Segmenter) {
                            const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });
                            emojis = Array.from(segmenter.segment(msg.content.trim().replace(/\s/g, ''))).map(s => s.segment);
                          } else {
                            emojis = Array.from(msg.content.trim().replace(/\s/g, ''));
                          }
                          return emojis.map((emo, idx) => (
                            <AnimatedEmoji
                              key={`${msg.id}-emo-${idx}`}
                              emoji={emo}
                              size={size}
                              interactive={true}
                            />
                          ));
                        })()}
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
                    
                    {/* Reactions */}
                    {msg.reactions && msg.reactions.length > 0 && (
                      <div className={`absolute -bottom-3 ${isMe ? "right-1" : "left-1"} flex flex-wrap gap-1 z-10`}>
                        {Array.from(new Set(msg.reactions.map(r => r.emoji))).map(emoji => (
                          <div 
                            key={emoji} 
                            onClick={(e) => {
                              e.stopPropagation();
                              toggleReaction(msg.id, emoji as string);
                            }}
                            className="bg-zinc-850/95 hover:bg-zinc-750 border border-zinc-700/60 rounded-full px-2 py-0.5 text-xs shadow-md cursor-pointer transition-all duration-150 hover:scale-105 active:scale-95 flex items-center gap-1 backdrop-blur-sm"
                            title={`Reaction: ${emoji}`}
                          >
                            <AnimatedEmoji
                              emoji={emoji as string}
                              size="reaction"
                              interactive={false}
                            />
                            {msg.reactions!.filter(r => r.emoji === emoji).length > 1 && (
                              <span className="text-[10px] text-zinc-300 font-semibold tracking-tight">
                                {msg.reactions!.filter(r => r.emoji === emoji).length}
                              </span>
                            )}
                          </div>
                        ))}
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
                    <div className="relative">
                      <button
                        onClick={() => setActiveReactionMessageId(activeReactionMessageId === msg.id ? null : msg.id)}
                        className="p-1 text-zinc-400 hover:text-white hover:bg-zinc-900 rounded-lg transition-colors cursor-pointer"
                        title="React"
                      >
                        <Smile className="h-3.5 w-3.5" />
                      </button>
                      {activeReactionMessageId === msg.id && (
                        <ReactionPopup
                          onSelect={(emoji) => toggleReaction(msg.id, emoji)}
                          onClose={() => setActiveReactionMessageId(null)}
                        />
                      )}
                    </div>
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
              <form onSubmit={handleSendMessage} className="p-2 sm:px-4 sm:py-3 relative animate-fade-in bg-transparent">
                <div className="flex items-center gap-2 sm:gap-3 py-1">
                  {/* Cylinder wrapper */}
                  <div className="flex-1 min-w-0 flex items-center px-0.5 sm:px-1 py-0.5 sm:py-1 relative transition-all min-h-[44px] sm:min-h-[48px]">
                    
                    {/* Emoji Button inside cylinder */}
                    <div className="relative shrink-0" ref={emojiPickerRef}>
                      <button
                        type="button"
                        disabled={isRecording}
                        onClick={() => {
                          if (showEmojiPicker) {
                            setShowEmojiPicker(false);
                            inputRef.current?.focus();
                          } else {
                            setShowEmojiPicker(true);
                            inputRef.current?.blur();
                          }
                        }}
                        className={`flex h-8 w-8 sm:h-10 sm:w-10 items-center justify-center rounded-full transition-all duration-200 cursor-pointer ${
                          showEmojiPicker
                            ? "text-[var(--theme-accent)] bg-[var(--theme-accent)]/10"
                            : "text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)]"
                        }`}
                        title="Emoji"
                      >
                        {showEmojiPicker ? <span className="text-xl leading-none font-bold">⌨️</span> : <Smile className="h-5 w-5 sm:h-6 sm:w-6" />}
                      </button>
                    </div>

                    {/* Input Field or Recording State */}
                    {isRecording ? (
                      <div className="flex-1 flex items-center justify-between px-3 h-full">
                        <div className="flex items-center gap-2 text-red-500 animate-pulse">
                          <Mic className="h-5 w-5" />
                          <span className="text-[16px] font-semibold text-red-400">
                            {Math.floor(recordingDuration / 60)}:{(recordingDuration % 60).toString().padStart(2, '0')}
                          </span>
                        </div>
                        <button
                          type="button"
                          onClick={stopRecording}
                          className="rounded-full bg-red-500 p-1.5 text-white hover:bg-red-600 cursor-pointer transition-colors"
                        >
                          <Square className="h-4 w-4" fill="currentColor" />
                        </button>
                      </div>
                    ) : (
                      <input
                        type="text"
                        ref={inputRef}
                        value={inputValue}
                        onChange={handleInputChange}
                        onFocus={() => setShowEmojiPicker(false)}
                        placeholder={editingMessage ? "Edit your message..." : "Message"}
                        className="flex-1 min-w-0 bg-transparent px-3 py-2 text-[16px] text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)] focus:outline-none transition-all duration-200 h-full"
                      />
                    )}

                    {/* Right-side Icons inside cylinder */}
                    {!isRecording && (
                      <div className="flex items-center gap-0.5 sm:gap-1 pr-0.5 sm:pr-1 shrink-0 overflow-x-auto no-scrollbar max-w-[50%] sm:max-w-none">
                        <button
                          type="button"
                          disabled={isUploadingFile}
                          onClick={() => fileInputRef.current?.click()}
                          className="flex h-8 w-8 sm:h-10 sm:w-10 items-center justify-center rounded-full text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all duration-200 cursor-pointer disabled:opacity-50"
                          title="Attach File"
                        >
                          {isUploadingFile ? (
                            <Loader2 className="h-5 w-5 animate-spin text-[var(--theme-accent)]" />
                          ) : (
                            <Paperclip className="h-5 w-5 -rotate-45" />
                          )}
                        </button>
                        
                        <button
                          type="button"
                          disabled={isRecording}
                          className="hidden sm:flex h-8 w-8 sm:h-10 sm:w-10 items-center justify-center rounded-full text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all duration-200 cursor-pointer disabled:opacity-50"
                          title="Payment"
                        >
                          <div className="h-5 w-5 rounded-full border-[1.5px] border-current flex items-center justify-center">
                            <IndianRupee className="h-3 w-3" />
                          </div>
                        </button>

                        <button
                          type="button"
                          disabled={isRecording}
                          onClick={() => startCamera()}
                          className="flex h-8 w-8 sm:h-10 sm:w-10 items-center justify-center rounded-full text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all duration-200 cursor-pointer disabled:opacity-50"
                          title="Camera"
                        >
                          <Camera className="h-5 w-5" />
                        </button>
                      </div>
                    )}
                  </div>

                  {/* Mic / Send Button (Outside) */}
                  {!inputValue.trim() && !isRecording ? (
                    <button
                      type="button"
                      onClick={startRecording}
                      className="flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-full bg-[#111b21] hover:bg-[#202c33] border border-[var(--theme-border-color)] text-white shadow-lg transition-all duration-200 cursor-pointer"
                      title="Hold or Click to Record"
                    >
                      <Mic className="h-5 w-5 sm:h-6 sm:w-6" />
                    </button>
                  ) : (
                    <button
                      type="submit"
                      disabled={isRecording || !inputValue.trim()}
                      className="flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-full text-white shadow-lg hover:opacity-95 transition-all duration-200 cursor-pointer disabled:opacity-50 animate-fade-in"
                      style={{
                        background: "linear-gradient(to top right, #0097a7, #00d4ff)"
                      }}
                    >
                      <Send className="h-5 w-5 ml-1" />
                    </button>
                  )}
                </div>
              </form>
            )}

            {/* Docked Emoji Picker beneath input bar */}
            {showEmojiPicker && (
              <div className="w-full bg-[var(--theme-bg-chat-input)] border-t border-[var(--theme-border-color)]/20 animate-fade-in flex justify-center pb-2">
                <EmojiPicker
                  onEmojiClick={(emojiData) => {
                    onEmojiClick(emojiData);
                  }}
                  theme={(theme === "aqua-light" ? "light" : "dark") as Theme}
                  width="100%"
                  height={300}
                  searchPlaceholder="Search emoji..."
                  autoFocusSearch={false}
                  previewConfig={{ showPreview: false }}
                />
              </div>
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

      {/* Android-Parity Wallpaper Customization Modal */}
      <WallpaperModal
        isOpen={showWallpaperPicker}
        onClose={() => setShowWallpaperPicker(false)}
        conversationId={chat?.id}
        conversationName={chat?.name}
      />

      {/* Generic Profile View – Full Screen */}
      {profileUser && (
        <div className="fixed inset-0 z-[9999] flex flex-col bg-black animate-fade-in overflow-y-auto">
          {/* Top bar */}
          <div className="flex items-center justify-between px-4 py-4 shrink-0 bg-[var(--theme-bg-sidebar)]/80 backdrop-blur-md border-b border-[var(--theme-border-color)]">
            <button
              onClick={() => setProfileUser(null)}
              className="flex items-center gap-2 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer"
            >
              <ArrowLeft className="h-5 w-5" />
              <span className="text-sm font-semibold">Back</span>
            </button>
            <span className="text-sm font-bold text-[var(--theme-text-primary)]">Contact Info</span>
            <div className="w-16" />
          </div>

          {/* Hero avatar section */}
          <div
            className="relative flex flex-col items-center justify-center py-12 px-6 cursor-pointer bg-[var(--theme-bg-sidebar)]"
            onClick={() => window.open(getAvatarUrl(profileUser.avatarUrl, profileUser.username), "_blank")}
          >
            <div className="relative z-10 flex flex-col items-center gap-4">
              <img
                src={getAvatarUrl(profileUser.avatarUrl, profileUser.username)}
                alt={profileUser.username}
                className="h-48 w-48 rounded-full border-4 border-white/20 object-cover shadow-2xl"
              />
              {onlineUsers.includes(profileUser.id) && (
                <span className="absolute bottom-4 right-0 h-6 w-6 rounded-full border-4 border-[var(--theme-bg-app)] bg-green-500 shadow-lg" />
              )}
              <div className="text-center">
                <h2 className="text-2xl font-black text-[var(--theme-text-primary)]">{profileUser.username}</h2>
                <p className="text-sm mt-1">
                  {onlineUsers.includes(profileUser.id) ? (
                    <span className="text-green-400 font-semibold flex items-center justify-center gap-1">
                      <span className="h-2 w-2 rounded-full bg-green-400 animate-pulse inline-block" /> Online
                    </span>
                  ) : profileUser.lastSeen ? (
                    <span className="text-[var(--theme-text-secondary)]">Last seen {formatLastSeen(profileUser.lastSeen)}</span>
                  ) : (
                    <span className="text-[var(--theme-text-secondary)]">Offline</span>
                  )}
                </p>
              </div>
            </div>
          </div>

          {/* Call Actions */}
          {onStartCall && profileUser.id !== user?.id && (
            <div className="flex justify-center gap-6 pb-6 px-4">
              <button
                onClick={() => {
                  setProfileUser(null);
                  onStartCall("audio");
                }}
                className="flex flex-col items-center gap-2 group cursor-pointer"
              >
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[var(--theme-accent)]/10 text-[var(--theme-accent)] group-hover:bg-[var(--theme-accent)]/20 transition-colors">
                  <Phone className="h-5 w-5" />
                </div>
                <span className="text-xs font-bold text-[var(--theme-text-secondary)] group-hover:text-[var(--theme-accent)] transition-colors">Voice</span>
              </button>
              <button
                onClick={() => {
                  setProfileUser(null);
                  onStartCall("video");
                }}
                className="flex flex-col items-center gap-2 group cursor-pointer"
              >
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[var(--theme-accent)]/10 text-[var(--theme-accent)] group-hover:bg-[var(--theme-accent)]/20 transition-colors">
                  <Video className="h-5 w-5" />
                </div>
                <span className="text-xs font-bold text-[var(--theme-text-secondary)] group-hover:text-[var(--theme-accent)] transition-colors">Video</span>
              </button>
            </div>
          )}

          {/* Info Cards */}
          <div className="flex flex-col gap-4 px-4 pb-10 max-w-lg w-full mx-auto">
            {/* About */}
            <div className="rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] overflow-hidden">
              <div className="px-4 py-3 border-b border-[var(--theme-border-color)]">
                <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)]">About</span>
              </div>
              <div className="px-4 py-4">
                <p className="text-sm text-[var(--theme-text-primary)] leading-relaxed">
                  {profileUser.bio || "Hey there! I am using DOLSYX."}
                </p>
              </div>
            </div>

            {/* Contact Info */}
            {(profileUser.email || profileUser.phoneNumber) && (
              <div className="rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] overflow-hidden">
                <div className="px-4 py-3 border-b border-[var(--theme-border-color)]">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)]">Contact</span>
                </div>
                <div className="px-4 py-4 space-y-3">
                  {profileUser.email && (
                    <div className="flex items-center gap-3">
                      <Mail className="h-4 w-4 text-[var(--theme-accent)] shrink-0" />
                      <span className="text-sm text-[var(--theme-text-primary)] truncate">{profileUser.email}</span>
                    </div>
                  )}
                  {profileUser.phoneNumber && (
                    <div className="flex items-center gap-3">
                      <Phone className="h-4 w-4 text-[var(--theme-accent)] shrink-0" />
                      <span className="text-sm text-[var(--theme-text-primary)]">{profileUser.phoneNumber}</span>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Actions */}
            {user?.id !== profileUser.id && (
              <button
                type="button"
                onClick={() => handleToggleBlock(profileUser.id)}
                className={`w-full flex items-center justify-center gap-2 rounded-2xl py-3.5 text-sm font-bold transition-all cursor-pointer border ${
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
      )}

      {/* Group Profile Modal */}
      {showGroupProfile && (
        <GroupProfileModal
          chat={chat}
          onClose={() => setShowGroupProfile(false)}
          onlineUsers={onlineUsers}
        />
      )}
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

      {/* Delete Modal */}
      {showDeleteModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/60 px-4 animate-fade-in backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-[var(--theme-bg-sidebar)] p-6 shadow-2xl border border-[var(--theme-border-color)]">
            <h3 className="text-lg font-bold text-[var(--theme-text-primary)] mb-2">Delete message?</h3>
            <p className="text-sm text-[var(--theme-text-secondary)] mb-6">
              This action cannot be undone.
            </p>
            <div className="flex flex-col gap-3">
              {Array.from(selectedMessageIds).every((id) => {
                const msg = messages.find((m) => m.id === id);
                return msg && msg.senderId === user?.id;
              }) && (
                <button
                  onClick={() => executeDelete("everyone")}
                  className="w-full py-3 rounded-xl bg-red-500/10 text-red-500 font-bold hover:bg-red-500/20 transition-all cursor-pointer border border-red-500/20"
                >
                  Delete for everyone
                </button>
              )}
              <button
                onClick={() => executeDelete("me")}
                className="w-full py-3 rounded-xl bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] font-bold hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer border border-[var(--theme-border-color)]"
              >
                Delete for me
              </button>
              <button
                onClick={() => setShowDeleteModal(false)}
                className="w-full py-3 rounded-xl font-bold text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer mt-1"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
