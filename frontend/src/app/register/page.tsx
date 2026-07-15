"use client";

import React, { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function RegisterPage() {
  const router = useRouter();

  useEffect(() => {
    router.replace("/login");
  }, [router]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-950 text-white">
      <div className="h-5 w-5 animate-spin rounded-full border-2 border-violet-500 border-t-transparent" />
    </div>
  );
}
