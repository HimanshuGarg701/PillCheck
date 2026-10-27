import { defineEventHandler } from "nitro/h3";
import { getRun } from "workflow/api";
import { checkRequest, validCancellation } from "../../push-security.mjs";
export default defineEventHandler(async ({ req }) => {
  try {
    checkRequest(req);
    const body = await req.json();
    if (!validCancellation(body.runId, body.token))
      return Response.json(
        { error: "Invalid cancellation capability." },
        { status: 403 },
      );
    const run = getRun(body.runId);
    if (await run.exists) {
      const status = await run.status;
      if (["pending", "running"].includes(status)) await run.cancel();
    }
    return { cancelled: true };
  } catch {
    return Response.json(
      {
        error:
          "Reminder cancellation could not complete. It will retry when you reopen the app.",
      },
      { status: 502 },
    );
  }
});
