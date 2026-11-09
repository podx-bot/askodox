"""Work Mode teams: invite code, join, step totals, who is walking now, leave.
Only names typed for the team, outfits and daily step totals are shared."""
import dataclasses
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit, work_teams
from app.services.session_tokens import issue_token


@pytest.fixture()
def team(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    settings = dataclasses.replace(container.settings, database_path=str(tmp_path / "team.db"))
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "work_teams", None, raising=False)
    yield TestClient(app), container


def _me(container, phone):
    return {"Authorization": "Bearer " + issue_token(f"app-phone-{phone}", container.settings.session_token_secret)}


def _today():
    return datetime.now(timezone.utc).date().isoformat()


def test_sign_in_is_required(team):
    client, _ = team
    assert client.get("/api/work/team").status_code == 401
    assert client.post("/api/work/team", json={"name": "A", "job": "paddy"}).status_code == 401
    assert client.post("/api/work/team/join", json={"code": "ABCDEF", "name": "A"}).status_code == 401


def test_create_invite_join_and_share_only_names_and_steps(team):
    client, container = team
    me, wife = _me(container, "919800000301"), _me(container, "919800000302")
    assert client.get("/api/work/team", headers=me).json() == {"team": None}
    made = client.post("/api/work/team", json={"name": "Manohar", "team_name": "Our home", "job": "paddy",
                                               "size": "large", "wear": "lungi"}, headers=me).json()["team"]
    code = made["code"]
    assert len(code) == 6 and code.isalnum() and made["job"] == "paddy" and made["size"] == "large"
    joined = client.post("/api/work/team/join", json={"code": code.lower(), "name": "Lakshmi", "wear": "saree"},
                         headers=wife).json()["team"]
    assert [m["name"] for m in joined["members"]] == ["Manohar", "Lakshmi"]
    assert [m["me"] for m in joined["members"]] == [False, True]
    text = repr(joined)
    for secret in ("919800000301", "919800000302", "app-phone"):
        assert secret not in text
    # Each phone reports its own day total; the team sees both, and who moved just now.
    client.put("/api/work/team/steps", json={"day": _today(), "steps": 4200}, headers=me)
    seen = client.get("/api/work/team", headers=wife).json()["team"]["members"]
    assert seen[0]["steps"] == 4200 and seen[0]["active"] is True
    assert seen[1]["steps"] == 0 and seen[1]["active"] is False
    # A smaller number (phone restart, old copy) never lowers the day total.
    client.put("/api/work/team/steps", json={"day": _today(), "steps": 100}, headers=me)
    assert client.get("/api/work/team", headers=me).json()["team"]["members"][0]["steps"] == 4200


def test_one_team_at_a_time_full_team_and_wrong_code(team):
    client, container = team
    heads = [_me(container, f"91980000031{i}") for i in range(6)]
    code = client.post("/api/work/team", json={"name": "A", "job": "hotel"}, headers=heads[0]).json()["team"]["code"]
    assert client.post("/api/work/team", json={"name": "A", "job": "paddy"}, headers=heads[0]).status_code == 409
    assert client.post("/api/work/team/join", json={"code": "ZZZZZZ", "name": "B"}, headers=heads[1]).status_code == 404
    for i in (1, 2, 3):
        assert client.post("/api/work/team/join", json={"code": code, "name": f"P{i}"}, headers=heads[i]).status_code == 200
    full = client.post("/api/work/team/join", json={"code": code, "name": "P4"}, headers=heads[4])
    assert full.status_code == 409 and full.json()["detail"] == "TEAM_FULL"
    # Joining again with the same code is harmless.
    assert client.post("/api/work/team/join", json={"code": code, "name": "P1"}, headers=heads[1]).status_code == 200


def test_walking_now_expires_and_bad_days_are_refused(team, monkeypatch):
    client, container = team
    me = _me(container, "919800000321")
    client.post("/api/work/team", json={"name": "A", "job": "paper"}, headers=me)
    client.put("/api/work/team/steps", json={"day": _today(), "steps": 500}, headers=me)
    later = datetime.now(timezone.utc) + timedelta(minutes=work_teams.ACTIVE_MINUTES + 1)
    monkeypatch.setattr(work_teams, "_now", lambda: later)
    member = client.get("/api/work/team", params={"day": _today()}, headers=me).json()["team"]["members"][0]
    assert member["steps"] == 500 and member["active"] is False
    assert client.put("/api/work/team/steps", json={"day": "2020-01-01", "steps": 5}, headers=me).status_code == 400


def test_leaving_and_account_deletion(team):
    client, container = team
    me, friend = _me(container, "919800000331"), _me(container, "919800000332")
    code = client.post("/api/work/team", json={"name": "A", "job": "paddy"}, headers=me).json()["team"]["code"]
    client.post("/api/work/team/join", json={"code": code, "name": "B"}, headers=friend)
    assert client.post("/api/work/team/leave", headers=me).json() == {"left": True}
    rest = client.get("/api/work/team", headers=friend).json()["team"]
    assert [m["name"] for m in rest["members"]] == ["B"]
    # The last one out removes the team; its code no longer works.
    client.post("/api/work/team/leave", headers=friend)
    assert client.post("/api/work/team/join", json={"code": code, "name": "C"}, headers=me).status_code == 404
