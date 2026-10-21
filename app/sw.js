// =============================================================================
// SGP · Service Worker
// La VERSIÓN se sube en CADA despliegue: es lo que obliga al teléfono a soltar la copia
// guardada. Si solo se sube index.html, los teléfonos pueden quedarse con la versión
// anterior sin avisar (lección del SGS).
// =============================================================================
const VERSION = 'sgp-0.2.0';

const BASE = [
  './', 'index.html', 'manifest.webmanifest',
  'vendor/supabase.js',
  'vendor/source-sans-3-latin-400-normal.woff2',
  'vendor/source-sans-3-latin-600-normal.woff2',
  'vendor/source-sans-3-latin-700-normal.woff2',
  'assets/logo-horizontal.png', 'assets/logo-centrado.png',
  'assets/icon-192.png', 'assets/icon-512.png', 'assets/icon-maskable-512.png',
  'assets/apple-touch-icon.png', 'assets/favicon.png',
];

self.addEventListener('install', (ev) => {
  ev.waitUntil(caches.open(VERSION).then((c) => c.addAll(BASE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (ev) => {
  ev.waitUntil(
    caches.keys()
      .then((claves) => Promise.all(claves.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (ev) => {
  const req = ev.request;
  const url = new URL(req.url);
  // Solo archivos propios. Las llamadas a Supabase nunca se guardan en caché.
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;

  // La página: primero la red (para recibir actualizaciones); sin conexión, la copia guardada.
  if (req.mode === 'navigate') {
    ev.respondWith(
      fetch(req).then((r) => {
        const copia = r.clone(); caches.open(VERSION).then((c) => c.put('index.html', copia));
        return r;
      }).catch(() => caches.match('index.html'))
    );
    return;
  }

  // Librerías, tipografía e imágenes: primero la copia guardada.
  ev.respondWith(caches.match(req).then((guardado) => guardado || fetch(req)));
});
