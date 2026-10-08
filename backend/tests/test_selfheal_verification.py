"""Self-Healing never reports success without evidence (APK 1312): APPLIED
means the action ran; recovery is VERIFIED only when real outcomes after the
fix show it, NOT_RECOVERED when they show it did not, else UNVERIFIED."""
import sqlite3
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services import self_healing as sh


@pytest.fixture()
def engine(tmp_path):
    db = str(tmp_path / "heal.db")
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE discovery_events (demand_id TEXT, source TEXT, status TEXT, created_at TEXT, "
                     "UNIQUE(demand_id, source))")
    return sh.SelfHealingEngine(SimpleNamespace(settings=SimpleNamespace(database_path=db))), db


def _bypass(engine, minutes_ago=5, expired=False):
    now = datetime.now(timezone.utc)
    until = now - timedelta(minutes=1) if expired else now + timedelta(minutes=10)
    item = engine._log(issue_key="source_errors:nearby", issue="Places failed", risk=sh.GREEN,
                       action="bypass_source", target="nearby", reason="r", status="APPLIED")
    engine._set(item["id"], expires_at=until.isoformat(), status="EXPIRED" if expired else "APPLIED")
    return item["id"]


def _event(db, demand, source, status, minutes_ago=1):
    at = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    with sqlite3.connect(db) as conn:
        conn.execute("INSERT INTO discovery_events VALUES (?,?,?,?)", (demand, source, status, at))


def test_applied_is_not_success_until_evidence(engine):
    e, _ = engine
    log_id = _bypass(e)
    assert e.get(log_id)["verification"]["state"] == sh.UNVERIFIED
    e.verify_applied()
    assert e.get(log_id)["verification"]["state"] == sh.UNVERIFIED, "no searches yet -> still unverified"


def test_answered_searches_verify_the_bypass(engine):
    e, db = engine
    log_id = _bypass(e)
    _event(db, "d1", "online", "ok")
    _event(db, "d2", "nearby", "ok")  # the bypassed source itself never counts
    counts = e.verify_applied()
    v = e.get(log_id)["verification"]
    assert v["state"] == sh.VERIFIED and v["answered"] == 1 and counts[sh.VERIFIED] == 1


def test_an_expired_bypass_with_no_answers_is_not_recovered(engine):
    e, db = engine
    log_id = _bypass(e, expired=True)
    _event(db, "d3", "online", "error")
    e.verify_applied()
    assert e.get(log_id)["verification"]["state"] == sh.NOT_RECOVERED


def test_conversation_fix_is_verified_only_when_rendered(engine, monkeypatch):
    e, _ = engine
    monkeypatch.setattr(e, "_flag", lambda key: True)
    plain = e.record_conversation_fix("duplicate_cta")
    assert plain["verification"]["state"] == sh.UNVERIFIED
    e.verify_applied()
    assert e.get(plain["id"])["verification"]["state"] == sh.UNVERIFIED
    shown = e.record_conversation_fix("stale_state", detail={"rendered": True})
    e.verify_applied()
    assert e.get(shown["id"])["verification"]["state"] == sh.VERIFIED


def test_proposals_have_no_recovery_claim(engine):
    e, _ = engine
    item = e._log(issue_key="x", issue="x", risk=sh.GREEN, action="bypass_source", reason="r", status="PROPOSED")
    assert item["verification"] is None
