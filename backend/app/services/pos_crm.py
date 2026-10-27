"""ASKODOX Business CRM -- leads, enquiries, quotations, follow-ups / reminders,
customer history, complaints, sales pipeline and reports, INSIDE My Business
on the ONE POS core (owner rule 2026-10-27: no duplicate modules).

Reused, never copied:
* customers  = ``pos_customers`` (a lead links to one, or "Customer గా save"
  creates it through ``PosStore.add_customer``);
* quotations = the sale screen's quotation drafts (``pos_drafts`` kind
  ``quotation``); CRM only adds the link to a lead + its status;
* invoices / payments / dues = ``pos_invoices`` / ``pos_payments`` /
  ``pos_ledger`` (read only here; a WON lead may point at a real invoice);
* staff = ``pos_members`` (assignees are members of this shop only);
* roles = ``PosStore._require`` with the ``crm`` permission; every change is in
  ``pos_audit`` and in the lead / complaint timeline (append-only activity).

Money stays with the shop: nothing here takes or holds a payment.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from app.services.pos_store import IST, PosError, PosStore, _clean, _id

SOURCES = ("walk_in", "phone_call", "whatsapp", "askodox", "referral", "online", "other")
KINDS = ("lead", "enquiry")
STAGES = ("new", "contacted", "quoted", "negotiation", "won", "lost")
OPEN_STAGES = ("new", "contacted", "quoted", "negotiation")
ACTIVITY_KINDS = ("note", "call", "visit", "message", "meeting")
QUOTE_STATUSES = ("draft", "sent", "accepted", "rejected", "expired", "billed")
COMPLAINT_STATUSES = ("open", "in_progress", "resolved", "closed")
PRIORITIES = ("low", "normal", "high", "urgent")
FOLLOWUP_STATUSES = ("open", "done", "skipped")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_crm_leads (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, kind TEXT NOT NULL,"
    " name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', customer_id TEXT, source TEXT NOT NULL, source_ref TEXT"
    " NOT NULL DEFAULT '', need TEXT NOT NULL DEFAULT '', value_paise INTEGER NOT NULL DEFAULT 0, stage TEXT NOT NULL,"
    " lost_reason TEXT NOT NULL DEFAULT '', won_invoice_id TEXT, assigned_to TEXT, created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL, closed_at TEXT, version INTEGER NOT NULL DEFAULT 1)",
    "CREATE INDEX IF NOT EXISTS idx_pos_crm_leads_biz ON pos_crm_leads(business_id, stage)",
    "CREATE INDEX IF NOT EXISTS idx_pos_crm_leads_cust ON pos_crm_leads(business_id, customer_id)",
    # Append-only timeline: never edited, never deleted.
    "CREATE TABLE IF NOT EXISTS pos_crm_activity (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,"
    " lead_id TEXT, customer_id TEXT, complaint_id TEXT, kind TEXT NOT NULL, text TEXT NOT NULL, by_user TEXT NOT NULL,"
    " at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_crm_activity ON pos_crm_activity(business_id, lead_id, customer_id)",
    "CREATE TABLE IF NOT EXISTS pos_crm_followups (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, lead_id TEXT,"
    " customer_id TEXT, complaint_id TEXT, due_utc TEXT NOT NULL, note TEXT NOT NULL, status TEXT NOT NULL,"
    " assigned_to TEXT, created_by TEXT NOT NULL, created_at TEXT NOT NULL, done_at TEXT, done_by TEXT,"
    " outcome TEXT NOT NULL DEFAULT '', reminded_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_crm_followups_due ON pos_crm_followups(status, due_utc)",
    # A quotation IS the sale screen's quotation draft; this row only links it to a lead and tracks its status.
    "CREATE TABLE IF NOT EXISTS pos_crm_quotes (draft_id TEXT PRIMARY KEY, business_id TEXT NOT NULL, lead_id TEXT,"
    " customer_id TEXT, status TEXT NOT NULL, estimate_paise INTEGER NOT NULL DEFAULT 0, valid_until TEXT,"
    " invoice_id TEXT, updated_by TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_crm_complaints (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, customer_id TEXT,"
    " name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', invoice_id TEXT, subject TEXT NOT NULL, detail TEXT NOT NULL"
    " DEFAULT '', priority TEXT NOT NULL, status TEXT NOT NULL, resolution TEXT NOT NULL DEFAULT '', assigned_to TEXT,"
    " created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, resolved_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_crm_complaints ON pos_crm_complaints(business_id, status)",
]

# Allowed stage moves. won / lost are final unless an owner / manager reopens the lead.
_NEXT = {
    "new": {"contacted", "quoted", "negotiation", "won", "lost"},
    "contacted": {"new", "quoted", "negotiation", "won", "lost"},
    "quoted": {"contacted", "negotiation", "won", "lost"},
    "negotiation": {"contacted", "quoted", "won", "lost"},
    "won": set(),
    "lost": set(),
}


def _now_utc(store: PosStore) -> datetime:
    now = store.clock()
    return now if now.tzinfo else now.replace(tzinfo=timezone.utc)


def parse_due(value: Any) -> datetime:
    """``YYYY-MM-DD`` (10:00 IST that day) or ``YYYY-MM-DDTHH:MM`` (IST unless it carries an offset)."""
    text = str(value or "").strip()
    if not text:
        raise PosError(400, "due_at", "Follow-up date is required.")
    try:
        if len(text) == 10:
            local = datetime.strptime(text, "%Y-%m-%d").replace(hour=10, tzinfo=IST)
        else:
            local = datetime.fromisoformat(text.replace("Z", "+00:00"))
            if local.tzinfo is None:
                local = local.replace(tzinfo=IST)
    except ValueError as error:
        raise PosError(400, "due_at", "Date must be YYYY-MM-DD or YYYY-MM-DDTHH:MM.") from error
    return local.astimezone(timezone.utc)


class PosCrm:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------- helpers
    def _staff_ref(self, business_id: str, key: str) -> str:
        return hashlib.sha256(f"{business_id}|{key}".encode("utf-8")).hexdigest()[:12]

    def _member_key(self, conn: sqlite3.Connection, business_id: str, user: str) -> str:
        row = conn.execute("SELECT phone_key FROM pos_members WHERE business_id = ? AND active = 1 AND app_user_id = ?",
                           (business_id, user)).fetchone()
        return row["phone_key"] if row else user

    def _assignee(self, conn: sqlite3.Connection, business_id: str, ref: Any, user: str) -> Optional[str]:
        """``me`` / a staff ref from ``staff()`` -> that member's phone key (members of THIS shop only)."""
        ref = str(ref or "").strip()
        if not ref:
            return None
        if ref == "me":
            return self._member_key(conn, business_id, user)
        for row in conn.execute("SELECT phone_key FROM pos_members WHERE business_id = ? AND active = 1", (business_id,)):
            if self._staff_ref(business_id, row["phone_key"]) == ref:
                return row["phone_key"]
        raise PosError(400, "assigned_to", "That person is not active staff of this shop.")

    def _who(self, business_id: str, key: Optional[str], me_key: str) -> Optional[Dict[str, Any]]:
        if not key:
            return None
        return {"ref": self._staff_ref(business_id, key), "last4": str(key)[-4:], "me": key == me_key}

    def _log(self, conn: sqlite3.Connection, business_id: str, user: str, kind: str, text: str, *,
             lead_id: Optional[str] = None, customer_id: Optional[str] = None, complaint_id: Optional[str] = None,
             at: Optional[str] = None) -> None:
        conn.execute("INSERT INTO pos_crm_activity (business_id, lead_id, customer_id, complaint_id, kind, text, by_user,"
                     " at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                     (business_id, lead_id, customer_id, complaint_id, kind, _clean(text, 500), user,
                      at or _now_utc(self.store).isoformat()))

    def _customer_ok(self, conn: sqlite3.Connection, business_id: str, customer_id: Any) -> Optional[str]:
        if not customer_id:
            return None
        row = conn.execute("SELECT id FROM pos_customers WHERE id = ? AND business_id = ?",
                           (str(customer_id), business_id)).fetchone()
        if row is None:
            raise PosError(404, "customer", "Customer not found.")
        return row["id"]

    def _invoice_ok(self, conn: sqlite3.Connection, business_id: str, invoice_id: Any) -> Optional[str]:
        if not invoice_id:
            return None
        row = conn.execute("SELECT id FROM pos_invoices WHERE id = ? AND business_id = ? AND doc_kind = 'invoice'",
                           (str(invoice_id), business_id)).fetchone()
        if row is None:
            raise PosError(404, "invoice", "Invoice not found in this shop.")
        return row["id"]

    def _lead_row(self, conn: sqlite3.Connection, business_id: str, lead_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_crm_leads WHERE id = ? AND business_id = ?", (lead_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "lead", "Lead not found.")
        return row

    def _lead_out(self, conn: sqlite3.Connection, row: sqlite3.Row, me_key: str) -> Dict[str, Any]:
        out = dict(row)
        out["assigned_to"] = self._who(row["business_id"], row["assigned_to"], me_key)
        out.pop("created_by", None)
        nxt = conn.execute("SELECT id, due_utc, note FROM pos_crm_followups WHERE business_id = ? AND lead_id = ? AND"
                           " status = 'open' ORDER BY due_utc LIMIT 1", (row["business_id"], row["id"])).fetchone()
        out["next_followup"] = self._due_out(dict(nxt)) if nxt else None
        return out

    def _due_out(self, row: Dict[str, Any]) -> Dict[str, Any]:
        due = datetime.fromisoformat(row.pop("due_utc"))
        row["due_at"] = due.astimezone(IST).isoformat(timespec="minutes")
        row["overdue"] = row.get("status", "open") == "open" and due < _now_utc(self.store)
        return row

    # --------------------------------------------------------------- staff
    def staff(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        """Who a lead / follow-up / complaint can be given to: this shop's active staff (masked)."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            rows = conn.execute("SELECT phone_key, role FROM pos_members WHERE business_id = ? AND active = 1 ORDER BY"
                                " created_at", (business_id,)).fetchall()
        return [{**self._who(business_id, r["phone_key"], me), "role": r["role"]} for r in rows]

    # --------------------------------------------------------------- leads
    def add_lead(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("kind") or "lead")
        source = str(data.get("source") or "walk_in")
        if kind not in KINDS:
            raise PosError(400, "kind", "kind must be lead or enquiry.")
        if source not in SOURCES:
            raise PosError(400, "source", "Unknown source.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            customer_id = self._customer_ok(conn, business_id, data.get("customer_id"))
            name = _clean(data.get("name"), 80)
            phone = _clean(data.get("phone"), 20)
            if customer_id and not name:
                cust = conn.execute("SELECT name, phone FROM pos_customers WHERE id = ?", (customer_id,)).fetchone()
                name, phone = cust["name"], phone or cust["phone"]
            if not name:
                raise PosError(400, "name", "Name is required.")
            source_ref = _clean(data.get("source_ref"), 80)
            if source_ref:
                dup = conn.execute("SELECT id FROM pos_crm_leads WHERE business_id = ? AND source = ? AND source_ref = ?",
                                   (business_id, source, source_ref)).fetchone()
                if dup:  # the same ASKODOX request saved twice -> the existing lead
                    me = self._member_key(conn, business_id, user)
                    return self._lead_out(conn, self._lead_row(conn, business_id, dup["id"]), me)
            now = _now_utc(self.store).isoformat()
            lead_id = _id("lead")
            assigned = self._assignee(conn, business_id, data.get("assigned_to") or "me", user)
            conn.execute("INSERT INTO pos_crm_leads (id, business_id, kind, name, phone, customer_id, source, source_ref,"
                         " need, value_paise, stage, assigned_to, created_by, created_at, updated_at) VALUES"
                         " (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, ?)",
                         (lead_id, business_id, kind, name, phone, customer_id, source, source_ref,
                          _clean(data.get("need"), 500), max(0, int(data.get("value_paise") or 0)), assigned, user, now,
                          now))
            self._log(conn, business_id, user, "created", f"{kind} · {source}", lead_id=lead_id, customer_id=customer_id,
                      at=now)
            self.store._audit(conn, business_id, user, "crm.lead.add", lead_id, {"kind": kind, "source": source}, now)
            if data.get("followup_at"):
                self._add_followup(conn, business_id, user, {"lead_id": lead_id, "due_at": data["followup_at"],
                                                             "note": data.get("followup_note") or "Follow-up"})
            me = self._member_key(conn, business_id, user)
            return self._lead_out(conn, self._lead_row(conn, business_id, lead_id), me)

    def leads(self, business_id: str, user: str, *, stage: str = "", kind: str = "", q: str = "",
              mine: bool = False, customer_id: str = "") -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            sql = "SELECT * FROM pos_crm_leads WHERE business_id = ?"
            args: List[Any] = [business_id]
            if stage == "open":
                sql += " AND stage IN ('new', 'contacted', 'quoted', 'negotiation')"
            elif stage:
                sql += " AND stage = ?"
                args.append(stage)
            if kind:
                sql += " AND kind = ?"
                args.append(kind)
            if customer_id:
                sql += " AND customer_id = ?"
                args.append(customer_id)
            if mine:
                sql += " AND assigned_to = ?"
                args.append(me)
            text = _clean(q, 60)
            if text:
                sql += " AND (name LIKE ? OR phone LIKE ? OR need LIKE ?)"
                args += [f"%{text}%"] * 3
            rows = conn.execute(sql + " ORDER BY updated_at DESC LIMIT 300", args).fetchall()
            return [self._lead_out(conn, r, me) for r in rows]

    def lead(self, business_id: str, user: str, lead_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            out = self._lead_out(conn, self._lead_row(conn, business_id, lead_id), me)
            out["timeline"] = self._timeline(conn, business_id, "lead_id", lead_id, me)
            out["followups"] = [self._due_out(dict(r)) for r in conn.execute(
                "SELECT id, due_utc, note, status, outcome, done_at FROM pos_crm_followups WHERE business_id = ? AND"
                " lead_id = ? ORDER BY due_utc", (business_id, lead_id))]
            out["quotations"] = self._quotes(conn, business_id, "lead_id", lead_id)
            return out

    def update_lead(self, business_id: str, user: str, lead_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "crm")
            row = self._lead_row(conn, business_id, lead_id)
            if data.get("version") is not None and int(data["version"]) != row["version"]:
                raise PosError(409, "version", "Someone else changed this lead. Reload and try again.")
            now = _now_utc(self.store).isoformat()
            fields: Dict[str, Any] = {}
            notes: List[str] = []
            for key, limit in (("name", 80), ("phone", 20), ("need", 500)):
                if key in data and data[key] is not None:
                    fields[key] = _clean(data[key], limit)
            if fields.get("name") == "":
                raise PosError(400, "name", "Name is required.")
            if data.get("value_paise") is not None:
                fields["value_paise"] = max(0, int(data["value_paise"]))
            if "assigned_to" in data:
                fields["assigned_to"] = self._assignee(conn, business_id, data["assigned_to"], user)
                notes.append("assigned")
            if "customer_id" in data:
                fields["customer_id"] = self._customer_ok(conn, business_id, data["customer_id"])
            stage = data.get("stage")
            if stage and stage != row["stage"]:
                if stage not in STAGES:
                    raise PosError(400, "stage", "Unknown stage.")
                reopen = row["stage"] in ("won", "lost")
                if reopen:
                    if role not in ("owner", "manager"):
                        raise PosError(403, "permission", "Only the owner or a manager can reopen a closed lead.")
                    if stage not in OPEN_STAGES:
                        raise PosError(400, "stage", "A reopened lead goes back to an open stage.")
                elif stage not in _NEXT[row["stage"]]:
                    raise PosError(409, "stage", f"Cannot move from {row['stage']} to {stage}.")
                fields["stage"] = stage
                if stage == "lost":
                    reason = _clean(data.get("lost_reason"), 200)
                    if not reason:
                        raise PosError(400, "lost_reason", "Write why the lead was lost.")
                    fields["lost_reason"] = reason
                if stage == "won":
                    fields["won_invoice_id"] = self._invoice_ok(conn, business_id, data.get("won_invoice_id"))
                fields["closed_at"] = now if stage in ("won", "lost") else None
                notes.append(f"{row['stage']} → {stage}" + (" (reopened)" if reopen else ""))
            if not fields:
                return self.lead(business_id, user, lead_id)
            fields["updated_at"] = now
            sets = ", ".join(f"{k} = ?" for k in fields)
            conn.execute(f"UPDATE pos_crm_leads SET {sets}, version = version + 1 WHERE id = ? AND business_id = ?",
                         (*fields.values(), lead_id, business_id))
            text = "; ".join(notes) or "details updated"
            self._log(conn, business_id, user, "stage" if stage and stage != row["stage"] else "update", text,
                      lead_id=lead_id, customer_id=fields.get("customer_id", row["customer_id"]), at=now)
            self.store._audit(conn, business_id, user, "crm.lead.update", lead_id,
                              {k: (v if k in ("stage", "value_paise") else True) for k, v in fields.items()
                               if k != "updated_at"}, now)
        return self.lead(business_id, user, lead_id)

    def lead_to_customer(self, business_id: str, user: str, lead_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Save the lead as a POS customer (the ONE customer list) and link it."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            row = self._lead_row(conn, business_id, lead_id)
        if row["customer_id"]:
            return self.lead(business_id, user, lead_id)
        customer = self.store.add_customer(business_id, user, {
            "name": data.get("name") or row["name"], "phone": data.get("phone") or row["phone"],
            "address": data.get("address") or "", "gstin": data.get("gstin"), "state_code": data.get("state_code")})
        return self.update_lead(business_id, user, lead_id, {"customer_id": customer["id"]})

    def add_activity(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("kind") or "note")
        if kind not in ACTIVITY_KINDS:
            raise PosError(400, "kind", "kind must be note, call, visit, message or meeting.")
        text = _clean(data.get("text"), 500)
        if not text:
            raise PosError(400, "text", "Write what happened.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            lead_id = complaint_id = None
            customer_id = self._customer_ok(conn, business_id, data.get("customer_id"))
            if data.get("lead_id"):
                lead = self._lead_row(conn, business_id, str(data["lead_id"]))
                lead_id, customer_id = lead["id"], customer_id or lead["customer_id"]
                conn.execute("UPDATE pos_crm_leads SET updated_at = ? WHERE id = ?",
                             (_now_utc(self.store).isoformat(), lead_id))
            if data.get("complaint_id"):
                comp = self._complaint_row(conn, business_id, str(data["complaint_id"]))
                complaint_id, customer_id = comp["id"], customer_id or comp["customer_id"]
            if not (lead_id or customer_id or complaint_id):
                raise PosError(400, "target", "Pick a lead, customer or complaint.")
            self._log(conn, business_id, user, kind, text, lead_id=lead_id, customer_id=customer_id,
                      complaint_id=complaint_id)
        return {"ok": True}

    def _timeline(self, conn: sqlite3.Connection, business_id: str, column: str, value: str,
                  me_key: str) -> List[Dict[str, Any]]:
        rows = conn.execute(f"SELECT kind, text, by_user, at FROM pos_crm_activity WHERE business_id = ? AND {column} = ?"
                            " ORDER BY id DESC LIMIT 200", (business_id, value)).fetchall()
        out = []
        for r in rows:
            key = self._member_key(conn, business_id, r["by_user"])
            out.append({"kind": r["kind"], "text": r["text"], "at": r["at"], "by": self._who(business_id, key, me_key)})
        return out

    # ----------------------------------------------------------- follow-ups
    def _add_followup(self, conn: sqlite3.Connection, business_id: str, user: str, data: Dict[str, Any]) -> str:
        due = parse_due(data.get("due_at"))
        note = _clean(data.get("note"), 240)
        if not note:
            raise PosError(400, "note", "Write what to do on the follow-up.")
        lead_id = customer_id = complaint_id = None
        assigned = None
        if data.get("lead_id"):
            lead = self._lead_row(conn, business_id, str(data["lead_id"]))
            lead_id, customer_id, assigned = lead["id"], lead["customer_id"], lead["assigned_to"]
        if data.get("complaint_id"):
            comp = self._complaint_row(conn, business_id, str(data["complaint_id"]))
            complaint_id, customer_id, assigned = comp["id"], comp["customer_id"], assigned or comp["assigned_to"]
        if data.get("customer_id"):
            customer_id = self._customer_ok(conn, business_id, data["customer_id"])
        if not (lead_id or customer_id or complaint_id):
            raise PosError(400, "target", "Pick a lead, customer or complaint for the follow-up.")
        if data.get("assigned_to"):
            assigned = self._assignee(conn, business_id, data["assigned_to"], user)
        assigned = assigned or self._member_key(conn, business_id, user)
        followup_id = _id("fup")
        now = _now_utc(self.store).isoformat()
        conn.execute("INSERT INTO pos_crm_followups (id, business_id, lead_id, customer_id, complaint_id, due_utc, note,"
                     " status, assigned_to, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)",
                     (followup_id, business_id, lead_id, customer_id, complaint_id, due.isoformat(), note, assigned, user,
                      now))
        self._log(conn, business_id, user, "followup", f"Follow-up {due.astimezone(IST):%d %b %H:%M}: {note}",
                  lead_id=lead_id, customer_id=customer_id, complaint_id=complaint_id, at=now)
        return followup_id

    def add_followup(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            followup_id = self._add_followup(conn, business_id, user, data)
            self.store._audit(conn, business_id, user, "crm.followup.add", followup_id, {}, _now_utc(self.store).isoformat())
        return {"id": followup_id}

    def followups(self, business_id: str, user: str, *, when: str = "due", mine: bool = False) -> List[Dict[str, Any]]:
        """when = due (overdue + today) | upcoming | done | all."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            now = _now_utc(self.store)
            end_today = datetime.combine(now.astimezone(IST).date(), datetime.max.time(), IST).astimezone(timezone.utc)
            sql = ("SELECT f.*, l.name AS lead_name, c.name AS customer_name, k.subject AS complaint_subject FROM"
                   " pos_crm_followups f LEFT JOIN pos_crm_leads l ON l.id = f.lead_id LEFT JOIN pos_customers c ON"
                   " c.id = f.customer_id LEFT JOIN pos_crm_complaints k ON k.id = f.complaint_id WHERE f.business_id = ?")
            args: List[Any] = [business_id]
            if when == "due":
                sql += " AND f.status = 'open' AND f.due_utc <= ?"
                args.append(end_today.isoformat())
            elif when == "upcoming":
                sql += " AND f.status = 'open' AND f.due_utc > ?"
                args.append(end_today.isoformat())
            elif when == "done":
                sql += " AND f.status != 'open'"
            if mine:
                sql += " AND f.assigned_to = ?"
                args.append(me)
            rows = conn.execute(sql + " ORDER BY f.due_utc LIMIT 300", args).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            item["assigned_to"] = self._who(business_id, item["assigned_to"], me)
            for k in ("created_by", "done_by", "reminded_at"):
                item.pop(k, None)
            out.append(self._due_out(item))
        return out

    def close_followup(self, business_id: str, user: str, followup_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        status = str(data.get("status") or "done")
        if status not in ("done", "skipped"):
            raise PosError(400, "status", "status must be done or skipped.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            row = conn.execute("SELECT * FROM pos_crm_followups WHERE id = ? AND business_id = ?",
                               (followup_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "followup", "Follow-up not found.")
            if row["status"] != "open":
                raise PosError(409, "status", "This follow-up is already closed.")
            now = _now_utc(self.store).isoformat()
            outcome = _clean(data.get("outcome"), 240)
            conn.execute("UPDATE pos_crm_followups SET status = ?, done_at = ?, done_by = ?, outcome = ? WHERE id = ?",
                         (status, now, user, outcome, followup_id))
            self._log(conn, business_id, user, "followup_" + status, outcome or row["note"], lead_id=row["lead_id"],
                      customer_id=row["customer_id"], complaint_id=row["complaint_id"], at=now)
            if data.get("next_at"):
                self._add_followup(conn, business_id, user, {"lead_id": row["lead_id"], "customer_id": row["customer_id"],
                                                             "complaint_id": row["complaint_id"], "due_at": data["next_at"],
                                                             "note": data.get("next_note") or row["note"]})
        return {"ok": True}

    def due_reminders(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Open follow-ups whose time has come and that were never reminded (all shops) -- for the push job."""
        now = _now_utc(self.store).isoformat()
        with self.store._tx() as conn:
            rows = conn.execute(
                "SELECT f.id, f.business_id, f.note, f.assigned_to, m.app_user_id FROM pos_crm_followups f LEFT JOIN"
                " pos_members m ON m.business_id = f.business_id AND m.phone_key = f.assigned_to AND m.active = 1 WHERE"
                " f.status = 'open' AND f.reminded_at IS NULL AND f.due_utc <= ? ORDER BY f.due_utc LIMIT ?",
                (now, limit)).fetchall()
            for r in rows:
                conn.execute("UPDATE pos_crm_followups SET reminded_at = ? WHERE id = ?", (now, r["id"]))
        return [dict(r) for r in rows]

    # ----------------------------------------------------------- quotations
    def _quotes(self, conn: sqlite3.Connection, business_id: str, column: str, value: str) -> List[Dict[str, Any]]:
        rows = conn.execute(f"SELECT q.*, d.title, d.created_at AS made_at FROM pos_crm_quotes q LEFT JOIN pos_drafts d ON"
                            f" d.id = q.draft_id WHERE q.business_id = ? AND q.{column} = ? ORDER BY q.updated_at DESC",
                            (business_id, value)).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            item.pop("updated_by", None)
            item["draft_exists"] = item.get("title") is not None
            out.append(item)
        return out

    def link_quote(self, business_id: str, user: str, draft_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Link a quotation (made on the sale screen) to a lead / customer, and track its status."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            draft = conn.execute("SELECT * FROM pos_drafts WHERE id = ? AND business_id = ? AND kind = 'quotation'",
                                 (draft_id, business_id)).fetchone()
            existing = conn.execute("SELECT * FROM pos_crm_quotes WHERE draft_id = ? AND business_id = ?",
                                    (draft_id, business_id)).fetchone()
            if draft is None and existing is None:
                raise PosError(404, "quotation", "Quotation not found. Make it on the sale screen first.")
            payload = json.loads(draft["payload"]) if draft else {}
            lead_id = existing["lead_id"] if existing else None
            if data.get("lead_id"):
                lead_id = self._lead_row(conn, business_id, str(data["lead_id"]))["id"]
            customer_id = self._customer_ok(conn, business_id, data.get("customer_id") or payload.get("customer_id")
                                            or (existing["customer_id"] if existing else None))
            status = str(data.get("status") or (existing["status"] if existing else "draft"))
            if status not in QUOTE_STATUSES:
                raise PosError(400, "status", "Unknown quotation status.")
            estimate = data.get("estimate_paise", payload.get("estimate_paise",
                                                              existing["estimate_paise"] if existing else 0))
            invoice_id = self._invoice_ok(conn, business_id, data.get("invoice_id")) if data.get("invoice_id") else (
                existing["invoice_id"] if existing else None)
            if status == "billed" and not invoice_id:
                raise PosError(400, "invoice_id", "Pick the bill this quotation became.")
            valid_until = _clean(data.get("valid_until"), 10) or (existing["valid_until"] if existing else None)
            now = _now_utc(self.store).isoformat()
            conn.execute("INSERT INTO pos_crm_quotes (draft_id, business_id, lead_id, customer_id, status, estimate_paise,"
                         " valid_until, invoice_id, updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                         " ON CONFLICT(draft_id) DO UPDATE SET lead_id = excluded.lead_id, customer_id ="
                         " excluded.customer_id, status = excluded.status, estimate_paise = excluded.estimate_paise,"
                         " valid_until = excluded.valid_until, invoice_id = excluded.invoice_id, updated_by ="
                         " excluded.updated_by, updated_at = excluded.updated_at",
                         (draft_id, business_id, lead_id, customer_id, status, max(0, int(estimate or 0)), valid_until,
                          invoice_id, user, now))
            changed = existing is None or existing["status"] != status
            if changed:
                self._log(conn, business_id, user, "quotation", f"Quotation {status}", lead_id=lead_id,
                          customer_id=customer_id, at=now)
            if lead_id:
                lead = self._lead_row(conn, business_id, lead_id)
                if lead["stage"] in ("new", "contacted") and status in ("draft", "sent"):
                    conn.execute("UPDATE pos_crm_leads SET stage = 'quoted', updated_at = ?, version = version + 1"
                                 " WHERE id = ?", (now, lead_id))
                    self._log(conn, business_id, user, "stage", f"{lead['stage']} → quoted", lead_id=lead_id,
                              customer_id=customer_id, at=now)
                if not lead["value_paise"] and estimate:
                    conn.execute("UPDATE pos_crm_leads SET value_paise = ? WHERE id = ?", (int(estimate), lead_id))
            self.store._audit(conn, business_id, user, "crm.quote", draft_id, {"status": status}, now)
            return dict(conn.execute("SELECT * FROM pos_crm_quotes WHERE draft_id = ?", (draft_id,)).fetchone())

    def quotations(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        """Every quotation draft of the shop with its CRM status (unlinked ones show as draft)."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            rows = conn.execute(
                "SELECT d.id AS draft_id, d.title, d.created_at AS made_at, d.payload, q.lead_id, q.customer_id, q.status,"
                " q.estimate_paise, q.valid_until, q.invoice_id, l.name AS lead_name FROM pos_drafts d LEFT JOIN"
                " pos_crm_quotes q ON q.draft_id = d.id LEFT JOIN pos_crm_leads l ON l.id = q.lead_id WHERE d.business_id"
                " = ? AND d.kind = 'quotation' ORDER BY d.updated_at DESC LIMIT 300", (business_id,)).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            payload = json.loads(item.pop("payload") or "{}")
            item["status"] = item["status"] or "draft"
            item["customer_id"] = item["customer_id"] or payload.get("customer_id")
            item["estimate_paise"] = item["estimate_paise"] or int(payload.get("estimate_paise") or 0)
            item["lines"] = len(payload.get("lines") or [])
            out.append(item)
        return out

    # ------------------------------------------------------------ complaints
    def _complaint_row(self, conn: sqlite3.Connection, business_id: str, complaint_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_crm_complaints WHERE id = ? AND business_id = ?",
                           (complaint_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "complaint", "Complaint not found.")
        return row

    def add_complaint(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        priority = str(data.get("priority") or "normal")
        if priority not in PRIORITIES:
            raise PosError(400, "priority", "Unknown priority.")
        subject = _clean(data.get("subject"), 120)
        if not subject:
            raise PosError(400, "subject", "Write the complaint in one line.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            customer_id = self._customer_ok(conn, business_id, data.get("customer_id"))
            name = _clean(data.get("name"), 80)
            phone = _clean(data.get("phone"), 20)
            if customer_id:
                cust = conn.execute("SELECT name, phone FROM pos_customers WHERE id = ?", (customer_id,)).fetchone()
                name, phone = name or cust["name"], phone or cust["phone"]
            if not name:
                raise PosError(400, "name", "Customer name is required.")
            invoice_id = self._invoice_ok(conn, business_id, data.get("invoice_id"))
            now = _now_utc(self.store).isoformat()
            complaint_id = _id("cmp")
            conn.execute("INSERT INTO pos_crm_complaints (id, business_id, customer_id, name, phone, invoice_id, subject,"
                         " detail, priority, status, assigned_to, created_by, created_at, updated_at) VALUES"
                         " (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)",
                         (complaint_id, business_id, customer_id, name, phone, invoice_id, subject,
                          _clean(data.get("detail"), 1000), priority,
                          self._assignee(conn, business_id, data.get("assigned_to") or "me", user), user, now, now))
            self._log(conn, business_id, user, "complaint", f"Complaint: {subject}", customer_id=customer_id,
                      complaint_id=complaint_id, at=now)
            self.store._audit(conn, business_id, user, "crm.complaint.add", complaint_id, {"priority": priority}, now)
        return self.complaint(business_id, user, complaint_id)

    def complaints(self, business_id: str, user: str, *, status: str = "", customer_id: str = "") -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            sql = "SELECT * FROM pos_crm_complaints WHERE business_id = ?"
            args: List[Any] = [business_id]
            if status == "active":
                sql += " AND status IN ('open', 'in_progress')"
            elif status:
                sql += " AND status = ?"
                args.append(status)
            if customer_id:
                sql += " AND customer_id = ?"
                args.append(customer_id)
            rows = conn.execute(sql + " ORDER BY CASE priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2"
                                " ELSE 3 END, created_at DESC LIMIT 300", args).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            item.pop("created_by", None)
            item["assigned_to"] = self._who(business_id, item["assigned_to"], me)
            out.append(item)
        return out

    def complaint(self, business_id: str, user: str, complaint_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            item = dict(self._complaint_row(conn, business_id, complaint_id))
            item.pop("created_by", None)
            item["assigned_to"] = self._who(business_id, item["assigned_to"], me)
            item["timeline"] = self._timeline(conn, business_id, "complaint_id", complaint_id, me)
            return item

    def update_complaint(self, business_id: str, user: str, complaint_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "crm")
            row = self._complaint_row(conn, business_id, complaint_id)
            now = _now_utc(self.store).isoformat()
            fields: Dict[str, Any] = {}
            status = data.get("status")
            if status and status != row["status"]:
                if status not in COMPLAINT_STATUSES:
                    raise PosError(400, "status", "Unknown status.")
                if status in ("resolved", "closed"):
                    resolution = _clean(data.get("resolution"), 500) or row["resolution"]
                    if not resolution:
                        raise PosError(400, "resolution", "Write how it was solved before closing.")
                    fields["resolution"] = resolution
                    fields["resolved_at"] = row["resolved_at"] or now
                else:
                    fields["resolved_at"] = None  # reopened
                fields["status"] = status
            if data.get("priority"):
                if data["priority"] not in PRIORITIES:
                    raise PosError(400, "priority", "Unknown priority.")
                fields["priority"] = data["priority"]
            if "assigned_to" in data:
                fields["assigned_to"] = self._assignee(conn, business_id, data["assigned_to"], user)
            if not fields:
                return self.complaint(business_id, user, complaint_id)
            fields["updated_at"] = now
            sets = ", ".join(f"{k} = ?" for k in fields)
            conn.execute(f"UPDATE pos_crm_complaints SET {sets} WHERE id = ?", (*fields.values(), complaint_id))
            text = f"{row['status']} → {status}" if "status" in fields else "updated"
            if fields.get("resolution") and "status" in fields:
                text += f": {fields['resolution']}"
            self._log(conn, business_id, user, "complaint", text, customer_id=row["customer_id"],
                      complaint_id=complaint_id, at=now)
            self.store._audit(conn, business_id, user, "crm.complaint.update", complaint_id,
                              {"status": fields.get("status"), "priority": fields.get("priority")}, now)
        return self.complaint(business_id, user, complaint_id)

    # ------------------------------------------------------ customer history
    def customer_history(self, business_id: str, user: str, customer_id: str) -> Dict[str, Any]:
        """One customer, everything the shop recorded: bills, payments, dues, leads, quotations, complaints, notes."""
        customer = self.store.customer(business_id, user, customer_id)  # also checks membership
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            invoices = []
            for r in conn.execute("SELECT id, doc_kind, number, local_date, totals, status, balance_paise FROM pos_invoices"
                                  " WHERE business_id = ? AND customer_id = ? ORDER BY issued_at DESC LIMIT 100",
                                  (business_id, customer_id)):
                item = dict(r)
                item["total_paise"] = int(json.loads(item.pop("totals") or "{}").get("grand_total_paise") or 0)
                invoices.append(item)
            payments = [dict(r) for r in conn.execute(
                "SELECT id, method, amount_paise, verification, kind, local_date FROM pos_payments WHERE business_id = ?"
                " AND customer_id = ? ORDER BY at DESC LIMIT 100", (business_id, customer_id))]
            billed = sum(i["total_paise"] for i in invoices if i["doc_kind"] == "invoice" and i["status"] == "issued")
            returned = sum(i["total_paise"] for i in invoices if i["doc_kind"] != "invoice" and i["status"] == "issued")
            leads = [self._lead_out(conn, r, me) for r in conn.execute(
                "SELECT * FROM pos_crm_leads WHERE business_id = ? AND customer_id = ? ORDER BY updated_at DESC",
                (business_id, customer_id))]
            complaints = [dict(r) for r in conn.execute(
                "SELECT id, subject, priority, status, created_at, resolved_at FROM pos_crm_complaints WHERE business_id"
                " = ? AND customer_id = ? ORDER BY created_at DESC", (business_id, customer_id))]
            followups = [self._due_out(dict(r)) for r in conn.execute(
                "SELECT id, due_utc, note, status FROM pos_crm_followups WHERE business_id = ? AND customer_id = ? AND"
                " status = 'open' ORDER BY due_utc", (business_id, customer_id))]
            timeline = self._timeline(conn, business_id, "customer_id", customer_id, me)
            quotes = self._quotes(conn, business_id, "customer_id", customer_id)
        last = invoices[0]["local_date"] if invoices else None
        return {"customer": customer, "summary": {
            "bills": sum(1 for i in invoices if i["doc_kind"] == "invoice" and i["status"] == "issued"),
            "billed_paise": billed, "returned_paise": returned, "due_paise": customer.get("balance_paise", 0),
            "last_bill": last, "open_leads": sum(1 for x in leads if x["stage"] in OPEN_STAGES),
            "open_complaints": sum(1 for x in complaints if x["status"] in ("open", "in_progress"))},
            "invoices": invoices, "payments": payments, "leads": leads, "quotations": quotes,
            "complaints": complaints, "followups": followups, "timeline": timeline}

    # ------------------------------------------------------ pipeline / today
    def pipeline(self, business_id: str, user: str, *, mine: bool = False) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "crm")
            me = self._member_key(conn, business_id, user)
            where, args = "business_id = ?", [business_id]
            if mine:
                where += " AND assigned_to = ?"
                args.append(me)
            stages = {s: {"count": 0, "value_paise": 0} for s in STAGES}
            for r in conn.execute(f"SELECT stage, COUNT(*) AS n, COALESCE(SUM(value_paise), 0) AS v FROM pos_crm_leads"
                                  f" WHERE {where} GROUP BY stage", args):
                stages[r["stage"]] = {"count": r["n"], "value_paise": r["v"]}
            now = _now_utc(self.store)
            end_today = datetime.combine(now.astimezone(IST).date(), datetime.max.time(), IST).astimezone(timezone.utc)
            fq = "SELECT COUNT(*) FROM pos_crm_followups WHERE business_id = ? AND status = 'open' AND due_utc {op} ?"
            fargs = [business_id]
            if mine:
                fq += " AND assigned_to = ?"
            overdue = conn.execute(fq.format(op="<"), fargs + [now.isoformat()] + ([me] if mine else [])).fetchone()[0]
            today = conn.execute(fq.format(op="<=") + " AND due_utc >= ?",
                                 fargs + [end_today.isoformat()] + ([me] if mine else []) + [now.isoformat()]).fetchone()[0]
            complaints = conn.execute("SELECT COUNT(*) FROM pos_crm_complaints WHERE business_id = ? AND status IN"
                                      " ('open', 'in_progress')", (business_id,)).fetchone()[0]
            enquiries = conn.execute("SELECT COUNT(*) FROM pos_crm_leads WHERE business_id = ? AND kind = 'enquiry' AND"
                                     " stage = 'new'", (business_id,)).fetchone()[0]
        open_value = sum(stages[s]["value_paise"] for s in OPEN_STAGES)
        return {"stages": [{"stage": s, **stages[s]} for s in STAGES], "open_value_paise": open_value,
                "followups_overdue": overdue, "followups_today": today, "complaints_active": complaints,
                "new_enquiries": enquiries,
                "basis": "Counted from this shop's CRM records; values are the estimates you typed, not sales."}

    # --------------------------------------------------------------- reports
    def report(self, business_id: str, user: str, date_from: str, date_to: str) -> Dict[str, Any]:
        try:
            start = datetime.strptime(date_from, "%Y-%m-%d").replace(tzinfo=IST)
            end = datetime.strptime(date_to, "%Y-%m-%d").replace(tzinfo=IST) + timedelta(days=1)
        except ValueError as error:
            raise PosError(400, "date", "Dates must be YYYY-MM-DD.") from error
        if end <= start or (end - start).days > 400:
            raise PosError(400, "date", "Pick a range of 1 to 400 days.")
        s_utc, e_utc = start.astimezone(timezone.utc).isoformat(), end.astimezone(timezone.utc).isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            by_source = []
            for r in conn.execute(
                    "SELECT source, COUNT(*) AS leads, SUM(stage = 'won') AS won, SUM(stage = 'lost') AS lost,"
                    " COALESCE(SUM(CASE WHEN stage = 'won' THEN value_paise END), 0) AS won_value FROM pos_crm_leads WHERE"
                    " business_id = ? AND created_at >= ? AND created_at < ? GROUP BY source ORDER BY leads DESC",
                    (business_id, s_utc, e_utc)):
                closed = (r["won"] or 0) + (r["lost"] or 0)
                by_source.append({**dict(r), "win_rate_pct": round(100 * (r["won"] or 0) / closed, 1) if closed else None})
            lost_reasons = [dict(r) for r in conn.execute(
                "SELECT lost_reason AS reason, COUNT(*) AS count FROM pos_crm_leads WHERE business_id = ? AND stage ="
                " 'lost' AND closed_at >= ? AND closed_at < ? GROUP BY lower(lost_reason) ORDER BY count DESC LIMIT 10",
                (business_id, s_utc, e_utc))]
            won_rows = conn.execute("SELECT created_at, closed_at FROM pos_crm_leads WHERE business_id = ? AND stage = 'won'"
                                    " AND closed_at >= ? AND closed_at < ?", (business_id, s_utc, e_utc)).fetchall()
            days = [(datetime.fromisoformat(r["closed_at"]) - datetime.fromisoformat(r["created_at"])).total_seconds()
                    / 86400 for r in won_rows]
            fu = conn.execute("SELECT SUM(status = 'done') AS done, SUM(status = 'skipped') AS skipped, SUM(status = 'open'"
                              " AND due_utc < ?) AS overdue FROM pos_crm_followups WHERE business_id = ? AND due_utc >= ?"
                              " AND due_utc < ?", (_now_utc(self.store).isoformat(), business_id, s_utc, e_utc)).fetchone()
            comp = conn.execute("SELECT COUNT(*) AS raised, SUM(status IN ('resolved', 'closed')) AS solved FROM"
                                " pos_crm_complaints WHERE business_id = ? AND created_at >= ? AND created_at < ?",
                                (business_id, s_utc, e_utc)).fetchone()
            solved = conn.execute("SELECT created_at, resolved_at FROM pos_crm_complaints WHERE business_id = ? AND"
                                  " resolved_at >= ? AND resolved_at < ?", (business_id, s_utc, e_utc)).fetchall()
            hours = [(datetime.fromisoformat(r["resolved_at"]) - datetime.fromisoformat(r["created_at"])).total_seconds()
                     / 3600 for r in solved]
            top = []
            for r in conn.execute(
                    "SELECT customer_id, json_extract(customer_snapshot, '$.name') AS name, COUNT(*) AS bills, SUM("
                    "json_extract(totals, '$.grand_total_paise')) AS billed_paise FROM pos_invoices WHERE business_id = ?"
                    " AND doc_kind = 'invoice' AND status = 'issued' AND customer_id IS NOT NULL AND local_date >= ? AND"
                    " local_date <= ? GROUP BY customer_id ORDER BY billed_paise DESC LIMIT 10",
                    (business_id, date_from, date_to)):
                top.append(dict(r))
            dues = [dict(r) for r in conn.execute(
                "SELECT c.id AS customer_id, c.name, SUM(l.debit_paise - l.credit_paise) AS due_paise FROM pos_ledger l JOIN"
                " pos_customers c ON c.id = l.customer_id WHERE l.business_id = ? GROUP BY c.id HAVING due_paise > 0 ORDER"
                " BY due_paise DESC LIMIT 10", (business_id,))]
        total = sum(x["leads"] for x in by_source)
        won = sum(x["won"] or 0 for x in by_source)
        return {"from": date_from, "to": date_to, "leads": total, "won": won,
                "conversion_pct": round(100 * won / total, 1) if total else None,
                "avg_days_to_win": round(sum(days) / len(days), 1) if days else None,
                "by_source": by_source, "lost_reasons": lost_reasons,
                "followups": {k: int(fu[k] or 0) for k in ("done", "skipped", "overdue")},
                "complaints": {"raised": int(comp["raised"] or 0), "solved": int(comp["solved"] or 0),
                               "avg_hours_to_solve": round(sum(hours) / len(hours), 1) if hours else None},
                "top_customers": top, "dues": dues,
                "basis": "Leads, follow-ups and complaints from CRM records; customers' sales and dues from issued bills"
                         " and the customer ledger. Nothing is estimated except the lead values you typed."}
