"use client";

import React, { createContext, useContext, useEffect, useState } from "react";
import { io, Socket } from "socket.io-client";
import { useAuth, API_URL } from "@/context/auth-context";

interface SocketContextType {
  socket: Socket | null;
  isConnected: boolean;
}

const SocketContext = createContext<SocketContextType>({
  socket: null,
  isConnected: false,
});

export const SocketProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { token, logout } = useAuth();
  const [socket, setSocket] = useState<Socket | null>(null);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    if (!token) {
      if (socket) {
        socket.disconnect();
      }
      setSocket(null);
      setIsConnected(false);
      return;
    }

    const targetUrl = typeof window !== "undefined" && (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1")
      ? (process.env.NEXT_PUBLIC_SOCKET_URL && !process.env.NEXT_PUBLIC_SOCKET_URL.includes("onrender.com")
          ? process.env.NEXT_PUBLIC_SOCKET_URL.replace(/\/+$/, "")
          : `http://${window.location.hostname}:4000`)
      : (process.env.NEXT_PUBLIC_SOCKET_URL?.replace(/\/+$/, "") || API_URL);

    const newSocket = io(targetUrl, {
      auth: { token },
      autoConnect: true,
      reconnectionAttempts: 10,
      reconnectionDelay: 1000,
      transports: ["websocket", "polling"],
    });

    setSocket(newSocket);

    newSocket.on("connect", () => {
      setIsConnected(true);
    });

    newSocket.on("disconnect", () => {
      setIsConnected(false);
    });

    newSocket.on("connect_error", (err) => {
      console.warn("[Socket] Connection attempt status:", err.message);
      setIsConnected(false);

      // If server rejects token as expired or invalid, log out stale session to stop retry storm
      if (
        err.message &&
        (err.message.includes("Authentication error") ||
         err.message.includes("jwt expired") ||
         err.message.includes("Invalid token") ||
         err.message.includes("Token missing"))
      ) {
        console.warn("[Socket] Stale token rejected by server, resetting session...");
        logout();
      }
    });

    // Handle real-time device revocation from mobile
    newSocket.on("DEVICE_REVOKED", (data) => {
      console.warn("[Auth] Device session revoked remotely:", data);
      logout();
      if (typeof window !== "undefined") {
        alert("This device was logged out from another DOLSYX device.");
      }
    });

    return () => {
      newSocket.disconnect();
      setSocket(null);
      setIsConnected(false);
    };
  }, [token]);

  return (
    <SocketContext.Provider value={{ socket, isConnected }}>
      {children}
    </SocketContext.Provider>
  );
};

export const useSocketContext = () => useContext(SocketContext);
