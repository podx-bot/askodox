"""Phone health reports (owner 2026-11-26): only with the person's "పంపు" every time, only the app's own check ids,
numbers masked for staff, nothing free-text, gone with the account."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.phone_health import MAX_PER_DAY, PhoneHealth, PhoneHealthError

USER = "app-phone-9300003001"


def _svc(tmp_path):
    now = [datetime(2026, 11, 26, 6, 0, tzinfo=timezone.utc)]
    return PhoneHealth(str(tmp_path / "h.db"), clock=lambda: now[0]), now


def test_no_report_without_consent_in_that_request(tmp_path):
    svc, _ = _svc(tmp_path)
    for consent in (False, None, "yes", 1):
        with pytest.raises(PhoneHealthError) as err:
            svc.report(USER, {"consent": consent, "checks": {"battery": "bad"}})
        assert err.value.code == "consent_needed"
    assert svc.overview()["reports"] == 0


def test_only_known_checks_and_clean_words_are_kept(tmp_path):
    svc, _ = _svc(tmp_path)
    out = svc.report(USER, {"consent": True, "maker": "Xiaomi <script>", "android": "14", "app_build": "1703",
                            "why": "payment_voice_missing",
                            "checks": {"battery": "bad", "notifications": "ok", "autostart": "unknown",
                                       "sms_inbox": "bad", "volume": "loud", "contacts": "ok"}})
    assert out["kept"] == ["autostart", "battery", "notifications"] and out["bad"] == 1
    seen = svc.overview()
    row = seen["newest"][0]
    assert row["user"] == "••••3001" and USER not in str(seen), "the sign-in number is never shown in full"
    assert row["maker"] == "xiaomi script" and row["failing"] == ["battery"] and row["why"] == "payment_voice_missing"
    assert seen["by_check"] == [{"check": "battery", "count": 1}]
    assert seen["by_maker"][0]["maker"] == "xiaomi script" and seen["by_maker"][0]["top"] == "battery"
    with pytest.raises(PhoneHealthError) as err:
        svc.report(USER, {"consent": True, "checks": {"sms_inbox": "bad"}})
    assert err.value.code == "no_checks"


def test_a_few_reports_a_day_old_ones_go_and_account_deletion_clears(tmp_path):
    svc, now = _svc(tmp_path)
    for _ in range(MAX_PER_DAY):
        svc.report(USER, {"consent": True, "maker": "vivo", "checks": {"battery": "bad"}})
    with pytest.raises(PhoneHealthError) as err:
        svc.report(USER, {"consent": True, "checks": {"battery": "bad"}})
    assert err.value.status == 429
    now[0] += timedelta(days=2)
    svc.report("app-phone-9300003002", {"consent": True, "maker": "samsung", "checks": {"voice": "ok"}})
    seen = svc.overview(days=30)
    assert seen["reports"] == MAX_PER_DAY + 1 and seen["with_problem"] == MAX_PER_DAY
    assert [m["maker"] for m in seen["by_maker"]] == ["vivo", "samsung"]
    assert svc.forget(USER) == MAX_PER_DAY and svc.overview()["reports"] == 1
    now[0] += timedelta(days=100)
    svc.report(USER, {"consent": True, "checks": {"voice": "ok"}})
    assert svc.overview(days=90)["reports"] == 1, "reports older than 90 days are deleted"


def test_http_report_needs_sign_in_and_consent():
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    user = "app-phone-9411100902"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    body = {"maker": "oppo", "android": "13", "app_build": "1703", "checks": {"battery": "bad", "notifications": "ok"}}
    assert client.post("/api/me/phone-health/report", json={**body, "consent": True}).status_code == 401
    assert client.post("/api/me/phone-health/report", headers=auth, json=body).status_code == 400
    ok = client.post("/api/me/phone-health/report", headers=auth, json={**body, "consent": True})
    assert ok.status_code == 200 and ok.json()["bad"] == 1
