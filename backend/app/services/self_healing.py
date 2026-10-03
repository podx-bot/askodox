"""Self-Healing Engine (Command Center -> System -> Self-healing).

Risk-bounded by design:

* GREEN -- safe, temporary, reversible, customer-neutral: bypass a discovery
  source that keeps failing (Google Places / web search) for 15 minutes so
  customers get the other sources quickly instead of timeouts. Applied
  automatically only when "selfheal.green_auto" is ON; otherwise proposed.
  Every bypass expires by itself and can be rolled back at once.
* ORANGE -- changes something customers or partners see (e.g. pausing a
  campaign with impossible click counts): always PROPOSED and sent through
  the approvals workflow; a person approves.
* RED -- payments, refunds, credentials, security, permissions, deploys,
  mass deletion, privacy, ledgers, irreversible data: NEVER automated. The
  engine only raises an alert to the Owner.

Each issue records: what was seen, risk, action, reason, result, how to roll
back and when. Nothing here runs code, SQL or shell supplied by anyone.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

GREEN, ORANGE, RED = "GREEN", "ORANGE", "RED"
BYPASSABLE = {"nearby": "Google Places (nearby shops)", "used_deals": "Web search (online / used / deals)",
              "jobs": "Web search (jobs)"}
WINDOW_MINUTES = 30
MIN_ERRORS = 5
ERROR_SHARE = 0.6
BYPASS_MINUTES = 15
RED_NEVER_AUTO = ("payments", "refunds", "credentials", "security", "permissions", "deploys", "mass deletion",
                  "privacy", "ledgers", "irreversible database changes")


def _now() -> datetime:
    return datetime.now(timezone.utc)


class SelfHealingEngine:
    def __init__(self, container: Any) -> None:
        self.container = container
        self.db_path = container.settings.database_path
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS cc_healing_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, issue_key TEXT NOT NULL, issue TEXT NOT NULL,
                    risk TEXT NOT NULL, action TEXT NOT NULL, reason TEXT NOT NULL, status TEXT NOT NULL,
                    result TEXT, rollback TEXT, target TEXT, approval_id INTEGER, evidence_json TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, expires_at TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_healing_issue ON cc_healing_log(issue_key, status);
                CREATE TABLE IF NOT EXISTS cc_healing_bypass (
                    source TEXT PRIMARY KEY, until TEXT NOT NULL, log_id INTEGER
                );
                """
            )

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # --------------------------------------------------------------- flags --

    def _flag(self, key: str) -> bool:
        from app.api.routes.command_center import feature_enabled

        return feature_enabled(self.container, key)

    def settings(self) -> Dict[str, Any]:
        return {"enabled": self._flag("selfheal.enabled"), "green_auto": self._flag("selfheal.green_auto"),
                "orange_requires_approval": True, "red_owner_only_never_auto": True,
                "red_categories": list(RED_NEVER_AUTO)}

    # ----------------------------------------------------------------- log --

    def _open_issue(self, issue_key: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM cc_healing_log WHERE issue_key=? AND status IN "
                               "('PROPOSED','APPLIED','PENDING_APPROVAL','ALERTED') ORDER BY id DESC LIMIT 1",
                               (issue_key,)).fetchone()
        return self._row(row) if row else None

    def _log(self, *, issue_key: str, issue: str, risk: str, action: str, reason: str, status: str,
             rollback: str = "", target: str = "", evidence: Dict[str, Any] | None = None,
             expires_at: str | None = None, result: str = "") -> Dict[str, Any]:
        from app.services.governance import redact

        now = _now().isoformat()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO cc_healing_log(issue_key,issue,risk,action,reason,status,result,rollback,target,"
                "evidence_json,created_at,updated_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (issue_key, issue, risk, action, reason, status, result, rollback, target,
                 json.dumps(redact(evidence or {}), default=str), now, now, expires_at))
            log_id = int(cur.lastrowid)
        self._event(risk, action, status)
        return self.get(log_id) or {}

    def _set(self, log_id: int, **fields: Any) -> None:
        fields["updated_at"] = _now().isoformat()
        cols = ", ".join(f"{k}=?" for k in fields)
        with self._connect() as conn:
            conn.execute(f"UPDATE cc_healing_log SET {cols} WHERE id=?", (*fields.values(), int(log_id)))

    def get(self, log_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM cc_healing_log WHERE id=?", (int(log_id),)).fetchone()
        return self._row(row) if row else None

    def log(self, limit: int = 200) -> List[Dict[str, Any]]:
        self._expire()
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM cc_healing_log ORDER BY id DESC LIMIT ?", (int(limit),)).fetchall()
        return [self._row(r) for r in rows]

    @staticmethod
    def _row(row) -> Dict[str, Any]:
        data = dict(row)
        data["evidence"] = json.loads(data.pop("evidence_json") or "{}")
        return data

    def _event(self, risk: str, action: str, status: str) -> None:
        try:
            from app.api.routes.platform import platform

            platform(self.container).repo.record_event("selfheal", source=risk,
                                                       detail={"action": action, "status": status})
        except Exception:
            pass

    # ------------------------------------------------- conversation (GREEN) --
    # Safe, customer-neutral corrections the app applies itself inside one
    # conversation turn. Only these kinds/actions exist; nothing here can
    # touch payments, permissions, data or configuration (ORANGE/RED).
    CONVERSATION_FIXES = {
        "irrelevant_fallback": ("hide_unrelated_results", "Results unrelated to the request were not shown."),
        "duplicate_cta": ("dedupe_actions", "A repeated or unrelated call-to-action was not shown."),
        "attachment_intent_mismatch": ("explain_attachment_first",
                                       "An attachment sent to be understood was explained instead of searched."),
        "stale_state": ("flag_stale_state", "An out-of-date state (e.g. last detected place) was flagged, not "
                                            "used silently."),
        "wrong_fallback_branch": ("route_to_correct_branch", "The turn was routed to the matching branch."),
    }

    def record_conversation_fix(self, kind: str, *, result: str = "applied", detail: Dict[str, Any] | None = None
                                ) -> Optional[Dict[str, Any]]:
        if kind not in self.CONVERSATION_FIXES or not self._flag("selfheal.enabled"):
            return None
        action, reason = self.CONVERSATION_FIXES[kind]
        issue_key = f"conversation:{kind}"
        since = (_now() - timedelta(minutes=10)).isoformat()
        with self._connect() as conn:
            row = conn.execute("SELECT id, evidence_json FROM cc_healing_log WHERE issue_key=? AND created_at>=? "
                               "ORDER BY id DESC LIMIT 1", (issue_key, since)).fetchone()
            if row:  # one row per kind per 10 minutes; repeats are counted
                evidence = json.loads(row[1] or "{}")
                evidence["occurrences"] = int(evidence.get("occurrences") or 1) + 1
                conn.execute("UPDATE cc_healing_log SET evidence_json=?, updated_at=? WHERE id=?",
                             (json.dumps(evidence), _now().isoformat(), row[0]))
                return self.get(int(row[0]))
        return self._log(issue_key=issue_key, issue=kind.replace("_", " "), risk=GREEN, action=action,
                         reason=reason, status="APPLIED", result=(result or "applied")[:80],
                         rollback="Not needed: applied to one reply only.",
                         evidence={**(detail or {}), "occurrences": 1, "applied_by": "app"})

    def repeated_conversation_fixes(self, *, days: int = 7, minimum: int = 3) -> List[Dict[str, Any]]:
        """Conversation fixes applied at least ``minimum`` times -> evidence
        for an AI Insight (the guard works, but the root cause remains)."""
        since = (_now() - timedelta(days=days)).isoformat()
        totals: Dict[str, Dict[str, Any]] = {}
        with self._connect() as conn:
            rows = conn.execute("SELECT issue_key, issue, evidence_json FROM cc_healing_log WHERE issue_key LIKE "
                                "'conversation:%' AND created_at>=?", (since,)).fetchall()
        for key, issue, evidence in rows:
            n = int((json.loads(evidence or "{}") or {}).get("occurrences") or 1)
            entry = totals.setdefault(key, {"issue_key": key, "issue": issue, "occurrences": 0})
            entry["occurrences"] += n
        return sorted((e for e in totals.values() if e["occurrences"] >= minimum), key=lambda e: -e["occurrences"])

    # ------------------------------------------------------------- bypass --

    def _expire(self) -> None:
        now = _now().isoformat()
        with self._connect() as conn:
            expired = conn.execute("SELECT * FROM cc_healing_bypass WHERE until<=?", (now,)).fetchall()
            conn.execute("DELETE FROM cc_healing_bypass WHERE until<=?", (now,))
        for row in expired:
            if row["log_id"]:
                self._set(row["log_id"], status="EXPIRED", result="Bypass ended; the source is used again.")

    def bypassed_sources(self) -> set[str]:
        """Sources discovery must skip right now (never raises)."""
        try:
            self._expire()
            with self._connect() as conn:
                return {r["source"] for r in conn.execute("SELECT source FROM cc_healing_bypass").fetchall()}
        except Exception:
            return set()

    def _apply_bypass(self, log_id: int, source: str) -> None:
        until = (_now() + timedelta(minutes=BYPASS_MINUTES)).isoformat()
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO cc_healing_bypass VALUES (?, ?, ?)", (source, until, log_id))
        self._set(log_id, status="APPLIED", expires_at=until,
                  result=f"{BYPASS_MINUTES}-minute bypass: customers get the other sources without waiting.")

    # ------------------------------------------------------------ actions --

    def apply(self, log_id: int, actor: str) -> Dict[str, Any]:
        """A person applies a GREEN proposal (ORANGE goes through approvals)."""
        item = self.get(log_id)
        if not item:
            raise KeyError(log_id)
        if item["risk"] != GREEN:
            raise PermissionError("Only GREEN fixes can be applied directly; ORANGE needs an approval, RED never.")
        if item["status"] != "PROPOSED":
            raise ValueError(f"already {item['status'].lower()}")
        if item["action"] == "bypass_source":
            self._apply_bypass(log_id, item["target"])
        return self.get(log_id) or {}

    def rollback(self, log_id: int, actor: str) -> Dict[str, Any]:
        item = self.get(log_id)
        if not item:
            raise KeyError(log_id)
        if item["status"] != "APPLIED":
            raise ValueError("only an applied fix can be rolled back")
        if item["action"] == "bypass_source":
            with self._connect() as conn:
                conn.execute("DELETE FROM cc_healing_bypass WHERE source=?", (item["target"],))
        elif item["action"] == "pause_campaign":
            self._campaign_action(item["target"], "resume", actor)
        self._set(log_id, status="ROLLED_BACK", result=f"Rolled back by {actor}.")
        return self.get(log_id) or {}

    def _campaign_action(self, campaign_id: str, action: str, actor: str) -> None:
        from app.api.routes.platform import platform

        platform(self.container).resources.action("promotion_campaigns", campaign_id, action, actor=actor)

    def execute_approved(self, log_id: int, decider: str) -> Dict[str, Any]:
        """Approval executor for ORANGE proposals."""
        item = self.get(log_id)
        if not item or item["status"] != "PENDING_APPROVAL":
            raise ValueError("proposal is not waiting for approval")
        if item["action"] == "pause_campaign":
            self._campaign_action(item["target"], "pause", f"selfheal:{decider}")
            self._set(log_id, status="APPLIED", result=f"Campaign paused after approval by {decider}.")
        return self.get(log_id) or {}

    def mark_rejected(self, approval_id: int) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE cc_healing_log SET status='REJECTED', updated_at=? WHERE approval_id=? AND "
                         "status='PENDING_APPROVAL'", (_now().isoformat(), int(approval_id)))

    # --------------------------------------------------------------- scan --

    def scan(self) -> Dict[str, Any]:
        if not self._flag("selfheal.enabled"):
            return {"ran": False, "reason": "Self-Healing is switched off"}
        self._expire()
        found: List[Dict[str, Any]] = []
        found += self._scan_sources()
        found += self._scan_campaigns()
        found += self._scan_payments()
        return {"ran": True, "new_issues": len(found), "issues": found}

    def _scan_sources(self) -> List[Dict[str, Any]]:
        since = (_now() - timedelta(minutes=WINDOW_MINUTES)).isoformat()
        try:
            with self._connect() as conn:
                rows = conn.execute("SELECT source, status, COUNT(*) n FROM discovery_events WHERE created_at>=? "
                                    "GROUP BY source, status", (since,)).fetchall()
        except sqlite3.Error:
            return []
        stats: Dict[str, Dict[str, int]] = {}
        for r in rows:
            stats.setdefault(r["source"], {})[r["status"]] = r["n"]
        out = []
        auto = self._flag("selfheal.green_auto")
        active = self.bypassed_sources()
        for source, by in stats.items():
            if source not in BYPASSABLE or source in active:
                continue
            errors = by.get("error", 0)
            total = sum(v for k, v in by.items() if k not in ("not_applicable", "needs_location", "disabled"))
            if errors < MIN_ERRORS or not total or errors / total < ERROR_SHARE:
                continue
            key = f"source_errors:{source}"
            if self._open_issue(key):
                continue
            item = self._log(
                issue_key=key, issue=f"{BYPASSABLE[source]} failed {errors} of {total} times in {WINDOW_MINUTES} min",
                risk=GREEN, action="bypass_source", target=source, status="PROPOSED",
                reason="Repeated provider errors slow every search down; other sources still answer.",
                rollback="Remove the bypass (Rollback) -- it also ends by itself after 15 minutes.",
                evidence={"errors": errors, "checked": total, "window_minutes": WINDOW_MINUTES})
            if auto:
                self._apply_bypass(item["id"], source)
            out.append(self.get(item["id"]))
        return out

    def _scan_campaigns(self) -> List[Dict[str, Any]]:
        try:
            from app.api.routes.platform import platform

            pf = platform(self.container)
            since = (_now() - timedelta(days=1)).isoformat()
            counts = pf.repo.event_counts(since=since, group="campaign_id")
        except Exception:
            return []
        delivered = {r["campaign_id"]: r["n"] for r in counts if r["event"] == "notification_delivery"
                     and r.get("campaign_id")}
        clicks = {r["campaign_id"]: r["n"] for r in counts if r["event"] == "campaign_click" and r.get("campaign_id")}
        out = []
        for cid, n in delivered.items():
            if n < 5 or clicks.get(cid, 0) <= n:
                continue
            key = f"campaign_clicks:{cid}"
            if self._open_issue(key):
                continue
            record = pf.repo.get(cid)
            if not record or record.get("status") != "ACTIVE":
                continue
            item = self._log(
                issue_key=key, issue=f"Promotion {cid}: {clicks[cid]} clicks for {n} deliveries in 24 h",
                risk=ORANGE, action="pause_campaign", target=cid, status="PENDING_APPROVAL",
                reason="More clicks than deliveries points to automated / repeated clicks.",
                rollback="Resume the campaign (Rollback).", evidence={"delivered": n, "clicks": clicks[cid]})
            approval = self._request_approval(item)
            if approval:
                self._set(item["id"], approval_id=approval["id"])
            out.append(self.get(item["id"]))
        return out

    def _scan_payments(self) -> List[Dict[str, Any]]:
        try:
            from app.api.routes.platform import platform

            since = (_now() - timedelta(hours=1)).isoformat()
            payments = [p for p in platform(self.container).repo.payments(limit=2000) if p["created_at"] >= since]
        except Exception:
            return []
        failed = sum(1 for p in payments if p["status"] == "FAILED")
        if len(payments) < 5 or failed / len(payments) <= 0.3:
            return []
        key = f"payments_failing:{_now().strftime('%Y%m%d%H')}"
        if self._open_issue(key):
            return []
        item = self._log(
            issue_key=key, issue=f"{failed} of {len(payments)} payments failed in the last hour",
            risk=RED, action="alert_owner", status="ALERTED",
            reason="Payments are RED: never changed automatically.",
            rollback="Nothing was changed.", evidence={"failed": failed, "total": len(payments)},
            result="Owner alerted; no automatic action.")
        try:
            from app.api.routes.command_center import command_center

            command_center(self.container).notify_once(f"selfheal:{item['id']}", "selfheal_critical",
                                                       item["issue"], str(item["id"]))
        except Exception:
            pass
        return [item]

    def _request_approval(self, item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        try:
            from app.api.routes.command_center import command_center

            cc = command_center(self.container)
            approval = cc.create_approval(
                action="selfheal.apply", target=f"selfheal:{item['id']}", risk=ORANGE, reason=item["reason"],
                old={"campaign": item["target"], "status": "ACTIVE"},
                proposed={"campaign": item["target"], "status": "PAUSED"},
                params={"log_id": item["id"], "needs": "selfheal:view"}, requested_by="selfheal",
                requested_role="system")
            cc.notify_once(f"approval:{approval['id']}", "approval", f"ORANGE approval needed: {item['issue']}",
                           str(approval["id"]))
            return approval
        except Exception:
            return None


def engine(container: Any) -> SelfHealingEngine:
    eng = getattr(container, "self_healing_engine", None)
    if eng is None or eng.db_path != container.settings.database_path:
        eng = SelfHealingEngine(container)
        container.self_healing_engine = eng
    return eng
