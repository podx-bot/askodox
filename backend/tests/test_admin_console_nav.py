"""The Command Center console map: every page exactly once, in a heading ->
category -> page tree, with English + Telugu names and a guide."""
import re

from app.api.routes import admin_console, admin_console_nav as nav
from app.services import platform_schema

TELUGU = re.compile(r"[ఀ-౿]")


def _render_views() -> set[str]:
    page = admin_console.PAGE
    block = page.split("const f={", 1)[1].split("}[VIEW]", 1)[0]
    return {v.strip() for v in block.split(",")}


def test_every_page_is_listed_exactly_once():
    ids = [i["id"] for s in nav.NAV for c in s["cats"] for i in c["items"]]
    assert len(ids) == len(set(ids)), "a page is listed twice"
    assert sorted(nav.views()) == sorted(_render_views())
    assert sorted(nav.resources()) == sorted(platform_schema.RESOURCES)


def test_every_heading_category_and_page_is_bilingual_with_a_guide():
    for s in nav.NAV:
        assert s["en"] and TELUGU.search(s["te"]) and TELUGU.search(s["what_te"])
        assert s["cats"]
        for c in s["cats"]:
            assert c["en"] and TELUGU.search(c["te"]) and c["items"]
            for i in c["items"]:
                assert i["en"] and i["what_en"] and i["do_en"], i["id"]
                assert TELUGU.search(i["te"]) and TELUGU.search(i["what_te"]) and TELUGU.search(i["do_te"]), i["id"]
                assert ("res" in i) != ("perm" in i)


def test_console_page_carries_the_map_guide_and_error_explanations():
    page = admin_console.PAGE
    assert "__NAV_JSON__" not in page and '"what_te"' in page
    for marker in ("function explainError", "function errText", "function home()", "function sectionPage",
                   "function renderCrumbs", "Guide · గైడ్"):
        assert marker in page
    assert "</script" not in page.split("const NAV=", 1)[1].split(";\n", 1)[0]


def test_console_is_one_mixed_language_view_without_separate_toggles():
    """Owner rule (2026-10-27): ONE Telugu-English mixed Command Center, no separate English / Telugu screens."""
    from app.api.routes import admin_console

    html = next(v for v in vars(admin_console).values() if isinstance(v, str) and "<script>" in v)
    for toggle in ("STATE.wqLang", "STATE.incLang", 'id="wq_lang"'):
        assert toggle not in html, toggle
    assert "My work queue · నా పని జాబితా" in html and "Problem · సమస్య" in html
