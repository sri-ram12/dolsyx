import "dotenv/config";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function applyIndexes() {
  console.log("Applying optimized database indexes...");
  const indexes = [
    `CREATE INDEX IF NOT EXISTS "idx_message_conv_sender" ON "Message" ("conversationId", "senderId")`,
    `CREATE INDEX IF NOT EXISTS "idx_message_parent_msg" ON "Message" ("parentMessageId")`,
    `CREATE INDEX IF NOT EXISTS "idx_conversation_updated_at" ON "Conversation" ("updatedAt" DESC)`,
    `CREATE INDEX IF NOT EXISTS "idx_user_is_online" ON "User" ("isOnline")`,
    `CREATE INDEX IF NOT EXISTS "idx_user_last_seen" ON "User" ("lastSeen" DESC)`,
  ];

  for (const sql of indexes) {
    try {
      const start = Date.now();
      await prisma.$executeRawUnsafe(sql);
      console.log(`✅ [${Date.now() - start}ms] Executed: ${sql}`);
    } catch (err) {
      console.error(`❌ Failed: ${sql}`, err.message);
    }
  }

  await prisma.$disconnect();
  console.log("Index creation complete.");
}

applyIndexes().catch((err) => {
  console.error("Index script error:", err);
  process.exit(1);
});
