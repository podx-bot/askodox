"""Detect -> Diagnose -> Explain -> Propose -> Approve -> Execute -> Verify
-> Report, with an audit record and rollback for every admin action.

* read-only actions (re-check a provider, rescan billing alerts) may run
  without approval -- rate limited (never more than twice per action per
  hour) so a failing provider is not hammered.
* change actions need an explicit approval by a person with the action's
  permission, run once, are verified with real evidence, and keep their
  rollback. Two NOT_RECOVERED results for the same action block it (no
  unsafe retry loop).
* Only actions in CATALOG exist; the AI can only propose them.
"""
from __future__ import annotations

import json
import sqlite3
import time
from contextlib import closing
from typing import Any, Callable

CATALOG: dict[str, dict[str, Any]] = {
    "recheck": {"risk": "read_only", "permission": "health:view",
                "description": "Re-check a provider with one real call / refresh its state"},
    "rescan_billing": {"risk": "read_only", "permission": "health:view",
                       "description": "Re-evaluate API billing alerts from recorded usage"},
    "selfheal_apply": {"risk": "change", "permission": "selfheal:manage",
                       "description": "Apply a proposed GREEN self-healing fix (temporary, reversible)"},
}
READ_ONLY_PER_HOUR = 2
MAX_NOT_RECOVERED = 2


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS admin_action_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, incident_key TEXT, action TEXT NOT NULL, target TEXT,
        risk TEXT NOT NULL, status TEXT NOT NULL, proposed_by TEXT, approved_by TEXT, result TEXT,
        verification TEXT, rollback TEXT, timeline TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)""")
    return conn


def _row(r: sqlite3.Row) -> dict[str, Any]:
    out = dict(r)
    out["timeline"] = json.loads(out["timeline"] or "[]")
    return out


def get(db_path: str, run_id: int) -> dict[str, Any] | None:
    with closing(_connect(db_path)) as conn:
        r = conn.execute("SELECT * FROM admin_action_runs WHERE id=?", (run_id,)).fetchone()
    return _row(r) if r else None


def runs(db_path: str, limit: int = 100) -> list[dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        return [_row(r) for r in conn.execute("SELECT * FROM admin_action_runs ORDER BY id DESC LIMIT ?",
                                               (limit,)).fetchall()]


def _update(db_path: str, run_id: int, step: str, actor: str, **fields: Any) -> dict[str, Any]:
    run = get(db_path, run_id)
    timeline = run["timeline"] + [{"step": step, "by": actor, "at": time.time()}]
    fields = {**fields, "timeline": json.dumps(timeline), "updated_at": time.time()}
    with closing(_connect(db_path)) as conn:
        conn.execute(f"UPDATE admin_action_runs SET {', '.join(f'{k}=?' for k in fields)} WHERE id=?",
                     [*fields.values(), run_id])
        conn.commit()
    return get(db_path, run_id)


def propose(db_path: str, action: str, target: str, *, actor: str, incident_key: str = "") -> dict[str, Any]:
    if action not in CATALOG:
        raise ValueError("unknown action")
    now = time.time()
    with closing(_connect(db_path)) as conn:
        blocked = conn.execute("SELECT COUNT(*) FROM admin_action_runs WHERE action=? AND target=? AND "
                               "verification='NOT_RECOVERED'", (action, target)).fetchone()[0]
        if blocked >= MAX_NOT_RECOVERED:
            raise PermissionError("blocked: this action already failed to recover twice -- a person must investigate")
        cur = conn.execute(
            "INSERT INTO admin_action_runs(incident_key, action, target, risk, status, proposed_by, timeline, "
            "created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
            (incident_key, action, target, CATALOG[action]["risk"], "PROPOSED", actor,
             json.dumps([{"step": "detected+diagnosed+explained+proposed", "by": actor, "at": now}]), now, now))
        conn.commit()
        return get(db_path, int(cur.lastrowid))


def approve(db_path: str, run_id: int, *, actor: str, can: Callable[[str], bool]) -> dict[str, Any]:
    run = get(db_path, run_id)
    if run is None:
        raise KeyError(run_id)
    if run["status"] != "PROPOSED":
        raise ValueError(f"cannot approve a {run['status']} action")
    if not can(CATALOG[run["action"]]["permission"]):
        raise PermissionError(f"needs {CATALOG[run['action']]['permission']}")
    return _update(db_path, run_id, "approved", actor, status="APPROVED", approved_by=actor)


def reject(db_path: str, run_id: int, *, actor: str) -> dict[str, Any]:
    run = get(db_path, run_id)
    if run is None:
        raise KeyError(run_id)
    if run["status"] not in ("PROPOSED", "APPROVED"):
        raise ValueError(f"cannot reject a {run['status']} action")
    return _update(db_path, run_id, "rejected", actor, status="REJECTED")


def execute(db_path: str, run_id: int, *, actor: str, can: Callable[[str], bool],
            runners: dict[str, Callable[[str], dict[str, Any]]]) -> dict[str, Any]:
    """Run the action, verify with real evidence, report. ``runners[action]
    (target)`` returns {"result", "verified": bool | None, "rollback"}."""
    run = get(db_path, run_id)
    if run is None:
        raise KeyError(run_id)
    spec = CATALOG[run["action"]]
    if not can(spec["permission"]):
        raise PermissionError(f"needs {spec['permission']}")
    if spec["risk"] == "change" and run["status"] != "APPROVED":
        raise PermissionError("a change needs approval before it runs")
    if spec["risk"] == "read_only":
        if run["status"] not in ("PROPOSED", "APPROVED"):
            raise ValueError(f"cannot run a {run['status']} action")
        with closing(_connect(db_path)) as conn:
            recent = conn.execute("SELECT COUNT(*) FROM admin_action_runs WHERE action=? AND target=? AND "
                                  "status IN ('EXECUTED','VERIFIED','NOT_RECOVERED','REPORTED') AND updated_at>?",
                                  (run["action"], run["target"], time.time() - 3600)).fetchone()[0]
        if recent >= READ_ONLY_PER_HOUR:
            raise PermissionError("rate limited: this check already ran twice in the last hour")
    runner = runners.get(run["action"])
    if runner is None:
        raise ValueError("no runner for this action in this deployment")
    try:
        outcome = runner(run["target"] or "")
    except Exception as error:  # reported, never retried automatically
        return _update(db_path, run_id, "executed (failed)", actor, status="REPORTED",
                       result=f"failed: {type(error).__name__}", verification="NOT_RECOVERED")
    verified = outcome.get("verified")
    verification = "VERIFIED" if verified is True else "NOT_RECOVERED" if verified is False else "UNVERIFIED"
    _update(db_path, run_id, "executed", actor, status="EXECUTED", result=str(outcome.get("result") or "")[:500],
            rollback=str(outcome.get("rollback") or "") or None)
    return _update(db_path, run_id, f"verified: {verification}; reported", actor, status="REPORTED",
                   verification=verification)
