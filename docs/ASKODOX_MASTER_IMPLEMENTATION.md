# ASKODOX Master Implementation Direction

Status: LOCKED

ASKODOX is an AI-first Local Commerce / Local Services / Local Discovery product. The AI conversation is the primary experience; commerce, sellers, services, deals, requests, maps, appointments and support open contextually only when needed.

## Execution order
1. Backend/core functionality
2. Integrations
3. Matching/search/AI flows
4. Hybrid admin system
5. Analytics/reports
6. Testing
7. Final UI design system
8. Final screens/polish
9. Animations
10. Responsive/accessibility pass
11. End-to-end test
12. Release verification

## Locked core chat behavior
- Home is chat-first.
- Text/voice starts from the main ASKODOX input.
- Home expands into full conversation mode on the SAME screen; do not navigate to a separate chat page.
- Promotional/activity/suggestion content may collapse when chat starts.
- Contextual results, seller/service profiles, requests, maps and business pages open only when needed.
- Back returns to the active conversation without losing context.

## Locked home behavior
- Compact ASKODOX header.
- Only compact Location and Language actions near title.
- Location and language open selection flows.
- Promotion/banner may appear above the input.
- Use one compact horizontal mixed activity row for nearby/community activity, deals/offers, new businesses/services and relevant opportunities.
- Preserve vertical space for conversation.
- AI-assistant-first visual identity; avoid ecommerce-feed behavior.

## Buyer flow
- Natural text/voice intent capture.
- Detect category, budget, location, preferences and constraints.
- Local matches first; then local alternatives; online fallback only when appropriate.
- Photo search: exact/same product, closest match, similar alternatives, nearby availability, price, distance.
- Confidence shown only when technically reliable.
- No forced catalog browsing.

## Seller/service-provider flow
- Natural-language registration and offer description.
- AI-assisted listing/catalog draft from photo.
- Draft title, category, description, likely attributes, color, variant/size fields and tags.
- Never finalize uncertain image-inferred values.
- Price, exact size, stock, brand, material and uncertain data remain editable/confirmable.
- Flow: Photo Upload -> AI Draft -> Seller Review -> Corrections -> Preview -> Publish.
- Full manual mode remains available.
- Image assistance may include crop/background cleanup/clarity/catalog formatting; original seller image remains primary.

## Contact/support escalation
ASKODOX AI -> Seller Chat if needed -> Seller Contact if still needed -> ASKODOX Support -> Call only when necessary.

No permanent call buttons. Preserve in-app conversation history.

## Hybrid admin system
- Main admin: separate secure Web Admin Console.
- App admin mode: limited quick/emergency controls only.
- No secret-code-only production entrance.
- Secure login, role-based access, 2FA/biometric where applicable.
- Roles: Super Admin, Operations, Support, Content Admin, Verification Admin, Analytics/Reports.
- Support add/edit/modify/enable/disable/delete/restore/save/draft/preview/publish/bulk update across users, businesses, listings, categories, deals, offers, banners, requests, appointments, complaints, verification, chips, notifications, plans, location/language content, support flows and safely dynamic UI visibility/configuration.
- Audit log, change history, practical rollback, risky-change confirmation, Draft -> Preview -> Publish.

## Analytics and intelligence
Track aggregated operational metrics including search behavior, voice/text/photo usage, zero-result/unmet demand, category/location demand, registrations, rejection reasons, response time, leads, chats, conversions, successful/failed deals, cancellations, complaints, repeat use, promotion performance, AI-resolution/escalation rates, retention and supply gaps.

Generate causal statements only when supported by measurable data; otherwise label as correlation/hypothesis.

## Reports
Filters: date, location, category, seller/service provider, user type, source, status, conversion stage.
Exports: CSV, Excel and PDF where useful.
Cadence: daily, weekly, monthly and custom range.

## Privacy/data governance
- Prefer aggregated analytics.
- Do not expose private conversation content unnecessarily.
- Restrict sensitive admin data by role.
- Audit sensitive access.
- Production-suitable consent/privacy handling.

## AI/discovery
Universal natural-language intent detection, multilingual support, location discovery, voice STT/TTS, photo search, permitted long-term context, context-aware results, advisor behavior, safer/better alternatives, unmet-demand tracking.

## Local commerce modules
Products, services, opportunities/jobs where applicable, appointments, local delivery/riders, nearby shops, street vendors, deals/offers, requests, matching, reviews/trust, verification, maps/location, seller assist, saved items, history, notifications and planned business ledger.

## Matching rules
Intent -> structured internal fields -> local matching -> best matches -> unmet-demand admin signal if none. Contact sharing follows approved trust flow. Reviews should follow real completed interactions/deals where possible.

## Language
Selection persists across screens/relaunch. Location may suggest but not force language. User can change anytime. STT/TTS follows selected language. No gender assumptions in voice selection.

## Maps/location
Global-ready mapping, nearby discovery, distance-aware ranking, contextual map page, compact header location action.

## Quality gate
Never mark GREEN until implemented, integrated, tested and verified.
For each block: fix compile/static-analysis errors, run tests/CI, verify backend/frontend, signed release and production environment as applicable, commit/push, and report exact evidence.

## Execution mode
Proceed continuously. Parallelize independent work when safe. Do not reopen locked product decisions unless technically required. Ask the user only for credentials, external approval, payment/legal decisions or genuinely non-resolvable product choices. Preserve verified working features. Functionality first, UI polish later.
