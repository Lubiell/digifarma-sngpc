/* FARMÁCIA — SNGPC: service worker
   Casca em cache para o app abrir offline. Dados nunca são cacheados:
   o Firebase cuida da fila offline e sincroniza quando a conexão volta. */
/* Trocar esta versao e o que faz o navegador buscar a casca de novo: o
   fetch aqui e cache-first, e o activate apaga todo cache cujo nome nao
   seja este. Publicar sem trocar deixa quem ja abriu o app vendo a versao
   antiga para sempre. */
const VERSAO = 'farmacia-sngpc-v46';
const CASCA = [
  './',
  './index.html',
  './app.js',
  './estilo.css',
  './manifest.json',
  './laboratorios.json',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (e) => {
  // cache: 'reload' passa por cima do cache HTTP do navegador: sem isso a
  // versao nova podia guardar o app.js velho que o navegador ainda tinha
  e.waitUntil(caches.open(VERSAO)
    .then((c) => c.addAll(CASCA.map((u) => new Request(u, { cache: 'reload' }))))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      // só o cache deste app: o módulo de receitas mora no mesmo endereço
      // (lubiell.github.io), e o cache é do endereço, não da pasta
      .then((chaves) => Promise.all(chaves
        .filter((k) => k.startsWith('farmacia-sngpc-') && k !== VERSAO)
        .map((k) => caches.delete(k))))
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

/* Avisos do agente (Firebase Cloud Messaging). O FCM entrega a mensagem
   como Web Push; quem mostra e este handler, sem o SDK do Firebase aqui.
   O agente manda o texto em notification (webpush) e repete em data:
   o que vier, vira aviso. Push sem aviso visivel o navegador nao aceita. */
function avisoDoPush(dados) {
  const n = (dados && dados.notification) || {};
  const d = (dados && dados.data) || {};
  return {
    titulo: n.title || d.titulo || 'Farmácia SNGPC',
    texto: n.body || d.texto || 'Há pendências no SNGPC.'
  };
}

self.addEventListener('push', (e) => {
  let dados = {};
  try { dados = e.data ? e.data.json() : {}; } catch (_) { dados = { data: { texto: e.data && e.data.text() } }; }
  const aviso = avisoDoPush(dados);
  e.waitUntil(self.registration.showNotification(aviso.titulo, {
    body: aviso.texto, icon: './icon-192.png', badge: './icon-192.png', tag: 'farmacia-sngpc', renotify: true
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((abertas) => {
      const aberta = abertas.find((c) => c.url.startsWith(self.registration.scope));
      return aberta ? aberta.focus() : self.clients.openWindow(self.registration.scope);
    })
  );
});
