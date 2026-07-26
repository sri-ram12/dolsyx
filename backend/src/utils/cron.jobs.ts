import cron from 'node-cron';
import { prisma } from '../config/db.js';

export const initCronJobs = () => {
  // Run every hour at minute 0
  cron.schedule('0 * * * *', async () => {
    console.log('[CRON] Running disappearing messages cleanup job...');
    try {
      // Fetch users who have disappearing messages enabled
      const users = await prisma.user.findMany({
        where: {
          disappearingTimer: {
            not: 'OFF'
          }
        },
        select: { id: true, disappearingTimer: true }
      });

      let deletedCount = 0;

      for (const user of users) {
        let thresholdHours = 0;
        if (user.disappearingTimer === '24H') thresholdHours = 24;
        else if (user.disappearingTimer === '7D') thresholdHours = 24 * 7;
        else if (user.disappearingTimer === '90D') thresholdHours = 24 * 90;

        if (thresholdHours === 0) continue;

        const thresholdDate = new Date(Date.now() - (thresholdHours * 60 * 60 * 1000));

        // Delete messages sent by this user older than the threshold
        const result = await prisma.message.deleteMany({
          where: {
            senderId: user.id,
            createdAt: {
              lt: thresholdDate
            }
          }
        });
        
        deletedCount += result.count;
      }

      console.log(`[CRON] Disappearing messages cleanup complete. Deleted ${deletedCount} messages.`);
    } catch (error) {
      console.error('[CRON] Error during disappearing messages cleanup:', error);
    }
  });
  
  console.log('Cron jobs initialized.');
};
