"use client";

import React, { useState, useEffect, useRef } from "react";
import { Lock, ArrowRight, ShieldAlert } from "lucide-react";
import { useTheme } from "@/context/theme-context";

interface AppLockProps {
  onUnlock: () => void;
}

export default function AppLock({ onUnlock }: AppLockProps) {
  const [pinDigits, setPinDigits] = useState<string[]>(Array(4).fill(""));
  const [error, setError] = useState("");
  const { theme } = useTheme();
  const inputRefs = [
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null), // Supports up to 6 digits dynamically
  ];

  const [pinLength, setPinLength] = useState(4);

  useEffect(() => {
    // Detect PIN configuration length from local storage hash target
    const storedHash = localStorage.getItem("dolsyx_pin_hash");
    if (storedHash) {
      // We will dynamically allow input up to 6 digits. Enter will submit or auto-submit when filled.
      // E.g. Check length if they enter digits
    }
    inputRefs[0].current?.focus();
  }, []);

  const handleDigitChange = (index: number, val: string) => {
    const digit = val.replace(/[^0-9]/g, "").slice(-1);
    const newDigits = [...pinDigits];
    newDigits[index] = digit;
    setPinDigits(newDigits);
    setError("");

    if (digit && index < pinLength - 1) {
      inputRefs[index + 1].current?.focus();
    }

    // Auto verify if all fields filled
    const entered = newDigits.slice(0, pinLength).join("");
    if (entered.length === pinLength && !newDigits.slice(0, pinLength).includes("")) {
      verifyPin(entered);
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace") {
      if (!pinDigits[index] && index > 0) {
        const newDigits = [...pinDigits];
        newDigits[index - 1] = "";
        setPinDigits(newDigits);
        inputRefs[index - 1].current?.focus();
      } else {
        const newDigits = [...pinDigits];
        newDigits[index] = "";
        setPinDigits(newDigits);
      }
    }
  };

  const verifyPin = async (enteredPin: string) => {
    const storedHash = localStorage.getItem("dolsyx_pin_hash");
    if (!storedHash) {
      onUnlock();
      return;
    }

    // Hash entered PIN using SHA-256
    const msgBuffer = new TextEncoder().encode(enteredPin);
    const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    if (hashHex === storedHash) {
      sessionStorage.setItem("dolsyx_unlocked", "true");
      onUnlock();
    } else {
      setError("Incorrect PIN. Please try again.");
      setPinDigits(Array(pinLength).fill(""));
      inputRefs[0].current?.focus();
    }
  };

  const togglePinLength = () => {
    const nextLen = pinLength === 4 ? 6 : 4;
    setPinLength(nextLen);
    setPinDigits(Array(nextLen).fill(""));
    setError("");
    setTimeout(() => {
      inputRefs[0].current?.focus();
    }, 50);
  };

  return (
    <div className="fixed inset-0 z-[99999] flex flex-col items-center justify-center bg-slate-950 px-4">
      <div className="w-full max-w-md space-y-8 rounded-2xl border border-zinc-900 bg-slate-900/40 p-8 shadow-2xl backdrop-blur-xl text-center">
        <div className="flex flex-col items-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-cyan-600/10 text-cyan-400 border border-cyan-500/20 shadow-md">
            <Lock className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-2xl font-black text-white">App Locked</h2>
          <p className="mt-2 text-xs text-slate-400">Enter your secure PIN to access DOLSYX Messenger</p>
        </div>

        {error && (
          <div className="flex items-center justify-center gap-2 rounded-xl border border-red-500/20 bg-red-500/10 p-3.5 text-xs text-red-400">
            <ShieldAlert className="h-4 w-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        <div className="flex justify-center gap-3">
          {Array.from({ length: pinLength }).map((_, idx) => (
            <input
              key={idx}
              ref={inputRefs[idx]}
              type="password"
              pattern="[0-9]*"
              inputMode="numeric"
              maxLength={1}
              value={pinDigits[idx] || ""}
              onChange={(e) => handleDigitChange(idx, e.target.value)}
              onKeyDown={(e) => handleKeyDown(idx, e)}
              className="h-12 w-12 text-center text-xl font-bold rounded-xl border border-zinc-800 bg-slate-950 text-white focus:border-cyan-500 focus:outline-none transition-all"
            />
          ))}
        </div>

        <div className="pt-2">
          <button
            onClick={togglePinLength}
            className="text-[10px] font-bold text-slate-400 hover:text-white transition-colors cursor-pointer"
          >
            Switch to {pinLength === 4 ? "6" : "4"}-digit PIN entry
          </button>
        </div>
      </div>
    </div>
  );
}
