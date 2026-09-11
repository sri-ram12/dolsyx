'use client';

import React, { useState, useRef, useCallback, useEffect } from 'react';
import TwemojiText from './twemoji-text';
import {
  getEmojiAnimationProfile,
  EmojiAnimationProfile,
} from '@/lib/emoji-animation/emoji-profiles';
import { EmojiParticleCanvas } from '@/lib/emoji-animation/emoji-particle-canvas';
import {
  playEmojiSound,
  triggerEmojiHaptic,
} from '@/lib/emoji-animation/emoji-feedback';

export interface AnimatedEmojiProps {
  emoji: string;
  size?: 'large' | 'medium' | 'inline' | 'reaction';
  className?: string;
  interactive?: boolean;
  onTap?: () => void;
}

export const AnimatedEmoji: React.FC<AnimatedEmojiProps> = ({
  emoji,
  size = 'large',
  className = '',
  interactive = true,
  onTap,
}) => {
  const [isAnimating, setIsAnimating] = useState(false);
  const [showParticles, setShowParticles] = useState(false);
  const [intensity, setIntensity] = useState(1.0);
  const [animKey, setAnimKey] = useState(0);
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);

  const lastTapTimeRef = useRef<number>(0);
  const tapCountRef = useRef<number>(0);
  const resetTimerRef = useRef<NodeJS.Timeout | null>(null);

  // Check for reduced motion accessibility preference
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    setPrefersReducedMotion(mediaQuery.matches);

    const listener = (e: MediaQueryListEvent) => setPrefersReducedMotion(e.matches);
    mediaQuery.addEventListener('change', listener);
    return () => mediaQuery.removeEventListener('change', listener);
  }, []);

  const profile: EmojiAnimationProfile = getEmojiAnimationProfile(emoji);

  const handleTap = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (!interactive) return;
      e.stopPropagation();

      const now = Date.now();
      const elapsedSinceLastTap = now - lastTapTimeRef.current;
      lastTapTimeRef.current = now;

      // Calculate rapid-tap intensity multiplier
      if (elapsedSinceLastTap < 650) {
        tapCountRef.current = Math.min(tapCountRef.current + 1, 3);
      } else {
        tapCountRef.current = 1;
      }

      // Intensity scale: 1st tap = 1.0, 2nd tap = 1.18, 3rd tap = 1.35
      const newIntensity = 1.0 + (tapCountRef.current - 1) * 0.175;
      setIntensity(newIntensity);

      // Trigger sensory feedback
      triggerEmojiHaptic(profile.hapticType);
      playEmojiSound(profile.soundType);

      // Trigger visual animations
      setIsAnimating(true);
      setShowParticles(!prefersReducedMotion && !!profile.particleConfig);
      setAnimKey((prev) => prev + 1);

      if (onTap) {
        onTap();
      }

      // Auto-settle timer
      if (resetTimerRef.current) {
        clearTimeout(resetTimerRef.current);
      }

      resetTimerRef.current = setTimeout(() => {
        setIsAnimating(false);
        tapCountRef.current = 0;
        setIntensity(1.0);
      }, profile.durationMs);
    },
    [interactive, profile, prefersReducedMotion, onTap]
  );

  const handleParticleComplete = useCallback(() => {
    setShowParticles(false);
  }, []);

  // Compute dimensions according to presentation mode
  const getFontSize = () => {
    switch (size) {
      case 'large':
        return '38px';
      case 'medium':
        return '28px';
      case 'reaction':
        return '14px';
      case 'inline':
      default:
        return '18px';
    }
  };

  // Determine glow styling
  const glowStyle =
    isAnimating && profile.glow && !prefersReducedMotion
      ? {
          filter: `drop-shadow(0 0 ${Math.round(profile.glow.spread * intensity)}px ${profile.glow.color})`,
        }
      : {};

  return (
    <div
      onClick={handleTap}
      className={`relative inline-flex items-center justify-center select-none ${
        interactive ? 'cursor-pointer' : ''
      } ${className}`}
      style={{
        fontSize: getFontSize(),
        lineHeight: 1,
      }}
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onKeyDown={(e) => {
        if (interactive && (e.key === 'Enter' || e.key === ' ')) {
          e.preventDefault();
          handleTap(e as any);
        }
      }}
    >
      {/* Main Animated Glyph - Stable in place with zero zooming and no background overlay */}
      <span
        key={`glyph-${animKey}`}
        className="inline-block"
      >
        <TwemojiText text={emoji} />
      </span>
    </div>
  );
};

export default AnimatedEmoji;
