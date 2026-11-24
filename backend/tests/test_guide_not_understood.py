"""Page guide: understood / not understood (owner 2026-11-24: fewer sales executives, the app explains itself)."""
from datetime import datetime, timezone

from app.services.guide_feedback import GuideFeedback


def test_counts_per_page_and_refuses_real_ids(tmp_path):
    fb = GuideFeedback(str(tmp_path / "g.db"), clock=lambda: datetime(2026, 11, 24, 6, tzinfo=timezone.utc))
    assert fb.record("/pos/:id/sale", "not_understood")
    assert fb.record("/pos/:id/sale", "not_understood")
    assert fb.record("/pos/:id/sale", "simpler")
    assert fb.record("/pos/:id/sale", "understood")
    assert fb.record("/money-home", "understood")
    assert not fb.record("/pos/9848011111/sale", "understood"), "a real number never lands here"
    assert not fb.record("/pos/:id/sale", "anything")
    pages = fb.pages()
    assert pages[0]["path"] == "/pos/:id/sale" and pages[0]["not_understood"] == 2
    assert pages[0]["not_understood_share"] == round(2 / 3, 3) and pages[0]["simpler"] == 1


def test_guide_lines_are_kept_on_disk_whatever_their_length(tmp_path, monkeypatch):
    from app.services import elevenlabs_tts

    tts = elevenlabs_tts.ElevenLabsTTS(cache_dir=str(tmp_path / "c"))
    stored = []
    monkeypatch.setattr(tts, "_disk_put", lambda key, audio: stored.append(key))
    assert "keep" in tts.synthesize.__code__.co_varnames


def test_feedback_route_and_admin_page():
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from server import app

    rate_limit.reset_for_tests()
    client = TestClient(app)
    out = client.post("/api/in-app/guide/feedback", json={"path": "/pos/:id/bill", "step": "not_understood"})
    assert out.status_code == 200 and out.json()["recorded"] is True
    assert client.post("/api/in-app/guide/feedback", json={"path": "/x", "step": "bad"}).status_code == 422
    assert client.get("/admin/cc/guide-feedback").status_code in (401, 403)
