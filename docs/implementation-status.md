# Implementation status (update after every work unit)

Last update: 2026-10-12 · branch `claude/navigator-ux-p0` · PR #182 (draft) · main untouched (`bae9c9e`).

## Done this round (code + automated tests; NOT phone-verified)
- Catalogue engine is ONE admin-editable, data-driven system: resource `catalog_templates` (seeded from
  `backend/app/services/catalogue_templates.py`), parent inheritance (`product_base`, `service_base`),
  attributes with group / unit / multi / depends_on / min / max / filterable, 13 seller templates.
- Indexed listing attributes (`listing_attributes`), buyer filters from real listings
  (`GET /api/catalog/filters/{key}`), search filtering (`/api/products/search?attr=key:value`),
  `/api/products/mine` returns attributes.
- Bug fixed: route quotes treated any listing mentioning "courier" as a delivery partner.
- App editor: grouped sections, number fields, multi-select chips, conditional fields.

## Earlier rounds on this branch
Navigator header / Result Board tabs / one "+" / Profile 5 sections / My Listings search + thumbnails +
confirm remove / mic until Stop / one draft (typed + voice + attachments) / no repeat listings / model JSON
strict=False / chunked voice with text revealed as read / point spacing. APKs 1316-1319 (phone-test links).

## Pending (next executable steps, in order)
1. Wire attribute filters into `/deals` matching + Result Board filter chips (app).
2. Mobility: goods transport kinds, multi-stop, pricing models (per-km/kg/hour/stop/contract), provider quotes.
3. Per-role registration wizard + document verification queue (reuse `listing_reviews` pattern).
4. More seed templates (healthcare non-Rx, education, travel, B2B industrial, rentals).
5. Travel Radio (needs owner decisions: content sources, voice budget) and Radio billing (needs gateway approval).

## Blockers needing the owner
- Merge PR #182 -> production deploy (approval).
- Payment gateway + any price activation (Radio ₹29/149/399 are proposals only).
- Two product rules still open: speak every reply (also typed)? reply in the spoken language over the UI preference?
