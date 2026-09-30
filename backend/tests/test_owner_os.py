"""Owner OS: configurable referral Priority Notification Credits, localized
non-repeating greetings, delivery Party-B matching, staging defaults, setup."""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import owner_os
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-os-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
NOW = datetime(2026, 9, 30, 10, tzinfo=timezone.utc)


def _rule(**data):
    base = {"referrals_required": 1, "credits_awarded": 2, "expiry_days": 0, "max_balance": 0}
    return {"id": "rcr_1", "status": "ACTIVE", "archived": False, "data": {**base, **data}}


def _tpl(i, kind, lang, text):
    return {"id": f"grt_{i}", "status": "ACTIVE", "archived": False,
            "data": {"kind": kind, "language": lang, "text": text}}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "o.db")),
                        raising=False)
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


# ------------------------------------------------------------ credits --
def test_credit_award_uses_configured_values_slabs_and_caps(tmp_path):
    pc = owner_os.PriorityCredits(str(tmp_path / "c.db"))
    rule = _rule(referrals_required=2, credits_awarded=3, bonus_slabs={"4": 10},
                 max_balance=12, expiry_days=30)
    assert pc.award_referral("u1", referral_count=1, rule=rule, ref="r1", now=NOW)["granted"] == 0
    assert pc.award_referral("u1", referral_count=2, rule=rule, ref="r2", now=NOW)["granted"] == 3
    # 4th referral: 3 + bonus 10, capped by max balance 12 (3 already held)
    assert pc.award_referral("u1", referral_count=4, rule=rule, ref="r4", now=NOW)["granted"] == 9
    assert pc.balance("u1", now=NOW) == 12
    # idempotent per referral
    assert pc.award_referral("u1", referral_count=2, rule=rule, ref="r2", now=NOW)["granted"] == 0
    # expiry
    assert pc.balance("u1", now=NOW + timedelta(days=31)) == 0


def test_credit_daily_limit_roles_and_spending(tmp_path):
    pc = owner_os.PriorityCredits(str(tmp_path / "c.db"))
    rule = _rule(credits_awarded=5, daily_limit=6, eligible_roles=["seller"],
                 eligible_notification_types=["nearby_request"], spend_daily_limit=1)
    assert pc.award_referral("u", referral_count=1, rule=rule, roles=["buyer"], ref="a")["reason"] == \
        "role_not_eligible"
    assert pc.award_referral("u", referral_count=1, rule=rule, roles=["seller"], ref="b", now=NOW)["granted"] == 5
    assert pc.award_referral("u", referral_count=2, rule=rule, roles=["seller"], ref="c", now=NOW)["granted"] == 1
    assert pc.spend("u", "offer", rule=rule, now=NOW)["reason"] == "type_not_eligible"
    assert pc.spend("u", "nearby_request", rule=rule, now=NOW)["ok"] is True
    assert pc.spend("u", "nearby_request", rule=rule, now=NOW)["reason"] == "daily_limit"
    assert pc.balance("u", now=NOW) == 5
    assert pc.spend("x", "nearby_request", rule=None)["reason"] == "no_active_rule"
    assert pc.spend("nobody", "nearby_request", rule=_rule(), now=NOW)["reason"] == "no_credits"


def test_highest_priority_live_rule_wins():
    rules = [dict(_rule(priority=1), id="a"), dict(_rule(priority=5), id="b"),
             dict(_rule(priority=9), id="c", status="DISABLED")]
    assert owner_os.PriorityCredits.active_rule(rules)["id"] == "b"
    assert owner_os.PriorityCredits.active_rule([]) is None


# ---------------------------------------------------------- greetings --
def test_greeting_by_local_time_language_and_rotation(tmp_path):
    tpls = [_tpl(1, "morning", "en", "Good morning {name}!"), _tpl(2, "morning", "en", "Morning, {name}!"),
            _tpl(3, "morning", "ta", "காலை வணக்கம் {name}!"), _tpl(4, "evening", "", "Hello!"),
            _tpl(5, "returning", "es", "¡Bienvenido de nuevo!")]
    assert owner_os.greeting_kind(7) == "morning" and owner_os.greeting_kind(14) == "afternoon"
    assert owner_os.greeting_kind(19) == "evening" and owner_os.greeting_kind(2) == "night"
    g = owner_os.greet(tpls, None, user_id="", local_hour=8, language="ta-IN", name="Ravi")["greeting"]
    assert g["text"] == "காலை வணக்கம் Ravi!" and g["language_matched"]
    first = owner_os.greet(tpls, None, user_id="", local_hour=8, language="en", name="A")["greeting"]["text"]
    second = owner_os.greet(tpls, None, user_id="", local_hour=8, language="en", name="A",
                            last_text=first)["greeting"]["text"]
    assert first != second
    # any language falls back to the language-neutral text, flagged as not matched
    g = owner_os.greet(tpls, None, user_id="", local_hour=19, language="sw")["greeting"]
    assert g["text"] == "Hello!" and not g["language_matched"]
    # returning user in Spanish; returning without a text falls back to time of day
    assert owner_os.greet(tpls, None, user_id="", local_hour=8, language="es", returning=True)["greeting"][
        "kind"] == "returning"
    assert owner_os.greet(tpls, None, user_id="", local_hour=8, language="en", returning=True)["greeting"][
        "kind"] == "morning"
    assert owner_os.greet(tpls, None, user_id="", local_hour=14, language="en")["reason"] == "no_template"


def test_greeting_not_repeated_for_the_same_user(tmp_path):
    log = owner_os.GreetingLog(str(tmp_path / "g.db"))
    tpls = [_tpl(1, "morning", "en", "Good morning!")]
    assert owner_os.greet(tpls, log, user_id="u", local_hour=8, language="en", now=NOW)["greeting"]
    again = owner_os.greet(tpls, log, user_id="u", local_hour=8, language="en", now=NOW + timedelta(hours=1))
    assert again == {"greeting": None, "reason": "recently_greeted"}
    assert owner_os.greet(tpls, log, user_id="u", local_hour=8, language="en",
                          now=NOW + timedelta(hours=5))["greeting"]


# ----------------------------------------------------------- delivery --
def _partner(i, **data):
    base = {"kind": "independent", "services": ["food", "parcel"], "available": True, "latitude": 16.36,
            "longitude": 80.84, "radius_km": 5}
    return {"id": f"dlp_{i}", "name": f"P{i}", "status": "ACTIVE", "archived": False, "data": {**base, **data}}


def test_delivery_matching_filters_and_supports_external_partners():
    partners = [_partner(1), _partner(2, verified=True, latitude=16.37), _partner(3, available=False),
                _partner(4, services=["grocery"]), _partner(5, latitude=17.5),
                dict(_partner(6), status="PENDING_REVIEW"),
                _partner(7, kind="external", integration_key="shiprocket"),
                _partner(8, kind="external", integration_key="dunzo")]
    out = owner_os.match_delivery(partners, service="parcel", latitude=16.36, longitude=80.84,
                                  integration_ready=lambda k: k == "shiprocket")
    assert [c["id"] for c in out["independent"]] == ["dlp_2", "dlp_1"]  # verified first
    assert [c["id"] for c in out["external"]] == ["dlp_7"]
    assert out["skipped"] == {"unavailable": 1, "service": 1, "out_of_range": 1, "not_approved": 1,
                              "integration_not_configured": 1}


# ------------------------------------------------------------ routes ---
def test_seed_setup_greeting_and_referral_credit_flow(env, monkeypatch):
    client, container = env
    assert client.post("/admin/cc/owner/seed-staging").status_code in (401, 403)
    first = client.post("/admin/cc/owner/seed-staging", headers=OWNER)
    assert first.status_code == 200, first.text
    assert first.json()["created"]["qa_checks"] == len(owner_os.OPEN_FINDINGS)
    assert client.post("/admin/cc/owner/seed-staging", headers=OWNER).json()["created"] == {}  # idempotent
    qa = client.get("/admin/cc/platform/r/qa_checks", headers=OWNER).json()["items"]
    assert qa and all(r["status"] == "OPEN" for r in qa)

    setup = client.get("/admin/cc/owner/setup", headers=OWNER).json()
    assert setup["qa"]["OPEN"] == len(owner_os.OPEN_FINDINGS)
    assert {r["role"] for r in setup["email_roles"]} >= {"support", "admin", "partners", "notifications",
                                                         "no_reply", "security"}
    assert all(r["status"] == "DISABLED" for r in setup["email_roles"])  # unverified placeholders
    assert setup["flags"]["referrals.priority_credits"] is False
    assert setup["flags"]["location.background_optin"] is False

    uid, auth = _user(container)
    g = client.get("/api/greeting", params={"language": "en", "local_hour": 9, "name": "Asha"}, headers=auth)
    assert g.json()["greeting"]["text"] == "Good morning Asha! What can I find for you today?"
    assert client.get("/api/greeting", params={"language": "en", "local_hour": 9},
                      headers=auth).json()["reason"] == "recently_greeted"

    # referral -> credits only once the flag is switched on
    referrer, rauth = _user(container)
    invitee, iauth = _user(container)
    code = client.post("/api/referrals", headers=rauth, json={}).json()
    code = code.get("code") or code.get("referral", {}).get("code")
    container.command_center_repository.set_flag("referrals.priority_credits", True, "test")
    assert client.post(f"/api/referrals/{code}/redeem", headers=iauth).status_code == 200
    mine = client.get("/api/priority-credits/mine", headers=rauth).json()
    assert mine["enabled"] is True and mine["balance"] == 2 and mine["rule"]["credits_awarded"] == 2
    assert client.get("/api/priority-credits/mine").status_code == 401


def test_seed_refused_in_production(env, monkeypatch):
    client, container = env
    from app.api.routes.platform import platform

    monkeypatch.setitem(platform(container).registry.env, "RAILWAY_ENVIRONMENT_NAME", "production")
    assert client.post("/admin/cc/owner/seed-staging", headers=OWNER).status_code == 403


def test_delivery_partner_needs_second_person_approval_and_match_route(env):
    client, _ = env
    r = client.post("/admin/cc/platform/r/delivery_partners", headers=OWNER,
                    json={"data": {"name": "Ravi bike", "kind": "independent", "services": ["parcel"],
                                   "available": True, "latitude": 16.36, "longitude": 80.84, "radius_km": 5}})
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "PENDING_REVIEW"
    m = client.post("/admin/cc/delivery/match", headers=OWNER,
                    json={"service": "parcel", "latitude": 16.36, "longitude": 80.84}).json()
    assert m["independent"] == [] and m["skipped"].get("not_approved") == 1 and m["matching_enabled"] is False
