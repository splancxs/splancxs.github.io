// Service worker: prima la rete (contenuti sempre aggiornati), cache come riserva offline.
const CACHE = 'recomp-v29';
const ASSETS = [
  './', './index.html', './assets/css/style.css?v=30', './assets/js/allenamento.js?v=30', './assets/js/app.js?v=30', './assets/js/data.js?v=30', './assets/js/sync.js?v=30', './assets/js/firebase-config.js',
  './manifest.webmanifest', './assets/icons/favicon.svg', './assets/icons/icon-192.png', './assets/icons/icon-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
  );
});
