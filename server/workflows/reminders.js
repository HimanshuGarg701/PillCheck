import { sleep } from "workflow";
import { sendReminder } from "./send-reminder.js";
export async function scheduleReminder(
  subscription,
  scheduledAt,
  windowMinutes,
  doseId,
  test = false,
) {
  "use workflow";
  const start = new Date(scheduledAt).getTime();
  const offsets = test
    ? [0]
    : [
        0,
        ...Array.from(
          { length: Math.ceil(windowMinutes / 30) },
          (_, i) => 15 + i * 30,
        ).filter((n) => n < windowMinutes),
      ];
  for (const offset of offsets) {
    const due = start + offset * 60000;
    if (due > Date.now()) await sleep(new Date(due));
    if (Date.now() > start + windowMinutes * 60000) break;
    const alive = await sendReminder(subscription, doseId, offset, test);
    if (!alive) break;
  }
  return { finished: true };
}
