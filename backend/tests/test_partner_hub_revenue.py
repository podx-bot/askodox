"""Affiliate / Partner Hub, affiliate tracking funnel and the Revenue Center.

Partners here are test fixtures ("Example Mart"), not real companies.
"""
import dataclasses
import json
import uuid
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.partner_revenue_repository import PartnerRevenueRepository
from app.services import affiliate_partner_service as svc
from app.services import external_call_budget, rate_limit
from app.services.revenue_center_service import RevenueCenter, period_bounds

OWNER_KEY = "owner-ph-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
MART = {
    "name": "Example Mart", "categories": ["electronics", "tv"], "countries": ["IN"],
    "signup_url": "https://mart.example/affiliates", "tracking_id": "askodox-21",
    "deep_link_template": "https://mart.example/s?k={query}&tag={tracking_id}", "sub_id_param": "subid",
    "campaign_params": {"utm_source": "askodox"}, "commission": {"percent": 4}, "active": True,
}


@pytest.fixture(autouse=True)
def _fresh():
    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                                                   public_base_url="https://api.askodox.test"))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    monkeypatch.setattr(container, "partner_revenue_repository",
                        PartnerRevenueRepository(str(tmp_path / "partners.db")), raising=False)
    return TestClient(app, follow_redirects=False), container


def tv_request():
    return {"user_id": "", "raw_text": "43 inch TV", "intent": "buy", "subject": "43 inch TV", "category": "product",
            "quantity": None, "unit": None, "price": None,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
            "dynamic_fields": {}, "trace": {"language": "te"}}


def create(client, **extra):
    response = client.post("/admin/cc/partners", headers=OWNER, json={**MART, **extra})
    assert response.status_code == 200, response.text
    return response.json()


# ------------------------------------------------------------ S7 hub --

def test_partner_hub_crud_capabilities_and_secrets_never_leave_the_backend(api):
    client, container = api
    assert client.get("/admin/cc/partners").status_code == 401, "admin only"
    partner = create(client)
    assert partner["slug"] == "example-mart" and partner["active"] is True
    assert partner["capabilities"]["highest_level"] == 1
    assert "orders" not in partner["capabilities"]["measurable"], "a link alone never measures orders"
    secret = "sk-live-" + uuid.uuid4().hex
    assert client.put(f"/admin/cc/partners/{partner['id']}/secrets/api_key", headers=OWNER,
                      json={"value": secret}).status_code == 200
    token = client.post(f"/admin/cc/partners/{partner['id']}/postback-token", headers=OWNER).json()
    assert "/api/partners/example-mart/postback?token=" in token["postback_url"]
    listed = client.get("/admin/cc/partners", headers=OWNER).text
    assert secret not in listed and token["postback_url"].split("token=")[1].split("&")[0] not in listed
    assert '"set":true' in listed.replace(" ", "")
    again = client.get("/admin/cc/partners", headers=OWNER).json()["items"][0]
    assert again["capabilities"]["level3_postback"] and "orders" in again["capabilities"]["measurable"]
    # Disable / edit.
    edited = client.patch(f"/admin/cc/partners/{partner['id']}", headers=OWNER, json={"active": False}).json()
    assert edited["active"] is False
    assert client.patch(f"/admin/cc/partners/{partner['id']}", headers=OWNER,
                        json={"deep_link_template": "http://insecure.example/{query}"}).status_code == 422
    guide = client.get("/admin/cc/partners/guide", headers=OWNER).json()
    assert [lvl["level"] for lvl in guide["levels"]] == [1, 2, 3, 4]
    assert any(f["field"] == "tracking_id" for f in guide["fields"])


def test_integration_test_reports_what_is_missing_and_what_works(api):
    client, _ = api
    partner = create(client, deep_link_template="", base_url="", sub_id_param="")
    report = client.post(f"/admin/cc/partners/{partner['id']}/test", headers=OWNER).json()
    assert report["ok"] is False
    assert {m["field"] for m in report["missing"]} >= {"deep_link_template", "sub_id_param"}
    fixed = client.patch(f"/admin/cc/partners/{partner['id']}", headers=OWNER,
                         json={"deep_link_template": MART["deep_link_template"], "sub_id_param": "subid"}).json()
    report = client.post(f"/admin/cc/partners/{fixed['id']}/test", headers=OWNER).json()
    assert report["ok"] is True
    link = next(c for c in report["checks"] if c["check"] == "tracked link")["value"]
    assert link.startswith("https://mart.example/s?k=test") and "tag=askodox-21" in link and "subid=ckTEST" in link
    stored = client.get("/admin/cc/partners", headers=OWNER).json()["items"][0]
    assert stored["last_check_ok"] is True and stored["last_check_at"]


def test_build_link_placeholders_and_https_only():
    partner = {**MART, "campaign_params": {"campaign": "diwali", "utm_campaign": "{campaign}"}}
    url = svc.build_link(partner, query="43 inch tv", click_id="ck123")
    assert url == "https://mart.example/s?k=43+inch+tv&tag=askodox-21&subid=ck123&utm_campaign=diwali"
    assert svc.build_link({"base_url": "http://x.example/{query}"}, query="tv") is None
    product = svc.build_link({"deep_link_template": "https://go.example/r?u={url}&t={tracking_id}",
                              "tracking_id": "t1"}, query="tv", target_url="https://shop.example/p/1")
    assert product == "https://go.example/r?u=https%3A%2F%2Fshop.example%2Fp%2F1&t=t1"


def test_generic_feed_adapter_level2_uses_backend_key_and_real_fields(tmp_path):
    repo = PartnerRevenueRepository(str(tmp_path / "p.db"))
    partner = repo.create_partner({**MART, "feed": {"url": "https://feed.mart.example/search?q={query}",
                                                    "items_path": "data.items", "title": "name", "item_url": "link",
                                                    "price": "price", "auth": "header:X-Api-Key"}})
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["key"] = request.headers.get("X-Api-Key")
        return httpx.Response(200, json={"data": {"items": [
            {"name": "Mart 43 inch TV", "link": "https://mart.example/p/43", "price": "27990"},
            {"name": "no link"},
        ]}})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    with pytest.raises(svc.PartnerFeedError):
        svc.fetch_feed(repo, repo.get_partner(partner["id"]), "tv", client=client)  # no key yet
    repo.set_secret(partner["id"], "api_key", "feed-secret-123")
    partner = repo.get_partner(partner["id"])
    rows, errors = svc.partner_results(repo, {"domain": "PRODUCT", "subject": "43 inch TV"}, feed_client=client)
    assert errors == [] and seen["key"] == "feed-secret-123"
    assert len(rows) == 1 and rows[0]["title"] == "Mart 43 inch TV" and rows[0]["price"] == 27990.0
    assert rows[0]["price_verified"] is True and "feed-secret" not in json.dumps(rows)
    assert "subid=" in rows[0]["destination_url"] and rows[0]["segment"] == "partner" and rows[0]["affiliate"]


# ---------------------------------------------- S8 pipeline + tracking --

def test_partner_rows_join_the_universal_pipeline_after_local_and_are_tracked(api):
    client, container = api
    create(client)
    create(client, name="Travel Partner", categories=["hotel"], deep_link_template="https://trip.example/{query}")
    found = client.post("/deals/discover", json=tv_request())
    assert found.status_code == 200, found.text
    matches = found.json()["matches"]
    partner_rows = [m for m in matches if m.get("segment") == "partner"]
    assert len(partner_rows) == 1, "only partners for this category"
    row = partner_rows[0]
    assert row["source_name"] == "Example Mart" and row["affiliate"] and "commission" in row["disclosure"]
    assert row["price"] is None and row["price_verified"] is False, "a link-only partner invents no price"
    assert matches.index(row) == len(matches) - 1 or all(
        m.get("segment") == "partner" for m in matches[matches.index(row):]), "local-first ordering"
    click_id = row["click_id"]
    assert row["redirect_path"] == f"/go/{click_id}" and f"subid={click_id}" in row["destination_url"]

    assert client.post("/api/partners/event", json={"click_id": click_id, "event": "click"}).status_code == 200
    assert client.post("/api/partners/event", json={"click_id": "ckunknown00", "event": "click"}).status_code == 404
    opened = client.get(f"/go/{click_id}")
    assert opened.status_code == 302 and opened.headers["location"] == row["destination_url"]
    assert client.get("/go/ck-not-issued").status_code == 404, "no open redirect"

    repo = container.partner_revenue_repository
    now = datetime.now(timezone.utc)
    events = repo.events_between((now - timedelta(hours=1)).isoformat(), (now + timedelta(hours=1)).isoformat())
    kinds = [e["event"] for e in events]
    assert kinds.count("search") == 1 and "impression" in kinds and "click" in kinds and "partner_opened" in kinds
    impression = next(e for e in events if e["event"] == "impression")
    assert impression["language"] == "te" and impression["location"] == "Vijayawada"


def test_postback_is_token_verified_and_maps_the_click_back_to_the_search(api):
    client, container = api
    partner = create(client)
    row = next(m for m in client.post("/deals/discover", json=tv_request()).json()["matches"]
               if m.get("segment") == "partner")
    url = client.post(f"/admin/cc/partners/{partner['id']}/postback-token", headers=OWNER).json()["postback_url"]
    token = url.split("token=")[1].split("&")[0]
    base = "/api/partners/example-mart/postback"
    assert client.get(base, params={"token": "wrong", "order_id": "A1"}).status_code == 403
    lead = client.get(base, params={"token": token, "event": "lead", "click_id": row["click_id"]}).json()
    assert lead == {"recorded": "lead", "matched_click": True}
    order = client.post(base, json={"token": token, "click_id": row["click_id"], "order_id": "A1",
                                    "order_value": "30000", "status": "pending"}).json()
    assert order["status"] == "PENDING" and order["matched_click"] is True
    stored = container.partner_revenue_repository.conversions_between("2000", "2100")[0]
    assert stored["commission"] == 1200.0 and stored["commission_source"] == "rule", "rule-based = expected only"
    assert stored["category"] == "PRODUCT" and "token" not in stored["raw"]
    # The partner later approves with its own commission figure.
    client.get(base, params={"token": token, "order_id": "A1", "status": "approved", "commission": "1100"})
    stored = container.partner_revenue_repository.conversions_between("2000", "2100")[0]
    assert stored["status"] == "CONFIRMED" and stored["commission"] == 1100.0
    assert stored["commission_source"] == "partner"


def test_report_import_and_manual_reconciliation(api):
    client, container = api
    partner = create(client)
    csv_text = "Order_ID,Sub_ID,Order_Value,Commission,Status,Date\nB1,,1000,40,approved,2026-09-20\n" \
               "B2,,500,,pending,2026-09-21\nB3,,x,,paid,2026-09-21\n"
    result = client.post(f"/admin/cc/partners/{partner['id']}/import", headers=OWNER, json={"csv": csv_text}).json()
    assert result["imported"] == 2 and result["errors"][0]["line"] == 4
    rows = {c["external_id"]: c for c in container.partner_revenue_repository.conversions_between("2000", "2100")}
    assert rows["B1"]["status"] == "CONFIRMED" and rows["B2"]["commission"] == 20.0
    changed = client.patch(f"/admin/cc/partners/conversions/{rows['B1']['id']}", headers=OWNER,
                           json={"status": "REVERSED"}).json()
    assert changed["status"] == "REVERSED"
    assert client.patch(f"/admin/cc/partners/conversions/{rows['B1']['id']}", headers=OWNER,
                        json={"status": "maybe"}).status_code == 422


# ----------------------------------------- S9-S11 revenue + why ------

def _seed(repo, partner_id, day: datetime, *, searches, impressions, clicks, orders, commission, status="CONFIRMED",
          category="PRODUCT"):
    ts = day.isoformat()
    for _ in range(searches):
        repo.record_event("search", category=category, location="Vijayawada", occurred_at=ts)
    for n in range(impressions):
        repo.record_event("impression", partner_id=partner_id, click_id=f"ck{day:%d}{n}", category=category,
                          occurred_at=ts)
    for n in range(clicks):
        repo.record_event("click", partner_id=partner_id, click_id=f"ck{day:%d}{n}", category=category,
                          occurred_at=ts)
    for n in range(orders):
        repo.upsert_conversion(partner_id=partner_id, external_id=f"o{day:%m%d}{n}", source="postback", status=status,
                               order_value=1000, commission=commission, category=category, occurred_at=ts)


def test_revenue_center_aggregates_all_sources_with_period_filters(api):
    client, container = api
    repo = container.partner_revenue_repository
    partner = create(client)
    now = datetime.now(timezone.utc)
    _seed(repo, partner["id"], now - timedelta(hours=1), searches=30, impressions=30, clicks=6, orders=2,
          commission=40)
    repo.upsert_conversion(partner_id=partner["id"], external_id="pend", source="postback", status="PENDING",
                           order_value=500, commission=20, occurred_at=(now - timedelta(hours=1)).isoformat())
    repo.upsert_conversion(partner_id=partner["id"], external_id="rev", source="postback", status="REVERSED",
                           order_value=500, commission=20, occurred_at=(now - timedelta(hours=1)).isoformat())
    entry = client.post("/admin/cc/revenue/entries", headers=OWNER,
                        json={"source": "subscription", "amount": 499, "reference": "UPI-1"}).json()
    assert entry["source"] == "subscription"
    assert client.post("/admin/cc/revenue/entries", headers=OWNER,
                       json={"source": "made_up", "amount": 1}).status_code == 422
    summary = client.get("/admin/cc/revenue", headers=OWNER, params={"period": "7d"}).json()
    m = summary["metrics"]
    assert m["searches"] == 31 or m["searches"] == 30
    assert m["clicks"] == 6 and m["ctr_pct"] == 20.0 and m["orders"] == 4
    assert m["confirmed_commission"] == 80.0 and m["pending_commission"] == 20.0 and m["reversed_commission"] == 20.0
    assert m["total_revenue"] == 80.0 + 499, "revenue = confirmed + paid + recorded entries; never pending/reversed"
    assert {r["key"] for r in summary["breakdowns"]["source"]} == {"affiliate_commission", "subscription"}
    assert summary["funnel"][0]["stage"] == "Searches" and len(summary["series"]) == 7
    assert summary["subscriptions"]["available"] is True and "not revenue" in summary["subscriptions"]["note"]
    filtered = client.get("/admin/cc/revenue", headers=OWNER, params={"period": "7d", "partner": "nobody"}).json()
    assert filtered["metrics"]["orders"] == 0
    assert client.get("/admin/cc/revenue", headers=OWNER, params={"period": "custom", "start": "2026-09-10"}
                      ).status_code == 422
    csv_text = client.get("/admin/cc/revenue/export.csv", headers=OWNER,
                          params={"kind": "conversions", "period": "30d"}).text
    assert csv_text.splitlines()[0].startswith("id,partner_id,external_id") and "pend" in csv_text
    records = client.get("/admin/cc/revenue/records", headers=OWNER, params={"kind": "conversions"}).json()
    assert len(records["items"]) == 4


def test_period_bounds_are_in_the_owner_time_zone():
    now = datetime(2026, 9, 28, 20, 0, tzinfo=timezone.utc)  # 01:30 on 29 Sep in India
    today = period_bounds("today", now=now)
    assert today["first_day"] == "2026-09-29" and today["start"] == "2026-09-28T18:30:00+00:00"
    month = period_bounds("month", now=now)
    assert month["first_day"] == "2026-09-01" and month["days"] == 29
    assert month["previous"]["first_day"] == "2026-08-03"


def test_why_down_separates_confirmed_data_from_correlation_and_never_invents(tmp_path):
    repo = PartnerRevenueRepository(str(tmp_path / "why.db"))
    mart = repo.create_partner({**MART})
    trip = repo.create_partner({**MART, "name": "Trip Partner", "categories": ["hotel"]})
    now = datetime.now(timezone.utc)
    previous_day, current_day = now - timedelta(days=8), now - timedelta(days=1)
    _seed(repo, mart["id"], previous_day, searches=100, impressions=100, clicks=20, orders=10, commission=50)
    _seed(repo, trip["id"], previous_day, searches=0, impressions=40, clicks=8, orders=4, commission=100,
          category="HOTEL")
    _seed(repo, mart["id"], current_day, searches=60, impressions=60, clicks=12, orders=6, commission=50)
    repo.update_partner(trip["id"], {"active": False})
    center = RevenueCenter(repo)
    why = center.explain(period_bounds("7d"))
    assert why["direction"] == "down" and why["revenue_delta"] == -(500 + 400 - 300)
    levels = {f["level"] for f in why["findings"]}
    assert "CONFIRMED" in levels and "POSSIBLE_CORRELATION" in levels
    text = " ".join(f["statement"] for f in why["findings"])
    assert "Partner 'Trip Partner' is disabled" in text
    assert "Searches went down 40%" in text
    correlation = next(f for f in why["findings"] if f["level"] == "POSSIBLE_CORRELATION")
    assert "does not prove" in correlation["statement"] and correlation["data"]
    assert all(f["data"] for f in why["findings"]), "every statement shows its data"
    assert why["findings"][0]["level"] == "CONFIRMED", "confirmed first"


def test_why_with_too_little_data_says_so(tmp_path):
    repo = PartnerRevenueRepository(str(tmp_path / "empty.db"))
    why = RevenueCenter(repo).explain(period_bounds("7d"))
    assert [f["level"] for f in why["findings"]] == ["INSUFFICIENT_EVIDENCE"]


def test_admin_web_has_partner_hub_and_revenue_center_tabs(api):
    client, _ = api
    page = client.get("/admin").text
    assert "Partner Hub" in page and "Revenue Center" in page and "Why up / down" in page
