"""Free / Plus / Pro: seeded once; only Free is on (Rs 0); Plus Rs 499 and
Pro Rs 999 (7-day trial) are stored INACTIVE -- shown as not available,
refused by /api/subscriptions; staff edits are never overwritten."""
import uuid

from fastapi.testclient import TestClient

from app.services import subscription_plans
from app.services.session_tokens import issue_token


def _client():
    from server import app, container

    return TestClient(app), container


def test_catalogue_shows_proposed_prices_but_sells_only_free():
    client, container = _client()
    items = {p["code"]: p for p in client.get("/api/plans/catalogue").json()["items"]}
    assert (items["free"]["price"], items["free"]["available"]) == (0, True)
    assert (items["plus"]["price"], items["plus"]["available"]) == (499, False)
    assert (items["pro"]["price"], items["pro"]["trial_days"], items["pro"]["available"]) == (999, 7, False)
    assert not any(code.startswith("radio_") for code in items), "add-ons are never base plans"
    public = {p["code"] for p in client.get("/api/plans").json()["items"]}
    assert "plus" not in public and "pro" not in public
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    me = {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}
    assert client.post("/api/subscriptions", headers=me, json={"plan_code": "pro"}).status_code == 404
    free = client.post("/api/subscriptions", headers=me, json={"plan_code": "free"}).json()
    assert free["subscription"]["status"] == "ACTIVE" and free["note"] == ""


def test_seed_never_overwrites_staff_edits():
    _, container = _client()
    from app.api.routes.growth import growth

    repo = growth(container)
    plan = repo.plan("plus")
    repo.upsert_plan("plus", name="Plus", audience="base", price=449, period_days=30, active=False)
    try:
        subscription_plans.seed(repo)
        assert repo.plan("plus")["price"] == 449
    finally:
        repo.upsert_plan("plus", name=plan["name"], audience="base", price=plan["price"],
                         period_days=plan["period_days"], active=False)
