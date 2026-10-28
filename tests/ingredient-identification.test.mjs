import test from "node:test";
import assert from "node:assert/strict";
import { runTask, makeTask } from "../server/meta.mjs";

const reference =
  (name, ingredients, tty = "BN") =>
  async (url, options) => {
    assert.equal(new URL(url).hostname, "rxnav.nlm.nih.gov");
    assert.equal(options.headers.Authorization, undefined);
    if (url.includes("/rxcui.json?"))
      return Response.json({ idGroup: { rxnormId: ["12345"] } });
    if (url.includes("/properties.json"))
      return Response.json({ properties: { name, rxcui: "12345", tty } });
    return Response.json({
      relatedGroup: {
        conceptGroup: [
          {
            conceptProperties: ingredients.map((name, index) => ({
              name,
              tty: "IN",
              rxcui: String(500 + index),
            })),
          },
        ],
      },
    });
  };
const meta =
  (data, inspect = () => {}) =>
  async (url, request) => {
    assert.equal(url, "https://api.meta.ai/v1/responses");
    inspect(JSON.parse(request.body));
    return Response.json({
      id: "test-identify",
      output: [
        {
          type: "message",
          content: [{ type: "output_text", text: JSON.stringify(data) }],
        },
      ],
    });
  };

test("name alone resolves an ingredient through references and live-shaped Meta output", async () => {
  const name = "Identification brand one";
  const result = await runTask(
    { task: "identify", name, identity: { ingredients: ["injected"] } },
    {
      apiKey: "test",
      referenceFetchImpl: reference(name, ["metformin"]),
      fetchImpl: meta(
        { status: "matched", ingredients: ["metformin"] },
        (payload) => {
          assert.equal(payload.model, "muse-spark-1.3");
          assert.match(payload.input[0].content[0].text, /metformin/);
          assert.doesNotMatch(payload.input[0].content[0].text, /injected/);
        },
      ),
    },
  );
  assert.equal(result.status, "matched");
  assert.equal(result.aiStatus, "completed");
  assert.equal(result.source, "meta");
  assert.deepEqual(result.ingredients, ["metformin"]);
  assert.ok(result.sourceURL.startsWith("https://rxnav.nlm.nih.gov/"));
});

test("specific combination product retains every ingredient and rejects a dropped ingredient", async () => {
  const name = "Identification combination";
  const options = {
    apiKey: "test",
    referenceFetchImpl: reference(name, ["amlodipine", "atorvastatin"], "SBD"),
  };
  const result = await runTask(
    { task: "identify", name },
    {
      ...options,
      fetchImpl: meta({
        status: "matched",
        ingredients: ["atorvastatin", "amlodipine"],
      }),
    },
  );
  assert.deepEqual(result.ingredients, ["amlodipine", "atorvastatin"]);
  const rejected = await runTask(
    { task: "identify", name },
    {
      ...options,
      fetchImpl: meta({ status: "matched", ingredients: ["amlodipine"] }),
    },
  );
  assert.equal(rejected.aiStatus, "rejected");
  assert.deepEqual(rejected.ingredients, []);
});

test("broad brands with multiple ingredient possibilities are not filled as a combination", async () => {
  let calls = 0;
  const result = await runTask(
    { task: "identify", name: "Identification broad brand" },
    {
      apiKey: "test",
      referenceFetchImpl: reference(
        "Identification broad brand",
        ["one", "two"],
        "BN",
      ),
      fetchImpl: async () => {
        calls++;
        throw Error("must not call Meta");
      },
    },
  );
  assert.equal(result.status, "unresolved");
  assert.deepEqual(result.ingredients, []);
  assert.equal(calls, 0);
});

test("unknown names and reference outages cannot turn into model guesses", async () => {
  for (const name of ["Unknown identification", "Offline identification"]) {
    const result = await runTask(
      { task: "identify", name },
      {
        referenceFetchImpl: async () =>
          name.startsWith("Offline")
            ? Promise.reject(Error("offline"))
            : Response.json({}),
        fetchImpl: async () => {
          throw Error("Meta must not be called");
        },
      },
    );
    assert.equal(result.status, "unresolved");
    assert.equal(result.aiStatus, "not_run");
    assert.deepEqual(result.ingredients, []);
  }
});

test("provider failure preserves the verified reference match without claiming AI verification", async () => {
  const result = await runTask(
    { task: "identify", name: "Identification offline Meta" },
    {
      apiKey: "",
      referenceFetchImpl: reference("Identification offline Meta", [
        "metformin",
      ]),
    },
  );
  assert.equal(result.status, "matched");
  assert.equal(result.aiStatus, "unavailable");
  assert.equal(result.source, "references_only");
  assert.equal(result.model, null);
  assert.deepEqual(result.ingredients, ["metformin"]);
});

test("unsupported or uncertain model identity is never auto-filled", async () => {
  for (const [index, output] of [
    { status: "matched", ingredients: ["invented"] },
    { status: "matched", ingredients: ["metformin", "metformin"] },
    { status: "uncertain", ingredients: [] },
  ].entries()) {
    const name = `Identification uncertain ${index}`;
    const result = await runTask(
      { task: "identify", name },
      {
        apiKey: "test",
        referenceFetchImpl: reference(name, ["metformin"]),
        fetchImpl: meta(output),
      },
    );
    assert.equal(result.status, "unresolved");
    assert.deepEqual(result.ingredients, []);
  }
});

test("invalid names and client-only reference context are rejected before inference", async () => {
  for (const name of [null, "", "a", "x".repeat(151)])
    await assert.rejects(
      runTask(
        { task: "identify", name },
        {
          referenceFetchImpl: async () => {
            throw Error("unexpected lookup");
          },
        },
      ),
      /medicine name/,
    );
  assert.throws(
    () => makeTask({ task: "identify", name: "Glucophage", identity: {} }),
    /references are required/,
  );
});
