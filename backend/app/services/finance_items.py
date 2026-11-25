"""Finance items (owner 2026-11-21 plan, built 2026-11-25): insurance / loan / credit-card items a staff member adds
with the COMPANY'S OWN documents (PDFs, photos of a brochure / premium chart), the customer's doubts answered from
those documents FIRST, and -- only with the customer's yes -- a call back from an ASKODOX executive.

The rules this module keeps (do not loosen):

* ASKODOX gives no financial advice. An answer is a sentence the document itself supports: every answer carries the
  page it came from and a short QUOTE that must really stand on that page (``_quote_on_page``); an answer without one
  is dropped and the customer is told plainly "this is not in the company's document".
* The item's key points and ready question / answers are shown to customers only after a staff member CHECKED them.
* A call back needs the customer's consent in that very request. The number is the customer's own OTP-proven
  sign-in number; it is shown to staff only through ``reveal`` (audited by the route), never in a list.
* What an executive answered on a call can be saved as an answer of the item (source ``executive``), so the next
  customer hears it from the app. It is labelled as the executive's answer, never as the document's.
* Nothing here moves money, and no price / premium is invented: figures come from the documents only.

Tables (``fin_*``) live in the same database as the item store (``affiliate_products``); an item is a
``financial_offer`` row there. The readers of a PDF / a photo and the model are INJECTED, so the module is pure to test.
"""
from __future__ import annotations

import json
import re
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

KINDS = ("insurance", "loan", "credit_card", "other")
WHEN = ("now", "evening", "tomorrow")
OUTCOMES = ("answered", "deal", "not_interested", "no_answer")

MAX_DOCS = 8
MAX_DOC_BYTES = 8 * 1024 * 1024
MAX_PAGES = 80
MAX_PAGE_CHARS = 6000
PROMPT_CHARS = 28000  # document text handed to the model in one question
MAX_QA = 40
MAX_OPEN_CALLBACKS_PER_USER = 3

NOT_IN_DOCUMENT = {
    "en": "This is not in the company's document, so I will not guess.",
    "te": "ఇది కంపెనీ document లో లేదు, కాబట్టి నేను ఊహించి చెప్పను.",
}
NOT_ADVICE = {
    "en": "This is what the company's document says, not advice. Read the full terms before you take it.",
    "te": "ఇది సలహా కాదు — కంపెనీ document లో ఉన్నది మాత్రమే. తీసుకునే ముందు పూర్తి terms చదవండి.",
}

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS fin_meta (item_id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'other',"
    " points TEXT NOT NULL DEFAULT '[]', checked_by TEXT NOT NULL DEFAULT '', checked_at TEXT NOT NULL DEFAULT '',"
    " updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS fin_docs (id TEXT PRIMARY KEY, item_id TEXT NOT NULL, name TEXT NOT NULL,"
    " mime TEXT NOT NULL, pages TEXT NOT NULL, created_by TEXT NOT NULL, created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS fin_docs_item ON fin_docs (item_id)",
    "CREATE TABLE IF NOT EXISTS fin_qa (id TEXT PRIMARY KEY, item_id TEXT NOT NULL, question TEXT NOT NULL,"
    " answer TEXT NOT NULL, doc_id TEXT NOT NULL DEFAULT '', page INTEGER NOT NULL DEFAULT 0,"
    " quote TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT 'document', created_by TEXT NOT NULL DEFAULT '',"
    " created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS fin_qa_item ON fin_qa (item_id)",
    "CREATE TABLE IF NOT EXISTS fin_callbacks (id TEXT PRIMARY KEY, item_id TEXT NOT NULL, user_id TEXT NOT NULL,"
    " phone TEXT NOT NULL, question TEXT NOT NULL DEFAULT '', when_pref TEXT NOT NULL DEFAULT 'now',"
    " status TEXT NOT NULL DEFAULT 'new', outcome TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',"
    " created_at TEXT NOT NULL, done_by TEXT NOT NULL DEFAULT '', done_at TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS fin_callbacks_status ON fin_callbacks (status, created_at)",
    "CREATE TABLE IF NOT EXISTS fin_misses (item_id TEXT NOT NULL, question TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 1,"
    " last_at TEXT NOT NULL, PRIMARY KEY (item_id, question))",
]


class FinanceError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


def _clean(text: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip()[:limit]


def _norm(text: str) -> str:
    """Letters and digits only, lower case: a quote is compared with its page without spacing / punctuation noise."""
    return re.sub(r"[\W_]+", "", text.lower(), flags=re.UNICODE)


def _quote_on_page(quote: str, page_text: str) -> bool:
    q = _norm(quote)
    return len(q) >= 12 and q in _norm(page_text)


def _json(text: str) -> Any:
    raw = (text or "").strip()
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(raw[start:end + 1])
    except (TypeError, ValueError):
        return None


def phone_of(user_id: str) -> str:
    """The customer's own sign-in number (``app-phone-<10 digits>``); '' for any other kind of account."""
    match = re.fullmatch(r"app-phone-(\d{10})", user_id or "")
    return match.group(1) if match else ""


def mask(phone: str) -> str:
    return f"••{phone[-3:]}" if len(phone) >= 3 else "••"


class FinanceItems:
    def __init__(self, database_path: str, *, item: Callable[[str], Optional[Dict[str, Any]]],
                 read_pdf: Optional[Callable[[bytes], List[str]]] = None,
                 read_image: Optional[Callable[[bytes, str], str]] = None,
                 write_text: Optional[Callable[[str], str]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.path = database_path
        self.item = item
        self.read_pdf = read_pdf or pdf_pages
        self.read_image = read_image
        self.write_text = write_text
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with closing(self._connect()) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=15)
        conn.row_factory = sqlite3.Row
        return conn

    def _now(self) -> str:
        return self.clock().isoformat()

    # ------------------------------------------------------------------ the item
    def _finance_item(self, item_id: str, *, live: bool = False) -> Dict[str, Any]:
        found = self.item(item_id)
        if not found or found.get("item_type") != "financial_offer":
            raise FinanceError(404, "item", "Finance item not found.")
        if live and found.get("review_status") != "LIVE":
            raise FinanceError(404, "item", "Finance item not found.")
        return found

    def _meta(self, conn: sqlite3.Connection, item_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM fin_meta WHERE item_id = ?", (item_id,)).fetchone()
        if row is None:
            conn.execute("INSERT INTO fin_meta (item_id, updated_at) VALUES (?, ?)", (item_id, self._now()))
            row = conn.execute("SELECT * FROM fin_meta WHERE item_id = ?", (item_id,)).fetchone()
        return row

    def _docs(self, conn: sqlite3.Connection, item_id: str) -> List[sqlite3.Row]:
        return conn.execute("SELECT * FROM fin_docs WHERE item_id = ? ORDER BY created_at", (item_id,)).fetchall()

    @staticmethod
    def _pages(doc: sqlite3.Row) -> List[str]:
        try:
            pages = json.loads(doc["pages"] or "[]")
        except (TypeError, ValueError):
            pages = []
        return [str(p) for p in pages] if isinstance(pages, list) else []

    def _qa_out(self, row: sqlite3.Row, names: Dict[str, str]) -> Dict[str, Any]:
        return {"id": row["id"], "question": row["question"], "answer": row["answer"], "page": row["page"],
                "document": names.get(row["doc_id"], ""), "source": row["source"]}

    # ------------------------------------------------------------------ staff: documents
    def set_kind(self, item_id: str, kind: str) -> Dict[str, Any]:
        self._finance_item(item_id)
        if kind not in KINDS:
            raise FinanceError(400, "kind", "Choose insurance, loan, credit card or other.")
        with closing(self._connect()) as conn:
            self._meta(conn, item_id)
            conn.execute("UPDATE fin_meta SET kind = ?, updated_at = ? WHERE item_id = ?", (kind, self._now(), item_id))
            conn.commit()
        return self.staff_view(item_id)

    def add_document(self, item_id: str, name: str, mime: str, data: bytes, actor: str) -> Dict[str, Any]:
        """One PDF or photo of the company's own paper: its text is kept page by page (the file itself is not)."""
        self._finance_item(item_id)
        if not data or len(data) > MAX_DOC_BYTES:
            raise FinanceError(413, "size", "The file is empty or larger than 8 MB.")
        if data[:5] == b"%PDF-":
            kind = "application/pdf"
            try:
                pages = self.read_pdf(data)
            except Exception:
                raise FinanceError(422, "unreadable", "Could not read this PDF. Try a photo of the page instead.") from None
        elif data[:3] == b"\xff\xd8\xff" or data[:4] == b"\x89PNG" or (data[:4] == b"RIFF" and b"WEBP" in data[:16]):
            kind = "image/jpeg" if data[:3] == b"\xff\xd8\xff" else ("image/png" if data[:4] == b"\x89PNG" else "image/webp")
            if self.read_image is None:
                raise FinanceError(503, "no_reader", "Photos cannot be read right now. Add the PDF instead.")
            try:
                pages = [self.read_image(data, kind)]
            except Exception:
                raise FinanceError(503, "unreadable", "Could not read this photo. Take a clear, straight photo.") from None
        else:
            raise FinanceError(415, "type", "Add a PDF or a photo (JPG / PNG).")
        pages = [_clean_page(p) for p in pages[:MAX_PAGES]]
        if not any(len(p) >= 40 for p in pages):
            raise FinanceError(422, "no_text", "No readable text was found. A scanned PDF needs clear photos of its pages.")
        doc_id = "fd_" + uuid.uuid4().hex[:16]
        with closing(self._connect()) as conn:
            if len(self._docs(conn, item_id)) >= MAX_DOCS:
                raise FinanceError(409, "too_many", f"At most {MAX_DOCS} documents per item. Remove one first.")
            conn.execute("INSERT INTO fin_docs (id, item_id, name, mime, pages, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (doc_id, item_id, _clean(name, 80) or "document", kind, json.dumps(pages, ensure_ascii=False),
                          actor, self._now()))
            # New paper: what was checked before no longer covers it.
            self._meta(conn, item_id)
            conn.execute("UPDATE fin_meta SET checked_by = '', checked_at = '', updated_at = ? WHERE item_id = ?",
                         (self._now(), item_id))
            conn.commit()
        return self.staff_view(item_id)

    def remove_document(self, item_id: str, doc_id: str) -> Dict[str, Any]:
        self._finance_item(item_id)
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM fin_docs WHERE id = ? AND item_id = ?", (doc_id, item_id))
            conn.execute("DELETE FROM fin_qa WHERE doc_id = ? AND item_id = ? AND source = 'document'", (doc_id, item_id))
            conn.execute("UPDATE fin_meta SET checked_by = '', checked_at = '', updated_at = ? WHERE item_id = ?",
                         (self._now(), item_id))
            conn.commit()
        return self.staff_view(item_id)

    # ------------------------------------------------------------------ staff: the AI's reading
    def _document_text(self, docs: Sequence[sqlite3.Row], budget: int = PROMPT_CHARS) -> Tuple[str, Dict[Tuple[str, int], str]]:
        """The pages as the model sees them ("[D1 p3] ...") and the same pages by (doc id, page) for the quote check."""
        blocks: List[str] = []
        index: Dict[Tuple[str, int], str] = {}
        left = budget
        for n, doc in enumerate(docs, start=1):
            for p, text in enumerate(self._pages(doc), start=1):
                index[(doc["id"], p)] = text
                if left <= 0 or not text:
                    continue
                piece = text[:left]
                left -= len(piece)
                blocks.append(f"[D{n} p{p}] {piece}")
        return "\n".join(blocks), index

    def study(self, item_id: str, actor: str) -> Dict[str, Any]:
        """The model reads the documents and proposes key points + ready answers; staff must check them."""
        item = self._finance_item(item_id)
        if self.write_text is None:
            raise FinanceError(503, "no_model", "The AI reader is not available right now.")
        with closing(self._connect()) as conn:
            docs = self._docs(conn, item_id)
        if not docs:
            raise FinanceError(422, "no_documents", "Add the company's PDF or photos first.")
        text, index = self._document_text(docs)
        prompt = (
            "You read a finance company's OWN documents about one product (insurance / loan / credit card). Each page "
            "starts with a tag like [D1 p3] (document 1, page 3). Return ONLY JSON: {\"points\": [string], \"qa\": "
            "[{\"q\": string, \"a\": string, \"doc\": int, \"page\": int, \"quote\": string}]}.\n"
            "points = at most 6 short plain facts a customer should know first (who can take it, what it covers / "
            "costs, main conditions). qa = 8 to 14 questions customers really ask, each answered in one or two plain "
            "sentences. RULES: use ONLY what the pages say. Every qa needs the doc number, the page number and quote "
            "= 5 to 25 words copied EXACTLY from that page that prove the answer. No advice, no comparison with other "
            "companies, no 'best', no figure that is not printed there. If the pages are thin, return fewer items.\n"
            f"PRODUCT: {_clean(item.get('title'), 160)}\nPAGES:\n{text}")
        try:
            payload = _json(self.write_text(prompt))
        except Exception:
            payload = None
        if not isinstance(payload, dict):
            raise FinanceError(503, "no_answer", "The AI reader gave no usable answer. Try again.")
        points = [p for p in (_clean(x, 220) for x in (payload.get("points") or []) if isinstance(x, str)) if p][:6]
        kept: List[Tuple[str, str, str, int, str]] = []
        for entry in (payload.get("qa") or [])[:MAX_QA]:
            if not isinstance(entry, dict):
                continue
            try:
                doc = docs[int(entry.get("doc")) - 1]
                page = int(entry.get("page"))
            except (TypeError, ValueError, IndexError):
                continue
            question, answer, quote = _clean(entry.get("q"), 200), _clean(entry.get("a"), 600), _clean(entry.get("quote"), 300)
            if question and answer and _quote_on_page(quote, index.get((doc["id"], page), "")):
                kept.append((question, answer, doc["id"], page, quote))
        now = self._now()
        with closing(self._connect()) as conn:
            self._meta(conn, item_id)
            conn.execute("DELETE FROM fin_qa WHERE item_id = ? AND source = 'document'", (item_id,))
            for question, answer, doc_id, page, quote in kept:
                conn.execute("INSERT INTO fin_qa (id, item_id, question, answer, doc_id, page, quote, source, created_by, created_at)"
                             " VALUES (?, ?, ?, ?, ?, ?, ?, 'document', ?, ?)",
                             ("fq_" + uuid.uuid4().hex[:16], item_id, question, answer, doc_id, page, quote, actor, now))
            conn.execute("UPDATE fin_meta SET points = ?, checked_by = '', checked_at = '', updated_at = ? WHERE item_id = ?",
                         (json.dumps(points, ensure_ascii=False), now, item_id))
            conn.commit()
        return self.staff_view(item_id)

    def confirm(self, item_id: str, actor: str, *, points: Optional[List[str]] = None,
                remove_qa: Sequence[str] = ()) -> Dict[str, Any]:
        """Staff read the AI's points and answers, drop what is wrong, and take responsibility: only now customers see them."""
        self._finance_item(item_id)
        with closing(self._connect()) as conn:
            meta = self._meta(conn, item_id)
            if not self._docs(conn, item_id):
                raise FinanceError(422, "no_documents", "Add the company's PDF or photos first.")
            kept = json.loads(meta["points"] or "[]")
            if points is not None:
                kept = [p for p in (_clean(x, 220) for x in points) if p][:6]
            for qa_id in list(remove_qa)[:MAX_QA]:
                conn.execute("DELETE FROM fin_qa WHERE id = ? AND item_id = ?", (str(qa_id), item_id))
            conn.execute("UPDATE fin_meta SET points = ?, checked_by = ?, checked_at = ?, updated_at = ? WHERE item_id = ?",
                         (json.dumps(kept, ensure_ascii=False), actor, self._now(), self._now(), item_id))
            conn.commit()
        return self.staff_view(item_id)

    def staff_view(self, item_id: str) -> Dict[str, Any]:
        item = self._finance_item(item_id)
        with closing(self._connect()) as conn:
            meta = self._meta(conn, item_id)
            docs = self._docs(conn, item_id)
            names = {d["id"]: d["name"] for d in docs}
            qa = conn.execute("SELECT * FROM fin_qa WHERE item_id = ? ORDER BY source DESC, created_at", (item_id,)).fetchall()
            misses = conn.execute("SELECT question, n FROM fin_misses WHERE item_id = ? ORDER BY n DESC, last_at DESC LIMIT 10",
                                  (item_id,)).fetchall()
            conn.commit()
        return {"item_id": item_id, "title": item.get("title") or "", "kind": meta["kind"],
                "documents": [{"id": d["id"], "name": d["name"], "pages": len(self._pages(d)), "mime": d["mime"]} for d in docs],
                "points": json.loads(meta["points"] or "[]"), "qa": [self._qa_out(r, names) for r in qa],
                "checked": bool(meta["checked_at"]), "checked_at": meta["checked_at"],
                "not_answered": [{"question": m["question"], "times": m["n"]} for m in misses]}

    # ------------------------------------------------------------------ customer
    def public_view(self, item_id: str) -> Dict[str, Any]:
        item = self._finance_item(item_id, live=True)
        with closing(self._connect()) as conn:
            meta = self._meta(conn, item_id)
            docs = self._docs(conn, item_id)
            names = {d["id"]: d["name"] for d in docs}
            qa = conn.execute("SELECT * FROM fin_qa WHERE item_id = ? ORDER BY source DESC, created_at LIMIT 12", (item_id,)).fetchall()
            conn.commit()
        checked = bool(meta["checked_at"])
        return {"item_id": item_id, "title": item.get("title") or "", "kind": meta["kind"],
                "image_url": item.get("image_url") or "", "has_link": bool(item.get("affiliate_url") or item.get("original_product_url")),
                "points": json.loads(meta["points"] or "[]") if checked else [],
                "questions": [self._qa_out(r, names) for r in qa] if checked else [],
                "can_ask": checked and bool(docs), "not_advice": NOT_ADVICE}

    def ask(self, item_id: str, question: str, language: str = "te") -> Dict[str, Any]:
        """One customer question: answered from the document (with its page) or an executive's saved answer -- or not."""
        item = self._finance_item(item_id, live=True)
        lang = "te" if language == "te" else "en"
        asked = _clean(question, 300)
        if len(asked) < 3:
            raise FinanceError(400, "question", "Type your question.")
        with closing(self._connect()) as conn:
            meta = self._meta(conn, item_id)
            docs = self._docs(conn, item_id)
            said = conn.execute("SELECT question, answer FROM fin_qa WHERE item_id = ? AND source = 'executive'"
                                " ORDER BY created_at DESC LIMIT 20", (item_id,)).fetchall()
            conn.commit()
        miss = {"found": False, "answer": NOT_IN_DOCUMENT[lang], "page": 0, "document": "", "source": "",
                "offer_callback": True, "not_advice": NOT_ADVICE[lang]}
        if not meta["checked_at"] or not docs or self.write_text is None:
            self._missed(item_id, asked)
            return miss
        text, index = self._document_text(docs)
        notes = "\n".join(f"[E{n}] Q: {r['question']} A: {r['answer']}" for n, r in enumerate(said, start=1))
        prompt = (
            "A customer asks about ONE finance product. Answer ONLY from the company's pages below (each starts with "
            "a tag like [D1 p3]) or from the EXECUTIVE notes (tags [E1]...). Return ONLY JSON: {\"found\": bool, "
            "\"answer\": string, \"doc\": int, \"page\": int, \"quote\": string, \"executive\": int}.\n"
            f"Write the answer in simple {'Telugu (English product words may stay)' if lang == 'te' else 'English'}, one "
            "to three sentences. From a page: give doc, page and quote = 5 to 25 words copied EXACTLY from that page "
            "that prove it (executive = 0). From an executive note: executive = its number (doc = 0, page = 0, quote "
            "= \"\"). If neither answers the question, found = false and nothing else. NEVER advise whether to take "
            "it, never compare companies, never give a figure that is not printed there, never guess.\n"
            f"PRODUCT: {_clean(item.get('title'), 160)}\nQUESTION: {asked}\nEXECUTIVE NOTES:\n{notes or '(none)'}\nPAGES:\n{text}")
        try:
            payload = _json(self.write_text(prompt))
        except Exception:
            payload = None
        if not isinstance(payload, dict) or payload.get("found") is not True:
            self._missed(item_id, asked)
            return miss
        answer = _clean(payload.get("answer"), 700)
        try:
            executive = int(payload.get("executive") or 0)
        except (TypeError, ValueError):
            executive = 0
        if answer and 1 <= executive <= len(said):
            return {"found": True, "answer": answer, "page": 0, "document": "", "source": "executive",
                    "offer_callback": False, "not_advice": NOT_ADVICE[lang]}
        try:
            doc = docs[int(payload.get("doc")) - 1]
            page = int(payload.get("page"))
        except (TypeError, ValueError, IndexError):
            self._missed(item_id, asked)
            return miss
        if not answer or not _quote_on_page(_clean(payload.get("quote"), 300), index.get((doc["id"], page), "")):
            self._missed(item_id, asked)
            return miss
        return {"found": True, "answer": answer, "page": page, "document": doc["name"], "source": "document",
                "offer_callback": False, "not_advice": NOT_ADVICE[lang]}

    def _missed(self, item_id: str, question: str) -> None:
        """What customers ask that the paper does not answer (no person kept): staff see it and add the document."""
        try:
            with closing(self._connect()) as conn:
                conn.execute("INSERT INTO fin_misses (item_id, question, n, last_at) VALUES (?, ?, 1, ?)"
                             " ON CONFLICT(item_id, question) DO UPDATE SET n = n + 1, last_at = excluded.last_at",
                             (item_id, question.lower()[:200], self._now()))
                conn.commit()
        except sqlite3.Error:
            pass

    # ------------------------------------------------------------------ call back (consent first)
    def request_callback(self, item_id: str, user_id: str, *, question: str, when: str, consent: bool) -> Dict[str, Any]:
        self._finance_item(item_id, live=True)
        if consent is not True:
            raise FinanceError(400, "consent", "We call only when you say yes.")
        phone = phone_of(user_id)
        if not phone:
            raise FinanceError(409, "no_phone", "Sign in with your mobile number to get a call back.")
        when = when if when in WHEN else "now"
        with closing(self._connect()) as conn:
            same = conn.execute("SELECT id FROM fin_callbacks WHERE item_id = ? AND user_id = ? AND status = 'new'",
                                (item_id, user_id)).fetchone()
            if same is not None:
                conn.execute("UPDATE fin_callbacks SET question = ?, when_pref = ? WHERE id = ?",
                             (_clean(question, 300), when, same["id"]))
                conn.commit()
                return {"id": same["id"], "status": "new", "again": True}
            open_now = conn.execute("SELECT COUNT(*) AS n FROM fin_callbacks WHERE user_id = ? AND status = 'new'",
                                    (user_id,)).fetchone()["n"]
            if open_now >= MAX_OPEN_CALLBACKS_PER_USER:
                raise FinanceError(429, "too_many", "You already have call backs waiting. We will call you soon.")
            callback_id = "fc_" + uuid.uuid4().hex[:16]
            conn.execute("INSERT INTO fin_callbacks (id, item_id, user_id, phone, question, when_pref, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?)", (callback_id, item_id, user_id, phone, _clean(question, 300), when, self._now()))
            conn.commit()
        return {"id": callback_id, "status": "new", "again": False}

    def cancel_callback(self, user_id: str, callback_id: str) -> Dict[str, Any]:
        """The customer changes their mind: the request and the number in it are removed."""
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM fin_callbacks WHERE id = ? AND user_id = ? AND status = 'new'", (callback_id, user_id))
            conn.commit()
        return {"ok": True}

    def callbacks(self, *, status: str = "new", limit: int = 100) -> List[Dict[str, Any]]:
        """Staff list: who to call, about what -- the number MASKED (the full number only through ``reveal``)."""
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT * FROM fin_callbacks WHERE status = ? ORDER BY created_at LIMIT ?",
                                ("done" if status == "done" else "new", max(1, min(limit, 300)))).fetchall()
        out = []
        for r in rows:
            item = self.item(r["item_id"]) or {}
            out.append({"id": r["id"], "item_id": r["item_id"], "title": item.get("title") or "", "customer": mask(r["phone"]),
                        "question": r["question"], "when": r["when_pref"], "status": r["status"], "outcome": r["outcome"],
                        "created_at": r["created_at"], "done_at": r["done_at"]})
        return out

    def reveal(self, callback_id: str) -> Dict[str, Any]:
        """The number to dial, for the staff member who is about to call (the route writes the audit line)."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM fin_callbacks WHERE id = ?", (callback_id,)).fetchone()
        if row is None or row["status"] != "new":
            raise FinanceError(404, "callback", "Call back not found.")
        return {"id": row["id"], "phone": row["phone"], "item_id": row["item_id"]}

    def close_callback(self, callback_id: str, actor: str, *, outcome: str, answer: str = "", note: str = "") -> Dict[str, Any]:
        if outcome not in OUTCOMES:
            raise FinanceError(400, "outcome", "Choose what happened on the call.")
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM fin_callbacks WHERE id = ?", (callback_id,)).fetchone()
            if row is None:
                raise FinanceError(404, "callback", "Call back not found.")
            now = self._now()
            # The number is not needed after the call: it is wiped with the request closed.
            conn.execute("UPDATE fin_callbacks SET status = 'done', outcome = ?, note = ?, done_by = ?, done_at = ?, phone = ?"
                         " WHERE id = ?", (outcome, _clean(note, 300), actor, now, mask(row["phone"]), callback_id))
            said = _clean(answer, 600)
            saved = False
            if said and row["question"]:
                conn.execute("INSERT INTO fin_qa (id, item_id, question, answer, source, created_by, created_at)"
                             " VALUES (?, ?, ?, ?, 'executive', ?, ?)",
                             ("fq_" + uuid.uuid4().hex[:16], row["item_id"], row["question"], said, actor, now))
                saved = True
            conn.commit()
        return {"ok": True, "answer_saved": saved}


def _clean_page(text: Any) -> str:
    return re.sub(r"[ \t\r\f\v]+", " ", re.sub(r"\n{3,}", "\n\n", str(text or ""))).strip()[:MAX_PAGE_CHARS]


def pdf_pages(data: bytes) -> List[str]:
    """Text of each page of a PDF (pypdf); a scanned PDF gives empty pages -- the caller says so."""
    import io

    from pypdf import PdfReader

    reader = PdfReader(io.BytesIO(data))
    return [(page.extract_text() or "") for page in list(reader.pages)[:MAX_PAGES]]


IMAGE_PROMPT = (
    "This is a photo or scan of a finance company's paper (brochure, premium / rate chart, terms). Return ONLY JSON: "
    "{\"text\": string} with ALL the text exactly as printed, line by line, tables row by row (cells separated by ' | '). "
    "Do not summarise, do not add anything that is not printed.")
