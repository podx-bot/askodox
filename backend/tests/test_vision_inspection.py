"""Vision Inspection: one evidence contract across unrelated domains.

A photo never certifies anything: food safety, roadworthiness, tyre pressure,
exact animal weight, structural safety, confirmed disease and authenticity are
moved to not_verifiable whatever the model wrote. Cost: bounded images per
mode, model fallback limits, cached repeats, no call without an image."""
import base64

import pytest
from fastapi.testclient import TestClient

from app.services import external_call_budget, rate_limit, vision_inspection
from app.services.vision_inspection import DOMAIN_PROFILES, MODES, resolve_domain, sanitize_report

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")


def _payload(observed=(), inferred=(), quantities=(), **extra):
    return {
        "subject": extra.pop("subject", "item"),
        "observed": [{"finding": f, "region": "centre", "confidence": 0.9} for f in observed],
        "inferred": [{"finding": f, "basis": "colour and texture", "confidence": 0.7} for f in inferred],
        "quantities": list(quantities),
        "confidence": extra.pop("confidence", 0.85),
        **extra,
    }


# ------------------------------------------------------------ never-claim rules

@pytest.mark.parametrize("domain, claim, kept", [
    ("food", "The chicken is safe to eat", "Pink flesh with a moist surface"),
    ("food", "Milk is free from adulteration", "Milk packet sealed, no leaks"),
    ("food", "These mangoes contain carbide", "Uniform yellow skin with green patches"),
    ("vehicle", "The car is roadworthy", "Dent on the rear left door"),
    ("vehicle", "Engine is in good condition", "Headlight lens is cloudy"),
    ("tyre", "Pressure is about 32 psi", "Uneven wear on the outer shoulder"),
    ("tyre", "Tread depth is 4 mm", "Small crack on the sidewall"),
    ("construction", "The wall is structurally safe", "Hairline vertical crack near the window"),
    ("crop", "Confirmed diagnosis: leaf blast", "Brown spindle-shaped spots on leaves"),
    ("crop", "Spray 2 ml per litre of mancozeb", "Yellowing on lower leaves"),
    ("livestock", "The goat is healthy", "Goat standing, coat looks glossy"),
    ("product", "This phone is 100% genuine", "Box print is slightly blurred"),
])
def test_photo_never_certifies_across_domains(domain, claim, kept):
    report = sanitize_report(_payload(observed=[claim, kept]), domain, "deep")
    findings = [o["finding"] for o in report["observed"]]
    assert kept in findings
    assert claim not in findings, f"{domain}: certifying claim must not stay observed"
    assert report["not_verifiable"], "the limitation is stated instead"
    assert report["corrected_claims"] == 1
    assert report["confidence"] <= 0.6


def test_inferred_claims_are_filtered_too_and_need_a_basis():
    raw = _payload(inferred=["Food is fit for consumption"])
    raw["inferred"].append({"finding": "Probably two days old", "basis": "", "confidence": 0.9})
    report = sanitize_report(raw, "food", "quick")
    assert [i["finding"] for i in report["inferred"]] == ["Probably two days old"]
    assert report["inferred"][0]["confidence"] <= 0.4, "an inference without basis is tentative"


def test_domain_warnings_and_checks_always_attached():
    for domain in ("food", "vehicle", "livestock", "crop"):
        report = sanitize_report(_payload(observed=["visible thing"]), domain, "quick")
        for warning in DOMAIN_PROFILES[domain]["warnings"]:
            assert warning in report["safety_warnings"]
        for check in DOMAIN_PROFILES[domain]["checks"]:
            assert check in report["recommended_checks"]


def test_general_and_non_commerce_photos_use_the_same_contract():
    report = sanitize_report(_payload(observed=["A handwritten note on paper"], subject="note"), "general", "quick")
    assert report["status"] == "ok" and report["domain"] == "general"
    assert set(report) >= {"observed", "inferred", "not_verifiable", "recommended_checks", "safety_warnings",
                           "quantities", "needs_more_evidence", "limits"}


# ------------------------------------------------------------ quantities

def test_livestock_weight_without_reference_object_is_unavailable():
    raw = _payload(observed=["Goat side view"],
                   quantities=[{"name": "live weight", "low": 22, "high": 28, "unit": "kg", "basis": "body length"}])
    report = sanitize_report(raw, "livestock", "expert")
    assert report["quantities"] == []
    assert any("reference object" in n for n in report["not_verifiable"])


def test_livestock_weight_with_reference_is_experimental_range():
    raw = _payload(observed=["Goat beside an A4 sheet"],
                   quantities=[{"name": "live weight", "low": 25, "high": 25, "unit": "kg", "basis": "A4 sheet"}])
    report = sanitize_report(raw, "livestock", "expert", reference_object="A4 sheet")
    (q,) = report["quantities"]
    assert q["status"] == "experimental" and q["low"] < 25 < q["high"], "single value widened, never exact"


def test_invalid_quantities_dropped_for_any_domain():
    raw = _payload(observed=["Biryani in a steel plate"], quantities=[
        {"name": "rice", "low": 300, "high": 200, "unit": "g"},
        {"name": "chicken", "low": "abc", "high": 2, "unit": "pieces"},
        {"name": "serving", "low": 1, "high": 2, "unit": "plates", "basis": "plate size"},
    ])
    report = sanitize_report(raw, "dish", "deep")
    assert [q["name"] for q in report["quantities"]] == ["serving"]


# ------------------------------------------------------------ quality / status

def test_unusable_photo_asks_for_more_evidence():
    report = sanitize_report(_payload(observed=["Blurry object"], image_quality={"usable": False, "issues": ["blur"]}),
                             "general", "quick")
    assert report["status"] == "low_confidence" and report["confidence"] <= 0.3
    assert report["needs_more_evidence"]


def test_empty_model_payload_is_insufficient_not_invented():
    report = sanitize_report({}, "food", "quick")
    assert report["status"] == "insufficient_evidence" and report["observed"] == []


def test_domain_and_mode_resolution():
    assert resolve_domain("goat") == "livestock" and resolve_domain("biryani") == "dish"
    assert resolve_domain("unknown-thing") == "general"
    assert vision_inspection.resolve_mode("turbo") == "quick"


# ------------------------------------------------------------ service + route

class _Brain:
    client = object()

    def __init__(self, payload=None):
        self.calls = []
        self.payload = payload if payload is not None else _payload(
            observed=["Chicken pieces, pink, moist", "Looks safe to eat"], subject="chicken")

    def analyze_with_prompt(self, images, prompt, max_models=1, allow_second_provider=False):
        self.calls.append({"images": len(images), "prompt": prompt, "max_models": max_models,
                           "second": allow_second_provider})
        return self.payload, 1 if self.payload else max_models


@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    external_call_budget.reset_for_tests()
    brain = _Brain()
    monkeypatch.setattr(container, "universal_image_service", brain, raising=False)
    monkeypatch.setattr(container, "vision_inspection_service", None, raising=False)
    return TestClient(app), brain


def _img():
    return {"image_base64": base64.b64encode(PNG).decode(), "mime_type": "image/png"}


def test_route_returns_evidence_report_and_strips_certification(api):
    client, brain = api
    response = client.post("/api/vision/inspect", json={"images": [_img()], "domain": "food", "mode": "quick",
                                                         "language": "te", "user_text": "ఈ చికెన్ ఫ్రెష్‌గా ఉందా?"})
    assert response.status_code == 200, response.text
    report = response.json()["report"]
    assert report["domain"] == "food" and report["mode"] == "quick"
    assert all("safe to eat" not in o["finding"] for o in report["observed"])
    assert "A photo cannot certify that food is safe to eat." in report["safety_warnings"]
    assert "Telugu" in brain.calls[0]["prompt"], "replies in the user's language"
    assert response.json()["facts"].startswith("Inspection (food, quick)")


@pytest.mark.parametrize("mode", list(MODES))
def test_mode_bounds_images_and_model_fallback(api, mode):
    client, brain = api
    response = client.post("/api/vision/inspect", json={"images": [_img()] * 6, "domain": "vehicle", "mode": mode})
    assert response.status_code == 200, response.text
    call = brain.calls[-1]
    assert call["images"] == MODES[mode]["max_images"]
    assert call["max_models"] == MODES[mode]["max_models"]
    assert call["second"] == MODES[mode]["second_provider"]
    cost = response.json()["report"]["cost"]
    assert cost["images_sent"] == MODES[mode]["max_images"] and cost["images_dropped"] == 6 - MODES[mode]["max_images"]


def test_identical_request_is_cached_and_metered(api):
    client, brain = api
    body = {"images": [_img()], "domain": "tyre", "mode": "deep"}
    first = client.post("/api/vision/inspect", json=body).json()["report"]["cost"]
    second = client.post("/api/vision/inspect", json=body).json()["report"]["cost"]
    assert len(brain.calls) == 1, "the repeat is served from cache, no second paid call"
    assert first["cached"] is False and second["cached"] is True
    usage = external_call_budget.usage_snapshot()["vision_inspect"]
    assert usage["calls"] == 1 and usage["cache_hits"] == 1


def test_no_provider_answer_is_honest_failure(api, monkeypatch):
    client, brain = api
    brain.payload = {}
    response = client.post("/api/vision/inspect", json={"images": [_img()], "domain": "crop"})
    assert response.status_code == 502


def test_non_image_and_bad_data_rejected(api):
    client, brain = api
    pdf = {"image_base64": base64.b64encode(b"%PDF-1.4").decode(), "mime_type": "application/pdf"}
    assert client.post("/api/vision/inspect", json={"images": [pdf]}).status_code == 415
    bad = {"image_base64": "not base64!!", "mime_type": "image/jpeg"}
    assert client.post("/api/vision/inspect", json={"images": [bad]}).status_code == 400
    assert client.post("/api/vision/inspect", json={"images": []}).status_code == 422
    assert brain.calls == [], "no model call without a valid image"


def test_profiles_endpoint_lists_every_domain_in_both_languages(api):
    client, _ = api
    en = client.get("/api/vision/profiles").json()
    te = client.get("/api/vision/profiles", params={"language": "te"}).json()
    assert {p["domain"] for p in en["profiles"]} == set(DOMAIN_PROFILES)
    food_te = next(p for p in te["profiles"] if p["domain"] == "food")
    assert food_te["label"] == "ఆహార నాణ్యత & తాజాదనం" and food_te["guidance"]
