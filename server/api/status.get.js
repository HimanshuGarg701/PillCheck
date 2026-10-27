import { defineEventHandler } from "nitro/h3";
export default defineEventHandler(() =>
  Response.json(
    {
      configured: !!process.env.MODEL_API_KEY,
      provider: "Meta Model API",
      model: process.env.MODEL_ID || "muse-spark-1.3",
    },
    { headers: { "Cache-Control": "no-store" } },
  ),
);
