"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import QRCode from "react-qr-code";
import { io, Socket } from "socket.io-client";
import {
  MessageSquare, ShieldAlert, Key, User, CheckCircle2, Mail, Sun,
  Moon, ArrowRight, Loader2, Fingerprint, Lock, Eye, EyeOff, QrCode, Smartphone,
  RefreshCw, AlertTriangle, ShieldCheck, Laptop
} from "lucide-react";

type Step =
  | "email"        // Enter email
  | "local-auth"   // Existing user: PIN or fingerprint
  | "otp"          // New user: verify email OTP
  | "register"     // New user: choose username
  | "set-pin";     // After first login: set PIN

const PIN_LENGTH = 4;

export type QrFlowState =
  | "INITIALIZING"
  | "QR_GENERATING"
  | "WAITING_FOR_SCAN"
  | "SCANNED"
  | "WAITING_FOR_APPROVAL"
  | "APPROVED"
  | "AUTHENTICATING"
  | "AUTHENTICATED"
  | "EXPIRED"
  | "REJECTED"
  | "ERROR";

export default function LoginPage() {
  const [loginMode, setLoginMode] = useState<"qr" | "email">("qr");

  // Pre-5pm Classic QR Session State & Resilient Fallback Engine
  const [qrSessionId, setQrSessionId] = useState<string>("");
  const [qrStatus, setQrStatus] = useState<"loading" | "pending" | "approved" | "error" | "expired">("loading");
  const [qrCountdown, setQrCountdown] = useState<number>(120);
  const [qrErrorMessage, setQrErrorMessage] = useState<string>("");

  const pollIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const countdownIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const qrSocketRef = useRef<Socket | null>(null);

  const [email, setEmail] = useState("");
  const [step, setStep] = useState<Step>("email");
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [countdown, setCountdown] = useState(300);

  // OTP digits (new user email verification)
  const [otpDigits, setOtpDigits] = useState<string[]>(Array(4).fill(""));
  const otpRefs = Array.from({ length: 4 }, () => useRef<HTMLInputElement>(null));

  // PIN entry (existing user local auth)
  const [pinDigits, setPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [showPin, setShowPin] = useState(false);
  const pinRefs = Array.from({ length: PIN_LENGTH }, () => useRef<HTMLInputElement>(null));

  // Set-PIN (new user after first login)
  const [newPinDigits, setNewPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [confirmPinDigits, setConfirmPinDigits] = useState<string[]>(Array(PIN_LENGTH).fill(""));
  const [newPinFocused, setNewPinFocused] = useState(true);
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Initialize QR Session (Classic Pre-5pm WhatsApp Web Architecture + Fallback)
  // ─────────────────────────────────────────────────────────────────────────────
  const initQrSession = useCallback(async () => {
    if (pollIntervalRef.current) {
      clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
    if (countdownIntervalRef.current) {
      clearInterval(countdownIntervalRef.current);
      countdownIntervalRef.current = null;
    }
    if (qrSocketRef.current) {
      qrSocketRef.current.disconnect();
      qrSocketRef.current = null;
    }

    setQrStatus("loading");
    setQrErrorMessage("");

    try {
      // 1. Fetch classic QR session (Pre-5pm today)
      let sessionId = "";
      try {
        const res = await fetch(`${API_URL}/api/auth/qr-session`);
        if (res.ok) {
          const data = await res.json();
          if (data && (data.sessionId || data.id)) {
            sessionId = data.sessionId || data.id;
          }
        }
      } catch (e) {
        console.warn("Classic QR session fetch failed, checking fallback:", e);
      }

      // 2. Fallback: try device pair create if classic was unreachable
      if (!sessionId) {
        try {
          const pairRes = await fetch(`${API_URL}/api/devices/pair/create`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
          });
          if (pairRes.ok) {
            const pairData = await pairRes.json();
            if (pairData && pairData.pairingId) {
              sessionId = pairData.pairingId;
            }
          }
        } catch (e) {
          console.warn("Pairing route fallback also failed:", e);
        }
      }

      if (!sessionId) {
        setQrStatus("error");
        setQrErrorMessage("Unable to connect to authentication server. Please check your network and retry.");
        return;
      }

      setQrSessionId(sessionId);
      setQrStatus("pending");
      setQrCountdown(120);

      // Countdown ticker (120 seconds)
      let secondsLeft = 120;
      countdownIntervalRef.current = setInterval(() => {
        secondsLeft -= 1;
        setQrCountdown(secondsLeft);
        if (secondsLeft <= 0) {
          if (countdownIntervalRef.current) clearInterval(countdownIntervalRef.current);
          if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
          if (qrSocketRef.current) qrSocketRef.current.disconnect();
          setQrStatus("expired");
        }
      }, 1000);

      // Realtime WebSocket notification listener for instantaneous login
      try {
        const socket = io(API_URL, {
          auth: { sessionId, qrSessionId: sessionId, pairingId: sessionId },
          transports: ["websocket", "polling"],
          reconnectionAttempts: 3,
        });
        qrSocketRef.current = socket;
        socket.emit("join_qr_room", sessionId);
        socket.on("qr_approved", (data: any) => {
          if (data?.token && data?.user) {
            if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
            if (countdownIntervalRef.current) clearInterval(countdownIntervalRef.current);
            setQrStatus("approved");
            login(data.token, data.user);
          }
        });
        socket.on("PAIRING_APPROVED", () => {
          checkSessionStatus(sessionId);
        });
      } catch (_) {}

      // Polling loop (runs every 2s to guarantee 100% login reliability)
      const checkSessionStatus = async (sid: string) => {
        try {
          // Check classic QR session status
          const checkRes = await fetch(`${API_URL}/api/auth/check-qr-session/${sid}`);
          if (checkRes.ok) {
            const checkData = await checkRes.json();
            if (checkData.status === "APPROVED" && checkData.token && checkData.user) {
              if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
              if (countdownIntervalRef.current) clearInterval(countdownIntervalRef.current);
              if (qrSocketRef.current) qrSocketRef.current.disconnect();
              setQrStatus("approved");
              login(checkData.token, checkData.user);
              return;
            } else if (checkData.status === "EXPIRED") {
              if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
              if (countdownIntervalRef.current) clearInterval(countdownIntervalRef.current);
              if (qrSocketRef.current) qrSocketRef.current.disconnect();
              setQrStatus("expired");
              return;
            }
          }

          // Also check device pairing status fallback
          const pairStatusRes = await fetch(`${API_URL}/api/devices/pair/status/${sid}`);
          if (pairStatusRes.ok) {
            const pairStatusData = await pairStatusRes.json();
            if (pairStatusData.status === "APPROVED") {
              const consumeRes = await fetch(`${API_URL}/api/devices/pair/consume`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ pairingId: sid }),
              });
              const consumeData = await consumeRes.json();
              if (consumeData.success && consumeData.token && consumeData.user) {
                if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
                if (countdownIntervalRef.current) clearInterval(countdownIntervalRef.current);
                if (qrSocketRef.current) qrSocketRef.current.disconnect();
                setQrStatus("approved");
                login(consumeData.token, consumeData.user);
              }
            }
          }
        } catch (_) {}
      };

      pollIntervalRef.current = setInterval(() => {
        checkSessionStatus(sessionId);
      }, 2000);
    } catch (err) {
      console.error("QR initialization error:", err);
      setQrStatus("error");
      setQrErrorMessage("Network error connecting to DOLSYX server");
    }
  }, [login]);

  // Trigger QR initialization when QR login mode is active
  useEffect(() => {
    if (loginMode === "qr") {
      initQrSession();
    }

    return () => {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
        pollIntervalRef.current = null;
      }
      if (countdownIntervalRef.current) {
        clearInterval(countdownIntervalRef.current);
        countdownIntervalRef.current = null;
      }
      if (qrSocketRef.current) {
        qrSocketRef.current.disconnect();
        qrSocketRef.current = null;
      }
    };
  }, [loginMode, initQrSession]);

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
          // Existing user
          const hasPin = localStorage.getItem(`dolsyx_pin_${email.trim().toLowerCase()}`);
          const bioEnabled = localStorage.getItem(`dolsyx_bio_enabled_${email.trim().toLowerCase()}`) === "true";
          
          if (hasPin || bioEnabled) {
            // Has PIN or Bio enabled locally, prompt for it
            setStep("local-auth");
            setHasBiometrics(bioEnabled);
            if (bioEnabled) setTimeout(() => triggerBiometric(), 300);
          } else {
            // New device / No PIN set -> Direct Access without OTP!
            await doLoginWithoutOtp();
          }
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
    if (pin.length < PIN_LENGTH) { setError("Please enter all 4 PIN digits."); return; }
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
    if (digit && index < 3) otpRefs[index + 1].current?.focus();
    const complete = nd.join("");
    if (complete.length === 4 && !nd.includes("")) verifyOtp(complete);
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
    const paste = e.clipboardData.getData("text").replace(/[^0-9]/g, "").slice(0, 4);
    if (paste.length === 4) {
      setOtpDigits(paste.split("")); otpRefs[3].current?.focus(); verifyOtp(paste);
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

      {/* ── WHATSAPP WEB STYLE QR CODE LOGIN MODE ── */}
      {loginMode === "qr" ? (
        <div className="w-full max-w-4xl rounded-3xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] p-8 md:p-12 shadow-2xl backdrop-blur-xl">
          <div className="flex flex-col md:flex-row items-center justify-between gap-10">
            
            {/* Left Column: Instructions */}
            <div className="flex-1 space-y-6 text-left">
              <div className="flex items-center gap-3">
                <div className="flex h-12 w-12 items-center justify-center rounded-2xl text-white shadow-lg bg-gradient-to-tr from-violet-600 to-indigo-600">
                  <MessageSquare className="h-6 w-6" />
                </div>
                <h1 className="text-2xl md:text-3xl font-black text-[var(--theme-text-primary)]">Log into DOLSYX Web</h1>
              </div>

              <p className="text-sm text-[var(--theme-text-secondary)] leading-relaxed">
                Message and call privately with friends and family using DOLSYX on your web browser.
              </p>

              <ol className="space-y-4 text-sm text-[var(--theme-text-primary)] font-medium">
                <li className="flex items-start gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[var(--theme-accent)] text-white text-xs font-bold">1</span>
                  <span>Open <strong className="text-[var(--theme-accent)]">DOLSYX</strong> on your mobile phone</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[var(--theme-accent)] text-white text-xs font-bold">2</span>
                  <span>Go to <strong>Settings ⚙️</strong> &rarr; <strong>Linked Devices</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[var(--theme-accent)] text-white text-xs font-bold">3</span>
                  <span>Tap <strong>Link a device</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[var(--theme-accent)] text-white text-xs font-bold">4</span>
                  <span>Point your phone camera at this screen to scan the QR code</span>
                </li>
              </ol>

              <div className="pt-4 border-t border-[var(--theme-border-color)]">
                <button
                  type="button"
                  onClick={() => setLoginMode("email")}
                  className="inline-flex items-center gap-2 text-sm font-bold text-[var(--theme-accent)] hover:underline cursor-pointer"
                >
                  <span>Log in with Email / PIN</span>
                  <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </div>

            {/* Right Column: QR Code Box */}
            <div className="flex flex-col items-center justify-center space-y-4">
              <div className="relative flex h-72 w-72 flex-col items-center justify-center rounded-3xl border-4 border-[var(--theme-accent)] bg-white p-5 shadow-2xl transition-all duration-300">
                {qrStatus === "loading" ? (
                  <div className="flex flex-col items-center gap-3 text-center">
                    <Loader2 className="h-12 w-12 animate-spin text-[var(--theme-accent)]" />
                    <span className="text-xs font-bold text-gray-700">Generating QR Code...</span>
                    <span className="text-[10px] text-gray-500">Establishing encrypted link</span>
                  </div>
                ) : qrStatus === "approved" ? (
                  <div className="flex flex-col items-center gap-3 p-4 text-center text-emerald-600">
                    <CheckCircle2 className="h-16 w-16 animate-bounce text-emerald-500" />
                    <span className="text-base font-black text-emerald-700">Login Approved!</span>
                    <p className="text-xs font-medium text-gray-600">
                      Syncing your DOLSYX account...
                    </p>
                    <Loader2 className="h-5 w-5 animate-spin text-emerald-600" />
                  </div>
                ) : qrStatus === "expired" ? (
                  <div className="flex flex-col items-center gap-3 p-4 text-center">
                    <div className="flex h-14 w-14 items-center justify-center rounded-full bg-amber-100 text-amber-600">
                      <AlertTriangle className="h-8 w-8" />
                    </div>
                    <span className="text-sm font-black text-gray-800">QR Code Expired</span>
                    <p className="text-[11px] text-gray-500">
                      For security, QR codes expire after 2 minutes.
                    </p>
                    <button
                      type="button"
                      onClick={() => initQrSession()}
                      className="mt-1 flex items-center gap-2 rounded-full bg-[var(--theme-accent)] px-4 py-2 text-xs font-extrabold text-white shadow-md hover:opacity-95 cursor-pointer"
                    >
                      <RefreshCw className="h-3.5 w-3.5" />
                      <span>Generate New QR Code</span>
                    </button>
                  </div>
                ) : qrStatus === "error" ? (
                  <div className="flex flex-col items-center gap-3 p-4 text-center">
                    <ShieldAlert className="h-12 w-12 text-red-500" />
                    <span className="text-xs font-bold text-red-600">{qrErrorMessage || "Failed to load QR code"}</span>
                    <button
                      type="button"
                      onClick={() => initQrSession()}
                      className="mt-2 flex items-center gap-2 rounded-full bg-gray-800 px-3 py-1.5 text-xs font-bold text-white shadow hover:bg-gray-700 cursor-pointer"
                    >
                      <RefreshCw className="h-3 w-3" />
                      <span>Retry</span>
                    </button>
                  </div>
                ) : (
                  /* PENDING: Render QR code (Vector SVG + image fallback) */
                  <div className="relative flex h-full w-full flex-col items-center justify-center">
                    <div className="relative p-1">
                      {qrSessionId && (
                        <QRCode
                          value={`${qrSessionId}||${API_URL}`}
                          size={196}
                          level="M"
                        />
                      )}
                      {/* Centered DOLSYX Brand Badge */}
                      <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
                        <div className="flex h-11 w-11 items-center justify-center rounded-2xl border-2 border-white bg-gradient-to-tr from-violet-600 to-indigo-600 text-white shadow-xl">
                          <MessageSquare className="h-5 w-5" />
                        </div>
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Status and countdown info */}
              {qrStatus === "pending" && (
                <div className="flex flex-col items-center gap-1.5">
                  <div className="flex items-center gap-2 rounded-full bg-[var(--theme-bg-sidebar-search)] px-3 py-1 text-xs font-bold text-[var(--theme-text-primary)] border border-[var(--theme-border-color)] shadow-sm">
                    <div className={`h-2 w-2 rounded-full ${qrCountdown > 20 ? "bg-emerald-500 animate-ping" : "bg-amber-500 animate-pulse"}`} />
                    <span>Expires in {qrCountdown}s</span>
                  </div>
                  <span className="text-[11px] text-[var(--theme-text-secondary)] font-medium">
                    Scan with your phone to log in instantly
                  </span>
                </div>
              )}
            </div>

          </div>
        </div>
      ) : (

      /* ── TRADITIONAL EMAIL / PIN LOGIN MODE ── */
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

        {/* ── STEP: Email / Google ── */}
        {step === "email" && (
          <div className="mt-8 space-y-6">
            {/* Google OAuth Button */}
            <button
              type="button"
              disabled={isLoading}
              onClick={() => {
                setIsLoading(true);
                setInfo("Redirecting to Google authentication...");
                window.location.href = `${API_URL}/api/auth/google`;
              }}
              className="flex w-full items-center justify-center gap-3 rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-container)] py-3.5 px-4 text-sm font-bold text-[var(--theme-text-primary)] hover:bg-[var(--theme-bg-sidebar-item-hover)] shadow-md hover:shadow-lg transition-all cursor-pointer disabled:opacity-50"
            >
              {isLoading ? (
                <Loader2 className="h-5 w-5 animate-spin text-[var(--theme-accent)]" />
              ) : (
                <>
                  <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24">
                    <path
                      fill="#4285F4"
                      d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                    />
                    <path
                      fill="#34A853"
                      d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                    />
                    <path
                      fill="#FBBC05"
                      d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"
                    />
                    <path
                      fill="#EA4335"
                      d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"
                    />
                  </svg>
                  <span>Continue with Google</span>
                </>
              )}
            </button>

            <div className="relative flex items-center justify-center">
              <div className="w-full border-t border-[var(--theme-border-color)]" />
              <span className="absolute bg-[var(--theme-bg-container)] px-3 text-[10px] font-bold uppercase tracking-wider text-[var(--theme-text-secondary)]">
                Or continue with email
              </span>
            </div>

            <form className="space-y-4" onSubmit={handleEmailSubmit}>
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
                    className="block w-full rounded-full border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] py-3 pl-10 pr-4 text-sm text-[var(--theme-text-primary)] focus:border-[var(--theme-accent)] focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]"
                    placeholder="Enter your email address"
                  />
                </div>
              </div>
              <button
                type="submit"
                disabled={isLoading}
                className="flex w-full items-center justify-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer shadow-lg"
              >
                {isLoading ? (
                  <Loader2 className="h-5 w-5 animate-spin" />
                ) : (
                  <>
                    <span>Continue with Email</span>
                    <ArrowRight className="h-4 w-4" />
                  </>
                )}
              </button>
              <div className="mt-4 text-center text-xs text-[var(--theme-text-secondary)]">
                Don't have an account?{" "}
                <button
                  type="button"
                  onClick={() => router.push("/register")}
                  className="font-bold text-[var(--theme-accent)] hover:underline"
                >
                  Sign up
                </button>
              </div>
            </form>
          </div>
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
                className="flex w-full justify-center items-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
              >
                {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <><Lock className="h-4 w-4" /><span>Unlock</span></>}
              </button>

              {hasBiometrics && (
                <button
                  type="button" onClick={triggerBiometric} disabled={isLoading}
                  className="flex w-full items-center justify-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-text-primary)] border border-[var(--theme-border-color)] bg-transparent hover:bg-[var(--theme-bg-sidebar-item-hover)] transition-all cursor-pointer"
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
                className="flex w-full justify-center items-center gap-2 rounded-full py-3.5 text-sm font-extrabold text-[var(--theme-accent-text)] bg-[var(--theme-accent)] hover:opacity-95 disabled:opacity-50 transition-all cursor-pointer"
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
              Set a 4-digit PIN to quickly unlock the app next time you log in.
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
              <button
                type="button"
                onClick={handleSkipPin}
                className="w-full text-center text-xs text-[var(--theme-text-secondary)] hover:text-[var(--theme-accent)] hover:underline cursor-pointer"
              >
                Skip for now
              </button>
            </div>
            <div className="pt-4 border-t border-[var(--theme-border-color)] text-center">
              <button
                type="button"
                onClick={() => setLoginMode("qr")}
                className="inline-flex items-center gap-2 text-xs font-bold text-[var(--theme-accent)] hover:underline cursor-pointer"
              >
                <QrCode className="h-4 w-4" />
                <span>Log in with QR Code instead</span>
              </button>
            </div>
          </div>
        )}
      </div>
      )}
    </div>
  );
}
