"""Sign-in diagnostics trail (APK 1336 network failures): placed exactly, nothing personal kept."""
import dataclasses
import logging

import pytest
from fastapi.testclient import TestClient

from app.api.routes.onboarding_auth import clean_trace_line


@pytest.fixture()
def client(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "trace.db")))
    monkeypatch.setattr(container, "platform", None, raising=False)
    yield TestClient(app)


TRAIL = [
    "+0ms send_otp.tap valid=true path=firebase resend=false",
    "+12ms firebase.verify_start resend=false",
    "+40ms firebase.verify_requested",
    "+900ms app.lifecycle state=inactive step=1",
    "+950ms app.lifecycle state=paused step=1",
    "+21000ms firebase.verification_failed code=unknown settled=false "
    "message=An_internal_error_has_occurred._[_Software_caused_connection_abort_]",
    "+46000ms firebase.settled result=failed_unknown",
    "+46010ms send_otp.firebase_failed code=unknown network=true",
]


def test_trace_is_logged_in_order_without_personal_data(client, caplog):
    caplog.set_level(logging.INFO, logger="uvicorn.error")
    lines = TRAIL + ["+1ms send_otp.tap number=+919876543210 path=firebase", "free text 9876543210 here",
                     "+5ms verify_otp.tap otp=123456"]
    response = client.post("/onboarding/diagnostics/trace", json={
        "outcome": "failed", "stage": "send_otp", "code": "unknown", "app_version": "1337", "lines": lines})
    assert response.status_code == 200, response.text
    assert response.json()["kept"] == len(TRAIL) + 2  # free text dropped, private keys removed
    logged = "\n".join(r.getMessage() for r in caplog.records if "signin.trace" in r.getMessage())
    assert "outcome=failed stage=send_otp code=unknown app=1337" in logged
    assert logged.index("state=paused") < logged.index("connection_abort")
    for secret in ("9876543210", "123456", "number=", "otp="):
        assert secret not in logged


def test_trace_rejects_unknown_outcomes_and_oversized_payloads(client):
    assert client.post("/onboarding/diagnostics/trace", json={"outcome": "hacked", "lines": []}).status_code == 422
    too_many = {"outcome": "failed", "lines": ["+1ms a.b"] * 81}
    assert client.post("/onboarding/diagnostics/trace", json=too_many).status_code == 422
    assert client.post("/onboarding/diagnostics/trace",
                       json={"outcome": "failed", "app_version": "1 337 x"}).status_code == 422


def test_clean_trace_line_keeps_codes_and_drops_numbers():
    assert clean_trace_line("+3ms firebase.code_sent after_failure=false") == "+3ms firebase.code_sent after_failure=false"
    assert clean_trace_line("+3ms firebase.verification_failed code=network-request-failed message=") \
        == "+3ms firebase.verification_failed code=network-request-failed message="
    assert "98765" not in (clean_trace_line("+3ms x.y token=abc mobile=9876543210 ref=98765432") or "")
    assert clean_trace_line("not a trail line") is None
