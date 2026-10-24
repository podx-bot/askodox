"""POS restaurant module: tables, orders, KOT numbering, kitchen states, void rules,
move / merge, split bill through the same invoice engine, roles."""
import uuid
from datetime import datetime, timezone

import pytest

from app.services import pos_tax
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9200000001"
WAITER = "app-phone-9200000002"
CHEF = "app-phone-9200000003"
CASHIER = "app-phone-9200000004"


def _txn():
    return "t-" + uuid.uuid4().hex


@pytest.fixture()
def r(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 24, 7, 0, tzinfo=timezone.utc))
    rest = PosRestaurant(store)
    head = "36AAPFU0939F1Z"
    biz = store.create_business(OWNER, {"name": "Hotel Annapurna", "registration_type": "regular",
                                        "gstin": head + pos_tax.gstin_check_char(head), "template": "restaurant",
                                        "invoice_prefix": "HA"})["id"]
    for phone, role in (("9200000002", "waiter"), ("9200000003", "kitchen"), ("9200000004", "cashier")):
        store.set_member(biz, OWNER, phone, role)
    biryani = store.add_product(biz, OWNER, {"name": "Chicken biryani", "unit": "plate", "price_paise": 25200,
                                             "rate_bp": 500, "hsn_sac": "996331", "is_service": True})
    tea = store.add_product(biz, OWNER, {"name": "Tea", "unit": "pcs", "price_paise": 2100, "rate_bp": 500,
                                         "hsn_sac": "996331", "is_service": True})
    t1 = rest.add_table(biz, OWNER, {"name": "T1"})["id"]
    t2 = rest.add_table(biz, OWNER, {"name": "T2"})["id"]
    return store, rest, biz, biryani["id"], tea["id"], t1, t2


def test_order_kot_kitchen_and_split_bill(r):
    store, rest, biz, biryani, tea, t1, _ = r
    order = rest.open_order(biz, WAITER, {"table_id": t1, "guests": 3})
    assert rest.open_order(biz, WAITER, {"table_id": t1})["id"] == order["id"], "one open order per table"
    rest.add_items(biz, WAITER, order["id"], [{"product_id": biryani, "qty_milli": 2000, "note": "less spicy",
                                               "client_txn_id": "item-0001"},
                                              {"product_id": tea, "qty_milli": 3000}])
    rest.add_items(biz, WAITER, order["id"], [{"product_id": biryani, "qty_milli": 2000, "client_txn_id": "item-0001"}])
    sent = rest.send_kot(biz, WAITER, order["id"])
    assert sent["kot"]["number"] == 1 and len(sent["kot"]["items"]) == 2, "a resent item is not doubled"
    assert sent["kot"]["items"][0]["note"] == "less spicy" and sent["kot"]["table_name"] == "T1"
    with pytest.raises(PosError):
        rest.send_kot(biz, WAITER, order["id"])  # nothing new
    assert [k["number"] for k in rest.kitchen(biz, CHEF)] == [1]
    rest.set_kot_status(biz, CHEF, sent["kot"]["id"], "preparing")
    with pytest.raises(PosError):
        rest.set_kot_status(biz, CHEF, sent["kot"]["id"], "served")  # must be ready first
    rest.set_kot_status(biz, CHEF, sent["kot"]["id"], "ready")
    rest.set_kot_status(biz, CHEF, sent["kot"]["id"], "served")
    assert rest.kitchen(biz, CHEF) == []
    with pytest.raises(PosError) as e:
        rest.bill(biz, WAITER, order["id"], {"client_txn_id": _txn()})
    assert e.value.status == 403, "a waiter cannot bill"
    tea_item = next(i for i in rest.order(biz, WAITER, order["id"])["items"] if i["name"] == "Tea")
    first = rest.bill(biz, CASHIER, order["id"], {"client_txn_id": _txn(), "item_ids": [tea_item["id"]],
                                                  "payments": [{"method": "cash", "amount_paise": 6300}]})
    assert first["totals"]["grand_total_paise"] == 6300 and first["document_type"] == "tax_invoice"
    assert first["order"]["status"] == "open" and first["order"]["item_count"] == 1
    txn = _txn()
    rest_bill = rest.bill(biz, CASHIER, order["id"], {"client_txn_id": txn,
                                                      "payments": [{"method": "upi", "amount_paise": 50400}]})
    assert rest_bill["totals"]["grand_total_paise"] == 50400 and rest_bill["order"]["status"] == "billed"
    assert rest_bill["payments"][0]["verification"] == "cashier_confirmed"
    assert rest.bill(biz, CASHIER, order["id"], {"client_txn_id": txn})["replayed"]
    assert rest.tables(biz, WAITER)[0]["order"] is None, "the table is free again"


def test_void_rules_move_merge_and_roles(r):
    store, rest, biz, biryani, tea, t1, t2 = r
    a = rest.open_order(biz, WAITER, {"table_id": t1})
    rest.add_items(biz, WAITER, a["id"], [{"product_id": tea}])
    pending = rest.order(biz, WAITER, a["id"])["items"][0]
    assert rest.remove_item(biz, WAITER, a["id"], pending["id"])["items"] == [], "unsent item: just removed"
    rest.add_items(biz, WAITER, a["id"], [{"product_id": biryani}])
    rest.send_kot(biz, WAITER, a["id"])
    sent = rest.order(biz, WAITER, a["id"])["items"][0]
    with pytest.raises(PosError) as e:
        rest.remove_item(biz, WAITER, a["id"], sent["id"], "guest changed mind")
    assert e.value.status == 403
    with pytest.raises(PosError):
        rest.remove_item(biz, OWNER, a["id"], sent["id"], "")
    voided = rest.remove_item(biz, OWNER, a["id"], sent["id"], "guest changed mind")
    assert voided["items"][0]["status"] == "void", "a sent item is kept as VOID, never deleted"
    assert any(x["action"] == "order.item_void" for x in store.audit(biz, OWNER))
    b = rest.open_order(biz, WAITER, {"table_id": t2})
    rest.add_items(biz, WAITER, b["id"], [{"product_id": tea, "qty_milli": 2000}])
    rest.send_kot(biz, WAITER, b["id"])
    merged = rest.move(biz, WAITER, b["id"], t1)
    assert merged["id"] == a["id"] and len([i for i in merged["items"] if i["status"] == "sent"]) == 1
    assert len(merged["kots"]) == 2
    moved = rest.move(biz, WAITER, a["id"], t2)
    assert moved["table_name"] == "T2"
    take = rest.open_order(biz, CASHIER, {"kind": "takeaway"})
    rest.add_items(biz, CASHIER, take["id"], [{"product_id": tea}])
    with pytest.raises(PosError) as e:
        rest.bill(biz, CASHIER, take["id"], {"client_txn_id": _txn(), "payments": [{"method": "cash", "amount_paise": 2100}]})
    assert e.value.code == "unsent"
    billed = rest.bill(biz, CASHIER, take["id"], {"client_txn_id": _txn(), "include_unsent": True,
                                                  "payments": [{"method": "cash", "amount_paise": 2100}]})
    assert billed["order"]["status"] == "billed"
    with pytest.raises(PosError) as e:
        rest.kitchen(biz, WAITER)
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        rest.add_table(biz, CASHIER, {"name": "T9"})
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        rest.tables(biz, "app-phone-9299999999")
    assert e.value.status == 404
    closed = rest.void_order(biz, OWNER, a["id"], "guests left")
    assert closed["status"] == "void"


def test_http_routes(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_restaurant", None, raising=False)
    owner = f"app-phone-96{uuid.uuid4().int % 10**8:08d}"
    h = {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}
    c = TestClient(app)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Dhaba", "state_code": "37", "template": "restaurant"}).json()
    item = c.post(f"/api/pos/businesses/{biz['id']}/products", headers=h,
                  json={"name": "Meals", "unit": "plate", "price_paise": 12000}).json()
    table = c.post(f"/api/pos/businesses/{biz['id']}/tables", headers=h, json={"name": "T1"}).json()
    order = c.post(f"/api/pos/businesses/{biz['id']}/orders", headers=h, json={"table_id": table["id"]}).json()
    c.post(f"/api/pos/businesses/{biz['id']}/orders/{order['id']}/items", headers=h,
           json={"items": [{"product_id": item["id"], "qty_milli": 2000}]})
    kot = c.post(f"/api/pos/businesses/{biz['id']}/orders/{order['id']}/kot", headers=h).json()
    assert kot["kot"]["number"] == 1
    assert len(c.get(f"/api/pos/businesses/{biz['id']}/kitchen", headers=h).json()["kots"]) == 1
    bill = c.post(f"/api/pos/businesses/{biz['id']}/orders/{order['id']}/bill", headers=h,
                  json={"client_txn_id": _txn(), "payments": [{"method": "cash", "amount_paise": 24000}]})
    assert bill.status_code == 200 and bill.json()["document_type"] == "bill"
    assert c.get(f"/api/pos/businesses/{biz['id']}/tables").status_code == 401
