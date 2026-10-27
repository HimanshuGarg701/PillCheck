import { defineEventHandler } from "nitro/h3";
import { start } from "workflow/api";
import { scheduleReminder } from "../../workflows/reminders.js";
import {
  checkRequest,
  validateSubscription,
  cancellationToken,
} from "../../push-security.mjs";
export default defineEventHandler(async ({ req }) => {
  try {
    checkRequest(req);
    const text = await req.text();
    if (text.length > 6000) throw new Error("Request too large.");
    const body = JSON.parse(text);
    const subscription = validateSubscription(body.subscription);
    const due = new Date(body.scheduledAt).getTime();
    const test = body.test === true;
    const windowMinutes = test ? 1 : body.windowMinutes;
    if (
      !Number.isFinite(due) ||
      due < Date.now() - 4 * 3600000 ||
      due > Date.now() + 8 * 86400000 ||
      ![1, 60, 120, 240].includes(windowMinutes)
    )
      throw new Error("Invalid reminder window.");
    const doseId = String(body.doseId || "test").slice(0, 200);
    const run = await start(scheduleReminder, [
      subscription,
      new Date(due).toISOString(),
      windowMinutes,
      doseId,
      test,
    ]);
    return Response.json(
      { runId: run.runId, token: cancellationToken(run.runId) },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (e) {
    return Response.json(
      {
        error: /Invalid|Unsupported|limit|Cross-origin|large|configured/.test(
          e.message,
        )
          ? e.message
          : "The background reminder could not be scheduled.",
      },
      { status: 400 },
    );
  }
});
