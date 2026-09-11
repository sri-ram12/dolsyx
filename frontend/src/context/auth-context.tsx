"use client";

import React, { createContext, useContext, useState, useEffect } from "react";
import { useRouter } from "next/navigation";

export interface User {
  id: string;
  username: string;
  email?: string | null;
  phoneNumber?: string | null;
  avatarUrl: string | null;
  bio?: string | null;
  lastSeen?: string | null;
  createdAt: string;
}

interface AuthContextType {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (token: string, user: User) => void;
  logout: () => void;
  updateUser: (user: User) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const API_URL = typeof window !== "undefined"
  ? (process.env.NEXT_PUBLIC_API_URL || 
      (process.env.NODE_ENV === "development" 
        ? `${window.location.protocol}//${window.location.hostname}:4000` 
        : window.location.origin))
  : (process.env.NEXT_PUBLIC_API_URL || "http://localhost:4000");

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(() => {
    if (typeof window !== "undefined") {
      try {
        const cached = localStorage.getItem("dolsyx_user");
        return cached ? JSON.parse(cached) : null;
      } catch (_) {}
    }
    return null;
  });
  const [token, setToken] = useState<string | null>(() => {
    if (typeof window !== "undefined") {
      return localStorage.getItem("dolsyx_token");
    }
    return null;
  });
  const [isLoading, setIsLoading] = useState<boolean>(() => {
    if (typeof window !== "undefined") {
      // If we have cached token & user, we are already interactive
      return !localStorage.getItem("dolsyx_token");
    }
    return true;
  });
  const router = useRouter();

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch((err) => {
        console.error('Service Worker registration failed:', err);
      });
    }
  }, []);

  useEffect(() => {
    const initializeAuth = async () => {
      const storedToken = localStorage.getItem("dolsyx_token");
      if (!storedToken) {
        setIsLoading(false);
        return;
      }

      // 10-second background verification
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000);

      try {
        const res = await fetch(`${API_URL}/api/auth/me`, {
          headers: {
            Authorization: `Bearer ${storedToken}`,
          },
          signal: controller.signal,
        });

        if (res.ok) {
          const data = await res.json();
          setUser(data.user);
          setToken(storedToken);
          localStorage.setItem("dolsyx_user", JSON.stringify(data.user));
        } else if (res.status === 401 || res.status === 403) {
          // Token is strictly invalid/expired by the server
          localStorage.removeItem("dolsyx_token");
          localStorage.removeItem("dolsyx_user");
          setToken(null);
          setUser(null);
        }
      } catch (err: any) {
        // Network timeout / offline / connection drop: DO NOT wipe user session
        console.warn("[Auth] Background session revalidation skipped (offline/slow connection):", err.message || err);
      } finally {
        clearTimeout(timeoutId);
        setIsLoading(false);
      }
    };

    initializeAuth();
  }, []);

  const login = (newToken: string, newUser: User) => {
    localStorage.setItem("dolsyx_token", newToken);
    localStorage.setItem("dolsyx_user", JSON.stringify(newUser));
    setToken(newToken);
    setUser(newUser);
    router.push("/chat");
  };

  const logout = async () => {
    const storedToken = localStorage.getItem("dolsyx_token");
    if (storedToken) {
      try {
        await fetch(`${API_URL}/api/auth/logout`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${storedToken}`,
          },
        });
      } catch (err) {
        console.error("Failed to notify backend of logout:", err);
      }
    }
    localStorage.removeItem("dolsyx_token");
    localStorage.removeItem("dolsyx_user");
    localStorage.removeItem("dolsyx_pin_hash");
    localStorage.removeItem("dolsyx_bio_enabled");
    sessionStorage.removeItem("dolsyx_unlocked");
    setToken(null);
    setUser(null);
    router.push("/login");
  };

  const updateUser = (updatedUser: User) => {
    setUser(updatedUser);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        isAuthenticated: !!user,
        isLoading,
        login,
        logout,
        updateUser,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
};
