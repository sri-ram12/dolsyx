import admin from 'firebase-admin';

// Initialize Firebase Admin SDK conditionally
// To make it work in production, you should provide the serviceAccountKey.json
export const initFirebase = () => {
  try {
    if (!admin.apps.length) {
      // For now, if no credentials are provided, we don't initialize to prevent crashes
      // When ready, you can uncomment this and provide credentials:
      /*
      const serviceAccount = require('../../serviceAccountKey.json');
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      console.log('Firebase Admin initialized.');
      */
      console.log('Firebase Admin NOT initialized (requires serviceAccountKey.json). Push notifications are mocked.');
    }
  } catch (error) {
    console.error('Firebase Admin initialization error:', error);
  }
};

export const sendPushNotification = async (fcmToken: string, title: string, body: string, data?: any) => {
  if (!fcmToken) return;

  if (admin.apps.length > 0) {
    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: data || {},
      });
      console.log(`Push notification sent to ${fcmToken}`);
    } catch (error) {
      console.error('Failed to send push notification:', error);
    }
  } else {
    // Mock push notification when Firebase is not configured
    console.log(`[MOCK PUSH] To: ${fcmToken} | Title: ${title} | Body: ${body}`);
  }
};
