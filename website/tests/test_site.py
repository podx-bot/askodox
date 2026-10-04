"""Website build checks (standard library only).

    cd website && python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import build  # noqa: E402

ROUTES = ["", "about", "how-it-works", "discover", "sellers", "service-providers", "deals", "videos", "app", "join",
          "partners", "support", "faq", "contact", "report-a-problem", "trust", "status", "privacy", "terms", "cookies",
          "affiliate-disclosure", "accessibility"]


class _Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs, self.h1 = [], 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "a" and a.get("href"):
            self.hrefs.append(a["href"])
        if tag == "h1":
            self.h1 += 1


def _build(env: dict | None = None) -> tuple[Path, Path, dict]:
    tmp = Path(tempfile.mkdtemp())
    out, red = tmp / "site", tmp / "gen.caddy"
    info = build.build(out, env or {}, red)
    return out, red, info


class SiteBuild(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out, cls.red, cls.info = _build()

    def page(self, route: str) -> str:
        return (self.out / route / "index.html").read_text(encoding="utf-8") if route else (self.out / "index.html").read_text(encoding="utf-8")

    def test_every_route_built_with_seo(self):
        for r in ROUTES:
            html = self.page(r)
            self.assertIn('<link rel="canonical" href="https://askodox.com/', html, r)
            self.assertIn('property="og:image"', html, r)
            self.assertRegex(html, r'<meta name="description" content="[^"]{40,}"', r)
            p = _Links(); p.feed(html)
            self.assertEqual(p.h1, 1, f"{r} should have exactly one h1")
        self.assertTrue((self.out / "404.html").exists())
        sm = (self.out / "sitemap.xml").read_text()
        self.assertEqual(sm.count("<url>"), len(ROUTES))

    def test_internal_links_resolve(self):
        for r in ROUTES:
            p = _Links(); p.feed(self.page(r))
            for h in p.hrefs:
                if not h.startswith("/") or h.startswith("/go/") or h.split("?")[0] in build.PROXIED_PATHS:
                    continue
                path = h.split("#")[0].split("?")[0]
                target = self.out / path.strip("/") / "index.html" if not Path(path).suffix else self.out / path.lstrip("/")
                self.assertTrue(target.exists(), f"{r}: broken link {h}")

    def test_no_partner_link_or_store_url_published_by_default(self):
        self.assertEqual(self.info["active_links"], 0)
        red = self.red.read_text()
        self.assertNotIn("amazon", red.lower())
        for r in ROUTES:
            html = self.page(r)
            self.assertNotIn("play.google.com", html)
            self.assertNotIn("apps.apple.com", html)
            self.assertNotIn('href="tel:', html)
            self.assertNotIn("wa.me/", html, "WhatsApp must only appear when configured")

    def test_demo_content_is_marked(self):
        home = self.page("")
        for block in ("results-demo", "video-demo", "deals-demo", "nomatch"):
            start = home.index(f'class="{block}"')
            chunk = home[start:start + 60000]
            self.assertIn("t-example", chunk, f"{block} must carry an Example marker")
        self.assertIn("Price unverified", home)
        self.assertIn("Affiliate link", home)

    def test_phone_numbers_hidden_before_acceptance(self):
        home = self.page("")
        self.assertIn("Number hidden", home)
        self.assertIsNone(re.search(r"\+\d{2}\s?\d{5}\s?\d{5}", home))

    def test_legal_placeholders_until_configured(self):
        for r in ("privacy", "terms"):
            self.assertIn('class="placeholder"', self.page(r))

    def test_forms_are_honest_without_endpoint(self):
        join = self.page("join")
        self.assertIn("Continue in your email app", join)
        self.assertIn("Nothing is sent until you press send", join)


class Configured(unittest.TestCase):
    def test_env_overrides(self):
        out, red, info = _build({
            "ASKODOX_SITE_WHATSAPP": "+91 90000 00000",
            "ASKODOX_SITE_PLAY_STORE_URL": "https://play.google.com/store/apps/details?id=com.askodox.app",
            "ASKODOX_SITE_FORMS_ENDPOINT": "https://forms.example.com/hook",
            "ASKODOX_SITE_LEGAL_NAME": "Example Ltd",
            "ASKODOX_SITE_LINKS_JSON": json.dumps([{"slug": "shop", "partner": "Shop", "programme": "Shop Affiliates", "url": "https://shop.example/?tag=x", "status": "active", "approved": True, "affiliate": True}]),
        })
        support = (out / "support" / "index.html").read_text()
        self.assertIn("https://wa.me/919000000000", support)
        self.assertIn("play.google.com", (out / "index.html").read_text())
        self.assertIn("Request early access", (out / "join" / "index.html").read_text())
        self.assertIn("Example Ltd", (out / "terms" / "index.html").read_text())
        self.assertIn("redir /go/shop https://shop.example/?tag=x 302", red.read_text())
        self.assertIn("connect-src 'self' https://forms.example.com", red.read_text())
        self.assertEqual(info["active_links"], 1)

    def test_unapproved_link_never_published(self):
        _, red, info = _build({"ASKODOX_SITE_LINKS_JSON": json.dumps([{"slug": "x", "partner": "X", "programme": "X", "url": "https://x.example", "status": "active", "approved": False}])})
        self.assertEqual(info["active_links"], 0)
        self.assertNotIn("x.example", red.read_text())

    def test_telugu_locale_without_duplicated_pages(self):
        out, _, info = _build({"ASKODOX_SITE_LOCALES": "en,te"})
        te = (out / "te" / "index.html").read_text()
        self.assertIn('lang="te"', te)
        self.assertIn("కనుగొనండి", te)
        self.assertIn('href="/te/discover/"', te)
        self.assertIn('href="/static/', te)
        self.assertIn("https://askodox.com/te/", te)
        self.assertEqual(info["locales"], ["en", "te"])

    def test_locale_files_have_no_unknown_keys(self):
        en = json.loads((ROOT / "locales" / "en.json").read_text())
        for f in (ROOT / "locales").glob("*.json"):
            extra = set(json.loads(f.read_text())) - set(en)
            self.assertFalse(extra, f"{f.name} has keys missing from en.json: {extra}")


if __name__ == "__main__":
    unittest.main()


class WebChatProxyTest(unittest.TestCase):
    """askodox.com/chat is the backend's web chat, proxied (one engine)."""

    def test_caddy_proxies_only_the_chat_paths_to_the_backend(self):
        caddy = (ROOT / "server" / "Caddyfile").read_text()
        self.assertIn("@askodox_chat path /chat /api/in-app/assistant /deals/discover /api/advisor/next", caddy)
        self.assertIn("reverse_proxy {$ASKODOX_BACKEND_URL:https://podx-ai-connect-production-3279.up.railway.app}",
                      caddy)
        self.assertNotIn("/admin", caddy.split("@askodox_chat")[1].split("}")[0])

    def test_ask_box_and_nav_point_to_chat(self):
        cfg = json.loads((ROOT / "config" / "site.json").read_text())
        self.assertEqual(cfg["app"]["web_app_url"], "/chat")
        self.assertIn(("/chat", "nav.chat"), build.NAV)
