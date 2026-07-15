"use client";

import { useEffect } from "react";
import { useAuth } from "@/context/auth-context";
import { useRouter } from "next/navigation";

export default function Home() {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!isLoading) {
      if (isAuthenticated) {
        router.push("/chat");
      } else {
        router.push("/login");
      }
    }
  }, [isAuthenticated, isLoading, router]);

  return (
    <div className="flex h-screen w-full items-center justify-center bg-zinc-950">
      <div className="flex flex-col items-center gap-4">
        <div className="text-4xl font-extrabold tracking-widest text-transparent bg-clip-text bg-gradient-to-r from-violet-400 via-fuchsia-500 to-indigo-400 animate-pulse">
          DOLSYX
        </div>
        <div className="h-1 w-20 overflow-hidden rounded-full bg-zinc-800">
          <div className="h-full w-full origin-left animate-[pulse_1.5s_infinite_ease-in-out] bg-gradient-to-r from-violet-500 to-fuchsia-500" />
        </div>
      </div>
    </div>
  );
}
