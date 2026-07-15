/**
 * Returns a default avatar URL for a user who has not uploaded a profile picture.
 * Alternates between male and female silhouette based on a hash of the username,
 * so each user always gets the same consistent avatar.
 */

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
    hash |= 0;
  }
  return Math.abs(hash);
}

/**
 * Returns either "/default-male.svg" or "/default-female.svg"
 * deterministically based on the username.
 *
 * @param name - The username or display name.
 */
export function getDefaultAvatar(name: string): string {
  const clean = (name || "?").trim();
  // Even hash → male, odd hash → female
  const isFemale = hashString(clean) % 2 === 1;
  return isFemale ? "/default-female.svg" : "/default-male.svg";
}

/**
 * Returns the final avatar URL to display. If the provided avatar URL is empty
 * or points to a default DiceBear template, returns the deterministic default silhouette.
 */
export function getAvatarUrl(avatarUrl: string | null | undefined, name: string): string {
  if (!avatarUrl || avatarUrl.includes("dicebear.com")) {
    return getDefaultAvatar(name);
  }
  return avatarUrl;
}
