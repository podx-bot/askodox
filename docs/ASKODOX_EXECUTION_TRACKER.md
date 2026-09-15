# ASKODOX Execution Tracker — 52-Point Completion Ledger

Status: ACTIVE EXECUTION LEDGER
Date: 2026-09-11
Linked source of truth: `docs/ASKODOX_MASTER_ARCHITECTURE.md`

## Purpose
This tracker prevents lost requirements, rework, silent gaps, and false completion claims. The Master Architecture defines WHAT ASKODOX must be. This ledger records WHAT has actually been implemented, tested, verified, and saved.

## Allowed Statuses
- NOT STARTED
- IN PROGRESS
- BLOCKED
- VERIFIED GREEN

A point may be marked VERIFIED GREEN only when code exists, integration exists, relevant tests pass, CI/build passes, the real end-to-end flow is verified, edge/failure cases are checked, and admin/audit behavior is checked where relevant.

## 52 Top-Level Points
1. Core Identity — Everyday AI Friend + Helping Mind + Decision Partner + Action Assistant
2. Eight Master Layers
3. Universal Roles
4. Registration / Identity
5. Universal Need Understanding
6. Dynamic Categories
7. Matching Engine
8. Local / Nearby / Online / External Fallback
9. Affiliate + Non-Affiliate Neutrality
10. Universal Online Comparison
11. BFSI / Financial Products
12. Life & Business Ecosystems
13. Party A / Party B Consent
14. AI Negotiation / Conversion Assistant
15. Seller / Business Module
16. AI Catalog
17. Service Lifecycle
18. Jobs Lifecycle
19. Ride Lifecycle
20. Delivery / Courier Lifecycle
21. Payment Architecture
22. Universal Deal State Machine
23. Cancellation / Refund / Return / Replacement
24. Disputes
25. Trust / Reviews / Fraud
26. Location / Maps
27. Language / Voice
28. Memory / History
29. Vision / Photo Search
30. Influencer / Creator + Deals
31. Notifications / AI Customer Desk
32. Admin Control Center
33. Analytics / Opportunity Intelligence
34. Privacy / Security
35. Failure Recovery
36. Inventory / Capacity / Pricing
37. Invoice / Ledger
38. Global Architecture
39. AI Self-Gap Detection
40. Recommendation Quality / User Agency
41. UI Core Rules
42. Accessibility / Performance
43. Release / Backend / Observability
44. Testing / Demo Environment
45. Completion Gate
46. Change-Control Rule
47. Historical / Superseded Positioning
48. Revenue Principles
49. Working Audit Checklist
50. Master Principle / External Source of Truth
51. WhatsApp Support-Only Channel
52. Automatic Point-by-Point Execution Protocol

## Point 1 — Core Identity
Status: IN PROGRESS
Requirement version/date: 2026-09-11

Requirement:
ASKODOX must operate as an Everyday AI Friend + Helping Mind + Decision Partner + Action Assistant. It must not force a marketplace/local-commerce flow on general needs. It should understand the actual request, preserve context, ask only missing information, think/compare/advise, route to appropriate actions when useful, and remain honest about actions/research actually performed. USER BENEFIT FIRST.

Acceptance criteria:
1. General requests route through the universal AI assistant rather than forced commerce/category forms.
2. Same-language response behavior is preserved.
3. Existing memory/context is available to the conversation runtime.
4. General assistant does not falsely claim live research, bookings, messages, reminders, sources, or completed actions.
5. Domain-specific transactional flows can still delegate to deterministic/runtime handlers.
6. Core app channel is in-app first; WhatsApp is support-only and must not remain the canonical core conversation channel.
7. Relevant smoke/integration tests pass and CI/build evidence is attached before VERIFIED GREEN.
8. Real in-app end-to-end verification is completed before VERIFIED GREEN.

Code evidence:
- `backend/app/services/universal_ai_assistant_service.py` implements the OASAT GENERAL path and safe/honest general-assistant prompt rules.
- `backend/app/api/app_factory.py` wires research, universal AI, user memory, ConversationOS, and customer response policy.
- User memory repository/service is supplied to ConversationOS.
- Commit `dd93b5fc1c09b506d69f3a13783f3a4024a63c5f` added `backend/app/services/whatsapp_support_only_gate.py`, a deterministic WhatsApp support-only guard that does not falsely claim Case ID creation.
- Commit `f825240a6821e51c20775a1ff9bb28f78f51e738` changed the canonical ConversationOS channel to `in_app` and placed the support-only gate in the WhatsApp webhook's first text-dispatch dependency, preventing normal text messages from falling through into job, insurance, commerce, ride, or general AI routing.

Test evidence:
- `.github/workflows/universal-ai-assistant-smoke.yml` covers GENERAL routing, same-language prompt behavior, commerce delegation, provider failure fallback, and readiness checks.
- `.github/workflows/user-memory-smoke.yml` exists for user-memory / ConversationOS behavior.
- Commit `48889f4e201d7aca0a78edc91da84285272a8eda` added `.github/workflows/whatsapp-support-channel-smoke.yml`.
- GitHub Actions run `34616415480` for `whatsapp-support-channel-smoke` completed successfully on commit `48889f4e201d7aca0a78edc91da84285272a8eda`.

CI/build evidence:
- WhatsApp support-channel smoke: SUCCESS on run `34616415480`.
- Flutter CI run `34616415459` for the same head commit was still PENDING at the last verification check; therefore Point 1 is not GREEN yet.
- Railway/deployment combined status was also still pending at the last verification check.

Known gaps / blockers to GREEN:
- Full friend-like decision loop (understand → remember → clarify only missing → compare → advise → action → help until done) is not yet proven end-to-end across the real in-app route.
- Real in-app E2E verification is not yet attached.
- Full CI/build/deploy evidence for the current head is not yet fully green.
- WhatsApp media/location legacy paths still contain historical operational behavior; the new text gate prevents normal text fall-through, but Point 51 cannot be GREEN until support case IDs/admin sync and the remaining media/location behavior are fully audited and separated.

### Real device GPS integration (2026-09-14, code change, not yet CI/device-verified)
Forensic finding: `lib/features/location/application/location_controller.dart`'s `requestPermission()` never called any real OS/GPS API — it unconditionally set in-memory `permission` state to `granted` with no `geolocator`/`permission_handler` dependency in `pubspec.yaml`. This is why tapping "లొకేషన్ అనుమతి ఇవ్వండి" in the app did nothing observable and every user was forced onto manual location selection with no way to auto-detect a default location. Confirmed live by the product owner via screenshots on 2026-09-14 (asked for "5 kilala chicken" with no default location set → app correctly asked for delivery details; then opened location setup → "Location permission granted" banner appeared with no real detection happening).

Fix applied (uncommitted at time of writing, staged on the owner's machine only):
- Added `lib/features/location/domain/device_location_gateway.dart` (`DeviceLocationGateway` interface) and `lib/features/location/data/geolocator_location_gateway.dart` (real implementation using the `geolocator` package, added to `pubspec.yaml` as `geolocator: ^14.0.3`).
- `LocationController` now takes a `DeviceLocationGateway` and its `requestPermission()`/`retryLocation()` call `ensurePermission()` + `getCurrentPosition()` for real, saving a `SavedLocationType.currentLocation` default location only when a real GPS fix is obtained; a missing fix now surfaces an honest "could not be read" message instead of a false "granted" state.
- Android manifest already declared `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (no manifest change needed); no iOS project exists in this repo (Android + web only).
- Added `test/features/location/fakes/fake_device_location_gateway.dart` and 2 new regression tests in `test/features/location/location_controller_test.dart` covering (a) granted permission + real fix → becomes the default location, and (b) granted permission + no fix → honest failure message, no default silently fabricated. Updated the pre-existing `permission denied flow` test and `location_widget_test.dart` construction site to the new two-argument `LocationController` constructor.

NOT yet verified:
- `flutter pub get` / `flutter analyze` / `flutter test` have not been run against this change — no Flutter SDK is reachable from this forensic/audit environment, and no local shell access exists on the owner's device from here either. Manual brace/paren-balance and import-consistency review only.
- Real device GPS behavior (actual permission dialog, actual coordinate fix, `deniedForever`/service-disabled device flows) is unverified — needs a real Android build/run.
- GitHub Actions `Flutter CI` has not yet run against this change.
- `lib/features/location/application/location_controller.dart`'s `geoRepositoryProvider` still uses `MockGeoRepository` for nearby-shop search — this fix only makes the *default location itself* real; nearby-shop discovery against a real backend is a separate, not-yet-scoped gap.

Next action:
- Verify Flutter CI and deployment for commit `48889f4e201d7aca0a78edc91da84285272a8eda`.
- Audit WhatsApp audio/image/document/location paths so none can bypass support-only policy.
- Verify a real in-app conversation E2E path and the full friend-like decision loop.
- Commit + push the real-GPS-integration change above on a dedicated branch, verify Flutter CI, then verify on a real Android device before marking any part of this GREEN.
- Reassess Point 1 only after all evidence is green.

Regression impact:
Potentially affects onboarding, memory/history, notifications, customer desk, WhatsApp support routing, job/ride legacy WhatsApp behavior, and any runtime handlers that previously assumed WhatsApp was the canonical channel.

### 2026-09-14 — Gemini reliability chain + AI Companion Positioning reaffirmation
Three real production reliability failures were found and fixed in sequence via live user testing (screenshots) + Railway log forensics, all in the "general assistant falls back to a hardcoded canned Dart reply instead of a real answer" failure family that this point's acceptance criteria (item 4: no false claims; the wider friend-like decision loop) depend on:
1. Gemini 503 "high demand" transient errors — fixed earlier with a short in-service retry (`_generate_with_retry`).
2. Gemini free-tier daily quota (`429 RESOURCE_EXHAUSTED`, 20 requests/day) exhausted by combined testing volume — resolved by the product owner enabling pay-as-you-go billing on the Gemini API key (OpenAI kept as a configured-but-unfunded secondary fallback for now, by owner's choice).
3. NEW finding: for longer/multi-detail messages, Gemini's "thinking" tokens were deducted from the same `max_output_tokens` budget as the visible JSON reply, truncating the response to a bare `{"reply": "` fragment and causing a parse failure (`no json object found in model reply`). Fixed by disabling thinking (`thinking_config=types.ThinkingConfig(thinking_budget=0)`) and raising `max_output_tokens` to 2048. Shipped in PR #46 (`fix/gemini-thinking-budget`), deployed and confirmed clean in Railway logs plus a real re-test by the product owner.

Separately, the product owner restated the Core Identity positioning in sharper, explicit terms (see `docs/ASKODOX_MASTER_ARCHITECTURE.md`, "Addendum — AI Companion Positioning & Engineering Layer Breakdown (2026-09-14)"). This reaffirms rather than changes this point's requirement; the addendum also records a related Point 7 violation found the same day (see Point 7 below).

## Point 44 — Testing / Demo Environment
Status: REQUIREMENT LOCKED; reusable demo-data implementation verification pending.
Requirement version/date: 2026-09-11

Requirement:
ASKODOX must have reusable dummy/demo accounts and seed data for realistic final end-to-end testing. These accounts must be prepared during development and reused for regression testing, not created only at the last minute.

Required demo roles / fixtures:
- Dummy general user / buyer.
- Dummy seller / business.
- Dummy service provider.
- Dummy employer and worker/job seeker.
- Dummy driver / rider / courier.
- Dummy admin / customer-care agent.
- Domain-specific fixtures when relevant, including BFSI, travel, expert/provider, catalog/products/services, locations, and offers.

Acceptance criteria:
1. Demo identities are clearly non-production and cannot be confused with real users.
2. Seed/reset mechanism can recreate a known clean demo state without manually rebuilding every account.
3. Test data covers registration/onboarding, AI conversation, category/need understanding, matching, accept/reject, contact/consent, chat, order/deal flow, delivery/courier/pickup, payment simulation, cancellation/refund/return/replacement, disputes, reviews/trust, notifications, and admin actions as applicable.
4. Support testing includes unresolved in-app issue → support case creation → admin/customer-care handling → optional WhatsApp support communication → status/resolution written back to ASKODOX history/audit.
5. Failure/edge fixtures cover no-match, wrong/partial input, duplicate account, failed payment simulation, delivery failure, timeout/retry, network interruption, language change, location change, app restart/session recovery, provider/API failure, and permission denial where relevant.
6. Multi-language demo coverage includes Telugu plus representative additional languages; language persistence across relaunch is verified.
7. Role isolation, permissions, privacy, and admin/audit records are testable with the demo identities.
8. Final regression run uses the reusable fixtures and records pass/fail evidence for each master point before release.
9. Demo/reset tooling must not wipe or modify production data.
10. Point 44 cannot be VERIFIED GREEN until seeded accounts/data, reset flow, automated tests where practical, and a real full-flow demo have all been verified.

Next action:
- Audit the repository for any existing demo seed/reset utilities, dummy fixtures, test users, and E2E scripts before creating new ones.
- Reuse existing fixtures where safe; add missing roles/scenarios instead of duplicating test infrastructure.

Regression impact:
This point ultimately validates all user-facing and admin flows and therefore depends on many earlier points. It should be built incrementally during development, then used as the final full-system regression gate.

## Point 51 — WhatsApp Support-Only Channel
Status: IN PROGRESS — text gate implemented; support-case/admin-sync and remaining media/location route verification pending.

WhatsApp is NOT the core ASKODOX business, matching, commerce, deal, or AI workflow. It is a secondary support channel for customer care, complaints, HR, admin support, verification assistance, unresolved issue escalation, and support follow-up. WhatsApp support interactions should create or link a Case ID, retain resolution status/history, and sync relevant outcomes into ASKODOX admin/audit records.

Implementation evidence:
- `whatsapp_support_only_gate.py` now blocks normal WhatsApp text from entering primary ASKODOX flows and routes users toward app-first usage or approved support categories.
- `app_factory.py` now makes ConversationOS `channel="in_app"` canonical.
- Support-channel smoke run `34616415480` passed.

Media/location path audit (2026-09-14, forensic pass, code-read not CI-verified):
- Text: gated. `webhook.py` routes every text message through `easy_job_command_service` (the gate), which always returns a reply, so `job_lifecycle_service`/`insurance_router`/`conversation_service` can never run from WhatsApp text.
- Audio: already effectively gated. The audio path transcribes the voice note and feeds the transcript through the same `_process_user_text` helper as text, so it hits the same gate.
- Location: **was bypassing the gate** — a location share drove `WORKER_LOCATION`/`EMPLOYER_LOCATION` session-step business logic directly (`save_location`, `complete_worker_registration`, `save_employer_job_location` + `job_matching_service.match_and_notify`, `job_lifecycle_service.handle_location`), fully independent of the text gate. Fixed in working tree: `webhook.py`'s location loop now calls a new `WhatsAppSupportOnlyGate.process_location()` (deterministic, stateless redirect reply) instead of touching session/user/job state. Unit tests added: `backend/tests/test_whatsapp_support_only_gate.py`. **Not yet committed, not yet CI-verified** — do not mark this bullet GREEN until a real commit/CI/E2E pass confirms it.
- Image/document: `payload_parser.py` has `extract_image_messages`/`extract_document_messages`, but `webhook.py` never calls them — image/document messages are silently dropped (no reply, but also no business-flow bypass since nothing runs). This is a separate UX gap, not a support-only policy bypass; still open.

Remaining requirements before Point 51 can be GREEN:
- Real support Case ID repository/creation.
- Admin/customer-care queue/history and closure status.
- Sync important WhatsApp support outcomes back into ASKODOX history/audit.
- Commit + CI-verify the location-gate fix above (implemented but unverified as of 2026-09-14).
- Decide and implement image/document handling (currently silently dropped) — at minimum give the user a reply pointing to the app, matching the text/location gate behavior.
- E2E support escalation verification.
- E2E support escalation verification.

## Point 52 — Automatic Point-by-Point Execution Protocol
Status: ACTIVE PROCESS RULE.

For every point, work in this exact order:
1. READ — Load the Master Architecture and current tracker entry before work.
2. GAP CHECK — Compare the requirement against current code, tests, admin, UX, security, payments/delivery implications, analytics, localization, and failure cases.
3. DEFINE ACCEPTANCE — Write exact acceptance criteria before marking implementation complete.
4. IMPLEMENT — Make the code/config/schema/UI/backend changes needed for that point.
5. INTEGRATE — Connect dependent modules; do not leave isolated code.
6. TEST — Unit/integration/UI/E2E/failure tests as relevant.
7. VERIFY — Verify CI/build plus the real user flow.
8. SAVE EVIDENCE — Record commit/PR/test/build evidence in this ledger.
9. STATUS — Mark VERIFIED GREEN only if the Master Completion Gate is satisfied; otherwise IN PROGRESS or BLOCKED.
10. DEPENDENCY CHECK — Confirm the completed point did not break an already-green point.
11. GAP SWEEP — Run a short self-gap check against the Master Architecture before moving on.
12. NEXT POINT — Continue to the next point only after the current status/evidence is saved.

## Rework-Prevention Rules
- Never rely on ChatGPT conversational memory as the canonical specification.
- Every new user requirement must be recorded in the Master Architecture or linked decision/requirement ledger before implementation is considered locked.
- Never silently delete old requirements; mark them SUPERSEDED and link the replacement.
- Never mark a point GREEN from a mockup, plan, code existence, or verbal claim alone.
- If the same method fails twice, reassess/change method before a third attempt.
- Before changing shared engines, identify which already-completed points are affected and re-run their relevant regression tests.
- Keep requirement evidence and implementation evidence separate.

## Execution Order
Default: Point 1 → Point 52 sequentially. A dependent technical subtask may be done earlier when necessary, but the tracker must show the dependency explicitly and the parent point cannot be marked GREEN until all its gates pass.


## Point 7 — Matching Engine
Status: IN PROGRESS (containment fix shipped 2026-09-14; underlying per-domain schema gap still open)
Requirement version/date: 2026-09-14 (see Master Architecture Point 7 and the 2026-09-14 Addendum)

Requirement:
Rank matches by relevant location/budget/availability/quality/verification/trust/preferences and show reasons. Local is a useful source, not a mandatory identity. A match must only be shown once the request is actually understood (see Point 39 — AI Self-Gap Detection) — never a placeholder/demo result presented as if it were a real, ready recommendation.

### 2026-09-14 — Forensic finding: DEMO match cards shown before request understood, and domain-mismatched
Live test: "naku insurance kavali" -> "health" produced a "Relevant matches" card (visibly labelled DEMO) showing "QuickFix Local Services" / "Nearby Home Service Pro" — generic home-service placeholder businesses with zero relevance to insurance — WHILE the assistant was still asking for budget/sum-assured/headcount. Root cause: `askodox_primary_home_screen.dart` calls `DemoNaturalMatchCatalog.forDeal(deal, enabled: true)` whenever `transactional` is true and a deal exists; the gate meant to prevent this (`UniversalDeal.missingForMatch` / `readyToMatch`, in `lib/features/deal_brain/domain/universal_deal.dart`) only defines required-field sets for ride/worker/service/appointment/buy-sell intents. An insurance request is absorbed into the generic `needService`/`offerService` case, whose only required fields are `subject` + `location` — so `readyToMatch` went true far too early, and the demo catalog has no insurance-specific card set anyway (it fell through to generic service placeholders).

This is also a confirmed instance of the never-shipped "DemoNaturalMatchCatalog is fake, not real seller data" gap already known from earlier this session (chicken-order flow investigation) — every domain, not just insurance, is currently shown fake/demo matches, clearly labelled "DEMO" in the UI but not gated correctly on actual completeness.

Code evidence (containment fix, not the underlying fix):
- `lib/features/home/presentation/askodox_primary_home_screen.dart`: both `DemoNaturalMatchCatalog.forDeal(deal, enabled: true)` call sites changed to `enabled: false`, so the "Relevant matches" section (`if (_matches.isNotEmpty)`) never renders until real seller-backed matching exists. Pushed on branch `fix/hide-demo-match-cards`.

Known gaps / next action:
- `UniversalDeal.missingForMatch` has no case for BFSI/insurance (or several other Point 12 life/business ecosystems) — needs a real per-domain required-fields schema before any match card for those domains is safe to re-enable (see Point 6, Point 11).
- No real seller/provider database is wired into this AI chat matching path for ANY domain yet — `DemoNaturalMatchCatalog` is 100% hardcoded sandbox data. Real matching (Point 7 proper, backed by `ProductCatalogRepository`/`seller_products` or an equivalent per-domain provider table) is a distinct, larger, not-yet-scoped project.
- Not yet re-verified with `flutter analyze`/tests beyond the 2-line change review (no Flutter SDK reachable from this audit environment).

Next action: product-owner decision needed on priority — build a real BFSI/insurance schema + matching next, or a different backlog item first. Do not set `enabled: true` again for any domain until its `missingForMatch` requirements are verified correct for that domain.

### 2026-09-15 — Real (non-demo) matching bootstrap started, per explicit product-owner direction
Status update: IN PROGRESS -> containment fix above superseded by a real bootstrap (still not the full Point 7 ranking engine).

Product owner's explicit priority order for the remaining backlog: (1) real seller matching, (2) BFSI/insurance category, (3) more reliability testing. For (1), given no seller-onboarding pipeline exists yet, the product owner's explicit instruction was to add a handful of real products/sellers manually together and show them to the buyer.

Shipped this round:
- `askodox_primary_home_screen.dart`: both former `DemoNaturalMatchCatalog.forDeal(...)` call sites replaced (not merely disabled) with calls to a new `RealProductMatchService.search(query)`, gated by the same `deal.readyToMatch` check.
- New Flutter service `lib/services/real_product_match_service.dart`, same pattern as `SponsoredAdsService`.
- Backend: `ProductCatalogRepository` (`backend/app/repositories/product_catalog_repository.py`) extended with `seller_name`/`location_label`/`contact_phone` columns and a new `search_active(query, limit)` method; new route `GET /api/products/search` (`backend/app/api/routes/product_search.py`) returns results shaped for `UniversalMatch.fromJson`; new temporary manual-seed tool `GET /admin/products/new?key=...` (`backend/app/api/routes/product_catalog_admin.py`), protected by a new `ADMIN_SEED_KEY` setting, so the product owner and this assistant can add real seller rows together without needing the full seller-onboarding UI first.
- New backend tests: `backend/tests/test_product_catalog_search.py` (6 cases covering search matching, brand/variant search, inactive/limit handling, blank-query and no-match behavior, and upsert dedup-by-seller+subject).

Known gaps still open (unchanged by this bootstrap):
- No BFSI/insurance required-fields schema in `UniversalDeal.missingForMatch` yet (Point 11, next in the product owner's stated priority order).
- No real seller-onboarding pipeline — `MockSellerRepository` is still hardwired in the Flutter app; the manual seed tool is a deliberate, explicitly-chosen bootstrap, not a replacement for that larger future project.
- `search_active` is a simple case-insensitive substring match with no ranking (location/budget/trust/availability) yet — the real Point 7 ranking engine is still a distinct, larger follow-up once there is meaningful real-data volume.
- Not yet re-verified with `flutter analyze`/`pytest` beyond manual review, `py_compile`, and standalone script-equivalent test runs (no Flutter SDK or `pytest`/`google-genai` package reachable from this audit environment).

## Per-Point Record Template
For each point, maintain:
- Status:
- Requirement version/date:
- Acceptance criteria:
- Code evidence:
- Integration evidence:
- Test evidence:
- CI/build evidence:
- E2E verification:
- Edge/failure verification:
- Admin/audit verification:
- Dependencies:
- Known gaps:
- Next action:
- Regression impact:

## Current Overall Status
52 top-level points are tracked. Point 1 remains IN PROGRESS. The canonical core channel is now in-app and a WhatsApp text support-only gate plus passing smoke test are implemented, but full CI/deploy, real in-app E2E, and remaining WhatsApp media/location separation are still pending. Point 44 has locked reusable dummy/demo account and final E2E regression requirements. Point 51 is now IN PROGRESS rather than requirement-only because a real text-routing guard exists, but it is not GREEN until case/admin-sync and all remaining paths are verified.


STEP 3 — dependency check (కొత్త dependency ఏమీ అవసరం లేదు)
--------------------------------------------------------------
ఈ ఫీచర్‌కి backend/requirements.txt లో కొత్తగా ఏమీ యాడ్ చెయ్యనవసరం లేదు (python-multipart లాంటిది కూడా అవసరం లేదు — admin form GET-based గా డిజైన్ చేశాను కావాలనే). lib/pubspec.yaml లో కూడా కొత్త package అవసరం లేదు (http package ఇప్పటికే వాడుతున్నాం, SponsoredAdsService లాగే).

STEP 4 — verify & test (వీలైతే)
---------------------------------
    cd backend
    python -m pytest tests/test_product_catalog_search.py -v

Flutter వైపు:
    flutter analyze
    (ఏమైనా error వస్తే నాకు screenshot పంపు, నేను చూస్తాను)

STEP 5 — commit మరియు push చెయ్యి
------------------------------------
    git add backend/app/repositories/product_catalog_repository.py backend/tests/test_product_catalog_search.py backend/app/api/routes/product_search.py backend/app/api/routes/product_catalog_admin.py backend/app/core/settings.py backend/app/api/app_factory.py backend/.env.example lib/services/real_product_match_service.dart lib/features/home/presentation/askodox_primary_home_screen.dart docs/ASKODOX_MASTER_ARCHITECTURE.md docs/ASKODOX_EXECUTION_TRACKER.md

    git commit -m "Add real seller-backed product matching bootstrap; replace fake DEMO match cards with real search"

    git push -u origin feature/real-product-matching-bootstrap

STEP 6 — GitHub లో Pull Request క్రియేట్ చేసి, main కి merge చెయ్యి
----------------------------------------------------------------------
GitHub Copilot/git tool నుండి ఈ బ్రాంచ్ కోసం Pull Request క్రియేట్ చెయ్యి (base: main, compare: feature/real-product-matching-bootstrap), review చేసి, merge చెయ్యి.

merge అయిన తర్వాత నాకు "Done" అని చెప్పు — నేను Railway లో deploy సరిగ్గా అయ్యిందో లేదో చెక్ చేస్తాను.

STEP 7 — Railway లో ఒక కొత్త Environment Variable యాడ్ చెయ్యాలి (చాలా ముఖ్యం)
-------------------------------------------------------------------------------
ఈ ఫీచర్ పని చేయాలంటే Railway production లో ఈ variable యాడ్ చెయ్యాలి:

    ADMIN_SEED_KEY=yrUGU38JNhJLhWSYipjs2Hmc

(ఇది నేను రాండమ్‌గా జనరేట్ చేసిన సీక్రెట్ కీ — ఇది తెలిసిన వాళ్ళు మాత్రమే ప్రొడక్ట్స్ యాడ్ చేయగలరు.) నువ్వు Railway dashboard లో పెట్టొచ్చు, లేదా "Railway లో ఈ variable పెట్టు" అని నాకు చెప్తే నేనే పెడతాను.

STEP 8 — నిజమైన ప్రొడక్ట్స్ యాడ్ చేయడం ఎలా (deploy అయిన తర్వాత)
--------------------------------------------------------------------
Deploy అయ్యి, ADMIN_SEED_KEY పెట్టిన తర్వాత, ఈ లింక్ (మీ Railway URL + /admin/products/new?key=... ) బ్రౌజర్‌లో ఓపెన్ చెయ్యి:

    https://podx-ai-connect-production-3279.up.railway.app/admin/products/new?key=yrUGU38JNhJLhWSYipjs2Hmc

అందులో ఒక ఫారమ్ కనిపిస్తుంది — సెల్లర్ పేరు, ఏమి అమ్ముతున్నారు (subject), ధర, లొకేషన్ లాంటి వివరాలు నింపి "Save" నొక్కితే, ఆ ప్రొడక్ట్ నిజంగా డేటాబేస్‌లో సేవ్ అవుతుంది. ఈ లింక్‌ను (key తో సహా) బుక్‌మార్క్ చేసుకోండి — మనం కలిసి కొన్ని రియల్ ప్రొడక్ట్స్/సర్వీసులను ఇలా యాడ్ చేసుకోవచ్చు (ఉదాహరణకు: చికెన్ సెల్లర్, AC రిపేర్ వ్యక్తి, మొబైల్ షాప్ మొదలైనవి).

యాడ్ చేసిన తర్వాత, బయ్యర్ యాప్‌లో ఆ సబ్జెక్ట్‌కి సంబంధించిన మాట (ఉదా. "చికెన్ కావాలి") టైప్ చేస్తే, ఆ నిజమైన ప్రొడక్ట్ "సంబంధిత ఎంపికలు" కార్డులో కనిపించాలి — DEMO లేబుల్ లేకుండా, నిజమైన సెల్లర్ పేరు/ధర/లొకేషన్‌తో.

గమనిక: ఇప్పటికి ఇన్సూరెన్స్ లాంటి BFSI ప్రొడక్ట్స్ కోసం ప్రత్యేక స్కీమా లేదు (అది తర్వాతి ప్రయారిటీ) — కానీ ఇప్పుడు నిజమైన సెర్చ్ వాడుతున్నందున, సరిపోయే రియల్ డేటా లేకపోతే ఖాళీగా ఉంటుంది తప్ప, ఇంతకుముందులా తప్పు/సంబంధం లేని fake కార్డులు ఇక కనిపించవు.

ఏదైనా స్టెప్‌లో స్టక్ అయితే, ఎక్కడ స్టక్ అయ్యావో స్క్రీన్‌షాట్ పంపు, నేను హెల్ప్ చేస్తాను.