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

Next action:
- Verify Flutter CI and deployment for commit `48889f4e201d7aca0a78edc91da84285272a8eda`.
- Audit WhatsApp audio/image/document/location paths so none can bypass support-only policy.
- Verify a real in-app conversation E2E path and the full friend-like decision loop.
- Reassess Point 1 only after all evidence is green.

Regression impact:
Potentially affects onboarding, memory/history, notifications, customer desk, WhatsApp support routing, job/ride legacy WhatsApp behavior, and any runtime handlers that previously assumed WhatsApp was the canonical channel.

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

Remaining requirements before Point 51 can be GREEN:
- Real support Case ID repository/creation.
- Admin/customer-care queue/history and closure status.
- Sync important WhatsApp support outcomes back into ASKODOX history/audit.
- Audit/separate audio, image, document, and location paths so no legacy business flow bypasses the support-only policy.
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