"use client";

import React, { useState, useRef } from "react";
import { X, Check, Image as ImageIcon, Sliders, Palette, Sparkles, Trash2, Undo2 } from "lucide-react";
import { useTheme } from "@/context/theme-context";
import {
  WALLPAPER_SOLID_COLORS,
  WALLPAPER_GRADIENT_PATTERNS,
  WallpaperConfig,
  DEFAULT_WALLPAPER,
} from "@/utils/dolsyx-themes";

interface WallpaperModalProps {
  isOpen: boolean;
  onClose: () => void;
  conversationId?: string | null;
  conversationName?: string | null;
}

export default function WallpaperModal({
  isOpen,
  onClose,
  conversationId,
  conversationName,
}: WallpaperModalProps) {
  const {
    currentTheme,
    globalWallpaper,
    setGlobalWallpaper,
    getWallpaperForChat,
    setChatWallpaper,
    removeChatWallpaper,
  } = useTheme();

  const initialConfig = conversationId
    ? getWallpaperForChat(conversationId)
    : globalWallpaper;

  const [activeTab, setActiveTab] = useState<"solid" | "pattern" | "custom">("pattern");
  const [selectedType, setSelectedType] = useState<WallpaperConfig["type"]>(initialConfig.type);
  const [selectedValue, setSelectedValue] = useState<string>(initialConfig.value);
  const [opacity, setOpacity] = useState<number>(initialConfig.opacity ?? 1.0);
  const [blur, setBlur] = useState<number>(initialConfig.blur ?? 0);

  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!isOpen) return null;

  const handleApply = (applyToAll: boolean) => {
    const config: WallpaperConfig = {
      type: selectedType,
      value: selectedValue,
      opacity,
      blur,
    };

    if (applyToAll || !conversationId) {
      setGlobalWallpaper(config);
    } else {
      setChatWallpaper(conversationId, config);
    }
    onClose();
  };

  const handleReset = () => {
    if (conversationId) {
      removeChatWallpaper(conversationId);
    } else {
      setGlobalWallpaper(DEFAULT_WALLPAPER);
    }
    setSelectedType("default");
    setSelectedValue("");
    setOpacity(1.0);
    setBlur(0);
  };

  const handleCustomUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      setSelectedType("custom");
      setSelectedValue(result);
    };
    reader.readAsDataURL(file);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  // Build style for live preview
  const getPreviewBackgroundStyle = () => {
    if (selectedType === "solid" && selectedValue) {
      return { backgroundColor: selectedValue };
    }
    if (selectedType === "pattern" && selectedValue) {
      const colors = selectedValue.split(",");
      if (colors.length >= 2) {
        return { background: `linear-gradient(135deg, ${colors[0]}, ${colors[1]})` };
      }
      return { backgroundColor: colors[0] };
    }
    if (selectedType === "custom" && selectedValue) {
      return {
        backgroundImage: `url(${selectedValue})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
      };
    }
    return { backgroundColor: currentTheme.backgroundColor };
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-4 animate-fade-in">
      <div className="flex flex-col md:flex-row w-full max-w-4xl max-h-[90vh] rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] shadow-2xl overflow-hidden text-[var(--theme-text-primary)]">
        
        {/* Left Side: Live Preview (Matching Android WallpaperSettingsScreen) */}
        <div className="w-full md:w-80 flex flex-col items-center justify-between p-6 border-b md:border-b-0 md:border-r border-[var(--theme-border-color)] bg-black/30">
          <div className="w-full text-center">
            <h3 className="font-extrabold text-base tracking-wide">Wallpaper Preview</h3>
            <p className="text-xs text-[var(--theme-text-secondary)] mt-0.5">
              {conversationName ? `Chat: ${conversationName}` : "Global Chat Theme"}
            </p>
          </div>

          {/* Live Mock Chat Bubble Box */}
          <div className="relative w-64 h-80 my-4 rounded-2xl overflow-hidden border border-white/10 shadow-2xl flex flex-col justify-end p-4">
            {/* Base Background */}
            <div
              className="absolute inset-0 transition-all duration-300"
              style={{
                ...getPreviewBackgroundStyle(),
                opacity: opacity,
                filter: blur > 0 ? `blur(${blur}px)` : "none",
              }}
            />

            {/* Mock Incoming Bubble */}
            <div
              className="relative z-10 max-w-[85%] rounded-2xl rounded-bl-none px-3.5 py-2.5 mb-3 text-xs shadow-md backdrop-blur-sm self-start"
              style={{
                backgroundColor: currentTheme.bubbleReceiver,
                color: currentTheme.textPrimary,
              }}
            >
              <p className="font-medium">How does this wallpaper look?</p>
              <span className="text-[9px] opacity-60 block text-right mt-1">10:42 AM</span>
            </div>

            {/* Mock Outgoing Bubble */}
            <div
              className="relative z-10 max-w-[85%] rounded-2xl rounded-br-none px-3.5 py-2.5 text-xs shadow-md backdrop-blur-sm self-end"
              style={{
                backgroundColor: currentTheme.bubbleSender,
                color: currentTheme.textPrimary,
              }}
            >
              <p className="font-semibold">Crisp, bold & vibrant! ✨</p>
              <span className="text-[9px] opacity-70 block text-right mt-1">10:43 AM ✓✓</span>
            </div>
          </div>

          {/* Sliders for Dimming & Blur */}
          <div className="w-full space-y-3 pt-2">
            <div className="space-y-1">
              <div className="flex justify-between text-xs font-semibold">
                <span className="text-[var(--theme-text-secondary)]">Dimming (Opacity)</span>
                <span className="text-[var(--theme-primary)]">{Math.round(opacity * 100)}%</span>
              </div>
              <input
                type="range"
                min="0.05"
                max="1.0"
                step="0.05"
                value={opacity}
                onChange={(e) => setOpacity(parseFloat(e.target.value))}
                className="w-full accent-[var(--theme-primary)] cursor-pointer h-1.5 bg-white/10 rounded-lg"
              />
            </div>

            <div className="space-y-1">
              <div className="flex justify-between text-xs font-semibold">
                <span className="text-[var(--theme-text-secondary)]">Blur Effect</span>
                <span className="text-[var(--theme-primary)]">{blur.toFixed(1)} px</span>
              </div>
              <input
                type="range"
                min="0"
                max="10"
                step="0.5"
                value={blur}
                onChange={(e) => setBlur(parseFloat(e.target.value))}
                className="w-full accent-[var(--theme-primary)] cursor-pointer h-1.5 bg-white/10 rounded-lg"
              />
            </div>
          </div>
        </div>

        {/* Right Side: Options and Grid */}
        <div className="flex-1 flex flex-col justify-between overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--theme-border-color)]">
            <div className="flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-[var(--theme-primary)]" />
              <h2 className="text-lg font-bold">Choose Wallpaper</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 rounded-xl hover:bg-white/10 text-[var(--theme-text-secondary)] hover:text-white transition-colors cursor-pointer"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          {/* Category Tabs */}
          <div className="flex border-b border-[var(--theme-border-color)] px-6">
            <button
              onClick={() => setActiveTab("pattern")}
              className={`flex items-center gap-2 py-3 px-4 text-xs font-bold border-b-2 cursor-pointer transition-colors ${
                activeTab === "pattern"
                  ? "border-[var(--theme-primary)] text-[var(--theme-primary)]"
                  : "border-transparent text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
              }`}
            >
              <Palette className="h-4 w-4" />
              Patterns & Gradients (30)
            </button>
            <button
              onClick={() => setActiveTab("solid")}
              className={`flex items-center gap-2 py-3 px-4 text-xs font-bold border-b-2 cursor-pointer transition-colors ${
                activeTab === "solid"
                  ? "border-[var(--theme-primary)] text-[var(--theme-primary)]"
                  : "border-transparent text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
              }`}
            >
              <Sliders className="h-4 w-4" />
              Solid Colors (20)
            </button>
            <button
              onClick={() => setActiveTab("custom")}
              className={`flex items-center gap-2 py-3 px-4 text-xs font-bold border-b-2 cursor-pointer transition-colors ${
                activeTab === "custom"
                  ? "border-[var(--theme-primary)] text-[var(--theme-primary)]"
                  : "border-transparent text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
              }`}
            >
              <ImageIcon className="h-4 w-4" />
              Custom Photo
            </button>
          </div>

          {/* Grid Content */}
          <div className="flex-1 overflow-y-auto p-6">
            {activeTab === "pattern" && (
              <div className="grid grid-cols-3 sm:grid-cols-5 gap-3">
                {WALLPAPER_GRADIENT_PATTERNS.map((p) => {
                  const valString = p.colors.join(",");
                  const isSelected = selectedType === "pattern" && selectedValue === valString;
                  return (
                    <button
                      key={p.id}
                      onClick={() => {
                        setSelectedType("pattern");
                        setSelectedValue(valString);
                      }}
                      className={`relative aspect-[3/4] rounded-xl overflow-hidden border-2 transition-all cursor-pointer group shadow-sm hover:scale-105 ${
                        isSelected ? "border-[var(--theme-primary)] scale-105 ring-2 ring-[var(--theme-primary)]/40" : "border-transparent hover:border-white/20"
                      }`}
                      style={{
                        background: `linear-gradient(135deg, ${p.colors[0]}, ${p.colors[1]})`,
                      }}
                    >
                      <span className="absolute bottom-1 inset-x-1 text-[10px] font-bold text-center bg-black/60 rounded py-0.5 text-white truncate px-1">
                        {p.label}
                      </span>
                      {isSelected && (
                        <div className="absolute top-1.5 right-1.5 bg-[var(--theme-primary)] text-white p-1 rounded-full shadow">
                          <Check className="h-3 w-3" />
                        </div>
                      )}
                    </button>
                  );
                })}
              </div>
            )}

            {activeTab === "solid" && (
              <div className="grid grid-cols-4 sm:grid-cols-5 gap-3">
                {WALLPAPER_SOLID_COLORS.map((hex) => {
                  const isSelected = selectedType === "solid" && selectedValue === hex;
                  return (
                    <button
                      key={hex}
                      onClick={() => {
                        setSelectedType("solid");
                        setSelectedValue(hex);
                      }}
                      className={`relative aspect-[3/4] rounded-xl border-2 transition-all cursor-pointer shadow-sm hover:scale-105 ${
                        isSelected ? "border-[var(--theme-primary)] scale-105 ring-2 ring-[var(--theme-primary)]/40" : "border-white/10 hover:border-white/30"
                      }`}
                      style={{ backgroundColor: hex }}
                    >
                      {isSelected && (
                        <div className="absolute top-1.5 right-1.5 bg-[var(--theme-primary)] text-white p-1 rounded-full shadow">
                          <Check className="h-3 w-3" />
                        </div>
                      )}
                    </button>
                  );
                })}
              </div>
            )}

            {activeTab === "custom" && (
              <div className="flex flex-col items-center justify-center h-full min-h-[220px] text-center p-6 border-2 border-dashed border-[var(--theme-border-color)] rounded-2xl">
                <input
                  type="file"
                  ref={fileInputRef}
                  onChange={handleCustomUpload}
                  accept="image/*"
                  className="hidden"
                />
                <ImageIcon className="h-12 w-12 text-[var(--theme-text-secondary)] mb-3" />
                <h4 className="font-bold text-sm mb-1">Upload Your Custom Wallpaper</h4>
                <p className="text-xs text-[var(--theme-text-secondary)] max-w-sm mb-4">
                  Select any high-resolution photo or background from your computer.
                </p>
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="px-5 py-2.5 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-opacity cursor-pointer shadow"
                >
                  Browse Image
                </button>
              </div>
            )}
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-between px-6 py-4 border-t border-[var(--theme-border-color)] bg-black/10">
            <button
              onClick={handleReset}
              className="flex items-center gap-1.5 text-xs font-bold text-red-400 hover:text-red-300 transition-colors cursor-pointer"
            >
              <Trash2 className="h-4 w-4" />
              Reset Wallpaper
            </button>

            <div className="flex items-center gap-3">
              {conversationId && (
                <button
                  onClick={() => handleApply(false)}
                  className="px-4 py-2 rounded-xl border border-[var(--theme-border-color)] hover:bg-white/10 text-xs font-bold transition-all cursor-pointer"
                >
                  Set for this chat
                </button>
              )}
              <button
                onClick={() => handleApply(true)}
                className="px-5 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-opacity cursor-pointer shadow"
              >
                Set for All Chats
              </button>
            </div>
          </div>

        </div>

      </div>
    </div>
  );
}
