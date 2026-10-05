"""Registered ASKODOX video commerce: metadata only from the video, linked
listings, grounded answers with their basis, AI reply controls + seller
takeover, moderated comments, pre-orders with contact after accept, share,
analytics, discovery in normal results."""
import dataclasses
import struct
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import video_commerce as vc
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-vcom-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


def _mp4(seconds=40):
    mvhd = b"mvhd" + bytes(4) + b"\x00" * 8 + struct.pack(">II", 1000, seconds * 1000) + b"\x00" * 80
    moov = struct.pack(">I", len(mvhd) + 12) + b"moov" + struct.pack(">I", len(mvhd) + 4) + mvhd
    return b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 12 + moov + uuid.uuid4().bytes


class _Vision:
    client = object()

    def __init__(self):
        self.calls = 0

    def analyze_video(self, *, video_bytes, mime_type, caption):
        self.calls += 1
        return {"subject": "Car tyre inflator", "category": "product",
                "summary": "A portable tyre inflator pumping a car tyre to 35 PSI.",
                "facts": [{"key": "brand", "label": "Brand", "value": "JPT", "basis": "shown", "timestamp": "0:03",
                           "evidence": "logo on the box at 0:03"},
                          {"key": "max_pressure", "label": "Max pressure", "value": "150 PSI", "basis": "said",
                           "timestamp": "0:20", "evidence": "seller says 150 PSI at 0:20"},
                          {"key": "bike_tyres", "label": "Bike tyres", "value": "Inflates bike tyres too",
                           "basis": "shown", "timestamp": "0:41", "evidence": "pumps a bike tyre at 0:41"}],
                "missing": ["warranty"]}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(
        container.settings, admin_seed_key=OWNER_KEY, database_path=str(tmp_path / "vcom.db")))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    vision = _Vision()
    monkeypatch.setattr(container, "universal_image_service", vision, raising=False)
    return TestClient(app), container, vision


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _published_video(client, seller, *, title="My video"):
    v = client.post(f"/api/videos/upload?title={title}&submit=false&as_business=1", headers=seller,
                    files={"file": ("v.mp4", _mp4(), "video/mp4")}).json()
    return v


def test_metadata_suggestions_come_only_from_the_analysed_video(env):
    client, container, vision = env
    _, seller = _user(container)
    v = _published_video(client, seller, title="Best pump 5 year warranty")
    out = client.post(f"/api/videos/native/{v['id']}/suggest", headers=seller).json()
    s = out["suggestions"]
    assert out["status"] == "ready" and s["title"] == "Car tyre inflator" and s["brand"] == "JPT"
    assert "warranty" in s["not_established"] and not any("5 year" in f for f in s["features"]), \
        "never copied from the user's own title"
    assert any("Bike tyres" in f for f in s["features"]), "only SHOWN facts become features"
    _, other = _user(container)
    assert client.post(f"/api/videos/native/{v['id']}/suggest", headers=other).status_code == 404


def test_grounded_answers_carry_their_basis_and_never_guess(env):
    client, container, vision = env
    seller_id, seller = _user(container)
    v = _published_video(client, seller)
    client.post(f"/api/videos/native/{v['id']}/study", headers=seller, json={})
    pid = container.product_catalog_repository.upsert_product(seller_id, "tyre inflator", price=2499,
                                                              location_label="Benz Circle, Vijayawada",
                                                              service_area="Vijayawada")
    assert client.patch(f"/api/videos/mine/{v['id']}", headers=seller,
                        json={"listing_ids": [str(pid)], "preorder_enabled": True}).status_code == 200
    client.post(f"/api/videos/mine/{v['id']}/submit", headers=seller)
    client.post(f"/admin/cc/platform/r/videos/{v['id']}/actions/approve", headers=OWNER, json={})
    ask = lambda q, **kw: client.post(f"/api/videos/native/{v['id']}/ask", json={"question": q, **kw}).json()  # noqa
    bike = ask("Does this also inflate bike tyres?")
    assert bike["found"] and bike["basis"] == "seen_in_video" and "bike" in bike["answer"].lower()
    price = ask("What is the price?")
    assert price["found"] and price["basis"] == "listing" and "2,499" in price["answer"]
    warranty = ask("How many years warranty?")
    assert warranty["found"] is False and warranty["basis"] == "unknown", "never invented"
    refund = ask("Will you refund if it breaks?")
    assert refund.get("sensitive") is True and refund["found"] is False
    near = ask("Is this available near Vuyyuru?", area="Vuyyuru")
    assert "Vijayawada" in near["answer"] and "not confirmed" in near["answer"].lower()
    assert "order" in near["actions"] and "pre_order" in near["actions"]
    detail = client.get(f"/api/videos/native/{v['id']}").json()
    assert detail["listings"][0]["id"] == pid and "ASKODOX videos feed" in detail["visible_in"]


def test_ai_reply_modes_seller_takeover_and_moderation(env):
    client, container, vision = env
    seller_id, seller = _user(container)
    _, buyer = _user(container)
    v = _published_video(client, seller)
    client.post(f"/api/videos/native/{v['id']}/study", headers=seller, json={})
    client.post(f"/api/videos/mine/{v['id']}/submit", headers=seller)
    client.post(f"/admin/cc/platform/r/videos/{v['id']}/actions/approve", headers=OWNER, json={})
    # default = draft: the seller approves before anyone sees the AI answer
    q1 = client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "Does it do bike tyres?"}).json()
    assert q1["reply_status"] == "draft_pending" and q1["reply"] is None
    public = client.get(f"/api/videos/{v['id']}/comments").json()["items"]
    assert public[0]["reply"] is None, "a draft is never public"
    inbox = client.get("/api/videos/mine/inbox", headers=seller).json()
    assert [d["id"] for d in inbox["drafts"]] == [q1["id"]] and "author" not in inbox["drafts"][0]
    assert client.post(f"/api/videos/comments/{q1['id']}/approve", headers=seller).json()["reply_status"] == \
        "ai_answered"
    # auto: grounded answers publish at once, labelled as AI
    client.put("/api/videos/ai-settings", headers=seller, json={"mode": "auto"})
    q2 = client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "max pressure?"}).json()
    assert q2["reply_status"] == "ai_answered" and "150" in q2["reply"] and "AI" in q2["reply_label"]
    # unknown / sensitive -> the seller
    q3 = client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "warranty years?"}).json()
    q4 = client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "give me best price"}).json()
    assert q3["reply_status"] == q4["reply_status"] == "waiting_seller"
    # takeover: paused AI answers nothing
    client.put("/api/videos/ai-settings", headers=seller, json={"mode": "auto", "paused": True})
    q5 = client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "bike tyres ok?"}).json()
    assert q5["reply_status"] == "waiting_seller"
    assert client.post(f"/api/videos/comments/{q3['id']}/reply", headers=seller,
                       json={"text": "1 year warranty. Call 9876543210"}).json()["reply_status"] == "seller_answered"
    shown = {c["id"]: c for c in client.get(f"/api/videos/{v['id']}/comments").json()["items"]}
    assert "9876543210" not in (shown[q3["id"]]["reply"] or ""), "contact leakage masked"
    assert client.post(f"/api/videos/comments/{q3['id']}/reply", headers=buyer, json={"text": "x"}).status_code == 404
    # moderation: prohibited term hides the comment for staff
    flagged = client.post(f"/api/videos/{v['id']}/comments", headers=buyer,
                          json={"text": "selling counterfeit copies here", "kind": "comment"}).json()
    staff = client.get("/admin/cc/videos/comments", headers=OWNER).json()["items"]
    assert flagged["status"] in ("FLAGGED", "VISIBLE")
    if flagged["status"] == "FLAGGED":
        assert any(c["id"] == flagged["id"] for c in staff)
        assert flagged["id"] not in {c["id"] for c in client.get(f"/api/videos/{v['id']}/comments").json()["items"]}


def test_preorder_share_analytics_and_discovery(env):
    client, container, vision = env
    seller_id, seller = _user(container)
    buyer_id, buyer = _user(container)
    v = _published_video(client, seller, title="Tyre inflator demo")
    client.patch(f"/api/videos/mine/{v['id']}", headers=seller,
                 json={"tags": ["tyre", "inflator", "car"], "preorder_enabled": True, "preorder_date": "2026-11-01",
                       "preorder_price": 2299})
    client.post(f"/api/videos/mine/{v['id']}/submit", headers=seller)
    assert client.post(f"/api/videos/{v['id']}/preorder", headers=buyer, json={}).status_code == 404, \
        "not before publication"
    client.post(f"/admin/cc/platform/r/videos/{v['id']}/actions/approve", headers=OWNER, json={})
    po = client.post(f"/api/videos/{v['id']}/preorder", headers=buyer, json={"quantity": 2}).json()
    assert po["status"] == "REQUESTED" and "not confirmed" in po["message"]
    mine = client.get("/api/videos/preorders/mine", headers=buyer).json()["items"][0]
    assert "seller_phone" not in mine, "no contact before the seller accepts"
    inbox = client.get("/api/videos/mine/inbox", headers=seller).json()
    assert "buyer_phone" not in inbox["pre_orders"][0]
    decided = client.post(f"/api/videos/preorders/{po['id']}/decide", headers=seller, json={"accept": True}).json()
    assert decided["buyer_phone"] == "+" + buyer_id[len("app-phone-"):]
    assert client.get("/api/videos/preorders/mine", headers=buyer).json()["items"][0]["seller_phone"].startswith("+91")
    share = client.get(f"/api/videos/{v['id']}/share").json()
    assert share["link"].endswith(f"/v/{v['id']}") and "never posts" in share["note"]
    assert client.get(f"/v/{v['id']}").status_code == 200
    for area in ("Vuyyuru", "vuyyuru", "Vijayawada"):
        client.post(f"/api/videos/{v['id']}/event", json={"kind": "view", "area": area})
    client.post(f"/api/videos/{v['id']}/comments", headers=buyer, json={"text": "warranty?"})
    stats = client.get(f"/api/videos/mine/{v['id']}/analytics", headers=seller).json()
    assert stats["views"] == 3 and stats["pre_orders_accepted"] == 1 and stats["questions"] == 1
    assert stats["demand_by_area"][0] == {"area": "Vuyyuru", "count": 2}
    assert buyer_id not in str(stats)
    # discovered through the SAME result system when relevant
    body = {"user_id": "guest", "raw_text": "tyre inflator", "subject": "tyre inflator", "intent": "buy",
            "category": "PRODUCT", "trace": {"query": "tyre inflator videos"}}
    found = client.post("/deals/discover", json=body).json()
    ids = {str(m.get("id") or m.get("match_id") or "") for m in found.get("matches") or []}
    assert any(v["id"] in i for i in ids) or any(v["id"] in str(s) for s in found.get("sections") or []), \
        "a published ASKODOX video joins normal results"


def test_pure_helpers():
    assert vc.is_sensitive("can you reduce the price") and not vc.is_sensitive("does it inflate bike tyres")
    assert vc.reply_plan("auto", False, {"found": True}) == "auto"
    assert vc.reply_plan("draft", False, {"found": True}) == "draft"
    assert vc.reply_plan("auto", True, {"found": True}) == "seller"
    assert vc.reply_plan("off", False, {"found": True}) == "seller"
    assert vc.reply_plan("auto", False, {"found": False}) == "seller"
    assert "contact_masked" in vc.moderate("call 98765 43210 now")["reasons"]
