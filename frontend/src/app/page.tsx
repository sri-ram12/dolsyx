"use client";

import { useEffect } from "react";
import { useAuth } from "@/context/auth-context";
import { useRouter } from "next/navigation";

export default function Home() {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  // We rely on the video onEnded event to navigate now
  // but if it fails to load or user wants to skip we could add a skip button, 
  // for now we'll just wait for the video to end.

  return (
    <div className="flex h-screen w-full items-center justify-center bg-black overflow-hidden relative">
      <video
        src="/intro.mp4"
        autoPlay
        muted
        playsInline
        className="w-full h-full object-contain"
        onEnded={() => {
          if (isAuthenticated) {
            router.push("/chat");
          } else {
            router.push("/login");
          }
        }}
      />
    </div>
  );
}
