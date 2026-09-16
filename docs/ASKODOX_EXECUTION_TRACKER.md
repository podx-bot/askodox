# ASKODOX Execution Tracker â€” 52-Point Completion Ledger

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
1. Core Identity â€” Everyday AI Friend + Helping Mind + Decision Partner + Action Assistant
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

## Point 1 â€” Core Identity
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
- Full friend-like decision loop (understand â†’ remember â†’ clarify only missing â†’ compare â†’ advise â†’ action â†’ help until done) is not yet proven end-to-end across the real in-app route.
- Real in-app E2E verification is not yet attached.
- Full CI/build/deploy evidence for the current head is not yet fully green.
- WhatsApp media/location legacy paths still contain historical operational behavior; the new text gate prevents normal text fall-through, but Point 51 cannot be GREEN until support case IDs/admin sync and the remaining media/location behavior are fully audited and separated.

### Real device GPS integration (2026-09-14, code change, not yet CI/device-verified)
Forensic finding: `lib/features/location/application/location_controller.dart`'s `requestPermission()` never called any real OS/GPS API â€” it unconditionally set in-memory `permission` state to `granted` with no `geolocator`/`permission_handler` dependency in `pubspec.yaml`. This is why tapping "à°²à±Šà°•à±‡à°·à°¨à± à°…à°¨à±à°®à°¤à°¿ à°‡à°µà±à°µà°‚à°¡à°¿" in the app did nothing observable and every user was forced onto manual location selection with no way to auto-detect a default location. Confirmed live by the product owner via screenshots on 2026-09-14 (asked for "5 kilala chicken" with no default location set â†’ app correctly asked for delivery details; then opened location setup â†’ "Location permission granted" banner appeared with no real detection happening).

Fix applied (uncommitted at time of writing, staged on the owner's machine only):
- Added `lib/features/location/domain/device_location_gateway.dart` (`DeviceLocationGateway` interface) and `lib/features/location/data/geolocator_location_gateway.dart` (real implementation using the `geolocator` package, added to `pubspec.yaml` as `geolocator: ^14.0.3`).
- `LocationController` now takes a `DeviceLocationGateway` and its `requestPermission()`/`retryLocation()` call `ensurePermission()` + `getCurrentPosition()` for real, saving a `SavedLocationType.currentLocation` default location only when a real GPS fix is obtained; a missing fix now surfaces an honest "could not be read" message instead of a false "granted" state.
- Android manifest already declared `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (no manifest change needed); no iOS project exists in this repo (Android + web only).
- Added `test/features/location/fakes/fake_device_location_gateway.dart` and 2 new regression tests in `test/features/location/location_controller_test.dart` covering (a) granted permission + real fix â†’ becomes the default location, and (b) granted permission + no fix â†’ honest failure message, no default silently fabricated. Updated the pre-existing `permission denied flow` test and `location_widget_test.dart` construction site to the new two-argument `LocationController` constructor.

NOT yet verified:
- `flutter pub get` / `flutter analyze` / `flutter test` have not been run against this change â€” no Flutter SDK is reachable from this forensic/audit environment, and no local shell access exists on the owner's device from here either. Manual brace/paren-balance and import-consistency review only.
- Real device GPS behavior (actual permission dialog, actual coordinate fix, `deniedForever`/service-disabled device flows) is unverified â€” needs a real Android build/run.
- GitHub Actions `Flutter CI` has not yet run against this change.
- `lib/features/location/application/location_controller.dart`'s `geoRepositoryProvider` still uses `MockGeoRepository` for nearby-shop search â€” this fix only makes the *default location itself* real; nearby-shop discovery against a real backend is a separate, not-yet-scoped gap.

Next action:
- Verify Flutter CI and deployment for commit `48889f4e201d7aca0a78edc91da84285272a8eda`.
- Audit WhatsApp audio/image/document/location paths so none can bypass support-only policy.
- Verify a real in-app conversation E2E path and the full friend-like decision loop.
- Commit + push the real-GPS-integration change above on a dedicated branch, verify Flutter CI, then verify on a real Android device before marking any part of this GREEN.
- Reassess Point 1 only after all evidence is green.

Regression impact:
Potentially affects onboarding, memory/history, notifications, customer desk, WhatsApp support routing, job/ride legacy WhatsApp behavior, and any runtime handlers that previously assumed WhatsApp was the canonical channel.

### 2026-09-14 â€” Gemini reliability chain + AI Companion Positioning reaffirmation
Three real production reliability failures were found and fixed in sequence via live user testing (screenshots) + Railway log forensics, all in the "general assistant falls back to a hardcoded canned Dart reply instead of a real answer" failure family that this point's acceptance criteria (item 4: no false claims; the wider friend-like decision loop) depend on:
1. Gemini 503 "high demand" transient errors â€” fixed earlier with a short in-service retry (`_generate_with_retry`).
2. Gemini free-tier daily quota (`429 RESOURCE_EXHAUSTED`, 20 requests/day) exhausted by combined testing volume â€” resolved by the product owner enabling pay-as-you-go billing on the Gemini API key (OpenAI kept as a configured-but-unfunded secondary fallback for now, by owner's choice).
3. NEW finding: for longer/multi-detail messages, Gemini's "thinking" tokens were deducted from the same `max_output_tokens` budget as the visible JSON reply, truncating the response to a bare `{"reply": "` fragment and causing a parse failure (`no json object found in model reply`). Fixed by disabling thinking (`thinking_config=types.ThinkingConfig(thinking_budget=0)`) and raising `max_output_tokens` to 2048. Shipped in PR #46 (`fix/gemini-thinking-budget`), deployed and confirmed clean in Railway logs plus a real re-test by the product owner.

Separately, the product owner restated the Core Identity positioning in sharper, explicit terms (see `docs/ASKODOX_MASTER_ARCHITECTURE.md`, "Addendum â€” AI Companion Positioning & Engineering Layer Breakdown (2026-09-14)"). This reaffirms rather than changes this point's requirement; the addendum also records a related Point 7 violation found the same day (see Point 7 below).

## Point 44 â€” Testing / Demo Environment
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
4. Support testing includes unresolved in-app issue â†’ support case creation â†’ admin/customer-care handling â†’ optional WhatsApp support communication â†’ status/resolution written back to ASKODOX history/audit.
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

## Point 51 â€” WhatsApp Support-Only Channel
Status: IN PROGRESS â€” text gate implemented; support-case/admin-sync and remaining media/location route verification pending.

WhatsApp is NOT the core ASKODOX business, matching, commerce, deal, or AI workflow. It is a secondary support channel for customer care, complaints, HR, admin support, verification assistance, unresolved issue escalation, and support follow-up. WhatsApp support interactions should create or link a Case ID, retain resolution status/history, and sync relevant outcomes into ASKODOX admin/audit records.

Implementation evidence:
- `whatsapp_support_only_gate.py` now blocks normal WhatsApp text from entering primary ASKODOX flows and routes users toward app-first usage or approved support categories.
- `app_factory.py` now makes ConversationOS `channel="in_app"` canonical.
- Support-channel smoke run `34616415480` passed.

Media/location path audit (2026-09-14, forensic pass, code-read not CI-verified):
- Text: gated. `webhook.py` routes every text message through `easy_job_command_service` (the gate), which always returns a reply, so `job_lifecycle_service`/`insurance_router`/`conversation_service` can never run from WhatsApp text.
- Audio: already effectively gated. The audio path transcribes the voice note and feeds the transcript through the same `_process_user_text` helper as text, so it hits the same gate.
- Location: **was bypassing the gate** â€” a location share drove `WORKER_LOCATION`/`EMPLOYER_LOCATION` session-step business logic directly (`save_location`, `complete_worker_registration`, `save_employer_job_location` + `job_matching_service.match_and_notify`, `job_lifecycle_service.handle_location`), fully independent of the text gate. Fixed in working tree: `webhook.py`'s location loop now calls a new `WhatsAppSupportOnlyGate.process_location()` (deterministic, stateless redirect reply) instead of touching session/user/job state. Unit tests added: `backend/tests/test_whatsapp_support_only_gate.py`. **Not yet committed, not yet CI-verified** â€” do not mark this bullet GREEN until a real commit/CI/E2E pass confirms it.
- Image/document: `payload_parser.py` has `extract_image_messages`/`extract_document_messages`, but `webhook.py` never calls them â€” image/document messages are silently dropped (no reply, but also no business-flow bypass since nothing runs). This is a separate UX gap, not a support-only policy bypass; still open.

Remaining requirements before Point 51 can be GREEN:
- Real support Case ID repository/creation.
- Admin/customer-care queue/history and closure status.
- Sync important WhatsApp support outcomes back into ASKODOX history/audit.
- Commit + CI-verify the location-gate fix above (implemented but unverified as of 2026-09-14).
- Decide and implement image/document handling (currently silently dropped) â€” at minimum give the user a reply pointing to the app, matching the text/location gate behavior.
- E2E support escalation verification.
- E2E support escalation verification.

## Point 52 â€” Automatic Point-by-Point Execution Protocol
Status: ACTIVE PROCESS RULE.

For every point, work in this exact order:
1. READ â€” Load the Master Architecture and current tracker entry before work.
2. GAP CHECK â€” Compare the requirement against current code, tests, admin, UX, security, payments/delivery implications, analytics, localization, and failure cases.
3. DEFINE ACCEPTANCE â€” Write exact acceptance criteria before marking implementation complete.
4. IMPLEMENT â€” Make the code/config/schema/UI/backend changes needed for that point.
5. INTEGRATE â€” Connect dependent modules; do not leave isolated code.
6. TEST â€” Unit/integration/UI/E2E/failure tests as relevant.
7. VERIFY â€” Verify CI/build plus the real user flow.
8. SAVE EVIDENCE â€” Record commit/PR/test/build evidence in this ledger.
9. STATUS â€” Mark VERIFIED GREEN only if the Master Completion Gate is satisfied; otherwise IN PROGRESS or BLOCKED.
10. DEPENDENCY CHECK â€” Confirm the completed point did not break an already-green point.
11. GAP SWEEP â€” Run a short self-gap check against the Master Architecture before moving on.
12. NEXT POINT â€” Continue to the next point only after the current status/evidence is saved.

## Rework-Prevention Rules
- Never rely on ChatGPT conversational memory as the canonical specification.
- Every new user requirement must be recorded in the Master Architecture or linked decision/requirement ledger before implementation is considered locked.
- Never silently delete old requirements; mark them SUPERSEDED and link the replacement.
- Never mark a point GREEN from a mockup, plan, code existence, or verbal claim alone.
- If the same method fails twice, reassess/change method before a third attempt.
- Before changing shared engines, identify which already-completed points are affected and re-run their relevant regression tests.
- Keep requirement evidence and implementation evidence separate.

## Execution Order
Default: Point 1 â†’ Point 52 sequentially. A dependent technical subtask may be done earlier when necessary, but the tracker must show the dependency explicitly and the parent point cannot be marked GREEN until all its gates pass.


## Point 7 â€” Matching Engine
Status: IN PROGRESS (containment fix shipped 2026-09-14; underlying per-domain schema gap still open)
Requirement version/date: 2026-09-14 (see Master Architecture Point 7 and the 2026-09-14 Addendum)

Requirement:
Rank matches by relevant location/budget/availability/quality/verification/trust/preferences and show reasons. Local is a useful source, not a mandatory identity. A match must only be shown once the request is actually understood (see Point 39 â€” AI Self-Gap Detection) â€” never a placeholder/demo result presented as if it were a real, ready recommendation.

### 2026-09-14 â€” Forensic finding: DEMO match cards shown before request understood, and domain-mismatched
Live test: "naku insurance kavali" -> "health" produced a "Relevant matches" card (visibly labelled DEMO) showing "QuickFix Local Services" / "Nearby Home Service Pro" â€” generic home-service placeholder businesses with zero relevance to insurance â€” WHILE the assistant was still asking for budget/sum-assured/headcount. Root cause: `askodox_primary_home_screen.dart` calls `DemoNaturalMatchCatalog.forDeal(deal, enabled: true)` whenever `transactional` is true and a deal exists; the gate meant to prevent this (`UniversalDeal.missingForMatch` / `readyToMatch`, in `lib/features/deal_brain/domain/universal_deal.dart`) only defines required-field sets for ride/worker/service/appointment/buy-sell intents. An insurance request is absorbed into the generic `needService`/`offerService` case, whose only required fields are `subject` + `location` â€” so `readyToMatch` went true far too early, and the demo catalog has no insurance-specific card set anyway (it fell through to generic service placeholders).

This is also a confirmed instance of the never-shipped "DemoNaturalMatchCatalog is fake, not real seller data" gap already known from earlier this session (chicken-order flow investigation) â€” every domain, not just insurance, is currently shown fake/demo matches, clearly labelled "DEMO" in the UI but not gated correctly on actual completeness.

Code evidence (containment fix, not the underlying fix):
- `lib/features/home/presentation/askodox_primary_home_screen.dart`: both `DemoNaturalMatchCatalog.forDeal(deal, enabled: true)` call sites changed to `enabled: false`, so the "Relevant matches" section (`if (_matches.isNotEmpty)`) never renders until real seller-backed matching exists. Pushed on branch `fix/hide-demo-match-cards`.

Known gaps / next action:
- `UniversalDeal.missingForMatch` has no case for BFSI/insurance (or several other Point 12 life/business ecosystems) â€” needs a real per-domain required-fields schema before any match card for those domains is safe to re-enable (see Point 6, Point 11).
- No real seller/provider database is wired into this AI chat matching path for ANY domain yet â€” `DemoNaturalMatchCatalog` is 100% hardcoded sandbox data. Real matching (Point 7 proper, backed by `ProductCatalogRepository`/`seller_products` or an equivalent per-domain provider table) is a distinct, larger, not-yet-scoped project.
- Not yet re-verified with `flutter analyze`/tests beyond the 2-line change review (no Flutter SDK reachable from this audit environment).

Next action: product-owner decision needed on priority â€” build a real BFSI/insurance schema + matching next, or a different backlog item first. Do not set `enabled: true` again for any domain until its `missingForMatch` requirements are verified correct for that domain.

### 2026-09-15 â€” Real (non-demo) matching bootstrap started, per explicit product-owner direction
Status update: IN PROGRESS -> containment fix above superseded by a real bootstrap (still not the full Point 7 ranking engine).

Product owner's explicit priority order for the remaining backlog: (1) real seller matching, (2) BFSI/insurance category, (3) more reliability testing. For (1), given no seller-onboarding pipeline exists yet, the product owner's explicit instruction was to add a handful of real products/sellers manually together and show them to the buyer.

Shipped this round:
- `askodox_primary_home_screen.dart`: both former `DemoNaturalMatchCatalog.forDeal(...)` call sites replaced (not merely disabled) with calls to a new `RealProductMatchService.search(query)`, gated by the same `deal.readyToMatch` check.
- New Flutter service `lib/services/real_product_match_service.dart`, same pattern as `SponsoredAdsService`.
- Backend: `ProductCatalogRepository` (`backend/app/repositories/product_catalog_repository.py`) extended with `seller_name`/`location_label`/`contact_phone` columns and a new `search_active(query, limit)` method; new route `GET /api/products/search` (`backend/app/api/routes/product_search.py`) returns results shaped for `UniversalMatch.fromJson`; new temporary manual-seed tool `GET /admin/products/new?key=...` (`backend/app/api/routes/product_catalog_admin.py`), protected by a new `ADMIN_SEED_KEY` setting, so the product owner and this assistant can add real seller rows together without needing the full seller-onboarding UI first.
- New backend tests: `backend/tests/test_product_catalog_search.py` (6 cases covering search matching, brand/variant search, inactive/limit handling, blank-query and no-match behavior, and upsert dedup-by-seller+subject).

Known gaps still open (unchanged by this bootstrap):
- No BFSI/insurance required-fields schema in `UniversalDeal.missingForMatch` yet (Point 11, next in the product owner's stated priority order).
- No real seller-onboarding pipeline â€” `MockSellerRepository` is still hardwired in the Flutter app; the manual seed tool is a deliberate, explicitly-chosen bootstrap, not a replacement for that larger future project.
- `search_active` is a simple case-insensitive substring match with no ranking (location/budget/trust/availability) yet â€” the real Point 7 ranking engine is still a distinct, larger follow-up once there is meaningful real-data volume.
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

### 2026-09-15 â€” Seller listing schema extended

The real seller listing bootstrap now persists and exposes `category_tag`,
`service_area`, and `working_hours`. The protected manual seed form accepts
these fields, backend search includes category matches, and buyer-facing
match subtitles display the supplied category, service area, and hours.
This remains bootstrap metadata rather than a full ranking or seller-onboarding
system.

### 2026-09-15 (round 2) â€” Role-segmented research (Seller / Service Provider / Buyer / Service Taker) and a further trust/compliance schema extension

Following the first round above, the product owner asked for a deeper, role-by-role check against real top platforms (not just a flat field list): what do real apps require specifically from a Seller, a Service Provider, a Buyer, and a Service Taker to actually close a deal. A research pass grounded in Amazon/Flipkart/Etsy/IndiaMART/Meesho (seller), Urban Company/TaskRabbit/Upwork/Fiverr/Google Business Profile (service provider), and Amazon/Flipkart/Etsy checkout plus Urban Company/Swiggy/Zomato/Uber/Ola (buyer and service-taker) surfaced 6 gaps that mattered for at least 2 of the 4 roles:

1. Precise/structured location (GPS pin + landmark) -- our `location_label` is a plain text area/city only.
2. Payment/payout details -- every platform researched collects this.
3. Identity/trust verification (GSTIN/PAN for Seller; Aadhaar/police check for Service Provider).
4. Real scheduling (date/time slot booking) -- we only have static `working_hours`.
5. Ratings/reviews history -- a universal trust signal, currently absent.
6. Cancellation/return/refund policy.

Product owner's decision: implement all 6 now for the parts that are a straightforward schema/admin-form extension of the existing seller-side bootstrap (same pattern as the round-1 fields); explicitly defer (4) real scheduling and (5) ratings/reviews until after the BFSI/insurance domain is built, matching the product owner's own original priority order (1. real seller matching [done], 2. BFSI/insurance, 3. reliability testing) -- these two need real subsystems (a booking/slot calendar; a reviews store and UI) that don't yet exist and shouldn't be improvised as bare columns.

Shipped this round (Seller/Service-Provider side only -- see "known gap" below for Buyer/Service-Taker):
- `product_catalog_repository.py`: `_ADDED_COLUMNS` extended with `precise_location`, `cancellation_policy`, `payout_reference`, `gstin`, `pan`, `id_verification_status`.
- **Deliberate compliance decision**: `id_verification_status` stores only a plain status string (e.g. `VERIFIED`/`UNVERIFIED`) -- it and no other field ever stores a raw Aadhaar (or other national ID) number. Storing raw Aadhaar numbers outside a UIDAI-authorized flow is both a legal exposure (Aadhaar Act) and a security risk for a bootstrap tool with no encryption-at-rest story. GSTIN and PAN ARE stored as given, since these are business/tax identifiers that real e-commerce platforms (Amazon, Flipkart) already collect and store the same way for KYC/TDS purposes -- a materially different risk profile from a biometric national ID.
- `payout_reference` (e.g. a UPI VPA) is informational-only metadata for the product owner's own records -- there is still no real payment processing (Master Architecture Point 21 remains not built), so this is not wired to any money movement.
- `product_search.py`: buyer-facing match subtitle now shows a plain "âœ“ ID Verified" trust badge when `id_verification_status` is `VERIFIED` (never the underlying number), and falls back to `precise_location` when no `location_label` was given.
- `product_catalog_admin.py`: manual seed form gets 6 new inputs (Precise location, Cancellation/return policy, Payout reference, GSTIN, PAN, ID verification status dropdown), with an explicit on-page note that no Aadhaar/national-ID number is ever collected here.
- `test_product_catalog_search.py`: 2 new tests (`test_upsert_product_persists_trust_and_compliance_fields`, `test_upsert_product_leaves_trust_fields_unset_by_default`) -- 12 tests total now.

Verified via standalone script execution (12/12 pass), `py_compile`, and template-render smoke tests of both the admin form and the search subtitle (no `pytest`/Flutter SDK reachable from this audit environment).

Known gap, explicitly not started this round: the Buyer-side and Service-Taker-side fields the same research surfaced (structured delivery address, GPS pin-drop, saved payment method, alternate contact for Buyer; job-spec attributes, date/time slot, access instructions, OTP handshake for Service Taker) are NOT a column addition to `seller_products` -- there is currently no buyer/service-taker profile persistence at all in ASKODOX. Building that is a separate, materially larger project (new table/repository, wiring into the deal-brain/chat flow, real address+geo capture UX) overlapping Master Architecture Points 4 (Registration/Identity), 21 (Payment Architecture) and 26 (Location/Maps). Flagged for a future dedicated round rather than silently built into this bootstrap-form change.

### 2026-09-15 (round 2, requirement recorded) â€” Future direction: AI-conversational registration (chat or voice), both Seller/Provider and Buyer/Service-Taker

Product owner's explicit new requirement, recorded here per the project's own Rework-Prevention Rule ("every new user requirement must be recorded ... before implementation is considered locked") even though implementation is deferred: today, filling in any of the fields above (round 1 or round 2) is a manual step -- either this assistant and the product owner typing into the `/admin/products/new` web form together, or (once real onboarding exists) a person filling a form themselves. The product owner instead wants the AI itself to conduct registration/onboarding as a natural conversation, over in-app chat or voice, for **both** sides -- Seller/Service-Provider **and** Buyer/Service-Taker:

- The AI asks for each required field conversationally (not a static form) and fills them in from the person's natural-language answers as the conversation goes.
- Answers are saved (persisted) as they come in, not only at the end, so a partially-completed registration is not lost.
- The AI tracks which required fields are still missing and proactively asks the person directly for exactly what's missing, rather than silently leaving a gap or making up a value.
- This applies to both the round-1 fields (category, service area, working hours) and the round-2 fields (precise location, cancellation policy, payout reference, GSTIN, PAN, ID verification status) documented above, plus whatever Buyer/Service-Taker fields are scoped when that side is built (see the known gap immediately above).

This is a genuinely large feature (a conversational registration/intake flow driven by the deal-brain/AI-assistant layer, with per-field extraction, partial-save, and gap-detection logic across two different role types) and overlaps Master Architecture Point 4 (Registration/Identity) directly, plus Points 15/16 (Seller/Business Module, AI Catalog) for the seller side. **Explicitly deferred**: product owner confirmed this should be taken up after the BFSI/insurance domain (Point 11), matching the standing priority order (1. real seller matching [done], 2. BFSI/insurance, 3. reliability testing). No implementation has started. This entry exists so the requirement is not lost between now and when that work begins.

### 2026-09-15 (round 4) — Forensic finding: "place order" was a local UI animation; a seller's own "sell" chat never reached the real catalog either

Product owner's own end-to-end test: as a seller, typed "I want to sell mango pickle" in the app's own chat and completed the flow; as a buyer, searched for "mango pickle" / "mango pickles". Nothing showed up anywhere — no listing, no order, no history, on either side.

Root-cause trace (code-level, not speculation):
- The "sell" side of `UniversalDealController` (`lib/features/deal_brain/application/universal_deal_controller.dart`) only ever persists a completed deal to local `SharedPreferences` (`_persist()`/`_restore()`), and `askodox_primary_home_screen.dart` only ever matched a completed deal against the hardcoded `DemoNaturalMatchCatalog` (later `RealProductMatchService`, see the round-3 entry above) — **for every intent, including `sell`**, with no branch that treats a completed sell as "save this listing." A seller's own "I want to sell X" therefore never reached the real `seller_products` table at all; it only ever searched for buyer-style matches of X, which is a no-op for a seller.
- The only real path into `seller_products` was the admin-key-gated `/admin/products/new` form (`product_catalog_admin.py`), usable only by this project's developer, not an ordinary app user.
- There is no `orders` table or endpoint anywhere in the ASKODOX backend. Every "Place Order" surface in the Flutter app (`OrderRequestScreen` in `shop_details_screen.dart`, the order banner in `universal_match_screen.dart`) only drives a local timer/animation; nothing is ever sent to or saved on the server.
- Live-verified against production: `GET /api/products/search?q=mango` and `q=pickle` both returned `{"items":[]}` while `q=chicken` correctly returned the known real listing — confirming the search API itself works fine and the mango-pickle listing genuinely was never saved anywhere real.

Product owner's explicit re-prioritization once this was found (his own words): showing a match/request is not enough — ASKODOX must actually place and save a real order, covering everything short of actual payment, because "AI-powered" to him means advanced/effortless/complete, not a dead end that still needs a manual step somewhere else. He explicitly chose to fix this immediately, ahead of resuming BFSI/insurance (Point 11).

### 2026-09-15 (round 5) — Real order placement + real self-service seller listings shipped

Status: IN PROGRESS (backend unit-tested; Flutter wiring done, not yet CI-verified — see below). This directly closes the round-4 finding above. Still does not include actual payment processing (Master Architecture Point 21 remains not built) — order status can be updated by a seller via the backend endpoint, but settling money between buyer and seller still happens outside the app, same as before.

Backend, shipped this round:
- New `backend/app/repositories/order_repository.py` (`OrderRepository`): a plain `orders` table (buyer/seller user id, product id/title, quantity, unit, price, currency, computed `total_amount`, `status`, buyer/seller notes, timestamps), same connection/migration style as `product_catalog_repository.py`. `VALID_STATUSES = (PLACED, ACCEPTED, REJECTED, FULFILLED, CANCELLED)`; only PLACED is buyer-set, everything else via `update_status()`.
- New `backend/app/api/routes/orders.py`: `POST /api/orders` (buyer places an order against a real, active `seller_products` row — 404 if the listing is gone, 409 if it has no seller on record), `GET /api/orders/mine` (buyer's own order history), `GET /api/orders/incoming` (seller's incoming orders), `POST /api/orders/{id}/status` (seller updates status; returns 404 rather than 403 for a non-owner, so the endpoint does not confirm/deny which orders exist to a non-owner). Reuses the exact same `app-` prefixed user-id convention already used by `/deals` — no new auth system.
- New `backend/app/api/routes/product_catalog_self_service.py`: `POST /api/products/mine` and `GET /api/products/mine` — lets an ordinary "app-" user create/list their own real listings via the exact same `ProductCatalogRepository.upsert_product()`/table the admin-only bootstrap form and buyer search already use, so no search/matching code needed to change. Deliberately does **not** add a moderation/review step this round — same bootstrap-stage tradeoff already accepted for `/deals` elsewhere in this codebase; a spam/abuse review pass is future work.
- `product_catalog_repository.py`: added `list_active_for_seller(seller_user_id, limit)` for the new "my listings" endpoint.
- `container.py`/`app_factory.py`: wired `OrderRepository` and the two new routers in.
- New `backend/tests/test_order_repository.py` (9 cases) and 2 new cases added to `test_product_catalog_search.py` (`list_active_for_seller` — own-listings-only, most-recently-updated-first). **23/23 passing**, verified via the same manual pytest-shim runner used throughout this session (no `pytest` package reachable from this audit environment); all 6 backend files also `py_compile`/`ast.parse` clean (`fastapi`/`pydantic` are not importable in this audit environment either, so route-level logic was additionally hand-traced against the already-tested repository methods).

Flutter, shipped this round:
- New `lib/features/orders/data/order_repository.dart` (`OrderRepository`/`ApiOrderRepository`): `placeOrder()`, `myOrders()`, `incomingOrders()`, using the exact same `ApiClient`/`ApiRequestOptions`/`ApiSuccess`/`ApiError` mutation pattern and `app-` user-id resolution (`authSessionProvider`) as `ApiUniversalMatchRepository` in `universal_match_repository.dart`.
- New `lib/features/selling/data/seller_listing_repository.dart` (`SellerListingRepository`/`ApiSellerListingRepository`): turns a completed `DealIntent.sell` deal into a real `POST /api/products/mine` call. Deliberately a new, separate module rather than folding into the existing `lib/features/seller/` tree, which is the older, still-fully-mock `MockSellerRepository`-backed seller dashboard (out of scope to touch this round — see known gap below).
- `askodox_primary_home_screen.dart`: both `_restore()` and `_send()` now branch on `deal.intent == DealIntent.sell` when a deal becomes `readyToMatch` — a completed sell deal calls the new listing repository and shows a live/error confirmation banner (`_ListingBanner`) instead of running a buyer-style search against itself (the exact bug from the round-4 finding). `_MatchCard` (shown for buyer-side matches) gained a real "Place order" button that calls `OrderRepository.placeOrder()` with loading/success/error states.
- `profile_screen.dart`: added "My orders" (always visible) and "Incoming orders" (visible when the Seller role chip is selected) entries linking to the two new screens, so the requirement that an order be visible to both sides is actually reachable in the UI.
- New `lib/features/orders/presentation/order_screens.dart` (`MyOrdersScreen`, `IncomingOrdersScreen`): simple, read-only order-history lists (status badge, quantity/amount, buyer note, timestamp), styled after `DealInboxScreen` in `features/deals/presentation/deal_screens.dart`. No accept/reject UI yet, even though the backend supports status updates — kept to viewing only this round to close the reported gap without expanding scope further.
- `app_router.dart`: new unguarded routes `/orders/mine`, `/orders/incoming` (same routing tier as `/deals` — not inside the `/seller/*` `RouteGuard`-protected shell, since ordinary buyers must reach `/orders/mine` too).

Verified: all `.dart` changes hand-traced (bracket/paren balance checked, import correctness confirmed against the actual `origin/main` source of each touched file) since no Flutter SDK is reachable from this audit environment. **Not yet verified by `flutter analyze`/`flutter test`** — wait for `flutter-ci.yml` to go green after this instruction file is applied and pushed, same as every other Dart change this session. The backend change additionally gets a real end-to-end check from `backend-monorepo-smoke.yml` (builds the Docker image and boots the real FastAPI server) once pushed.

Known gaps, explicitly not started this round:
- No accept/reject/fulfil UI for the seller on `IncomingOrdersScreen` yet (the backend endpoint exists — `POST /api/orders/{id}/status` — only the screen doesn't call it yet).
- Only `DealIntent.sell` triggers real listing creation this round, matching the product owner's exact tested scenario. Whether `offerService`/`offerRide`/other "offer"-side intents should also create a real record is not yet scoped.
- The older `lib/features/seller/` module (`MockSellerRepository`, `seller_dashboard_screen.dart`, etc.) is untouched and remains fully mock/disconnected from the real `seller_products`/`orders` tables — consolidating or replacing it is a separate, larger future project, not part of this round.
- No spam/abuse moderation on the new self-service listing or order endpoints (see round-5 backend note above) — same bootstrap-stage tradeoff already accepted elsewhere in this codebase.
- Actual payment processing (Master Architecture Point 21) is still not built — this round is everything short of payment, as the product owner explicitly asked for.

Next action: apply this instruction file, wait for `flutter-ci.yml` and `backend-monorepo-smoke.yml` to go green, then re-test the exact original scenario (sell "mango pickle" as a seller, confirm it appears under Profile -> My listings via search, then order it as a buyer and confirm it appears on both Profile -> My orders and Profile -> Incoming orders) before resuming BFSI/insurance (Point 11).

### 2026-09-15 (round 6) — Forensic finding: the round-5 real-listing path was still unreachable from the AI chat (semantic router forced every product/food message to "buy"), AND round 5 itself had never actually been merged

**Important correction to the round-5 entry above**: that entry was written when round 5's instruction file was handed off, and this tracker (like the product owner) believed it had been applied. Direct verification against the live GitHub repository and the live production API on 2026-09-15 (checking for `/api/orders/*` and `/api/products/mine`, both of which returned 404, and confirming no pull request for this work was ever opened) established that **round 5's code was never actually committed/merged/deployed** — the product owner had reviewed Copilot's proposed diff but a PR for it was never created. Round 5 above should be read as "written and verified locally, not yet shipped" rather than "shipped." This instruction file ships round 5 and round 6 together, for the first time, in one combined change.

Separately, re-testing the intended round-5 behavior end-to-end (as if it had shipped) surfaced a second, independent bug: typing a sell-side message for "Homemade Mango Pickle" in the main chat, the AI assistant replied "Great! Your store listing for Homemade Mango Pickle has been set up and published." This claim was **not taken at face value** — checked directly against the live production backend (`GET /api/products/search?q=mango&limit=10` on the production API) which returned `{"items":[]}`: no listing was ever actually saved, despite the AI confidently saying otherwise. (This particular check would have failed regardless of the round-5-never-merged issue above, because of the separate routing bug described next.)

Root-cause trace (code-level, not speculation):
- The AI-classified chat path routes every message through `AskodoxSemanticDealInput.build()` (`lib/features/home/domain/semantic_deal_input.dart`) before it ever reaches `UniversalDealController`/`UniversalDealBrain`. This method takes the backend's classified `domain` (PRODUCT, FOOD, SERVICE, RIDE, etc.) and rewrites the message into a fixed English phrase for the deal-brain to parse.
- That rewrite was **unconditional**: `'PRODUCT' || 'FOOD' => 'i want to buy $payload'`, `'SERVICE' => 'need service $payload'`, `'RIDE' => 'need a ride $payload'` — with no case that ever produced sell/offer phrasing, regardless of what the user actually typed.
- `UniversalDealBrain._intent()` (`lib/features/deal_brain/application/universal_deal_brain.dart`) only recognises `DealIntent.sell` from phrases like "i want to sell", "for sale", "అమ్మాలి" — none of which the router above could ever produce for a PRODUCT/FOOD message. So a seller's "sell mango pickle" message was silently rewritten to "i want to buy mango pickle" before intent detection ever ran, always landing on `DealIntent.buy`.
- Round 5's real listing-creation code (`_createRealListing()` in `askodox_primary_home_screen.dart`, wired in the previous round) only runs when `deal.intent == DealIntent.sell` — so it was structurally unreachable from this chat path. Round 5 itself was correct and is confirmed working when a deal genuinely resolves to `DealIntent.sell`; the gap was entirely upstream, in message routing.
- Separately noted, **found but deliberately not fixed this round** (kept out to limit blast radius, see below): the backend's `AssistantDecision` response model (`backend/app/api/routes/in_app_assistant.py`) does not declare an `entities` field, so the `entities` dict computed by `universal_ai_assistant_service.py`'s `decide()` is silently dropped from every API response (Pydantic default `extra="ignore"`). This is unrelated to the buy/sell misrouting above, but is recorded here as a known gap for future work — fixing it would activate a currently fully-dead payload-reconstruction path in `semantic_deal_input.dart` that does not currently forward `price`, which needs its own dedicated, test-covered round rather than being bundled in here.
- Also noted: the AI's free-text `reply` (e.g. "has been set up and published") is generated independently of whether any real backend action succeeded — it is not tied to the outcome of `_createRealListing()`. The prompt instructs the model not to claim an action happened, but this is not currently enforced in code. Recorded as a known trust/grounding gap, not fixed this round.

Fix shipped this round:
- `lib/features/home/domain/semantic_deal_input.dart`: added `_isOfferingSide(original, decision)`, which checks the AI's classified `action` string for offering-side hints (`sell`, `list_product`, `create_listing`, `publish_listing`, `offer_service`, `offer_ride`, etc.) and, failing that, checks the user's own raw message for the same offer/sell phrase families `UniversalDealBrain._intent()` already recognises ("i want to sell", "for sale", "selling my", "offer service", "provide service", "offer ride", "seats available", "అమ్మాలి", "అమ్మకం", etc.). `build()`'s switch statement now branches on this: `SERVICE` emits `offer service $payload` when offering (else `need service $payload`), `RIDE` emits `offer ride $payload` (else `need a ride $payload`), and `PRODUCT`/`FOOD` emits `i want to sell $payload` (else `i want to buy $payload`). The emitted phrasing deliberately reuses the exact phrase families `_intent()` already matches, so this fix only changes routing, not intent-detection logic itself, keeping risk scoped to this one file.
- Deliberately scoped to only this file (beyond re-shipping round 5 itself). The `entities`-field Pydantic gap and the AI-reply grounding gap (both noted above) are documented but not touched this round, to keep this fix small, isolated, and easy to verify against the exact reported scenario.

This instruction file therefore ships, together, for the first time: every round-5 file (real order placement + self-service seller listing — backend routes/repository, Flutter repositories/screens/router/profile entries) exactly as originally written and unit-tested, re-verified against the actual current `main` branch (only one unrelated file, `backend/app/api/routes/product_search.py`, had changed on `main` since round 5 was originally written, and it is untouched by this change), plus the round-6 routing fix on top. Backend: all 23 existing repository-level tests (9 for orders, 14 for product catalog search/self-service) re-run against a fresh copy of the current `main` backend and pass. Flutter: hand-traced bracket/paren balance and diffed against the current `main` branch (no Flutter SDK reachable from this audit environment) — `_createRealListing`/`_ListingBanner`/`_MatchCard`'s "Place order" button are unchanged from their original round-5 design and slot into the current AI-first chat screen's existing `_restore()`/`_send()` methods (which now use `RealProductMatchService` rather than the older demo catalog) via the same `deal.intent == DealIntent.sell` branch point.

Verified: **not yet verified by `flutter-ci.yml`/`backend-monorepo-smoke.yml`** — wait for both to go green after this instruction file is applied and pushed, since this is the first time this code actually reaches CI.

Next action: apply this instruction file, wait for `flutter-ci.yml` and `backend-monorepo-smoke.yml` to go green, **create and merge a pull request** (this step was missed for round 5 — confirm a PR actually exists and is merged this time, not just that Copilot applied the changes locally), publish a new Android release (Actions -> "Android Live Build" -> "Run workflow" -> check "Publish a GitHub prerelease with the APK" -> Run — a normal merge-triggered build does not publish a release), update the app, then re-test the exact "sell mango pickle" scenario. Verify success against the real backend search API rather than the AI's own chat reply, since round 6 exists specifically because that reply was confidently wrong.

### 2026-09-15 (round 7) — Forensic finding: real listings/orders were saving with garbled titles and no price, because the AI's extracted `entities` were silently dropped from every API response

Round 6 fixed routing (sell messages stopped being forced into "buy" phrasing) and rounds 5+6 together were confirmed genuinely merged and working end-to-end: a seller lists "Maruti 800" via chat, a buyer finds and orders it, and the order appears on both `My orders` and `Incoming orders`. The product owner then reported that this working flow still wasn't good enough — the saved records themselves were missing details.

This was **not taken at face value**. Checked directly against the live production API:
- `GET /api/products/search?q=maruti&limit=5` returned a listing with `"title":"\"I want to sell Maruti 800 for 50000"` (the user's raw typed text, quote character and all) and `"price":null`, despite the seller having stated "₹50,000" in chat.
- A second listing from the same seller showed `"title":"2000 model good condition"` — a follow-up clarification sentence saved as if it were the product name.
- `GET /api/products/search?q=car&limit=10` returned `{"items":[]}` — neither listing is findable by the word "car", because neither title contains it.

Root-cause trace (code-level, not speculation):
- `universal_ai_assistant_service.py`'s `decide()` has always computed a clean, sanitised `entities` dict (`subject`, `quantity`, `unit`, `location`, `price`, and more — see `ALLOWED_ENTITY_KEYS`) and returned it as part of its result dict.
- `backend/app/api/routes/in_app_assistant.py`'s `AssistantDecision` response model, however, never declared an `entities` field. Pydantic's default `extra="ignore"` behaviour meant this dict was silently dropped from every single `/api/in-app/assistant` HTTP response — the field was computed correctly on every request and then thrown away before the app ever saw it.
- The Flutter side (`lib/services/in_app_assistant_service.dart`) already had full, correct, previously-dormant support for parsing an `entities` map out of the JSON response (`InAppAssistantDecision.fromJson`, `entityText()`, `entityNumber()`) — this was built ahead of time and never exercised in production, because the map coming from the backend was always empty.
- `AskodoxSemanticDealInput.build()` (`lib/features/home/domain/semantic_deal_input.dart`) builds its routed payload from exactly these entities (`subject`, `quantity`, `unit`, `location`). With `entities` always empty, `parts` was always empty, so `build()` always fell back to `original.trim()` — the user's raw, unedited chat message — which is exactly the garbled titles seen in production. Separately, `build()` never read a `price` entity at all, even once entities exist, so price would have stayed null regardless.
- This bug was actually found earlier, during round 6, and its fix was **deliberately deferred** at the time (see the round-6 entry above: "found but deliberately not fixed this round ... needs its own dedicated, test-covered round rather than being bundled in here"). This round is that dedicated fix, now made necessary by live production evidence of real data loss rather than a theoretical gap.

Fix shipped this round (3 files):
- `backend/app/api/routes/in_app_assistant.py`: added `entities: dict[str, Any] = Field(default_factory=dict)` to `AssistantDecision`. This is the actual fix — it turns on entity delivery for every domain at once (PRODUCT, FOOD, STAFFING, JOB_SEEKER, SERVICE, PARCEL, RIDE, APPOINTMENT), not just the one that was reported, since the field was equally being dropped for all of them.
- `lib/features/home/domain/semantic_deal_input.dart`: added `decision.entityNumber('price')`, rendered as `'₹<amount>'` and appended to `parts` last (after location), so it flows into the routed payload text and `UniversalDealBrain._price()` picks it up.
- `lib/features/deal_brain/application/universal_deal_brain.dart`: updated subject and location extraction to stop at a trailing `₹<amount>`, and to strip a bare trailing price when no location phrase is present.

Verification performed:
- Backend syntax and the existing backend repository tests remain the targeted validation for the API model change.
- The Flutter parser changes preserve the existing routing shape while carrying the extracted price through to deterministic deal parsing.

Known gaps, explicitly not started this round:
- `budget`/`salary`/`pay` entities are still not read by `semantic_deal_input.dart`; wiring those up is a separate round if needed.
- Existing production rows with garbled titles/null prices are not retroactively fixed by this change.
- The AI-reply grounding gap noted in the round-6 entry is still not fixed.

Next action: apply this instruction file, wait for `flutter-ci.yml` and `backend-monorepo-smoke.yml` to go green, **create and merge a pull request**, publish a new Android release, update the app, then re-test selling "Maruti 800" for ₹50,000 and confirm through the product search API that the saved title and price are correct.

### 2026-09-16 (round 8) — Product-owner correction: "Place order" was a one-tap instant deal for every category alike, with no consent step and a real phone-number privacy leak

Round 7 was confirmed genuinely merged and working end-to-end from the product owner's own screenshots: selling "Maruti 800" for ₹50,000 now saves a clean title and correct price, a buyer can find and order it, and the order appears on both `My orders` and `Incoming orders`. The product owner then raised a deeper objection to the flow itself, not to any bug in it: tapping "Place order" instantly creates a real order for a bag of rice and a used Maruti 800 alike, with no step in between for the seller to actually agree to anything. The product owner pointed to how real marketplace/classifieds platforms (OLX, Cars24, IndiaMART, Urban Company, and "thousands of other products" across sectors) always require both parties to express interest, reach mutual acceptance, and exchange contact -- only then does a deal close -- and asked for this correction to be added to the roadmap and implemented immediately.

This was **not taken as only a UX complaint** -- it was checked directly against this project's own existing specification and against what the "Place order" button's data actually contains:

- `docs/ASKODOX_MASTER_ARCHITECTURE.md` Point 13 ("Party A / Party B Consent") already states: "Contact details are not shared before both parties accept." Point 22 ("Universal Deal State Machine") already specifies a `Request -> Understand -> Match -> Negotiate -> Both Accept -> Deal Confirm -> Fulfilment -> ...` flow. The round-5/7 "Place order" button violates both of these points that were already written down before this round -- this is a compliance gap against this project's own architecture, not a new feature being requested for the first time.
- Checking `order_repository.py`/`orders.py`'s `OrderResponse` model against `AuthController.completeOnboarding()` (which builds each user's id as `'phone-$digits'`, later prefixed `'app-'` by `order_repository.dart`'s `_appUser()`) confirmed that `buyer_user_id`/`seller_user_id` are not opaque identifiers -- they are literally the other party's phone number, in `"app-phone-<digits>"` form. The order API was returning **both** parties' phone numbers in every response, in every status, including the instant a buyer merely sends a request nobody has agreed to yet. This is a real, independently-found privacy leak, not just a missing negotiation step.
- The already-existing `POST /api/orders/{order_id}/status` endpoint and `VALID_STATUSES = ("PLACED", "ACCEPTED", "REJECTED", "FULFILLED", "CANCELLED")` (both shipped in round 5) already model exactly the accept/decline step this correction needs -- but no screen in the app has ever called this endpoint. The gap was flagged in round 5's own tracker entry ("No accept/reject/fulfil UI for the seller on `IncomingOrdersScreen` yet") and left open until now.

The roadmap (published as a Claude artifact) was updated with a new, top-priority Phase 0 ("Contact only after both sides agree") ahead of all 9 previously-planned phases, tagged against Master Architecture Points 13 and 22, before any code was written -- per the product owner's explicit request to "add this correction to all and make all to roadmap phase."

Fix shipped this round (6 files):
- New `backend/app/services/order_contact_visibility.py`: a small, deliberately dependency-free module (no FastAPI/pydantic import, unlike every other backend file touched this session) exposing `mask_contact_for_viewer(row, viewer=...)`. It withholds the *other* party's `..._user_id` field unless the order's status is `ACCEPTED` or `FULFILLED`; an unrecognised `viewer` value masks both sides rather than defaulting to showing anything. Kept dependency-free specifically so it could be unit-tested directly in this audit environment, where `fastapi`/`pydantic` are not installable (confirmed again this round: `pip install fastapi pydantic` fails with no matching distribution).
- `backend/app/api/routes/orders.py`: `_to_response()` now takes a `viewer` ("buyer" or "seller") and calls the new masking function before building `OrderResponse`. All 4 existing call sites (`place_order`, `my_orders`, `incoming_orders`, `update_order_status`) updated to pass the correct viewer for who is calling that endpoint.
- New `backend/tests/test_orders_contact_masking.py`: parametrized pytest cases covering both viewers, all 5 statuses (split into "hidden" vs "revealed" groups), case-insensitive status matching, and that the input row is never mutated. This project's minimal pytest-shim used elsewhere this session does not support `@pytest.mark.parametrize`, so this file could not be run through it in this audit environment; the underlying function's correctness was independently confirmed via an equivalent manual assertion script covering the same cases, which passed. The test file itself is standard pytest and will run normally under real CI.
- `lib/features/orders/data/order_repository.dart`: `Order` gained `sellerContact`/`buyerContact` getters that turn whichever id the backend chose to reveal into a plain phone number (via a `app-phone-(\d+)` pattern match), returning `null` both when the backend withheld it and when the other side is a guest with no real phone. `OrderRepository`/`ApiOrderRepository` gained `respondToOrder({orderId, status, sellerNote})`, POSTing to the already-existing `/api/orders/{id}/status` endpoint -- the first UI-reachable caller of that endpoint since it was built in round 5.
- `lib/features/orders/presentation/order_screens.dart`: `_OrderCard` converted from a read-only `StatelessWidget` to a `ConsumerStatefulWidget`. It now shows Accept/Decline buttons (seller-only, only while `status == PLACED`) wired to `respondToOrder()`, with loading/error state; and a tap-to-copy contact row (seller's number for the buyer, buyer's number for the seller) that only ever appears once the backend itself has revealed that contact -- there is no client-side override of the masking. `_statusLabel` rewritten to use one `_t()`-based mapping for both languages (previously English silently fell back to a raw enum string while only Telugu had real wording), and `PLACED` now reads "Requested"/"అభ్యర్థించారు" instead of "Placed"/"ప్లేస్ చేయబడింది", matching the corrected mental model. Empty-state copy on both `MyOrdersScreen` and `IncomingOrdersScreen` updated from "orders"/"ఆర్డర్లు" wording to "requests"/"అభ్యర్థనలు" wording for the same reason.
- `lib/features/home/presentation/askodox_primary_home_screen.dart`: the buyer-facing button and its messages renamed to match what actually happens now -- "Place order"/"ఆర్డర్ చేయండి" -> "Send request"/"అభ్యర్థన పంపండి"; "Order placed! The seller can now see it." -> "Request sent! The seller can now review and accept it." (and the Telugu equivalents); error copy similarly reworded from "place this order" to "send this request."

Verification performed:
- `order_contact_visibility.py` and `orders.py` both `ast.parse` clean; grepped the whole repository to confirm `_to_response` has no other callers than the 4 already updated.
- `mask_contact_for_viewer`'s logic independently re-verified via a manual assertion script (all cases from the new test file, run directly rather than through the project's pytest-shim, which does not support `@pytest.mark.parametrize`) -- all checks passed.
- All 3 touched `.dart` files hand-traced for brace/paren/bracket balance and diffed line-by-line against the current `main` branch to confirm every change is additive/intentional (no Flutter SDK reachable from this audit environment, same limitation noted in every prior round's Flutter changes).
- **Not yet verified by `flutter-ci.yml`/`backend-monorepo-smoke.yml`** — wait for both to go green after this instruction file is applied and pushed.

Known gaps, explicitly not started this round:
- No in-app messaging/negotiation between buyer and seller before acceptance -- today's fix gates *contact exchange* on acceptance, but a buyer and seller still cannot ask each other a question inside the app before that point (e.g. "is the car still available", "can you do ₹45,000"). This is Phase 0's own next step, not yet built.
- No way for a buyer to cancel/withdraw a request they sent (`CANCELLED` exists in `VALID_STATUSES` but nothing in the UI sets it).
- Declining a request does not notify the buyer beyond them seeing the status change next time they open `My orders` -- there is no push/SMS notification for any order-status change yet.
- The AI chat flow itself (`universal_deal_brain.dart`/`semantic_deal_input.dart`) still talks about "placing an order" in its own reply text in some branches -- only the two Flutter screens above were re-worded this round; a broader pass over the AI's own chat copy was out of scope to keep this round reviewable.
- Existing already-placed production orders are unaffected structurally (their `status` values are unchanged) but will retroactively start hiding contact details on any order not already `ACCEPTED`/`FULFILLED`, the moment this ships -- this is the intended fix, not a regression, but worth the product owner knowing before re-testing.

Next action: apply this instruction file, wait for `flutter-ci.yml` and `backend-monorepo-smoke.yml` to go green, **create and merge a pull request**, publish a new Android release, update the app, then re-test end-to-end: send a request as a buyer (button now reads "Send request"), confirm the seller's "Incoming orders" screen shows it without a Decline/Accept-gated contact number visible, tap Accept, and confirm the buyer's number becomes visible to the seller *and* the seller's number becomes visible to the buyer, in both directions. Also test Decline and confirm contact stays hidden. After this verification, resume whichever roadmap phase the product owner selects next (Phase 1 "Reconnect what already works" onward).

## Current Overall Status
52 top-level points are tracked. Point 1 remains IN PROGRESS. The canonical core channel is now in-app and a WhatsApp text support-only gate plus passing smoke test are implemented, but full CI/deploy, real in-app E2E, and remaining WhatsApp media/location separation are still pending. Point 44 has locked reusable dummy/demo account and final E2E regression requirements. Point 51 is now IN PROGRESS rather than requirement-only because a real text-routing guard exists, but it is not GREEN until case/admin-sync and all remaining paths are verified.
