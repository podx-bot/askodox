"""Canonical mobility system: rides, driver join + approval, driver
workspace, parcels, order fulfilment responsibility, carpool, reports,
Mobility Command Center. Nothing is 'confirmed' until a partner accepts and
contact details stay hidden until then."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import fulfillment
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-mob-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "m.db")),
                        raising=False)
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _town():
    """A unique spot per test so partners from other tests are out of range."""
    lat = 10 + (uuid.uuid4().int % 6000) / 1000
    lng = 75 + (uuid.uuid4().int % 6000) / 1000
    return {"label": "Pickup", "latitude": round(lat, 4), "longitude": round(lng, 4)}, \
        {"label": "Drop", "latitude": round(lat + 0.02, 4), "longitude": round(lng + 0.02, 4)}


def _driver(client, headers, at, services=("ride_auto",), approve=True):
    applied = client.post("/api/delivery/partners/apply", headers=headers, json={
        "name": "Ravi", "services": list(services), "vehicle": "three_wheeler", "vehicle_number": "ap16ab1234",
        "licence_last4": "4321", "town": "Vuyyuru", "radius_km": 5})
    assert applied.status_code == 200, applied.text
    body = applied.json()
    assert body["status"] == "PENDING_REVIEW" and body["available"] is False
    if approve:
        assert client.post(f"/admin/cc/platform/r/delivery_partners/{body['id']}/actions/approve", headers=OWNER,
                           json={}).status_code == 200
        on = client.post("/api/delivery/partners/me/availability", headers=headers,
                         json={"available": True, "latitude": at["latitude"], "longitude": at["longitude"]})
        assert on.status_code == 200 and on.json()["available"] is True, on.text
    return body["id"]


def test_driver_join_review_correction_and_online_rules(env):
    client, container = env
    pickup, _ = _town()
    uid, me = _user(container)
    pid = _driver(client, me, pickup, approve=False)
    assert client.post("/api/delivery/partners/apply", headers=me, json={
        "name": "Ravi", "services": ["ride_auto"], "vehicle": "car"}).status_code == 409, "one application each"
    refused = client.post("/api/delivery/partners/me/availability", headers=me,
                          json={"available": True, "latitude": 16.3, "longitude": 80.8})
    assert refused.status_code == 409, "cannot go online before approval"
    # staff ask for a correction -> the driver edits and resubmits
    assert client.post(f"/admin/cc/platform/r/delivery_partners/{pid}/actions/request_correction", headers=OWNER,
                       json={}).json()["status"] == "DRAFT"
    fixed = client.patch("/api/delivery/partners/me", headers=me, json={
        "name": "Ravi Kumar", "services": ["ride_auto", "parcel"], "vehicle": "three_wheeler",
        "licence_last4": "4321"})
    assert fixed.json()["status"] == "PENDING_REVIEW" and fixed.json()["name"] == "Ravi Kumar"
    assert client.post("/api/delivery/partners/apply", headers=me, json={
        "name": "X", "services": ["ride_auto"], "vehicle": "car", "licence_last4": "12345678"}).status_code == 422, \
        "only the last 4 licence digits are ever accepted"
    assert client.post(f"/admin/cc/platform/r/delivery_partners/{pid}/actions/approve", headers=OWNER,
                       json={}).status_code == 200
    assert client.post("/api/delivery/partners/me/availability", headers=me,
                       json={"available": True}).status_code == 422, "online needs a location"
    assert client.post(f"/admin/cc/platform/r/delivery_partners/{pid}/actions/disable", headers=OWNER,
                       json={"confirm": True}).json()["status"] == "DISABLED"
    assert client.get("/api/delivery/partners/me", headers=me).json()["partner"]["status"] == "DISABLED"
    assert client.post("/api/delivery/partners/apply", json={
        "name": "Anon", "services": ["parcel"], "vehicle": "car"}).status_code == 401


def test_ride_request_is_not_confirmed_until_a_driver_accepts_and_contact_stays_hidden(env):
    client, container = env
    pickup, drop = _town()
    cust_id, customer = _user(container)
    drv_id, driver = _user(container)
    _driver(client, driver, pickup)
    ride = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "ride_auto", "pickup": pickup, "drop": drop,
        "details": {"passengers": 2, "contact_phone": "+919000000001", "notes_private": "gate 2"}}).json()
    assert ride["status"] == "PARTNER_SEARCH" and ride["confirmed_by_partner"] is False
    assert "not confirmed" in ride["stage"].lower() or "waiting" in ride["stage"].lower()
    assert "partner" not in ride
    offer = client.get("/api/delivery/offers", headers=driver).json()["items"][0]
    assert offer["details"] == {"passengers": 2}, "private details stay hidden before acceptance"
    assert "requester" not in offer and "customer_phone" not in offer
    accepted = client.post(f"/api/delivery/jobs/{ride['id']}/accept", headers=driver).json()
    assert accepted["customer_phone"] == "+919000000001" and accepted["details"]["notes_private"] == "gate 2"
    mine = client.get(f"/api/delivery/jobs/{ride['id']}", headers=customer).json()
    assert mine["confirmed_by_partner"] is True
    assert mine["partner"]["vehicle_number"] == "AP16AB1234" and mine["partner"]["phone"].startswith("+91")
    for step in ("EN_ROUTE_PICKUP", "ARRIVED_PICKUP", "PICKED_UP", "IN_TRANSIT", "DELIVERED"):
        assert client.post(f"/api/delivery/jobs/{ride['id']}/status", headers=driver,
                           json={"status": step}).json()["status"] == step
    trips = client.get("/api/delivery/jobs/assigned", headers=driver).json()
    assert trips["active"] == [] and trips["history"][0]["id"] == ride["id"]
    assert client.post(f"/api/delivery/jobs/{ride['id']}/confirm", headers=customer).json()["status"] == "CONFIRMED"
    assert [j["id"] for j in client.get("/api/delivery/jobs/mine", headers=customer).json()["items"]] == [ride["id"]]


def test_decline_by_every_driver_is_no_driver_found_and_release_reoffers(env):
    client, container = env
    pickup, drop = _town()
    _, customer = _user(container)
    _, d1 = _user(container)
    _, d2 = _user(container)
    _driver(client, d1, pickup, services=("ride_bike",))
    _driver(client, d2, pickup, services=("ride_bike",))
    ride = client.post("/api/delivery/jobs", headers=customer,
                       json={"kind": "ride_bike", "pickup": pickup, "drop": drop}).json()
    assert len(ride["offered"]) == 2
    # d1 accepts then backs out before pickup -> offered again to d2 only
    assert client.post(f"/api/delivery/jobs/{ride['id']}/accept", headers=d1).status_code == 200
    assert client.post(f"/api/delivery/jobs/{ride['id']}/release", headers=d1, json={}).json()["released"]
    assert client.get("/api/delivery/offers", headers=d1).json()["items"] == []
    assert client.get(f"/api/delivery/jobs/{ride['id']}", headers=customer).json()["status"] == "PARTNER_SEARCH"
    assert client.post(f"/api/delivery/jobs/{ride['id']}/decline", headers=d2, json={}).json()["declined"]
    final = client.get(f"/api/delivery/jobs/{ride['id']}", headers=customer).json()
    assert final["status"] == "NEEDS_PARTNER" and "no driver" in final["stage"].lower()


def test_no_driver_nearby_is_honest_and_fare_only_from_configured_rate(env):
    client, container = env
    pickup, drop = _town()
    _, customer = _user(container)
    nobody = client.post("/api/delivery/jobs", headers=customer,
                         json={"kind": "ride_taxi", "pickup": pickup, "drop": drop}).json()
    assert nobody["status"] == "NEEDS_PARTNER" and nobody["quote"] is None, "no rate configured -> no estimate"
    rate = client.post("/admin/cc/platform/r/mobility_services", headers=OWNER, json={"data": {
        "name": "Taxi", "kind": "ride_taxi", "base_fare": 50, "per_km": 12, "minimum_fare": 80}})
    assert rate.status_code == 200, rate.text
    quoted = client.post("/api/delivery/jobs", headers=customer,
                         json={"kind": "ride_taxi", "pickup": pickup, "drop": drop}).json()
    assert quoted["quote"]["basis"] == "configured_rate" and quoted["quote"]["amount"] >= 80
    assert client.post(f"/admin/cc/platform/r/mobility_services/{rate.json()['id']}/actions/disable",
                       headers=OWNER, json={"confirm": True}).status_code == 200
    off = client.post("/api/delivery/jobs", headers=customer, json={"kind": "ride_taxi", "pickup": pickup, "drop": drop})
    assert off.status_code == 409 and off.json()["detail"]["code"] == "service_off"
    taxi = next(s for s in client.get("/api/delivery/services").json()["items"] if s["kind"] == "ride_taxi")
    assert taxi["offered"] is False


def test_typed_place_without_coordinates_is_geocoded_or_refused(env, monkeypatch):
    client, container = env
    _, customer = _user(container)

    class _Maps:
        enabled = True

        def geocode(self, text):
            return {"label": text + ", Vijayawada", "latitude": 16.5062, "longitude": 80.648}

    monkeypatch.setattr(container, "google_maps_service", _Maps())
    job = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "parcel", "pickup": {"label": "Benz Circle"}, "drop": {"label": "Bus stand",
                                                                       "latitude": 16.51, "longitude": 80.62}})
    assert job.status_code == 200 and job.json()["pickup"]["latitude"] == 16.5062

    class _Off:
        enabled = False

    monkeypatch.setattr(container, "google_maps_service", _Off())
    refused = client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "parcel", "pickup": {"label": "Benz Circle"}, "drop": {"label": "Home"}})
    assert refused.status_code == 422 and refused.json()["detail"]["code"] == "needs_location"


def test_parcel_recipient_contact_is_protected_until_acceptance(env):
    client, container = env
    pickup, drop = _town()
    _, sender = _user(container)
    _, rider = _user(container)
    _driver(client, rider, pickup, services=("parcel",))
    job = client.post("/api/delivery/jobs", headers=sender, json={
        "kind": "parcel", "pickup": pickup, "drop": drop,
        "details": {"item_description": "documents", "parcel_size": "small", "recipient_name": "Sita",
                    "recipient_phone": "+919000000002"}}).json()
    assert job["details"]["recipient_phone"] == "+919000000002", "the sender sees their own details"
    offer = client.get("/api/delivery/offers", headers=rider).json()["items"][0]
    assert "recipient_phone" not in offer["details"] and "recipient_name" not in offer["details"]
    assert offer["details"]["item_description"] == "documents"
    accepted = client.post(f"/api/delivery/jobs/{job['id']}/accept", headers=rider).json()
    assert accepted["details"]["recipient_phone"] == "+919000000002"


def _order(container, buyer, seller):
    return container.order_repository.create_order(buyer_user_id=buyer, seller_user_id=seller, product_id=1,
                                                   product_title="Rice 25 kg")


def test_fulfilment_responsibility_is_separate_from_the_order_state(env):
    client, container = env
    pickup, drop = _town()
    buyer_id, buyer = _user(container)
    seller_id, seller = _user(container)
    _, rider = _user(container)
    _, stranger = _user(container)
    oid = _order(container, buyer_id, seller_id)
    view = client.get(f"/api/delivery/orders/{oid}/fulfillment", headers=buyer).json()
    assert view["responsibility"] == "TO_BE_DECIDED" and view["delivery_status"] == "TO_BE_DECIDED"
    assert client.get(f"/api/delivery/orders/{oid}/fulfillment", headers=stranger).status_code == 404
    # a driver before the seller accepted is refused
    early = client.post(f"/api/delivery/orders/{oid}/fulfillment", headers=buyer,
                        json={"mode": "ASKODOX_NETWORK_DRIVER", "pickup": pickup, "drop": drop})
    assert early.status_code == 409
    container.order_repository.update_status(oid, "ACCEPTED")
    seller_mode = client.post(f"/api/delivery/orders/{oid}/fulfillment", headers=seller,
                              json={"mode": "SELLER_DELIVERY"}).json()
    assert seller_mode["commerce_status"] == "ACCEPTED" and seller_mode["delivery_status"] == "NOT_STARTED", \
        "the seller accepting the order is not a delivery confirmation"
    container.order_repository.update_status(oid, "DISPATCHED")
    assert client.get(f"/api/delivery/orders/{oid}/fulfillment", headers=buyer).json()["delivery_status"] == "IN_TRANSIT"
    pickup_mode = client.post(f"/api/delivery/orders/{oid}/fulfillment", headers=buyer,
                              json={"mode": "CUSTOMER_PICKUP"}).json()
    assert pickup_mode["delivery_status"] == "NOT_REQUIRED"

    oid2 = _order(container, buyer_id, seller_id)
    container.order_repository.update_status(oid2, "ACCEPTED")
    _driver(client, rider, pickup, services=("product",))
    net = client.post(f"/api/delivery/orders/{oid2}/fulfillment", headers=buyer,
                      json={"mode": "ASKODOX_NETWORK_DRIVER", "pickup": pickup, "drop": drop}).json()
    assert net["delivery_status"] == "OFFERED" and net["delivery_job"]["order_id"] == str(oid2)
    job_id = net["delivery_job"]["id"]
    assert client.post(f"/api/delivery/orders/{oid2}/fulfillment", headers=buyer, json={
        "mode": "ASKODOX_NETWORK_DRIVER", "pickup": pickup, "drop": drop}).status_code == 409, "one open request"
    client.post(f"/api/delivery/jobs/{job_id}/accept", headers=rider)
    assert client.get(f"/api/delivery/orders/{oid2}/fulfillment", headers=seller).json()["delivery_status"] == \
        "DRIVER_ACCEPTED"
    client.post(f"/api/delivery/jobs/{job_id}/status", headers=rider, json={"status": "PICKED_UP"})
    assert client.get(f"/api/delivery/orders/{oid2}/fulfillment", headers=buyer).json()["delivery_status"] == \
        "PICKED_UP"


def test_delivery_state_mapping_covers_every_responsibility():
    for mode in fulfillment.MODES:
        state = fulfillment.delivery_state(mode, "ACCEPTED")
        assert state in fulfillment.DELIVERY_STATES
        assert state not in ("DRIVER_ACCEPTED", "DELIVERED"), mode
    assert fulfillment.delivery_state("COURIER_PARCEL_PROVIDER", "CANCELLED") == "CANCELLED"
    assert fulfillment.delivery_state("ASKODOX_NETWORK_DRIVER", "ACCEPTED", {"status": "NEEDS_PARTNER"}) == \
        "NEEDS_DRIVER"


def test_carpool_offer_request_accept_contact_after_and_moderation(env):
    client, container = env
    origin, dest = _town()
    host_id, host = _user(container)
    rider_id, rider = _user(container)
    _, other = _user(container)
    ride = client.post("/api/delivery/carpool/rides", headers=host, json={
        "origin": origin, "dest": dest, "depart_at": "2026-10-10T08:00", "seats": 1, "contribution": 150}).json()
    assert "host" not in ride and "host_phone" not in ride and ride["mine"] is True
    found = client.get("/api/delivery/carpool/search", headers=rider, params={
        "from_lat": origin["latitude"], "from_lng": origin["longitude"], "to_lat": dest["latitude"],
        "to_lng": dest["longitude"], "date": "2026-10-10"}).json()["items"]
    assert [r["id"] for r in found] == [ride["id"]] and "host_phone" not in found[0]
    req = client.post(f"/api/delivery/carpool/rides/{ride['id']}/request", headers=rider, json={"seats": 1}).json()
    assert req["status"] == "REQUESTED"
    assert client.post(f"/api/delivery/carpool/rides/{ride['id']}/request", headers=host,
                       json={"seats": 1}).status_code == 422, "no booking your own ride"
    riding = client.get("/api/delivery/carpool/mine", headers=rider).json()["riding"][0]
    assert "host_phone" not in riding["ride"], "no contact before the host accepts"
    assert client.post(f"/api/delivery/carpool/requests/{req['id']}/decide", headers=other,
                       json={"accept": True}).status_code == 403
    decided = client.post(f"/api/delivery/carpool/requests/{req['id']}/decide", headers=host,
                          json={"accept": True}).json()
    assert decided["status"] == "ACCEPTED" and decided["passenger_phone"] == "+" + rider_id[len("app-phone-"):]
    riding = client.get("/api/delivery/carpool/mine", headers=rider).json()["riding"][0]
    assert riding["ride"]["host_phone"] == "+" + host_id[len("app-phone-"):]
    assert riding["ride"]["status"] == "FULL"
    rep = client.post("/api/delivery/reports", headers=rider, json={
        "subject_type": "carpool_ride", "subject_id": ride["id"], "reason": "driver was rude, call 9876543210"})
    assert rep.status_code == 200
    overview = client.get("/admin/cc/mobility/overview", headers=OWNER).json()
    stored = next(r for r in overview["reports"] if r["id"] == rep.json()["id"])
    assert "9876543210" not in stored["reason"], "phone numbers in reports are masked"
    assert client.post(f"/admin/cc/mobility/carpool/{ride['id']}", headers=OWNER,
                       json={"status": "HIDDEN"}).json()["status"] == "HIDDEN"
    assert client.post(f"/admin/cc/mobility/reports/{rep.json()['id']}", headers=OWNER,
                       json={"status": "RESOLVED"}).json()["status"] == "RESOLVED"


def test_mobility_command_center_is_privacy_safe_and_permissioned(env):
    client, container = env
    pickup, drop = _town()
    cust_id, customer = _user(container)
    client.post("/api/delivery/jobs", headers=customer, json={
        "kind": "ride_airport", "pickup": pickup, "drop": drop, "details": {"contact_phone": "+919000000003"}})
    assert client.get("/admin/cc/mobility/overview").status_code in (401, 403)
    body = client.get("/admin/cc/mobility/overview", headers=OWNER).json()
    text = str(body)
    assert cust_id not in text and "+919000000003" not in text
    assert body["analytics"]["by_kind"].get("ride_airport", 0) >= 1
    assert body["analytics"]["no_provider_found"] >= 1
    for area in body["analytics"]["unmet_by_area"]:
        lat, lng = area.split(",")
        assert len(lat.split(".")[-1]) <= 1, "areas are rounded (~10 km), never exact points"
