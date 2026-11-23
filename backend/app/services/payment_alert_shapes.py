"""Payment messages in NEW words: what every phone learns from people's answers (owner 2026-11-23).

Owner: "payment confirmations come like this -- when they come with new words, why does it not read them?"
A phone that cannot read a money message asks its person once: came in / went out / not a payment
(``PaymentAlertParser.unread`` on the phone). The answer teaches that phone. When the person allows it, the phone
also sends the message's SHAPE here: the sender id (a registered SMS sender such as ``sms:ICICIT``, or the money
app's package ``app:com.phonepe.app``), the shape words (``PaymentAlertParser.skeleton``: only common words such as
"debited", "from", "a/c" and the ``₹#`` amount mark -- never a name, an amount or a number) and the answer.

When enough DIFFERENT people give the SAME answer for the same sender + shape and nobody answered otherwise, the
shape is served to every phone (``GET /api/payment-alerts/shapes``), so that kind of message is read without an app
update. "Came in" needs more people than "went out" / "not a payment", because a wrong "came in" would SAY money
arrived. Staff can approve or reject any shape in the Command Center (``payments:manage``).

Nothing here can identify a person: votes keep only a salted hash of the voter, the shape words are checked
against the phone's own word list (``SHAPE_WORDS``, the same as ``SKELETON_WORDS`` in PaymentAlertParser.kt -- a
test keeps them equal) and a person's own phone number is never a sender.
"""
from __future__ import annotations

import hashlib
import re
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

# The ONLY words a shape may carry: PaymentAlertParser.kt SKELETON_WORDS (+ the "₹#" amount mark).
SHAPE_WORDS = frozenset({
    "received", "receive", "credited", "credit", "debited", "debit", "sent", "send", "paid", "pay", "payment", "to",
    "you", "your", "from", "by", "in", "into", "of", "has", "have", "money", "successfully", "successful", "bank",
    "account", "a/c", "ac", "acct", "upi", "transferred", "transfer", "trf", "added", "wallet", "balance", "avl", "bal",
    "is", "was", "on", "via", "for", "at", "done", "completed", "linked", "sbi", "hdfc", "icici", "axis", "kotak", "phonepe",
    "gpay", "paytm", "bhim", "vpa", "towards", "withdrawn", "spent", "deposited", "refund", "cashback", "request",
    "జమ", "అందింది", "అందాయి", "పంపారు", "చెల్లించారు",
})
AMOUNT_MARK = "₹#"
ANSWERS = ("in", "out", "none")
# How many different people must agree (with nobody answering otherwise) before every phone reads the shape.
AGREE_TO_SHARE = {"in": 5, "out": 3, "none": 3}
MIN_WORDS, MAX_WORDS = 3, 40
STATUSES = ("new", "approved", "rejected")
_SMS_SENDER = re.compile(r"^sms:[A-Z0-9]{3,9}$")
_APP_SENDER = re.compile(r"^app:[a-z][a-z0-9_]*(?:\.[a-z0-9_]+){1,8}$")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS payment_alert_shapes (id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL,"
    " skeleton TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'new', kind TEXT, decided_by TEXT,"
    " first_at TEXT NOT NULL, last_at TEXT NOT NULL, UNIQUE (sender, skeleton))",
    "CREATE TABLE IF NOT EXISTS payment_alert_shape_votes (shape_id INTEGER NOT NULL, voter TEXT NOT NULL,"
    " answer TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY (shape_id, voter))",
]


class ShapeError(ValueError):
    """A shape or sender this service will not keep (the message says why)."""


def clean_skeleton(value: Any) -> str:
    """The shape words, checked: only words the phone itself can produce. Anything else is refused, never cut."""
    words = str(value or "").strip().lower().split()
    if not MIN_WORDS <= len(words) <= MAX_WORDS:
        raise ShapeError("shape_size")
    for w in words:
        if w != AMOUNT_MARK and w not in SHAPE_WORDS:
            raise ShapeError("shape_word")
    return " ".join(words)


def clean_sender(value: Any) -> str:
    """``sms:ICICIT`` (a registered SMS sender id) or ``app:<package>``; a phone number or a name is refused."""
    s = str(value or "").strip()
    if s.startswith("sms:"):
        s = "sms:" + s[4:].upper()
    if _SMS_SENDER.match(s) or _APP_SENDER.match(s):
        return s
    raise ShapeError("sender")


class PaymentAlertShapes:
    def __init__(self, database_path: str, salt: str = "") -> None:
        self.database_path = database_path
        self.salt = salt or "askodox-shapes"
        with closing(self._connect()) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.database_path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat(timespec="seconds")

    def _voter(self, user: str) -> str:
        return hashlib.sha256(f"{self.salt}|{user}".encode()).hexdigest()[:20]

    # ------------------------------------------------------------------ phones
    def answer(self, user: str, sender: Any, skeleton: Any, answer: Any) -> Dict[str, Any]:
        """One person's answer about one shape (their newest answer counts). Returns whether it is now shared."""
        sender_ok, shape = clean_sender(sender), clean_skeleton(skeleton)
        kind = str(answer or "").strip().lower()
        if kind not in ANSWERS:
            raise ShapeError("answer")
        now = self._now()
        with closing(self._connect()) as conn:
            conn.execute("INSERT INTO payment_alert_shapes (sender, skeleton, first_at, last_at) VALUES (?, ?, ?, ?)"
                         " ON CONFLICT(sender, skeleton) DO UPDATE SET last_at = excluded.last_at",
                         (sender_ok, shape, now, now))
            row = conn.execute("SELECT * FROM payment_alert_shapes WHERE sender = ? AND skeleton = ?",
                               (sender_ok, shape)).fetchone()
            conn.execute("INSERT INTO payment_alert_shape_votes (shape_id, voter, answer, at) VALUES (?, ?, ?, ?)"
                         " ON CONFLICT(shape_id, voter) DO UPDATE SET answer = excluded.answer, at = excluded.at",
                         (row["id"], self._voter(user), kind, now))
            self._settle(conn, row["id"])
            conn.commit()
            out = conn.execute("SELECT status, kind FROM payment_alert_shapes WHERE id = ?", (row["id"],)).fetchone()
        return {"ok": True, "shared": out["status"] == "approved", "kind": out["kind"]}

    def _counts(self, conn: sqlite3.Connection, shape_id: int) -> Dict[str, int]:
        counts = {a: 0 for a in ANSWERS}
        for r in conn.execute("SELECT answer, COUNT(*) AS n FROM payment_alert_shape_votes WHERE shape_id = ? GROUP BY answer",
                              (shape_id,)):
            counts[r["answer"]] = int(r["n"])
        return counts

    def _settle(self, conn: sqlite3.Connection, shape_id: int) -> None:
        """Share a shape once enough people agree and nobody disagrees; a staff decision is never overwritten."""
        row = conn.execute("SELECT status, decided_by FROM payment_alert_shapes WHERE id = ?", (shape_id,)).fetchone()
        if row["decided_by"]:
            return
        counts = self._counts(conn, shape_id)
        agreed = [a for a in ANSWERS if counts[a] >= AGREE_TO_SHARE[a] and sum(counts.values()) == counts[a]]
        if agreed:
            conn.execute("UPDATE payment_alert_shapes SET status = 'approved', kind = ? WHERE id = ?", (agreed[0], shape_id))
        elif row["status"] == "approved":
            # Somebody answered otherwise after it was shared: it stops being shared until staff decide.
            conn.execute("UPDATE payment_alert_shapes SET status = 'new', kind = NULL WHERE id = ?", (shape_id,))

    def shared(self) -> List[Dict[str, str]]:
        """What every phone reads: sender + shape words + kind (in / out / none)."""
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT sender, skeleton, kind FROM payment_alert_shapes WHERE status = 'approved'"
                                " AND kind IS NOT NULL ORDER BY id").fetchall()
        return [{"sender": r["sender"], "skeleton": r["skeleton"], "kind": r["kind"]} for r in rows]

    # ------------------------------------------------------------------ staff
    def list(self, status: Optional[str] = None, limit: int = 300) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            where, args = ("WHERE status = ?", [status]) if status in STATUSES else ("", [])
            rows = conn.execute(f"SELECT * FROM payment_alert_shapes {where} ORDER BY last_at DESC LIMIT ?",
                                (*args, max(1, min(int(limit), 1000)))).fetchall()
            items = []
            for r in rows:
                counts = self._counts(conn, r["id"])
                items.append({"id": r["id"], "sender": r["sender"], "skeleton": r["skeleton"], "status": r["status"],
                              "kind": r["kind"], "decided_by_staff": bool(r["decided_by"]), "answers": counts,
                              "people": sum(counts.values()), "first_at": r["first_at"], "last_at": r["last_at"]})
        return {"items": items, "rules": {"agree_to_share": AGREE_TO_SHARE}}

    def decide(self, shape_id: int, status: str, kind: Optional[str], staff: str) -> Dict[str, Any]:
        if status not in STATUSES:
            raise ShapeError("status")
        if status == "approved" and kind not in ANSWERS:
            raise ShapeError("kind")
        with closing(self._connect()) as conn:
            if conn.execute("SELECT 1 FROM payment_alert_shapes WHERE id = ?", (shape_id,)).fetchone() is None:
                raise LookupError("shape")
            if status == "new":
                # Back to the people's answers.
                conn.execute("UPDATE payment_alert_shapes SET status = 'new', kind = NULL, decided_by = NULL WHERE id = ?",
                             (shape_id,))
                self._settle(conn, shape_id)
            else:
                conn.execute("UPDATE payment_alert_shapes SET status = ?, kind = ?, decided_by = ? WHERE id = ?",
                             (status, kind if status == "approved" else None, staff or "staff", shape_id))
            conn.commit()
        return {"ok": True}


def payment_alert_shapes(container: Any) -> PaymentAlertShapes:
    service = getattr(container, "payment_alert_shapes", None)
    if service is None:
        settings = container.settings
        service = PaymentAlertShapes(settings.database_path, str(getattr(settings, "session_token_secret", "") or ""))
        try:
            container.payment_alert_shapes = service
        except Exception:
            pass
    return service
