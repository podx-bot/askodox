# ASKODOX Agent Instructions

## Mandatory startup
Before changing ASKODOX:
1. Read `ASKODOX_PROJECT_MEMORY.md`.
2. Read current GitHub `main` and verify the latest merged PR/build. Code on current main is the source of truth.
3. Reconcile memory with current code. If memory conflicts with code, update the memory; never blindly restore old behavior.
4. Inspect existing implementations before adding new ones. Reuse working architecture and avoid duplicate category-specific paths.

## Product rules
- ASKODOX is a universal AI/local-commerce assistant, not an ecommerce-only app.
- Keep flows category-agnostic across products, used/refurbished/surplus, sellers, services, surveys, jobs, travel, BFSI, local discovery, affiliate/online fallback, and future categories.
- Conversation should feel like one continuous assistant: text, voice, camera/photos/files, vision, results, actions and follow-ups share context.
- Results must not appear before required information is gathered.
- Contact details are released only after the seller/provider accepts the relevant request/deal.
- Prefer local matching; use truthful online/affiliate fallback when local supply is unavailable/thin.
- Never claim live availability, prices, verification or successful actions without evidence.
- Never expose or store secrets, tokens, passwords, API keys, OTPs, card/Aadhaar/PAN data in project memory.

## Change discipline
- Do not rewrite stable systems merely for cleanup.
- Do not delete files/modules called duplicate/dead until references and runtime purpose are traced.
- Do not change signing/package/release identity, production config, DNS or secrets without explicit owner approval.
- Every behavioral fix needs regression tests and, for device-dependent flows, real-phone evidence.
- Keep production/staging/demo/mock paths clearly isolated.
- After each meaningful merged PR, update `ASKODOX_PROJECT_MEMORY.md` with verified changes, remaining issues, tests and next step.

## Current protected areas
Until evidence says otherwise, preserve the Decision Brain/search-ready gate, Sarvam segmentation/endpointing, Android MediaRecorder/MainActivity bridge, webhook/video layering, OASAT wiring, signing/package identity and Result Contract v2.

## Reporting
Clearly separate VERIFIED FACTS, OWNER/DEVICE EVIDENCE, HYPOTHESES and RECOMMENDATIONS. Never present a hypothesis as a root cause.
