// Retire the former PWA without deleting its local medication records.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key.startsWith("pillcheck-"))
          .map((key) => caches.delete(key)),
      );
      const subscription =
        await self.registration.pushManager?.getSubscription();
      if (subscription) await subscription.unsubscribe();
      await self.clients.claim();
      await self.registration.unregister();
    })(),
  );
});
