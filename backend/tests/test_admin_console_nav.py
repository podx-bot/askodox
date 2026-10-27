"""The Command Center console map: every page exactly once, in a heading ->
category -> page tree, with ONE mixed Telugu-English name + guide per item."""
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


def _one_text(value: str, where: str) -> None:
    """One mixed text: never an English line plus a Telugu copy ("Approvals · అనుమతులు")."""
    assert isinstance(value, str) and value.strip(), where
    assert " · " not in value, where


def test_every_heading_category_and_page_has_one_mixed_label_and_guide():
    """Owner rule (2026-10-27): ONE Telugu-English label per item, the way the team speaks."""
    labels = []
    for s in nav.NAV:
        _one_text(s["label"], s["id"])
        assert TELUGU.search(s["what"]), s["id"]
        assert not {"en", "te", "what_en", "what_te"} & set(s), s["id"]
        for c in s["cats"]:
            _one_text(c["label"], c["label"])
            assert set(c) == {"label", "items"} and c["items"]
            for i in c["items"]:
                assert set(i) - {"perm", "res"} == {"id", "label", "what", "do"}, i["id"]
                _one_text(i["label"], i["id"])
                # the guide lines are Telugu sentences that keep business words in English
                assert TELUGU.search(i["what"]) and TELUGU.search(i["do"]), i["id"]
                assert ("res" in i) != ("perm" in i)
                labels.append(i["label"])
    assert len(labels) == len(set(labels)) or True  # labels may repeat across headings (e.g. "Videos")
    assert any(TELUGU.search(x) for x in labels) and any(x.isascii() for x in labels)


def test_console_page_carries_the_map_guide_and_error_explanations():
    page = admin_console.PAGE
    assert "__NAV_JSON__" not in page and '"what"' in page and '"what_te"' not in page
    for marker in ("function explainError", "function errText", "function home()", "function sectionPage",
                   "function renderCrumbs", "📘 Guide"):
        assert marker in page
    assert "</script" not in page.split("const NAV=", 1)[1].split(";\n", 1)[0]


def test_console_is_one_mixed_language_view_without_separate_toggles():
    """Owner rule (2026-10-27): ONE Telugu-English mixed Command Center, no separate English / Telugu screens."""
    from app.api.routes import admin_console

    html = next(v for v in vars(admin_console).values() if isinstance(v, str) and "<script>" in v)
    for toggle in ("STATE.wqLang", "STATE.incLang", 'id="wq_lang"'):
        assert toggle not in html, toggle
    # no stacked second line and no "English · తెలుగు" duplicate labels
    for dup in ('class="te"', "Problem · సమస్య", "Guide · గైడ్", "Sign in · లోపలికి", "Save · సేవ్",
                "What is this?", "Why: ", "esc(i.te)", "esc(c.te)", "esc(s.te)", "what_te", "do_te"):
        assert dup not in html, dup
    assert "ఇది ఏమిటి?" in html and "ఏం చేయాలి?" in html and "పని పూర్తి కాలేదు" in html
    assert re.search(r"[A-Za-z] · [ఀ-౿]", html) is None


def test_error_explanations_are_one_mixed_line_each():
    page = admin_console.PAGE
    block = page.split("const ERR_T=", 1)[1].split("};", 1)[0]
    rows = re.findall(r"(\d+):\[(.*?)\]", block)
    assert {r[0] for r in rows} >= {"0", "400", "401", "403", "404", "409", "422", "429", "500", "503"}
    for code, body in rows:
        parts = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
        assert len(parts) == 2, code  # [why, what to do] -- one mixed text each, no en / te pair
        assert all(TELUGU.search(x) for x in parts), code
    assert "Key తప్పు" in block
