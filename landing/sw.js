// Retires the service worker of the web app that used to live at the site
// root (it now lives under /app/ with its own worker). Browsers that still
// have the old one fetch this file on their next visit: it deletes the old
// caches, unregisters itself and reloads open pages, which then get the
// landing page or, for home-screen installs, the app at /app/.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('siddur-')) await caches.delete(key);
    }
    await self.registration.unregister();
    for (const client of await self.clients.matchAll({type: 'window'})) {
      client.navigate(client.url);
    }
  })());
});
