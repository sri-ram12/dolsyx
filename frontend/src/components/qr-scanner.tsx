"use client";

import React, { useEffect, useState, useRef } from "react";
import { Html5Qrcode } from "html5-qrcode";

interface QRScannerProps {
  onScanSuccess: (decodedText: string) => void;
  onScanFailure?: (error: any) => void;
}

export default function QRScanner({ onScanSuccess, onScanFailure }: QRScannerProps) {
  const [error, setError] = useState<string>("");
  const scannerRef = useRef<Html5Qrcode | null>(null);

  useEffect(() => {
    let isMounted = true;
    const html5QrCode = new Html5Qrcode("qr-reader");
    scannerRef.current = html5QrCode;

    html5QrCode.start(
      { facingMode: "environment" },
      { fps: 10, qrbox: { width: 250, height: 250 } },
      (decodedText) => {
        if (isMounted) {
          html5QrCode.stop().then(() => {
            onScanSuccess(decodedText);
          }).catch(console.error);
        }
      },
      (errorMessage) => {
        if (onScanFailure) onScanFailure(errorMessage);
      }
    ).catch((err) => {
      if (isMounted) {
        setError("Camera not found or permission denied. Please check your browser permissions.");
        console.error("QR Scanner Start Error:", err);
      }
    });

    return () => {
      isMounted = false;
      if (html5QrCode.isScanning) {
        html5QrCode.stop().catch(console.error);
      }
    };
  }, [onScanSuccess, onScanFailure]);

  return (
    <div className="w-full max-w-sm mx-auto flex flex-col items-center">
      <div id="qr-reader" className="w-full bg-black rounded-xl overflow-hidden shadow-inner" style={{ minHeight: "250px" }} />
      {error && <p className="text-red-500 mt-2 text-xs font-semibold px-2">{error}</p>}
    </div>
  );
}
