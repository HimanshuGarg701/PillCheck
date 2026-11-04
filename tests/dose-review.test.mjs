import test from "node:test";
import assert from "node:assert/strict";
import { doseSummary, finishDoseAssessment, unavailableDoseAssessment } from "../server/dose-review.mjs";
import { finishReview, reviewPrompt, unavailableReview, validateReviewInput } from "../server/medication-review.mjs";

function context(name = "Amlodipine", quantity = 1) {
  return {
    candidate: { id: "candidate", name, ingredient: name.toLowerCase(), doseQuantity: quantity,
      strengthMg: 5, doseUnit: "tablet", times: ["08:00", "18:00"], frequency: "Twice daily", status: "active" },
    medications: [], pairs: [], warnings: [],
    identities: [{ medicationId: "candidate", status: "matched" }],
    sources: [{ id: "label-candidate", medicationIds: ["candidate"], truncated: false,
      text: "The dosage needs to be individualized according to the patient's response." }],
  };
}
const high = { finding: "potential_high_dose", basis: "strength_or_daily_total", evidence: [] };
const noFlag = { finding: "not_flagged", basis: "none", evidence: [] };

test("dose assessment uses model feedback across medicines without a product or quantity cutoff", () => {
  for (const name of ["Amlodipine", "Glucophage", "Ibuprofen", "Unknown medicine"]) {
    for (const count of [1, 7, 99, 100, 200]) {
      const c = context(name, count);
      assert.equal(finishDoseAssessment(c, high).finding, "potential_high_dose");
      assert.equal(finishDoseAssessment(c, noFlag).finding, "not_flagged");
    }
  }
  assert.ok(!Object.hasOwn(finishDoseAssessment(context(), high), "maximumDailyMg"));
});
test("calculated dose respects liquid concentration and dose frequency", () => {
  const c = context();
  c.candidate.doseQuantity = 7;
  assert.deepEqual(doseSummary(c.candidate), { mgPerDose: 35, dailyMg: 70, quantityPerDose: 7, quantityPerDay: 14, unit: "tablet", dosesPerDay: 2 });
  const liquid = { ...c.candidate, strengthMg: 250, strengthVolumeMl: 5, doseQuantity: 7.5, doseUnit: "mL" };
  assert.equal(doseSummary(liquid).mgPerDose, 375);
  assert.equal(doseSummary(liquid).dailyMg, 750);
  assert.throws(() => validateReviewInput({ candidate: { ...liquid, strengthVolumeMl: Number.MIN_VALUE }, medications: [] }), /concentration/);
});
test("unknown identities and missing labels cannot become a reassuring dose result", () => {
  const c = context(); c.identities[0].status = "unresolved"; c.sources = [];
  assert.equal(finishDoseAssessment(c, noFlag).finding, "uncertain");
  assert.equal(finishDoseAssessment(c, high).finding, "potential_high_dose");
  assert.equal(finishDoseAssessment(c, undefined).finding, "uncertain");
  assert.equal(unavailableDoseAssessment().source, "unavailable");
});
test("dose evidence must be an actual candidate label passage", () => {
  const c = context();
  const referenceFinding = { ...high, basis: "references", evidence: [{ sourceId: "label-candidate", quote: c.sources[0].text }] };
  assert.equal(finishDoseAssessment(c, referenceFinding).finding, "potential_high_dose");
  assert.throws(() => finishDoseAssessment(c, { ...referenceFinding, evidence: [] }), /evidence/);
  assert.throws(() => finishDoseAssessment(c, { ...referenceFinding, evidence: [{ sourceId: "label-candidate", quote: "Invented dosing advice." }] }), /evidence/);
  c.sources[0].medicationIds = ["another-medicine"];
  assert.throws(() => finishDoseAssessment(c, referenceFinding), /evidence/);
  for (const assessment of [{ ...high, finding: "safe" }, { ...high, basis: "none" }, { ...high, evidence: null }]) {
    assert.throws(() => finishDoseAssessment(context(), assessment));
  }
});
test("a validated dose concern survives an incomplete interaction review, but is not fabricated on outage", () => {
  const c = context("Another medicine", 100);
  assert.equal(unavailableReview(c, "Interaction review incomplete.", high).doseAssessment.finding, "potential_high_dose");
  const offline = unavailableReview(c, "Meta unavailable.");
  assert.equal(offline.doseAssessment.finding, "uncertain");
  assert.equal(offline.doseAssessment.source, "unavailable");
});
test("dose concerns are returned for a first medicine with no interaction pairs", () => {
  const c = context();
  const review = finishReview(c, { summary: "Review the recorded dose.", pairs: [], doseAssessment: high, proposedCandidateTimes: [], timingExplanation: "No schedule change." });
  assert.equal(review.doseAssessment.finding, "potential_high_dose");
  assert.deepEqual(review.pairs, []);
  const prompt = reviewPrompt(c);
  assert.match(prompt, /EVERY medicine/);
  assert.match(prompt, /strengthMg \/ strengthVolumeMl \* doseQuantity/);
  assert.match(prompt, /Do not provide numerical dose ceilings/);
});
