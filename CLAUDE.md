# ASKODOX — Claude Code project memory

Compact by design. Full history lives in `docs/ASKODOX_EXECUTION_TRACKER.md` —
read only its most recent 1–2 round sections, or grep it for a specific past
decision. Never read it in full "just in case." If anything here conflicts
with the actual repo or `git log`/`git show origin/main`, the repo wins — fix
this file, don't trust it blindly.

## Current verified checkpoint
- `main` (2026-10-27, `21d306c`): master command rounds 1-4 + Universal POS merged in order #220 (Smart Tools, vision inspection),
  #221 (income tax / GST / fraud / smart tricks), #222 (BLE devices, push-to-talk), #223 (photo measurement), #224 (POS
  core), #225 (restaurant tables / KOT / kitchen, held bills), POS round 3 PR (barcode from a camera photo, BLE scale reading,
  invoice PDF + native `shareFile`, suppliers / purchase bills / supplier ledger, batch + expiry FEFO, valuation, input
  tax as recorded), POS round 4 PR #227 (box <-> pieces packs, serial / IMEI, purchase orders, Classic Bluetooth + USB
  printers via `AskodoxHardware.kt` on channel `com.askodox.app/hardware`, Telugu PDF text as images, Smart Tools
  protractor / magnifier / light / sound meters / vehicle walk-around report), then #228 shop advance, #229 guide on every screen + POS online channel, #230 ready catalogue + item
  details, #231 guide offers help by itself + picture tiles + rates by quantity + spoken multi-item bill, #232 self-shopping,
  #233 guide speaks + answers, examples / pre-fill, History backup, #234 Profile tabs + search, #235 profile editor
  (mini boxes), then the new logo / app icon + Command Center heading -> category -> page grid, then #237 POS payment voice
  alerts (2026-10-26; Razorpay bank-confirmed voice with the app closed PHONE VERIFIED on APK 1374), #238 FCM speak service,
  #239 own payment methods + POS collect + "Know this first" + LIVE order checkout refused + one mixed-language console,
  #240 UPI QR photo reader (PHONE VERIFIED on 1379, PhonePe dark QR), #241 AI Credits (TEST, charging OFF), #242 collect
  safety (bank-check confirm, undo 15 min, customer pay link `/pay/upi/{id}`), #244 AI usage metering
  (`ai_usage_meter.py`, one httpx hook, counts only) -- production `d3d4df4` (2026-10-27); then (owner "1", 2026-10-27
  22:46) #245 one mixed Telugu-English Command Center, #246 Business CRM, #248 role AI agents + buyer agent, #247
  Personal Finance (Personal Tax Assistant), #249 personalization consent / clear + Telugu affiliate labels -> main
  `21d306c` = phone-test APK 1384 code (Live Build run 40543475171). Personalization stays default ON + ask-once card
  (owner decision). NOT phone verified. Status matrices: docs/MASTER_COMMAND_STATUS.md, docs/POS_STATUS.md. Production verified by a
  throwaway probe workflow (curl /health commit). Nothing phone / hardware verified.
  Before: `604d8ff` -- PR #213 (2026-10-17): Firebase OTP on APK 1336 failed ("network-request-failed" /
  "unknown [Software caused connection abort]"): MainActivity had `taskAffinity=""`, so Firebase's singleTask
  RecaptchaActivity opened in a separate task and after the reCAPTCHA browser step ASKODOX stayed in the background
  (emulator repro: browser stays in front on 1336, MainActivity resumes after the fix). Removed it (guard test
  `test_android_manifest_firebase.py`); network-class Firebase failures named; sign-in trail -> POST
  `/onboarding/diagnostics/trace` -> Railway log `signin.trace` (no numbers / codes / tokens).
  Before: PR #211 (`e96b4c4`): APK 1335 white screen = shared_preferences_android 2.5.0 (Pigeon JNI); pinned 2.4.28 in
  `dependency_overrides` (no pubspec.lock -- deps float); `askodoxStartupPrefs` (8 s -> "Try again"); publish
  workflow runs an emulator startup gate (one bash script: the emulator runner splits script lines).
  Earlier: #205-#210 auth / Firebase SMS OTP / re-login (APK 1331-1335). Firebase project askodox-81252.
  See docs/auth-and-push.md, docs/implementation-status.md, docs/resume-instructions.md, docs/payments-setup.md.
- Dev branch `claude/friendly-ramanujan-538sbj` (NOT merged, NOT in
  production, staging only) carries the post-1313 master round: voice one-audio
  lifecycle + pause / resume / mute / replay; message copy / select / share;
  Result Board mega expand with per-category navigation + provider-failure
  notice; reply meaning colours; profile memory; My Roles / My Business
  sections (promotions, automation, creations); API Health & Billing; Admin AI
  incidents + action framework; strict release gate. Every new flow is CODE
  READY only -- no real-phone verification yet.
- Railway: production env → podx-ai-connect from `main` (`podx-ai-connect-production-3279.up.railway.app`, also
  served at `admin.askodox.com` -- same service, verified 2026-10-27; console at `/admin/console`); staging env →
  `staging.askodox.com` from `claude/friendly-ramanujan-538sbj` with its OWN
  variables + volume; askodox.com → askodox-website (root `/website`), deploying from `main`
  since 2026-10-04 (the old `claude/askodox-website` branch is retired).
- Android Live Build #253 on `c2ae7d4`: PASS, in-app update published.
  Real phone: current place named "Uyyuru" (location naming verified).
- Sprint status: NOT complete. NOT yet verified: real Brave/Maps/Routes/
  Geocoding results in production (the cloud dev container cannot reach
  Brave, Railway or OSM tiles) and real-phone acceptance for every flow
  (TV, chicken "yes" = order, car Maruti→Tata, AC nearby, job openings,
  multi-category, location allow/deny/change, silent notifications + tap
  deep-link, privacy export/delete, Telugu voice).
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
- Every change follows `docs/UNIVERSAL_DEVELOPMENT_RULE.md` (universal-first,
  no category-specific fixes, cross-category tests; each PR reports universal
  applicability, extension points, cross-category tests, regressions prevented,
  justified exceptions and limitations).
- Approved features are locked in `docs/approved_features.json` (routes,
  response keys, widget keys, symbols, flag defaults, acceptance tests). The
  `Feature Registry gate` workflow fails a PR that loses any of them or deletes
  an entry; removal = status `deprecated` + owner approval + migration. Add a
  registry entry with every new approved feature.
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
- Backend tests that only hit `/deals/discover` with the user's words in
  `raw_text` do NOT reproduce the phone: replay the app's real payload
  (rewritten raw_text + `trace.query`) on `POST /deals` + `/matches`.
- Video Study: only `/api/videos/{id}/study|ask|market` + the attachment
  path; never study search results automatically (cost). Answers must cite
  the stored study (fact keys / timestamps) or say "not in this video".
- Main Chat layout: the latest results turn (`_pinnedResultsTurn`) renders
  ONCE in `_resultContext` above the chat list (bounded height, foldable);
  `_chat` skips that turn's results. Don't render it in the list again.
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
- `android/app/src/main/kotlin/.../MainActivity.kt` is the ONE native
  bridge. The Live Build / Flutter CI scripts (`tool/apply_android_*.sh`)
  used to overwrite it with older heredoc copies (so the phone APK lacked
  Geocoder naming + notifications); they must never write it again. CI
  greps guard reverseGeocode/showNotification/speechRange.
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
- Affiliate / Partner Hub + Revenue Center live in `partner_revenue_repository.py`
  (tables `partners`, `partner_secrets`, `revenue_events`,
  `partner_conversions`, `revenue_entries`), `affiliate_partner_service.py`,
  `revenue_center_service.py` and `routes/partners.py` (admin
  `/admin/cc/partners|revenue`, permissions `partners:*`, `revenue:*`).
  Partner rows join `_discover` AFTER local + online (segment `partner`);
  opens go through `/go/{click_id}` (only URLs stored with an impression);
  conversions come only from token-verified postbacks or CSV imports.
  Secrets are never returned by any API. Revenue = confirmed + paid
  commission + recorded entries; "why" findings are rule-based and graded
  CONFIRMED / POSSIBLE_CORRELATION / INSUFFICIENT_EVIDENCE.
- Offers & rewards (benefits): `benefits_repository.py` (tables `benefit_*`),
  `benefits_engine.py`, `routes/benefits.py`; results carry `benefits`
  (verified campaigns only: external types need source_url + verified_at);
  claims idempotent per (campaign, user, trigger); Scratch & Reveal is
  server-decided (highest-priority live campaign) once per completed order.
  Distinct from the older seller/admin promotions in `offers_engine.py`.
- Chat attachments: ONE endpoint `POST /api/attachments/analyze` (MIME ->
  image / video / document processor, facts via `attachment_facts.py`);
  the chat keeps real bytes (`ChatAttachment`), pickers are injectable
  (`askodoxMediaPickerProvider`); facts go in `ConversationTurnRecord.context`,
  never in the shown text.
- Customer shell (`app_shell.dart`): Home · History · centre mic (starts
  voice via `AskodoxChatRequest.voice()`) · Updates · Profile. No drawer.
  One place per function: request status lives in Updates
  (`features/notifications`); old mock alerts/communication/preferences
  routes only redirect. Don't re-add duplicate entry points.
- Acting (send request / contact) needs identity; the executor returns
  `needsSignIn` and the UI offers `/onboarding?signin=1` (real OTP), then
  retries the same action. `/auth/login` redirects there.
- Location: no built-in city anywhere (`LocationState.hasPlace`); follows
  the phone only while allowed + foreground (`watchPosition`, 300 m) and
  never overrides a hand-picked place (`followsDevice`).
- Nearby (Places) needs a real place: no location -> source status
  `needs_location`, never a country-wide query. Places/web rows in another
  country are filtered (`place_region_mismatch`, `region_mismatch`).
- Account deletion revokes earlier tokens via
  `session_tokens.set_revocation_check` (table `account_deletions`).
- Deployment keys: read through `commerce_finance.env_value` / `youtube_api_key`
  (aliases in `ENV_ALIASES`), never `os.getenv` directly in a new caller.
- #128's campaigns live in `social_sponsored_campaigns`; `sponsored_campaigns`
  belongs to `sponsored_repository.py` (rename migration in both).
- Affiliate Product Manager: `affiliate_catalog.py` + `routes/affiliate_catalog.py`
  on #127's `affiliate_products` table (columns added by migration; history in
  `affiliate_product_history`, health in `affiliate_source_health`). Eligibility
  and affiliate/organic routing are computed on read (never stored); source
  settings live in the #113 `affiliate_providers` registry via `save_source`
  (merge, never overwrite). Permissions `affiliate_products:*` (stock /
  commission / links are separate grants); console views `affproducts` /
  `affsources`. Catalog rows are `source: online` + `origin: affiliate_catalog`.
- Marketplaces (Amazon.in / Flipkart / Meesho) come from ONE site-restricted
  Brave query after local + online (`_marketplace_and_catalog`), never for
  services, fresh food or used. `classify_page` treats a store host's catalogue
  page as a store BEFORE the article regex ("Best Prices" used to drop them).
- Universal Advisor = ONE engine (`advisor_engine.py`) configured by schema
  resources `advisor_categories` (aliases, broad aliases, required /
  optional decision fields), `advisor_questions` (generic per-field wording,
  category overrides; keyword questions only when NO category matches) and
  `advisor_rules`; defaults in `advisor_defaults.py`, seeded once by
  `platform()` (v2 archives untouched v1 keyword seeds). Category = AI
  category (ignored when it just echoes the subject) -> head noun -> alias;
  a broad AI group yields to a same-group head noun. Each field has its own
  state (known / no_preference / unknown); "any" settles only the field just
  asked. A REQUIRED unanswered question holds final results in the app
  (`askodoxAdvisorHolds`) unless "show me". A question counts as asked
(`_lastAskedQuestion`) only if the reply showed it. Flag `advisor.enabled`.
- Demand Intelligence reads `pf_events` (`search` carries `local` + budget
  band; `request` / `seller_accept` / `order` / `order_completed` via
  `journey_event`). Rules = `demand_alert_rules`; matching reuses
  `app_demand_broadcast.candidate_providers`; every alert is logged with
  reasons in `demand_alerts` (cooldown + per-seller daily max, across rules).
  Sellers read `/api/opportunities`. Flag `demand.alerts`. No cron: instant
  rules run at most every 10 min after new demand, digests via Run.
- Auto-responses: `auto_response.py` (approved FAQ only, hours, handoff,
  masked contacts) hooked into `/debug/deal-message`; sellers self-serve at
  `/api/business/auto-response`. Flag `autoresponse.enabled`.
- Bounded settings: `platform_settings` resource + `platform_settings.get`
  (e.g. `video_study.max_seconds`, 30 s cache). Contact masking: one helper
  `pii_mask.py`. Deep Video Study only for uploads and REGISTERED sellers'
  videos (`_registered_video`); external videos are playback only.
- A local server uses `PODX_DATABASE_PATH` (not DATABASE_PATH).
- Web search (`brave_web_search_provider.py`): per-thread `last_error`
  (discovery runs sources in a thread pool), pacing learned from the
  X-RateLimit headers, a breaker for quota/auth errors, and `LastGoodStore`
  (`search_last_good`) serving the last good answer (rows carry `stale`,
  `cached_at`, `price_verified=false`). Never fabricate rows on failure.
- App flags: `lib/core/flags/askodox_remote_flags.dart` reads `/api/flags`
  (role / category / stable install id for %), caches 10 min + on disk, and
  keeps defaults (all on) when the fetch fails. Read a flag with
  `askodoxFlagProvider('key')`; never block UI on the fetch.
- New seller listings go through `listing_quality.check`: prohibited terms /
  flooding -> 422; contact details / links / one number across accounts ->
  held (inactive) + a `listing_reviews` record that staff approve / reject.
- The real-phone acceptance checklist is seeded into `qa_checks` as CODE
  READY (`owner_os.ACCEPTANCE_CHECKS`); only a real phone test with evidence
  moves an item to PHONE VERIFIED.
- Universal Sources (`universal_sources.py`, schema resource `sources`):
  connectors manual / feed (synced INTO `affiliate_products`, searchable
  without web search) / json_search (live, isolated, `source_health`) /
  site_search (joins the marketplace Brave query) / api. Add sources in the
  Command Center -- never per-source code. `results.sources` flag.
- `affiliate_products` is the ONE item store for staff-curated things:
  `item_type` (product/offer/coupon/service/link/news/video/content),
  `review_status` (DRAFT/NEEDS_REVIEW/APPROVED/LIVE/PAUSED/EXPIRED; rows from
  before = LIVE), `canonical_key` (duplicate detection). Only LIVE shopping
  types reach results. Health toggles: `catalog.*` platform settings.
- Staff Workspace: page `/staff` + API `routes/staff_workspace.py`, same
  permissions as the Command Center. Staff sign in with their OWN linked
  number (staff PATCH `phone`; OTP -> `/api/staff/session` -> 12 h
  `x-askodox-staff-session`, re-checked every request) or an `stf_` token.
  App: Profile "Staff Workspace" + Android Share -> one-time handoff code.
  `workspace:approve` = may publish directly; others submit for review.
- Early Access (`early_access` resource) + `/api/feedback` (masked by
  `pii_mask.mask_sensitive`; diagnostics only with consent) + client errors;
  dashboard `/admin/cc/early-access/dashboard`. Enum options in schema
  resources must be lowercase (values are lower-cased on save).
- Result Contract v2 (`result_orchestrator.py`): `/deals/discover` AND
  `/deals/{id}/matches` return `sections` (local, deals, online, affiliate,
  partner, content, videos, shorts, jobs, sponsored), `conversation_state`
  (explicit constraints EXACTLY as given), `answer.may_claim_results`, plus
  `matches` (kept for old APKs). Sources ADD sections, never replace; a
  failing source empties only its own (asked-for empty sections carry
  `empty_reason`). Order/limits = Command Center `result_orchestration`.
  The app orders rows by sections (no client re-sort) and reports drawn
  sections to `POST /api/results/rendered`; staff read
  `/admin/cc/results/diagnostics` (console "Result diagnostics").
  20 combinations: `tests/test_result_contract_combinations.py`
  (`result-contract-gate.yml`). `/matches` now carries the advisor too.
- Chat honesty (APK 1292): no reply claims "showing / finding / here are"
  unless cards render (`askodoxReplyClaimsResults`); a reply restating a
  different size is replaced (`askodoxReplyAltersSize`); "Any" settles only
  the asked field via `no_preference` (typed slots stay empty); the user's
  size is applied exactly (`askodoxExplicitSize`); a short reply to a
  finished request refines it; one no-results notice per request id.
- Public news/content = LIVE item-store rows of type news/content/video
  (`/api/content`, page `/content`, section `content`). Nearest junction:
  `/api/discover/junction` (Places, honest `unavailable`). Feeds sync on
  the background runner (`periodic_jobs` "feeds"), never in a search.
- Web search = `web_search_chain.py` (`container.web_search_chain`): Brave,
  then Google Programmable Search (`GOOGLE_CSE_API_KEY` + `GOOGLE_CSE_ID`,
  backend-only) ONLY when Brave fails (never on an honest empty answer); a
  stale Brave copy yields to a live fallback answer. `_web_search(container)`
  picks the chain; tests that replace `brave_web_search_provider` alone get
  that provider. `/health/search` shows `fallbacks`.
- Nearest junction: `is_junction` needs a transit/route type or a junction
  word in the place's own name with no business type ("Unacademy Centre" is
  a school). The app's map picker shows "Near X · N m", "Pin here", and adds
  ", near X" to the confirmed label (pickup / drop / location).
- Videos: `result_orchestrator.video_preference` puts Shorts or long videos
  first from the user's own words (`demand["said"]` = trace.query); rows are
  ranked by subject relevance; videos still only when asked / relevant.
- App results: `source == 'content'` rows form the "News" compare group.
- Mobility = `delivery_jobs.py` + `routes/delivery.py` (ONE system: rides,
  parcels, local / order delivery, carpool, reports). `REQUESTED/PARTNER_SEARCH`
  is never "confirmed"; trip steps forward-only (`allowed_step`);
  `PRIVATE_DETAIL_KEYS` + phones only to the requester / assigned partner after
  acceptance; fares only from `mobility_services` (ACTIVE row). Partners are
  `delivery_partners` (apply -> PENDING_REVIEW; staff approve / correction /
  disable). Order fulfilment responsibility: `fulfillment.py` (delivery state
  derived, separate from commerce state). Older WhatsApp ride stacks
  (`ride_repository`, `local_dispatch_*`) are legacy -- don't extend them.
- Native video: `routes/native_video.py` (upload metadata may come as query
  params -- the app's `ApiClient.upload` sends only the file). Unpublished
  media only to owner / staff. Video DMs answer from approved FAQ only.
- Integration states: `integration_readiness.runtime_rows` + public
  `/health/integrations` (no secrets). Firebase "configured" is never LIVE.
- Theme: `PodxApp` uses `ThemeMode.light` (the shell is light). A dark app
  theme turned every pushed route black -- don't reintroduce it.
- Category tree = `taxonomy.py` + resource `taxonomy_nodes` (staff-editable,
  seeded once) + `/api/taxonomy/resolve`; capabilities inherit down the path.
  The app calls it only for delivery capability / partner phrases.
- Video commerce = `video_commerce.py` (grounding basis, sensitive topics never
  AI-answered, reply plan off/draft/auto) + `routes/video_commerce.py`; the
  detail route `/api/videos/native/{id}` is registered LAST. App:
  `native_video/video_commerce.dart`; chat questions about a video go to its
  study (`_videoStudyRef`, `nv_` -> native ask endpoint), never the deal search.
- In-app Screen Guide = `features/guide/in_app_guide.dart`, mounted in the app
  builder. Steps target existing widget KEYS (`x*` = prefix); visible = a hit
  test reaches it. Renaming a targeted key breaks a walkthrough -- grep
  `askodoxGuideFlows`. Private routes pause it (`askodoxGuidePrivateRoutes`).
- Mobility draft (`askodoxMobilityDraftProvider`) is the ONE ride / parcel being
  set up, shared by chat and the Rides screen.
- Push preferences: `push_prefs` (app Notifications switches via
  `PUT /api/me/notification-settings`); `PushService.notify` obeys them.
- Own-supply fit: `supply_fit.evaluate` judges a registered listing against the
  customer's explicit constraints (matched / unmatched / unknown -- unknown is
  never assumed); registered rows carry `fit` + `why` and rank by fit; gaps are
  aggregated in `supply_gaps` (no customer identity) for sellers and staff.
- Smart Entry = `smart_entry.py` + `POST /admin/cc/smart-entry` (prepares forms
  only; value + confidence + provenance; only high confidence pre-fills); the
  console view maps results onto the real create forms. Reuses
  `affiliate_catalog.extract_metadata` -- don't add another page fetcher.
- Staff work queue items are explained by `admin_actions.enrich` (fixed en/te
  WHAT / WHY / IMPACT / ACTION per key, severity from real counts). A new queue
  key needs a TEXT entry. Integration failures come from
  `_failing_integrations` (same live state as the readiness page).
- `tests/test_admin_functional_audit.py` audits every platform resource from
  its schema; a new resource with a cross-field rule needs an OVERRIDES entry.
- Decision brain: `decide()` returns `mode` advice / follow_up / commerce / chat.
  Advice (`wants_advice` on the USER's words only -- `split_app_context` strips
  the app's "Options already shown" context) gets a separate reasoning call
  (`_advise`) and NO search; the app's `adviceOnly` keeps it out of the deal flow.
- Follow-ups over shown results (compare / cheapest / nearest / reviews / deals /
  under budget / directions ...) are answered by `follow_up_router.dart` from the
  pinned results, never a new search; unknown facts say "Not verified".
- Price truth = `price_truth.py` (list / selling / offer / starting_from /
  page_level; conditional bank / coupon prices go in `offer_price` +
  `offer_condition`, never the price). Strict budgets ("only", "max") drop over-
  budget rows into `rejected`; the app labels "with eligible offer".
- Requested place (`_requestedPlace` in the home screen) survives follow-ups
  until "near me" or a hand-picked place change; it is separate from the device
  location.
- Smart Entry everywhere: `qaStrip`/`qaSetup` in the console add Quick Add,
  templates (built-in `smart_entry.TEMPLATES` + resource `entry_templates`,
  structure only -- `TEMPLATE_FACT_FIELDS` refused), field states, Required /
  Recommended / Advanced and Duplicate previous to every create form. Bulk =
  `/admin/cc/smart-entry` (CSV too) with NEW / UPDATE / DUPLICATE / INVALID /
  NEEDS_REVIEW + `/smart-entry/import` (confirm, drafts only, per-item perms).
- Admin assistant commands = `admin_ops.py` (en/te); the assistant never writes,
  it returns an `operation` the console opens behind a confirm.
- Result Diagnostics payload also carries mode, requested location, raw vs kept,
  rejected, price provenance, ranking and card actions (`_decision_trace`).
- Search readiness belongs to the Conversation Decision Brain: `decide()` returns
  `state` (facts / flexible / unknown_critical), `search_ready`, ONE
  `next_question`, a consolidated `search_subject`, `new_need`; the app sends
  `searched_for` (what is on screen). EVERY retrieval passes
  `askodoxSearchGate` (`lib/features/home/domain/search_readiness.dart`):
  user "show me" > brain readiness > the offline schema rule (only when the
  brain gave none). Brain facts go into the deal via `applyBrainState`; the
  restore path needs `dynamicFields['searched']`. Never add category scripts,
  keyword -> question rules or "search after N answers". Changed details mark
  pinned cards outdated (`askodoxResultsOutdated`); a different need hides them.
  Real-LLM proof: `conversation-trace.yml` + `.github/conversation-traces.json`
  (branch push -> waits for staging `/health` commit -> per-turn TRACE lines).
- Conversation relation (`conversation_relation.py`) compares CONTENT words only
  (grammar, constraints, acks, option refs, numbers removed; Indic-aware tokens,
  plural-insensitive). Thin refinements / acks / choice questions keep the deck;
  a single new word is a WEAK new topic that counts only when the model agrees
  (`reconcile_relation`); a model-confirmed new need whose own description shares
  nothing with the active one retires the deck. The app sends `said_subject` +
  `sources` in `searched_for`. Never add per-category phrases.
- Video asks: a search only when there is something to search videos OF
  (`_video_search_wanted`); talk about Facebook / Instagram / Meta / setup stays
  chat (app: `askodoxTalksAboutVideoPlatform`).
- Comparisons never name a place / price / status / source label as a thing
  (`comparison_entities.py`, app `askodoxComparableLabel`).
- Result Board (home screen): `_boardMinimizedFor` (pill "N Results • ₹20k
  subject ▲", restore), fresh results re-expand, retirement clears pill +
  selected context (`askodoxSelectedContext`), "the best one" -> one card
  (`askodoxWantsSingleResult` / `askodoxBestOnly`). Built on `_resultsByTurn`.
- Header language chip = the reply language (lock > preferred > automatic);
  choosing there is an explicit lock (`lockTo`, PR #166 semantics).
- Affiliate Product Hub: `affiliate_providers.py` (adapter registry, Meesho
  __NEXT_DATA__ first; provenance per field; commission never from a page),
  `affiliate_hub.py` + `routes/affiliate_hub.py` (preview / import / bulk-action),
  console view `affhub`; grant `affiliate_products:publish`. Same item store
  (`affiliate_products`); Smart Links stay routing only.
- Provider health = real answers (`provider_health.py`): Sarvam 402 ->
  QUOTA_EXHAUSTED; readiness rows + Command Center use it, never key presence.
- One-time advice = `advice_memory.py` inside the ONE brain (`decide()` / `_advise`):
  the app keeps the ledger per conversation (`_adviceLedger`, in the snapshot) and
  sends `advice_given`; the reply returns `advice` + `advice_ledger`. A repeat is
  allowed only for new_information / user_asked / critical; others are flagged +
  counted (`assistant_health`). Never add per-category warning rules.
- Command Center feature health (`/admin/cc/health`): `assistant_health.py`
  (conversation_intelligence, media_analysis, advice_policy -- real outcomes, per
  process; no traffic = unknown) + `result_discovery` from `discovery_events`.
  Provider readiness is separate (`provider_health`); neither proves a phone flow.
- Result Board ARCHIVED: a deck retired by a topic change shows only the chip
  `askodoxArchivedResultsRestore` (restores on tap, never on its own).
- Result Board lifecycle + sizing = `lib/features/home/domain/result_board.dart`
  (`askodoxBoardStateOf`, `askodoxBoardMaxHeight` from the Home column's REAL
  height via LayoutBuilder; no room -> pill). Never size it from the full screen.
- Reasoning before results: `DECISION_GUIDANCE_RULES` in the brain prompt (ready
  turns reply with guidance, never a bare acknowledgement; estimates labelled,
  never presented as verified). The app keeps that reply with the cards; a false
  results claim is removed sentence by sentence (`askodoxStripResultClaims`),
  never the whole reply; an advisor hold keeps the brain's answer
  (`askodoxWithoutTrailingQuestion`).
- Channel = `channel_preference.py` (app `askodoxChannelPreference`): online-only
  skips local sources + forces the web search; local-only skips the web search;
  remembered as deal `dynamicFields['channel']`; a channel switch archives the old
  deck. Never per-category.
- Assistant replies render through `AskodoxRichReply` (headings / points / bold /
  tables / links); speech gets `askodoxPlainReply`. Never show raw markup.
- Voice ends on the user's Stop; `AskodoxVoiceEndpointer` silence (8 s) and 2 min
  are safety limits only. Companion menus = `askodoxCompanionMenuActions` (no
  Location; the header chip is the one location control).
- Self-healing: APPLIED != recovered; `verify_applied` sets VERIFIED /
  NOT_RECOVERED from real evidence, else UNVERIFIED (console "Recovery").
- Voice = ONE audio lifecycle: every `_speakReply` takes `_speechTurn`; Stop / a newer
  reply bump it so a cut-off reply never falls back to device TTS (two voices). Pause:
  Sarvam pauses in place (`pauseReplyAudio`); device TTS stops and resumes from the last
  `speechRange` start with the SAME engine (`deviceOnly`). Mute skips speech; Replay forces.
- Provider failures carry their kind: Brave `last_error_kind` (per thread) -> chain ->
  `provider_failure.failure_kind` -> source status quota_exhausted / rate_limited /
  auth_failed / error (never `no_results`); app `askodoxProviderProblemText`.
- Result Board default = the LOCKED one-rail layout (after 1303). Category boxes with
  up / down + n/N exist only in mega expand (`askodoxResultBoardMega`); positions live in
  `_boardPositions` ("dealId:kind") so they survive minimize. Don't replace the rail.
- Reply meaning colours come ONLY from the brain's [ok] / [caution] / [risk] tags
  (`askodoxSeverityOf`), never from app keyword guesses; tags are stripped from speech / copy.
- Profile memory = `profile_memory.py` + `/api/me/memory` (hooked in `create_deal` via
  `_remember`): role buyer / seller / service_provider / service_taker (= seeking services
  or jobs), same need UPDATES (history), secrets dropped / masked, private unless consent,
  deleted with the account. Separate from the live demand records.
- Personalization consent: `/api/me/memory` returns `chosen` (False = ON by default, never decided -> the memory screen
  asks once) and `cleared_at`; "delete all memory" also stops EARLIER chats (`conversation_backup.recent_requests(since=
  cleared_at)` on server `saved_at`, which an unchanged re-sync never bumps) from personalizing answers.
- My Business sections = `askodoxBusinessSections` (insights / Analytics first, then
  sections). New sections need a real route; Home must never link My Business.
- API Health & Billing (`api_billing.py`): a balance is REAL only from the provider
  (Brave X-RateLimit headers); otherwise UNKNOWN or a labelled ESTIMATE from an admin
  budget. No recharge route may exist (release gate checks it).
- Admin AI incidents (`admin_incidents.py`) are template text over telemetry; a reason is
  confirmed only from the provider's own answer. Actions only via
  `admin_action_framework.CATALOG` (read-only max 2/h; changes need approval; blocked after
  two NOT_RECOVERED).
- Release gate (`release_gate.py`, `/admin/cc/release-gate`): READY only when all PASS;
  device = qa_checks PHONE VERIFIED only. Image / video generation stay NOT_AVAILABLE
  until a provider is chosen and its cost approved.
- Travel Radio = `travel_radio.py` + `routes/radio.py`: add-on plans live in `growth_plans` with audience
  `addon_radio` (INACTIVE; `/api/subscriptions` refuses add-ons); passes in `radio_passes` (paid = PENDING_PAYMENT,
  staff PROMOTIONAL only); segments only from geocoding / Places / LIVE content; cost model = ESTIMATE.
- Base plans = `subscription_plans.py` (audience `base`, seeded once from `growth()`, never overwritten);
  Smart Fill = `catalogue_templates.smart_fill` (seller's own words only; app fills empty fields only).
- Partners take jobs only with `docs_checked` complete (`delivery.docs_missing`); paid plans go on sale only
  with `billing.live_pricing`; updates install only on a matching SHA-256 (`askodoxApkDigestMatches`).
- Billing = `billing.py` + `routes/billing.py` on the ONE payment layer (`commerce_finance.PaymentService`,
  `razorpay_gateway.py`, `cashfree_gateway.py`); purchases activate only via `Platform.sync_order` on PAID
  (`billing:` order_ref). Live mode = env `ASKODOX_PAYMENTS_LIVE_APPROVED` only (never the console).
- Razorpay checkout = the hosted page `/billing/pay/{id}` (routes/billing.py `page_router`, mounted in app_factory);
  payment.failed never fails an order (retry allowed); `billing.refresh` reads back via GET only. Env-only gateway
  credentials enable TEST mode until staff configure the row (`updated_by`). The public health row must never
  contain the word "secret" (test_integration_states).
- Gateway state = `payment_gateway_health.check` ONLY (public health row, readiness, API Health, Billing); only a
  Razorpay 401 records a failed check. TEST money -> purchase TEST_PAID, never a subscription / pass. Why a tester has no Pay
  button: Railway deploy logs, filter `billing.options` (masked last 4, tester, reasons).
- Integration Platform (docs/integration-platform.md): `integration_catalog` statuses are COMPUTED (never
  hand-set; mock never counts as tested; NOT BUILT / interface_ready named honestly); sign-in OTP =
  `otp_delivery` (ASKODOX_OTP_CHANNELS); demo number works in production only with ASKODOX_DEMO_LOGIN=yes;
  KYC = `kyc_engine` (consent first, masked + HMAC only, AI extraction never verifies, staff verify only
  business / professional docs); commissions = `commission_engine` on Partner Hub (forward-only lifecycle,
  clicks never conversions); identity = `account_identity` (auth_accounts, one id per 10-digit number; the app
  stores the server's app_user_id).
- Sessions / sign-out: ONE place a verified number becomes a session (`onboarding_auth.signed_in`: returning +
  saved profile -- the app never overwrites it). Sign-out = `lib/core/auth/sign_out.dart` (Profile Settings &
  Privacy last item + header menu Logout): server revoke, FCM token delete, per-account phone data stash
  (`askodoxAccountScopedKeys`, a new account-scoped prefs key must be added there), `AskodoxAppRestart` (fresh
  ProviderScope). Start-up `askodoxCheckSession`: 401 -> signed out, offline -> kept. Firebase init only via
  `AskodoxFirebaseConfig.ensureInitialized` (single flight). Diagnostics never in APP_ENV=production builds.
- Firebase Android config is GENERATED in CI (`tool/firebase_android_config.py write`, required on main) from the
  four FIREBASE_* GitHub variables -> git-ignored `android/app/google-services.json` + Dart define file; the Google
  Services plugin (4.5.0, settings.gradle.kts) is applied only when that file exists; `check-apk` proves the APK
  carries it. Never commit google-services.json or print the values.
- `flutter analyze` in `android-apk.yml` (build-apk) is FATAL on infos too; CI logs are not readable through the
  proxy -- push a throwaway branch whose workflow echoes analyzer / test lines as `::warning::` annotations.
- AXE (`executive_ai.py`) only composes existing gate / incidents / billing / registry; it never runs actions.
- Universal POS = `pos_tax.py` (pure GST arithmetic, versioned `RULES_VERSION`, sourced) + `pos_store.py` (tables `pos_*`)
  + `routes/pos.py` (`/api/pos/*`); app `lib/features/pos` (entry My Business -> `/pos`). Money = integer paise, qty =
  milli-units, rates = basis points; issued invoices / payments / ledger / stock moves / audit are append-only (fix with a
  credit note or same-day cancel that keeps the row). Every write is idempotent on `client_txn_id`. Non-members get 404.
  Counter UPI / card = `cashier_confirmed`, never bank-verified. HSN / GST rate only from the shop's own entry. Shared
  vectors `test/fixtures/pos_tax_vectors.json` must pass in BOTH pytest and flutter test -- change both engines together.
  Offline bills use a per-device series (`<P>D<n>/<FY>/<6>`, <=16 chars). Invoice prefix max 3 chars.
  Restaurant = `pos_restaurant.py` (bills via `PosStore._issue` in the same tx); purchases / suppliers / batches =
  `pos_purchases.py` + FEFO in `PosStore._allocate_batches` (expired stock is never sold). New columns go in
  `pos_store.MIGRATIONS` (ALTER TABLE ADD COLUMN), never by recreating a table. Widget tests: never `await` a stream
  subscription `cancel()` / `Future.timeout` in code a fake-async test drives (they hung; see `AskodoxScaleReader`).
  NEVER add `mobile_scanner`: it broke the OTP SMS-consent background case (`sms-consent-e2e.yml`, A/B on 2026-10-24);
  barcodes are read from a photo with pure-Dart `zxing_lib` (`askodoxDecodeBarcodePixels`). Any new native plugin must
  pass `sms-consent-e2e.yml` (it only runs on Kotlin / gradle changes -- dispatch it by hand for a pubspec change).
- Printers / meters native code lives ONLY in `AskodoxHardware.kt` (own channel `com.askodox.app/hardware`, one
  register line in MainActivity); saved printer ids `classic:<MAC>` / `usb:<device>` route native, others BLE
  (`AskodoxRoutingPrinterTransport`). PDFs draw non-ASCII text via `lib/core/pdf/askodox_pdf_text.dart` (await `want`
  before building). POS packs: stock + FEFO always in base units (`base_qty_milli`); serials in `pos_serials`.
- Shop advance = `pos_advance.py` (record only; money stays with the shop): every deposit / deduction / refund is a
  pending `pos_advance_entries` row that ONLY the customer's own OTP-proven number (`app-phone-*`, phone_key = customer
  phone) can approve via `/api/pos/me/advances/{id}/decision`; the shop can only withdraw a pending row. Terms en/te
  (`TERMS_VERSION`) must be accepted by the owner (settings) and by each customer on first approval. Never let staff
  approve, never pay out across shops, never call it a wallet (no RBI licence).
- POS online channel = `pos_online.py`: shop default `pos_businesses.online_default` + item `pos_products.channel`
  (NULL = default); Online / Both = ONE `seller_products` row per item via `pos_online_links` (screened by
  `listing_quality`; review -> hidden + `listing_reviews`); routes call `_online_sync` after sales / stock / purchases
  (best effort, never fails the sale). Online-only items are filtered out of the sale screen picker only.
- Guide button on every screen = `features/guide/screen_help.dart` (`askodoxScreenHelp` by router path pattern, en+te)
  + `screen_help_button.dart` (mounted in app.dart). A NEW SCREEN ROUTE NEEDS AN ENTRY (or an exempt reason) or
  `test/features/guide/screen_help_test.dart` fails. Hub tiles = `shared/widgets/askodox_tile_grid.dart`;
  `AskodoxNavSection` rows without a trailing control are drawn as the same tiles.
- POS catalogue = `pos_catalogue.py` on the ONE `catalogue_templates` engine (shop template = `catalogue_template`
  or `DEFAULT_TEMPLATE[business type]`; `UNIT_MAP` to POS units; import needs the owner's price + GST % when
  regular; details via `clean_attributes` into `pos_products.attributes` -> listing attributes; `online_price_paise`
  (owner / manager) = listing price). Field "?" guides = `shared/widgets/askodox_field_guide.dart`
  (`askodoxAttributeGuide` is generated from the spec -- never per-category text); `AskodoxPosField(guideEn: ...)`.
- Startup: `AskodoxStartupHint` (in memory, cleared on sign-out / account delete) -> the router (rebuilt on every
  session change) starts at '/' after onboarding; onboarding never un-hides the language step while leaving.
  `justOnboarded` -> Home opens the welcome guide once (screen_help_button).
- Guide watching = `features/guide/guide_watch.dart` (`AskodoxGuideNudges` singleton; `AskodoxFieldGuideInfo` wraps a field
  with its help text; `AskodoxPosField(guideEn: ...)` does it). The help layer turns an empty focused box (5 s) or a
  reported error (POS `_fail` on 400/403/409/422) into "Need help?"; a page change clears it. Don't add "?" icons to fields.
  POS rates by quantity = `pos_price_tiers` (per base unit, from a minimum) + `pos_products.min_qty_milli`, applied in
  `PosStore._issue` and app `askodoxTierPrice` (keep both rules equal); photos = `pos_product_photos` (<= 300 KB PNG/JPEG).
  Spoken orders = `askodoxSplitPosOrder` / `askodoxParsePosOrder` -> `AskodoxPosOrderReviewSheet` (never adds silently).
- Self-shopping = `pos_selfshop.py` (tables `pos_selfshop_*`) + `/api/pos/selfshop/*` (customer, any signed-in user, join
  rate-limited) + `/api/pos/businesses/{id}/selfshop*` (staff). Daily 6-digit code (QR `ASKODOX-SHOP:<code>`); sessions
  OPEN -> CHECKOUT (4-digit exit code) -> BILLED via `PosStore.create_invoice` (client_txn_id `selfshop-<sid>`); weighed /
  serial items are refused to the counter. Exit check = `askodoxDecodeAllBarcodesPixels` (zxing GenericMultipleBarcodeReader,
  DISTINCT codes only -> quantities by hand). Payment stays at the counter; never mark a list paid without the cashier.
- Guide sheet = `features/guide/guide_sheet.dart` (reads the screen help aloud, ask box + mic -> `/api/in-app/guide/ask`
  grounded on the screen help only, "Show me" = `askodoxFlowsOwnedBy(path)`: flows whose last routed step is on this
  screen -- never guess a flow from a step that merely passes through). POS boxes show an example inside
  (`askodoxPosFieldExample`); item details pre-fill EMPTY details via Smart Fill from the item name / seller's words.
  History = local archive + `/api/me/conversations` backup (`conversation_backup.py`, newer copy wins, deleted with the
  account); `_user_memory` in in_app_assistant gives the brain the caller's own earlier requests (token only).
- Profile = search / talk bar (`askodoxProfileSearch` + mic; one spoken match opens it) + three tabs `askodoxProfileTab-me|
  business|settings` + recent chips (`askodox.profile.recent.v1`). Rows go through the local `row(...)` helper so they are
  indexed for search; a running walkthrough switches to the tab holding its target key. Keep every row key when moving rows.
- Profile editor = `profile_editor.dart` (`askodoxOpenProfileEditor`): mini-box grid, one box open at a time, phones
  (`phones` JSON: kind / number / same_as_personal / from / to; the verified number is shown locked) + addresses
  (`addresses` JSON; old `address` / `business_address` follow the first home / business entry server-side), roles chosen
  ONLY in its roles card (signed-in Profile shows no role chips). Guide targets open their box (`_guideTargets`).
- App icon / splash = COMMITTED PNGs in android/app/src/main/res (adaptive mipmaps, drawable-nodpi/askodox_splash_mark.png);
  source art `assets/brand/askodox_logo_source.svg`; in-app `AskodoxLogo`. `tool/apply_android_askodox_branding.sh` must never
  write launcher / splash files again (it only checks they exist).
- Command Center console map = `admin_console_nav.py` (heading -> category -> page; ONE mixed Telugu-English `label` /
  `what` / `do` per item -- "Payment స్థితి", never "English · తెలుగు" or a stacked Telugu line). A new console view or
  schema resource needs exactly one entry there or `tests/test_admin_console_nav.py` fails. View titles come from the
  nav label (`head()` -> `labelOf(VIEW)`). Errors go through `explainError` / `errText` (ONE mixed why / what-to-do per
  HTTP status). Work queue `admin_actions.enrich` -> `explain` = one mixed {what, why, impact, action, button};
  incidents: the console reads `?language=te` (= the mixed text).
- POS payment voice alerts = `pos_payment_alerts.py` (events, dedupe, devices, acks, fan-out; phone events are ALWAYS
  `notification_unverified`) + `pos_payment_providers.py` (the shop's OWN Razorpay: encrypted keys, UPI QR, signed webhook
  `/api/pos/payment-webhooks/razorpay/{id}` + Razorpay API re-check -> `record_verified`; live keys only with
  `ASKODOX_POS_PROVIDER_LIVE_APPROVED=yes`). Native = `AskodoxPaymentAlerts.kt` (channel `com.askodox.app/payment_alerts`,
  chime + max media volume + LoudnessEnhancer player, `speakRemote` once per event) + `AskodoxMessagingService` (subclass of the FlutterFire messaging service; the plugin service is removed in the manifest)
  (high-priority FCM data `type=payalert` via `PushService.send_data`, speaks with the app closed). The notification
  LISTENER is NEVER in the default manifest: Play Protect blocked sideloaded APK 1366 for it -- Play builds only
  (`tool/apply_android_payment_alerts.sh`, Live Build `include_payment_alerts` + `build_play_bundle`); CI fails a
  sideloaded APK that declares it. Flag `pos.payment_alerts` = emergency off. Flutter: `/pos/:id/payment-alerts`.
- AI Credits = `ai_credits.py` + `routes/ai_credits.py` (append-only `ai_credit_ledger`, UNIQUE ref, live + TEST balance;
  added ONLY in `billing.on_payment`; assistant reserves one 'chat' use before the model, releases on no answer; charging
  OFF until staff rates). Packs = growth plans audience `ai_credits` (seeded INACTIVE). Play Store sale needs Play Billing.
- Business CRM = `pos_crm.py` + `/api/pos/businesses/{id}/crm/*` (app `pos_crm_screens.dart`, My Business -> `/crm`,
  shop tile `/pos/:id/crm`). ON the POS core, never a copy: customers = `pos_customers` (save-as-customer via
  `PosStore.add_customer`), quotations = `pos_drafts` kind quotation (`pos_crm_quotes` only links + status; the sale screen
  takes `?lead=&customer=` and the drafts route auto-links), staff = `pos_members` (masked refs), bills / dues read from
  `pos_invoices` / `pos_payments` / `pos_ledger`. Permission `crm` (owner / manager / cashier), reports need `reports`.
  Timeline `pos_crm_activity` is append-only; follow-up pushes = periodic job `crm_reminders` (once per follow-up).
- Role AI agents = `pos_agents.py` + `/api/pos/businesses/{id}/agents|agent-actions` (app `pos_agent_screens.dart`,
  `/pos/:id/agents`, buyer agent `/me/agent` via `/api/pos/me/agents/buyer/ask`). An agent = a role VIEW (its POS
  permission), facts via the same store methods, the model only re-words (`_phraser`, AI Credits reserve when charging ON).
  SAFE actions run as the caller; SENSITIVE ones PENDING_APPROVAL -> owner / manager approves -> run AS THE APPROVER (four
  eyes for managers, staff roles owner-only). Never add an agent action that moves money, messages customers or deletes.
- ASKODOX NEVER holds buyer / seller money (owner rule 2026-10-27). Own ways to be paid = `payment_methods.py`
  (`user_payment_methods`, any app's UPI QR via `parse_upi_qr`, bank number encrypted) + `/api/me/payment-methods`; POS
  collect to the owner's own UPI = `pos_payment_alerts` collect requests (a notification only MATCHES, the shop confirms);
  orders show `pay_to` to the buyer; a LIVE platform checkout for orders is refused (409). Escrow only via a licensed
  partner after owner + legal decision. Command Center = ONE Telugu-English mixed view (no separate en / te toggles).
- Backend tests use a per-run temp DB (`backend/tests/conftest.py`); don't
  reintroduce a shared `podx_v2.db` -- data leaked across re-runs.

## Known open issues (verified, not yet fixed)
- Voice replies: Sarvam Bulbul audio first, device TTS fallback (the old
  `/discover/*` screen with the system recognizer is removed; the Kotlin
  `startVoiceSearch` method remains unused).
- A combined answer ("1 kg curry cut skinless") is stored whole in both
  `cut` and `chickenPreference` (matching still completes).
- No automated check catches "a route's auth requirement changed but a
  Flutter caller wasn't updated" — manual grep only (see gotcha above).
- Naming the current location needs the Geocoding API enabled on the Maps
  key; otherwise the app honestly keeps "Current location".
- Provider leads (`/deals/leads`) are in-app only (home-screen inbox +
  Updates): WhatsApp-only providers are not targeted.
- Background push: server (`push_service.py`) + Android FCM client are built but inactive until the Firebase
  project exists: GitHub variables FIREBASE_API_KEY / APP_ID / SENDER_ID / PROJECT_ID (APK build) and Railway
  FIREBASE_SERVICE_ACCOUNT_JSON. Until then notifications are local + silent while the app is open.
  Exact steps: `docs/auth-and-push.md`.
- Maps (2026-10-04 11:09 probe): Geocoding, Places (New), Places nearby and
  Routes are all OK in production (`/health/maps` all_ok). Real nearby rows
  and the nearest junction now come back; real-phone check still pending.
- Brands: no fixed list -- AI `brand` entity, phrasing, brands on real
  listings (`/api/products/brands`), or a short reply that filled nothing.
  A brand the AI misses in the FIRST message and that no listing carries
  can stay in the subject next to a later brand.
- Companion: human 3D personas are ONE procedural rig (`companion_human.dart`)
  on the shared rasterizer (`AskodoxRaster` in `companion_3d.dart`) --
  stylized, not photoreal; robot = Lite fallback; flat 2D = 3D off. Optional
  avatar packs (`companion_avatar_packs.dart`, `ASKODOX_AVATAR_BASE_URL`) are
  not hosted anywhere yet. Lip-sync needs device TTS `onRangeStart` (API
  26+) or Sarvam audio position; otherwise text-paced. See
  `docs/COMPANION_AVATARS.md`.
- Monetization/price-benchmark l10n strings still contain demo wording but
  are not reachable from customer screens. No-match "Notify me" not built.
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
- Partner Hub: secrets are Fernet-encrypted (`ASKODOX_SECRETS_KEY`, fail
  closed without it); click ids are HMAC-signed, counted once, expire
  (`ASKODOX_CLICK_TTL_HOURS`); raw events roll up per day after
  `ASKODOX_EVENT_RETENTION_DAYS` (run lazily at most daily -- no cron). No real
  partner is configured.
- Affiliate catalog: stock / commission change by staff edits, a feed
  import, or (once credentials exist) the marketplace API refresh;
  page-metadata extraction often gets blocked by marketplaces.
  #127's partner registry / staff assignments / BFSI flows and
  `partner_revenue_events` remain unwired (superseded by Partner Hub).
- Customer web chat is the backend-served `/chat` page (same APIs as the
  app); askodox.com proxies `/chat` + its 3 APIs to the backend (website
  Caddyfile). It cannot send requests (identity stays in the app).
- Social auto-DM: Facebook / Instagram adapters are built (`social_dm.py`,
  `/webhooks/meta-messaging`, `social_dm_accounts`, mock simulate) but need
  Meta App Review + the Meta app credentials + each business's Page token
  (EXTERNAL SETUP). WhatsApp auto-DM needs the business's own WABA number;
  Snapchat has no public messaging API.
- Marketplace product APIs: Amazon PA-API 5 / Flipkart adapters are built
  (`marketplace_api.py`, catalog "Refresh from marketplace API") but no
  credentials are configured; Meesho has no product API (feed / staff only).
- Brave web search: the plan was out of credit (HTTP 402) until the owner
  funded it on 2026-10-04; production probes since then answer 200 with real
  online / marketplace rows. The 402 breaker + stale last-good stay in place.
- Mobility: production has no approved driver yet and `delivery.matching` is
  off, so every request honestly ends NEEDS_CONFIGURATION / NEEDS_PARTNER.
  No payment for rides (fare = configured estimate only); no live tracking
  map (partner steps only). Carpool is cost-sharing, not commercial.
- Native video files live on the Railway volume next to the DB
  (`video_uploads/`); no transcoding or server thumbnails (optional upload).

## Working efficiently in this repo
- Delegate broad repo exploration, multi-file call-chain tracing, full
  test-suite runs used for diagnosis, and CI-failure investigation to a
  subagent — bring back only the conclusion, not the raw output.
- Prefer targeted grep/glob over reading whole large files, especially
  `docs/ASKODOX_EXECUTION_TRACKER.md`. It's a historical log, not a
  briefing document.
