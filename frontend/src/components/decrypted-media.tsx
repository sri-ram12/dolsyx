"use client";

import React, { useState, useEffect, useRef } from "react";
import { resolveMediaUrl } from "@/utils/avatar";
import { decryptFileBytes } from "@/utils/e2ee/cryptoService";
import { Loader2, AlertCircle, RefreshCw } from "lucide-react";

// Global in-memory cache of decrypted Object URLs to prevent redundant re-decryptions during scrolling
const decryptedBlobCache = new Map<string, string>();

/** Helper to detect media mime type from binary magic headers */
function detectMimeType(buffer: ArrayBuffer, fallbackType: "image" | "video"): string {
  const bytes = new Uint8Array(buffer.slice(0, 16));
  
  // MP4 / MOV: 'ftyp' at bytes 4..7
  if (bytes.length >= 8 && bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
    return "video/mp4";
  }
  // WebM / Matroska: 0x1A 0x45 0xDF 0xA3
  if (bytes.length >= 4 && bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3) {
    return "video/webm";
  }
  // JPEG: 0xFF, 0xD8, 0xFF
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  // PNG: 0x89, 0x50, 0x4E, 0x47
  if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return "image/png";
  }
  // GIF: 'GIF8'
  if (bytes.length >= 4 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
    return "image/gif";
  }
  // WebP: 'RIFF' + 'WEBP'
  if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
    return "image/webp";
  }

  return fallbackType === "video" ? "video/mp4" : "image/jpeg";
}

interface DecryptedImageProps {
  mediaUrl: string;
  mediaKey?: string | null;
  nonce?: string | null;
  isE2EEMedia?: boolean;
  alt?: string;
  className?: string;
  onClick?: () => void;
}

export const DecryptedImage: React.FC<DecryptedImageProps> = ({
  mediaUrl,
  mediaKey,
  nonce,
  isE2EEMedia,
  alt = "Image attachment",
  className = "w-full max-h-96 object-cover cursor-pointer hover:opacity-90 transition-opacity",
  onClick,
}) => {
  const [src, setSrc] = useState<string>(() => {
    if (!isE2EEMedia || !mediaKey) {
      return resolveMediaUrl(mediaUrl);
    }
    return decryptedBlobCache.get(mediaUrl) || "";
  });
  const [loading, setLoading] = useState<boolean>(!src);
  const [error, setError] = useState<boolean>(false);

  useEffect(() => {
    if (!mediaUrl) return;

    // Non-E2EE media can be displayed directly
    if (!isE2EEMedia || !mediaKey) {
      setSrc(resolveMediaUrl(mediaUrl));
      setLoading(false);
      return;
    }

    // Check cached decrypted Object URL
    if (decryptedBlobCache.has(mediaUrl)) {
      setSrc(decryptedBlobCache.get(mediaUrl)!);
      setLoading(false);
      return;
    }

    let isMounted = true;
    setLoading(true);
    setError(false);

    const loadAndDecrypt = async () => {
      try {
        const resolvedUrl = resolveMediaUrl(mediaUrl);
        const res = await fetch(resolvedUrl);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const encryptedBuffer = await res.arrayBuffer();

        const decryptedBuffer = await decryptFileBytes(encryptedBuffer, mediaKey, nonce || "");
        const mimeType = detectMimeType(decryptedBuffer, "image");
        const blob = new Blob([decryptedBuffer], { type: mimeType });
        const blobUrl = URL.createObjectURL(blob);

        decryptedBlobCache.set(mediaUrl, blobUrl);
        if (isMounted) {
          setSrc(blobUrl);
          setLoading(false);
        }
      } catch (err) {
        console.warn("[DecryptedImage] Failed to decrypt image:", err);
        if (isMounted) {
          setError(true);
          setLoading(false);
        }
      }
    };

    loadAndDecrypt();

    return () => {
      isMounted = false;
    };
  }, [mediaUrl, mediaKey, nonce, isE2EEMedia]);

  if (loading) {
    return (
      <div className="w-full h-64 bg-zinc-900 flex flex-col items-center justify-center text-zinc-400 gap-2 select-none animate-pulse">
        <Loader2 className="w-6 h-6 animate-spin text-emerald-500" />
        <span className="text-[12px] font-medium">Decrypting photo...</span>
      </div>
    );
  }

  if (error || !src) {
    return (
      <div className="w-full h-48 bg-zinc-900 border border-zinc-800 rounded-2xl flex flex-col items-center justify-center p-4 text-center">
        <AlertCircle className="w-8 h-8 text-amber-500 mb-2" />
        <p className="text-[13px] font-medium text-zinc-300">Unable to decrypt photo</p>
        <button
          onClick={() => {
            setError(false);
            setLoading(true);
            decryptedBlobCache.delete(mediaUrl);
            setSrc("");
          }}
          className="mt-2.5 flex items-center gap-1.5 px-3 py-1 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white text-[11px] font-semibold transition-colors"
        >
          <RefreshCw className="w-3.5 h-3.5" /> Retry
        </button>
      </div>
    );
  }

  return (
    <img
      src={src}
      alt={alt}
      className={className}
      onClick={onClick || (() => window.open(src, "_blank"))}
      loading="lazy"
    />
  );
};

interface DecryptedVideoProps {
  mediaUrl: string;
  mediaKey?: string | null;
  nonce?: string | null;
  isE2EEMedia?: boolean;
  className?: string;
  fileName?: string;
}

export const DecryptedVideo: React.FC<DecryptedVideoProps> = ({
  mediaUrl,
  mediaKey,
  nonce,
  isE2EEMedia,
  className = "w-full max-h-72 object-contain bg-black rounded-2xl",
  fileName = "dolsyx_video.mp4",
}) => {
  const [src, setSrc] = useState<string>(() => {
    if (!isE2EEMedia || !mediaKey) {
      return resolveMediaUrl(mediaUrl);
    }
    return decryptedBlobCache.get(mediaUrl) || "";
  });
  const [loading, setLoading] = useState<boolean>(!src);
  const [error, setError] = useState<boolean>(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (!mediaUrl) return;

    if (!isE2EEMedia || !mediaKey) {
      setSrc(resolveMediaUrl(mediaUrl));
      setLoading(false);
      return;
    }

    if (decryptedBlobCache.has(mediaUrl)) {
      setSrc(decryptedBlobCache.get(mediaUrl)!);
      setLoading(false);
      return;
    }

    let isMounted = true;
    setLoading(true);
    setError(false);

    const loadAndDecrypt = async () => {
      try {
        const resolvedUrl = resolveMediaUrl(mediaUrl);
        const res = await fetch(resolvedUrl);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const encryptedBuffer = await res.arrayBuffer();

        const decryptedBuffer = await decryptFileBytes(encryptedBuffer, mediaKey, nonce || "");
        const mimeType = detectMimeType(decryptedBuffer, "video");
        const blob = new Blob([decryptedBuffer], { type: mimeType });
        const blobUrl = URL.createObjectURL(blob);

        decryptedBlobCache.set(mediaUrl, blobUrl);
        if (isMounted) {
          setSrc(blobUrl);
          setLoading(false);
        }
      } catch (err) {
        console.warn("[DecryptedVideo] Failed to decrypt video:", err);
        if (isMounted) {
          setError(true);
          setLoading(false);
        }
      }
    };

    loadAndDecrypt();

    return () => {
      isMounted = false;
    };
  }, [mediaUrl, mediaKey, nonce, isE2EEMedia]);

  if (loading) {
    return (
      <div className="w-full h-56 bg-zinc-950 flex flex-col items-center justify-center text-zinc-400 gap-2.5 rounded-2xl border border-zinc-800">
        <Loader2 className="w-8 h-8 animate-spin text-emerald-500" />
        <span className="text-[13px] font-semibold text-zinc-200">Decrypting & buffering video...</span>
        <span className="text-[11px] text-zinc-500">End-to-End Encrypted</span>
      </div>
    );
  }

  if (error || !src) {
    return (
      <div className="w-full h-56 bg-zinc-950 border border-zinc-800 rounded-2xl flex flex-col items-center justify-center p-4 text-center">
        <AlertCircle className="w-8 h-8 text-amber-500 mb-2" />
        <p className="text-[13px] font-medium text-zinc-300">Unable to play video</p>
        <p className="text-[11px] text-zinc-500 mt-0.5">Decryption failed or stream unavailable</p>
        <button
          onClick={() => {
            setError(false);
            setLoading(true);
            decryptedBlobCache.delete(mediaUrl);
            setSrc("");
          }}
          className="mt-3 flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white text-[12px] font-semibold transition-colors"
        >
          <RefreshCw className="w-3.5 h-3.5" /> Retry Playback
        </button>
      </div>
    );
  }

  return (
    <div className="relative group">
      <video
        ref={videoRef}
        src={src}
        controls
        preload="auto"
        playsInline
        className={className}
        style={{ display: "block" }}
        onError={(e) => {
          console.error("Decrypted video playback error:", e);
          setError(true);
        }}
      >
        <source src={src} type="video/mp4" />
        Your browser does not support video playback.
      </video>
    </div>
  );
};
