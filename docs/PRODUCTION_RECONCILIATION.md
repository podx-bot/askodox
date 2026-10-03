# Production reconciliation (2026-10-03)

One consolidated pass over everything merged since `c2ae7d4` (PR #112 → #130),
the long-running Command Center branch (`claude/friendly-ramanujan-538sbj`),
PR #110 (companions) and PR #111 (website). Facts below were read from git and
from the Railway project itself (service config, domains, variable *names* --
no value was read).

## Where each surface really comes from

| Surface | Railway project / env | Service | Deploys branch | Notes |
|---|---|---|---|---|
| Mobile release APK backend | lavish-perfection / **production** | podx-ai-connect | `main` | `podx-ai-connect-production-3279.up.railway.app` (no custom domain). Volume `/data`. |
| `staging.askodox.com` (incl. `/admin/console`, phone-test APKs) | lavish-perfection / **staging** | podx-ai-connect | `claude/friendly-ramanujan-538sbj` | A real, separate environment with its **own variables and its own volume instance**. |
| `askodox.com`, `www.askodox.com` | lavish-perfection / production | askodox-website | `claude/askodox-website` (PR #111 head) | Root `/website`, Dockerfile, watch `/website/**`, healthcheck `/health`. |

So the word "staging" is accurate: `staging.askodox.com` is the Railway
*staging* environment, not production.

## YouTube "NEEDS_CONFIGURATION · Missing: api_key" -- root cause

1. The New Admin Console (`/admin/console`, `admin_console.py`) and its
   integration registry (`commerce_finance.IntegrationRegistry`) exist only on
   the Command Center branch, which only the **staging** environment runs.
   Production (`main`) never had that console; #129/#130 fixed the *classic*
   Command Center list (`command_center._integration_states`) on `main`.
2. The registry mapped YouTube to `YOUTUBE_API_KEY` only (no
   `YOUTUBE_DATA_API_KEY` alias), and the staging deployment predates
   #129/#130.
3. The staging environment's variables do **not** include `YOUTUBE_API_KEY`
   or `YOUTUBE_DATA_API_KEY` (production has both). Railway variables are
   per environment, so the production key is invisible to staging.

Fix in this PR: one resolution helper (`commerce_finance.youtube_api_key` /
`env_value`) used by the registry, the classic Command Center state, the
platform video search and `SocialVideoApiService`; either name works, and when
both are set the well-formed one wins. The console now prints which
environment / service / branch / commit it is reading. After merge, the
console runs on production (`main`), where the key exists → `CONFIGURED`, and
`LIVE` only after **Check** passes against the real API.

Staging will keep (correctly) showing NOT_CONFIGURED until the staging
environment gets its own variable -- an Owner decision, see below.

## Integration readiness vocabulary (one source)

`/admin/cc/platform/integrations` (registry) now returns `readiness`:
`NOT_CONFIGURED` (required value missing) · `DISABLED` (configured, switched
off) · `CONFIGURED` (enabled, no passed check yet) · `CHECK_FAILED` (last real
check failed) · `OK` (check passed, test mode / built-in) · `LIVE` (live mode +
passed check). Secret values are never returned; tests assert the key text is
absent from responses.

The classic `/admin/web` Integrations list (`_integration_states`) is still a
second list for non-registry services (Brave, Maps, Sarvam, OpenAI…); its
YouTube row now uses the same key resolution.

## PR #112 → #130 matrix

| PR | What | State after this PR |
|---|---|---|
| #112 | Website upgrade | Merged into `claude/askodox-website`, live on askodox.com. Now also in `main` via #111 merge. |
| #113–#114, #120–#122 | Affiliate provider config + admin UI | Wired: classic admin "Affiliate Partners" tab (`/admin/cc/integrations/affiliate-providers`). |
| #115–#116, #118 | External gateway, deep link → web fallback | Wired: app opens `deep_link`, falls back to `web_fallback_url` (merged with the Partner Hub `/go/` path). |
| #117, #123 | Click / conversion tracking | Wired: app → `POST /deals/external/click` (now rate-limited). |
| #119 | Partner API connector | Backend only; no partner API is configured. |
| #124 | Signed conversion callbacks | Built; needs `ASKODOX_PARTNER_<ID>_CALLBACK_SECRET` per partner (none set). |
| #125–#126 | Hardening + master register doc | Docs + code merged. |
| #127 | Partner & Revenue Hub (curated catalog, BFSI, staff) | Catalog rows join discovery as disclosed affiliate rows; admin tab wired. Commission does not affect ranking. |
| #128 | Social video, ads, offers, scratch rewards | Admin APIs + tabs wired. **Fixed:** table collision, scratch INSERT bug. Its campaigns/offers/scratch rows are *not* served to customers (admin data stores only). |
| #129–#130 | YouTube key alias + classic readiness | On production; now unified with the canonical registry. |

## Overlaps kept on purpose (documented, not deleted)

No working feature was removed. Canonical choice per area:

- Sponsored placements: **`sponsored_repository.py`** (labelled, served after
  organic, approval + budget). #128 `social_sponsored_campaigns` = admin-only.
- Offers / scratch rewards served to customers: **`benefits_engine.py`**
  (verified-only external offers, server-decided scratch once per completed
  order). #128 `partner_offers` / `scratch_rewards` = admin-only.
- Partner links: Partner Hub (`partners`, encrypted secrets, signed `/go/`
  clicks) + #113 affiliate provider config + #127 curated catalog all feed
  discovery; clicks are counted in `revenue_events` (Partner Hub rows) and
  `external_commerce_events` (#117) respectively.
- Admin UIs: New Admin Console `/admin/console` (canonical) and classic
  `/admin/web` (kept; holds #113–#128 tabs not yet ported).

## PR #110 / #111

- **#110** (human companions): its head `101a1cc` is an ancestor of this
  branch -- every one of its 30 commits is already included and was built on
  (later fixes to the companion, attachments, sponsored, Partner Hub). Nothing
  to port; this PR supersedes it. Close #110 after this merges.
- **#111** (website): touches only `website/` (32 files, includes #112). Merged
  here so `main` is the source of truth; its own tests pass (11). Nothing in
  the backend imports it. After merge, switch the askodox-website service's
  source branch to `main` (keep root `/website`, watch `/website/**`), then
  close #111. Until switched, askodox.com keeps serving the identical branch.

## Owner-only configuration (not doable from code)

1. Optional: add a YouTube key to the **staging** environment (Railway →
   lavish-perfection → staging → podx-ai-connect → Variables) if staging should
   show YouTube as configured. The value is the Owner's choice; nothing is
   copied by code.
2. askodox-website service: source branch `claude/askodox-website` → `main`
   after merge.
3. Production has no `SESSION_TOKEN_SECRET`; tokens are signed with a value
   derived from `ADMIN_SEED_KEY` (secure, works). Setting a dedicated
   `SESSION_TOKEN_SECRET` would sign out every user once -- schedule it.
4. Unconfigured (code ready, honestly NOT_CONFIGURED): Instagram/Facebook
   Graph (`META_GRAPH_ACCESS_TOKEN`), Firebase push, SMTP, SMS, payment
   gateways, affiliate networks, partner callback secrets,
   `ASKODOX_SECRETS_KEY` (Partner Hub secret storage fails closed without it).

## Post-merge production verification

1. Railway production deployment for the merge commit is SUCCESS.
2. `https://podx-ai-connect-production-3279.up.railway.app/admin/console` →
   sign in → Integrations: banner says `production · branch main`; YouTube
   shows Configured (no "Missing"); press **Check** → LIVE/OK on success.
3. `/admin/web` → Integrations: YouTube Data API configured.
4. A chat search still returns local + online results; a partner card opens.
5. Volume data intact (users, listings, orders counts unchanged on the
   dashboard before/after).
