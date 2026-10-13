# Implementation status (update after every work unit)

Last update: 2026-10-13 IST · PR #183 merged (main 70e0255, deployed); PR #185 phase 3 -- all items below are CODE + automated tests,
NOT phone-verified. Production = main (PR #182 merged 2026-10-12, `1db4f74`).

## Done on claude/master-phase2 (code + automated tests; NOT phone-verified)
- Structured catalogue attributes in matching: `supply_fit` judges registered listings by the seller's indexed
  attributes; rows carry `attributes`; Result Board attribute chips filter the SHOWN deck (never a new search).
- Mobility: goods kinds (mini truck, tempo, lorry, packers & movers, intercity courier, cold chain), pricing models
  (per km / kg / hour / stop / fixed / quotation), up to 5 stops, bids + counter-offers + accept (agreed fare);
  app: goods chips, stops, weight / size / handling, quote / counter / accept on the trip card.
- Registration: one profile, many roles (courier, cab, bike taxi, fleet, restaurant, manufacturer, wholesaler,
  enterprise, freelancer ...), draft until required details exist, staff verification queue (`role_verifications`,
  only the reference's last 4 kept); app: My Roles -> Registration progress + Verify.
- Catalogue: 19 templates (+ health & wellness non-Rx, education, travel & stays, rentals, B2B industrial,
  digital services); dependency evaluation independent of override order.
- Travel Radio add-on (`travel_radio.py`, `routes/radio.py`, app `/radio`): segments only from real facts
  (place name, nearby places, LIVE content), shared area cache (cell `radio.cell_km`), cached Sarvam audio (7 days),
  no repeats (`radio.repeat_hours`), daily minute cap, usage metering. Flag `radio.enabled` default OFF.
- Radio billing: plans radio_1d / 7d / 30d (proposed Rs 29 / 149 / 399) stored INACTIVE, audience `addon_radio`,
  separate from the base plan (`/api/subscriptions` refuses add-ons); paid pass = PENDING_PAYMENT (no gateway);
  staff may grant PROMOTIONAL passes only.
- Cost model (`/admin/cc/radio`, ESTIMATE): with the nearby-places lookup ON the proposed prices lose money for
  medium / heavy listeners; with it OFF (`radio.nearby_places=0`) light + medium are covered and only the heavy
  30-day listener loses (~Rs 668 cost vs Rs 399). Owner decision needed before activation.
- AXE executive brief (`executive_ai.py`, `GET /admin/cc/axe/brief`, console Readiness panel): graded findings over
  release gate, incidents, API spend, radio pricing, Feature Registry; recommends catalog actions only.

## Done on claude/phase3-smartfill-plans (PR #185; code + automated tests; NOT phone-verified)
- Smart Fill in the ready-made catalogue editor: `POST /api/catalog/templates/{key}/smart-fill`, values only
  from the seller's own words (options named, number next to the attribute name / unique unit, explicit
  "name: value"); fills only empty fields; never replaces the seller's price or choices.
- Plans: Free (Rs 0, active), Plus Rs 499, Pro Rs 999 + 7-day trial seeded INACTIVE (audience `base`);
  `GET /api/plans/catalogue`; app Plans screen (Menu -> Plans & subscription); old mock `/admin/subscriptions`
  redirects to the Command Center.
- Travel Radio internal testing: staff add testers (`POST /admin/cc/radio/testers`); testers hear Radio with the
  customer flag OFF, no pass, no price (metered + capped); app shows "Internal testing -- no price".
- Phone acceptance: 6 new checks seeded into `qa_checks`; full checklist `docs/phone-test-checklist.md`.
- Studio: existing My Studio (creations AI draft / edit / share / delete, native video edit / submit) verified
  present with tests; the original "Studio editing" spec text was not saved in the repo, so nothing new was
  invented there.

## Pending (next executable steps)
1. Real-phone acceptance of every flow (none is PHONE VERIFIED) -- `docs/phone-test-checklist.md`.
2. Retire the legacy mock admin screens (`/admin/<section>`, `/admin/analytics`, `/admin/reports`): admin-only,
   duplicate the live Command Center (owner approval for removal).
3. Variant combinations matrix, seller bulk CSV import, barcode scan, nested-screen restyle.

## Owner decisions 2026-10-12 23:09 (apply; do not ask again)
1. PR merge + deploy to Railway production when all required checks pass and nothing destructive /
   security-sensitive needs approval; verify deployment health.
2. Voice: Voice Mode on -> every reply spoken; Text Mode -> optional. Travel Radio plays audio. Cost controls,
   caching, metering; respect mute / pause / preferences.
3. Language: reply in the language the user speaks / selected; never force the UI language.

## Blockers needing the owner
- Payment gateway + any price activation (Radio Rs 29 / 149 / 399 and Plus Rs 499 / Pro Rs 999 are proposals; plans stay inactive).
- What Plus / Pro unlock (entitlements are empty until decided).
- Switching `radio.enabled` on, and whether to keep the nearby-places lookup (main cost driver).
