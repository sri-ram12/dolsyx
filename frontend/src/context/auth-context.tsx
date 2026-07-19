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
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const initializeAuth = async () => {
      const storedToken = localStorage.getItem("dolsyx_token");
      if (!storedToken) {
        setIsLoading(false);
        return;
      }

      // Abort after 10 seconds to prevent hanging on slow tunnel connections
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
        } else {
          // Token is invalid/expired
          localStorage.removeItem("dolsyx_token");
        }
      } catch (err: any) {
        if (err?.name === "AbortError") {
          console.warn("Auth init timed out – clearing token");
          localStorage.removeItem("dolsyx_token");
        } else {
          console.error("Auth init error:", err);
        }
      } finally {
        clearTimeout(timeoutId);
        setIsLoading(false);
      }
    };

    initializeAuth();
  }, []);

  const login = (newToken: string, newUser: User) => {
    localStorage.setItem("dolsyx_token", newToken);
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
