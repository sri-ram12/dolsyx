"use client";

import React, { useEffect, useRef } from "react";

interface TwemojiTextProps {
  text: string;
  className?: string;
}

// Renders text with custom Twemoji SVG emojis
// Uses the Twemoji CDN to replace native OS emoji with consistent cross-platform images
export default function TwemojiText({ text, className }: TwemojiTextProps) {
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    // Use Twemoji CDN SVGs for consistent rendering
    try {
      // Dynamically import twemoji to avoid SSR issues
      import("twemoji").then((twemojiModule) => {
        const twemoji = twemojiModule.default || twemojiModule;
        if (ref.current) {
          (twemoji as any).parse(ref.current, {
            folder: "svg",
            ext: ".svg",
            base: "https://cdn.jsdelivr.net/gh/twitter/twemoji@14/assets/",
            className: "twemoji-img",
          });
        }
      });
    } catch (e) {
      // Fallback: render as plain text
    }
  }, [text]);

  return (
    <span
      ref={ref}
      className={className}
      style={{ wordBreak: "break-word" }}
      suppressHydrationWarning
    >
      {text}
    </span>
  );
}
