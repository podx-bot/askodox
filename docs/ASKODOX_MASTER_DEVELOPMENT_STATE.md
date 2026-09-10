# ASKODOX — Master Development State

> Source of truth for development continuity. Read this file before starting or resuming ASKODOX work. Do not rely on chat memory alone.

## Identity lock
- Official brand name: **ASKODOX**.
- Do not rename the product to PODX, Daxodex, Bordex, or another historical/internal name in status updates, UI, demo copy, or new implementation unless the owner explicitly approves a rename.
- Active repository: `podx-bot/askodox`.
- Flutter package imports currently use `package:podx/...`; package namespace is technical legacy and is not the customer-facing brand.

## Product lock
ASKODOX is a universal **Local Commerce / Lead Generation** platform, not a conventional ecommerce marketplace and not commission-first.

Core positioning:
- Find Local, Buy Local.
- Buyers, sellers, service providers and other local roles connect directly.
- Business/customer/payment relationship remains direct wherever possible.
- Natural AI advisor rather than a basic Q&A/search interface.

## Registration / matching lock
1. Language.
2. Mobile OTP with fallback.
3. Name.
4. Role selection.
5. User explains what they need or offer in natural language.
6. Dynamic category/role-specific questions.
7. Local matching using category, opposite-side role, location/radius and relevant structured requirements.
8. Admin/no-match recovery when a valid match is unavailable.

Rules:
- Do not use one generic questionnaire for all categories.
- Prevent wrong-category suggestions.
- Prevent same-side matches.
- Prevent candidates outside the allowed radius.
- Contact details are shared only after the required acceptance/chat gate.
- Reviews are allowed after a completed deal.

## UI lock
- AI-app feel, not ecommerce-store appearance.
- Bright/white, readable visual direction.
- One primary home/chat experience; avoid unnecessary second-page navigation.
- Keep conversation/history/results accessible from Home.
- Robot/voice interaction states: listening, thinking, speaking.
- Compact location + language controls.
- More chat space; seller/request flows open only when needed.
- Influencer product video/recommendation/review support is part of the approved direction.

## Voice / language lock
- Multilingual architecture; Telugu is the preferred current demo/test language.
- Locale must persist across navigation and relaunch.
- Voice preference: Automatic / Male / Female; never infer user gender.
- STT/TTS must stay synchronized with selected app language.

## Investor demo priority lock
Investor demo readiness has priority over side-feature expansion.

Required demo story:
`Buyer request → category/location match → seller accept → chat → deal/order → sandbox payment → invoice/bill → completion → review`

Also demonstrate at least one Service Provider flow.

Execution order:
1. Pending core work.
2. Live Matching E2E.
3. Full dummy/sandbox profiles.
4. Sandbox payment/billing.
5. Admin TEST/LIVE switch.
6. Full investor E2E demo verification.

Do not ask the owner to repeatedly update/install APKs during intermediate blocks. Complete the sandbox/demo blockers first, then use the latest verified build for a consolidated mobile E2E test.

## Sandbox architecture lock
- Reuse the existing Party A / Party B concept; do not create a duplicate matching system.
- Party A = request/need side.
- Party B = offer side.
- Sandbox should behave production-like while using no real money.
- Reuse existing matching, communication, deal lifecycle and monetization architecture where possible.
- Sandbox payment states should cover success, failure, pending, refund and cancellation as applicable.
- Billing must be configurable rather than hard-coded where practical.
- Provide a master `TEST/SANDBOX ↔ LIVE` environment control.
- Sandbox/test records must never leak into LIVE results.
- Keep reusable sandbox fixtures for regression testing.

## Requirement / complaint / rejection decision workflow — LOCKED
Every owner requirement, complaint, rejected implementation, correction, and final approval is part of the living ASKODOX architecture and must not be treated as disposable chat context.

For each meaningful decision, follow this sequence:
1. Capture the requirement/complaint/rejection precisely.
2. Check the existing architecture and prior locked decisions before changing code.
3. Record why the old behavior/design was rejected when relevant.
4. Define the final approved rule/flow and the behavior that must not recur.
5. Implement by extending/reusing existing architecture; avoid duplicate systems.
6. Add or update tests/regression gates where the decision can be tested.
7. Verify CI/runtime as applicable before marking GREEN.
8. Update this Master Development State after the verified block so a later chat can resume without repeating or contradicting the decision.

Anti-repeat rules:
- A rejected UI/flow must not silently return in a later implementation.
- A completed feature must not be rebuilt merely because chat context was lost.
- A pending feature must retain its dependency and next-action context.
- If a new request conflicts with a locked decision, identify the conflict before implementation rather than guessing.
- Owner corrections override earlier assumptions; preserve the correction as the new source-of-truth rule.
- ChatGPT Memory is a convenience layer only. GitHub Master Development State plus verified repository code/CI is the project continuity source of truth.

Examples already locked:
- Brand is ASKODOX; historical/internal names are not substitutes.
- Ecommerce-style UI was rejected; approved direction is AI-app/local-commerce UI.
- Wrong-category and same-side matching are prohibited.
- Category questionnaires are dynamic/category-specific, not one generic form.
- Sandbox/demo data must not leak into LIVE.

## Verified development checkpoint — 2026-09-10
Latest verified checkpoint before this master-state document:
- `c2b429d6e2e3d6b01f5f1d566d292247e6246e74` — `test(demo): lock investor sandbox catalog coverage`.
- Flutter CI #661: SUCCESS.
- Bootstrap Android Runner #513: SUCCESS.

Important preceding verified work:
- `0f6751817c59019f3b66009b330cf7cc91a4516d` — expanded investor sandbox profile catalog (~20–30 fixture choices across product/service/job/ride/parcel/appointment/catering/retail branches).
- `6b7f96077e6895bfd0147e5e7972b5941b985ef7` — strict chicken investor matching requirements; Flutter CI #659 SUCCESS and signed update publish succeeded.
- `44ff694509bcbd69954423baffebb460ae33c5a9` — selected coordinates fed into local matching; associated CI verified green.
- `fd1bf899` — compatible TTS voice selection/safe fallback checkpoint; language/STT/TTS synchronization verified at that checkpoint.

## Current development target
**IN PROGRESS:**
`Party A/B acceptance → chat/contact gate → deal lifecycle → sandbox payment/billing → invoice → completion/review → TEST/LIVE isolation → investor E2E verification`.

Known architectural facts to preserve:
- `UniversalMatchRepository` already separates mock/demo matching from live backend matching.
- Demo catalog is enabled through the mock-client path; do not allow fake matches to hide live backend failures/no-match.
- Existing `DealLifecycleEngine` and lifecycle tests cover negotiation/completion/dispute rules and should be reused.
- Existing monetization screens/routes include order review, payment and invoice history; extend/reuse rather than duplicate.
- Local/demo `acceptMatch` was previously a no-op and therefore needs realistic sandbox acceptance state for production-like E2E behavior.

## Development discipline
- Verify repository state before every continuation.
- Never claim a commit, CI result, release, percentage or completed feature without checking it.
- A feature is GREEN only when implemented, integrated, tested and verified.
- If the same repair method fails twice, change the method.
- Do not redo completed work or create duplicate systems.
- Do not change approved product/brand decisions silently.
- After each meaningful verified block, update this master state with the new checkpoint and next target.

## Owner action
At this checkpoint: **no user action required**. Continue development in the repository until an external credential, account approval, device-only test, or explicit product decision genuinely requires owner input.
