import React from "react";
import Link from "next/link";
import { MessageSquare, ArrowLeft } from "lucide-react";

export default function NotFound() {
  return (
    <div className="min-h-screen w-full flex items-center justify-center bg-[#0b0e14] text-white p-6">
      <div className="max-w-md w-full bg-[#151922] border border-[#232936] rounded-2xl p-8 text-center shadow-2xl">
        <div className="w-16 h-16 rounded-full bg-blue-500/10 border border-blue-500/20 text-blue-400 flex items-center justify-center mx-auto mb-6">
          <MessageSquare className="w-8 h-8" />
        </div>

        <h1 className="text-4xl font-extrabold tracking-tight mb-2 text-white">404</h1>
        <h2 className="text-lg font-semibold text-gray-200 mb-2">Page Not Found</h2>
        <p className="text-gray-400 text-sm mb-6 leading-relaxed">
          The conversation or page you are looking for doesn't exist or may have been moved.
        </p>

        <Link
          href="/chat"
          className="inline-flex items-center justify-center gap-2 w-full px-5 py-3 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-medium text-sm transition shadow-lg shadow-blue-600/25 active:scale-95"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to DOLSYX Chats
        </Link>
      </div>
    </div>
  );
}
