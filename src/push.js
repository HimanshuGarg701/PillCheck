import { scheduleFor, localDay } from "./domain.js";
const KEY = "pillcheck:push-runs";
let stopping = false;
function bounded(promise, message, ms = 15000) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}
export const pushSupported = () =>
  "serviceWorker" in navigator &&
  "PushManager" in window &&
  "Notification" in window;
async function call(path, body) {
  const res = await fetch(`/api/push/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const data = await res.json();
  if (!res.ok)
    throw new Error(data.error || "Background reminders could not be updated.");
  return data;
}
function keyBytes(str) {
  const text = atob(str.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(text, (c) => c.charCodeAt(0));
}
async function subscription() {
  const sw = await bounded(
    navigator.serviceWorker.ready,
    "Offline support has not finished installing. Reload the app while online, then try again.",
  );
  return sw.pushManager.getSubscription();
}
export async function enablePush(state) {
  stopping = false;
  if (!pushSupported())
    throw new Error("This browser does not support background Web Push.");
  const permission = await bounded(
    Notification.requestPermission(),
    "The browser has not completed notification permission. Open PillCheck in Chrome, Edge, or Safari and allow notifications.",
    20000,
  );
  if (permission !== "granted")
    throw new Error(
      "Notifications were not allowed. You can enable them in your browser settings.",
    );
  const sw = await bounded(
    navigator.serviceWorker.ready,
    "Offline support has not finished installing. Reload the app while online, then try again.",
  );
  const info = await fetch("/api/push/key").then((r) => r.json());
  if (!info.publicKey)
    throw new Error(
      info.error || "The server is not ready for background reminders.",
    );
  await bounded(
    sw.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: keyBytes(info.publicKey),
    }),
    "This browser could not connect to its push service. Try Chrome, Edge, or Safari with notifications allowed.",
  );
  await syncPush(state, true);
}
export async function disablePush() {
  stopping = true;
  if (syncing) await syncing.catch(() => {});
  const runs = JSON.parse(localStorage.getItem(KEY) || "{}");
  for (const [id, r] of Object.entries(runs)) {
    await call("cancel", r);
    delete runs[id];
    localStorage.setItem(KEY, JSON.stringify(runs));
  }
  const sub = await subscription();
  if (sub) await sub.unsubscribe();
}
let syncing;
export async function syncPush(state, force = false) {
  if (stopping) return;
  if (syncing)
    return syncing.then(
      () => syncPush(state, force),
      () => syncPush(state, force),
    );
  if (!force && !state.pushEnabled) return;
  if (!navigator.onLine) return;
  syncing = (async () => {
    const sub = await subscription();
    if (!sub)
      throw new Error(
        "Background reminder permission needs to be enabled again.",
      );
    const target = [];
    const current = Date.now();
    for (let offset = 0; offset < 7; offset++) {
      const day = new Date();
      day.setDate(day.getDate() + offset);
      for (const med of state.medications) {
        for (const d of scheduleFor(med, localDay(day))) {
          const actual = state.doses.find((x) => x.id === d.id) || d;
          if (
            actual.status === "pending" &&
            new Date(actual.scheduledAt).getTime() +
              state.reminderWindowMinutes * 60000 >
              current
          )
            target.push(actual);
        }
      }
    }
    const runs = JSON.parse(localStorage.getItem(KEY) || "{}");
    for (const [id, run] of Object.entries(runs)) {
      const wanted = target.find((d) => d.id === id);
      if (
        !wanted ||
        run.scheduledAt !== wanted.scheduledAt ||
        run.window !== state.reminderWindowMinutes
      ) {
        await call("cancel", run);
        delete runs[id];
        localStorage.setItem(KEY, JSON.stringify(runs));
      }
    }
    for (const d of target) {
      if (stopping) break;
      if (!runs[d.id]) {
        const run = await call("schedule", {
          subscription: sub.toJSON(),
          doseId: d.id,
          scheduledAt: d.scheduledAt,
          windowMinutes: state.reminderWindowMinutes,
        });
        runs[d.id] = {
          ...run,
          scheduledAt: d.scheduledAt,
          window: state.reminderWindowMinutes,
        };
        localStorage.setItem(KEY, JSON.stringify(runs));
      }
    }
  })().finally(() => (syncing = null));
  return syncing;
}
export async function testPush() {
  const sub = await subscription();
  if (!sub) throw new Error("Enable background reminders first.");
  return call("schedule", {
    subscription: sub.toJSON(),
    scheduledAt: new Date(Date.now() + 10000).toISOString(),
    windowMinutes: 1,
    test: true,
  });
}
