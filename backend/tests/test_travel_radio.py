"""Travel Radio add-on: separate billing (never replaces the base plan),
plans stored INACTIVE, no access without an ACTIVE pass, segments built only
from real facts, cached audio, no repeats, metering + daily cap, and an
ESTIMATE cost model for light / medium / heavy listeners."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services import travel_radio
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-radio-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


class FakeMaps:
    enabled = True

    def __init__(self):
        self.calls = 0

    def reverse_geocode(self, lat, lng):
        self.calls += 1
        return {"area": "Uyyuru", "city": "Uyyuru", "label": "Uyyuru, Andhra Pradesh"}

    def search_places(self, q, latitude=None, longitude=None, radius_m=0, limit=4):
        self.calls += 1
        return [{"name": "Sri Kanaka Durga Temple"}, {"name": "Prakasam Barrage"}]


class FakeVoice:
    def __init__(self):
        self.texts = []

    def synthesize(self, text, voice="automatic"):
        self.texts.append(text)
        return {"success": True, "tts_path": "sarvam_bulbul", "content": b"OGG" + text.encode()[:8],
                "mime_type": "audio/ogg"}


@pytest.fixture()
def env(monkeypatch):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    maps, voice = FakeMaps(), FakeVoice()
    monkeypatch.setattr(container, "google_maps_service", maps, raising=False)
    monkeypatch.setattr(container, "voice_assistant_service", voice, raising=False)
    _cc(container).set_flag("radio.enabled", True, "test")
    yield TestClient(app), container, maps, voice
    _cc(container).set_flag("radio.enabled", False, "test")


def _cc(container):
    from app.api.routes.command_center import command_center

    return command_center(container)


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _spot():  # a fresh cell per test so the area cache never leaks
    n = uuid.uuid4().int % 2400
    return {"latitude": -40.0 + n * 0.05, "longitude": 10.0 + n * 0.05}


def test_plans_are_seeded_inactive_and_never_replace_the_base_plan(env):
    client, container, *_ = env
    uid, me = _user(container)
    status = client.get("/api/radio/status", headers=me).json()
    assert {(p["code"], p["price"], p["period_days"]) for p in status["plans"]} == {
        ("radio_1d", 29, 1), ("radio_7d", 149, 7), ("radio_30d", 399, 30)}
    assert all(p["available"] is False for p in status["plans"]), "proposed prices are NOT activated"
    assert status["access"] is False and status["billing"] == "not_available"
    assert client.post("/api/radio/pass", headers=me, json={"plan_code": "radio_7d"}).status_code == 409
    # Even if staff activate a plan, the base subscription route refuses an add-on.
    from app.api.routes.growth import growth

    repo = growth(container)
    plan = repo.plan("radio_7d")
    repo.upsert_plan("radio_7d", name=plan["name"], audience=plan["audience"], price=plan["price"],
                     period_days=plan["period_days"], entitlements=plan["entitlements"], active=True)
    try:
        assert client.post("/api/subscriptions", headers=me, json={"plan_code": "radio_7d"}).status_code == 409
        assert all(p["code"] != "radio_7d" for p in client.get("/api/plans").json()["items"])
        asked = client.post("/api/radio/pass", headers=me, json={"plan_code": "radio_7d"}).json()
        assert asked["pass"]["status"] == "PENDING_PAYMENT", "no gateway: a paid pass never grants access"
        assert client.post("/api/radio/next", headers=me, json=_spot()).status_code == 402
    finally:
        repo.upsert_plan("radio_7d", name=plan["name"], audience=plan["audience"], price=plan["price"],
                         period_days=plan["period_days"], entitlements=plan["entitlements"], active=False)


def test_flag_off_and_sign_in_are_enforced(env):
    client, container, *_ = env
    _, me = _user(container)
    assert client.post("/api/radio/next", json=_spot()).status_code == 401
    _cc(container).set_flag("radio.enabled", False, "test")
    assert client.post("/api/radio/next", headers=me, json=_spot()).status_code == 503


def test_promotional_pass_real_facts_cached_audio_no_repeats(env):
    client, container, maps, voice = env
    uid, me = _user(container)
    other, me2 = _user(container)
    assert client.post("/admin/cc/radio/passes", json={"user_id": uid, "plan_code": "radio_1d"}).status_code in (401, 403)
    for u in (uid, other):
        granted = client.post("/admin/cc/radio/passes", headers=OWNER, json={"user_id": u, "plan_code": "radio_1d"})
        assert granted.status_code == 200 and granted.json()["pass"]["source"] == "promotional"
    spot = _spot()
    first = client.post("/api/radio/next", headers=me, json={**spot, "lang": "te"}).json()
    assert first["status"] == "ok"
    seg = first["segment"]
    assert "Uyyuru" in seg["text"] and "Prakasam Barrage" in seg["text"]
    assert first["audio_b64"] and first["audio_cached"] is False
    assert maps.calls == 2
    # Same place again: never the same segment twice; when the real facts
    # (area + any LIVE news) run out the answer is "nothing new", no filler.
    texts = [seg["text"]]
    for _ in range(10):
        again = client.post("/api/radio/next", headers=me, json={**spot, "lang": "te"}).json()
        if again["status"] == "nothing_new":
            break
        texts.append(again["segment"]["text"])
    assert again == {"status": "nothing_new", "segment": None}
    assert len(texts) == len(set(texts))
    # Another listener in the same cell: area facts AND audio come from cache.
    shared = client.post("/api/radio/next", headers=me2, json={**spot, "lang": "te"}).json()
    assert shared["segment"]["text"] == seg["text"] and shared["audio_cached"] is True
    assert maps.calls == 2 and voice.texts.count(seg["text"]) == 1
    board = client.get("/admin/cc/radio", headers=OWNER).json()
    assert board["usage"]["segments"] >= 2 and board["usage"]["cost_basis"] == "ESTIMATE"


def test_no_facts_means_no_segment(env):
    client, container, maps, _ = env
    uid, me = _user(container)
    maps.enabled = False
    client.post("/admin/cc/radio/passes", headers=OWNER, json={"user_id": uid, "plan_code": "radio_1d"})
    from app.api.routes import affiliate_catalog

    class NoContent:
        def content(self, **_):
            return []

    container.affiliate_catalog, saved = NoContent(), getattr(container, "affiliate_catalog", None)
    try:
        out = client.post("/api/radio/next", headers=me, json=_spot()).json()
    finally:
        container.affiliate_catalog = saved
    assert out == {"status": "nothing_new", "segment": None}
    assert affiliate_catalog  # module import kept for the monkeypatched store


def test_daily_cap_is_enforced(env, monkeypatch):
    client, container, *_ = env
    uid, me = _user(container)
    client.post("/admin/cc/radio/passes", headers=OWNER, json={"user_id": uid, "plan_code": "radio_1d"})
    from app.api.routes.radio import radio

    monkeypatch.setattr(radio(container), "seconds_today", lambda user: 10 ** 6)
    assert client.post("/api/radio/next", headers=me, json=_spot()).status_code == 429


def test_cost_model_light_medium_heavy_estimates():
    model = travel_radio.cost_model()
    assert model["basis"] == "ESTIMATE"
    rows = {r["profile"]: r for r in model["profiles"]}
    assert set(rows) == {"light", "medium", "heavy"}
    assert rows["light"]["total_inr_per_day"] < rows["medium"]["total_inr_per_day"] < rows["heavy"]["total_inr_per_day"]
    assert rows["heavy"]["minutes_per_day"] <= model["assumptions"]["daily_minutes_cap"]
    # Switching the nearby lookup off leaves only the cheap place-name call.
    from app.services import platform_settings

    real = platform_settings.get
    try:
        platform_settings.get = lambda key, default=None: 0.0 if key == "radio.nearby_places" else real(key, default)
        lean = {r["profile"]: r for r in travel_radio.cost_model()["profiles"]}
    finally:
        platform_settings.get = real
    assert lean["heavy"]["maps_inr_per_day"] < rows["heavy"]["maps_inr_per_day"]
    for row in rows.values():
        assert {p["code"] for p in row["plans"]} == {"radio_1d", "radio_7d", "radio_30d"}
        for p in row["plans"]:
            assert p["margin_estimate_inr"] == pytest.approx(p["price"] - p["cost_estimate_inr"], abs=0.01)
