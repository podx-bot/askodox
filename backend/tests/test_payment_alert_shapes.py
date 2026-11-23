"""Owner 2026-11-23 ("payment confirmations come with NEW words -- why does it not read them?"): a phone asks its person
once about a money message it could not read; with their leave only the message SHAPE comes here, and once enough
different people agree (nobody disagreeing) every phone reads that shape. Made-up senders / words only."""
import dataclasses
import re
import uuid
from pathlib import Path

import pytest

from app.services.payment_alert_shapes import (AGREE_TO_SHARE, SHAPE_WORDS, PaymentAlertShapes, ShapeError,
                                               clean_sender, clean_skeleton)

KOTLIN = Path(__file__).resolve().parents[2] / "android/app/src/main/kotlin/com/askodox/askodox/PaymentAlertParser.kt"
SHAPE = "credit of ₹# received in a/c for from"
DEBIT = "₹# debit to a/c upi towards"


def test_shape_words_are_exactly_the_phones_word_list():
    text = KOTLIN.read_text(encoding="utf-8")
    block = re.search(r"SKELETON_WORDS = setOf\((.*?)\n    \)", text, re.S).group(1)
    phone_words = set(re.findall(r'"([^"]+)"', block))
    assert phone_words == set(SHAPE_WORDS), "keep payment_alert_shapes.SHAPE_WORDS equal to PaymentAlertParser.SKELETON_WORDS"


def test_only_shape_words_and_registered_senders_are_kept():
    assert clean_skeleton("Credit of ₹# received in A/C for from") == SHAPE
    for bad in ("credit of ₹# received from ramesh", "₹500 credited to a/c", "credited 9876543210 to a/c",
                "to a/c", "credited " * 41):
        with pytest.raises(ShapeError):
            clean_skeleton(bad)
    assert clean_sender("sms:newbnk") == "sms:NEWBNK"
    assert clean_sender("app:com.example.bankapp") == "app:com.example.bankapp"
    for bad in ("sms:+919876543210", "9876543210", "Ramesh", "sms:", "app:ramesh"):
        with pytest.raises(ShapeError):
            clean_sender(bad)


def test_shared_only_when_enough_people_agree(tmp_path):
    shapes = PaymentAlertShapes(str(tmp_path / "s.db"))
    need = AGREE_TO_SHARE["out"]
    for i in range(need - 1):
        assert shapes.answer(f"app-phone-91000000{i:02d}", "sms:NEWBNK", DEBIT, "out")["shared"] is False
    # the same person answering again is still one person
    assert shapes.answer("app-phone-9100000000", "sms:NEWBNK", DEBIT, "out")["shared"] is False
    assert shapes.answer(f"app-phone-91000000{need:02d}", "sms:NEWBNK", DEBIT, "out") == {"ok": True, "shared": True, "kind": "out"}
    assert shapes.shared() == [{"sender": "sms:NEWBNK", "skeleton": DEBIT, "kind": "out"}]
    # the same shape from ANOTHER sender is a different shape
    assert all(s["sender"] == "sms:NEWBNK" for s in shapes.shared())
    # somebody answers otherwise: it stops being shared until staff decide
    shapes.answer("app-phone-9199999999", "sms:NEWBNK", DEBIT, "none")
    assert shapes.shared() == []


def test_came_in_needs_more_people_than_went_out(tmp_path):
    shapes = PaymentAlertShapes(str(tmp_path / "s.db"))
    assert AGREE_TO_SHARE["in"] > AGREE_TO_SHARE["out"]
    for i in range(AGREE_TO_SHARE["out"]):
        shapes.answer(f"app-phone-92000000{i:02d}", "sms:NEWBNK", SHAPE, "in")
    assert shapes.shared() == []
    for i in range(AGREE_TO_SHARE["out"], AGREE_TO_SHARE["in"]):
        shapes.answer(f"app-phone-92000000{i:02d}", "sms:NEWBNK", SHAPE, "in")
    assert shapes.shared() == [{"sender": "sms:NEWBNK", "skeleton": SHAPE, "kind": "in"}]


def test_staff_decision_wins_and_can_be_handed_back(tmp_path):
    shapes = PaymentAlertShapes(str(tmp_path / "s.db"))
    shapes.answer("app-phone-9300000001", "app:com.example.bankapp", SHAPE, "in")
    shape_id = shapes.list("new")["items"][0]["id"]
    shapes.decide(shape_id, "approved", "in", "staff-1")
    assert shapes.shared() == [{"sender": "app:com.example.bankapp", "skeleton": SHAPE, "kind": "in"}]
    # people answering otherwise never undo a staff decision
    shapes.answer("app-phone-9300000002", "app:com.example.bankapp", SHAPE, "none")
    assert shapes.shared()[0]["kind"] == "in"
    shapes.decide(shape_id, "rejected", None, "staff-1")
    assert shapes.shared() == []
    shapes.decide(shape_id, "new", None, "staff-1")
    item = shapes.list("all")["items"][0]
    assert item["status"] == "new" and item["decided_by_staff"] is False and item["answers"] == {"in": 1, "out": 0, "none": 1}
    with pytest.raises(ShapeError):
        shapes.decide(shape_id, "approved", "maybe", "staff-1")
    with pytest.raises(LookupError):
        shapes.decide(shape_id + 99, "rejected", None, "staff-1")


def test_routes_sign_in_shape_check_and_staff(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    owner_key = "owner-shapes-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=owner_key))
    monkeypatch.setattr(container, "payment_alert_shapes", None, raising=False)
    rate_limit.reset_for_tests()
    client = TestClient(app)
    sender = "sms:T" + uuid.uuid4().hex[:6].upper()
    body = {"sender": sender, "skeleton": DEBIT, "answer": "out"}
    assert client.post("/api/payment-alerts/shapes", json=body).status_code == 401
    assert client.get("/api/payment-alerts/shapes").status_code == 401

    def h(n):
        return {"Authorization": f"Bearer {issue_token(f'app-phone-94111{n:05d}', container.settings.session_token_secret)}"}

    bad = client.post("/api/payment-alerts/shapes", headers=h(1), json={**body, "skeleton": "₹# debited to ramesh kumar"})
    assert bad.status_code == 422 and bad.json()["detail"]["code"] == "shape_shape_word"
    for n in range(AGREE_TO_SHARE["out"]):
        assert client.post("/api/payment-alerts/shapes", headers=h(n), json=body).status_code == 200
    got = client.get("/api/payment-alerts/shapes", headers=h(1)).json()["shapes"]
    assert {"sender": sender, "skeleton": DEBIT, "kind": "out"} in got

    assert client.get("/admin/cc/payment-shapes").status_code in (401, 403)
    admin = {"X-ASKODOX-Admin-Key": owner_key}
    listed = client.get("/admin/cc/payment-shapes?status=approved", headers=admin)
    assert listed.status_code == 200
    row = next(i for i in listed.json()["items"] if i["sender"] == sender)
    assert row["people"] == AGREE_TO_SHARE["out"] and row["answers"]["out"] == AGREE_TO_SHARE["out"]
    # nothing that could identify a person is ever returned
    assert "voter" not in str(listed.json()) and "app-phone" not in str(listed.json())
    assert client.post(f"/admin/cc/payment-shapes/{row['id']}", headers=admin, json={"status": "rejected"}).status_code == 200
    assert {"sender": sender, "skeleton": DEBIT, "kind": "out"} not in client.get(
        "/api/payment-alerts/shapes", headers=h(2)).json()["shapes"]


def test_console_view_is_on_the_map():
    from app.api.routes import admin_console, admin_console_nav

    assert "async function payshapes(" in admin_console.PAGE and "payshapes}[VIEW]" in admin_console.PAGE
    views = [v for h in admin_console_nav.NAV for c in h["cats"] for v in c["items"]]
    assert any(v["id"] == "payshapes" and v["perm"] == "payments:view" for v in views)
