import { prisma } from "../config/db.js";

// Check if requester is blocked by target, or target is blocked by requester
export const getBlockStatus = async (userAId: string, userBId: string) => {
  const blocks = await prisma.userBlock.findMany({
    where: {
      OR: [
        { blockerId: userAId, blockedId: userBId },
        { blockerId: userBId, blockedId: userAId },
      ],
    },
  });

  return {
    aBlocksB: blocks.some(b => b.blockerId === userAId && b.blockedId === userBId),
    bBlocksA: blocks.some(b => b.blockerId === userBId && b.blockedId === userAId),
    isAnyBlocked: blocks.length > 0,
  };
};

// Check if B is in A's contacts list
export const isContactOf = async (ownerId: string, contactId: string): Promise<boolean> => {
  const contact = await prisma.contact.findUnique({
    where: { userId_contactId: { userId: ownerId, contactId } },
  });
  return !!contact;
};

// Helper: Check if a user is in an exception list
const inExceptionList = (listJson: string | string[], userId: string): boolean => {
  try {
    if (Array.isArray(listJson)) {
      return listJson.includes(userId);
    }
    const list = JSON.parse(listJson);
    return Array.isArray(list) && list.includes(userId);
  } catch (e) {
    return false;
  }
};

// Evaluates general privacy setting for a field (lastSeen, avatar, about)
const evaluatePrivacySetting = async (
  requesterId: string,
  target: any,
  privacySetting: string,
  exceptListJson: string
): Promise<boolean> => {
  if (requesterId === target.id) return true;

  const blocks = await getBlockStatus(requesterId, target.id);
  if (blocks.isAnyBlocked) return false;

  switch (privacySetting) {
    case "EVERYONE":
      return true;

    case "MY_CONTACTS":
      return await isContactOf(target.id, requesterId);

    case "EXCEPT":
      const inContacts = await isContactOf(target.id, requesterId);
      if (!inContacts) return false;
      return !inExceptionList(exceptListJson, requesterId);

    case "NOBODY":
      return false;

    default:
      return true;
  }
};

// 1. Can requester view target's avatar?
export const canViewAvatar = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;
  return await evaluatePrivacySetting(
    requesterId,
    target,
    target.avatarPrivacy,
    target.avatarPrivacyExceptList
  );
};

// 2. Can requester view target's last seen?
export const canViewLastSeen = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;
  return await evaluatePrivacySetting(
    requesterId,
    target,
    target.lastSeenPrivacy,
    target.lastSeenPrivacyExceptList
  );
};

// 3. Can requester view target's online status?
export const canViewOnlineStatus = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;

  if (requesterId === target.id) return true;

  if (target.onlinePrivacy === "NOBODY") return false;
  if (target.onlinePrivacy === "SAME_AS_LAST_SEEN") {
    return await canViewLastSeen(requesterId, targetUserId);
  }
  if (target.onlinePrivacy === "MY_CONTACTS") {
    return await isContactOf(target.id, requesterId);
  }
  if (target.onlinePrivacy === "EXCEPT") {
    const inContacts = await isContactOf(target.id, requesterId);
    if (!inContacts) return false;
    return !inExceptionList(target.lastSeenPrivacyExceptList, requesterId);
  }
  // EVERYONE
  return true;
};

// 4. Can requester view target's about message?
export const canViewAbout = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;
  return await evaluatePrivacySetting(
    requesterId,
    target,
    target.aboutPrivacy,
    target.aboutPrivacyExceptList
  );
};

// 5. Can requester view target's status updates?
export const canViewStatus = async (
  requesterId: string,
  targetUserId: string,
  statusSnapshot?: { privacyType?: string | null; privacyList?: string | string[] | null }
): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;

  if (requesterId === targetUserId) return true;

  const blocks = await getBlockStatus(requesterId, targetUserId);
  if (blocks.isAnyBlocked) return false;

  // Status Privacy visibility
  const inContacts = await isContactOf(targetUserId, requesterId);
  if (!inContacts) return false;

  // Use status creation snapshot if provided, otherwise target user's current settings
  const privacyType = statusSnapshot?.privacyType || target.statusPrivacyType;
  const privacyList = statusSnapshot?.privacyList ?? target.statusPrivacyList;

  switch (privacyType) {
    case "MY_CONTACTS":
      return true;

    case "EXCEPT":
      return !inExceptionList(privacyList, requesterId);

    case "ONLY_SHARE":
      return inExceptionList(privacyList, requesterId);

    default:
      return false;
  }
};

// 6. Can read receipts be sent/exchanged?
export const canExchangeReadReceipts = async (userAId: string, userBId: string): Promise<boolean> => {
  // If either has readReceipts = false, then no seen ticks are sent or displayed
  const users = await prisma.user.findMany({
    where: { id: { in: [userAId, userBId] } },
    select: { readReceipts: true },
  });
  return users.every(u => u.readReceipts === true);
};

export const canViewProfilePhoto = canViewAvatar;
export const canViewOnline = canViewOnlineStatus;
