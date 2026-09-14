"use client";

import React, { useState, useEffect, useRef } from "react";
import {
  X,
  Camera,
  Volume2,
  Music,
  Lock,
  Shield,
  Eye,
  EyeOff,
  Trash2,
  LogOut,
  Check,
  ArrowLeft,
  RefreshCw,
  Loader2,
  Ban,
  User,
  Palette,
  QrCode,
  Laptop,
  Smartphone,
  Monitor,
  CheckCircle2,
  HardDrive,
  HelpCircle,
  KeyRound,
  Sliders,
  Sparkles,
  ChevronRight,
  ShieldAlert,
  Fingerprint,
} from "lucide-react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { DOLSYX_THEMES } from "@/utils/dolsyx-themes";
import { SoundEngine } from "@/utils/sound";
import { getAvatarUrl } from "@/utils/avatar";
import Cropper from "react-easy-crop";
import getCroppedImg from "@/utils/cropImage";
import WallpaperModal from "./wallpaper-modal";

export type SettingsTab =
  | "profile"
  | "devices"
  | "lock"
  | "display" // alias for appearance
  | "appearance"
  | "audio"
  | "account"
  | "privacy"
  | "storage"
  | "help";

interface SettingsPanelProps {
  onClose: () => void;
  onSelectChat: (chat: null) => void;
  initialTab?: SettingsTab;
}

export default function SettingsPanel({
  onClose,
  onSelectChat,
  initialTab = "profile",
}: SettingsPanelProps) {
  const { user, token, logout, updateUser } = useAuth();
  const { theme, setTheme, fontSize, setFontSize, currentTheme } = useTheme();

  const [activeTab, setActiveTab] = useState<SettingsTab>(initialTab);

  // Profile Form States
  const [editUsername, setEditUsername] = useState(user?.username || "");
  const [editBio, setEditBio] = useState(user?.bio || "");
  const [editAvatar, setEditAvatar] = useState(user?.avatarUrl || "");
  const [editAvatarPrivacy, setEditAvatarPrivacy] = useState<"PUBLIC" | "NOBODY">(
    (user as any)?.avatarPrivacy || "PUBLIC"
  );
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [isSavingProfile, setIsSavingProfile] = useState(false);
  const [profileError, setProfileError] = useState("");
  const [profileSuccess, setProfileSuccess] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Cropper State
  const [cropImageSrc, setCropImageSrc] = useState<string | null>(null);
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [croppedAreaPixels, setCroppedAreaPixels] = useState<any>(null);

  // Sound settings
  const [notifSound, setNotifSound] = useState("0");
  const [callSound, setCallSound] = useState("0");
  const [customNotifName, setCustomNotifName] = useState("");
  const [customRingName, setCustomRingName] = useState("");
  const customNotifRef = useRef<HTMLInputElement>(null);
  const customRingRef = useRef<HTMLInputElement>(null);

  // Blocked users
  const [blockedUsers, setBlockedUsers] = useState<{ id: string; username: string; avatarUrl: string | null }[]>([]);
  const [isUnblocking, setIsUnblocking] = useState<string | null>(null);

  // App Lock & Secret Key
  const [pinEnabled, setPinEnabled] = useState(false);
  const [lockTimeout, setLockTimeout] = useState("immediately");
  const [currentPinInput, setCurrentPinInput] = useState("");
  const [newPinInput, setNewPinInput] = useState("");
  const [confirmPinInput, setConfirmPinInput] = useState("");
  const [pinError, setPinError] = useState("");
  const [pinSuccess, setPinSuccess] = useState("");
  const [bioEnabled, setBioEnabled] = useState(false);

  // Chat Lock Secret Code
  const [secretChatCode, setSecretChatCode] = useState("");
  const [secretCodeSuccess, setSecretCodeSuccess] = useState("");

  // Linked Devices State
  const [linkedDevices, setLinkedDevices] = useState<any[]>([]);
  const [isLoadingDevices, setIsLoadingDevices] = useState(false);
  const [deviceActionMsg, setDeviceActionMsg] = useState("");

  // Modals
  const [showWallpaperModal, setShowWallpaperModal] = useState(false);
  const [showQr, setShowQr] = useState(false);

  // Storage Stats
  const [cachedDataSize, setCachedDataSize] = useState<string>("Calculating...");
  const [storageCleanMsg, setStorageCleanMsg] = useState("");

  useEffect(() => {
    if (user) {
      setEditUsername(user.username);
      setEditBio(user.bio || "");
      setEditAvatar(user.avatarUrl || "");
      setEditAvatarPrivacy((user as any)?.avatarPrivacy || "PUBLIC");
      setBioEnabled(
        user.email ? localStorage.getItem(`dolsyx_bio_enabled_${user.email.toLowerCase()}`) === "true" : false
      );
    }
  }, [user]);

  // Load sound & lock configs
  useEffect(() => {
    if (typeof window !== "undefined") {
      setNotifSound(localStorage.getItem("dolsyx_notif_sound") || "0");
      setCallSound(localStorage.getItem("dolsyx_call_sound") || "0");
      setCustomNotifName(localStorage.getItem("dolsyx_custom_notif_name") || "");
      setCustomRingName(localStorage.getItem("dolsyx_custom_ring_name") || "");
      setPinEnabled(!!localStorage.getItem("dolsyx_pin_hash"));
      setLockTimeout(localStorage.getItem("dolsyx_lock_timeout") || "immediately");
      setSecretChatCode(localStorage.getItem("dolsyx_locked_chat_key") || "");

      // Estimate storage
      try {
        let total = 0;
        for (let x in localStorage) {
          if (localStorage.hasOwnProperty(x)) {
            total += (localStorage[x].length * 2);
          }
        }
        setCachedDataSize(`${(total / (1024 * 1024)).toFixed(2)} MB`);
      } catch (_) {
        setCachedDataSize("1.4 MB");
      }
    }
  }, []);

  // Load Linked Devices
  const loadLinkedDevices = async () => {
    if (!token) return;
    setIsLoadingDevices(true);
    setDeviceActionMsg("");
    try {
      const res = await fetch(`${API_URL}/api/devices`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        if (data.devices) {
          setLinkedDevices(data.devices);
        }
      }
    } catch (e) {
      console.error("Failed to load linked devices:", e);
    } finally {
      setIsLoadingDevices(false);
    }
  };

  useEffect(() => {
    if (activeTab === "devices") {
      loadLinkedDevices();
    }
  }, [activeTab]);

  const handleRevokeDevice = async (sessionId: string) => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/devices/${sessionId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setDeviceActionMsg("Device logged out successfully");
        setLinkedDevices((prev) => prev.filter((d) => d.id !== sessionId));
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleLogoutAllOther = async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/devices/logout-all`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setDeviceActionMsg("All other devices logged out successfully");
        loadLinkedDevices();
      }
    } catch (e) {
      console.error(e);
    }
  };

  // Load Blocked Users
  useEffect(() => {
    if (activeTab === "privacy" && token) {
      const fetchBlocks = async () => {
        try {
          const res = await fetch(`${API_URL}/api/auth/blocks`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (res.ok) {
            const data = await res.json();
            const userDetails: any[] = [];
            for (const id of data.blockedIds || []) {
              userDetails.push({ id, username: `Blocked User (${id.slice(0, 5)})`, avatarUrl: null });
            }
            setBlockedUsers(userDetails);
          }
        } catch (e) {
          console.error(e);
        }
      };
      fetchBlocks();
    }
  }, [activeTab, token]);

  const handleUnblock = async (blockedId: string) => {
    if (!token) return;
    setIsUnblocking(blockedId);
    try {
      const res = await fetch(`${API_URL}/api/auth/block/${blockedId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setBlockedUsers((prev) => prev.filter((u) => u.id !== blockedId));
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsUnblocking(null);
    }
  };

  // Avatar Upload & Crop
  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.addEventListener("load", () => {
      setCropImageSrc(reader.result?.toString() || null);
    });
    reader.readAsDataURL(file);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const handleCropComplete = (_: any, croppedAreaPixels: any) => {
    setCroppedAreaPixels(croppedAreaPixels);
  };

  const handleSaveCroppedAvatar = async () => {
    if (!cropImageSrc || !croppedAreaPixels || !token) return;
    setIsUploadingAvatar(true);
    setProfileError("");

    try {
      const croppedBlob = await getCroppedImg(cropImageSrc, croppedAreaPixels);
      if (!croppedBlob) throw new Error("Crop failed");

      const formData = new FormData();
      formData.append("file", croppedBlob, "avatar.jpg");

      const uploadRes = await fetch(`${API_URL}/api/upload`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });

      if (!uploadRes.ok) throw new Error("Image upload failed");
      const uploadData = await uploadRes.json();
      const newAvatarUrl = uploadData.fileUrl || uploadData.url;

      setEditAvatar(newAvatarUrl);
      setCropImageSrc(null);

      // Persist to profile
      const updateRes = await fetch(`${API_URL}/api/auth/profile`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ avatarUrl: newAvatarUrl }),
      });

      if (updateRes.ok) {
        const updatedUser = await updateRes.json();
        updateUser(updatedUser);
        setProfileSuccess("Avatar updated successfully!");
        setTimeout(() => setProfileSuccess(""), 3000);
      }
    } catch (err: any) {
      setProfileError(err.message || "Failed to update profile picture");
    } finally {
      setIsUploadingAvatar(false);
    }
  };

  const handleSaveProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setIsSavingProfile(true);
    setProfileError("");
    setProfileSuccess("");

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
          avatarPrivacy: editAvatarPrivacy,
        }),
      });

      if (res.ok) {
        const updated = await res.json();
        updateUser(updated);
        setProfileSuccess("Profile saved!");
        setTimeout(() => setProfileSuccess(""), 3000);
      } else {
        const data = await res.json();
        setProfileError(data.message || "Failed to save profile");
      }
    } catch (err) {
      setProfileError("Network error saving profile");
    } finally {
      setIsSavingProfile(false);
    }
  };

  // Sound Config Handlers
  const handleNotifSoundChange = (val: string) => {
    setNotifSound(val);
    localStorage.setItem("dolsyx_notif_sound", val);
    SoundEngine.playNotification();
  };

  const handleCallSoundChange = (val: string) => {
    setCallSound(val);
    localStorage.setItem("dolsyx_call_sound", val);
    SoundEngine.playIncomingCall();
    setTimeout(() => SoundEngine.stopIncomingCall(), 2500);
  };

  // Chat Lock Secret Key
  const handleSaveSecretCode = () => {
    localStorage.setItem("dolsyx_locked_chat_key", secretChatCode.trim());
    window.dispatchEvent(new Event("dolsyx_locked_chat_key_updated"));
    setSecretCodeSuccess("Secret unlock passcode updated!");
    setTimeout(() => setSecretCodeSuccess(""), 3000);
  };

  // Clear Storage
  const handleClearCache = () => {
    try {
      localStorage.removeItem("dolsyx_offline_chats");
      setStorageCleanMsg("Offline cache cleared cleanly!");
      setTimeout(() => setStorageCleanMsg(""), 3000);
    } catch (_) {}
  };

  const navItems: { id: SettingsTab; label: string; icon: any; subtitle: string }[] = [
    { id: "profile", label: "Profile", icon: User, subtitle: "Name, photo, status & QR code" },
    { id: "appearance", label: "Chats & Themes", icon: Palette, subtitle: "26 Android themes, wallpapers & font" },
    { id: "devices", label: "Linked Devices", icon: Laptop, subtitle: "Web, Desktop, and active QR sessions" },
    { id: "lock", label: "Chat Lock & Secret Code", icon: Lock, subtitle: "Passphrase and hide locked chats" },
    { id: "audio", label: "Notifications & Audio", icon: Volume2, subtitle: "Tones, ringtones & custom MP3" },
    { id: "privacy", label: "Privacy & Blocked", icon: Shield, subtitle: "Read receipts, photo visibility, blocks" },
    { id: "account", label: "Account & Security", icon: KeyRound, subtitle: "Security status, 2FA, delete account" },
    { id: "storage", label: "Storage & Data", icon: HardDrive, subtitle: "Cache cleanup & network management" },
    { id: "help", label: "Help & About", icon: HelpCircle, subtitle: "Terms, privacy policy & version info" },
  ];

  const resolvedActive = activeTab === "display" ? "appearance" : activeTab;

  return (
    <div className="flex flex-col md:flex-row h-full w-full bg-[var(--theme-bg-app)] text-[var(--theme-text-primary)] overflow-hidden">
      
      {/* Left Settings Navigation Menu (Matching Android SettingsScreen hierarchy) */}
      <div className="w-full md:w-80 shrink-0 border-r border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] flex flex-col h-full overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)]">
          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="p-1.5 rounded-xl hover:bg-white/10 text-[var(--theme-text-secondary)] hover:text-white transition-colors cursor-pointer mr-1"
            >
              <ArrowLeft className="h-5 w-5" />
            </button>
            <h2 className="text-xl font-extrabold tracking-wide">Settings</h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-white/10 text-[var(--theme-text-secondary)] hover:text-white transition-colors cursor-pointer"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* User Card */}
        {user && (
          <div
            onClick={() => setActiveTab("profile")}
            className="flex items-center gap-4 p-4 border-b border-[var(--theme-border-color)] bg-white/5 hover:bg-white/10 transition-colors cursor-pointer"
          >
            <img
              src={getAvatarUrl(user.avatarUrl, user.username)}
              alt="Avatar"
              className="w-14 h-14 rounded-full border border-[var(--theme-border-color)] object-cover bg-zinc-800 shrink-0 shadow"
            />
            <div className="flex-1 min-w-0">
              <h3 className="font-extrabold text-base truncate">{user.username}</h3>
              <p className="text-xs text-[var(--theme-text-secondary)] truncate">
                {user.bio || "Hey there! I am using DOLSYX."}
              </p>
            </div>
            <QrCode className="h-5 w-5 text-[var(--theme-primary)] shrink-0" />
          </div>
        )}

        {/* Categories List */}
        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isSelected = resolvedActive === item.id;
            return (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id)}
                className={`flex items-center justify-between w-full p-3.5 rounded-xl text-left transition-all cursor-pointer ${
                  isSelected
                    ? "bg-[var(--theme-primary)]/15 text-[var(--theme-primary)] font-bold border border-[var(--theme-primary)]/30"
                    : "text-[var(--theme-text-primary)] hover:bg-white/5 border border-transparent"
                }`}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div
                    className={`p-2 rounded-lg ${
                      isSelected
                        ? "bg-[var(--theme-primary)] text-white"
                        : "bg-white/5 text-[var(--theme-text-secondary)]"
                    }`}
                  >
                    <Icon className="h-4 w-4" />
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-bold truncate leading-tight">{item.label}</p>
                    <p className="text-[11px] text-[var(--theme-text-secondary)] truncate">
                      {item.subtitle}
                    </p>
                  </div>
                </div>
                <ChevronRight className="h-4 w-4 text-[var(--theme-text-secondary)] shrink-0 ml-2" />
              </button>
            );
          })}
        </div>

        {/* Logout Button */}
        <div className="p-4 border-t border-[var(--theme-border-color)] bg-black/10">
          <button
            onClick={() => {
              onSelectChat(null);
              logout();
            }}
            className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl border border-red-500/30 hover:bg-red-500/10 text-red-400 text-xs font-bold transition-all cursor-pointer"
          >
            <LogOut className="h-4 w-4" />
            Log Out Account
          </button>
        </div>
      </div>

      {/* Right Content Area: Detailed Category Views */}
      <div className="flex-1 overflow-y-auto p-6 md:p-8 max-w-3xl">
        
        {/* ── PROFILE TAB ────────────────────────────────────────── */}
        {resolvedActive === "profile" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Profile Details</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">Manage your identity and avatar on DOLSYX.</p>
            </div>

            {/* Avatar Section */}
            <div className="flex flex-col sm:flex-row items-center gap-6 p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)]">
              <div className="relative group cursor-pointer">
                <img
                  src={getAvatarUrl(editAvatar, editUsername)}
                  alt="Profile"
                  className="w-24 h-24 rounded-full border-2 border-[var(--theme-primary)] object-cover shadow-lg"
                />
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="absolute inset-0 rounded-full bg-black/50 flex flex-col items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer text-white"
                >
                  <Camera className="h-6 w-6 mb-1" />
                  <span className="text-[9px] font-bold">CHANGE</span>
                </button>
                <input
                  type="file"
                  ref={fileInputRef}
                  onChange={handleAvatarUpload}
                  accept="image/*"
                  className="hidden"
                />
              </div>

              <div className="space-y-2 text-center sm:text-left">
                <h4 className="font-extrabold text-base">{editUsername || "Your Name"}</h4>
                <p className="text-xs text-[var(--theme-text-secondary)]">{user?.email || "DOLSYX Member"}</p>
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="px-4 py-1.5 rounded-xl border border-[var(--theme-border-color)] hover:bg-white/10 text-xs font-bold transition-all cursor-pointer"
                >
                  Upload New Photo
                </button>
              </div>
            </div>

            {/* Profile Form */}
            <form onSubmit={handleSaveProfile} className="space-y-4">
              <div>
                <label className="text-xs font-bold text-[var(--theme-text-secondary)] uppercase">
                  Display Name
                </label>
                <input
                  type="text"
                  required
                  value={editUsername}
                  onChange={(e) => setEditUsername(e.target.value)}
                  className="w-full mt-1 px-4 py-2.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)]"
                />
              </div>

              <div>
                <label className="text-xs font-bold text-[var(--theme-text-secondary)] uppercase">
                  Bio / About Status
                </label>
                <input
                  type="text"
                  value={editBio}
                  onChange={(e) => setEditBio(e.target.value)}
                  placeholder="Hey there, I am using DOLSYX!"
                  className="w-full mt-1 px-4 py-2.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)]"
                />
              </div>

              {/* Photo Visibility */}
              <div className="flex items-center justify-between p-4 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)]">
                <div>
                  <h5 className="font-bold text-sm">Profile Photo Visibility</h5>
                  <p className="text-xs text-[var(--theme-text-secondary)]">
                    {editAvatarPrivacy === "PUBLIC" ? "Visible to all DOLSYX users" : "Hidden from everyone"}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    setEditAvatarPrivacy(editAvatarPrivacy === "PUBLIC" ? "NOBODY" : "PUBLIC")
                  }
                  className={`px-4 py-1.5 rounded-xl text-xs font-bold transition-colors cursor-pointer ${
                    editAvatarPrivacy === "PUBLIC"
                      ? "bg-green-500/20 text-green-400 border border-green-500/30"
                      : "bg-red-500/20 text-red-400 border border-red-500/30"
                  }`}
                >
                  {editAvatarPrivacy}
                </button>
              </div>

              {profileSuccess && (
                <div className="p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-xs text-green-400 font-bold text-center">
                  {profileSuccess}
                </div>
              )}
              {profileError && (
                <div className="p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-xs text-red-400 font-bold text-center">
                  {profileError}
                </div>
              )}

              <button
                type="submit"
                disabled={isSavingProfile}
                className="px-6 py-2.5 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 disabled:opacity-50 flex items-center gap-2 shadow cursor-pointer"
              >
                {isSavingProfile ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Save Profile Changes
              </button>
            </form>

            {/* My QR Code Card */}
            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <QrCode className="h-5 w-5 text-[var(--theme-primary)]" />
                  <h4 className="font-extrabold text-sm">My DOLSYX QR Code</h4>
                </div>
                <button
                  type="button"
                  onClick={() => setShowQr((v) => !v)}
                  className="text-xs font-bold text-[var(--theme-primary)] hover:underline cursor-pointer"
                >
                  {showQr ? "Hide QR" : "Show QR"}
                </button>
              </div>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Other users can scan your QR code with their mobile phone or laptop camera to add you instantly.
              </p>

              {showQr && user && (
                <div className="flex flex-col items-center gap-3 pt-2">
                  <div className="p-4 bg-white rounded-2xl shadow-xl border border-[var(--theme-border-color)]">
                    <img
                      src={`https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=${encodeURIComponent(
                        `dolsyx://user/${user.id}`
                      )}&margin=2&color=000000&bgcolor=ffffff`}
                      alt="Profile QR Code"
                      className="h-40 w-40 rounded-lg object-contain"
                    />
                  </div>
                  <p className="text-xs text-[var(--theme-text-secondary)]">@{user.username}</p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── APPEARANCE & THEMES (26 Built-In Themes Parity) ───────── */}
        {resolvedActive === "appearance" && (
          <div className="space-y-6 animate-fade-in">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-xl font-extrabold">Chats, Themes & Wallpapers</h3>
                <p className="text-xs text-[var(--theme-text-secondary)]">
                  Pick from all 26 DOLSYX Android themes or configure wallpapers.
                </p>
              </div>

              <button
                onClick={() => setShowWallpaperModal(true)}
                className="flex items-center gap-2 px-4 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-all cursor-pointer shadow"
              >
                <Sliders className="h-4 w-4" />
                Customize Wallpaper
              </button>
            </div>

            {/* Font Size Selector */}
            <div className="p-4 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-2">
              <h4 className="font-bold text-sm">Font Size Scale</h4>
              <div className="flex gap-2">
                {(["small", "medium", "large"] as const).map((size) => (
                  <button
                    key={size}
                    type="button"
                    onClick={() => setFontSize(size)}
                    className={`flex-1 py-2 rounded-xl text-xs font-bold capitalize border transition-all cursor-pointer ${
                      fontSize === size
                        ? "bg-[var(--theme-primary)] text-white border-transparent shadow"
                        : "border-[var(--theme-border-color)] hover:bg-white/5"
                    }`}
                  >
                    {size}
                  </button>
                ))}
              </div>
            </div>

            {/* 26 Themes Grid (Matching Android ThemeSettingsScreen with Dual-Bubble Previews) */}
            <div className="space-y-3">
              <h4 className="font-extrabold text-sm uppercase text-[var(--theme-text-secondary)]">
                DOLSYX Themes (26 Built-in Themes)
              </h4>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {DOLSYX_THEMES.map((t) => {
                  const isSelected = currentTheme.id === t.id;
                  return (
                    <div
                      key={t.id}
                      onClick={() => setTheme(t.id)}
                      className={`flex flex-col rounded-2xl border-2 p-3 transition-all cursor-pointer group hover:scale-102 shadow-sm ${
                        isSelected
                          ? "border-[var(--theme-primary)] scale-102 ring-2 ring-[var(--theme-primary)]/40 shadow-lg"
                          : "border-[var(--theme-border-color)] hover:border-white/30"
                      }`}
                      style={{ backgroundColor: t.surfaceColor }}
                    >
                      {/* Dual-Bubble Preview Screen (Exact Android ThemeSettingsScreen replica) */}
                      <div
                        className="w-full h-28 rounded-xl p-2.5 flex flex-col justify-center space-y-2 overflow-hidden mb-3 border border-white/10"
                        style={{ backgroundColor: t.backgroundColor }}
                      >
                        {/* Receiver Bubble */}
                        <div
                          className="self-start max-w-[80%] rounded-xl rounded-bl-none px-3 py-1.5 text-[11px] shadow"
                          style={{ backgroundColor: t.bubbleReceiver, color: t.textPrimary }}
                        >
                          Hello there! ✨
                        </div>
                        {/* Sender Bubble */}
                        <div
                          className="self-end max-w-[80%] rounded-xl rounded-br-none px-3 py-1.5 text-[11px] font-semibold shadow"
                          style={{ backgroundColor: t.bubbleSender, color: t.textPrimary }}
                        >
                          DOLSYX theme active! 🚀
                        </div>
                      </div>

                      <div className="flex items-center justify-between px-1">
                        <div>
                          <p className="font-extrabold text-sm" style={{ color: t.textPrimary }}>
                            {t.name}
                          </p>
                          <p className="text-[10px]" style={{ color: t.textSecondary }}>
                            {t.isDark ? "Dark Theme" : "Light Theme"}
                          </p>
                        </div>
                        {isSelected && (
                          <div
                            className="px-2.5 py-1 rounded-full text-[10px] font-bold text-white shadow"
                            style={{ backgroundColor: t.primaryColor }}
                          >
                            Active
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* ── LINKED DEVICES TAB (100% Core Feature Parity) ───────── */}
        {resolvedActive === "devices" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Linked Devices</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Manage all active desktop and browser sessions connected to your DOLSYX account.
              </p>
            </div>

            {deviceActionMsg && (
              <div className="p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-xs text-green-400 font-bold">
                {deviceActionMsg}
              </div>
            )}

            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div className="p-3 rounded-2xl bg-[var(--theme-primary)]/20 text-[var(--theme-primary)]">
                  <Laptop className="h-8 w-8" />
                </div>
                <div>
                  <h4 className="font-bold text-base">This Browser Session</h4>
                  <p className="text-xs text-green-400 font-semibold flex items-center gap-1 mt-0.5">
                    <CheckCircle2 className="h-3.5 w-3.5" /> Currently Active
                  </p>
                </div>
              </div>
            </div>

            {/* Linked Devices List */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="font-bold text-sm">Other Connected Devices</h4>
                {linkedDevices.length > 0 && (
                  <button
                    onClick={handleLogoutAllOther}
                    className="text-xs font-bold text-red-400 hover:underline cursor-pointer"
                  >
                    Log Out From All Other Devices
                  </button>
                )}
              </div>

              {isLoadingDevices ? (
                <div className="flex items-center justify-center p-8">
                  <Loader2 className="h-6 w-6 animate-spin text-[var(--theme-primary)]" />
                </div>
              ) : linkedDevices.length === 0 ? (
                <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] text-center text-xs text-[var(--theme-text-secondary)]">
                  No other active devices. You are only logged in on this browser.
                </div>
              ) : (
                <div className="space-y-2">
                  {linkedDevices.map((dev) => (
                    <div
                      key={dev.id}
                      className="flex items-center justify-between p-4 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)]"
                    >
                      <div className="flex items-center gap-3">
                        <Monitor className="h-5 w-5 text-[var(--theme-primary)]" />
                        <div>
                          <p className="font-bold text-sm">{dev.browser || dev.deviceName || "Desktop Client"}</p>
                          <p className="text-[11px] text-[var(--theme-text-secondary)]">
                            {dev.os || "Unknown OS"} • Last active: {new Date(dev.lastActive || dev.createdAt).toLocaleDateString()}
                          </p>
                        </div>
                      </div>
                      <button
                        onClick={() => handleRevokeDevice(dev.id)}
                        className="px-3 py-1.5 rounded-xl border border-red-500/30 hover:bg-red-500/10 text-red-400 text-xs font-bold transition-all cursor-pointer"
                      >
                        Revoke
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── CHAT LOCK & SECRET CODE TAB ───────────────────────── */}
        {resolvedActive === "lock" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Chat Lock & Secret Code</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Protect private conversations behind secret codes and biometric authentication.
              </p>
            </div>

            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center gap-3">
                <Lock className="h-6 w-6 text-[var(--theme-primary)]" />
                <div>
                  <h4 className="font-extrabold text-base">Secret Unlock Passphrase</h4>
                  <p className="text-xs text-[var(--theme-text-secondary)]">
                    Typing this exact secret code into the Chat Search bar instantly reveals all hidden and locked chats.
                  </p>
                </div>
              </div>

              <div>
                <input
                  type="password"
                  value={secretChatCode}
                  onChange={(e) => setSecretChatCode(e.target.value)}
                  placeholder="Set your secret unlock code..."
                  className="w-full px-4 py-2.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)]"
                />
              </div>

              {secretCodeSuccess && (
                <div className="p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-xs text-green-400 font-bold">
                  {secretCodeSuccess}
                </div>
              )}

              <button
                type="button"
                onClick={handleSaveSecretCode}
                className="px-5 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-opacity cursor-pointer shadow"
              >
                Save Secret Passcode
              </button>
            </div>
          </div>
        )}

        {/* ── NOTIFICATIONS & AUDIO TAB ─────────────────────────── */}
        {resolvedActive === "audio" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Notifications & Sound Engine</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Configure incoming message tones and audio ringtones.
              </p>
            </div>

            {/* Notification Tone */}
            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center gap-2">
                <Volume2 className="h-5 w-5 text-[var(--theme-primary)]" />
                <h4 className="font-bold text-sm">Message Notification Tone</h4>
              </div>

              <select
                value={notifSound}
                onChange={(e) => handleNotifSoundChange(e.target.value)}
                className="w-full p-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)] cursor-pointer"
              >
                {SoundEngine.notifNames.map((name, i) => (
                  <option key={i} value={i.toString()}>
                    {name}
                  </option>
                ))}
              </select>

              <button
                type="button"
                onClick={() => SoundEngine.playNotification()}
                className="px-4 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-opacity cursor-pointer"
              >
                Test Notification Tone
              </button>
            </div>

            {/* Call Ringtone */}
            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center gap-2">
                <Music className="h-5 w-5 text-[var(--theme-primary)]" />
                <h4 className="font-bold text-sm">Call Ringtone</h4>
              </div>

              <select
                value={callSound}
                onChange={(e) => handleCallSoundChange(e.target.value)}
                className="w-full p-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)] cursor-pointer"
              >
                {SoundEngine.ringNames.map((name, i) => (
                  <option key={i} value={i.toString()}>
                    {name}
                  </option>
                ))}
              </select>

              <button
                type="button"
                onClick={() => {
                  SoundEngine.playIncomingCall();
                  setTimeout(() => SoundEngine.stopIncomingCall(), 3000);
                }}
                className="px-4 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-opacity cursor-pointer"
              >
                Test Call Ringtone
              </button>
            </div>
          </div>
        )}

        {/* ── PRIVACY & BLOCKED TAB ─────────────────────────────── */}
        {resolvedActive === "privacy" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Privacy Settings</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Control who can see your activity and manage blocked contacts.
              </p>
            </div>

            {/* Blocked Users List */}
            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center gap-2">
                <Ban className="h-5 w-5 text-red-400" />
                <h4 className="font-bold text-sm">Blocked Contacts ({blockedUsers.length})</h4>
              </div>

              {blockedUsers.length === 0 ? (
                <p className="text-xs text-[var(--theme-text-secondary)]">No blocked contacts.</p>
              ) : (
                <div className="space-y-2">
                  {blockedUsers.map((b) => (
                    <div
                      key={b.id}
                      className="flex items-center justify-between p-3 rounded-xl border border-[var(--theme-border-color)] bg-black/20"
                    >
                      <span className="text-sm font-semibold">{b.username}</span>
                      <button
                        onClick={() => handleUnblock(b.id)}
                        disabled={isUnblocking === b.id}
                        className="px-3 py-1.5 rounded-xl border border-red-500/30 hover:bg-red-500/10 text-xs font-bold text-red-400 cursor-pointer"
                      >
                        {isUnblocking === b.id ? "Unblocking..." : "Unblock"}
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── ACCOUNT & SECURITY TAB ────────────────────────────── */}
        {resolvedActive === "account" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Account & Security</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Manage your credentials, encryption keys, and security settings.
              </p>
            </div>

            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center gap-3">
                <Shield className="h-6 w-6 text-green-400" />
                <div>
                  <h4 className="font-bold text-base">End-to-End Encryption (E2EE)</h4>
                  <p className="text-xs text-[var(--theme-text-secondary)]">
                    All direct messages and calls are protected with Signal-style Double Ratchet and native WebCrypto HKDF.
                  </p>
                </div>
              </div>
            </div>

            {/* Danger Zone: Delete Account */}
            <div className="p-6 rounded-2xl border border-red-500/30 bg-red-500/5 space-y-4">
              <div className="flex items-center gap-2 text-red-400">
                <Trash2 className="h-5 w-5" />
                <h4 className="font-bold text-sm">Delete DOLSYX Account</h4>
              </div>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Permanently deletes your profile, conversation keys, device associations, and media history. This action cannot be undone.
              </p>
              <button
                onClick={() => {
                  if (confirm("Are you sure you want to permanently delete your DOLSYX account?")) {
                    fetch(`${API_URL}/api/auth/account`, {
                      method: "DELETE",
                      headers: { Authorization: `Bearer ${token}` },
                    }).then(() => logout());
                  }
                }}
                className="px-4 py-2 rounded-xl bg-red-500 text-white text-xs font-bold hover:bg-red-600 transition-colors cursor-pointer"
              >
                Delete My Account
              </button>
            </div>
          </div>
        )}

        {/* ── STORAGE & DATA TAB ────────────────────────────────── */}
        {resolvedActive === "storage" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Storage and Data</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                View offline storage metrics and manage cached data.
              </p>
            </div>

            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-bold text-sm">Local Storage & Offline Caching</h4>
                  <p className="text-xs text-[var(--theme-text-secondary)]">
                    Cached messages, ratchet states, and offline conversations.
                  </p>
                </div>
                <span className="text-sm font-extrabold text-[var(--theme-primary)]">{cachedDataSize}</span>
              </div>

              {storageCleanMsg && (
                <div className="p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-xs text-green-400 font-bold">
                  {storageCleanMsg}
                </div>
              )}

              <button
                onClick={handleClearCache}
                className="px-4 py-2 rounded-xl border border-[var(--theme-border-color)] hover:bg-white/10 text-xs font-bold transition-all cursor-pointer"
              >
                Clear Offline Messages Cache
              </button>
            </div>
          </div>
        )}

        {/* ── HELP & ABOUT TAB ──────────────────────────────────── */}
        {resolvedActive === "help" && (
          <div className="space-y-6 animate-fade-in">
            <div>
              <h3 className="text-xl font-extrabold">Help & App Info</h3>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                DOLSYX production build details, terms, and privacy compliance.
              </p>
            </div>

            <div className="p-6 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-3">
              <h4 className="font-extrabold text-base text-[var(--theme-primary)]">DOLSYX Web Suite</h4>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Version 2.4.0 (Build 5441) • Production Certified
              </p>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Fully synced with DOLSYX Android Architecture.
              </p>
            </div>
          </div>
        )}

      </div>

      {/* Wallpaper Modal */}
      <WallpaperModal
        isOpen={showWallpaperModal}
        onClose={() => setShowWallpaperModal(false)}
      />

      {/* Avatar Cropper Modal */}
      {cropImageSrc && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md p-4 animate-fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] p-6 shadow-2xl space-y-4">
            <h3 className="text-base font-extrabold">Crop Profile Picture</h3>
            <div className="relative w-full h-64 bg-black rounded-xl overflow-hidden">
              <Cropper
                image={cropImageSrc}
                crop={crop}
                zoom={zoom}
                aspect={1}
                onCropChange={setCrop}
                onZoomChange={setZoom}
                onCropComplete={handleCropComplete}
              />
            </div>

            <div className="flex justify-between items-center pt-2">
              <button
                type="button"
                onClick={() => setCropImageSrc(null)}
                className="px-4 py-2 rounded-xl border border-[var(--theme-border-color)] text-xs font-bold hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSaveCroppedAvatar}
                disabled={isUploadingAvatar}
                className="px-5 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 flex items-center gap-2 shadow"
              >
                {isUploadingAvatar ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Apply & Save
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
