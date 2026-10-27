"""Admin AI incidents: grounded in recorded telemetry only, in English or
Telugu, in ONE format:

  Problem / Impact / Reason / Evidence / Solution / Action Status / Retest /
  AI Explanation

* Reason is CONFIRMED only when the evidence itself states the cause (e.g. a
  provider answered HTTP 402 -> credit / quota). Otherwise it says "Root
  cause not confirmed".
* Correlations between incidents are labelled POSSIBLE_CORRELATION -- never
  presented as a proven cause.
* The text is built from templates over the evidence (no free LLM text), so
  it cannot invent a number, a provider or a fix. No secret is read.
* Release readiness is never READY while real-device verification is
  missing.
* History: each incident key is kept with first / last seen and how often.
"""
from __future__ import annotations

import json
import sqlite3
import time
from contextlib import closing
from typing import Any

_LABELS = {
    "en": {"problem": "Problem", "impact": "Impact", "reason": "Reason", "evidence": "Evidence",
           "solution": "Solution", "action_status": "Action Status", "retest": "Retest",
           "ai_explanation": "AI Explanation", "not_confirmed": "Root cause not confirmed"},
    # "te" = the ONE mixed Telugu-English text the Command Center shows (owner rule 2026-10-27).
    "te": {"problem": "సమస్య", "impact": "Impact", "reason": "కారణం", "evidence": "Evidence",
           "solution": "పరిష్కారం", "action_status": "Action స్థితి", "retest": "మళ్ళీ Test",
           "ai_explanation": "AI వివరణ", "not_confirmed": "అసలు కారణం ఇంకా confirm కాలేదు"},
}

_FAILURE_TEXT = {
    "billing_quota": ("the provider refused for credit / quota", "Provider credit / quota అయిపోయిందని reject చేసింది",
                      "Recharge or raise the quota on the provider's dashboard (a person does this; ASKODOX never pays).",
                      "Provider dashboard లో recharge చేయండి / quota పెంచండి (మనిషే చేయాలి; ASKODOX ఎప్పుడూ pay చేయదు)."),
    "credential": ("the provider rejected the credentials", "Provider మన key (credentials) ని reject చేసింది",
                   "Replace the key in the deployment settings (owner only), then run Check now.",
                   "Deployment settings లో key మార్చండి (owner మాత్రమే), తర్వాత Check now నొక్కండి."),
    "rate_limit": ("the provider is rate limiting requests", "Provider మన requests ని limit చేస్తోంది",
                   "Wait for the window to reset; reduce repeated calls (cache) or raise the plan limit.",
                   "Window reset అయ్యే వరకు ఆగండి; repeat calls తగ్గించండి (cache) లేదా plan limit పెంచండి."),
    "downtime": ("the last real call failed", "చివరి real call fail అయింది",
                 "Re-check the provider; if it stays down, keep the fallback on and watch the provider's status page.",
                 "Provider ని మళ్ళీ check చేయండి; down లోనే ఉంటే fallback on గా ఉంచి provider status page చూడండి."),
}


_STATUS = {"en": ("proposed -- needs approval", "ready -- read-only check", "no automatic action"),
           "te": ("Propose చేశాం — approval కావాలి", "Ready — read-only check మాత్రమే", "Automatic action ఏమీ లేదు")}


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS admin_incident_history (
        incident_key TEXT PRIMARY KEY, title TEXT NOT NULL, severity TEXT NOT NULL, first_seen REAL NOT NULL,
        last_seen REAL NOT NULL, seen_count INTEGER NOT NULL, last_payload TEXT)""")
    return conn


def _incident(lang: str, key: str, severity: str, problem: str, impact: str, reason: str | None,
              evidence: list[str], solution: str, retest: str, action: str | None) -> dict[str, Any]:
    labels = _LABELS[lang]
    confirmed = reason is not None
    return {
        "key": key, "severity": severity,
        "problem": problem, "impact": impact,
        "reason": reason if confirmed else labels["not_confirmed"], "reason_confirmed": confirmed,
        "evidence": evidence, "solution": solution,
        "action_status": _STATUS[lang][0] if action and action.startswith("change:") else
                         (_STATUS[lang][1] if action else _STATUS[lang][2]),
        "proposed_action": action, "retest": retest,
        "labels": labels,
    }


def build(*, components: list[dict[str, Any]], billing_rows: list[dict[str, Any]],
          selfheal: list[dict[str, Any]], registry: list[dict[str, Any]], lang: str = "en") -> list[dict[str, Any]]:
    lang = "te" if lang == "te" else "en"
    te = lang == "te"
    out: list[dict[str, Any]] = []
    for row in billing_rows:
        kind = row.get("failure_type")
        if not kind:
            continue
        cause_en, cause_te, fix_en, fix_te = _FAILURE_TEXT[kind]
        code = row.get("http_status")
        evidence = [f"state={row['state']}" + (f", HTTP {code}" if code else ""),
                    f"last success: {(row.get('timestamps') or {}).get('last_success_at') or 'none recorded'}"]
        # A cause is CONFIRMED only from the provider's own answer.
        confirmed = kind in ("billing_quota", "credential", "rate_limit") and bool(code or row["state"])
        out.append(_incident(
            lang, f"provider:{row['provider']}:{kind}", "red" if kind in ("billing_quota", "credential") else "orange",
            (f"{row['label']}: {row['state']}" if not te else f"{row['label']}: {row['state']}"),
            ("Features using it fall back" + (f" to {row['fallback']}" if row.get("fallback") else " or fail")
             if not te else "దీన్ని వాడే features " + (f"{row['fallback']} కి మారతాయి" if row.get("fallback") else "fail అవుతాయి")),
            (cause_te if te else cause_en) if confirmed else None,
            evidence, fix_te if te else fix_en,
            "API Health & Billing -> Check alerts now; Integrations -> Check now" if not te else
            "API Health & Billing -> Check alerts now; Integrations -> Check now",
            f"read:recheck:{row['provider']}"))
    for comp in components:
        status = str(comp.get("status") or "")
        if status not in ("error", "degraded", "quota_exhausted"):
            continue
        out.append(_incident(
            lang, f"component:{comp['name']}:{status}", "red" if status == "error" else "orange",
            f"{comp['name']}: {status}", ("User-facing feature affected" if not te else "Customers వాడే feature మీద ప్రభావం ఉంది"),
            None, [str(comp.get("detail") or "")], (
                "Open the component's view, compare with provider incidents above, then retest."
                if not te else "ఆ component view open చేసి, పైన ఉన్న provider సమస్యలతో పోల్చి, మళ్ళీ test చేయండి."),
            "Command Center -> Health", None))
    for item in selfheal:
        verification = (item.get("verification") or {}).get("state") if isinstance(item.get("verification"), dict) \
            else item.get("verification")
        if item.get("status") == "PROPOSED" or verification == "NOT_RECOVERED":
            out.append(_incident(
                lang, f"selfheal:{item['id']}", "orange", str(item.get("issue") or "self-heal issue"),
                ("Waiting on a person" if not te else "మనిషి approval కోసం ఆగింది"), None,
                [f"status={item.get('status')}", f"recovery={verification or 'UNVERIFIED'}"],
                str(item.get("action") or ""), "Self-healing -> verification",
                f"change:selfheal_apply:{item['id']}" if item.get("status") == "PROPOSED" and
                item.get("risk") == "GREEN" else None))
    for feat in registry:
        if feat.get("state") in ("FAILED", "DEGRADED"):
            out.append(_incident(
                lang, f"feature:{feat['id']}:{feat['state']}", "red" if feat["state"] == "FAILED" else "orange",
                f"{feat['name']}: {feat['state']}", str(feat.get("expected_behavior") or "")[:160], None,
                [str(feat.get("why") or "")], ("Fix the failing health signal, then retest the feature."
                                              if not te else "Fail అవుతున్న health signal సరిచేసి, feature ని మళ్ళీ test చేయండి."),
                "Feature registry -> state", None))
    # Correlation: a degraded user-facing component next to a failing
    # provider is a POSSIBLE correlation, never a proven cause.
    providers = [i for i in out if i["key"].startswith("provider:")]
    for inc in out:
        if inc["key"].startswith(("component:", "feature:")) and providers:
            inc["correlation"] = {"label": "POSSIBLE_CORRELATION",
                                  "with": [p["key"] for p in providers]}
    for inc in out:
        inc["ai_explanation"] = _explain(inc, te)
    order = {"red": 0, "orange": 1}
    return sorted(out, key=lambda i: order.get(i["severity"], 2))


def _explain(inc: dict[str, Any], te: bool) -> str:
    if te:
        why = inc["reason"] if inc["reason_confirmed"] else "కారణం ఇంకా confirm కాలేదు"
        return f"{inc['problem']}. {why}. Evidence: {'; '.join(e for e in inc['evidence'] if e)}. తర్వాత: {inc['solution']}"
    why = f"Confirmed: {inc['reason']}" if inc["reason_confirmed"] else "The root cause is not confirmed yet"
    return f"{inc['problem']}. {why}. Evidence: {'; '.join(e for e in inc['evidence'] if e)}. Next: {inc['solution']}"


def release_readiness(incidents: list[dict[str, Any]]) -> dict[str, Any]:
    red = [i["key"] for i in incidents if i["severity"] == "red"]
    if red:
        return {"state": "NOT_READY", "why": "open red incidents", "blocking": red}
    return {"state": "NEEDS_DEVICE_VERIFICATION",
            "why": "no red incident in telemetry, but real-phone acceptance is not proven by the server",
            "blocking": []}


def remember(db_path: str, incidents: list[dict[str, Any]], *, now: float | None = None) -> None:
    now = now or time.time()
    with closing(_connect(db_path)) as conn:
        for inc in incidents:
            conn.execute(
                "INSERT INTO admin_incident_history(incident_key, title, severity, first_seen, last_seen, seen_count, "
                "last_payload) VALUES(?,?,?,?,?,1,?) ON CONFLICT(incident_key) DO UPDATE SET last_seen=excluded.last_seen,"
                " seen_count=seen_count+1, severity=excluded.severity, last_payload=excluded.last_payload",
                (inc["key"], inc["problem"], inc["severity"], now, now, json.dumps(inc)[:4000]))
        conn.commit()


def history(db_path: str, limit: int = 100) -> list[dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        return [{k: r[k] for k in r.keys() if k != "last_payload"} for r in conn.execute(
            "SELECT * FROM admin_incident_history ORDER BY last_seen DESC LIMIT ?", (limit,)).fetchall()]


INCIDENT_WORDS = ("incident", "problem", "issue", "down", "error", "failing", "health", "release", "status",
                  "ready", "సమస్య", "ఏమైంది", "పని చేయట్లేదు", "లోపం", "రిలీజ్")


def is_incident_question(question: str) -> bool:
    q = question.casefold()
    return any(w in q for w in INCIDENT_WORDS)
