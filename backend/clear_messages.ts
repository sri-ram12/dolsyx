import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function clearMessages() {
  await prisma.message.deleteMany({});
  console.log("Legacy messages cleared.");
  await prisma.$disconnect();
}

clearMessages().catch(console.error);
