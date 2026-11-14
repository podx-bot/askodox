"""POS payment voice alerts: notification-only events, dedupe, staff fan-out, roles, kill switch."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_payment_alerts import PosPaymentAlerts, announcement
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000301"
CASHIER = "app-phone-9400000302"
ACCOUNTANT = "app-phone-9400000303"
STRANGER = "app-phone-9400000399"
PHONEPE = "com.phonepe.app.business"


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 26, 5, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now


@pytest.fixture()
def env(tmp_path):
    clock = Clock()
    store = PosStore(str(tmp_path / "pos.db"), clock=clock)
    pushes = []
    feature = {"on": True}
    alerts = PosPaymentAlerts(store, notify=lambda *a: pushes.append(a), feature_on=lambda: feature["on"])
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000302", "cashier")
    store.set_member(biz, OWNER, "9400000303", "accountant")
    # staff link their app identity the first time they open the shop
    store.business(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"enabled": True})
    owner_dev = alerts.register_device(biz, OWNER, {"device_key": "owner-phone-1", "label": "Counter phone",
                                                    "listener_on": True})["device_id"]
    cashier_dev = alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-1", "label": "Cashier"})["device_id"]
    return store, alerts, biz, owner_dev, cashier_dev, pushes, feature, clock


def _event(owner_dev, n="1", **kw):
    data = {"client_event_id": f"{PHONEPE}|key{n}|1729900000{n}", "source_app": PHONEPE, "amount_paise": 50000,
            "device_id": owner_dev, "spoken": "announced"}
    data.update(kw)
    return data


def test_valid_notification_is_unverified_and_fans_out_to_staff(env):
    store, alerts, biz, owner_dev, cashier_dev, pushes, _, _ = env
    e = alerts.report(biz, OWNER, _event(owner_dev, reference="T2410261234567890"))
    assert e["status"] == "notification_unverified" and e["verification"] == "notification_only"
    assert e["verified"] is False and e["duplicate"] is False
    assert e["reference_tail"] == "7890" and e["source_label"] == "PhonePe Business"
    assert e["receiving_device"] == "Counter phone"
    assert "బ్యాంకులో నిర్ధారించుకోండి" in e["announcement"]["te"], "unverified wording always asks to check the bank"
    assert [p[0] for p in pushes] == [CASHIER], "staff device gets the alert; the reporter does not"
    assert pushes[0][3] == f"/pos/{biz}/payment-alerts"
    assert e["delivery_pending"] == 1, "cashier device has not acknowledged yet"
    done = alerts.ack(biz, CASHIER, e["id"], {"device_id": cashier_dev, "state": "announced"})
    assert done["delivery_pending"] == 0 and done["status"] == "notification_unverified", "sharing never changes status"
    # nothing reached POS payments / revenue
    with store._connect() as conn:
        assert conn.execute("SELECT COUNT(*) FROM pos_payments").fetchone()[0] == 0


def test_duplicate_by_reference_and_by_event_id(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    a = alerts.report(biz, OWNER, _event(owner_dev, "1", reference="UTR998877665544"))
    b = alerts.report(biz, OWNER, _event(owner_dev, "2", reference="UTR998877665544"))  # update of same payment
    assert b["duplicate"] is True and b["id"] == a["id"]
    c = alerts.report(biz, OWNER, _event(owner_dev, "3", amount_paise=70000))  # a different payment
    d = alerts.report(biz, OWNER, _event(owner_dev, "3", amount_paise=70000))
    assert d["duplicate"] is True and d["id"] == c["id"]
    assert len(pushes) == 2, "a duplicate never alerts twice"
    assert alerts.events(biz, OWNER, status="duplicate")["events"][0]["duplicates"] >= 1


def test_same_payment_reported_twice_speaks_once(env):
    """Owner 2026-11-14: one payment gave 2 notifications (PhonePe re-posted it a minute later)."""
    _, alerts, biz, owner_dev, _, pushes, _, clock = env
    a = alerts.report(biz, OWNER, _event(owner_dev, "1"))
    clock.now = clock.now + timedelta(minutes=1)
    b = alerts.report(biz, OWNER, _event(owner_dev, "2"))  # same amount, new notification key
    assert b["duplicate"] is True and b["id"] == a["id"]
    assert len(pushes) == 1, "a second report of the same payment never alerts again"
    assert alerts.events(biz, OWNER)["last_24h"]["count"] == 1


def test_phone_and_razorpay_for_one_payment_are_one_event(env):
    """Owner 2026-11-14: the Razorpay webhook and the phone's PhonePe notification gave 2 alerts."""
    _, alerts, biz, owner_dev, _, pushes, _, clock = env
    phone = alerts.report(biz, OWNER, _event(owner_dev, "1"))
    clock.now = clock.now + timedelta(seconds=30)
    verified = alerts.record_verified(biz, provider="razorpay", label="Razorpay", amount_paise=50000,
                                      payment_id="pay_ABC123", reference="pay_ABC123")
    assert verified["id"] == phone["id"] and verified["duplicate"] is True
    assert verified["status"] == "provider_verified"
    assert len(pushes) == 1, "the bank-confirmed copy does not speak again"
    last = alerts.events(biz, OWNER)["last_24h"]
    assert last["count"] == 0, "the one payment is no longer an unverified notification"
    assert last["verified_count"] == 1, "it is now the single bank-confirmed event"


def test_same_amount_far_apart_are_separate_payments(env):
    _, alerts, biz, owner_dev, _, _, _, clock = env
    a = alerts.report(biz, OWNER, _event(owner_dev, "1"))
    clock.now = clock.now + timedelta(minutes=6)  # outside the window
    b = alerts.report(biz, OWNER, _event(owner_dev, "2"))
    assert a["id"] != b["id"] and not b["duplicate"]
    assert alerts.events(biz, OWNER)["last_24h"]["count"] == 2


def test_missing_amount_is_ambiguous_and_unsupported_app_refused(env):
    _, alerts, biz, owner_dev, _, _, _, _ = env
    e = alerts.report(biz, OWNER, _event(owner_dev, amount_paise=None, reason="amount_missing"))
    assert e["status"] == "ambiguous" and "మొత్తం స్పష్టంగా లేదు" in e["announcement"]["te"]
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "9", source_app="com.whatsapp"))
    assert err.value.code == "unsupported_app"


def test_client_can_never_claim_bank_verified(env):
    _, alerts, biz, owner_dev, _, _, _, _ = env
    for fake in ({"verification": "bank_verified"}, {"status": "provider_verified"}):
        with pytest.raises(PosError) as err:
            alerts.report(biz, OWNER, _event(owner_dev, **fake))
        assert err.value.code == "verification"


def test_test_event_works_even_before_enabling_and_is_labelled(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    alerts.update_settings(biz, OWNER, {"enabled": False})
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev))
    assert err.value.code == "not_enabled"
    t = alerts.report(biz, OWNER, {"client_event_id": "test-evt-000001", "amount_paise": 100, "test": True,
                                   "device_id": owner_dev})
    assert t["test"] is True and t["announcement"]["te"].startswith("టెస్ట్")
    assert alerts.events(biz, OWNER)["last_24h"]["count"] == 0, "test events are never counted"
    assert pushes and "(test)" in pushes[-1][1]


def test_roles_revocation_and_shop_isolation(env):
    store, alerts, biz, owner_dev, cashier_dev, pushes, _, _ = env
    with pytest.raises(PosError) as err:
        alerts.events(biz, STRANGER)
    assert err.value.status == 404
    store.business(biz, ACCOUNTANT)
    with pytest.raises(PosError) as err:
        alerts.events(biz, ACCOUNTANT)
    assert err.value.status == 403, "accountant is not in the default alert roles"
    alerts.update_settings(biz, OWNER, {"roles": ["manager"]})
    with pytest.raises(PosError):
        alerts.events(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"roles": ["manager", "cashier"]})
    with pytest.raises(PosError) as err:
        alerts.update_settings(biz, CASHIER, {"enabled": False})
    assert err.value.status == 403
    alerts.revoke_device(biz, OWNER, cashier_dev)
    pushes.clear()
    alerts.report(biz, OWNER, _event(owner_dev, "5"))
    assert pushes == [], "a revoked device's user gets no fan-out"
    with pytest.raises(PosError) as err:
        alerts.ack(biz, CASHIER, alerts.events(biz, OWNER)["events"][0]["id"], {"device_id": cashier_dev, "state": "seen"})
    assert err.value.code == "device_revoked"
    # second shop is isolated
    other = store.create_business(STRANGER, {"name": "Other", "state_code": "36"})["id"]
    alerts.update_settings(other, STRANGER, {"enabled": True})
    assert alerts.events(other, STRANGER)["events"] == []
    with pytest.raises(PosError):
        alerts.report(other, OWNER, _event(owner_dev, "6"))


def test_delayed_and_future_notifications(env):
    _, alerts, biz, owner_dev, _, _, _, clock = env
    late = (clock.now - timedelta(hours=5)).isoformat()
    e = alerts.report(biz, OWNER, _event(owner_dev, "7", detected_at=late))
    assert e["detected_at"] == late, "offline phone syncs later with its real detection time"
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "8", detected_at=(clock.now - timedelta(days=4)).isoformat()))
    assert err.value.code == "too_old"
    with pytest.raises(PosError):
        alerts.report(biz, OWNER, _event(owner_dev, "9", detected_at=(clock.now + timedelta(hours=1)).isoformat()))


def test_restart_keeps_history_and_retention_expires(env, tmp_path):
    store, alerts, biz, owner_dev, _, _, _, clock = env
    alerts.report(biz, OWNER, _event(owner_dev, "1"))
    again = PosPaymentAlerts(PosStore(store.db_path, clock=clock))  # backend restart
    assert len(again.events(biz, OWNER)["events"]) == 1
    clock.now += timedelta(days=91)
    assert again.events(biz, OWNER)["events"] == []


def test_push_failure_never_fails_report_and_kill_switch(env):
    store, _, biz, owner_dev, _, _, feature, clock = env

    def boom(*args):
        raise RuntimeError("FCM down")

    alerts = PosPaymentAlerts(store, notify=boom, feature_on=lambda: feature["on"])
    assert alerts.report(biz, OWNER, _event(owner_dev, "1"))["id"]
    feature["on"] = False
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "2"))
    assert err.value.status == 503 and alerts.settings(biz, OWNER)["feature_on"] is False


def test_settings_validation_and_announcements():
    assert announcement(50000, "te") == "500 రూపాయల పేమెంట్ నోటిఫికేషన్ వచ్చింది. బ్యాంకులో నిర్ధారించుకోండి."
    assert announcement(50000, "te", verified=True) == "మీకు 500 రూపాయలు అందాయి."
    assert announcement(12550, "en").startswith("Payment notification of 125 rupees 50 paise")
    assert "बैंक" in announcement(100, "hi")


def test_settings_rejects_bad_values(env):
    _, alerts, biz, *_ = env
    for bad in ({"quiet_start": "25:00", "quiet_end": "06:00"}, {"quiet_start": "22:00"}, {"apps": {"not a pkg": "x"}},
                {"language": "fr"}):
        with pytest.raises(PosError):
            alerts.update_settings(biz, OWNER, bad)
    s = alerts.update_settings(biz, OWNER, {"quiet_start": "22:00", "quiet_end": "06:00", "language": "hi"})
    assert s["quiet_start"] == "22:00" and s["language"] == "hi" and s["can_edit"] is True


def test_voice_picker_and_payer_name_switch(env):
    _, alerts, biz, *_ = env
    s = alerts.settings(biz, OWNER)
    assert s["say_name"] is True and s["shop_name"]  # name spoken by default; the phone needs the shop name
    s = alerts.update_settings(biz, OWNER, {"voice": "male2", "say_name": False})
    assert s["voice"] == "male2" and s["say_name"] is False
    s = alerts.update_settings(biz, OWNER, {"language": "en"})  # other changes keep both
    assert s["voice"] == "male2" and s["say_name"] is False
    with pytest.raises(PosError):
        alerts.update_settings(biz, OWNER, {"voice": "robot"})


def test_http_flow(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_payment_alerts", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner = "app-phone-9411100301"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Shop", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}/payment-alerts"
    assert client.get(f"{base}/settings").status_code == 401
    s = client.get(f"{base}/settings", headers=auth(owner)).json()
    assert s["enabled"] is False and PHONEPE in s["apps"] and s["language"] == "te"
    assert client.put(f"{base}/settings", headers=auth(owner), json={"enabled": True}).json()["enabled"] is True
    dev = client.post(f"{base}/devices", headers=auth(owner), json={"device_key": "phone-key-123", "label": "Counter",
                                                                     "listener_on": True}).json()["device_id"]
    r = client.post(f"{base}/events", headers=auth(owner), json={"client_event_id": "evt-http-0001", "source_app": PHONEPE,
                                                                 "amount_paise": 25000, "device_id": dev})
    assert r.status_code == 200 and r.json()["status"] == "notification_unverified"
    fake = client.post(f"{base}/events", headers=auth(owner), json={"client_event_id": "evt-http-0002",
                                                                    "source_app": PHONEPE, "amount_paise": 25000,
                                                                    "status": "provider_verified"})
    assert fake.status_code == 400
    listed = client.get(f"{base}/events", headers=auth(owner)).json()
    assert len(listed["events"]) == 1 and listed["last_24h"]["notified_total_paise"] == 25000
    csv = client.get(f"{base}/export.csv", headers=auth(owner))
    assert csv.status_code == 200 and "Not bank-verified" in csv.text and "250.00" in csv.text
    assert "pos.payment_alerts" in client.get("/api/flags").json()["flags"]


def test_alert_carries_speak_data_for_closed_app(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    alerts.report(biz, OWNER, _event(owner_dev, "77"))
    speak = pushes[-1][5]
    assert speak["type"] == "payalert" and speak["verified"] == "0" and speak["language"] == "te"
    assert "బ్యాంకులో నిర్ధారించుకోండి" in speak["text"]


def test_push_service_data_message_is_high_priority_once(tmp_path):
    from app.services.push_service import PushService

    class Client:
        def __init__(self):
            self.sent = []

        def post(self, url, json=None, headers=None, data=None):
            self.sent.append(json)

            class R:
                status_code = 200
                text = ""
            return R()

    client = Client()
    push = PushService(str(tmp_path / "p.db"), service_account_json='{"project_id":"p","client_email":"e","private_key":"k"}',
                       client=client)
    push._access = ("tok", 9e12)
    push.register("u1", "fcm-token-1")
    n = push.send_data("u1", data={"type": "payalert", "text": "hi"}, event_key="payalert:e1")
    assert n == 1 and push.send_data("u1", data={"type": "payalert"}, event_key="payalert:e1") == 0
    msg = client.sent[0]["message"]
    assert msg["android"]["priority"] == "high" and "notification" not in msg and msg["data"]["type"] == "payalert"


def test_attendant_role_hears_alerts_only_when_the_owner_allows_it_and_cannot_bill(env):
    """Owner 2026-11-10: manager / cashier / attendant chosen by the owner get the payment sound."""
    store, alerts, biz, owner_dev, _cashier_dev, pushes, _, _ = env
    attendant = "app-phone-9400000304"
    store.set_member(biz, OWNER, "9400000304", "attendant")
    store.business(biz, attendant)  # the attendant opens the shop once (links their app identity)
    with pytest.raises(PosError) as e:
        alerts.register_device(biz, attendant, {"device_key": "attendant-phone-1", "label": "Pump 2"})
    assert e.value.status == 403, "not allowed until the owner ticks the role"
    assert "attendant" in alerts.settings(biz, OWNER)["all_roles"]
    alerts.update_settings(biz, OWNER, {"roles": ["manager", "cashier", "attendant"]})
    alerts.register_device(biz, attendant, {"device_key": "attendant-phone-1", "label": "Pump 2"})
    pushes.clear()
    alerts.report(biz, OWNER, _event(owner_dev, n="7", reference="T2410269999999991"))
    assert attendant in [p[0] for p in pushes], "the attendant's phone gets the alert"
    with pytest.raises(PosError) as e:
        store.members(biz, attendant)
    assert e.value.status == 403, "an attendant cannot manage staff"


def test_razorpay_partner_signup_link_only_from_a_razorpay_https_url(env, monkeypatch):
    from app.services.commerce_finance import razorpay_partner_signup_url

    ok = "https://razorpay.com/partners/signup/?ref=askodox"
    assert razorpay_partner_signup_url({"ASKODOX_RAZORPAY_PARTNER_URL": ok}) == ok
    assert razorpay_partner_signup_url({"ASKODOX_RAZORPAY_PARTNER_URL": "https://rzp.io/l/askodox"}) == "https://rzp.io/l/askodox"
    for bad in ("", "http://razorpay.com/x", "https://evil.example/razorpay.com", "https://razorpay.com.evil.in/x",
                "javascript:alert(1)"):
        assert razorpay_partner_signup_url({"ASKODOX_RAZORPAY_PARTNER_URL": bad}) == ""
    _, alerts, biz, *_ = env
    monkeypatch.delenv("ASKODOX_RAZORPAY_PARTNER_URL", raising=False)
    assert alerts.settings(biz, OWNER)["razorpay_signup_url"] == ""
    monkeypatch.setenv("ASKODOX_RAZORPAY_PARTNER_URL", ok)
    assert alerts.settings(biz, CASHIER)["razorpay_signup_url"] == ok
    phrases = alerts.settings(biz, OWNER)["phrases"]
    assert "money received" in phrases["incoming"] and isinstance(phrases["reject"], list)


def test_sender_chooses_who_hears_and_listener_can_mute_or_pause(env):
    store, alerts, biz, owner_dev, cashier_dev, pushes, _feature, clock = env
    cashier_dev2 = alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-1"})["device_id"]
    assert cashier_dev2 == cashier_dev
    store.set_member(biz, OWNER, "9400000302", "cashier", "Ravi")
    view = alerts.settings(biz, OWNER)
    people = {p["role"]: p for p in view["people"]}
    assert people["cashier"]["name"] == "Ravi" and people["owner"]["me"] is True
    assert all(CASHIER not in str(p) and "9400000302" not in str(p) for p in view["people"]), "refs never leak ids"
    ravi = people["cashier"]["ref"]

    # default: everyone allowed hears, and the spoken text says whose payment it is
    alerts.report(biz, OWNER, _event(owner_dev, "11"))
    assert [p[0] for p in pushes] == [CASHIER]
    assert pushes[-1][5]["text"].startswith("యజమాని: 500 రూపాయల")
    alerts.report(biz, CASHIER, _event(cashier_dev, "12", amount_paise=20000))
    assert pushes[-1][0] == OWNER and pushes[-1][5]["text"].startswith("Ravi: ")

    # the cashier keeps their own payments to themselves
    pushes.clear()
    assert alerts.set_share(biz, CASHIER, {"mode": "none"})["my_share"]["mode"] == "none"
    alerts.report(biz, CASHIER, _event(cashier_dev, "13", amount_paise=30000))
    assert pushes == []
    # the owner shares only with chosen people (refs outside the shop are dropped)
    out = alerts.set_share(biz, OWNER, {"mode": "some", "listeners": [ravi, "nope"]})
    assert out["my_share"] == {"mode": "some", "listeners": [ravi]}
    alerts.report(biz, OWNER, _event(owner_dev, "14", amount_paise=40000))
    assert [p[0] for p in pushes] == [CASHIER]
    alerts.set_share(biz, OWNER, {"mode": "some", "listeners": []})
    alerts.report(biz, OWNER, _event(owner_dev, "15", amount_paise=60000))
    assert len(pushes) == 1

    # the listener mutes / pauses on their own phone; resuming brings it back
    alerts.set_share(biz, OWNER, {"mode": "all"})
    owner_ref = people["owner"]["ref"]
    alerts.set_listening(biz, CASHIER, {"source": owner_ref, "muted": True})
    alerts.report(biz, OWNER, _event(owner_dev, "16"))
    assert len(pushes) == 1
    alerts.set_listening(biz, CASHIER, {"source": owner_ref, "muted": False})
    view = alerts.set_listening(biz, CASHIER, {"source": "*", "pause_minutes": 30})
    assert view["my_listening"]["*"]["paused_until"]
    alerts.report(biz, OWNER, _event(owner_dev, "17"))
    assert len(pushes) == 1
    clock.now += timedelta(minutes=31)
    alerts.report(biz, OWNER, _event(owner_dev, "18"))
    assert len(pushes) == 2 and pushes[-1][0] == CASHIER
    with pytest.raises(PosError):
        alerts.set_listening(biz, CASHIER, {"source": "unknownref"})
    with pytest.raises(PosError):
        alerts.set_share(biz, CASHIER, {"mode": "everyone"})


def test_member_label_is_kept_when_role_changes_without_one(env):
    store, alerts, biz, *_ = env
    store.set_member(biz, OWNER, "9400000302", "cashier", "  Ravi   Kumar ")
    store.set_member(biz, OWNER, "9400000302", "manager")
    member = [m for m in store.members(biz, OWNER) if m["phone_last4"] == "0302"][0]
    assert member["label"] == "Ravi Kumar" and member["role"] == "manager"
