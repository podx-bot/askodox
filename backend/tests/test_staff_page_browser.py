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
        tab.wait_for_selector("#m_link")
        check(tab)
        browser.close()
        assert errors == [], errors


def test_link_fetch_fills_the_form_with_commission_boxes():
    def check(tab):
        tab.click("details.card summary")  # the old "read the store page" way is folded (owner 2026-11-20)
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


def test_affiliate_four_step_form_names_the_missing_box():
    """Owner 2026-11-20: link (not opened) -> photos -> fill + price -> publish; a missing box is named, not a 400."""
    def check(tab):
        tab.click("#m_link")
        tab.wait_for_selector("#a_link", timeout=5000)
        tab.fill("#a_link", "https://www.meesho.com/s/p/abc")
        tab.dispatch_event("#a_link", "input")
        assert tab.input_value("#a_store") == "Meesho"
        tab.click("#a_submit")
        assert "ఫోటో" in tab.inner_text("#a_err"), "no photo -> step 2 is named"
        assert tab.is_visible("#a_fill") and tab.is_visible("#a_price") and tab.is_visible("#a_aivid")

    _run(check)


def test_finance_tab_opens_an_item_and_the_call_back_list():
    view = {"item_id": "7", "title": "Suraksha Health Plan", "kind": "insurance", "checked": False, "checked_at": "",
            "documents": [{"id": "fd_1", "name": "brochure.pdf", "pages": 3, "mime": "application/pdf"}],
            "points": ["Entry age 18 to 65 years"], "not_answered": [{"question": "is maternity covered?", "times": 2}],
            "qa": [{"id": "fq_1", "question": "When are old diseases covered?", "answer": "After 36 months.", "page": 2,
                    "document": "brochure.pdf", "source": "document"}]}
    calls = {"callbacks": [{"id": "fc_1", "item_id": "7", "title": "Suraksha Health Plan", "customer": "••321",
                            "question": "Is maternity covered?", "when": "evening", "status": "new", "outcome": ""}]}
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
            for part, body in (("/workspace/me", {**ME, "item_types": ["product", "financial_offer"]}),
                               ("/finance-callbacks/fc_1/reveal", {"id": "fc_1", "phone": "9000000321"}),
                               ("/finance-callbacks", calls), ("/workspace/finance/7", view),
                               ("/workspace/items", {"items": [{"id": 7, "title": "Suraksha Health Plan",
                                                                "review_status": "DRAFT"}]})):
                if part in url:
                    return route.fulfill(body=json.dumps(body), content_type="application/json")
            return route.fulfill(status=404, body="{}")

        tab.route("**/*", handle)
        tab.goto("http://staff.test/staff")
        tab.evaluate("sessionStorage.setItem('askodox_staff', JSON.stringify({token: 'stf_test'}))")
        tab.goto("http://staff.test/staff")
        tab.click("#nav button[data-t=finance]")
        tab.click("button[data-fopen='7']")
        tab.wait_for_selector("#fok_7", timeout=5000)
        assert "brochure.pdf" in tab.inner_text("#fbox_7") and "36 months" in tab.inner_text("#fbox_7")
        tab.click("#fn_calls")
        tab.wait_for_selector("button[data-fnum='fc_1']", timeout=5000)
        assert "9000000321" not in tab.inner_text("main") and "••321" in tab.inner_text("main")
        tab.click("button[data-fnum='fc_1']")
        tab.wait_for_selector("#fnum_fc_1 a", timeout=5000)
        assert tab.inner_text("#fnum_fc_1") == "9000000321"
        browser.close()
        assert errors == [], errors
