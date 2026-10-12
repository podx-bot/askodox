"""Mobility on ONE engine: goods transport kinds, pricing models (estimate only
from a configured rule), multi-stop, and customer <-> partner bargaining where
nothing is booked until the other side accepts that exact amount."""
from app.services import delivery_jobs as dj
from tests.test_delivery_jobs import DROP, OWNER, PICKUP, _partner, _user, env  # noqa: F401

STOP = {"label": "Bus stand, Vuyyuru", "latitude": 16.368, "longitude": 80.847}


def test_pricing_models_only_from_configured_rules():
    assert dj.fare_quote({"pricing_model": "per_kg", "base_fare": 100, "per_kg": 5}, 3, weight_kg=200)["amount"] == 1100
    assert dj.fare_quote({"pricing_model": "per_kg", "base_fare": 100, "per_kg": 5}, 3) is None, "no weight, no guess"
    assert dj.fare_quote({"pricing_model": "per_hour", "base_fare": 0, "per_hour": 400}, 9, hours=3)["amount"] == 1200
    assert dj.fare_quote({"pricing_model": "per_stop", "base_fare": 50, "per_stop": 30}, 4, stops=2)["amount"] == 140
    assert dj.fare_quote({"pricing_model": "fixed", "fixed_fare": 999}, 40)["amount"] == 999
    assert dj.fare_quote({"pricing_model": "quotation", "base_fare": 100}, 5) is None, "partners quote"
    assert dj.fare_quote({"base_fare": 30, "per_km": 10, "per_stop": 20}, 2, stops=1)["amount"] == 70
    assert dj.fare_quote(None, 5) is None


def test_goods_job_with_stops_and_bargaining(env):  # noqa: F811
    client, container = env
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    cust_id, customer = _user(container)
    driver_id, driver = _user(container)
    _, stranger = _user(container)
    partner_id = _partner(client, container, driver_id, services=("goods_mini_truck",))
    job = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "goods_mini_truck", "pickup": PICKUP, "drop": DROP, "stops": [STOP],
        "details": {"weight_kg": 450, "dimensions": "2 x 1 x 1 m", "handling": "fragile"}}).json()
    assert job["status"] == "PARTNER_SEARCH" and job["details"]["stops"][0]["label"] == "Bus stand, Vuyyuru"
    direct = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "goods_mini_truck", "pickup": PICKUP, "drop": DROP}).json()
    assert job["distance_km"] >= direct["distance_km"], "distance goes through the stop"

    jid = job["id"]
    assert client.post(f"/api/delivery/jobs/{jid}/bids/accept", headers=customer,
                       json={"partner_id": partner_id}).status_code == 409, "nothing to accept yet"
    quoted = client.post(f"/api/delivery/jobs/{jid}/bids/partner", headers=driver, json={"amount": 1500}).json()
    assert quoted["status"] == "PARTNER_SEARCH" and quoted["bids"][0]["by"] == "partner"
    assert "actor" not in quoted["bids"][0], "who typed an offer (a phone-bearing id) is never shown"
    assert client.post(f"/api/delivery/jobs/{jid}/bids/partner", headers=stranger, json={"amount": 1}).status_code == 403
    countered = client.post(f"/api/delivery/jobs/{jid}/bids", headers=customer,
                            json={"partner_id": partner_id, "amount": 1300, "note": "regular customer"}).json()
    assert [b["amount"] for b in countered["bids"]] == [1500, 1300] and countered["status"] == "PARTNER_SEARCH"
    assert client.post(f"/api/delivery/jobs/{jid}/bids/accept", headers=customer,
                       json={"partner_id": partner_id}).status_code == 409, "cannot accept your own offer"
    booked = client.post(f"/api/delivery/jobs/{jid}/bids/partner/accept", headers=driver).json()
    assert booked["status"] == "PARTNER_ACCEPTED" and booked["agreed_fare"] == 1300
    assert "Agreed fare ₹1300" in booked["history"][-1]["note"]
    mine = client.get(f"/api/delivery/jobs/{jid}", headers=customer).json()
    assert mine["partner"]["phone"], "contact shared only after the agreed booking"
    assert client.post(f"/api/delivery/jobs/{jid}/bids", headers=customer,
                       json={"partner_id": partner_id, "amount": 1}).status_code == 409, "closed after booking"


def test_customer_accepts_a_partner_quote(env):  # noqa: F811
    client, container = env
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    _, customer = _user(container)
    driver_id, driver = _user(container)
    partner_id = _partner(client, container, driver_id, services=("packers_movers",))
    jid = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "packers_movers", "pickup": PICKUP, "drop": DROP}).json()["id"]
    client.post(f"/api/delivery/jobs/{jid}/bids/partner", headers=driver, json={"amount": 6000})
    booked = client.post(f"/api/delivery/jobs/{jid}/bids/accept", headers=customer, json={"partner_id": partner_id}).json()
    assert booked["status"] == "PARTNER_ACCEPTED" and booked["agreed_fare"] == 6000
    assert client.get("/api/delivery/jobs/assigned", headers=driver).json()["active"][0]["id"] == jid
