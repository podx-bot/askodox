# ASKODOX website (askodox.com)

The official ASKODOX website. It is completely separate from the app and
backend: its own folder, its own Docker image and its own Railway service.
Nothing here is imported by the backend, and the repo-root `.dockerignore`
already excludes this folder from the backend image.

## How it works

- `config/site.json` — brand, tagline, contact emails, app store links,
  languages, social links and the **feature status list** (Live / Beta /
  Coming soon). Every status label on the site comes from here.
- `config/links.json` — the central registry for partner, affiliate and deep
  links. Pages link to `/go/<slug>`; the server redirects. A link is only
  published when `"status": "active"` **and** `"approved": true` and it has
  a `url`. Nothing is active today.
- `pages.py` — page content. `demos.py` — the illustrated example blocks
  (result cards, no-match, videos, deals, consent). Every example block
  carries a visible **Example** marker; product pictures are SVG
  illustrations, never photos of real items. `build.py` — layout, SEO
  (titles, descriptions, canonical, Open Graph, JSON-LD, sitemap, robots),
  assets.
- `locales/*.json` + `i18n.py` — interface and home-page text per language.
  One set of pages is rendered once per published locale (`/te/...`), with
  missing keys falling back to English, so a translation can be partial.
  English is the only published locale today; Telugu (`te.json`) is ready
  for the navigation, footer and home-page headlines.
- `static/css/tokens.css` — design tokens, identical to the app's
  `lib/config/theme/askodox_design_tokens.dart`. Published as `/tokens.json`
  for other surfaces (admin, seller tools, social templates).
- `<askodox-companion>` in `static/js/site.js` — the AI companion slot. It
  draws the brand orb today; a future voice / animated / 3D companion
  registers a renderer on `window.ASKODOX.companionRenderers` and pages
  don't change.
- `server/` — Caddy config and entrypoint. At container start, `build.py`
  regenerates the site from config + environment, so changing a Railway
  variable and restarting the service updates the website.

## Settings (Railway variables on the `askodox-website` service)

| Variable | What it changes |
| --- | --- |
| `ASKODOX_SITE_URL` | Canonical URL (default `https://askodox.com`) |
| `ASKODOX_SITE_NOINDEX` | `true` hides the site from search engines (use for staging) |
| `ASKODOX_SITE_TAGLINE` | The tagline everywhere |
| `ASKODOX_SITE_CONTACT_EMAIL`, `_SUPPORT_EMAIL`, `_PARTNERS_EMAIL`, `_PRIVACY_EMAIL` | Contact addresses (default admin@askodox.com) |
| `ASKODOX_SITE_WHATSAPP` | Official WhatsApp number in international format; turns WhatsApp support to Live |
| `ASKODOX_SITE_PLAY_STORE_URL` / `ASKODOX_SITE_APP_STORE_URL` | Store buttons become real links and the app turns Live |
| `ASKODOX_SITE_WEB_APP_URL` | The hero ask box sends questions there (`?q=`) instead of showing the preview |
| `ASKODOX_SITE_FORMS_ENDPOINT` | HTTPS endpoint that receives form JSON (see below); otherwise forms open the visitor's email app and say so |
| `ASKODOX_SITE_LEGAL_NAME`, `_LEGAL_ADDRESS`, `_LEGAL_COMPANY_NUMBER`, `_LEGAL_JURISDICTION` | Verified legal details. Until set, policies show a clearly marked placeholder |
| `ASKODOX_SITE_LOCALES` | Published languages, e.g. `en,te` |
| `ASKODOX_SITE_SOCIAL_JSON` | e.g. `{"youtube":"https://youtube.com/@askodox"}` |
| `ASKODOX_SITE_FEATURES_JSON` | Override statuses, e.g. `{"partner_deals":"live"}` |
| `ASKODOX_SITE_LINKS_JSON` | Replace the partner/affiliate link registry |

## Form endpoint contract

When `ASKODOX_SITE_FORMS_ENDPOINT` is set, every form POSTs JSON:

```
{ "form": "join" | "refer" | "contact" | "report",
  "subject": "...", "fields": { ... }, "page": "/join/", "locale": "en" }
```

Only a 2xx reply is shown as "Received". Any other reply or a 15 s timeout
keeps the visitor's input and offers email instead. The endpoint must allow
CORS from https://askodox.com. Its origin is added to the site's CSP
automatically. Forms include a hidden honeypot field (`website`) that the
browser never sends; the endpoint should still rate-limit.

## Tests

```
cd website
python3 -m unittest discover -s tests -v
```

Checks every route builds with SEO tags and one h1, internal links resolve,
no partner link, store URL, phone or WhatsApp number is published unless
configured, example blocks are marked, legal placeholders show until set,
forms are honest without an endpoint, and the Telugu build works.

## Local preview

```
cd website
python3 build.py --out dist
python3 -m http.server -d dist 8080
```

`tools/render_images.py` regenerates the PNG icons and social image
(needs Playwright; only when the logo changes).

## Rules

- Never mark a feature Live, or a partner/affiliate programme active,
  before it is really live or approved.
- No invented numbers, reviews, testimonials, businesses or partners.
  Examples on the home page are labelled as sample data.
