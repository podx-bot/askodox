# Master Command — Feature Status (kept current per round)

Last updated: 2026-10-23 · Rounds 1–4 on stacked PRs #220 → #221 → #222 → (round 4 PR). **Nothing here is merged or
deployed**; production gets these backends only after owner-approved merge + Railway deploy.

Status words: IMPLEMENTED AND TESTED · IMPLEMENTED BUT HARDWARE UNVERIFIED · PARTIALLY IMPLEMENTED ·
BLOCKED BY EXTERNAL DEPENDENCY · NOT IMPLEMENTED. "Tested" = automated tests (backend pytest + Flutter tests in CI);
no item is PHONE VERIFIED until a real-phone test with evidence.

| Area | Feature | Status | Notes / blocker |
|---|---|---|---|
| Smart Toolbox | Registry (≈40 tools, needs + readiness), hub, chat discovery | IMPLEMENTED AND TESTED | |
| Smart Toolbox | Area, volume, brick/block + mortar, concrete, plaster, tile/flooring, paint, load & space planner | IMPLEMENTED AND TESTED | user's own rates only |
| Smart Toolbox | Level / inclinometer / plumb, compass | IMPLEMENTED BUT HARDWARE UNVERIFIED | sensors_plus |
| Measurement | Measure from a photo with a reference object (A4 / card / typed) | IMPLEMENTED BUT HARDWARE UNVERIFIED | range + quality; same-plane condition |
| Measurement | AR measuring tape, distance / height meter, room / wall AR | BLOCKED BY EXTERNAL DEPENDENCY | needs native ARCore integration + an ARCore-capable test phone |
| Smart Toolbox | Protractor (3 taps on a photo, ± from tap accuracy), magnifier (photo, pinch zoom ≤10x, contrast) | IMPLEMENTED BUT HARDWARE UNVERIFIED | no live camera preview (a camera plugin broke the OTP SMS-consent test) |
| Smart Toolbox | Light meter (phone light sensor, lux + band) and sound level (mic dBFS; ≈ dB only after the user calibrates against a real meter) | IMPLEMENTED BUT HARDWARE UNVERIFIED | sensors uncalibrated; sound is not for legal / occupational checks; nothing recorded |
| Smart Toolbox | Colour picker, vibration / RPM, object counter | NOT IMPLEMENTED | |
| Vision | Evidence-tiered photo inspection (food, dish, vehicle, tyre, livestock, crop, construction, product, general), quick/deep/expert, cache, metering, caps | IMPLEMENTED BUT HARDWARE UNVERIFIED | real Gemini output not yet observed |
| Vision | Guided 4-side vehicle walk-around (front / rear / left / right → one Expert inspection) + PDF report with photos and disclaimer | IMPLEMENTED BUT HARDWARE UNVERIFIED | real Gemini output not yet observed; never a roadworthiness / fitness certificate |
| Vision | OBD-II | NOT IMPLEMENTED | needs a tested adapter |
| Vision | Livestock weight | PARTIALLY IMPLEMENTED | experimental range only with a reference object; no validated model |
| Vision | Reverse recipe → shopping list → sellers | PARTIALLY IMPLEMENTED | dish inspection only |
| Agriculture | Leaf / crop symptoms (suspected only) | PARTIALLY IMPLEMENTED | weather / soil lab / market not integrated |
| Money & safety | Income tax (new vs old, rebate + marginal relief, surcharge relief, cess; FY 2025-26 verified, tax year 2026-27 rates verified) | IMPLEMENTED AND TESTED | sources: Income Tax Dept, PIB, Finance Bill 2026 memo |
| Money & safety | GST registration by State, composition, GST split, rate structure | IMPLEMENTED AND TESTED | thresholds from CBIC 2019 publication — confirm State limit on the portal |
| Money & safety | Tax-evasion / scam how-to asks → awareness only | IMPLEMENTED AND TESTED | |
| Money & safety | Fraud & Market Reality: 12 scheme checklists with official channels (1930, cybercrime.gov.in, NCH 1915, Sanchar Saathi, VAHAN, RERA, BIS Care) | IMPLEMENTED AND TESTED | card body text English; titles / warning signs en+te |
| Money & safety | Smart Tricks: unit price, buy vs rent, repair vs replace, bulk buy, total cost of ownership | IMPLEMENTED AND TESTED | no invented prices / offers |
| Money & safety | Live price comparison, verified discounts, government benefit eligibility | NOT IMPLEMENTED | needs verified retrieval sources |
| Connectivity | Add Device flow (BLE), device dashboard, registry (hashed ids), compatibility catalog | IMPLEMENTED BUT HARDWARE UNVERIFIED | |
| Connectivity | BLE standard profiles: weight scale, temperature/humidity, thermometer, heart rate, battery | IMPLEMENTED BUT HARDWARE UNVERIFIED | private-protocol devices show no readings |
| Connectivity | NFC, IR, Wi-Fi Direct / Aware, mDNS discovery, USB serial, UWB | NOT IMPLEMENTED | |
| Connectivity | Matter / Thread, Zigbee, Z-Wave, LoRa, UHF RFID | BLOCKED BY EXTERNAL DEPENDENCY | hubs / radios / SDK agreements |
| Smart home | Device control, universal remote, schedules, automations | BLOCKED BY EXTERNAL DEPENDENCY | each brand's official API or a hub; never simulated |
| Communication | Push-to-talk over the internet (groups by code, 60 s clips, 24 h expiry) | IMPLEMENTED BUT HARDWARE UNVERIFIED | needs two real phones to verify |
| Communication | Offline long-range radio | BLOCKED BY EXTERNAL DEPENDENCY | phones lack the radio (stated in app) |
| Communication | WebRTC calls, live group voice, screen sharing, nearby file transfer | NOT IMPLEMENTED | |
| Business | Universal POS (GST billing, credit notes, customer credit, stock, day close, offline, BLE printer) | see `docs/POS_STATUS.md` | PR #224, stacked on round 4 |

## Owner actions
1. Approve merge order #220 → #221 → #222 → round 4, then a production deploy (backend features are unreachable from
   any APK until then).
2. Real-phone checks on the phone-test APK: level, compass, calculators, photo measurement, Add Device with any BLE
   device, push-to-talk between two phones (after deploy), inspection / tax / fraud cards (after deploy).
3. Hardware for later rounds: a standard BLE scale or thermometer, an OBD-II adapter, an ARCore phone.
