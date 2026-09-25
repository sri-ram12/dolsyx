"use client";

import { useEffect, useRef, useCallback } from "react";
import { useAuth } from "@/context/auth-context";
import { useRouter } from "next/navigation";

export default function Home() {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);

  const navigateDestination = useCallback(() => {
    const hasToken = typeof window !== "undefined" && !!localStorage.getItem("dolsyx_token");
    if (isAuthenticated || hasToken) {
      router.replace("/chat");
    } else {
      router.replace("/login");
    }
  }, [isAuthenticated, router]);

  useEffect(() => {
    // If already authenticated with a saved token, bypass intro immediately for fast startup
    const hasToken = typeof window !== "undefined" && !!localStorage.getItem("dolsyx_token");
    if (hasToken) {
      navigateDestination();
      return;
    }

    // Safety fallback: if video is slow or blocked, don't leave user hanging
    const timer = setTimeout(() => {
      navigateDestination();
    }, 4500);

    return () => clearTimeout(timer);
  }, [navigateDestination]);

  return (
    <div 
      className="flex h-screen w-full items-center justify-center bg-black overflow-hidden relative cursor-pointer select-none"
      onClick={navigateDestination}
    >
      <video
        ref={videoRef}
        src="/intro.mp4"
        autoPlay
        muted
        playsInline
        className="w-full h-full object-contain"
        onEnded={navigateDestination}
        onError={navigateDestination}
      />

      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          navigateDestination();
        }}
        className="absolute bottom-8 right-8 z-20 px-4 py-2 rounded-full bg-white/10 hover:bg-white/20 text-white/80 text-sm backdrop-blur-md border border-white/10 transition-all duration-200"
      >
        Skip &rarr;
      </button>
    </div>
  );
}
