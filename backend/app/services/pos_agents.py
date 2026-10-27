"""Role-based AI agents for a shop (owner, sales, support, finance, inventory, HR, tax) and a
personal buyer agent -- ON the existing POS permissions, audit and a human approval step.

* An agent is a ROLE VIEW, not a new power: it is offered only when the caller's POS role
  has the agent's permission, and every fact it reads goes through the same store method
  (and the same ``_require`` check) the app's own screens use.
* Answers are grounded: the facts come from the shop's records; the model (when one is
  configured) may only re-phrase those facts. Without a model the answer is the
  rule-based text. Nothing is invented.
* Actions: SAFE ones (a follow-up, a note, a lead stage) run at once as the caller.
  SENSITIVE ones (money received, stock change, closing a complaint, staff roles) are only
  PROPOSED; an owner / manager approves and the action then runs AS THE APPROVER (so the
  store's own permission check applies to the person who said yes). A manager cannot
  approve their own proposal; staff role changes need the owner. Every step is in
  ``pos_audit`` and ``pos_agent_actions``.
* Agents never move money, never message customers, never delete anything.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from datetime import timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_crm import PosCrm
from app.services.pos_store import IST, PosError, PosStore, _clean, _id

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_agent_actions (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, agent TEXT NOT NULL,"
    " action TEXT NOT NULL, risk TEXT NOT NULL, params TEXT NOT NULL, summary TEXT NOT NULL, status TEXT NOT NULL,"
    " proposed_by TEXT NOT NULL, proposed_at TEXT NOT NULL, decided_by TEXT, decided_at TEXT, result TEXT, error TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_agent_actions ON pos_agent_actions(business_id, status)",
]

# agent -> the POS permission it needs, its skills (read-only facts) and actions.
AGENTS: Dict[str, Dict[str, Any]] = {
    "owner": {"perm": "settings", "en": "Owner agent", "te": "Owner agent",
              "about_en": "The whole shop today: sales, dues, follow-ups, complaints, stock, approvals.",
              "about_te": "ఈరోజు shop మొత్తం: sales, బాకీలు, follow-ups, complaints, stock, approvals.",
              "skills": ["today_sales", "followups_due", "pipeline", "complaints_active", "dues", "low_stock",
                         "pending_approvals"],
              "actions": ["crm_followup", "crm_stage", "complaint_note", "complaint_resolve", "record_payment",
                          "stock_adjust", "set_member_role"]},
    "sales": {"perm": "crm", "en": "Sales agent", "te": "Sales agent",
              "about_en": "Your leads, follow-ups due, quotations and the pipeline.",
              "about_te": "మీ leads, చేయాల్సిన follow-ups, quotations, pipeline.",
              "skills": ["followups_due", "my_leads", "pipeline", "quotations"],
              "actions": ["crm_followup", "crm_stage"]},
    "support": {"perm": "crm", "en": "Support agent", "te": "Support agent",
                "about_en": "Open complaints by priority and their follow-ups.",
                "about_te": "Priority వారీగా open complaints, వాటి follow-ups.",
                "skills": ["complaints_active", "followups_due"],
                "actions": ["complaint_note", "complaint_resolve", "crm_followup"]},
    "finance": {"perm": "reports", "en": "Finance agent", "te": "Finance agent",
                "about_en": "Today's sales and payments by method, and who owes the shop.",
                "about_te": "ఈరోజు sales, payment method వారీగా డబ్బు, shop కి ఎవరు బాకీ.",
                "skills": ["today_sales", "dues"],
                "actions": ["record_payment"]},
    "inventory": {"perm": "stock", "en": "Inventory agent", "te": "Inventory agent",
                  "about_en": "Low stock and batches expiring soon.",
                  "about_te": "తక్కువ stock, త్వరలో expire అయ్యే batches.",
                  "skills": ["low_stock", "expiry"],
                  "actions": ["stock_adjust"]},
    "hr": {"perm": "members", "en": "HR agent", "te": "HR agent",
           "about_en": "Staff and their roles (phone numbers stay masked).",
           "about_te": "Staff, వాళ్ళ roles (phone numbers దాచి ఉంటాయి).",
           "skills": ["staff"],
           "actions": ["set_member_role"]},
    "tax": {"perm": "reports", "en": "Tax agent", "te": "Tax agent",
            "about_en": "This month's GST from issued bills, for your accountant to check.",
            "about_te": "ఈ నెల issue చేసిన bills నుండి GST — మీ accountant check చేయాలి.",
            "skills": ["gst_month"],
            "actions": []},
}

# action -> risk + the POS permission needed to PROPOSE it (approval needs owner / manager).
ACTIONS: Dict[str, Dict[str, Any]] = {
    "crm_followup": {"risk": "safe", "perm": "crm"},
    "crm_stage": {"risk": "safe", "perm": "crm"},
    "complaint_note": {"risk": "safe", "perm": "crm"},
    "complaint_resolve": {"risk": "sensitive", "perm": "crm"},
    "record_payment": {"risk": "sensitive", "perm": "reports"},
    "stock_adjust": {"risk": "sensitive", "perm": "stock"},
    "set_member_role": {"risk": "sensitive", "perm": "members", "owner_only": True},
}

# Words that point a question at a skill (en + te); no match -> all of the agent's skills.
_SKILL_WORDS = {
    "today_sales": ["sale", "sales", "today", "bill", "cash", "upi", "అమ్మకం", "ఈరోజు", "బిల్లు", "డబ్బు"],
    "followups_due": ["follow", "remind", "call", "ఫాలో", "గుర్తు", "కాల్"],
    "my_leads": ["lead", "enquir", "customer", "లీడ్", "ఎంక్వైరీ"],
    "pipeline": ["pipeline", "stage", "value", "won", "lost"],
    "quotations": ["quote", "quotation", "కొటేషన్"],
    "complaints_active": ["complain", "problem", "issue", "ఫిర్యాదు", "సమస్య"],
    "dues": ["due", "owe", "credit", "baki", "బాకీ", "అప్పు"],
    "low_stock": ["stock", "low", "reorder", "స్టాక్", "సరుకు"],
    "expiry": ["expir", "batch", "ఎక్స్‌పైరీ"],
    "staff": ["staff", "role", "member", "సిబ్బంది"],
    "gst_month": ["gst", "tax", "పన్ను", "జీఎస్టీ"],
    "pending_approvals": ["approv", "pending", "అనుమతి"],
}

MAX_PAYMENT_PAISE = 10_000_000  # Rs 1 lakh per agent-proposed payment record


def _short(value: Any) -> str:
    return hashlib.sha256(str(value).encode("utf-8")).hexdigest()[:8]


class PosAgents:
    def __init__(self, store: PosStore, crm: Optional[PosCrm] = None, purchases: Any = None) -> None:
        self.store = store
        self.crm = crm or PosCrm(store)
        self.purchases = purchases
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ----------------------------------------------------------- catalogue
    def _role(self, business_id: str, user: str) -> str:
        with self.store._connect() as conn:
            return self.store._require(conn, business_id, user, "view")

    def agents(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        """The agents this caller's role may use (an agent never adds a permission)."""
        from app.services.pos_store import PERMISSIONS

        role = self._role(business_id, user)
        perms = PERMISSIONS[role]
        out = []
        for key, a in AGENTS.items():
            if a["perm"] not in perms:
                continue
            out.append({"id": key, "name_en": a["en"], "name_te": a["te"], "about_en": a["about_en"],
                        "about_te": a["about_te"], "skills": a["skills"],
                        "actions": [{"id": x, "risk": ACTIONS[x]["risk"], "can_propose": ACTIONS[x]["perm"] in perms}
                                    for x in a["actions"]]})
        return out

    def _agent(self, business_id: str, user: str, agent: str) -> Dict[str, Any]:
        from app.services.pos_store import PERMISSIONS

        spec = AGENTS.get(agent)
        if spec is None:
            raise PosError(404, "agent", "Unknown agent.")
        role = self._role(business_id, user)
        if spec["perm"] not in PERMISSIONS[role]:
            raise PosError(403, "permission", f"Your role ({role}) cannot use the {agent} agent.", role=role)
        return spec

    # -------------------------------------------------------------- skills
    def _today(self) -> str:
        return self.store.clock().astimezone(IST).date().isoformat()

    def _skill(self, skill: str, business_id: str, user: str) -> Dict[str, Any]:
        fn: Dict[str, Callable[[], Dict[str, Any]]] = {
            "today_sales": lambda: self.store.day_summary(business_id, user, self._today()),
            "followups_due": lambda: {"followups": [
                {k: f.get(k) for k in ("id", "note", "due_at", "overdue", "lead_id", "lead_name", "customer_name",
                                       "complaint_id")} for f in self.crm.followups(business_id, user, when="due")][:15]},
            "my_leads": lambda: {"leads": [
                {k: x.get(k) for k in ("id", "name", "stage", "need", "value_paise")}
                for x in self.crm.leads(business_id, user, stage="open", mine=True)][:15]},
            "pipeline": lambda: {k: v for k, v in self.crm.pipeline(business_id, user).items() if k != "basis"},
            "quotations": lambda: {"quotations": [
                {k: q.get(k) for k in ("draft_id", "title", "status", "estimate_paise", "lead_name")}
                for q in self.crm.quotations(business_id, user)][:10]},
            "complaints_active": lambda: {"complaints": [
                {k: c.get(k) for k in ("id", "subject", "name", "priority", "status", "created_at")}
                for c in self.crm.complaints(business_id, user, status="active")][:15]},
            "dues": lambda: {"dues": self.crm.report(business_id, user, self._today(), self._today())["dues"]},
            "low_stock": lambda: {"low_stock": [
                {"id": p["id"], "name": p["name"], "unit": p["unit"], "stock_milli": p["stock_milli"],
                 "low_stock_milli": p["low_stock_milli"]}
                for p in self.store.products(business_id, user) if p.get("low_stock")][:20]},
            "expiry": lambda: {"expiring": self.store.expiry_report(business_id, user, 30)["items"][:20]},
            "staff": lambda: {"staff": self.store.members(business_id, user)},
            "gst_month": lambda: self.store.gst_summary(business_id, user, self._today()[:8] + "01", self._today()),
            "pending_approvals": lambda: {"pending": self.actions(business_id, user, status="PENDING_APPROVAL")[:10]},
        }
        return fn[skill]()

    def _pick(self, spec: Dict[str, Any], question: str) -> List[str]:
        text = (question or "").lower()
        picked = [s for s in spec["skills"] if any(w in text for w in _SKILL_WORDS.get(s, []))]
        return picked or list(spec["skills"])

    def facts(self, business_id: str, user: str, agent: str, question: str = "") -> Dict[str, Any]:
        spec = self._agent(business_id, user, agent)
        out: Dict[str, Any] = {}
        for skill in self._pick(spec, question):
            try:
                out[skill] = self._skill(skill, business_id, user)
            except PosError as error:  # this role cannot read that part: say so, never guess
                out[skill] = {"unavailable": error.message}
        return out

    # ------------------------------------------------- rule-based answer
    @staticmethod
    def _rs(paise: Any) -> str:
        return f"₹{int(paise or 0) / 100:,.2f}".replace(".00", "")

    def answer_lines(self, facts: Dict[str, Any], te: bool) -> List[str]:
        lines: List[str] = []
        t = (lambda en, tel: tel if te else en)
        for skill, data in facts.items():
            if "unavailable" in data:
                lines.append(t(f"{skill}: not allowed for your role.", f"{skill}: మీ role కి అనుమతి లేదు."))
                continue
            if skill == "today_sales":
                pay = ", ".join(f"{m} {self._rs(v['net_paise'])}" for m, v in (data.get("payments") or {}).items()) or "-"
                lines.append(t(f"Today: {data['invoices']} bills, sales {self._rs(data['sales_paise'])}; received {pay}.",
                               f"ఈరోజు: {data['invoices']} bills, sales {self._rs(data['sales_paise'])}; వచ్చింది {pay}."))
            elif skill == "followups_due":
                f = data["followups"]
                late = sum(1 for x in f if x.get("overdue"))
                lines.append(t(f"Follow-ups due: {len(f)} ({late} overdue).", f"చేయాల్సిన follow-ups: {len(f)} ({late} ఆలస్యం)."))
                lines += [f"• {x['note']} — {x.get('lead_name') or x.get('customer_name') or ''} ({str(x['due_at'])[:16]})"
                          for x in f[:5]]
            elif skill == "my_leads":
                lines.append(t(f"Your open leads: {len(data['leads'])}.", f"మీ open leads: {len(data['leads'])}."))
                lines += [f"• {x['name']} · {x['stage']} · {self._rs(x['value_paise'])}" for x in data["leads"][:5]]
            elif skill == "pipeline":
                open_n = sum(s["count"] for s in data["stages"] if s["stage"] not in ("won", "lost"))
                lines.append(t(f"Pipeline: {open_n} open leads worth {self._rs(data['open_value_paise'])} (your estimates).",
                               f"Pipeline: {open_n} open leads, విలువ {self._rs(data['open_value_paise'])} (మీ అంచనాలు)."))
            elif skill == "quotations":
                q = data["quotations"]
                waiting = sum(1 for x in q if x["status"] in ("draft", "sent"))
                lines.append(t(f"Quotations: {len(q)} recent, {waiting} waiting for an answer.",
                               f"Quotations: {len(q)} ఇటీవలివి, {waiting} జవాబు కోసం ఆగాయి."))
            elif skill == "complaints_active":
                c = data["complaints"]
                urgent = sum(1 for x in c if x["priority"] in ("urgent", "high"))
                lines.append(t(f"Open complaints: {len(c)} ({urgent} high / urgent).",
                               f"Open complaints: {len(c)} ({urgent} high / urgent)."))
                lines += [f"• {x['subject']} — {x['name']} ({x['priority']})" for x in c[:5]]
            elif skill == "dues":
                d = data["dues"]
                total = sum(int(x["due_paise"]) for x in d)
                lines.append(t(f"Top dues: {len(d)} customers, {self._rs(total)}.", f"ఎక్కువ బాకీలు: {len(d)} customers, {self._rs(total)}."))
                lines += [f"• {x['name']} {self._rs(x['due_paise'])}" for x in d[:5]]
            elif skill == "low_stock":
                s = data["low_stock"]
                lines.append(t(f"Low stock: {len(s)} items.", f"తక్కువ stock: {len(s)} items."))
                lines += [f"• {x['name']} ({(x['stock_milli'] or 0) / 1000:g} {x['unit']})" for x in s[:5]]
            elif skill == "expiry":
                e = data["expiring"]
                expired = sum(1 for x in e if x["expired"])
                lines.append(t(f"Batches expiring in 30 days: {len(e)} ({expired} already expired — never sold).",
                               f"30 రోజుల్లో expire అయ్యే batches: {len(e)} ({expired} ఇప్పటికే expire — అమ్మము)."))
            elif skill == "staff":
                lines.append(t(f"Staff: {len(data['staff'])} ({', '.join(s['role'] for s in data['staff'])}).",
                               f"Staff: {len(data['staff'])} ({', '.join(s['role'] for s in data['staff'])})."))
            elif skill == "gst_month":
                tot = data.get("totals") or data.get("summary") or {}
                tax = tot.get("tax_paise") if isinstance(tot, dict) else None
                lines.append(t("GST this month from issued bills" + (f": tax {self._rs(tax)}" if tax is not None else "")
                               + ". Check with your accountant before filing.",
                               "ఈ నెల issue చేసిన bills GST" + (f": tax {self._rs(tax)}" if tax is not None else "")
                               + ". File చేసే ముందు accountant తో check చేయండి."))
            elif skill == "pending_approvals":
                p = data["pending"]
                lines.append(t(f"Waiting for your approval: {len(p)}.", f"మీ approval కోసం ఆగినవి: {len(p)}."))
                lines += [f"• {x['summary']}" for x in p[:5]]
        return lines

    def ask(self, business_id: str, user: str, agent: str, question: str, *, te: bool = False,
            phrase: Optional[Callable[[str], str]] = None) -> Dict[str, Any]:
        facts = self.facts(business_id, user, agent, question)
        lines = self.answer_lines(facts, te)
        rules = "\n".join(lines)
        answer, source = rules, "rules"
        if phrase is not None and question.strip():
            prompt = ("You are the " + AGENTS[agent]["en"] + " of a small Indian shop. Answer the owner's question in 2-5 "
                      "short sentences using ONLY the facts below (amounts in rupees). If the facts do not answer it, say "
                      "so plainly. Never invent numbers, names or actions; never say you did something. No markdown.\n"
                      + ("Reply in simple Telugu mixed with English business words.\n" if te else "Reply in simple English.\n")
                      + "Facts:\n" + rules[:3500] + "\nQuestion: " + question[:500])
            try:
                text = (phrase(prompt) or "").strip()
            except Exception:
                text = ""
            if text:
                answer, source = text, "ai"
        return {"agent": agent, "answer": answer, "answer_source": source, "facts_text": lines, "facts": facts,
                "suggestions": self._suggest(agent, facts),
                "basis": "Read from this shop's records with your role's permission; the AI only re-words them."}

    def _suggest(self, agent: str, facts: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Ready-made proposals the person can tap (still subject to the approval rules)."""
        out: List[Dict[str, Any]] = []
        allowed = set(AGENTS[agent]["actions"])
        for f in (facts.get("followups_due") or {}).get("followups", [])[:3]:
            if f.get("overdue") and f.get("lead_id") and "crm_followup" in allowed:
                out.append({"action": "crm_followup", "label_en": f"Move '{f['note']}' to tomorrow",
                            "label_te": f"'{f['note']}' ని రేపటికి మార్చండి",
                            "params": {"lead_id": f["lead_id"], "due_at": "tomorrow", "note": f["note"]}})
        for c in (facts.get("complaints_active") or {}).get("complaints", [])[:3]:
            if "complaint_note" in allowed:
                out.append({"action": "complaint_note", "label_en": f"Add a note to '{c['subject']}'",
                            "label_te": f"'{c['subject']}' కి note రాయండి", "params": {"complaint_id": c["id"]}})
        return out

    # ------------------------------------------------------------- actions
    def _params(self, action: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Validate and keep only the fields each action uses."""
        p = dict(params or {})
        if action == "crm_followup":
            due = str(p.get("due_at") or "")
            if due == "tomorrow":
                due = (self.store.clock().astimezone(IST) + timedelta(days=1)).date().isoformat()
            if not (p.get("lead_id") or p.get("customer_id") or p.get("complaint_id")):
                raise PosError(400, "target", "Pick a lead, customer or complaint.")
            return {"lead_id": p.get("lead_id"), "customer_id": p.get("customer_id"),
                    "complaint_id": p.get("complaint_id"), "due_at": due, "note": _clean(p.get("note"), 240)}
        if action == "crm_stage":
            return {"lead_id": str(p.get("lead_id") or ""), "stage": str(p.get("stage") or ""),
                    "lost_reason": _clean(p.get("lost_reason"), 200)}
        if action == "complaint_note":
            return {"complaint_id": str(p.get("complaint_id") or ""), "text": _clean(p.get("text"), 500)}
        if action == "complaint_resolve":
            resolution = _clean(p.get("resolution"), 500)
            if not resolution:
                raise PosError(400, "resolution", "Write how it was solved.")
            return {"complaint_id": str(p.get("complaint_id") or ""), "resolution": resolution}
        if action == "record_payment":
            amount = int(p.get("amount_paise") or 0)
            if amount <= 0 or amount > MAX_PAYMENT_PAISE:
                raise PosError(400, "amount", "Amount must be between Re 0.01 and Rs 1 lakh.")
            return {"customer_id": str(p.get("customer_id") or ""), "amount_paise": amount,
                    "method": str(p.get("method") or ""), "reference": _clean(p.get("reference"), 60)}
        if action == "stock_adjust":
            reason = _clean(p.get("reason"), 160)
            if not reason:
                raise PosError(400, "reason", "Say why the stock changes.")
            kind = str(p.get("kind") or "adjustment")
            if kind not in ("adjustment", "count", "wastage"):
                raise PosError(400, "kind", "kind must be adjustment, count or wastage.")
            return {"product_id": str(p.get("product_id") or ""), "kind": kind, "qty_milli": int(p.get("qty_milli") or 0),
                    "reason": reason, "batch_no": _clean(p.get("batch_no"), 40) or None}
        if action == "set_member_role":
            phone = re.sub(r"\D", "", str(p.get("phone") or ""))
            if len(phone) < 10:
                raise PosError(400, "phone", "Give the staff member's 10-digit number.")
            return {"phone": phone, "role": str(p.get("role") or "")}
        raise PosError(404, "action", "Unknown action.")

    def _summary(self, action: str, p: Dict[str, Any]) -> str:
        return {
            "crm_followup": f"Follow-up on {p.get('due_at')}: {p.get('note')}",
            "crm_stage": f"Lead → {p.get('stage')}",
            "complaint_note": "Complaint note",
            "complaint_resolve": f"Close complaint: {p.get('resolution')}",
            "record_payment": f"Money received {self._rs(p.get('amount_paise'))} by {p.get('method')}",
            "stock_adjust": f"Stock {p.get('kind')} {int(p.get('qty_milli') or 0) / 1000:g}: {p.get('reason')}",
            "set_member_role": f"Staff …{str(p.get('phone'))[-4:]} → {p.get('role')}",
        }[action]

    def _execute(self, business_id: str, actor: str, action: str, p: Dict[str, Any], action_id: str) -> Dict[str, Any]:
        """Runs through the SAME store method the app uses, as ``actor`` (its permission check applies)."""
        if action == "crm_followup":
            return self.crm.add_followup(business_id, actor, p)
        if action == "crm_stage":
            return {"stage": self.crm.update_lead(business_id, actor, p["lead_id"], {
                "stage": p["stage"], "lost_reason": p.get("lost_reason")})["stage"]}
        if action == "complaint_note":
            return self.crm.add_activity(business_id, actor, {"complaint_id": p["complaint_id"], "kind": "note",
                                                              "text": p["text"]})
        if action == "complaint_resolve":
            return {"status": self.crm.update_complaint(business_id, actor, p["complaint_id"], {
                "status": "resolved", "resolution": p["resolution"]})["status"]}
        if action == "record_payment":
            out = self.store.collect(business_id, actor, p["customer_id"], {
                "method": p["method"], "amount_paise": p["amount_paise"], "reference": p.get("reference"),
                "client_txn_id": f"agent-{action_id}"})
            return {"payment_id": out["payment_id"], "balance_paise": out["balance_paise"]}
        if action == "stock_adjust":
            out = self.store.stock_move(business_id, actor, {**p, "client_txn_id": f"agent-{action_id}"})
            return {k: out.get(k) for k in ("move_id", "stock_milli", "replayed") if k in out}
        if action == "set_member_role":
            out = self.store.set_member(business_id, actor, p["phone"], p["role"])
            return {"role": out.get("role") if isinstance(out, dict) else p["role"]}
        raise PosError(404, "action", "Unknown action.")

    def propose(self, business_id: str, user: str, agent: str, action: str, params: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.pos_store import PERMISSIONS

        spec = self._agent(business_id, user, agent)
        if action not in spec["actions"] or action not in ACTIONS:
            raise PosError(400, "action", f"The {agent} agent does not do {action}.")
        rule = ACTIONS[action]
        role = self._role(business_id, user)
        if rule["perm"] not in PERMISSIONS[role]:
            raise PosError(403, "permission", f"Your role ({role}) cannot propose this.", role=role)
        p = self._params(action, params)
        action_id = _id("agt")
        now = self.store.clock().isoformat()
        summary = self._summary(action, p)
        status = "PENDING_APPROVAL" if rule["risk"] == "sensitive" else "RUNNING"
        with self.store._tx() as conn:
            conn.execute("INSERT INTO pos_agent_actions (id, business_id, agent, action, risk, params, summary, status,"
                         " proposed_by, proposed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (action_id, business_id, agent, action, rule["risk"], json.dumps(p), summary, status, user, now))
            self.store._audit(conn, business_id, user, "agent.propose", action_id,
                              {"agent": agent, "action": action, "risk": rule["risk"]}, now)
        if rule["risk"] == "safe":
            return self._run(business_id, user, action_id)
        return self.action(business_id, user, action_id)

    def _run(self, business_id: str, actor: str, action_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM pos_agent_actions WHERE id = ?", (action_id,)).fetchone()
        try:
            result = self._execute(business_id, actor, row["action"], json.loads(row["params"]), action_id)
            status, error = "DONE", None
        except PosError as failure:
            result, status, error = None, "FAILED", failure.message
        now = self.store.clock().isoformat()
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_agent_actions SET status = ?, result = ?, error = ? WHERE id = ?",
                         (status, json.dumps(result, default=str) if result is not None else None, error, action_id))
            self.store._audit(conn, business_id, actor, "agent.execute", action_id, {"status": status}, now)
        return self.action(business_id, actor, action_id)

    def decide(self, business_id: str, user: str, action_id: str, approve: bool, note: str = "") -> Dict[str, Any]:
        """Owner / manager approve or reject a sensitive proposal; approving runs it as the approver."""
        role = self._role(business_id, user)
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_agent_actions WHERE id = ? AND business_id = ?",
                               (action_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "action", "Agent action not found.")
            if row["status"] != "PENDING_APPROVAL":
                raise PosError(409, "status", "This action was already decided.")
            if role not in ("owner", "manager"):
                raise PosError(403, "permission", "Only the owner or a manager can approve agent actions.", role=role)
            if ACTIONS[row["action"]].get("owner_only") and role != "owner":
                raise PosError(403, "permission", "Only the owner can approve staff role changes.", role=role)
            if row["proposed_by"] == user and role != "owner":
                raise PosError(403, "four_eyes", "Someone else must approve what you proposed.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_agent_actions SET status = ?, decided_by = ?, decided_at = ?, error = ? WHERE id = ?",
                         ("APPROVED" if approve else "REJECTED", user, now, _clean(note, 200) or None, action_id))
            self.store._audit(conn, business_id, user, "agent.approve" if approve else "agent.reject", action_id,
                              {"action": row["action"]}, now)
        if approve:
            return self._run(business_id, user, action_id)
        return self.action(business_id, user, action_id)

    def _out(self, row: sqlite3.Row, user: str) -> Dict[str, Any]:
        item = dict(row)
        params = json.loads(item.pop("params"))
        if "phone" in params:
            params["phone"] = "…" + str(params["phone"])[-4:]
        item["params"] = params
        item["result"] = json.loads(item["result"]) if item.get("result") else None
        item["mine"] = item["proposed_by"] == user
        item["proposed_by"] = "…" + _short(item["proposed_by"])[-4:]
        item["decided_by"] = "…" + _short(item["decided_by"])[-4:] if item.get("decided_by") else None
        return item

    def action(self, business_id: str, user: str, action_id: str) -> Dict[str, Any]:
        self._role(business_id, user)
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM pos_agent_actions WHERE id = ? AND business_id = ?",
                               (action_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "action", "Agent action not found.")
        return self._out(row, user)

    def actions(self, business_id: str, user: str, *, status: str = "") -> List[Dict[str, Any]]:
        self._role(business_id, user)
        with self.store._connect() as conn:
            sql = "SELECT * FROM pos_agent_actions WHERE business_id = ?"
            args: List[Any] = [business_id]
            if status:
                sql += " AND status = ?"
                args.append(status)
            rows = conn.execute(sql + " ORDER BY proposed_at DESC LIMIT 100", args).fetchall()
        return [self._out(r, user) for r in rows]


# ------------------------------------------------------------- buyer agent
def buyer_facts(store: PosStore, user: str) -> Dict[str, Any]:
    """The personal buyer agent: only the caller's own records, through the same services the app uses."""
    from app.services.pos_advance import PosAdvances

    out: Dict[str, Any] = {}
    try:
        shops = PosAdvances(store).mine(user)["shops"]
        out["shop_advances_waiting"] = sum(len(s["pending"]) for s in shops)
        out["shop_advance_balance_paise"] = sum(int(s["balance_paise"]) for s in shops)
    except Exception:
        out["shop_advances_waiting"] = None  # unknown, never guessed
    try:
        with store._connect() as conn:
            out["payment_methods"] = int(conn.execute("SELECT COUNT(*) FROM user_payment_methods WHERE user_id = ?",
                                                      (user,)).fetchone()[0])
    except sqlite3.Error:
        out["payment_methods"] = None
    out["my_shops"] = len(store.my_businesses(user))
    return out


def buyer_answer(facts: Dict[str, Any], te: bool) -> List[str]:
    t = (lambda en, tel: tel if te else en)
    lines = []
    waiting = facts.get("shop_advances_waiting")
    if waiting is not None:
        lines.append(t(f"Shop advances waiting for your approval: {waiting} (Profile → Personal Finance → Shop advances).",
                       f"మీ approval కోసం ఆగిన shop advances: {waiting} (Profile → Personal Finance → Shop advances)."))
    methods = facts.get("payment_methods")
    if methods is not None:
        lines.append(t(f"Your saved ways to be paid: {methods}.", f"మీ payment methods: {methods}."))
    lines.append(t("Ask in ASKODOX chat to find or compare things to buy; I never pay or approve for you.",
                   "కొనాల్సినవి వెతకడానికి / పోల్చడానికి ASKODOX chat లో అడగండి; మీ తరఫున నేను pay / approve చేయను."))
    return lines


