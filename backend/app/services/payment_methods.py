"""ASKODOX -- a person's OWN ways to receive money (UPI IDs / QR codes, bank accounts, their own Razorpay).

ASKODOX never holds or moves money. These are only shown to the other party (Party A or Party B) so they can pay
the receiver DIRECTLY, in the receiver's own UPI app / bank. Any app's QR works (PhonePe, Google Pay, Paytm, BHIM,
a bank's merchant QR ...): the app reads the ``upi://pay`` text from the QR photo and stores the UPI ID + name.

* UPI: ``upi_id`` (VPA) + payee name + which app / bank issued it (label only).
* Bank: holder, bank, IFSC, account number -- the number is stored ENCRYPTED (``secret_box``; refused when the
  server has no secrets key) and returned in full only to the owner and to a counter-party who is entitled to pay
  (an accepted order); everyone else sees the last 4 digits.
* Exactly one default; deleting is a soft delete (history of what a payer was shown stays explainable).
"""
from __future__ import annotations

import re
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qs, unquote, urlparse

from app.services.payment_gateway import upi_intent, valid_vpa
from app.services.secret_box import SecretBox, SecretsNotConfigured

KINDS = ("upi", "bank")
MAX_METHODS = 10
_IFSC = re.compile(r"^[A-Z]{4}0[A-Z0-9]{6}$")
_ACCOUNT = re.compile(r"^[0-9]{6,18}$")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS user_payment_methods (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL,"
    " label TEXT NOT NULL DEFAULT '', app TEXT NOT NULL DEFAULT '', upi_id TEXT NOT NULL DEFAULT '',"
    " payee_name TEXT NOT NULL DEFAULT '', bank_name TEXT NOT NULL DEFAULT '', account_holder TEXT NOT NULL DEFAULT '',"
    " account_enc TEXT NOT NULL DEFAULT '', account_last4 TEXT NOT NULL DEFAULT '', ifsc TEXT NOT NULL DEFAULT '',"
    " is_default INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_user_payment_methods_user ON user_payment_methods(user_id, active)",
]


class PaymentMethodError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def parse_upi_qr(text: str) -> Dict[str, str]:
    """``upi://pay?pa=x@bank&pn=Name&...`` (what every UPI QR holds) -> {upi_id, payee_name}. Raises on anything else."""
    raw = str(text or "").strip()
    if valid_vpa(raw):
        return {"upi_id": raw, "payee_name": ""}
    parsed = urlparse(raw)
    if parsed.scheme.lower() != "upi":
        raise PaymentMethodError(400, "not_upi_qr", "This QR is not a UPI payment QR.")
    query = parse_qs(parsed.query)
    vpa = unquote((query.get("pa") or [""])[0]).strip()
    if not valid_vpa(vpa):
        raise PaymentMethodError(400, "not_upi_qr", "This QR has no valid UPI ID.")
    return {"upi_id": vpa, "payee_name": unquote((query.get("pn") or [""])[0]).strip()[:60]}


class PaymentMethods:
    def __init__(self, db_path: str, box: Optional[SecretBox] = None) -> None:
        self.db_path = db_path
        self.box = box or SecretBox()
        with closing(sqlite3.connect(db_path)) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _out(self, row: sqlite3.Row, *, full: bool) -> Dict[str, Any]:
        out: Dict[str, Any] = {"id": row["id"], "kind": row["kind"], "label": row["label"], "app": row["app"],
                               "is_default": bool(row["is_default"])}
        if row["kind"] == "upi":
            out.update({"upi_id": row["upi_id"], "payee_name": row["payee_name"]})
        else:
            out.update({"bank_name": row["bank_name"], "account_holder": row["account_holder"], "ifsc": row["ifsc"],
                        "account_last4": row["account_last4"]})
            if full:
                number = self.box.decrypt(row["account_enc"]) if row["account_enc"] else ""
                if number:
                    out["account_number"] = number
        return out

    # --------------------------------------------------------------- owner
    def list(self, user_id: str) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT * FROM user_payment_methods WHERE user_id = ? AND active = 1"
                                " ORDER BY is_default DESC, created_at", (user_id,)).fetchall()
        return [self._out(r, full=True) for r in rows]

    def add(self, user_id: str, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        kind = str(data.get("kind") or "")
        if kind not in KINDS:
            raise PaymentMethodError(400, "kind", "kind must be upi or bank.")
        now = self._now()
        fields: Dict[str, Any] = {"label": str(data.get("label") or "").strip()[:40],
                                  "app": str(data.get("app") or "").strip()[:30]}
        if kind == "upi":
            if data.get("qr_text"):
                fields.update(parse_upi_qr(str(data["qr_text"])))
            else:
                vpa = str(data.get("upi_id") or "").strip()
                if not valid_vpa(vpa):
                    raise PaymentMethodError(400, "upi_id", "Enter a UPI ID like name@okhdfcbank.")
                fields.update({"upi_id": vpa, "payee_name": ""})
            if data.get("payee_name"):
                fields["payee_name"] = str(data["payee_name"]).strip()[:60]
        else:
            number = re.sub(r"\s+", "", str(data.get("account_number") or ""))
            ifsc = str(data.get("ifsc") or "").strip().upper()
            holder = str(data.get("account_holder") or "").strip()[:60]
            if not _ACCOUNT.match(number):
                raise PaymentMethodError(400, "account_number", "Account number must be 6-18 digits.")
            if not _IFSC.match(ifsc):
                raise PaymentMethodError(400, "ifsc", "IFSC looks like HDFC0001234.")
            if not holder:
                raise PaymentMethodError(400, "account_holder", "Enter the account holder's name.")
            try:
                enc = self.box.encrypt(number)
            except SecretsNotConfigured:
                raise PaymentMethodError(503, "secrets_not_configured",
                                         "Bank accounts cannot be saved yet (server secret key missing). Use UPI.")
            fields.update({"bank_name": str(data.get("bank_name") or "").strip()[:40], "account_holder": holder,
                           "ifsc": ifsc, "account_enc": enc, "account_last4": number[-4:]})
        with closing(self._connect()) as conn:
            count = conn.execute("SELECT COUNT(*) FROM user_payment_methods WHERE user_id = ? AND active = 1",
                                 (user_id,)).fetchone()[0]
            if count >= MAX_METHODS:
                raise PaymentMethodError(409, "too_many", f"At most {MAX_METHODS} payment methods.")
            if kind == "upi" and conn.execute("SELECT 1 FROM user_payment_methods WHERE user_id = ? AND active = 1"
                                              " AND kind = 'upi' AND lower(upi_id) = lower(?)",
                                              (user_id, fields["upi_id"])).fetchone():
                raise PaymentMethodError(409, "duplicate", "This UPI ID is already saved.")
            make_default = count == 0 or bool(data.get("is_default"))
            if make_default:
                conn.execute("UPDATE user_payment_methods SET is_default = 0 WHERE user_id = ?", (user_id,))
            columns = ["id", "user_id", "kind", "is_default", "created_at", "updated_at", *fields]
            values = [f"pm_{uuid.uuid4().hex[:20]}", user_id, kind, int(make_default), now, now, *fields.values()]
            conn.execute(f"INSERT INTO user_payment_methods ({', '.join(columns)}) VALUES ({', '.join('?' * len(values))})",
                         values)
            conn.commit()
        self._mirror_profile(user_id)
        return self.list(user_id)

    def set_default(self, user_id: str, method_id: str) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            if not conn.execute("SELECT 1 FROM user_payment_methods WHERE id = ? AND user_id = ? AND active = 1",
                                (method_id, user_id)).fetchone():
                raise PaymentMethodError(404, "method", "Payment method not found.")
            conn.execute("UPDATE user_payment_methods SET is_default = (id = ?), updated_at = ? WHERE user_id = ?",
                         (method_id, self._now(), user_id))
            conn.commit()
        self._mirror_profile(user_id)
        return self.list(user_id)

    def remove(self, user_id: str, method_id: str) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT is_default FROM user_payment_methods WHERE id = ? AND user_id = ? AND active = 1",
                               (method_id, user_id)).fetchone()
            if row is None:
                raise PaymentMethodError(404, "method", "Payment method not found.")
            conn.execute("UPDATE user_payment_methods SET active = 0, is_default = 0, account_enc = '', updated_at = ?"
                         " WHERE id = ?", (self._now(), method_id))
            if row["is_default"]:
                nxt = conn.execute("SELECT id FROM user_payment_methods WHERE user_id = ? AND active = 1"
                                   " ORDER BY created_at LIMIT 1", (user_id,)).fetchone()
                if nxt:
                    conn.execute("UPDATE user_payment_methods SET is_default = 1 WHERE id = ?", (nxt["id"],))
            conn.commit()
        self._mirror_profile(user_id)
        return self.list(user_id)

    def _mirror_profile(self, user_id: str) -> None:
        """Older readers use ``user_profiles.upi_id``: keep it equal to the default UPI (best effort)."""
        try:
            default = self.default_upi(user_id)
            with closing(sqlite3.connect(self.db_path)) as conn:
                conn.execute("UPDATE user_profiles SET upi_id = ? WHERE user_id = ?",
                             ((default or {}).get("upi_id") or None, user_id))
                conn.commit()
        except sqlite3.Error:
            pass

    # ------------------------------------------------------------- readers
    def get(self, user_id: str, method_id: str) -> Optional[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM user_payment_methods WHERE id = ? AND user_id = ? AND active = 1",
                               (method_id, user_id)).fetchone()
        return self._out(row, full=True) if row else None

    def default_upi(self, user_id: str) -> Optional[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM user_payment_methods WHERE user_id = ? AND active = 1 AND kind = 'upi'"
                               " ORDER BY is_default DESC, created_at LIMIT 1", (user_id,)).fetchone()
        return self._out(row, full=False) if row else None

    def pay_to(self, receiver: str, *, amount: Optional[float], note: str, reference: str,
               fallback_name: str = "") -> List[Dict[str, Any]]:
        """What a payer who is ENTITLED to pay this receiver sees: UPI links with the amount, bank details in full."""
        out = []
        for m in self.list(receiver):
            if m["kind"] == "upi":
                link = upi_intent(m["upi_id"], m.get("payee_name") or fallback_name, amount, note, reference)
                if link:
                    out.append({**m, "upi_link": link})
            else:
                out.append(m)
        return out
