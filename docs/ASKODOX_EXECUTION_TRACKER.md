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

Code evidence found:
- `backend/app/services/universal_ai_assistant_service.py` implements an OASAT GENERAL path and explicitly tells ASKODOX to answer naturally, use the user's language, avoid forced shopping/local-commerce flows, avoid fake live-web claims, and avoid inventing actions.
- `backend/app/api/app_factory.py` wires live/deep research, universal AI, user memory, ConversationOS, and a customer-facing response policy into the conversation stack.
- User memory repository/service is instantiated and supplied to ConversationOS.

Test evidence found:
- `.github/workflows/universal-ai-assistant-smoke.yml` exercises GENERAL routing, same-language prompt behavior, commerce delegation, provider failure fallback, and readiness checks.
- `.github/workflows/user-memory-smoke.yml` exists for the user-memory / ConversationOS path.

Known gaps / blockers to GREEN:
- `backend/app/api/app_factory.py` currently constructs `ConversationOSRuntimeService(... channel="whatsapp")`. This conflicts with Point 51, where WhatsApp is support-only and the ASKODOX app/in-app experience is the core channel.
- The universal assistant service covers the GENERAL path, but this audit has not yet proved the full friend-like decision loop (understand → remember → clarify only missing → compare → advise → action → help until done) end-to-end across in-app routing.
- Current CI/build result for this exact audited state has not yet been attached to this point.
- Real in-app E2E verification has not yet been attached.

Next action:
- Separate the core ConversationOS channel from WhatsApp support routing; make the in-app conversation path the canonical core path while preserving WhatsApp for support/escalation only.
- Add/adjust regression tests proving the core identity is not commerce-forced and that WhatsApp support cannot become the main business/AI route.
- Re-run/verify relevant CI and real in-app flow, then reassess Point 1 for VERIFIED GREEN.

Regression impact:
Potentially affects onboarding, memory/history, notifications, customer desk, WhatsApp support-only routing, and any runtime handlers that assume `channel="whatsapp"`. These must be checked before the channel change is declared complete.

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
Status: REQUIREMENT LOCKED; implementation verification pending.

WhatsApp is NOT the core ASKODOX business, matching, commerce, deal, or AI workflow. It is a secondary support channel for customer care, complaints, HR, admin support, verification assistance, unresolved issue escalation, and support follow-up. WhatsApp support interactions should create or link a Case ID, retain resolution status/history, and sync relevant outcomes into ASKODOX admin/audit records.

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
52 top-level points are tracked. Point 1 audit has started and is IN PROGRESS with concrete code/test evidence plus a verified channel-architecture gap. Point 44 now has locked reusable dummy/demo account and final E2E regression requirements. Requirements/process are defined, but this does NOT mean all 52 are implemented or GREEN. Actual implementation status must be audited from repository and CI evidence point by point before any completion percentage is claimed.
