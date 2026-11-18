"""Front desk: QR menu -> customer order -> kitchen confirms availability -> lanes -> bill (GST only if registered)."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_frontdesk import QR_PREFIX, PosFrontDesk
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000101"
COOK = "app-phone-9400000102"
CASHIER = "app-phone-9400000103"
CUSTOMER = "app-phone-9876543210"
T0 = datetime(2026, 11, 15, 6, 0, tzinfo=timezone.utc)


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    rest = PosRestaurant(store)
    pushes = []
    desk = PosFrontDesk(store, rest, notify=lambda u, t, b, r, k: pushes.append((u, t, r, k)),
                        pay_to=lambda owner, amount, note, ref: [{"kind": "upi", "upi_link": f"upi://pay?am={amount}"}])
    biz = store.create_business(OWNER, {"name": "Murali Hotel", "template": "restaurant", "invoice_prefix": "MH",
                                         "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000102", "kitchen", accepts_orders=True)  # the owner allowed the cook to accept
    store.set_member(biz, OWNER, "9400000103", "cashier")
    table = rest.add_table(biz, OWNER, {"name": "T1"})["id"]
    biryani = store.add_product(biz, OWNER, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 16000})["id"]
    fry = store.add_product(biz, OWNER, {"name": "Chicken Fry", "unit": "plate", "price_paise": 30000})["id"]
    return desk, store, rest, biz, table, biryani, fry, now, pushes


def _order(desk, code, items, **extra):
    return desk.place(CUSTOMER, code, {"items": items, "client_txn_id": "txn-" + extra.pop("txn", "a1b2c3d4"), **extra})


def test_scan_menu_and_dine_in_order_to_bill(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    code = f"{QR_PREFIX}{biz}:{table}"
    seen = desk.resolve(code, CUSTOMER)
    assert seen["table"]["name"] == "T1" and "dine_in" in seen["modes"] and seen["business"]["gst"] is False
    assert {m["name"] for m in seen["menu"]} == {"Chicken Biryani", "Chicken Fry"}
    order = _order(desk, code, [{"product_id": biryani, "qty": 2}, {"product_id": fry, "qty": 1}])
    assert order["stage"] == "placed" and order["kind"] == "dine_in" and order["estimate_paise"] == 62000
    assert any(p[0] == OWNER and p[2] == f"/desk/{biz}" for p in pushes)  # the owner is told
    # the same request again (a flaky network) is the same order
    assert _order(desk, code, [{"product_id": biryani, "qty": 2}], txn="a1b2c3d4")["id"] == order["id"]
    # kitchen: fry is finished -> accepted without it; the customer is told; it is sold out for today
    done = desk.confirm(biz, COOK, order["id"], {fry: False})
    assert done["stage"] == "accepted" and done["pos_order_id"]
    assert [i["status"] for i in done["items"] if i["product_id"] == fry] == ["unavailable"]
    assert done["estimate_paise"] == 32000
    assert all(m["available"] is False for m in desk.resolve(code, CUSTOMER)["menu"] if m["id"] == fry)
    kot = rest.kitchen(biz, OWNER)[0]
    assert [i["name"] for i in kot["items"]] == ["Chicken Biryani"] and kot["table_name"] == "T1"
    desk.advance(biz, COOK, order["id"], "preparing")
    assert rest.kitchen(biz, OWNER)[0]["status"] == "preparing"
    desk.advance(biz, COOK, order["id"], "ready")
    with pytest.raises(PosError) as e:  # a cook cannot bill
        desk.bill(biz, COOK, order["id"], [])
    assert e.value.status == 403
    desk.advance(biz, CASHIER, order["id"], "served")
    billed = desk.bill(biz, CASHIER, order["id"], [{"method": "upi", "amount_paise": 32000}])
    assert billed["invoice"]["total_paise"] == 32000 and billed["invoice"]["balance_paise"] == 0
    assert desk.advance(biz, CASHIER, order["id"], "done")["stage"] == "done"
    mine = desk.view_mine(CUSTOMER, order["id"])
    assert mine["stage"] == "done" and [t["stage"] for t in mine["timeline"]][:2] == ["placed", "accepted"]
    assert any(p[0] == CUSTOMER and p[3].endswith(":done:" + CUSTOMER) for p in pushes)  # thank you


def test_rules_forward_only_and_nothing_left_rejects(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    code = f"{QR_PREFIX}{biz}"
    order = _order(desk, code, [{"product_id": fry, "qty": 1}])
    assert order["kind"] == "takeaway"
    with pytest.raises(PosError):  # cannot skip acceptance
        desk.advance(biz, COOK, order["id"], "ready")
    out = desk.confirm(biz, COOK, order["id"], {fry: False})
    assert out["stage"] == "rejected"
    with pytest.raises(PosError):
        desk.advance(biz, COOK, order["id"], "ready")
    second = _order(desk, code, [{"product_id": biryani, "qty": 1}], txn="b2c3d4e5")
    desk.confirm(biz, COOK, second["id"])
    desk.advance(biz, COOK, second["id"], "ready")
    with pytest.raises(PosError):
        desk.advance(biz, COOK, second["id"], "preparing")  # backwards
    with pytest.raises(PosError) as e:
        desk.advance(biz, COOK, second["id"], "done")  # not billed
    assert e.value.code in ("stage", "bill")


def test_delivery_needs_address_and_runs_to_delivered(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    code = f"{QR_PREFIX}{biz}"
    with pytest.raises(PosError) as e:
        _order(desk, code, [{"product_id": biryani}], kind="delivery")
    assert e.value.code == "address"
    order = _order(desk, code, [{"product_id": biryani}], kind="delivery", address="12-3 Main road, Vijayawada",
                   lat=16.5062, lng=80.648, landmark="near temple")
    assert order["maps_url"].startswith("https://www.google.com/maps/search/?api=1&query=16.506200")
    desk.confirm(biz, COOK, order["id"])
    desk.advance(biz, COOK, order["id"], "ready")
    desk.advance(biz, COOK, order["id"], "packed")
    with pytest.raises(PosError) as e:
        desk.advance(biz, COOK, order["id"], "out_for_delivery")
    assert e.value.code == "assignee"
    out = desk.advance(biz, COOK, order["id"], "out_for_delivery", assignee="Ravi")
    assert out["assignee"] == "Ravi"
    desk.advance(biz, COOK, order["id"], "delivered")
    desk.bill(biz, CASHIER, order["id"], [{"method": "cash", "amount_paise": 16000}])
    assert desk.advance(biz, CASHIER, order["id"], "done")["stage"] == "done"


def test_dine_in_needs_the_table_qr_and_closed_shop_refuses(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    with pytest.raises(PosError):
        _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": biryani}], kind="dine_in")
    store.set_status(biz, OWNER, "paused")
    with pytest.raises(PosError) as e:
        _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": biryani}])
    assert e.value.status == 409
    assert desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["open"] is False


def test_customer_cancel_limits_and_privacy(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    code = f"{QR_PREFIX}{biz}"
    first = _order(desk, code, [{"product_id": biryani}])
    assert desk.cancel_mine(CUSTOMER, first["id"])["stage"] == "cancelled"
    for n in range(3):
        _order(desk, code, [{"product_id": biryani}], txn=f"limit-{n}-zz")
    with pytest.raises(PosError) as e:
        _order(desk, code, [{"product_id": biryani}], txn="limit-9-zz")
    assert e.value.status == 429
    other = "app-phone-9000000009"
    with pytest.raises(PosError):
        desk.view_mine(other, first["id"])
    with pytest.raises(PosError):
        desk.orders(biz, other)  # a stranger is not staff: 404
    with pytest.raises(PosError):
        desk.orders(biz, "app-phone-9400000104")


def test_owner_is_told_after_a_minute(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": biryani}])
    assert desk.escalate_due() == 0
    now[0] = T0 + timedelta(seconds=75)
    assert desk.escalate_due() == 1 and desk.escalate_due() == 0  # once
    assert any(p[0] == OWNER and ":late:" in p[3] for p in pushes)
    assert desk.order(biz, OWNER, order["id"])["escalated"] is True
    assert desk.orders(biz, COOK)["counts"]["new"] == 1


def test_counter_order_voice_menu_and_availability(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    # the owner speaks the menu: preview first, import after review
    parsed = desk.parse_menu(biz, OWNER, "mutton biryani 250 today only, chicken biryani 170, tea 10")
    by = {i["name"]: i for i in parsed["items"]}
    assert by["Mutton biryani"]["today_only"] and by["Chicken biryani"]["exists"] and by["Chicken biryani"]["old_price_paise"] == 16000
    assert desk.import_menu(biz, OWNER, parsed["items"]) == {"created": 2, "updated": 1}
    menu = {m["name"]: m for m in desk.menu_admin(biz, OWNER)["items"]}
    assert menu["Chicken Biryani"]["price_paise"] == 17000 and menu["Mutton biryani"]["today_only_flag"]
    # today-only shows today and not tomorrow
    assert "Mutton biryani" in {m["name"] for m in desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["menu"]}
    now[0] = T0 + timedelta(days=1)
    assert "Mutton biryani" not in {m["name"] for m in desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["menu"]}
    # availability: finished today, back tomorrow
    desk.set_availability(biz, COOK, fry, False)
    assert next(m for m in desk.menu_admin(biz, COOK)["items"] if m["id"] == fry)["available"] is False
    now[0] = T0 + timedelta(days=2)
    assert next(m for m in desk.menu_admin(biz, COOK)["items"] if m["id"] == fry)["available"] is True
    # the receptionist at the counter and for a customer
    said = desk.assist_counter(biz, CASHIER, "2 chicken fry", [], te=False)
    assert said["add"][0]["product_id"] == fry and said["add"][0]["qty"] == 2
    placed = desk.place(CASHIER, None, {"items": [{"product_id": fry, "qty": 2}], "kind": "takeaway", "name": "Suresh",
                                        "client_txn_id": "counter-0001"}, business_id=biz, source="reception")
    assert placed["source"] == "reception" and placed["customer_name"] == "Suresh"
    with pytest.raises(PosError):  # a cook can't change the menu's prices
        desk.import_menu(biz, COOK, parsed["items"])


def test_gst_only_when_the_shop_is_registered(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "g.db"), clock=lambda: now[0])
    rest = PosRestaurant(store)
    desk = PosFrontDesk(store, rest)
    biz = store.create_business(OWNER, {"name": "GST Hotel", "template": "restaurant", "invoice_prefix": "GH",
                                         "registration_type": "regular", "gstin": "29AAGCB7383J1Z4", "state_code": "29"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Thali", "unit": "plate", "price_paise": 10500, "rate_bp": 500,
                                          "price_includes_tax": True})["id"]
    code = f"{QR_PREFIX}{biz}"
    assert desk.resolve(code, CUSTOMER)["business"]["gst"] is True
    order = desk.place(CUSTOMER, code, {"items": [{"product_id": item, "qty": 2}], "client_txn_id": "gst-order-1"})
    assert order["gst"] is True
    desk.confirm(biz, OWNER, order["id"])
    billed = desk.bill(biz, OWNER, order["id"], [{"method": "cash", "amount_paise": 21000}])
    assert billed["invoice"]["total_paise"] == 21000
    invoice = store.invoice(biz, OWNER, billed["invoice"]["id"])
    assert invoice["totals"]["tax_paise"] == 1000  # 5% inside Rs 210


def test_http_routes_end_to_end(monkeypatch):
    """The wiring: auth on every route, customer order, owner accepts + bills, stranger blocked, quick bill."""
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_frontdesk", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner, customer, stranger = "app-phone-9411100011", "app-phone-9811100012", "app-phone-9811100013"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Hotel X", "state_code": "36", "template": "restaurant"}).json()["id"]
    item = client.post(f"/api/pos/businesses/{biz}/products", headers=auth(owner),
                       json={"name": "Dosa", "unit": "plate", "price_paise": 6000}).json()["id"]
    code = f"{QR_PREFIX}{biz}"
    assert client.get("/api/pos/order-desk/resolve", params={"code": code}).status_code == 401
    seen = client.get("/api/pos/order-desk/resolve", params={"code": code}, headers=auth(customer)).json()
    assert [m["name"] for m in seen["menu"]] == ["Dosa"]
    said = client.post("/api/pos/order-desk/assist", headers=auth(customer), json={"code": code, "text": "2 dosa", "cart": []}).json()
    assert said["add"][0]["qty"] == 2
    placed = client.post("/api/pos/order-desk/orders", headers=auth(customer),
                         json={"code": code, "items": [{"product_id": item, "qty": 2}], "client_txn_id": "http-order-1"})
    assert placed.status_code == 200, placed.text
    oid = placed.json()["id"]
    assert client.get(f"/api/pos/order-desk/mine/{oid}", headers=auth(stranger)).status_code == 404
    assert client.get(f"/api/pos/businesses/{biz}/desk/orders", headers=auth(stranger)).status_code == 404
    lane = client.get(f"/api/pos/businesses/{biz}/desk/orders", params={"lane": "new"}, headers=auth(owner)).json()
    assert lane["counts"]["new"] == 1
    assert client.post(f"/api/pos/businesses/{biz}/desk/orders/{oid}/confirm", headers=auth(owner), json={"decisions": {}}).json()["stage"] == "accepted"
    for stage in ("preparing", "ready", "packed", "handed"):
        assert client.post(f"/api/pos/businesses/{biz}/desk/orders/{oid}/advance", headers=auth(owner), json={"stage": stage}).status_code == 200
    billed = client.post(f"/api/pos/businesses/{biz}/desk/orders/{oid}/bill", headers=auth(owner),
                         json={"payments": [{"method": "cash", "amount_paise": 12000}]})
    assert billed.status_code == 200, billed.text
    assert client.get("/api/pos/order-desk/mine", headers=auth(customer)).json()["orders"][0]["invoice"]["total_paise"] == 12000
    qr = client.get(f"/api/pos/businesses/{biz}/desk/qr", headers=auth(owner)).json()
    assert qr["shop"] == code
    quick = client.post(f"/api/pos/businesses/{biz}/quick-bill", headers=auth(owner),
                        json={"lines": [{"name": "Tea", "amount_paise": 1000}], "advance_paise": 400, "name": "Ravi",
                              "client_txn_id": "http-quick-1"})
    assert quick.status_code == 200 and quick.json()["pending_paise"] == 600
    # table requests: a dine-in order at a table -> ask -> the staff list -> done; a stranger sees nothing
    table = client.post(f"/api/pos/businesses/{biz}/tables", headers=auth(owner), json={"name": "T9"}).json()["id"]
    dine = client.post("/api/pos/order-desk/orders", headers=auth(customer),
                       json={"code": f"{code}:{table}", "items": [{"product_id": item, "qty": 1, "note": "crisp"}],
                             "client_txn_id": "http-order-2"}).json()
    assert client.post(f"/api/pos/order-desk/mine/{dine['id']}/requests", headers=auth(customer), json={"kinds": ["water"]}).status_code == 409
    client.post(f"/api/pos/businesses/{biz}/desk/orders/{dine['id']}/confirm", headers=auth(owner), json={"decisions": {}})
    assert client.post(f"/api/pos/order-desk/mine/{dine['id']}/requests", json={"kinds": ["water"]}).status_code == 401
    assert client.post(f"/api/pos/order-desk/mine/{dine['id']}/requests", headers=auth(stranger), json={"kinds": ["water"]}).status_code == 404
    asked = client.post(f"/api/pos/order-desk/mine/{dine['id']}/requests", headers=auth(customer),
                        json={"kinds": ["water"], "text": "onions"})
    assert asked.status_code == 200, asked.text
    assert {a["kind"] for a in asked.json()["asked"]} == {"water", "onions"}
    mine = client.get(f"/api/pos/order-desk/mine/{dine['id']}/requests", headers=auth(customer)).json()
    assert mine["can_ask"] and len(mine["requests"]) == 2
    assert client.get(f"/api/pos/businesses/{biz}/desk/requests", headers=auth(stranger)).status_code == 404
    waiting = client.get(f"/api/pos/businesses/{biz}/desk/requests", headers=auth(owner)).json()
    assert waiting["count"] == 2 and waiting["requests"][0]["table_name"] == "T9"
    done = client.post(f"/api/pos/businesses/{biz}/desk/requests/{waiting['requests'][0]['id']}/done", headers=auth(owner))
    assert done.status_code == 200 and done.json()["count"] == 1
    cancel = client.post(f"/api/pos/order-desk/requests/{waiting['requests'][1]['id']}/cancel", headers=auth(customer))
    assert cancel.status_code == 200 and client.get(f"/api/pos/businesses/{biz}/desk/requests", headers=auth(owner)).json()["count"] == 0
    assert client.get(f"/api/pos/businesses/{biz}/desk/request-settings", headers=auth(customer)).status_code == 404
    saved = client.put(f"/api/pos/businesses/{biz}/desk/request-settings", headers=auth(owner),
                       json={"off": ["tissue"], "custom": [{"en": "Papad", "te": "అప్పడం"}]})
    assert saved.status_code == 200, saved.text
    assert [r["en"] for r in saved.json()["requests"] if r["custom"]] == ["Papad"]


def test_a_shop_name_said_in_telugu_or_hindi_finds_the_english_named_shop(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    shop = store.create_business(OWNER, {"name": "Murali Manohar Mutton Chicken Shop", "template": "restaurant",
                                         "invoice_prefix": "MM", "state_code": "37"})["id"]
    store.add_product(shop, OWNER, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 18000})
    for said in ("మురళి మనోహర్ చికెన్ అండ్ మటన్‌లో ఒక బిర్యానీ ఆర్డర్", "मुरली मनोहर चिकन से बिरयानी",
                 "murali manohar chiken lo biryani"):
        assert [s["id"] for s in desk.find_shops(said)] == [shop], said
    assert desk.find_shops("చికెన్ బిర్యానీ ఎక్కడ దొరుకుతుంది") == []  # food words alone never pick a shop
    assert [s["id"] for s in desk.search_shops("మురళి మనోహర్")] == [shop]


def test_find_shops_matches_the_shop_name_the_person_said(env):
    """'Murali hotel lo biryani order' finds the ASKODOX shop by its own name; a stray generic word does not
    (owner 2026-11-16: do not send the person to Swiggy / Zomato for a shop that is on ASKODOX)."""
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    hit = desk.find_shops("murali hotel lo biryani order cheyyali")
    assert [h["id"] for h in hit] == [biz] and hit[0]["code"] == f"{QR_PREFIX}{biz}"
    assert desk.find_shops("best hotel near me for biryani") == []  # one generic word is not a shop name
    assert desk.find_shops("zzz unknown place") == []


def test_find_items_shows_our_shops_with_menu_prices_and_skips_sold_out(env):
    """'good biryani nearby' finds the ASKODOX shop whose MENU has biryani (item words, no category list), with
    the menu price; an item finished today is not offered (owner 2026-11-16)."""
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    hit = desk.find_items("nearby good biryani order cheyyi")
    assert [h["id"] for h in hit] == [biz]
    assert hit[0]["items"] == [{"name": "Chicken Biryani", "price_paise": 16000, "unit": "plate"}]
    assert desk.find_items("cheap laptop under 40000") == []  # nothing on any menu
    desk.set_availability(biz, OWNER, biryani, False)
    assert desk.find_items("biryani") == []  # sold out today -> not offered


class _FakeVision:
    def __init__(self, payload):
        self.payload = payload
        self.prompts = []

    def analyze_with_prompt(self, images, prompt, max_models=1, allow_second_provider=False):
        self.prompts.append(prompt)
        return self.payload, 1


def test_menu_photo_preview_keeps_printed_prices_and_never_guesses(env):
    """The photo's items + prices come back as a PREVIEW (nothing saved); an unclear price stays empty; existing
    items show their old price (owner 2026-11-16)."""
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    vision = _FakeVision({"items": [
        {"name": "Chicken Biryani", "price": "₹170", "unit": "plate"},
        {"name": "Mutton Biryani", "price": 250, "unit": None},
        {"name": "Tea", "price": None, "unit": "cup"},
        {"name": "chicken biryani", "price": 999},          # duplicate of the first -> dropped
        {"name": "Call 9876543210", "price": 99999999},      # silly price -> needs a price, not imported blindly
    ]})
    out = desk.parse_menu_photo(biz, OWNER, [(b"jpeg", "image/jpeg")], vision)
    by = {i["name"]: i for i in out["items"]}
    assert out["read"] is True and len(out["items"]) == 4
    assert by["Chicken Biryani"]["price_paise"] == 17000 and by["Chicken Biryani"]["exists"] is True
    assert by["Chicken Biryani"]["old_price_paise"] == 16000
    assert by["Mutton Biryani"]["price_paise"] == 25000 and by["Mutton Biryani"]["exists"] is False
    assert by["Tea"]["needs_price"] is True and by["Tea"]["price_paise"] == 0 and by["Tea"]["unit"] == "cup"
    assert by["Call 9876543210"]["needs_price"] is True
    # nothing was saved by the preview
    assert {m["name"] for m in desk.menu_admin(biz, OWNER)["items"]} == {"Chicken Biryani", "Chicken Fry"}
    with pytest.raises(PosError):  # a cook cannot change the menu
        desk.parse_menu_photo(biz, COOK, [(b"jpeg", "image/jpeg")], vision)
    # a provider that failed says so (the app shows "could not read"), no invented items
    assert desk.parse_menu_photo(biz, OWNER, [(b"jpeg", "image/jpeg")], _FakeVision({}))["read"] is False


DRIVER = "app-phone-9400000104"
RUNNER = "app-phone-9400000105"


def _staff_with_accounts(store, biz):
    """Give the members an app account so they can be told (the env fixture only has phone numbers)."""
    with store._tx() as conn:
        for phone, uid in (("9400000102", COOK), ("9400000103", CASHIER)):
            conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND phone_key LIKE ?", (uid, biz, "%" + phone[-10:]))


def test_orders_are_routed_to_the_people_the_owner_chose_not_everyone(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    _staff_with_accounts(store, biz)
    store.set_member(biz, OWNER, "9400000104", "delivery", "Ravi")
    with store._tx() as conn:
        conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND role = 'delivery'", (DRIVER, biz))
    code = f"{QR_PREFIX}{biz}"
    placed = _order(desk, code, [{"product_id": biryani, "qty": 2}], kind="takeaway", txn="route001")
    new_alerts = {p[0] for p in pushes if p[3].endswith(":new:" + p[0])}
    assert new_alerts == {OWNER, COOK}  # the owner + the person the owner allowed to accept (never the delivery person)
    pushes.clear()
    desk.confirm(biz, OWNER, placed["id"])
    kitchen = {p[0] for p in pushes if ":kitchen:" in p[3]}
    assert kitchen == {COOK}  # the kitchen person hears it (the owner who confirmed does not)
    # the owner picks WHO hears a new order among the people allowed to accept: only the cook (not himself)
    out = desk.set_desk_settings(biz, OWNER, {"new": [COOK]}, None)
    assert out["routing"]["new"] == [COOK] and {p["id"] for p in out["people"]} >= {OWNER, COOK, CASHIER, DRIVER}
    pushes.clear()
    _order(desk, code, [{"product_id": biryani, "qty": 1}], kind="takeaway", txn="route002")
    assert {p[0] for p in pushes if ":new:" in p[3]} == {COOK}
    with pytest.raises(PosError):  # a cook cannot change who hears what
        desk.set_desk_settings(biz, COOK, {"new": [COOK]}, None)
    with pytest.raises(PosError):  # only this shop's staff
        desk.set_desk_settings(biz, OWNER, {"new": ["app-phone-0000000000"]}, None)


def test_delivery_person_sees_only_their_orders_and_assign_alerts_them(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    _staff_with_accounts(store, biz)
    store.set_member(biz, OWNER, "9400000104", "delivery", "Ravi")
    store.set_member(biz, OWNER, "9400000105", "delivery", "Suresh")
    with store._tx() as conn:
        conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND label = 'Ravi'", (DRIVER, biz))
        conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND label = 'Suresh'", (RUNNER, biz))
    code = f"{QR_PREFIX}{biz}"
    mine = _order(desk, code, [{"product_id": biryani, "qty": 1}], kind="delivery", address="Gandigunta, Vuyyuru 521165",
                  phone="9876543210", txn="deliv001")
    other = _order(desk, code, [{"product_id": biryani, "qty": 1}], kind="delivery", address="Main road, Vuyyuru 521165",
                   phone="9876543210", txn="deliv002")
    for oid in (mine["id"], other["id"]):
        desk.confirm(biz, OWNER, oid)
        desk.advance(biz, OWNER, oid, "preparing")
        desk.advance(biz, OWNER, oid, "ready")
    pushes.clear()
    desk.assign(biz, OWNER, mine["id"], "", assignee_user=DRIVER)
    assert [p[0] for p in pushes if ":assign" in p[3]] == [DRIVER]  # Ravi's phone is told
    desk.advance(biz, OWNER, mine["id"], "packed")
    assert DRIVER in {p[0] for p in pushes if ":step" in p[3]} and RUNNER not in {p[0] for p in pushes if ":step" in p[3]}
    # Ravi sees only his own order and can only move it out / delivered
    seen = desk.orders(biz, DRIVER)["orders"]
    assert [o["id"] for o in seen] == [mine["id"]]
    with pytest.raises(PosError):
        desk.order(biz, DRIVER, other["id"])  # not his
    with pytest.raises(PosError):
        desk.confirm(biz, DRIVER, other["id"])  # a delivery person never answers orders
    with pytest.raises(PosError):
        desk.advance(biz, DRIVER, mine["id"], "done")  # only out for delivery / delivered
    out = desk.advance(biz, DRIVER, mine["id"], "out_for_delivery")
    assert out["stage"] == "out_for_delivery" and out["assignee"] == "Ravi"
    assert desk.advance(biz, DRIVER, mine["id"], "delivered")["stage"] == "delivered"


def test_an_order_waits_for_the_owner_or_an_allowed_person_never_auto_accepted(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    _staff_with_accounts(store, biz)
    code = f"{QR_PREFIX}{biz}"
    desk.set_desk_settings(biz, OWNER, None, True)  # an old app asking for auto-confirm changes nothing
    assert desk.desk_settings(biz, OWNER)["auto_confirm"] is False
    pushes.clear()
    order = _order(desk, code, [{"product_id": biryani, "qty": 1}], kind="takeaway", txn="wait0001")
    assert order["stage"] == "placed"
    told = {p[0] for p in pushes if ":new" in p[3]}
    assert OWNER in told and COOK in told and CASHIER not in told  # only the people who may accept are rung
    with pytest.raises(PosError) as e:
        desk.confirm(biz, CASHIER, order["id"])  # the cashier was not allowed
    assert e.value.status == 403
    # the owner allows the cashier, then pauses the cook: the cook is no longer rung and cannot accept
    store.member_by_ref(biz, OWNER, "0103", "cashier", accepts_orders=True)
    store.member_by_ref(biz, OWNER, "0102", "kitchen", paused=True)
    assert {m["phone_last4"]: (m["accepts_orders"], m["paused"]) for m in store.members(biz, OWNER)}["0102"] == (True, True)
    with pytest.raises(PosError):
        desk.confirm(biz, COOK, order["id"])
    accepted = desk.confirm(biz, CASHIER, order["id"])
    assert accepted["stage"] == "accepted"
    steps = [t["stage"] for t in accepted["timeline"] if t["kind"] == "step"]
    assert steps == ["placed", "accepted"] and accepted["flow"][:2] == ["placed", "accepted"]
    with pytest.raises(PosError) as again:  # a second tap never makes a second acceptance
        desk.confirm(biz, OWNER, order["id"])
    assert again.value.status == 409


class _PerPhotoVision:
    """Answers each photo on its own (the menu reader sends one call per photo, thinking off)."""

    def __init__(self):
        self.calls = []

    def analyze_with_prompt(self, images, prompt, max_models=1, allow_second_provider=False, fast=False):
        self.calls.append((len(images), fast))
        data = images[0][0]
        if data == b"broken":
            return {}, 1
        return {"items": [{"name": data.decode(), "price": 100, "unit": None}]}, 1


def test_menu_photos_are_read_one_call_each_in_parallel_and_merged():
    from app.services import pos_menu_photo

    vision = _PerPhotoVision()
    out = pos_menu_photo.read_menu(vision, [(b"Tea", "image/jpeg"), (b"broken", "image/jpeg"), (b"Coffee", "image/jpeg")])
    assert out["read"] is True
    assert [i["name"] for i in out["items"]] == ["Tea", "Coffee"]
    assert sorted(vision.calls) == [(1, True)] * 3
    # every photo failing -> honest "not read"
    assert pos_menu_photo.read_menu(vision, [(b"broken", "image/png")])["read"] is False


def test_parcel_order_is_billed_on_accept_and_reaches_my_bills(env):
    """Owner 2026-11-16: accept -> the bill (unpaid, with Pay) is in the customer's "My bills"; marking it paid later
    clears the balance the customer sees; the order still walks its lane to done."""
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": biryani, "qty": 2}], kind="takeaway")
    accepted = desk.confirm(biz, OWNER, order["id"])
    assert accepted["invoice"] and accepted["invoice"]["balance_paise"] == 32000
    mine = desk.bills.my_bills(CUSTOMER)
    assert len(mine) == 1 and mine[0]["due_paise"] == 32000 and mine[0]["pay"]
    assert any(p[2] == "/me/bills" for p in pushes if p[0] == CUSTOMER)
    desk.bills.settle(biz, OWNER, accepted["invoice"]["id"], "phonepe", 0, "settle-desk-01")
    seen = desk.track(CUSTOMER, order["id"]) if hasattr(desk, "track") else desk.order(biz, OWNER, order["id"])
    assert seen["invoice"]["balance_paise"] == 0 and seen["pay"] == []
    for stage in ("ready", "packed", "handed", "done"):
        out = desk.advance(biz, OWNER, order["id"], stage)
    assert out["stage"] == "done"


def test_dine_in_is_not_billed_on_accept(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}:{table}", [{"product_id": fry, "qty": 1}], kind="dine_in")
    assert desk.confirm(biz, OWNER, order["id"])["invoice"] is None


def test_shop_search_and_chat_card(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    assert [s["id"] for s in desk.search_shops("mura")] == [biz]
    assert desk.search_shops("m") == [] and desk.search_shops("zzz") == []
    card = desk.chat_card(biz, CUSTOMER, "murali hotel")
    assert card["open"] and card["prepared"] == [] and {i["id"] for i in card["items"]} == {biryani, fry}
    assert all(i["item_no"] for i in card["items"]) and "takeaway" in card["modes"] and "dine_in" not in card["modes"]
    said = desk.chat_card(biz, CUSTOMER, "murali hotel 2 chicken biryani")
    assert said["prepared"] and said["prepared"][0]["product_id"] == biryani and said["items"][0]["id"] == biryani
    # "the usual" = the last order, ready for one confirm tap (nothing is placed)
    _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": fry, "qty": 3}], kind="takeaway")
    usual = desk.chat_card(biz, CUSTOMER, "murali hotel usual")
    assert usual["prepared"] == [{"product_id": fry, "qty": 3}]


def test_cashier_taking_money_for_a_bill_made_on_accept_settles_it(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": fry, "qty": 1}], kind="takeaway")
    desk.confirm(biz, OWNER, order["id"])
    out = desk.bill(biz, OWNER, order["id"], payments=[{"method": "cash", "amount_paise": 30000}], client_txn_id="cash-at-counter")
    assert out["invoice"]["balance_paise"] == 0
    again = desk.bill(biz, OWNER, order["id"], payments=[{"method": "cash", "amount_paise": 30000}], client_txn_id="cash-at-counter")
    assert again["invoice"]["balance_paise"] == 0  # nothing taken twice


# ---- table service requests (owner 2026-11-16): water / extra gravy / onions / bill, answered by the waiter
def _accepted_dine_in(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}:{table}", [{"product_id": biryani, "qty": 1, "note": "less spicy"}])
    desk.confirm(biz, COOK, order["id"])
    return order


def test_table_request_by_tap_and_words_reaches_the_waiter(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _accepted_dine_in(env)
    assert desk.view_mine(CUSTOMER, order["id"])["items"][0]["note"] == "less spicy"  # item note kept
    mine = desk.requests.for_order(CUSTOMER, order["id"])
    assert mine["can_ask"] and {q["key"] for q in mine["quick"]} >= {"water", "extra_gravy", "onions", "bill", "call"}
    pushes.clear()
    out = desk.requests.ask(CUSTOMER, order["id"], ["water"], "extra onions and papad")
    assert {a["kind"] for a in out["asked"]} == {"water", "onions", "other"}
    assert any(p[2] == f"/desk/{biz}" for p in pushes)  # a waiter / the owner is told
    assert out["asked"] and [r["text"] for r in out["requests"] if r["kind"] == "other"] == ["papad"]
    # tapping the same thing twice never doubles it
    again = desk.requests.ask(CUSTOMER, order["id"], ["water"])
    assert again["asked"] == [] and again["already_waiting"] == 1
    # the staff queue shows the table; one tap answers it and the customer is told
    queue = desk.requests.open_list(biz, COOK)
    assert queue["count"] == 3 and {r["table_name"] for r in queue["requests"]} == {"T1"}
    assert desk.view_mine(CUSTOMER, order["id"])["requests"]
    pushes.clear()
    rid = next(r["id"] for r in queue["requests"] if r["kind"] == "water")
    assert desk.requests.done(biz, COOK, rid)["count"] == 2
    assert any(p[0] == CUSTOMER for p in pushes)


def test_table_requests_need_an_accepted_dine_in_order_of_your_own(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _order(desk, f"{QR_PREFIX}{biz}:{table}", [{"product_id": biryani, "qty": 1}])
    with pytest.raises(PosError) as e:  # not accepted yet
        desk.requests.ask(CUSTOMER, order["id"], ["water"])
    assert e.value.status == 409
    with pytest.raises(PosError) as e:  # someone else's order
        desk.requests.ask("app-phone-9111111111", order["id"], ["water"])
    assert e.value.status == 404
    take = _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": fry, "qty": 1}], txn="zz9y8x7w")
    desk.confirm(biz, COOK, take["id"])
    with pytest.raises(PosError) as e:  # takeaway has no table
        desk.requests.ask(CUSTOMER, take["id"], ["water"])
    assert e.value.status == 409


def test_shop_chooses_its_quick_requests_and_adds_its_own(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _accepted_dine_in(env)
    with pytest.raises(PosError):  # only the owner sets it up
        desk.requests.set_settings(biz, COOK, ["tissue"], None)
    out = desk.requests.set_settings(biz, OWNER, ["tissue", "extra_plate"], [{"en": "Papad", "te": "అప్పడం"}])
    keys = {r["key"]: r["enabled"] for r in out["requests"]}
    assert keys["tissue"] is False and keys["extra_plate"] is False and keys["water"] is True
    quick = desk.requests.for_order(CUSTOMER, order["id"])["quick"]
    assert "tissue" not in {q["key"] for q in quick} and "Papad" in {q["en"] for q in quick}
    papad = next(q["key"] for q in quick if q["en"] == "Papad")
    assert desk.requests.ask(CUSTOMER, order["id"], [papad])["asked"][0]["label"]["te"] == "అప్పడం"
    with pytest.raises(PosError):  # a switched-off one cannot be asked
        desk.requests.ask(CUSTOMER, order["id"], ["tissue"])


def test_own_requests_with_telugu_names_stay_separate_and_words_match_whole_words(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    order = _accepted_dine_in(env)
    out = desk.requests.set_settings(biz, OWNER, None, [{"en": "అప్పడం", "te": "అప్పడం"}, {"en": "పెరుగు", "te": "పెరుగు"},
                                                        {"en": "అప్పడం", "te": "అప్పడం"}])
    own = [r for r in out["requests"] if r["custom"]]
    assert [r["te"] for r in own] == ["అప్పడం", "పెరుగు"] and len({r["key"] for r in own}) == 2  # one key each, no double
    asked = desk.requests.ask(CUSTOMER, order["id"], [own[1]["key"]])
    assert asked["asked"][0]["label"]["te"] == "పెరుగు"
    said = desk.requests.ask(CUSTOMER, order["id"], [], "అప్పడం కావాలి")  # said in words -> the shop's own item
    assert [a["kind"] for a in said["asked"]] == [own[0]["key"]]
    # the keys stay the same when the list is saved again, and removing one keeps the other
    again = desk.requests.set_settings(biz, OWNER, None, [{"key": r["key"], "en": r["en"], "te": r["te"]} for r in own[1:]])
    assert [(r["key"], r["te"]) for r in again["requests"] if r["custom"]] == [(own[1]["key"], "పెరుగు")]
    with desk.store._connect() as conn:
        kinds = lambda text: [h["kind"] for h in desk.requests.parse(conn, biz, text)]  # noqa: E731
        assert kinds("watermelon juice") == ["other"]  # not "water"
        assert kinds("నీళ్లు తీసుకురండి") == ["water"]  # "bring" is not "call the waiter"
        assert kinds("2 plates and tissues") == ["extra_plate", "tissue"]
        assert kinds("ఉల్లిపాయలు కొంచెం") == ["onions"]
        assert kinds("bill please") == ["bill"] and kinds("call the waiter") == ["call"]


def test_menu_sections_and_veg_marks_reach_the_chat_card(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    store.update_product(biz, OWNER, biryani, {"menu_group": "Biryani", "food_type": "nonveg"})
    desk.import_menu(biz, OWNER, [{"name": "Veg Biryani", "price_paise": 14000, "menu_group": "Biryani", "food_type": "veg"}])
    card = desk.chat_card(biz, CUSTOMER, "", True, limit=150)
    by_name = {i["name"]: (i["menu_group"], i["food_type"]) for i in card["items"]}
    assert by_name["Chicken Biryani"] == ("Biryani", "nonveg") and by_name["Veg Biryani"] == ("Biryani", "veg")
    assert by_name["Chicken Fry"] == ("", "") and card["more"] == 0
    with pytest.raises(PosError):
        store.update_product(biz, OWNER, fry, {"food_type": "spicy"})


def test_printed_menu_number_leaves_the_name_and_becomes_the_item_number(env):
    """Owner 2026-11-18: the chat menu showed "#55 117) Fish Biryani" -- ONE number per item."""
    desk, store, rest, biz, *_ = env
    desk.import_menu(biz, OWNER, [{"name": "117) Fish Biryani", "price_paise": 26000},
                                  {"name": "7-Up", "price_paise": 4000},
                                  {"name": "2 Idli", "price_paise": 3000}])
    items = {i["name"]: i for i in desk.menu_admin(biz, OWNER)["items"]}
    assert "Fish Biryani" in items and items["Fish Biryani"]["item_no"] == 117
    assert "7-Up" in items and "2 Idli" in items, "a name that merely starts with a number is left alone"
    # an old row saved with the number in its name is cleaned the next time the menu is read
    old = store.add_product(biz, OWNER, {"name": "69) Kadal Chicken", "unit": "plate", "price_paise": 27000})
    names = {i["id"]: (i["name"], i["item_no"]) for i in desk.menu_admin(biz, OWNER)["items"]}
    assert names[old["id"]] == ("Kadal Chicken", 69)


def test_every_push_route_exists_in_the_app():
    """Owner 2026-11-18: tapping an order notification showed "Page not found" (/order/track/...)."""
    import pathlib
    import re as _re

    root = pathlib.Path(__file__).resolve().parents[2]
    app_routes = set()
    for dart in (root / "lib").rglob("*.dart"):
        app_routes.update(_re.findall(r"path: '(/[^']*)'", dart.read_text(encoding="utf-8")))
    patterns = [_re.compile("^" + _re.sub(r":\w+", r"[^/]+", r) + "$") for r in app_routes]
    sent = set()
    for py in (root / "backend" / "app" / "services").glob("pos_*.py"):
        for route in _re.findall(r'f"(/[a-z][a-z-]*/[^"\s?]*)"', py.read_text(encoding="utf-8")):
            sent.add(_re.sub(r"\{[^}]+\}", "x1", route))
    sent.discard("/b/x1")  # the public bill web page (WhatsApp link), served by the backend, not an app screen
    missing = sorted(r for r in sent if not any(p.match(r) for p in patterns))
    assert missing == [], missing


def test_short_follow_up_opens_the_shop_named_earlier_in_the_chat(env, monkeypatch):
    """Owner 2026-11-18: after talking about an ASKODOX shop, "menu" showed unrelated search results."""
    from types import SimpleNamespace

    from app.api.routes import in_app_assistant, pos_frontdesk

    desk, store, rest, biz, *_ = env
    monkeypatch.setattr(pos_frontdesk, "_desk", lambda request: desk)
    turn = lambda role, text: SimpleNamespace(role=role, text=text)  # noqa: E731
    payload = SimpleNamespace(history=[turn("user", "Murali Hotel lo biryani undha"), turn("assistant", "Undi.")])
    reply = {"reply": "సరే, Murali Hotel మెనూ చూడండి."}
    got = in_app_assistant._shop_in_conversation(None, payload, reply, "menu")
    assert [s["id"] for s in got] == [biz]
    # the brain did not name the shop -> no guess
    assert in_app_assistant._shop_in_conversation(None, payload, {"reply": "Which shop?"}, "menu") == []
    # a long new request is not a follow-up
    assert in_app_assistant._shop_in_conversation(None, payload, reply, "show me good mobile phones under ten thousand") == []
    # nothing about the shop in the chat -> nothing
    assert in_app_assistant._shop_in_conversation(None, SimpleNamespace(history=[]), reply, "menu") == []


def test_customer_chooses_cash_or_online(env):
    """Owner 2026-11-18: the order page offered only "Pay by UPI" -- the customer chooses cash or online."""
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    o = _order(desk, f"{QR_PREFIX}{biz}", [{"product_id": biryani, "qty": 1}])
    assert o["pay_choice"] == ""
    got = desk.set_pay_choice(CUSTOMER, o["id"], "cash")
    assert got["pay_choice"] == "cash"
    assert any("Cash" in p[1] for p in pushes), "the floor staff hear that cash will be paid"
    n = len(pushes)
    desk.set_pay_choice(CUSTOMER, o["id"], "cash")
    assert len(pushes) == n, "told once"
    assert desk.set_pay_choice(CUSTOMER, o["id"], "online")["pay_choice"] == "online"
    with pytest.raises(PosError):
        desk.set_pay_choice(CUSTOMER, o["id"], "card")
    with pytest.raises(PosError):
        desk.set_pay_choice("app-phone-9999999999", o["id"], "cash")
    staff_view = [x for x in desk.orders(biz, OWNER)["orders"] if x["id"] == o["id"]][0]
    assert staff_view["pay_choice"] == "online"


def test_askodox_shopping_lists_only_askodox_businesses(env):
    """Owner 2026-11-18: ASKODOX Shopping -- shops on ASKODOX by name or by what their menu has."""
    desk, store, rest, biz, *_ = env
    by_name = desk.shopping("murali")
    assert [s["id"] for s in by_name] == [biz] and by_name[0]["why"] == "name"
    by_menu = desk.shopping("biryani")
    assert by_menu[0]["id"] == biz and by_menu[0]["items"][0]["name"] == "Chicken Biryani"
    assert desk.shopping("television") == []
    browse = desk.shopping("")
    assert [s["id"] for s in browse] == [biz] and browse[0]["item_count"] == 2


def test_http_shopping_route(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_frontdesk", None, raising=False)
    auth = {"Authorization": f"Bearer {issue_token('app-phone-9411100071', container.settings.session_token_secret)}"}
    client = TestClient(app)
    biz = client.post("/api/pos/businesses", headers=auth, json={"name": "Lakshmi Tiffins", "state_code": "36",
                                                                 "template": "restaurant"}).json()["id"]
    client.post(f"/api/pos/businesses/{biz}/products", headers=auth, json={"name": "Masala Dosa", "unit": "plate",
                                                                           "price_paise": 6000})
    assert client.get("/api/pos/shopping", params={"q": "dosa"}).status_code == 401
    got = client.get("/api/pos/shopping", params={"q": "dosa"}, headers=auth).json()
    mine = [s for s in got["shops"] if s["id"] == biz]
    assert mine and mine[0]["items"][0]["name"] == "Masala Dosa"
    assert isinstance(got["items"], list)
