#!/usr/bin/env python3
"""ASKODOX website builder.

Pure standard-library Python. Reads config/site.json and config/links.json,
applies ASKODOX_SITE_* environment overrides, and writes a complete static
site (HTML, CSS, JS, sitemap.xml, robots.txt, manifest, tokens.json) plus a
Caddy redirect snippet for /go/<slug> partner links.

Runs at container start (so Railway variables take effect on restart) and
locally:  python3 build.py --out dist
"""
from __future__ import annotations

import argparse
import base64
import copy
import datetime as _dt
import hashlib
import html
import json
import os
import re
import shutil
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ENV_MAP = {
    "ASKODOX_SITE_URL": ("site", "url"),
    "ASKODOX_SITE_NOINDEX": ("site", "noindex"),
    "ASKODOX_SITE_LEGAL_NAME": ("site", "legal_name"),
    "ASKODOX_SITE_LEGAL_ADDRESS": ("site", "legal_address"),
    "ASKODOX_SITE_TAGLINE": ("brand", "tagline"),
    "ASKODOX_SITE_ASK_PROMPT": ("brand", "ask_prompt"),
    "ASKODOX_SITE_CONTACT_EMAIL": ("contact", "general_email"),
    "ASKODOX_SITE_SUPPORT_EMAIL": ("contact", "support_email"),
    "ASKODOX_SITE_PARTNERS_EMAIL": ("contact", "partners_email"),
    "ASKODOX_SITE_PRIVACY_EMAIL": ("contact", "privacy_email"),
    "ASKODOX_SITE_WHATSAPP": ("contact", "whatsapp_number"),
    "ASKODOX_SITE_FORMS_ENDPOINT": ("contact", "forms_endpoint"),
    "ASKODOX_SITE_PLAY_STORE_URL": ("app", "play_store_url"),
    "ASKODOX_SITE_APP_STORE_URL": ("app", "app_store_url"),
    "ASKODOX_SITE_WEB_APP_URL": ("app", "web_app_url"),
}


def _truthy(v: str) -> bool:
    return str(v).strip().lower() in {"1", "true", "yes", "on"}


def load_config(env: dict[str, str]) -> dict:
    cfg = json.loads((ROOT / "config" / "site.json").read_text(encoding="utf-8"))
    for key, (section, field) in ENV_MAP.items():
        if key in env and env[key].strip() != "":
            val: object = env[key].strip()
            if field == "noindex":
                val = _truthy(str(val))
            cfg[section][field] = val
    if env.get("ASKODOX_SITE_SOCIAL_JSON"):
        overrides = json.loads(env["ASKODOX_SITE_SOCIAL_JSON"])  # {"youtube": "https://..."}
        for s in cfg["social"]:
            if s["id"] in overrides:
                s["url"] = overrides[s["id"]]
    if env.get("ASKODOX_SITE_FEATURES_JSON"):
        overrides = json.loads(env["ASKODOX_SITE_FEATURES_JSON"])  # {"whatsapp_support": "live"}
        for f in cfg["features"]:
            if f["id"] in overrides:
                f["status"] = overrides[f["id"]]
    links = json.loads((ROOT / "config" / "links.json").read_text(encoding="utf-8"))["links"]
    if env.get("ASKODOX_SITE_LINKS_JSON"):
        links = json.loads(env["ASKODOX_SITE_LINKS_JSON"])
    cfg["links"] = links

    # Derived feature states that depend on configured values.
    feats = {f["id"]: f for f in cfg["features"]}
    wa = re.sub(r"\D", "", cfg["contact"].get("whatsapp_number") or "")
    cfg["contact"]["whatsapp_digits"] = wa
    if wa:
        feats["whatsapp_support"]["status"] = "live"
        feats["whatsapp_support"]["note"] = "Message us on WhatsApp."
    if cfg["app"].get("play_store_url"):
        feats["android_app"]["status"] = "live"
        feats["android_app"]["note"] = "Available on Google Play."
    if cfg["app"].get("app_store_url"):
        feats["ios_app"]["status"] = "live"
        feats["ios_app"]["note"] = "Available on the App Store."
    if cfg["app"].get("web_app_url"):
        feats["web_chat"]["status"] = "live"
        feats["web_chat"]["note"] = "Ask from any browser."
    cfg["feature"] = feats
    cfg["site"]["url"] = cfg["site"]["url"].rstrip("/")
    return cfg


def active_links(cfg: dict) -> list[dict]:
    return [l for l in cfg["links"] if l.get("status") == "active" and l.get("approved") and l.get("url")]


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def e(s: object) -> str:
    return html.escape(str(s), quote=True)


STATUS_LABEL = {"live": "Live", "beta": "Beta", "soon": "Coming soon"}


def badge(status: str) -> str:
    return f'<span class="status status-{e(status)}">{STATUS_LABEL.get(status, status)}</span>'


def fbadge(cfg: dict, fid: str) -> str:
    return badge(cfg["feature"][fid]["status"])


ICONS = {
    "spark": '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
    "bag": '<path d="M5 8h14l-1 12H6z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
    "tools": '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.6 2.6-2.4-.6-.6-2.4z"/>',
    "pin": '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>',
    "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 2.5 15.3 0 18M12 3c-2.5 2.7-2.5 15.3 0 18"/>',
    "tag": '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.5"/>',
    "play": '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 9l5 3-5 3z"/>',
    "store": '<path d="M4 9l1.5-5h13L20 9"/><path d="M4 9h16v2a3 3 0 0 1-5.3 2 3 3 0 0 1-5.4 0A3 3 0 0 1 4 11z"/><path d="M5 13v7h14v-7"/>',
    "mic": '<rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
    "camera": '<rect x="3" y="6" width="18" height="14" rx="3"/><circle cx="12" cy="13" r="3.5"/><path d="M9 6l1.5-2h3L15 6"/>',
    "file": '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    "type": '<path d="M4 6h16M4 12h10M4 18h7"/>',
    "send": '<path d="M5 12h13M13 6l6 6-6 6"/>',
    "mail": '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 7l9 6 9-6"/>',
    "chat": '<path d="M4 5h16v11H9l-5 4z"/>',
    "help": '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.5V14"/><path d="M12 17.5v.01"/>',
    "flag": '<path d="M5 21V4h11l-2 4 2 4H5"/>',
    "menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "close": '<path d="M6 6l12 12M18 6L6 18"/>',
    "android": '<path d="M6 10h12v7a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2z"/><path d="M6 10a6 6 0 0 1 12 0M9 7.5v.01M15 7.5v.01M8 4l1.5 2M16 4l-1.5 2"/>',
    "apple": '<path d="M16 3c-1.5.2-3 1.4-3 3 1.6 0 3-1.3 3-3z"/><path d="M12 8c-1 0-2-.6-3-.6C6.8 7.4 5 9.3 5 12.4 5 16 7.4 21 9.3 21c1 0 1.5-.6 2.7-.6s1.6.6 2.7.6c1.4 0 2.8-2.4 3.3-4-1.6-.7-2.6-2-2.6-3.8 0-1.5.8-2.8 2-3.5-.8-1.2-2.1-1.7-3.3-1.7-1 0-2 .6-2.4.6z"/>',
    "shield": '<path d="M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
}


def icon(name: str, cls: str = "") -> str:
    c = f' class="{cls}"' if cls else ""
    return f'<svg{c} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>'


MARK_SVG = (
    '<svg class="brand-mark" viewBox="0 0 64 64" aria-hidden="true">'
    '<defs><linearGradient id="axg" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#B48CFF"/><stop offset=".55" stop-color="#603EFF"/><stop offset="1" stop-color="#2F7BFF"/>'
    '</linearGradient></defs>'
    '<circle cx="32" cy="32" r="22" fill="none" stroke="url(#axg)" stroke-width="9"/>'
    '<circle cx="47.5" cy="16.5" r="7" fill="#39C8FF"/>'
    '</svg>'
)

FAVICON_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<rect width="64" height="64" rx="14" fill="#070816"/>'
    '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#B48CFF"/><stop offset=".55" stop-color="#603EFF"/><stop offset="1" stop-color="#2F7BFF"/>'
    '</linearGradient></defs>'
    '<circle cx="31" cy="34" r="17" fill="none" stroke="url(#g)" stroke-width="8"/>'
    '<circle cx="44" cy="20" r="6" fill="#39C8FF"/></svg>'
)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

NAV = [
    ("/discover/", "Discover"),
    ("/how-it-works/", "How it works"),
    ("/sellers/", "Sellers"),
    ("/service-providers/", "Providers"),
    ("/deals/", "Deals"),
    ("/videos/", "Videos"),
    ("/support/", "Help"),
]

FOOTER = [
    ("Explore", [("/discover/", "Discover"), ("/how-it-works/", "How it works"), ("/deals/", "Deals and offers"), ("/videos/", "Videos and reviews"), ("/app/", "The app")]),
    ("Join", [("/join/", "Join ASKODOX"), ("/sellers/", "For sellers"), ("/service-providers/", "For service providers"), ("/videos/#creators", "For creators"), ("/partners/", "Partners"), ("/join/#refer", "Refer a business")]),
    ("Help", [("/support/", "Help center"), ("/faq/", "FAQ"), ("/contact/", "Contact us"), ("/report-a-problem/", "Report a problem"), ("/status/", "What's live")]),
    ("Company", [("/about/", "About ASKODOX"), ("/trust/", "Trust and safety"), ("/privacy/", "Privacy policy"), ("/terms/", "Terms and conditions"), ("/cookies/", "Cookie policy"), ("/affiliate-disclosure/", "Affiliate disclosure"), ("/accessibility/", "Accessibility")]),
]


class Page:
    def __init__(self, path: str, title: str, description: str, body: str, *, crumb: str | None = None,
                 jsonld: list | None = None, priority: str = "0.7", in_sitemap: bool = True, head_extra: str = ""):
        self.path = path
        self.title = title
        self.description = description
        self.body = body
        self.crumb = crumb
        self.jsonld = jsonld or []
        self.priority = priority
        self.in_sitemap = in_sitemap
        self.head_extra = head_extra


def render_page(cfg: dict, page: Page, assets: dict, locale: dict) -> str:
    site = cfg["site"]
    brand = cfg["brand"]
    url = site["url"] + page.path
    is_home = page.path == "/"
    full_title = f'{brand["name"]}: {brand["tagline"]}' if is_home else f'{page.title} | {brand["name"]}'
    robots = "noindex, nofollow" if site.get("noindex") or not page.in_sitemap else "index, follow, max-image-preview:large"
    og_image = site["url"] + assets["og"]

    org = {
        "@context": "https://schema.org",
        "@type": "Organization",
        "@id": site["url"] + "/#organization",
        "name": brand["name"],
        "url": site["url"] + "/",
        "logo": site["url"] + assets["logo"],
        "slogan": brand["tagline"],
        "email": cfg["contact"]["general_email"],
        "contactPoint": [{"@type": "ContactPoint", "contactType": "customer support", "email": cfg["contact"]["support_email"], "availableLanguage": ["English"]}],
    }
    same_as = [s["url"] for s in cfg["social"] if s.get("url")]
    if same_as:
        org["sameAs"] = same_as
    blocks = [org]
    if is_home:
        blocks.append({"@context": "https://schema.org", "@type": "WebSite", "@id": site["url"] + "/#website", "url": site["url"] + "/", "name": brand["name"], "publisher": {"@id": site["url"] + "/#organization"}, "inLanguage": locale["code"]})
    else:
        blocks.append({"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Home", "item": site["url"] + "/"},
            {"@type": "ListItem", "position": 2, "name": page.crumb or page.title, "item": url},
        ]})
    blocks.extend(page.jsonld)
    ld = "\n".join(f'<script type="application/ld+json">{json.dumps(b, ensure_ascii=False)}</script>' for b in blocks)

    published = [l for l in cfg["locales"] if l.get("published")]
    hreflang = "".join(f'<link rel="alternate" hreflang="{e(l["code"])}" href="{e(site["url"] + ("" if l["code"] == site["default_locale"] else "/" + l["code"]) + page.path)}">' for l in published)
    hreflang += f'<link rel="alternate" hreflang="x-default" href="{e(url)}">'

    client_cfg = {
        "askPrompt": brand["ask_prompt"],
        "webAppUrl": cfg["app"].get("web_app_url") or "",
        "supportEmail": cfg["contact"]["support_email"],
        "formsEndpoint": cfg["contact"].get("forms_endpoint") or "",
        "locale": locale["code"],
    }

    current = ' aria-current="page"'
    nav = "".join(
        f'<li><a href="{p}"{current if page.path == p else ""}>{e(t)}</a></li>' for p, t in NAV
    )
    mobile_nav = "".join(f'<a href="{p}">{e(t)}</a>' for p, t in NAV)
    mobile_sub = "".join(f'<a href="{p}">{e(t)}</a>' for p, t in [("/about/", "About"), ("/join/", "Join"), ("/contact/", "Contact"), ("/app/", "App"), ("/partners/", "Partners"), ("/status/", "What's live")])

    crumbs = ""
    footer_cols = "".join(
        f'<div><h2>{e(h)}</h2><ul>' + "".join(f'<li><a href="{p}">{e(t)}</a></li>' for p, t in items) + "</ul></div>"
        for h, items in FOOTER
    )
    lang_opts = "".join(
        f'<option value="{e(l["code"])}"' + (" selected" if l["code"] == locale["code"] else "") + ("" if l.get("published") else " disabled")
        + (f' data-href="{e(("" if l["code"] == site["default_locale"] else "/" + l["code"]) + page.path)}"' if l.get("published") else "")
        + f'>{e(l["native"])}{"" if l.get("published") else " (coming soon)"}</option>'
        for l in cfg["locales"]
    )
    socials = "".join(f'<li><a href="{e(s["url"])}" rel="me noopener" target="_blank">{e(s["label"])}</a></li>' for s in cfg["social"] if s.get("url"))
    social_html = f'<ul class="legend" aria-label="ASKODOX on social media">{socials}</ul>' if socials else ""
    legal = e(site.get("legal_name") or brand["name"])
    year = _dt.date.today().year
    years = f'{site["launch_year"]}' if year <= int(site["launch_year"]) else f'{site["launch_year"]}–{year}'

    return f"""<!doctype html>
<html lang="{e(locale['code'])}" dir="{e(locale.get('dir', 'ltr'))}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{e(full_title)}</title>
<meta name="description" content="{e(page.description)}">
<meta name="robots" content="{robots}">
<link rel="canonical" href="{e(url)}">
{hreflang}
<meta name="theme-color" content="{e(site['theme_color'])}">
<meta name="color-scheme" content="dark light">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{e(brand['name'])}">
<meta property="og:title" content="{e(full_title)}">
<meta property="og:description" content="{e(page.description)}">
<meta property="og:url" content="{e(url)}">
<meta property="og:image" content="{e(og_image)}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="ASKODOX: {e(brand['tagline'])}">
<meta property="og:locale" content="en_US">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{e(full_title)}">
<meta name="twitter:description" content="{e(page.description)}">
<meta name="twitter:image" content="{e(og_image)}">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon-32.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="preload" href="/static/fonts/bricolage-grotesque-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/static/fonts/atkinson-hyperlegible-next-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{assets['css']}">
<script>document.documentElement.classList.add("js")</script>
{page.head_extra}
{ld}
</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>
<header class="site-header">
  <div class="wrap header-inner">
    <a class="brand" href="/" aria-label="{e(brand['name'])} home">{MARK_SVG}<span>{e(brand['name'])}</span></a>
    <nav class="main-nav" aria-label="Main"><ul>{nav}</ul></nav>
    <a class="btn btn-primary header-cta" href="/join/">Get early access</a>
    <button class="menu-toggle" id="menu-open" type="button" aria-expanded="false" aria-controls="mobile-menu">{icon('menu')}<span>Menu</span></button>
  </div>
</header>
<div class="mobile-menu" id="mobile-menu" aria-hidden="true" role="dialog" aria-modal="true" aria-label="Menu">
  <div class="mobile-menu-top">
    <a class="brand" href="/">{MARK_SVG}<span>{e(brand['name'])}</span></a>
    <button class="menu-toggle" id="menu-close" type="button" style="display:inline-flex">{icon('close')}<span>Close</span></button>
  </div>
  <nav aria-label="Mobile">{mobile_nav}</nav>
  <div class="sub">{mobile_sub}</div>
  <a class="btn btn-primary" href="/join/">Get early access</a>
</div>
<main id="main">
{crumbs}{page.body}
</main>
<footer class="site-footer">
  <div class="wrap">
    <div class="footer-top">
      <div class="footer-brand">
        <a class="brand" href="/">{MARK_SVG}<span>{e(brand['name'])}</span></a>
        <p>{e(brand['tagline'])} One place to ask, discover, decide and connect, wherever you are.</p>
        <p><a href="mailto:{e(cfg['contact']['general_email'])}">{e(cfg['contact']['general_email'])}</a></p>
      </div>
      {footer_cols}
    </div>
    <div class="footer-bottom">
      <p>© {years} {legal}. All rights reserved.</p>
      <div class="legend" aria-label="Feature status labels">{badge('live')}{badge('beta')}{badge('soon')}<a href="/status/">What these mean</a></div>
      {social_html}
      <label class="lang"><span>Language</span><select id="lang-select" aria-label="Choose language">{lang_opts}</select></label>
    </div>
  </div>
</footer>
<script id="ax-config" type="application/json">{json.dumps(client_cfg)}</script>
<script src="{assets['js']}" defer></script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def _hashed(src: str, name: str, ext: str) -> tuple[str, str]:
    h = hashlib.sha256(src.encode("utf-8")).hexdigest()[:10]
    return f"/static/{ext}/{name}.{h}.{ext}", h


def build(out: Path, env: dict[str, str], redirects_path: Path | None = None) -> dict:
    from pages import all_pages  # local module

    cfg = load_config(env)
    if out.exists():
        shutil.rmtree(out)
    (out / "static").mkdir(parents=True)

    # Static files (fonts, images) copied as-is.
    for sub in ("fonts", "img"):
        src = ROOT / "static" / sub
        if src.exists():
            shutil.copytree(src, out / "static" / sub)

    css = (ROOT / "static" / "css" / "tokens.css").read_text(encoding="utf-8") + "\n" + \
        (ROOT / "static" / "css" / "site.css").read_text(encoding="utf-8").replace('@import url("/static/css/tokens.css");', "")
    js = (ROOT / "static" / "js" / "site.js").read_text(encoding="utf-8")
    css_path, _ = _hashed(css, "askodox", "css")
    js_path, _ = _hashed(js, "askodox", "js")
    for p, content in ((css_path, css), (js_path, js)):
        f = out / p.lstrip("/")
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(content, encoding="utf-8")

    assets = {"css": css_path, "js": js_path, "og": "/static/img/og-askodox.png", "logo": "/static/img/askodox-logo-512.png"}
    (out / "favicon.svg").write_text(FAVICON_SVG, encoding="utf-8")
    for name in ("favicon-32.png", "apple-touch-icon.png", "icon-192.png", "icon-512.png"):
        src = ROOT / "static" / "img" / name
        if src.exists():
            shutil.copy(src, out / name)

    locale = next(l for l in cfg["locales"] if l["code"] == cfg["site"]["default_locale"])
    pages = all_pages(cfg)
    for page in pages:
        html_out = render_page(cfg, page, assets, locale)
        target = out / ("404.html" if page.path == "/404/" else page.path.strip("/") + "/index.html" if page.path != "/" else "index.html")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html_out, encoding="utf-8")

    site = cfg["site"]
    today = _dt.date.today().isoformat()
    urls = "".join(
        f"<url><loc>{e(site['url'] + p.path)}</loc><lastmod>{today}</lastmod><priority>{p.priority}</priority></url>"
        for p in pages if p.in_sitemap
    )
    (out / "sitemap.xml").write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n', encoding="utf-8")
    if site.get("noindex"):
        robots = "User-agent: *\nDisallow: /\n"
    else:
        robots = f"User-agent: *\nAllow: /\nDisallow: /go/\n\nSitemap: {site['url']}/sitemap.xml\n"
    (out / "robots.txt").write_text(robots, encoding="utf-8")

    manifest = {
        "name": cfg["brand"]["name"], "short_name": cfg["brand"]["name"], "description": cfg["brand"]["promise"],
        "start_url": "/", "display": "standalone", "background_color": "#070816", "theme_color": "#070816",
        "icons": [{"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"}, {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"}, {"src": "/favicon.svg", "sizes": "any", "type": "image/svg+xml"}],
    }
    (out / "site.webmanifest").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    tokens = {}
    for m in re.finditer(r"--(ax-[\w-]+):\s*([^;]+);", (ROOT / "static" / "css" / "tokens.css").read_text(encoding="utf-8")):
        tokens[m.group(1)] = m.group(2).strip()
    (out / "tokens.json").write_text(json.dumps({"name": "ASKODOX design tokens", "source": "website/static/css/tokens.css (mirrors lib/config/theme/askodox_design_tokens.dart)", "tokens": tokens}, indent=2), encoding="utf-8")

    (out / ".well-known").mkdir(exist_ok=True)
    (out / ".well-known" / "security.txt").write_text(
        f"Contact: mailto:{cfg['contact']['general_email']}\nExpires: {(_dt.date.today() + _dt.timedelta(days=365)).isoformat()}T00:00:00.000Z\nPreferred-Languages: en\nCanonical: {site['url']}/.well-known/security.txt\n",
        encoding="utf-8")

    # Server directives generated from config: security headers (CSP with the
    # hash of the one inline script) and /go/<slug> partner redirects — only
    # approved, active links are ever published.
    inline = 'document.documentElement.classList.add("js")'
    sha = base64.b64encode(hashlib.sha256(inline.encode()).digest()).decode()
    connect = "'self'"
    endpoint = cfg["contact"].get("forms_endpoint") or ""
    m = re.match(r"(https://[^/]+)", endpoint)
    if m:
        connect += " " + m.group(1)
    csp = ("default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
           f"script-src 'self' 'sha256-{sha}'; font-src 'self'; connect-src {connect}; "
           "object-src 'none'; base-uri 'self'; form-action 'self' mailto:; frame-ancestors 'none'; upgrade-insecure-requests")
    lines = ["# Generated by build.py at container start. Do not edit.", f'header Content-Security-Policy "{csp}"']
    for link in active_links(cfg):
        slug = re.sub(r"[^a-z0-9-]", "", link["slug"].lower())
        lines.append(f"redir /go/{slug} {link['url']} 302")
    lines.append("redir /go/* /deals/ 302")
    if redirects_path:
        redirects_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return {"pages": len(pages), "css": css_path, "js": js_path, "active_links": len(active_links(cfg))}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "dist"))
    ap.add_argument("--redirects", default="")
    args = ap.parse_args()
    import sys
    sys.path.insert(0, str(ROOT))
    result = build(Path(args.out), dict(os.environ), Path(args.redirects) if args.redirects else None)
    print(json.dumps(result))
