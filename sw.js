/* FARMÁCIA — SNGPC: service worker
   Casca em cache para o app abrir offline. Dados nunca são cacheados:
   o Firebase cuida da fila offline e sincroniza quando a conexão volta. */
/* Trocar esta versao e o que faz o navegador buscar a casca de novo: o
   fetch aqui e cache-first, e o activate apaga todo cache cujo nome nao
   seja este. Publicar sem trocar deixa quem ja abriu o app vendo a versao
   antiga para sempre. */
const VERSAO = 'farmacia-sngpc-v8';
const CASCA = [
  './',
  './index.html',
  './app.js',
  './estilo.css',
  './manifest.json',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSAO).then((c) => c.addAll(CASCA)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((chaves) => Promise.all(chaves.filter((k) => k !== VERSAO).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // Firebase e CDN sempre pela rede
  if (url.origin !== self.location.origin) return;
  e.respondWith(
    caches.match(e.request).then((achado) =>
      achado || fetch(e.request).then((resp) => {
        const copia = resp.clone();
        caches.open(VERSAO).then((c) => c.put(e.request, copia));
        return resp;
      }).catch(() => caches.match('./index.html'))
    )
  );
});
