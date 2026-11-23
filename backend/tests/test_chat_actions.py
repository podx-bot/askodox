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
    assert "ai_credits" in block and "rides_parcels" not in block
    assert "rides_parcels" in ca.prompt_block(), "old APKs / Phase 2 still get the whole catalog"
    assert ca.resolve({"key": "rides_parcels"}, phase1_only=True) is None
    assert ca.resolve({"key": "ai_credits"}, phase1_only=True)["route"] == "/me/ai-credits"

    brain, models = _brain({"key": "rides_parcels"})
    caps = ["meaning_tags", ca.CAPABILITY, ca.PHASE1_CAPABILITY]
    out = brain.decide("bill veyyali", capabilities=caps)
    assert "rides_parcels" not in models.prompts[-1] and "app_action" not in out
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


def test_shopping_switch_adds_the_shop_tools_to_a_phase1_build():
    from app.services import chat_actions as ca
    phase1 = ca.keys_for(["app_actions", "phase1_only"])
    shopping = ca.keys_for(["app_actions", "phase1_only", "shopping_tools"])
    assert ca.keys_for(["app_actions"]) is None
    # Owner 2026-11-19 (later the same day): shop tools open from the chat in every Phase 1 build.
    assert "pos_bill" in phase1 and "shop_agents" in phase1 and "shop_new_bill" in shopping
    assert ca.resolve({"key": "shop_agents"}, False, phase1)["route"] == "/my-shop/agents"
    assert ca.resolve({"key": "rides_parcels"}, False, shopping) is None
    assert "my ai agents" in ca.prompt_block(phase1)


def _shop_page_names():
    """The app's ONE name per shop page (lib/features/pos/domain/shop_page_names.dart) + `/my-shop/<tool>` -> page."""
    import pathlib

    lib = pathlib.Path(__file__).resolve().parents[2] / "lib"
    src = lib / "features" / "pos" / "domain" / "shop_page_names.dart"
    if not src.exists():
        pytest.skip("app sources not in this checkout")
    text = src.read_text(encoding="utf-8")
    names = {t: (en, te) for t, en, te in re.findall(r"  '([^']+)': \('([^']+)', '([^']+)'\),", text)}
    tools = dict(re.findall(r"  '([^']+)': '(/[^']+)',", text))
    biz = (lib / "features" / "business" / "presentation" / "biz_hub.dart").read_text(encoding="utf-8")
    body = biz[biz.index("String askodoxBizRoute"):biz.index("class AskodoxBizTileSpec")]
    pages = {}
    for keys, route in re.findall(r"((?:'[^']+'\s*(?:\|\|\s*)?)+)=>\s*'([^'$]*\$id[^']*)',", body):
        for key in re.findall(r"'([^']+)'", keys):
            pages[key] = route.replace("$id", "<id>")
    return names, tools, pages


def test_a_chat_button_names_a_shop_page_exactly_as_the_app_does():
    """Owner 2026-11-24: "New bill" and "Counter bill" were two pins for the same counter page -- one page, one name."""
    names, tools, _ = _shop_page_names()
    assert names["/pos/<id>/sale"] == ("Counter bill", "కౌంటర్ బిల్లు")
    checked = 0
    for key, route, en, te, _about in ca.CATALOG:
        m = re.fullmatch(r"/my-shop/([^/?]+)", route)
        if not m:
            continue
        assert m.group(1) in tools, f"{key}: /my-shop/{m.group(1)} is not in askodoxShopToolPages"
        assert (en, te) == names[tools[m.group(1)]], f"{key} is called {(en, te)}, the app calls it {names[tools[m.group(1)]]}"
        checked += 1
    assert checked >= 15


def test_the_ask_bar_names_a_shop_page_exactly_as_the_app_does():
    from app.services import pos_hub

    names, _, pages = _shop_page_names()
    # These keys are ACTIONS that land on a shared page ("Add staff" opens Staff & roles), not that page's name.
    actions = {"orders.calls", "orders.delivery", "staff.add"}
    checked = 0
    for key, (en, te) in pos_hub.PAGES.items():
        page = pages.get(key)
        if key in actions or page not in names:
            continue
        assert (en, te) == names[page], f"ASK bar page {key} is called {(en, te)}, the app calls it {names[page]}"
        checked += 1
    assert checked >= 5
