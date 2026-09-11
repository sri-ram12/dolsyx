/**
 * DOLSYX Premium Interactive Emoji Animation System
 * Centralized Animation Registry & Profile Configuration
 */

export type AnimationCategory =
  | 'heart'
  | 'laugh'
  | 'love-eyes'
  | 'angry'
  | 'cry'
  | 'celebrate'
  | 'fire'
  | 'thumbs'
  | 'clap'
  | 'animal'
  | 'food'
  | 'generic';

export type ParticleType =
  | 'hearts'
  | 'tears'
  | 'confetti'
  | 'flames'
  | 'sparks'
  | 'stars'
  | 'bubbles'
  | 'impact';

export type HapticType =
  | 'soft'
  | 'heartbeat'
  | 'light-rapid'
  | 'medium'
  | 'heavy'
  | 'celebration'
  | 'snap';

export type SoundType =
  | 'heartbeat'
  | 'pop'
  | 'laugh'
  | 'sparkle'
  | 'chime'
  | 'whoosh'
  | 'flame'
  | 'impact'
  | 'drip'
  | 'none';

export interface ParticleConfig {
  type: ParticleType;
  count: number;
  speed: number;
  spread: number;
  gravity: number;
  colors?: string[];
  maxScale?: number;
}

export interface EmojiAnimationProfile {
  id: string;
  category: AnimationCategory;
  animationClass: string;
  durationMs: number;
  scaleMax: number;
  particleConfig?: ParticleConfig;
  glow?: {
    color: string;
    spread: number;
  };
  hapticType?: HapticType;
  soundType?: SoundType;
  cooldownMs: number;
}

// Default Fallback Profile: Applied to any emoji without an emotional override
export const DEFAULT_FALLBACK_PROFILE: EmojiAnimationProfile = {
  id: 'generic-spring',
  category: 'generic',
  animationClass: 'animate-emoji-generic-spring',
  durationMs: 650,
  scaleMax: 1.2,
  particleConfig: {
    type: 'stars',
    count: 7,
    speed: 55,
    spread: 360,
    gravity: 0.1,
    colors: ['#FDE047', '#60A5FA', '#F472B6'],
    maxScale: 1.0,
  },
  glow: {
    color: 'rgba(255, 255, 255, 0.35)',
    spread: 12,
  },
  hapticType: 'soft',
  soundType: 'pop',
  cooldownMs: 300,
};

// Emotional Profiles Map
export const EMOJI_PROFILES: Record<string, EmojiAnimationProfile> = {
  // 1. HEART / LOVE FAMILY (❤️, 🧡, 💛, 💚, 💙, 💜, 🖤, 🤍, 💖, 💗, 💓, 💞, 💕, 💘, 💝)
  heart: {
    id: 'heart-pulse',
    category: 'heart',
    animationClass: 'animate-emoji-heart-beat',
    durationMs: 850,
    scaleMax: 1.32,
    particleConfig: {
      type: 'hearts',
      count: 10,
      speed: 65,
      spread: 130, // Upward floating fan
      gravity: -0.06, // Float upward
      colors: ['#EF4444', '#EC4899', '#F43F5E', '#FB7185'],
      maxScale: 1.15,
    },
    glow: {
      color: 'rgba(239, 68, 68, 0.55)',
      spread: 20,
    },
    hapticType: 'heartbeat',
    soundType: 'heartbeat',
    cooldownMs: 350,
  },

  // 2. LAUGH / JOY FAMILY (😂, 🤣, 😆, 😹)
  laugh: {
    id: 'laugh-shake',
    category: 'laugh',
    animationClass: 'animate-emoji-laugh-shake',
    durationMs: 950,
    scaleMax: 1.25,
    particleConfig: {
      type: 'tears',
      count: 8,
      speed: 80,
      spread: 220,
      gravity: 0.18,
      colors: ['#38BDF8', '#60A5FA', '#93C5FD'],
      maxScale: 0.95,
    },
    glow: {
      color: 'rgba(250, 204, 21, 0.4)',
      spread: 14,
    },
    hapticType: 'light-rapid',
    soundType: 'laugh',
    cooldownMs: 320,
  },

  // 3. LOVE-EYES / ADORATION (😍, 🥰, 😘, 😻)
  loveEyes: {
    id: 'love-bounce',
    category: 'love-eyes',
    animationClass: 'animate-emoji-love-bounce',
    durationMs: 900,
    scaleMax: 1.28,
    particleConfig: {
      type: 'hearts',
      count: 9,
      speed: 60,
      spread: 360,
      gravity: -0.04,
      colors: ['#F43F5E', '#FB7185', '#FDA4AF'],
      maxScale: 1.05,
    },
    glow: {
      color: 'rgba(244, 63, 94, 0.5)',
      spread: 18,
    },
    hapticType: 'soft',
    soundType: 'chime',
    cooldownMs: 350,
  },

  // 4. ANGER / RAGE (😡, 🤬, 👿, 💢)
  angry: {
    id: 'angry-shake',
    category: 'angry',
    animationClass: 'animate-emoji-angry-shake',
    durationMs: 700,
    scaleMax: 1.24,
    particleConfig: {
      type: 'sparks',
      count: 12,
      speed: 95,
      spread: 360,
      gravity: 0.12,
      colors: ['#EF4444', '#DC2626', '#B91C1C', '#EA580C'],
      maxScale: 1.1,
    },
    glow: {
      color: 'rgba(239, 68, 68, 0.7)',
      spread: 22,
    },
    hapticType: 'heavy',
    soundType: 'impact',
    cooldownMs: 300,
  },

  // 5. CRY / SADNESS (😭, 😢, 🥺, 😿)
  cry: {
    id: 'cry-slump',
    category: 'cry',
    animationClass: 'animate-emoji-cry-slump',
    durationMs: 1000,
    scaleMax: 1.18,
    particleConfig: {
      type: 'tears',
      count: 11,
      speed: 45,
      spread: 70, // Straight down arc
      gravity: 0.28, // Fast falling droplets
      colors: ['#38BDF8', '#0284C7', '#0EA5E9', '#7DD3FC'],
      maxScale: 1.0,
    },
    glow: {
      color: 'rgba(56, 189, 248, 0.45)',
      spread: 15,
    },
    hapticType: 'medium',
    soundType: 'drip',
    cooldownMs: 380,
  },

  // 6. CELEBRATION / PARTY (🎉, 🥳, 🎊, 🏆, 🍾, 🎆)
  celebrate: {
    id: 'celebrate-pop',
    category: 'celebrate',
    animationClass: 'animate-emoji-celebrate-pop',
    durationMs: 1100,
    scaleMax: 1.34,
    particleConfig: {
      type: 'confetti',
      count: 22,
      speed: 115,
      spread: 360,
      gravity: 0.14,
      colors: ['#F59E0B', '#EF4444', '#10B981', '#6366F1', '#EC4899', '#3B82F6'],
      maxScale: 1.3,
    },
    glow: {
      color: 'rgba(245, 158, 11, 0.6)',
      spread: 24,
    },
    hapticType: 'celebration',
    soundType: 'sparkle',
    cooldownMs: 400,
  },

  // 7. FIRE / ENERGY (🔥, ⚡, 💥, ✨, ⭐)
  fire: {
    id: 'fire-flare',
    category: 'fire',
    animationClass: 'animate-emoji-fire-flare',
    durationMs: 800,
    scaleMax: 1.3,
    particleConfig: {
      type: 'flames',
      count: 14,
      speed: 75,
      spread: 110,
      gravity: -0.15, // Ascend rapidly
      colors: ['#F97316', '#EF4444', '#FBBF24', '#DC2626'],
      maxScale: 1.2,
    },
    glow: {
      color: 'rgba(249, 115, 22, 0.65)',
      spread: 22,
    },
    hapticType: 'medium',
    soundType: 'flame',
    cooldownMs: 300,
  },

  // 8. THUMBS UP / APPROVAL (👍, 🤝, 👌, 🤙)
  thumbs: {
    id: 'thumbs-bounce',
    category: 'thumbs',
    animationClass: 'animate-emoji-generic-spring',
    durationMs: 600,
    scaleMax: 1.26,
    particleConfig: {
      type: 'impact',
      count: 8,
      speed: 70,
      spread: 360,
      gravity: 0.08,
      colors: ['#10B981', '#34D399', '#6EE7B7'],
      maxScale: 0.9,
    },
    glow: {
      color: 'rgba(16, 185, 129, 0.5)',
      spread: 14,
    },
    hapticType: 'snap',
    soundType: 'pop',
    cooldownMs: 250,
  },

  // 9. CLAPPING / APPLAUSE (👏, 🙌, 👐)
  clap: {
    id: 'clap-bounce',
    category: 'clap',
    animationClass: 'animate-emoji-clap-bounce',
    durationMs: 750,
    scaleMax: 1.25,
    particleConfig: {
      type: 'sparks',
      count: 10,
      speed: 80,
      spread: 360,
      gravity: 0.1,
      colors: ['#FBBF24', '#F59E0B', '#FCD34D'],
      maxScale: 1.0,
    },
    glow: {
      color: 'rgba(251, 191, 36, 0.5)',
      spread: 16,
    },
    hapticType: 'light-rapid',
    soundType: 'impact',
    cooldownMs: 280,
  },

  // 10. ANIMALS (🐶, 🐱, 🦊, 🐻, 🐼, 🐨, 🐯, 🦁, 🐰, 🐹)
  animal: {
    id: 'animal-bob',
    category: 'animal',
    animationClass: 'animate-emoji-generic-spring',
    durationMs: 700,
    scaleMax: 1.22,
    particleConfig: {
      type: 'stars',
      count: 8,
      speed: 50,
      spread: 360,
      gravity: 0.08,
      colors: ['#A78BFA', '#F472B6', '#FBBF24'],
      maxScale: 0.9,
    },
    glow: {
      color: 'rgba(167, 139, 250, 0.45)',
      spread: 14,
    },
    hapticType: 'soft',
    soundType: 'pop',
    cooldownMs: 300,
  },

  // 11. FOOD (🍕, 🍔, 🍩, 🍎, 🍟, 🌮, 🍣, 🍰, 🍦)
  food: {
    id: 'food-hop',
    category: 'food',
    animationClass: 'animate-emoji-generic-spring',
    durationMs: 650,
    scaleMax: 1.24,
    particleConfig: {
      type: 'sparks',
      count: 7,
      speed: 60,
      spread: 360,
      gravity: 0.12,
      colors: ['#FBBF24', '#F97316', '#EF4444'],
      maxScale: 0.85,
    },
    glow: {
      color: 'rgba(249, 115, 22, 0.4)',
      spread: 12,
    },
    hapticType: 'soft',
    soundType: 'pop',
    cooldownMs: 280,
  },
};

// Regex patterns mapping Unicode emojis to emotion profile keys
const EMOJI_MATCHERS: Array<{ regex: RegExp; profileKey: string }> = [
  // Hearts & love
  {
    regex: /(?:❤️|🧡|💛|💚|💙|💜|🖤|🤍|🤎|💖|💗|💓|💞|💕|💘|💝|💟|💌)/u,
    profileKey: 'heart',
  },
  // Laughing & joyous
  {
    regex: /😂|🤣|😹|😆|😸/,
    profileKey: 'laugh',
  },
  // Love-struck
  {
    regex: /😍|🥰|😘|😻|😚|😙/,
    profileKey: 'loveEyes',
  },
  // Anger & rage
  {
    regex: /😡|🤬|👿|💢|😠|😤|👺/,
    profileKey: 'angry',
  },
  // Cry & tearful sadness
  {
    regex: /😭|😢|🥺|😿|😥|😓/,
    profileKey: 'cry',
  },
  // Celebration & party
  {
    regex: /🎉|🥳|🎊|🏆|🍾|🎆|🎇|✨/,
    profileKey: 'celebrate',
  },
  // Fire & energy
  {
    regex: /🔥|⚡|💥|⭐|🌟|💫/,
    profileKey: 'fire',
  },
  // Thumbs & hand gesture
  {
    regex: /👍|🤝|👌|🤙|✌️|🤞|🤙/,
    profileKey: 'thumbs',
  },
  // Clapping
  {
    regex: /👏|🙌|👐/,
    profileKey: 'clap',
  },
  // Animals
  {
    regex: /🐶|🐱|🦊|🐻|🐼|🐨|🐯|🦁|🐰|🐹|🐭|🐵|🐶|🐺/,
    profileKey: 'animal',
  },
  // Food
  {
    regex: /🍕|🍔|🍩|🍎|🍟|🌮|🍣|🍰|🍦|🥞|🍿|🍉|🍓|🍫/,
    profileKey: 'food',
  },
];

// Extensibility store for custom or plugin-registered emoji profiles
const customEmojiRegistry = new Map<string, Partial<EmojiAnimationProfile>>();

/**
 * Checks if a specific emoji glyph has an enhanced, emotionally tailored profile.
 */
export function isAnimatedEmojiSupported(emoji: string): boolean {
  if (!emoji) return false;
  const clean = emoji.trim();
  if (customEmojiRegistry.has(clean)) return true;
  return EMOJI_MATCHERS.some((m) => m.regex.test(clean));
}

/**
 * Returns the exact EmojiAnimationProfile for a given emoji string.
 * Always returns a valid profile (falling back to DEFAULT_FALLBACK_PROFILE if unmapped).
 */
export function getEmojiAnimationProfile(emoji: string): EmojiAnimationProfile {
  if (!emoji) return DEFAULT_FALLBACK_PROFILE;
  const clean = emoji.trim();

  // Check custom runtime registration first
  if (customEmojiRegistry.has(clean)) {
    return {
      ...DEFAULT_FALLBACK_PROFILE,
      ...customEmojiRegistry.get(clean),
    };
  }

  // Match against standard emotional categories
  for (const matcher of EMOJI_MATCHERS) {
    if (matcher.regex.test(clean)) {
      const profile = EMOJI_PROFILES[matcher.profileKey];
      if (profile) return profile;
    }
  }

  return DEFAULT_FALLBACK_PROFILE;
}

/**
 * Extensibility API: Register a brand-new or modified emoji profile at runtime
 * without having to edit the core animation engine.
 */
export function registerCustomEmojiProfile(
  emoji: string,
  profile: Partial<EmojiAnimationProfile>
): void {
  if (!emoji) return;
  customEmojiRegistry.set(emoji.trim(), profile);
}

// Known high-definition animated WebP assets
const ANIMATED_EMOJI_URL_MAP: Record<string, string> = {
  // Hearts & Love
  '❤️': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2764_fe0f/512.webp',
  '🧡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f9e1/512.webp',
  '💛': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49b/512.webp',
  '💚': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49a/512.webp',
  '💙': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f499/512.webp',
  '💜': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49c/512.webp',
  '🖤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f5a4/512.webp',
  '🤍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f90d/512.webp',
  '🤎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f90e/512.webp',
  '💔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f494/512.webp',
  '💖': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f496/512.webp',
  '💗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f497/512.webp',
  '💓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f493/512.webp',
  '💞': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49e/512.webp',
  '💕': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f495/512.webp',
  '💘': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f498/512.webp',
  '💝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49d/512.webp',

  // Laughing / Joy
  '😂': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/512.webp',
  '🤣': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f923/512.webp',
  '😆': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f606/512.webp',
  '😅': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f605/512.webp',
  '😄': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f604/512.webp',
  '😃': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f603/512.webp',
  '😀': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f600/512.webp',
  '😁': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f601/512.webp',

  // Love-Struck / Affection
  '😍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60d/512.webp',
  '🥰': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f970/512.webp',
  '😘': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f618/512.webp',
  '😗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f617/512.webp',
  '😙': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f619/512.webp',
  '😚': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61a/512.webp',

  // Anger / Rage
  '😡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f621/512.webp',
  '🤬': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92c/512.webp',
  '😠': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f620/512.webp',
  '😤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f624/512.webp',

  // Cry / Sadness
  '😭': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62d/512.webp',
  '😢': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f622/512.webp',
  '🥺': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f97a/512.webp',
  '😥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f625/512.webp',
  '😓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f613/512.webp',

  // Celebration / Party
  '🎉': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f389/512.webp',
  '🥳': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f973/512.webp',
  '🎊': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f38a/512.webp',
  '🏆': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f3c6/512.webp',

  // Fire / Energy
  '🔥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f525/512.webp',
  '⚡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/26a1/512.webp',
  '💥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a5/512.webp',
  '✨': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2728/512.webp',
  '⭐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2b50/512.webp',
  '🌟': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f31f/512.webp',
  '💯': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4af/512.webp',

  // Hands / Gestures
  '👍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44d/512.webp',
  '👎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44e/512.webp',
  '👏': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44f/512.webp',
  '🙌': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f64c/512.webp',
  '🙏': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f64f/512.webp',
  '🤝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f91d/512.webp',
  '👌': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44c/512.webp',
  '✌️': 'https://fonts.gstatic.com/s/e/notoemoji/latest/270c_fe0f/512.webp',

  // Expressive Faces from WhatsApp/demovideo
  '🥵': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f975/512.webp',
  '🥶': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f976/512.webp',
  '😳': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f633/512.webp',
  '🤢': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f922/512.webp',
  '🤮': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92e/512.webp',
  '😫': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62b/512.webp',
  '😩': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f629/512.webp',
  '🤤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f924/512.webp',
  '🤐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f910/512.webp',
  '😮‍💨': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62e_200d_1f4a8/512.webp',
  '😴': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f634/512.webp',
  '🥱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f971/512.webp',
  '🤯': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92f/512.webp',
  '😱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f631/512.webp',
  '🤔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f914/512.webp',
  '🫡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1fae1/512.webp',
  '🫠': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1fae0/512.webp',
  '🤫': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92b/512.webp',
  '🤭': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92d/512.webp',
  '🙄': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f644/512.webp',
  '😎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60e/512.webp',
  '🤓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f913/512.webp',
  '🧐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f9d0/512.webp',
  '😉': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f609/512.webp',
  '😊': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60a/512.webp',
  '😇': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f607/512.webp',
  '🙂': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f642/512.webp',
  '🙃': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f643/512.webp',
  '😋': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60b/512.webp',
  '😜': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61c/512.webp',
  '🤪': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92a/512.webp',
  '😝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61d/512.webp',
  '😛': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61b/512.webp',
  '🤑': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f911/512.webp',
  '🤗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f917/512.webp',
  '🤡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f921/512.webp',
  '💩': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a9/512.webp',
  '👻': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f47b/512.webp',
  '💀': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f480/512.webp',
  '👽': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f47d/512.webp',
  '🤖': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.webp',
  '🐶': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f436/512.webp',
  '🐱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f431/512.webp',
  '🍕': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f355/512.webp',
  '🍔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f354/512.webp',
};

/**
 * Returns the high-definition animated WebP URL for an emoji if available
 */
export function getAnimatedEmojiUrl(emoji: string): string | null {
  if (!emoji) return null;
  const clean = emoji.trim();
  if (ANIMATED_EMOJI_URL_MAP[clean]) {
    return ANIMATED_EMOJI_URL_MAP[clean];
  }

  // Fallback to codepoint calculation
  const codePoints: string[] = [];
  for (const char of clean) {
    const cp = char.codePointAt(0);
    if (cp && cp !== 0xfe0f) {
      codePoints.push(cp.toString(16));
    }
  }

  if (codePoints.length > 0) {
    const hex = clean === '❤️' ? '2764_fe0f' : codePoints.join('_');
    return `https://fonts.gstatic.com/s/e/notoemoji/latest/${hex}/512.webp`;
  }

  return null;
}
