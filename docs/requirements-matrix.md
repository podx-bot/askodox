# ASKODOX requirements matrix (Master Autonomous Command, 2026-10-12)

Status words: VERIFIED COMPLETE (automated tests + phone evidence), CODE+CI (implemented, automated tests
pass, NO phone evidence yet), PARTIAL, MISSING, BLOCKED. Nothing here is "complete" without a real-phone check.
Branch: `claude/master-phase2` (PR #183). PR #182 merged + deployed 2026-10-12.

| # | Requirement | Status | Evidence (code / tests) | Gap |
|---|---|---|---|---|
| 1.1 | Mobile OTP sign-in | CODE+CI (prod, earlier rounds) | `onboarding_auth.py`, `session_tokens.py` | phone re-check |
| 1.2 | Name, preferred language, auto/manual location | CODE+CI | `onboarding_screen.dart`, `location_controller` | — |
| 1.3 | Many roles under one master profile, switch with confirmation | CODE+CI | `active_role.dart`, Profile `askodoxActiveRolePicker`, `/api/me/profile` | — |
| 1.4 | Category-specific registration, documents, hours, service areas, photos, drafts, admin approval | CODE+CI | `ROLE_FIELDS`/`ROLE_REQUIRED`, `/api/me/profile/registration`, `role_verifications` queue (last 4 only), My Roles progress + Verify | document image upload not built (checked outside the app) |
| 2.1 | Listing: text / voice / photo -> draft | CODE+CI | chat sell flow, `_draftFromMedia`, catalogue editor | barcode scan MISSING |
| 2.2 | Title, brand, model, specs, SKU, MRP, discount, wholesale + MOQ, variants, stock, warranty, returns, delivery, installation, negotiable | CODE+CI (this round) | `catalogue_templates.py` `_PRODUCT_BASE` + per-category attrs; tests `test_catalogue_attributes.py` | variant *combinations* matrix MISSING |
| 2.3 | Draft / preview / publish / edit / archive, seller confirms AI details | CODE+CI | editor Review -> Publish; draft when price / required detail missing; My Listings edit + confirm-remove | bulk CSV import for sellers MISSING (staff Smart Entry exists) |
| 3.1 | DB-driven hierarchical category + attribute master, unlimited, en/te/hi | CODE+CI (this round) | Command Center resource `catalog_templates` (seeded once, admin-editable, parent inheritance, abstract parents); `taxonomy_nodes` tree | 40 attributes per template node (unlimited via parents) |
| 3.2 | Required / optional / conditional attrs, groups, units, ranges, multi-select, validation, filterable | CODE+CI | `_attr(group, unit, multi, depends_on, min, max, filterable)`, `clean_attributes` | — |
| 3.3 | Seed templates for all sectors | CODE+CI | 19 templates incl. health & wellness (non-Rx), education, travel & stays, rentals, B2B industrial, digital | finance products not seeded (regulated) |
| 4 | Ready-made catalog navigator (detect -> template -> attrs -> price/stock -> preview -> publish), admin-editable, no hardcoded forms | CODE+CI | chat seller flow + My Listings "Ready-made catalog"; editor renders any template from data | category auto-detection from free text uses existing chat cue only |
| 5.1 | Backend filters from indexed listing attributes | CODE+CI | `listing_attributes`, `/api/catalog/filters/{key}`, search `attr=`, `supply_fit` uses attributes, rows carry `attributes`, Result Board chips | phone check |
| 5.2 | Result Board layout (above conversation, minimize pill, restore, pin, tabs) | CODE+CI | `result_board.dart`, `result_board_tabs.dart`, tests | phone check |
| 6 | Mobility & logistics engine (courier, delivery, rides, goods, last mile; pricing models; bidding; lifecycle) | CODE+CI | goods kinds, pricing models, 5 stops, bids/counter/accept (`test_mobility_goods_bids.py`, `mobility_screen_test.dart`) | no live GPS map (never faked); no approved driver in production; no ride payments |
| 7 | Travel Radio | CODE+CI (flag OFF) | `travel_radio.py`, `routes/radio.py`, app `/radio`, `test_travel_radio.py`, `travel_radio_test.dart` | owner must switch `radio.enabled` on; phone audio check |
| 8 | Travel Radio add-on billing (₹29 / ₹149 / ₹399 proposals) | CODE+CI, BLOCKED for activation | plans INACTIVE (`addon_radio`), separate from base plan, PENDING_PAYMENT, promotional grants, ESTIMATE cost model light/medium/heavy | gateway + price approval (heavy listeners lose money at Rs 399/30 d) |
| 9 | AXE executive review | CODE+CI | `executive_ai.py` over release gate + incidents + billing + radio cost + registry, `/admin/cc/axe/brief`, console panel | template text (no model call) by design |
| 10 | Cross-system integration | PARTIAL | see rows above | Result Board filters, Radio, billing |
| 11 | Persistent progress + resume | CODE (this round) | `docs/implementation-status.md`, `docs/resume-instructions.md` | Claude cannot restart itself; resume is a manual one-message step |
| 13 | Automated tests | CODE+CI | backend 1078 passed; Flutter CI + APK CI green on claude/master-phase2 | Android integration tests on a device NOT run (no device in CI) |
| 14 | Merge / deploy / release | per owner rule 2026-10-12 | PR #182 merged + deployed; PR #183 merges when every required check passes | phone acceptance still pending |
