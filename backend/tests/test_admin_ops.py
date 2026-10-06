"""Admin Assistant operational commands: answers from stored records, a
previewed operation (never executed by the assistant), Telugu, permissions."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import admin_ops

PAGE = """<html><head><script type="application/ld+json">{"@type":"Product","name":"Steel Bottle 1L",
"offers":{"@type":"Offer","price":"250"}}</script></head></html>"""


def test_command_detection_en_te():
    assert admin_ops.commands("add these links https://shop.example.in/p/1") == ["add_links"]
    assert admin_ops.commands("show products with missing prices") == ["missing_prices"]
    assert admin_ops.commands("ధర లేని ఉత్పత్తులు చూపించు") == ["missing_prices"]
    assert admin_ops.commands("find duplicates") == ["duplicates"]
    assert admin_ops.commands("which sources are failing?") == ["failing_sources"]
    assert admin_ops.commands("what needs review?") == ["needs_review"]
    assert admin_ops.commands('why didn\'t "Kurti Blue" appear?') == ["why_missing"]
    assert admin_ops.commands("assign opportunities") == ["opportunities"]
    assert admin_ops.commands("what increased today?") == []
    assert admin_ops.language("ధర లేని ఉత్పత్తులు") == "te" and admin_ops.language("x", "te") == "te"


def test_why_missing_explains_eligibility_in_words():
    items = [{"id": 3, "title": "Kurti Blue", "platform": "meesho",
              "eligibility": {"reasons": ["out_of_stock", "review_needs_review"]}}]
    out = admin_ops.run("why_missing", 'why didn\'t "kurti blue" appear?', "en", catalog_items=lambda: items)
    assert "OUT_OF_STOCK" in out["observed"][0] and "NEEDS_REVIEW" in out["observed"][0]
    none = admin_ops.run("why_missing", 'why didn\'t "rice cooker" appear?', "en", catalog_items=lambda: items)
    assert "No catalog product" in none["observed"][0] and none["operation"]["view"] == "resultdiag"
    denied = admin_ops.run("missing_prices", "missing prices", "te", catalog_items=None)
    assert "అనుమతి" in denied["observed"][0]


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-ops-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(
        container.settings, admin_seed_key=key, database_path=str(tmp_path / "ops.db")))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    monkeypatch.setattr(container, "affiliate_page_fetch", lambda url: PAGE, raising=False)
    monkeypatch.setattr(container, "affiliate_catalog", None, raising=False)
    return TestClient(app), {"X-ASKODOX-Admin-Key": key}


def test_assistant_commands_preview_without_writing(api):
    client, owner = api
    ask = lambda q, **kw: client.post("/admin/cc/assistant/ask", headers=owner, json={"question": q, **kw})
    for title, price in (("Steel Bottle 1L", 250), ("Steel bottle 1l", None)):
        r = client.post("/admin/cc/affiliate-products", headers=owner,
                        json={"title": title, "original_product_url": f"https://shop{price}.example.in/p/{title[-2:]}",
                              "price": price})
        assert r.status_code == 200, r.text
    before = client.get("/admin/cc/affiliate-products", headers=owner).json()["summary"]["total"]

    links = ask("add these links https://shop.example.in/p/9 https://shop.example.in/p/10").json()
    a = links["answers"][0]
    assert a["topic"] == "add_links" and a["operation"]["kind"] == "open_smart_entry"
    assert len(a["operation"]["inputs"]) == 2 and a["operation"]["preview"]["NEW"] + a["operation"]["preview"]["NEEDS_REVIEW"] == 2
    assert client.get("/admin/cc/affiliate-products", headers=owner).json()["summary"]["total"] == before

    miss = ask("show products with missing prices").json()["answers"][0]
    assert miss["observed"][0].startswith("1 catalog product") and miss["operation"]["view"] == "affproducts"
    dup = ask("find duplicates").json()["answers"][0]
    assert dup["observed"][0].startswith("1 title")
    te = ask("ధర లేని ఉత్పత్తులు చూపించు").json()
    assert te["language"] == "te" and te["answers"][0]["title"] == "ధర లేని ఉత్పత్తులు"
    review = ask("what needs review?").json()["answers"][0]
    assert review["topic"] == "needs_review"
    # the older data questions still work
    assert ask("what increased today?").status_code == 200


def test_assistant_respects_permissions(api):
    client, owner = api
    staff = client.post("/admin/cc/staff", headers=owner, json={"name": "sup", "role": "support_agent"})
    token = {"X-ASKODOX-Staff-Token": staff.json()["token"]}
    r = client.post("/admin/cc/assistant/ask", headers=token, json={"question": "show products with missing prices"})
    assert r.status_code == 200 and "permission" in r.json()["answers"][0]["observed"][0]
    r = client.post("/admin/cc/assistant/ask", headers=token, json={"question": "add https://shop.example.in/p/1"})
    assert r.json()["answers"][0]["operation"] is None
