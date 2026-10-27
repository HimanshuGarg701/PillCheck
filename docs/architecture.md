# Architecture

## Browser

Vanilla JavaScript, semantic HTML, responsive CSS, and Vite. `domain.js` contains pure validation/schedule functions; `storage.js` handles versioned local records. `app.js` implements intake/review, daily cards, reminders, medication versions, history, and settings. `pdf.js` exports selected dose history using pdf-lib. All profile data is fictional.

Records include Medication, DoseEvent, ScheduleChange, InteractionFlag, and audit entries. Event times are stored as ISO UTC timestamps and displayed locally. Regimen changes archive the old medication version and cancel only its pending future events. Completed records are not rewritten. Device time-zone travel handling remains phase 2.

The service worker precaches app assets and sample labels. It never caches API responses. Offline, reviewed records, confirmations, history, PDFs, and in-app reminders work while the page is open. AI needs a network connection. Offline changes sync background-reminder cancellations when connectivity returns. The worker also receives completed-dose IDs to suppress already-recorded notifications locally.

## Meta

`POST /api/ai` accepts four narrowly scoped operations: scan, speak, replan, and connection. Calls are server-side only, with structured JSON response schemas. Extracted data always requires user review. The replan response must preserve quantities, event identities, local date, original order, and the synthetic minimum spacing; invalid responses do not alter schedules. High-risk medicines are rejected before a model call. No fixture text is substituted for a failed model response.

AI routes have same-origin checks, payload limits, timeouts, sanitized errors, and per-instance burst limits. These limits are not distributed spending protection; provider quotas and Vercel firewall rules are separate operational controls.

## Background reminders

The user opts into Push API permission. A subscription is sent to `/api/push/schedule` with a due timestamp and reminder window. A Vercel Workflow sleeps until due, sends a generic encrypted Web Push, then repeats at +15 minutes and every 30 minutes until the window ends. Opening the app schedules the next seven days. An opaque HMAC cancellation capability is returned for each run; a bare run ID cannot cancel a job. Confirming/skipping/archiving/replanning cancels affected runs. Provider 404/410 responses end an expired subscription's workflow.

The server allows only known HTTPS push-service hosts and validates subscription shape. No client-supplied arbitrary fetch endpoint is accepted. VAPID identity and cancellation capabilities use distinct HMAC purposes derived from the Vercel-only credential. Rotation changes the VAPID identity, so clients must subscribe again.

Delivery depends on OS/browser support, permission, and internet. iOS requires installation on the Home Screen. A phone/browser restart does not remove server jobs, but notification delivery is not guaranteed by the OS. Offline closed-app notification delivery is outside the owner-approved scope.

## Known boundaries

- One curated interaction pair; not a clinical interaction database.
- Model-driven timing adjustment is limited to the synthetic seeded scenario; no clinical minimum-spacing dataset was supplied.
- Voice recognition and available speech voices vary by browser; button controls and visible text remain usable.
- Records are device-local, without cross-device authentication/sync.
- PDF's built-in fonts cover Latin text; non-Latin record text currently appears as replacement characters. Preferred-language speech supports English, Spanish, and Hindi separately.
- Automated tests do not establish clinical safety or prove notification delivery across every phone OS.
