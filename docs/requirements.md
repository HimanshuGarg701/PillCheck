# Implementation checklist

This checklist translates the supplied PillCheck requirements brief into verification targets. Unchecked items are not complete. A scaffold or simulated response does not count as a verified integration.

## Platform and judging artifacts

- [x] Create a public repository in HimanshuGarg701.
- [x] Connect Vercel to this repository for automatic deployments.
- [x] Configure the Meta Model API credential only on the server.
- [x] Resolve the brief's Llama model name against current Meta account availability with the owner: Muse Spark 1.3 approved.
- [x] Deploy one responsive web app at a public HTTPS URL, with no login required by judges.
- [ ] Verify the full flow on phone and desktop, including an incognito session.
- [x] Preload 3–4 synthetic medications and a full daily schedule.
- [x] Bundle three synthetic label images covering ordinary intake, duplicate ingredient, and interaction scenarios.
- [x] Provide instant reminder and late-dose demo controls that exercise the implemented workflows.
- [ ] Record a self-contained demo of at most three minutes and publish its accessible YouTube link.
- [x] Prepare submission text naming the Indie Developer track and Build for Your World theme, the problem, audience, Meta tools, and why the models matter. See [submission draft](submission.md).
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

- [x] S-01: AI timing changes cannot increase, decrease, or combine doses; validated on both server and client.
- [x] S-02: Reference results never claim that a medication combination is safe.
- [x] S-03: Recognized missed/late high-risk medicines route to a pharmacist; the explicit user flag also blocks replanning.
- [x] S-04: Persist timing changes with before/after times and reasons; log failed replans and risk acknowledgments.
- [x] S-05: Show the required disclaimer on guidance screens, reminders, and PDFs.
- [x] S-06: Track adherence and flag concerns without recommending medication starts, stops, or quantity changes.

The missed-dose timing rules and the prohibition on medical advice require careful implementation. The brief does not supply a clinically validated medication-specific spacing dataset. This is an unresolved requirement, not permission to invent clinical thresholds.

## Data and persistence

- [x] Medication, DoseEvent, ScheduleChange, and InteractionFlag entities.
- [x] UTC timestamp storage and local-time presentation.
- [x] Persist dose state across refreshes and retain historical regimen versions.
- [x] Preserve stopped medications and append-only audit history.
- [x] Clearly mark this entire app as synthetic; newly reviewed entries record manual/model provenance. No real-patient mode is offered.
- [x] Validate model output before accepting it into the schedule.

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
- 2026-10-26: 18 focused automated tests pass; Vercel production build passes. The final tests cover confirmation and disabling while a background schedule request is still in flight.
- 2026-10-26: desktop (1280px) and phone (375px) layout inspected; no horizontal overflow observed. This is browser viewport testing, not physical-phone certification or an incognito check.
- 2026-10-26: live production image extraction succeeds for Metformin and Glucophage. Glucophage review shows the duplicate salt-name match and 2,000 mg combined amount; required acknowledgment blocks saving.
- 2026-10-26: live production reminder generation succeeds. The UI late-dose scenario records 10 AM, receives a live Meta proposal, moves the fictional evening event from 6 PM to 8 PM, and preserves the one-tablet quantity and audit reason.
- 2026-10-26: Cimetidine interaction warning verified using manual review. Its live image-extraction request returned provider errors; that specific sample's extraction is not marked verified.
- 2026-10-26: Meta intermittently returns `404 model_not_found` for the approved `muse-spark-1.3` model, interspersed with successful calls. The adapter retries the same model within a bounded timeout, then reports failure. No fallback provider, model, or fake successful response is substituted.
- 2026-10-26: final reminder-card confirmation persists after refresh. With the local origin server completely stopped, the service-worker-cached app reloads, displays a due in-app reminder, saves confirmation, and exports the updated PDF.
- 2026-10-26: browser-downloaded PDF parsed across eight pages, including the offline confirmation. A generated PDF's first page was visually rendered and inspected; history and regimen sections are present.
- 2026-10-26: production push public-key route and service-worker assets respond successfully. Client schedule/cancel races and server subscription/cancellation validation are tested. Physical Web Push delivery remains deferred at the owner's request ("I'll test notifications later").
- 2026-10-26: a 2:37 narrated walkthrough draft uses actual app captures, including a clearly identified manual interaction check. Public YouTube publication remains pending.

Remaining acceptance checks: supported-phone notification delivery, microphone/voice confirmation and multilingual speech on real devices, incognito flow, the final YouTube link and submission review. Clinical timing rules and comprehensive interaction coverage remain outside the validated demonstration.
