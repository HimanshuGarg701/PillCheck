export const DISCLAIMER =
  "Informational only, not medical advice. Confirm with your doctor or pharmacist.";
export const PHARMACIST =
  "This medicine needs your pharmacist's advice. Call your pharmacist before taking it.";
export const localDay = (date = new Date(), timeZone) =>
  new Date(date).toLocaleDateString(
    "en-CA",
    timeZone ? { timeZone } : undefined,
  );
export const atTime = (day, time) =>
  new Date(`${day}T${time}:00`).toISOString();
export const uid = () => globalThis.crypto.randomUUID();
export const canonical = (value) =>
  String(value || "")
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ")
    .replace(/\s+(hydrochloride|hcl)$/, "");
const HIGH_RISK =
  /insulin|warfarin|apixaban|rivaroxaban|dabigatran|edoxaban|heparin|enoxaparin|clopidogrel|carbidopa|levodopa|ropinirole|pramipexole|levetiracetam|phenytoin|carbamazepine|valpro|lamotrigine|tacrolimus|cyclosporine|mycophenolate|sirolimus|anticoagulant|antiplatelet|parkinson|seizure|transplant|blood thinner/i;
export const isHighRisk = (med) =>
  !!med.highRisk ||
  HIGH_RISK.test(`${med.name} ${med.ingredient} ${med.riskClass || ""}`);
export const samples = [
  {
    id: "metformin",
    name: "Metformin",
    ingredient: "metformin",
    strengthMg: 500,
    doseQuantity: 1,
    doseUnit: "tablet",
    times: ["08:00", "18:00"],
    instructions: "With meals",
    caption: "Read a label",
    color: "sage",
  },
  {
    id: "glucophage",
    name: "Glucophage",
    ingredient: "metformin",
    strengthMg: 500,
    doseQuantity: 1,
    doseUnit: "tablet",
    times: ["08:00", "18:00"],
    instructions: "With meals",
    caption: "Catch a duplicate ingredient",
    color: "peach",
  },
  {
    id: "cimetidine",
    name: "Cimetidine",
    ingredient: "cimetidine",
    strengthMg: 200,
    doseQuantity: 1,
    doseUnit: "tablet",
    times: ["12:00"],
    instructions: "Synthetic label for an interaction demo",
    caption: "See an interaction flag",
    color: "lavender",
  },
];
export const interactionReferences = [
  {
    ingredients: ["metformin", "cimetidine"],
    severity: "Consult pharmacist",
    explanation:
      "Cimetidine can reduce the clearance of metformin and increase its exposure. Check with your doctor or pharmacist before taking these together.",
    source: "DailyMed · Metformin hydrochloride prescribing information",
    url: "https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=f19ad89c-8dbe-4806-8068-f63aa895488d&type=display",
  },
];
export function validateMedication(input) {
  if (!input || typeof input !== "object")
    throw new Error("Enter the medication details.");
  for (const key of ["name", "ingredient", "doseUnit"]) {
    if (
      typeof input[key] !== "string" ||
      !input[key].trim() ||
      input[key].length > 100
    )
      throw new Error(`Please confirm ${key}.`);
  }
  if (
    !Number.isFinite(input.strengthMg) ||
    input.strengthMg <= 0 ||
    input.strengthMg > 100000
  )
    throw new Error("Confirm the strength in mg.");
  if (
    !Number.isFinite(input.doseQuantity) ||
    input.doseQuantity <= 0 ||
    input.doseQuantity > 100
  )
    throw new Error("Confirm the dose quantity.");
  if (
    !Array.isArray(input.times) ||
    !input.times.length ||
    input.times.length > 8 ||
    input.times.some((t) => !/^([01]\d|2[0-3]):[0-5]\d$/.test(t)) ||
    new Set(input.times).size !== input.times.length
  )
    throw new Error("Confirm distinct times in HH:MM format.");
  if (
    input.startDate &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(input.startDate) ||
      localDay(new Date(`${input.startDate}T12:00:00`)) !== input.startDate)
  )
    throw new Error("Confirm a valid start date.");
  return {
    ...input,
    name: input.name.trim(),
    ingredient: canonical(input.ingredient),
    times: [...input.times].sort(),
    highRisk: isHighRisk(input),
  };
}
export const dailyMg = (med) =>
  med.strengthMg * med.doseQuantity * med.times.length;
export function checkRisks(
  candidate,
  medications,
  problems = [],
  now = new Date(),
) {
  const flags = [];
  const active = medications.filter(
    (m) => m.status === "active" && m.id !== candidate.id,
  );
  const duplicates = active.filter(
    (m) => canonical(m.ingredient) === canonical(candidate.ingredient),
  );
  if (duplicates.length)
    flags.push({
      kind: "duplicate",
      title: "Same ingredient, different label",
      medications: duplicates.map((m) => m.id),
      combinedMg:
        dailyMg(candidate) + duplicates.reduce((sum, m) => sum + dailyMg(m), 0),
      explanation: `This has the same active ingredient as ${duplicates.map((m) => m.name).join(", ")}. Taking both can double your daily dose. Check with your doctor before starting this.`,
    });
  for (const other of medications.filter((m) => m.id !== candidate.id)) {
    const recent =
      other.status === "stopped" &&
      other.endDate &&
      new Date(now) >= new Date(other.endDate) &&
      new Date(now) - new Date(other.endDate) <= 30 * 86400000;
    if (other.status !== "active" && !recent) continue;
    const reference = interactionReferences.find(
      (r) =>
        r.ingredients.includes(canonical(candidate.ingredient)) &&
        r.ingredients.includes(canonical(other.ingredient)) &&
        canonical(candidate.ingredient) !== canonical(other.ingredient),
    );
    if (reference)
      flags.push({
        kind: "interaction",
        title: `${candidate.name} + ${other.name}`,
        medications: [other.id],
        ...reference,
        explanation: `${recent ? "Recently stopped medicine: " : ""}${reference.explanation}`,
      });
  }
  if (problems.some((p) => canonical(p) === canonical(candidate.riskClass)))
    flags.push({
      kind: "history",
      title: "Recorded medication-class concern",
      explanation:
        "A problem with this medicine class is recorded in the demo history. Tell your doctor about this before you start it.",
    });
  return flags;
}
export function scheduleFor(med, day) {
  if (
    med.status !== "active" ||
    day < med.startDate ||
    (med.endDate && day > med.endDate)
  )
    return [];
  return med.times.map((time) => ({
    id: `${med.id}:${day}:${time}`,
    medicationId: med.id,
    scheduledAt: atTime(day, time),
    originalScheduledAt: atTime(day, time),
    status: "pending",
    confirmedAt: null,
    method: null,
    replanReason: null,
  }));
}
export function recordDose(state, id, status, method, now, reason = "") {
  const dose = state.doses.find((d) => d.id === id);
  if (!dose) throw new Error("Dose not found.");
  if (dose.status !== "pending" && dose.status !== "missed")
    throw new Error("This dose is already recorded.");
  if (!["taken", "skipped", "missed"].includes(status))
    throw new Error("Unknown confirmation.");
  if (!["button", "voice", "timer"].includes(method))
    throw new Error("Unknown confirmation method.");
  const confirmedAt = new Date(now).toISOString();
  const actual =
    status === "taken"
      ? new Date(now) - new Date(dose.scheduledAt) > 30 * 60000
        ? "taken_late"
        : "taken_on_time"
      : status;
  const updated = {
    ...dose,
    status: actual,
    confirmedAt: status === "missed" ? null : confirmedAt,
    method,
    reason,
  };
  return {
    ...state,
    doses: state.doses.map((d) => (d.id === id ? updated : d)),
    audit: [
      ...state.audit,
      {
        id: uid(),
        type: "dose_recorded",
        doseId: id,
        at: confirmedAt,
        before: dose.status,
        after: actual,
        reason: reason || "User confirmation",
        method,
      },
    ],
  };
}
// This validates a synthetic model proposal. These are fixture constraints, NOT clinical spacing rules.
export function validateReplan(
  med,
  confirmed,
  future,
  proposal,
  day,
  timeZone,
) {
  if (isHighRisk(med)) throw new Error(PHARMACIST);
  if (
    !med.demo ||
    med.id !== "med-metformin" ||
    med.minSpacingHours !== 10 ||
    canonical(med.ingredient) !== "metformin" ||
    med.strengthMg !== 500 ||
    med.doseQuantity !== 1
  )
    throw new Error(
      "A pharmacist-approved timing plan is required for this medicine.",
    );
  if (
    !proposal ||
    !Array.isArray(proposal.changes) ||
    proposal.changes.length !== future.length ||
    typeof proposal.explanation !== "string" ||
    !proposal.explanation.trim()
  )
    throw new Error("The model did not return a complete plan.");
  if (
    proposal.explanation.length > 600 ||
    /double|increase|decrease|take\b|stop\b|safe to|skip\b|resume tomorrow/i.test(
      proposal.explanation,
    )
  )
    throw new Error("The explanation needs pharmacist review.");
  const seen = new Set();
  let last = new Date(confirmed.confirmedAt).getTime();
  for (const item of proposal.changes) {
    const original = future.find((d) => d.id === item.doseId);
    if (
      !original ||
      seen.has(item.doseId) ||
      item.doseQuantity !== med.doseQuantity
    )
      throw new Error("A proposal changed a dose or omitted an event.");
    seen.add(item.doseId);
    const when = new Date(item.newTime).getTime();
    if (
      typeof item.newTime !== "string" ||
      !/(Z|[+-]\d{2}:\d{2})$/.test(item.newTime) ||
      !Number.isFinite(when) ||
      localDay(item.newTime, timeZone) !== day ||
      when < new Date(original.scheduledAt).getTime() ||
      when - last < med.minSpacingHours * 3600000
    )
      throw new Error(
        "The proposed times do not meet the synthetic spacing constraints.",
      );
    last = when;
  }
  return proposal;
}
export function applyReplan(state, med, confirmed, proposal) {
  const future = state.doses
    .filter(
      (d) =>
        d.medicationId === med.id &&
        d.status === "pending" &&
        localDay(d.scheduledAt) === localDay(confirmed.confirmedAt),
    )
    .sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt));
  validateReplan(
    med,
    confirmed,
    future,
    proposal,
    localDay(confirmed.confirmedAt),
  );
  const changes = proposal.changes.map((c) => ({
    id: uid(),
    doseId: c.doseId,
    medicationId: med.id,
    oldTime: future.find((d) => d.id === c.doseId).scheduledAt,
    newTime: new Date(c.newTime).toISOString(),
    reason: proposal.explanation,
    at: confirmed.confirmedAt,
  }));
  return {
    ...state,
    doses: state.doses.map((d) => {
      const change = changes.find((c) => c.doseId === d.id);
      return change
        ? { ...d, scheduledAt: change.newTime, replanReason: change.reason }
        : d;
    }),
    changes: [...state.changes, ...changes],
    audit: [
      ...state.audit,
      {
        id: uid(),
        type: "replan",
        at: confirmed.confirmedAt,
        reason: proposal.explanation,
        source: proposal.source || "unknown",
      },
    ],
  };
}
export function makeSeed(now = new Date()) {
  const day = localDay(now);
  const start = new Date(`${day}T12:00:00`);
  start.setDate(start.getDate() - 30);
  const startDate = localDay(start);
  const medications = [
    { ...samples[0], id: "med-metformin", minSpacingHours: 10 },
    {
      id: "med-amlodipine",
      name: "Amlodipine",
      ingredient: "amlodipine",
      strengthMg: 5,
      doseQuantity: 1,
      doseUnit: "tablet",
      times: ["08:00"],
      instructions: "Follow the recorded prescription",
      color: "peach",
    },
    {
      id: "med-atorvastatin",
      name: "Atorvastatin",
      ingredient: "atorvastatin",
      strengthMg: 20,
      doseQuantity: 1,
      doseUnit: "tablet",
      times: ["20:00"],
      instructions: "Follow the recorded prescription",
      color: "lavender",
    },
  ].map((m) => ({
    ...m,
    status: "active",
    startDate,
    endDate: null,
    demo: true,
    highRisk: false,
  }));
  const doses = [];
  for (let offset = -30; offset <= 0; offset++) {
    const date = new Date(`${day}T12:00:00`);
    date.setDate(date.getDate() + offset);
    for (const med of medications)
      for (const dose of scheduleFor(med, localDay(date))) {
        if (offset < 0) {
          const index = doses.length;
          dose.status =
            index % 19 === 0
              ? "missed"
              : index % 17 === 0
                ? "skipped"
                : index % 13 === 0
                  ? "taken_late"
                  : "taken_on_time";
          dose.confirmedAt = ["missed"].includes(dose.status)
            ? null
            : new Date(
                new Date(dose.scheduledAt).getTime() +
                  (dose.status === "taken_late" ? 70 : 2) * 60000,
              ).toISOString();
          dose.method = "button";
        }
        doses.push(dose);
      }
  }
  return {
    version: 1,
    demo: true,
    day,
    demoTime: atTime(day, "08:00"),
    patient: "Alex Morgan (fictional)",
    medications,
    doses,
    changes: [],
    flags: [],
    problems: [],
    audit: [
      {
        id: uid(),
        type: "demo_created",
        at: new Date(now).toISOString(),
        reason: "Synthetic demonstration data; no real patient records.",
      },
    ],
    language: "en-US",
    remindersEnabled: false,
    reminderAttempts: {},
    reminderWindowMinutes: 120,
  };
}
export function ensureToday(state, now = new Date()) {
  const day = localDay(now);
  if (state.day === day) return state;
  const existing = new Set(state.doses.map((d) => d.id));
  const added = [];
  const cursor = new Date(`${state.day}T12:00:00`);
  cursor.setDate(cursor.getDate() + 1);
  while (localDay(cursor) <= day) {
    for (const med of state.medications)
      for (const dose of scheduleFor(med, localDay(cursor))) {
        if (!existing.has(dose.id))
          added.push({
            ...dose,
            status: localDay(cursor) < day ? "missed" : "pending",
          });
      }
    cursor.setDate(cursor.getDate() + 1);
  }
  return {
    ...state,
    day,
    demoTime: atTime(day, "08:00"),
    doses: [
      ...state.doses.map((d) =>
        d.status === "pending" && localDay(d.scheduledAt) < day
          ? { ...d, status: "missed" }
          : d,
      ),
      ...added,
    ],
    audit: [
      ...state.audit,
      {
        id: uid(),
        type: "day_rollover",
        at: new Date(now).toISOString(),
        reason: "Unconfirmed previous doses marked missed; today generated.",
      },
    ],
  };
}
