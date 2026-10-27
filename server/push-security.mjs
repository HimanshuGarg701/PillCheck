import { createHmac, createECDH, timingSafeEqual } from "node:crypto";
function derive(purpose) {
  if (!process.env.MODEL_API_KEY)
    throw new Error("The server credential is not configured.");
  return createHmac("sha256", process.env.MODEL_API_KEY)
    .update(`PillCheck/v1/${purpose}`)
    .digest();
}
// Domain-separated derivation avoids adding a second secret to this small public demo.
// Credential rotation also rotates the push identity; clients must re-enable Web Push.
export function vapidKeys() {
  const ec = createECDH("prime256v1");
  ec.setPrivateKey(derive("web-push-vapid"));
  return {
    publicKey: ec.getPublicKey().toString("base64url"),
    privateKey: ec.getPrivateKey().toString("base64url"),
  };
}
export function cancellationToken(runId) {
  return createHmac("sha256", derive("workflow-cancellation"))
    .update(runId)
    .digest("base64url");
}
export function validCancellation(runId, token) {
  if (
    typeof runId !== "string" ||
    runId.length > 150 ||
    typeof token !== "string"
  )
    return false;
  const expected = Buffer.from(cancellationToken(runId));
  const supplied = Buffer.from(token);
  return (
    expected.length === supplied.length && timingSafeEqual(expected, supplied)
  );
}
const counters = new Map();
export function checkRequest(req) {
  const origin = req.headers.get("origin");
  if (origin && new URL(origin).host !== new URL(req.url).host)
    throw new Error("Cross-origin requests are not allowed.");
  const key = req.headers.get("x-forwarded-for")?.split(",")[0] || "local";
  const now = Date.now();
  for (const [k, v] of counters) if (now - v.at > 3600000) counters.delete(k);
  const counter = counters.get(key) || { at: now, n: 0 };
  if (++counter.n > 250)
    throw new Error(
      "Background reminder request limit reached. Try again later.",
    );
  counters.set(key, counter);
}
export function validateSubscription(sub) {
  if (!sub || typeof sub.endpoint !== "string" || sub.endpoint.length > 3000)
    throw new Error("Invalid push subscription.");
  const url = new URL(sub.endpoint);
  const allowed =
    url.hostname === "fcm.googleapis.com" ||
    url.hostname === "updates.push.services.mozilla.com" ||
    url.hostname.endsWith(".push.services.mozilla.com") ||
    url.hostname === "web.push.apple.com" ||
    url.hostname.endsWith(".notify.windows.com");
  if (
    url.protocol !== "https:" ||
    url.port ||
    url.username ||
    url.password ||
    !allowed
  )
    throw new Error("Unsupported push service.");
  for (const field of ["p256dh", "auth"])
    if (
      typeof sub.keys?.[field] !== "string" ||
      !/^[A-Za-z0-9_-]+={0,2}$/.test(sub.keys[field]) ||
      sub.keys[field].length > 160
    )
      throw new Error("Invalid push encryption key.");
  return {
    endpoint: sub.endpoint,
    keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth },
  };
}
