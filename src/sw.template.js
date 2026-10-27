const CACHE = "pillcheck-__VERSION__";
const PRECACHE = __PRECACHE__;
self.addEventListener("install", (event) =>
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting()),
  ),
);
self.addEventListener("activate", (event) =>
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k.startsWith("pillcheck-") && k !== CACHE)
            .map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  ),
);
self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);
  if (
    req.method !== "GET" ||
    url.origin !== self.location.origin ||
    url.pathname.startsWith("/api/") ||
    url.pathname.startsWith("/.well-known/")
  )
    return;
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((r) => {
          if (r.ok) {
            const copy = r.clone();
            caches.open(CACHE).then((c) => c.put("/", copy));
          }
          return r;
        })
        .catch(() => caches.match("/")),
    );
  } else {
    event.respondWith(caches.match(req).then((r) => r || fetch(req)));
  }
});
function db() {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open("pillcheck-push", 1);
    r.onupgradeneeded = () => r.result.createObjectStore("state");
    r.onsuccess = () => resolve(r.result);
    r.onerror = reject;
  });
}
async function saveBlocked(ids) {
  const database = await db();
  await new Promise((resolve) => {
    const tx = database.transaction("state", "readwrite");
    tx.objectStore("state").put(ids, "blocked");
    tx.oncomplete = resolve;
  });
  database.close();
}
async function blocked(id) {
  const database = await db();
  return new Promise((resolve) => {
    const r = database.transaction("state").objectStore("state").get("blocked");
    r.onsuccess = () => {
      database.close();
      resolve((r.result || []).includes(id));
    };
    r.onerror = () => resolve(false);
  });
}
self.addEventListener("message", (event) => {
  if (event.data?.type === "BLOCK_DOSES" && Array.isArray(event.data.ids))
    event.waitUntil(saveBlocked(event.data.ids));
});
self.addEventListener("push", (event) =>
  event.waitUntil(
    (async () => {
      let data;
      try {
        data = event.data.json();
      } catch {
        return;
      }
      if (!data.test && (await blocked(data.doseId))) return;
      await self.registration.showNotification(data.title, {
        body: data.body,
        icon: "/icons/icon-192.png",
        badge: "/icons/icon-192.png",
        tag: data.test ? "pillcheck-test" : `pillcheck-${data.doseId}`,
        renotify: true,
        data: { url: "/" },
      });
    })(),
  ),
);
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clients) => {
        const client = clients.find(
          (c) => new URL(c.url).origin === self.location.origin,
        );
        return client ? client.focus() : self.clients.openWindow("/");
      }),
  );
});
