# Combined Master Command — requirement audit (2026-10-04)

Baseline: `main` @ `2e61473` (after PR #154). "Fixed now" = closed in the
round that follows this audit (PR after #154). Status words:
COMPLETE (code + automated tests), PARTIAL, MISSING, EXTERNALLY BLOCKED.
Real-phone verification is listed separately at the end; nothing here is
claimed as phone-verified.

| # | Requirement | Before this round | Evidence / what was done |
|---|---|---|---|
| 1 | Universal advisor + dynamic decision questions | COMPLETE | `advisor_engine.py`, advisor tests; production probe asks usage/budget correctly |
| 2 | Result Orchestrator + persistent constraints | COMPLETE | contract v2, `test_result_contract_combinations.py` (31) |
| 3 | Local / nearby / registered / online / marketplace / organic / affiliate / sponsored / deals / reviews / videos / warnings / next actions | COMPLETE (code); affiliate + sponsored have no live campaign | sections in `result_orchestrator.py`; production rows from Places, Brave, Amazon/Flipkart/Meesho |
| 4 | Brave funded — recheck | COMPLETE | production probe 37210777743: HTTP 200, real rows, 0 stale |
| 5 | Maps stack (current location, manual search, map pick/drop, nearby, typed place, junction) | COMPLETE | `/health/maps` all OK; `/api/discover/resolve` + junction verified in production |
| 6 | Taxi / ride booking / drivers | PARTIAL → fixed | mobility system existed; chat ride requests did not reach it → chat "Request a driver" hand-off |
| 7 | Bike taxi | COMPLETE | `ride_bike` kind, partner service |
| 8 | Carpooling | COMPLETE | carpool offer/search/request/decide, contact after accept |
| 9 | Parcel delivery | PARTIAL → fixed | parcel kind existed; chat parcel requests now hand off too |
| 10 | Pickup/drop + local delivery | COMPLETE | `pickup_drop`, `local_delivery` |
| 11 | Travel workflows (airport / outstation / scheduled) | PARTIAL → fixed | backend `schedule_at` existed; app had no schedule field → date/time picker, shown on cards |
| 12 | Driver registration + availability | COMPLETE | apply → review → online toggle |
| 13 | Customer booking flow | COMPLETE | Book tab + chat hand-off |
| 14 | Driver acceptance before confirmation | COMPLETE | never "confirmed" before `PARTNER_ACCEPTED` (tests) |
| 15 | Who supplies the driver before confirming | PARTIAL → fixed | backend `fulfillment.py` existed with no app UI → order card "Delivery: …" chooser + separate delivery status |
| 16 | Pricing / distance / route + configurable rules | COMPLETE | `mobility_services` fare rows; route quote in chat; distance on jobs |
| 17 | Admin controls for mobility | COMPLETE | Command Center "Mobility & delivery" |
| 18 | Staff Workspace Android + web, same backend | COMPLETE | `/staff`, Profile entry, handoff code |
| 19 | Staff link workflow | COMPLETE | blocked-page → manual entry tests; review → LIVE |
| 20 | Bulk / import / sources / duplicates / lifecycle / audit | COMPLETE | `affiliate_catalog`, `universal_sources`, `canonical_key` |
| 21 | Native video / reels with uploads | PARTIAL → fixed | upload/review/feed existed; feed opened an external player → in-app vertical reels (`video_player`) |
| 22 | Shorts + long video ranking | COMPLETE | `video_preference` tests |
| 23 | Registered-content deep study only from evidence | PARTIAL → fixed | native uploads could not be studied → `POST /api/videos/native/{id}/study` from the stored file; title/caption never sent; facts without evidence dropped (test) |
| 24 | Native Auto-DM for videos / images / catalogs / products / offers | PARTIAL → fixed | video DM existed (no app UI); deal chats ignored product/catalog/offer rules → reels "Ask the business", owner Messages inbox, deal-chat trigger selection (test) |
| 25 | External social DM via official APIs only | EXTERNALLY BLOCKED | adapters built; Meta App Review + tokens needed; never shown LIVE |
| 26 | Customer + staff support | COMPLETE | support escalation, staff support queue |
| 27 | Content / news app experience | PARTIAL → fixed | results "News" group only → "News & updates" in Updates (LIVE staff content only) |
| 28 | Affiliate products + sources | COMPLETE (code) | no partner credentials configured |
| 29 | Organic vs affiliate vs sponsored | COMPLETE | routing computed on read; labels |
| 30 | Unlimited configurable sources + isolation | COMPLETE | `sources` resource, `source_health` |
| 31 | Deals / offers / card offers / rewards | COMPLETE (code) | no live campaign |
| 32 | Notifications + demand routing | COMPLETE in-app; push EXTERNALLY BLOCKED | Firebase service account + app missing |
| 33 | Early Access + flags | COMPLETE | `/api/flags`, early access resource |
| 34 | Command Center CRUD / perms / analytics / diagnostics / health / audit | PARTIAL → fixed | video report endpoint had no console view → "Video reports" |
| 35 | Camera / Photos / Files attachments | COMPLETE | one `/api/attachments/analyze`, tests |
| 36 | Voice / language / location / profile + Android bugs | COMPLETE (code) | phone verification pending |
| 37 | YouTube kept working | COMPLETE | proof workflow green on every push |
| 38 | Contact only after acceptance | COMPLETE | orders, mobility, carpool, video DMs (tests) |
| 39 | Sensitive data protections | COMPLETE | masking, Privacy Shield, no secrets in public health |
| 40 | 1292/1294 regressions | COMPLETE | contract + Flutter honesty tests |
| 41 | Source-failure isolation | COMPLETE | combination tests |
| 42 | Combination regression tests | COMPLETE | CI `result-contract-gate.yml` |
| 43 | Production Result Diagnostics | COMPLETE | `/admin/cc/results/diagnostics` |
| 44 | Integration states without secrets | COMPLETE | `/health/integrations` verified in production |
| 45 | Secrets backend-only | COMPLETE | APK guard: production hosts only, no keys |
| 46 | Signing lineage + production-only release | COMPLETE | APK 1297 cert 727b4a66…57cf verified |

Production configuration still owned by the owner (not code):
`delivery.matching` is OFF in production and no driver is approved, so
rides/deliveries honestly end "no driver" until switched on in the
Command Center.
