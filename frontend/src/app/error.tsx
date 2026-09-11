"use client";

import React, { useEffect } from "react";
import { AlertTriangle, RefreshCw, Home } from "lucide-react";
import Link from "next/link";

interface ErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function GlobalRouteError({ error, reset }: ErrorProps) {
  useEffect(() => {
    // Log client error for debugging or send to APM/monitoring
    console.error("[DOLSYX Client Error Boundary Caught]:", error);
  }, [error]);

  return (
    <div className="min-h-screen w-full flex items-center justify-center bg-[#0b0e14] text-white p-6">
      <div className="max-w-md w-full bg-[#151922] border border-[#232936] rounded-2xl p-8 text-center shadow-2xl backdrop-blur-md">
        <div className="w-16 h-16 rounded-full bg-rose-500/10 border border-rose-500/20 text-rose-400 flex items-center justify-center mx-auto mb-6">
          <AlertTriangle className="w-8 h-8 animate-pulse" />
        </div>

        <h2 className="text-2xl font-bold tracking-tight mb-2">Something went wrong</h2>
        <p className="text-gray-400 text-sm mb-6 leading-relaxed">
          We encountered an unexpected display error. Your messages and account data remain completely safe.
        </p>

        {error?.digest && (
          <div className="bg-[#0b0e14] rounded-lg p-3 mb-6 text-left border border-[#232936]">
            <p className="text-xs text-gray-500 font-mono">Error Reference:</p>
            <p className="text-xs text-rose-400 font-mono truncate">{error.digest}</p>
          </div>
        )}

        <div className="flex flex-col sm:flex-row gap-3">
          <button
            onClick={() => reset()}
            className="flex-1 inline-flex items-center justify-center gap-2 px-5 py-3 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-medium text-sm transition shadow-lg shadow-blue-600/25 active:scale-95 cursor-pointer"
          >
            <RefreshCw className="w-4 h-4" />
            Try Again
          </button>

          <Link
            href="/chat"
            className="flex-1 inline-flex items-center justify-center gap-2 px-5 py-3 rounded-xl bg-[#232936] hover:bg-[#2e3646] text-gray-300 hover:text-white font-medium text-sm transition active:scale-95"
          >
            <Home className="w-4 h-4" />
            Return to Chats
          </Link>
        </div>
      </div>
    </div>
  );
}
