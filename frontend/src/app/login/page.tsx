"use client";

import React, { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { MessageSquare, ShieldAlert, Key, User, CheckCircle2, Mail, Sun, Moon, ArrowRight, RefreshCw, Loader2 } from "lucide-react";

export default function LoginPage() {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [otpDigits, setOtpDigits] = useState<string[]>(Array(6).fill(""));
  const [step, setStep] = useState<"login" | "otp">("login");
  const [isNewUser, setIsNewUser] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [isResending, setIsResending] = useState(false);
  const [countdown, setCountdown] = useState(300); // 5 minutes (300s)

  const { theme, setTheme } = useTheme();
  const { login, isAuthenticated, isLoading: authLoading } = useAuth();
  const router = useRouter();

  // References for OTP segmented inputs
  const inputRefs = [
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
  ];

  // Countdown timer for Resend OTP (5 minutes)
  useEffect(() => {
    let timer: NodeJS.Timeout;
    if (step === "otp" && countdown > 0) {
      timer = setTimeout(() => setCountdown(countdown - 1), 1000);
    }
    return () => clearTimeout(timer);
  }, [step, countdown]);

  useEffect(() => {
    if (!authLoading && isAuthenticated) {
      router.push("/chat");
    }
  }, [isAuthenticated, authLoading, router]);

  const handleSendOtp = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setError("");
    setInfo("");

    if (isNewUser && !fullName.trim()) {
      setError("Please enter your Full Name to complete sign up.");
      return;
    }

    if (!email.trim()) {
      setError("Please enter your Email Address.");
      return;
    }

    // Email regex validation
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError("Please enter a valid email address format.");
      return;
    }

    setIsLoading(true);
    console.log(`[handleSendOtp] Sending request to POST /api/auth/send-otp. Name: ${fullName.trim()}, Email: ${email.trim().toLowerCase()}`);

    try {
      const res = await fetch(`${API_URL}/api/auth/send-otp`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fullName: isNewUser ? fullName.trim() : undefined,
          email: email.trim().toLowerCase(),
        }),
      });

      const data = await res.json();
      console.log("[handleSendOtp] Response status:", res.status, "data:", data);

      if (res.ok) {
        if (data.isDirectLogin) {
          login(data.token, data.user);
          router.push("/chat");
          return;
        }

        setStep("otp");
        setCountdown(300); // Reset to 5 minutes
        setInfo(data.message || `Verification code sent to ${email.trim().toLowerCase()}.`);
        
        // Focus first digit
        setTimeout(() => {
          inputRefs[0].current?.focus();
        }, 100);
      } else {
        if (data.isNewUser) {
          setIsNewUser(true);
          setError("This email is not registered yet. Please enter your Full Name to sign up.");
        } else {
          setError(data.message || "Failed to send OTP.");
        }
      }
    } catch (err) {
      console.error("Send OTP error:", err);
      setError("Failed to connect to server. Please try again.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleResendOtp = async () => {
    setError("");
    setInfo("");
    setIsResending(true);
    setOtpDigits(Array(6).fill(""));

    try {
      const res = await fetch(`${API_URL}/api/auth/resend-otp`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fullName: fullName.trim(),
          email: email.trim().toLowerCase(),
        }),
      });

      const data = await res.json();

      if (res.ok) {
        setCountdown(300); // Reset countdown
        setInfo(`A new verification code was sent to ${email.trim().toLowerCase()}.`);
        
        setTimeout(() => {
          inputRefs[0].current?.focus();
        }, 100);
      } else {
        setError(data.message || "Failed to resend OTP.");
      }
    } catch (err) {
      console.error("Resend OTP error:", err);
      setError("Failed to connect to server. Please try again.");
    } finally {
      setIsResending(false);
    }
  };

  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const newDigits = [...otpDigits];
    newDigits[index] = digit;
    setOtpDigits(newDigits);

    // Auto focus next input
    if (digit && index < 5) {
      inputRefs[index + 1].current?.focus();
    }

    // Auto submit if all digits are entered
    const completeCode = newDigits.join("");
    if (completeCode.length === 6 && !newDigits.includes("")) {
      verifyCode(completeCode);
    }
  };

  const handleOtpKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace") {
      if (!otpDigits[index] && index > 0) {
        // Current is empty, delete previous and focus it
        const newDigits = [...otpDigits];
        newDigits[index - 1] = "";
        setOtpDigits(newDigits);
        inputRefs[index - 1].current?.focus();
      } else {
        // Delete current
        const newDigits = [...otpDigits];
        newDigits[index] = "";
        setOtpDigits(newDigits);
      }
    }
  };

  const handleOtpPaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    e.preventDefault();
    const pasteData = e.clipboardData.getData("text").replace(/[^0-9]/g, "").slice(0, 6);
    if (pasteData.length === 6) {
      const newDigits = pasteData.split("");
      setOtpDigits(newDigits);
      inputRefs[5].current?.focus();
      verifyCode(pasteData);
    }
  };

  const verifyCode = async (code: string) => {
    setError("");
    setInfo("");
    setIsVerifying(true);
    console.log(`[verifyCode] Submitting code for verification. Email: ${email.trim().toLowerCase()}, Code: ${code}`);

    try {
      const res = await fetch(`${API_URL}/api/auth/verify-otp`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fullName: fullName.trim(),
          email: email.trim().toLowerCase(),
          code,
        }),
      });

      const data = await res.json();
      console.log("[verifyCode] Response status:", res.status, "data:", data);

      if (res.ok) {
        setInfo("Authentication successful! Redirecting...");
        console.log("[verifyCode] Token received. Triggering login() context redirect.");
        setTimeout(() => {
          login(data.token, data.user);
        }, 800);
      } else {
        setError(data.message || "Invalid or expired OTP code.");
      }
    } catch (err) {
      console.error("Verify OTP error:", err);
      setError("Failed to connect to server. Please try again.");
    } finally {
      setIsVerifying(false);
    }
  };

  const formatCountdown = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  const toggleTheme = () => {
    if (theme === "dolsy-dark") {
      setTheme("aqua-light");
    } else if (theme === "aqua-light") {
      setTheme("aqua-dark");
    } else {
      setTheme("dolsy-dark");
    }
  };

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[var(--theme-bg-app)]">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-[var(--theme-accent)] border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center px-4 py-12 transition-colors duration-300">
      {/* Theme Toggle Button */}
      <button
        onClick={toggleTheme}
        className="absolute right-6 top-6 flex h-10 w-10 items-center justify-center rounded-xl border border-zinc-850 bg-[var(--theme-bg-container)] backdrop-blur-md text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] hover:border-[var(--theme-accent)] transition-all cursor-pointer z-50 shadow-md"
        title="Cycle theme (Classic / Light / Dark)"
      >
        {theme === "aqua-light" ? (
          <Sun className="h-5 w-5 text-amber-500 animate-spin-slow" />
        ) : theme === "aqua-dark" ? (
          <Moon className="h-5 w-5 text-emerald-400" />
        ) : (
          <MessageSquare className="h-5 w-5 text-violet-400" />
        )}
      </button>

      {/* Main Container Card */}
      <div className="w-full max-w-md space-y-8 rounded-2xl border border-zinc-850/80 bg-[var(--theme-bg-container)] p-8 shadow-2xl backdrop-blur-xl transition-all duration-300">
        
        {/* Header Block */}
        <div className="flex flex-col items-center justify-center text-center">
          <div 
            className="flex h-14 w-14 items-center justify-center rounded-2xl text-white shadow-lg transition-all duration-300"
            style={{
              background: theme.startsWith("aqua") 
                ? "linear-gradient(135deg, #00a884, #008069)" 
                : "linear-gradient(135deg, #8b5cf6, #4f46e5)",
              boxShadow: theme.startsWith("aqua")
                ? "0 4px 12px rgba(0, 168, 132, 0.25)"
                : "0 4px 12px rgba(139, 92, 246, 0.25)"
            }}
          >
            <MessageSquare className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-3xl font-black tracking-tight text-[var(--theme-text-primary)]">
            {theme.startsWith("aqua") ? "DOLSYX Chat" : "DOLSYX Messenger"}
          </h2>
          <p className="mt-2 text-sm text-[var(--theme-text-secondary)]">
            {step === "login" && "Enter your name and email to request a secure verification code"}
            {step === "otp" && "Enter the verification code sent to your email"}
          </p>
        </div>

        {/* Alert Notifications */}
        {error && (
          <div className="flex items-start gap-3 rounded-xl border border-red-500/20 bg-red-500/10 p-3.5 text-xs text-red-400 animate-shake">
            <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}

        {info && (
          <div 
            className="flex items-start gap-3 rounded-xl border p-3.5 text-xs animate-fade-in"
            style={{
              borderColor: "rgba(var(--theme-accent), 0.2)",
              backgroundColor: "rgba(100, 100, 100, 0.05)",
              color: "var(--theme-text-primary)"
            }}
          >
            <CheckCircle2 className="h-4 w-4 shrink-0 mt-0.5 text-emerald-400" />
            <span>{info}</span>
          </div>
        )}

        {/* Step 1: Login Form */}
        {step === "login" && (
          <form className="mt-8 space-y-6 animate-fade-in" onSubmit={(e) => handleSendOtp(e)}>
            <div className="space-y-4">
              
              {/* Full Name Input Box */}
              {isNewUser && (
                <div>
                  <label
                    htmlFor="fullName"
                    className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1"
                  >
                    Full Name
                  </label>
                  <div className="relative">
                    <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                      <User className="h-4 w-4" />
                    </div>
                    <input
                      id="fullName"
                      type="text"
                      required
                      value={fullName}
                      onChange={(e) => setFullName(e.target.value)}
                      className="block w-full rounded-xl border border-zinc-800 bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] placeholder-zinc-650 focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all duration-200"
                      placeholder="Enter your full name"
                    />
                  </div>
                </div>
              )}

              {/* Email Input Box */}
              <div>
                <label
                  htmlFor="email"
                  className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1"
                >
                  Email Address
                </label>
                <div className="relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                    <Mail className="h-4 w-4" />
                  </div>
                  <input
                    id="email"
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="block w-full rounded-xl border border-zinc-800 bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] placeholder-zinc-650 focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all duration-200"
                    placeholder="Enter your email address"
                  />
                </div>
              </div>
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] hover:opacity-95 focus:outline-none disabled:opacity-50 transition-all duration-200 cursor-pointer shadow-lg"
              style={{ backgroundColor: "var(--theme-accent)" }}
            >
              {isLoading ? (
                <Loader2 className="h-5 w-5 animate-spin" />
              ) : (
                <>
                  <span>Send OTP</span>
                  <ArrowRight className="h-4 w-4" />
                </>
              )}
            </button>
          </form>
        )}

        {/* Step 2: Segmented OTP Code Input Form */}
        {step === "otp" && (
          <div className="mt-8 space-y-6 animate-fade-in">
            <div className="space-y-4">
              <div className="text-center text-xs text-[var(--theme-text-secondary)] mb-2">
                Verification email sent to <span className="font-semibold text-[var(--theme-text-primary)]">{email.trim().toLowerCase()}</span>
              </div>
              
              {/* Segmented Inputs */}
              <div className="flex justify-between items-center gap-2">
                {otpDigits.map((digit, index) => (
                  <input
                    key={index}
                    ref={inputRefs[index]}
                    type="text"
                    pattern="[0-9]*"
                    inputMode="numeric"
                    maxLength={1}
                    value={digit}
                    onChange={(e) => handleOtpChange(index, e.target.value)}
                    onKeyDown={(e) => handleOtpKeyDown(index, e)}
                    onPaste={index === 0 ? handleOtpPaste : undefined}
                    disabled={isVerifying}
                    className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-zinc-800 bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:ring-1 focus:ring-[var(--theme-accent)] focus:outline-none transition-all duration-150 disabled:opacity-50"
                  />
                ))}
              </div>
            </div>

            <div className="flex flex-col gap-3 pt-2">
              <button
                type="button"
                onClick={() => verifyCode(otpDigits.join(""))}
                disabled={isVerifying || otpDigits.includes("")}
                className="flex w-full justify-center items-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] hover:opacity-95 focus:outline-none disabled:opacity-50 transition-all duration-200 cursor-pointer shadow-lg"
                style={{ backgroundColor: "var(--theme-accent)" }}
              >
                {isVerifying ? (
                  <Loader2 className="h-5 w-5 animate-spin" />
                ) : (
                  "Verify & Connect"
                )}
              </button>

              {/* Actions & Countdown */}
              <div className="flex justify-between items-center text-xs text-[var(--theme-text-secondary)] px-1 mt-1">
                <button
                  type="button"
                  onClick={() => {
                    setStep("login");
                    setError("");
                    setInfo("");
                    setOtpDigits(Array(6).fill(""));
                  }}
                  className="hover:underline hover:text-[var(--theme-text-primary)] cursor-pointer"
                >
                  Change Email
                </button>

                <div className="flex items-center gap-2">
                  {countdown > 0 ? (
                    <span className="font-medium text-amber-500">{formatCountdown(countdown)} remaining</span>
                  ) : (
                    <button
                      type="button"
                      onClick={handleResendOtp}
                      disabled={isResending}
                      className="flex items-center gap-1 font-bold text-[var(--theme-accent)] hover:underline cursor-pointer disabled:opacity-50"
                    >
                      {isResending ? (
                        <Loader2 className="h-3 w-3 animate-spin" />
                      ) : (
                        <RefreshCw className="h-3 w-3" />
                      )}
                      <span>Resend OTP</span>
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
