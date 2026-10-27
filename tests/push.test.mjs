import test from "node:test";
import assert from "node:assert/strict";
import { localDay, scheduleFor } from "../src/domain.js";

function deferred() {
  let resolve;
  const promise = new Promise((r) => (resolve = r));
  return { promise, resolve };
}

function fixture(t, times = ["12:00"]) {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const day = localDay(tomorrow);
  const med = {
    id: "test-medicine",
    status: "active",
    startDate: day,
    endDate: day,
    times,
  };
  const stored = new Map();
  const calls = [];
  const started = deferred();
  const release = deferred();
  let unsubscribed = false;
  const sub = {
    toJSON: () => ({ endpoint: "https://push.example.test/fixture" }),
    unsubscribe: async () => {
      unsubscribed = true;
    },
  };
  const replacements = {
    navigator: {
      onLine: true,
      serviceWorker: {
        ready: Promise.resolve({
          pushManager: { getSubscription: async () => sub },
        }),
      },
    },
    localStorage: {
      getItem: (key) => stored.get(key) ?? null,
      setItem: (key, value) => stored.set(key, value),
    },
    fetch: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) });
      if (calls.length === 1) {
        started.resolve();
        await release.promise;
      }
      return {
        ok: true,
        json: async () => ({ runId: "test-run", token: "test-capability" }),
      };
    },
  };
  for (const [name, value] of Object.entries(replacements)) {
    const previous = Object.getOwnPropertyDescriptor(globalThis, name);
    Object.defineProperty(globalThis, name, { value, configurable: true });
    t.after(() =>
      previous
        ? Object.defineProperty(globalThis, name, previous)
        : delete globalThis[name],
    );
  }
  return {
    state: {
      medications: [med],
      doses: [],
      pushEnabled: true,
      reminderWindowMinutes: 120,
    },
    doses: scheduleFor(med, day),
    calls,
    started,
    release,
    stored,
    unsubscribed: () => unsubscribed,
  };
}

test("confirmation during a pending schedule request cancels the newly created reminder", async (t) => {
  const f = fixture(t);
  const { syncPush } = await import("../src/push.js?confirmation-race");
  const scheduling = syncPush(f.state);
  await f.started.promise;
  const confirmed = syncPush({
    ...f.state,
    doses: f.doses.map((d) => ({ ...d, status: "taken_on_time" })),
  });
  f.release.resolve();
  await Promise.all([scheduling, confirmed]);
  assert.deepEqual(
    f.calls.map((c) => c.url),
    ["/api/push/schedule", "/api/push/cancel"],
  );
  assert.equal(f.calls[1].body.runId, "test-run");
  assert.deepEqual(JSON.parse(f.stored.get("pillcheck:push-runs")), {});
});

test("disabling during synchronization cancels the in-flight run and prevents remaining schedules", async (t) => {
  const f = fixture(t, ["12:00", "18:00"]);
  const { syncPush, disablePush } = await import("../src/push.js?disable-race");
  const scheduling = syncPush(f.state);
  await f.started.promise;
  const disabling = disablePush();
  f.release.resolve();
  await Promise.all([scheduling, disabling]);
  assert.deepEqual(
    f.calls.map((c) => c.url),
    ["/api/push/schedule", "/api/push/cancel"],
  );
  assert.equal(f.unsubscribed(), true);
  await syncPush(f.state);
  assert.equal(f.calls.length, 2);
});
