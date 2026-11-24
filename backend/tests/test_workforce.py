"""Workers under an authority (owner plan 2026-11-24, steps 3-6 + owner changes 11:17 / 11:40 / 11:49)."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services import workforce as wfm
from app.services.pos_delivery_jobs import PosDeliveryJobs
from app.services.pos_store import PosError, PosStore
from app.services.workforce import Workforce

OWNER = "app-phone-9400000801"
OWNER2 = "app-phone-9400000805"
LAXMI = "app-phone-9400000802"
RAJU = "app-phone-9400000803"
CUSTOMER = "app-phone-9400000804"
T0 = datetime(2026, 12, 1, 6, 30, tzinfo=timezone.utc)
GSTIN = "37AAAAA0000A1Z"


def _gstin():
    base = GSTIN
    chars = wfm._GST_CHARS
    total = 0
    for i, ch in enumerate(base):
        p = chars.index(ch) * (2 if i % 2 else 1)
        total += p // 36 + p % 36
    return base + chars[(36 - total % 36) % 36]


@pytest.fixture()
def env(tmp_path, monkeypatch):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    pushes = []
    notify = lambda u, t, b, r, k, *rest: pushes.append((u, t, b, r, k))  # noqa: E731
    shop = store.create_business(OWNER, {"name": "Sai Travels", "state_code": "37"})["id"]
    small = store.create_business(OWNER2, {"name": "Small Tiffin", "state_code": "37"})["id"]
    monkeypatch.setattr(Workforce, "_category", lambda self, conn, biz: "transport" if biz == shop else "food")
    jobs = PosDeliveryJobs(store, notify=notify, clock=lambda: now[0])
    wf = Workforce(store, notify=notify, clock=lambda: now[0])
    return store, wf, jobs, shop, small, pushes, now


def _worker(wf, user, name, types=("delivery", "car_driver"), **extra):
    return wf.save_worker(user, {"name": name, "work_types": list(types), "town": "Vuyyuru", "adult": True, **extra})


def test_gst_and_udyam_formats():
    assert wfm.gstin_ok(_gstin())
    assert not wfm.gstin_ok(GSTIN + ("0" if _gstin()[-1] != "0" else "1"))
    assert wfm.udyam_ok("UDYAM-AP-07-0012345") and not wfm.udyam_ok("UDYAM-AP-7-12345")


def test_worker_signup_needs_18_plus_and_a_work_type(env):
    _, wf, *_ = env
    with pytest.raises(PosError) as adult:
        wf.save_worker(LAXMI, {"name": "Laxmi", "work_types": ["delivery"]})
    assert adult.value.code == "adult"
    with pytest.raises(PosError):
        wf.save_worker(LAXMI, {"name": "Laxmi", "work_types": ["astronaut"], "adult": True})
    me = _worker(wf, LAXMI, "Laxmi")["worker"]
    assert me["name"] == "Laxmi" and "phone" not in me


def test_cards_only_for_gst_udyam_never_a_phone_invite_and_join(env):
    store, wf, jobs, shop, small, pushes, _ = env
    _worker(wf, LAXMI, "Laxmi")
    _worker(wf, RAJU, "Raju", types=("cook",))
    with pytest.raises(PosError) as gate:
        wf.cards(shop, OWNER)
    assert gate.value.code == "gate"
    wf.set_authority(small, OWNER2, {})  # no GST / Udyam = a small shop
    with pytest.raises(PosError):
        wf.cards(small, OWNER2)
    wf.set_authority(shop, OWNER, {"gstin": _gstin(), "address": "Main road, Vuyyuru", "prices": {"delivery": 5000}})
    cards = wf.cards(shop, OWNER)["cards"]
    assert [c["name"] for c in cards] == ["Laxmi"], "a travels business sees delivery / driver workers, not cooks"
    assert all("phone" not in c for c in cards)
    wf.invite(shop, OWNER, LAXMI, "licence")
    assert pushes[-1][0] == LAXMI and "licence" in pushes[-1][2]
    team = wf.authority(shop, OWNER)["team"]
    assert team[0]["status"] == "invited" and "phone" not in team[0]
    wf.answer_invite(LAXMI, shop, True)
    team = wf.authority(shop, OWNER)["team"]
    assert team[0]["phone"] == "9400000802", "the phone only after the worker joined"
    assert [c["key"] for c in team[0]["suggested_checks"]] == ["licence"]
    assert any(p["id"] == LAXMI for p in jobs.people(shop, OWNER)["people"]), "joined = can get step-1 jobs too"


def test_documents_open_only_with_the_workers_code_view_only(env):
    _, wf, _, shop, _, _, now = env
    _worker(wf, LAXMI, "Laxmi")
    wf.set_authority(shop, OWNER, {"udyam": "UDYAM-AP-07-0012345", "address": "Vuyyuru"})
    wf.invite(shop, OWNER, LAXMI)
    wf.answer_invite(LAXMI, shop, True)
    doc = wf.add_doc(LAXMI, "licence", b"\xff\xd8jpeg", "image/jpeg")
    with pytest.raises(PosError):
        wf.doc_image(shop, OWNER, LAXMI, doc["id"])
    code = wf.doc_code(LAXMI, shop)["code"]
    with pytest.raises(PosError):
        wf.open_docs(shop, OWNER, LAXMI, "000000" if code != "000000" else "111111")
    opened = wf.open_docs(shop, OWNER, LAXMI, code)
    assert opened["view_only"] and opened["docs"][0]["kind"] == "licence"
    assert wf.doc_image(shop, OWNER, LAXMI, doc["id"])[0] == b"\xff\xd8jpeg"
    with pytest.raises(PosError):
        wf.open_docs(shop, OWNER, LAXMI, code)  # one time only
    now[0] = T0 + timedelta(minutes=11)
    with pytest.raises(PosError):
        wf.doc_image(shop, OWNER, LAXMI, doc["id"])


def _team(wf, jobs, shop, *workers):
    wf.set_authority(shop, OWNER, {"gstin": _gstin(), "address": "Vuyyuru", "prices": {"delivery": 5000},
                                   "assigned_money": "upi"})
    for user, name in workers:
        _worker(wf, user, name)
        wf.invite(shop, OWNER, user)
        wf.answer_invite(user, shop, True)
        jobs.set_status(user, "free")


def test_customer_order_worker_takes_it_cash_authority_told(env):
    _, wf, jobs, shop, _, pushes, _ = env
    _team(wf, jobs, shop, (LAXMI, "Laxmi"), (RAJU, "Raju"))
    options = wf.authorities_for("delivery")["options"]
    assert options[0]["name"] == "Sai Travels" and options[0]["price_paise"] == 5000 and "phone" not in options[0]
    order = wf.place(CUSTOMER, {"work_type": "delivery", "business_id": shop, "place": "Param"})
    assert order["label"].startswith("#") and "worker_phone" not in order
    assert {LAXMI, RAJU} <= {p[0] for p in pushes if "ఒప్పుకుంటారా" in p[2]}
    taken = wf.worker_answer(LAXMI, order["id"], True)
    assert taken["money_mode"] == "cash" and taken["taken_by"] == "worker", "owner 11:17: self-taken = cash"
    assert any("Laxmi #" in p[1] and p[0] == OWNER for p in pushes), "the authority is told at once"
    seen = wf.order(CUSTOMER, order["id"])
    assert seen["worker_name"] == "Laxmi" and seen["worker_phone"] == "9400000802"
    with pytest.raises(PosError):
        wf.worker_answer(RAJU, order["id"], True)
    wf.done(LAXMI, order["id"])
    wf.record_share(shop, OWNER, order["id"], 3000)
    assert wf.ack_share(LAXMI, order["id"])["share_ack"] is True


def test_refusing_while_free_is_a_minus_point_but_not_while_off(env):
    _, wf, jobs, shop, _, _, _ = env
    _team(wf, jobs, shop, (LAXMI, "Laxmi"), (RAJU, "Raju"))
    one = wf.place(CUSTOMER, {"work_type": "delivery", "business_id": shop})
    out = wf.worker_answer(RAJU, one["id"], False)
    assert out["minus_point"] is True
    jobs.set_status(LAXMI, "off")
    two = wf.place(CUSTOMER, {"work_type": "delivery", "business_id": shop})
    assert two["id"] not in [o["id"] for o in wf.worker_orders(LAXMI)["offers"]], "an OFF worker is not asked"
    assert wf.badge(RAJU)["minus_points"] == 1 and wf.badge(RAJU)["rating"] == 1
    assert wf.badge(LAXMI)["minus_points"] == 0
    assigned = wf.assign(shop, OWNER, two["id"], LAXMI)
    assert assigned["money_mode"] == "upi" and assigned["taken_by"] == "authority", "assigned = the authority's choice"


def test_home_entry_asks_once_without_police_verification(env):
    _, wf, jobs, shop, _, _, _ = env
    wf.set_authority(shop, OWNER, {"gstin": _gstin(), "address": "Vuyyuru", "agency": True})
    wf.save_worker(LAXMI, {"name": "Laxmi", "work_types": ["ayah"], "adult": True})
    wf.invite(shop, OWNER, LAXMI)
    wf.answer_invite(LAXMI, shop, True)
    jobs.set_status(LAXMI, "free")
    order = wf.place(CUSTOMER, {"work_type": "ayah", "business_id": shop})
    assert wf.worker_orders(LAXMI)["offers"] == [], "home work never reaches an unverified worker by itself"
    with pytest.raises(PosError) as ask:
        wf.assign(shop, OWNER, order["id"], LAXMI)
    assert ask.value.code == "home_entry"
    assert wf.assign(shop, OWNER, order["id"], LAXMI, "confirm_home")["status"] == "assigned"


def test_ratings_once_per_month_complaints_and_badge(env):
    store, wf, jobs, shop, _, pushes, now = env
    _team(wf, jobs, shop, (LAXMI, "Laxmi"))
    wf.save_worker(LAXMI, {"name": "Laxmi", "work_types": ["delivery"], "adult": True, "udyam": "UDYAM-AP-07-0099999",
                           "upi": "laxmi@ybl"})
    order = wf.place(CUSTOMER, {"work_type": "delivery", "business_id": shop})
    with pytest.raises(PosError):
        wf.rate(CUSTOMER, order["id"], 5)  # not done yet
    wf.worker_answer(LAXMI, order["id"], True)
    wf.done(LAXMI, order["id"])
    assert wf.rate(CUSTOMER, order["id"], 5)["counted"] is True
    with pytest.raises(PosError):
        wf.rate(CUSTOMER, order["id"], 5)
    jobs.set_status(LAXMI, "free")
    second = wf.place(CUSTOMER, {"work_type": "delivery", "business_id": shop})
    wf.worker_answer(LAXMI, second["id"], True)
    wf.done(LAXMI, second["id"])
    assert wf.rate(CUSTOMER, second["id"], 5)["counted"] is False, "same customer counts once a month"
    badge = wf.badge(LAXMI)
    assert badge["has"] is False and badge["steps"]["udyam"] and not badge["steps"]["days"]
    c = wf.complain(CUSTOMER, order["id"], "late")
    assert any(p[0] == OWNER and "ఫిర్యాదు" in p[1] for p in pushes)
    assert wf.badge(LAXMI)["open_complaints"] == 1
    wf.answer_complaint(shop, OWNER, c["id"], "sorry", True)
    assert wf.badge(LAXMI)["open_complaints"] == 0


def test_badge_after_days_jobs_rating_then_independent_orders_capped(env, monkeypatch):
    store, wf, jobs, shop, _, _, now = env
    monkeypatch.setitem(wfm.SETTINGS, "workforce.badge_days", 90)
    monkeypatch.setattr(wfm, "_setting", lambda k: {"workforce.badge_jobs": 2}.get(k, wfm.SETTINGS[k]))
    _team(wf, jobs, shop, (LAXMI, "Laxmi"))
    wf.save_worker(LAXMI, {"name": "Laxmi", "work_types": ["delivery"], "adult": True, "udyam": "UDYAM-AP-07-0099999",
                           "upi": "laxmi@ybl"})
    for i in range(2):
        o = wf.place(f"app-phone-94000009{i:02d}", {"work_type": "delivery", "business_id": shop})
        wf.worker_answer(LAXMI, o["id"], True)
        wf.done(LAXMI, o["id"])
        wf.rate(f"app-phone-94000009{i:02d}", o["id"], 5)
        jobs.set_status(LAXMI, "free")
    assert wf.badge(LAXMI)["has"] is False
    now[0] = T0 + timedelta(days=91)
    assert wf.badge(LAXMI)["has"] is True
    independent = [o for o in wf.authorities_for("delivery")["options"] if o["kind"] == "independent"]
    assert independent and "స్వతంత్రుడు" in independent[0]["label"]
    with pytest.raises(PosError) as cap:
        wf.place(CUSTOMER, {"work_type": "delivery", "worker": LAXMI, "price_paise": 250000})
    assert cap.value.code == "cap"
    own = wf.place(CUSTOMER, {"work_type": "delivery", "worker": LAXMI, "price_paise": 50000})
    wf.worker_answer(LAXMI, own["id"], True)
    assert wf.order(CUSTOMER, own["id"])["pay_upi"] == "laxmi@ybl", "a స్వతంత్రుడు is paid to his own UPI"


def test_monthly_posting_and_site_attendance(env):
    _, wf, jobs, shop, _, _, _ = env
    _team(wf, jobs, shop, (RAJU, "Raju"))
    post = wf.post(shop, OWNER, {"worker": RAJU, "site": "ABC Factory", "shift": "night", "month": "2026-12",
                                 "lat": 16.36, "lon": 80.84})
    with pytest.raises(PosError) as far:
        wf.mark_site(RAJU, post["id"], "face_live", 16.50, 80.84)
    assert far.value.code == "far"
    assert wf.mark_site(RAJU, post["id"], "face_live", 16.3601, 80.8401)["site"] == "ABC Factory"
    seen = wf.postings(shop, OWNER, "2026-12")["postings"][0]
    assert seen["name"] == "Raju" and seen["shift"] == "night" and len(seen["days_present"]) == 1


def test_work_types_come_from_the_command_center():
    rows = [{"data": {"key": "painter", "label_en": "Painter", "categories": "real_estate,services"}, "status": "ACTIVE"},
            {"data": {"key": "cook"}, "status": "DISABLED"}]
    wfm.set_source(lambda: rows, key="test-db")
    try:
        keys = [w["key"] for w in wfm.work_types()]
        assert "painter" in keys and "cook" not in keys
        assert "painter" in wfm.types_for_category("services")
    finally:
        wfm.set_source(None)
