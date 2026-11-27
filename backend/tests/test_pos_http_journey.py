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


def test_purchase_supplier_payable_and_stock_in(api):
    """Supplier -> purchase bill (stock in) -> part payment -> payable shrinks; a stranger cannot see the supplier."""
    c, auth = api
    owner = f"app-phone-91{uuid.uuid4().int % 10**8:08d}"
    stranger = f"app-phone-92{uuid.uuid4().int % 10**8:08d}"
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey Store", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    item = c.post(f"{base}/products", headers=h, json={"name": "Oil", "unit": "kg", "price_paise": 15000, "track_stock": True}).json()["id"]
    sup = c.post(f"{base}/suppliers", headers=h, json={"name": "Agro Traders", "phone": "9400000777"}).json()["id"]
    pur = c.post(f"{base}/purchases", headers=h, json={
        "client_txn_id": _id(), "supplier_id": sup, "supplier_bill_no": "AT-101",
        "lines": [{"product_id": item, "qty_milli": 10000, "cost_paise": 12000}]})
    assert pur.status_code == 200, pur.text
    rows = c.get(f"{base}/products", headers=h).json()
    rows = rows.get("products", rows)
    assert [p for p in rows if p["id"] == item][0]["stock_milli"] == 10000
    before = c.get(f"{base}/suppliers/{sup}", headers=h).json()
    pay = c.post(f"{base}/suppliers/{sup}/payments", headers=h, json={"client_txn_id": _id(), "method": "cash", "amount_paise": 50000})
    assert pay.status_code == 200, pay.text
    after = c.get(f"{base}/suppliers/{sup}", headers=h).json()
    assert before["owed_paise"] == 120000 and after["owed_paise"] == 70000, (before, after)
    assert c.get(f"{base}/suppliers/{sup}", headers=auth(stranger)).status_code in (403, 404)
    again = c.post(f"{base}/purchases", headers=h, json={
        "client_txn_id": pur.json().get("client_txn_id") or _id(), "supplier_id": sup, "supplier_bill_no": "AT-101",
        "lines": [{"product_id": item, "qty_milli": 10000, "cost_paise": 12000}]})
    assert again.status_code in (200, 409)


def test_bulk_price_preview_then_apply_and_staff_cannot(api):
    c, auth = api
    n = uuid.uuid4().int % 10**8
    owner, cashier = f"app-phone-81{n:08d}", f"app-phone-82{n:08d}"
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey Prices", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    ids = [c.post(f"{base}/products", headers=h, json={"name": nm, "unit": "kg", "price_paise": p}).json()["id"]
           for nm, p in (("Dal", 10000), ("Sugar", 4500))]
    assert c.post(f"{base}/members", headers=h, json={"phone": cashier[-10:], "role": "cashier"}).status_code == 200
    body = {"scope": "all", "mode": "up_percent", "value": 10, "round_paise": 100}
    prev = c.post(f"{base}/prices/bulk", headers=h, json=body)
    assert prev.status_code == 200, prev.text
    rows = c.get(f"{base}/products", headers=h).json()
    rows = rows.get("products", rows)
    assert sorted(p["price_paise"] for p in rows) == [4500, 10000], "preview changes nothing"
    assert c.post(f"{base}/prices/bulk", headers=auth(cashier), json={**body, "apply": True}).status_code in (403, 404)
    done = c.post(f"{base}/prices/bulk", headers=h, json={**body, "apply": True})
    assert done.status_code == 200, done.text
    rows = c.get(f"{base}/products", headers=h).json()
    rows = rows.get("products", rows)
    assert sorted(p["price_paise"] for p in rows) == [5000, 11000]
    assert ids


def test_family_list_members_items_and_outsider(api):
    c, auth = api
    n = uuid.uuid4().int % 10**8
    me, wife, outsider = f"app-phone-71{n:08d}", f"app-phone-72{n:08d}", f"app-phone-73{n:08d}"
    lst = c.get("/api/me/family-lists", headers=auth(me))
    assert lst.status_code == 200, lst.text
    first = lst.json()
    lists = first.get("lists", first)
    lid = lists[0]["id"] if isinstance(lists, list) else first["id"]
    path = f"/api/me/family-lists/{lid}"
    assert c.post(f"{path}/members", headers=auth(me), json={"phone": wife[-10:], "label": "Wife"}).status_code == 200
    add = c.post(f"{path}/items", headers=auth(me), json={"texts": ["Milk", "Eggs"], "qty": "2"})
    assert add.status_code == 200, add.text
    assert c.post(f"{path}/items", headers=auth(outsider), json={"texts": ["Spy"]}).status_code in (403, 404)


def test_selfshop_customer_scans_checks_out_and_cashier_bills(api):
    c, auth = api
    n = uuid.uuid4().int % 10**8
    owner, buyer, other = f"app-phone-61{n:08d}", f"app-phone-62{n:08d}", f"app-phone-63{n:08d}"
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey Mart", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    item = c.post(f"{base}/products", headers=h, json={"name": "Soap", "unit": "pcs", "price_paise": 4000,
                                                       "barcode": "8901234567890"})
    assert item.status_code == 200, item.text
    on = c.put(f"{base}/selfshop", headers=h, json={"enabled": True, "minutes": 60})
    assert on.status_code == 200, on.text
    code = on.json().get("code") or c.get(f"{base}/selfshop", headers=h).json()["code"]
    joined = c.post("/api/pos/selfshop/join", headers=auth(buyer), json={"code": str(code)})
    assert joined.status_code == 200, joined.text
    sid = joined.json()["id"]
    for _ in range(2):
        s = c.post(f"/api/pos/selfshop/{sid}/scan", headers=auth(buyer), json={"barcode": "8901234567890"})
        assert s.status_code == 200, s.text
    assert c.get(f"/api/pos/selfshop/{sid}", headers=auth(other)).status_code in (403, 404), "another customer's list"
    out = c.post(f"/api/pos/selfshop/{sid}/checkout", headers=auth(buyer))
    assert out.status_code == 200, out.text
    assert c.post(f"{base}/selfshop/sessions/{sid}/bill", headers=auth(buyer),
                  json={"payments": []}).status_code in (403, 404), "a customer can never bill himself"
    bill = c.post(f"{base}/selfshop/sessions/{sid}/bill", headers=h,
                  json={"payments": [{"method": "cash", "amount_paise": 8000}]})
    assert bill.status_code == 200, bill.text


def test_crm_lead_followup_complaint_and_briefs(api):
    c, auth = api
    n = uuid.uuid4().int % 10**8
    owner, stranger = f"app-phone-51{n:08d}", f"app-phone-52{n:08d}"
    h = auth(owner)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Journey CRM", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    lead = c.post(f"{base}/crm/leads", headers=h, json={"name": "Sita", "phone": "9400000888", "need": "20 chairs"})
    assert lead.status_code == 200, lead.text
    fu = c.post(f"{base}/crm/followups", headers=h, json={"due_at": "2026-12-01T10:00:00", "note": "Call back",
                                                          "lead_id": lead.json()["id"]})
    assert fu.status_code == 200, fu.text
    assert c.post(f"{base}/crm/followups/{fu.json()['id']}/close", headers=h, json={"note": "done"}).status_code == 200
    comp = c.post(f"{base}/crm/complaints", headers=h, json={"subject": "Broken leg", "name": "Sita", "phone": "9400000888"})
    assert comp.status_code == 200, comp.text
    assert c.post(f"{base}/crm/leads", headers=auth(stranger), json={"name": "X"}).status_code in (403, 404)
    for path in (f"{base}/morning-brief", f"{base}/automations", "/api/me/morning-brief", "/api/automations/buyer"):
        r = c.get(path, headers=h)
        assert r.status_code == 200, (path, r.text)
    assert c.get(f"{base}/morning-brief", headers=auth(stranger)).status_code in (403, 404)
