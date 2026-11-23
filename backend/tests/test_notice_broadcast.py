"""Paid notifications (owner 2026-11-24): audience, caps, charge only what reached, receivers in control."""
import sqlite3
from datetime import datetime, timezone

import pytest

from app.services.notice_broadcast import NoticeBroadcast, NoticeError, clean_text, distance_km

NOON = datetime(2026, 11, 24, 6, 30, tzinfo=timezone.utc)  # 12:00 IST
NIGHT = datetime(2026, 11, 24, 17, 0, tzinfo=timezone.utc)  # 22:30 IST
SETTINGS = {"notices.rate_paise": 5, "notices.max_recipients": 1000, "notices.per_day_sender": 3,
            "notices.per_day_receiver": 3}


def _db(tmp_path):
    path = str(tmp_path / "n.db")
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE pos_businesses (id TEXT, owner_user_id TEXT, name TEXT);"
        "CREATE TABLE shop_follows (business_id TEXT, app_user_id TEXT);"
        "CREATE TABLE user_profiles (user_id TEXT, latitude REAL, longitude REAL);"
        "CREATE TABLE push_tokens (user_id TEXT, token TEXT);"
        "INSERT INTO pos_businesses VALUES ('b1', 'owner', 'Ravi Stores');")
    for i in range(5):
        conn.execute("INSERT INTO shop_follows VALUES ('b1', ?)", (f"f{i}",))
        conn.execute("INSERT INTO push_tokens VALUES (?, 't')", (f"f{i}",))
    conn.execute("INSERT INTO shop_follows VALUES ('b1', 'nophone')")
    conn.execute("INSERT INTO user_profiles VALUES ('owner', 16.36, 80.84)")
    conn.execute("INSERT INTO user_profiles VALUES ('near', 16.37, 80.85)")
    conn.execute("INSERT INTO user_profiles VALUES ('far', 17.38, 78.48)")
    conn.execute("INSERT INTO push_tokens VALUES ('near', 't')")
    conn.execute("INSERT INTO push_tokens VALUES ('far', 't')")
    conn.commit()
    conn.close()
    return path


class Push:
    def __init__(self, fail=()):
        self.sent, self.fail = [], set(fail)

    def notify(self, user_id, **kw):
        self.sent.append((user_id, kw))
        return 0 if user_id in self.fail else 1


def _svc(tmp_path, clock=NOON):
    return NoticeBroadcast(_db(tmp_path), setting=lambda k: SETTINGS[k], clock=lambda: clock)


def _send(svc, txn="t1", charged=None, **kw):
    def charge(ref, paise):
        if charged is not None:
            charged.append(paise)
        return {"charged": True, "paise": paise}

    args = dict(title="Weekend offer", body="Biryani 20% off today", audience="followers", business_id="b1",
                client_txn_id=txn, charge=charge)
    args.update(kw)
    return svc.create("owner", **args)


def test_followers_with_a_phone_are_counted_and_priced(tmp_path):
    svc = _svc(tmp_path)
    out = svc.preview("owner", audience="followers", business_id="b1")
    assert out["people"] == 5 and out["cost_paise"] == 25


def test_only_the_owner_reaches_followers(tmp_path):
    with pytest.raises(NoticeError) as err:
        _svc(tmp_path).preview("stranger", audience="followers", business_id="b1")
    assert err.value.code == "not_owner"


def test_nearby_uses_distance_and_skips_the_sender(tmp_path):
    svc = _svc(tmp_path)
    assert svc.audience("owner", audience="nearby", radius_km=5) == ["near"]
    assert distance_km(16.36, 80.84, 17.38, 78.48) > 200


def test_send_charges_then_gives_back_what_did_not_reach(tmp_path):
    svc = _svc(tmp_path)
    charged, unused = [], []
    out = _send(svc, charged=charged)
    assert charged == [25] and len(out["people"]) == 5
    reached = svc.deliver(out["id"], Push(fail={"f0", "f1"}), on_unused=unused.append)
    assert reached == 3 and unused == [10]
    assert svc.get_own(out["id"], "owner")["cost_paise"] == 15


def test_same_tap_twice_is_one_notification(tmp_path):
    svc = _svc(tmp_path)
    charged = []
    first = _send(svc, charged=charged)
    again = _send(svc, charged=charged)
    assert again["id"] == first["id"] and charged == [25]


def test_receiver_gets_one_a_day_from_the_same_sender(tmp_path):
    svc = _svc(tmp_path)
    _send(svc, txn="a")
    with pytest.raises(NoticeError) as err:
        _send(svc, txn="b")
    assert err.value.code == "nobody"


def test_sender_daily_limit_and_quiet_hours(tmp_path):
    with pytest.raises(NoticeError) as err:
        _send(_svc(tmp_path, NIGHT))
    assert err.value.code == "quiet_hours"


def test_links_and_phone_numbers_are_refused_and_words_masked():
    for bad in ("Visit www.shop.com", "call 9876543210", "https://x.in/a"):
        with pytest.raises(NoticeError):
            clean_text(bad, 200)
    assert clean_text("  Fresh   mangoes  ", 200) == "Fresh mangoes"


def test_receiver_open_is_counted_once_and_strangers_see_nothing(tmp_path):
    svc = _svc(tmp_path)
    out = _send(svc, image=b"\x89PNG....", image_mime="image/png")
    svc.deliver(out["id"], Push())
    assert svc.open(out["id"], "f2")["from_shop"] == "Ravi Stores"
    svc.open(out["id"], "f2")
    assert svc.get_own(out["id"], "owner")["opened"] == 1
    assert svc.image(out["id"], "f2")[1] == "image/png"
    with pytest.raises(NoticeError):
        svc.open(out["id"], "far")
    with pytest.raises(NoticeError):
        svc.image(out["id"], "far")


def test_push_kind_is_offers_and_can_be_switched_off():
    from app.services.push_service import PushService

    assert "offers" in PushService.KINDS
    assert PushService.kind_of("notice:ntc_1") == "offers"


def test_credits_spend_is_free_while_charging_is_off_and_atomic_when_on(tmp_path):
    from app.services.ai_credits import AiCredits, CreditsError

    credits = AiCredits(str(tmp_path / "c.db"))
    assert credits.spend("u", 25, "notice:a", feature="notice")["charged"] is False
    credits.update_settings({"charging": True, "rates_paise": {"chat": 25}}, actor="t")
    with pytest.raises(CreditsError) as err:
        credits.spend("u", 25, "notice:b", feature="notice")
    assert err.value.status == 402
    credits.topup("u", paise=100, purchase_id="p1", mode="live")
    assert credits.spend("u", 25, "notice:c", feature="notice")["charged"] is True
    assert credits.spend("u", 25, "notice:c", feature="notice").get("repeat") is True
    assert credits.balance("u")["live"] == 75
    assert credits.refund_unused("u", "notice:c", 10, feature="notice") is True
    assert credits.refund_unused("u", "notice:c", 10, feature="notice") is False
    assert credits.balance("u")["live"] == 85


def test_routes_need_sign_in_and_answer_with_a_reason():
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    client = TestClient(app)
    assert client.post("/api/notices/preview", json={"audience": "nearby"}).status_code == 401
    auth = {"Authorization": f"Bearer {issue_token('app-phone-9411100801', container.settings.session_token_secret)}"}
    out = client.post("/api/notices/preview", json={"audience": "nearby"}, headers=auth)
    assert out.status_code == 409 and out.json()["detail"]["code"] == "no_location"
    out = client.post("/api/notices/preview", json={"audience": "nearby", "lat": 16.3, "lon": 80.8}, headers=auth)
    assert out.status_code == 200 and out.json()["people"] >= 0 and "charging" in out.json()
    assert client.get("/api/notices/mine", headers=auth).json() == {"notices": []}
    assert client.get("/api/notices/ntc_missing", headers=auth).status_code == 404
