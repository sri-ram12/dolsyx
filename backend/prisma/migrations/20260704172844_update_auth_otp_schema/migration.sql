/*
  Warnings:

  - You are about to drop the column `phoneNumber` on the `Otp` table. All the data in the column will be lost.
  - Added the required column `email` to the `Otp` table without a default value. This is not possible if the table is not empty.

*/
-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Otp" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "requestCount" INTEGER NOT NULL DEFAULT 0,
    "lastRequestedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "new_Otp" ("code", "createdAt", "expiresAt", "id") SELECT "code", "createdAt", "expiresAt", "id" FROM "Otp";
DROP TABLE "Otp";
ALTER TABLE "new_Otp" RENAME TO "Otp";
CREATE UNIQUE INDEX "Otp_email_key" ON "Otp"("email");
CREATE TABLE "new_User" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "username" TEXT NOT NULL,
    "email" TEXT,
    "phoneNumber" TEXT,
    "password" TEXT,
    "avatarUrl" TEXT,
    "coverUrl" TEXT,
    "bio" TEXT,
    "statusMessage" TEXT,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "streakCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "lastSeen" DATETIME DEFAULT CURRENT_TIMESTAMP,
    "lastLogin" DATETIME DEFAULT CURRENT_TIMESTAMP,
    "emailVerified" BOOLEAN NOT NULL DEFAULT false,
    "isOnline" BOOLEAN NOT NULL DEFAULT false
);
INSERT INTO "new_User" ("avatarUrl", "bio", "coverUrl", "createdAt", "email", "id", "lastSeen", "password", "phoneNumber", "statusMessage", "streakCount", "updatedAt", "username", "xp") SELECT "avatarUrl", "bio", "coverUrl", "createdAt", "email", "id", "lastSeen", "password", "phoneNumber", "statusMessage", "streakCount", "updatedAt", "username", "xp" FROM "User";
DROP TABLE "User";
ALTER TABLE "new_User" RENAME TO "User";
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");
CREATE UNIQUE INDEX "User_phoneNumber_key" ON "User"("phoneNumber");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
