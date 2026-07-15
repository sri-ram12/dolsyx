"use client";

import React, { useState, useEffect, useRef } from "react";
import { X, Camera, Volume2, Music, Lock, Shield, Eye, EyeOff, Trash2, LogOut, Check, ArrowLeft, RefreshCw, Loader2, Ban, User } from "lucide-react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { SoundEngine } from "@/utils/sound";
import { getAvatarUrl } from "@/utils/avatar";

interface SettingsPanelProps {
  onClose: () => void;
  onSelectChat: (chat: null) => void;
}

export default function SettingsPanel({ onClose, onSelectChat }: SettingsPanelProps) {
  const { user, token, logout, updateUser } = useAuth();
  const { theme, setTheme } = useTheme();
  const [activeTab, setActiveTab] = useState<"profile" | "audio" | "privacy" | "lock">("profile");

  // Profile Form States
  const [editUsername, setEditUsername] = useState(user?.username || "");
  const [editBio, setEditBio] = useState(user?.bio || "");
  const [editAvatar, setEditAvatar] = useState(user?.avatarUrl || "");
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [isSavingProfile, setIsSavingProfile] = useState(false);
  const [profileError, setProfileError] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);

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

  // App Lock
  const [pinEnabled, setPinEnabled] = useState(false);
  const [currentPinInput, setCurrentPinInput] = useState("");
  const [newPinInput, setNewPinInput] = useState("");
  const [confirmPinInput, setConfirmPinInput] = useState("");
  const [pinError, setPinError] = useState("");
  const [pinSuccess, setPinSuccess] = useState("");

  useEffect(() => {
    if (user) {
      setEditUsername(user.username);
      setEditBio(user.bio || "");
      setEditAvatar(user.avatarUrl || "");
    }
  }, [user]);

  // Load sound configurations
  useEffect(() => {
    if (typeof window !== "undefined") {
      setNotifSound(localStorage.getItem("dolsyx_notif_sound") || "0");
      setCallSound(localStorage.getItem("dolsyx_call_sound") || "0");
      setCustomNotifName(localStorage.getItem("dolsyx_custom_notif_name") || "");
      setCustomRingName(localStorage.getItem("dolsyx_custom_ring_name") || "");
      setPinEnabled(!!localStorage.getItem("dolsyx_pin_hash"));
    }
  }, []);

  // Load Blocked Users list
  useEffect(() => {
    if (activeTab === "privacy" && token) {
      const fetchBlocks = async () => {
        try {
          const res = await fetch(`${API_URL}/api/auth/blocks`, {
            headers: { Authorization: `Bearer ${token}` }
          });
          if (res.ok) {
            const data = await res.json();
            const userDetails: any[] = [];
            for (const id of data.blockedIds) {
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
        headers: { Authorization: `Bearer ${token}` },
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
        setProfileError("Profile updated successfully!");
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

  // Sound Handlers
  const handleNotifSoundChange = (val: string) => {
    setNotifSound(val);
    localStorage.setItem("dolsyx_notif_sound", val);
    if (val !== "custom") {
      SoundEngine.previewNotification(parseInt(val));
    }
  };

  const handleCallSoundChange = (val: string) => {
    setCallSound(val);
    localStorage.setItem("dolsyx_call_sound", val);
    if (val !== "custom") {
      SoundEngine.previewRingtone(parseInt(val));
    }
  };

  const handleCustomAudioUpload = (type: "notif" | "ring", e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (ev) => {
      const base64 = ev.target?.result as string;
      if (type === "notif") {
        localStorage.setItem("dolsyx_custom_notif", base64);
        localStorage.setItem("dolsyx_custom_notif_name", file.name);
        setCustomNotifName(file.name);
        setNotifSound("custom");
        localStorage.setItem("dolsyx_notif_sound", "custom");
      } else {
        localStorage.setItem("dolsyx_custom_ring", base64);
        localStorage.setItem("dolsyx_custom_ring_name", file.name);
        setCustomRingName(file.name);
        setCallSound("custom");
        localStorage.setItem("dolsyx_call_sound", "custom");
      }
    };
    reader.readAsDataURL(file);
  };

  // Unblock Handler
  const handleUnblock = async (targetId: string) => {
    if (!token) return;
    setIsUnblocking(targetId);
    try {
      const res = await fetch(`${API_URL}/api/auth/block/${targetId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      });
      if (res.ok) {
        setBlockedUsers(prev => prev.filter(u => u.id !== targetId));
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsUnblocking(null);
    }
  };

  // PIN App Lock Handlers
  const handleSetPin = async (e: React.FormEvent) => {
    e.preventDefault();
    pinResetAlerts();

    if (!/^\d{4,6}$/.test(newPinInput)) {
      setPinError("PIN must be 4 to 6 numeric digits");
      return;
    }
    if (newPinInput !== confirmPinInput) {
      setPinError("Confirm PIN does not match");
      return;
    }

    const msgBuffer = new TextEncoder().encode(newPinInput);
    const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    localStorage.setItem("dolsyx_pin_hash", hashHex);
    setPinEnabled(true);
    setPinSuccess("PIN enabled successfully!");
    setNewPinInput("");
    setConfirmPinInput("");
  };

  const handleDisablePin = async (e: React.FormEvent) => {
    e.preventDefault();
    pinResetAlerts();

    const storedHash = localStorage.getItem("dolsyx_pin_hash");
    if (!storedHash) return;

    const msgBuffer = new TextEncoder().encode(currentPinInput);
    const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    if (hashHex !== storedHash) {
      setPinError("Incorrect PIN");
      return;
    }

    localStorage.removeItem("dolsyx_pin_hash");
    sessionStorage.removeItem("dolsyx_unlocked");
    setPinEnabled(false);
    setPinSuccess("App lock disabled!");
    setCurrentPinInput("");
  };

  const pinResetAlerts = () => {
    setPinError("");
    setPinSuccess("");
  };

  return (
    <div className="flex flex-col h-full w-full bg-[var(--theme-bg-sidebar)] border-r border-[var(--theme-border-color)] sm:w-96 shrink-0 z-40 relative transition-all duration-300">
      
      {/* Top Header - Matches Image 2 layout (arrow back + title) */}
      <div className="flex items-center gap-4 px-5 py-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)]">
        <button onClick={onClose} className="p-1 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <span className="text-base font-bold text-[var(--theme-text-primary)]">Profile Settings</span>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-[var(--theme-border-color)] px-4 py-2 bg-[var(--theme-bg-sidebar-header)] overflow-x-auto gap-2">
        {["profile", "audio", "privacy", "lock"].map((t) => (
          <button
            key={t}
            onClick={() => setActiveTab(t as any)}
            className={`px-3 py-1 text-xs font-bold rounded-lg capitalize transition-all cursor-pointer ${activeTab === t ? "bg-[var(--theme-accent)] text-black" : "text-[var(--theme-text-secondary)] hover:text-white"}`}
          >
            {t}
          </button>
        ))}
      </div>

      {/* Settings Scrollable Content Area */}
      <div className="flex-1 overflow-y-auto space-y-6">
        
        {/* PROFILE TAB */}
        {activeTab === "profile" && (
          <div className="animate-fade-in text-left">
            {/* Banner Cover Image (Image 2 style) */}
            <div className="h-28 w-full bg-gradient-to-r from-teal-800 to-[#10b981] relative">
              {/* Optional Camera Icon for Banner upload (placeholder) */}
              <div className="absolute right-4 bottom-4 p-1.5 rounded-full bg-black/60 border border-slate-700 text-white hover:opacity-80 transition-opacity">
                <Camera className="h-4.5 w-4.5" />
              </div>
            </div>

            {/* Overlapping Profile Photo */}
            <div className="px-6 -mt-10 flex flex-col relative mb-4">
              <div className="relative w-20 h-20 rounded-full border-4 border-[var(--theme-bg-sidebar)] overflow-hidden bg-[var(--theme-bg-sidebar-search)] group cursor-pointer" onClick={() => fileInputRef.current?.click()}>
                <img
                  src={getAvatarUrl(editAvatar, editUsername)}
                  alt="Avatar Preview"
                  className="w-full h-full object-cover transition-opacity group-hover:opacity-85"
                />
                <div className="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity">
                  {isUploadingAvatar ? <Loader2 className="h-5 w-5 text-white animate-spin" /> : <Camera className="h-5 w-5 text-white" />}
                </div>
              </div>
              <input type="file" ref={fileInputRef} onChange={handleAvatarUpload} className="hidden" accept="image/*" />
            </div>

            {/* Form */}
            <form onSubmit={handleSaveProfile} className="px-6 space-y-6">
              {profileError && (
                <div className="rounded-xl bg-[var(--theme-accent)]/10 border border-[var(--theme-accent)]/20 p-3 text-xs text-center text-[var(--theme-text-primary)]">
                  {profileError}
                </div>
              )}

              {/* Action row buttons (Image 2 style) */}
              <div className="grid grid-cols-2 gap-3 pb-4 border-b border-[var(--theme-border-color)]">
                <button
                  type="submit"
                  disabled={isSavingProfile || isUploadingAvatar}
                  className="flex items-center justify-center gap-1.5 rounded-xl border border-[var(--theme-accent)]/30 hover:bg-[var(--theme-accent)]/10 text-[var(--theme-accent)] py-2 text-xs font-bold transition-all cursor-pointer"
                >
                  {isSavingProfile ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                  Save Details
                </button>
                <button
                  type="button"
                  onClick={() => { onSelectChat(null); logout(); }}
                  className="flex items-center justify-center gap-1.5 rounded-xl border border-red-500/30 hover:bg-red-500/10 text-red-400 py-2 text-xs font-bold transition-all cursor-pointer"
                >
                  <LogOut className="h-3.5 w-3.5" />
                  Logout
                </button>
              </div>

              {/* List details with left-aligned icons (Image 2 style) */}
              <div className="space-y-5 pt-2">
                
                {/* Username Input Field */}
                <div className="flex items-start gap-4">
                  <User className="h-5 w-5 text-slate-400 mt-2.5 shrink-0" />
                  <div className="flex-1 space-y-1">
                    <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Display Name</label>
                    <input
                      type="text"
                      value={editUsername}
                      onChange={(e) => setEditUsername(e.target.value)}
                      placeholder="Enter name"
                      required
                      maxLength={30}
                      className="w-full border-b border-[var(--theme-border-color)] bg-transparent py-1.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)] transition-colors"
                    />
                  </div>
                </div>

                {/* About Bio Field */}
                <div className="flex items-start gap-4">
                  <Shield className="h-5 w-5 text-slate-400 mt-2.5 shrink-0" />
                  <div className="flex-1 space-y-1">
                    <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Status / About</label>
                    <input
                      type="text"
                      value={editBio}
                      onChange={(e) => setEditBio(e.target.value)}
                      placeholder="Status message..."
                      maxLength={100}
                      className="w-full border-b border-[var(--theme-border-color)] bg-transparent py-1.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)] transition-colors"
                    />
                  </div>
                </div>

                {/* Theme Selector Widget */}
                <div className="flex flex-col gap-2 pt-2 border-t border-[var(--theme-border-color)]">
                  <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Select Theme</label>
                  <div className="grid grid-cols-3 gap-2">
                    {[
                      { id: "dolsy-dark", label: "Aqua Dark" },
                      { id: "aqua-light", label: "Aqua Light" },
                      { id: "aqua-dark", label: "Aqua Deep" },
                    ].map((t) => (
                      <button
                        key={t.id}
                        type="button"
                        onClick={() => setTheme(t.id as any)}
                        className={`py-2 rounded-lg text-center border text-[10px] font-bold transition-all cursor-pointer ${theme === t.id ? "bg-[var(--theme-accent)] text-black border-transparent" : "border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] hover:text-white"}`}
                      >
                        {t.label}
                      </button>
                    ))}
                  </div>
                </div>

              </div>
            </form>
          </div>
        )}

        {/* SOUND TAB */}
        {activeTab === "audio" && (
          <div className="space-y-6 p-6 animate-fade-in text-left">
            {/* Notification Sounds */}
            <div className="space-y-3">
              <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
                <Volume2 className="h-5 w-5 text-[var(--theme-accent)]" />
                <h4 className="font-bold text-sm">Notification Tone</h4>
              </div>
              <select
                value={notifSound}
                onChange={(e) => handleNotifSoundChange(e.target.value)}
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)]"
              >
                {SoundEngine.notifNames.map((name, i) => (
                  <option key={i} value={i.toString()}>{name}</option>
                ))}
                <option value="custom">Custom Audio File {customNotifName ? `(${customNotifName})` : ""}</option>
              </select>
              
              <div className="flex items-center justify-between gap-3 pt-1">
                <button
                  onClick={() => customNotifRef.current?.click()}
                  className="flex-1 text-center py-2 px-3 rounded-lg border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] text-xs font-bold text-[var(--theme-text-secondary)] hover:text-white transition-all cursor-pointer"
                >
                  Upload Custom MP3
                </button>
                <input
                  type="file"
                  ref={customNotifRef}
                  onChange={(e) => handleCustomAudioUpload("notif", e)}
                  accept="audio/*"
                  className="hidden"
                />
                <button
                  onClick={() => SoundEngine.playNotification()}
                  className="px-4 py-2 rounded-lg bg-[var(--theme-accent)] text-black text-xs font-bold cursor-pointer"
                >
                  Test Tone
                </button>
              </div>
            </div>

            {/* Ringtone Sounds */}
            <div className="space-y-3 pt-6 border-t border-[var(--theme-border-color)]">
              <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
                <Music className="h-5 w-5 text-[var(--theme-accent)]" />
                <h4 className="font-bold text-sm">Call Ringtone</h4>
              </div>
              <select
                value={callSound}
                onChange={(e) => handleCallSoundChange(e.target.value)}
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)]"
              >
                {SoundEngine.ringNames.map((name, i) => (
                  <option key={i} value={i.toString()}>{name}</option>
                ))}
                <option value="custom">Custom Ringtone {customRingName ? `(${customRingName})` : ""}</option>
              </select>

              <div className="flex items-center justify-between gap-3 pt-1">
                <button
                  onClick={() => customRingRef.current?.click()}
                  className="flex-1 text-center py-2 px-3 rounded-lg border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] text-xs font-bold text-[var(--theme-text-secondary)] hover:text-white transition-all cursor-pointer"
                >
                  Upload Custom Ringtone
                </button>
                <input
                  type="file"
                  ref={customRingRef}
                  onChange={(e) => handleCustomAudioUpload("ring", e)}
                  accept="audio/*"
                  className="hidden"
                />
                <div className="flex gap-1.5">
                  <button
                    onClick={() => SoundEngine.playRingtone()}
                    className="px-3 py-2 rounded-lg bg-[var(--theme-accent)] text-black text-xs font-bold cursor-pointer"
                  >
                    Play
                  </button>
                  <button
                    onClick={() => SoundEngine.stopRingtone()}
                    className="px-3 py-2 rounded-lg bg-red-650 text-white text-xs font-bold cursor-pointer"
                  >
                    Stop
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* PRIVACY TAB */}
        {activeTab === "privacy" && (
          <div className="space-y-4 animate-fade-in text-left">
            <div className="flex items-center gap-2 text-[var(--theme-text-primary)] mb-2">
              <Ban className="h-5 w-5 text-red-400" />
              <h4 className="font-bold text-sm">Blocked Accounts</h4>
            </div>

            <p className="text-xs text-[var(--theme-text-secondary)] leading-relaxed">
              When you block someone, they won't be able to message you or see your online status.
            </p>

            <div className="space-y-2.5 pt-3">
              {blockedUsers.length === 0 ? (
                <div className="text-center py-8 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-xs text-[var(--theme-text-secondary)]">
                  No blocked users
                </div>
              ) : (
                blockedUsers.map((bu) => (
                  <div key={bu.id} className="flex items-center justify-between p-3 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)]">
                    <div className="min-w-0">
                      <p className="font-semibold text-xs text-[var(--theme-text-primary)] truncate">Blocked User</p>
                      <p className="text-[10px] text-[var(--theme-text-secondary)] truncate">ID: {bu.id}</p>
                    </div>
                    <button
                      onClick={() => handleUnblock(bu.id)}
                      disabled={isUnblocking === bu.id}
                      className="px-3 py-1.5 rounded-lg border border-red-500/30 hover:bg-red-500/10 text-red-400 text-[10px] font-bold cursor-pointer transition-all"
                    >
                      {isUnblocking === bu.id ? "Unblocking..." : "Unblock"}
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {/* LOCK TAB */}
        {activeTab === "lock" && (
          <div className="space-y-6 animate-fade-in text-left">
            <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
              <Lock className="h-5 w-5 text-[var(--theme-accent)]" />
              <h4 className="font-bold text-sm">App PIN Lock</h4>
            </div>

            <p className="text-xs text-[var(--theme-text-secondary)] leading-relaxed">
              Require a secure PIN to open this application on this device. Helps secure your private conversations.
            </p>

            {pinError && (
              <div className="rounded-lg bg-red-500/10 border border-red-500/20 p-3 text-xs text-red-400 text-center animate-fade-in">
                {pinError}
              </div>
            )}

            {pinSuccess && (
              <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3 text-xs text-emerald-400 text-center animate-fade-in">
                {pinSuccess}
              </div>
            )}

            {!pinEnabled ? (
              <form onSubmit={handleSetPin} className="space-y-4">
                <div className="space-y-1.5">
                  <label className="text-xs font-bold text-[var(--theme-text-secondary)]">Create New PIN (4-6 digits)</label>
                  <input
                    type="password"
                    pattern="[0-9]*"
                    inputMode="numeric"
                    maxLength={6}
                    value={newPinInput}
                    onChange={(e) => setNewPinInput(e.target.value.replace(/[^0-9]/g, ""))}
                    placeholder="Enter PIN"
                    className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)] tracking-widest text-center"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-xs font-bold text-[var(--theme-text-secondary)]">Confirm New PIN</label>
                  <input
                    type="password"
                    pattern="[0-9]*"
                    inputMode="numeric"
                    maxLength={6}
                    value={confirmPinInput}
                    onChange={(e) => setConfirmPinInput(e.target.value.replace(/[^0-9]/g, ""))}
                    placeholder="Confirm PIN"
                    className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)] tracking-widest text-center"
                  />
                </div>
                <button
                  type="submit"
                  className="w-full rounded-xl bg-[var(--theme-accent)] text-black hover:opacity-90 py-3 text-xs font-bold cursor-pointer"
                >
                  Enable PIN Lock
                </button>
              </form>
            ) : (
              <form onSubmit={handleDisablePin} className="space-y-4 pt-4 border-t border-[var(--theme-border-color)]">
                <div className="space-y-1.5">
                  <label className="text-xs font-bold text-red-400">Enter Current PIN to Disable Lock</label>
                  <input
                    type="password"
                    pattern="[0-9]*"
                    inputMode="numeric"
                    maxLength={6}
                    value={currentPinInput}
                    onChange={(e) => setCurrentPinInput(e.target.value.replace(/[^0-9]/g, ""))}
                    placeholder="Enter PIN"
                    className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-4 py-2.5 text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-red-500 tracking-widest text-center"
                  />
                </div>
                <button
                  type="submit"
                  className="w-full rounded-xl bg-red-650 hover:bg-red-700 text-white py-3 text-xs font-bold cursor-pointer"
                >
                  Disable PIN Lock
                </button>
              </form>
            )}
          </div>
        )}

      </div>
    </div>
  );
}
