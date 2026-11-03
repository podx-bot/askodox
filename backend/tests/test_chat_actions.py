"""Chat actions (owner vision 2026-10-30): any ASKODOX feature opens from the
main chat. ONE catalog, picked by the brain by meaning; the app shows a button
the user taps. Old APKs (no ``app_actions`` capability) see nothing new."""
import json
import re
from types import SimpleNamespace

import pytest

from app.services import chat_actions as ca
from app.services import universal_ai_assistant_service as svc


class _Models:
    def __init__(self, app_action):
        self.prompts = []
        self.app_action = app_action

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        body = {"reply": "POS లో bill వేయొచ్చు.", "domain": "GENERAL", "transactional": False,
                "action": "open_feature", "confidence": 0.9, "entities": {}}
        if self.app_action is not None:
            body["app_action"] = self.app_action
        return SimpleNamespace(text=json.dumps(body, ensure_ascii=False))


def _brain(app_action):
    models = _Models(app_action)
    return svc.UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=models)), models


def test_catalog_is_one_table_with_unique_keys_and_app_routes():
    keys = [row[0] for row in ca.CATALOG]
    assert len(keys) == len(set(keys))
    for key, route, en, te, about in ca.CATALOG:
        assert re.fullmatch(r"[a-z_]{2,40}", key) and route.startswith("/") and en and te and about


def test_every_catalog_route_exists_in_the_app_router():
    import pathlib

    lib = pathlib.Path(__file__).resolve().parents[2] / "lib"
    if not lib.exists():
        pytest.skip("app sources not in this checkout")
    declared = set()
    for path in lib.rglob("*.dart"):
        declared.update(re.findall(r"path: '(/[^']*)'", path.read_text(encoding="utf-8", errors="ignore")))
    missing = [r for r in ca.routes() if r not in declared]
    assert not missing, f"chat actions point at routes the app does not have: {missing}"


def test_resolve_accepts_only_known_keys():
    assert ca.resolve({"key": "pos_bill"}) == {"key": "pos_bill", "route": "/pos", "label": "Billing / POS"}
    assert ca.resolve("ai_credits", telugu=True)["label"] == "AI Credits"
    assert ca.resolve({"key": "delete_everything"}) is None
    assert ca.resolve({"key": "../admin"}) is None
    assert ca.resolve(None) is None


def test_brain_returns_the_action_only_for_apps_that_render_it():
    brain, models = _brain({"key": "pos_bill"})
    old = brain.decide("bill veyyali 2 kg rice")
    assert "app_action" not in old and "APP ACTIONS" not in models.prompts[-1]
    new = brain.decide("bill veyyali 2 kg rice", capabilities=["meaning_tags", ca.CAPABILITY])
    assert "APP ACTIONS" in models.prompts[-1] and "pos_bill" in models.prompts[-1]
    assert new["app_action"] == {"key": "pos_bill", "route": "/pos", "label": "Billing / POS"}


def test_unknown_or_missing_model_action_adds_nothing():
    for raw in ({"key": "hack"}, None):
        brain, _ = _brain(raw)
        assert "app_action" not in brain.decide("hello", capabilities=[ca.CAPABILITY])


def test_phase1_app_is_offered_and_given_only_phase1_screens():
    """Owner decision 2026-11-04: a Phase 1 app hides business / POS / rides / roles screens."""
    assert ca.PHASE1_KEYS <= {row[0] for row in ca.CATALOG}
    block = ca.prompt_block(phase1_only=True)
    assert "ai_credits" in block and "pos_bill" not in block and "rides_parcels" not in block
    assert "pos_bill" in ca.prompt_block(), "old APKs / Phase 2 still get the whole catalog"
    assert ca.resolve({"key": "pos_bill"}, phase1_only=True) is None
    assert ca.resolve({"key": "ai_credits"}, phase1_only=True)["route"] == "/me/ai-credits"

    brain, models = _brain({"key": "pos_bill"})
    caps = ["meaning_tags", ca.CAPABILITY, ca.PHASE1_CAPABILITY]
    out = brain.decide("bill veyyali", capabilities=caps)
    assert "pos_bill" not in models.prompts[-1] and "app_action" not in out
    brain, models = _brain({"key": "payment_methods"})
    out = brain.decide("naa upi qr add cheyyali", capabilities=caps)
    assert out["app_action"]["route"] == "/me/payment-methods"


def test_prompt_keeps_searches_as_searches_and_never_claims_opening():
    block = ca.prompt_block()
    assert "searches stay searches" in block and "Never claim the screen was opened" in block
    assert "taps a button" in block


def test_route_carries_app_action_through_the_response_model(monkeypatch):
    from fastapi.testclient import TestClient

    from server import app, container

    seen = []

    def decide(message, **kwargs):
        seen.append(kwargs.get("capabilities"))
        return {"reply": "ok", "domain": "GENERAL", "transactional": False, "action": "open_feature",
                "confidence": 0.9, "entities": {}, "mode": "chat",
                "app_action": {"key": "orders_mine", "route": "/orders/mine", "label": "My orders"}}

    monkeypatch.setattr(container.universal_ai_assistant_service, "decide", decide, raising=False)
    body = TestClient(app).post("/api/in-app/assistant",
                                json={"message": "naa orders choopinchu", "capabilities": [ca.CAPABILITY]}).json()
    assert seen[-1] == [ca.CAPABILITY]
    assert body.get("app_action") == {"key": "orders_mine", "route": "/orders/mine", "label": "My orders"}
