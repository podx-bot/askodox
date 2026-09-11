# ASKODOX Master Architecture — Source of Truth

Status: ACTIVE MASTER SPECIFICATION
Updated: 2026-09-11
Purpose: Persistent external source of truth for ASKODOX requirements, decisions, gaps, flows, business modules, UX rules, and completion gates. This file must be checked before changing or implementing a feature so previously agreed requirements are not silently dropped.

## 1. Core Identity — LOCKED
ASKODOX is NOT a Local Commerce app, ecommerce app, marketplace-only app, or simple Q&A chatbot.

ASKODOX = Everyday AI Friend + Helping Mind + Decision Partner + Action Assistant.

Core promise: Understand the user's real situation, remember context, ask only missing questions, think through options, explain tradeoffs, recommend what benefits the user, connect or act when useful, and stay with the user until the problem is solved.

Core loop:
ASK → UNDERSTAND → REMEMBER → CLARIFY ONLY MISSING POINTS → THINK → COMPARE → ADVISE → SUGGEST → CONNECT/ACTION → HELP UNTIL DONE → LEARN/IMPROVE.

Permanent principle: USER BENEFIT FIRST. Local, online, affiliate, BFSI, products, services, jobs, travel and other channels are solution sources, not ASKODOX's identity.

## 2. Eight Master Layers
1. Understand Me — text, voice, photo, language, location, context, memory, budget, urgency, preferences.
2. Think for Me — only needed questions, pros/cons, risk, affordability and alternatives such as buy/repair/rent/used/do-not-buy.
3. Find Solutions — local, nearby, online, affiliate/non-affiliate, professionals, services, BFSI, jobs, travel, education, government/public resources.
4. Recommend Fairly — rank for user benefit, not commission; explain why each recommendation fits.
5. Connect & Act — matching, chat, consent, negotiation, booking, appointment, delivery, payment path, applications/referrals where appropriate.
6. Stay Until Done — fulfilment, tracking, confirmation, cancellation, return/refund, dispute, invoice, review, after-sales support.
7. Protect the User — verification, privacy, fraud/scam protection, financial safeguards, consent, security and human escalation.
8. Learn & Improve — history, memory, unfinished-flow resume, feedback, trust, analytics, no-match intelligence and AI self-gap detection.

## 3. Universal Roles
Buyer, Seller, Service Provider, Survey Taker, Employer, Worker/Job Seeker, Driver/Rider, Courier/Delivery Partner, Expert/Professional, Creator/Influencer, and future roles. One person may hold and switch multiple roles.

## 4. Registration / Identity
Language → mobile OTP → name → role selection → natural-language need/offer. Support OTP retry/expiry/fallback, duplicate-account handling, business/driver document verification, expiry/reverification, suspension/reactivation and fake identity detection. Do not guess user gender.

## 5. Universal Need Understanding
Accept text/voice/photo. Extract category, intent, budget, quantity, location, urgency, date/time, quality and preferences. Never re-ask known information. Low confidence must trigger a concise clarification or broader search rather than a confident wrong answer.

## 6. Dynamic Categories
100+ category-specific schemas/questions. Do not reuse the same questions blindly. Wrong category mapping must be blocked. Admin can add/edit category schemas. Common engine + domain-specific modules, not 100 duplicated flows.

## 7. Matching Engine
Rank by relevant combination of location/distance, budget/price, availability/stock/capacity/time, quality, verification, trust, response and user preferences. Show reasons. Rejection/no-response moves to next candidate. Local is a useful source, not a mandatory identity or always-first rule when user intent indicates otherwise.

## 8. Local → Nearby → Online / External Fallback
When an appropriate local solution is unavailable, automatically expand nearby and then surface suitable online/external solutions. The user should not have to repeat the request. Preserve budget, specifications and other constraints.

## 9. Affiliate + Non-Affiliate Neutrality
Show the best fitting solution whether or not ASKODOX receives affiliate commission. Affiliate status must never control recommendation ranking. Track eligible attribution/conversion revenue and clearly distinguish sponsored/affiliate relationships where required.

## 10. Universal Online Comparison
Compare meaningful total value: price, specifications/quality, availability, delivery, warranty/returns, source reliability and user constraints. Explain why an option is better for this user rather than simply sorting by price.

## 11. BFSI / Financial Products
Dedicated regulated-domain layer for bank accounts, loans, credit cards, insurance, deposits and investments where supported. Compare eligibility, fees/interest, tenure, conditions, risks and official/provider information. Apply suitability, disclosure, privacy and regulated-source checks. Never rank a financial product higher merely because referral commission is higher.

## 12. Life & Business Ecosystems
Support modular routing for: products; services; jobs/careers; rides/travel; courier/parcel/delivery; appointments/bookings; BFSI; education; health navigation; government/citizen services; home/family; food/daily needs; real estate; business assistant; vehicle assistant; legal-help navigation; agriculture/rural assistance; events/family planning; senior support; student help; emergency/problem solving; subscriptions/bills; used/second-hand; experts/professionals; creators/influencers; deals/savings; after-purchase support; life opportunities.

ASKODOX must not convert every problem into a purchase. Correct advice may be repair, rent, reuse, wait, use a free official service, avoid a loan/product, or contact an appropriate professional.

## 13. Party A / Party B Consent
Structured capture by role/domain. Contact details are not shared before both parties accept. Material changes to price/scope/time/terms invalidate previous acceptance and require reconfirmation.

## 14. AI Negotiation / Conversion Assistant
Help both sides understand requirements, compare fair pricing, respond, negotiate, translate, summarize final terms and complete the deal/work without manipulative pressure.

## 15. Seller / Business Module
Business profile, products/services, hours, service radius, availability, pricing, photos, stock, offers, chat, leads/requests, repeat customers, ledger and performance insights.

## 16. AI Catalog
Photo → detect item → title → description → category → variants/sizes → suggested/default editable rate → multiple images. Include near-image matching, duplicate detection, photo-quality guidance and scalable/bulk paths.

## 17. Service Lifecycle
Request → match → quote → accept → appointment/schedule → travelling/arrived where relevant → started → completed → customer confirmation → payment/completion → review. Service flows must not be forced into a product-order lifecycle.

## 18. Jobs Lifecycle
Employer/worker matching using skills, location, compensation and availability; consent before contact; application/interview/hired/not-hired states; fake-job and abuse protections.

## 19. Ride Lifecycle
Passenger/driver, route extraction and overlap, pickup/drop, fare, driver verification/availability, acceptance, start/end, cancellation/no-show and safety/privacy controls.

## 20. Delivery / Courier Lifecycle
Delivery method selection: seller delivery / delivery partner / self pickup / no courier. Courier availability before conditional payment where applicable; matching/reassignment; pickup OTP/proof; tracking; delivery OTP/proof; failed delivery; unavailable customer; damage; redelivery; return-to-sender.

## 21. Payment Architecture
Prefer not to hold user funds unnecessarily. Support appropriate direct seller QR/offline/referral paths and optional protected transaction models when justified. Explicit payment states: Pending, Confirmed/Authorized, Fulfilment, Completed/Released, Refunded, Disputed. Prevent duplicates and preserve proof/audit. Payment initiation must not be treated as fulfilment completion.

## 22. Universal Deal State Machine
Request → Understand → Match → Negotiate → Both Accept → Deal Confirm → Fulfilment → Payment state as appropriate → Prepare/Start → Pickup/In Progress → Delivered/Completed → Customer Confirm → Invoice → Review → Closed.
Domain modules may alter valid transitions, but shared identity/consent/trust/chat/notifications/audit remain common.

## 23. Cancellation / Refund / Return / Replacement
Handle buyer/seller/provider/courier cancellations, post-payment cases, partial refunds, failed delivery, returns, replacements, wrong/damaged goods, service issues, deadlines and evidence.

## 24. Disputes
Reason/evidence → AI triage → admin/human escalation when needed → decision → refund/release/resolution → notifications → immutable audit trail.

## 25. Trust / Reviews / Fraud
Trust uses verified identity/business, completed deals, response/fulfilment, cancellations/disputes, legitimate reviews and suspicious behavior. Reviews only after real completion. Detect fake/duplicate/review-ring manipulation. Provide report/block/rate-limit controls and protections against spam, harassment, fake payment/delivery and no-shows.

## 26. Location / Maps
Permission-aware location, manual selection, GPS denied/off/inaccurate handling, radius/nearby/global addresses, location change, directions, courier tracking, ride routes, pickup/drop, distance/ETA and privacy. Keep Location and Language compact in the header.

## 27. Language / Voice
Auto/suggest language from context/location with manual change anytime and persistence after restart. UI + AI + STT + TTS stay synchronized. Voice states: listen → understand/think → speak. Support correction, interruption/retry, Automatic/Male/Female preference and safe TTS fallback. Never infer gender.

## 28. Memory / History
Remember relevant recent searches, chats, active deals, preferences and unfinished flows. Save/resume last step and recover after app restart. The external Master Architecture is the product source of truth and must not rely on ChatGPT conversational memory alone.

## 29. Vision / Photo Search
Recognition, local/online similar products, catalog creation, visual search, unclear-photo handling and seller photo-quality assistance.

## 30. Influencer / Creator + Deals
Video recommendations/reviews/creator content, with sponsored vs organic distinction and misleading-promotion protection. Personalized offers with expiry/spam controls.

## 31. Notifications / Customer Desk
In-app primary notifications for match, accept/reject, messages, quote, appointment, courier, pickup, ETA, delivery, payment, refund, dispute and resolution. Retry failed notifications. AI Customer Desk gets full deal context and escalates unresolved issues with context handoff; call button is for unresolved escalation.

## 32. Admin Control Center
In-app preferred. CRUD/manage/suspend users and businesses, verification, disputes, catalog moderation, matching override, support, offers/content/config. Every manual override records who/when/why.

## 33. Analytics / Opportunity Intelligence
Searches, no-match, rejection, abandonment, conversion, joins, daily business/deals, category/geographic demand, response, disputes, delivery failures, retention, rise/fall reasons and downloadable reports. Repeated no-match patterns should become demand/business-opportunity insights.

## 34. Privacy / Security
Least-data principle; no premature contact sharing; exact address only when needed; protect contact/location/documents; admin RBAC; consent/deletion controls; OTP abuse protection; session/API auth; encryption; secret handling; webhook verification; replay protection; audit logs.

## 35. Failure Recovery
Handle network/app/server/API failure, double tap, duplicate webhook, OTP failure, payment callback loss, courier/seller/provider disappearance, retry, idempotency, offline/resume and safe recovery.

## 36. Inventory / Capacity / Pricing
Stock reservation/concurrency/oversell prevention; provider capacity; unavailable fallback. Quotes/rates, delivery fee, tax/GST where relevant, discount, advance/partial payment and price changes requiring renewed consent.

## 37. Invoice / Ledger
Deal summary, payment/refund records, business ledger and downloadable/shareable invoice/receipt where applicable.

## 38. Global Architecture
No unnecessary India hardcoding. Country, language, currency, address, timezone, payment/provider integrations and compliance behavior must be configurable by market/domain.

## 39. AI Self-Gap Detection
Before advancing a flow, ASKODOX checks: identity? intent? missing requirements? consent? final terms? safety? payment state? fulfilment? completion proof? review eligibility? If a required gate is missing, do not silently proceed.

## 40. Recommendation Quality / User Agency
Recommendations combine relevant price, distance, quality, availability, trust, urgency and preferences. Explain “why this”. User makes the final decision. Present alternatives. Warn with reasons when a choice appears harmful or poor, without forcing.

## 41. UI Core Rules
Bright, clean, AI-first; maximize chat space; avoid ecommerce clutter; compact Location + Language; history/results on Home; secondary flows open on demand; one-main-page feel where practical. Robot states should reflect real listening/thinking/searching/matching/speaking/success/error state.

## 42. Accessibility / Performance
Low-end Android and slow-network support, large text/accessibility, voice-first usability, multilingual fonts, fast startup/loading, no overlap/double pane/type blocking, graceful degraded network behavior.

## 43. Release / Backend / Observability
API-first modular architecture: app, DB, AI, maps, voice, search, payments, notifications, admin independently replaceable/scalable. Preserve active deals through updates/migrations. Signed APK/AAB, CI, staging/prod, rollback and visible versioning. Monitor errors, latency, AI/matching/payment/notification/courier failures, crashes and server health with actionable alerts.

## 44. Testing / Demo
Unit, integration, UI, E2E, security, load, multilingual, device, failure/chaos tests. Explicit tests for disappearing parties, bad network, duplicate payment, wrong category, GPS failure, consent invalidation, courier failure, refunds/disputes. Demo environment must contain realistic dummy buyers, sellers, providers, employers/workers, drivers/couriers, products/services, locations, payments, no-match, cancel and dispute scenarios.

## 45. Completion Gate — NON-NEGOTIABLE
A feature is GREEN only when:
1. Requirement is defined.
2. Code exists.
3. Integration exists.
4. Relevant tests pass.
5. CI/build passes.
6. Real end-to-end flow is verified.
7. Failure/edge cases are checked.
8. Admin/audit behavior is checked where relevant.

Code existence, mockups, plans, or verbal confirmation alone are NOT GREEN.

## 46. Change-Control Rule — PREVENT LOST REQUIREMENTS
For every new user requirement or correction:
1. Capture it in this Master Architecture or a linked requirement ledger.
2. Identify which existing section/flow it changes.
3. Check for conflicts with previous decisions.
4. Update acceptance criteria and affected tests.
5. Only then implement.
6. Do not delete an old requirement silently; mark it SUPERSEDED with the replacement and date/reason.
7. Before declaring a feature complete, compare implementation against this master source.

If a method fails twice, reassess/change the method rather than repeatedly applying the same failed approach.

## 47. Historical / Superseded Positioning
Earlier PODX documents described a WhatsApp ride/lead platform and later local-commerce concepts. Preserve them as project history, but they do not override the current ASKODOX core identity.

SUPERSEDED: “ASKODOX/PODX is primarily a Local Commerce app.”
CURRENT: “ASKODOX is an Everyday AI Friend and Helping Mind; local commerce is one optional solution channel.”

## 48. Revenue Principles
Possible revenue channels: affiliate commissions, BFSI/referral fees where compliant, business subscriptions/SaaS, premium AI features, clearly labelled promoted placements, service/lead tools, and optional transaction-protection fees. Revenue must not distort the user's recommendation.

Permanent rule: ASKODOX earns after helping the user; it must never recommend a worse option merely because it earns more.

## 49. Working Audit Checklist
For every feature change, explicitly review:
- Product/core logic
- UX
- Admin
- Security/privacy
- Fraud/trust
- Payment/refund/dispute implications
- Delivery/courier/pickup implications
- Retry/timeouts/offline
- Notifications
- Permissions
- Analytics/audit
- Scalability/cost
- Localization/accessibility
- Testing/verification

## 50. Master Principle
Do not depend on chat memory as the canonical specification. This GitHub document is the persistent source of truth. Future detailed requirements should be appended/updated here (or in linked versioned docs) before they are considered locked.
