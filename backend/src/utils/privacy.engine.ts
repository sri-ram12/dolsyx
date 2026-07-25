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
const inExceptionList = (listJson: string, userId: string): boolean => {
  try {
    const list = JSON.parse(listJson);
    return Array.isArray(list) && list.includes(userId);
  } catch (e) {
    return false;
  }
};

// Evaluates general privacy setting for a field (lastSeen, avatar, about)
const evaluatePrivacySetting = async (
  requesterId: string,
  targetUser: any, // User object containing privacy settings
  privacyType: string, // targetUser's setting value (e.g. EVERYONE, MY_CONTACTS, EXCEPT, NOBODY)
  exceptListJson: string // JSON array of user IDs
): Promise<boolean> => {
  // If same user, always allow
  if (requesterId === targetUser.id) return true;

  // 1. Check if either user has blocked the other
  const blocks = await getBlockStatus(requesterId, targetUser.id);
  if (blocks.isAnyBlocked) return false;

  // 2. Evaluate visibility options
  switch (privacyType) {
    case "EVERYONE":
    case "PUBLIC":
      return true;

    case "MY_CONTACTS":
    case "CONTACTS":
      // Requester must be in target's contacts list
      return await isContactOf(targetUser.id, requesterId);

    case "EXCEPT":
    case "MY_CONTACTS_EXCEPT":
      // Requester must be in target's contacts AND NOT in exception list
      const inContacts = await isContactOf(targetUser.id, requesterId);
      if (!inContacts) return false;
      return !inExceptionList(exceptListJson, requesterId);

    case "NOBODY":
    default:
      return false;
  }
};

// 1. Can requester view target's last seen?
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

// 2. Can requester view target's online status?
export const canViewOnline = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;

  // B blocks A or A blocks B
  const blocks = await getBlockStatus(requesterId, targetUserId);
  if (blocks.isAnyBlocked) return false;

  if (target.onlinePrivacy === "EVERYONE") return true;

  if (target.onlinePrivacy === "SAME_AS_LAST_SEEN") {
    return await canViewLastSeen(requesterId, targetUserId);
  }

  // NOBODY
  return false;
};

// 3. Can requester view target's profile photo?
export const canViewProfilePhoto = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;
  return await evaluatePrivacySetting(
    requesterId,
    target,
    target.avatarPrivacy,
    target.avatarPrivacyExceptList
  );
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
export const canViewStatus = async (requesterId: string, targetUserId: string): Promise<boolean> => {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target) return false;

  if (requesterId === targetUserId) return true;

  const blocks = await getBlockStatus(requesterId, targetUserId);
  if (blocks.isAnyBlocked) return false;

  // Status Privacy visibility
  const inContacts = await isContactOf(targetUserId, requesterId);
  if (!inContacts) return false;

  switch (target.statusPrivacyType) {
    case "MY_CONTACTS":
      return true;

    case "EXCEPT":
      return !inExceptionList(target.statusPrivacyList, requesterId);

    case "ONLY_SHARE":
      return inExceptionList(target.statusPrivacyList, requesterId);

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
