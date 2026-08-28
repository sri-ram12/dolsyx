"use client";

import React, { useState } from "react";
import Link from "next/link";
import { Trash2, AlertOctagon, CheckCircle2, ArrowLeft, ShieldAlert, Loader2 } from "lucide-react";

export default function DeleteAccountPage() {
  const [email, setEmail] = useState("");
  const [reason, setReason] = useState("");
  const [confirmUnderstood, setConfirmUnderstood] = useState(false);
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [message, setMessage] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !confirmUnderstood) return;

    setStatus("loading");
    setMessage("");

    try {
      const res = await fetch("/api/auth/request-account-deletion", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim().toLowerCase(), reason }),
      });

      const data = await res.json();
      if (res.ok) {
        setStatus("success");
        setMessage(
          data.message ||
            "Your deletion request has been processed. All personal data and account records will be permanently removed within 24 hours."
        );
      } else {
        setStatus("error");
        setMessage(data.message || "Failed to process request. Please contact support@dolsyx.com");
      }
    } catch (err) {
      setStatus("error");
      setMessage("Network error. Please try again or contact support@dolsyx.com");
    }
  };

  return (
    <div className="min-h-screen bg-[#0b141a] text-[#e9edef] overflow-y-auto px-4 py-8 md:py-16">
      <div className="max-w-2xl mx-auto">
        {/* Navigation */}
        <div className="mb-8 flex items-center justify-between border-b border-[#222d34] pb-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-[#00a884] hover:underline text-sm font-medium"
          >
            <ArrowLeft className="w-4 h-4" /> Back to DOLSYX
          </Link>
          <span className="text-xs text-[#8696a0]">Google Play Compliant Data Portal</span>
        </div>

        {/* Title */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center p-3 rounded-full bg-red-500/10 text-red-400 mb-4">
            <Trash2 className="w-10 h-10" />
          </div>
          <h1 className="text-3xl font-bold tracking-tight text-white mb-2">
            Request Account & Data Deletion
          </h1>
          <p className="text-[#8696a0] text-sm md:text-base">
            Under Google Play user data policy, you can permanently delete your DOLSYX account and all associated personal data.
          </p>
        </div>

        {/* Informational Warning */}
        <div className="bg-red-500/10 border border-red-500/30 rounded-2xl p-5 mb-8">
          <div className="flex items-start gap-3">
            <ShieldAlert className="w-6 h-6 text-red-400 shrink-0 mt-0.5" />
            <div className="text-sm">
              <h2 className="font-semibold text-red-400 mb-1">What happens when you delete your account?</h2>
              <ul className="list-disc list-inside space-y-1 text-[#d1d7db] text-xs md:text-sm">
                <li>Your profile details (display name, username, bio, and avatar) will be permanently erased.</li>
                <li>Your End-to-End Encryption cryptographic identity keys and device sessions will be deleted.</li>
                <li>Your contact links, group memberships, and call histories will be cleared.</li>
                <li>This action is <strong>irreversible</strong> and cannot be undone.</li>
              </ul>
            </div>
          </div>
        </div>

        {status === "success" ? (
          <div className="bg-[#111b21] p-8 rounded-2xl border border-[#00a884]/40 text-center space-y-4">
            <div className="inline-flex p-3 rounded-full bg-[#00a884]/20 text-[#00a884]">
              <CheckCircle2 className="w-12 h-12" />
            </div>
            <h3 className="text-xl font-bold text-white">Deletion Request Submitted</h3>
            <p className="text-[#8696a0] text-sm leading-relaxed">{message}</p>
            <div className="pt-4">
              <Link
                href="/"
                className="inline-block px-6 py-2.5 bg-[#00a884] text-[#111b21] font-semibold rounded-xl hover:bg-[#00c298] transition-colors text-sm"
              >
                Return to Home
              </Link>
            </div>
          </div>
        ) : (
          <form
            onSubmit={handleSubmit}
            className="bg-[#111b21] p-6 md:p-8 rounded-2xl border border-[#222d34] space-y-6"
          >
            {status === "error" && (
              <div className="p-4 bg-red-500/20 border border-red-500/40 rounded-xl text-red-300 text-sm flex items-center gap-2">
                <AlertOctagon className="w-5 h-5 shrink-0" />
                <span>{message}</span>
              </div>
            )}

            <div>
              <label className="block text-xs font-semibold text-[#8696a0] uppercase tracking-wider mb-2">
                Registered Email Address or Phone <span className="text-red-400">*</span>
              </label>
              <input
                type="text"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="e.g. user@example.com or +1234567890"
                className="w-full px-4 py-3 bg-[#0b141a] border border-[#222d34] rounded-xl text-white placeholder-[#8696a0] focus:outline-none focus:border-[#00a884] text-sm"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-[#8696a0] uppercase tracking-wider mb-2">
                Reason for leaving (Optional)
              </label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={3}
                placeholder="Help us improve (optional feedback)"
                className="w-full px-4 py-3 bg-[#0b141a] border border-[#222d34] rounded-xl text-white placeholder-[#8696a0] focus:outline-none focus:border-[#00a884] text-sm resize-none"
              />
            </div>

            <div className="flex items-start gap-3 pt-2">
              <input
                type="checkbox"
                id="confirm"
                checked={confirmUnderstood}
                onChange={(e) => setConfirmUnderstood(e.target.checked)}
                className="mt-1 w-4 h-4 rounded border-[#222d34] bg-[#0b141a] text-[#00a884] focus:ring-[#00a884]"
              />
              <label htmlFor="confirm" className="text-xs text-[#8696a0] cursor-pointer">
                I understand that deleting my account is permanent and all associated messages, keys, and profile records will be permanently deleted.
              </label>
            </div>

            <button
              type="submit"
              disabled={!confirmUnderstood || !email || status === "loading"}
              className="w-full py-3.5 px-4 bg-red-600 hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 text-sm shadow-lg shadow-red-900/20"
            >
              {status === "loading" ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  Processing Deletion...
                </>
              ) : (
                <>
                  <Trash2 className="w-4 h-4" />
                  Permanently Delete My DOLSYX Account
                </>
              )}
            </button>
          </form>
        )}

        {/* Footer */}
        <div className="mt-12 text-center text-xs text-[#8696a0] border-t border-[#222d34] pt-6 flex flex-wrap justify-center gap-6">
          <Link href="/privacy" className="hover:text-white transition-colors">Privacy Policy</Link>
          <Link href="/terms" className="hover:text-white transition-colors">Terms of Service</Link>
          <span>&copy; {new Date().getFullYear()} DOLSYX. All rights reserved.</span>
        </div>
      </div>
    </div>
  );
}
