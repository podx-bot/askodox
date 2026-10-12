# Implementation status (update after every work unit)

Last update: 2026-10-12 23:55 IST · PR #182 MERGED -> main `1db4f74`, deployed to Railway production (deployment cdda8021, SUCCESS; /health healthy on 1db4f74, /readiness ready; new catalogue endpoints 200 -- probe run on branch claude/prod-health-probe) · release APK 1321 (sha256 2ad83867…459a) · next work branch: `claude/master-phase2`.

## Done (merged + deployed 2026-10-12)
- Reply language = the language the user speaks (UI language never forces it); Voice Mode (speak every reply once the user used the mic; Profile switch).
- Catalogue attributes reject contact details / links.

## Done earlier this round (code + automated tests; NOT phone-verified)
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

## Owner decisions 2026-10-12 23:09 (apply; do not ask again)
1. PR #182: review code, deps, migrations, CI, security; fix failures; merge + deploy to Railway production if all
   required checks pass and nothing destructive / security-sensitive needs approval; verify deployment health.
2. Voice: Voice Mode on -> every conversational reply is spoken; Text Mode -> voice optional (replay). Travel Radio
   must play audio. Cost controls, caching, metering; respect mute / pause / preferences.
3. Language: reply in the language the user speaks / explicitly selected for the conversation; never force the UI
   language onto replies; Telugu, Hindi, English and mixed speech.

## Blockers needing the owner
- Payment gateway + any price activation (Radio ₹29/149/399 are proposals only).
