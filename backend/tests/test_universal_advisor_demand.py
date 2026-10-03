"""Universal Advisor (configurable questions, per-field state, guidance),
Demand Intelligence (insights, opportunities, ranked seller matching,
cooldown / daily caps, why-selected audit, seller opportunities), platform
settings, the Admin Assistant and the Staff work queue."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services import advisor_engine as ae
from app.services import demand_insights as di
from app.services.session_tokens import issue_token

TAG = "zorbo"  # a word no other test searches for


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from app.api.routes.platform import platform
    from server import app, container

    key = "owner-ad-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    catalog = ProductCatalogRepository(str(tmp_path / "catalog.db"))
    monkeypatch.setattr(container, "product_catalog_repository", catalog)
    monkeypatch.setattr(container, "demand_alert_log", di.DemandAlertLog(str(tmp_path / "alerts.db")), raising=False)
    monkeypatch.setattr(container, "brave_web_search_provider", None)
    pf = platform(container)
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}, pf, catalog


def _staff(client, owner, role, **extra):
    r = client.post("/admin/cc/staff", headers=owner, json={"name": f"{role} user", "role": role, **extra})
    assert r.status_code == 200, r.text
    return {"X-ASKODOX-Staff-Token": r.json()["token"]}


def _user(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def _records(pf, name):
    return pf.repo.list(name)


# ------------------------------------------------------------- advisor --

def test_defaults_are_seeded_into_the_command_center_and_editable(api):
    client, _, owner, pf, _ = api
    questions = _records(pf, "advisor_questions")
    assert any(q["data"]["field"] == "budget" for q in questions)
    assert any(r["data"]["title"] == "Standing all day" for r in _records(pf, "advisor_rules"))
    listing = client.get("/admin/cc/platform/r/advisor_questions", headers=owner)
    assert listing.status_code == 200 and listing.json()["items"]


def _cats(pf):
    return _records(pf, "advisor_categories")


def test_each_field_has_its_own_state_any_brand_never_settles_budget(api):
    _, _, _, pf, _ = api
    qs, rules = _records(pf, "advisor_questions"), _records(pf, "advisor_rules")
    cats = _cats(pf)
    demand = {"side": "NEED", "domain": "PRODUCT", "subject": "running shoes", "raw_text": "running shoes",
              "constraints": {"dynamic_fields": {"brand": "any", "no_preference": ["brand"]}}}
    view = ae.advise(demand, qs, rules, language="en", category_records=cats)
    assert view["field_states"]["brand"] == "no_preference"
    assert view["field_states"]["budget"] == "unknown"
    assert view["ready"] is False and view["questions"][0]["field"] == "budget"
    # Telugu conversation: the same question in Telugu.
    te = ae.advise(demand, qs, rules, language="te", category_records=cats)
    assert te["questions"][0]["question"] == "మీ బడ్జెట్ ఎంత అనుకుంటున్నారు?"
    # Budget given -> ready; the next useful question is optional usage.
    demand["constraints"]["dynamic_fields"]["budget_max"] = 2000
    view = ae.advise(demand, qs, rules, category_records=cats)
    assert view["ready"] is True and view["questions"][0]["field"] == "usage"
    assert view["questions"][0]["required"] is False
    # "any" for budget settles budget only (not usage).
    demand2 = {"side": "NEED", "subject": "shoes", "raw_text": "shoes",
               "constraints": {"dynamic_fields": {"no_preference": ["budget"]}}}
    view2 = ae.advise(demand2, qs, rules, category_records=cats)
    assert view2["ready"] is True and view2["field_states"]["usage"] == "unknown"
    # "show me now" never waits.
    assert ae.advise({"side": "NEED", "subject": "tv", "raw_text": "tv"}, qs, rules, show_now=True, category_records=cats)["ready"]


def test_guidance_explains_tradeoffs_and_high_stakes_boundaries(api):
    _, _, _, pf, _ = api
    rules = _records(pf, "advisor_rules")
    shoes = ae.guidance({"subject": "shoes", "raw_text": "shoes for standing all day at work"}, rules)
    assert shoes and "cushioning" in shoes[0]["factors"] and shoes[0]["high_stakes"] is False
    loan = ae.guidance({"subject": "personal loan", "raw_text": "need a personal loan"}, rules)
    assert loan[0]["high_stakes"] is True and "guaranteed" in loan[0]["advice"]
    # Questions are not asked for a seller's own listing.
    assert ae.next_questions({"side": "OFFER", "subject": "tv"}, _records(pf, "advisor_questions")) == []


def test_admin_controls_questions_without_code(api):
    client, container, owner, pf, _ = api
    budget = next(q for q in _records(pf, "advisor_questions")
                  if q["data"]["field"] == "budget" and q["data"]["category"] == "any")
    tv = next(c for c in _cats(pf) if c["data"]["key"] == "tv")
    r = client.post(f"/admin/cc/platform/r/advisor_questions/{budget['id']}/actions/disable", headers=owner,
                    json={"params": {}, "confirm": True})
    assert r.status_code == 200, r.text
    try:
        _check_admin_question_changes(client, owner, tv)
    finally:  # the seeded records are shared by later tests
        client.post(f"/admin/cc/platform/r/advisor_questions/{budget['id']}/actions/enable", headers=owner,
                    json={"params": {}, "confirm": True})
        client.patch(f"/admin/cc/platform/r/advisor_categories/{tv['id']}", headers=owner,
                     json={"data": {"required_fields": tv["data"]["required_fields"]}})
        for q in _records(pf, "advisor_questions"):
            if q["data"].get("question_en") == "Smart TV or regular?":
                client.delete(f"/admin/cc/platform/r/advisor_questions/{q['id']}?confirm=true", headers=owner)


def _check_admin_question_changes(client, owner, tv):
    preview = client.post("/admin/cc/advisor/preview", headers=owner, json={"text": "43 inch tv"}).json()
    assert preview["category"]["key"] == "tv"
    assert all(q["field"] != "budget" for q in preview["questions"])  # generic budget wording switched off
    # Staff add a decision field to the TV category and its wording -- no release.
    r = client.patch(f"/admin/cc/platform/r/advisor_categories/{tv['id']}", headers=owner,
                     json={"data": {"required_fields": ["capacity", "budget"]}})
    assert r.status_code == 200, r.text
    created = client.post("/admin/cc/platform/r/advisor_questions", headers=owner, json={"data": {
        "category": "tv", "field": "capacity", "question_en": "Smart TV or regular?", "priority": 900}})
    assert created.status_code == 200, created.text
    preview = client.post("/admin/cc/advisor/preview", headers=owner, json={"text": "43 inch tv"}).json()
    assert preview["questions"][0]["question"] == "Smart TV or regular?"
    assert preview["questions"][0]["required"] is True
    assert any("matched by head noun" in line for line in preview["explanation"])
    # Advisor configuration needs advisor permissions.
    analyst = _staff(client, owner, "analyst")
    assert client.post("/admin/cc/advisor/preview", headers=analyst, json={"text": "tv"}).status_code == 403


def test_discover_and_advisor_next_share_one_engine(api):
    client, _, _, _, _ = api
    body = {"user_id": "", "raw_text": "running shoes", "intent": "buy", "subject": "running shoes",
            "category": "product", "dynamic_fields": {"brand": "any", "no_preference": ["brand"]}}
    data = client.post("/deals/discover", json=body).json()
    assert data["advisor"]["ready"] is False and data["advisor"]["questions"][0]["field"] == "budget"
    body["dynamic_fields"]["budget_max"] = 2000
    data = client.post("/deals/discover", json=body).json()
    assert data["advisor"]["ready"] is True
    nxt = client.post("/api/advisor/next", json={"raw_text": "shoes for standing all day", "language": "en"}).json()
    assert nxt["questions"][0]["field"] == "budget" and nxt["guidance"][0]["title"] == "Standing all day"


# -------------------------------------------------------------- demand --

def _searches(pf, n, *, subject=f"{TAG} running shoes", area="Vijayawada", band="₹1,000-2,000", local=0,
              category="footwear"):
    for _ in range(n):
        pf.repo.record_event("search", category=category, location=area,
                             detail={"subject": subject, "results": 3, "local": local, "budget_band": band})


def _rule(client, owner, **extra):
    data = {"name": "Footwear demand", "category": "any", "keywords": [TAG], "window_days": 7, "min_searches": 10,
            "max_local_results": 0, "require_budget_fit": True, "require_in_stock": True, "mode": "instant",
            "cooldown_hours": 24, "daily_max_per_seller": 2, "max_recipients": 5, "channels": ["in_app"], **extra}
    r = client.post("/admin/cc/platform/r/demand_alert_rules", headers=owner, json={"data": data})
    assert r.status_code == 200, r.text
    rid = r.json()["id"]
    client.post(f"/admin/cc/platform/r/demand_alert_rules/{rid}/actions/enable", headers=owner,
                json={"params": {}, "confirm": True})
    return rid


def test_demand_becomes_ranked_explained_seller_opportunities(api):
    client, container, owner, pf, catalog = api
    catalog.upsert_product("app-seller-a", f"{TAG} running shoes", price=1499, stock_status="IN_STOCK",
                           location_label="Vijayawada")
    catalog.upsert_product("app-seller-b", f"{TAG} running shoes premium", price=6999, stock_status="IN_STOCK",
                           location_label="Vijayawada")
    catalog.upsert_product("app-seller-c", f"{TAG} running shoes", price=1299, stock_status="IN_STOCK",
                           location_label="Hyderabad")
    catalog.upsert_product("app-seller-d", "kitchen tawa", price=499, location_label="Vijayawada")
    _searches(pf, 12)
    _searches(pf, 3, subject=f"{TAG} cricket bat")  # below the threshold

    insights = client.get("/admin/cc/demand/insights?days=7", headers=owner).json()
    top = next(t for t in insights["top_searches"] if TAG in t["subject"] and "running" in t["subject"])
    assert top["count"] == 12 and top["no_local_supply"] == 12 and top["budget_bands"] == {"₹1,000-2,000": 12}

    rid = _rule(client, owner)
    opps = client.get("/admin/cc/demand/opportunities", headers=owner).json()["items"]
    mine = [o for o in opps if o["rule_id"] == rid]
    assert len(mine) == 1 and mine[0]["searches"] == 12 and mine[0]["area"] == "vijayawada"
    key = mine[0]["key"]

    preview = client.post("/admin/cc/demand/opportunities/preview", headers=owner,
                          json={"rule_id": rid, "opportunity_key": key}).json()
    assert [e["recipient"] for e in preview["eligible"]] == ["app-seller-a"]
    reasons = {e["recipient"]: e["reason"] for e in preview["excluded"]}
    assert reasons["app-seller-b"] == "no listing within the demand budget"
    assert "app-seller-c" not in [e["recipient"] for e in preview["eligible"]], "other area"
    assert "app-seller-d" not in reasons and "app-seller-d" not in [e["recipient"] for e in preview["eligible"]]
    assert any("budget" in r for r in preview["eligible"][0]["reasons"])

    assert client.post("/admin/cc/demand/opportunities/notify", headers=owner,
                       json={"rule_id": rid, "opportunity_key": key}).status_code == 409, "needs confirm"
    sent = client.post("/admin/cc/demand/opportunities/notify", headers=owner,
                       json={"rule_id": rid, "opportunity_key": key, "confirm": True}).json()
    assert sent["sent"] == 1 and sent["recipients"] == ["app-seller-a"]
    again = client.post("/admin/cc/demand/opportunities/notify", headers=owner,
                        json={"rule_id": rid, "opportunity_key": key, "confirm": True}).json()
    assert again["sent"] == 0, "no duplicate spam"
    assert {e["recipient"]: e["reason"] for e in again["excluded"]}["app-seller-a"].startswith("cooldown")

    # The seller sees the opportunity (aggregate only) and responds.
    seller = _user(container, "app-seller-a")
    mine = client.get("/api/opportunities", headers=seller).json()["items"]
    assert mine[0]["searches"] == 12 and "12 customers" in mine[0]["body"]
    assert "user" not in str(mine).lower() or "app-" not in str(mine), "no buyer identity"
    r = client.post(f"/api/opportunities/{mine[0]['id']}/respond", headers=seller, json={"response": "interested"})
    assert r.json()["item"]["response"] == "interested"
    other = _user(container, "app-seller-b")
    assert client.post(f"/api/opportunities/{mine[0]['id']}/respond", headers=other,
                       json={"response": "interested"}).status_code == 404
    assert client.get("/api/opportunities").status_code == 401

    log = client.get("/admin/cc/demand/alerts", headers=owner).json()["items"]
    assert log[0]["rule_id"] == rid and log[0]["responded_at"] and log[0]["reasons"]
    assert "demand.notify" in client.get("/admin/cc/audit?limit=50", headers=owner).text


def test_daily_maximum_and_permissions(api):
    client, container, owner, pf, catalog = api
    catalog.upsert_product("app-seller-a", f"{TAG} shoes", price=999, location_label="Guntur")
    for subject in (f"{TAG} shoes black", f"{TAG} shoes white", f"{TAG} shoes red"):
        _searches(pf, 10, subject=subject, area="Guntur")
    rid = _rule(client, owner, daily_max_per_seller=2, require_budget_fit=False)
    run = client.post("/admin/cc/demand/run", headers=owner, json={"confirm": True}).json()
    sent_to_a = [a for a in client.get("/admin/cc/demand/alerts", headers=owner).json()["items"]
                 if a["recipient"] == "app-seller-a"]
    assert len(sent_to_a) == 2, "daily maximum per seller (across every rule)"
    assert run["opportunities"] >= 3

    ops = _staff(client, owner, "demand_operations")
    assert client.get("/admin/cc/demand/insights", headers=ops).status_code == 200
    analyst = _staff(client, owner, "analyst")
    assert client.get("/admin/cc/demand/insights", headers=analyst).status_code == 200
    assert client.post("/admin/cc/demand/run", headers=analyst, json={"confirm": True}).status_code == 403
    support = _staff(client, owner, "support_agent")
    assert client.get("/admin/cc/demand/insights", headers=support).status_code == 403


def test_no_eligible_seller_is_reported_honestly(api):
    client, _, owner, pf, _ = api
    _searches(pf, 11, subject=f"{TAG} wedding sherwani", area="Eluru")
    rid = _rule(client, owner)
    opp = next(o for o in client.get("/admin/cc/demand/opportunities", headers=owner).json()["items"]
               if "sherwani" in o["subject"])
    out = client.post("/admin/cc/demand/opportunities/notify", headers=owner,
                      json={"rule_id": rid, "opportunity_key": opp["key"], "confirm": True}).json()
    assert out["sent"] == 0 and "recruit" in out["note"]


def test_request_and_search_events_feed_the_funnel(api):
    client, container, owner, pf, _ = api
    headers = _user(container, "app-buyer-funnel")
    body = {"user_id": "app-buyer-funnel", "raw_text": f"{TAG} football boots size 9 under 1500",
            "intent": "buy", "subject": f"{TAG} football boots", "category": "product", "price": 1500,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6}}
    created = client.post("/deals", json=body, headers=headers)
    assert created.status_code == 200, created.text
    requests = pf.repo.events(event="request", limit=50)
    assert any(TAG in str(e["detail"].get("subject")) and e["detail"].get("budget_band") == "₹1,000-2,000"
               for e in requests)
    assert all("app-buyer" not in str(e) for e in requests), "no identity in analytics"
    client.post("/deals/discover", json={**body, "user_id": ""})
    search = next(e for e in pf.repo.events(event="search", limit=50) if TAG in str(e["detail"].get("subject")))
    assert "local" in search["detail"] and search["detail"]["budget_band"] == "₹1,000-2,000"


# ---------------------------------------------------- settings / assistant --

def test_platform_settings_are_bounded_and_apply_without_deploy(api):
    client, _, owner, _, _ = api
    from app.services import platform_settings
    from app.services.video_study import study_max_seconds

    bad = client.post("/admin/cc/platform/r/platform_settings", headers=owner,
                      json={"data": {"key": "video_study.max_seconds", "value": 5000}})
    assert bad.status_code in (400, 422) and "between" in bad.text
    good = client.post("/admin/cc/platform/r/platform_settings", headers=owner,
                       json={"data": {"key": "video_study.max_seconds", "value": 120, "reason": "test"}})
    assert good.status_code == 200, good.text
    platform_settings.invalidate()
    assert study_max_seconds() == 120
    eff = client.get("/admin/cc/settings/effective", headers=owner).json()["items"]
    assert eff["video_study.max_seconds"]["source"] == "command_center"
    client.post(f"/admin/cc/platform/r/platform_settings/{good.json()['id']}/actions/disable", headers=owner,
                json={"params": {}, "confirm": True})
    platform_settings.invalidate()
    assert study_max_seconds() == 180


def test_admin_assistant_answers_from_data_with_fact_likely_action(api):
    client, _, owner, pf, _ = api
    _searches(pf, 60, subject=f"{TAG} rain coat", area="Vijayawada")
    out = client.post("/admin/cc/assistant/ask", headers=owner,
                      json={"question": "Which categories have unmet demand?"}).json()
    unmet = next(a for a in out["answers"] if a["topic"] == "unmet")
    assert any("rain coat" in line for line in unmet["observed"])
    assert unmet["actions"] and out["basis"].startswith("Recorded")
    rising = client.post("/admin/cc/assistant/ask", headers=owner, json={"question": "Why did searches rise?"}).json()
    r = next(a for a in rising["answers"] if a["topic"] == "rising")
    assert all("not recorded" in line for line in r["likely"]), "never invents a cause"


def test_staff_work_queue_shows_only_permitted_work(api):
    client, _, owner, _, _ = api
    catalog_staff = _staff(client, owner, "affiliate_catalog_staff")
    keys = {i["key"] for i in client.get("/admin/cc/staff/work-queue", headers=catalog_staff).json()["items"]}
    assert "stock_unknown" in keys and "support" not in keys and "commission_unknown" not in keys
    support = _staff(client, owner, "support_agent")
    keys = {i["key"] for i in client.get("/admin/cc/staff/work-queue", headers=support).json()["items"]}
    assert "support" in keys and "stock_unknown" not in keys
    every = client.get("/admin/cc/staff/work-queue", headers=owner).json()["items"]
    assert all({"what_to_do", "why", "done_when", "where"} <= set(i) for i in every)


# ------------------------------------------------------- auto-response --

def test_auto_response_answers_only_from_approved_faq():
    from datetime import datetime, timezone

    from app.services import auto_response as ar

    rule = {"faq": {"delivery": "We deliver across Vijayawada in 2 days.",
                    "returns policy": "7-day returns. Call 98765 43210 for pickup."},
            "business_hours": "09-21", "out_of_hours_reply": "We open at 9 AM."}
    day = datetime(2026, 10, 3, 6, 0, tzinfo=timezone.utc)   # 11:30 IST
    night = datetime(2026, 10, 3, 18, 0, tzinfo=timezone.utc)  # 23:30 IST
    assert ar.answer("Do you deliver to Benz Circle?", rule, at=day)["source"] == "faq:delivery"
    returns = ar.answer("what is your returns policy", rule, at=day)
    assert returns["status"] == "answered" and "98765" not in returns["text"], "contacts masked"
    assert ar.answer("Is the sole leather?", rule, at=day)["status"] == "unknown", "never guessed"
    assert ar.answer("I want a refund now", rule, at=day)["status"] == "handoff"
    assert ar.answer("Do you deliver?", rule, at=night) == {"status": "out_of_hours", "text": "We open at 9 AM.",
                                                            "source": "business_hours"}


def test_seller_sets_up_auto_response_and_it_replies_in_deal_chat(api):
    client, container, owner, pf, _ = api
    seller = _user(container, "app-seller-auto")
    assert client.get("/api/business/auto-response").status_code == 401
    saved = client.put("/api/business/auto-response", headers=seller, json={
        "enabled": True, "business_hours": "", "faq": {"delivery": "Free delivery in Vijayawada."}})
    assert saved.status_code == 200, saved.text
    assert saved.json()["item"]["status"] == "ACTIVE"
    assert client.post("/api/business/auto-response/preview", headers=seller,
                       json={"message": "Do you deliver?"}).json()["status"] == "answered"
    # Another seller cannot see it.
    other = client.get("/api/business/auto-response", headers=_user(container, "app-seller-x")).json()
    assert other["item"] is None
    # In a deal chat the buyer's question gets the approved answer, marked as an auto-reply.
    from app.api.routes.in_app_deal import _auto_reply, _ensure_messages_table

    db = container.database
    _ensure_messages_table(db)
    result = _auto_reply(container, db, 991, "app-buyer-auto", "app-seller-auto", "do you deliver to my area?")
    assert result["status"] == "answered" and result["handoff_to_owner"] is False
    row = db.fetchone("SELECT * FROM in_app_deal_messages WHERE request_id=991 ORDER BY id DESC LIMIT 1")
    assert row["message_type"] == "AUTO_REPLY" and row["message_text"].startswith("Auto-reply: Free delivery")
    unknown = _auto_reply(container, db, 991, "app-buyer-auto", "app-seller-auto", "what colour is it?")
    assert unknown["status"] == "unknown" and unknown["handoff_to_owner"] is True
    # Admin kill switch.
    client.put("/admin/cc/config/autoresponse.enabled", headers=owner, json={"enabled": False, "confirm": True})
    try:
        assert _auto_reply(container, db, 991, "app-buyer-auto", "app-seller-auto", "do you deliver?") is None
    finally:
        client.put("/admin/cc/config/autoresponse.enabled", headers=owner, json={"enabled": True, "confirm": True})
