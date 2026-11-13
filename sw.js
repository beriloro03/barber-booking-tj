const CACHE_NAME = "barber-booking-shell-v2";
const APP_SHELL = ["./", "./offline.html", "./manifest.json", "./icon.svg"];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key.startsWith("barber-booking-shell-") && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch {
        const offlineUrl = new URL("./offline.html", self.registration.scope).href;
        return (await caches.match(offlineUrl)) ||
          new Response("Шумо ҳоло офлайн ҳастед. Интернетро фаъол карда, саҳифаро нав кунед.", {
            status: 503,
            headers: { "Content-Type": "text/plain; charset=utf-8" }
          });
      }
    })());
    return;
  }

  const url = new URL(request.url);
  const staticFiles = ["manifest.json", "icon.svg", "offline.html"];
  if (staticFiles.some(file => url.pathname === new URL(file, self.registration.scope).pathname)) {
    event.respondWith(
      caches.match(request).then(cached => cached || fetch(request))
    );
  }
});
