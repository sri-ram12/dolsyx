/**
 * DOLSYX Emoji Feedback Engine
 * Handles micro-haptic patterns and low-latency synthesized Web Audio micro-tones.
 */

import { HapticType, SoundType } from './emoji-profiles';

// Persistent Web Audio context singleton
let audioContext: AudioContext | null = null;
let soundEnabled = true;
let hapticsEnabled = true;

/**
 * Ensures safe audio context initialization on user gesture
 */
function getAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  try {
    if (!audioContext || audioContext.state === 'closed') {
      const AudioContextClass =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!AudioContextClass) return null;
      audioContext = new AudioContextClass();
    }
    if (audioContext.state === 'suspended') {
      audioContext.resume().catch(() => {});
    }
    return audioContext;
  } catch {
    return null;
  }
}

/**
 * Configure global emoji feedback preferences
 */
export function setEmojiFeedbackConfig(options: { sound?: boolean; haptics?: boolean }) {
  if (options.sound !== undefined) soundEnabled = options.sound;
  if (options.haptics !== undefined) hapticsEnabled = options.haptics;
}

/**
 * Triggers subtle physical haptic feedback if supported by the browser/device
 */
export function triggerEmojiHaptic(type: HapticType = 'soft'): void {
  if (!hapticsEnabled || typeof window === 'undefined' || !navigator.vibrate) {
    return;
  }

  try {
    switch (type) {
      case 'heartbeat':
        // Double-thump heartbeat
        navigator.vibrate([22, 60, 26]);
        break;
      case 'light-rapid':
        // Triple chuckle/clap flutter
        navigator.vibrate([14, 25, 14, 25, 14]);
        break;
      case 'celebration':
        // Festive ascending rhythm
        navigator.vibrate([10, 30, 15, 30, 20]);
        break;
      case 'snap':
      case 'heavy':
        // Snappy impact
        navigator.vibrate(35);
        break;
      case 'medium':
        navigator.vibrate(22);
        break;
      case 'soft':
      default:
        navigator.vibrate(12);
        break;
    }
  } catch {
    // Ignore unsupported vibration calls
  }
}

/**
 * Plays ultra-short, pleasant micro-sounds via Web Audio API.
 * Keeps gain strictly low (0.04 to 0.10) to remain non-intrusive and organic.
 */
export function playEmojiSound(type: SoundType = 'pop'): void {
  if (!soundEnabled || type === 'none') return;

  const ctx = getAudioContext();
  if (!ctx) return;

  const now = ctx.currentTime;

  try {
    switch (type) {
      case 'heartbeat': {
        // Deep warm sub-bass pulse
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(80, now);
        osc.frequency.exponentialRampToValueAtTime(38, now + 0.16);

        gain.gain.setValueAtTime(0.08, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.18);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.19);

        // Secondary pulse 120ms later
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(70, now + 0.11);
        osc2.frequency.exponentialRampToValueAtTime(32, now + 0.28);

        gain2.gain.setValueAtTime(0.06, now + 0.11);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.29);

        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now + 0.11);
        osc2.stop(now + 0.3);
        break;
      }

      case 'pop': {
        // Snappy organic bubble pop
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(320, now);
        osc.frequency.exponentialRampToValueAtTime(680, now + 0.07);

        gain.gain.setValueAtTime(0.07, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.08);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.09);
        break;
      }

      case 'laugh': {
        // Bouncy two-tone chuckle
        [0, 0.08].forEach((delay, i) => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(400 + i * 120, now + delay);
          osc.frequency.exponentialRampToValueAtTime(560 + i * 120, now + delay + 0.07);

          gain.gain.setValueAtTime(0.05, now + delay);
          gain.gain.exponentialRampToValueAtTime(0.001, now + delay + 0.08);

          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now + delay);
          osc.stop(now + delay + 0.09);
        });
        break;
      }

      case 'chime': {
        // Pure harmonic love chime
        [523.25, 659.25, 783.99].forEach((freq, idx) => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(freq, now + idx * 0.035);

          gain.gain.setValueAtTime(0.045, now + idx * 0.035);
          gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.035 + 0.32);

          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now + idx * 0.035);
          osc.stop(now + idx * 0.035 + 0.34);
        });
        break;
      }

      case 'sparkle': {
        // Festive sparkle arpeggio
        [660, 880, 1174.66, 1567.98].forEach((freq, idx) => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(freq, now + idx * 0.04);

          gain.gain.setValueAtTime(0.035, now + idx * 0.04);
          gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.04 + 0.22);

          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now + idx * 0.04);
          osc.stop(now + idx * 0.04 + 0.24);
        });
        break;
      }

      case 'flame':
      case 'whoosh': {
        // Gentle airy filtered whoosh
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(140, now);
        osc.frequency.exponentialRampToValueAtTime(320, now + 0.08);
        osc.frequency.exponentialRampToValueAtTime(100, now + 0.2);

        gain.gain.setValueAtTime(0.04, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.22);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.24);
        break;
      }

      case 'impact': {
        // Punchy tactile thud
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(180, now);
        osc.frequency.exponentialRampToValueAtTime(45, now + 0.12);

        gain.gain.setValueAtTime(0.06, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.14);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.15);
        break;
      }

      case 'drip': {
        // Descending water drop tone
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(820, now);
        osc.frequency.exponentialRampToValueAtTime(480, now + 0.14);

        gain.gain.setValueAtTime(0.06, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.16);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.18);
        break;
      }
    }
  } catch {
    // Audio synthesis failure safe catch
  }
}
