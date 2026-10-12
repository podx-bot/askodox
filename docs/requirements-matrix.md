# ASKODOX requirements matrix (Master Autonomous Command, 2026-10-12)

Status words: VERIFIED COMPLETE (automated tests + phone evidence), CODE+CI (implemented, automated tests
pass, NO phone evidence yet), PARTIAL, MISSING, BLOCKED. Nothing here is "complete" without a real-phone check.
Branch: `claude/navigator-ux-p0` (PR #182, draft, NOT merged, NOT deployed).

| # | Requirement | Status | Evidence (code / tests) | Gap |
|---|---|---|---|---|
| 1.1 | Mobile OTP sign-in | CODE+CI (prod, earlier rounds) | `onboarding_auth.py`, `session_tokens.py` | phone re-check |
| 1.2 | Name, preferred language, auto/manual location | CODE+CI | `onboarding_screen.dart`, `location_controller` | — |
| 1.3 | Many roles under one master profile, switch with confirmation | CODE+CI | `active_role.dart`, Profile `askodoxActiveRolePicker`, `/api/me/profile` | — |
| 1.4 | Category-specific registration, documents, hours, service areas, photos, drafts, admin approval | PARTIAL | seller tiers, `listing_reviews`, delivery partner apply -> staff review | no generic per-role registration wizard; document upload + verification queue for all roles MISSING |
| 2.1 | Listing: text / voice / photo -> draft | CODE+CI | chat sell flow, `_draftFromMedia`, catalogue editor | barcode scan MISSING |
| 2.2 | Title, brand, model, specs, SKU, MRP, discount, wholesale + MOQ, variants, stock, warranty, returns, delivery, installation, negotiable | CODE+CI (this round) | `catalogue_templates.py` `_PRODUCT_BASE` + per-category attrs; tests `test_catalogue_attributes.py` | variant *combinations* matrix MISSING |
| 2.3 | Draft / preview / publish / edit / archive, seller confirms AI details | CODE+CI | editor Review -> Publish; draft when price / required detail missing; My Listings edit + confirm-remove | bulk CSV import for sellers MISSING (staff Smart Entry exists) |
| 3.1 | DB-driven hierarchical category + attribute master, unlimited, en/te/hi | CODE+CI (this round) | Command Center resource `catalog_templates` (seeded once, admin-editable, parent inheritance, abstract parents); `taxonomy_nodes` tree | 40 attributes per template node (unlimited via parents) |
| 3.2 | Required / optional / conditional attrs, groups, units, ranges, multi-select, validation, filterable | CODE+CI | `_attr(group, unit, multi, depends_on, min, max, filterable)`, `clean_attributes` | — |
| 3.3 | Seed templates for all sectors | PARTIAL | 13 templates: grocery, fruits/veg, fashion, meat, pickles, tiles/marble, electronics, services, furniture, vehicles/parts, jewellery/beauty, agriculture, property/rentals | healthcare, education, travel, finance, digital, B2B industrial, rentals (non-property) MISSING |
| 4 | Ready-made catalog navigator (detect -> template -> attrs -> price/stock -> preview -> publish), admin-editable, no hardcoded forms | CODE+CI | chat seller flow + My Listings "Ready-made catalog"; editor renders any template from data | category auto-detection from free text uses existing chat cue only |
| 5.1 | Backend filters from indexed listing attributes | CODE+CI (this round) | table `listing_attributes`, `GET /api/catalog/filters/{key}` (real values + counts + price range), `GET /api/products/search?attr=key:value` | not yet wired into `/deals` matching / Result Board UI |
| 5.2 | Result Board layout (above conversation, minimize pill, restore, pin, tabs) | CODE+CI | `result_board.dart`, `result_board_tabs.dart`, tests | phone check |
| 6 | Mobility & logistics engine (courier, delivery, rides, goods, last mile; pricing models; bidding; lifecycle) | PARTIAL | `delivery_jobs.py`, `routes/delivery.py`, `mobility_services`, partner apply/review; route-quote partner matching fixed this round | goods transport, multi-stop, per-kg/per-stop/contract pricing, bidding/negotiation, fleet MISSING; no live GPS (never faked) |
| 7 | Travel Radio | MISSING | — | needs product + content-source + cost decisions |
| 8 | Travel Radio add-on billing (₹29 / ₹149 / ₹399 proposals) | MISSING / BLOCKED | subscriptions exist without gateway (PENDING_PAYMENT) | payment gateway + price approval BLOCKED |
| 9 | AXE executive review | PARTIAL | existing: Feature Registry gate, release gate, Admin AI incidents, feature health | AXE as a separate module not built (would duplicate the gates) |
| 10 | Cross-system integration | PARTIAL | see rows above | Result Board filters, Radio, billing |
| 11 | Persistent progress + resume | CODE (this round) | `docs/implementation-status.md`, `docs/resume-instructions.md` | Claude cannot restart itself; resume is a manual one-message step |
| 13 | Automated tests | CODE+CI | backend 1049 passed; Flutter CI green on last push | Android integration tests on a device NOT run (no device in CI) |
| 14 | Merge / deploy / release | BLOCKED (approval) | — | merging PR #182 deploys production (Railway from main) -> owner approval required |
