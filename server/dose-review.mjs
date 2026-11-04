// This is a plausibility screen, not a dose calculator or a prescription limit.
const choices = (...values) => ({ type: "string", enum: values });
export const doseAssessmentSchema = {
  type: "object",
  properties: {
    finding: choices("potential_high_dose", "not_flagged", "uncertain"),
    basis: choices("quantity", "strength_or_daily_total", "references", "insufficient_information", "none"),
    evidence: {
      type: "array",
      items: {
        type: "object",
        properties: { sourceId: { type: "string" }, quote: { type: "string" } },
        required: ["sourceId", "quote"], additionalProperties: false,
      },
    },
  },
  required: ["finding", "basis", "evidence"], additionalProperties: false,
};

export function doseSummary(medicine) {
  const liquid = medicine.doseUnit.toLowerCase() === "ml";
  const mgPerDose = medicine.strengthMg / (liquid ? medicine.strengthVolumeMl ?? 1 : 1) * medicine.doseQuantity;
  return { mgPerDose, dailyMg: mgPerDose * medicine.times.length,
    quantityPerDose: medicine.doseQuantity, quantityPerDay: medicine.doseQuantity * medicine.times.length,
    unit: medicine.doseUnit, dosesPerDay: medicine.times.length };
}

export function unavailableDoseAssessment() {
  return {
    finding: "uncertain", basis: "insufficient_information", source: "unavailable", evidence: [],
    message: "The dose could not be fully checked.",
  };
}

const compact = (value) => String(value).replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
export function finishDoseAssessment(context, assessment) {
  // Older/malformed responses must never imply that a dose was checked.
  if (!assessment) return unavailableDoseAssessment();
  if (!doseAssessmentSchema.properties.finding.enum.includes(assessment.finding)
      || !doseAssessmentSchema.properties.basis.enum.includes(assessment.basis)
      || !Array.isArray(assessment.evidence) || assessment.evidence.length > 3) {
    throw Error("Invalid dose assessment.");
  }
  for (const evidence of assessment.evidence) {
    const source = context.sources.find((s) => s.id === evidence.sourceId);
    if (!source || !source.medicationIds.includes(context.candidate.id)
        || source.id.startsWith("identity-") || typeof evidence.quote !== "string"
        || evidence.quote.length < 12 || evidence.quote.length > 350
        || !compact(source.text).includes(compact(evidence.quote))) {
      throw Error("Dose evidence could not be verified.");
    }
  }
  const high = assessment.finding === "potential_high_dose";
  if ((high && !["quantity", "strength_or_daily_total", "references"].includes(assessment.basis))
      || (!high && assessment.basis !== (assessment.finding === "uncertain" ? "insufficient_information" : "none"))
      || (assessment.basis === "references" && !assessment.evidence.length)) {
    throw Error("Dose assessment did not match its evidence.");
  }
  const resolved = context.identities.find((i) => i.medicationId === context.candidate.id)?.status === "matched";
  const hasLabel = context.sources.some((s) => s.id === `label-${context.candidate.id}` && !s.truncated);
  if (assessment.finding === "uncertain" || (!high && (!resolved || !hasLabel))) {
    return { ...unavailableDoseAssessment(), source: "meta" };
  }
  return {
    finding: assessment.finding, basis: assessment.basis, source: "meta", evidence: assessment.evidence,
    // Keep the visible wording bounded; never turn a model guess into an exact maximum or replacement dose.
    message: high ? "The entered dose may be too high. Confirm the amount with your pharmacist."
      : "No dose concern was flagged. This does not confirm the dose is appropriate for you.",
  };
}
