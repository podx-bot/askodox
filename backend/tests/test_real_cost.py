"""Real cost of a choice (owner 2026-11-26): near vs far, pickup vs delivery -- one total per option."""
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes.real_cost import router
from app.services import real_cost as rc
from app.services import universal_ai_assistant_service as svc


def tv(far_price=9500, near_price=10000, km=40, people=2, meals=4, extras=300, mode="bike"):
    return [
        {"label": "Uyyuru", "price": near_price, "one_way_km": 0, "mode": "none"},
        {"label": "Vijayawada", "price": far_price, "one_way_km": km, "mode": mode, "people": people,
         "meals": meals, "extras": extras},
    ]


def test_owner_tv_example_the_500_saving_is_gone_after_the_trip():
    out = rc.compare(tv())
    far = [r for r in out["options"] if r["label"] == "Vijayawada"][0]
    assert far["trip_km"] == 80.0
    assert far["travel"] == pytest.approx(80 / 45 * 105, abs=0.02)          # petrol
    assert far["meals"] == 480.0                                               # 4 meals
    assert far["extra_on_top"] == pytest.approx(far["travel"] + 480 + 300, abs=0.02)
    assert out["best"] == "Uyyuru" and out["money_decides"] is True
    assert out["sticker_winner_differs"] is True                               # 9,500 looked cheaper
    assert out["saves_vs_next"] == pytest.approx(966.67 - 500, abs=0.05)   # the trip costs ~Rs 967, the saving was Rs 500


def test_break_even_is_the_extra_the_trip_adds():
    out = rc.compare(tv())
    far = [r for r in out["options"] if r["label"] == "Vijayawada"][0]
    assert far["break_even_discount"] == far["extra_on_top"]
    near = [r for r in out["options"] if r["label"] == "Uyyuru"][0]
    assert near["break_even_discount"] == 0.0


def test_a_big_enough_saving_makes_the_far_shop_win():
    out = rc.compare(tv(far_price=7000))
    assert out["best"] == "Vijayawada" and out["saves_vs_next"] > 1000


def test_pickup_against_delivery_against_a_better_place():
    out = rc.compare([
        {"label": "pickup", "price": 200, "one_way_km": 3, "mode": "bike"},
        {"label": "delivered", "price": 200, "delivery_fee": 20},
        {"label": "better place", "price": 250, "delivery_fee": 0, "one_way_km": 6, "mode": "bike"},
    ])
    totals = {r["label"]: r["total"] for r in out["options"]}
    assert totals["delivered"] == 220.0
    assert totals["pickup"] == pytest.approx(200 + 6 / 45 * 105, abs=0.02)
    assert out["best"] == "pickup"          # 214 < 220 < ~264
    # delivery beats the trip when the trip is dearer than the fee
    far = rc.compare([{"label": "pickup", "price": 200, "one_way_km": 12, "mode": "car"},
                      {"label": "delivered", "price": 200, "delivery_fee": 20}])
    assert far["best"] == "delivered"


def test_a_near_tie_says_money_does_not_decide():
    out = rc.compare([{"label": "a", "price": 1000}, {"label": "b", "price": 1020}])
    assert out["money_decides"] is False
    assert "equal" in rc.summary(out)
    assert "సమానం" in rc.summary(out, te=True)


def test_the_persons_own_numbers_override_and_time_can_be_priced():
    base = rc.compare(tv())
    cheap_fuel = rc.compare(tv(), {"petrol_per_litre": 50})
    assert cheap_fuel["assumed"]["petrol_per_litre"] == 50
    a = [r for r in base["options"] if r["label"] == "Vijayawada"][0]["travel"]
    b = [r for r in cheap_fuel["options"] if r["label"] == "Vijayawada"][0]["travel"]
    assert b < a
    priced = rc.compare(tv(), {"time_value_per_hour": 100})
    assert [r for r in priced["options"] if r["label"] == "Vijayawada"][0]["time_value"] > 0
    assert [r for r in base["options"] if r["label"] == "Vijayawada"][0]["time_value"] == 0   # time shown, never priced


def test_bus_fare_counts_every_person_and_one_way_trips_work():
    two = rc.compare([{"label": "near", "price": 100}, {"label": "far", "price": 90, "one_way_km": 10, "mode": "bus",
                                                         "people": 2, "round_trip": False}])
    far = [r for r in two["options"] if r["label"] == "far"][0]
    assert far["travel"] == 10 * 2.0 * 2 and far["trip_km"] == 10.0


@pytest.mark.parametrize("bad", [
    [{"price": 1}],                                   # one option
    [{"price": -1}, {"price": 2}],                    # negative
    [{"price": "x"}, {"price": 2}],                   # not a number
    [{"price": 1, "mode": "rocket"}, {"price": 2}],   # unknown mode
    [{"price": 1, "one_way_km": 99999}, {"price": 2}],
])
def test_bad_input_is_refused(bad):
    with pytest.raises(rc.RealCostError):
        rc.compare(bad)


def test_route_answers_in_telugu_and_refuses_bad_input():
    app = FastAPI()
    app.include_router(router)
    client = TestClient(app)
    ok = client.post("/api/real-cost/compare", json={"options": tv(), "language": "te"})
    assert ok.status_code == 200
    body = ok.json()
    assert body["best"] == "Uyyuru" and body["estimate"] is True and "బెటర్" in body["summary"]
    bad = client.post("/api/real-cost/compare", json={"options": [{"price": -5}, {"price": 1}]})
    assert bad.status_code == 422


def test_brain_rule_names_the_total_and_uses_the_same_numbers():
    rule = svc.FRIEND_REASONING_RULES
    for must in ("The real cost of going", "ONE total", "break-even", "about 3 percent",
                 "never invent a price", "estimates the person can change"):
        assert must in rule, must
    assert rc.assumption_sentence() in rule
    lowered = rule.lower()
    for banned in ("stove", "burner", "saree", "fridge", "phone", "meesho", "amazon", "gold", "jewel", "ghost"):
        assert banned not in lowered, banned
