"use client";

import React, { useEffect } from "react";

export default function RootGlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[DOLSYX Root Global Error Caught]:", error);
  }, [error]);

  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0, backgroundColor: "#0b0e14", color: "#ffffff", fontFamily: "system-ui, -apple-system, sans-serif" }}>
        <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", padding: "24px" }}>
          <div style={{ maxWidth: "440px", width: "100%", backgroundColor: "#151922", border: "1px solid #232936", borderRadius: "16px", padding: "32px", textAlign: "center", boxShadow: "0 25px 50px -12px rgba(0,0,0,0.5)" }}>
            <h1 style={{ fontSize: "22px", fontWeight: "700", marginBottom: "8px", color: "#f43f5e" }}>Critical Error</h1>
            <p style={{ color: "#9ca3af", fontSize: "14px", lineHeight: "1.6", marginBottom: "24px" }}>
              The application encountered a fatal initialization error. Please reload to restore session.
            </p>
            <button
              onClick={() => reset()}
              style={{
                backgroundColor: "#2563eb",
                color: "#ffffff",
                border: "none",
                padding: "12px 24px",
                borderRadius: "10px",
                fontSize: "14px",
                fontWeight: "600",
                cursor: "pointer",
                width: "100%"
              }}
            >
              Reload Application
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
