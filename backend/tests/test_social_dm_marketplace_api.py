"""Social Auto-DM (Meta) + marketplace product APIs: built internally, testable
in MOCK mode, never claimed LIVE without real credentials and a passed check.
Every credential / id here is a test fixture; no network is used."""
import dataclasses
import hashlib
import hmac
import json
import uuid
from datetime import datetime, timezone

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import affiliate_catalog as ac
from app.services import marketplace_api, rate_limit, social_dm

OWNER_KEY = "owner-dm-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
APP_SECRET = "app-secret-" + uuid.uuid4().hex


class FakeHttp:
    def __init__(self, responses=None):
        self.calls, self.responses = [], responses or {}

    def __call__(self, method, url, **kwargs):
        self.calls.append({"method": method, "url": url, **kwargs})
        for fragment, response in self.responses.items():
            if fragment in url:
                return response
        return 500, {"error": {"code": 1}}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "dm.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    monkeypatch.setattr(container, "affiliate_catalog", ac.AffiliateCatalog(str(tmp_path / "dm.db")), raising=False)
    http = FakeHttp()
    monkeypatch.setattr(container, "comms_http", http, raising=False)
    monkeypatch.setattr(container, "integration_probes", None, raising=False)
    yield TestClient(app), container, http
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None


def _pf(container):
    from app.api.routes.platform import platform

    return platform(container)


def _business(pf, biz, page="111222333", channels=("askodox_chat", "facebook")):
    rule = pf.resources.create("auto_response_rules", {
        "name": "faq", "business_ref": biz, "faq": {"delivery": "We deliver in 2 days. Call 9876543210"},
        "channels": list(channels)}, actor="t", owner_ref=biz)
    pf.resources.action("auto_response_rules", rule["id"], "enable", actor="t", owner_ref=biz)
    acct = pf.resources.create("social_dm_accounts", {"name": "Shop page", "channel": "facebook",
                                                      "account_id": page, "business_ref": biz}, actor="t")
    return rule, acct


def _dm(page, text, sender="cust-1"):
    return {"object": "page", "entry": [{"id": page, "messaging": [
        {"sender": {"id": sender}, "recipient": {"id": page}, "message": {"mid": "m1", "text": text}}]}]}


def _signed(body):
    raw = json.dumps(body).encode()
    return raw, {"X-Hub-Signature-256": "sha256=" + hmac.new(APP_SECRET.encode(), raw, hashlib.sha256).hexdigest(),
                 "Content-Type": "application/json"}


def test_status_is_honest_without_credentials(api):
    client, container, _ = api
    body = client.get("/admin/cc/social-dm", headers=OWNER).json()
    ch = {k: v["status"] for k, v in body["channels"].items()}
    assert ch == {"askodox_chat": "LIVE", "facebook": "EXTERNAL_SETUP_REQUIRED",
                  "instagram": "EXTERNAL_SETUP_REQUIRED", "whatsapp": "EXTERNAL_SETUP_REQUIRED",
                  "snapchat": "NOT_AVAILABLE"}
    assert client.get("/admin/cc/social-dm").status_code in (401, 403)
    # webhook refuses until the app secret is configured
    assert client.post("/webhooks/meta-messaging", json=_dm("1", "hi")).status_code == 503


def test_unlinked_or_pending_account_never_replies_and_simulation_is_mock(api):
    client, container, http = api
    pf = _pf(container)
    biz = "app-biz-" + uuid.uuid4().hex[:6]
    _, acct = _business(pf, biz)
    sim = {"channel": "facebook", "account_id": "111222333", "text": "do you deliver?"}
    r = client.post("/admin/cc/social-dm/simulate", json=sim, headers=OWNER).json()
    assert r["results"][0]["status"] == "no_linked_business", "PENDING_VERIFICATION is not linked yet"
    pf.resources.action("social_dm_accounts", acct["id"], "activate", actor="t")
    r = client.post("/admin/cc/social-dm/simulate", json=sim, headers=OWNER).json()["results"][0]
    assert r["status"] == "answered" and r["delivery"]["mode"] == "mock" and r["delivery"]["sent"]
    assert "9876543210" not in r["text"], "contacts stay masked"
    assert http.calls == [], "simulation never contacts Meta"
    r = client.post("/admin/cc/social-dm/simulate", json=dict(sim, text="I want a refund"), headers=OWNER).json()
    assert r["results"][0]["status"] == "handoff" and r["results"][0]["handoff_to_owner"]
    events = pf.repo.events(event="social_dm", limit=10)
    assert events and all("text" not in (e.get("detail") or {}) for e in events)


def test_signed_webhook_live_reply_goes_to_meta_only_with_token(api):
    client, container, http = api
    pf = _pf(container)
    biz = "app-biz-" + uuid.uuid4().hex[:6]
    _, acct = _business(pf, biz, page="555")
    pf.resources.action("social_dm_accounts", acct["id"], "activate", actor="t")
    pf.registry.configure("meta_messaging", actor="t", enabled=True, mode="test", config={"app_id": "42"},
                          secrets={"app_secret": APP_SECRET, "verify_token": "vt-1"})
    assert social_dm.channel_status(pf.registry, "facebook")["status"] == "CONFIGURED_NOT_VERIFIED"
    # subscription handshake
    ok = client.get("/webhooks/meta-messaging", params={"hub.mode": "subscribe", "hub.verify_token": "vt-1",
                                                        "hub.challenge": "c123"})
    assert ok.status_code == 200 and ok.text == "c123"
    assert client.get("/webhooks/meta-messaging", params={"hub.mode": "subscribe", "hub.verify_token": "x",
                                                          "hub.challenge": "c"}).status_code == 403
    raw, headers = _signed(_dm("555", "delivery time?"))
    assert client.post("/webhooks/meta-messaging", content=raw,
                       headers=dict(headers, **{"X-Hub-Signature-256": "sha256=bad"})).status_code == 403
    # no Page token yet -> nothing sent
    assert client.post("/webhooks/meta-messaging", content=raw, headers=headers).json()["handled"] == 1
    assert http.calls == []
    assert client.put("/admin/cc/social-dm/token", json={"channel": "facebook", "account_id": "555",
                                                          "token": "PAGE-TOKEN-x"}, headers=OWNER).json()["token_set"]
    assert "PAGE-TOKEN-x" not in client.get("/admin/cc/social-dm", headers=OWNER).text
    http.responses["/me/messages"] = (200, {"message_id": "mid.1"})
    client.post("/webhooks/meta-messaging", content=raw, headers=headers)
    call = http.calls[-1]
    assert call["headers"]["Authorization"] == "Bearer PAGE-TOKEN-x"
    assert call["json"]["recipient"] == {"id": "cust-1"} and call["json"]["messaging_type"] == "RESPONSE"
    # echoes of the page's own messages are ignored
    echo = _dm("555", "delivery")
    echo["entry"][0]["messaging"][0]["message"]["is_echo"] = True
    assert social_dm.parse_inbound(echo) == []


def test_rule_without_the_channel_does_not_answer_social_dms(api):
    client, container, _ = api
    pf = _pf(container)
    biz = "app-biz-" + uuid.uuid4().hex[:6]
    _, acct = _business(pf, biz, page="777", channels=("askodox_chat",))
    pf.resources.action("social_dm_accounts", acct["id"], "activate", actor="t")
    r = client.post("/admin/cc/social-dm/simulate", json={"channel": "facebook", "account_id": "777",
                                                           "text": "delivery?"}, headers=OWNER).json()
    assert r["results"][0]["status"] == "no_rule"


def test_sigv4_is_deterministic_and_well_formed():
    now = datetime(2026, 10, 4, 12, 0, tzinfo=timezone.utc)
    a = marketplace_api.sigv4_headers(access_key="AKIDEXAMPLE", secret_key="s", body=b"{}", now=now)
    b = marketplace_api.sigv4_headers(access_key="AKIDEXAMPLE", secret_key="s", body=b"{}", now=now)
    assert a == b and a["x-amz-date"] == "20261004T120000Z"
    assert a["Authorization"].startswith("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261004/eu-west-1/"
                                         "ProductAdvertisingAPI/aws4_request, SignedHeaders=content-encoding;"
                                         "content-type;host;x-amz-date;x-amz-target, Signature=")
    assert marketplace_api.sigv4_headers(access_key="AKIDEXAMPLE", secret_key="t", body=b"{}", now=now) != a


def _product(store, platform="amazon", pid="B0TEST1234"):
    return store.create({"title": "Phone holder", "original_product_url": f"https://www.{platform}.in/dp/{pid}",
                         "platform": platform, "product_id": pid, "price": 500, "mrp": 800}, actor="t")


def test_marketplace_api_status_mock_preview_and_real_refresh(api):
    client, container, http = api
    pf = _pf(container)
    store = container.affiliate_catalog
    items = client.get("/admin/cc/marketplace-apis", headers=OWNER).json()["items"]
    assert {k: v["status"] for k, v in items.items()} == {
        "amazon": "EXTERNAL_SETUP_REQUIRED", "flipkart": "EXTERNAL_SETUP_REQUIRED", "meesho": "NOT_AVAILABLE"}
    item = _product(store)
    r = client.post(f"/admin/cc/affiliate-products/{item['id']}/api-refresh", headers=OWNER).json()
    assert r["ok"] is False and r["applied"] is False and http.calls == []
    # mock mode: a preview, never written
    pf.registry.configure("amazon_associates", actor="t", enabled=True, mode="mock")
    r = client.post(f"/admin/cc/affiliate-products/{item['id']}/api-refresh", headers=OWNER).json()
    assert r["mock"] and r["applied"] is False and http.calls == []
    assert store.get(item["id"])["price"] == 500
    # real (test) mode with a recorded PA-API answer
    pf.registry.configure("amazon_associates", actor="t", enabled=True, mode="test",
                          config={"access_key": "AKIDEXAMPLE", "partner_tag": "askodox-21"},
                          secrets={"secret_key": "s3cret"})
    http.responses["paapi5/getitems"] = (200, {"ItemsResult": {"Items": [{
        "ASIN": "B0TEST1234", "DetailPageURL": "https://www.amazon.in/dp/B0TEST1234",
        "ItemInfo": {"Title": {"DisplayValue": "Phone holder"}},
        "Offers": {"Listings": [{"Price": {"Amount": 449.0}, "SavingBasis": {"Amount": 799.0},
                                 "Availability": {"Type": "Now"}}]}}]}})
    r = client.post(f"/admin/cc/affiliate-products/{item['id']}/api-refresh", headers=OWNER).json()
    assert r["applied"] is True and r["status"] == "CONFIGURED_NOT_VERIFIED"
    row = store.get(item["id"])
    assert row["price"] == 449.0 and row["mrp"] == 799.0 and row["stock_status"] == "IN_STOCK"
    assert any(h["check_source"] == "api" for h in store.history(item["id"]))
    call = http.calls[-1]
    assert call["headers"]["x-amz-target"].endswith("GetItems") and b"askodox-21" in call["content"]
    assert "s3cret" not in json.dumps(call["headers"])


def test_flipkart_lookup_and_meesho_has_no_api(api):
    _, container, http = api
    pf = _pf(container)
    pf.registry.configure("flipkart_affiliate", actor="t", enabled=True, mode="test",
                          config={"affiliate_id": "askodox"}, secrets={"token": "fk-token"})
    http.responses["product.json"] = (200, {"productBaseInfoV1": {
        "title": "Holder", "flipkartSpecialPrice": {"amount": 299}, "maximumRetailPrice": {"amount": 599},
        "inStock": False, "productUrl": "https://www.flipkart.com/x/p/itm1", "imageUrls": {"400x400": "https://i/1"}}})
    r = marketplace_api.lookup(pf.registry, http, "flipkart", "MOBX1")
    assert r["ok"] and r["fields"]["price"] == 299 and r["fields"]["stock"] == "OUT_OF_STOCK"
    assert http.calls[-1]["headers"]["Fk-Affiliate-Token"] == "fk-token"
    assert marketplace_api.lookup(pf.registry, http, "meesho", "1")["status"] == "NOT_AVAILABLE"
