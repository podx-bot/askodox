"""Own payment methods (any app's UPI QR / bank) + POS collect to the shop's own UPI + online order pay-to."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.payment_methods import PaymentMethodError, PaymentMethods, parse_upi_qr
from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_store import PosError, PosStore
from app.services.secret_box import SecretBox

OWNER = "app-phone-9400000501"
CASHIER = "app-phone-9400000502"
PHONEPE = "com.phonepe.app.business"


def test_parse_any_upi_qr():
    assert parse_upi_qr("upi://pay?pa=lakshmi.kirana@ybl&pn=Lakshmi%20Kirana&mc=5411") == \
        {"upi_id": "lakshmi.kirana@ybl", "payee_name": "Lakshmi Kirana"}
    assert parse_upi_qr("UPI://pay?pa=shop@okhdfcbank")["upi_id"] == "shop@okhdfcbank"
    assert parse_upi_qr("9876543210@paytm")["upi_id"] == "9876543210@paytm"
    for bad in ("https://example.com", "ASKODOX-SHOP:123456", "upi://pay?pn=NoId"):
        with pytest.raises(PaymentMethodError):
            parse_upi_qr(bad)


def test_methods_default_bank_encrypted_and_remove(tmp_path):
    db = str(tmp_path / "pm.db")
    pm = PaymentMethods(db, SecretBox("k" * 40))
    methods = pm.add(OWNER, {"kind": "upi", "qr_text": "upi://pay?pa=lk@ybl&pn=LK", "app": "PhonePe"})
    assert methods[0]["is_default"] and methods[0]["upi_id"] == "lk@ybl"
    with pytest.raises(PaymentMethodError):
        pm.add(OWNER, {"kind": "upi", "upi_id": "LK@ybl"})
    methods = pm.add(OWNER, {"kind": "bank", "account_holder": "Lakshmi", "account_number": "50100012345678",
                             "ifsc": "hdfc0001234", "bank_name": "HDFC"})
    bank = next(m for m in methods if m["kind"] == "bank")
    assert bank["account_number"] == "50100012345678" and bank["account_last4"] == "5678" and bank["ifsc"] == "HDFC0001234"
    import sqlite3

    with sqlite3.connect(db) as conn:
        stored = conn.execute("SELECT account_enc FROM user_payment_methods WHERE kind='bank'").fetchone()[0]
    assert stored.startswith("enc:v1:") and "50100012345678" not in stored
    pm.set_default(OWNER, bank["id"])
    assert pm.default_upi(OWNER)["upi_id"] == "lk@ybl", "default UPI = the only UPI even when the bank is default"
    left = pm.remove(OWNER, bank["id"])
    assert [m["kind"] for m in left] == ["upi"] and left[0]["is_default"]
    with pytest.raises(PaymentMethodError) as err:
        PaymentMethods(db, SecretBox()).add(OWNER, {"kind": "bank", "account_holder": "x", "account_number": "1234567",
                                                    "ifsc": "HDFC0001234"})
    assert err.value.status == 503, "never store an account number without encryption"


def test_pay_to_links_have_amount(tmp_path):
    pm = PaymentMethods(str(tmp_path / "pm.db"), SecretBox("k" * 40))
    pm.add(OWNER, {"kind": "upi", "upi_id": "lk@ybl", "payee_name": "Lakshmi Kirana"})
    out = pm.pay_to(OWNER, amount=250.0, note="ASKODOX order 7", reference="ASKODOX7")
    assert out[0]["upi_link"].startswith("upi://pay?pa=lk@ybl") and "am=250.00" in out[0]["upi_link"]


@pytest.fixture()
def shop(tmp_path):
    db = str(tmp_path / "pos.db")
    clock = {"now": datetime(2026, 10, 27, 4, 0, tzinfo=timezone.utc)}
    store = PosStore(db, clock=lambda: clock["now"])
    pm = PaymentMethods(db, SecretBox("k" * 40))
    alerts = PosPaymentAlerts(store, methods=pm)
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000502", "cashier")
    store.business(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"enabled": True})
    return store, pm, alerts, biz, clock


def test_collect_needs_owner_upi_then_matches_notification_never_confirms(shop):
    store, pm, alerts, biz, clock = shop
    with pytest.raises(PosError) as err:
        alerts.create_request(biz, CASHIER, {"amount_paise": 25000})
    assert err.value.code == "no_upi"
    pm.add(OWNER, {"kind": "upi", "upi_id": "lk@ybl", "payee_name": "Lakshmi Kirana"})
    second = pm.add(OWNER, {"kind": "upi", "upi_id": "9400000501@okhdfcbank"})[1]
    with pytest.raises(PosError):
        alerts.set_collect_method(biz, CASHIER, second["id"])
    assert alerts.set_collect_method(biz, OWNER, second["id"])["method"]["upi_id"] == "9400000501@okhdfcbank"
    assert alerts.collect_settings(biz, CASHIER)["options"] == [], "staff never see the owner's other accounts"
    req = alerts.create_request(biz, CASHIER, {"amount_paise": 25000, "label": "Bill INV-12"})
    assert req["status"] == "pending" and "am=250.00" in req["upi_link"] and "pa=9400000501@okhdfcbank" in req["upi_link"]
    other = alerts.create_request(biz, CASHIER, {"amount_paise": 9900})
    event = alerts.report(biz, OWNER, {"client_event_id": f"{PHONEPE}|k1|1", "source_app": PHONEPE,
                                       "amount_paise": 25000})
    assert event["matched_request"]["id"] == req["id"]
    by_id = {r["id"]: r for r in alerts.requests(biz, OWNER)}
    assert by_id[req["id"]]["status"] == "matched" and by_id[other["id"]]["status"] == "pending"
    assert not by_id[req["id"]]["confirmed"], "a notification never confirms a payment by itself"
    assert alerts.decide_request(biz, CASHIER, req["id"], "confirm")["status"] == "confirmed"
    clock["now"] += timedelta(hours=1)
    late = alerts.report(biz, OWNER, {"client_event_id": f"{PHONEPE}|k2|2", "source_app": PHONEPE, "amount_paise": 9900})
    assert late["matched_request"] is None, "older than 30 minutes: not matched"


def test_http_methods_and_order_pay_to(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    from dataclasses import replace

    monkeypatch.setattr(container, "settings", replace(container.settings, secrets_key="k" * 40))
    monkeypatch.setattr(container, "payment_methods", None, raising=False)
    secret = container.settings.session_token_secret
    seller = "app-phone-9411100501"
    auth = {"Authorization": f"Bearer {issue_token(seller, secret)}"}
    client = TestClient(app)
    assert client.get("/api/me/payment-methods").status_code == 401
    preview = client.post("/api/me/payment-methods/read-qr", headers=auth,
                          json={"qr_text": "upi://pay?pa=seller@ybl&pn=Ravi%20Stores"}).json()
    assert preview == {"upi_id": "seller@ybl", "payee_name": "Ravi Stores"}
    out = client.post("/api/me/payment-methods", headers=auth,
                      json={"kind": "upi", "qr_text": "upi://pay?pa=seller@ybl&pn=Ravi%20Stores", "app": "PhonePe"})
    assert out.status_code == 200 and out.json()["methods"][0]["upi_id"] == "seller@ybl"
    from app.api.routes.orders import _pay_to
    from app.services import deal_lifecycle as lifecycle

    order = {"id": 77, "seller_user_id": seller, "status": lifecycle.ACCEPTED, "payment_state": "AWAITING_PAYMENT",
             "settlement_method": lifecycle.DIRECT_UPI, "total_amount": 400}
    shown = _pay_to(container, order, "buyer")
    assert shown and "am=400.00" in shown[0]["upi_link"]
    assert _pay_to(container, order, "seller") == []
    assert _pay_to(container, {**order, "status": "REQUESTED"}, "buyer") == [], "only after the seller accepts"


def test_live_platform_checkout_never_collects_order_money(monkeypatch):
    from types import SimpleNamespace

    import pytest as _pytest
    from fastapi import HTTPException

    from app.api.routes import orders
    from app.services import commerce_finance as fin
    from app.services import deal_lifecycle as lifecycle

    class Registry:
        def status(self, provider):
            return {"status": fin.STATUS_LIVE}

    pf = SimpleNamespace(checkout_provider=lambda: "razorpay", registry=Registry())
    cc = SimpleNamespace(flags=lambda: {})
    monkeypatch.setattr("app.api.routes.platform.platform", lambda container: pf)
    monkeypatch.setattr("app.api.routes.command_center.command_center", lambda container: cc)
    order = {"id": 5, "status": lifecycle.ACCEPTED, "payment_state": "AWAITING_PAYMENT", "total_amount": 100}
    with _pytest.raises(HTTPException) as err:
        orders._online_payment(SimpleNamespace(), None, order, "start_online", None)
    assert err.value.status_code == 409 and "does not collect" in err.value.detail
