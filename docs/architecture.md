# Architecture

## Native application

`ios/PillCheck` is a SwiftUI app targeting iOS 17+. It uses only Apple frameworks; there are no third-party iOS runtime dependencies. The checked-in Xcode project opens directly. `scripts/generate-ios-project.py` can regenerate the project when files are added.

`Core/Models.swift`, `MedicationEngine.swift`, and `ReminderPlan.swift` also form the independent `PillCheckCore` Swift package test target. The app compiles those same files. Medication versions, DoseEvent records, ScheduleChange records, risk acknowledgments, and audit entries are Codable values with UTC timestamps.

`PillStore` applies changes to a copy, writes it atomically with iOS file protection, then publishes the saved state. Startup decoding failures preserve the original file and block further changes. There is no automatic reset or delete-history button. Regimen updates stop the earlier version, cancel pending future events, and create a new version without changing completed history. Day rollover generates missing events and classifies expired unconfirmed windows as missed.

SwiftUI screens implement intake/review, grouped reminders, medicines, history, and preferences. Photo selection uses PhotosPicker, file import uses the native picker, and camera access is optional. Medical-name fields disable autocorrect. Form labels remain visible after entry. `HistoryPDF` uses UIKit's PDF renderer and system fonts; `UIActivityViewController` shares PDF and JSON exports.

`SpeechService` uses AVSpeechSynthesizer for playback and SFSpeechRecognizer with on-device recognition required for confirmation. Permission is requested only when the user invokes voice control. Only a final exact Done/Next command or its supported Spanish/Hindi equivalent is accepted. Timeout and recognition failure preserve records. Buttons remain available.

## Reminders

`ReminderPlanner` produces a chronological queue from recorded doses and the next 30 days of the regimen. It groups simultaneous doses and creates the required 0, 15, 45, 75… minute cadence within the configured window. It selects at most 60 requests, leaving room for a test notification and a daily generic queue-refresh prompt.

`LocalReminders` submits local calendar notifications to UNUserNotificationCenter. It serializes reconciliation so an older asynchronous update cannot cancel a newer queue. Completion, skipping, regimen changes, and timing changes reconcile pending and delivered alerts. Notification taps open review cards; they do not silently confirm medication. The pending coverage horizon is visible in Preferences.

Already-scheduled local notifications do not require a running application or network. The finite queue is replenished when the app opens; a daily generic prompt helps avoid silent exhaustion. iOS permission, Focus, power/device state, and physical restart behavior still require device verification. There is no server push workflow or APNs credential.

## Meta API

`POST /api/ai` supports scan, speak, replan, and connection operations. Native URLSession requests omit browser Origin headers. The server retains browser same-origin checks when an Origin is provided, plus payload bounds, a per-instance burst limit, structured response schemas, a timeout, and sanitized errors. These are not distributed spending controls.

The Vercel-only credential calls Muse Spark 1.3 through Meta's Responses endpoint. Selected label images are resized locally and submitted as image input, never replaced with fixture text. Missing fields remain uncertain and require review. Failed requests do not create medicines or change schedules. Reminder text is cached locally by exact medicine, quantity, unit, and language for offline playback.

Timing proposals are limited to the explicitly seeded fictional metformin scenario. Both the backend and native engine require unchanged quantities and identities, original order, no earlier times, the same local date, and the fictional spacing. High-risk detection blocks automatic proposals. Other medicines refer to a pharmacist; no clinical spacing data is invented.

The JavaScript server shares `shared/domain.js` with backend tests. Swift implements the matching client rules independently with its own tests. Neither validator relies on a model to determine arithmetic or accept schedule mutations.

## Retired browser client

The root HTML is a small migration notice. `/sw.js` replaces the prior PWA worker, removes PillCheck caches, unsubscribes legacy Web Push, and unregisters itself. Browser localStorage is preserved. Old browser code and push scheduling endpoints are removed; their history is recoverable in Git. Native records are independent of old browser records.

## Boundaries

- Synthetic records only; one curated interaction pair and limited name/class matching.
- No cloud record sync, account recovery, caregiver escalation, or travel-time-zone management.
- Native UI is English; spoken reminders and explanations support English, Spanish, and Hindi, subject to available voices/on-device recognition.
- A 60-alert queue provides a visible finite coverage horizon, not indefinite offline operation.
- Provider routing errors can prevent live AI operations; the app reports them and preserves manual/local workflows.
- Tests verify software behavior, not clinical safety or reliable notification delivery on every physical iPhone.
