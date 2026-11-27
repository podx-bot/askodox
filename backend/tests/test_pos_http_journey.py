"""One shop day over HTTP, the way the app does it: item -> cash bill -> credit bill (baaki) -> part payment ->
statement -> QR collect (own UPI, +1 paise) -> confirm -> cancel -> day close. Demo data only."""
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit
from app.services.session_tokens import issue_token


@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    secret = container.settings.session_token_secret
    return TestClient(app), lambda u: {"Authorization": f"Bearer {issue_token(u, secret)}"}


def _id():
    return uuid.uuid4().hex[:16]


def test_shop_day_journey(api):
    c, auth = api
    owner = f"app-phone-96{uuid.uuid4().int % 10**8:08d}"
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey Kirana", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    item = c.post(f"{base}/products", headers=h, json={"name": "Rice", "unit": "kg", "price_paise": 6000, "track_stock": True}).json()
    assert item["id"]
    assert c.post(f"{base}/stock", headers=h, json={"product_id": item["id"], "kind": "purchase", "qty_milli": 50000}).status_code == 200
    cust = c.post(f"{base}/customers", headers=h, json={"name": "Ravi", "phone": "9400000555"}).json()

    # cash bill
    cash = c.post(f"{base}/invoices", headers=h, json={
        "client_txn_id": _id(), "lines": [{"product_id": item["id"], "qty_milli": 2000}],
        "payments": [{"method": "cash", "amount_paise": 12000}]})
    assert cash.status_code == 200, cash.text
    assert cash.json()["totals"]["grand_total_paise"] == 12000

    # credit bill = baaki
    cr = c.post(f"{base}/invoices", headers=h, json={
        "client_txn_id": _id(), "customer_id": cust["id"],
        "lines": [{"product_id": item["id"], "qty_milli": 5000}], "payments": []})
    assert cr.status_code == 200, cr.text
    due = c.get(f"{base}/customers/{cust['id']}", headers=h).json()
    assert due["balance_paise"] == 30000, due

    # part payment of the baaki
    pay = c.post(f"{base}/customers/{cust['id']}/payments", headers=h, json={"client_txn_id": _id(), "method": "cash", "amount_paise": 10000})
    assert pay.status_code == 200, pay.text
    after = c.get(f"{base}/customers/{cust['id']}", headers=h).json()
    assert after["balance_paise"] == 20000, after

    # stock went down by 7 kg
    prods = c.get(f"{base}/products", headers=h).json()
    rows = prods.get("products", prods)
    rice = [p for p in rows if p["id"] == item["id"]][0]
    assert rice["stock_milli"] == 43000, rice

    # own UPI -> QR collect, two open QRs of one amount stay apart
    m = c.post("/api/me/payment-methods", headers=h, json={"kind": "upi", "upi_id": "journey@okhdfc", "label": "Shop UPI", "is_default": True})
    assert m.status_code == 200, m.text
    mid = m.json()["methods"][0]["id"]
    assert c.put(f"{base}/collect", headers=h, json={"method_id": mid}).status_code == 200
    q1 = c.post(f"{base}/collect/requests", headers=h, json={"amount_paise": 25000, "label": "A"}).json()
    q2 = c.post(f"{base}/collect/requests", headers=h, json={"amount_paise": 25000, "label": "B"}).json()
    assert q1["amount_paise"] != q2["amount_paise"], "same amount must differ by a paise"
    assert q1["share_url"].startswith("http")
    page = c.get(q1["share_url"].split("://", 1)[1].split("/", 1)[1].join(["/", ""]) if False else
                 "/" + q1["share_url"].split("/", 3)[3])
    assert page.status_code == 200 and "upi://" in page.text
    ok = c.post(f"{base}/collect/requests/{q1['id']}", headers=h, json={"action": "confirm", "checked_bank": True})
    assert ok.status_code == 200 and ok.json()["status"] == "confirmed", ok.text
    gone = c.post(f"{base}/collect/requests/{q2['id']}", headers=h, json={"action": "cancel"})
    assert gone.status_code == 200 and gone.json()["status"] == "cancelled"

    # cancel the cash bill the same day, then close the day
    assert c.post(f"{base}/invoices/{cash.json()['id']}/cancel", headers=h, json={"reason": "wrong item"}).status_code == 200
    from datetime import datetime, timezone

    day = c.post(f"{base}/day-close", headers=h, json={"local_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                                                       "counted_cash_paise": 0})
    assert day.status_code == 200, day.text


def test_table_order_kitchen_bill_and_staff_boundaries(api):
    """Table -> order -> KOT -> kitchen steps -> bill; a kitchen member cannot bill; a stranger sees nothing."""
    c, auth = api
    n = uuid.uuid4().int % 10**8
    owner, kitchen, stranger = (f"app-phone-97{n:08d}", f"app-phone-98{n:08d}", f"app-phone-99{n:08d}")
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey Mess", "state_code": "36", "template": "restaurant"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    dish = c.post(f"{base}/products", headers=h, json={"name": "Biryani", "unit": "plate", "price_paise": 20000}).json()["id"]
    table = c.post(f"{base}/tables", headers=h, json={"name": "T1", "seats": 4}).json()["id"]
    assert c.post(f"{base}/members", headers=h, json={"phone": kitchen[-10:], "role": "kitchen"}).status_code == 200
    order = c.post(f"{base}/orders", headers=h, json={"kind": "dine_in", "table_id": table, "guests": 2}).json()["id"]
    added = c.post(f"{base}/orders/{order}/items", headers=h, json={"items": [{"product_id": dish, "qty_milli": 2000}]})
    assert added.status_code == 200, added.text
    assert c.post(f"{base}/orders/{order}/kot", headers=h).status_code == 200

    kots = c.get(f"{base}/kitchen", headers=auth(kitchen))
    assert kots.status_code == 200 and kots.json()["kots"], "kitchen sees the ticket"
    kid = kots.json()["kots"][0]["id"]
    for step in ("preparing", "ready", "served"):
        assert c.post(f"{base}/kitchen/{kid}", headers=auth(kitchen), json={"status": step}).status_code == 200

    assert c.post(f"{base}/orders/{order}/bill", headers=auth(kitchen),
                  json={"client_txn_id": _id(), "payments": []}).status_code in (403, 404), "kitchen must not bill"
    assert c.get(f"{base}/kitchen", headers=auth(stranger)).status_code in (403, 404)
    bill = c.post(f"{base}/orders/{order}/bill", headers=h, json={
        "client_txn_id": _id(), "payments": [{"method": "upi", "amount_paise": 40000}]})
    assert bill.status_code == 200, bill.text
    assert bill.json()["totals"]["grand_total_paise"] == 40000
