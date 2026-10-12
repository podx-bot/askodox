# Implementation status (update after every work unit)

Last update: 2026-10-13 IST · branch `claude/master-phase2` (PR #183) -- all items below are CODE + automated tests,
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

## Pending (next executable steps)
1. Real-phone acceptance of every flow above (none is PHONE VERIFIED).
2. Smart Fill / Studio editing / Free-Plus-Pro subscription screens (earlier backlog), nested-screen restyle.
3. Variant combinations matrix, seller bulk CSV import, barcode scan.

## Owner decisions 2026-10-12 23:09 (apply; do not ask again)
1. PR merge + deploy to Railway production when all required checks pass and nothing destructive /
   security-sensitive needs approval; verify deployment health.
2. Voice: Voice Mode on -> every reply spoken; Text Mode -> optional. Travel Radio plays audio. Cost controls,
   caching, metering; respect mute / pause / preferences.
3. Language: reply in the language the user speaks / selected; never force the UI language.

## Blockers needing the owner
- Payment gateway + any price activation (Radio Rs 29 / 149 / 399 are proposals; plans stay inactive).
- Switching `radio.enabled` on, and whether to keep the nearby-places lookup (main cost driver).
