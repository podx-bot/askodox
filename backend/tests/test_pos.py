"""ASKODOX Universal POS: GST arithmetic, immutable invoices, idempotent checkout,
roles + business isolation, credit notes, cancel, ledger / statements, stock,
day close, GST summary. Hardware is NOT exercised here (no printer / scale)."""
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.services import pos_tax, rate_limit
from app.services.pos_store import PosError, PosStore
from app.services.session_tokens import issue_token

VECTORS = Path(__file__).resolve().parents[2] / "test" / "fixtures" / "pos_tax_vectors.json"


def _gstin(state: str, pan: str = "AAPFU0939F") -> str:
    head = f"{state}{pan}1Z"
    return head + pos_tax.gstin_check_char(head)


# ------------------------------------------------------------------ tax engine
def test_shared_vectors_match_engine():
    data = json.loads(VECTORS.read_text())
    assert data["rules_version"] == pos_tax.RULES_VERSION
    for case in data["cases"]:
        r = pos_tax.invoice_totals([dict(l) for l in case["lines"]], registration_type=case["registration_type"],
                                   business_state=case["business_state"], place_of_supply=case["place_of_supply"])
        exp = case["expected"]
        assert r["document_type"] == exp["document_type"], case["name"]
        assert r["mode"] == exp["mode"], case["name"]
        assert r["state_tax_label"] == exp["state_tax_label"], case["name"]
        for k, v in exp["totals"].items():
            assert r["totals"][k] == v, (case["name"], k)
        for got, want in zip(r["lines"], exp["lines"]):
            for k, v in want.items():
                assert got[k] == v, (case["name"], k)


def test_hand_checked_values():
    # Rs 118 inclusive of 18% -> taxable 100, CGST 9, SGST 9.
    t = pos_tax.line_tax(qty_milli=1000, unit_price_paise=11800, rate_bp=1800, price_includes_tax=True)
    assert (t["taxable_paise"], t["cgst_paise"], t["sgst_paise"], t["total_paise"]) == (10000, 900, 900, 11800)
    # 1.235 kg at Rs 240/kg = Rs 296.40 exactly (decimal, no float drift)
    t = pos_tax.line_tax(qty_milli=1235, unit_price_paise=24000, category="exempt")
    assert t["total_paise"] == 29640
    # inclusive price: the customer always pays exactly the shown price
    for price in range(1, 3000, 7):
        t = pos_tax.line_tax(qty_milli=1000, unit_price_paise=price, rate_bp=1800, price_includes_tax=True)
        assert t["total_paise"] == price


def test_gstin_validation_uses_checksum():
    # Published sample GSTINs validate; one changed character does not.
    for good in ("27AAPFU0939F1ZV", "29AAGCB7383J1Z4", "33AAACH7409R1Z8"):
        assert pos_tax.validate_gstin(good)["valid"], good
    assert pos_tax.validate_gstin("27AAPFU0939F1ZW")["reason"] == "checksum"
    assert pos_tax.validate_gstin("99AAPFU0939F1ZV")["valid"] is False
    assert pos_tax.validate_gstin("27AAPFU0939F1ZV")["active_status"] == "not_checked"


def test_rates_and_codes_are_never_invented():
    with pytest.raises(pos_tax.TaxError):
        pos_tax.line_tax(qty_milli=1000, unit_price_paise=100, rate_bp=1700)
    assert pos_tax.check_hsn("0207")["ok"]
    assert pos_tax.check_hsn("02071")["ok"] is False
    assert pos_tax.check_hsn("1234", is_service=True)["reason"] == "sac_starts_99"
    assert pos_tax.check_hsn("0207", turnover_above_5cr=True)["enough_digits"] is False
    assert pos_tax.financial_year("2026-03-31") == "2526" and pos_tax.financial_year("2026-04-01") == "2627"
    assert pos_tax.series_label("INV", "2627", 12) == "INV/2627/000012"
    with pytest.raises(pos_tax.TaxError):
        pos_tax.series_label("TOOLONGPFX", "2627", 1)
    assert pos_tax.recipient_requirements(recipient_gstin=None, total_paise=50_000_00, mode="intra") == [
        "address", "delivery_address", "name", "state_code"]
    assert pos_tax.recipient_requirements(recipient_gstin=None, total_paise=49_999_99, mode="intra") == []


# ---------------------------------------------------------------- store layer
class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 23, 6, 0, tzinfo=timezone.utc)  # 11:30 IST

    def __call__(self):
        return self.now


@pytest.fixture()
def store(tmp_path):
    clock = Clock()
    s = PosStore(str(tmp_path / "pos.db"), clock=clock)
    s.clock_obj = clock
    return s


OWNER = "app-phone-9100000001"
CASHIER = "app-phone-9100000002"
ACCOUNTANT = "app-phone-9100000003"
STRANGER = "app-phone-9100000009"


def _txn():
    return "t-" + uuid.uuid4().hex


def _shop(store, **kw):
    data = {"name": "Sri Lakshmi Chicken Centre", "registration_type": "regular", "gstin": _gstin("36"),
            "template": "meat_fish", "invoice_prefix": "SL", **kw}
    return store.create_business(OWNER, data)


def _item(store, biz, **kw):
    data = {"name": "Chicken curry cut", "unit": "kg", "price_paise": 24000, "rate_bp": 0, "category": "exempt",
            "track_stock": True, "opening_stock_milli": 20000, **kw}
    return store.add_product(biz, OWNER, data)


def test_business_roles_and_isolation(store):
    biz = _shop(store)["id"]
    store.set_member(biz, OWNER, "+91 91000 00002", "cashier")
    store.set_member(biz, OWNER, "9100000003", "accountant")
    assert store.business(biz, CASHIER)["my_role"] == "cashier"
    assert [b["id"] for b in store.my_businesses(ACCOUNTANT)] == [biz]
    with pytest.raises(PosError) as e:
        store.business(biz, STRANGER)
    assert e.value.status == 404  # never reveals another shop exists
    with pytest.raises(PosError) as e:
        store.add_product(biz, CASHIER, {"name": "x", "price_paise": 1})
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        store.set_member(biz, CASHIER, "9100000004", "manager")
    assert e.value.status == 403
    other = store.create_business(STRANGER, {"name": "Other shop", "state_code": "37"})["id"]
    assert store.products(other, STRANGER) == []
    with pytest.raises(PosError):
        store.products(other, OWNER)


def test_composition_and_unregistered_rules(store):
    with pytest.raises(PosError):
        store.create_business(OWNER, {"name": "x", "registration_type": "regular", "gstin": "36AAPFU0939F1ZZ"})
    with pytest.raises(PosError):
        store.create_business(OWNER, {"name": "x", "registration_type": "unregistered", "gstin": _gstin("36")})
    comp = store.create_business(OWNER, {"name": "Comp", "registration_type": "composition", "gstin": _gstin("37")})
    item = store.add_product(comp["id"], OWNER, {"name": "Biscuit", "price_paise": 1000, "rate_bp": 1800,
                                                 "hsn_sac": "1905"})
    inv = store.create_invoice(comp["id"], OWNER, {"client_txn_id": _txn(), "lines": [
        {"product_id": item["id"], "qty_milli": 3000}], "payments": [{"method": "cash", "amount_paise": 3000}]})
    assert inv["document_type"] == "bill_of_supply" and inv["title"] == "Bill of Supply"
    assert inv["totals"]["tax_paise"] == 0
    assert inv["business_snapshot"]["heading"] == "composition taxable person, not eligible to collect tax on supplies"


def test_checkout_is_idempotent_and_immutable(store):
    biz = _shop(store)["id"]
    item = _item(store, biz)
    store.set_member(biz, OWNER, "9100000002", "cashier")
    txn = _txn()
    body = {"client_txn_id": txn, "lines": [{"product_id": item["id"], "weight": {"gross_milli": 1335,
                                                                                    "tare_milli": 100}}],
            "payments": [{"method": "upi", "amount_paise": 29640, "reference": "UTR 1234"}]}
    first = store.create_invoice(biz, CASHIER, body)
    again = store.create_invoice(biz, CASHIER, body)
    assert again["replayed"] and again["id"] == first["id"] and again["number"] == first["number"]
    assert first["number"] == "SLB/2627/000001"  # exempt-only sale: bill of supply series
    assert first["lines"][0]["qty_milli"] == 1235 and first["lines"][0]["weight"]["source"] == "typed"
    assert first["totals"]["grand_total_paise"] == 29640
    assert first["payments"][0]["verification"] == "cashier_confirmed"  # never bank-verified from the counter
    changed = dict(body, payments=[{"method": "cash", "amount_paise": 29640}])
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, changed)
    assert e.value.status == 409
    assert store.product(biz, OWNER, item["id"])["stock_milli"] == 20000 - 1235
    # Editing the item later never rewrites the issued invoice.
    store.update_product(biz, OWNER, item["id"], {"price_paise": 26000})
    assert store.invoice(biz, OWNER, first["id"])["lines"][0]["unit_price_paise"] == 24000
    assert store.product_history(biz, OWNER, item["id"])[-1]["changes"]["before"]["price_paise"] == 24000


def test_cashier_cannot_override_price_and_unpaid_needs_customer(store):
    biz = _shop(store)["id"]
    item = _item(store, biz)
    store.set_member(biz, OWNER, "9100000002", "cashier")
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
            {"product_id": item["id"], "qty_milli": 1000, "unit_price_paise": 1000}]})
    assert e.value.code == "price_override"
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
            {"product_id": item["id"], "qty_milli": 1000}], "payments": [{"method": "cash", "amount_paise": 100}]})
    assert e.value.code == "balance"
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
            {"product_id": item["id"], "qty_milli": 1000}], "payments": [{"method": "cash", "amount_paise": 99999}]})
    assert e.value.code == "payment"
    manager_override = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "lines": [
        {"product_id": item["id"], "qty_milli": 1000, "unit_price_paise": 23000}],
        "payments": [{"method": "cash", "amount_paise": 23000}]})
    assert manager_override["lines"][0]["price_source"] == "manual_override"
    assert any(a["action"] == "invoice.issue" and a["detail"]["price_overrides"] == [1]
               for a in store.audit(biz, OWNER))


def test_b2b_hsn_and_b2c_threshold(store):
    biz = _shop(store)["id"]
    taxed = store.add_product(biz, OWNER, {"name": "Masala", "price_paise": 10000, "rate_bp": 500})  # no HSN
    walk = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "lines": [
        {"product_id": taxed["id"], "qty_milli": 1000}], "payments": [{"method": "cash", "amount_paise": 10000}]})
    assert walk["document_type"] == "tax_invoice"  # B2C up to Rs 5 crore may omit HSN
    hotel = store.add_customer(biz, OWNER, {"name": "Hotel Grand", "gstin": _gstin("36", "AAGCB7383J"),
                                            "address": "Main Road"})
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "customer_id": hotel["id"], "lines": [
            {"product_id": taxed["id"], "qty_milli": 1000}]})
    assert e.value.code == "hsn_sac"
    big = store.add_product(biz, OWNER, {"name": "Freezer", "price_paise": 60_000_00, "rate_bp": 1800,
                                         "hsn_sac": "8418"})
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "lines": [
            {"product_id": big["id"], "qty_milli": 1000}], "payments": [{"method": "cash", "amount_paise": 60_000_00}]})
    assert e.value.code == "recipient" and "address" in e.value.extra["missing"]


def test_inter_state_igst_and_device_series(store):
    biz = _shop(store)["id"]
    item = store.add_product(biz, OWNER, {"name": "Pickle jar", "price_paise": 20000, "rate_bp": 1200,
                                          "hsn_sac": "2001", "price_includes_tax": False})
    cust = store.add_customer(biz, OWNER, {"name": "Bengaluru Mart", "gstin": _gstin("29", "AAGCB7383J"),
                                           "address": "Bengaluru"})
    inv = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "customer_id": cust["id"], "place_of_supply": "29",
                                            "lines": [{"product_id": item["id"], "qty_milli": 2000}]})
    assert inv["mode"] == "inter" and inv["totals"]["igst_paise"] == 4800 and inv["totals"]["cgst_paise"] == 0
    assert inv["balance_paise"] == 44800
    series = store.register_device_series(biz, OWNER, "device-abc123")
    assert series["prefix"] == "SD1" and series["fy"] == "2627"
    label = pos_tax.series_label(series["prefix"], series["fy"], 1)
    offline = store.create_invoice(biz, OWNER, {
        "client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 1000}], "offline": True,
        "issued_at": "2026-10-23T10:00:00+05:30", "device_id": "device-abc123", "invoice_number": label,
        "payments": [{"method": "cash", "amount_paise": 22400}]})
    assert offline["number"] == label and offline["offline"]
    with pytest.raises(PosError) as e:  # a number can never be used twice
        store.create_invoice(biz, OWNER, {
            "client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 1000}], "offline": True,
            "device_id": "device-abc123", "invoice_number": label,
            "payments": [{"method": "cash", "amount_paise": 22400}]})
    assert e.value.status == 409
    with pytest.raises(PosError):  # another device cannot use this device's series
        store.create_invoice(biz, OWNER, {
            "client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 1000}], "offline": True,
            "device_id": "device-zzz999", "invoice_number": pos_tax.series_label("SD1", "2627", 2),
            "payments": [{"method": "cash", "amount_paise": 22400}]})


def test_credit_note_cancel_ledger_and_statement(store):
    biz = _shop(store)["id"]
    item = _item(store, biz)
    hotel = store.add_customer(biz, OWNER, {"name": "Hotel Annapurna", "address": "Uyyuru"})
    store.set_customer_price(biz, OWNER, hotel["id"], item["id"], 22000)  # restaurant rate
    inv = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "customer_id": hotel["id"], "lines": [
        {"product_id": item["id"], "qty_milli": 10000}], "payments": [{"method": "cash", "amount_paise": 100000}]})
    assert inv["lines"][0]["price_source"] == "customer_rate" and inv["totals"]["grand_total_paise"] == 220000
    assert store.customer(biz, OWNER, hotel["id"])["balance_paise"] == 120000
    note = store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "2 kg returned",
                                                            "lines": [{"line_no": 1, "qty_milli": 2000}]})
    assert note["document_type"] == "credit_note" and note["number"] == "SLC/2627/000001"
    assert note["original_invoice"]["number"] == inv["number"] and note["totals"]["grand_total_paise"] == 44000
    assert store.customer(biz, OWNER, hotel["id"])["balance_paise"] == 76000
    with pytest.raises(PosError):  # cannot credit more than was sold
        store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "x",
                                                         "lines": [{"line_no": 1, "qty_milli": 8001}]})
    with pytest.raises(PosError) as e:  # an invoice with a credit note is never cancelled
        store.cancel_invoice(biz, OWNER, inv["id"], "mistake")
    assert e.value.code == "has_credit_note"
    paid = store.collect(biz, OWNER, hotel["id"], {"client_txn_id": "collect-0001", "method": "upi",
                                                   "amount_paise": 50000})
    assert paid["verification"] == "cashier_confirmed" and paid["balance_paise"] == 26000
    assert store.collect(biz, OWNER, hotel["id"], {"client_txn_id": "collect-0001", "method": "upi",
                                                   "amount_paise": 50000})["replayed"]
    st = store.statement(biz, OWNER, hotel["id"], "2026-10")
    assert st["opening_paise"] == 0 and st["closing_paise"] == 26000
    assert [e["balance_paise"] for e in st["entries"]] == [220000, 120000, 76000, 26000]
    # cancel a second, same-day invoice: row kept, everything reversed
    second = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "customer_id": hotel["id"], "lines": [
        {"product_id": item["id"], "qty_milli": 1000}]})
    stock_before = store.product(biz, OWNER, item["id"])["stock_milli"]
    cancelled = store.cancel_invoice(biz, OWNER, second["id"], "billed twice")
    assert cancelled["status"] == "cancelled" and cancelled["number"] == second["number"]
    assert store.product(biz, OWNER, item["id"])["stock_milli"] == stock_before + 1000
    assert store.customer(biz, OWNER, hotel["id"])["balance_paise"] == 26000


def test_day_close_is_final_and_counts_cash(store):
    biz = _shop(store)["id"]
    item = _item(store, biz)
    store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 1000}],
                                      "payments": [{"method": "cash", "amount_paise": 24000}]})
    store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 500}],
                                      "payments": [{"method": "upi", "amount_paise": 12000}]})
    day = store.day_summary(biz, OWNER, "2026-10-23")
    assert day["invoices"] == 2 and day["sales_paise"] == 36000
    assert day["payments"]["upi"]["cashier_confirmed_paise"] == 12000
    closed = store.close_day(biz, OWNER, {"local_date": "2026-10-23", "opening_float_paise": 50000,
                                          "counted_cash_paise": 73000})
    assert closed["closed"]["expected_cash_paise"] == 74000 and closed["closed"]["difference_paise"] == -1000
    with pytest.raises(PosError) as e:
        store.close_day(biz, OWNER, {"local_date": "2026-10-23", "counted_cash_paise": 1})
    assert e.value.status == 409
    inv = store.invoices(biz, OWNER)[0]
    with pytest.raises(PosError) as e:
        store.cancel_invoice(biz, OWNER, inv["id"], "late")
    assert e.value.code == "day_closed"


def test_gst_summary_and_csv(store):
    biz = _shop(store)["id"]
    a = store.add_product(biz, OWNER, {"name": "Biscuits", "price_paise": 11800, "rate_bp": 1800,
                                       "hsn_sac": "1905"})
    b = _item(store, biz)
    evil = store.add_customer(biz, OWNER, {"name": "=HYPERLINK(evil)"})
    inv = store.create_invoice(biz, OWNER, {"client_txn_id": _txn(), "customer_id": evil["id"], "lines": [
        {"product_id": a["id"], "qty_milli": 2000}, {"product_id": b["id"], "qty_milli": 1000}],
        "payments": [{"method": "cash", "amount_paise": 47600}]})
    store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "return",
                                                     "lines": [{"line_no": 1, "qty_milli": 1000}],
                                                     "refund": {"method": "cash", "amount_paise": 11800}})
    rep = store.gst_summary(biz, OWNER, "2026-10-01", "2026-10-31")
    by = {(r["rate_bp"], r["category"]): r for r in rep["by_rate"]}
    assert by[(1800, "taxable")]["taxable_paise"] == 10000 and by[(1800, "taxable")]["cgst_paise"] == 900
    assert by[(0, "exempt")]["taxable_paise"] == 24000
    assert "not a filed GST return" in rep["disclaimer"]
    csv = store.register_csv(biz, OWNER, "2026-10-01", "2026-10-31")
    assert csv.splitlines()[0].startswith("number,date") and "\"'=HYPERLINK(evil)\"" in csv  # no formula runs
    store.set_member(biz, OWNER, "9100000002", "cashier")
    with pytest.raises(PosError) as e:
        store.gst_summary(biz, CASHIER, "2026-10-01", "2026-10-31")
    assert e.value.status == 403


def test_stock_moves_are_append_only(store):
    biz = _shop(store)["id"]
    item = _item(store, biz)
    with pytest.raises(PosError):
        store.stock_move(biz, OWNER, {"product_id": item["id"], "kind": "adjustment", "qty_milli": -500})
    store.stock_move(biz, OWNER, {"product_id": item["id"], "kind": "purchase", "qty_milli": 5000,
                                  "client_txn_id": "purchase-01"})
    assert store.stock_move(biz, OWNER, {"product_id": item["id"], "kind": "purchase", "qty_milli": 5000,
                                         "client_txn_id": "purchase-01"})["replayed"]
    store.stock_move(biz, OWNER, {"product_id": item["id"], "kind": "count", "qty_milli": 24000})
    moves = store.stock_moves(biz, OWNER, item["id"])
    assert [m["kind"] for m in moves] == ["opening", "purchase", "count"]
    assert moves[-1]["balance_milli"] == 24000 and moves[-1]["qty_milli"] == -1000


# --------------------------------------------------------------------- HTTP
@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    return TestClient(app), auth


def test_http_flow_requires_token_and_membership(api):
    client, auth = api
    owner = f"app-phone-92{uuid.uuid4().int % 10**8:08d}"
    stranger = f"app-phone-93{uuid.uuid4().int % 10**8:08d}"
    assert client.get("/api/pos/businesses").status_code == 401
    assert client.get("/api/pos/meta").json()["states"]["36"] == "Telangana"
    biz = client.post("/api/pos/businesses", headers=auth(owner),
                      json={"name": "Kirana", "state_code": "37", "template": "kirana"}).json()
    assert biz["registration_type"] == "unregistered" and biz["my_role"] == "owner"
    item = client.post(f"/api/pos/businesses/{biz['id']}/products", headers=auth(owner),
                       json={"name": "Rice", "unit": "kg", "price_paise": 6000}).json()
    body = {"client_txn_id": _txn(), "lines": [{"product_id": item["id"], "qty_milli": 2500}],
            "payments": [{"method": "cash", "amount_paise": 15000}]}
    inv = client.post(f"/api/pos/businesses/{biz['id']}/invoices", headers=auth(owner), json=body)
    assert inv.status_code == 200 and inv.json()["document_type"] == "bill" and inv.json()["totals"]["tax_paise"] == 0
    assert client.post(f"/api/pos/businesses/{biz['id']}/invoices", headers=auth(owner), json=body).json()["replayed"]
    assert client.get(f"/api/pos/businesses/{biz['id']}/invoices/{inv.json()['id']}",
                      headers=auth(stranger)).status_code == 404
    bad = client.post(f"/api/pos/businesses/{biz['id']}/invoices", headers=auth(owner),
                      json={**body, "client_txn_id": _txn(), "payments": [{"method": "cash", "amount_paise": 99999}]})
    assert bad.status_code == 400 and bad.json()["detail"]["code"] == "payment"
    csv = client.get(f"/api/pos/businesses/{biz['id']}/reports/register.csv?date_from=2026-01-01&date_to=2030-01-01",
                     headers=auth(owner))
    assert csv.status_code == 200 and csv.headers["content-type"].startswith("text/csv")


def test_account_deletion_ends_pos_membership(api):
    client, auth = api
    owner = f"app-phone-94{uuid.uuid4().int % 10**8:08d}"
    staff = f"app-phone-95{uuid.uuid4().int % 10**8:08d}"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Shop", "state_code": "36"}).json()
    client.post(f"/api/pos/businesses/{biz['id']}/members", headers=auth(owner),
                json={"phone": staff[-10:], "role": "cashier"})
    assert client.get(f"/api/pos/businesses/{biz['id']}", headers=auth(staff)).status_code == 200
    assert client.delete("/api/me?confirm=DELETE", headers=auth(staff)).status_code == 200
    assert client.get("/api/pos/businesses", headers=auth(owner)).json()["businesses"]
