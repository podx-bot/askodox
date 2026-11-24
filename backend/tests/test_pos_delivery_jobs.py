"""Delivery jobs for a shop's own people (owner plan 2026-11-24, step 1) + owner-UPI collect (step 2): one line -> job
card with the shop order number, ask the free people, answers, give / first 'now' by itself, colours by the person,
money cash / owner UPI (one-paise rule, both told), day report per person."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_delivery_jobs import PosDeliveryJobs, parse_line
from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000701"
RAVI = "app-phone-9400000702"
SURESH = "app-phone-9400000703"
STRANGER = "app-phone-9400000709"
T0 = datetime(2026, 12, 1, 6, 30, tzinfo=timezone.utc)  # 12:00 IST


class _Maps:
    enabled = True

    def __init__(self):
        self.calls = 0

    def geocode(self, q):
        self.calls += 1
        return {"latitude": 16.36, "longitude": 80.84, "name": q}

    def compute_route(self, points):
        self.calls += 1
        return {"distance_km": 7.4, "duration_minutes": 18}


class _Methods:
    def default_for(self, *a, **k):
        return None


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    pushes = []
    notify = lambda u, t, b, r, k, *rest: pushes.append((u, t, b, r, k))  # noqa: E731
    shop = store.create_business(OWNER, {"name": "Sai Bakery", "state_code": "37"})["id"]
    store.set_member(shop, OWNER, "9400000702", "delivery", label="Ravi")
    store.set_member(shop, OWNER, "9400000703", "delivery", label="Suresh")
    alerts = PosPaymentAlerts(store, notify=notify)
    maps = _Maps()
    jobs = PosDeliveryJobs(store, notify=notify, maps=maps, collect=alerts, clock=lambda: now[0])
    return store, jobs, alerts, shop, pushes, now, maps


def test_one_line_becomes_a_job_card():
    assert parse_line("ఉయ్యూరు నుంచి పారం కి కేక్ ఒకటి డెలివరీ, 250 రూపాయలు ఇస్తారు") == {
        "from": "ఉయ్యూరు", "to": "పారం", "item": "కేక్ ఒకటి", "fee_paise": 0, "collect_paise": 25000, "missing": []}
    english = parse_line("from Vuyyuru to Param one cake delivery, collect Rs 250, delivery charge 40 rupees")
    assert (english["from"], english["to"], english["fee_paise"], english["collect_paise"]) == ("Vuyyuru", "Param", 4000, 25000)
    hindi = parse_line("Vuyyuru se Param tak 2 packet delivery, 300 rupaye lena, delivery boy ki 50 rupaye")
    assert (hindi["to"], hindi["fee_paise"], hindi["collect_paise"]) == ("Param", 5000, 30000)
    only_to = parse_line("గుడివాడ కి 2 బిర్యానీ పార్సిల్, 1,200 రూపాయలు")
    assert only_to["from"] == "" and only_to["to"] == "గుడివాడ" and only_to["collect_paise"] == 120000
    assert parse_line("hello")["missing"] == ["to"]


def test_route_is_asked_once_per_pair(env):
    _, jobs, _, shop, _, _, maps = env
    first = jobs.draft(shop, OWNER, "ఉయ్యూరు నుంచి పారం కి కేక్ డెలివరీ")
    assert (first["km"], first["minutes"], first["cached"]) == (7.4, 18, False)
    calls = maps.calls
    again = jobs.draft(shop, OWNER, "ఉయ్యూరు నుంచి పారం కి కేక్ డెలివరీ")
    assert again["cached"] is True and maps.calls == calls


def test_ask_free_people_answers_give_and_colours(env):
    store, jobs, _, shop, pushes, now, _ = env
    with pytest.raises(PosError) as nobody:
        jobs.create(shop, OWNER, {"from": "Uyyuru", "to": "Param", "collect_paise": 25000})
    assert nobody.value.code == "nobody"  # nobody set green yet
    jobs.set_status(RAVI, "free")
    jobs.set_status(SURESH, "free")
    people = jobs.people(shop, OWNER)["people"]
    assert [p["colour"] for p in people[:2]] == ["free", "free"] and people[-1]["role"] == "owner"
    job = jobs.create(shop, OWNER, {"from": "Uyyuru", "to": "Param", "item": "cake", "fee_paise": 4000,
                                    "collect_paise": 25000})
    assert job["order_no"] == 1 and job["label"] == "#1" and job["status"] == "asking"
    assert {p[0] for p in pushes[-2:]} == {RAVI, SURESH}
    offer = jobs.mine(RAVI)["offers"][0]
    assert offer["label"] == "#1" and "asks" not in offer, "a person never sees the others' answers"
    jobs.answer(SURESH, job["id"], "10")
    jobs.answer(RAVI, job["id"], "now")
    answers = {a["label"]: a["answer"] for a in jobs.job(shop, OWNER, job["id"])["asks"]}
    assert answers == {"Ravi": "now", "Suresh": "10"}
    with pytest.raises(PosError):
        jobs.answer(STRANGER, job["id"], "now")
    given = jobs.give(shop, OWNER, job["id"], RAVI)
    assert given["status"] == "given" and given["assignee_label"] == "Ravi"
    assert jobs.my_status(RAVI)["colour"] == "busy", "accepting a job turns the person orange"
    with pytest.raises(PosError):
        jobs.give(shop, OWNER, job["id"], SURESH)
    jobs.step(RAVI, job["id"], "picked")
    with pytest.raises(PosError) as money:
        jobs.step(RAVI, job["id"], "done")
    assert money.value.code == "money"
    done = jobs.step(RAVI, job["id"], "done", "cash")
    assert done["status"] == "done" and jobs.my_status(RAVI)["colour"] == "free"
    assert any("క్యాష్ Ravi దగ్గర" in p[2] for p in pushes if p[0] == OWNER)
    report = jobs.day(shop, OWNER)["people"][0]
    assert (report["label"], report["cash_paise"], report["orders"]) == ("Ravi", 25000, ["#1"])
    assert jobs.mine(RAVI)["cash_today"][0]["paise"] == 25000


def test_first_now_gets_it_by_itself(env):
    _, jobs, _, shop, _, _, _ = env
    job = jobs.create(shop, OWNER, {"to": "Gudivada", "ask": [RAVI, SURESH], "auto_first": True})
    assert job["from"] == "Sai Bakery", "no 'from' = the shop itself"
    jobs.answer(SURESH, job["id"], "now")
    after = jobs.job(shop, OWNER, job["id"])
    assert after["status"] == "given" and after["assignee_user"] == SURESH
    with pytest.raises(PosError):
        jobs.answer(RAVI, job["id"], "now")


def test_grey_after_three_hours_and_red_at_night(env):
    _, jobs, _, _, _, now, _ = env
    jobs.set_status(RAVI, "free")
    now[0] = T0 + timedelta(hours=3, minutes=1)
    assert jobs.my_status(RAVI)["colour"] == "unknown"
    jobs.set_status(RAVI, "free")
    now[0] = datetime(2026, 12, 1, 17, 40, tzinfo=timezone.utc)  # 23:10 IST
    assert jobs.my_status(RAVI)["colour"] == "off"
    jobs.set_status(RAVI, "free")  # set again after 23:00 -> stays what the person said
    assert jobs.my_status(RAVI)["colour"] == "free"


def test_owner_upi_collect_one_paise_rule_and_both_told(env):
    store, jobs, alerts, shop, pushes, _, _ = env
    with store._tx() as conn:  # the owner's own UPI (normally from Profile -> Payment methods)
        conn.execute("INSERT INTO pos_collect_settings (business_id, method_id, updated_by, updated_at) VALUES (?,?,?,?)",
                     (shop, "m1", OWNER, T0.isoformat()))
    alerts._collect_method = lambda conn, biz: {"upi_id": "sai@okhdfcbank", "payee_name": "Sai Bakery"}
    a = jobs.create(shop, OWNER, {"to": "Param", "collect_paise": 25000, "ask": [RAVI]})
    b = jobs.create(shop, OWNER, {"to": "Gudivada", "collect_paise": 25000, "ask": [SURESH]})
    jobs.give(shop, OWNER, a["id"], RAVI)
    jobs.give(shop, OWNER, b["id"], SURESH)
    qr_a = jobs.collect_upi(RAVI, a["id"])
    qr_b = jobs.collect_upi(SURESH, b["id"])
    assert qr_a["amount_paise"] == 25000 and qr_a["label"].startswith("#")
    assert qr_b["amount_paise"] == 25001 and qr_b["paise_added"] == 1, "same amount open -> the later one +1 paise"
    assert "sai@okhdfcbank" in qr_a["upi_link"]
    assert jobs.collect_upi(RAVI, a["id"])["id"] == qr_a["id"], "the same open QR again, never a second one"
    with store._tx() as conn:
        alerts._match_request(conn, shop, "ppe_x", 25001)
    told = [p for p in pushes if "వచ్చింది" in p[1]]
    assert {p[0] for p in told} == {SURESH, OWNER} and "250.01" in told[0][1]
