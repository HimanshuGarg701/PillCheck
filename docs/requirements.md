# iOS requirements and verification

The original 12-page `pillcheck-requirements-garg.pdf` was reread for the native migration. Its functional requirements remain the reference. The owner's October 27 instruction explicitly replaces the web-only constraint with a native iOS app and excludes submission, distribution, and video work. The earlier approved Muse Spark 1.3 substitution remains in effect.

## Requirement mapping

| Requirement | Native implementation | Verification / limits |
| --- | --- | --- |
| FR-01 / FR-01A | Actual image or pasted-label extraction through Meta; three bundled synthetic labels; uncertain-field review; manual fallback | Native request/error handling checked. Provider returned `model_not_found` during iOS image and spoken-reminder checks; live success for those operations has not yet been reverified. |
| FR-02 | Manual review form, automatic name-to-ingredient identification, pills by default with a liquid toggle, combined pill dose or prescribed mL amount, persistent field labels | Native entry, form switching, and duplicate acknowledgment checked. |
| FR-03 | Chronological Today schedule; append-only regimen versions and completed history | Core tests cover new future events without backfilling earlier times. |
| FR-04 | Reference flags at intake and on the active schedule | Offline curated metformin/cimetidine flag plus AI pairwise review of retrieved U.S. label excerpts. Sources, unresolved identities, and incomplete checks are explicit; no “safe” outcome. |
| FR-05 | Duplicate ingredient acknowledgment with combined daily mg | Local combined-total checks remain; U.S. RxNorm identity now detects shared ingredients across brands and combination products before AI interpretation. |
| FR-06 | Active and recently stopped medicines plus recorded class concerns | Core tests cover a recently stopped interaction and class concern. |
| FR-07 | Native local notifications at dose time, +15 min, then every 30 min within window; missed-record catch-up | Cadence, queue bound, and confirmation cancellation tested. Finite queue is visible; physical offline/restart and sound delivery are still unverified. |
| FR-08 | Already-taken confirmation or skipped-with-reason record; exact saved timestamp and method | Group button confirmation checked in simulator; voice needs physical-device testing. |
| FR-09 | Large grouped cards with counter, Next, final Done, and spoken reminder | Simulator Next/final Done verified. Failed live speech generation is displayed without fake fallback. |
| FR-10 | Live model proposal and explanation with immutable quantities and validated schedule changes | Restricted to the seeded fictional 10-hour fixture. General clinical replanning is not implemented without pharmacist-approved spacing data. Invalid proposal tests pass. |
| FR-11 | Automatic high-risk name/class guards; no user-facing risk toggle | Client and server tests cover guards and preservation of existing high-risk flags; static pharmacist guidance supports selected speech language. |
| FR-12 | Thirty seeded days, retained regimen versions, filters, adherence, audit trail, protected local persistence | Core rollover and persistence tests plus simulator history checks. Uninstalling still removes device-local records. |
| FR-13 | Native PDF with patient, generated date, all regimens/start/end dates, filtered dose logs, and disclaimer | Ten-page native PDF rendered and inspected; corrected share sheet displays the PDF with Preview and Save to Files. |
| FR-14 | Dynamic Type, large primary actions, spoken English/Spanish/Hindi, optional on-device Done/Next | UI inspected at iPhone size. VoiceOver, extreme text sizes, and actual speech recognition still need device verification. |

## Safety interpretation

The brief does not supply a validated clinical interaction or spacing database. Its fictional schedule example is therefore not promoted to a general dosing rule. High-risk medicines and non-fixture regimens direct the user to a pharmacist. No automated decision advises starting, skipping, stopping, or changing a dose. Failed scans, rejected proposals, and incomplete voice recognition preserve records.

## Verification record — October 27, 2026

- Swift core tests: 11 checks for duplicates, high-risk detection, atomic confirmation, replan rejection/acceptance, versioned regimens, historical reference flags, rollover, notification planning, and Codable persistence.
- Node backend tests: 23 checks, including language validation and observed provider-routing retry behavior.
- Native builds passed for both iPhone Simulator (Debug) and generic physical iOS (Release, unsigned), using Xcode 26.0.1; deployment target iOS 17.
- Simulator: launch, grouped reminders, confirmation persistence across app update/relaunch, ingredient suggestion, required review, duplicate warning/acknowledgment, history, regimen versioning/archive, and PDF share sheet checked.
- Simulator testing found, corrected, and rechecked medical-name autocorrect and a blank PDF share-sheet state bug.
- Meta requests: earlier scan and speech checks returned `404: model_not_found`; their inputs and saved records were preserved. A subsequent live medication review completed with Muse Spark 1.3 in the iOS Simulator, identified the Glucophage/metformin overlap, displayed citations, and preserved uncertain interaction findings. Mocked API tests are separate from this live verification.
- Deployment verified: public GitHub main and Vercel production include the native migration; the web root serves only the iOS backend notice. The API remains configured with Muse Spark 1.3. The medication review endpoint completed successfully after earlier model-access failures; earlier scan/speech outcomes remain recorded separately.
- Still pending: physical signing/install, local alert delivery offline and after a physical restart, voice permissions/recognition, camera capture, and extended accessibility checks.

The current app can be run locally in Xcode without distributing it. No submission or video work is part of this migration.


## U.S. medication review extension

The owner requested AI checks for interactions with the existing list, potentially harmful co-timing, and the same active ingredient under different brands, and selected the United States market. The app now adds these checks during intake and exposes **AI interactions & timing** for each saved medicine. RxNorm identity retrieval and U.S. label retrieval were checked live with Glucophage/metformin and levothyroxine/calcium carbonate.

The first timing-rule coverage is the label-supported four-hour oral levothyroxine/calcium separation. Draft generation is restricted to a once-daily candidate, validated across midnight, and presented for pharmacist review without changing prescriptions. This does not solve every interaction or guarantee an absence of harm. Other unsupported timing conflicts remain pharmacist-review cases.

New tests reject omitted pairs, invented citations, downgraded duplicates, safety guarantees, unsupported timing proposals, and inadequate separation. They distinguish missing references and unavailable AI from completed checks and verify that older iOS records still decode with optional review snapshots. The live native review completed with Muse Spark 1.3; the ingredient-overlap result and its source links were inspected in the Simulator. Salt forms related through RxNorm are displayed as reference alternatives, not a confirmed package formulation.

A live production timing review also completed with Muse Spark 1.3 using two synthetic records initially set to 08:00. It flagged the levothyroxine/calcium spacing conflict and returned a 12:00 candidate draft that passed the four-hour validator while preserving the other medicine time. This was an endpoint test; it did not update any user prescription or Simulator record.

The native prescription form was also checked against production: a later AI response without adequate label evidence was rejected and shown as incomplete, while reference-only duplicate findings remained visible. Save stayed disabled until the explicit incomplete-check acknowledgment was selected. The form was then cancelled, leaving medication records unchanged.

## Manual ingredient identification — October 28, 2026

Typing a medicine name now starts automatic ingredient identification using Meta with server-retrieved RxNorm evidence. The iOS form displays the ingredient for review instead of requiring users to know it. Reference lookups were verified live for Glucophage, Advil, and the amlodipine/atorvastatin combination. Seven added backend tests cover exact matches, combinations, broad-brand ambiguity, outages, invalid input, and unsupported model output. Current automated results: 30 Node tests and 11 Swift tests passing; native Simulator and backend builds pass.

Native verification against production: entering Glucophage filled metformin with completed Meta verification. Changing names while a lookup was pending correctly ended with Tylenol/acetaminophen, without retaining the earlier ingredient. The correction control exposed an editable label-ingredient field. These were unsaved form checks; no medication or dose record was added.

## Notification-to-card flow — October 28, 2026

Due groups now open automatically when the app becomes active within their reminder window. Notification taps and foreground deliveries route to the corresponding unconfirmed cards. An open intake, review, export, or alert defers the cards until it closes. Dismissed cards do not reopen on each timer tick. Button and exact final voice confirmation retain the recorded timestamp/method and cancel the group's remaining alerts. Speech sessions are invalidated when leaving a card or backgrounding the app, so delayed results cannot confirm a record.

The existing test-notification control now opens a clearly labeled preview whose final Done does not write dose history. Six added core tests cover presentation timing, foreground/form deferral, duplicate and stale notification IDs, preview isolation, and rejection of partial or negated voice commands. All 17 Swift tests pass; the native Simulator Debug build succeeds.

Simulator verification: reminders are enabled with a two-hour window and the preview clock is off. Launch automatically opened the two due 08:00 cards. Next displayed the final Done and Confirm by voice actions. Closing the cards left today's taken count at zero and did not immediately reopen them. Backgrounding and reopening with an intake form open preserved the form; closing it then presented the due group. No dose confirmations or new medicine records were made during these checks. Native coordinate controls repeatedly failed with a window-availability error, preventing completion of the test-notification delivery/tap/preview check. Physical notification delivery, restart/offline behavior, and microphone recognition remain unverified.

## Simplified medicine entry — October 29, 2026

New manual entries default to pills. The High risk toggle and separate Quantity per dose field are removed. One Dose field records the pill amount and form, including multiple or fractional pills, without silently assuming one pill. A Liquid medicine toggle at the top replaces the pill fields with Bottle strength (mg / mL) and Amount per dose (mL). Each form retains its own draft values when switched. Existing high-risk flags and automatic recognition remain enforced.

Liquid records retain the concentration denominator separately from the prescribed volume. Daily ingredient totals, medicine cards, reminders, history exports, scan extraction, and AI review carry those units consistently. Older records continue to decode; no saved history migration is required. A scanned concentration alone does not establish a dose volume, and an incomplete concentration remains for review.

Validation: 25 Swift tests and 34 Node tests pass; iOS Simulator Debug and backend builds succeed. Simulator checks confirmed the initial pill mode, removal of both old controls, replacement with mL fields, and preservation of `100 mg / 2 capsules` and `250 mg / 5 mL / 7.5 mL per dose` drafts when switching forms. These were unsaved entry checks. Live Meta extraction of a liquid label was not exercised in this check; schema/prompt and response-validation behavior were tested with controlled responses.

## Schedule controls and AI review recovery — October 29, 2026

Medicines now offers Pause schedule, Resume schedule, and Stop schedule. Pausing preserves the record in interaction checks, cancels pending reminder events, and prevents automatic cards from reopening it. Resume schedules only future events; persisted pause intervals prevent catch-up from filling in paused days. Stop moves the record to history. Completed dose history is retained, including when editing a paused regimen. Muse/model branding and the connection-debug control have been removed from product screens; data-sharing explanations remain at the AI action.

The reported AI interactions & timing failure was not reproduced: an Amlodipine review completed on the earlier build, and a Metformin review completed on the updated build after cancelling and retrying. The updated review cancels requests when dismissed, rejects stale results, and handles offline, timeout, rate-limit, server, and malformed-response failures with a retryable message. The original failure remains unconfirmed pending reproduction details.

Validation: 38 Swift tests and 34 Node tests pass; iOS Simulator Debug build succeeds. Simulator pause/resume persisted successfully and left all 134 existing dose records and schedule-change entries identical afterward. The stop confirmation was inspected and cancelled; stop behavior is covered by core tests. The live review cancel/retry path returned a completed result. Physical-device notification cancellation and the original reported failure still need verification. Preferences wording was checked in source; simulator coordinate control could not select its tab.

## Native visual refresh — October 29, 2026

The app uses a blue/navy palette, SF system typography, white bordered cards, and semantic status colors. Today emphasizes the next scheduled time and recorded progress. Medicine cards group Edit/Pause controls beneath the AI review action. Text styles remain compatible with Dynamic Type; paired actions and history summaries stack at accessibility sizes. The implementation adds no fonts, images, dependencies, background tasks, or network calls. Medicine cards render lazily as the list scrolls.

Validation: the iOS Simulator Debug build and all 38 existing Swift tests pass. Today, Medicines, History, Preferences, intake, and the empty manual-entry form were inspected at the simulator's existing text size; no doses or medicine records were saved during these checks. Primary white-on-blue text measures 6.05:1 contrast and muted text on the screen background measures 5.23:1. Physical-device frame-rate profiling and extreme text-size verification remain outside this visual check.
