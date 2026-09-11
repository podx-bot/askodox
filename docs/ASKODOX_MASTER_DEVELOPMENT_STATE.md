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

## Dynamic Party A / Party B conversation lock — 2026-09-11
- Party A and Party B are **dynamic transaction sides**, not permanent user types.
- Party A = the need/request side for the current transaction.
- Party B = the offer/fulfilment side for the current transaction.
- Do **not** hard-code Party A as Buyer or Party B as Seller. The same architecture must support Buyer ↔ Seller, Customer ↔ Service Provider, Employer ↔ Job Seeker, Passenger ↔ Driver, Sender ↔ Delivery Partner, Patient ↔ Doctor, and future categories/roles.
- The same person may be Party A in one transaction and Party B in another.
- Matching remains intent/category/opposite-side/location/radius/requirements based.

Conversation behavior:
- Category-specific mandatory questions remain structured and are used to collect the minimum data required for a valid match/deal.
- After matching, Party A is **not restricted to a fixed question list**. Party A may ask any relevant natural-language question about the current product/service/deal.
- ASKODOX may answer from Party B's verified/profile/catalog/service/deal data when the requested fact is available.
- Examples include price, availability, size, quantity, delivery/fulfilment, warranty, location, timing, customization and other category-relevant details.
- If the answer is not present in trusted Party B/deal data, AI must **not invent or guess it**. Mark/route it as requiring Party B confirmation and continue the conversation when Party B responds.
- Mandatory structured questionnaire + open natural conversation are complementary; neither replaces the other.
- Contact sharing remains behind the required acceptance/chat gate.
- Add regression coverage so future implementations cannot reduce Party A/B chat to fixed canned questions or hard-code Buyer/Seller roles.

## Universal Party A/B AI assistance lock — 2026-09-11
ASKODOX must act as the intelligent assistant/mediator for **both transaction sides throughout the journey**, not only as a matcher or buyer Q&A bot.

Party A assistance includes, according to the transaction/category:
- understanding the need in natural language;
- explaining how/where/when to buy, book, request, receive, pick up or use a service;
- collecting only the missing information needed to progress;
- comparing/matching appropriate local offers/providers;
- explaining availability, price, quantity, size, timing, fulfilment and next steps from trusted data;
- continuing the conversation through matching, deal, fulfilment and completion.

Party B assistance includes, according to the transaction/category:
- explaining how to sell, offer or fulfil a product/service;
- guiding product/service upload, photo capture, catalog creation, pricing inputs, availability and fulfilment information;
- answering Party B questions such as how to upload, what information is required, how to title/describe the listing, and what to do next;
- helping Party B respond to Party A questions and confirmation requests;
- continuing assistance through acceptance, chat, deal, fulfilment, completion and review.

Auto-catalog behavior:
- A seller/provider may provide a product/service photo plus natural voice/text details instead of manually filling a long catalog form.
- ASKODOX should transform the supplied facts into structured fields such as title, description, category, price/rate, size/variants, quantity/stock, color where applicable, availability and fulfilment/location details.
- When the owner does not specify a title or description, ASKODOX may generate useful default title/description copy **only from the supplied/verified facts**.
- Explicit seller/provider instructions for title, description or other editable listing fields take priority over generated defaults.
- ASKODOX must never invent factual attributes such as warranty, stock, size, price, certification or delivery promise when they were not supplied or verified.
- Generated/structured catalog data should remain reviewable/editable before final publication/save where confirmation is appropriate.
- The same principle applies to service-provider listings, with category-relevant fields such as service name, rate, service area, timing, availability and experience where supplied.

Universal assistant principle:
**The user tells ASKODOX what they are trying to accomplish; ASKODOX understands the context, asks only what is needed, explains the next action and helps carry the transaction forward.** This intelligence layer must work for Party A and Party B across products, services, jobs, rides, delivery, appointments and future categories.

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
`Party A request → category/location match → Party B accept → chat → deal/order → sandbox payment → invoice/bill → completion → review`

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
- Party A/B roles are transaction-dynamic, and open relevant questions must not be limited to canned/fixed questions.
- ASKODOX assists both Party A and Party B through the transaction rather than forcing users to understand every screen/form themselves.
- Product/service catalog creation should be photo + natural voice/text first where possible, with structured fields/default copy generated from trusted facts and no invented factual attributes.

## Verified development checkpoint — 2026-09-11
Verified recent blocks:
- `db82445a2793c5a0783289516974493538ebd668` — regression gate for trusted Party B/deal answers and unknown-fact Party B confirmation; deployment status SUCCESS.
- `60e571cb357314fa5f5252267e8a1e2bb8e29152` — trusted Party B/deal data answer routing service.
- `75d7c1d01b4a18a31d53134562fefed9d31425ad` — bilateral sandbox Party A/B contact-sharing gate regression; deployment status SUCCESS.
- `516643df25cccbb7d016bc0580b0bb83d591c9b4` — bilateral sandbox Party A/B gate domain logic.
- `8b4ff5d64ac26fce01e53f3f330189391428a860` — sandbox match acceptance regression.
- `32d0b5a445443ce13e87d1288c688685d6177689` — persist sandbox/local match acceptance instead of silently no-oping.

Earlier verified demo checkpoint:
- `c2b429d6e2e3d6b01f5f1d566d292247e6246e74` — investor sandbox catalog coverage; Flutter CI #661 SUCCESS and Bootstrap Android Runner #513 SUCCESS.
- `0f6751817c59019f3b66009b330cf7cc91a4516d` — expanded investor sandbox profile catalog.
- `6b7f96077e6895bfd0147e5e7972b5941b985ef7` — strict chicken investor matching requirements; Flutter CI #659 SUCCESS and signed update publish succeeded.
- `44ff694509bcbd69954423baffebb460ae33c5a9` — selected coordinates fed into local matching; associated CI verified green.
- `fd1bf899` — compatible TTS voice selection/safe fallback checkpoint; language/STT/TTS synchronization verified at that checkpoint.

Important integration status:
- Trusted-answer/Party B-confirmation domain/service logic and regression coverage exist.
- Bilateral sandbox gate domain logic and regression coverage exist.
- These blocks are **not yet full app-wide integration GREEN** until wired through the existing in-app deal endpoint/UI and verified E2E.

## Current development target
**IN PROGRESS:**
`Wire dynamic Party A/B trusted-answer + Party B confirmation into existing in-app deal chat → enforce bilateral contact gate in sandbox path → neutralize remaining hard-coded Buyer/Seller user-facing semantics → deal lifecycle → sandbox payment/billing → invoice → completion/review → TEST/LIVE isolation → investor E2E verification`.

Known architectural facts to preserve:
- `UniversalMatchRepository` already separates mock/demo matching from live backend matching.
- Demo catalog is enabled through the mock-client path; do not allow fake matches to hide live backend failures/no-match.
- Existing `DealLifecycleEngine` and lifecycle tests cover negotiation/completion/dispute rules and should be reused.
- Existing monetization screens/routes include order review, payment and invoice history; extend/reuse rather than duplicate.
- Existing backend in-app deal thread supports free-text messaging and lifecycle status; reuse it rather than creating a duplicate chat system.
- Legacy backend/database identifiers may still use buyer/seller internally for compatibility, but generic user-facing behavior and new architecture must remain dynamic Party A/B semantics.

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
