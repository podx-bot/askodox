# ASKODOX — Claude Code project memory

Compact by design. Full history lives in `docs/ASKODOX_EXECUTION_TRACKER.md` —
read only its most recent 1–2 round sections, or grep it for a specific past
decision. Never read it in full "just in case." If anything here conflicts
with the actual repo or `git log`/`git show origin/main`, the repo wins — fix
this file, don't trust it blindly.

## Current verified checkpoint
- `main` @ `70efccb` -- PR #161 (2026-10-06): decision brain (advice vs
  commerce `mode`), follow-up router over shown results, price truth + strict
  budgets, requested-place persistence, compact results workspace, My Business
  tiles + seller listing edit, Admin Smart Entry everywhere (Quick Add,
  templates, field states, progressive forms, CSV / bulk preview + draft
  import), admin assistant commands (en/te), Result Diagnostics decision trace.
  Production probe (run 37451777690 on the deployed 70efccb): advice questions
  -> mode=advice (en + te), shopping -> commerce, new admin endpoints 401
  signed-out, Maps all OK, price kinds labelled; strict-budget rejection and
  conditional offers are test-verified only (no priced rows in that probe).
  Signed MAIN APK 1303 (Live Build 37451688264 on 70efccb, sha256
  22fbc31c…1c93, cert 727b4a66…57cf = production; pinned in MAIN_APKS).
  Before: #159 + APK 1302.
- Railway: production env → podx-ai-connect from `main` (no custom domain,
  `podx-ai-connect-production-3279.up.railway.app`); staging env →
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
- Background push: server side is built (`push_service.py`, FCM HTTP v1,
  silent channel, once per event) but sends nothing until
  `FIREBASE_SERVICE_ACCOUNT_JSON` is set in Railway; the Android FCM client
  is added only once a Firebase app / google-services.json exists. Until
  then notifications are local + silent while the app is open/resumed.
  Exact steps: `docs/EXTERNAL_SETUP.md`.
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
