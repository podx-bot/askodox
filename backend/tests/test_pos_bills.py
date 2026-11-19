"""Bills after the counter (owner 2026-11-16): bill by item NUMBER, which app paid, send to the customer's number
(ASKODOX inbox or WhatsApp + public page), settle later, history totals."""
import sqlite3
from datetime import datetime, timezone

import pytest

from app.services.pos_bills import PosBills, mode_of, pay_choice, whatsapp_number
from app.services.pos_quick_bill import PosQuickBill
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000201"
CUSTOMER = "app-phone-9400000299"


@pytest.fixture()
def env(tmp_path):
    now = [datetime(2026, 11, 16, 10, 0, tzinfo=timezone.utc)]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    biz = store.create_business(OWNER, {"name": "Sai Hotel", "template": "restaurant", "invoice_prefix": "SH",
                                        "state_code": "37", "registration_type": "unregistered"})["id"]
    tea = store.add_product(biz, OWNER, {"name": "Tea", "unit": "pcs", "price_paise": 1000})["id"]
    biryani = store.add_product(biz, OWNER, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 17000})["id"]
    pushes = []
    bills = PosBills(store, notify=lambda u, t, b, r, k: pushes.append((u, t, r)),
                     pay_to=lambda owner, amount, note, ref: [{"kind": "upi", "upi_link": f"upi://pay?am={amount / 100}"}],
                     clock=lambda: now[0])
    with sqlite3.connect(store.db_path) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS auth_accounts (phone_key TEXT PRIMARY KEY, user_id TEXT NOT NULL,"
                     " created_at TEXT, last_sign_in_at TEXT, sign_ins INTEGER)")
        conn.execute("INSERT INTO auth_accounts VALUES ('9400000299', ?, '', '', 1)", (CUSTOMER,))
    return store, bills, biz, tea, biryani, pushes


def test_pay_choice_and_modes():
    assert pay_choice("PhonePe") == ("upi", "phonepe")
    assert pay_choice("Google Pay") == ("upi", "gpay")
    assert pay_choice("cash") == ("cash", "")
    assert mode_of("upi", "") == "other_upi"
    assert whatsapp_number("94000 00299") == "919400000299"
    with pytest.raises(PosError):
        pay_choice("bitcoin")


def test_items_get_stable_numbers_and_bill_by_number(env):
    store, bills, biz, tea, biryani, _ = env
    assert bills.numbers(biz) == {tea: 1, biryani: 2}
    out = PosQuickBill(store).make(biz, OWNER, {
        "lines": [{"item_no": 1, "count": 2}, {"item_no": 2, "count": 1}, {"name": "Pan", "amount_paise": 2000}],
        "advance_paise": 21000, "method": "phonepe", "client_txn_id": "qb-number-1"})
    assert out["totals"]["grand_total_paise"] == 21000 and out["pending_paise"] == 0
    assert out["pay_mode"] == "phonepe"
    assert [l["name"] for l in out["lines"]] == ["Tea", "Chicken Biryani", "Pan"]
    assert out["lines"][0]["qty_milli"] == 2000
    # the new name joined the menu with the next number; old numbers did not move
    numbers = bills.numbers(biz)
    assert numbers[tea] == 1 and numbers[biryani] == 2 and sorted(numbers.values()) == [1, 2, 3]
    with pytest.raises(PosError) as bad:
        PosQuickBill(store).make(biz, OWNER, {"lines": [{"item_no": 99, "count": 1}], "advance_paise": 100,
                                              "client_txn_id": "qb-number-2"})
    assert bad.value.code == "item_no"


def test_send_to_askodox_user_goes_to_inbox_else_whatsapp(env):
    store, bills, biz, tea, biryani, pushes = env
    inv = PosQuickBill(store).make(biz, OWNER, {"lines": [{"item_no": 2, "count": 2}], "advance_paise": 0,
                                                "phone": "9400000299", "client_txn_id": "qb-send-01"})
    assert inv["pending_paise"] == 34000
    sent = bills.send(biz, OWNER, inv["id"], "9400000299", base_url="https://x.test")
    assert sent["channel"] == "askodox" and sent["on_askodox"] and pushes[-1][0] == CUSTOMER and pushes[-1][2] == "/me/bills"
    mine = bills.my_bills(CUSTOMER)
    assert len(mine) == 1 and mine[0]["due_paise"] == 34000 and mine[0]["status"] == "due"
    assert mine[0]["pay"][0]["upi_link"].endswith("340.0")
    # someone not on ASKODOX: WhatsApp text to that number with the public page link
    other = bills.send(biz, OWNER, inv["id"], "9400000300", base_url="https://x.test")
    assert other["channel"] == "whatsapp" and other["whatsapp_to"] == "919400000300"
    assert other["url"].startswith("https://x.test/b/") and other["url"] in other["text"]
    page = bills.public(other["token"])
    assert page["shop"] == "Sai Hotel" and page["total_paise"] == 34000 and page["lines"][0]["name"] == "Chicken Biryani"
    assert bills.public("nope") is None and bills.public("x" * 12) is None
    with pytest.raises(PosError):
        bills.send(biz, "app-phone-9999999999", inv["id"], "9400000299")  # not this shop's staff


def test_customer_says_paid_tells_shop_and_settle_closes_the_bill(env):
    store, bills, biz, tea, biryani, pushes = env
    inv = PosQuickBill(store).make(biz, OWNER, {"lines": [{"item_no": 1, "count": 5}], "advance_paise": 2000,
                                                "method": "cash", "phone": "9400000299", "client_txn_id": "qb-settle-1"})
    sent = bills.send(biz, OWNER, inv["id"], "9400000299")
    said = bills.customer_says_paid(sent["token"], "gpay")
    assert said["customer_says_paid"] and said["due_paise"] == 3000  # saying is not paying
    assert pushes[-1][0] == OWNER
    n = len(pushes)
    bills.customer_says_paid(sent["token"], "gpay")
    assert len(pushes) == n  # told once
    with pytest.raises(PosError):
        bills.settle(biz, OWNER, inv["id"], "gpay", 99999, "settle-too-much")
    done = bills.settle(biz, OWNER, inv["id"], "gpay", 0, "settle-ok-0001")
    assert done["due_paise"] == 0
    assert bills.settle(biz, OWNER, inv["id"], "gpay", 0, "settle-ok-0001")["replayed"] is True
    with pytest.raises(PosError) as again:
        bills.settle(biz, OWNER, inv["id"], "cash", 0, "settle-ok-0002")
    assert again.value.code == "paid"
    assert bills.my_bills(CUSTOMER)[0]["status"] == "paid"
    # the customer's running balance at the shop is cleared too
    customer_id = store.invoice(biz, OWNER, inv["id"])["customer_id"]
    assert store.customer(biz, OWNER, customer_id)["balance_paise"] == 0


def test_history_totals_per_way_of_paying(env):
    store, bills, biz, tea, biryani, _ = env
    q = PosQuickBill(store)
    q.make(biz, OWNER, {"lines": [{"item_no": 1, "count": 1}], "advance_paise": 1000, "method": "cash", "client_txn_id": "h-000001"})
    q.make(biz, OWNER, {"lines": [{"item_no": 2, "count": 1}], "advance_paise": 17000, "method": "phonepe", "client_txn_id": "h-000002"})
    due = q.make(biz, OWNER, {"lines": [{"item_no": 2, "count": 1}], "advance_paise": 7000, "method": "upi",
                              "phone": "9400000299", "client_txn_id": "h-000003"})
    out = bills.history(biz, OWNER)
    assert out["totals"]["cash"] == 1000 and out["totals"]["phonepe"] == 17000 and out["totals"]["other_upi"] == 7000
    assert out["totals"]["due"] == 10000 and len(out["bills"]) == 3
    only = bills.history(biz, OWNER, only_due=True)["bills"]
    assert [b["id"] for b in only] == [due["id"]] and only[0]["customer_phone_last4"] == "0299"
    assert len(bills.history(biz, OWNER, query="0299")["bills"]) == 1
    with pytest.raises(PosError):
        bills.history(biz, "app-phone-9999999999")


def test_bill_routes_and_public_page(monkeypatch):
    """HTTP: quick bill by number -> send -> the public page shows the bill; a wrong token is 404."""
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    for name in ("pos_store", "pos_frontdesk", "pos_bills"):
        monkeypatch.setattr(container, name, None, raising=False)
    client = TestClient(app)
    h = {"Authorization": f"Bearer {issue_token('app-phone-9411100071', container.settings.session_token_secret)}"}
    biz = client.post("/api/pos/businesses", headers=h, json={
        "name": "Sai Hotel", "template": "restaurant", "invoice_prefix": "SH", "state_code": "37",
        "registration_type": "unregistered"})
    assert biz.status_code == 200, biz.text
    bid = biz.json()["id"]
    assert client.post(f"/api/pos/businesses/{bid}/products", headers=h,
                       json={"name": "Tea", "unit": "pcs", "price_paise": 1000}).status_code == 200
    menu = client.get(f"/api/pos/businesses/{bid}/desk/menu", headers=h).json()
    assert menu["items"][0]["item_no"] == 1
    bill = client.post(f"/api/pos/businesses/{bid}/quick-bill", headers=h, json={
        "lines": [{"item_no": 1, "count": 3}], "advance_paise": 0, "phone": "9400000299", "client_txn_id": "api-bill-1"})
    assert bill.status_code == 200, bill.text
    sent = client.post(f"/api/pos/businesses/{bid}/bills/{bill.json()['id']}/send", headers=h, json={"phone": "9400000299"})
    assert sent.status_code == 200, sent.text
    page = client.get("/b/" + sent.json()["token"])
    assert page.status_code == 200 and "Sai Hotel" in page.text and "₹30" in page.text
    assert client.get("/b/abcdefgh12").status_code == 404
    hist = client.get(f"/api/pos/businesses/{bid}/bills?due=true", headers=h).json()
    assert hist["totals"]["due"] == 3000 and len(hist["bills"]) == 1
    assert client.get("/api/pos/me/bills").status_code == 401


def test_printed_number_rules():
    from app.services.pos_menu_sort import printed_number

    assert printed_number("117) Fish Biryani") == ("Fish Biryani", 117)
    assert printed_number("12. Tea") == ("Tea", 12)
    assert printed_number("5 - Dosa") == ("Dosa", 5)
    assert printed_number("7-Up")[1] is None
    assert printed_number("500 ml Coke")[1] is None


def test_history_flags_bills_not_printed_until_the_phone_prints(env):
    """Owner 2026-11-19: "Next bill" skips printing; history shows which bills still need printing."""
    store, bills, biz, _tea, _biryani, _ = env
    out = PosQuickBill(store).make(biz, OWNER, {"lines": [{"item_no": 1, "count": 1}], "advance_paise": 1000,
                                                "method": "cash", "client_txn_id": "qb-print-1"})
    row = bills.history(biz, OWNER)["bills"][0]
    assert row["id"] == out["id"] and row["printed"] is False
    first = bills.mark_printed(biz, OWNER, out["id"])
    assert first["printed"] is True and first["printed_at"]
    again = bills.mark_printed(biz, OWNER, out["id"])
    assert again["printed_at"] == first["printed_at"]  # a reprint keeps the first print time
    assert bills.history(biz, OWNER)["bills"][0]["printed"] is True
    with pytest.raises(PosError):
        bills.mark_printed(biz, "app-phone-9400000777", out["id"])  # a stranger cannot touch the shop's bills
