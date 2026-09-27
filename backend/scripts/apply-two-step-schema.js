import "dotenv/config";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function applyTwoStepColumns() {
  console.log("Applying Two-Step Verification database columns...");
  const queries = [
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepEnabled" BOOLEAN NOT NULL DEFAULT false`,
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepPin" TEXT`,
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepFailedAttempts" INTEGER NOT NULL DEFAULT 0`,
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepLockoutUntil" TIMESTAMP(3)`,
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepResetRequestedAt" TIMESTAMP(3)`,
    `ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoStepResetCooldownDays" INTEGER NOT NULL DEFAULT 7`,
  ];

  for (const sql of queries) {
    try {
      const start = Date.now();
      await prisma.$executeRawUnsafe(sql);
      console.log(`✅ [${Date.now() - start}ms] Executed: ${sql}`);
    } catch (err) {
      console.error(`❌ Failed: ${sql}`, err.message);
    }
  }

  await prisma.$disconnect();
  console.log("Two-Step Verification columns applied successfully.");
}

applyTwoStepColumns().catch((err) => {
  console.error("Migration script error:", err);
  process.exit(1);
});
