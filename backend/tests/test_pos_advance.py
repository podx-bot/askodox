"""Shop advance: every change waits for the CUSTOMER's own approval; the shop can never spend it alone."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_advance import TERMS, TERMS_VERSION, PosAdvances
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000101"
CASHIER = "app-phone-9400000102"
CUSTOMER = "app-phone-9876543210"
STRANGER = "app-phone-9000000009"


def _txn():
    return "t-" + uuid.uuid4().hex


@pytest.fixture()
def env(tmp_path):
    now = [datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    adv = PosAdvances(store)
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "template": "kirana", "invoice_prefix": "LK", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000102", "cashier")
    cust = store.add_customer(biz, OWNER, {"name": "Ramu", "phone": "+91 98765 43210"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Rice 1kg", "unit": "pcs", "price_paise": 6000})["id"]
    return store, adv, biz, cust, item, now


def _on(adv, biz, limit=200_000):
    return adv.update_settings(biz, OWNER, {"enabled": True, "max_balance_paise": limit,
                                            "accept_terms_version": TERMS_VERSION})


def test_owner_must_accept_terms_and_limits_are_capped(env):
    store, adv, biz, cust, item, now = env
    with pytest.raises(PosError) as e:
        adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 50000, "method": "cash", "client_txn_id": _txn()})
    assert e.value.code == "advance_off"
    with pytest.raises(PosError) as e:
        adv.update_settings(biz, OWNER, {"enabled": True})
    assert e.value.code == "terms"
    with pytest.raises(PosError):
        adv.update_settings(biz, CASHIER, {"enabled": True, "accept_terms_version": TERMS_VERSION})
    with pytest.raises(PosError) as e:
        _on(adv, biz, limit=5_000_000)
    assert e.value.code == "max_balance"
    s = _on(adv, biz)
    assert s["enabled"] and s["max_balance_paise"] == 200_000
    assert "not responsible" in TERMS["en"] and "ASKODOX కి ఏ సంబంధం లేదు" in TERMS["te"]


def test_deposit_counts_only_after_the_customer_confirms(env):
    store, adv, biz, cust, item, now = env
    _on(adv, biz)
    dep = adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 50000, "method": "cash", "client_txn_id": _txn()})
    assert dep["status"] == "pending"
    assert adv.customer_view(biz, OWNER, cust)["balance_paise"] == 0, "nothing counts before approval"
    assert adv.mine(STRANGER)["shops"] == [], "another number never sees it"
    with pytest.raises(PosError) as e:
        adv.decide(STRANGER, dep["id"], True, TERMS_VERSION)
    assert e.value.status == 404
    with pytest.raises(PosError):
        adv.decide(OWNER, dep["id"], True, TERMS_VERSION)  # the shop cannot approve for the customer
    mine = adv.mine(CUSTOMER)
    assert mine["shops"][0]["shop"] == "Lakshmi Kirana" and mine["shops"][0]["pending"][0]["id"] == dep["id"]
    with pytest.raises(PosError) as e:
        adv.decide(CUSTOMER, dep["id"], True)  # first time: terms must be accepted
    assert e.value.code == "terms"
    out = adv.decide(CUSTOMER, dep["id"], True, TERMS_VERSION)
    assert out["status"] == "approved" and out["balance_paise"] == 50000
    day = store.day_summary(biz, OWNER, "2026-10-24")
    assert day["payments"]["cash"]["net_paise"] == 50000, "the cash the shop received is in its day close"
    with pytest.raises(PosError):
        adv.decide(CUSTOMER, dep["id"], True)  # already decided


def test_paying_a_bill_from_the_advance_needs_customer_approval(env):
    store, adv, biz, cust, item, now = env
    _on(adv, biz)
    dep = adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 50000, "method": "upi", "client_txn_id": _txn()})
    adv.decide(CUSTOMER, dep["id"], True, TERMS_VERSION)
    with pytest.raises(PosError) as e:
        adv.request(biz, CASHIER, cust, "redeem", {"amount_paise": 12000, "client_txn_id": _txn()})
    assert e.value.code == "more_than_due", "nothing is owed yet"
    store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust,
                                        "lines": [{"product_id": item, "qty_milli": 2000}], "payments": []})
    with pytest.raises(PosError) as e:
        adv.request(biz, CASHIER, cust, "redeem", {"amount_paise": 60000, "client_txn_id": _txn()})
    assert e.value.code == "insufficient"
    red = adv.request(biz, CASHIER, cust, "redeem", {"amount_paise": 12000, "client_txn_id": _txn()})
    assert adv.customer_view(biz, OWNER, cust)["balance_paise"] == 50000
    rej = adv.decide(CUSTOMER, red["id"], False)
    assert rej["status"] == "rejected" and rej["balance_paise"] == 50000, "a refusal changes nothing"
    red = adv.request(biz, CASHIER, cust, "redeem", {"amount_paise": 12000, "client_txn_id": _txn()})
    ok = adv.decide(CUSTOMER, red["id"], True)
    assert ok["balance_paise"] == 38000
    view = adv.customer_view(biz, OWNER, cust)
    assert view["due_paise"] == 0, "the bill is paid"
    day = store.day_summary(biz, OWNER, "2026-10-24")
    assert day["payments"]["advance"]["net_paise"] == 12000 and "cash" not in day["payments"]


def test_refund_limit_expiry_withdraw_and_idempotency(env):
    store, adv, biz, cust, item, now = env
    _on(adv, biz, limit=100_000)
    txn = _txn()
    dep = adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 80000, "method": "cash", "client_txn_id": txn})
    again = adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 80000, "method": "cash", "client_txn_id": txn})
    assert again["replayed"] and again["id"] == dep["id"]
    adv.decide(CUSTOMER, dep["id"], True, TERMS_VERSION)
    with pytest.raises(PosError) as e:
        adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 30000, "method": "cash", "client_txn_id": _txn()})
    assert e.value.code == "max_balance"
    with pytest.raises(PosError):
        adv.request(biz, CASHIER, cust, "refund", {"amount_paise": 10000, "method": "cash", "client_txn_id": _txn()})
    ref = adv.request(biz, OWNER, cust, "refund", {"amount_paise": 30000, "method": "cash", "client_txn_id": _txn()})
    assert adv.decide(CUSTOMER, ref["id"], True)["balance_paise"] == 50000
    red = adv.request(biz, CASHIER, cust, "deposit",
                      {"amount_paise": 1000, "method": "cash", "client_txn_id": _txn()})
    assert adv.withdraw(biz, CASHIER, red["id"])["status"] == "withdrawn"
    with pytest.raises(PosError):
        adv.decide(CUSTOMER, red["id"], True)
    late = adv.request(biz, CASHIER, cust, "deposit", {"amount_paise": 1000, "method": "cash", "client_txn_id": _txn()})
    now[0] = now[0] + timedelta(days=8)
    with pytest.raises(PosError) as e:
        adv.decide(CUSTOMER, late["id"], True)
    assert e.value.code == "status" and "expired" in e.value.message
    assert adv.customer_view(biz, OWNER, cust)["balance_paise"] == 50000


def test_customer_without_a_mobile_number_cannot_get_an_advance(env):
    store, adv, biz, cust, item, now = env
    _on(adv, biz)
    walk_in = store.add_customer(biz, OWNER, {"name": "Walk-in"})["id"]
    with pytest.raises(PosError) as e:
        adv.request(biz, CASHIER, walk_in, "deposit", {"amount_paise": 1000, "method": "cash", "client_txn_id": _txn()})
    assert e.value.code == "customer_phone"


def test_http_customer_approves_in_their_own_app(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_advances", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner, customer = "app-phone-9411100001", "app-phone-9811100002"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Shop", "state_code": "36"}).json()["id"]
    cust = client.post(f"/api/pos/businesses/{biz}/customers", headers=auth(owner),
                       json={"name": "Sita", "phone": "9811100002"}).json()["id"]
    terms = client.get(f"/api/pos/businesses/{biz}/advance/settings", headers=auth(owner)).json()
    assert terms["enabled"] is False and terms["terms"]["te"]
    assert client.put(f"/api/pos/businesses/{biz}/advance/settings", headers=auth(owner),
                      json={"enabled": True, "accept_terms_version": terms["terms_version"]}).status_code == 200
    dep = client.post(f"/api/pos/businesses/{biz}/customers/{cust}/advance/deposit", headers=auth(owner),
                      json={"amount_paise": 20000, "method": "cash", "client_txn_id": _txn()}).json()
    assert dep["status"] == "pending"
    assert client.get("/api/pos/me/advances").status_code == 401
    mine = client.get("/api/pos/me/advances", headers=auth(customer)).json()
    assert mine["shops"][0]["pending"][0]["id"] == dep["id"] and mine["shops"][0]["accepted_terms"] is False
    assert client.post(f"/api/pos/me/advances/{dep['id']}/decision", headers=auth(owner),
                       json={"approve": True, "accept_terms_version": TERMS_VERSION}).status_code == 404
    ok = client.post(f"/api/pos/me/advances/{dep['id']}/decision", headers=auth(customer),
                     json={"approve": True, "accept_terms_version": TERMS_VERSION}).json()
    assert ok["status"] == "approved" and ok["balance_paise"] == 20000
    view = client.get(f"/api/pos/businesses/{biz}/customers/{cust}/advance", headers=auth(owner)).json()
    assert view["balance_paise"] == 20000
