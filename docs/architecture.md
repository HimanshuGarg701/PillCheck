# Architecture

## Native application

`ios/PillCheck` is a SwiftUI app targeting iOS 17+. It uses only Apple frameworks; there are no third-party iOS runtime dependencies. The checked-in Xcode project opens directly. `scripts/generate-ios-project.py` can regenerate the project when files are added.

`Core/Models.swift`, `MedicationEngine.swift`, and `ReminderPlan.swift` also form the independent `PillCheckCore` Swift package test target. The app compiles those same files. Medication versions, DoseEvent records, ScheduleChange records, risk acknowledgments, and audit entries are Codable values with UTC timestamps.

`PillStore` applies changes to a copy, writes it atomically with iOS file protection, then publishes the saved state. Startup decoding failures preserve the original file and block further changes. There is no automatic reset or delete-history button. Regimen updates stop the earlier version, cancel pending future events, and create a new version without changing completed history. Day rollover generates missing events and classifies expired unconfirmed windows as missed.

Optional `Medication.schedulePauses` records pause and resume intervals without changing the medicine's active status for interaction checks. Pause cancels unconfirmed pending events and removes that medicine from the notification plan and automatic reminder cards. Resume restores only future pause-cancelled events, retaining existing timing changes; catch-up excludes paused intervals. Editing a paused regimen keeps its replacement paused. Stop archives the regimen and cancels all pending events. Completed and missed history is preserved. Older records without pause fields decode as before.

SwiftUI screens implement intake/review, grouped reminders, medicines, history, and preferences. Photo selection uses PhotosPicker, file import uses the native picker, and camera access is optional. Medical-name fields disable autocorrect. Form labels remain visible after entry. `HistoryPDF` uses UIKit's PDF renderer and system fonts; `UIActivityViewController` shares PDF and JSON exports.

`MedicineDraft` defaults to pill entry with one combined amount/unit field. Liquid entry uses a separate mL dose and a label concentration in mg / mL. Switching form keeps the two drafts separate and never reinterprets a pill count as a volume. `Medication.strengthVolumeMl` is an optional concentration denominator; older records decode without migration. Daily ingredient totals divide by that volume for liquids, while legacy mL records retain their original mg-per-mL interpretation. The scan schema and AI review payload preserve concentration and dose volume separately. Scans missing the concentration denominator require manual review rather than assuming it. Name/class checks and existing high-risk flags remain enforced without an intake toggle.

`SpeechService` uses AVSpeechSynthesizer for playback and SFSpeechRecognizer with on-device recognition required for confirmation. Permission is requested only when the user invokes voice control. Only a final exact Done/Next command or its supported Spanish/Hindi equivalent is accepted. Timeout and recognition failure preserve records. Buttons remain available.

Each listening attempt has a session identifier. Closing or changing cards, opening the skipped-dose dialog, or backgrounding the app invalidates that session before stopping recognition. Late permission callbacks and recognition results cannot resume a cancelled session or confirm a dose. Pending generated reminder text is also checked against the visible card before playback.

## Reminders

`ReminderPlanner` produces a chronological queue from recorded doses and the next 30 days of the regimen. It groups simultaneous doses and creates the required 0, 15, 45, 75… minute cadence within the configured window. It selects at most 60 requests, leaving room for a test notification and a daily generic queue-refresh prompt.

`LocalReminders` submits local calendar notifications to UNUserNotificationCenter. It serializes reconciliation so an older asynchronous update cannot cancel a newer queue. Completion, skipping, regimen changes, and timing changes reconcile pending and delivered alerts. Notification taps open review cards; they do not silently confirm medication. The pending coverage horizon is visible in Preferences.

`ReminderCardQueue` routes notification taps and foreground deliveries to unconfirmed records. It defers presentation until the app is active and other forms, review sheets, exports, or alerts have closed. On launch/foreground and periodic refresh, it automatically presents pending groups whose time has arrived and whose reminder window remains open. Already-presented doses are suppressed for the current foreground session; a later notification can request them again. Completed, cancelled, unknown, duplicate, and future identifiers are filtered. The test notification carries a preview flag; its Done action exits without calling the record-confirmation path.

Already-scheduled local notifications do not require a running application or network. The finite queue is replenished when the app opens; a daily generic prompt helps avoid silent exhaustion. iOS permission, Focus, power/device state, and physical restart behavior still require device verification. There is no server push workflow or APNs credential.

## Meta API

`POST /api/ai` supports identify, scan, speak, replan, review, and connection operations. Native URLSession requests omit browser Origin headers. The server retains browser same-origin checks when an Origin is provided, plus payload bounds, a per-instance burst limit, structured response schemas, a timeout, and sanitized errors. These are not distributed spending controls.

The Vercel-only credential calls Muse Spark 1.3 through Meta's Responses endpoint. Selected label images are resized locally and submitted as image input, never replaced with fixture text. Missing fields remain uncertain and require review. Failed requests do not create medicines or change schedules. Reminder text is cached locally by exact medicine, quantity, unit, and language for offline playback.

Timing proposals are limited to the preloaded metformin sample schedule. Both the backend and native engine require unchanged quantities and identities, original order, no earlier times, the same local date, and the sample spacing interval. High-risk detection blocks automatic proposals. Other medicines refer to a pharmacist; no clinical spacing data is invented.

The JavaScript server shares `shared/domain.js` with backend tests. Swift implements the matching client rules independently with its own tests. Neither validator relies on a model to determine arithmetic or accept schedule mutations.

## Medication review

`server/medication-review.mjs` validates a limited medicine-only input, resolves names with RxNorm, retrieves oral ingredient label references from openFDA, and builds the evidence supplied to Meta. Server-generated source IDs and URLs cannot be supplied by the client. The model must cover every pair and use exact supplied quotes for substantive interaction findings. Validation prevents the model from erasing reference flags or inventing sources. Resolution and retrieval failures are uncertainty, not a negative interaction check. Sources disclose ingredient-only matching and excerpt truncation.

The shared reference deadline is 12 seconds, duplicate lookups are coalesced within a request, and successful name-to-ingredient identities are cached for one day. The Meta call retains its bounded timeout and retries. The review route can return reference-only findings with `aiStatus: unavailable`; that is never labeled live AI success. The native client allows 60 seconds, matching the Vercel function limit.

`AITransport` translates offline, timeout, rate-limit, unavailable-service, and unreadable-response failures into recoverable messages. The saved-medicine review uses a SwiftUI lifecycle task keyed by a request ID. Cancel, dismissal, or a replacement request prevents the older task from publishing a result. A retry starts explicitly from the screen; review-only requests never write schedules. Preferences and review screens describe AI features without exposing the model name or a developer connection test.

Timing drafts are limited to the reviewed levothyroxine/calcium rule and a once-daily candidate. Validation checks all existing times using circular 24-hour distance, rejects duplicate/high-risk/uncertain combinations, and leaves quantities and existing medication times unchanged. Drafts are preview/share only; they do not write dose schedules. A medication edit invalidates the review, and a medication-list change prevents saving with an old review. Optional `medicationReviews` preserves backwards decoding compatibility. Saved snapshots remain historical and do not silently become current-list safety clearance.

## Retired browser client

The root HTML is a small migration notice. `/sw.js` replaces the prior PWA worker, removes PillCheck caches, unsubscribes legacy Web Push, and unregisters itself. Browser localStorage is preserved. Old browser code and push scheduling endpoints are removed; their history is recoverable in Git. Native records are independent of old browser records.

## Boundaries

- Preloaded sample records; one offline interaction pair, live U.S. label-excerpt review, and limited name/class matching. These do not form a comprehensive clinical interaction database.
- No cloud record sync, account recovery, caregiver escalation, or travel-time-zone management.
- Native UI is English; spoken reminders and explanations support English, Spanish, and Hindi, subject to available voices/on-device recognition.
- A 60-alert queue provides a visible finite coverage horizon, not indefinite offline operation.
- Provider routing errors can prevent live AI operations; the app reports them and preserves manual/local workflows.
- Tests verify software behavior, not clinical safety or reliable notification delivery on every physical iPhone.

## Product wording and sample data

The main screens use ordinary medicine, prescription, and history terminology. Sample labels and reminder previews are optional controls, with the latter grouped in Preferences. Sample label images are rendered from native SwiftUI text before the actual image is submitted to Meta. Historical sample entries remain identified as samples in history and PDF exports. Known legacy system labels are formatted for display without rewriting saved audit records. Spoken reminder cache keys are versioned so previously generated development wording is not replayed. Clinical limitations and pharmacist-review requirements remain explicit.

## Ingredient identification during manual entry

The native form debounces name entry by 900 ms and calls `identify` with the name alone. The server resolves a unique RxNorm identity, then asks Meta to verify the supplied name and ingredient set. The model cannot introduce, drop, or substitute reference ingredients. Broad brand matches with multiple ingredient possibilities require a more specific product name; specific combination products retain every ingredient. Unknown names and failed reference lookups never fall back to model memory. A provider failure can return an explicitly labeled reference-only match.

The ingredient is displayed as a reviewable result rather than a required blank field. Users can correct it or enter the label ingredient if lookup fails. Changing the medicine name clears the previous ingredient and invalidates its review. Cancelled requests, responses for older names, and responses arriving after a manual override cannot overwrite the current form. Strength, quantity, and schedule remain user-entered prescription details.
