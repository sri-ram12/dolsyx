"use client";

import React, { createContext, useContext, useState, useCallback } from "react";
import { X, CheckCircle, AlertTriangle, Info, AlertCircle } from "lucide-react";

export type ToastType = "success" | "error" | "warning" | "info";

interface Toast {
  id: string;
  message: string;
  type: ToastType;
  duration?: number;
}

interface ToastContextType {
  toast: (message: string, type?: ToastType, duration?: number) => void;
  toasts: Toast[];
  removeToast: (id: string) => void;
}

const ToastContext = createContext<ToastContextType | undefined>(undefined);

export const ToastProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const removeToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback((message: string, type: ToastType = "info", duration = 4000) => {
    const id = Math.random().toString(36).substring(2, 9);
    setToasts((prev) => [...prev, { id, message, type, duration }]);

    setTimeout(() => {
      removeToast(id);
    }, duration);
  }, [removeToast]);

  return (
    <ToastContext.Provider value={{ toast, toasts, removeToast }}>
      {children}
      {/* Floating Toast Container */}
      <div className="fixed bottom-5 right-5 z-[9999] flex flex-col gap-3 max-w-sm w-full pointer-events-none">
        {toasts.map((t) => {
          const iconMap = {
            success: <CheckCircle className="h-5 w-5 text-emerald-400 shrink-0" />,
            error: <AlertCircle className="h-5 w-5 text-rose-400 shrink-0" />,
            warning: <AlertTriangle className="h-5 w-5 text-amber-400 shrink-0" />,
            info: <Info className="h-5 w-5 text-cyan-400 shrink-0" />,
          };

          const borderMap = {
            success: "border-emerald-500/20 bg-emerald-950/80 text-emerald-100",
            error: "border-rose-500/20 bg-rose-950/80 text-rose-100",
            warning: "border-amber-500/20 bg-amber-950/80 text-amber-100",
            info: "border-cyan-500/20 bg-cyan-950/80 text-cyan-100",
          };

          return (
            <div
              key={t.id}
              className={`flex items-start gap-3 rounded-xl border p-4 shadow-2xl backdrop-blur-md pointer-events-auto animate-[slideIn_0.2s_ease-out] transition-all duration-300 ${borderMap[t.type]}`}
            >
              {iconMap[t.type]}
              <div className="flex-1 text-xs font-semibold leading-relaxed">
                {t.message}
              </div>
              <button
                onClick={() => removeToast(t.id)}
                className="text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] shrink-0 transition-colors p-0.5 rounded-lg hover:bg-white/5 cursor-pointer"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
};

export const useToast = () => {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error("useToast must be used within a ToastProvider");
  }
  return context;
};
