# Implementation checklist

This checklist translates the supplied PillCheck requirements brief into verification targets. Unchecked items are not complete. A scaffold or simulated response does not count as a verified integration.

## Platform and judging artifacts

- [x] Create a public repository in HimanshuGarg701.
- [x] Connect Vercel to this repository for automatic deployments.
- [x] Configure the Meta Model API credential only on the server.
- [x] Resolve the brief's Llama model name against current Meta account availability with the owner: Muse Spark 1.3 approved.
- [ ] Deploy one responsive web app at a public HTTPS URL, with no login required by judges.
- [ ] Verify the full flow on phone and desktop, including an incognito session.
- [x] Preload 3–4 synthetic medications and a full daily schedule.
- [x] Bundle three synthetic label images covering ordinary intake, duplicate ingredient, and interaction scenarios.
- [ ] Provide instant reminder and late-dose demo controls that exercise the implemented workflows.
- [ ] Record a self-contained demo of at most three minutes and publish its accessible YouTube link.
- [ ] Prepare submission text naming the Indie Developer track and Build for Your World theme, the problem, audience, Meta tools, and why the models matter.
- [ ] Verify public repository, live URL, video, and team details before submission.

## Functional requirements

| ID | Required behavior | Verification target |
| --- | --- | --- |
| FR-01 / FR-01A | Live model extraction from uploaded or bundled label images; no camera required | Name, ingredient, strength, quantity, frequency, timing; uncertain fields require review; scan failure preserves entry |
| FR-02 | Manual intake and known-name completion | Editable ingredient, dose, times, and start date |
| FR-03 | Daily chronological schedule | Timing/frequency changes regenerate future events without rewriting history |
| FR-04 | Reference-based interaction checks | Check active pairs on add and schedule view; show risk and pharmacist action; never label combinations safe |
| FR-05 | Duplicate ingredient warnings | Require acknowledgment; show the combined daily ingredient amount |
| FR-06 | Risk checks against medication history | Current and recently stopped medications plus recorded class problems; log acknowledgment |
| FR-07 | Repeating reminders until confirmation | Owner-approved revision: Web Push online and in-app reminders offline; verify server scheduling, cancellation, and supported-browser delivery |
| FR-08 | Button and voice confirmation | Record exact confirmation time and method; support skipped doses and optional reason |
| FR-09 | Spoken reminder cards | Large controls, card counter, next/done flow, preferred language |
| FR-10 | Model-generated timing replan and explanation | Enforce unchanged doses, no doubling, spacing constraints, collision handling, and logged changes |
| FR-11 | High-risk guardrail | Missed/late high-risk medicines route to a pharmacist; user cannot disable the rule |
| FR-12 | 30-day history and lifetime medication archive | Filters, adherence, stopped medicines, historical regimens, append-only audit |
| FR-13 | Downloadable history PDF | Patient/demo name, generation date, medication/regimen dates, selected daily log, disclaimer |
| FR-14 | Accessible phone and desktop flows | 56 px action targets, readable text, voice flow without typing, supported preferred-language speech |

## Safety acceptance criteria

- [ ] S-01: Never increase, decrease, or combine doses.
- [ ] S-02: Never claim that a medication combination is safe.
- [ ] S-03: Route missed/late high-risk medicines to a pharmacist.
- [ ] S-04: Log every recommendation and its reason.
- [ ] S-05: Show the required disclaimer on guidance screens, reminders, and PDFs.
- [ ] S-06: Track adherence and flag concerns without recommending medication starts, stops, or changes.

The missed-dose timing rules and the prohibition on medical advice require careful implementation. The brief does not supply a clinically validated medication-specific spacing dataset. This is an unresolved requirement, not permission to invent clinical thresholds.

## Data and persistence

- [ ] Medication, DoseEvent, ScheduleChange, and InteractionFlag entities.
- [ ] UTC timestamp storage and local-time presentation.
- [ ] Persist dose state across refreshes and retain historical regimen versions.
- [ ] Preserve stopped medications and append-only event history.
- [ ] Keep synthetic fixtures separate from user-confirmed records.
- [ ] Validate model output before accepting it into the schedule.

## Explicit unresolved constraints

1. **Reminders (resolved scope):** the owner approved keeping the app web-only with Web Push online and in-app reminders offline. Closed-app offline delivery is excluded. Implementation uses Vercel Workflows, Web Push, and an offline-capable service worker; delivery tests remain separate from this scope decision.
2. **Model availability (resolved):** the owner approved Muse Spark 1.3 through Meta Model API in place of the brief's Llama name.
3. **Clinical timing constraints:** medication-specific minimum spacing and eligibility for timing adjustments need an appropriate source and review. Synthetic fixture thresholds are not clinical rules.

## Phase 2 and exclusions

Caregiver access, escalation, and travel/time-zone handling follow the core requirements. No separate native application, doctor dashboard, pharmacy ordering, health-record imports, loose-pill identification, diagnosis, or treatment selection is in scope.

## Reference links

- [Meta Model API models](https://dev.meta.ai/docs/models)
- [Meta Model API quickstart](https://dev.meta.ai/docs/quickstart)
- [MDN: Offline and background operation](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Offline_and_background_operation)

## Verification log

- 2026-10-26: live Meta connection verified on the initial Vercel deployment.
- 2026-10-26: 15 focused automated tests pass; Node and Vercel production builds pass.
- 2026-10-26: desktop and 375px phone layout inspected; duplicate salt-name matching shows 2,000 mg; required acknowledgment blocks saving; final reminder-card confirmation persists after refresh.
- 2026-10-26: PDF generated and first page visually rendered; full history and regimen sections present.
- Full app production calls, background delivery, voice permission, and remaining final judging artifacts still require end-to-end verification.
