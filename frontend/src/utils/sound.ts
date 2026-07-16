/**
 * DOLSYX SoundEngine
 * Provides 10 built-in notification tones, 10 ringtones (via Web Audio API),
 * and support for a custom uploaded audio file stored as base64 in localStorage.
 *
 * Settings keys:
 *   dolsyx_notif_sound  — "0"-"9" or "custom"
 *   dolsyx_call_sound   — "0"-"9" or "custom"
 *   dolsyx_custom_notif — base64 audio data URL
 *   dolsyx_custom_ring  — base64 audio data URL
 */

class SoundEngineClass {
  private audioCtx: AudioContext | null = null;
  private ringIntervalId: ReturnType<typeof setInterval> | null = null;
  private ringAudioEl: HTMLAudioElement | null = null;

  /* ── AudioContext ──────────────────────────────────────────────────── */

  private getCtx(): AudioContext | null {
    if (typeof window === "undefined") return null;
    try {
      if (!this.audioCtx || this.audioCtx.state === "closed") {
        const Cls = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
        if (!Cls) return null;
        this.audioCtx = new Cls();
      }
      if (this.audioCtx && this.audioCtx.state === "suspended") {
        this.audioCtx.resume();
      }
      return this.audioCtx;
    } catch {
      return null;
    }
  }

  /** Call this on first user gesture to unlock AudioContext */
  unlock() {
    this.getCtx();
  }

  /* ── Low-level tone helpers ───────────────────────────────────────── */

  private playTone(
    ctx: AudioContext,
    freq: number,
    start: number,
    dur: number,
    gain = 0.22,
    type: OscillatorType = "sine"
  ) {
    const osc = ctx.createOscillator();
    const gainNode = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, start);
    gainNode.gain.setValueAtTime(0, start);
    gainNode.gain.linearRampToValueAtTime(gain, start + 0.02);
    gainNode.gain.exponentialRampToValueAtTime(0.001, start + dur);
    osc.connect(gainNode);
    gainNode.connect(ctx.destination);
    osc.start(start);
    osc.stop(start + dur + 0.01);
  }

  /* ── 10 notification sound generators ────────────────────────────── */

  private notifGenerators: Array<(ctx: AudioContext) => void> = [
    // 0: Classic double ping (C6->E6)
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 1046.5, t, 0.18, 0.28);
      this.playTone(ctx, 1318.5, t + 0.12, 0.22, 0.20);
    },
    // 1: WhatsApp-style pop
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 880, t, 0.08, 0.25, "triangle");
      this.playTone(ctx, 1100, t + 0.05, 0.12, 0.20, "triangle");
    },
    // 2: Soft chime
    (ctx) => {
      const t = ctx.currentTime;
      [523.25, 659.25, 783.99, 1046.5].forEach((f, i) =>
        this.playTone(ctx, f, t + i * 0.07, 0.25, 0.18)
      );
    },
    // 3: Rising arpeggio
    (ctx) => {
      const t = ctx.currentTime;
      [440, 554.37, 659.25, 880].forEach((f, i) =>
        this.playTone(ctx, f, t + i * 0.06, 0.15, 0.2, "square")
      );
    },
    // 4: Digital blip
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 1760, t, 0.04, 0.3, "square");
      this.playTone(ctx, 1760, t + 0.08, 0.04, 0.3, "square");
    },
    // 5: Bell tone
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 1318.5, t, 0.5, 0.35);
      this.playTone(ctx, 2637, t, 0.25, 0.12);
    },
    // 6: Gentle knock
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 200, t, 0.1, 0.4, "triangle");
      this.playTone(ctx, 300, t + 0.12, 0.08, 0.3, "triangle");
    },
    // 7: Space ping
    (ctx) => {
      const t = ctx.currentTime;
      const osc = ctx.createOscillator();
      const g = ctx.createGain();
      osc.type = "sine";
      osc.frequency.setValueAtTime(400, t);
      osc.frequency.linearRampToValueAtTime(1200, t + 0.3);
      g.gain.setValueAtTime(0.25, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.35);
      osc.connect(g); g.connect(ctx.destination);
      osc.start(t); osc.stop(t + 0.4);
    },
    // 8: Marimba two-note
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 784, t, 0.4, 0.28, "triangle");
      this.playTone(ctx, 1046.5, t + 0.15, 0.35, 0.22, "triangle");
    },
    // 9: Subtle click
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 600, t, 0.03, 0.35, "square");
    },
  ];

  /* ── 10 ringtone generators ──────────────────────────────────────── */

  private ringGenerators: Array<(ctx: AudioContext) => void> = [
    // 0: Classic phone ring (two-tone)
    (ctx) => {
      const t = ctx.currentTime;
      this.playTone(ctx, 880, t, 0.3, 0.15);
      this.playTone(ctx, 1320, t + 0.15, 0.4, 0.15);
    },
    // 1: Modern pulse
    (ctx) => {
      const t = ctx.currentTime;
      [0, 0.3, 0.6].forEach((offset) => {
        this.playTone(ctx, 660, t + offset, 0.2, 0.18);
      });
    },
    // 2: Ascending melody
    (ctx) => {
      const t = ctx.currentTime;
      [523.25, 587.33, 659.25, 698.46, 783.99].forEach((f, i) =>
        this.playTone(ctx, f, t + i * 0.12, 0.2, 0.2)
      );
    },
    // 3: Retro beep
    (ctx) => {
      const t = ctx.currentTime;
      [0, 0.2, 0.4, 0.8, 1.0, 1.2].forEach((off) =>
        this.playTone(ctx, 800, t + off, 0.15, 0.2, "square")
      );
    },
    // 4: Piano jingle
    (ctx) => {
      const t = ctx.currentTime;
      const notes = [523.25, 659.25, 783.99, 1046.5, 783.99, 659.25];
      notes.forEach((f, i) => this.playTone(ctx, f, t + i * 0.1, 0.18, 0.22, "triangle"));
    },
    // 5: Marimba loop
    (ctx) => {
      const t = ctx.currentTime;
      const notes = [784, 1046.5, 880, 1174.7];
      notes.forEach((f, i) => this.playTone(ctx, f, t + i * 0.13, 0.3, 0.22, "triangle"));
    },
    // 6: Space chime
    (ctx) => {
      const t = ctx.currentTime;
      [440, 660, 880, 1100, 1320].forEach((f, i) => {
        this.playTone(ctx, f, t + i * 0.1, 0.25, 0.18);
        this.playTone(ctx, f * 2, t + i * 0.1, 0.12, 0.1);
      });
    },
    // 7: Fanfare
    (ctx) => {
      const t = ctx.currentTime;
      const notes = [523.25, 523.25, 523.25, 659.25, 523.25, 659.25, 783.99];
      notes.forEach((f, i) => this.playTone(ctx, f, t + i * 0.1, 0.18, 0.2));
    },
    // 8: Buzz ring
    (ctx) => {
      const t = ctx.currentTime;
      [0, 0.5, 1.0].forEach((off) => {
        this.playTone(ctx, 200, t + off, 0.4, 0.3, "sawtooth");
      });
    },
    // 9: Soft bell loop
    (ctx) => {
      const t = ctx.currentTime;
      [1046.5, 1318.5, 1568].forEach((f, i) =>
        this.playTone(ctx, f, t + i * 0.18, 0.5, 0.2)
      );
    },
  ];

  /* ── Public: Play notification ────────────────────────────────────── */

  playNotification() {
    try {
      const ctx = this.getCtx();
      if (!ctx) return;
      const key = typeof window !== "undefined" ? (localStorage.getItem("dolsyx_notif_sound") ?? "0") : "0";
      if (key === "custom") {
        const dataUrl = localStorage.getItem("dolsyx_custom_notif");
        if (dataUrl) {
          const audio = new Audio(dataUrl);
          audio.volume = 0.7;
          audio.play().catch(() => {});
          return;
        }
      }
      const idx = Math.min(Math.max(parseInt(key) || 0, 0), 9);
      this.notifGenerators[idx](ctx);
    } catch {}
  }

  /* ── Public: Preview a specific notification tone ──────────────────── */

  previewNotification(idx: number) {
    try {
      const ctx = this.getCtx();
      if (!ctx) return;
      const i = Math.min(Math.max(idx, 0), 9);
      this.notifGenerators[i](ctx);
    } catch {}
  }

  /* ── Public: Preview a specific ringtone ─────────────────────────── */

  previewRingtone(idx: number) {
    try {
      const ctx = this.getCtx();
      if (!ctx) return;
      const i = Math.min(Math.max(idx, 0), 9);
      this.ringGenerators[i](ctx);
    } catch {}
  }

  /* ── Public: Start ringtone loop ─────────────────────────────────── */

  playRingtone() {
    this.stopRingtone();
    try {
      const key = typeof window !== "undefined" ? (localStorage.getItem("dolsyx_call_sound") ?? "0") : "0";
      if (key === "custom") {
        const dataUrl = typeof window !== "undefined" ? localStorage.getItem("dolsyx_custom_ring") : null;
        if (dataUrl) {
          this.ringAudioEl = new Audio(dataUrl);
          this.ringAudioEl.loop = true;
          this.ringAudioEl.volume = 0.8;
          this.ringAudioEl.play().catch(() => {});
          return;
        }
      }
      const idx = Math.min(Math.max(parseInt(key) || 0, 0), 9);
      const ctx = this.getCtx();
      if (!ctx) return;
      const playOnce = () => {
        try { this.ringGenerators[idx](ctx); } catch {}
      };
      playOnce();
      this.ringIntervalId = setInterval(playOnce, 2500);
    } catch {}
  }

  /* ── Public: Stop ringtone ────────────────────────────────────────── */

  stopRingtone() {
    if (this.ringIntervalId !== null) {
      clearInterval(this.ringIntervalId);
      this.ringIntervalId = null;
    }
    if (this.ringAudioEl) {
      this.ringAudioEl.pause();
      this.ringAudioEl = null;
    }
  }

  /* ── Public: Tone names ───────────────────────────────────────────── */

  notifNames = [
    "Classic Ping",
    "WhatsApp Pop",
    "Soft Chime",
    "Rising Arpeggio",
    "Digital Blip",
    "Bell Tone",
    "Gentle Knock",
    "Space Ping",
    "Marimba",
    "Subtle Click",
  ];

  ringNames = [
    "Classic Ring",
    "Modern Pulse",
    "Ascending Melody",
    "Retro Beep",
    "Piano Jingle",
    "Marimba Loop",
    "Space Chime",
    "Fanfare",
    "Buzz Ring",
    "Soft Bells",
  ];
}

export const SoundEngine = new SoundEngineClass();
