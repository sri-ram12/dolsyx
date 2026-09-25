"use client";

import React, { createContext, useContext, useState, useEffect } from "react";
import {
  ChatTheme,
  DOLSYX_THEMES,
  getThemeById,
  applyThemeToDocument,
  WallpaperConfig,
  DEFAULT_WALLPAPER,
} from "@/utils/dolsyx-themes";

export type LegacyThemeType = "dolsy-dark" | "aqua-light" | "aqua-dark" | "radiant-blue";
export type ThemeType = LegacyThemeType | string;
export type FontSizeType = "small" | "medium" | "large";

interface ThemeContextType {
  theme: ThemeType;
  currentTheme: ChatTheme;
  setTheme: (themeId: ThemeType) => void;
  fontSize: FontSizeType;
  setFontSize: (size: FontSizeType) => void;
  // Wallpaper settings
  globalWallpaper: WallpaperConfig;
  setGlobalWallpaper: (config: WallpaperConfig) => void;
  getWallpaperForChat: (conversationId: string) => WallpaperConfig;
  setChatWallpaper: (conversationId: string, config: WallpaperConfig) => void;
  removeChatWallpaper: (conversationId: string) => void;
  wallpaperOpacity: number;
  setWallpaperOpacity: (opacity: number, conversationId?: string) => void;
  wallpaperBlur: number;
  setWallpaperBlur: (blur: number, conversationId?: string) => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

// Legacy theme mapping to Android IDs
const LEGACY_TO_ANDROID_MAP: Record<LegacyThemeType, string> = {
  "dolsy-dark": "midnight_black",
  "aqua-light": "default_whatsapp",
  "aqua-dark": "emerald_oasis",
  "radiant-blue": "titanium_eclipse",
};

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [themeId, setThemeId] = useState<string>("slate_gray");
  const [currentTheme, setCurrentTheme] = useState<ChatTheme>(getThemeById("slate_gray"));
  const [fontSize, setFontSizeState] = useState<FontSizeType>("medium");

  const [globalWallpaper, setGlobalWallpaperState] = useState<WallpaperConfig>(DEFAULT_WALLPAPER);
  const [chatWallpapers, setChatWallpapers] = useState<Record<string, WallpaperConfig>>({});

  const applyTheme = (id: string) => {
    // Map legacy names if passed
    const resolvedId = LEGACY_TO_ANDROID_MAP[id as LegacyThemeType] || id;
    const themeObj = getThemeById(resolvedId);
    setCurrentTheme(themeObj);
    applyThemeToDocument(themeObj);
  };

  const applyFontSize = (size: FontSizeType) => {
    if (typeof window === "undefined") return;
    const root = window.document.documentElement;
    root.classList.remove("font-scale-small", "font-scale-medium", "font-scale-large");
    root.classList.add(`font-scale-${size}`);
  };

  useEffect(() => {
    if (typeof window === "undefined") return;

    // Load theme
    const storedTheme = localStorage.getItem("dolsyx_theme") || "slate_gray";
    const resolvedId = LEGACY_TO_ANDROID_MAP[storedTheme as LegacyThemeType] || storedTheme;
    setThemeId(resolvedId);
    applyTheme(resolvedId);

    // Load font size
    const storedFontSize = localStorage.getItem("dolsyx_fontsize") as FontSizeType;
    const validFonts: FontSizeType[] = ["small", "medium", "large"];
    const initialFont = validFonts.includes(storedFontSize) ? storedFontSize : "medium";
    setFontSizeState(initialFont);
    applyFontSize(initialFont);

    // Load global wallpaper
    try {
      const storedWp = localStorage.getItem("dolsyx_global_wallpaper");
      if (storedWp) {
        setGlobalWallpaperState(JSON.parse(storedWp));
      }
      const storedChatWp = localStorage.getItem("dolsyx_chat_wallpapers_map");
      if (storedChatWp) {
        setChatWallpapers(JSON.parse(storedChatWp));
      }
    } catch (_) {}
  }, []);

  const setTheme = (newThemeId: ThemeType) => {
    const resolvedId = LEGACY_TO_ANDROID_MAP[newThemeId as LegacyThemeType] || newThemeId;
    setThemeId(resolvedId);
    localStorage.setItem("dolsyx_theme", resolvedId);
    applyTheme(resolvedId);
  };

  const setFontSize = (size: FontSizeType) => {
    setFontSizeState(size);
    localStorage.setItem("dolsyx_fontsize", size);
    applyFontSize(size);
  };

  const setGlobalWallpaper = (config: WallpaperConfig) => {
    setGlobalWallpaperState(config);
    localStorage.setItem("dolsyx_global_wallpaper", JSON.stringify(config));
  };

  const getWallpaperForChat = (conversationId: string): WallpaperConfig => {
    return chatWallpapers[conversationId] || globalWallpaper;
  };

  const setChatWallpaper = (conversationId: string, config: WallpaperConfig) => {
    const updated = { ...chatWallpapers, [conversationId]: config };
    setChatWallpapers(updated);
    localStorage.setItem("dolsyx_chat_wallpapers_map", JSON.stringify(updated));
  };

  const removeChatWallpaper = (conversationId: string) => {
    const updated = { ...chatWallpapers };
    delete updated[conversationId];
    setChatWallpapers(updated);
    localStorage.setItem("dolsyx_chat_wallpapers_map", JSON.stringify(updated));
  };

  const setWallpaperOpacity = (opacity: number, conversationId?: string) => {
    if (conversationId) {
      const current = getWallpaperForChat(conversationId);
      setChatWallpaper(conversationId, { ...current, opacity });
    } else {
      setGlobalWallpaper({ ...globalWallpaper, opacity });
    }
  };

  const setWallpaperBlur = (blur: number, conversationId?: string) => {
    if (conversationId) {
      const current = getWallpaperForChat(conversationId);
      setChatWallpaper(conversationId, { ...current, blur });
    } else {
      setGlobalWallpaper({ ...globalWallpaper, blur });
    }
  };

  return (
    <ThemeContext.Provider
      value={{
        theme: themeId,
        currentTheme,
        setTheme,
        fontSize,
        setFontSize,
        globalWallpaper,
        setGlobalWallpaper,
        getWallpaperForChat,
        setChatWallpaper,
        removeChatWallpaper,
        wallpaperOpacity: globalWallpaper.opacity,
        setWallpaperOpacity,
        wallpaperBlur: globalWallpaper.blur,
        setWallpaperBlur,
      }}
    >
      {children}
    </ThemeContext.Provider>
  );
};

export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within a ThemeProvider");
  }
  return context;
};
