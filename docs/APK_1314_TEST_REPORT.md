# APK 1314 — test report (2026-10-09)

Automated results and phone results are kept SEPARATE. Nothing here is PHONE
VERIFIED until the owner confirms it on a real phone.

## A. Automated — local test suites (mocked providers)
| Suite | Result |
|---|---|
| Backend (`backend/tests`, 120 files, main `bae9c9e`) | **1034 passed, 0 failed** |
| Flutter (`flutter test`, Live Build run 37885318118) | **956 passed, 4 skipped** |
| CI on main `bae9c9e` (20 workflows incl. result-contract, registry gate, e2e smokes) | **20/20 success** |

Covers (mocked): sessions/tokens, profile memory, roles, orders + contact
masking, payments webhooks, delivery/mobility, admin RBAC + audit, flags,
backup, notifications/push, support, partners, attachments, video study,
search resilience, result contract (20 combinations).

## B. Automated — LIVE API probe (real providers)
Workflow `API live probe`, run 37887259779 (commit `d951ffe`).
Staging = functional (own data, own keys). Production = read-only GETs and
no-credential refusals only. No payments, no customer messages, no production
writes.

Totals: **staging 46 PASS / 2 FAIL / 2 PARTIAL; production 10/10 PASS**; no call over 20 s.

| Area | Check | Result | Evidence |
|---|---|---|---|
| Platform | /health (staging d951ffe, prod bae9c9e) | PASS | 200 |
| Integrations | /health/integrations | PASS | Maps LIVE; Gemini, OpenAI, Sarvam STT/TTS, Brave = CONFIGURED_NOT_VERIFIED; Google CSE fallback DISABLED; Firebase push NOT_CONFIGURED; Mobility DISABLED (staging) / NOT_CONFIGURED (prod) |
| Maps | /health/maps | PASS | geocoding, places text, places nearby, routes all OK |
| Voice readiness | /debug/voice-readiness | PASS | TTS model/voice present, ffmpeg available |
| Flags | /api/flags | PASS | 18 flags; only `companion.screen_guide` off |
| Reasoning | AC 3-turn continuity | PASS | T1 asks type/size (search_ready false) -> T2 asks room size -> T3 search_ready true, subject "1.5 Ton Split AC" (~2 s/turn) |
| Telugu | Telugu request -> Telugu reply | PASS | 85 Telugu chars, asks door type + budget |
| Advice | advice mode, no search, no raw tags for old apps | PASS | mode advice, search_ready false, raw_tags false (~10 s) |
| APK 1314 | meaning tags with capability | PASS | tags present when capability sent |
| Context | Maruti -> "Tata instead" | PASS | facts.brand = tata |
| Search | product: 1.5 ton split AC | PASS (quality PARTIAL) | 9 cards: local 1, deals 4, online 4; links 9/9, images 4/9, **price 1/9**, all prices unverified; one card is a category page ("Buy Air Conditioners Online…") |
| Search | videos: Samsung Galaxy S24 review | **FAIL** | videos/shorts `no_results`; online/marketplaces/used `quota_exhausted` |
| Search | jobs: delivery boy jobs | **FAIL (probe + quota)** | jobs not planned (probe sent intent "buy"); web sources `quota_exhausted` |
| Search | AC repair nearby | PASS | Places: "SML AC SERVICES / ELECTRICAL WORKS" |
| Search | no location -> no country-wide search | PASS | nearby not run |
| Search | provider failure is labelled, not "no results" | PASS | `quota_exhausted` per source; `answer.unavailable` lists them |
| Location | reverse geocode | PASS | "Mogalrajapuram, Vijayawada, Andhra Pradesh" |
| Location | nearby places / junction | PASS | 6 places; junction ok |
| Voice | Sarvam TTS te / en | PASS | audio/ogg 8.3 KB te-IN / 5.4 KB en-IN, ~1-1.6 s |
| Voice | Sarvam STT round trip te / en | PASS | "నమస్కారం, మీకు ఏ సహాయం కావాలి?" exact; "Hello, how can I help you?" |
| Attachments | image (vision) | PARTIAL | processed (vision, confidence 0.95) — synthetic image, no facts expected |
| Attachments | PDF | PARTIAL | text layer read; no structured facts from the synthetic invoice |
| Errors | empty message 422, TTS too long 422, bad base64 415, unknown 404, empty audio 400 | PASS | |
| Payments | webhook with bad signature | PASS | 401 refused |
| Auth | memory/orders/leads/creations/notification settings without or with forged token | PASS | 401 |
| Auth | admin health/release gate/billing/audit/backup without key | PASS | 401 (staging + production) |
| Rate limit | admin sign-in lockout | PASS | 401 x10 then 429 |
| Backup | /admin/backup page | PASS | 200, holds no data |
| Web | /chat | PASS | 200 |

### Root causes and recommended fixes
1. **Staging Brave web search: quota exhausted (HTTP 402).** After the first
   query every online / marketplace / used / video lookup returned
   `quota_exhausted`; the breaker then pauses Brave. The app reports it
   honestly. Fix: top up the Brave plan used by staging (owner billing
   decision). **Production status is not proven** by this run (no production
   search was made): check Command Center → Integrations → Brave → Check.
   If production shares the key, live users see no online results.
2. **Google CSE fallback is DISABLED** in both environments, so there is no
   second web-search provider when Brave fails. Fix: configure
   `GOOGLE_CSE_API_KEY` + `GOOGLE_CSE_ID` (owner decision, paid).
3. **Prices on online cards are sparse (1/9)** — online rows are store /
   category pages; prices are never invented. Improvement: prefer product
   pages / affiliate catalog rows with prices (follow-up).
4. **Video search returned nothing** while Brave was exhausted; needs a retest
   after the quota is fixed before calling it a defect.
5. **Jobs probe** sent intent "buy"; the app sends the brain's intent. Retest
   through the assistant flow (phone test 3.x / 4.8).
6. **Firebase push not configured** — background notifications cannot work
   yet (known, EXTERNAL SETUP).

### Not covered live (and why)
Signed-in flows (memory CRUD, roles, orders, My Business, admin with key) need
a real session or the owner key — covered by the local suites and by the phone
checklist. Gemini -> OpenAI fallback cannot be forced live without breaking a
key; covered by unit tests. Real payments and customer notifications are
deliberately not exercised.

## C. Real-phone results (owner)
All items: **NOT TESTED** until the owner reports them (checklist:
`docs/APK_1314_PHONE_TEST_CHECKLIST.md`).
