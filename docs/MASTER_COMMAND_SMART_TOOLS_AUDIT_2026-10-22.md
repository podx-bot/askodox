# Master Command (Smart Tools / Vision / Connectivity / Tricks / Fraud / Tax) — Audit, Plan, Round 1

Date: 2026-10-22 · Base: `main` @ `567671a` (PR #218) · Branch: `claude/smart-tools-vision-foundation`

Reporting rule (AGENTS.md): VERIFIED FACTS / HYPOTHESES / RECOMMENDATIONS are kept separate. Nothing here is
PHONE VERIFIED.

## A. Repository audit (verified facts)

| Area | State on `main` @ 567671a |
|---|---|
| Flutter app | 278 Dart files under `lib/`, 37 feature folders, Riverpod + go_router (67 `GoRoute`s), one primary journey (`askodox_primary_home_screen.dart`, ~5.5k lines) |
| Backend | FastAPI, 526 Python files, ~433 decorated routes, SQLite on the Railway volume; production runs `backend/server.py` |
| Tests | Backend: 139 test files, **1152 passed / 0 failed** (local run, this session). Flutter: 156 test files — no Flutter SDK in the cloud container, so `flutter analyze` / `flutter test` run only in CI (`Flutter CI`, `Android APK CI`) |
| CI | 49 workflows; last 5 runs on `main` @ 567671a all green (Flutter CI, Android APK CI, Android Live Build, Feature Registry gate, Bootstrap runner) |
| Releases | Latest phone-test prerelease `phone-test-1343` (from unmerged PR #219); 1342 built from `main` |
| Open PRs | #219 (adaptive Profile, "do not merge without approval"), #86, #78, #36, #33, #26, #23 (draft), #15 — all older than this round; none touch the files changed here |
| Camera / media | `image_picker` + `file_picker` via `MultimodalCaptureService` / `askodoxMediaPickerProvider`; ONE attachment endpoint `POST /api/attachments/analyze`; image brain = Gemini (2 models) → OpenAI fallback, single generic prompt |
| Voice | Native `MediaRecorder` → Sarvam STT; Sarvam Bulbul TTS → device TTS fallback |
| Location | `geolocator`, Places / Geocoding / Routes through `external_call_budget` |
| Result Board | Locked one-rail layout, mega-expand, pin / minimize / archive (`result_board.dart`) |
| Android | `minSdk = max(flutter, 23)`; permissions: INTERNET, RECORD_AUDIO, FINE/COARSE LOCATION, POST_NOTIFICATIONS, SYSTEM_ALERT_WINDOW, FOREGROUND_SERVICE(_SPECIAL_USE), REQUEST_INSTALL_PACKAGES. **No** CAMERA, BLUETOOTH*, NFC, UWB declarations |
| Sensors / BLE / NFC / AR / OBD / IoT | **Nothing existed** (no sensors package, no BLE, no NFC, no ARCore, no MQTT/Matter, no device registry) |
| Cost control | `external_call_budget.cached_call` (cache + per-provider usage + ₹ estimate in Admin), `rate_limit.check` per client |

### Classification of the master command's scope before this round

- **Working:** chat, voice, attachments (single generic image analysis), location, discovery, result board, orders / consent,
  billing (test mode), Admin / Command Center.
- **Partial:** image analysis exists but has no domain evidence policy (it can say "fresh"/"genuine"), no scan modes, no
  multi-image, no cost bounds beyond the generic cache.
- **Missing:** every Smart Tool, sensors, AR, connectivity / pairing / smart home, walkie-talkie, Smart Tricks engine,
  Fraud & Market Reality engine, GST / Income-tax module, device compatibility DB, OBD-II, livestock / crop / food
  domain models.

### Security / risk notes relevant to this command

- New public, unauthenticated AI endpoints cost money per call: every new one must be rate-limited and metered (done
  for `/api/vision/inspect`: 10/min per client + `vision_inspect` usage + cache).
- Device control (locks, pumps, geysers) must never be simulated; no pairing code may bypass vendor auth.
- Fraud / tax content must stay awareness-only (no operational evasion guidance).

## B. Architecture decision (one pipeline, configured domains)

Twelve "engines" are NOT twelve services. They map onto what already exists:

| Engine (command) | Implemented as |
|---|---|
| AI Vision + Micro Vision | `vision_inspection.py`: ONE evidence contract; domains = config rows (`DOMAIN_PROFILES`); modes quick / deep / expert bound images, resolution and model fallback |
| Measurement, Smart Toolbox | `lib/features/smart_tools/` — ONE registry (`askodoxSmartTools`) with needs + honest readiness; pure on-device calculators; sensor maths |
| Results / Reports / Action | Reuse chat + Result Board; tools open from chat via `askodoxToolIntent` (no new results page) |
| Cost control | Reuse `external_call_budget` (+ `vision_inspect` cost row) and `rate_limit` |
| Connectivity / Pairing / Smart Home / Compatibility | Registry entries (`pairing`, `bt_scale`, …) marked *coming soon / needs external device*; nothing simulated |
| Smart Tricks, Fraud & Market Reality, Tax & Legal | Next rounds: grounded retrieval inside the existing Decision Brain (`decide()` / advisor), not separate bots |

## C. Round 1 implementation (this branch)

Backend
- `app/services/vision_inspection.py` — evidence-tiered report (`observed` / `inferred` / `not_verifiable` /
  `recommended_checks` / `safety_warnings` / `quantities` / `needs_more_evidence` / `limits`), never-claim rules per
  domain (food safety, adulterants, roadworthiness, mechanical condition, tyre PSI / tread depth, exact animal weight,
  animal health, structural safety, confirmed disease, chemical doses, authenticity), single values widened to ranges,
  livestock weight only with a reference object and labelled experimental.
- `UniversalImageService.analyze_with_prompt` — one multi-image call, bounded model fallback, optional second provider.
- `routes/vision_inspect.py` — `POST /api/vision/inspect`, `GET /api/vision/profiles` (rate-limited, metered, cached).
- `external_call_budget` — `vision_inspect` ₹ estimate row.

Flutter
- Registry of 32 tools with needs (phone sensor / camera / camera+AI / ARCore / external sensor / Bluetooth / USB /
  cloud / manual) and readiness; hub at `/tools` (Profile > Smart Tools).
- Calculators (on-device): area & perimeter, volume, brick / block (+ mortar cement & sand), concrete, plaster, tile &
  flooring (+ boxes, user-rate cost, labour), paint (+ primer), load & space planner (payload from the user, rotation-
  aware oversize check, "tight" above 85 %, heaviest-first loading order).
- Sensor tools: level / inclinometer / plumb (flat + edge modes, set-zero), tilt-compensated magnetic compass with
  interference warning; honest "sensor not available" after 3 s with no readings.
- AI photo inspection screen (domain chips + server capture guidance, quick / deep / expert, ≤4 photos, report view).
- Chat: explicit tool asks and material-quantity questions open the tool; commerce asks never match; unbuilt tools are
  reported as unavailable; with results on screen only explicit tool names interrupt.

## D. Testing (this round)

- Backend: `tests/test_vision_inspection.py` — 29 tests (12 domain never-claim cases, quantities, quality, mode bounds,
  cache + metering, provider failure, bad input, profiles en/te). Full suite: see PR.
- Flutter: `test/features/smart_tools/smart_tools_domain_test.dart` (calculators, load planner, sensor maths, router
  incl. Telugu + commerce negatives, registry consistency) and `smart_tools_widgets_test.dart` (calculator, hub honesty,
  level with fake sensors + zeroing, sensor unavailable, compass, inspection with fake API + picker). Run in CI only.
- Hardware: **NOT HARDWARE VERIFIED** — sensors are tested with injected streams; no real phone run yet.

## E. Feature status after round 1

| Feature | Status |
|---|---|
| Smart Tools registry + hub + chat discovery | IMPLEMENTED AND TESTED (unit / widget; phone pending) |
| Area, volume, brick/block, concrete, plaster, tile, paint, load planner | IMPLEMENTED AND TESTED |
| Level / inclinometer / plumb, compass | IMPLEMENTED BUT HARDWARE UNVERIFIED |
| AI photo inspection (food, dish, vehicle, tyre, livestock, crop, construction, product, general) | IMPLEMENTED BUT HARDWARE UNVERIFIED (backend tested with a fake model; real Gemini output not yet observed; backend not deployed until merge) |
| Livestock weight | PARTIALLY IMPLEMENTED (experimental range only with a reference object; no validated model) |
| AR measuring, distance / height meter, protractor, magnifier, colour picker, light / sound / vibration / RPM, object counter | NOT IMPLEMENTED |
| Bluetooth scale, moisture / temperature sensors, electrical tester, laser meter | BLOCKED BY EXTERNAL DEPENDENCY (hardware + vendor protocol) |
| Connectivity engine, device pairing, smart home / universal remote, walkie-talkie | NOT IMPLEMENTED |
| Vehicle guided inspection workflow + OBD-II | PARTIALLY IMPLEMENTED (single-shot vehicle inspection only; no guided 4-side flow, no OBD) |
| Agriculture advisor (weather, soil lab, market) | PARTIALLY IMPLEMENTED (leaf/crop photo inspection only) |
| Reverse recipe | PARTIALLY IMPLEMENTED (dish inspection domain; no recipe / shopping list generation yet) |
| Smart Tricks & Savings, Fraud & Market Reality, GST / Income-tax | NOT IMPLEMENTED |

## F. Dependency-aware plan for the next rounds

1. **Round 2 – grounded engines in the ONE brain:** Fraud & Market Reality + GST / Income-tax as `advisor` knowledge
   resources with source URL + `verified_at` (CBIC / incometax.gov.in), FY/AY-aware, awareness-only rules; Smart Tricks
   as a result-section that only shows evidence-backed savings (existing price_truth / benefits data).
2. **Round 3 – guided vision workflows:** vehicle 4-side guided capture + checklist report (PDF via existing `pdf`
   package), reverse-recipe → shopping list → local sellers via the existing deal flow, time-series comparison.
3. **Round 4 – connectivity foundation:** device registry + compatibility table (backend), BLE scan with
   `flutter_blue_plus` and runtime BLUETOOTH_SCAN/CONNECT permissions requested only on "Add device", one tested
   BLE weighing-scale profile (needs a physical scale).
4. **Round 5 – AR:** ARCore availability check + point-to-point measure (needs ARCore-capable test phone).
5. Smart home / Matter / OBD-II / walkie-talkie only after a target device list and vendor SDK terms are chosen.

## G. Owner actions needed

- Approve merging the PR (production backend gets `/api/vision/inspect` only after merge + Railway deploy).
- Real-phone test of the phone-test APK: level, compass, calculators, one inspection per domain.
- For later rounds: a Bluetooth scale / OBD-II adapter / ARCore phone to test with, and which smart-home brands matter.
