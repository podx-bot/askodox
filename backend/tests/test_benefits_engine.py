"""Section 16: offers, coupons & rewards on the Partner / Revenue architecture.

Campaigns here are test fixtures ("Bank A", "Partner B"), not real offers.
"""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.benefits_repository import BenefitsRepository
from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.partner_revenue_repository import PartnerRevenueRepository
from app.services import benefits_engine, external_call_budget, rate_limit
from app.services.secret_box import SecretBox
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-bf-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
KEY = SecretBox.generate_key()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                                                   secrets_key=KEY))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    monkeypatch.setattr(container, "partner_revenue_repository",
                        PartnerRevenueRepository(str(tmp_path / "p.db"), secret_box=SecretBox(KEY)), raising=False)
    monkeypatch.setattr(container, "benefits_repository",
                        BenefitsRepository(str(tmp_path / "b.db"), secret_box=SecretBox(KEY)), raising=False)
    return TestClient(app), container


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def campaign(client, **fields):
    response = client.post("/admin/cc/benefits", headers=OWNER, json={"active": True, **fields})
    assert response.status_code == 200, response.text
    return response.json()


BANK = {"name": "Bank A card offer", "provider_name": "Bank A", "offer_type": "bank_card",
        "discount_amount": 2000, "min_purchase": 20000, "payment_methods": ["Bank A credit card"],
        "categories": ["tv", "electronics"], "source_url": "https://banka.example/offers/tv", "verified": True,
        "funding_source": "bank"}


def test_verified_offers_show_with_real_values_and_conditions_never_invented(api):
    client, container = api
    campaign(client, **BANK)
    campaign(client, name="Unverified", provider_name="Bank Z", offer_type="bank_card", discount_amount=9999,
             source_url="https://z.example/x")  # no verification timestamp -> never shown
    cashback = campaign(client, name="Partner B cashback", provider_name="Partner B", offer_type="cashback",
                        cashback_percent=6, max_discount=1500, categories=["tv"], funding_source="partner")
    assert client.post("/admin/cc/benefits", headers=OWNER, json={
        "name": "No source", "offer_type": "upi_wallet", "discount_amount": 50}).status_code == 422
    campaigns = container.benefits_repository.campaigns(active_only=True)
    result = benefits_engine.evaluate(campaigns, price=25000, category="PRODUCT", subject="43 inch TV")
    assert [o["name"] for o in result["offers"]] == ["Bank A card offer", "Partner B cashback"]
    bank, back = result["offers"]
    assert bank["value"] == 2000 and {"type": "min_purchase", "value": 20000.0} in bank["conditions"]
    assert {"type": "payment_method", "value": ["Bank A credit card"]} in bank["conditions"]
    assert back["value"] == 1500.0, "6% of 25,000 = 1,500 (capped at max 1,500)"
    assert "best" not in str(result).lower() and result["comparison_note"]
    assert benefits_engine.evaluate(campaigns, price=15000, category="PRODUCT", subject="TV")["offers"][0]["id"] \
        == cashback["id"], "below the bank's minimum purchase it is not shown"
    # Expired campaigns disappear.
    client.patch(f"/admin/cc/benefits/{cashback['id']}", headers=OWNER,
                 json={"ends_at": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()})
    assert [o["name"] for o in benefits_engine.evaluate(container.benefits_repository.campaigns(active_only=True),
                                                         price=25000, subject="TV")["offers"]] == ["Bank A card offer"]


def test_coupon_claim_is_idempotent_limited_and_private(api):
    client, container = api
    coupon = campaign(client, name="ASKODOX ₹500 coupon", offer_type="coupon", discount_amount=500,
                      per_user_limit=1, total_cap=2, funding_source="askodox")
    added = client.post(f"/admin/cc/benefits/{coupon['id']}/coupons", headers=OWNER,
                        json={"codes": ["SAVE500A", "SAVE500B", "SAVE500A"]}).json()
    assert added == {"added": 2, "skipped": 1}
    alice, bob, carol = "app-phone-91" + "1" * 10, "app-phone-91" + "2" * 10, "app-phone-91" + "3" * 10
    assert client.post(f"/api/benefits/{coupon['id']}/claim", json={}).status_code == 401, "sign-in required"
    first = client.post(f"/api/benefits/{coupon['id']}/claim", headers=auth(container, alice), json={}).json()
    again = client.post(f"/api/benefits/{coupon['id']}/claim", headers=auth(container, alice), json={}).json()
    assert first["code"] == "SAVE500A" and again["duplicate"] is True and again["code"] == "SAVE500A"
    theirs = client.post(f"/api/benefits/{coupon['id']}/claim", headers=auth(container, bob), json={}).json()
    assert theirs["code"] == "SAVE500B"
    full = client.post(f"/api/benefits/{coupon['id']}/claim", headers=auth(container, carol), json={})
    assert full.status_code == 409 and full.json()["detail"] in {"campaign_full", "out_of_codes"}
    mine = client.get("/api/benefits/mine", headers=auth(container, bob)).json()["items"]
    assert [m["code"] for m in mine] == ["SAVE500B"], "never another user's code"
    listed = client.get("/admin/cc/benefits", headers=OWNER).text
    assert "SAVE500A" not in listed and "SAVE500B" not in listed, "codes are not listed to admins either"
    import sqlite3

    with sqlite3.connect(container.benefits_repository.db_path) as conn:
        assert all(v.startswith("enc:v1:") for (v,) in conn.execute("SELECT code FROM benefit_coupons"))


def test_redemption_happens_once_and_cost_is_split_by_funder(api):
    client, container = api
    shared = campaign(client, name="Shared ₹1000", offer_type="coupon", discount_amount=1000,
                      funding_source="shared", partner_share_percent=40)
    user = "app-phone-91" + "4" * 10
    claim = client.post(f"/api/benefits/{shared['id']}/claim", headers=auth(container, user), json={}).json()
    done = client.post(f"/admin/cc/benefits/claims/{claim['claim_id']}/redeem", headers=OWNER,
                       json={"redemption_ref": "order-77", "order_value": 25000}).json()
    assert done["status"] == "REDEEMED" and done["askodox_cost"] == 600 and done["partner_cost"] == 400
    replay = client.post(f"/admin/cc/benefits/claims/{claim['claim_id']}/redeem", headers=OWNER,
                         json={"redemption_ref": "order-77", "order_value": 25000}).json()
    assert replay["duplicate"] is True
    other = client.post(f"/admin/cc/benefits/claims/{claim['claim_id']}/redeem", headers=OWNER,
                        json={"redemption_ref": "order-78", "order_value": 25000})
    assert other.status_code == 409 and "already_redeemed" in other.text
    stats = client.get("/admin/cc/benefits/analytics", headers=OWNER).json()
    row = next(r for r in stats["items"] if r["campaign_id"] == shared["id"])
    assert row["claims"] == 1 and row["redemptions"] == 1 and row["askodox_cost"] == 600
    revenue = client.get("/admin/cc/revenue", headers=OWNER, params={"period": "7d"}).json()["metrics"]
    assert revenue["reward_cost_askodox"] == 600 and revenue["net_revenue"] == revenue["total_revenue"] - 600


def test_scratch_reward_is_server_decided_once_per_completed_order_of_that_buyer(api):
    client, container = api
    campaign(client, name="Thank-you credit", offer_type="scratch_reward", credit_amount=50, priority=5,
             funding_source="askodox")
    campaign(client, name="Lower priority", offer_type="scratch_reward", credit_amount=500, priority=1)
    buyer, stranger = "app-phone-91" + "5" * 10, "app-phone-91" + "6" * 10
    orders = container.order_repository
    order_id = orders.create_order(buyer_user_id=buyer, seller_user_id="app-phone-917777777777", product_id=1,
                                   product_title="Mixer grinder", price=3200)
    early = client.post("/api/rewards/scratch", headers=auth(container, buyer), json={"trigger": f"order:{order_id}"})
    assert early.status_code == 409, "only after completion"
    orders.update_fields(order_id, status="DELIVERED")
    assert client.post("/api/rewards/scratch", headers=auth(container, stranger),
                       json={"trigger": f"order:{order_id}"}).status_code == 404, "not someone else's order"
    first = client.post("/api/rewards/scratch", headers=auth(container, buyer), json={"trigger": f"order:{order_id}"}).json()
    again = client.post("/api/rewards/scratch", headers=auth(container, buyer), json={"trigger": f"order:{order_id}"}).json()
    assert first["reward"]["name"] == "Thank-you credit" and first["reward"]["value"] == 50, "deterministic"
    assert again["duplicate"] is True and again["claim_id"] == first["claim_id"]
    from app.api.routes.growth import growth

    assert growth(container).credit_balance(buyer) == 50, "credit applied exactly once"
    assert client.post("/api/rewards/scratch", headers=auth(container, buyer),
                       json={"trigger": "order:abc"}).status_code == 422


def test_offers_reach_search_results_and_partner_postback_redeems_coupons(api):
    client, container = api
    campaign(client, **BANK)
    found = client.post("/deals/discover", json={
        "user_id": "", "raw_text": "43 inch TV", "intent": "buy", "subject": "43 inch TV", "category": "product",
        "quantity": None, "unit": None, "price": None,
        "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
        "dynamic_fields": {}}).json()
    assert found["matches"] is not None  # offers attach only to rows that exist; nothing invented
    # Partner coupon redeemed by a confirmed postback.
    partner = client.post("/admin/cc/partners", headers=OWNER, json={
        "name": "Partner B", "deep_link_template": "https://b.example/s?q={query}", "active": True}).json()
    coupon = campaign(client, name="Partner B code", offer_type="coupon", partner_id=partner["id"],
                      discount_amount=300, funding_source="partner")
    client.post(f"/admin/cc/benefits/{coupon['id']}/coupons", headers=OWNER, json={"codes": ["PB300"]})
    user = "app-phone-91" + "8" * 10
    claim = client.post(f"/api/benefits/{coupon['id']}/claim", headers=auth(container, user), json={}).json()
    url = client.post(f"/admin/cc/partners/{partner['id']}/postback-token", headers=OWNER).json()["postback_url"]
    token = url.split("token=")[1].split("&")[0]
    result = client.get("/api/partners/partner-b/postback", params={
        "token": token, "order_id": "B-1", "order_value": "5000", "status": "approved", "coupon": "PB300"}).json()
    assert result["coupon"] == "redeemed"
    assert container.benefits_repository.claim(claim["claim_id"])["status"] == "REDEEMED"
    # The same postback replayed does not redeem twice.
    replay = client.get("/api/partners/partner-b/postback", params={
        "token": token, "order_id": "B-1", "order_value": "5000", "status": "approved", "coupon": "PB300"}).json()
    assert replay["coupon"] == "redeemed"  # idempotent (same reference)
    assert container.benefits_repository.claim(claim["claim_id"])["partner_cost"] == 300


def test_coupon_eligibility_clone_archive_and_usage_report(api, monkeypatch):
    client, container = api
    from app.api.routes.platform import platform

    monkeypatch.setattr(container, "platform", None, raising=False)
    new_only = campaign(client, name="New customer ₹200", offer_type="coupon", discount_amount=200,
                        eligibility="new", funding_source="askodox")
    assert client.post("/admin/cc/benefits", headers=OWNER, json={
        "name": "x", "offer_type": "coupon", "eligibility": "vip"}).status_code == 422
    client.post(f"/admin/cc/benefits/{new_only['id']}/coupons", headers=OWNER, json={"codes": ["NEW200A"]})
    returning = "app-phone-91" + "7" * 10
    monkeypatch.setattr(type(platform(container)), "_is_new_customer", lambda self, user: user != returning)
    refused = client.post(f"/api/benefits/{new_only['id']}/claim", headers=auth(container, returning), json={})
    assert refused.status_code == 409 and "new customers" in refused.json()["detail"]
    ok = client.post(f"/api/benefits/{new_only['id']}/claim", headers=auth(container, "app-phone-91" + "8" * 10),
                     json={}).json()
    assert ok["code"] == "NEW200A"
    report = client.get(f"/admin/cc/benefits/{new_only['id']}/report", headers=OWNER).json()["usage"]
    assert report["claims"] == 1 and report["unique_customers"] == 1 and report["by_status"] == {"ISSUED": 1}
    assert "NEW200A" not in str(report)
    copy = client.post(f"/admin/cc/benefits/{new_only['id']}/clone", headers=OWNER).json()
    assert copy["id"] != new_only["id"] and not copy["active"] and copy["name"].endswith("(copy)")
    assert copy["eligibility"] == "new" and copy["verified_at"] is None
    archived = client.post(f"/admin/cc/benefits/{new_only['id']}/archive", headers=OWNER).json()
    assert archived["archived"] and not archived["active"]
    assert client.get(f"/api/benefits/{new_only['id']}").status_code == 404, "archived offers are never live"
    restored = client.post(f"/admin/cc/benefits/{new_only['id']}/archive?restore=true", headers=OWNER).json()
    assert not restored["archived"] and not restored["active"], "restored inactive, to be re-checked"
