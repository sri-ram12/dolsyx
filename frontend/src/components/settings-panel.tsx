"use client";

import React, { useState, useEffect, useRef } from "react";
import { X, Camera, Volume2, Music, Lock, Shield, Eye, EyeOff, Trash2, LogOut, Check, ArrowLeft, RefreshCw, Loader2, Ban, User, Palette, QrCode } from "lucide-react";
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
  const [activeTab, setActiveTab] = useState<"profile" | "display" | "audio" | "privacy" | "lock">("profile");

  // Profile Form States
  const [editUsername, setEditUsername] = useState(user?.username || "");
  const [editBio, setEditBio] = useState(user?.bio || "");
  const [editAvatar, setEditAvatar] = useState(user?.avatarUrl || "");
  const [editAvatarPrivacy, setEditAvatarPrivacy] = useState<"PUBLIC" | "NOBODY">((user as any)?.avatarPrivacy || "PUBLIC");
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [isSavingProfile, setIsSavingProfile] = useState(false);
  const [profileError, setProfileError] = useState("");
  const [profileSuccess, setProfileSuccess] = useState("");
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
  const [bioEnabled, setBioEnabled] = useState(false);
  const [fontScale, setFontScale] = useState(1.0);
  const [showQr, setShowQr] = useState(false);
  const [statusPrivacy, setStatusPrivacy] = useState("CONTACTS");
  const [showFullAvatar, setShowFullAvatar] = useState(false);

  useEffect(() => {
    if (user) {
      setEditUsername(user.username);
      setEditBio(user.bio || "");
      setEditAvatar(user.avatarUrl || "");
      setEditAvatarPrivacy((user as any)?.avatarPrivacy || "PUBLIC");
      setBioEnabled(user.email ? localStorage.getItem(`dolsyx_bio_enabled_${user.email.toLowerCase()}`) === "true" : false);
    }
  }, [user]);

  // Load sound configurations + font scale
  useEffect(() => {
    if (typeof window !== "undefined") {
      setNotifSound(localStorage.getItem("dolsyx_notif_sound") || "0");
      setCallSound(localStorage.getItem("dolsyx_call_sound") || "0");
      setCustomNotifName(localStorage.getItem("dolsyx_custom_notif_name") || "");
      setCustomRingName(localStorage.getItem("dolsyx_custom_ring_name") || "");
      setPinEnabled(!!localStorage.getItem("dolsyx_pin_hash"));
      setStatusPrivacy(localStorage.getItem("dolsyx_status_privacy") || "CONTACTS");
      const storedScale = parseFloat(localStorage.getItem("dolsyx_font_scale") || "1.0");
      setFontScale(storedScale);
      document.documentElement.style.fontSize = `${storedScale * 16}px`;
    }
  }, []);

  const handleFontScaleChange = (val: number) => {
    setFontScale(val);
    localStorage.setItem("dolsyx_font_scale", val.toString());
    document.documentElement.style.fontSize = `${val * 16}px`;
  };

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
          avatarUrl: editAvatar,
          avatarPrivacy: editAvatarPrivacy,
        }),
      });

      if (res.ok) {
        const data = await res.json();
        updateUser(data.user);
        setProfileSuccess("Profile updated successfully!");
      } else {
        const data = await res.json();
        setProfileError(data.message || "Failed to update profile");
      }
    } catch (err) {
      console.error(err);
      setProfileError("Error saving profile. Check your connection.");
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

  const handleToggleBiometrics = async () => {
    if (!user?.email) return;
    pinResetAlerts();

    if (bioEnabled) {
      localStorage.removeItem(`dolsyx_bio_enabled_${user.email.toLowerCase()}`);
      setBioEnabled(false);
      setPinSuccess("Biometric lock disabled!");
      return;
    }

    try {
      if (!window.PublicKeyCredential) {
        setPinError("Biometrics not supported on this browser.");
        return;
      }
      const challenge = new Uint8Array(32);
      window.crypto.getRandomValues(challenge);
      const options: PublicKeyCredentialCreationOptions = {
        challenge,
        rp: { name: "DOLSYX" },
        user: {
          id: new Uint8Array(16),
          name: user.email,
          displayName: user.username,
        },
        pubKeyCredParams: [{ type: "public-key", alg: -7 }],
        timeout: 60000,
        attestation: "none"
      };
      const credential = await navigator.credentials.create({ publicKey: options }) as PublicKeyCredential | null;
      if (credential) {
        const credId = btoa(String.fromCharCode(...new Uint8Array(credential.rawId)));
        localStorage.setItem(`dolsyx_bio_cred_id_${user.email.toLowerCase()}`, credId);
        localStorage.setItem(`dolsyx_bio_enabled_${user.email.toLowerCase()}`, "true");
        setBioEnabled(true);
        setPinSuccess("Biometric lock enabled successfully!");
      }
    } catch (err: any) {
      console.error(err);
      setPinError(err.message || "Failed to set up biometrics.");
    }
  };

  const handleStatusPrivacyChange = (val: string) => {
    setStatusPrivacy(val);
    localStorage.setItem("dolsyx_status_privacy", val);
  };

  const pinResetAlerts = () => {
    setPinError("");
    setPinSuccess("");
  };

  return (
    <div className="flex flex-col h-full w-full bg-[var(--theme-bg-sidebar)] border-r border-[var(--theme-border-color)] sm:w-96 shrink-0 z-40 relative transition-all duration-300">
      
      {/* Top Header - Matches Image 2 layout (arrow back + title) */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)]">
        <div className="flex items-center gap-4">
          <button onClick={onClose} className="p-1 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <span className="text-base font-bold text-[var(--theme-text-primary)]">Profile Settings</span>
        </div>
        {activeTab === "profile" && (
          <button
            onClick={() => {
              const event = { preventDefault: () => {} } as React.FormEvent;
              handleSaveProfile(event);
            }}
            disabled={isSavingProfile || isUploadingAvatar}
            className="text-xs font-black uppercase text-[var(--theme-accent)] hover:opacity-80 transition-opacity cursor-pointer disabled:opacity-50"
          >
            {isSavingProfile ? "Saving..." : "Save"}
          </button>
        )}
      </div>

      <div className="flex border-b border-[var(--theme-border-color)] px-4 py-2 bg-[var(--theme-bg-sidebar-header)] overflow-x-auto gap-2">
        {["profile", "display", "audio", "privacy", "chat lock"].map((t) => (
          <button
            key={t}
            onClick={() => setActiveTab((t === "chat lock" ? "lock" : t) as any)}
            className={`px-3 py-1 text-xs font-bold rounded-lg capitalize transition-all cursor-pointer whitespace-nowrap ${
              (activeTab === "lock" && t === "chat lock") || activeTab === t
                ? "bg-[var(--theme-accent)] text-[var(--theme-accent-text)]"
                : "text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
            }`}
          >
            {t === "chat lock" ? "Chat Lock" : t}
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
              <div className="relative w-20 h-20 rounded-full border-4 border-[var(--theme-bg-sidebar)] overflow-hidden bg-[var(--theme-bg-sidebar-search)] group cursor-pointer" onClick={() => setShowFullAvatar(true)}>
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
              {profileSuccess && (
                <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/30 p-3 text-xs text-center text-emerald-400 font-semibold">
                  ✓ {profileSuccess}
                </div>
              )}
              {profileError && (
                <div className="rounded-xl bg-red-500/10 border border-red-500/30 p-3 text-xs text-center text-red-400">
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

                {/* Avatar Privacy Toggle */}
                <div className="flex items-center justify-between gap-4 py-2 border-t border-[var(--theme-border-color)]">
                  <div className="flex items-center gap-3">
                    <Eye className="h-5 w-5 text-slate-400 shrink-0" />
                    <div>
                      <p className="text-xs font-bold text-[var(--theme-text-primary)]">Profile Photo Visibility</p>
                      <p className="text-[10px] text-[var(--theme-text-secondary)]">
                        {editAvatarPrivacy === "PUBLIC" ? "Everyone can see your photo" : "Photo hidden from others"}
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEditAvatarPrivacy(editAvatarPrivacy === "PUBLIC" ? "NOBODY" : "PUBLIC")}
                    className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${
                      editAvatarPrivacy === "PUBLIC" ? "bg-[var(--theme-accent)]" : "bg-slate-700"
                    }`}
                  >
                    <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-lg transition-transform duration-200 ease-in-out ${
                      editAvatarPrivacy === "PUBLIC" ? "translate-x-5" : "translate-x-0"
                    }`} />
                  </button>
                </div>

                {/* Theme Selector Widget */}
                <div className="flex flex-col gap-2 pt-2 border-t border-[var(--theme-border-color)]">
                  <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Select Theme</label>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {[
                      { id: "dolsy-dark", label: "Aqua Dark" },
                      { id: "aqua-light", label: "Aqua Light" },
                      { id: "aqua-dark", label: "Aqua Deep" },
                      { id: "radiant-blue", label: "Radiant Blue" },
                    ].map((t) => (
                      <button
                        key={t.id}
                        type="button"
                        onClick={() => setTheme(t.id as any)}
                        className={`py-2 rounded-lg text-center border text-[10px] font-bold transition-all cursor-pointer ${theme === t.id ? "bg-[var(--theme-accent)] text-[var(--theme-accent-text)] border-transparent" : "border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"}`}
                      >
                        {t.label}
                      </button>
                    ))}
                  </div>
                </div>

              </div>
            </form>

            {/* QR Code Profile Sharing */}
            <div className="px-6 pb-6 pt-2 space-y-3 border-t border-[var(--theme-border-color)]">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <QrCode className="h-5 w-5 text-[var(--theme-accent)]" />
                  <h4 className="font-bold text-sm text-[var(--theme-text-primary)]">My QR Code</h4>
                </div>
                <button
                  type="button"
                  onClick={() => setShowQr((v) => !v)}
                  className="text-[10px] font-bold text-[var(--theme-accent)] hover:opacity-70 cursor-pointer transition-opacity"
                >
                  {showQr ? "Hide" : "Show"}
                </button>
              </div>
              <p className="text-[10px] text-[var(--theme-text-secondary)] leading-relaxed">
                Share your QR code so others can add you on DOLSYX instantly by scanning it.
              </p>
              {showQr && user?.email && (
                <div className="flex flex-col items-center gap-3 py-4">
                  <div className="p-3 bg-white rounded-2xl shadow-xl border border-[var(--theme-border-color)]">
                    <img
                      src={`https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=${encodeURIComponent(`dolsyx://add?email=${user.email}&username=${user.username}`)}&margin=2&color=000000&bgcolor=ffffff`}
                      alt="Profile QR Code"
                      className="h-40 w-40 rounded-lg object-contain"
                    />
                  </div>
                  <p className="text-[10px] text-[var(--theme-text-secondary)] text-center">
                    Point a camera at this code to connect with <span className="font-bold text-[var(--theme-text-primary)]">@{user.username}</span>
                  </p>
                </div>
              )}
            </div>
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
                  className="flex-1 text-center py-2 px-3 rounded-lg border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] text-xs font-bold text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
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
                  className="px-4 py-2 rounded-lg bg-[var(--theme-accent)] text-[var(--theme-accent-text)] text-xs font-bold cursor-pointer"
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
                  className="flex-1 text-center py-2 px-3 rounded-lg border border-[var(--theme-border-color)] hover:border-[var(--theme-accent)] text-xs font-bold text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer"
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

        {/* DISPLAY TAB */}
        {activeTab === "display" && (
          <div className="space-y-6 p-6 animate-fade-in text-left">

            {/* Theme Selection */}
            <div className="space-y-3">
              <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
                <Palette className="h-5 w-5 text-[var(--theme-accent)]" />
                <h4 className="font-bold text-sm">Theme</h4>
              </div>
              <div className="grid grid-cols-2 gap-3">
                {([
                  { id: "dolsy-dark", label: "Dolsyx Dark", bg: "#0d1117", accent: "#10b981" },
                  { id: "aqua-dark",  label: "Aqua Dark",  bg: "#0a1628", accent: "#22d3ee" },
                  { id: "aqua-light", label: "Aqua Light", bg: "#f0f4f8", accent: "#0ea5e9" },
                  { id: "radiant-blue", label: "Radiant Blue", bg: "#0f172a", accent: "#6366f1" },
                ] as { id: any; label: string; bg: string; accent: string }[]).map((t) => (
                  <button
                    key={t.id}
                    type="button"
                    onClick={() => setTheme(t.id)}
                    className={`relative rounded-xl overflow-hidden border-2 transition-all cursor-pointer ${
                      theme === t.id ? "border-[var(--theme-accent)] scale-105 shadow-lg" : "border-[var(--theme-border-color)] hover:border-slate-500"
                    }`}
                    style={{ background: t.bg }}
                  >
                    <div className="flex flex-col items-start p-3 gap-1.5">
                      <div className="flex gap-1">
                        <div className="h-2 w-2 rounded-full" style={{ background: t.accent }} />
                        <div className="h-2 w-6 rounded-full opacity-40" style={{ background: t.accent }} />
                      </div>
                      <div className="h-1.5 w-10 rounded-full opacity-30 bg-white" />
                      <div className="h-1.5 w-8 rounded-full opacity-20 bg-white" />
                    </div>
                    <p className="text-[10px] font-bold px-3 pb-2" style={{ color: t.accent }}>{t.label}</p>
                    {theme === t.id && (
                      <div className="absolute top-1.5 right-1.5 h-4 w-4 rounded-full flex items-center justify-center" style={{ background: t.accent }}>
                        <Check className="h-2.5 w-2.5 text-black" />
                      </div>
                    )}
                  </button>
                ))}
              </div>
            </div>

            {/* Font Size Options */}
            <div className="space-y-3 pt-4 border-t border-[var(--theme-border-color)]">
              <h4 className="font-bold text-sm text-[var(--theme-text-primary)]">Font Size</h4>
              <div className="grid grid-cols-3 gap-2">
                {[
                  { label: "Small", value: 0.875 },
                  { label: "Medium", value: 1.0 },
                  { label: "Large", value: 1.125 }
                ].map((opt) => (
                  <button
                    key={opt.label}
                    type="button"
                    onClick={() => handleFontScaleChange(opt.value)}
                    className={`py-2 rounded-xl text-center text-xs font-bold border transition-all cursor-pointer ${
                      fontScale === opt.value
                        ? "bg-[var(--theme-accent)] text-[var(--theme-accent-text)] border-transparent shadow-md"
                        : "border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
                    }`}
                  >
                    {opt.label}
                  </button>
                ))}
              </div>
              <p className="text-[10px] text-[var(--theme-text-secondary)] leading-relaxed">
                Changes the text size across the entire app. Takes effect immediately.
              </p>
            </div>

            {/* Chat Wallpaper hint */}
            <div className="pt-4 border-t border-[var(--theme-border-color)] rounded-xl bg-[var(--theme-bg-sidebar-search)] p-3.5 border border-[var(--theme-border-color)]">
              <p className="text-xs font-bold text-[var(--theme-text-primary)] mb-1">Chat Wallpaper</p>
              <p className="text-[10px] text-[var(--theme-text-secondary)] leading-relaxed">
                You can set a custom chat background from inside any chat window — tap the 3-dot menu → Wallpaper.
              </p>
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

            <div className="pt-4 border-t border-[var(--theme-border-color)] space-y-2">
              <div className="flex items-center gap-2 text-[var(--theme-text-primary)]">
                <Shield className="h-5 w-5 text-[var(--theme-accent)]" />
                <h4 className="font-bold text-sm">Status Privacy</h4>
              </div>
              <p className="text-[10px] text-[var(--theme-text-secondary)] leading-relaxed">
                Choose who can view your uploaded status stories:
              </p>
              <select
                value={statusPrivacy}
                onChange={(e) => handleStatusPrivacyChange(e.target.value)}
                className="w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] px-3 py-2.5 text-xs text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-accent)]"
              >
                <option value="CONTACTS">My Contacts (Default)</option>
                <option value="SHARE_ONLY">Only Share With Active Chat Contacts</option>
                <option value="PRIVATE">Private (Only Me)</option>
              </select>
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

            <div className="pt-6 border-t border-[var(--theme-border-color)]">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-xs font-bold text-[var(--theme-text-primary)]">Biometric Fingerprint Lock</p>
                  <p className="text-[10px] text-[var(--theme-text-secondary)]">Use fingerprint or Face ID to verify login</p>
                </div>
                <button
                  type="button"
                  onClick={handleToggleBiometrics}
                  className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${
                    bioEnabled ? "bg-[var(--theme-accent)]" : "bg-slate-700"
                  }`}
                >
                  <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-lg transition-transform duration-200 ease-in-out ${
                    bioEnabled ? "translate-x-5" : "translate-x-0"
                  }`} />
                </button>
              </div>
            </div>
          </div>
        )}

      </div>

      {/* Full Screen Avatar Modal */}
      {showFullAvatar && (
        <div className="fixed inset-0 z-[9999] flex flex-col items-center justify-center bg-black/95 backdrop-blur-md p-4 animate-fade-in">
          {/* Header */}
          <div className="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
            <span className="text-white font-bold text-sm">Profile Photo</span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  setShowFullAvatar(false);
                  setTimeout(() => fileInputRef.current?.click(), 100);
                }}
                className="p-2.5 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors cursor-pointer"
                title="Change Photo"
              >
                <Camera className="h-5 w-5" />
              </button>
              <button
                onClick={() => setShowFullAvatar(false)}
                className="p-2.5 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors cursor-pointer"
                title="Close"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Full Screen Image */}
          <div className="max-w-full max-h-[80vh] flex items-center justify-center">
            <img
              src={getAvatarUrl(editAvatar, editUsername)}
              alt="Avatar Full Screen"
              className="max-w-full max-h-[80vh] object-contain rounded-2xl shadow-2xl border border-white/10"
            />
          </div>
        </div>
      )}
    </div>
  );
}
