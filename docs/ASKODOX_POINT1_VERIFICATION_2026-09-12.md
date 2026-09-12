# ASKODOX Point 1 Verification Evidence — 2026-09-12

Status: VERIFIED EVIDENCE RECORDED; POINT 1 REMAINS IN PROGRESS

## Scope
This checkpoint records verified evidence for the current ASKODOX master repo only: `podx-bot/askodox`.

## Current master baseline
- Continuity/single-repo lock commit: `2d1f37f0d7015037b7bc8c3c900cff5cb654790b`.
- Flutter CI run #734 on that commit completed SUCCESS.
- Bootstrap Android Runner run #586 on that commit completed SUCCESS.

## WhatsApp support-only media audit
The active support-channel smoke gate verifies the following behavior:
- Normal WhatsApp text is intercepted by `WhatsAppSupportOnlyGate` before legacy job/lifecycle/general-AI routing.
- Audio messages are transcribed and routed back through `_process_user_text`, so the same support-only text gate protects voice/audio input.
- The active webhook does not import the image or document extractors, so image/document messages cannot currently enter legacy business flows through that webhook.
- `extract_location_messages()` intentionally returns an empty list while support attachment handling is not implemented, preventing historical WhatsApp location handlers from bypassing the support-only policy.
- In-app location behavior is unaffected by this WhatsApp-specific suppression.

Evidence files:
- `.github/workflows/whatsapp-support-channel-smoke.yml`
- `backend/app/api/routes/webhook.py`
- `backend/app/whatsapp/payload_parser.py`
- `backend/app/services/whatsapp_support_only_gate.py`

## What this closes
- Current CI/build verification for the latest master checkpoint is no longer pending.
- The immediate WhatsApp audio/image/document/location bypass audit is recorded with deterministic smoke assertions.

## What is still NOT GREEN
Point 1 must remain IN PROGRESS until real in-app end-to-end verification proves the friend-like decision loop through the actual app route.

Point 51 must remain IN PROGRESS until support Case ID persistence, admin/customer-care queue/history, support outcome sync, and E2E support escalation are implemented and verified.

## Next execution target
1. Verify the real in-app conversation E2E path: understand → remember → clarify only missing information → compare/advise → action/delegation → continue until done.
2. Record concrete pass/fail evidence rather than verbal completion.
3. Do not mark Point 1 VERIFIED GREEN until the master completion gate is satisfied.
