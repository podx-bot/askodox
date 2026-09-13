# ASKODOX Point 1 Verification Evidence — 2026-09-13

Status: IN PROGRESS — reopened after live-device regression findings

## Scope
This checkpoint records verified evidence for the current ASKODOX master repo only: `podx-bot/askodox`.

## Point 1 — Core Identity
ASKODOX must behave as an Everyday AI Friend + Helping Mind + Decision Partner + Action Assistant. It must understand the user's actual request, preserve context, ask only relevant missing information, avoid forcing commerce on general requests, and route transactional needs to the correct domain without stale-category leakage.

## Previously verified evidence that still stands
- Backend GENERAL routing exists through the universal AI assistant.
- Same-language prompt behavior is covered by automated tests.
- ConversationOS memory/ledger infrastructure exists.
- In-app is the canonical core channel; WhatsApp remains support-only.
- Transactional requests can delegate to deterministic handlers.
- Flutter CI/release and signed APK publishing have passed on the latest verified release path.

## Live-device findings that invalidate the old GREEN decision
The previous VERIFIED GREEN decision is revoked because real-device testing found user-visible failures that automated tests did not catch.

1. GENERAL request card leakage — FIXED and live-verified
   - Request: `ఈ రోజు నా పనులు ప్లాన్ చేసుకోవడానికి సహాయం చేయి.`
   - Earlier failure: local provider/demo cards were shown for a general planning request.
   - Client routing guard was added and the updated APK was live-tested.
   - Current result: planning response appears without local provider/demo cards.

2. Conversation continuation — OPEN BUG
   - Follow-up: `అదే ప్లాన్ కొనసాగించు, ఇప్పుడు తర్వాత ఏం చేయాలి?`
   - Live result repeated essentially the same generic response instead of using prior context and giving the next useful step.
   - Point 1 cannot be GREEN until contextual continuation is corrected and live-verified.

3. Category switching / stale match state — OPEN BUG
   - Live testing showed an AC-repair request could temporarily display chicken seller results after a prior chicken flow, while a later AC test routed correctly.
   - Intent/category changes must clear or replace stale match state deterministically.

4. Job sub-intent specificity — OPEN / cross-point dependency
   - `job kavali` correctly routes to Jobs.
   - `delivery job kavali` was initially shown generic office/back-office jobs rather than delivery-specific jobs.
   - Delivery-job specific demo classification/matching has been added in the current fix batch, but requires CI + updated APK + live-device verification.
   - Full category depth ultimately belongs to Points 5/6/7, but Point 1 must at minimum avoid incorrect/stale routing during domain switching.

## Current retouch / re-audit gate
Point 1 must be rechecked end-to-end instead of trusting the old automated GREEN result.

Required retouch checklist:
1. GENERAL requests never force local-commerce/results cards.
2. General conversation gives a useful answer, not only a generic acknowledgement.
3. Follow-up turns use previous context and advance the conversation rather than repeat.
4. Same-language behavior remains correct.
5. Memory/context survives normal continuation and app/session restoration where applicable.
6. Intent switching clears stale deal/match state.
7. Transactional requests route to the correct top-level domain.
8. Closely related sub-intents do not silently fall back to unrelated results.
9. Assistant never falsely claims actions/research/bookings/messages completed when they were not.
10. In-app remains the core conversation channel.
11. Automated regression coverage includes the live bugs found by the owner.
12. Flutter tests + CI + signed release + in-app update publish must pass on the final Point-1 fix head.
13. A short live-device regression set must pass after the final update.

## Live regression set before GREEN
Minimum owner-device verification after the final Point-1 update:
- General planning request.
- General planning follow-up/continuation.
- Chicken → AC category switch.
- Job → delivery-job refinement.
- Parcel request.

Expected result: no repeated generic answers, no stale cards, no unrelated category results, and no forced commerce for general conversation.

## Completion decision
Point 1 is IN PROGRESS. The old VERIFIED GREEN statement is no longer valid. Point 2 must not be treated as unblocked by Point 1 until the above retouch checklist, CI/release, and final live-device regression pass.
