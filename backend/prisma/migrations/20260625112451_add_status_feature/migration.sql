-- CreateTable
CREATE TABLE "Status" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "mediaUrl" TEXT,
    "mediaType" TEXT NOT NULL DEFAULT 'TEXT',
    "caption" TEXT,
    "bgColor" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" DATETIME NOT NULL,
    CONSTRAINT "Status_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "StatusView" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "statusId" TEXT NOT NULL,
    "viewerId" TEXT NOT NULL,
    "viewedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "StatusView_statusId_fkey" FOREIGN KEY ("statusId") REFERENCES "Status" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "StatusView_viewerId_fkey" FOREIGN KEY ("viewerId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "StatusView_statusId_viewerId_key" ON "StatusView"("statusId", "viewerId");
