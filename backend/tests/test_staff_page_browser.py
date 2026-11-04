"""The Staff Workspace page in a real browser (owner 2026-11-04: a Meesho link
stayed on "Reading the page..." -- a script error after the fetch). Mocked API;
skipped where no browser is installed."""
import json

import pytest

from app.api.routes import staff_workspace_page as page

playwright = pytest.importorskip("playwright.sync_api")

ME = {"name": "Owner", "role": "super_admin", "counts": {}, "item_types": ["product"], "can_publish": True,
      "can_link": True, "can_commission": True,
      "sections": {k: True for k in "add review items tasks support feedback demand sources analytics".split()}}
IMPORTED = {"url": "https://www.meesho.com/s/p/abc", "ok": True, "source": {"name": "Meesho"}, "duplicates": [],
            "fields": {"title": "Cotton saree", "price": 399, "images": ["https://images.example/a.jpg"]},
            "field_status": {"title": "fetched"}, "status": "ok", "note": None}


def _run(check):
    with playwright.sync_playwright() as pw:
        try:
            browser = pw.chromium.launch()
        except Exception as error:  # noqa: BLE001
            pytest.skip(f"no browser: {error}")
        tab = browser.new_page()
        errors = []
        tab.on("pageerror", lambda e: errors.append(str(e)))

        def handle(route):
            url = route.request.url
            if url.endswith("/staff"):
                return route.fulfill(body=page.PAGE, content_type="text/html")
            for part, body in (("/workspace/me", ME), ("/workspace/import", IMPORTED),
                               ("/workspace/describe", {"ok": False, "reason": "off"})):
                if part in url:
                    return route.fulfill(body=json.dumps(body), content_type="application/json")
            return route.fulfill(status=404, body="{}")

        tab.route("**/*", handle)
        tab.goto("http://staff.test/staff")
        tab.evaluate("sessionStorage.setItem('askodox_staff', JSON.stringify({token: 'stf_test'}))")
        tab.goto("http://staff.test/staff")
        tab.wait_for_selector("#fetch")
        check(tab)
        browser.close()
        assert errors == [], errors


def test_link_fetch_fills_the_form_with_commission_boxes():
    def check(tab):
        tab.fill("#url", "Look at this https://www.meesho.com/s/p/abc?utm_source=s")
        tab.click("#fetch")
        tab.wait_for_selector("#f_title", timeout=5000)
        assert tab.input_value("#f_title") == "Cotton saree"
        assert tab.is_visible("#f_affiliate_url") and tab.is_visible("#f_verified_commission_rate")

    _run(check)


def test_own_brand_form_opens_without_errors():
    def check(tab):
        tab.click("#m_own")
        tab.wait_for_selector("#o_rate", timeout=5000)
        assert tab.is_visible("#o_aff")

    _run(check)
