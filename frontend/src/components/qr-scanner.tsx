"use client";

import React, { useEffect, useState } from "react";
import { Html5QrcodeScanner } from "html5-qrcode";

interface QRScannerProps {
  onScanSuccess: (decodedText: string) => void;
  onScanFailure?: (error: any) => void;
}

export default function QRScanner({ onScanSuccess, onScanFailure }: QRScannerProps) {
  const [error, setError] = useState<string>("");

  useEffect(() => {
    const scanner = new Html5QrcodeScanner(
      "qr-reader",
      { fps: 10, qrbox: { width: 250, height: 250 } },
      false
    );

    scanner.render(
      (text) => {
        scanner.clear();
        onScanSuccess(text);
      },
      (err) => {
        if (onScanFailure) onScanFailure(err);
      }
    );

    return () => {
      scanner.clear().catch(e => console.error("Failed to clear scanner", e));
    };
  }, [onScanSuccess, onScanFailure]);

  return (
    <div className="w-full max-w-sm mx-auto flex flex-col items-center">
      <div id="qr-reader" className="w-full bg-black/20 rounded-xl overflow-hidden text-[var(--theme-text-primary)]" />
      {error && <p className="text-red-500 mt-2 text-sm">{error}</p>}
    </div>
  );
}
