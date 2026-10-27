# PillCheck

A medication adherence and schedule companion for older adults and their caregivers.

**Status: implementation in progress.** The live app and Meta Model API integration are not yet deployed or verified. This repository is public so judges can inspect the work as it develops.

**Track:** Indie Developer · **Theme:** Build for Your World

> Informational only, not medical advice. Confirm with your doctor or pharmacist.

## What we are building

One responsive web app, one repository, and one public Vercel URL. A user can upload a prescription label or enter medication details, review the extracted information, follow a daily schedule, confirm doses by touch or voice, and export medication history as a PDF.

Meta Model API calls are required for label extraction, proposed timing replans, and plain-language explanations. Synthetic sample labels make the real scan flow accessible to judges without a camera. Preloaded test data supports demonstrations; it does not replace live model integration.

The application must never change dose amounts, combine doses, claim a combination is safe, or decide missed-dose actions for high-risk medicines. The safety constraints and requirement status are tracked in [the implementation checklist](docs/requirements.md).

## Current setup

- Public source repository: [HimanshuGarg701/PillCheck](https://github.com/HimanshuGarg701/PillCheck)
- Hosting target: Vercel with GitHub deployment integration.
- Model provider: Meta Model API. The provided brief names Llama; the current account lists Muse models. Model selection is awaiting owner confirmation.
- Credentials: server-side environment variables only. Never commit keys, paste them into issues, or expose them in browser bundles.
- All submitted data, labels, screenshots, and video content must be synthetic.

There is no published live demo or demo video yet. Setup and run instructions will be added with the working application.

## Review approach

Safety invariants will be tested before the complete demo flow. A working public deployment, live model calls, phone and desktop checks, reminder persistence checks, and PDF verification are required before marking the project ready for judging. Features will be reported as complete only after verification.
