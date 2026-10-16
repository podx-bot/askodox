"""AI-assisted KYC engine (Integration Platform, phase 2).

What it does
- Records the user's CONSENT before any document is read; revoking consent
  wipes every stored KYC field for that user.
- Reads a document the user chose (photo / PDF / text) with the SAME analysers
  the chat uses, classifies it (PAN card, GST certificate, bank proof, business
  document, professional licence, Aadhaar), extracts fields, prefills, lists
  what is missing and detects inconsistencies (GSTIN vs PAN, name vs profile,
  invalid GSTIN checksum, one ID used by several accounts).
- AI extraction is NEVER verification: such a check stays EXTRACTED /
  NEEDS_REVIEW / AWAITING_PROVIDER. Only an authoritative provider adapter
  (identity, GST, bank) or -- for business documents and professional
  licences only -- a staff review can make it VERIFIED. Verified checks
  expire.

Privacy (data minimisation)
- Full ID / account numbers are never stored or logged: only a masked form
  (last 4) and a keyed hash (duplicate detection). Aadhaar numbers are
  discarded and the user is pointed to DigiLocker.
- The raw document is not stored by this engine.

Levels (badges reflect COMPLETED verification only)
  L1 Mobile verified       signed in with OTP (never the shared demo account)
  L2 Identity verified     PAN or DigiLocker verified by a provider
  L3 Business verified     GST (provider) or business document (staff review)
  L4 Professional verified professional licence (staff review / provider)
  L5 Regulated partner KYC confirmed by a regulated partner (provider only)

Providers: ``container.kyc_providers`` maps a kind -> adapter with
``verify(kind, value, name) -> {"verified": bool, "reference": str, "reason": str}``.
None is configured in production yet, so those checks wait in
AWAITING_PROVIDER (CONFIGURATION REQUIRED in the Setup Wizard).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import re
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

CONSENT_VERSION = "kyc-consent-v1"
CONSENT_TEXT = ("I allow ASKODOX to read the documents I choose, extract the details needed for verification, and "
                "send them to an authorised verification provider. ASKODOX keeps only masked values, and I can "
                "withdraw this consent at any time, which deletes the stored details.")

KINDS: Dict[str, Dict[str, Any]] = {
    "pan": {"label": "PAN card", "level": 2, "staff_review": False, "expiry_days": 730},
    "digilocker": {"label": "DigiLocker document", "level": 2, "staff_review": False, "expiry_days": 365},
    "gst": {"label": "GST registration", "level": 3, "staff_review": False, "expiry_days": 365},
    "business_document": {"label": "Business registration document", "level": 3, "staff_review": True,
                          "expiry_days": 365},
    "professional_license": {"label": "Professional licence", "level": 4, "staff_review": True,
                             "expiry_days": 365},
    "bank_account": {"label": "Bank account proof", "level": 0, "staff_review": False, "expiry_days": 365},
    "regulated_partner_kyc": {"label": "Regulated partner KYC", "level": 5, "staff_review": False,
                              "expiry_days": 365},
}
LEVELS = {1: "Mobile verified", 2: "Identity verified", 3: "Business verified",
          4: "Professional / category verified", 5: "Regulated partner KYC verified"}
REQUIREMENTS = {  # activity -> minimum level (basic features never need full KYC)
    "buy": 1, "sell": 1, "offer_services": 1, "delivery_partner": 1, "receive_payouts": 2,
    "business_badge": 3, "professional_badge": 4, "regulated_products": 5,
}
STATES = ("EXTRACTED", "NEEDS_REVIEW", "AWAITING_PROVIDER", "VERIFIED", "REJECTED", "EXPIRED")
DEMO_KEY = "9999999999"

_PAN = re.compile(r"\b([A-Z]{5}[0-9]{4}[A-Z])\b")
_GSTIN = re.compile(r"\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z])\b")
_IFSC = re.compile(r"\b([A-Z]{4}0[A-Z0-9]{6})\b")
_AADHAAR = re.compile(r"\b(\d{4}\s?\d{4}\s?\d{4})\b")
_ACCOUNT = re.compile(r"(?:a/?c|account)\s*(?:no\.?|number|#)?\s*[:\-]?\s*(\d[\d\s]{7,20}\d)", re.IGNORECASE)
_DATE = re.compile(r"\b(\d{2})[/\-.](\d{2})[/\-.](\d{4})\b")
_NAME = re.compile(r"(?:^|\n)\s*(?:name|legal name|trade name|name of (?:the )?(?:proprietor|business|holder|"
                   r"enterprise|firm|company|applicant))\s*[:\-]\s*([A-Za-z][A-Za-z .]{2,60})", re.IGNORECASE)

_NAME_NEXT_LINE = re.compile(r"(?:^|\n)\s*(?:name|legal name|trade name)\s*\n\s*([A-Za-z][A-Za-z .]{2,60})",
                             re.IGNORECASE)

_CLASSIFY = [
    ("aadhaar", ("aadhaar", "unique identification authority", "uidai")),
    ("gst", ("goods and services tax", "gstin", "gst reg", "form gst")),
    ("pan", ("income tax department", "permanent account number", "pan card")),
    ("bank_account", ("ifsc", "passbook", "cancelled cheque", "bank statement", "account holder")),
    ("professional_license", ("licence", "license", "council", "registration no", "medical", "bar council")),
    ("business_document", ("certificate of incorporation", "udyam", "shop and establishment", "trade licence",
                           "partnership deed", "msme")),
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def phone_key(user_id: str) -> str:
    digits = "".join(ch for ch in str(user_id or "") if ch.isdigit())
    return digits[-10:] if len(digits) >= 10 else ""


def mask(value: str, keep: int = 4) -> str:
    value = re.sub(r"\s", "", str(value or ""))
    return ("•" * max(0, len(value) - keep) + value[-keep:]) if value else ""


# ------------------------------------------------------------- extraction --
_GST_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def gstin_valid(gstin: str) -> bool:
    """GSTIN check digit (mod 36 weighted sum, the official algorithm)."""
    gstin = str(gstin or "").upper()
    if not _GSTIN.fullmatch(gstin):
        return False
    total = 0
    for i, ch in enumerate(gstin[:14]):
        product = _GST_CHARS.index(ch) * (2 if i % 2 else 1)
        total += product // 36 + product % 36
    return _GST_CHARS[(36 - total % 36) % 36] == gstin[14]


def classify(text: str, hint: str = "") -> str:
    if hint in KINDS or hint == "aadhaar":
        return hint
    low = str(text or "").casefold()
    for kind, words in _CLASSIFY:
        if any(w in low for w in words):
            return kind
    up = str(text or "").upper()
    if _GSTIN.search(up):
        return "gst"
    if _PAN.search(up):
        return "pan"
    return "unknown"


def extract(text: str, *, hint: str = "", profile_name: str = "") -> Dict[str, Any]:
    """Fields from the document text -- values in memory only; the caller
    stores masked forms. Never a verification."""
    raw = str(text or "")
    up = raw.upper()
    kind = classify(raw, hint)
    values: Dict[str, str] = {}
    issues: List[str] = []
    if _AADHAAR.search(raw) and (kind == "aadhaar" or "aadhaar" in raw.casefold()):
        issues.append("Aadhaar number found: ASKODOX never stores it. Use DigiLocker for identity instead.")
    if (m := _GSTIN.search(up)):
        values["gstin"] = m.group(1)
        if not gstin_valid(m.group(1)):
            issues.append("GSTIN check digit does not match: re-check the number.")
    pans = [p for p in _PAN.findall(up) if not values.get("gstin") or p != values["gstin"][2:12]]
    if pans:
        values["pan"] = pans[0]
    elif values.get("gstin"):
        values["pan_in_gstin"] = values["gstin"][2:12]
    if values.get("pan") and values.get("gstin") and values["gstin"][2:12] != values["pan"]:
        issues.append("The PAN inside the GSTIN differs from the PAN on the document.")
    if (m := _IFSC.search(up)):
        values["ifsc"] = m.group(1)
    if (m := _ACCOUNT.search(raw)):
        values["account_number"] = re.sub(r"\s", "", m.group(1))
    if (m := _NAME.search(raw) or _NAME_NEXT_LINE.search(raw)):
        values["name"] = " ".join(m.group(1).split()).title()[:60]
    if (m := _DATE.search(raw)):
        values["date"] = f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
    needed = {"pan": ("pan", "name"), "gst": ("gstin", "name"), "bank_account": ("account_number", "ifsc", "name"),
              "business_document": ("name",), "professional_license": ("name",), "digilocker": ("name",)}
    missing = [f for f in needed.get(kind, ()) if not values.get(f)]
    if profile_name and values.get("name") and not _same_name(profile_name, values["name"]):
        issues.append("The name on the document does not match the profile name.")
    return {"kind": kind, "values": values, "missing": missing, "issues": issues}


def _same_name(a: str, b: str) -> bool:
    wa = {w for w in re.findall(r"[a-z]+", a.casefold()) if len(w) > 1}
    wb = {w for w in re.findall(r"[a-z]+", b.casefold()) if len(w) > 1}
    return bool(wa and wb) and len(wa & wb) >= min(2, len(wa), len(wb))


def masked_fields(values: Dict[str, str]) -> Dict[str, str]:
    out = {}
    for key, value in values.items():
        if key in ("pan", "pan_in_gstin", "gstin", "account_number"):
            out[key] = mask(value)
        elif key == "ifsc":
            out[key] = value[:4] + "•••••••"  # bank code only
        else:
            out[key] = value
    return out


# ----------------------------------------------------------------- store --
class KycStore:
    def __init__(self, db_path: str, secret: str) -> None:
        self.db_path = db_path
        self._key = ("kyc-hash:" + str(secret)).encode()
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS kyc_consents (
                    id TEXT PRIMARY KEY, user_id TEXT NOT NULL, version TEXT NOT NULL, text TEXT NOT NULL,
                    granted_at TEXT NOT NULL, revoked_at TEXT);
                CREATE INDEX IF NOT EXISTS ix_kyc_consents_user ON kyc_consents(user_id);
                CREATE TABLE IF NOT EXISTS kyc_checks (
                    id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                    method TEXT NOT NULL, provider TEXT, fields_json TEXT NOT NULL DEFAULT '{}',
                    value_hash TEXT, issues_json TEXT NOT NULL DEFAULT '[]', missing_json TEXT NOT NULL DEFAULT '[]',
                    consent_id TEXT NOT NULL, reference TEXT, reviewer TEXT, note TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, verified_at TEXT, expires_at TEXT,
                    deleted INTEGER NOT NULL DEFAULT 0);
                CREATE INDEX IF NOT EXISTS ix_kyc_checks_user ON kyc_checks(user_id);
                CREATE INDEX IF NOT EXISTS ix_kyc_checks_hash ON kyc_checks(value_hash);
                CREATE TABLE IF NOT EXISTS kyc_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, check_id TEXT, user_id TEXT NOT NULL, event TEXT NOT NULL,
                    actor TEXT NOT NULL, detail_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL);
                """
            )

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def value_hash(self, value: str) -> str:
        return hmac.new(self._key, re.sub(r"\s", "", value).upper().encode(), hashlib.sha256).hexdigest()

    def log(self, user_id: str, event: str, actor: str, check_id: str = "", detail: Optional[Dict] = None) -> None:
        with self._connect() as conn:
            conn.execute("INSERT INTO kyc_events(check_id,user_id,event,actor,detail_json,created_at) VALUES(?,?,?,?,?,?)",
                         (check_id, user_id, event, actor, json.dumps(detail or {})[:1500], _now().isoformat()))

    # consent ------------------------------------------------------------
    def consent(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM kyc_consents WHERE user_id=? AND revoked_at IS NULL "
                               "ORDER BY granted_at DESC LIMIT 1", (user_id,)).fetchone()
        return dict(row) if row else None

    def grant(self, user_id: str) -> Dict[str, Any]:
        found = self.consent(user_id)
        if found:
            return found
        row = {"id": "kc_" + uuid.uuid4().hex[:16], "user_id": user_id, "version": CONSENT_VERSION,
               "text": CONSENT_TEXT, "granted_at": _now().isoformat()}
        with self._connect() as conn:
            conn.execute("INSERT INTO kyc_consents(id,user_id,version,text,granted_at) VALUES(?,?,?,?,?)",
                         tuple(row.values()))
        self.log(user_id, "consent_granted", f"user:{user_id}")
        return row

    def revoke(self, user_id: str) -> int:
        """Withdrawing consent deletes every stored KYC field (audit trail kept)."""
        now = _now().isoformat()
        with self._connect() as conn:
            conn.execute("UPDATE kyc_consents SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL", (now, user_id))
            n = conn.execute("UPDATE kyc_checks SET deleted=1, fields_json='{}', value_hash=NULL, updated_at=? "
                             "WHERE user_id=? AND deleted=0", (now, user_id)).rowcount
        self.log(user_id, "consent_revoked", f"user:{user_id}", detail={"checks_wiped": n})
        return n

    # checks -------------------------------------------------------------
    def create(self, **row: Any) -> Dict[str, Any]:
        now = _now().isoformat()
        row = {"id": "kyc_" + uuid.uuid4().hex[:16], "created_at": now, "updated_at": now, **row}
        for key in ("fields_json", "issues_json", "missing_json"):
            if not isinstance(row.get(key), str):
                row[key] = json.dumps(row.get(key) or ({} if key == "fields_json" else []))
        with self._connect() as conn:
            conn.execute(f"INSERT INTO kyc_checks({','.join(row)}) VALUES({','.join('?' * len(row))})",
                         list(row.values()))
        return self.get(row["id"])  # type: ignore[return-value]

    def get(self, check_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM kyc_checks WHERE id=?", (check_id,)).fetchone()
        return self._row(row) if row else None

    @staticmethod
    def _row(row: sqlite3.Row) -> Dict[str, Any]:
        item = dict(row)
        item["fields"] = json.loads(item.pop("fields_json") or "{}")
        item["issues"] = json.loads(item.pop("issues_json") or "[]")
        item["missing"] = json.loads(item.pop("missing_json") or "[]")
        item.pop("value_hash", None)
        return item

    def update(self, check_id: str, **fields: Any) -> Dict[str, Any]:
        fields["updated_at"] = _now().isoformat()
        with self._connect() as conn:
            conn.execute(f"UPDATE kyc_checks SET {', '.join(f'{k}=?' for k in fields)} WHERE id=?",
                         [*fields.values(), check_id])
        return self.get(check_id)  # type: ignore[return-value]

    def checks(self, user_id: str = "", *, status: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM kyc_checks WHERE deleted=0", []
        if user_id:
            sql += " AND user_id=?"
            args.append(user_id)
        if status:
            sql += " AND status=?"
            args.append(status)
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY created_at DESC LIMIT ?", [*args, int(limit)]).fetchall()
        return [self._row(r) for r in rows]

    def others_with_hash(self, value_hash: str, user_id: str) -> int:
        with self._connect() as conn:
            return conn.execute("SELECT COUNT(DISTINCT user_id) FROM kyc_checks WHERE value_hash=? AND user_id<>? "
                                "AND deleted=0", (value_hash, user_id)).fetchone()[0]

    def expire_due(self) -> int:
        now = _now().isoformat()
        with self._connect() as conn:
            return conn.execute("UPDATE kyc_checks SET status='EXPIRED', updated_at=? WHERE status='VERIFIED' "
                                "AND expires_at IS NOT NULL AND expires_at<?", (now, now)).rowcount


def store(container: Any) -> KycStore:
    found = getattr(container, "kyc_store", None)
    if found is None or found.db_path != container.settings.database_path:
        found = KycStore(container.settings.database_path, container.settings.session_token_secret)
        container.kyc_store = found
    return found


class KycError(Exception):
    def __init__(self, code: str, status: int = 409) -> None:
        super().__init__(code)
        self.code, self.status = code, status


def providers(container: Any) -> Dict[str, Any]:
    return dict(getattr(container, "kyc_providers", None) or {})


def submit(container: Any, user_id: str, text: str, *, hint: str = "", profile_name: str = "") -> Dict[str, Any]:
    """Read one document the user chose. Returns the prefill + issues; stores
    only masked fields. A configured provider verifies immediately (the full
    value is used in memory only); otherwise the check waits for a provider or
    a staff review (business / professional documents)."""
    if phone_key(user_id) == DEMO_KEY:
        raise KycError("DEMO_ACCOUNT_NOT_ALLOWED", 403)
    kyc = store(container)
    consent = kyc.consent(user_id)
    if not consent:
        raise KycError("CONSENT_REQUIRED", 428)
    result = extract(text, hint=hint, profile_name=profile_name)
    kind = result["kind"]
    if kind == "aadhaar":
        kyc.log(user_id, "aadhaar_refused", f"user:{user_id}")
        return {"check": None, "kind": "aadhaar", "prefill": {}, "missing": [], "issues": result["issues"],
                "next_steps": ["Use DigiLocker (once enabled) to share identity without the Aadhaar number."]}
    if kind not in KINDS:
        return {"check": None, "kind": "unknown", "prefill": {}, "missing": [], "issues": [
            "This document could not be recognised. Upload a clear photo of a PAN card, GST certificate, bank "
            "proof, business registration or professional licence."], "next_steps": []}
    values = result["values"]
    key_value = values.get({"pan": "pan", "gst": "gstin", "bank_account": "account_number"}.get(kind, ""), "")
    value_hash = kyc.value_hash(key_value) if key_value else None
    issues = list(result["issues"])
    if value_hash and kyc.others_with_hash(value_hash, user_id):
        issues.append("This ID is already used by another ASKODOX account.")
    status, method, provider_name, reference, verified_at, expires_at = "EXTRACTED", "ai_extraction", None, None, None, None
    adapter = providers(container).get(kind)
    if issues or result["missing"]:
        status = "NEEDS_REVIEW"
    elif adapter is not None and key_value:
        outcome = adapter.verify(kind, key_value, values.get("name") or profile_name)
        provider_name = getattr(adapter, "name", "provider")
        method, reference = "provider", str(outcome.get("reference") or "")[:80]
        if outcome.get("verified"):
            status, verified_at = "VERIFIED", _now()
            expires_at = verified_at + timedelta(days=KINDS[kind]["expiry_days"])
        else:
            status = "REJECTED"
            issues.append(str(outcome.get("reason") or "the provider did not verify it")[:160])
    elif KINDS[kind]["staff_review"]:
        status = "NEEDS_REVIEW"
    else:
        status = "AWAITING_PROVIDER"
    check = kyc.create(user_id=user_id, kind=kind, status=status, method=method, provider=provider_name,
                       fields_json=masked_fields(values), value_hash=value_hash, issues_json=issues,
                       missing_json=result["missing"], consent_id=consent["id"], reference=reference,
                       verified_at=verified_at.isoformat() if verified_at else None,
                       expires_at=expires_at.isoformat() if expires_at else None)
    kyc.log(user_id, "document_submitted", f"user:{user_id}", check["id"], {"kind": kind, "status": status})
    return {"check": check, "kind": kind, "prefill": masked_fields(values), "missing": result["missing"],
            "issues": issues, "next_steps": next_steps(check)}


def next_steps(check: Dict[str, Any]) -> List[str]:
    status, kind = check["status"], check["kind"]
    if status == "VERIFIED":
        return [f"Verified until {str(check.get('expires_at') or '')[:10]}."]
    if check.get("missing"):
        return ["Upload a clearer photo showing: " + ", ".join(check["missing"]) + "."]
    if status == "NEEDS_REVIEW" and check.get("issues"):
        return ["Fix the issues above and upload again, or wait for staff review."]
    if status == "NEEDS_REVIEW":
        return ["Staff will review this document."]
    if status == "AWAITING_PROVIDER":
        return [f"{KINDS[kind]['label']} verification needs an authorised provider, which is not enabled yet. "
                "Your masked details are saved; nothing more is needed now."]
    if status == "REJECTED":
        return ["Upload the correct document or contact support."]
    return []


def review(container: Any, check_id: str, *, approve: bool, actor: str, note: str = "") -> Dict[str, Any]:
    kyc = store(container)
    check = kyc.get(check_id)
    if not check or check.get("deleted"):
        raise KycError("NOT_FOUND", 404)
    if check["status"] not in ("NEEDS_REVIEW", "AWAITING_PROVIDER", "EXTRACTED"):
        raise KycError("NOT_REVIEWABLE")
    if approve and not KINDS[check["kind"]]["staff_review"]:
        raise KycError("PROVIDER_VERIFICATION_REQUIRED")  # identity / GST / bank: only an authoritative source
    if approve and check.get("missing"):
        raise KycError("FIELDS_MISSING")
    now = _now()
    if approve:
        check = kyc.update(check_id, status="VERIFIED", method="staff_review", reviewer=actor, note=note[:300],
                           verified_at=now.isoformat(),
                           expires_at=(now + timedelta(days=KINDS[check["kind"]]["expiry_days"])).isoformat())
    else:
        check = kyc.update(check_id, status="REJECTED", reviewer=actor, note=note[:300])
    kyc.log(check["user_id"], "reviewed", actor, check_id, {"approve": approve})
    return check


def summary(container: Any, user_id: str) -> Dict[str, Any]:
    kyc = store(container)
    kyc.expire_due()
    checks = kyc.checks(user_id)
    verified = [c for c in checks if c["status"] == "VERIFIED"]
    badges = []
    if phone_key(user_id) != DEMO_KEY and user_id:
        badges.append(1)
    for c in verified:
        lvl = KINDS[c["kind"]]["level"]
        if lvl and lvl not in badges:
            badges.append(lvl)
    level = max(badges) if badges else 0
    return {"level": level, "level_label": LEVELS.get(level, "Not verified"),
            "badges": [{"level": b, "label": LEVELS[b]} for b in sorted(badges)],
            "consent": bool(kyc.consent(user_id)), "consent_text": CONSENT_TEXT, "consent_version": CONSENT_VERSION,
            "checks": [{k: c[k] for k in ("id", "kind", "status", "method", "fields", "issues", "missing",
                                          "verified_at", "expires_at", "created_at")}
                       | {"label": KINDS[c["kind"]]["label"], "next_steps": next_steps(c)} for c in checks],
            "requirements": {a: {"min_level": m, "met": level >= m} for a, m in REQUIREMENTS.items()},
            "providers": {k: ("configured" if k in providers(container) else "CONFIGURATION REQUIRED")
                          for k in KINDS if not KINDS[k]["staff_review"]}}
