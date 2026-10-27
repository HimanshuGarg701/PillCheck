# PillCheck — submission draft

**Track:** Indie Developer  
**Theme:** Build for Your World  
**Developer:** Himanshu Garg  
**Public app:** https://pillcheck-zeta.vercel.app/  
**Public repository:** https://github.com/HimanshuGarg701/PillCheck  
**Video:** [2:37 narrated walkthrough draft](media/pillcheck-demo-draft.mp4), with [captions](media/pillcheck-demo.vtt). Public YouTube upload is pending owner review/account selection.

## What it does

PillCheck helps people follow a recorded medication schedule and bring a clear history to a conversation with their pharmacist. The intended audience is older adults managing several prescriptions and the people who help them. A label photo becomes a reviewable medicine record; daily cards make confirmations visible; history and PDF export keep the record shareable.

The public demo uses a fictional Alex Morgan profile, three seeded medicines, three sample label images, and thirty days of synthetic dose history. It requires no login or camera. It runs as one responsive web app on Vercel, backed by one public GitHub repository.

## Why Meta matters

Muse Spark 1.3 through Meta Model API reads the actual label image or pasted text, preserving missing fields for review. It generates reminder language and a plain-language explanation of a timing-only adjustment in the bounded fictional scenario. These are real API calls, not canned label responses. The interface reports failures instead of inventing a successful result. Browser speech reads model-generated reminder text in the selected language.

## What makes the workflow useful

Review is part of intake. A second brand with the same active ingredient produces a combined daily amount and a required acknowledgment. A curated interaction reference provides a pharmacist action and its source. Confirmation records preserve the exact time and method. Updating or archiving a regimen keeps previous records. A visible practice clock makes reminder and late-dose behavior inspectable without waiting hours.

## Safety and current limits

This is a synthetic demonstration, not a clinical service. It never changes a dose quantity through AI, combines doses, or declares a combination safe. Known high-risk medicines are routed to pharmacist review. The interaction reference set is limited, and the replan's ten-hour spacing applies only to the seeded fictional example. Clinical deployment would require a validated medication knowledge base, clinical review, stronger privacy/security controls, and delivery testing across supported phones.

The owner approved Muse Spark 1.3 in place of the brief's original Llama model name, and Web Push online plus in-app reminders offline while retaining a web-only app. Notification delivery on a supported phone remains awaiting the owner's test. No clinical outcome, competitor-uniqueness, or population-impact statistic is claimed without supporting evidence.

Live production extraction, reminder generation, and the fictional timing replan have succeeded. The same Meta model has also returned intermittent `model_not_found` errors; bounded retries preserve the approved model and report persistent failures. The Cimetidine interaction screenshot in the walkthrough comes from manual review, because that sample's image request failed during testing.

> Informational only, not medical advice. Confirm with your doctor or pharmacist.
