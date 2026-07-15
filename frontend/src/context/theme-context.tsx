"use client";

import React, { createContext, useContext, useState, useEffect } from "react";

export type ThemeType = "dolsy-dark" | "aqua-light" | "aqua-dark";

interface ThemeContextType {
  theme: ThemeType;
  setTheme: (theme: ThemeType) => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [theme, setThemeState] = useState<ThemeType>("dolsy-dark");

  useEffect(() => {
    // Read theme from localStorage on load
    const storedTheme = localStorage.getItem("dolsyx_theme") as ThemeType;
    if (storedTheme && ["dolsy-dark", "aqua-light", "aqua-dark"].includes(storedTheme)) {
      setThemeState(storedTheme);
      applyTheme(storedTheme);
    } else {
      applyTheme("dolsy-dark");
    }
  }, []);

  const applyTheme = (newTheme: ThemeType) => {
    if (typeof window === "undefined") return;
    const root = window.document.documentElement;
    
    // Remove existing themes
    root.classList.remove("theme-dolsy", "theme-aqua-light", "theme-aqua-dark");
    
    // Add new theme class
    if (newTheme === "aqua-light") {
      root.classList.add("theme-aqua-light");
      root.style.colorScheme = "light";
    } else if (newTheme === "aqua-dark") {
      root.classList.add("theme-aqua-dark");
      root.style.colorScheme = "dark";
    } else {
      root.classList.add("theme-dolsy");
      root.style.colorScheme = "dark";
    }
  };

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
