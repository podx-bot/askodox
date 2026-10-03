"""Growth + intelligence engines (Master Fix Ticket engines 3, 5/10, 8,
13-18, 20). Every assertion is on a real backend record or response --
fixtures here are test data, not production results.
"""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.growth_repository import GrowthRepository
from app.services import domain_adapters, external_call_budget, offers_engine, rate_limit
from app.services.advisory_service import advise
from app.services.session_tokens import issue_token
from app.services.universal_category_schema import UniversalCategorySchemaRegistry

OWNER_KEY = "owner-growth-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture(autouse=True)
def _fresh_limits():
    rate_limit.reset_for_tests()
    external_call_budget.reset_for_tests()
    yield
    rate_limit.reset_for_tests()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    monkeypatch.setattr(container, "growth_repository", GrowthRepository(str(tmp_path / "growth.db")), raising=False)
    return TestClient(app), container


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def phone():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def listing(client, container, subject="43 inch TV", price=25000, **extra):
    seller = phone()
    r = client.post("/api/products/mine", headers=auth(container, seller),
                    json={"seller_user_id": seller, "subject": subject, "price": price, **extra})
    assert r.status_code == 200, r.text
    return seller, r.json()["id"]


def place(client, container, buyer, pid, **extra):
    r = client.post("/api/orders", headers=auth(container, buyer),
                    json={"buyer_user_id": buyer, "product_id": pid, "quantity": 1, **extra})
    assert r.status_code == 200, r.text
    return r.json()


def seller_status(client, container, seller, oid, status):
    return client.post(f"/api/orders/{oid}/status", headers=auth(container, seller),
                       json={"seller_user_id": seller, "status": status})


# ------------------------------------------------------------ offers engine --

def test_offer_rules_are_configurable_not_hard_coded():
    ctx = {"unit_price": 1000, "quantity": 2}
    assert offers_engine.evaluate({"rule_type": "percent", "params": {"percent": 10, "max_discount": 150}}, ctx)["discount"] == 150
    assert offers_engine.evaluate({"rule_type": "fixed", "params": {"amount": 300}}, ctx)["discount"] == 300
    assert offers_engine.evaluate({"rule_type": "buy_x_get_y", "params": {"buy": 1, "get": 1}}, ctx)["discount"] == 1000
    assert offers_engine.evaluate({"rule_type": "buy_x_get_y", "params": {"buy": 2, "get": 1}}, ctx) is None
    assert offers_engine.evaluate({"rule_type": "quantity", "params": {"min_qty": 5, "percent": 8}}, ctx) is None
    assert offers_engine.evaluate({"rule_type": "first_order", "params": {"amount": 100}}, {**ctx, "prior_orders": 1}) is None
    assert offers_engine.evaluate({"rule_type": "repeat_customer", "params": {"percent": 5}}, {**ctx, "prior_orders": 2})["discount"] == 100
    assert offers_engine.evaluate({"rule_type": "referral", "params": {"amount": 50}}, ctx) is None
    assert offers_engine.evaluate({"rule_type": "free_delivery", "params": {}}, ctx)["free_delivery"] is True
    assert offers_engine.evaluate({"rule_type": "percent", "params": {"percent": 10, "min_order": 5000}}, ctx) is None
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    assert offers_engine.evaluate({"rule_type": "festival", "params": {"percent": 20}, "ends_at": past}, ctx) is None
    assert offers_engine.evaluate({"rule_type": "fixed", "params": {"amount": 99999}}, ctx)["discount"] == 2000, \
        "a discount never exceeds the order"
    for bad in [("percent", {"percent": 95}), ("buy_x_get_y", {"buy": 1}), ("mystery", {})]:
        with pytest.raises(offers_engine.OfferError):
            offers_engine.validate(*bad)


def test_seller_offer_applies_to_a_real_order_and_only_on_own_listing(api):
    client, container = api
    seller, pid = listing(client, container, price=20000)
    other, _ = listing(client, container, subject="fridge")
    bad = client.post("/api/offers", headers=auth(container, other),
                      json={"rule_type": "percent", "params": {"percent": 10}, "scope": "listing", "scope_value": str(pid)})
    assert bad.status_code == 403
    ok = client.post("/api/offers", headers=auth(container, seller),
                     json={"rule_type": "percent", "params": {"percent": 10}, "title": "Diwali 10%",
                           "scope": "listing", "scope_value": str(pid)})
    assert ok.status_code == 200, ok.text
    public = client.get(f"/api/offers/listing/{pid}").json()
    assert public["best"]["discount"] == 2000
    order = place(client, container, phone(), pid)
    assert order["discount"] == 2000 and order["total_amount"] == 18000
    assert order["offer"]["title"] == "Diwali 10%"
    # Admin campaign competes; the single best offer wins (no stacking).
    client.post("/admin/cc/growth/offers", headers=OWNER,
                json={"rule_type": "fixed", "params": {"amount": 3000}, "title": "Festival ₹3000"})
    assert place(client, container, phone(), pid)["discount"] == 3000


# ---------------------------------------------- attribution + reward ledger --

def test_attribution_rewards_accrue_only_on_completion_and_need_admin_approval(api):
    client, container = api
    seller, pid = listing(client, container, price=10000)
    buyer, influencer = phone(), phone()
    client.put("/admin/cc/growth/reward-rules/influencer", headers=OWNER, json={"percent": 2, "amount": 50})
    order = place(client, container, buyer, pid,
                  attribution=[{"user_id": influencer, "role": "influencer"},
                               {"user_id": buyer, "role": "influencer"},          # self: ignored
                               {"user_id": phone(), "role": "president"}])         # unknown role: ignored
    oid = order["id"]
    detail = client.get(f"/api/orders/{oid}", headers=auth(container, buyer)).json()
    assert sorted(p["role"] for p in detail["participants"]) == ["buyer", "influencer", "seller"]
    assert client.get("/api/rewards/mine", headers=auth(container, influencer)).json()["items"] == []
    seller_status(client, container, seller, oid, "ACCEPTED")
    for step in ("PREPARING", "DISPATCHED", "DELIVERED"):
        seller_status(client, container, seller, oid, step)
    client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer))
    mine = client.get("/api/rewards/mine", headers=auth(container, influencer)).json()
    assert [(r["amount"], r["status"]) for r in mine["items"]] == [(250.0, "PENDING")]  # 2% of 10000 + 50
    rid = mine["items"][0]["id"]
    assert client.patch(f"/admin/cc/growth/rewards/{rid}", headers=OWNER, json={"status": "PAID"}).status_code == 409
    assert client.patch(f"/admin/cc/growth/rewards/{rid}", headers=OWNER, json={"status": "APPROVED"}).json()["status"] == "APPROVED"
    assert client.patch(f"/admin/cc/growth/rewards/{rid}", headers=OWNER, json={"status": "PAID"}).json()["status"] == "PAID"
    listed = client.get("/admin/cc/growth/rewards", headers=OWNER).json()["items"]
    assert influencer not in str(listed), "admin sees masked ids"


def test_cancelled_order_cancels_pending_rewards(api):
    client, container = api
    seller, pid = listing(client, container, price=5000)
    buyer, agent = phone(), phone()
    order = place(client, container, buyer, pid, attribution=[{"user_id": agent, "role": "agent"}])
    repo = container.growth_repository
    repo.set_reward_rule("agent", percent=5, amount=None)
    repo.accrue_rewards("order", order["id"], 5000)  # as if completed
    client.post(f"/api/orders/{order['id']}/cancel", headers=auth(container, buyer))
    assert [r["status"] for r in repo.rewards(user_id=agent)] == ["CANCELLED"]


# ---------------------------------------------------------------- referrals --

def test_refer_to_askodox_code_registers_the_invitee_and_credits_the_referrer(api):
    client, container = api
    customer, provider = phone(), phone()
    ref = client.post("/api/referrals", headers=auth(container, customer),
                      json={"invitee_name": "Ravi AC works", "category": "AC repair", "area": "Vijayawada"}).json()
    assert ref["code"].startswith("ASK") and "AC repair in Vijayawada" in ref["share_text"]
    assert client.post(f"/api/referrals/{ref['code']}/redeem", headers=auth(container, customer)).status_code == 404
    assert client.post(f"/api/referrals/{ref['code']}/redeem", headers=auth(container, provider)).json()["status"] == "REGISTERED"
    assert client.post(f"/api/referrals/{ref['code']}/redeem", headers=auth(container, phone())).status_code == 404
    mine = client.get("/api/referrals/mine", headers=auth(container, customer)).json()["items"]
    assert mine[0]["status"] == "REGISTERED"
    admin = client.get("/admin/cc/growth/referrals", headers=OWNER).json()["items"]
    assert customer not in str(admin) and provider not in str(admin)


def test_referral_fraud_safeguards(api, monkeypatch):
    client, container = api
    from app.api.routes import platform as platform_routes

    alice, bob, carol = phone(), phone(), phone()
    code = lambda who: client.post("/api/referrals", headers=auth(container, who), json={}).json()["code"]
    assert client.post(f"/api/referrals/{code(alice)}/redeem", headers=auth(container, bob)).status_code == 200
    # Bob was already credited to Alice: another code cannot re-credit him.
    assert client.post(f"/api/referrals/{code(carol)}/redeem", headers=auth(container, bob)).status_code == 404
    # Circular: Alice cannot be "registered" through Bob, whom she referred.
    assert client.post(f"/api/referrals/{code(bob)}/redeem", headers=auth(container, alice)).status_code == 404
    # A referrer blocked in the Command Center earns nothing.
    blocked_code = code(carol)
    with monkeypatch.context() as patch:
        patch.setattr(platform_routes, "is_blocked_user", lambda c, user: user == carol)
        assert client.post(f"/api/referrals/{blocked_code}/redeem",
                           headers=auth(container, phone())).status_code == 404
    # Daily invite cap.
    spammer = phone()
    from app.api.routes.growth import growth

    for _ in range(growth(container).REFERRALS_PER_DAY):
        client.post("/api/referrals", headers=auth(container, spammer), json={})
    assert client.post("/api/referrals", headers=auth(container, spammer), json={}).status_code == 429
    # Bursts of registrations are flagged for admin review (not auto-blocked).
    burst = phone()
    for _ in range(growth(container).REVIEW_REGISTRATIONS_PER_DAY + 1):
        client.post(f"/api/referrals/{code(burst)}/redeem", headers=auth(container, phone()))
    listing = client.get("/admin/cc/growth/referrals", headers=OWNER)
    assert listing.status_code == 200, listing.text
    admin = listing.json()["items"]
    assert any(i["review"] for i in admin) and burst not in str(admin)


# ---------------------------------------------------- plans / subscriptions --

def test_plans_are_admin_configured_and_paid_plans_are_never_faked_active(api):
    client, container = api
    assert client.put("/admin/cc/growth/plans/seller-free", json={"name": "Free"}).status_code == 401
    client.put("/admin/cc/growth/plans/seller-free", headers=OWNER,
               json={"name": "Seller Free", "audience": "seller", "credits": 20, "entitlements": {"listings": 5}})
    client.put("/admin/cc/growth/plans/seller-pro", headers=OWNER,
               json={"name": "Seller Pro", "audience": "seller", "price": 299, "entitlements": {"listings": 100}})
    client.put("/admin/cc/growth/plans/seller-trial", headers=OWNER,
               json={"name": "Pro trial", "audience": "seller", "price": 299, "trial_days": 14})
    assert {p["code"] for p in client.get("/api/plans?audience=seller").json()["items"]} == \
        {"seller-free", "seller-pro", "seller-trial"}
    user = phone()
    free = client.post("/api/subscriptions", headers=auth(container, user), json={"plan_code": "seller-free"}).json()
    assert free["subscription"]["status"] == "ACTIVE"
    assert free["entitlements"]["entitlements"] == {"listings": 5} and free["entitlements"]["credits"] == 20
    paid = client.post("/api/subscriptions", headers=auth(container, user), json={"plan_code": "seller-pro"}).json()
    assert paid["subscription"]["status"] == "PENDING_PAYMENT" and "Payment is not available" in paid["note"]
    me = client.get("/api/subscriptions/me", headers=auth(container, user)).json()
    assert me["entitlements"] == {}, "no entitlements until paid"
    trial = client.post("/api/subscriptions", headers=auth(container, user), json={"plan_code": "seller-trial"}).json()
    assert trial["subscription"]["status"] == "TRIAL"
    grant = client.post("/admin/cc/growth/credits", headers=OWNER,
                        json={"user_id": user, "amount": 50, "reason": "joining bonus"}).json()
    assert grant["balance"] == 70


# ---------------------------------------------------------------- catalog AI --

def test_catalog_draft_from_photo_never_invents_fields_and_publishes_after_review(api):
    client, container = api
    seller = phone()
    photo = {"subject": "mixer grinder", "brand": "Preethi", "domain": "product",
             "visual_summary": "A white 3-jar mixer grinder", "constraints": ["color:white"]}
    draft = client.post("/api/catalog/drafts", headers=auth(container, seller), json={"image_analysis": photo}).json()
    d = draft["draft"]
    assert d["title"] == "Preethi mixer grinder" and d["description"] == "A white 3-jar mixer grinder"
    assert d["price"] is None and "price" in draft["missing"] and "stock_status" in draft["missing"]
    assert d["attributes"] == {"brand": "Preethi", "color": "white"}
    assert client.post(f"/api/catalog/drafts/{draft['id']}/publish", headers=auth(container, phone()),
                       json={"price": 3200}).status_code == 404
    pub = client.post(f"/api/catalog/drafts/{draft['id']}/publish", headers=auth(container, seller),
                      json={"price": 3200, "stock_status": "IN_STOCK", "location_label": "Vijayawada"}).json()
    listed = container.product_catalog_repository.get(pub["listing_id"])
    assert listed["price"] == 3200 and "mixer grinder" in listed["subject"]
    assert client.post(f"/api/catalog/drafts/{draft['id']}/publish", headers=auth(container, seller),
                       json={}).status_code == 409
    words = client.post("/api/catalog/drafts", headers=auth(container, seller),
                        json={"text": "I sell fresh country eggs ₹8 each"}).json()
    assert words["draft"]["price"] == 8 and "price" not in words["missing"]
    assert client.post("/api/catalog/drafts", headers=auth(container, seller), json={}).status_code == 422


# ------------------------------------------------- advisory + domain adapters --

def test_advice_is_contextual_short_and_never_constant():
    assert advise({"subject": "43 inch TV"}, [], need_kind="product") == []
    staff = advise({"subject": "catering staff", "quantity": 10}, [], need_kind="service")
    assert [a["code"] for a in staff] == ["backup_staff", "pay_on_completion"]
    health = advise({"subject": "severe chest pain doctor"}, [], need_kind="service")
    assert health[0]["code"] == "health_emergency" and "108" in health[0]["text"]
    assert "cardiologist" in health[1]["text"] and "can't diagnose" in health[1]["text"]
    used = advise({"subject": "used bike"}, [{"price": 30000, "price_verified": False}], need_kind="product")
    assert [a["code"] for a in used] == ["inspect_used", "verify_price"]
    spread = advise({"subject": "fridge"}, [{"price": 20000}, {"price": 30000}], need_kind="product")
    assert spread[0]["code"] == "price_spread"
    assert all(len(advise({"subject": s, "quantity": 20}, [], need_kind="service")) <= 2
               for s in ["catering staff", "used car", "tooth pain"])


def test_domain_adapters_configure_the_one_core():
    assert domain_adapters.detect("need a room for 2 nights in Guntur").key == "hotel"
    assert domain_adapters.detect("bridal makeup salon").key == "salon"
    assert domain_adapters.detect("10 catering staff tomorrow").key == "catering"
    assert domain_adapters.detect("43 inch TV") is None
    assert domain_adapters.search_query("toothache") == "dentist"
    assert domain_adapters.search_query("skin rash doctor") == "dermatologist"
    assert domain_adapters.search_query("haircut") == "haircut salon"
    assert UniversalCategorySchemaRegistry.resolve("HOTEL").required_fields == ("location", "check_in", "check_out", "guests")
    assert UniversalCategorySchemaRegistry.resolve("staffing").category == "CATERING"
    assert "people_count" in UniversalCategorySchemaRegistry.resolve("CATERING").required_fields


def test_results_carry_advice_next_actions_and_offer_badges(api):
    client, container = api
    # Nellore: keeps this fixture out of other tests' Vijayawada broadcasts.
    seller, pid = listing(client, container, subject="catering staff service", price=800,
                          location_label="Nellore")
    client.post("/api/offers", headers=auth(container, seller),
                json={"rule_type": "percent", "params": {"percent": 5}, "title": "5% for new customers"})
    body = {"user_id": "", "raw_text": "10 catering staff", "intent": "needWorker", "subject": "catering staff",
            "category": "service", "quantity": 10, "unit": None, "price": 800,
            "location": {"label": "Nellore", "latitude": 14.44, "longitude": 79.99, "radius_km": 5},
            "dynamic_fields": {}}
    data = client.post("/deals/discover", json=body).json()
    assert [a["code"] for a in data["advice"]][:1] == ["backup_staff"]
    registered = [m for m in data["matches"] if m.get("match_source") == "registered"]
    assert registered and registered[0]["offer"]["title"] == "5% for new customers"
    assert data["next_actions"] == []
    none = client.post("/deals/discover", json={**body, "subject": "zzqx unobtainium welder"}).json()
    assert "refer_provider" in none["next_actions"]


# ------------------------------------------------------ route / place / cost --

class _Maps:
    enabled = True
    last_error = False

    def compute_route(self, points):
        return {"distance_km": 12.5, "duration_minutes": 34}

    def search_places(self, query, **kw):
        return [{"name": "Benz Circle", "address": "Vijayawada", "latitude": 16.5, "longitude": 80.65, "place_id": "x"}]


def test_pickup_drop_route_quote_uses_real_distance_and_partner_rates_only(api, monkeypatch):
    client, container = api
    monkeypatch.setattr(container, "google_maps_service", _Maps())
    body = {"pickup": {"latitude": 16.50, "longitude": 80.64}, "drop": {"latitude": 16.52, "longitude": 80.62}}
    empty = client.post("/api/discover/route", json=body).json()
    assert empty["distance_km"] == 12.5 and empty["duration_minutes"] == 34
    assert empty["quotes"] == [] and "No registered delivery partner" in empty["quote_note"]
    listing(client, container, subject="parcel delivery bike", price=12, unit="per km")
    quoted = client.post("/api/discover/route", json=body).json()
    assert quoted["quotes"][0]["quote"] == 150 and quoted["quotes"][0]["rate_unit"] == "per km"
    places = client.get("/api/discover/places", params={"q": "Benz Circle"}).json()
    assert places["status"] == "ok" and places["items"][0]["latitude"] == 16.5


def test_public_endpoints_are_rate_limited(api):
    client, _ = api
    codes = [client.get("/api/discover/place", params={"latitude": 16.5, "longitude": 80.6}).status_code
             for _ in range(31)]
    assert codes[:30].count(429) == 0 and codes[30] == 429


def test_llm_extraction_is_cached_and_usage_is_costed(api, monkeypatch):
    client, container = api
    from app.services.universal_request_extractor import UniversalRequestExtractor

    calls = []

    class _Interactions:
        def create(self, **kw):
            calls.append(kw)
            return type("R", (), {"output_text": '{"side": "NEED", "subject": "tv", "domain": "PRODUCT"}'})()

    extractor = UniversalRequestExtractor(api_key="")
    extractor._client = type("C", (), {"interactions": _Interactions()})()
    first = extractor.extract("I want a TV")
    second = extractor.extract("I want a TV")
    assert first["success"] and second["success"] and len(calls) == 1
    usage = {row["provider"]: row for row in client.get("/admin/cc/api-usage", headers=OWNER).json()["items"]}
    assert usage["llm_extract"]["cache_hits"] >= 1 and "est_cost_inr" in usage["llm_extract"]


def test_admin_growth_views_need_permission(api):
    client, _ = api
    analyst = client.post("/admin/cc/staff", headers=OWNER, json={"name": "a", "role": "analyst"}).json()["token"]
    growth_mgr = client.post("/admin/cc/staff", headers=OWNER, json={"name": "g", "role": "growth_manager"}).json()["token"]
    for path in ("offers", "rewards", "referrals", "plans", "subscriptions", "catalog-drafts"):
        assert client.get(f"/admin/cc/growth/{path}", headers={"X-ASKODOX-Staff-Token": analyst}).status_code == 403
        assert client.get(f"/admin/cc/growth/{path}", headers={"X-ASKODOX-Staff-Token": growth_mgr}).status_code == 200
    assert client.get("/admin/cc/returns", headers=OWNER).status_code == 200
