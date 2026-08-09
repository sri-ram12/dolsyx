import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

// Initialize Firebase Admin SDK
export const initFirebase = () => {
  try {
    if (!getApps().length) {
      // Option 1: Use FIREBASE_SERVICE_ACCOUNT env variable (recommended for deployment)
      const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
      
      if (serviceAccountJson) {
        const serviceAccount = JSON.parse(serviceAccountJson);
        initializeApp({
          credential: cert(serviceAccount),
        });
        console.log('✅ Firebase Admin initialized from environment variable.');
      } else {
        // Option 2: Try loading from file
        try {
          // Dynamic import for local development
          const fs = require('fs');
          const path = require('path');
          const keyPath = path.join(process.cwd(), 'serviceAccountKey.json');
          
          if (fs.existsSync(keyPath)) {
            const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf-8'));
            initializeApp({
              credential: cert(serviceAccount),
            });
            console.log('✅ Firebase Admin initialized from serviceAccountKey.json.');
          } else {
            console.log('⚠️ Firebase Admin NOT initialized. Push notifications disabled.');
            console.log('   → Set FIREBASE_SERVICE_ACCOUNT env var OR place serviceAccountKey.json in backend/');
          }
        } catch {
          console.log('⚠️ Firebase Admin NOT initialized. Push notifications disabled.');
        }
      }
    }
  } catch (error) {
    console.error('Firebase Admin initialization error:', error);
  }
};

export const sendPushNotification = async (fcmToken: string, title: string, body: string, data?: any) => {
  if (!fcmToken) return;

  if (getApps().length > 0) {
    try {
      const isCall = data?.type === "CALL" || data?.callType != null;
      const channelId = isCall ? "call_channel_v3" : "dolsyx_messages_v2";
      const sound = isCall ? "dolsyx_ringtone" : "dolsyx_message";

      const messagePayload: any = {
        token: fcmToken,
        data: data ? Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ) : {},
        android: {
          priority: 'high',
          ttl: 0,
          notification: {
            channelId,
            sound,
            priority: 'max',
            visibility: 'public',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              contentAvailable: true,
              sound: isCall ? sound : 'default',
            },
          },
        },
      };

      if (!isCall) {
        messagePayload.notification = { title, body };
      }

      await getMessaging().send(messagePayload);
      console.log(`📲 Push notification sent successfully (${isCall ? 'CALL' : 'MESSAGE'})`);
    } catch (error: any) {
      if (error?.code === 'messaging/registration-token-not-registered') {
        console.log(`🗑️ Stale FCM token, should be cleaned up`);
      } else {
        console.error('Failed to send push notification:', error);
      }
    }
  } else {
    console.log(`[MOCK PUSH] To token: ${fcmToken.substring(0, 20)}... | ${title}: ${body}`);
  }
};
