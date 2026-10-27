# PillCheck

A mobile-first medication schedule companion, demonstrated with fictional records.

**[Open the public demo](https://pillcheck-zeta.vercel.app/)** · **[Public source](https://github.com/HimanshuGarg701/PillCheck)**

**Track:** Indie Developer · **Theme:** Build for Your World

> Informational only, not medical advice. Confirm with your doctor or pharmacist.

## Try it

No login, camera, or patient information is needed. Alex Morgan is fictional. Three medications, today's schedule, and 30 days of synthetic history are ready on first visit.

1. Select **Add medicine** and a bundled label. Muse Spark 1.3 reads the actual image through Meta Model API; review its output before saving. Glucophage demonstrates a duplicate ingredient and combined daily amount; Cimetidine demonstrates a sourced interaction flag.
2. Select **Try a spoken reminder**. Meta generates its text; the browser reads it in the selected language. Review cards, then use the final Done button to record the group. Voice confirmation is optional and browser dependent.
3. Select **Explore a late dose** before confirming the morning metformin. Record the fictional 10 AM confirmation, then ask Meta for a timing-only proposal. Its 10-hour constraint belongs only to this synthetic scenario, **not to clinical metformin advice**. Other medicines require pharmacist review.
4. Open **History**, filter dates/medicines, and download the PDF. Updating or archiving a regimen retains old dose records and an audit trail.
5. In **Preferences**, enable in-app reminders or Web Push. In-app reminders use the adjustable practice clock. Background notifications use the real clock and require internet, notification permission, and browser/OS support.

## Scope and safety

This is a public hackathon demonstration, not a clinical service. Use synthetic labels only. Medication records stay in browser localStorage; selected label data is sent to Meta for extraction. Push subscriptions and generic reminder times are persisted by Vercel Workflows. Push payloads contain no medicine names.

The owner approved **Muse Spark 1.3 through Meta Model API** in place of the brief's original Llama name. The owner also approved **Web Push online + in-app reminders offline**, retaining the web-only scope. Closed-browser offline delivery and delivery after a phone restart without connectivity are not promised.

Interaction checking currently has one curated DailyMed pair: metformin/cimetidine. Absence of a flag does not establish safety. Ingredient matching normalizes common hydrochloride/HCl naming for the demo but is not a comprehensive drug terminology service. High-risk name/class matching blocks automated replanning. The app does not prescribe, choose treatment, or change dose quantities. Missing clinical spacing data is handled by pharmacist referral, not invented timing advice.

See [requirements and verification](docs/requirements.md), [architecture](docs/architecture.md), and [demo recording plan](docs/demo-script.md). A published YouTube demo and final submission review are still outstanding.

## Development

Requires Node 22 or newer and pnpm. Copy `.env.example` to `.env.local` and set `MODEL_API_KEY` locally; never commit it. The public demo's key lives only in Vercel environment variables.

```sh
pnpm install
pnpm dev
pnpm test
pnpm build
pnpm preview
```

Vite builds the browser app; Nitro provides server routes; Vercel Workflows persists and resumes reminder jobs. Pushes to `main` deploy through the Vercel GitHub integration. No separate account or paid reminder service is required by the implementation. Hosting/provider quotas still apply.

`MODEL_ID` defaults to `muse-spark-1.3`. The server endpoint is `https://api.meta.ai/v1/responses`. The API credential is never exposed in a browser bundle. VAPID and cancellation secrets are derived server-side with separate HMAC purposes from the configured server secret. Rotating that secret requires re-enabling Web Push on each browser.

## Verification

`pnpm test` checks output validation, dose immutability, duplicate totals, history preservation, high-risk guardrails, reference checks, push endpoint restrictions, and cancellation capabilities. The browser flow is checked at desktop and 375-pixel phone width. PDF output is rendered for visual inspection. Current end-to-end results and limits are maintained in the requirements checklist.
