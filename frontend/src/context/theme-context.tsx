"use client";

import React, { createContext, useContext, useState, useEffect } from "react";

export type ThemeType = "dolsy-dark" | "aqua-light" | "aqua-dark" | "radiant-blue";

interface ThemeContextType {
  theme: ThemeType;
  setTheme: (theme: ThemeType) => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

// Maps theme ID → CSS class on <html> (must match globals.css selectors)
const THEME_CLASS_MAP: Record<ThemeType, string> = {
  "dolsy-dark": "",                   // :root (default) — no extra class needed
  "aqua-light": "theme-whatsapp-light",
  "aqua-dark": "theme-whatsapp-dark",
  "radiant-blue": "theme-radiant-blue",
};

const ALL_THEME_CLASSES = Object.values(THEME_CLASS_MAP).filter(Boolean);

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [theme, setThemeState] = useState<ThemeType>("dolsy-dark");

  const applyTheme = (newTheme: ThemeType) => {
    if (typeof window === "undefined") return;
    const root = window.document.documentElement;
    // Remove all theme classes first
    root.classList.remove(...ALL_THEME_CLASSES);
    // Apply the correct class (empty string = default dark, no class added)
    const cls = THEME_CLASS_MAP[newTheme];
    if (cls) root.classList.add(cls);
    // Set color-scheme for browser chrome
    root.style.colorScheme = newTheme === "aqua-light" ? "light" : "dark";
  };

  useEffect(() => {
    const storedTheme = localStorage.getItem("dolsyx_theme") as ThemeType;
    const valid: ThemeType[] = ["dolsy-dark", "aqua-light", "aqua-dark"];
    const initial = valid.includes(storedTheme) ? storedTheme : "dolsy-dark";
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setThemeState(initial);
    applyTheme(initial);
  }, []);

  const setTheme = (newTheme: ThemeType) => {
    setThemeState(newTheme);
    localStorage.setItem("dolsyx_theme", newTheme);
    applyTheme(newTheme);
  };

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
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
