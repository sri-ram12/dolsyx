/**
 * Returns a default avatar URL for a user who has not uploaded a profile picture.
 * Uses inline SVG data URIs so avatars work on ALL devices without file serving.
 */

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
    hash |= 0;
  }
  return Math.abs(hash);
}

// Inline SVG male silhouette (teal theme)
const MALE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><defs><linearGradient id="bg1" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%231a2744"/><stop offset="100%" style="stop-color:%230d1a3a"/></linearGradient><linearGradient id="bd1" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%232a9d8f"/><stop offset="100%" style="stop-color:%231a7a6e"/></linearGradient><linearGradient id="sk1" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%23e8c5a0"/><stop offset="100%" style="stop-color:%23d4a878"/></linearGradient></defs><path d="M15 200 C15 145 52 122 100 122 C148 122 185 145 185 200Z" fill="url(%23bd1)"/><rect x="87" y="105" width="26" height="22" rx="6" fill="url(%23sk1)"/><ellipse cx="100" cy="82" rx="36" ry="40" fill="url(%23sk1)"/><path d="M64 72 C64 42 80 30 100 30 C120 30 136 42 136 72 C132 60 68 60 64 72Z" fill="%232d1b10"/><ellipse cx="87" cy="80" rx="5" ry="5.5" fill="%23fff"/><ellipse cx="113" cy="80" rx="5" ry="5.5" fill="%23fff"/><circle cx="88" cy="81" r="3" fill="%232d1b10"/><circle cx="114" cy="81" r="3" fill="%232d1b10"/><path d="M90 97 Q100 104 110 97" stroke="%23c49570" stroke-width="2" fill="none" stroke-linecap="round"/></svg>`;

// Inline SVG female silhouette (purple theme)
const FEMALE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><defs><linearGradient id="bg2" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%232a1a3a"/><stop offset="100%" style="stop-color:%231a0d2a"/></linearGradient><linearGradient id="bd2" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%237c3aed"/><stop offset="100%" style="stop-color:%235b21b6"/></linearGradient><linearGradient id="sk2" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%23f0d0b0"/><stop offset="100%" style="stop-color:%23dbb88a"/></linearGradient><linearGradient id="hr2" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:%234a2c0a"/><stop offset="100%" style="stop-color:%232d1b08"/></linearGradient></defs><path d="M18 200 C18 148 55 126 100 126 C145 126 182 148 182 200Z" fill="url(%23bd2)"/><path d="M86 126 L100 148 L114 126Z" fill="%236d28d9"/><rect x="89" y="108" width="22" height="22" rx="5" fill="url(%23sk2)"/><ellipse cx="100" cy="74" rx="40" ry="46" fill="url(%23hr2)"/><path d="M60 74 C52 90 50 115 58 132 C62 118 62 95 68 78Z" fill="url(%23hr2)"/><path d="M140 74 C148 90 150 115 142 132 C138 118 138 95 132 78Z" fill="url(%23hr2)"/><ellipse cx="100" cy="84" rx="32" ry="36" fill="url(%23sk2)"/><path d="M68 72 C66 48 82 34 100 34 C118 34 134 48 132 72 C128 56 72 56 68 72Z" fill="url(%23hr2)"/><ellipse cx="88" cy="82" rx="5" ry="5.5" fill="%23fff"/><ellipse cx="112" cy="82" rx="5" ry="5.5" fill="%23fff"/><circle cx="89" cy="83" r="3" fill="%232d1b10"/><circle cx="113" cy="83" r="3" fill="%232d1b10"/><path d="M83 78 L82 74 M86 77 L85 73 M89 77 L89 73" stroke="%232d1b10" stroke-width="1.2" stroke-linecap="round"/><path d="M107 78 L106 74 M110 77 L109 73 M113 77 L113 73" stroke="%232d1b10" stroke-width="1.2" stroke-linecap="round"/><path d="M91 99 Q100 106 109 99" stroke="%23c49070" stroke-width="2" fill="none" stroke-linecap="round"/></svg>`;

const MALE_DATA_URI = `data:image/svg+xml,${MALE_SVG}`;
const FEMALE_DATA_URI = `data:image/svg+xml,${FEMALE_SVG}`;

export function resolveMediaUrl(url: string | null | undefined): string {
  if (!url) return "";
  
  // Extract path if it contains /uploads/
  const uploadsIndex = url.indexOf("/uploads/");
  if (uploadsIndex !== -1) {
    const relativePath = url.substring(uploadsIndex);
    if (typeof window !== "undefined") {
      return `${window.location.origin}${relativePath}`;
    }
    return relativePath;
  }
  
  return url;
}

/**
 * Returns either a male or female default avatar (as data URI)
 * deterministically based on the username.
 */
export function getDefaultAvatar(name: string): string {
  const clean = (name || "?").trim();
  const isFemale = hashString(clean) % 2 === 1;
  return isFemale ? FEMALE_DATA_URI : MALE_DATA_URI;
}

/**
 * Returns the final avatar URL to display. If the provided avatar URL is empty
 * or points to a default DiceBear template, returns the deterministic default silhouette.
 */
export function getAvatarUrl(avatarUrl: string | null | undefined, name: string): string {
  if (!avatarUrl || avatarUrl.includes("dicebear.com")) {
    return getDefaultAvatar(name);
  }
  
  return resolveMediaUrl(avatarUrl);
}
