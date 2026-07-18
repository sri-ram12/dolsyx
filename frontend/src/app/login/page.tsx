"use client";

import React, { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { MessageSquare, ShieldAlert, Key, User, CheckCircle2, Mail, Sun, Moon, ArrowRight, RefreshCw, Loader2, Fingerprint } from "lucide-react";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  
  // Registration form
  const [username, setUsername] = useState("");
  const [regPassword, setRegPassword] = useState("");

  const [otpDigits, setOtpDigits] = useState<string[]>(Array(6).fill(""));
  const [step, setStep] = useState<"login" | "password" | "otp" | "register">("login");
  const [isNewUser, setIsNewUser] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [isResending, setIsResending] = useState(false);
  const [countdown, setCountdown] = useState(300);
  const [hasBiometrics, setHasBiometrics] = useState(false);

  const { theme, setTheme } = useTheme();
  const { login, isAuthenticated, isLoading: authLoading } = useAuth();
  const router = useRouter();

  const inputRefs = [
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
  ];

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

  // Check if biometric login is enabled for this device/email
  useEffect(() => {
    if (typeof window !== "undefined" && email) {
      const bioEnabled = localStorage.getItem(`dolsyx_bio_enabled_${email.trim().toLowerCase()}`) === "true";
      setHasBiometrics(bioEnabled);
    } else {
      setHasBiometrics(false);
    }
  }, [email]);

  const handleSendOtp = async (e?: React.FormEvent, forceOtp = false) => {
    if (e) e.preventDefault();
    setError("");
    setInfo("");

    if (!email.trim()) {
      setError("Please enter your Email Address.");
      return;
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError("Please enter a valid email address format.");
      return;
    }

    setIsLoading(true);

    try {
      const res = await fetch(`${API_URL}/api/auth/send-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim().toLowerCase(),
          forceOtp: forceOtp
        }),
      });

      const data = await res.json();

      if (res.ok) {
        if (data.requiresPassword && !forceOtp) {
          setStep("password");
          const bioEnabled = localStorage.getItem(`dolsyx_bio_enabled_${email.trim().toLowerCase()}`) === "true";
          if (bioEnabled) {
            setTimeout(() => {
              handleBiometricLogin();
            }, 150);
          }
        } else {
          setStep("otp");
          setIsNewUser(data.isNewUser);
          setCountdown(300);
          setInfo(data.message || `Verification code sent to ${email.trim().toLowerCase()}.`);
          setTimeout(() => inputRefs[0].current?.focus(), 100);
        }
      } else {
        setError(data.message || "Failed to initiate login.");
      }
    } catch (err) {
      console.error(err);
      setError("Failed to connect to server.");
    } finally {
      setIsLoading(false);
    }
  };

  const handlePasswordLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setInfo("");
    setIsLoading(true);

    try {
      const res = await fetch(`${API_URL}/api/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim().toLowerCase(),
          password: password
        }),
      });

      const data = await res.json();
      if (res.ok) {
        setInfo("Login successful! Redirecting...");
        setTimeout(() => {
          login(data.token, data.user);
        }, 800);
      } else {
        setError(data.message || "Incorrect password.");
      }
    } catch (err) {
      console.error(err);
      setError("Failed to connect to server.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleBiometricLogin = async () => {
    setError("");
    setInfo("");
    try {
      // Prompt native biometric verification using WebAuthn API
      if (!window.PublicKeyCredential) {
        setError("Biometrics not supported on this browser.");
        return;
      }
      
      const challenge = new Uint8Array(32);
      window.crypto.getRandomValues(challenge);
      
      const storedCredId = localStorage.getItem(`dolsyx_bio_cred_id_${email.trim().toLowerCase()}`);
      const allowCredentials = storedCredId ? [{
        type: "public-key" as const,
        id: new Uint8Array(atob(storedCredId).split("").map(c => c.charCodeAt(0)))
      }] : [];

      const credential = await navigator.credentials.get({
        publicKey: {
          challenge,
          timeout: 60000,
          userVerification: "required",
          allowCredentials
        }
      });

      if (credential) {
        // Biometrics verified successfully on device! Now get direct token
        setIsLoading(true);
        const res = await fetch(`${API_URL}/api/auth/send-otp`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            email: email.trim().toLowerCase(),
            forceOtp: true // bypass password
          }),
        });

        const data = await res.json();
        if (res.ok) {
          setStep("otp");
          setCountdown(300);
          setInfo("Biometrics verified. Please enter the OTP sent to your email to log in.");
        } else {
          setError("Biometrics validation failed on server.");
        }
      }
    } catch (err: any) {
      console.error(err);
      setError(err.message || "Biometric authentication cancelled.");
    } finally {
      setIsLoading(false);
    }
  };

  const verifyCode = async (code: string) => {
    setError("");
    setInfo("");
    setIsVerifying(true);

    try {
      const res = await fetch(`${API_URL}/api/auth/verify-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim().toLowerCase(),
          code,
        }),
      });

      const data = await res.json();

      if (res.ok) {
        if (data.isNewUser) {
          setStep("register");
          setInfo("Email verified successfully! Please choose your username.");
        } else {
          setInfo("Authentication successful! Redirecting...");
          setTimeout(() => {
            login(data.token, data.user);
          }, 800);
        }
      } else {
        setError(data.message || "Invalid or expired OTP code.");
      }
    } catch (err) {
      console.error(err);
      setError("Failed to verify code.");
    } finally {
      setIsVerifying(false);
    }
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setInfo("");

    if (!username.trim()) {
      setError("Username is required.");
      return;
    }

    setIsLoading(true);

    try {
      const res = await fetch(`${API_URL}/api/auth/register`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim().toLowerCase(),
          username: username.trim(),
          password: regPassword || undefined,
        }),
      });

      const data = await res.json();
      if (res.ok) {
        setInfo("Registration successful! Redirecting...");
        setTimeout(() => {
          login(data.token, data.user);
        }, 800);
      } else {
        setError(data.message || "Registration failed.");
      }
    } catch (err) {
      console.error(err);
      setError("Failed to register account.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const newDigits = [...otpDigits];
    newDigits[index] = digit;
    setOtpDigits(newDigits);

    if (digit && index < 5) {
      inputRefs[index + 1].current?.focus();
    }

    const completeCode = newDigits.join("");
    if (completeCode.length === 6 && !newDigits.includes("")) {
      verifyCode(completeCode);
    }
  };

  const handleOtpKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace") {
      if (!otpDigits[index] && index > 0) {
        const newDigits = [...otpDigits];
        newDigits[index - 1] = "";
        setOtpDigits(newDigits);
        inputRefs[index - 1].current?.focus();
      } else {
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

  const toggleTheme = () => {
    if (theme === "dolsy-dark") setTheme("aqua-light");
    else if (theme === "aqua-light") setTheme("aqua-dark");
    else if (theme === "aqua-dark") setTheme("radiant-blue");
    else setTheme("dolsy-dark");
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
      <button
        onClick={toggleTheme}
        className="absolute right-6 top-6 flex h-10 w-10 items-center justify-center rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-all cursor-pointer z-50 shadow-md"
      >
        {theme === "aqua-light" ? <Sun className="h-5 w-5 text-amber-500" /> : <Moon className="h-5 w-5" />}
      </button>

      <div className="w-full max-w-md space-y-8 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] p-8 shadow-2xl backdrop-blur-xl">
        <div className="flex flex-col items-center justify-center text-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl text-white shadow-lg bg-gradient-to-tr from-violet-600 to-indigo-600">
            <MessageSquare className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-3xl font-black tracking-tight text-[var(--theme-text-primary)]">
            DOLSYX
          </h2>
          <p className="mt-2 text-sm text-[var(--theme-text-secondary)]">
            {step === "login" && "Enter your email address to log in or create an account"}
            {step === "password" && "Enter your password to sign in"}
            {step === "otp" && "Enter the verification code sent to your email"}
            {step === "register" && "Complete your profile registration"}
          </p>
        </div>

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

        {step === "login" && (
          <form className="mt-8 space-y-6" onSubmit={(e) => handleSendOtp(e)}>
            <div className="space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">
                  Email Address
                </label>
                <div className="relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                    <Mail className="h-4 w-4" />
                  </div>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
                    placeholder="Enter your email address"
                  />
                </div>
              </div>
            </div>

             <div className="space-y-3">
              <button
                type="submit"
                disabled={isLoading}
                className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
              >
                {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <><span>Continue</span><ArrowRight className="h-4 w-4" /></>}
              </button>

              {hasBiometrics && (
                <button
                  type="button"
                  onClick={handleBiometricLogin}
                  disabled={isLoading}
                  className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-text-primary)] border border-[var(--theme-border-color)] bg-transparent hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer"
                >
                  <Fingerprint className="h-5 w-5 text-[var(--theme-accent)]" />
                  <span>Login with Fingerprint</span>
                </button>
              )}
            </div>
          </form>
        )}

        {step === "password" && (
          <form className="mt-8 space-y-6" onSubmit={handlePasswordLogin}>
            <div className="space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">
                  Password
                </label>
                <div className="relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                    <Key className="h-4 w-4" />
                  </div>
                  <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
                    placeholder="Enter your password"
                  />
                </div>
              </div>
            </div>

            <div className="space-y-3">
              <button
                type="submit"
                disabled={isLoading}
                className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : "Sign In"}
              </button>

              {hasBiometrics && (
                <button
                  type="button"
                  onClick={handleBiometricLogin}
                  className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-text-primary)] border border-[var(--theme-border-color)] bg-transparent hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer"
                >
                  <Fingerprint className="h-5 w-5 text-[var(--theme-accent)]" />
                  <span>Login with Fingerprint</span>
                </button>
              )}

              <button
                type="button"
                onClick={() => handleSendOtp(undefined, true)}
                className="w-full text-center text-xs text-[var(--theme-accent)] hover:underline cursor-pointer"
              >
                Login with Email OTP instead
              </button>
            </div>
          </form>
        )}

        {step === "otp" && (
          <div className="mt-8 space-y-6">
            <div className="space-y-4">
              <div className="text-center text-xs text-[var(--theme-text-secondary)] mb-2">
                Verification email sent to <span className="font-semibold text-[var(--theme-text-primary)]">{email.trim().toLowerCase()}</span>
              </div>
              
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
                    className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none transition-all disabled:opacity-50"
                  />
                ))}
              </div>
            </div>

            <div className="flex flex-col gap-3">
              <button
                type="button"
                onClick={() => verifyCode(otpDigits.join(""))}
                disabled={isVerifying || otpDigits.includes("")}
                className="flex w-full justify-center items-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                {isVerifying ? <Loader2 className="h-5 w-5 animate-spin" /> : "Verify & Continue"}
              </button>

              <div className="flex justify-between items-center text-xs text-[var(--theme-text-secondary)]">
                <button type="button" onClick={() => setStep("login")} className="hover:underline cursor-pointer">
                  Change Email
                </button>

                <div>
                  {countdown > 0 ? (
                    <span className="font-medium text-amber-500">{Math.floor(countdown / 60)}:{(countdown % 60).toString().padStart(2, "0")} remaining</span>
                  ) : (
                    <button type="button" onClick={() => handleSendOtp(undefined, true)} className="font-bold text-[var(--theme-accent)] hover:underline cursor-pointer">
                      Resend OTP
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {step === "register" && (
          <form className="mt-8 space-y-6" onSubmit={handleRegister}>
            <div className="space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">
                  Choose Username
                </label>
                <div className="relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                    <User className="h-4 w-4" />
                  </div>
                  <input
                    type="text"
                    required
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none"
                    placeholder="Choose a username"
                  />
                </div>
              </div>

              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)] mb-1">
                  Set Password (Optional)
                </label>
                <div className="relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-[var(--theme-text-secondary)]">
                    <Key className="h-4 w-4" />
                  </div>
                  <input
                    type="password"
                    value={regPassword}
                    onChange={(e) => setRegPassword(e.target.value)}
                    className="block w-full rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none"
                    placeholder="Enter password (optional)"
                  />
                </div>
              </div>
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="flex w-full items-center justify-center gap-2 rounded-xl py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
            >
              {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : "Complete Registration"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
