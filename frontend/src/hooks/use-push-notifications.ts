"use client";

import { useEffect } from "react";

export function usePushNotifications() {
  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!("serviceWorker" in navigator)) return;
    if (!("Notification" in window)) return;

    // Register the service worker
    navigator.serviceWorker
      .register("/sw.js")
      .then((reg) => {
        // SW Registered
      })
      .catch((err) => {
        console.warn("[SW] Registration failed:", err);
      });

    // Request notification permission if not already granted
    if (Notification.permission === "default") {
      Notification.requestPermission().then((perm) => {
        // Permission status
      });
    }
  }, []);
}
