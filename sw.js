// Gold Terminal Service Worker
const CACHE = 'gold-terminal-v1';

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(['/', '/index.html'])));
});

self.addEventListener('activate', e => {
  e.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', e => {
  // Cache-first pour les assets statiques
  if(e.request.url.includes('/api/')) return; // Pas de cache pour l'API
  e.respondWith(
    caches.match(e.request).then(r => r || fetch(e.request).then(res => {
      if(res && res.status === 200 && e.request.method === 'GET'){
        var rc = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, rc));
      }
      return res;
    }).catch(() => caches.match('/index.html')))
  );
});

// Reçoit un message depuis la page pour afficher une notif
self.addEventListener('message', e => {
  if(e.data && e.data.type === 'NOTIF'){
    self.registration.showNotification(e.data.title, {
      body: e.data.body,
      icon: '/icon.png',
      badge: '/icon.png',
      vibrate: [200, 100, 200],
      requireInteraction: true,
      tag: 'gold-signal',
      actions: [
        { action: 'open', title: '📊 Voir le signal' }
      ]
    });
  }
});

// Clic sur la notif → ouvre le site
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    clients.matchAll({type:'window'}).then(list => {
      for(var c of list) if(c.url.includes('gold-terminal') && 'focus' in c) return c.focus();
      if(clients.openWindow) return clients.openWindow('/');
    })
  );
});
