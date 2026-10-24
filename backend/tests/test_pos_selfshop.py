"""Self-shopping (scan & go): daily entry code, customer list, exit photo check, bill at the counter."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_selfshop import QR_PREFIX, PosSelfShop
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000501"
CASHIER = "app-phone-9400000502"
SHOPPER = "app-phone-9400000503"
OTHER = "app-phone-9400000504"


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now


@pytest.fixture()
def env(tmp_path):
    clock = Clock()
    store = PosStore(str(tmp_path / "pos.db"), clock=clock)
    shop = PosSelfShop(store)
    biz = store.create_business(OWNER, {"name": "Sri Super Market", "state_code": "36", "template": "supermarket"})["id"]
    store.set_member(biz, OWNER, "9400000502", "cashier")
    soap = store.add_product(biz, OWNER, {"name": "Soap", "unit": "pcs", "price_paise": 4000, "barcode": "8901000000011"})
    biscuit = store.add_product(biz, OWNER, {"name": "Biscuit", "unit": "pcs", "price_paise": 1000,
                                             "barcode": "8901000000028"})
    store.set_pack(biz, OWNER, biscuit["id"], {"name": "box", "factor_milli": 12000, "price_paise": 11000,
                                               "barcode": "8901000000035"})
    rice = store.add_product(biz, OWNER, {"name": "Rice loose", "unit": "kg", "price_paise": 6000, "barcode": "2000000000015"})
    return clock, store, shop, biz, soap, biscuit, rice


def test_off_until_the_owner_turns_it_on_and_the_code_changes_daily(env):
    clock, store, shop, biz, *_ = env
    assert shop.settings(biz, CASHIER)["code"] is None
    with pytest.raises(PosError):
        shop.update_settings(biz, CASHIER, {"enabled": True})  # cashier cannot change settings
    on = shop.update_settings(biz, OWNER, {"enabled": True, "minutes": 60})
    code = on["code"]
    assert len(code) == 6 and on["qr"] == QR_PREFIX + code
    assert shop.settings(biz, CASHIER)["code"] == code, "same code all day"
    clock.now += timedelta(days=1)
    assert shop.settings(biz, OWNER)["code"] != code, "a new code the next day"
    with pytest.raises(PosError) as e:
        shop.join(SHOPPER, code)
    assert e.value.status == 404, "yesterday's code no longer opens the shop"
    shop.update_settings(biz, OWNER, {"enabled": False})
    with pytest.raises(PosError):
        shop.join(SHOPPER, "123456")


def test_scan_checkout_verify_and_bill(env):
    clock, store, shop, biz, soap, biscuit, rice = env
    code = shop.update_settings(biz, OWNER, {"enabled": True})["code"]
    session = shop.join(SHOPPER, QR_PREFIX + code)
    assert session["status"] == "OPEN" and session["shop"] == "Sri Super Market" and "exit_code" not in session
    assert shop.join(SHOPPER, code)["id"] == session["id"], "joining again resumes the same list"
    sid = session["id"]
    out = shop.scan(SHOPPER, sid, "8901000000011")
    assert out["added"] and out["item"]["name"] == "Soap"
    shop.scan(SHOPPER, sid, "8901000000011")
    box = shop.scan(SHOPPER, sid, "8901000000035")
    assert box["added"] and box["item"]["pack"] == "box" and box["item"]["price_paise"] == 11000
    loose = shop.scan(SHOPPER, sid, "2000000000015")
    assert not loose["added"] and loose["reason"] == "weigh_at_counter"
    with pytest.raises(PosError) as e:
        shop.scan(SHOPPER, sid, "9999999999999")
    assert e.value.status == 404
    with pytest.raises(PosError):
        shop.view(OTHER, sid)  # nobody else sees the list
    view = shop.view(SHOPPER, sid)
    assert [(i["name"], i["qty_milli"]) for i in view["items"]] == [("Soap", 2000), ("Biscuit", 1000)]
    assert view["total_paise"] == 2 * 4000 + 11000

    with pytest.raises(PosError):
        shop.bill(biz, CASHIER, sid, {"payments": []})  # not at checkout yet
    done = shop.checkout(SHOPPER, sid)
    assert done["status"] == "CHECKOUT" and len(done["exit_code"]) == 4
    with pytest.raises(PosError):
        shop.scan(SHOPPER, sid, "8901000000028")  # locked
    staff = shop.by_exit_code(biz, CASHIER, done["exit_code"])
    assert staff["id"] == sid and staff["customer"] == "0503"

    # one photo: soap + a single biscuit (not the billed box) are visible
    check = shop.verify(biz, CASHIER, sid, ["8901000000011", "8901000000011", "8901000000028"])
    assert [m["name"] for m in check["matched"]] == ["Soap"]
    assert [m["name"] for m in check["count_by_hand"]] == ["Soap"], "2 soaps: one barcode seen, count by hand"
    assert [(n["name"], n["pack"]) for n in check["not_seen"]] == [("Biscuit", "box")]
    assert [n["name"] for n in check["not_billed"]] == ["Biscuit"]
    assert check["all_clear"] is False and check["seen"] == 2

    # staff fix the list (the box was not taken), then bill at the counter
    fixed = shop.set_qty(CASHIER, sid, biscuit["id"], "box", 0, staff_business=biz)
    assert [i["name"] for i in fixed["items"]] == ["Soap"]
    assert shop.verify(biz, CASHIER, sid, ["8901000000011"])["all_clear"] is True
    billed = shop.bill(biz, CASHIER, sid, {"payments": [{"method": "cash", "amount_paise": 8000}]})
    assert billed["invoice"]["totals"]["grand_total_paise"] == 8000
    assert shop.view(SHOPPER, sid)["status"] == "BILLED"
    again = shop.bill(biz, CASHIER, sid, {"payments": [{"method": "cash", "amount_paise": 8000}]})
    assert again["replayed"] and again["invoice"]["id"] == billed["invoice"]["id"], "never billed twice"


def test_sessions_expire_and_other_shops_staff_see_nothing(env):
    clock, store, shop, biz, soap, *_ = env
    code = shop.update_settings(biz, OWNER, {"enabled": True, "minutes": 30})["code"]
    sid = shop.join(SHOPPER, code)["id"]
    shop.scan(SHOPPER, sid, "8901000000011")
    other_biz = store.create_business(OTHER, {"name": "Other", "state_code": "36"})["id"]
    with pytest.raises(PosError) as e:
        shop.staff_view(other_biz, OTHER, sid)
    assert e.value.status == 404
    clock.now += timedelta(minutes=31)
    assert shop.view(SHOPPER, sid)["status"] == "EXPIRED"
    with pytest.raises(PosError):
        shop.scan(SHOPPER, sid, "8901000000011")
    with pytest.raises(PosError):
        shop.join(SHOPPER, "12")


def test_http_join_scan_checkout_and_bill(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_selfshop", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner, shopper = "app-phone-9411100051", "app-phone-9811100052"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Mart", "state_code": "36"}).json()["id"]
    client.post(f"/api/pos/businesses/{biz}/products", headers=auth(owner),
                json={"name": "Tea", "unit": "pcs", "price_paise": 5000, "barcode": "8902000000017"})
    code = client.put(f"/api/pos/businesses/{biz}/selfshop", headers=auth(owner), json={"enabled": True}).json()["code"]
    assert client.post("/api/pos/selfshop/join", json={"code": code}).status_code == 401
    session = client.post("/api/pos/selfshop/join", headers=auth(shopper), json={"code": code}).json()
    sid = session["id"]
    scan = client.post(f"/api/pos/selfshop/{sid}/scan", headers=auth(shopper), json={"barcode": "8902000000017"}).json()
    assert scan["added"] and scan["session"]["total_paise"] == 5000
    assert client.get(f"/api/pos/selfshop/{sid}", headers=auth(owner)).status_code == 404, "the shop owner is not the shopper"
    out = client.post(f"/api/pos/selfshop/{sid}/checkout", headers=auth(shopper)).json()
    staff = client.get(f"/api/pos/businesses/{biz}/selfshop/exit/{out['exit_code']}", headers=auth(owner)).json()
    assert staff["id"] == sid
    check = client.post(f"/api/pos/businesses/{biz}/selfshop/sessions/{sid}/verify", headers=auth(owner),
                        json={"barcodes": ["8902000000017"]}).json()
    assert check["all_clear"] is True
    bill = client.post(f"/api/pos/businesses/{biz}/selfshop/sessions/{sid}/bill", headers=auth(owner),
                       json={"payments": [{"method": "upi", "amount_paise": 5000, "reference": "UTR1"}]})
    assert bill.status_code == 200, bill.text
    assert client.get("/api/pos/selfshop/mine", headers=auth(shopper)).json()["sessions"][0]["status"] == "BILLED"
