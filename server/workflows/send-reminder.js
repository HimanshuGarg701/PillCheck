import webpush from "web-push";
import { vapidKeys, validateSubscription } from "../push-security.mjs";
export async function sendReminder(subscription, doseId, offset, test) {
  "use step";
  const keys = vapidKeys();
  webpush.setVapidDetails(
    "https://pillcheck-zeta.vercel.app",
    keys.publicKey,
    keys.privateKey,
  );
  const payload = {
    title: test
      ? "PillCheck test reminder"
      : offset
        ? "Your check-in is still waiting"
        : "Time for your PillCheck check-in",
    body: test
      ? "Background Web Push is connected."
      : `Open your fictional schedule to review and record. Informational only, not medical advice. Confirm with your doctor or pharmacist.`,
    doseId,
    test,
  };
  try {
    await webpush.sendNotification(
      validateSubscription(subscription),
      JSON.stringify(payload),
      { TTL: 300, urgency: offset >= 45 ? "high" : "normal", timeout: 10000 },
    );
    return true;
  } catch (e) {
    if ([404, 410, 401, 403].includes(e.statusCode)) return false;
    throw new Error("Push delivery temporarily failed.");
  }
}
