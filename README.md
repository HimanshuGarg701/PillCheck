# PillCheck for iOS

A native SwiftUI medication schedule companion with medication history and AI-assisted reviews. The iOS app and its Meta API backend live in this public repository.

[Public source](https://github.com/HimanshuGarg701/PillCheck) · [Requirements and verification](docs/requirements.md) · [Architecture](docs/architecture.md)

> Informational only, not medical advice. Confirm with your doctor or pharmacist.

## Run the iOS app

Requires Xcode with an iOS 17 or newer SDK. Development verification uses Xcode 26.0.1 and the iPhone 17 Pro simulator.

1. Open `ios/PillCheck.xcodeproj` in Xcode.
2. Select the **PillCheck** scheme and an iPhone simulator.
3. Press **Run**. No signing account or API key is needed for the simulator.

For a physical iPhone, connect and unlock it, select your own team under **Signing & Capabilities**, and choose that device in Xcode. The repository does not contain a signing identity or provisioning profile. Device signing, installation, and notification behavior after an actual phone restart still need verification.

The app starts with a sample profile for Alex Morgan, three medicines, and 30 days of sample history. Records persist in the app's Documents directory. An app update preserves them; uninstalling the app removes local data. Export records before uninstalling.

## Use the app

- **Today:** review grouped reminder cards, then confirm the group on its final card. Confirmations record an already-taken dose at the current time. Skipped doses can include a reason.
- **Add medicine:** photograph or import a label, paste its text, or enter medicine details manually. Three optional sample labels are available under **Try a sample label**. Review is mandatory. When entering a medicine manually, typing its name automatically identifies the active ingredient using Meta and NLM RxNorm. The ingredient appears for confirmation; manual entry is available for unresolved names or corrections. An AI review compares the new medicine with the active and recently stopped list, using U.S. RxNorm ingredient identities and retrieved label references. Review findings require acknowledgment.
- **Medicines:** use **AI interactions & timing** to review a saved medicine against the rest of the list, inspect ingredient overlap and source-linked findings, and view historical review snapshots. **Pause schedule** suspends that medicine's reminders; **Resume schedule** restores future doses at the recorded times without backfilling the pause. **Stop schedule** moves the record to history and cancels pending reminders. Earlier medication versions, dose records, and the audit trail remain available. Paused medicines still participate in interaction checks.
- **History:** filter dates and medicines, inspect adherence, and export a native PDF through the iOS share sheet.
- **Preferences:** choose English, Spanish, or Hindi for speech; enable local notifications; export all records as JSON; or expand **Sample medicines & previews** to explore check-ins at another time. Reminder previews pause notifications.

Medicine entry defaults to pills. Enter the dose in one field, such as `1 tablet` or `2 capsules`; there is no separate quantity field or high-risk toggle. Automatic high-risk checks remain active. Turn on **Liquid medicine** at the top of the form to enter the prescribed amount in mL and copy the bottle strength, such as `250 mg / 5 mL`. Reminders and exports retain the mL dose and bottle concentration.

The late-dose replan workflow is limited to the seeded metformin scenario. Its 10-hour spacing belongs to that sample schedule and is not clinical guidance. The separate AI medication review can offer a pharmacist-review timing draft for the supported label-spacing rule described below. Quantities never change through either workflow.

## Local reminders

After permission is granted, iOS schedules notifications on the device. Alerts occur at the recorded time, after 15 minutes, then every 30 minutes until confirmation, skipping, or the selected window ends. Confirming or changing a record reconciles queued alerts. Lock-screen messages omit medicine names.

Tapping a notification opens its medication cards. Opening the app while a dose is due also opens the cards, and foreground notifications do the same. Cards wait for an open form or review to close. Dismissing a card leaves the dose unconfirmed without reopening it on every timer tick. Review simultaneous medicines with **Next medicine**, then tap **Done — all already taken** or **Confirm by voice** and say **Done** on the final card. Voice input starts only when requested and requires microphone/speech permission and available on-device recognition.

The test notification in Preferences opens a labeled preview of the next unconfirmed group. **Done — finish preview** checks the interaction without changing dose history.

The app queues at most 60 dose alerts and displays the scheduled-through date. Opening it replenishes that queue. A daily generic reminder asks the user to reopen the app when the queue is limited. This is a finite coverage window, not an unlimited guarantee of offline reminders. Sound and presentation depend on iOS notification and Focus settings. Real-device restart and offline delivery remain to be tested.

## Meta backend

The owner approved **Muse Spark 1.3 through Meta Model API**. The app sends selected label data and limited reminder/replan data to the backend at `https://pillcheck-zeta.vercel.app/api/ai`. `MODEL_API_KEY` remains on Vercel; no credential is bundled in the iOS app.

The previous browser application has been retired. The Vercel root now identifies the iOS backend, and the retirement service worker removes the previous PWA cache and push subscription without erasing browser records. The earlier implementation remains available in Git history at `07551df`.

A live Muse Spark 1.3 medication review completed successfully in the iOS Simulator on October 27, 2026, identifying the shared metformin ingredient in Glucophage and displaying cited findings. Earlier scan, speech, and connection checks encountered `404: model_not_found`; those individual workflows have not been reverified successfully. The server retries provider failures within a bounded timeout, then reports an incomplete review without fabricating a model result. Manual entry and local medication workflows remain available.

For backend development, use Node 22 or newer and pnpm. Copy `.env.example` to `.env.local` and supply your own server credential. Never commit it.

```sh
pnpm install
pnpm dev
pnpm test
pnpm build
```

`MODEL_ID` defaults to `muse-spark-1.3`. Requests use Meta's `https://api.meta.ai/v1/responses` endpoint. Pushes to `main` deploy the backend through the existing Vercel integration.


## AI interactions, brand duplicates, and timing

The Meta operation `review` checks a candidate against every supplied active or recently stopped medicine (up to 20, without silent truncation). It looks for ingredient overlap under different brands and potential interactions. NLM RxNorm supplies ingredient identities, including ingredients within combination products. Label references come from openFDA and link to DailyMed. Unknown brands, ingredient mismatches, missing labels, and shortened excerpts remain visible limitations.

The model must return a finding for every comparison and cite actual supplied passages for interaction claims. The server rejects invented citations, erased deterministic warnings, safety guarantees, and unsupported timing drafts. A failed Meta call returns **AI review incomplete**, alongside clearly distinguished reference-only findings. Recording an existing prescription remains possible after explicit acknowledgment; it is not safety approval.

For scheduling, the AI may propose a **draft for pharmacist review** only when the server has an explicit spacing rule and the validator accepts it. Initial validated coverage is **oral levothyroxine / calcium carbonate, at least four hours apart**, based on [DailyMed prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=52a07ade-4098-477d-874e-dd692667041e). The first implementation limits drafts to a once-daily candidate, keeps all other times and dose amounts fixed, checks separation across midnight, and blocks drafts with duplicates, high-risk medicines, missing reference coverage, or unresolved other interactions. Drafts can be shared for review and never automatically alter the prescription. Meal instructions, formulation, clinical monitoring, and interactions that cannot be solved by spacing still need pharmacist review.

Names are sent to U.S. reference services; medication details and relevant reference excerpts are sent through the backend to Meta. The patient's name and dose history are excluded. Reviews saved with a prescription are retained as dated snapshots and must be rerun after medication changes. FDA explicitly says [not to rely on openFDA for medical-care decisions](https://open.fda.gov/apis/drug/label/).

## Native verification

```sh
swift test --package-path ios --scratch-path tmp/swift-build
xcodebuild -project ios/PillCheck.xcodeproj -scheme PillCheck \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath tmp/ios-build CODE_SIGNING_ALLOWED=NO build
```

The core test suite covers duplicate totals, high-risk protection, atomic confirmation, timing validation, history-preserving regimen changes, pause/resume/stop, date rollover, notification cadence/cancellation, persistent record round trips, and recoverable AI transport errors. The backend suite checks request validation, Meta integration, errors, and matching safety boundaries.

Offline interaction flags cover a curated metformin/cimetidine pair. The new AI review examines retrieved U.S. ingredient label excerpts for other pairs, but this is not a comprehensive clinical interaction database. No flag establishes safety. The app has no account, cloud history sync, caregiver escalation, or travel-time-zone workflow. Submission, distribution, and video work are outside the current iOS scope.
