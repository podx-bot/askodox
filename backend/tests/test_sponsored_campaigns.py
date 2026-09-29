"""Sponsored listings: admin module, approval rules, targeted serving (never
random), separate from organic ranking, tracked clicks and analytics.

Advertisers here are test fixtures, not real companies.
"""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.sponsored_repository import SponsoredError, SponsoredRepository
from app.services import external_call_budget, rate_limit

OWNER_KEY = "owner-sp-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture(autouse=True)
def _fresh():
    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    monkeypatch.setattr(container, "sponsored_repository", SponsoredRepository(str(tmp_path / "sp.db")),
                        raising=False)
    return TestClient(app, follow_redirects=False), container


def tv_request():
    return {"user_id": "", "raw_text": "43 inch TV", "intent": "buy", "subject": "43 inch TV", "category": "product",
            "quantity": None, "unit": None, "price": None,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
            "dynamic_fields": {}, "trace": {"language": "en"}}


def campaign(client, **extra):
    advertiser = client.post("/admin/cc/sponsored/advertisers", headers=OWNER,
                             json={"name": "Example Electronics", "kind": "brand"}).json()
    body = {"advertiser_id": advertiser["id"], "name": "TV launch", "kind": "sponsored_listing",
            "title": "Example 43 inch TV", "destination_url": "https://tv.example/43", "keywords": ["tv"],
            "budget": 100, "cost_per_click": 10, **extra}
    response = client.post("/admin/cc/sponsored/campaigns", headers=OWNER, json=body)
    assert response.status_code == 200, response.text
    return response.json()


def test_admin_module_is_empty_by_default_and_needs_permission(api):
    client, _ = api
    assert client.get("/admin/cc/sponsored").status_code in (401, 403)
    data = client.get("/admin/cc/sponsored", headers=OWNER).json()
    assert data["advertisers"] == [] and data["campaigns"] == [], "nothing is pre-filled"
    assert "influencer_video" in data["campaign_kinds"] and data["labels"] == ["Sponsored", "Promoted"]
    found = client.post("/deals/discover", json=tv_request()).json()["matches"]
    assert not [m for m in found if m.get("sponsored")], "no campaign -> no sponsored result"


def test_draft_is_not_served_and_approval_needs_a_target_and_https(api):
    client, _ = api
    draft = campaign(client, keywords=[])
    refused = client.post(f"/admin/cc/sponsored/campaigns/{draft['id']}/status", headers=OWNER,
                          json={"status": "APPROVED"})
    assert refused.status_code == 400 and "no untargeted ads" in refused.json()["detail"]
    bad_url = client.post("/admin/cc/sponsored/campaigns", headers=OWNER,
                          json={"name": "x", "kind": "deal", "title": "x", "destination_url": "http://a.example"})
    assert bad_url.status_code == 400
    targeted = campaign(client)
    found = client.post("/deals/discover", json=tv_request()).json()["matches"]
    assert not [m for m in found if m.get("sponsored")], "a DRAFT is never served"
    ok = client.post(f"/admin/cc/sponsored/campaigns/{targeted['id']}/status", headers=OWNER,
                     json={"status": "APPROVED"})
    assert ok.status_code == 200 and ok.json()["status"] == "APPROVED"


def test_approved_campaign_is_labelled_after_organic_and_only_when_relevant(api):
    client, _ = api
    tv = campaign(client)
    client.post(f"/admin/cc/sponsored/campaigns/{tv['id']}/status", headers=OWNER, json={"status": "APPROVED"})
    found = client.post("/deals/discover", json=tv_request()).json()["matches"]
    sponsored = [m for m in found if m.get("sponsored")]
    assert len(sponsored) == 1
    row = sponsored[0]
    assert row["sponsored_label"] == "Sponsored" and row["segment"] == "sponsored"
    assert "paid placement" in row["disclosure"]
    assert found.index(row) == len(found) - 1 or all(m.get("sponsored") for m in found[found.index(row):]), \
        "sponsored rows come after every organic row"
    assert row["redirect_path"].startswith("/go/sp/")

    unrelated = dict(tv_request(), raw_text="plumber", subject="plumber", category="service")
    rows = client.post("/deals/discover", json=unrelated).json()["matches"]
    assert not [m for m in rows if m.get("sponsored")], "a TV ad never shows for a plumber"


def test_location_dates_budget_pause_and_edit_reapproval(api):
    client, container = api
    repo = container.sponsored_repository
    elsewhere = campaign(client, locations=["hyderabad"])
    repo.set_status(elsewhere["id"], "APPROVED")
    assert repo.eligible(category="product", subject="43 inch tv", location="Vijayawada") == []
    assert repo.eligible(category="product", subject="43 inch tv", location="Hyderabad, Telangana")

    future = campaign(client, starts_at=(datetime.now(timezone.utc) + timedelta(days=3)).date().isoformat())
    repo.set_status(future["id"], "APPROVED")
    assert all(c["id"] != future["id"] for c in repo.eligible(subject="tv", location="Hyderabad"))

    capped = campaign(client, budget=10, cost_per_click=10)
    repo.set_status(capped["id"], "APPROVED")
    click = repo.record_impression(capped["id"])
    assert repo.open_click(click) == "https://tv.example/43"
    assert repo.open_click(click) == "https://tv.example/43"
    stats = repo.campaign_stats()[capped["id"]]
    assert stats["clicks"] == 1 and stats["spend"] == 10.0, "a click is counted once"
    assert all(c["id"] != capped["id"] for c in repo.eligible(subject="tv", location="Hyderabad")), "budget spent"

    paused = repo.set_status(elsewhere["id"], "PAUSED")
    assert paused["status"] == "PAUSED" and repo.eligible(subject="tv", location="Hyderabad") == []
    repo.set_status(elsewhere["id"], "APPROVED")
    edited = repo.save_campaign({"title": "Changed title"}, elsewhere["id"])
    assert edited["status"] == "DRAFT", "changing what is shown needs a new approval"
    renamed = repo.save_campaign({"notes": "internal"}, future["id"])
    assert renamed["status"] == "APPROVED", "internal notes do not"


def test_redirect_is_tracked_and_never_open(api):
    client, container = api
    tv = campaign(client)
    client.post(f"/admin/cc/sponsored/campaigns/{tv['id']}/status", headers=OWNER, json={"status": "APPROVED"})
    row = next(m for m in client.post("/deals/discover", json=tv_request()).json()["matches"] if m.get("sponsored"))
    opened = client.get(row["redirect_path"])
    assert opened.status_code == 302 and opened.headers["location"] == "https://tv.example/43"
    assert client.get("/go/sp/not-a-real-click").status_code == 404


def test_conversions_and_organic_vs_sponsored_analytics(api):
    client, container = api
    tv = campaign(client)
    client.post(f"/admin/cc/sponsored/campaigns/{tv['id']}/status", headers=OWNER, json={"status": "APPROVED"})
    client.post("/deals/discover", json=tv_request())
    recorded = client.post(f"/admin/cc/sponsored/campaigns/{tv['id']}/conversions", headers=OWNER,
                           json={"amount": 25000, "note": "advertiser report"})
    assert recorded.status_code == 200 and recorded.json()["conversions"] == 1
    with pytest.raises(SponsoredError):
        container.sponsored_repository.record_conversion(tv["id"], amount=-1)
    data = client.get("/admin/cc/sponsored/analytics?days=30", headers=OWNER).json()
    assert data["totals"]["impressions"] == 1 and data["totals"]["conversions"] == 1
    split = data["organic_vs_sponsored"]
    assert split["searches"] == 1 and split["sponsored_results"] == 1
    assert split["organic_results"] >= 0 and split["sponsored_share_percent"] is not None


def test_seller_listing_supply_sees_no_ads(api):
    client, container = api
    from app.api.routes.sponsored import sponsored_results

    tv = campaign(client)
    container.sponsored_repository.set_status(tv["id"], "APPROVED")
    assert sponsored_results(container, {"side": "OFFER", "subject": "tv", "domain": "product"}) == []
    assert len(sponsored_results(container, {"side": "NEED", "subject": "tv", "domain": "product"})) == 1


def test_admin_page_has_the_sponsored_tab(api):
    client, _ = api
    from app.api.routes.admin_web import PAGE

    assert '["Sponsored","sponsored"]' in PAGE and "async function sponsoredTab()" in PAGE
