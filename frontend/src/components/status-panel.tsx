"use client";

import React, { useState, useEffect, useRef } from "react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { useToast } from "@/context/toast-context";
import { useSocket } from "@/hooks/use-socket";
import { getDefaultAvatar, getAvatarUrl, resolveMediaUrl } from "@/utils/avatar";
import {
  X,
  Plus,
  Camera,
  Image as ImageIcon,
  Video,
  Type,
  Trash2,
  Eye,
  ChevronLeft,
  ChevronRight,
  Loader2,
  Upload,
} from "lucide-react";

interface StatusItem {
  id: string;
  userId: string;
  mediaUrl: string | null;
  mediaType: "TEXT" | "IMAGE" | "VIDEO";
  caption: string | null;
  bgColor: string | null;
  createdAt: string;
  expiresAt: string;
  isViewed: boolean;
  views: { viewerId: string; viewedAt: string }[];
  user: { id: string; username: string; avatarUrl: string | null };
}

interface StatusGroup {
  user: { id: string; username: string; avatarUrl: string | null };
  statuses: StatusItem[];
  hasUnread: boolean;
}

interface StatusPanelProps {
  onClose: () => void;
  onNewStatus?: (status: StatusItem) => void;
}

const TEXT_BG_COLORS = [
  "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
  "linear-gradient(135deg, #f093fb 0%, #f5576c 100%)",
  "linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)",
  "linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)",
  "linear-gradient(135deg, #fa709a 0%, #fee140 100%)",
  "linear-gradient(135deg, #a18cd1 0%, #fbc2eb 100%)",
  "linear-gradient(135deg, #fccb90 0%, #d57eeb 100%)",
  "linear-gradient(135deg, #fd7043 0%, #ffa726 100%)",
];

export default function StatusPanel({ onClose, onNewStatus }: StatusPanelProps) {
  const { user, token } = useAuth();
  const { theme } = useTheme();
  const { toast } = useToast();
  const { socket } = useSocket(token);

  const [statusGroups, setStatusGroups] = useState<StatusGroup[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Story viewer state
  const [viewingGroup, setViewingGroup] = useState<StatusGroup | null>(null);
  const [viewingIndex, setViewingIndex] = useState(0);
  const [storyProgress, setStoryProgress] = useState(0);
  const progressTimer = useRef<NodeJS.Timeout | null>(null);

  // Create status state
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [createType, setCreateType] = useState<"TEXT" | "IMAGE" | "VIDEO">("TEXT");
  const [captionText, setCaptionText] = useState("");
  const [selectedBgIndex, setSelectedBgIndex] = useState(0);
  const [mediaFile, setMediaFile] = useState<File | null>(null);
  const [mediaPreview, setMediaPreview] = useState<string>("");
  const [isUploading, setIsUploading] = useState(false);
  const [isPosting, setIsPosting] = useState(false);
  const [showViewsList, setShowViewsList] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Fetch statuses
  const fetchStatuses = async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/status`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setStatusGroups(data);
      }
    } catch (e) {
      console.error("Fetch statuses error:", e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchStatuses();
  }, [token]);

  // Listen to new status socket updates
  useEffect(() => {
    if (!socket) return;
    const handleNewStatus = () => {
      fetchStatuses();
    };
    socket.on("new_status", handleNewStatus);
    return () => {
      socket.off("new_status", handleNewStatus);
    };
  }, [socket]);

  const goNextStory = () => {
    if (!viewingGroup) return;
    if (viewingIndex < viewingGroup.statuses.length - 1) {
      setViewingIndex((i) => i + 1);
    } else {
      setViewingGroup(null);
    }
  };

  // Story progress timer
  useEffect(() => {
    if (!viewingGroup) return;
    if (showViewsList) {
      if (progressTimer.current) clearInterval(progressTimer.current);
      return;
    }
    setStoryProgress(0);
    if (progressTimer.current) clearInterval(progressTimer.current);

    const currentStatus = viewingGroup.statuses[viewingIndex];
    // Video status can play up to 60 seconds, text/image for 5 seconds
    const duration = currentStatus?.mediaType === "VIDEO" ? 60000 : 5000;
    const tick = 100;

    progressTimer.current = setInterval(() => {
      setStoryProgress((prev) => {
        if (prev >= 100) {
          // Auto-advance
          goNextStory();
          return 0;
        }
        return prev + (tick / duration) * 100;
      });
    }, tick);

    // Mark as viewed
    if (currentStatus && token) {
      fetch(`${API_URL}/api/status/${currentStatus.id}/view`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      }).catch(() => {});
    }

    return () => {
      if (progressTimer.current) clearInterval(progressTimer.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewingGroup, viewingIndex, showViewsList]);

  const openGroup = (group: StatusGroup) => {
    setViewingGroup(group);
    setViewingIndex(0);
  };

  const goPrevStory = () => {
    if (!viewingGroup) return;
    if (viewingIndex > 0) {
      setViewingIndex((i) => i - 1);
    }
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.type.startsWith("video/")) {
      const video = document.createElement("video");
      video.preload = "metadata";
      video.src = URL.createObjectURL(file);
      video.onloadedmetadata = () => {
        URL.revokeObjectURL(video.src);
        if (video.duration > 60) {
          toast("Video status must be under 60 seconds.", "error");
          e.target.value = "";
          return;
        }
        setMediaFile(file);
        setMediaPreview(video.src);
        setCreateType("VIDEO");
      };
    } else {
      setMediaFile(file);
      const url = URL.createObjectURL(file);
      setMediaPreview(url);
      setCreateType("IMAGE");
    }
  };

  const handlePostStatus = async () => {
    if (!token) return;
    setIsPosting(true);
    try {
      let mediaUrl: string | null = null;
      let mediaType = createType;

      if (mediaFile) {
        setIsUploading(true);
        const fd = new FormData();
        fd.append("file", mediaFile);
        const uploadRes = await fetch(`${API_URL}/api/status/upload`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body: fd,
        });
        if (!uploadRes.ok) throw new Error("Upload failed");
        const uploadData = await uploadRes.json();
        // Store relative path instead of absolute URL
        mediaUrl = uploadData.fileUrl;
        mediaType = uploadData.fileType.startsWith("video/") ? "VIDEO" : "IMAGE";
        setIsUploading(false);
      }

      const body: any = { mediaType };
      if (mediaUrl) body.mediaUrl = mediaUrl;
      if (captionText.trim()) body.caption = captionText.trim();
      if (createType === "TEXT") {
        body.bgColor = TEXT_BG_COLORS[selectedBgIndex];
      }

      const res = await fetch(`${API_URL}/api/status`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      if (res.ok) {
        const newStatus = await res.json();
        if (onNewStatus) onNewStatus(newStatus);
        setShowCreateModal(false);
        setCaptionText("");
        setMediaFile(null);
        setMediaPreview("");
        setCreateType("TEXT");
        fetchStatuses();
      }
    } catch (e) {
      console.error("Post status error:", e);
      toast("Failed to post status", "error");
    } finally {
      setIsPosting(false);
      setIsUploading(false);
    }
  };

  const handleDeleteStatus = async (statusId: string) => {
    if (!token) return;
    if (!confirm("Delete this status?")) return;
    try {
      const res = await fetch(`${API_URL}/api/status/${statusId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setViewingGroup(null);
        fetchStatuses();
      }
    } catch (e) {
      console.error("Delete status error:", e);
    }
  };

  const myGroup = statusGroups.find((g) => g.user.id === user?.id);
  const contactGroups = statusGroups.filter((g) => g.user.id !== user?.id);

  const formatTimeAgo = (dateStr: string) => {
    const diff = Date.now() - new Date(dateStr).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    return `${hrs}h ago`;
  };

  const currentStatus = viewingGroup?.statuses[viewingIndex];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-0 sm:p-4 animate-fade-in">

      {/* Story Viewer Overlay */}
      {viewingGroup && currentStatus && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black">
          {/* Progress bars */}
          <div className="absolute top-4 left-4 right-4 flex gap-1 z-10">
            {viewingGroup.statuses.map((_, i) => (
              <div key={i} className="flex-1 h-0.5 bg-white/30 rounded-full overflow-hidden">
                <div
                  className="h-full bg-white rounded-full transition-none"
                  style={{
                    width: i < viewingIndex ? "100%" : i === viewingIndex ? `${storyProgress}%` : "0%",
                  }}
                />
              </div>
            ))}
          </div>

          {/* Header */}
          <div className="absolute top-8 left-4 right-4 flex items-center justify-between z-10">
            <div className="flex items-center gap-3">
              <img
                src={getAvatarUrl(viewingGroup.user.avatarUrl, viewingGroup.user.username)}
                alt={viewingGroup.user.username}
                className="h-10 w-10 rounded-full border-2 border-white"
              />
              <div>
                <p className="text-white font-bold text-sm">{viewingGroup.user.username}</p>
                <p className="text-white/60 text-xs">{formatTimeAgo(currentStatus.createdAt)}</p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {viewingGroup.user.id === user?.id && (
                <button
                  onClick={() => handleDeleteStatus(currentStatus.id)}
                  className="p-2 text-white/70 hover:text-red-400 transition-colors"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              )}
              <button onClick={() => setViewingGroup(null)} className="p-2 text-white">
                <X className="h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Media Content */}
          <div className="w-full h-full flex items-center justify-center">
            {currentStatus.mediaType === "IMAGE" && currentStatus.mediaUrl ? (
              <img
                src={resolveMediaUrl(currentStatus.mediaUrl)}
                alt="Status"
                className="max-w-full max-h-full object-contain"
              />
            ) : currentStatus.mediaType === "VIDEO" && currentStatus.mediaUrl ? (
              <video
                key={currentStatus.id}
                src={resolveMediaUrl(currentStatus.mediaUrl)}
                autoPlay
                playsInline
                muted={false}
                controls={false}
                className="max-w-full max-h-full object-contain"
                onEnded={goNextStory}
              />
            ) : (
              <div
                className="w-full h-full flex items-center justify-center px-8 text-center"
                style={{ background: currentStatus.bgColor || "linear-gradient(135deg, #667eea 0%, #764ba2 100%)" }}
              >
                <p className="text-white text-2xl font-bold leading-snug drop-shadow-lg">
                  {currentStatus.caption}
                </p>
              </div>
            )}
          </div>

          {/* Caption overlay for media statuses */}
          {currentStatus.mediaType !== "TEXT" && currentStatus.caption && (
            <div className="absolute bottom-16 left-0 right-0 px-6 text-center">
              <p className="text-white text-base font-semibold drop-shadow-lg bg-black/30 rounded-xl px-4 py-2 inline-block">
                {currentStatus.caption}
              </p>
            </div>
          )}

          {/* Views count for own status */}
          {viewingGroup.user.id === user?.id && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                setShowViewsList(true);
              }}
              className="absolute bottom-6 left-6 flex items-center gap-1.5 text-white bg-black/50 hover:bg-black/75 px-3 py-1.5 rounded-full text-xs font-semibold transition-colors z-20 cursor-pointer shadow-md"
            >
              <Eye className="h-4 w-4 text-[var(--theme-accent)]" />
              <span>{currentStatus.views.length} View{currentStatus.views.length !== 1 ? "s" : ""}</span>
            </button>
          )}

          {/* Viewer List Drawer */}
          {showViewsList && (
            <div className="absolute inset-x-0 bottom-0 max-h-[50%] bg-[var(--theme-bg-sidebar)] border-t border-[var(--theme-border-color)] rounded-t-2xl flex flex-col z-30 animate-slide-up shadow-2xl p-4">
              <div className="flex items-center justify-between border-b border-[var(--theme-border-color)] pb-3 mb-3">
                <span className="text-sm font-bold text-[var(--theme-text-primary)]">Views ({currentStatus.views.length})</span>
                <button
                  onClick={() => setShowViewsList(false)}
                  className="p-1 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] cursor-pointer"
                >
                  <X className="h-4.5 w-4.5" />
                </button>
              </div>
              <div className="flex-1 overflow-y-auto space-y-3 pr-1 text-left">
                {currentStatus.views.length === 0 ? (
                  <div className="text-center py-6 text-xs text-[var(--theme-text-secondary)]">
                    No views yet
                  </div>
                ) : (
                  currentStatus.views.map((v: any, index: number) => (
                    <div key={index} className="flex items-center justify-between py-1 border-b border-[var(--theme-border-color)]/20 last:border-0">
                      <div className="flex items-center gap-3">
                        <img
                          src={getAvatarUrl(v.viewer?.avatarUrl, v.viewer?.username || "Viewer")}
                          alt={v.viewer?.username || "Viewer"}
                          className="h-8 w-8 rounded-full object-cover border border-[var(--theme-border-color)]"
                        />
                        <div>
                          <p className="text-xs font-bold text-[var(--theme-text-primary)]">
                            {v.viewer?.username || "Anonymous Viewer"}
                          </p>
                          <p className="text-[9px] text-[var(--theme-text-secondary)]">
                            {new Date(v.viewedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </p>
                        </div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}

          {/* Tap areas */}
          <button onClick={goPrevStory} className="absolute left-0 top-0 w-1/3 h-full z-10" />
          <button onClick={goNextStory} className="absolute right-0 top-0 w-1/3 h-full z-10" />
        </div>
      )}

      {/* Main Status Panel */}
      <div className="w-full max-w-md h-[85vh] max-h-[700px] rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl flex flex-col overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--theme-border-color)]">
          <h2 className="text-lg font-bold text-[var(--theme-text-primary)]">Status</h2>
          <button onClick={onClose} className="p-1 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-6 w-6 animate-spin text-[var(--theme-accent)]" />
            </div>
          ) : (
            <>
              {/* My Status */}
              <div className="px-4 pt-4 pb-2">
                <p className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase tracking-wider mb-2">My Status</p>
                <div className="flex items-center gap-4">
                  {/* Add Status Button */}
                  <button
                    onClick={() => setShowCreateModal(true)}
                    className="flex flex-col items-center gap-1.5 group cursor-pointer"
                  >
                    <div className="relative">
                      <div className={`h-14 w-14 rounded-full flex items-center justify-center border-2 ${
                        myGroup ? "border-[var(--theme-accent)]" : "border-dashed border-[var(--theme-border-color)]"
                      } bg-[var(--theme-bg-sidebar-search)] group-hover:border-[var(--theme-accent)] transition-all`}>
                        {myGroup ? (
                          <img
                            src={getAvatarUrl(user?.avatarUrl, user?.username || "U")}
                            alt="My status"
                            className="h-full w-full rounded-full object-cover"
                          />
                        ) : (
                          <Plus className="h-6 w-6 text-[var(--theme-text-secondary)] group-hover:text-[var(--theme-accent)] transition-colors" />
                        )}
                      </div>
                      <div className="absolute -bottom-0.5 -right-0.5 h-5 w-5 rounded-full bg-[var(--theme-accent)] flex items-center justify-center border-2 border-[var(--theme-bg-sidebar)]">
                        <Plus className="h-3 w-3 text-white" />
                      </div>
                    </div>
                    <span className="text-[10px] text-[var(--theme-text-secondary)] group-hover:text-[var(--theme-accent)] transition-colors">
                      {myGroup ? "My Status" : "Add Status"}
                    </span>
                  </button>

                  {/* View own statuses */}
                  {myGroup && (
                    <button
                      onClick={() => openGroup(myGroup)}
                      className="flex-1 flex items-center gap-3 rounded-xl px-3 py-2.5 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors text-left cursor-pointer"
                    >
                      <div>
                        <p className="text-sm font-semibold text-[var(--theme-text-primary)]">My Status</p>
                        <p className="text-xs text-[var(--theme-text-secondary)]">
                          {myGroup.statuses.length} update{myGroup.statuses.length !== 1 ? "s" : ""} · {formatTimeAgo(myGroup.statuses[0].createdAt)}
                        </p>
                      </div>
                    </button>
                  )}
                </div>
              </div>

              <div className="mx-4 my-3 border-t border-[var(--theme-border-color)]" />

              {/* Contacts' Statuses */}
              {contactGroups.length > 0 ? (
                <div className="px-4 pb-4">
                  <p className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase tracking-wider mb-2">Recent Updates</p>
                  <div className="space-y-1">
                    {contactGroups.map((group) => (
                      <button
                        key={group.user.id}
                        onClick={() => openGroup(group)}
                        className="flex items-center gap-3 w-full rounded-xl px-3 py-2.5 hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-colors text-left cursor-pointer"
                      >
                        <div className="relative shrink-0">
                          <div className={`h-12 w-12 rounded-full p-0.5 ${
                            group.hasUnread
                              ? "bg-gradient-to-br from-[var(--theme-accent)] to-fuchsia-500"
                              : "bg-zinc-600"
                          }`}>
                            <img
                              src={getAvatarUrl(group.user.avatarUrl, group.user.username)}
                              alt={group.user.username}
                              className="h-full w-full rounded-full object-cover border-2 border-[var(--theme-bg-sidebar)]"
                            />
                          </div>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-[var(--theme-text-primary)]">{group.user.username}</p>
                          <p className="text-xs text-[var(--theme-text-secondary)]">
                            {group.statuses.length} update{group.statuses.length !== 1 ? "s" : ""} · {formatTimeAgo(group.statuses[0].createdAt)}
                          </p>
                        </div>
                        {group.hasUnread && (
                          <div className="h-2.5 w-2.5 rounded-full bg-[var(--theme-accent)] shrink-0" />
                        )}
                      </button>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="flex flex-col items-center justify-center py-12 px-6 text-center">
                  <Camera className="h-10 w-10 text-[var(--theme-text-secondary)]/30 mb-3" />
                  <p className="text-sm text-[var(--theme-text-secondary)]">No updates yet</p>
                  <p className="text-xs text-[var(--theme-text-secondary)]/60 mt-1">Contacts with recent status updates will appear here</p>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Create Status Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 z-70 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
          <div className="w-full max-w-sm rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl overflow-hidden">
            {/* Header */}
            <div className="flex items-center justify-between px-5 py-4 border-b border-[var(--theme-border-color)]">
              <h3 className="text-base font-bold text-[var(--theme-text-primary)]">New Status</h3>
              <button onClick={() => setShowCreateModal(false)} className="p-1 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] cursor-pointer transition-colors">
                <X className="h-5 w-5" />
              </button>
            </div>

            {/* Type selector */}
            <div className="flex gap-2 px-5 pt-4">
              {[
                { type: "TEXT" as const, icon: Type, label: "Text" },
                { type: "IMAGE" as const, icon: ImageIcon, label: "Image" },
                { type: "VIDEO" as const, icon: Video, label: "Video" },
              ].map(({ type, icon: Icon, label }) => (
                <button
                  key={type}
                  onClick={() => {
                    setCreateType(type);
                    if (type === "IMAGE" || type === "VIDEO") {
                      fileInputRef.current?.click();
                    }
                  }}
                  className={`flex-1 flex flex-col items-center gap-1 rounded-xl py-2.5 border transition-all cursor-pointer text-xs font-semibold ${
                    createType === type
                      ? "border-[var(--theme-accent)] bg-[var(--theme-accent)]/10 text-[var(--theme-accent)]"
                      : "border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] hover:border-[var(--theme-accent)]/50"
                  }`}
                >
                  <Icon className="h-4 w-4" />
                  {label}
                </button>
              ))}
            </div>

            <input
              type="file"
              ref={fileInputRef}
              className="hidden"
              accept="image/*,video/*"
              onChange={handleFileSelect}
            />

            {/* Preview Area */}
            <div className="px-5 pt-4">
              {createType === "TEXT" ? (
                <div>
                  {/* Background color picker */}
                  <div className="flex gap-2 mb-3 flex-wrap">
                    {TEXT_BG_COLORS.map((bg, i) => (
                      <button
                        key={i}
                        onClick={() => setSelectedBgIndex(i)}
                        className={`h-7 w-7 rounded-full border-2 cursor-pointer transition-transform ${
                          selectedBgIndex === i ? "border-white scale-110" : "border-transparent"
                        }`}
                        style={{ background: bg }}
                      />
                    ))}
                  </div>
                  {/* Text preview */}
                  <div
                    className="w-full h-32 rounded-xl flex items-center justify-center text-center px-4 mb-3"
                    style={{ background: TEXT_BG_COLORS[selectedBgIndex] }}
                  >
                    <p className="text-white text-lg font-bold leading-snug">
                      {captionText || "Your status text..."}
                    </p>
                  </div>
                </div>
              ) : mediaPreview ? (
                <div className="relative w-full h-48 rounded-xl overflow-hidden mb-3 bg-black">
                  {createType === "IMAGE" ? (
                    <img src={mediaPreview} alt="Preview" className="w-full h-full object-contain" />
                  ) : (
                    <video src={mediaPreview} controls className="w-full h-full object-contain" />
                  )}
                  <button
                    onClick={() => { setMediaFile(null); setMediaPreview(""); setCreateType("TEXT"); }}
                    className="absolute top-2 right-2 bg-black/60 rounded-full p-1 text-white hover:bg-black/80 cursor-pointer"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => fileInputRef.current?.click()}
                  className="w-full h-48 border-2 border-dashed border-[var(--theme-border-color)] rounded-xl flex flex-col items-center justify-center gap-2 text-[var(--theme-text-secondary)] hover:border-[var(--theme-accent)] hover:text-[var(--theme-accent)] transition-all cursor-pointer mb-3"
                >
                  <Upload className="h-8 w-8" />
                  <span className="text-sm font-medium">Tap to select {createType === "IMAGE" ? "photo" : "video"}</span>
                </button>
              )}

              {/* Caption input */}
              <input
                type="text"
                value={captionText}
                onChange={(e) => setCaptionText(e.target.value)}
                placeholder={createType === "TEXT" ? "What's on your mind?" : "Add a caption..."}
                maxLength={150}
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/40 focus:border-[var(--theme-accent)] focus:outline-none transition-all"
              />
            </div>

            {/* Post button */}
            <div className="px-5 py-4">
              <button
                onClick={handlePostStatus}
                disabled={isPosting || isUploading || (createType === "TEXT" && !captionText.trim()) || ((createType === "IMAGE" || createType === "VIDEO") && !mediaFile)}
                className="w-full rounded-xl py-3 text-sm font-bold text-white transition-all cursor-pointer disabled:opacity-40 flex items-center justify-center gap-2"
                style={{ background: "linear-gradient(to right, var(--theme-accent), #7c3aed)" }}
              >
                {(isPosting || isUploading) && <Loader2 className="h-4 w-4 animate-spin" />}
                {isUploading ? "Uploading..." : isPosting ? "Posting..." : "Post Status"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
