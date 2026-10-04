"""Auto-DM triggers on the existing auto-response rules: trigger type,
targets, trigger words, schedule, limits, channels (external never live)."""
import uuid
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.services import auto_response as ar


def test_applies_checks_trigger_target_words_schedule():
    rule = {"trigger_type": "video", "targets": ["vid1"], "trigger_words": ["price"],
            "start_at": "2026-01-01", "end_at": "2026-12-31", "channels": ["askodox_chat", "instagram"]}
    at = datetime(2026, 6, 1, tzinfo=timezone.utc)
    assert ar.applies(rule, trigger="video", target="vid1", message="what is the price?", at=at) is None
    assert ar.applies(rule, trigger="product", target="vid1", message="price", at=at) == "trigger is video"
    assert ar.applies(rule, trigger="video", target="vid2", message="price", at=at) == "different item"
    assert "trigger words" in ar.applies(rule, trigger="video", target="vid1", message="hello", at=at)
    assert ar.applies(rule, trigger="video", target="vid1", message="price",
                      at=datetime(2027, 1, 2, tzinfo=timezone.utc)) == "ended"
    assert ar.channel_status(rule) == {"askodox_chat": "LIVE", "instagram": "EXTERNAL_SETUP_REQUIRED"}
    assert ar.within_limits({"daily_limit": 2}, sent_today=2, sent_to_customer_today=0) == "daily limit reached"
    assert ar.within_limits({"per_customer_daily_limit": 1}, sent_today=0, sent_to_customer_today=1)


def test_content_trigger_answers_then_hits_customer_limit():
    from app.api.routes.platform import platform
    from server import app, container

    client = TestClient(app)
    pf = platform(container)
    biz = "app-biz-" + uuid.uuid4().hex[:6]
    rec = pf.resources.create("auto_response_rules", {
        "name": "video price", "business_ref": biz, "faq": {"delivery": "2 days in Vijayawada"},
        "trigger_type": "video", "targets": ["v-1"], "trigger_words": ["price", "link"],
        "reply_text": "It is ₹499 -- call 9876543210 for details", "channels": ["askodox_chat", "whatsapp"],
        "per_customer_daily_limit": 1}, actor="test", owner_ref=biz)
    pf.resources.action("auto_response_rules", rec["id"], "enable", actor="test", owner_ref=biz)
    try:
        body = {"business_ref": biz, "trigger_type": "video", "target": "v-1", "message": "price please"}
        r = client.post("/api/auto-response/ask", json=body).json()
        assert r["status"] == "answered" and r["source"] == "trigger_reply" and "9876543210" not in r["text"]
        assert r["channels"]["whatsapp"] == "EXTERNAL_SETUP_REQUIRED"
        assert client.post("/api/auto-response/ask", json=body).json()["status"] == "limited"
        other = dict(body, target="v-2")
        assert client.post("/api/auto-response/ask", json=other).json()["status"] == "no_rule"
    finally:
        pf.repo.delete(rec["id"], actor="test")


def test_deal_chat_uses_the_product_trigger_before_the_general_rule():
    from types import SimpleNamespace

    from app.api.routes.in_app_deal import _deal_triggers
    from app.services import auto_response

    class _Demands:
        def get(self, demand_id):
            return {"domain": "PRODUCT", "side": "NEED"} if demand_id == 7 else None

    container = SimpleNamespace(universal_demand_repository=_Demands())
    assert _deal_triggers(container, 7) == ["product", "catalog", "listing", "any_message"]
    assert _deal_triggers(container, 8) == ["any_message"]
    rules = [{"id": "r1", "status": "ACTIVE", "data": {"business_ref": "s1", "trigger_type": "any_message",
                                                       "faq": {"hours": "9 to 9"}}},
             {"id": "r2", "status": "ACTIVE", "data": {"business_ref": "s1", "trigger_type": "product",
                                                       "faq": {"stock": "In stock"}}},
             {"id": "r3", "status": "ACTIVE", "data": {"business_ref": "s1", "trigger_type": "video",
                                                       "faq": {"stock": "video only"}}}]
    picked = next(r for r in (auto_response.rule_for(rules, "s1", trigger=t, message="stock?")
                              for t in _deal_triggers(container, 7)) if r)
    assert picked["_id"] == "r2"
    general = next(r for r in (auto_response.rule_for(rules, "s1", trigger=t, message="hours?")
                               for t in _deal_triggers(container, 8)) if r)
    assert general["_id"] == "r1", "a video-only rule never answers a deal chat"
