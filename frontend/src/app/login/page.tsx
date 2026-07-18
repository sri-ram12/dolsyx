"use client";

import React, { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import {
  MessageSquare, ShieldAlert, Key, User, CheckCircle2, Mail, Sun,
  Moon, ArrowRight, Loader2, Fingerprint, Lock, Eye, EyeOff
} from "lucide-react";

type Step =
  | "email"        // Enter email
  | "local-auth"   // Existing user: PIN or fingerprint
  | "otp"          // New user: verify email OTP
  | "register"     // New user: choose username
  | "set-pin";     // After first login: set PIN

const PIN_LENGTH = 6;

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [step, setStep] = useState<Step>("email");
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [countdown, setCountdown] = useState(300);

  // OTP digits (new user email verification)
  const [otpDigits, setOtpDigits] = useState<string[]>(Array(6).fill(""));
  const otpRefs = Array.from({ length: 6 }, () => useRef<HTMLInputElement>(null));

  // PIN entry (existing user local auth)
  const [pinDigits, setPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [showPin, setShowPin] = useState(false);
  const pinRefs = Array.from({ length: PIN_LENGTH }, () => useRef<HTMLInputElement>(null));

  // Set-PIN (new user after first login)
  const [newPinDigits, setNewPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [confirmPinDigits, setConfirmPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [newPinFocused, setNewPinFocused] = useState(true); // true = filling newPin, false = filling confirmPin
  const newPinRefs = Array.from({ length: PIN_LENGTH }, () => useRef<HTMLInputElement>(null));
  const confirmPinRefs = Array.from({ length: PIN_LENGTH }, () => useRef<HTMLInputElement>(null));

  // Registration
  const [username, setUsername] = useState("");

  // Biometrics
  const [hasBiometrics, setHasBiometrics] = useState(false);
  const [loggedInToken, setLoggedInToken] = useState<{ token: string; user: any } | null>(null);

  const { theme, setTheme } = useTheme();
  const { login, isAuthenticated, isLoading: authLoading } = useAuth();
  const router = useRouter();

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

  useEffect(() => {
    if (email) {
      const bioEnabled = localStorage.getItem(`dolsyx_bio_enabled_${email.trim().toLowerCase()}`) === "true";
      setHasBiometrics(bioEnabled);
    } else {
      setHasBiometrics(false);
    }
  }, [email]);

  // ──────────────────────────────────────────────────────────────────────
  //  Email submit: check if user exists
  // ──────────────────────────────────────────────────────────────────────
  const handleEmailSubmit = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setError(""); setInfo("");
    if (!email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError("Please enter a valid email address."); return;
    }
    setIsLoading(true);
    try {
      const res = await fetch(`${API_URL}/api/auth/send-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim().toLowerCase() }),
      });
      const data = await res.json();
      if (res.ok) {
        if (data.requiresLocalAuth) {
          // Existing user → PIN / biometric
          setStep("local-auth");
          const bioEnabled = localStorage.getItem(`dolsyx_bio_enabled_${email.trim().toLowerCase()}`) === "true";
          setHasBiometrics(bioEnabled);
          if (bioEnabled) setTimeout(() => triggerBiometric(), 300);
        } else {
          // New user → OTP flow
          setStep("otp");
          setCountdown(300);
          setInfo(data.message || `Verification code sent to ${email.trim().toLowerCase()}.`);
          setTimeout(() => otpRefs[0].current?.focus(), 100);
        }
      } else {
        setError(data.message || "Failed to initiate login.");
      }
    } catch {
      setError("Failed to connect to server.");
    } finally {
      setIsLoading(false);
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  PIN login for existing users
  // ──────────────────────────────────────────────────────────────────────
  const handlePinLogin = async () => {
    const pin = pinDigits.join("");
    if (pin.length < PIN_LENGTH) { setError("Please enter all 6 PIN digits."); return; }
    const storedPin = localStorage.getItem(`dolsyx_pin_${email.trim().toLowerCase()}`);
    if (!storedPin) {
      setError("No PIN set for this account. Please contact support or use a different device.");
      return;
    }
    if (pin !== storedPin) {
      setError("Incorrect PIN. Please try again.");
      setPinDigits(Array(PIN_LENGTH).fill(""));
      setTimeout(() => pinRefs[0].current?.focus(), 100);
      return;
    }
    await doLoginWithoutOtp();
  };

  const doLoginWithoutOtp = async () => {
    setIsLoading(true); setError(""); setInfo("");
    try {
      const res = await fetch(`${API_URL}/api/auth/login-without-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim().toLowerCase() }),
      });
      const data = await res.json();
      if (res.ok) {
        setInfo("Login successful! Redirecting...");
        setTimeout(() => login(data.token, data.user), 800);
      } else {
        setError(data.message || "Login failed.");
      }
    } catch {
      setError("Failed to connect to server.");
    } finally {
      setIsLoading(false);
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  Biometric (WebAuthn)
  // ──────────────────────────────────────────────────────────────────────
  const triggerBiometric = async () => {
    setError(""); setInfo("");
    try {
      if (!window.PublicKeyCredential) {
        setError("Biometrics not supported on this browser."); return;
      }
      const challenge = new Uint8Array(32);
      window.crypto.getRandomValues(challenge);
      const storedCredId = localStorage.getItem(`dolsyx_bio_cred_id_${email.trim().toLowerCase()}`);
      const allowCredentials: PublicKeyCredentialDescriptor[] = storedCredId
        ? [{ type: "public-key", id: new Uint8Array(atob(storedCredId).split("").map(c => c.charCodeAt(0))) }]
        : [];
      const credential = await navigator.credentials.get({
        publicKey: { challenge, timeout: 60000, userVerification: "required", allowCredentials }
      });
      if (credential) {
        await doLoginWithoutOtp();
      }
    } catch (err: any) {
      setError(err?.message || "Biometric authentication cancelled.");
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  OTP Verification (new user)
  // ──────────────────────────────────────────────────────────────────────
  const verifyOtp = async (code: string) => {
    setError(""); setInfo("");
    setIsVerifying(true);
    try {
      const res = await fetch(`${API_URL}/api/auth/verify-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim().toLowerCase(), code }),
      });
      const data = await res.json();
      if (res.ok) {
        if (data.isNewUser) {
          setStep("register");
          setInfo("Email verified! Choose a username to complete registration.");
        } else {
          setInfo("Authentication successful! Redirecting...");
          setTimeout(() => login(data.token, data.user), 800);
        }
      } else {
        setError(data.message || "Invalid or expired OTP.");
      }
    } catch {
      setError("Failed to verify code.");
    } finally {
      setIsVerifying(false);
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  Registration (new user)
  // ──────────────────────────────────────────────────────────────────────
  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(""); setInfo("");
    if (!username.trim()) { setError("Username is required."); return; }
    setIsLoading(true);
    try {
      const res = await fetch(`${API_URL}/api/auth/register`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim().toLowerCase(), username: username.trim() }),
      });
      const data = await res.json();
      if (res.ok) {
        // Save token/user for set-pin step
        setLoggedInToken({ token: data.token, user: data.user });
        setStep("set-pin");
        setInfo("Account created! Set a PIN to quickly log in next time.");
      } else {
        setError(data.message || "Registration failed.");
      }
    } catch {
      setError("Failed to register account.");
    } finally {
      setIsLoading(false);
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  Set PIN (new user after registration)
  // ──────────────────────────────────────────────────────────────────────
  const handleSetPin = () => {
    const newPin = newPinDigits.join("");
    const confirmPin = confirmPinDigits.join("");
    if (newPin.length < PIN_LENGTH || confirmPin.length < PIN_LENGTH) {
      setError("Please fill both PIN fields completely."); return;
    }
    if (newPin !== confirmPin) {
      setError("PINs do not match. Please try again.");
      setConfirmPinDigits(Array(PIN_LENGTH).fill(""));
      return;
    }
    localStorage.setItem(`dolsyx_pin_${email.trim().toLowerCase()}`, newPin);
    setInfo("PIN set successfully! Logging in...");
    if (loggedInToken) {
      setTimeout(() => login(loggedInToken.token, loggedInToken.user), 800);
    }
  };

  const handleSkipPin = () => {
    if (loggedInToken) login(loggedInToken.token, loggedInToken.user);
  };

  // ──────────────────────────────────────────────────────────────────────
  //  OTP digit helpers
  // ──────────────────────────────────────────────────────────────────────
  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const nd = [...otpDigits]; nd[index] = digit; setOtpDigits(nd);
    if (digit && index < 5) otpRefs[index + 1].current?.focus();
    const complete = nd.join("");
    if (complete.length === 6 && !nd.includes("")) verifyOtp(complete);
  };
  const handleOtpKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === "Backspace") {
      if (!otpDigits[index] && index > 0) {
        const nd = [...otpDigits]; nd[index - 1] = ""; setOtpDigits(nd);
        otpRefs[index - 1].current?.focus();
      } else {
        const nd = [...otpDigits]; nd[index] = ""; setOtpDigits(nd);
      }
    }
  };
  const handleOtpPaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const paste = e.clipboardData.getData("text").replace(/[^0-9]/g, "").slice(0, 6);
    if (paste.length === 6) {
      setOtpDigits(paste.split("")); otpRefs[5].current?.focus(); verifyOtp(paste);
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  PIN digit helpers (existing user entry)
  // ──────────────────────────────────────────────────────────────────────
  const handlePinChange = (index: number, value: string) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const nd = [...pinDigits]; nd[index] = digit; setPinDigits(nd);
    if (digit && index < PIN_LENGTH - 1) pinRefs[index + 1].current?.focus();
    if (nd.join("").length === PIN_LENGTH && !nd.includes("")) {
      setTimeout(() => handlePinLogin(), 100);
    }
  };
  const handlePinKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === "Backspace") {
      if (!pinDigits[index] && index > 0) {
        const nd = [...pinDigits]; nd[index - 1] = ""; setPinDigits(nd);
        pinRefs[index - 1].current?.focus();
      } else {
        const nd = [...pinDigits]; nd[index] = ""; setPinDigits(nd);
      }
    }
  };

  // ──────────────────────────────────────────────────────────────────────
  //  Set-PIN digit helpers
  // ──────────────────────────────────────────────────────────────────────
  const handleNewPinChange = (
    index: number, value: string,
    digits: string[], setDigits: (d: string[]) => void,
    refs: React.RefObject<HTMLInputElement | null>[],
    isNew: boolean
  ) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const nd = [...digits]; nd[index] = digit; setDigits(nd);
    if (digit && index < PIN_LENGTH - 1) refs[index + 1].current?.focus();
    if (nd.join("").length === PIN_LENGTH && !nd.includes("") && isNew) {
      setNewPinFocused(false);
      setTimeout(() => confirmPinRefs[0].current?.focus(), 100);
    }
  };
  const handleNewPinKeyDown = (
    index: number, e: React.KeyboardEvent,
    digits: string[], setDigits: (d: string[]) => void,
    refs: React.RefObject<HTMLInputElement | null>[]
  ) => {
    if (e.key === "Backspace") {
      if (!digits[index] && index > 0) {
        const nd = [...digits]; nd[index - 1] = ""; setDigits(nd);
        refs[index - 1].current?.focus();
      } else {
        const nd = [...digits]; nd[index] = ""; setDigits(nd);
      }
    }
  };

  const toggleTheme = () => {
    if (theme === "dolsy-dark") setTheme("aqua-light");
    else if (theme === "aqua-light") setTheme("aqua-dark");
    else if (theme === "aqua-dark") setTheme("radiant-blue");
    else setTheme("dolsy-dark");
  };

  if (authLoading) return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--theme-bg-app)]">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-[var(--theme-accent)] border-t-transparent" />
    </div>
  );

  const stepLabel: Record<Step, string> = {
    "email": "Enter your email to continue",
    "local-auth": "Verify it's you",
    "otp": "Enter the code sent to your email",
    "register": "Complete your account setup",
    "set-pin": "Set a PIN for quick login",
  };

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center px-4 py-12 transition-colors duration-300">
      <button
        onClick={toggleTheme}
        className="absolute right-6 top-6 flex h-10 w-10 items-center justify-center rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer z-50 shadow-md"
      >
        {theme === "aqua-light" ? <Sun className="h-5 w-5 text-amber-500" /> : <Moon className="h-5 w-5" />}
      </button>

      <div className="w-full max-w-md space-y-8 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] p-8 shadow-2xl backdrop-blur-xl">
        {/* Header */}
        <div className="flex flex-col items-center justify-center text-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl text-white shadow-lg bg-gradient-to-tr from-violet-600 to-indigo-600">
            <MessageSquare className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-3xl font-black tracking-tight text-[var(--theme-text-primary)]">DOLSYX</h2>
          <p className="mt-2 text-sm text-[var(--theme-text-secondary)]">{stepLabel[step]}</p>
        </div>

        {/* Alerts */}
        {error && (
          <div className="flex items-start gap-3 rounded-xl border border-red-500/20 bg-red-500/10 p-3.5 text-xs text-red-400">
            <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}
        {info && (
          <div className="flex items-start gap-3 rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3.5 text-xs text-emerald-400">
            <CheckCircle2 className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{info}</span>
          </div>
        )}

        {/* ── STEP: Email ── */}
        {step === "email" && (
          <form className="mt-8 space-y-6" onSubmit={handleEmailSubmit}>
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">Email Address</label>
              <div className="relative">
                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                  <Mail className="h-4 w-4" />
                </div>
                <input
                  type="email" required value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
                  placeholder="Enter your email address"
                />
              </div>
            </div>
            <button
              type="submit" disabled={isLoading}
              className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
            >
              {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <><span>Continue</span><ArrowRight className="h-4 w-4" /></>}
            </button>
          </form>
        )}

        {/* ── STEP: Local Auth (existing user: PIN or fingerprint) ── */}
        {step === "local-auth" && (
          <div className="mt-8 space-y-6">
            <div className="text-center text-xs text-[var(--theme-text-secondary)]">
              Signed in as <span className="font-semibold text-[var(--theme-text-primary)]">{email.trim().toLowerCase()}</span>
            </div>

            {/* PIN boxes */}
            <div>
              <div className="flex items-center justify-between mb-3">
                <label className="text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)]">Enter PIN</label>
                <button type="button" onClick={() => setShowPin(!showPin)} className="text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors">
                  {showPin ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <div className="flex justify-between items-center gap-2">
                {pinDigits.map((digit, index) => (
                  <input
                    key={index}
                    ref={pinRefs[index]}
                    type={showPin ? "text" : "password"}
                    pattern="[0-9]*" inputMode="numeric" maxLength={1}
                    value={digit}
                    onChange={(e) => handlePinChange(index, e.target.value)}
                    onKeyDown={(e) => handlePinKeyDown(index, e)}
                    autoFocus={index === 0}
                    className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all"
                  />
                ))}
              </div>
            </div>

            <div className="space-y-3">
              <button
                type="button"
                onClick={handlePinLogin}
                disabled={isLoading || pinDigits.includes("")}
                className="flex w-full justify-center items-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <><Lock className="h-4 w-4" /><span>Unlock</span></>}
              </button>

              {hasBiometrics && (
                <button
                  type="button" onClick={triggerBiometric} disabled={isLoading}
                  className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-text-primary)] border border-[var(--theme-border-color)] bg-transparent hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer"
                >
                  <Fingerprint className="h-5 w-5 text-[var(--theme-accent)]" />
                  <span>Use Fingerprint</span>
                </button>
              )}

              <button type="button" onClick={() => { setStep("email"); setPinDigits(Array(PIN_LENGTH).fill("")); setError(""); }}
                className="w-full text-center text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] hover:underline cursor-pointer">
                ← Change Email
              </button>
            </div>
          </div>
        )}

        {/* ── STEP: OTP (new user email verification) ── */}
        {step === "otp" && (
          <div className="mt-8 space-y-6">
            <div className="text-center text-xs text-[var(--theme-text-secondary)]">
              Verification email sent to <span className="font-semibold text-[var(--theme-text-primary)]">{email.trim().toLowerCase()}</span>
            </div>
            <div className="flex justify-between items-center gap-2">
              {otpDigits.map((digit, index) => (
                <input
                  key={index}
                  ref={otpRefs[index]}
                  type="text" pattern="[0-9]*" inputMode="numeric" maxLength={1}
                  value={digit}
                  onChange={(e) => handleOtpChange(index, e.target.value)}
                  onKeyDown={(e) => handleOtpKeyDown(index, e)}
                  onPaste={index === 0 ? handleOtpPaste : undefined}
                  disabled={isVerifying}
                  className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none transition-all disabled:opacity-50"
                />
              ))}
            </div>
            <div className="flex flex-col gap-3">
              <button
                type="button"
                onClick={() => verifyOtp(otpDigits.join(""))}
                disabled={isVerifying || otpDigits.includes("")}
                className="flex w-full justify-center items-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                {isVerifying ? <Loader2 className="h-5 w-5 animate-spin" /> : "Verify & Continue"}
              </button>
              <div className="flex justify-between items-center text-xs text-[var(--theme-text-secondary)]">
                <button type="button" onClick={() => setStep("email")} className="hover:underline cursor-pointer">Change Email</button>
                {countdown > 0
                  ? <span className="font-medium text-amber-500">{Math.floor(countdown / 60)}:{(countdown % 60).toString().padStart(2, "0")} remaining</span>
                  : <button type="button" onClick={handleEmailSubmit} className="font-bold text-[var(--theme-accent)] hover:underline cursor-pointer">Resend OTP</button>
                }
              </div>
            </div>
          </div>
        )}

        {/* ── STEP: Register (new user: choose username) ── */}
        {step === "register" && (
          <form className="mt-8 space-y-6" onSubmit={handleRegister}>
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">Choose Username</label>
              <div className="relative">
                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]"><User className="h-4 w-4" /></div>
                <input
                  type="text" required value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none"
                  placeholder="Choose a unique username"
                />
              </div>
            </div>
            <button
              type="submit" disabled={isLoading}
              className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
            >
              {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : "Create Account"}
            </button>
          </form>
        )}

        {/* ── STEP: Set PIN (after first registration) ── */}
        {step === "set-pin" && (
          <div className="mt-8 space-y-6">
            <div className="text-center text-xs text-[var(--theme-text-secondary)]">
              Set a 6-digit PIN to quickly unlock the app next time you log in.
            </div>

            {/* New PIN */}
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-2">New PIN</label>
              <div className="flex justify-between items-center gap-2">
                {newPinDigits.map((digit, index) => (
                  <input
                    key={index}
                    ref={newPinRefs[index]}
                    type="password" pattern="[0-9]*" inputMode="numeric" maxLength={1}
                    value={digit}
                    onChange={(e) => handleNewPinChange(index, e.target.value, newPinDigits, setNewPinDigits, newPinRefs, true)}
                    onKeyDown={(e) => handleNewPinKeyDown(index, e, newPinDigits, setNewPinDigits, newPinRefs)}
                    autoFocus={index === 0}
                    className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all"
                  />
                ))}
              </div>
            </div>

            {/* Confirm PIN */}
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-2">Confirm PIN</label>
              <div className="flex justify-between items-center gap-2">
                {confirmPinDigits.map((digit, index) => (
                  <input
                    key={index}
                    ref={confirmPinRefs[index]}
                    type="password" pattern="[0-9]*" inputMode="numeric" maxLength={1}
                    value={digit}
                    onChange={(e) => handleNewPinChange(index, e.target.value, confirmPinDigits, setConfirmPinDigits, confirmPinRefs, false)}
                    onKeyDown={(e) => handleNewPinKeyDown(index, e, confirmPinDigits, setConfirmPinDigits, confirmPinRefs)}
                    className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)] transition-all"
                  />
                ))}
              </div>
            </div>

            <div className="space-y-3">
              <button
                type="button"
                onClick={handleSetPin}
                disabled={newPinDigits.includes("") || confirmPinDigits.includes("")}
                className="flex w-full justify-center items-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                <Lock className="h-4 w-4" /> Save PIN & Continue
              </button>
              <button type="button" onClick={handleSkipPin}
                className="w-full text-center text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] hover:underline cursor-pointer">
                Skip for now
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
