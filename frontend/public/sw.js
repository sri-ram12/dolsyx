// DOLSYX Service Worker - Push Notifications
const CACHE_NAME = 'dolsyx-cache-v1';
const STATIC_ASSETS = ['/', '/manifest.json', '/dolsyx-logo.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch (e) { data = { title: 'DOLSYX', body: event.data ? event.data.text() : 'New message' }; }
  const title = data.title || 'DOLSYX';
  const options = {
    body: data.body || 'You have a new message',
    icon: '/dolsyx-logo.png',
    badge: '/dolsyx-logo.png',
    tag: data.tag || 'dolsyx-message',
    renotify: true,
    data: { url: data.url || '/chat' },
    actions: [{ action: 'open', title: 'Open' }, { action: 'dismiss', title: 'Dismiss' }],
    vibrate: [200, 100, 200],
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (event.action === 'dismiss') return;
  const targetUrl = (event.notification.data && event.notification.data.url) || '/chat';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
