"use client";

import React, { useEffect, useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useAuth, API_URL } from "@/context/auth-context";
import { Loader2, ShieldAlert, CheckCircle2, User, ArrowRight } from "lucide-react";

function GoogleCallbackContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { login } = useAuth();

  const [status, setStatus] = useState<"processing" | "needs-username" | "success" | "error">("processing");
  const [errorMessage, setErrorMessage] = useState("");
  const [token, setToken] = useState("");
  const [username, setUsername] = useState("");
  const [isSubmittingUsername, setIsSubmittingUsername] = useState(false);

  useEffect(() => {
    const errorParam = searchParams.get("error");
    const tokenParam = searchParams.get("token");
    const needsUsernameParam = searchParams.get("needsUsername");

    if (errorParam) {
      setStatus("error");
      const friendlyMessages: Record<string, string> = {
        access_denied: "Google authentication was cancelled or access was denied.",
        invalid_oauth_state: "Security validation failed (OAuth state mismatch). Please try again.",
        missing_oauth_parameters: "Invalid request parameters from Google.",
        unverified_google_email: "Your Google account email is not verified.",
      };
      setErrorMessage(friendlyMessages[errorParam] || decodeURIComponent(errorParam));
      return;
    }

    if (!tokenParam) {
      setStatus("error");
      setErrorMessage("No authentication session token was returned.");
      return;
    }

    setToken(tokenParam);

    if (needsUsernameParam === "true") {
      setStatus("needs-username");
    } else {
      completeAuth(tokenParam);
    }
  }, [searchParams]);

  const completeAuth = async (sessionToken: string) => {
    try {
      setStatus("processing");
      const res = await fetch(`${API_URL}/api/auth/me`, {
        headers: { Authorization: `Bearer ${sessionToken}` },
      });

      if (res.ok) {
        const userData = await res.json();
        setStatus("success");
        setTimeout(() => {
          login(sessionToken, userData.user || userData);
          router.push("/chat");
        }, 600);
      } else {
        setStatus("error");
        setErrorMessage("Failed to verify user profile.");
      }
    } catch {
      setStatus("error");
      setErrorMessage("Failed to connect to DOLSYX authentication service.");
    }
  };

  const handleUsernameSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username.trim()) return;

    setIsSubmittingUsername(true);
    setErrorMessage("");

    try {
      const res = await fetch(`${API_URL}/api/auth/username/setup`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ username: username.trim().toLowerCase() }),
      });

      const data = await res.json();
      if (res.ok) {
        await completeAuth(token);
      } else {
        setErrorMessage(data.message || "Failed to set username.");
      }
    } catch {
      setErrorMessage("Network error setting up username.");
    } finally {
      setIsSubmittingUsername(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--theme-bg-app)] px-4">
      <div className="w-full max-w-md rounded-3xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] p-8 shadow-2xl backdrop-blur-xl text-center">
        {status === "processing" && (
          <div className="space-y-4 py-8">
            <Loader2 className="mx-auto h-12 w-12 animate-spin text-[var(--theme-accent)]" />
            <h2 className="text-xl font-extrabold text-[var(--theme-text-primary)]">Completing Google Login</h2>
            <p className="text-xs text-[var(--theme-text-secondary)]">Verifying identity and restoring secure session...</p>
          </div>
        )}

        {status === "success" && (
          <div className="space-y-4 py-8 text-emerald-500">
            <CheckCircle2 className="mx-auto h-14 w-14 animate-bounce" />
            <h2 className="text-xl font-extrabold text-[var(--theme-text-primary)]">Authenticated!</h2>
            <p className="text-xs text-[var(--theme-text-secondary)]">Redirecting to DOLSYX Chat...</p>
          </div>
        )}

        {status === "error" && (
          <div className="space-y-6 py-4">
            <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-red-500/10 text-red-500">
              <ShieldAlert className="h-8 w-8" />
            </div>
            <div>
              <h2 className="text-xl font-extrabold text-[var(--theme-text-primary)]">Authentication Failed</h2>
              <p className="mt-2 text-xs text-red-400">{errorMessage}</p>
            </div>
            <button
              onClick={() => router.push("/login")}
              className="flex w-full items-center justify-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 transition-all cursor-pointer shadow-lg"
            >
              <span>Back to Login</span>
            </button>
          </div>
        )}

        {status === "needs-username" && (
          <div className="space-y-6 py-4 text-left">
            <div className="text-center space-y-2">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-tr from-violet-600 to-indigo-600 text-white">
                <User className="h-6 w-6" />
              </div>
              <h2 className="text-2xl font-black text-[var(--theme-text-primary)]">Choose your Username</h2>
              <p className="text-xs text-[var(--theme-text-secondary)]">
                Welcome to DOLSYX! Create your unique username to let friends message you.
              </p>
            </div>

            {errorMessage && (
              <div className="rounded-xl border border-red-500/20 bg-red-500/10 p-3 text-xs text-red-400">
                {errorMessage}
              </div>
            )}

            <form onSubmit={handleUsernameSubmit} className="space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">
                  DOLSYX Username
                </label>
                <div className="relative">
                  <span className="absolute left-4 top-3 text-sm font-bold text-[var(--theme-text-secondary)]">@</span>
                  <input
                    type="text"
                    required
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="alex_dev"
                    className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-9 pr-4 text-sm font-bold text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none"
                  />
                </div>
                <p className="mt-1 text-[10px] text-[var(--theme-text-secondary)]">
                  3–20 characters. Letters, numbers, and underscores only.
                </p>
              </div>

              <button
                type="submit"
                disabled={isSubmittingUsername || !username.trim()}
                className="flex w-full items-center justify-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
              >
                {isSubmittingUsername ? (
                  <Loader2 className="h-5 w-5 animate-spin" />
                ) : (
                  <>
                    <span>Complete Account Setup</span>
                    <ArrowRight className="h-4 w-4" />
                  </>
                )}
              </button>
            </form>
          </div>
        )}
      </div>
    </div>
  );
}

export default function GoogleCallbackPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-[var(--theme-bg-app)]">
          <Loader2 className="h-8 w-8 animate-spin text-[var(--theme-accent)]" />
        </div>
      }
    >
      <GoogleCallbackContent />
    </Suspense>
  );
}
