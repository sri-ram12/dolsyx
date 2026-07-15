import { prisma } from "./config/db.js";
async function main() {
    try {
        const conversations = await prisma.conversation.findMany({
            take: 5,
        });
        console.log("Conversations in DB:", conversations);
        const firstConv = conversations[0];
        if (firstConv) {
            const targetId = firstConv.id;
            console.log(`Attempting to delete conversation: ${targetId}`);
            // Start a transaction and try deleting it
            await prisma.$transaction(async (tx) => {
                // Find participants
                const participants = await tx.participant.findMany({
                    where: { conversationId: targetId },
                });
                console.log("Participants to delete:", participants);
                // Find messages
                const messages = await tx.message.findMany({
                    where: { conversationId: targetId },
                });
                console.log("Messages to delete count:", messages.length);
                // Delete conversation
                const deleted = await tx.conversation.delete({
                    where: { id: targetId },
                });
                console.log("Deleted successfully in transaction:", deleted);
                // Rollback so we don't actually destroy data during debug
                throw new Error("ROLLBACK");
            });
        }
        else {
            console.log("No conversations found to delete.");
        }
    }
    catch (err) {
        if (err.message === "ROLLBACK") {
            console.log("Database transaction rolled back successfully. Delete works!");
        }
        else {
            console.error("Prisma Delete Error:", err);
        }
    }
    finally {
        await prisma.$disconnect();
    }
}
main();
//# sourceMappingURL=test-delete-db.js.map