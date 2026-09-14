# ASKODOX Decision Record — Unified In-App AI Customer-Care Experience

Status: LOCKED CURRENT DECISION
Date: 2026-09-14
Applies to: ASKODOX overall product architecture, AI conversation layer, Flutter app UX, backend, category/matching engine, admin/analytics
Supersedes/extends: `docs/decisions/2026-09-11-whatsapp-support-channel.md` (that decision is reaffirmed and this record adds the concrete product/architecture consequence of it)

## Background
The project was originally planned around a WhatsApp-style customer-support experience. Because of WhatsApp/Meta platform restrictions, verification difficulty, and limits on achieving the required behavior there, the owner has decided the WhatsApp-like experience must be delivered **inside the ASKODOX app itself**, not on WhatsApp. WhatsApp remains only a secondary support/escalation channel per the 2026-09-11 decision.

## Decision
1. The ASKODOX app must provide the complete WhatsApp-like customer-care experience natively — the user should feel they are chatting with an intelligent customer-care assistant, not operating menus/forms/technical workflows.
2. Text, voice, images, products, services, requests, matching, recommendations, support, complaints, appointments, deals, follow-ups, notifications, and history must all work from the same AI conversation experience.
3. Do NOT rebuild the project as separate disconnected apps, pages, bots, or independent systems. All development stays in ONE unified app/backend/codebase.
4. Existing completed development must be reused, not rebuilt. Before any change: inspect existing codebase/architecture/DB/APIs/backend/Flutter/AI modules/completed flows first.
5. New features must be built as reusable modules that work across categories, not duplicated per category. The matching/question engine stays common; each category supplies its own dynamic questions, recommendation logic, and results.
6. The AI conversation is the MAIN interface and gets maximum screen space/priority. Forms, catalog, maps, deals, history, admin, etc. surface only when the conversation needs them — this is not an e-commerce-style interface.
7. One continuous user journey: request → AI understands intent → asks only necessary missing questions → identifies category → collects required info → searches/matches → recommends options → buyer/seller/provider interaction → acceptance → contact sharing when permitted → deal/service completion → payment/delivery confirmation where applicable → review/support/follow-up.
8. Conversation history and user progress must persist so users are never asked to repeat information already given (this includes location — see the open gap in `docs/ASKODOX_MASTER_DEVELOPMENT_STATE.md`/execution tracker about the assistant request not yet carrying saved/default location).
9. Buyer, seller, service-provider, jobs, appointments, delivery, catalog, influencer, offers, support, admin, analytics, search, voice, vision, location, multilingual, and notifications all stay connected to the SAME core AI system and the SAME underlying data — one source of truth for shared models, user profiles, categories, conversations, matching, permissions, language, location, and transaction/deal status.
10. Language and location must work across the whole app, not per-screen, and must persist across screens and app restarts.
11. Development workflow for every change: CHECK EXISTING IMPLEMENTATION → REUSE WHAT EXISTS → IDENTIFY THE GAP → MODIFY/EXTEND → INTEGRATE → TEST → VERIFY → COMMIT/PUSH. Never create a duplicate implementation because a feature was requested again — find and extend the existing one.

## Final Target
One app. One AI customer-care experience. One connected backend. One user history. One category/matching engine with category-specific logic. One admin & analytics system. One development codebase. WhatsApp-support-level simplicity for the user, with capabilities far broader than WhatsApp, fully controlled inside ASKODOX / AI CONNECT.

## Relationship to Earlier Architecture
REAFFIRMED: `docs/decisions/2026-09-11-whatsapp-support-channel.md` — WhatsApp stays support-only.
NEW: This record makes explicit that the WhatsApp-like *user experience* (natural chat-first customer care) is a first-class in-app requirement, not something deferred or built as a side system.

## Implementation Acceptance Criteria
This decision is not GREEN until:
1. The primary home/chat screen remains the dominant surface for all transaction types (already true for the categories audited so far — home chat routes to `UniversalDealController`).
2. Category-specific dynamic questions exist for more than the single hardcoded case (chicken) found in `UniversalDealBrain._dynamicFields` during the 2026-09-14 forensic audit — this is the concrete current gap against point 5 above.
3. The assistant request (`InAppAssistantService.decide` / `POST /api/in-app/assistant`) carries known context (e.g. saved/default location) so the AI does not re-ask for information the app already has — concrete current gap against point 8 above, found during the same audit.
4. No new feature is added as a disconnected page/bot/module without integrating into the shared conversation + matching engine.
5. Tests verify the conversation-first flow end-to-end for at least one representative category beyond chicken/product.

## Note on process
Per the existing Continuity Lock (`docs/ASKODOX_CONTINUITY_LOCK.md`), this record is the persisted source of truth for this instruction so it does not need to be re-explained in a future chat/session.
