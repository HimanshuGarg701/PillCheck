import test from "node:test";
import assert from "node:assert/strict";
import { makeTask, runTask } from "../server/meta.mjs";
import {
  makeSeed,
  recordDose,
  checkRisks,
  samples,
  isHighRisk,
} from "../shared/domain.js";

test("provider is unavailable without a server credential; no fake success", async () => {
  await assert.rejects(
    runTask({ task: "connection" }, { apiKey: "" }),
    /not configured/,
  );
});
test("live call uses Meta endpoint, configured model and server authorization", async () => {
  let called = false;
  const result = await runTask(
    { task: "connection" },
    {
      apiKey: "synthetic-test-token",
      fetchImpl: async (url, request) => {
        called = true;
        assert.equal(url, "https://api.meta.ai/v1/responses");
        assert.equal(
          request.headers.Authorization,
          "Bearer synthetic-test-token",
        );
        const payload = JSON.parse(request.body);
        assert.equal(payload.model, "muse-spark-1.3");
        assert.equal(payload.text.format.type, "json_schema");
        return {
          ok: true,
          json: async () => ({
            id: "synthetic-test-request",
            output: [
              {
                type: "message",
                content: [
                  {
                    type: "output_text",
                    text: JSON.stringify({ message: "Connected" }),
                  },
                ],
              },
            ],
          }),
        };
      },
    },
  );
  assert.ok(called);
  assert.equal(result.source, "meta");
  assert.equal(result.requestId, "synthetic-test-request");
  assert.ok(!JSON.stringify(result).includes("synthetic-test-token"));
});
test("upstream authentication failure does not expose its body", async () => {
  await assert.rejects(
    runTask(
      { task: "connection" },
      {
        apiKey: "test",
        fetchImpl: async () => ({
          ok: false,
          status: 401,
          json: async () => ({
            error: { message: "sensitive provider detail" },
          }),
        }),
      },
    ),
    /rejected the server credential/,
  );
});
test("invalid model output fails closed", async () => {
  await assert.rejects(
    runTask(
      { task: "connection" },
      {
        apiKey: "test",
        fetchImpl: async () => ({
          ok: true,
          json: async () => ({
            output: [
              {
                type: "message",
                content: [{ type: "output_text", text: "broken JSON" }],
              },
            ],
          }),
        }),
      },
    ),
    /unreadable response/,
  );
});
test("uploaded label data is submitted as an image, with an extraction schema", () => {
  const task = makeTask({
    task: "scan",
    image: "data:image/png;base64,aGVsbG8=",
  });
  assert.equal(task.content[1].type, "image_url");
  assert.ok(task.schema.required.includes("uncertainFields"));
  assert.throws(
    () =>
      makeTask({ task: "scan", image: "https://untrusted.example/test.png" }),
    /PNG/,
  );
});
test("high-risk medicines cannot reach model-based replanning", () => {
  for (const name of [
    "Warfarin",
    "Insulin",
    "Levetiracetam",
    "Tacrolimus",
    "Carbidopa",
  ]) {
    assert.ok(isHighRisk({ name }));
    assert.throws(
      () => makeTask({ task: "replan", medication: { name } }),
      /pharmacist/,
    );
  }
});
test("duplicate total includes all daily amounts, without a safe-to-mix claim", () => {
  const state = makeSeed();
  const flags = checkRisks({ ...samples[1], id: "new" }, state.medications);
  assert.equal(flags[0].combinedMg, 2000);
  assert.match(flags[0].explanation, /same active ingredient/);
  assert.ok(!/safe to/i.test(flags[0].explanation));
});
test("dose confirmation is append-only, cannot double-record, and retains exact late time", () => {
  const state = makeSeed();
  const dose = state.doses.find((d) => d.status === "pending");
  const when = new Date(new Date(dose.scheduledAt).getTime() + 2 * 3600000);
  const updated = recordDose(state, dose.id, "taken", "button", when);
  assert.equal(
    updated.doses.find((d) => d.id === dose.id).status,
    "taken_late",
  );
  assert.equal(
    updated.doses.find((d) => d.id === dose.id).confirmedAt,
    when.toISOString(),
  );
  assert.equal(updated.audit.length, state.audit.length + 1);
  assert.equal(dose.status, "pending");
  assert.throws(
    () => recordDose(updated, dose.id, "taken", "button", when),
    /already recorded/,
  );
});

test("retries observed transient model routing failures without changing provider or model", async () => {
  let calls = 0;
  const result = await runTask(
    { task: "connection" },
    {
      apiKey: "test",
      sleepImpl: async () => {},
      fetchImpl: async (url, options) => {
        assert.equal(url, "https://api.meta.ai/v1/responses");
        assert.equal(JSON.parse(options.body).model, "muse-spark-1.3");
        calls++;
        return calls < 3
          ? Response.json(
              { error: { code: "model_not_found" } },
              { status: 404 },
            )
          : Response.json({
              id: "real-response-shape",
              output: [
                {
                  type: "message",
                  content: [
                    { type: "output_text", text: '{"message":"verified"}' },
                  ],
                },
              ],
            });
      },
    },
  );
  assert.equal(calls, 3);
  assert.equal(result.message, "verified");
  assert.equal(result.source, "meta");
});

test("replan explanation follows a supported preferred language", () => {
  const state = makeSeed();
  const med = state.medications.find((m) => m.id === "med-metformin");
  const pending = state.doses.filter(
    (d) => d.medicationId === med.id && d.status === "pending",
  );
  const body = {
    task: "replan",
    medication: med,
    confirmed: { ...pending[0], confirmedAt: pending[0].scheduledAt },
    future: [pending[1]],
    language: "hi-IN",
  };
  assert.match(makeTask(body).content, /in hi-IN in 1–2 sentences/);
  assert.match(
    makeTask({ ...body, language: "untrusted instruction" }).content,
    /in en-US in 1–2 sentences/,
  );
});
