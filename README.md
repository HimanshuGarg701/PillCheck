# PillCheck for iOS

A native SwiftUI medication schedule companion using fictional records. The iOS app and its Meta API backend live in this public repository.

[Public source](https://github.com/HimanshuGarg701/PillCheck) · [Requirements and verification](docs/requirements.md) · [Architecture](docs/architecture.md)

> Informational only, not medical advice. Confirm with your doctor or pharmacist.

## Run the iOS app

Requires Xcode with an iOS 17 or newer SDK. Development verification uses Xcode 26.0.1 and the iPhone 17 Pro simulator.

1. Open `ios/PillCheck.xcodeproj` in Xcode.
2. Select the **PillCheck** scheme and an iPhone simulator.
3. Press **Run**. No signing account or API key is needed for the simulator.

For a physical iPhone, connect and unlock it, select your own team under **Signing & Capabilities**, and choose that device in Xcode. The repository does not contain a signing identity or provisioning profile. Device signing, installation, and notification behavior after an actual phone restart still need verification.

The app starts with Alex Morgan's fictional profile, three medicines, and 30 days of sample history. Records persist in the app's Documents directory. An app update preserves them; uninstalling the app removes local data. Export records before uninstalling.

## Use the app

- **Today:** review grouped reminder cards, then confirm the group on its final card. Confirmations record an already-taken dose at the current time. Skipped doses can include a reason.
- **Add medicine:** use one of three bundled synthetic label images, import an image, paste label text, or enter fields manually. Review is mandatory. Recognized names can fill the active ingredient. Duplicate ingredients and known interaction flags require acknowledgment.
- **Medicines:** inspect the regimen and reference flags. Updating or archiving a prescription preserves earlier medication versions, dose records, and the audit trail.
- **History:** filter dates and medicines, inspect adherence, and export a native PDF through the iOS share sheet.
- **Preferences:** choose English, Spanish, or Hindi for speech; enable local notifications; export all records as JSON; or use the optional practice clock. Practice mode switches off real notifications.

Only the seeded metformin scenario permits a model-generated timing proposal. Its 10-hour spacing is a fictional fixture, not clinical guidance. High-risk medicines and other regimens require pharmacist review. Quantities never change through replanning.

## Local reminders

After permission is granted, iOS schedules notifications on the device. Alerts occur at the recorded time, after 15 minutes, then every 30 minutes until confirmation, skipping, or the selected window ends. Confirming or changing a record reconciles queued alerts. Lock-screen messages omit medicine names.

The app queues at most 60 dose alerts and displays the scheduled-through date. Opening it replenishes that queue. A daily generic reminder asks the user to reopen the app when the queue is limited. This is a finite coverage window, not an unlimited guarantee of offline reminders. Sound and presentation depend on iOS notification and Focus settings. Real-device restart and offline delivery remain to be tested.

## Meta backend

The owner approved **Muse Spark 1.3 through Meta Model API**. The app sends selected synthetic label data and limited reminder/replan data to the backend at `https://pillcheck-zeta.vercel.app/api/ai`. `MODEL_API_KEY` remains on Vercel; no credential is bundled in the iOS app.

The previous browser application has been retired. The Vercel root now identifies the iOS backend, and the retirement service worker removes the previous PWA cache and push subscription without erasing browser records. The earlier implementation remains available in Git history at `07551df`.

Meta has returned intermittent `404: model_not_found` responses for this approved model. Native verification on October 27 also encountered this error. The latest deployed connection diagnostic reported that this model was not listed for the configured server key, despite appearing in the account model catalog; the key’s project/model access needs resolution. The server retries within a bounded timeout, then reports failure. No model result is fabricated; manual entry and local medication workflows remain available.

For backend development, use Node 22 or newer and pnpm. Copy `.env.example` to `.env.local` and supply your own server credential. Never commit it.

```sh
pnpm install
pnpm dev
pnpm test
pnpm build
```

`MODEL_ID` defaults to `muse-spark-1.3`. Requests use Meta's `https://api.meta.ai/v1/responses` endpoint. Pushes to `main` deploy the backend through the existing Vercel integration.

## Native verification

```sh
swift test --package-path ios --scratch-path tmp/swift-build
xcodebuild -project ios/PillCheck.xcodeproj -scheme PillCheck \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath tmp/ios-build CODE_SIGNING_ALLOWED=NO build
```

The core test suite covers duplicate totals, high-risk protection, atomic confirmation, timing validation, history-preserving regimen changes, date rollover, notification cadence/cancellation, and persistent record round trips. The backend suite checks request validation, Meta integration, errors, and matching safety boundaries.

This is a synthetic-data prototype. The interaction reference set contains one curated metformin/cimetidine pair, not a comprehensive clinical database. No flag establishes safety. The app has no account, cloud history sync, caregiver escalation, or travel-time-zone workflow. Submission, distribution, and video work are outside the current iOS scope.
