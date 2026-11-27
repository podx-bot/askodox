"""Bills & warranty: the photo reader's answer is cleaned and bounded, a warranty end is worked out only from printed
facts, nothing is stored, and a read that gave nothing costs nothing."""
import base64
from datetime import date

from app.services import paper_vault


class _Reader:
    def __init__(self, payload, fail=False):
        self.payload, self.fail, self.calls = payload, fail, 0

    def analyze_with_prompt(self, photos, prompt, **kwargs):
        self.calls += 1
        assert "NEVER guess" in prompt and photos
        if self.fail:
            raise RuntimeError("provider down")
        return self.payload, 1


PHOTO = [(b"\xff\xd8sample", "image/jpeg")]


def test_printed_facts_are_cleaned_and_the_end_day_is_worked_out_from_them():
    out = paper_vault.read_paper(_Reader({
        "item": "  Sample   Mixer Grinder 750W ", "shop": "Sample Stores", "bought_on": "2026-01-31",
        "warranty_months": 24, "warranty_until": None, "serial": "SN-12 34/AB!", "service_phone": "1800 123 4567",
        "amount": "3,499"}), PHOTO)
    assert out == {"read": True, "item": "Sample Mixer Grinder 750W", "shop": "Sample Stores", "bought_on": "2026-01-31",
                   "warranty_months": 24, "warranty_until": "2028-01-31", "warranty_from": "worked_out",
                   "serial": "SN-1234/AB", "service_phone": "18001234567", "amount_paise": 349900}


def test_a_printed_end_day_wins_and_unreadable_values_stay_empty():
    out = paper_vault.clean({"item": "Sample Phone", "bought_on": "31/01/2026", "warranty_months": 12,
                             "warranty_until": "2027-03-15", "service_phone": "12345", "amount": None})
    assert out["warranty_until"] == "2027-03-15" and out["warranty_from"] == "printed"
    assert out["bought_on"] == "" and out["service_phone"] == "" and out["amount_paise"] is None and out["read"] is True
    # a period with no purchase date gives no end day (never a guess)
    only_period = paper_vault.clean({"item": "Sample Fan", "warranty_months": 24})
    assert only_period["warranty_until"] == "" and only_period["warranty_from"] == "" and only_period["warranty_months"] == 24
    assert paper_vault.clean({"item": "Sample Fan", "warranty_months": 999})["warranty_months"] == 0
    assert paper_vault.clean("not json")["read"] is False and paper_vault.clean({})["read"] is False


def test_month_ends_and_days_left():
    assert paper_vault.warranty_end("2026-01-31", 1) == "2026-02-28"
    assert paper_vault.warranty_end("2024-02-29", 12) == "2025-02-28"
    assert paper_vault.warranty_end("", 12) == "" and paper_vault.warranty_end("2026-01-31", 0) == ""
    assert paper_vault.warranty_end("2026-13-40", 12) == ""
    assert paper_vault.days_left("2026-12-22", date(2026, 11, 27)) == 25
    assert paper_vault.days_left("2026-11-20", date(2026, 11, 27)) == -7
    assert paper_vault.days_left("", date(2026, 11, 27)) is None


def test_the_reader_never_raises():
    assert paper_vault.read_paper(_Reader(None, fail=True), PHOTO)["read"] is False
    assert paper_vault.read_paper(None, PHOTO)["read"] is False
    assert paper_vault.read_paper(_Reader({"item": "x"}), [])["read"] is False


def test_route_needs_sign_in_reads_and_gives_the_use_back_when_nothing_was_read(monkeypatch):
    from fastapi.testclient import TestClient

    from app.api.routes.ai_credits import ai_credits
    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    client = TestClient(app)
    user = "app-phone-9400000301"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    body = {"images": [{"data": base64.b64encode(b"\xff\xd8sample").decode(), "mime": "image/jpeg"}]}

    assert client.post("/api/me/vault/read", json=body).status_code == 401
    assert client.post("/api/me/vault/read", headers=auth, json={"images": []}).status_code == 400
    assert client.post("/api/me/vault/read", headers=auth,
                       json={"images": [{"data": "aGk=", "mime": "application/pdf"}]}).status_code == 400

    reserved, released = [], []
    credits = ai_credits(container)
    monkeypatch.setattr(credits, "reserve", lambda u, feature, ref: reserved.append((u, feature)) or {"charged": False})
    monkeypatch.setattr(credits, "release", lambda u, ref: released.append(u) or True)

    monkeypatch.setattr(container, "universal_image_service",
                        _Reader({"item": "Sample Mixer", "bought_on": "2026-01-31", "warranty_months": 12}), raising=False)
    out = client.post("/api/me/vault/read", headers=auth, json=body)
    assert out.status_code == 200 and out.json()["warranty_until"] == "2027-01-31" and out.json()["read"] is True
    assert reserved == [(user, "image")] and released == []

    monkeypatch.setattr(container, "universal_image_service", _Reader({}), raising=False)
    assert client.post("/api/me/vault/read", headers=auth, json=body).json()["read"] is False
    assert released == [user]
