"""Sign up / sign in / sign out end to end on the server:
returning users get their profile back (never a second account), sign-out
revokes only that session and never deletes data, a different account sees
none of the first one's data, Firebase phone sign-in is accepted only with a
genuinely signed ID token for this project, and a self push test reaches only
the caller's own devices."""
import base64
import dataclasses
import datetime
import json
import time
import uuid

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient

from app.services import account_identity, firebase_id_token

PROJECT = "askodox-test-project"


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "auth.db")))
    for attr in ("user_profile_repository", "push_service", "platform"):
        monkeypatch.setattr(container, attr, None, raising=False)
    for name in ("RAILWAY_ENVIRONMENT_NAME", "ASKODOX_ENV", "FIREBASE_PROJECT_ID", "ASKODOX_FIREBASE_PHONE_AUTH",
                 "FIREBASE_SERVICE_ACCOUNT_JSON"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("ASKODOX_TEST_OTP_MODE", "yes")
    from app.api.routes import auth_session, onboarding_auth

    onboarding_auth._otps.clear()
    auth_session._push_tests.clear()
    firebase_id_token.clear_cache()
    yield TestClient(app), monkeypatch, container


def _sign_in(client, monkeypatch, typed):
    from app.api.routes import onboarding_auth

    monkeypatch.setenv("ASKODOX_TEST_OTP_MOBILES", "".join(c for c in typed if c.isdigit()))
    onboarding_auth._otps.clear()
    sent = client.post("/onboarding/otp/send", json={"mobile": typed})
    assert sent.status_code == 200 and sent.json()["resend_after_seconds"] == 45
    r = client.post("/onboarding/otp/verify", json={"mobile": typed, "otp": "123456"})
    assert r.status_code == 200, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _number():
    return "9" + str(uuid.uuid4().int)[:9]


def test_signup_then_returning_signin_restores_the_same_profile(env):
    c, mp, _ = env
    n = _number()
    first = _sign_in(c, mp, "+91 " + n)
    assert first["returning"] is False and first["profile"].get("name", "") == ""
    assert c.put("/api/me/profile", headers=_auth(first["token"]),
                 json={"name": "Asha", "language": "te"}).status_code == 200
    again = _sign_in(c, mp, n)  # typed differently, same person
    assert again["app_user_id"] == first["app_user_id"]
    assert again["returning"] is True and again["profile"]["name"] == "Asha" and again["profile"]["language"] == "te"


def test_logout_revokes_only_that_session_and_keeps_all_data(env):
    c, mp, container = env
    n = _number()
    phone_a = _sign_in(c, mp, n)
    phone_b = _sign_in(c, mp, n)
    c.put("/api/me/profile", headers=_auth(phone_a["token"]), json={"name": "Ravi"})
    for who, tok in (("a", phone_a["token"]), ("b", phone_b["token"])):
        assert c.post("/api/me/push-token", headers=_auth(tok), json={"token": f"fcm-token-{who}-" + "x" * 30}).status_code == 200
    s = c.get("/api/me/session", headers=_auth(phone_a["token"]))
    assert s.status_code == 200 and s.json()["app_user_id"] == phone_a["app_user_id"]
    assert s.json()["profile"]["name"] == "Ravi"
    out = c.post("/api/me/logout", headers=_auth(phone_a["token"]), json={"push_token": "fcm-token-a-" + "x" * 30})
    assert out.json() == {"signed_out": True, "server_session": "revoked", "push_token_removed": True}
    assert c.get("/api/me/session", headers=_auth(phone_a["token"])).status_code == 401, "signed-out token is dead"
    assert c.get("/api/me/profile", headers=_auth(phone_a["token"])).status_code == 401
    from app.services.push_service import push_service

    left = push_service(container).tokens(phone_a["app_user_id"])
    assert "fcm-token-a-" + "x" * 30 not in left
    # Signing in again: same account, data intact (logout never deletes anything).
    time.sleep(1.1)
    back = _sign_in(c, mp, n)
    assert back["app_user_id"] == phone_a["app_user_id"] and back["profile"]["name"] == "Ravi"
    assert c.get("/api/me/profile", headers=_auth(back["token"])).json()["name"] == "Ravi"
    # A second logout with the dead token is harmless.
    assert c.post("/api/me/logout", headers=_auth(phone_a["token"]), json={}).json()["server_session"] == \
        "already_invalid"
    assert c.post("/api/me/logout", json={}).json()["signed_out"] is True


def test_session_issued_in_a_different_second_survives_another_logout(env):
    c, mp, _ = env
    n = _number()
    first = _sign_in(c, mp, n)
    time.sleep(1.1)
    second = _sign_in(c, mp, n)
    c.post("/api/me/logout", headers=_auth(first["token"]), json={})
    assert c.get("/api/me/session", headers=_auth(second["token"])).status_code == 200, "other phone stays in"


def test_switching_accounts_never_shows_the_other_accounts_data(env):
    c, mp, _ = env
    a = _sign_in(c, mp, _number())
    c.put("/api/me/profile", headers=_auth(a["token"]), json={"name": "Account A"})
    c.post("/api/me/logout", headers=_auth(a["token"]), json={})
    b = _sign_in(c, mp, _number())
    assert b["app_user_id"] != a["app_user_id"] and b["returning"] is False
    assert c.get("/api/me/profile", headers=_auth(b["token"])).json().get("name") in (None, "")
    assert c.get("/api/me/session", headers=_auth(b["token"])).json()["profile"].get("name", "") == ""


def test_resend_cooldown_says_how_long(env):
    c, mp, _ = env
    n = _number()
    mp.setenv("ASKODOX_TEST_OTP_MOBILES", n)
    assert c.post("/onboarding/otp/send", json={"mobile": n}).status_code == 200
    again = c.post("/onboarding/otp/send", json={"mobile": n})
    assert again.status_code == 429 and 1 <= int(again.headers["retry-after"]) <= 45
    wrong = c.post("/onboarding/otp/verify", json={"mobile": n, "otp": "000000"})
    assert wrong.status_code == 400 and wrong.json()["detail"] == "Incorrect OTP."


def test_international_numbers_never_share_an_account_with_indian_ones():
    assert account_identity.phone_key("+91 98765 43210") == account_identity.phone_key("09876543210") == \
        account_identity.phone_key("9876543210") == "9876543210"
    assert account_identity.phone_key("+1 987 654 3210") == "19876543210"
    assert not account_identity.same_number("app-phone-19876543210", "app-phone-919876543210")
    assert account_identity.same_number("app-phone-919876543210", "app-phone-9876543210")


# ------------------------------------------------------------ Firebase --

def _keypair(kid="k1"):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "securetoken.test")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(1).not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=1)).sign(key, hashes.SHA256()))
    return key, {kid: cert.public_bytes(serialization.Encoding.PEM).decode()}


def _jwt(key, claims, kid="k1", alg="RS256"):
    enc = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()  # noqa: E731
    head = f"{enc({'alg': alg, 'kid': kid, 'typ': 'JWT'})}.{enc(claims)}"
    sig = key.sign(head.encode(), padding.PKCS1v15(), hashes.SHA256())
    return head + "." + base64.urlsafe_b64encode(sig).rstrip(b"=").decode()


def _claims(phone="+919876500001", **over):
    now = int(time.time())
    return {"aud": PROJECT, "iss": f"https://securetoken.google.com/{PROJECT}", "sub": "uid-1", "iat": now - 5,
            "exp": now + 3600, "auth_time": now - 5, "phone_number": phone, **over}


def test_firebase_phone_sign_in_needs_a_real_token_for_this_project(env):
    c, mp, _ = env
    key, certs = _keypair()
    mp.setattr(firebase_id_token, "_fetch_certs", lambda: (certs, 3600.0))
    assert c.post("/onboarding/firebase/verify", json={"id_token": _jwt(key, _claims())}).status_code == 503, \
        "not configured -> honest 503"
    mp.setenv("FIREBASE_PROJECT_ID", PROJECT)
    ok = c.post("/onboarding/firebase/verify", json={"id_token": _jwt(key, _claims())})
    assert ok.status_code == 200, ok.text
    assert ok.json()["app_user_id"] == "app-phone-919876500001"
    assert c.get("/api/me/session", headers=_auth(ok.json()["token"])).status_code == 200
    other_key, _ = _keypair()
    bad = {
        "forged signature": _jwt(other_key, _claims()),
        "other project": _jwt(key, _claims(aud="someone-else")),
        "expired": _jwt(key, _claims(exp=int(time.time()) - 10)),
        "future": _jwt(key, _claims(iat=int(time.time()) + 3600)),
        "no phone": _jwt(key, _claims(phone="")),
        "unknown key": _jwt(key, _claims(), kid="k9"),
        "garbage": "a.b.c",
    }
    for why, token in bad.items():
        r = c.post("/onboarding/firebase/verify", json={"id_token": token})
        assert r.status_code == 401, why
        assert token not in r.text
    # The same number via server OTP lands in the same account.
    assert _sign_in(c, mp, "9876500001")["app_user_id"] == "app-phone-919876500001"


def test_methods_say_which_sign_in_is_available(env):
    c, mp, _ = env
    m = c.get("/onboarding/methods").json()
    assert m["firebase_phone_auth"] is False and m["resend_seconds"] == 45
    mp.setenv("FIREBASE_PROJECT_ID", PROJECT)
    assert c.get("/onboarding/methods").json()["firebase_phone_auth"] is False, "Owner switch needed (SMS cost)"
    mp.setenv("ASKODOX_FIREBASE_PHONE_AUTH", "yes")
    assert c.get("/onboarding/methods").json()["firebase_phone_auth"] is True


class _FakePush:
    configured = True

    def __init__(self):
        self.sent = []
        self._tokens = {}

    def tokens(self, user_id):
        return self._tokens.get(user_id, [])

    def notify(self, user_id, **kw):
        self.sent.append((user_id, kw["event_key"]))
        return len(self.tokens(user_id))


def test_push_test_goes_only_to_my_own_devices(env):
    c, mp, container = env
    me = _sign_in(c, mp, _number())
    assert c.post("/api/me/push-test", headers=_auth(me["token"])).json()["status"] == "NOT_CONFIGURED"
    assert c.post("/api/me/push-test").status_code == 401
    fake = _FakePush()
    from app.api.routes import platform as platform_routes

    class _P:
        def push(self):
            return fake

    mp.setattr(platform_routes, "platform", lambda _c: _P())
    assert c.post("/api/me/push-test", headers=_auth(me["token"])).json()["status"] == "NO_DEVICE_TOKENS"
    fake._tokens[me["app_user_id"]] = ["t1"]
    for _ in range(3):
        r = c.post("/api/me/push-test", headers=_auth(me["token"])).json()
        assert r == {"status": "SENT", "delivered": 1, "detail": "FCM accepted the message; check the phone."}
    assert c.post("/api/me/push-test", headers=_auth(me["token"])).status_code == 429
    assert {u for u, _ in fake.sent} == {me["app_user_id"]}, "never anybody else"
