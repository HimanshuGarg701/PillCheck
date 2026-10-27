# iOS requirements and verification

The original 12-page `pillcheck-requirements-garg.pdf` was reread for the native migration. Its functional requirements remain the reference. The owner's October 27 instruction explicitly replaces the web-only constraint with a native iOS app and excludes submission, distribution, and video work. The earlier approved Muse Spark 1.3 substitution remains in effect.

## Requirement mapping

| Requirement | Native implementation | Verification / limits |
| --- | --- | --- |
| FR-01 / FR-01A | Actual image or pasted-label extraction through Meta; three bundled synthetic labels; uncertain-field review; manual fallback | Native request/error handling checked. Provider returned `model_not_found` during iOS image and spoken-reminder checks; live success is not claimed for this run. |
| FR-02 | Manual review form, known-name ingredient suggestions, persistent field labels, no medical-name autocorrect | Native manual entry and duplicate acknowledgment checked. |
| FR-03 | Chronological Today schedule; append-only regimen versions and completed history | Core tests cover new future events without backfilling earlier times. |
| FR-04 | Reference flags at intake and on the active schedule | One curated DailyMed metformin/cimetidine pair only; no “safe” outcome. |
| FR-05 | Duplicate ingredient acknowledgment with combined daily mg | Core tests and simulator form verified a 2,000 mg fictional combined total. |
| FR-06 | Active and recently stopped medicines plus recorded class concerns | Core tests cover a recently stopped interaction and class concern. |
| FR-07 | Native local notifications at dose time, +15 min, then every 30 min within window; missed-record catch-up | Cadence, queue bound, and confirmation cancellation tested. Finite queue is visible; physical offline/restart and sound delivery are still unverified. |
| FR-08 | Already-taken confirmation or skipped-with-reason record; exact saved timestamp and method | Group button confirmation checked in simulator; voice needs physical-device testing. |
| FR-09 | Large grouped cards with counter, Next, final Done, and spoken reminder | Simulator Next/final Done verified. Failed live speech generation is displayed without fake fallback. |
| FR-10 | Live model proposal and explanation with immutable quantities and validated schedule changes | Restricted to the seeded fictional 10-hour fixture. General clinical replanning is not implemented without pharmacist-approved spacing data. Invalid proposal tests pass. |
| FR-11 | Automatic high-risk name/class guards cannot be disabled by the form switch | Client and server tests cover guards; static pharmacist guidance supports selected speech language. |
| FR-12 | Thirty seeded days, retained regimen versions, filters, adherence, audit trail, protected local persistence | Core rollover and persistence tests plus simulator history checks. Uninstalling still removes device-local records. |
| FR-13 | Native PDF with patient, generated date, all regimens/start/end dates, filtered dose logs, and disclaimer | Ten-page native PDF rendered and inspected; corrected share sheet displays the PDF with Preview and Save to Files. |
| FR-14 | Dynamic Type, large primary actions, spoken English/Spanish/Hindi, optional on-device Done/Next | UI inspected at iPhone size. VoiceOver, extreme text sizes, and actual speech recognition still need device verification. |

## Safety interpretation

The brief does not supply a validated clinical interaction or spacing database. Its fictional schedule example is therefore not promoted to a general dosing rule. High-risk medicines and non-fixture regimens direct the user to a pharmacist. No automated decision advises starting, skipping, stopping, or changing a dose. Failed scans, rejected proposals, and incomplete voice recognition preserve records.

## Verification record — October 27, 2026

- Swift core tests: 9 checks for duplicates, high-risk detection, atomic confirmation, replan rejection/acceptance, versioned regimens, historical reference flags, rollover, notification planning, and Codable persistence.
- Node backend tests: 15 checks, including language validation and observed provider-routing retry behavior.
- Native builds passed for both iPhone Simulator (Debug) and generic physical iOS (Release, unsigned), using Xcode 26.0.1; deployment target iOS 17.
- Simulator: launch, grouped reminders, confirmation persistence across app update/relaunch, ingredient suggestion, required review, duplicate warning/acknowledgment, history, regimen versioning/archive, and PDF share sheet checked.
- Simulator testing found, corrected, and rechecked medical-name autocorrect and a blank PDF share-sheet state bug.
- Meta requests: provider returned `404: model_not_found`; the app retained the image/input and saved records and showed actionable errors. Do not treat mocked automated API tests as live model verification.
- Deployment verified: public GitHub main and Vercel production include the native migration; the web root serves only the iOS backend notice. The API remains configured with Muse Spark 1.3. Its latest connection diagnostic reports the model is not listed for the server key, so project/model access remains an external blocker.
- Still pending: physical signing/install, local alert delivery offline and after a physical restart, voice permissions/recognition, camera capture, and extended accessibility checks.

The current app can be run locally in Xcode without distributing it. No submission or video work is part of this migration.
