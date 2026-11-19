"""A bill made inside the main chat (owner 2026-11-19): a shop's owner / staff says item NUMBERS ("bill 1 2, 3 1",
"#4 x3", or just "1 2, 3 1") and the chat shows the bill from the shop's OWN item numbers -- no AI call, no guessing.

Rules:
- Only for a person who may sell in a POS business (owner / manager / cashier); everyone else gets None.
- A number that is not on the shop's menu is listed as unknown -- never matched to a "close" item, never asked by name.
- Nothing is billed here: the card is a preview. The real bill is made by the same quick-bill API the Bill screen uses
  (``POST /api/pos/businesses/{id}/quick-bill`` with ``item_no`` + ``count`` lines), on one tap in the chat.
Universal: any shop type (hotel, kirana, tiffin, clothes ...) -- it only reads the shop's own numbered items.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from app.services.pos_store import PERMISSIONS, PosStore

_BILL_WORD = re.compile(r"\bbill\b|\bbilling\b|బిల్|बिल", re.IGNORECASE)
_MARK = r"(?:#|\bno\.?|\bnumber\b|\bitem\b|నంబర్|నెంబర్|నంబరు|नंबर)"
_QTY_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "ఒకటి": 1, "ఒక": 1, "రెండు": 2, "మూడు": 3, "నాలుగు": 4, "ఐదు": 5, "ఆరు": 6, "ఏడు": 7, "ఎనిమిది": 8,
    "తొమ్మిది": 9, "పది": 10,
    "एक": 1, "दो": 2, "तीन": 3, "चार": 4, "पांच": 5, "पाँच": 5, "छह": 6, "सात": 7, "आठ": 8, "नौ": 9, "दस": 10,
}
_SPLIT = re.compile(r"[,;\n+]|\band\b|మరియు|और")
# What may stand around the numbers in a "numbers only" message (no bill word): marks, x, quantity words, fillers.
_FILLER = re.compile(r"(?:#|\bx\b|\*|\bqty\b|\bno\.?|\bnumber\b|\bitem\b|నంబర్|నెంబర్|నంబరు|नंबर|\bplates?\b|ప్లేట్లు|ప్లేట్)",
                     re.IGNORECASE)
MAX_LINES = 40


def _qty_word(segment: str) -> Optional[int]:
    for word in re.findall(r"[^\s\d,;#x*]+", segment.lower()):
        if word in _QTY_WORDS:
            return _QTY_WORDS[word]
    return None


def _segment(segment: str) -> Optional[Tuple[int, int]]:
    """One "item number + count" piece -> (item_no, count), or None."""
    text = re.sub(r"(\d)\s*[x*×]\s*(\d)", r"\1 \2", segment.lower())
    marked = re.search(_MARK + r"\s*(\d{1,4})", text)
    if marked:
        item = int(marked.group(1))
        rest = (text[:marked.start()] + " " + text[marked.end():])
        others = re.findall(r"\d{1,3}", rest)
        count = int(others[0]) if others else (_qty_word(rest) or 1)
    else:
        numbers = re.findall(r"\d{1,4}", text)
        if not numbers:
            return None
        item = int(numbers[0])
        count = int(numbers[1]) if len(numbers) > 1 else (_qty_word(text) or 1)
    if item <= 0 or count <= 0 or count > 999:
        return None
    return item, count


def parse(text: str) -> List[Tuple[int, int]]:
    """Item-number lines from a bill message; [] when the message is not a number bill."""
    raw = str(text or "").strip()
    if not raw or len(raw) > 400 or not re.search(r"\d", raw):
        return []
    has_word = bool(_BILL_WORD.search(raw))
    body = _BILL_WORD.sub(" ", raw)
    if not has_word:
        # Without the word "bill" only a message made of numbers (and marks / quantity words) counts.
        leftover = _FILLER.sub(" ", body)
        leftover = re.sub(r"(?i)(?<![a-z])[x×](?![a-z])", " ", leftover)  # "1x2", "#4 x3"
        leftover = re.sub(r"[\d\s,;+.\-]", " ", leftover)
        words = [w for w in leftover.split() if w.lower() not in _QTY_WORDS]
        if words:
            return []
    lines = [line for line in (_segment(s) for s in _SPLIT.split(body)) if line]
    marked = re.search(_MARK, raw, re.IGNORECASE) or re.search(r"\d\s*[x×*]\s*\d|(?<![a-z])x\s*\d", raw, re.IGNORECASE)
    if not has_word and len(lines) == 1 and not marked and not re.search(r"[,;+]|\d\s+\d", raw):
        return []  # a lone number ("5") is an answer to something, not a bill
    return lines[:MAX_LINES]


class PosChatBill:
    def __init__(self, store: PosStore) -> None:
        self.store = store

    def _shop(self, user: str) -> Optional[Dict[str, Any]]:
        """The shop this person bills for: one they may sell in, the one with the latest bill first."""
        shops = [s for s in self.store.my_businesses(user) if "sell" in PERMISSIONS.get(str(s.get("role")), ())]
        if not shops:
            return None
        if len(shops) == 1:
            return shops[0]
        with self.store._connect() as conn:
            def last(shop: Dict[str, Any]) -> str:
                row = conn.execute("SELECT MAX(issued_at) AS t FROM pos_invoices WHERE business_id = ?",
                                   (shop["id"],)).fetchone()
                return str(row["t"] or "") if row else ""
            return max(shops, key=last)

    def card(self, user: str, text: str) -> Optional[Dict[str, Any]]:
        """The bill preview for a number message, or None (not a number bill / not someone who sells)."""
        if not str(user or "").startswith("app-"):
            return None
        lines = parse(text)
        if not lines:
            return None
        shop = self._shop(user)
        if shop is None:
            return None
        from app.services.pos_bills import PosBills

        bills = PosBills(self.store)
        out_lines: List[Dict[str, Any]] = []
        unknown: List[int] = []
        with self.store._connect() as conn:
            for item_no, count in lines:
                row = bills.item_by_number(conn, shop["id"], item_no)
                if row is None:
                    if item_no not in unknown:
                        unknown.append(item_no)
                    continue
                price = int(row["price_paise"] or 0)
                out_lines.append({"item_no": item_no, "name": row["name"], "unit": row["unit"] or "pcs",
                                  "price_paise": price, "count": count, "amount_paise": price * count})
        return {"business_id": shop["id"], "shop_name": shop.get("name") or "", "lines": out_lines,
                "unknown": unknown, "total_paise": sum(l["amount_paise"] for l in out_lines)}


def reply_text(card: Dict[str, Any], te: bool) -> str:
    """The chat line above the card: what is ready and what is missing, never a guess."""
    unknown = ", ".join(f"#{n}" for n in card.get("unknown") or [])
    if not card.get("lines"):
        return (f"{unknown} నంబర్లు {card['shop_name']} మెనూలో లేవు. సరైన నంబర్ చెప్పండి."
                if te else f"{unknown} is not on {card['shop_name']}'s menu. Say the right number.")
    head = ("బిల్లు సిద్ధం. చూసి, ఎలా కట్టారో ఎంచుకుని \"బిల్లు చేయి\" నొక్కండి."
            if te else "Bill ready. Check it, pick how it was paid and tap \"Make bill\".")
    if unknown:
        head += (f" {unknown} మెనూలో లేదు — దాన్ని వదిలేశాను." if te else f" {unknown} is not on the menu — left out.")
    return head
