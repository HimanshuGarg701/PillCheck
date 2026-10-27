import test from "node:test";
import assert from "node:assert/strict";
import {
  makeSeed,
  samples,
  checkRisks,
  recordDose,
  applyReplan,
  validateReplan,
  validateMedication,
  localDay,
  ensureToday,
  atTime,
} from "../src/domain.js";
import {
  vapidKeys,
  cancellationToken,
  validCancellation,
  validateSubscription,
} from "../server/push-security.mjs";
test("label salt form still detects duplicate ingredient and reference interaction", () => {
  const s = makeSeed();
  assert.equal(
    checkRisks(
      { ...samples[1], ingredient: "Metformin hydrochloride" },
      s.medications,
    )[0].combinedMg,
    2000,
  );
  assert.equal(checkRisks(samples[2], s.medications)[0].kind, "interaction");
});
test("recently stopped and class concerns remain part of checks", () => {
  const s = makeSeed();
  s.medications[0].status = "stopped";
  s.medications[0].endDate = s.day;
  assert.match(
    checkRisks(samples[2], s.medications)[0].explanation,
    /Recently stopped/,
  );
  assert.ok(
    checkRisks({ ...samples[2], riskClass: "statin" }, [], ["statin"]).some(
      (f) => f.kind === "history",
    ),
  );
});
test("review rejects missing dosage, ambiguous times, and unrecognized dates", () => {
  const base = { ...samples[0], startDate: "2026-10-26" };
  assert.throws(
    () => validateMedication({ ...base, strengthMg: null }),
    /strength/,
  );
  assert.throws(() => validateMedication({ ...base, times: ["8am"] }), /HH:MM/);
  assert.throws(
    () => validateMedication({ ...base, startDate: "2026-02-30" }),
    /date/,
  );
  assert.equal(
    validateMedication({ ...base, name: "Warfarin", highRisk: false }).highRisk,
    true,
  );
});
test("validated replan preserves amounts and adds an audit with before/after times", () => {
  let s = makeSeed();
  const med = s.medications[0];
  const first = s.doses.find(
    (d) => d.medicationId === med.id && d.status === "pending",
  );
  s = recordDose(s, first.id, "taken", "button", atTime(s.day, "10:00"));
  const confirmed = s.doses.find((d) => d.id === first.id);
  const future = s.doses.filter(
    (d) => d.medicationId === med.id && d.status === "pending",
  );
  const p = {
    changes: [
      {
        doseId: future[0].id,
        newTime: atTime(s.day, "20:00"),
        doseQuantity: 1,
      },
    ],
    explanation:
      "In this demo, the recorded morning dose was late; the evening event shifts to maintain the fictional interval.",
    source: "meta",
  };
  const updated = applyReplan(s, med, confirmed, p);
  assert.equal(updated.changes.length, 1);
  assert.equal(updated.changes[0].oldTime, future[0].scheduledAt);
  assert.equal(
    updated.doses.find((d) => d.id === future[0].id).scheduledAt,
    atTime(s.day, "20:00"),
  );
  for (const changes of [
    [{ ...p.changes[0], doseQuantity: 2 }],
    [{ ...p.changes[0], newTime: atTime(s.day, "18:00") }],
    [],
  ])
    assert.throws(() =>
      validateReplan(med, confirmed, future, { ...p, changes }, s.day),
    );
  assert.throws(
    () =>
      validateReplan(
        { ...med, ingredient: "unknown" },
        confirmed,
        future,
        p,
        s.day,
      ),
    /pharmacist/,
  );
});
test("rollover keeps completed history and creates new day without duplicate events", () => {
  const s = makeSeed(new Date("2026-10-24T12:00:00"));
  const old = s.doses
    .filter((d) => d.status !== "pending")
    .map((d) => ({ ...d }));
  const updated = ensureToday(s, new Date("2026-10-26T12:00:00"));
  assert.deepEqual(updated.doses.slice(0, old.length), old);
  assert.equal(
    new Set(updated.doses.map((d) => d.id)).size,
    updated.doses.length,
  );
  assert.equal(updated.doses.filter((d) => d.status === "pending").length, 4);
});
test("push credentials are deterministic, distinct by purpose, and cancellation is capability-protected", () => {
  process.env.MODEL_API_KEY = "synthetic-unit-test-root";
  const keys = vapidKeys();
  assert.equal(Buffer.from(keys.publicKey, "base64url").length, 65);
  assert.deepEqual(vapidKeys(), keys);
  const token = cancellationToken("run-test");
  assert.equal(validCancellation("run-test", token), true);
  assert.equal(validCancellation("run-other", token), false);
  assert.equal(validCancellation("run-test", "short"), false);
  assert.notEqual(token, keys.privateKey);
  delete process.env.MODEL_API_KEY;
});
test("push endpoints reject SSRF destinations and malformed keys", () => {
  for (const endpoint of [
    "http://localhost",
    "https://127.0.0.1",
    "https://fcm.googleapis.com.evil.example/a",
    "https://fcm.googleapis.com:8443/a",
  ])
    assert.throws(() =>
      validateSubscription({
        endpoint,
        keys: { p256dh: "test", auth: "test" },
      }),
    );
});
