# ASKODOX — Claude Code project memory

Compact by design. Full history lives in `docs/ASKODOX_EXECUTION_TRACKER.md` —
read only its most recent 1–2 round sections, or grep it for a specific past
decision. Never read it in full "just in case." If anything here conflicts
with the actual repo or `git log`/`git show origin/main`, the repo wins — fix
this file, don't trust it blindly.

## Current verified checkpoint
- `main` @ `261f0aa` — PR #103 (Master Fix Ticket remainder), merged
  2026-09-28. Previous: PR #101 (`b79ebc9`) universal human flow, PR #100
  (`1103389`) browse without sign-in + Admin flow traces.
- PR #103 CI was green on its head `0a8337d` (askodox-ci, build-apk with
  the new `flutter_map` dependency, docker-smoke, smoke, isolation + gates).
  Backend 260 tests, Flutter 498. Railway deploy of `261f0aa` started clean.
- Sprint status: NOT complete. NOT yet verified: real Brave/Maps/Routes/
  Geocoding results in production (the cloud dev container cannot reach
  Brave, Railway or OSM tiles) and real-phone acceptance for every flow
  (TV, chicken "yes" = order, car, AC, job, catering broadcast + leads
  inbox, parcel map pins, multi-category, catalog drafts, referrals,
  offers, Telugu voice, location naming).
- Master Fix Ticket engines are all BUILT at least partially (advisory,
  map pins/route quote, roles, refer→register, offers, attribution/
  rewards, subscriptions, catalog AI, domain adapters, cost control,
  Admin tabs). Still partial: see "Known open issues".
- The identity-spoofing audit (started before round 10) is CLOSED.
- Roadmap (14 points, phased delivery): https://claude.ai/artifact/TWUnjbA2TTubwczT9Lxg4n
  — Phase 0–1 done, Phase 2 round 1 (seller tiers) done, rest of Phase 2 and
  Phases 3–9 open.
- Always confirm this checkpoint against `git fetch origin main` before
  relying on it — this line is updated after each merge, but git is truth.

## Non-negotiable process rules
- The product owner has **no shell/terminal access**. Every code change is
  delivered as a single plain-text instruction file with clearly labeled
  file boundaries (a start-of-file marker naming the path and whether it's
  new or a replacement, the file's content, an end-of-file marker, and a
  final marker after the last file) that the paste-based delivery method
  expects. Files over ~50k characters must be saved to disk and read from
  there, not pasted into chat. (The exact marker text is intentionally not
  reproduced here, so this file can never be mistaken for one.)
- **Never trust a "merged"/"done" claim at face value.** Independently
  verify with `git fetch origin main` and diff the actual committed file
  content before reporting anything as confirmed.
- Before calling a change done: run the backend suite (`pip install -r
  backend/requirements.txt`, tests under `backend/tests/`) and, for Flutter
  changes, `flutter analyze` + `flutter test`.
- Update this file after each round that actually merges — edit it in
  place to reflect the new checkpoint; don't append another history section
  here (that's what the tracker is for).

## Architecture gotchas (expensive to relearn — read before touching)
- `/deals` and its sibling routes (`app/api/routes/universal_deals.py`) are
  mounted **only in `backend/server.py`**, not in `app.api.app_factory.
  create_app()` alone. A script/test importing `create_app()` directly
  will 404 on `/deals`. `server.py` is what production actually runs.
- Auth pattern used everywhere a caller's identity matters:
  `_authenticated_app_user(request)` (401 on missing/invalid/expired
  token) + `_matching_app_user(claimed, authenticated)` (403 on mismatch;
  keeps a legacy client-supplied id field for compatibility without
  trusting it alone). Tokens: `app/services/session_tokens.py`
  (HMAC-signed, dependency-free).
- `in_app_deal.py` is mounted at `/debug` but is a **real, live feature**
  (deal chat), not a debug endpoint. `debug.py` itself now only has two
  genuinely-diagnostic endpoints (`/debug/whatsapp-diagnostics`,
  `/debug/voice-readiness`) plus `_prepare_askodox_app_identity`, which
  `universal_deals.py` depends on directly.
- `ConversationOSRuntimeService` builds an internal LLM-routing prompt
  prefixed `"OASAT domain="`. Anything reading raw conversation text
  (like `UniversalCorrectionService.detect()`) must ignore messages
  starting with that prefix — it's machine-generated, never a real user
  reply.
- A backend route's auth requirement changing does **not** guarantee every
  Flutter caller was updated — this caused a real production outage once
  (round 13 → round 14 hotfix). Grep the whole Flutter app for every
  caller of a route whenever its auth changes.
- Main Chat (`askodox_primary_home_screen.dart`) is the primary journey:
  results are embedded per assistant turn (`chat_result_policy.dart` decides
  card actions: Party B → `acceptMatch`, numeric listing → order request,
  online/video → link only). Don't build a separate results page.
- `UniversalDealController.answer()` fills the field an answer *describes*
  (with positional fallback); short detail answers bypass the AI rewrite
  (`AskodoxHomeRequestRouting.isShortDetailAnswer`) so they can't restart the
  active deal. Keep both when touching follow-up handling.
- Main Chat voice = native `MediaRecorder` (`startVoiceRecording` on the
  `com.askodox.app/device` channel) → `POST /api/in-app/voice/transcribe`
  (Sarvam-first). Never reintroduce the `RecognizerIntent` fallback there.
- No Android SDK in the cloud dev container: Kotlin changes compile only in
  CI (`Android APK CI` / `Android Live Build`).
- Chat and card actions share ONE executor
  (`lib/features/home/application/match_action_executor.dart`): a typed
  "yes / order it / book it" must keep calling it, never answer with text.
  Supply roles (seller/provider/worker) come only from the user's own words
  (`askodoxContextRole`), never from a guessed deal intent.
- Discovery is India-first (`ASKODOX_SEARCH_COUNTRY`, default IN): Brave
  `country`, Places `regionCode`, `region_mismatch` + `classify_page`
  filters. Snippet prices are `price_verified=false`. Identical Brave/
  Places/Geocoding calls go through `external_call_budget` (cache + usage).
  `/deals/discover`, `/api/discover/place|places|route` are public and
  rate-limited per client (`rate_limit.py`); `/deals/leads` needs sign-in.
- Growth engines live in ONE repository (`growth_repository.py`, tables
  `growth_*`) + `routes/growth.py` (customer `/api/...`, admin
  `/admin/cc/growth/...`, permissions `growth:view|manage`). Offers are
  rule rows evaluated by `offers_engine.py` (never hard-coded promotions);
  rewards accrue only on customer-confirmed completion and need admin
  APPROVED -> PAID. Paid plans stay PENDING_PAYMENT (no gateway).
- Backend tests use a per-run temp DB (`backend/tests/conftest.py`); don't
  reintroduce a shared `podx_v2.db` -- data leaked across re-runs.

## Known open issues (verified, not yet fixed)
- `/discover/voice` (ProductDiscoveryScreen) still uses the Android system
  `RecognizerIntent`; only Main Chat voice goes through Sarvam. Voice
  *replies* still use device TTS, not Sarvam TTS.
- A combined answer ("1 kg curry cut skinless") is stored whole in both
  `cut` and `chickenPreference` (matching still completes).
- No automated check catches "a route's auth requirement changed but a
  Flutter caller wasn't updated" — manual grep only (see gotcha above).
- Naming the current location needs the Geocoding API enabled on the Maps
  key; otherwise the app honestly keeps "Current location".
- Provider leads (`/deals/leads`) are in-app only (home-screen inbox): no
  push/WhatsApp notification, and WhatsApp-only providers are not targeted.
- Rate limits, the API cache and live counters are per process; daily API
  usage (and the ₹ estimate) is persisted in `growth_api_usage`.
- Route distance needs the Routes API on the Maps key; map tiles use the
  public OpenStreetMap server (low volume only; heavy use needs a tile
  provider).
- Subscriptions: no payment gateway (paid plans PENDING_PAYMENT);
  entitlements are exposed but not enforced by any feature yet; the older
  Flutter subscription screens are still mock-backed.
- Offers: no stacking and no customer-typed coupon codes. Rewards payouts
  are recorded by admins only (no money moves).
- Hotel/salon/healthcare adapters configure the backend (schema, search
  noun, advice); the app's follow-up questions for them are still generic.
  Advisory is rule-based, not LLM-generated.
- Pre-existing: `deal-completion-memory-smoke` block 2 fails when run
  outside its workflow env (same on `main` before PR #101).
- Phase 2 gaps: `service_provider` seller tier not computed, no
  duplicate/spam listing detection, no tier backfill for sellers who
  listed before round 12.

## Working efficiently in this repo
- Delegate broad repo exploration, multi-file call-chain tracing, full
  test-suite runs used for diagnosis, and CI-failure investigation to a
  subagent — bring back only the conclusion, not the raw output.
- Prefer targeted grep/glob over reading whole large files, especially
  `docs/ASKODOX_EXECUTION_TRACKER.md`. It's a historical log, not a
  briefing document.
