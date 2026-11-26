"""Owner 2026-11-23 ("1 + 4 do"): the shop's everyday tools -- payment voice, quick bill, dues (baaki), sales reports --
are FREE FOR EVER. These tests are the tripwire: a later round cannot quietly put a price or a plan on them."""
import dataclasses
import inspect
import pathlib
import re
import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import shop_free_core
from app.services.ai_credits import FEATURES, AiCredits, CreditsError

OWNER_KEY = "owner-free-core-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
SERVICES = pathlib.Path(__file__).resolve().parents[1] / "app" / "services"

RULE = ("Owner rule 2026-11-23: payment voice, quick bill, dues and sales reports are free for ever. "
        "Do not charge AI Credits, answer 402 or check a plan here -- see app/services/shop_free_core.py.")


def _routes():
    from server import app

    return [r for r in app.routes if getattr(r, "path", "") and getattr(r, "endpoint", None) is not None]


def test_the_four_tools_are_locked_in_the_list():
    assert set(shop_free_core.keys()) >= {"payment_voice", "quick_bill", "dues", "sales_reports"}
    assert len(shop_free_core.keys()) == len(set(shop_free_core.keys()))
    telugu = re.compile(r"[ఀ-౿]")
    for row in shop_free_core.public():
        assert set(row) == {"key", "label", "what"}
        assert row["label"].strip() and telugu.search(row["what"]), row["key"]
        assert " · " not in row["label"], "ONE mixed Telugu-English label (Command Center rule)"


def test_every_pattern_still_points_at_a_real_route():
    """A renamed route must not silently fall out of the promise."""
    paths = [r.path for r in _routes()]
    for row in shop_free_core.FREE_FOREVER:
        for pattern in row["routes"]:
            assert any(re.search(pattern, p) for p in paths), f"{row['key']}: no route matches {pattern}"
    covered = {}
    for path in paths:
        key = shop_free_core.key_for_path(path)
        if key:
            covered.setdefault(key, set()).add(path)
    assert len(covered["payment_voice"]) >= 10 and len(covered["quick_bill"]) >= 8
    assert len(covered["dues"]) >= 5 and len(covered["sales_reports"]) >= 6
    assert "/api/pos/businesses/{business_id}/invoices" in covered["quick_bill"]
    assert "/api/pos/businesses/{business_id}/dues" in covered["dues"]
    assert "/api/pos/businesses/{business_id}/reports/day" in covered["sales_reports"]
    assert "/api/pos/businesses/{business_id}/payment-alerts/events" in covered["payment_voice"]
    assert "/api/in-app/voice/speak" in covered["payment_voice"], "the phone fetches the payment voice parts here"
    # paid extras stay outside the promise (they may use AI Credits)
    for extra in ("/api/pos/businesses/{business_id}/agents", "/api/images/edit", "/api/in-app/assistant"):
        assert shop_free_core.key_for_path(extra) is None, extra


def test_no_free_forever_route_charges_or_checks_a_plan():
    checked = 0
    for route in _routes():
        key = shop_free_core.key_for_path(route.path)
        if not key:
            continue
        marks = shop_free_core.charge_marks(inspect.getsource(route.endpoint))
        assert not marks, f"{route.path} ({key}) carries {marks}. {RULE}"
        checked += 1
    assert checked >= 40


def test_the_services_behind_them_never_reach_for_credits_or_billing():
    for name in ("pos_store.py", "pos_payment_alerts.py", "pos_bills.py", "pos_dues_followup.py", "pos_reports.py"):
        source = (SERVICES / name).read_text(encoding="utf-8")
        for word in ("ai_credits", "AiCredits", "import billing", "billing.options", "AI_CREDITS_LOW"):
            assert word not in source, f"{name} mentions {word}. {RULE}"


def test_the_charge_words_are_noticed():
    """The tripwire itself: a handler that reserves credits or answers 402 is caught."""
    assert shop_free_core.charge_marks("metered = _reserve_credits(request, locale)") == ["_reserve_credits"]
    assert shop_free_core.charge_marks('raise HTTPException(status_code=402, detail="AI_CREDITS_LOW")')
    assert shop_free_core.charge_marks("return store.create_invoice(business_id, user, body)") == []


def test_credits_can_never_carry_a_rate_for_them(tmp_path):
    assert not set(FEATURES) & set(shop_free_core.keys())
    svc = AiCredits(str(tmp_path / "c.db"), clock=lambda: datetime(2026, 11, 23, 6, 0, tzinfo=timezone.utc))
    for key in shop_free_core.keys():
        with pytest.raises(CreditsError) as err:
            svc.update_settings({"rates_paise": {key: 50}}, actor="staff:1")
        assert err.value.code == "free_forever" and err.value.detail == {"feature": key}
        with pytest.raises(CreditsError) as err:
            svc.update_settings({"free_per_day": {key: 3}}, actor="staff:1")
        assert err.value.code == "free_forever"
    # charging ON with a real rate: a free-forever tool is still free, and nothing is written to the ledger
    svc.update_settings({"plan": {"daily_free_paise": 0, "first_bonus_pct": 0, "daily_bonus_pct": 0}, "charging": True, "rates_paise": {"chat": 50}}, actor="staff:1")
    user = "app-phone-9400000911"
    for key in shop_free_core.keys():
        assert svc.reserve(user, key, f"r-{key}") == {"charged": False, "reason": "free_forever", "paise": 0}
    assert svc.history(user) == [] and svc.balance(user) == {"live": 0, "test": 0}
    with pytest.raises(CreditsError) as err:  # a paid AI feature still needs credits
        svc.reserve(user, "chat", "r-chat")
    assert err.value.status == 402


def test_command_center_shows_the_list_as_locked(monkeypatch):
    from app.api.routes import admin_console
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    client = TestClient(app)
    assert client.get("/admin/cc/ai-credits/settings").status_code in (401, 403)
    body = client.get("/admin/cc/ai-credits/settings", headers=OWNER)
    assert body.status_code == 200, body.text
    data = body.json()
    assert [x["key"] for x in data["free_forever"]] == list(shop_free_core.keys())
    assert {"charging", "rates_paise", "free_per_day"} <= set(data)
    refused = client.put("/admin/cc/ai-credits/settings", headers=OWNER, json={"rates_paise": {"quick_bill": 10}})
    assert refused.status_code == 400 and refused.json()["detail"]["code"] == "free_forever"
    assert "ఎప్పటికీ Free" in admin_console.PAGE and "st.free_forever" in admin_console.PAGE
