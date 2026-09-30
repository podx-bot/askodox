# ASKODOX Owner Operating System — audit, gap matrix and plan (2026-09-30)

Staging branch `claude/friendly-ramanujan-538sbj` @ `fc23f82`. Evidence = code in this repo, the staging smoke test and
CI runs. **No phone evidence** exists yet for anything marked "phone test required". Nothing here is production.

Legend: **E** exists · **P** partial · **M** missing. Status words: NOT TESTED / CODE READY / STAGING VERIFIED /
PHONE VERIFIED / LIVE VERIFIED.

## Gap matrix

| # | Feature | Existing (evidence) | Gap | Config needed | Owner action | Claude action | Test required | Status |
|---|---|---|---|---|---|---|---|---|
| A | Unified Command Center + consistent actions | E: `/admin/console`, generic resource engine (`platform_schema.py`: create/edit/approve/reject/schedule/pause/resume/duplicate/archive/restore/delete/export/history) for 12 resources | P: bespoke pages (support, staff, flags) lack some verbs; no "why unavailable" hints on disabled buttons | – | – | Show unavailable reason on every action; add Import (CSV) where safe | Browser render | STAGING VERIFIED (pages render) |
| B | Universal Master Profile | P: one `user_profiles` row per user (`roles_json`, business fields); roles derived from requests/orders/listings; app `AskodoxUserRole` (buyer, seller, provider, job seeker, delivery, employer, driver, …) | M: admin profile view that joins roles, catalog, service areas, verification, trust, transactions, referrals, credits, support; role add/remove/verify/suspend | – | Decide which roles need verification | Build `/admin/cc/profiles/{ref}` 360° view + role actions (audited, masked) | API + phone | NOT TESTED |
| C | Seller / business control | P: listings list + enable/disable (`/admin/cc/listings`), merchant offers resource, catalog drafts, seller tiers | M: shop profile (hours, radius, social, website) editing and approval queue; photo/video moderation per listing | – | – | Add `businesses` resource (hours, radius, links, status) reusing the engine | API + phone | PARTIAL |
| D | Services / freelance / jobs / tasks | P: one Party-A↔Party-B demand engine (`universal_need_offer_records`, domain adapters for jobs/services/hotel/salon/health) | M: admin views for quotes/proposals/appointments/availability/skills/portfolios (data only partly stored) | – | Confirm priority categories | Admin filters on the same engine (no new transaction system) | Phone | PARTIAL |
| E | Orders / bookings / deals lifecycle | E: `deal_lifecycle.py` states (placed…fulfilled, product & service steps, disputed, returns), `/admin/cc/orders`, payment verify, returns | P: admin timeline view per order; delivery-specific states (driver assigned, in transit) not modelled | – | – | Order timeline drawer from existing history; no editing of financial history | Phone | PARTIAL |
| F | Delivery / driver / parcel | P: ride/parcel runtime services, route quote (`/api/discover/route`), `delivery_partner`/`driver` roles | M: driver availability, assignment/reassignment, live status, map view | Routes API on Maps key | Decide in-house drivers vs partners | Assignment model + admin map (after owner decision) | Phone (end-to-end) | NOT TESTED |
| G | Maps & location admin | P: Integrations → Google Maps per-API check (Places/Geocoding/Routes), discovery radius constraints | M: failed/stale location event log, radius settings (service/delivery/matching/notification), city/country availability | Geocoding + Routes enabled on key | Enable APIs in Google Cloud | Location settings page + event counters | Phone | PARTIAL (staging place lookup unresolved) |
| H | Notification Command Center | E: targeted promotions (audience/role/category/intent/location/radius/schedule/caps/preview/approve/pause/metrics), templates, rules, outbox | P: language targeting, "Test to me", priority/transactional types, suppressed count view | Push/SMS/WhatsApp/email creds for non-in-app | Provide channel credentials later | Add language + test-send + suppressed metrics to campaigns | Phone (in-app card) | STAGING VERIFIED (in-app) |
| I | Referral → Priority Notification Credits | P: referrals (codes, redeem), `growth_credits` ledger, reward rules per role (cash/percent oriented) | M: configurable credit slabs, expiry, max, eligible roles/types; spending credits on priority notifications; profile balance display | – | Choose slab values | `referral_credit_rules` resource + credit ledger use in promotions; profile widget | API + phone | NOT TESTED |
| J | Hyper-local opportunity engine | P: promotion audience by radius; location follows phone in foreground | M: area-entry trigger (needs background location → Play restricted), GPS accuracy guard | – | Decide if background location is acceptable (policy + battery) | Foreground-only "when you open ASKODOX nearby" triggers first | Phone | NOT TESTED |
| K | Reminder rules | P: scheduled task service (reminder/scheduled/condition_watch per user) | M: admin-configured transactional reminder rules per deal state; separation from promo credits | – | – | `reminder_rules` resource driving the existing scheduler | API | NOT TESTED |
| L | Greetings / conversation settings | P: greeting strings exist in l10n and some services | M: configurable time-of-day greetings, returning-user, role-switch, no-result/fallback texts; anti-repetition | – | Provide preferred wording | `conversation_settings` resource read by the assistant | Phone | NOT TESTED (phone finding: not working) |
| M | Video / creator control | E: videos, discovered videos (promote to review), creators, sources, reviews resources, lifecycle, associations, funnel events | P: "Add URL" validation preview for arbitrary URLs | YouTube key optional | – | Minor | Browser | STAGING VERIFIED |
| N | Links manager | P: smart links (health test), affiliate programs/links, partner hub | M: one view across internal/deep/referral/social/support/map links with last-test and clicks | – | – | Unified Links page reading existing tables | Browser | PARTIAL |
| O | Integration center | E: registry with NEEDS_CONFIGURATION/DISABLED/MOCK/TEST/LIVE/ERROR, configure (write-only), check, test-send, readiness page | P: add CODE READY / MOCK VERIFIED / LIVE VERIFIED wording; STT/TTS/vision/OTP/storage rows | Many creds (names in INTEGRATION_READINESS.md) | Provide creds when ready | Extend registry rows + status words | Staging | STAGING VERIFIED |
| P | Configuration wizard | P: Integration readiness page (7 integrations) | M: domain, email, deep links, storage, voice, vision rows with what/why/where/variable name/how to test | – | – | "ASKODOX Setup" page generated from registry + static checklist | Browser | NOT TESTED |
| Q | Domain / email / brand readiness | P: staging.askodox.com connected | M: checklist for production/app links/emails; email templates | DNS, mailboxes | Buy/configure mailboxes (no purchase by Claude) | Checklist page + template records | Owner | NOT TESTED |
| R | Support Center | E: AI → ticket → assign → reply → resolve → notify → reopen; SLA; history | – | WhatsApp/email optional | – | – | Phone (reply in app) | STAGING VERIFIED |
| S | Self-healing | E: GREEN/ORANGE/RED engine, log, rollback, toggles | P: relevance of detectors (phone finding) | – | – | Add detectors only from real failure signals | Staging | STAGING VERIFIED (mechanics) |
| T | Feature flags | E: flags + risk + approvals + audit | P: per-flag history view, environment column | – | – | History drawer from audit rows | Browser | STAGING VERIFIED |
| U | Staff / RBAC | E: 15 roles, module:verb, custom roles, advisor | – | – | Create real staff | – | Browser | STAGING VERIFIED |
| V | Approvals | E | – | – | – | – | – | STAGING VERIFIED |
| W | Audit log | E: append-only, role/risk/result, redacted, export | P: environment column | – | – | Add environment field | – | STAGING VERIFIED |
| X | Analytics / AI insights | E: funnel, categories, locations, insights (observation/reason/action/impact), revenue command | P: seller response rate, notification effectiveness, repeated fallbacks | – | – | Add 3 insight rules from existing events | Staging | STAGING VERIFIED |
| Y | Phone-test / QA center | M | – | – | Record phone results | `qa_checks` resource with the 7 status words + evidence link | Browser | NOT TESTED |
| Z | Handover / system readiness | P: many docs (architecture, integration readiness, store compliance, CLAUDE.md) | M: single Handover page + how-to guides; owner-only action list | – | – | `docs/HANDOVER.md` + console page linking live status | Review | NOT TESTED |

## Open phone-test findings (kept open — no evidence of fixes)
Camera/attachment flow · multi-photo · photo understanding · video understanding · files/PDF · current location ·
maps end-to-end · female voice preference · repeated referral prompts · attachment intent mismatch · self-healing
relevance · Universal Master Profile · Screen Guide (not phone-verified; not in sideload builds) · delivery/driver/order
flow · location-based notifications · referral Priority Notification Credits · greetings. **All: NOT PHONE VERIFIED.**

## Safest implementation plan (staging only, reuse first)
1. **Phase 1 – Owner visibility, no new data model** (low risk): QA Center resource; Setup wizard page from the
   integration registry + static domain/email checklist; Handover page + `docs/HANDOVER.md` how-tos; flag history
   and audit environment; "why unavailable" on actions; unified Links page.
2. **Phase 2 – Configuration resources on the existing engine**: `referral_credit_rules`, `reminder_rules`,
   `conversation_settings`, `businesses`; wire them into referrals/credits, the scheduler and the assistant
   (with tests). Promotions gain language targeting, test-send and credit spending.
3. **Phase 3 – Master Profile 360° admin view** joining existing tables (masked, permission-gated) + role
   verify/suspend actions through approvals.
4. **Phase 4 – Fix the open phone findings** one by one with phone evidence (attachments, location, voice,
   referral prompt repetition, greetings) — separate small builds.
5. **Phase 5 – Delivery/driver operations and hyper-local triggers** only after owner decisions (driver model,
   background-location policy).

Never in any phase: arbitrary code/SQL/shell, secret display, production changes, merges, releases.
