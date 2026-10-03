"""Event Stream + AI Insights keep the specific detected category (never a
bare PRODUCT / SERVICES), insights are actionable, and the Revenue Command
Center reconciles sources without double counting."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import category_signal
from app.services import revenue_command as rc

OWNER_KEY = "owner-rev-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "r.db")),
                        raising=False)
    return TestClient(app), container


def test_category_signal_prefers_specific_over_domain():
    assert category_signal.detect(category="product", trace={"categories": ["Television"]},
                                  subject="samsung 43 inch tv")[0] == "Television"
    assert category_signal.detect(category="service", constraints={"service": "plumber"}, subject="fix tap")[0] == \
        "plumber"
    assert category_signal.detect(category="product", subject="chicken")[0] == "chicken"
    assert category_signal.for_demand({"domain": "PRODUCT", "subject": ""})[0] == "PRODUCT"  # last resort only
    cat, sub = category_signal.detect(constraints={"category_detected": "Mobile phones", "subcategory": "5G phones"})
    assert (cat, sub) == ("Mobile phones", "5G phones")


def test_discovery_events_carry_the_detected_category_not_product(env):
    client, container = env
    subject = "boat airdopes " + uuid.uuid4().hex[:5]
    r = client.post("/deals/discover", json={
        "user_id": "guest", "raw_text": f"I want {subject}", "intent": "buy", "subject": subject,
        "category": "product", "trace": {"categories": ["Wireless earbuds"], "language": "en"}})
    assert r.status_code == 200, r.text
    rows = client.get("/admin/cc/platform/events", headers=OWNER,
                      params={"event": "search", "q": subject}).json()["items"]
    assert rows, "the search was recorded"
    assert rows[0]["category"] == "Wireless earbuds" and rows[0]["domain"] == "PRODUCT"
    assert client.get("/admin/cc/platform/events", headers=OWNER,
                      params={"category": "wireless earbuds"}).json()["items"]


def test_insights_are_actionable_with_specific_categories(env):
    client, container = env
    from app.api.routes.platform import platform

    pf = platform(container)
    cat = "Tractor spares " + uuid.uuid4().hex[:4]
    for _ in range(3):
        pf.repo.record_event("search", category=cat)
        pf.repo.record_event("no_match", category=cat)
    items = client.get("/admin/cc/platform/insights", headers=OWNER).json()["items"]
    gap = next(i for i in items if i["kind"] == "supply_gap" and cat in i["observation"])
    for key in ("observation", "possible_reason", "recommended_action", "impact", "confidence", "evidence"):
        assert gap[key] not in (None, ""), key
    assert "PRODUCT" not in gap["observation"]


class _Partners:
    def __init__(self, conversions, entries):
        self._c, self._e = conversions, entries

    def partners(self):
        return [{"id": 1, "slug": "shopx"}]

    def conversions_between(self, start, end):
        return self._c

    def entries_between(self, start, end):
        return self._e


class _Ledger:
    def __init__(self, entries):
        self._e = entries

    def ledger(self, since=None, until=None):
        return self._e


def test_revenue_reconciles_without_double_counting():
    ledger = _Ledger([
        {"id": "led1", "kind": "affiliate_commission", "amount": 100, "state": "CONFIRMED", "conversion_id": "ORD-9",
         "campaign_id": None, "partner_id": "1", "source_ref": None, "occurred_at": "2026-09-29"},
        {"id": "led2", "kind": "campaign_revenue", "amount": 499, "state": "EXPECTED", "conversion_id": None,
         "campaign_id": "prm_1", "partner_id": None, "source_ref": None, "occurred_at": "2026-09-29"},
        {"id": "led3", "kind": "lead_fee", "amount": 50, "state": "REVERSED", "conversion_id": None,
         "campaign_id": None, "partner_id": None, "source_ref": None, "occurred_at": "2026-09-29"},
    ])
    partners = _Partners(
        [{"id": 1, "partner_id": 1, "external_id": "ORD-9", "commission": 100, "status": "CONFIRMED",
          "order_value": 2000, "occurred_at": "2026-09-29", "category": "Mobiles", "location": "Vijayawada"},
         {"id": 2, "partner_id": 1, "external_id": "ORD-10", "commission": 40, "status": "PAID",
          "order_value": 800, "occurred_at": "2026-09-29", "category": "Mobiles", "location": "Guntur"}],
        [{"id": 1, "source": "subscription", "amount": 299, "occurred_at": "2026-09-29", "reference": "SUB-1"}])
    out = rc.summary(ledger, partners, {"start": "2026-09-01", "end": "2026-10-01"}, reward_cost=20)
    t = out["totals"]
    assert t["confirmed"] == 100 + 299 and t["paid"] == 40  # ORD-9 counted once
    assert t["gross"] == 439 and t["expected"] == 499 and t["refund"] == 50
    assert t["net"] == 439 - 50 - 20
    assert out["duplicates_skipped"] == [{"conversion": "ORD-9", "kept": "platform_ledger"}]
    assert out["by_source"]["paid_notifications"]["expected"] == 499
    assert out["by_source"]["subscriptions"]["confirmed"] == 299
    assert {b["key"] for b in out["breakdowns"]["location"]} == {"Guntur"}


def test_revenue_command_route_and_permissions(env):
    client, _ = env
    r = client.get("/admin/cc/platform/revenue-command", headers=OWNER, params={"period": "7d"})
    assert r.status_code == 200 and "totals" in r.json() and "reconciliation" in r.json()
    assert client.get("/admin/cc/platform/revenue-command", headers=OWNER,
                      params={"period": "custom", "start": "2026-09-10", "end": "2026-09-01"}).status_code == 422
    staff = client.post("/admin/cc/staff", headers=OWNER, json={"name": "s", "role": "support_agent"}).json()
    assert client.get("/admin/cc/platform/revenue-command",
                      headers={"X-ASKODOX-Staff-Token": staff["token"]}).status_code == 403
