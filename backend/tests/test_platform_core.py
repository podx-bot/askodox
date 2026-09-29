"""Commercial platform core: schema-driven Command Center resources (CRUD,
lifecycle actions, duplicate/archive/restore, history, export), RBAC, smart
links with fallback + health checks, affiliate click -> conversion ->
commission, merchant offers claim/redeem, payments (idempotency, signed
webhooks, replay, refunds), revenue ledger, rewards ledger, account blocking,
the client tracking whitelist and integrations that wait for credentials.

Every merchant, program and link here is a test fixture, not a real company.
"""
import dataclasses
import hashlib
import hmac
import json
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import external_call_budget, rate_limit
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-pf-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
BASE = "/admin/cc/platform"


@pytest.fixture(autouse=True)
def _fresh():
    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "pf.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    # Other tests build their own apps (each re-registers the global token
    # revocation hook); bind it to the server container like production.
    from app.api.routes.account_privacy import deleted_before
    from app.api.routes.platform import revocation_check
    from app.services import session_tokens

    monkeypatch.setattr(session_tokens, "_revoked", revocation_check(container, deleted_before))
    monkeypatch.setattr(container, "link_fetcher", lambda url: 404 if "broken" in url else 200, raising=False)
    yield TestClient(app, follow_redirects=False), container
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None


def user(container, name):
    return {"Authorization": f"Bearer {issue_token(name, container.settings.session_token_secret)}"}


def staff(client, role):
    body = client.post("/admin/cc/staff", headers=OWNER, json={"name": f"{role} user", "role": role})
    assert body.status_code == 200, body.text
    return {"X-ASKODOX-Staff-Token": body.json()["token"]}


def create(client, resource, data, headers=OWNER):
    response = client.post(f"{BASE}/r/{resource}", headers=headers, json={"data": data})
    assert response.status_code == 200, response.text
    return response.json()


def act(client, resource, record_id, action, headers=OWNER, **params):
    return client.post(f"{BASE}/r/{resource}/{record_id}/actions/{action}", headers=headers,
                       json={"params": params, "confirm": True})


def live_affiliate(client, **link):
    program = create(client, "affiliate_programs", {"name": "Example Network", "network": "ExampleNet",
                                                    "commission_type": "percent", "commission_percent": 5,
                                                    "attribution_days": 30})
    assert act(client, "affiliate_programs", program["id"], "approve").status_code == 200
    body = {"title": "Example 43 inch TV", "program_id": program["id"], "link_type": "product",
            "affiliate_url": "https://shop.example/tv?aff=1", "keywords": ["tv", "television"], **link}
    record = create(client, "affiliate_links", body)
    assert act(client, "affiliate_links", record["id"], "approve").status_code == 200
    return program, record


# ------------------------------------------------------------------ schema --

def test_schema_lists_every_resource_and_needs_permission(api):
    client, _ = api
    assert client.get(f"{BASE}/schema").status_code == 401
    data = client.get(f"{BASE}/schema", headers=OWNER).json()
    names = {r["name"] for r in data["resources"]}
    assert {"affiliate_programs", "affiliate_links", "smart_links", "merchant_offers", "creators", "videos",
            "video_sources", "reviews", "notification_templates", "notification_rules",
            "subscription_promos"} <= names
    offers = next(r for r in data["resources"] if r["name"] == "merchant_offers")
    assert any(f["name"] == "min_bill" for f in offers["fields"]) and offers["actions"]


def test_crud_actions_duplicate_archive_restore_history_and_export(api):
    client, _ = api
    program = create(client, "affiliate_programs", {"name": "Example Program", "commission_type": "fixed",
                                                    "commission_fixed": 40})
    assert program["status"] == "DRAFT" and program["version"] == 1
    # Optimistic lock: a stale version is refused.
    edited = client.patch(f"{BASE}/r/affiliate_programs/{program['id']}", headers=OWNER,
                          json={"data": {"notes": "edited"}, "version": 1})
    assert edited.status_code == 200 and edited.json()["version"] == 2
    stale = client.patch(f"{BASE}/r/affiliate_programs/{program['id']}", headers=OWNER,
                         json={"data": {"notes": "stale"}, "version": 1})
    assert stale.status_code == 409
    for action, status in (("submit", "PENDING_REVIEW"), ("approve", "ACTIVE"), ("pause", "PAUSED"),
                           ("resume", "ACTIVE"), ("disable", "DISABLED"), ("enable", "ACTIVE")):
        response = act(client, "affiliate_programs", program["id"], action)
        assert response.status_code == 200, (action, response.text)
        assert response.json()["status"] == status
    assert act(client, "affiliate_programs", program["id"], "approve").status_code == 400, "illegal transition"
    copy = act(client, "affiliate_programs", program["id"], "duplicate").json()
    assert copy["id"] != program["id"] and copy["status"] == "DRAFT" and copy["name"].endswith("(copy)")
    assert act(client, "affiliate_programs", program["id"], "archive").json()["archived"]
    listed = client.get(f"{BASE}/r/affiliate_programs", headers=OWNER).json()["items"]
    assert program["id"] not in {i["id"] for i in listed}, "archived records leave the default list"
    archived = client.get(f"{BASE}/r/affiliate_programs?archived=true", headers=OWNER).json()["items"]
    assert [i["id"] for i in archived] == [program["id"]]
    assert act(client, "affiliate_programs", program["id"], "pause").status_code == 400, "restore first"
    assert not act(client, "affiliate_programs", program["id"], "restore").json()["archived"]
    history = client.get(f"{BASE}/r/affiliate_programs/{program['id']}/history", headers=OWNER).json()["items"]
    actions = [h["action"] for h in history]
    assert {"create", "edit", "approve", "archive", "restore"} <= set(actions)
    search = client.get(f"{BASE}/r/affiliate_programs?q=copy", headers=OWNER).json()["items"]
    assert [i["id"] for i in search] == [copy["id"]]
    csv_text = client.get(f"{BASE}/r/affiliate_programs/export.csv", headers=OWNER).text
    assert csv_text.startswith("id,status,archived,updated_at,name") and program["id"] in csv_text
    assert client.delete(f"{BASE}/r/affiliate_programs/{copy['id']}", headers=OWNER).status_code == 409
    assert client.delete(f"{BASE}/r/affiliate_programs/{copy['id']}?confirm=true", headers=OWNER).status_code == 200
    assert client.get(f"{BASE}/r/affiliate_programs/{copy['id']}", headers=OWNER).status_code == 404
    found = client.get(f"{BASE}/search?q=Example Program", headers=OWNER).json()["items"]
    assert any(h["id"] == program["id"] for h in found), "global search finds it"


def test_validation_rejects_unsafe_and_inconsistent_values(api):
    client, _ = api
    bad = [
        ("smart_links", {"title": "x", "slug": "promo", "link_type": "web", "web_url": "http://plain.example"}),
        ("smart_links", {"title": "x", "slug": "promo", "link_type": "deep_link", "deep_link": "javascript://x"}),
        ("smart_links", {"title": "x", "slug": "Bad Slug!", "link_type": "web", "web_url": "https://a.example"}),
        ("smart_links", {"title": "x", "slug": "wa", "link_type": "whatsapp"}),
        ("merchant_offers", {"title": "x", "offer_kind": "flat", "valid_from": "2026-10-10",
                             "valid_to": "2026-10-01"}),
        ("affiliate_programs", {"name": "x", "commission_type": "percent"}),
        ("videos", {"title": "x", "platform": "youtube", "url": "https://youtu.be/abcdefghijk",
                    "relationship": "sponsored"}),
    ]
    for resource, data in bad:
        response = client.post(f"{BASE}/r/{resource}", headers=OWNER, json={"data": data})
        assert response.status_code == 400, (resource, data, response.text)
    assert client.post(f"{BASE}/r/nope", headers=OWNER, json={"data": {}}).status_code == 404
    create(client, "smart_links", {"title": "Promo", "slug": "promo", "link_type": "web",
                                   "web_url": "https://a.example"})
    dup = client.post(f"{BASE}/r/smart_links", headers=OWNER,
                      json={"data": {"title": "Again", "slug": "PROMO", "link_type": "web",
                                     "web_url": "https://b.example"}})
    assert dup.status_code == 400 and "already used" in dup.json()["detail"]


def test_rbac_roles_see_only_their_areas(api):
    client, _ = api
    finance = staff(client, "finance")
    content = staff(client, "content_moderator")
    assert client.get(f"{BASE}/ledger", headers=finance).status_code == 200
    assert client.get(f"{BASE}/r/videos", headers=finance).status_code == 403
    assert client.get(f"{BASE}/r/videos", headers=content).status_code == 200
    assert client.get(f"{BASE}/payments", headers=content).status_code == 403
    assert client.post(f"{BASE}/r/affiliate_programs", headers=content,
                       json={"data": {"name": "x"}}).status_code == 403
    viewer = staff(client, "analytics_viewer")
    assert client.get(f"{BASE}/analytics", headers=viewer).status_code == 200
    assert client.get(f"{BASE}/insights", headers=viewer).status_code == 200
    assert client.get(f"{BASE}/r/affiliate_programs/export.csv", headers=viewer).status_code == 403
    assert client.get(f"{BASE}/dashboard", headers={"X-ASKODOX-Staff-Token": "stf_forged"}).status_code == 401


# ------------------------------------------------------------- smart links --

def test_smart_link_opens_app_first_then_web_fallback_and_is_tracked(api):
    client, container = api
    link = create(client, "smart_links", {
        "title": "TV offer", "slug": "tv-offer", "link_type": "app_link", "deep_link": "askodox://deal/42",
        "web_url": "https://shop.example/tv", "fallback_url": "https://askodox.example/help",
        "utm": {"utm_source": "askodox", "utm_campaign": "tv"}})
    page = client.get("/l/tv-offer", headers={"user-agent": "Mozilla/5.0 (Linux; Android 14)"})
    assert page.status_code == 200
    assert 'first="askodox://deal/42"' in page.text.replace(" ", "")
    assert "utm_source=askodox" in page.text and "utm_campaign=tv" in page.text
    assert client.get("/l/missing").status_code == 404
    events = client.get(f"{BASE}/events?event=deep_link", headers=OWNER).json()["items"]
    assert events and events[0]["link_id"] == link["id"] and events[0]["source"] == "android"
    act(client, "smart_links", link["id"], "disable")
    assert client.get("/l/tv-offer").status_code == 404, "a disabled link stops resolving"


def test_smart_link_whatsapp_call_maps_and_health_check(api):
    client, _ = api
    wa = create(client, "smart_links", {"title": "Chat", "slug": "chat", "link_type": "whatsapp",
                                        "phone": "+91 98765 43210", "message": "Hi, is the TV available?"})
    assert "https://wa.me/919876543210?text=Hi%2C%20is%20the%20TV%20available%3F" in client.get("/l/chat").text
    create(client, "smart_links", {"title": "Shop", "slug": "shop-map", "link_type": "maps", "latitude": 16.5,
                                   "longitude": 80.6})
    page = client.get("/l/shop-map").text
    assert "geo:16.5,80.6" in page and "google.com/maps/search" in page
    broken = create(client, "smart_links", {"title": "Old", "slug": "old", "link_type": "web",
                                            "web_url": "https://broken.example/x"})
    result = act(client, "smart_links", broken["id"], "test").json()
    assert result["result"]["state"] == "ERROR" and result["data"]["health"]["state"] == "ERROR"
    ok = act(client, "smart_links", wa["id"], "test").json()["result"]
    assert ok["state"] == "OK"
    insights = client.get(f"{BASE}/insights", headers=OWNER).json()["items"]
    assert any("old" in json.dumps(i) for i in insights), "broken links surface as an insight"


def test_smart_links_flag_switches_resolver_off(api):
    client, container = api
    create(client, "smart_links", {"title": "Promo", "slug": "promo", "link_type": "web",
                                   "web_url": "https://a.example"})
    container.command_center_repository.set_flag("links.smart", False, "test")
    assert client.get("/l/promo").status_code == 404


# --------------------------------------------------------------- affiliate --

def test_affiliate_rows_click_redirect_conversion_and_commission(api):
    client, container = api
    from app.api.routes.platform import platform

    program, link = live_affiliate(client)
    rows = platform(container).affiliate.rows({"subject": "43 inch tv", "raw_text": "43 inch tv"})
    assert len(rows) == 1 and rows[0]["affiliate"] and rows[0]["disclosure"]
    assert rows[0]["redirect_path"].startswith("/go/af/afc_")
    assert not platform(container).affiliate.rows({"subject": "plumber", "raw_text": "need a plumber"})
    click = rows[0]["click_id"]
    opened = client.get(f"/go/af/{click}")
    assert opened.status_code == 302 and opened.headers["location"] == "https://shop.example/tv?aff=1"
    client.get(f"/go/af/{click}")
    clicks = client.get(f"{BASE}/events?event=click", headers=OWNER).json()["items"]
    assert len(clicks) == 1, "a click is counted once"
    assert client.get("/go/af/afc_forged000000").status_code == 404
    conv = client.post(f"{BASE}/affiliate/conversions", headers=OWNER,
                       json={"click_id": click, "external_ref": "ORD-1", "order_value": 20000,
                             "status": "approved"}).json()
    assert conv["ledger"]["amount"] == 1000.0 and conv["ledger"]["state"] == "CONFIRMED"
    again = client.post(f"{BASE}/affiliate/conversions", headers=OWNER,
                        json={"click_id": click, "external_ref": "ORD-1", "order_value": 20000,
                              "status": "approved"}).json()
    assert again["created"] is False, "the same conversion is recorded once"
    unknown = client.post(f"{BASE}/affiliate/conversions", headers=OWNER,
                          json={"click_id": "afc_unknown00", "external_ref": "ORD-2", "order_value": 1})
    assert unknown.status_code == 409
    act(client, "affiliate_programs", program["id"], "pause")
    assert not platform(container).affiliate.rows({"subject": "tv", "raw_text": "tv"}), \
        "a paused program switches its links off"


# ---------------------------------------------------------- merchant offers --

def test_merchant_offer_review_claim_redeem_and_limits(api):
    client, container = api
    merchant, buyer, other = (user(container, "app-merchant-1"), user(container, "app-buyer-1"),
                              user(container, "app-buyer-2"))
    created = client.post("/api/merchant/offers", headers=merchant, json={"data": {
        "title": "₹100 off on TV installation", "offer_kind": "flat", "value": 100, "min_bill": 500,
        "redemption_limit": 1, "per_user_limit": 1, "budget": 150, "categories": ["tv"]}})
    assert created.status_code == 200, created.text
    offer = created.json()
    assert offer["status"] == "PENDING_REVIEW", "merchant offers are always reviewed first"
    assert client.post(f"/api/merchant-offers/{offer['id']}/claim", headers=buyer).status_code == 409
    assert client.post(f"/api/merchant/offers/{offer['id']}/approve", headers=merchant).status_code == 403
    act(client, "merchant_offers", offer["id"], "approve")
    assert client.post(f"/api/merchant-offers/{offer['id']}/claim", headers=merchant).status_code == 409, \
        "a merchant cannot claim their own offer"
    claim = client.post(f"/api/merchant-offers/{offer['id']}/claim", headers=buyer).json()
    assert claim["state"] == "CLAIMED" and claim["claim_code"]
    assert "user_ref" not in claim
    same = client.post(f"/api/merchant-offers/{offer['id']}/claim", headers=buyer).json()
    assert same["already"] and same["claim_code"] == claim["claim_code"], "claiming is idempotent"
    assert client.post(f"/api/merchant-offers/{offer['id']}/claim", headers=other).status_code == 409, \
        "redemption limit reached"
    code = claim["claim_code"]
    assert client.post(f"/api/merchant/claims/{code}/redeem", headers=other, json={"bill_amount": 900}) \
        .status_code == 404, "only the offering merchant can redeem"
    low = client.post(f"/api/merchant/claims/{code}/redeem", headers=merchant, json={"bill_amount": 100})
    assert low.status_code == 409 and "minimum bill" in low.json()["detail"]
    redeemed = client.post(f"/api/merchant/claims/{code}/redeem", headers=merchant, json={"bill_amount": 900})
    assert redeemed.status_code == 200 and redeemed.json()["benefit"] == 100
    assert client.post(f"/api/merchant/claims/{code}/redeem", headers=merchant,
                       json={"bill_amount": 900}).status_code == 409, "no double redemption"
    report = client.get(f"{BASE}/merchant-offers/{offer['id']}/report", headers=OWNER).json()
    assert report == {"claims": 1, "redeemed": 1, "expired": 0, "benefit_given": 100.0, "remaining": 0}
    mine = client.get("/api/merchant/offers", headers=merchant).json()["items"]
    assert [m["id"] for m in mine] == [offer["id"]] and mine[0]["report"]["redeemed"] == 1
    assert client.get("/api/merchant/offers", headers=buyer).json()["items"] == []
    # An owner's edit of a live offer sends it back to review.
    paused = client.post(f"/api/merchant/offers/{offer['id']}/pause", headers=merchant)
    assert paused.status_code == 200 and paused.json()["status"] == "PAUSED"
    assert client.post(f"/api/merchant/offers/{offer['id']}/pause", headers=buyer).status_code == 404


def test_merchant_offers_flag_and_sign_in(api):
    client, container = api
    assert client.post("/api/merchant/offers", json={"data": {"title": "x", "offer_kind": "flat"}}) \
        .status_code == 401
    container.command_center_repository.set_flag("offers.merchant", False, "test")
    refused = client.post("/api/merchant/offers", headers=user(container, "app-m-2"),
                          json={"data": {"title": "x", "offer_kind": "flat"}})
    assert refused.status_code == 409


# ---------------------------------------------------------------- payments --

def test_payments_idempotent_direct_confirm_refund_settle(api):
    client, _ = api
    body = {"idempotency_key": "order-1-pay", "method": "cod", "amount": 1200, "order_ref": "ord-1"}
    first = client.post(f"{BASE}/payments", headers=OWNER, json=body).json()
    assert first["status"] == "PENDING" and first["created"]
    again = client.post(f"{BASE}/payments", headers=OWNER, json=body).json()
    assert again["id"] == first["id"] and not again["created"], "same key -> same payment"
    conflict = client.post(f"{BASE}/payments", headers=OWNER, json=body | {"amount": 999})
    assert conflict.status_code == 409, "a reused key with a different amount is refused"
    paid = client.post(f"{BASE}/payments/{first['id']}/confirm", headers=OWNER, json={"reference": "cash"}).json()
    assert paid["status"] == "PAID"
    assert client.post(f"{BASE}/payments/{first['id']}/refund", headers=OWNER,
                       json={"amount": 200}).status_code == 409, "refund needs confirmation"
    partial = client.post(f"{BASE}/payments/{first['id']}/refund", headers=OWNER,
                          json={"amount": 200, "confirm": True}).json()
    assert partial["status"] == "PARTIALLY_REFUNDED" and partial["refunded_amount"] == 200
    over = client.post(f"{BASE}/payments/{first['id']}/refund", headers=OWNER,
                       json={"amount": 5000, "confirm": True})
    assert over.status_code in (400, 409), "cannot refund more than was paid"
    full = client.post(f"{BASE}/payments/{first['id']}/refund", headers=OWNER,
                       json={"amount": 1000, "confirm": True}).json()
    assert full["status"] == "REFUNDED"
    states = [h["to_state"] for h in full["history"]]
    assert states[:2] == ["CREATED", "PENDING"] and states[-1] == "REFUNDED"
    txns = client.get(f"{BASE}/transactions", headers=OWNER).json()
    assert {"payment", "refund"} <= set(txns["kinds"])


def test_gateway_payments_need_configuration_and_signed_webhooks(api):
    client, _ = api
    refused = client.post(f"{BASE}/payments", headers=OWNER,
                          json={"idempotency_key": "k1", "method": "card", "amount": 10, "provider": "razorpay"})
    assert refused.status_code == 409 and "needs configuration" in refused.json()["detail"]
    items = {i["provider"]: i for i in client.get(f"{BASE}/integrations", headers=OWNER).json()["items"]}
    assert items["razorpay"]["status"] == "NEEDS_CONFIGURATION" and items["direct_settlement"]["status"] == "LIVE"
    configured = client.put(f"{BASE}/integrations/razorpay", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"key_id": "rzp_test_example"},
        "secrets": {"key_secret": "sk-example", "webhook_secret": "whsec-example"}}).json()
    assert configured["status"] == "TEST" and "sk-example" not in json.dumps(configured)
    listing = client.get(f"{BASE}/integrations", headers=OWNER).text
    assert "whsec-example" not in listing and "sk-example" not in listing, "secrets are write-only"
    payment = client.post(f"{BASE}/payments", headers=OWNER,
                          json={"idempotency_key": "k2", "method": "card", "amount": 500,
                                "provider": "razorpay"}).json()
    assert payment["status"] == "CREATED"
    assert client.post(f"{BASE}/payments/{payment['id']}/confirm", headers=OWNER, json={}).status_code == 409, \
        "gateway payments are confirmed only by the gateway"
    event = json.dumps({"event_id": "evt_1", "payment_id": payment["id"], "status": "PAID",
                        "provider_ref": "pay_123"}).encode()
    good = hmac.new(b"whsec-example", event, hashlib.sha256).hexdigest()
    assert client.post("/api/payments/webhook/razorpay", content=event,
                       headers={"x-askodox-signature": "0" * 64}).status_code == 401
    ok = client.post("/api/payments/webhook/razorpay", content=event, headers={"x-askodox-signature": good})
    assert ok.status_code == 200 and ok.json() == {"ok": True, "duplicate": False, "status": "PAID"}
    replay = client.post("/api/payments/webhook/razorpay", content=event, headers={"x-askodox-signature": good})
    assert replay.json()["duplicate"] is True, "replayed events are ignored"
    audit = client.get("/admin/cc/audit", headers=OWNER).text
    assert "whsec-example" not in audit and "sk-example" not in audit


def test_integrations_refuse_secrets_without_encryption_key(api, monkeypatch):
    client, container = api
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, secrets_key=""))
    container.platform = None
    response = client.put(f"{BASE}/integrations/cashfree", headers=OWNER,
                          json={"secrets": {"client_secret": "x"}})
    assert response.status_code == 503


# ------------------------------------------------------ ledger and rewards --

def test_revenue_ledger_transitions_and_reconciliation(api):
    client, _ = api
    entry = client.post(f"{BASE}/ledger", headers=OWNER, json={
        "idempotency_key": "sp-1", "kind": "sponsored_revenue", "amount": 5000, "state": "EXPECTED"}).json()
    assert entry["created"] and entry["state"] == "EXPECTED"
    dup = client.post(f"{BASE}/ledger", headers=OWNER, json={
        "idempotency_key": "sp-1", "kind": "sponsored_revenue", "amount": 5000}).json()
    assert dup["id"] == entry["id"] and not dup["created"]
    for state in ("PENDING", "CONFIRMED"):
        assert client.post(f"{BASE}/ledger/{entry['id']}/state", headers=OWNER,
                           json={"state": state}).json()["state"] == state
    assert client.post(f"{BASE}/ledger/{entry['id']}/state", headers=OWNER,
                       json={"state": "PAID"}).status_code == 409, "paying needs confirmation"
    paid = client.post(f"{BASE}/ledger/{entry['id']}/state", headers=OWNER, json={"state": "PAID", "confirm": True})
    assert paid.json()["state"] == "PAID"
    assert client.post(f"{BASE}/ledger/{entry['id']}/state", headers=OWNER,
                       json={"state": "EXPECTED"}).status_code in (400, 409)
    summary = client.get(f"{BASE}/ledger", headers=OWNER).json()
    assert summary["summary"]["by_state"]["PAID"] == 5000.0
    assert "reconciliation" in summary


def test_rewards_ledger_lifecycle_and_customer_claim(api):
    client, container = api
    from app.api.routes.platform import user_ref

    buyer = user(container, "app-reward-buyer")
    ref = user_ref("app-reward-buyer")
    reward = client.post(f"{BASE}/rewards", headers=OWNER, json={
        "idempotency_key": "cb-1", "user_ref": ref, "reward_type": "cashback", "amount": 50,
        "title": "₹50 cashback"}).json()
    assert reward["created"] and reward["state"] == "AVAILABLE"
    assert client.post(f"{BASE}/rewards", headers=OWNER, json={
        "idempotency_key": "cb-2", "user_ref": ref, "reward_type": "cashback"}).status_code == 400, \
        "a reward needs a value"
    mine = client.get("/api/rewards/ledger/mine", headers=buyer).json()["items"]
    assert [r["id"] for r in mine] == [reward["id"]]
    assert client.post(f"/api/rewards/ledger/{reward['id']}", headers=buyer,
                       json={"action": "redeem"}).status_code == 403
    other = user(container, "app-someone-else")
    assert client.post(f"/api/rewards/ledger/{reward['id']}", headers=other,
                       json={"action": "claim"}).status_code == 404
    claimed = client.post(f"/api/rewards/ledger/{reward['id']}", headers=buyer, json={"action": "claim"})
    assert claimed.status_code == 200 and claimed.json()["state"] == "CLAIMED"
    assert client.post(f"/api/rewards/ledger/{reward['id']}", headers=buyer,
                       json={"action": "claim"}).status_code == 409
    for state in ("REDEEMED",):
        assert client.post(f"{BASE}/rewards/{reward['id']}/state", headers=OWNER,
                           json={"state": state}).json()["state"] == state
    by_state = client.get(f"{BASE}/rewards", headers=OWNER).json()["by_state"]
    assert by_state == {"REDEEMED": 1}
    container.command_center_repository.set_flag("rewards", False, "test")
    assert client.post(f"{BASE}/rewards", headers=OWNER, json={
        "idempotency_key": "cb-3", "user_ref": ref, "reward_type": "cashback", "amount": 5}).status_code == 409


# ---------------------------------------------------- accounts and tracking --

def test_blocking_a_user_revokes_their_sessions(api):
    client, container = api
    from app.api.routes.platform import user_ref

    headers = user(container, "app-blocked-user")
    assert client.get("/api/rewards/ledger/mine", headers=headers).status_code == 200
    ref = user_ref("app-blocked-user")
    assert client.post(f"{BASE}/accounts/user/{ref}", headers=OWNER, json={"blocked": True}).status_code == 409
    blocked = client.post(f"{BASE}/accounts/user/{ref}", headers=OWNER, json={"blocked": True, "confirm": True})
    assert blocked.status_code == 200 and blocked.json()["blocked"]
    assert client.get("/api/rewards/ledger/mine", headers=headers).status_code == 401
    listed = client.get(f"{BASE}/accounts/user", headers=OWNER).json()["items"]
    assert listed[0]["subject_ref"] == ref and "app-blocked-user" not in json.dumps(listed)
    client.post(f"{BASE}/accounts/user/{ref}", headers=OWNER, json={"blocked": False})
    assert client.get("/api/rewards/ledger/mine", headers=headers).status_code == 200, "unblock restores access"


def test_tracking_whitelist_and_identity_from_token_only(api):
    client, container = api
    from app.api.routes.platform import user_ref

    assert client.post("/api/track", json={"event": "commission"}).status_code == 400, \
        "money events never come from the client"
    ok = client.post("/api/track", headers=user(container, "app-tracker"),
                     json={"event": "video_watch_start", "ids": {"video_id": "vid_1", "user_ref": "spoofed"},
                           "category": "tv", "language": "te"})
    assert ok.json() == {"recorded": True}
    events = client.get(f"{BASE}/events?event=video_watch_start", headers=OWNER).json()["items"]
    assert events[0]["user_ref"] == user_ref("app-tracker") and events[0]["video_id"] == "vid_1"
    analytics = client.get(f"{BASE}/analytics?category=tv", headers=OWNER).json()
    assert next(s for s in analytics["video_funnel"] if s["step"] == "video_watch_start")["count"] == 1


def test_notification_rules_templates_and_channels_waiting_for_credentials(api):
    client, _ = api
    template = create(client, "notification_templates", {
        "key": "order_update", "channel": "in_app", "type": "order", "language": "en",
        "title": "Order {order}", "body": "Hi {name}, your order {order} is {status}."})
    preview = act(client, "notification_templates", template["id"], "preview",
                  values={"order": "A1", "name": "Ravi", "status": "ready"}).json()["result"]
    assert preview["body"] == "Hi Ravi, your order A1 is ready."
    create(client, "notification_templates", {"key": "order_update", "channel": "sms", "type": "order",
                                              "language": "en", "title": "Order", "body": "Order {order}"})
    rule = create(client, "notification_rules", {"name": "Order updates", "event": "order_status",
                                                 "template_key": "order_update", "channels": ["in_app", "sms"],
                                                 "throttle_minutes": 0})
    act(client, "notification_rules", rule["id"], "enable")
    results = client.post(f"{BASE}/notifications/test", headers=OWNER, json={
        "event": "order_status", "user_ref": "u_test", "values": {"order": "A1", "name": "R", "status": "ok"}}
    ).json()["results"]
    by_channel = {r["channel"]: r["status"] for r in results}
    assert by_channel == {"in_app": "sent", "sms": "skipped_needs_configuration"}


def test_dashboard_and_insights_are_suggestions_only(api):
    client, _ = api
    dash = client.get(f"{BASE}/dashboard", headers=OWNER).json()
    assert "integrations" in json.dumps(dash).lower()
    insights = client.get(f"{BASE}/insights", headers=OWNER).json()
    assert insights["note"].startswith("Suggestions only")
