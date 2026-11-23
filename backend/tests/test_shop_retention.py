"""Owner 2026-11-23 ("1 + 4 do"): do shops KEEP using ASKODOX? Counts for the Command Center, from real bills,
payments and payment-voice events made through the real services on chosen days."""
import dataclasses
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_quick_bill import PosQuickBill
from app.services.pos_store import PosStore
from app.services.shop_retention import LIST_LIMIT, ShopRetention, mask_phone

TODAY = datetime(2026, 11, 23, 6, 0, tzinfo=timezone.utc)  # 11:30 in India on 2026-11-23
PHONEPE = "com.phonepe.app.business"
OWNER_KEY = "owner-retention-" + uuid.uuid4().hex[:6]
ADMIN = {"X-ASKODOX-Admin-Key": OWNER_KEY}


class Clock:
    def __init__(self, now=TODAY):
        self.now = now

    def __call__(self):
        return self.now

    def days_ago(self, n, hour=6):
        self.now = (TODAY - timedelta(days=n)).replace(hour=hour)
        return self


class World:
    """Real services on one database with a clock we can move: shops, bills and payment-voice events on chosen days."""

    def __init__(self, db):
        self.db = db
        self.clock = Clock()
        self.store = PosStore(db, clock=self.clock)
        self.alerts = PosPaymentAlerts(self.store, notify=lambda *a: None, feature_on=lambda: True)
        self.quick = PosQuickBill(self.store)
        self.n = 0

    def shop(self, owner, name, joined_days_ago, **data):
        self.clock.days_ago(joined_days_ago)
        return self.store.create_business(owner, {"name": name, "state_code": "37", **data})["id"]

    def bill(self, biz, owner, days_ago, hour=6):
        self.clock.days_ago(days_ago, hour)
        self.n += 1
        return self.quick.make(biz, owner, {"lines": [{"name": "Rice", "amount_paise": 5000}], "advance_paise": 5000,
                                            "client_txn_id": f"qb-{self.n:07d}"})

    def voice(self, biz, owner, days_ago, hour=6):
        self.clock.days_ago(days_ago, hour)
        self.n += 1
        self.alerts.update_settings(biz, owner, {"enabled": True})
        device = self.alerts.register_device(biz, owner, {"device_key": f"phone-{biz[-6:]}", "label": "Counter",
                                                          "listener_on": True})["device_id"]
        return self.alerts.report(biz, owner, {"client_event_id": f"{PHONEPE}|k{self.n}|17299{self.n:06d}",
                                               "source_app": PHONEPE, "amount_paise": 30000 + self.n,
                                               "device_id": device, "spoken": "announced"})

    def retention(self):
        self.clock.now = TODAY
        return ShopRetention(self.db, clock=self.clock)


A, B, C, D, E = (f"app-phone-94000004{n:02d}" for n in range(1, 6))


@pytest.fixture()
def world(tmp_path):
    w = World(str(tmp_path / "shops.db"))
    # A: joined 70 days ago, works in week 1, week 2, month 2 and yesterday -> kept everywhere, active now
    a = w.shop(A, "Lakshmi Kirana", 70, phone="9848012345", address="Main Road, Vuyyuru")
    for ago in (70, 67, 61, 35, 1):
        w.bill(a, A, ago)
    # B: joined 70 days ago, one bill on its second day, then nothing -> stopped
    b = w.shop(B, "Ravi Tiffins", 70)
    w.bill(b, B, 69)
    # C: joined 20 days ago, only payment voice (day 0 and day 10) -> quiet (nothing for 10 days)
    c = w.shop(C, "Sai Medicals", 20)
    w.voice(c, C, 20)
    w.voice(c, C, 10)
    # D: joined 3 days ago, nothing yet; E: joined 70 days ago, never did anything
    d = w.shop(D, "New Shop", 3)
    e = w.shop(E, "Empty Shop", 70)
    w.ids = {"a": a, "b": b, "c": c, "d": d, "e": e}
    return w


def test_counts_who_still_uses_who_went_quiet_and_who_stopped(world):
    r = world.retention().report(lists=True)
    assert r["as_of"] == "2026-11-23"
    assert r["totals"] == {"shops": 5, "ever_used": 3, "never_used": 2, "active_7": 1, "active_30": 2,
                           "quiet": 1, "stopped": 1, "new_7": 1, "new_30": 2}
    # only shops old enough for the WHOLE window are judged (7 / 14 / 60 days): D (3 days) is in none, C not in month 2
    assert r["kept"]["week_1"] == {"of": 4, "kept": 3, "pct": 75.0}
    assert r["kept"]["week_2"] == {"of": 4, "kept": 2, "pct": 50.0}
    assert r["kept"]["month_2"] == {"of": 3, "kept": 1, "pct": 33.3}
    assert r["tools_30"] == {"bills": 1, "payments": 1, "payment_voice": 1, "other": 0}
    lists = r["lists"]
    assert [s["name"] for s in lists["quiet"]] == ["Sai Medicals"]
    assert [s["name"] for s in lists["stopped"]] == ["Ravi Tiffins"]
    assert [s["name"] for s in lists["never_used"]] == ["New Shop", "Empty Shop"], "newest first"
    quiet, stopped = lists["quiet"][0], lists["stopped"][0]
    assert quiet["last_day"] == "2026-11-13" and quiet["silent_days"] == 10 and quiet["payment_voice"] == 2
    assert stopped["last_day"] == "2026-09-15" and stopped["silent_days"] == 69 and stopped["bills"] == 1
    assert lists["never_used"][0]["silent_days"] is None and lists["never_used"][0]["last_day"] == ""
    assert lists["limit"] == LIST_LIMIT


def test_join_month_table_and_daily_trend(world):
    r = world.retention().report()
    assert r["lists"] is None, "names only when asked for"
    months = {m["month"]: m for m in r["months"]}
    assert list(months) == ["2026-11", "2026-09"], "newest month first"
    sep, nov = months["2026-09"], months["2026-11"]
    assert sep["shops"] == 3 and sep["week_1"] == {"of": 3, "kept": 2, "pct": 66.7}
    assert sep["week_2"] == {"of": 3, "kept": 1, "pct": 33.3} and sep["month_2"] == {"of": 3, "kept": 1, "pct": 33.3}
    assert sep["active_7"] == 1
    assert nov["shops"] == 2 and nov["week_1"] == {"of": 1, "kept": 1, "pct": 100.0}
    assert nov["month_2"] == {"of": 0, "kept": 0, "pct": None}, "too early is said, never guessed"
    trend = {t["day"]: t["active"] for t in r["trend"]}
    assert len(r["trend"]) == 30 and r["trend"][-1]["day"] == "2026-11-23" and r["trend"][0]["day"] == "2026-10-25"
    assert trend["2026-11-22"] == 1 and trend["2026-11-13"] == 1 and trend["2026-11-03"] == 1 and trend["2026-11-23"] == 0


def test_the_days_stay_after_payment_events_are_deleted_and_rolling_twice_adds_nothing(world):
    retention = world.retention()
    first = retention.roll()
    assert first["first"] is True and {"pos_invoices", "pos_payments", "pos_payment_events"} <= set(first["sources"])
    before = retention.report(lists=True, fresh=True)
    with sqlite3.connect(world.db) as conn:  # what the 90-day purge does to old payment events
        conn.execute("DELETE FROM pos_payment_events")
        rows = conn.execute("SELECT business_id, day, bills, payments, alerts FROM shop_activity_days"
                            " ORDER BY business_id, day").fetchall()
    again = retention.roll()
    assert again["first"] is False and again["since"] == "2026-11-21", "two days of overlap after the last roll"
    after = retention.report(lists=True, fresh=True)
    assert after["totals"] == before["totals"] and after["kept"] == before["kept"]
    assert after["lists"]["quiet"][0]["payment_voice"] == 2, "the payment-voice days are kept"
    with sqlite3.connect(world.db) as conn:
        assert conn.execute("SELECT business_id, day, bills, payments, alerts FROM shop_activity_days"
                            " ORDER BY business_id, day").fetchall() == rows, "counts never double"


def test_a_bill_that_syncs_late_and_the_india_day_boundary(world):
    retention = world.retention()
    assert retention.report()["totals"]["active_7"] == 1
    # B makes a bill dated yesterday (an offline phone syncing late), after the first roll already ran
    world.bill(world.ids["b"], B, 1)
    # E gets a payment-voice event at 20:00 UTC yesterday = 01:30 TODAY in India
    world.voice(world.ids["e"], E, 1, hour=20)
    world.clock.now = TODAY
    r = retention.report(lists=True, fresh=True)
    assert r["totals"]["active_7"] == 3 and r["totals"]["stopped"] == 0 and r["totals"]["never_used"] == 1
    trend = {t["day"]: t["active"] for t in r["trend"]}
    assert trend["2026-11-22"] == 2, "A and B worked yesterday"
    assert trend["2026-11-23"] == 1, "E's 20:00 UTC event belongs to the next India day"


def test_empty_deployment_and_too_early_answers(tmp_path):
    db = str(tmp_path / "none.db")
    r = ShopRetention(db, clock=Clock()).report(lists=True)
    assert r["totals"]["shops"] == 0 and r["kept"]["month_2"]["pct"] is None and r["months"] == []
    assert r["lists"] == {"quiet": [], "stopped": [], "never_used": [], "limit": LIST_LIMIT} and len(r["trend"]) == 30
    # shops exist but nobody is 7 days old yet: no rate is invented
    w = World(db)
    w.bill(w.shop(A, "Day One Shop", 2), A, 2)
    r = w.retention().report(fresh=True)  # the page re-rolls at most every 10 minutes; "refresh" rolls now
    assert r["totals"]["shops"] == 1 and r["totals"]["active_7"] == 1
    assert r["kept"]["week_1"] == {"of": 0, "kept": 0, "pct": None}


def test_a_persons_own_number_is_never_shown_in_full(world):
    assert mask_phone("app-phone-9400000402") == "app-phone-••••••0402"
    lists = world.retention().report(lists=True)["lists"]
    ravi = lists["stopped"][0]
    assert ravi["phone"] == "" and ravi["owner"] == "app-phone-••••••0402", "no shop number -> only the masked owner"
    assert "9400000402" not in str(lists)
    world.bill(world.ids["a"], A, 40)  # nothing changes for A: it keeps its own counter number on the row
    with sqlite3.connect(world.db) as conn:
        assert conn.execute("SELECT phone FROM pos_businesses WHERE id = ?", (world.ids["a"],)).fetchone()[0] == "9848012345"


def test_the_roll_up_job_is_scheduled():
    from app.services import periodic_jobs

    jobs = {name: (every, job) for name, every, job in periodic_jobs.default_jobs()}
    assert "shop_activity" in jobs and jobs["shop_activity"][0] >= 3600


def test_command_center_route_permissions_and_page(monkeypatch):
    from app.api.routes import admin_console, admin_console_nav
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "shop_retention", None, raising=False)
    store = PosStore(container.settings.database_path)
    name = "Route Shop " + uuid.uuid4().hex[:6]
    biz = store.create_business("app-phone-9400000499", {"name": name, "state_code": "37", "phone": "9848099999"})["id"]
    PosQuickBill(store).make(biz, "app-phone-9400000499", {"lines": [{"name": "Tea", "amount_paise": 1000}],
                                                            "advance_paise": 1000, "client_txn_id": "qb-" + uuid.uuid4().hex[:8]})
    client = TestClient(app)
    assert client.get("/admin/cc/shop-retention").status_code in (401, 403)
    owner = client.get("/admin/cc/shop-retention?fresh=true", headers=ADMIN)
    assert owner.status_code == 200, owner.text
    data = owner.json()
    assert data["can_see_shops"] is True and data["totals"]["shops"] >= 1 and data["totals"]["active_7"] >= 1
    assert set(data["lists"]) == {"quiet", "stopped", "never_used", "limit"}
    # a staff member who may read analytics but not users gets the counts only
    made = client.post("/admin/cc/staff", headers=ADMIN, json={"name": "Numbers only", "role": "analytics_viewer"})
    assert made.status_code == 200, made.text
    staff = {"X-ASKODOX-Staff-Token": made.json()["token"]}
    held = set(client.get("/admin/cc/me", headers=staff).json()["permissions"])
    assert "analytics:view" in held and "users:view" not in held
    seen = client.get("/admin/cc/shop-retention", headers=staff).json()
    assert seen["can_see_shops"] is False and seen["lists"] is None and name not in str(seen)
    assert seen["totals"] == data["totals"]
    # a staff member without analytics is refused
    other = client.post("/admin/cc/staff", headers=ADMIN, json={"name": "Seller help", "role": "seller_support"})
    token = {"X-ASKODOX-Staff-Token": other.json()["token"]}
    if "analytics:view" not in set(client.get("/admin/cc/me", headers=token).json()["permissions"]):
        assert client.get("/admin/cc/shop-retention", headers=token).status_code == 403
    assert "shopretention" in admin_console_nav.views() and "async function shopretention(" in admin_console.PAGE
