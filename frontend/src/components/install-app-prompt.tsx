"use client";

import React, { useState, useEffect } from "react";
import { Download, Share, PlusSquare, X, Smartphone, CheckCircle, Apple } from "lucide-react";

export default function InstallAppPrompt() {
  const [isIOS, setIsIOS] = useState(false);
  const [isAndroid, setIsAndroid] = useState(false);
  const [isStandalone, setIsStandalone] = useState(false);
  const [showPrompt, setShowPrompt] = useState(false);
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const ua = navigator.userAgent || "";
    const iosDevice = /iPhone|iPad|iPod/i.test(ua);
    const androidDevice = /Android/i.test(ua);
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      (navigator as any).standalone === true;

    setIsIOS(iosDevice);
    setIsAndroid(androidDevice);
    setIsStandalone(standalone);

    // Show prompt automatically for mobile devices if not already running in standalone app mode
    const dismissed = localStorage.getItem("dolsyx_install_dismissed");
    if (!standalone && (iosDevice || androidDevice) && !dismissed) {
      setShowPrompt(true);
    }

    const handleBeforeInstall = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e);
      if (!standalone) {
        setShowPrompt(true);
      }
    };

    window.addEventListener("beforeinstallprompt", handleBeforeInstall);
    return () => window.removeEventListener("beforeinstallprompt", handleBeforeInstall);
  }, []);

  const handleDismiss = () => {
    setShowPrompt(false);
    localStorage.setItem("dolsyx_install_dismissed", "true");
  };

  const handleNativeInstall = async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const choice = await deferredPrompt.userChoice;
      if (choice.outcome === "accepted") {
        setShowPrompt(false);
      }
      setDeferredPrompt(null);
    }
  };

  if (isStandalone || !showPrompt) return null;

  return (
    <div className="fixed bottom-4 left-4 right-4 z-[9999] max-w-md mx-auto bg-slate-900/95 backdrop-blur-xl border border-purple-500/30 shadow-2xl rounded-2xl p-4 text-white animate-in slide-in-from-bottom duration-300">
      <div className="flex items-start justify-between gap-3 mb-2">
        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-xl bg-gradient-to-tr from-purple-600 via-pink-500 to-blue-500 p-0.5 shadow-lg flex-shrink-0 flex items-center justify-center">
            <div className="w-full h-full bg-slate-950 rounded-[10px] flex items-center justify-center">
              <Smartphone className="w-6 h-6 text-purple-400" />
            </div>
          </div>
          <div>
            <h3 className="font-bold text-sm tracking-wide flex items-center gap-1.5">
              Install DOLSYX App
              {isIOS && (
                <span className="text-[10px] bg-purple-500/20 text-purple-300 border border-purple-500/40 px-2 py-0.5 rounded-full font-mono flex items-center gap-1">
                  <Apple className="w-3 h-3 inline" /> iPhone
                </span>
              )}
            </h3>
            <p className="text-xs text-slate-300 mt-0.5">
              {isIOS
                ? "Install DOLSYX on your iPhone for full native calling & messaging!"
                : "Download official DOLSYX app for instant notifications & video calls."}
            </p>
          </div>
        </div>
        <button
          onClick={handleDismiss}
          className="text-slate-400 hover:text-white p-1 rounded-lg transition-colors"
          title="Close"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* iPhone Specific Installation Guide */}
      {isIOS ? (
        <div className="mt-3 bg-purple-950/40 border border-purple-500/30 rounded-xl p-3 text-xs space-y-2">
          <p className="font-semibold text-purple-200">How to install on iPhone (3 Easy Steps):</p>
          <ol className="space-y-1.5 text-slate-300">
            <li className="flex items-center gap-2">
              <span className="w-5 h-5 rounded-full bg-purple-600/50 text-purple-200 flex items-center justify-center font-bold text-[10px]">
                1
              </span>
              <span>
                Tap the <Share className="w-3.5 h-3.5 inline text-blue-400 mx-0.5" /> <strong>Share</strong> button in Safari toolbar.
              </span>
            </li>
            <li className="flex items-center gap-2">
              <span className="w-5 h-5 rounded-full bg-purple-600/50 text-purple-200 flex items-center justify-center font-bold text-[10px]">
                2
              </span>
              <span>
                Scroll down and tap <PlusSquare className="w-3.5 h-3.5 inline text-purple-400 mx-0.5" /> <strong>Add to Home Screen</strong>.
              </span>
            </li>
            <li className="flex items-center gap-2">
              <span className="w-5 h-5 rounded-full bg-purple-600/50 text-purple-200 flex items-center justify-center font-bold text-[10px]">
                3
              </span>
              <span>
                Tap <strong>Add</strong> at top right. Launch DOLSYX right from your iPhone home screen!
              </span>
            </li>
          </ol>
        </div>
      ) : (
        <div className="mt-3 flex items-center gap-2">
          {deferredPrompt ? (
            <button
              onClick={handleNativeInstall}
              className="flex-1 py-2 px-3 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium text-xs flex items-center justify-center gap-1.5 transition-all shadow-lg active:scale-95"
            >
              <Download className="w-4 h-4" /> Install Web App
            </button>
          ) : (
            <a
              href="/dolsyx-app.apk"
              download="dolsyx-app.apk"
              className="flex-1 py-2 px-3 rounded-xl bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-500 hover:to-pink-500 text-white font-medium text-xs flex items-center justify-center gap-1.5 transition-all shadow-lg active:scale-95"
            >
              <Download className="w-4 h-4" /> Download Android APK
            </a>
          )}
        </div>
      )}
    </div>
  );
}
