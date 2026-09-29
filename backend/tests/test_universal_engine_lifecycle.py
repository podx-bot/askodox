"""Universal ASKODOX engine: any category from the app's structured
requirement -> saved request -> need-aware multi-source results -> mediated
seller Q&A/negotiation -> request -> accept/decline (+alternatives) ->
truthful payment state -> product/service execution -> customer confirmation
-> dispute via Customer Care -> resolution -> review -> close.

Fixture sellers/listings here are test data, not production results.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import deal_lifecycle as lc
from app.services.session_tokens import issue_token
from app.services.universal_multi_source_result_service import (
    UniversalMultiSourceResultService,
    need_kind,
)


@pytest.fixture()
def api():
    from server import app, container

    return TestClient(app), container


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def phone():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def app_deal(client, container, user, subject, category="product", intent="buy", raw=None, **extra):
    """Exactly the shape the Flutter app sends (universal_match_repository._payload)."""
    body = {
        "user_id": user, "raw_text": raw or subject, "intent": intent, "subject": subject,
        "category": category, "quantity": None, "unit": None, "price": None,
        "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
        "dynamic_fields": {}, **extra,
    }
    return client.post("/deals", json=body, headers=auth(container, user))


# ----------------------------------------------------- request persistence --

@pytest.mark.parametrize("subject,category,intent,raw", [
    ("43 inch portable battery TV", "product", "buy", "I want a 43 inch portable battery TV, budget 20000 to 30000"),
    ("AC installation", "service", "needService", "I need AC installation at home"),
    ("plumber", "service", "needService", "I need a plumber"),
    ("used bike", "product", "buy", "I want a used bike"),
    ("43 ఇంచ్ టీవీ", "product", "buy", "నాకు 43 ఇంచ్ టీవీ కావాలి"),
    ("aquarium cleaning", "service", "needService", "someone to clean my aquarium"),  # unseen category
])
def test_any_structured_app_requirement_is_saved_and_searchable(api, subject, category, intent, raw):
    client, container = api
    user = phone()
    created = app_deal(client, container, user, subject, category, intent, raw)
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["subject"] == subject and body["side"] == "NEED"
    assert body["domain"] == ("SERVICES" if category == "service" else "PRODUCT")
    matches = client.get(f"/deals/{body['deal_id']}/matches", headers=auth(container, user))
    assert matches.status_code == 200 and "source_status" in matches.json()


def test_follow_up_answers_update_the_same_request_and_demand_signal_fires(api, monkeypatch):
    client, container = api
    dispatched = []
    live = container.universal_live_capture_service
    monkeypatch.setattr(live, "_trigger_demand_intelligence", lambda stored: dispatched.append(stored["id"]))
    user = phone()
    first = app_deal(client, container, user, "washing machine repair", "service", "needService").json()
    second = app_deal(client, container, user, "washing machine repair", "service", "needService",
                      timing="tomorrow 10 am", price=800).json()
    assert second["deal_id"] == first["deal_id"], "answers refine the same requirement, no duplicate"
    assert dispatched == [first["deal_id"], first["deal_id"]], "existing demand-intelligence targeting is signalled"


def test_registered_service_provider_is_found_for_a_service_need(api):
    client, container = api
    provider = phone()
    title = f"AC installation {uuid.uuid4().hex[:5]}"
    client.post("/api/products/mine", headers=auth(container, provider),
                json={"seller_user_id": provider, "subject": title, "price": 1500, "unit": "per visit",
                      "location_label": "Vijayawada"})
    user = phone()
    deal = app_deal(client, container, user, title, "service", "needService").json()
    body = client.get(f"/deals/{deal['deal_id']}/matches", headers=auth(container, user)).json()
    assert any(m["match_source"] == "registered" and title in m["title"] for m in body["matches"])
    assert body["source_status"]["used_deals"] == "not_applicable"
    assert body["source_status"]["videos"] == "not_applicable"
    assert provider[-10:] not in str(body), "provider contact hidden before acceptance"


# ------------------------------------------------------- source selection --

class _Web:
    configured = True

    def __init__(self):
        self.queries = []

    def __call__(self, query, limit):
        self.queries.append(query)
        return [{"title": "Portable battery TV 43 inch sale offer", "url": "https://shop.example/tv?ref=a",
                 "snippet": "43 inch portable battery TV offer ₹24,999"}]

    def videos(self, query, limit):
        return []


class _Maps:
    enabled = True

    def __init__(self):
        self.queries = []

    def search_places(self, query, **kw):
        self.queries.append(query)
        return []


def test_sources_follow_the_kind_of_need_not_the_category_name():
    assert need_kind({"domain": "PRODUCT"}) == "product"
    assert need_kind({"domain": "SERVICES"}) == "service"
    assert need_kind({"domain": "JOBS"}) == "party"
    web, maps = _Web(), _Maps()
    svc = UniversalMultiSourceResultService(catalog=None, ranking=None, seller_profiles=None, maps=maps, web_search=web)
    svc.collect({"subject": "yoga teacher", "domain": "SERVICES", "location_text": "Guntur", "latitude": 16.3, "longitude": 80.4})
    # Discovery asks for videos only when the customer asked for them.
    svc.online_and_videos(category="SERVICES", subject="yoga teacher", include_online=True, location_text="Guntur",
                          include_videos=False)
    # Nothing nearby: the SAME need is searched in widening scopes
    # (nearby -> city -> region -> state), never a different query.
    assert maps.queries == ["yoga teacher service near Guntur"] * 4
    assert svc.scope["level"] == "state" and svc.scope["expanded"] is True
    assert web.queries == ["yoga teacher service in Guntur book"], "no used/surplus/deals/video queries for a service"
    status = svc.source_status()
    assert status["used_deals"] == status["videos"] == "not_applicable"
    # "yoga teacher videos": a service need may show how-to / review videos.
    asked = UniversalMultiSourceResultService(catalog=None, ranking=None, seller_profiles=None, maps=_Maps(),
                                              web_search=_Web())
    asked.collect({"subject": "yoga teacher", "domain": "SERVICES", "location_text": "Guntur"})
    asked.online_and_videos(category="SERVICES", subject="yoga teacher", include_online=False,
                            location_text="Guntur", include_videos=True)
    assert asked.source_status()["videos"] != "not_applicable"

    party = UniversalMultiSourceResultService(catalog=None, ranking=None, seller_profiles=None, maps=_Maps(), web_search=_Web())
    party.collect({"subject": "delivery job", "domain": "JOBS"})
    assert set(k for k, v in party.source_status().items() if v == "not_applicable") >= {"nearby", "online", "used_deals"}


# ------------------------------------------------------------- lifecycle --

def listing(client, container, subject, **extra):
    seller = phone()
    body = client.post("/api/products/mine", headers=auth(container, seller),
                       json={"seller_user_id": seller, "subject": subject, "price": 25000, **extra}).json()
    return seller, body["id"]


def place(client, container, buyer, product_id, **extra):
    r = client.post("/api/orders", headers=auth(container, buyer),
                    json={"buyer_user_id": buyer, "product_id": product_id, "quantity": 1, **extra})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def detail(client, container, user, order_id):
    return client.get(f"/api/orders/{order_id}", headers=auth(container, user)).json()


def seller_status(client, container, seller, order_id, status):
    return client.post(f"/api/orders/{order_id}/status", headers=auth(container, seller),
                       json={"seller_user_id": seller, "status": status})


def test_product_deal_full_lifecycle_with_mediated_negotiation(api):
    client, container = api
    seller, pid = listing(client, container, "43 inch battery TV")
    buyer = phone()
    oid = place(client, container, buyer, pid, question="Is it in stock?",
                request_context={"subject": "43 inch portable battery TV", "budget": "20000-30000", "deal_id": "77"})

    d = detail(client, container, buyer, oid)
    assert d["awaiting"] == "seller" and d["messages"][0]["kind"] == "QUESTION"
    assert d["request_context"]["budget"] == "20000-30000", "seller sees the requirement; nobody retypes it"
    assert seller[-10:] not in str(d), "contact hidden before acceptance"

    # Seller answers and counters through ASKODOX; buyer offers; seller accepts buyer's offer.
    client.post(f"/api/orders/{oid}/messages", headers=auth(container, seller), json={"kind": "ANSWER", "text": "Yes, 2 in stock"})
    client.post(f"/api/orders/{oid}/messages", headers=auth(container, buyer), json={"kind": "OFFER", "amount": 24000})
    assert client.post(f"/api/orders/{oid}/messages", headers=auth(container, buyer),
                       json={"kind": "ACCEPT_OFFER"}).status_code == 409, "cannot accept your own offer"
    client.post(f"/api/orders/{oid}/messages", headers=auth(container, seller), json={"kind": "COUNTER_OFFER", "amount": 25000})
    assert "accept_offer" in detail(client, container, buyer, oid)["actions"]
    d = client.post(f"/api/orders/{oid}/messages", headers=auth(container, buyer), json={"kind": "ACCEPT_OFFER"}).json()
    assert d["price"] == 25000 and d["total_amount"] == 25000

    # Forward-only transitions; accept unlocks contact + payment.
    assert seller_status(client, container, seller, oid, "DELIVERED").status_code == 409
    seller_status(client, container, seller, oid, "ACCEPTED")
    d = detail(client, container, buyer, oid)
    assert d["payment_state"] == "AWAITING_PAYMENT" and d["seller_user_id"].endswith(seller[-10:])
    assert client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer)).status_code == 409, \
        "cannot close before delivery"

    # Payment: buyer submits UTR, only the seller (or staff) can verify.
    client.post(f"/api/orders/{oid}/payment", headers=auth(container, buyer), json={"action": "submit_reference", "reference": "UTR123456789"})
    assert detail(client, container, buyer, oid)["payment_state"] == "PROOF_SUBMITTED"
    client.post(f"/api/orders/{oid}/payment", headers=auth(container, seller), json={"action": "confirm_received"})
    assert detail(client, container, buyer, oid)["payment_state"] == "VERIFIED"

    for step in ("PREPARING", "DISPATCHED", "DELIVERED"):
        assert seller_status(client, container, seller, oid, step).status_code == 200
    d = detail(client, container, buyer, oid)
    assert d["status"] == "DELIVERED" and d["awaiting"] == "buyer" and "confirm_completion" in d["actions"]
    assert client.post(f"/api/orders/{oid}/review", headers=auth(container, buyer), json={"rating": 5}).status_code == 409

    closed = client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer)).json()
    assert closed["status"] == "CLOSED" and closed["closed_at"]
    assert client.post(f"/api/orders/{oid}/review", headers=auth(container, buyer),
                       json={"rating": 5, "text": "Genuine"}).json()["status"] == "RECORDED"
    assert container.universal_review_repository.summary_for_user(seller)["review_count"] == 1


def test_service_booking_uses_service_states_and_dispute_blocks_close_until_support_resolves(api, monkeypatch):
    client, container = api
    import dataclasses

    key = "cc-" + uuid.uuid4().hex
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    seller, pid = listing(client, container, "AC installation service", unit="per visit")
    buyer = phone()
    oid = place(client, container, buyer, pid, request_context={"subject": "AC installation", "date": "Sunday 10 am"})
    assert detail(client, container, buyer, oid)["kind"] == "service"
    seller_status(client, container, seller, oid, "ACCEPTED")
    assert seller_status(client, container, seller, oid, "DISPATCHED").status_code == 409, "no product states for services"
    for step in ("SCHEDULED", "ARRIVED", "SERVICE_COMPLETED"):
        assert seller_status(client, container, seller, oid, step).status_code == 200

    problem = client.post(f"/api/orders/{oid}/problem", headers=auth(container, buyer),
                          json={"issue": "Installation incomplete, water leaking", "category": "SERVICE",
                                "ai_attempts": ["Suggested checking drain pipe"]}).json()
    case_id = problem["support_case_id"]
    assert problem["status"] == "DISPUTED" and problem["awaiting"] == "support"
    assert client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer)).status_code == 409, \
        "a dispute prevents premature closure"

    admin = {"X-ASKODOX-Admin-Key": key}
    case = client.get(f"/admin/cc/escalations/{case_id}", headers=admin).json()
    ctx = case["context"]
    assert ctx["order_id"] == oid and ctx["requirement"]["date"] == "Sunday 10 am"
    assert ctx["actions_tried"] == ["Suggested checking drain pipe"] and ctx["problem"].startswith("Installation")
    assert buyer not in str(case), "customer identity masked for staff"
    notes = [n for n in client.get("/admin/cc/notifications", headers=admin).json()["items"]
             if n["event_key"] == f"dispute:order:{oid}"]
    assert len(notes) == 1

    client.patch(f"/admin/cc/escalations/{case_id}", headers=admin,
                 json={"status": "RESOLVED", "confirm": True, "resolution_note": "Provider revisited and fixed leak"})
    d = detail(client, container, buyer, oid)
    assert d["status"] == "RESOLVED" and d["awaiting"] == "buyer", "customer confirms after support resolution"
    assert client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer)).json()["status"] == "CLOSED"


def test_decline_keeps_the_need_and_offers_alternatives_without_starting_over(api):
    client, container = api
    subject = f"Mixer grinder {uuid.uuid4().hex[:5]}"
    seller, pid = listing(client, container, subject)
    other, other_pid = listing(client, container, subject)
    buyer = phone()
    oid = place(client, container, buyer, pid, request_context={"subject": subject})
    seller_status(client, container, seller, oid, "REJECTED")
    d = detail(client, container, buyer, oid)
    assert d["status"] == "REJECTED" and "see_alternatives" in d["actions"]
    assert seller[-10:] not in str(d), "a decline never reveals contact"
    alt = client.get(f"/api/orders/{oid}/alternatives", headers=auth(container, buyer)).json()
    ids = [m["id"] for m in alt["matches"]]
    assert str(other_pid) in ids and str(pid) not in ids and alt["subject"] == subject


def test_unresponsive_seller_and_payment_verification_by_staff(api, monkeypatch):
    client, container = api
    import dataclasses

    key = "cc-" + uuid.uuid4().hex
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    seller, pid = listing(client, container, "Study table")
    buyer = phone()
    oid = place(client, container, buyer, pid)
    stale = (datetime.now(timezone.utc) - timedelta(hours=30)).isoformat()
    container.order_repository.update_fields(oid)  # no-op guard
    with container.order_repository._connect() as conn:
        conn.execute("UPDATE orders SET updated_at=? WHERE id=?", (stale, oid))
    d = detail(client, container, buyer, oid)
    assert d["seller_unresponsive"] is True and "contact_support" in d["actions"]

    seller_status(client, container, seller, oid, "ACCEPTED")
    client.post(f"/api/orders/{oid}/payment", headers=auth(container, buyer), json={"action": "submit_reference", "reference": "UTR99887766"})
    admin = {"X-ASKODOX-Admin-Key": key}
    assert client.patch(f"/admin/cc/orders/{oid}/payment", headers=admin, json={"state": "VERIFIED", "reason": "x"}).status_code == 409
    assert client.patch(f"/admin/cc/orders/{oid}/payment", headers=admin,
                        json={"state": "VERIFIED", "confirm": True, "reason": "UTR matched statement"}).status_code == 200
    assert detail(client, container, buyer, oid)["payment_state"] == "VERIFIED"


def test_only_the_parties_can_see_or_act_and_buyer_cannot_use_seller_actions(api):
    client, container = api
    seller, pid = listing(client, container, "Bookshelf")
    buyer, stranger = phone(), phone()
    oid = place(client, container, buyer, pid)
    assert client.get(f"/api/orders/{oid}", headers=auth(container, stranger)).status_code == 404
    assert client.post(f"/api/orders/{oid}/messages", headers=auth(container, buyer),
                       json={"kind": "COUNTER_OFFER", "amount": 5}).status_code == 422
    assert client.post(f"/api/orders/{oid}/payment", headers=auth(container, buyer),
                       json={"action": "confirm_received"}).status_code == 422
    assert client.post(f"/api/orders/{oid}/cancel", headers=auth(container, buyer)).json()["status"] == "CANCELLED"


def test_lifecycle_rules_are_category_aware_and_forward_only():
    assert lc.seller_next("PLACED", "product") == ("ACCEPTED", "REJECTED")
    assert lc.check_seller_transition("ACCEPTED", "FULFILLED", "service") == "SERVICE_COMPLETED"
    assert lc.check_seller_transition("PREPARING", "DELIVERED", "product") == "DELIVERED"
    with pytest.raises(lc.LifecycleError):
        lc.check_seller_transition("DELIVERED", "PREPARING", "product")
    with pytest.raises(lc.LifecycleError):
        lc.check_customer_confirm("DISPUTED")
    assert "PLACED" not in lc.CONTACT_VISIBLE and "REJECTED" not in lc.CONTACT_VISIBLE


def test_customer_care_reply_returns_to_the_requester_only(api, monkeypatch):
    client, container = api
    import dataclasses

    key = "cc-" + uuid.uuid4().hex
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    user, other = phone(), phone()
    case_id = client.post("/api/in-app/support/escalate", headers=auth(container, user),
                          json={"issue": "I need human help with my booking"}).json()["case_id"]
    assert client.get(f"/api/in-app/support/cases/{case_id}", headers=auth(container, other)).status_code == 404
    assert client.get(f"/api/in-app/support/cases/{case_id}").status_code == 404, "guests cannot read cases"
    client.patch(f"/admin/cc/escalations/{case_id}", headers={"X-ASKODOX-Admin-Key": key},
                 json={"status": "RESOLVED", "confirm": True, "resolution_note": "Booking moved to Sunday 10 am"})
    status = client.get(f"/api/in-app/support/cases/{case_id}", headers=auth(container, user)).json()
    assert status["status"] == "RESOLVED" and status["resolution_note"] == "Booking moved to Sunday 10 am"
    assert "requester_user_id" not in status and "context" not in status
