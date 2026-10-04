"""Universal Sources, Staff Workspace (phone sign-in, paste-link entry, review,
duplicates, tasks, permissions) and Early Access / feedback. Every URL, id
and number here is a test fixture; no network is used."""
import dataclasses
import json
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import affiliate_catalog as ac
from app.services import platform_settings, rate_limit, staff_sessions
from app.services.phase_6_9_assistant_service import AffiliateProviderConfig
from app.services.session_tokens import issue_token
from app.services.universal_sources import UniversalSources, applies, normalize

OWNER_KEY = "owner-ws-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
PAGE_HTML = """<html><head><meta property="og:title" content="Walking Shoes for Men">
<meta property="og:image" content="https://img.example/shoe.jpg">
<script type="application/ld+json">{"@type":"Product","name":"Walking Shoes for Men","brand":{"name":"Stride"},
"offers":{"price":"1499","priceCurrency":"INR","availability":"https://schema.org/InStock"}}</script></head></html>"""


class _DownBrave:
    """Web search is out of credit (production 2026-10-04): every call fails."""
    configured = True
    last_error = True

    def __call__(self, query, limit):
        self.last_error = True
        return []


class _Fetch:
    def __init__(self):
        self.answers, self.calls = {}, []

    def __call__(self, url, timeout=5.0, max_bytes=0):
        self.calls.append(url)
        for fragment, answer in self.answers.items():
            if fragment in url:
                if isinstance(answer, Exception):
                    raise answer
                return answer
        raise ValueError("no route")


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    db = str(tmp_path / "ws.db")
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY, database_path=db,
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    monkeypatch.setattr(container, "universal_sources", None, raising=False)
    monkeypatch.setattr(container, "affiliate_catalog", ac.AffiliateCatalog(db), raising=False)
    monkeypatch.setattr(container, "affiliate_provider_config", AffiliateProviderConfig(db_path=db), raising=False)
    monkeypatch.setattr(container, "brave_web_search_provider", _DownBrave())
    monkeypatch.setattr(container, "affiliate_page_fetch", lambda url: PAGE_HTML, raising=False)
    fetch = _Fetch()
    monkeypatch.setattr(container, "sources_fetch", fetch, raising=False)
    from app.api.routes import staff_workspace

    monkeypatch.setattr(staff_workspace, "_upload_dir", lambda request: str(tmp_path / "uploads"))
    yield TestClient(app), container, fetch
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None
    container.universal_sources = None
    platform_settings.invalidate()


def _pf(container):
    from app.api.routes.platform import platform

    return platform(container)


def _source(container, **data):
    pf = _pf(container)
    rec = pf.resources.create("sources", {"name": "Shoe Mart", "domains": ["shoemart.example"],
                                          "source_type": "merchant", "connector": "json_search",
                                          "priority": 10, **data}, actor="t")
    pf.resources.action("sources", rec["id"], "enable", actor="t")
    return rec


def _discover(client, subject="walking shoes", category="fashion"):
    body = {"user_id": "", "raw_text": f"{subject} show me", "intent": "buy", "subject": subject,
            "category": category, "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6},
            "dynamic_fields": {}}
    r = client.post("/deals/discover", json=body)
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------- sources ---------

def test_json_search_source_gives_real_rows_while_brave_is_down_and_a_failing_source_is_isolated(api):
    client, container, fetch = api
    good = _source(container, search_url_template="https://api.shoemart.example/search?q={q}&city={city}",
                   field_map={"items": "results"}, sectors=["fashion", "shoes"])
    bad = _source(container, name="Broken Source", domains=["broken.example"],
                  search_url_template="https://api.broken.example/s?q={q}")
    fetch.answers["shoemart"] = (200, "application/json", json.dumps({"results": [
        {"name": "Walking Shoes Pro", "url": "https://shoemart.example/p/1", "price": "1,299", "mrp": 1999,
         "image": "https://img.example/1.jpg", "availability": "in stock", "rating": 4.3},
        {"name": "Walking Shoes Old", "url": "https://shoemart.example/p/2", "price": 999,
         "availability": "out of stock"},
        {"name": "No link item", "price": 5}]}))
    fetch.answers["broken"] = TimeoutError("timed out")
    data = _discover(client)
    rows = [m for m in data["matches"] if m.get("origin") == "universal_source"]
    assert [r["title"] for r in rows] == ["Walking Shoes Pro"], "out-of-stock and link-less items never shown"
    row = rows[0]
    assert row["price"] == 1299 and row["original_price"] == 1999 and row["discount_percent"] == 35
    assert row["price_verified"] is False and row["affiliate"] is False and row["source_name"] == "Shoe Mart"
    call = next(c for c in fetch.calls if "shoemart" in c)
    assert "q=walking%20shoes" in call and "city=Vijayawada" in call
    health = UniversalSources(_pf(container)).health.all()
    assert health[good["id"]]["last_status"] == "ok"
    assert health[bad["id"]]["last_status"] == "error" and "TimeoutError" in health[bad["id"]]["last_error"]


def test_affiliate_deep_link_only_when_commission_is_active():
    src = {"id": "s1", "name": "X", "monetization": "affiliate", "commission_status": "UNKNOWN",
           "affiliate_link_template": "https://aff.example/r?u={url}"}
    raw = {"title": "Kettle", "url": "https://x.example/kettle"}
    assert normalize(src, raw, 0)["destination_url"] == "https://x.example/kettle"
    row = normalize({**src, "commission_status": "ACTIVE"}, raw, 0)
    assert row["affiliate"] and row["destination_url"].startswith("https://aff.example/r?u=https%3A%2F%2F")
    assert normalize(src, {"title": "x", "url": "http://insecure.example"}, 0) is None


def test_source_sector_and_coverage_matching():
    src = {"sectors": ["travel"], "cities": ["Hyderabad"]}
    assert applies(src, {"subject": "bus ticket", "domain": "travel", "location_text": "Hyderabad"}) is None
    assert applies(src, {"subject": "shoes", "domain": "fashion", "location_text": "Hyderabad"}) == "sector"
    assert applies(src, {"subject": "bus", "domain": "travel", "location_text": "Vijayawada"}) == "coverage"


def test_feed_sync_needs_review_then_is_searchable_without_web_search(api):
    client, container, fetch = api
    src = _source(container, name="Kettle Feed", domains=["kettles.example"], connector="feed",
                  feed_url="https://kettles.example/feed.csv", feed_format="csv")
    fetch.answers["feed.csv"] = (200, "text/csv",
                                 "title,url,price,mrp,stock\nElectric Kettle 1.5L,https://kettles.example/k1,899,1299,"
                                 "in stock\n")
    engine = UniversalSources(_pf(container), container.affiliate_catalog, fetch=fetch)
    result = engine.sync_feed({**_pf(container).resources.get("sources", src["id"])["data"], "id": src["id"]},
                              actor="t")
    assert result == {"created": 1, "updated": 0, "skipped": 0, "review_status": "NEEDS_REVIEW"}
    assert not [m for m in _discover(client, "electric kettle", "home")["matches"]
                if m.get("origin") == "affiliate_catalog"], "unreviewed feed items are not public"
    item = container.affiliate_catalog.duplicates("https://kettles.example/k1")[0]
    container.affiliate_catalog.set_review(item["id"], "LIVE", actor="owner")
    rows = [m for m in _discover(client, "electric kettle", "home")["matches"] if m.get("origin") == "affiliate_catalog"]
    assert rows and rows[0]["price"] == 899 and rows[0]["original_price"] == 1299
    again = engine.sync_feed({**_pf(container).resources.get("sources", src["id"])["data"], "id": src["id"]}, actor="t")
    assert again["created"] == 0 and again["updated"] == 1, "a re-sync updates, never duplicates"


def test_product_health_policy_toggles(api):
    _, container, _ = api
    store = container.affiliate_catalog
    item = store.create({"title": "Mixer Grinder", "original_product_url": "https://www.amazon.in/dp/B0MIXER123",
                         "affiliate_url": "https://amzn.to/x"}, actor="t", stock_status="IN_STOCK",
                        commission_status="INACTIVE")
    assert store.get(item["id"])["eligibility"]["eligible"] and store.get(item["id"])["eligibility"]["routing"] == "organic"
    pf = _pf(container)
    for key, value in (("catalog.organic_when_commission_inactive", 0), ("catalog.pause_on_out_of_stock", 1)):
        pf.resources.create("platform_settings", {"key": key, "value": value}, actor="t")
    platform_settings.invalidate()
    assert "commission_inactive_hidden" in store.get(item["id"])["eligibility"]["reasons"]
    store.set_stock(item["id"], "OUT_OF_STOCK", actor="t")
    assert store.get(item["id"])["review_status"] == "PAUSED"
    store.set_stock(item["id"], "IN_STOCK", actor="t")
    assert store.get(item["id"])["review_status"] == "LIVE", "back in stock -> automatically live again"


# ----------------------------------------------------------- staff ---------

def _staff(client, role, phone=None):
    r = client.post("/admin/cc/staff", headers=OWNER, json={"name": f"{role} person", "role": role})
    assert r.status_code == 200, r.text
    staff = r.json()
    if phone:
        r = client.patch(f"/admin/cc/staff/{staff['id']}", headers=OWNER, json={"phone": phone})
        assert r.status_code == 200, r.text
    return staff


def _app_bearer(container, phone):
    return {"Authorization": "Bearer " + issue_token(f"app-phone-{phone}", container.settings.session_token_secret)}


def test_staff_sign_in_with_own_number_session_permissions_and_revocation(api):
    client, container, _ = api
    staff = _staff(client, "affiliate_product_staff", phone="919812345678")
    stranger = _app_bearer(container, "919800000001")
    assert client.get("/api/staff/me", headers=stranger).json() == {"staff": False}
    assert client.post("/api/staff/session", headers=stranger).status_code == 403
    # the app sends the number without the country code: same person
    mine = _app_bearer(container, "9812345678")
    assert client.get("/api/staff/me", headers=mine).json()["staff"] is True
    session = client.post("/api/staff/session", headers=mine).json()
    assert session["session"].startswith("sts.") and "workspace:approve" not in session["permissions"]
    h = {"X-ASKODOX-Staff-Session": session["session"]}
    me = client.get("/admin/cc/workspace/me", headers=h).json()
    assert me["item_types"] == ["product", "link", "service"] and me["can_publish"] is False
    assert me["sections"]["review"] is False and me["sections"]["support"] is False
    assert client.get("/admin/cc/escalations", headers=h).status_code == 403, "server-side, not just hidden"
    # handoff code: single use
    code = client.post("/api/staff/handoff", headers=mine).json()["code"]
    assert client.post("/api/staff/handoff/redeem", json={"code": code}).status_code == 200
    assert client.post("/api/staff/handoff/redeem", json={"code": code}).status_code == 401
    # deactivate -> the session stops working immediately
    client.patch(f"/admin/cc/staff/{staff['id']}", headers=OWNER, json={"active": False, "confirm": True})
    assert client.get("/admin/cc/workspace/me", headers=h).status_code == 401
    assert staff_sessions.verify("sts.1.1.bad", "x") is None
    # demo numbers can never be staff
    other = _staff(client, "qa_staff")
    from app.api.routes.onboarding_auth import _DEMO_MOBILE

    assert client.patch(f"/admin/cc/staff/{other['id']}", headers=OWNER,
                        json={"phone": _DEMO_MOBILE}).status_code == 422


def test_paste_link_autofill_duplicates_review_and_publish(api):
    client, container, _ = api
    _staff(client, "affiliate_product_staff", phone="919811111111")
    junior = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                     headers=_app_bearer(container, "919811111111")).json()["session"]}
    url = "https://www.amazon.in/Stride-Walking-Shoes/dp/B0WALK1234?tag=x&ref=abc"
    got = client.post("/admin/cc/workspace/import", headers=junior, json={"url": url}).json()
    assert got["source"]["name"] == "Amazon" and got["duplicates"] == []
    assert got["fields"]["title"] == "Walking Shoes for Men" and got["field_status"]["title"] == "fetched"
    assert client.post("/admin/cc/workspace/import", headers=junior,
                       json={"url": url, "item_type": "news"}).status_code == 403
    saved = client.post("/admin/cc/workspace/items", headers=junior, json={
        "item_type": "product", "fields": {**got["fields"], "original_product_url": url}}).json()
    assert saved["review_status"] == "NEEDS_REVIEW", "junior staff cannot publish directly"
    item_id = saved["item"]["id"]
    assert not [m for m in _discover(client)["matches"] if m.get("origin") == "affiliate_catalog"]
    # the same product from another share link is a duplicate
    dup = client.post("/admin/cc/workspace/import", headers=junior,
                      json={"url": "https://amazon.in/dp/B0WALK1234"}).json()
    assert dup["duplicates"][0]["id"] == item_id
    assert client.post("/admin/cc/workspace/items", headers=junior, json={
        "item_type": "product", "fields": {"title": "Copy", "original_product_url": "https://amazon.in/dp/B0WALK1234"}
    }).status_code == 409
    assert client.post(f"/admin/cc/workspace/items/{item_id}/review", headers=junior,
                       json={"action": "approve"}).status_code == 403
    # a supervisor approves -> live in discovery
    _staff(client, "supervisor", phone="919822222222")
    sup = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                  headers=_app_bearer(container, "919822222222")).json()["session"]}
    queue = client.get("/admin/cc/workspace/items?status=NEEDS_REVIEW", headers=sup).json()["items"]
    assert [i["id"] for i in queue] == [item_id]
    assert client.post(f"/admin/cc/workspace/items/{item_id}/review", headers=sup,
                       json={"action": "reject"}).status_code == 422, "a send-back needs a reason"
    assert client.post(f"/admin/cc/workspace/items/{item_id}/review", headers=sup,
                       json={"action": "approve"}).json()["item"]["review_status"] == "LIVE"
    rows = [m for m in _discover(client)["matches"] if m.get("origin") == "affiliate_catalog"]
    assert rows and rows[0]["title"] == "Walking Shoes for Men"
    history = ac.AffiliateCatalog(container.settings.database_path).history(item_id)
    assert {h["action"] for h in history} >= {"create", "review"}
    # bulk paste: detection + duplicates
    bulk = client.post("/admin/cc/workspace/import/bulk", headers=junior, json={
        "urls": [url, "https://www.flipkart.com/x/p/itm123?pid=MOBX", "ftp://nope"]}).json()["items"]
    assert bulk[0]["duplicates"] and bulk[1]["source"]["name"] == "Flipkart" and bulk[2]["ok"] is False


def test_photo_upload_only_real_images(api):
    client, container, _ = api
    _staff(client, "content_staff", phone="919833333333")
    h = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                headers=_app_bearer(container, "919833333333")).json()["session"]}
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 64
    up = client.post("/admin/cc/workspace/uploads", headers=h, files={"file": ("a.png", png, "image/png")}).json()
    assert up["url"].endswith(".png")
    assert client.get("/media/staff/" + up["name"]).content == png
    assert client.post("/admin/cc/workspace/uploads", headers=h,
                       files={"file": ("x.png", b"<script>", "image/png")}).status_code == 415
    assert client.get("/media/staff/../../etc/passwd").status_code == 404


def test_demand_task_dedupe_and_only_the_assignee_moves_it(api):
    client, container, _ = api
    _staff(client, "affiliate_product_staff", phone="919844444444")
    mine = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                   headers=_app_bearer(container, "919844444444")).json()["session"]}
    _staff(client, "content_staff", phone="919855555555")
    other = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                    headers=_app_bearer(container, "919855555555")).json()["session"]}
    body = {"title": "Find supply: walking shoes under 2000", "why": "42 searches in Vijayawada, no local seller",
            "assignee_role": "affiliate_staff", "dedupe_key": "demand:r1:walking-shoes", "priority": "HIGH"}
    first = client.post("/admin/cc/workspace/tasks/from-demand", headers=OWNER, json=body).json()
    again = client.post("/admin/cc/workspace/tasks/from-demand", headers=OWNER, json=body).json()
    assert first["created"] and not again["created"] and first["task"]["id"] == again["task"]["id"]
    tasks = client.get("/admin/cc/workspace/tasks", headers=mine).json()["items"]
    assert [t["id"] for t in tasks] == [first["task"]["id"]]
    assert client.get("/admin/cc/workspace/tasks", headers=other).json()["items"] == []
    assert client.post(f"/admin/cc/workspace/tasks/{first['task']['id']}/done", headers=other).status_code == 403
    assert client.post(f"/admin/cc/workspace/tasks/{first['task']['id']}/done",
                       headers=mine).json()["task"]["status"] == "DONE"


def test_staff_page_is_served_with_a_strict_policy(api):
    client, _, _ = api
    r = client.get("/staff")
    assert r.status_code == 200 and "Staff sign-in" in r.text
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert r.headers["cache-control"] == "no-store"


# ---------------------------------------------------- early access ---------

def test_early_access_programme_targeting_is_stable_and_configurable(api):
    client, container, _ = api
    assert client.get("/api/early-access?install_id=abc").json() == {"active": False}
    pf = _pf(container)
    rec = pf.resources.create("early_access", {"name": "Beta 1", "label": "Early Access", "eligible_percent": 50,
                                               "regions": ["Vijayawada"], "free_trial": True,
                                               "feedback_prompt": True, "include_users": ["app-phone-919899999999"]},
                              actor="t")
    pf.resources.action("early_access", rec["id"], "enable", actor="t")
    answers = {i: client.get(f"/api/early-access?install_id=dev-{i}&city=Vijayawada").json()["active"]
               for i in range(60)}
    assert 15 < sum(answers.values()) < 45, "about half the installs"
    assert all(client.get(f"/api/early-access?install_id=dev-{i}&city=Vijayawada").json()["active"] == v
               for i, v in list(answers.items())[:10]), "same answer every time"
    assert client.get("/api/early-access?install_id=dev-1&city=Delhi").json() == {"active": False}
    vip = client.get("/api/early-access?city=Delhi", headers=_app_bearer(container, "919899999999")).json()
    assert vip["active"] and vip["free_trial"] and vip["label"] == "Early Access"


def test_feedback_is_masked_diagnostics_need_consent_and_dashboard_needs_permission(api):
    client, container, _ = api
    r = client.post("/api/feedback", json={
        "kind": "wrong_result", "feature": "chat_results", "app_version": "1.0.1293",
        "message": "Showed shoes for TV. My otp is 482913, card 4111 1111 1111 1111, call 9876543210",
        "diagnostics": {"screen": "home", "error": "x"}, "consent_diagnostics": False})
    assert r.status_code == 200
    rec = _pf(container).resources.get("feedback_reports", r.json()["reference"])
    msg = rec["data"]["message"]
    assert "482913" not in msg and "4111" not in msg and "9876543210" not in msg
    assert rec["data"]["diagnostics"] == {} and rec["status"] == "NEW"
    r = client.post("/api/feedback", json={"kind": "bug", "message": "App froze on video page",
                                           "diagnostics": {"screen": "video", "error": "Timeout", "secret": "s"},
                                           "consent_diagnostics": True}).json()
    diag = _pf(container).resources.get("feedback_reports", r["reference"])["data"]["diagnostics"]
    assert diag == {"screen": "video", "error": "Timeout"}, "allow-listed keys only"
    assert client.post("/api/diagnostics/client-error", json={"error": "boom", "consent": False}).json()["stored"] is False
    assert client.post("/api/diagnostics/client-error", json={"error": "StateError: bad", "screen": "home",
                                                              "consent": True}).json()["stored"]
    assert client.get("/admin/cc/early-access/dashboard").status_code in (401, 403)
    dash = client.get("/admin/cc/early-access/dashboard", headers=OWNER).json()
    assert dash["feedback"]["total"] == 2 and dash["feedback"]["by_kind"]["wrong_result"] == 1
    assert dash["errors"][0]["count"] == 1 and dash["errors"][0]["screen"] == "home"


def test_scheduled_feed_sync_runs_only_due_feeds_on_the_background_runner(api):
    _, container, fetch = api
    from app.services.periodic_jobs import PeriodicJobs, default_jobs

    assert "feeds" in [name for name, _, _ in default_jobs()]
    _source(container, name="Feed A", domains=["a.example"], connector="feed",
            feed_url="https://a.example/feed.csv", feed_format="csv")
    fetch.answers["a.example/feed.csv"] = (200, "text/csv", "title,url,price\nKettle,https://a.example/k,500\n")
    jobs = PeriodicJobs(container, jobs=[j for j in default_jobs() if j[0] == "feeds"])
    first = jobs.run_once()["feeds"]
    assert list(first.values())[0]["created"] == 1
    jobs._last.clear()
    assert jobs.run_once()["feeds"] == {}, "synced recently -> not due again"
    assert len([c for c in fetch.calls if "feed.csv" in c]) == 1
