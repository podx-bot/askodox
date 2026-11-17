"""Spoken menu + the front-desk "receptionist" brain (pure functions, no database, no model call).

Two jobs, one vocabulary (owner 2026-11-15: "the owner says the menu by voice; the customer asks the AI like a
receptionist"):

* ``parse_menu(text)``  -- "chicken biryani 160, fry 300, today only: mutton biryani 250" (Telugu / English / mixed,
  Telugu digits too) -> items with price, unit and daily vs today-only. The owner always reviews the result before
  anything is saved; nothing here writes.
* ``assist(text, menu, ...)`` -- one customer sentence ("2 biryani", "price of fry", "for 4 people", "same as last
  time", "that's all") -> a short reply + what to add to the cart. The answer comes ONLY from the shop's own menu
  (never invented); a sentence it cannot read returns ``intent: "unknown"`` so the app can say so honestly.

Cheap on purpose: no AI credit is spent here. A model may re-word a reply later; it never decides prices or items.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

_TELUGU_DIGITS = {ord(c): str(i) for i, c in enumerate("౦౧౨౩౪౫౬౭౮౯")}
_WORD = re.compile(r"[A-Za-z0-9ఀ-౿]+")


def normalize(text: str) -> str:
    """Lower-case, ASCII digits, one space between words; letters of every script are kept."""
    plain = str(text or "").translate(_TELUGU_DIGITS).lower().replace("₹", " ").replace("'", "").replace("\u2019", "")
    return " ".join(_WORD.findall(plain))


def tokens(text: str) -> List[str]:
    return normalize(text).split()


def _decimal_tokens(text: str) -> str:
    return str(text or "").translate(_TELUGU_DIGITS)


# --------------------------------------------------------------------------------------------- number words
NUMBER_WORDS: Dict[str, int] = {
    "ఒకటి": 1, "ఒక": 1, "ఒక్క": 1, "ఒక్కటి": 1, "one": 1, "a": 1, "an": 1,
    "రెండు": 2, "రెండ": 2, "two": 2, "ఇద్దరు": 2, "ఇద్దరికి": 2,
    "మూడు": 3, "three": 3, "ముగ్గురు": 3, "ముగ్గురికి": 3,
    "నాలుగు": 4, "four": 4, "నలుగురు": 4, "నలుగురికి": 4,
    "ఐదు": 5, "five": 5, "ఐదుగురు": 5, "ఐదుగురికి": 5,
    "ఆరు": 6, "six": 6, "ఆరుగురు": 6, "ఆరుగురికి": 6,
    "ఏడు": 7, "seven": 7, "ఏడుగురు": 7,
    "ఎనిమిది": 8, "eight": 8, "ఎనిమిదిమంది": 8,
    "తొమ్మిది": 9, "nine": 9,
    "పది": 10, "ten": 10,
}
_UNIT_WORDS = {"plate", "plates", "ప్లేట్", "ప్లేట్లు", "ప్లేటు", "ప్లేట్ల", "pcs", "piece", "pieces", "ముక్క", "ముక్కలు",
               "kg", "కేజీ", "కిలో", "కేజీలు", "glass", "గ్లాస్", "cup", "కప్పు", "packet", "ప్యాకెట్", "full", "ఫుల్", "of", "please"}
_FILLER = {"ధర", "రేటు", "రేట్", "price", "rate", "is", "are", "ఉంది", "ఉన్నాయి", "and", "మరియు", "ఇంకా", "అలాగే", "then",
           "next", "item", "items", "ఐటమ్", "ఐటమ్స్", "menu", "మెనూ", "add", "చేయండి", "ఇవ్వండి", "కావాలి", "కావాలి", "ప్లీజ్",
           "rs", "inr", "రూ", "రూపాయలు", "రూపాయి", "rupees", "rupee"}

UNIT_OF = {"plate": "plate", "plates": "plate", "ప్లేట్": "plate", "ప్లేట్లు": "plate", "ప్లేటు": "plate",
           "kg": "kg", "కేజీ": "kg", "కిలో": "kg", "pcs": "pcs", "piece": "pcs", "pieces": "pcs", "ముక్క": "pcs",
           "glass": "pcs", "గ్లాస్": "pcs", "cup": "pcs", "కప్పు": "pcs", "packet": "pack", "ప్యాకెట్": "pack"}

_TODAY = r"(?:ఈ ?రోజు(?:\s+(?:మాత్రమే|స్పెషల్))?|ఈరోజు(?:\s+(?:మాత్రమే|స్పెషల్))?|today'?s?\s+(?:only|special|menu)|today\s+only|స్పెషల్|special)"
_DAILY = r"(?:ప్రతి ?రోజు|రోజూ|రోజు ?వారీ|ఎప్పుడూ|daily|always|every ?day|regular)"
_MARKER = re.compile(rf"({_TODAY}|{_DAILY})", re.IGNORECASE)
_TODAY_RE = re.compile(rf"^{_TODAY}$", re.IGNORECASE)


def _paise(raw: str) -> Optional[int]:
    try:
        value = float(raw)
    except ValueError:
        return None
    paise = int(round(value * 100))
    return paise if 0 < paise <= 10_00_00_000_00 else None


def _clean_name(raw: str) -> Tuple[str, str]:
    """(name, unit) from the words before a price: filler / unit words leave the name, the unit is remembered."""
    words = [w for w in _WORD.findall(raw.translate(_TELUGU_DIGITS))]
    unit = ""
    kept: List[str] = []
    for w in words:
        low = w.lower()
        if low in _FILLER:
            continue
        if low in UNIT_OF:
            unit = UNIT_OF[low]
            continue
        if low in ("of", "please", "full", "ఫుల్"):
            continue
        kept.append(w)
    name = " ".join(kept).strip()
    if name and name.isascii():
        name = name[0].upper() + name[1:]
    return name[:80], unit


def parse_menu(text: str, default_unit: str = "plate") -> List[Dict[str, Any]]:
    """Spoken / typed menu -> [{name, price_paise, unit, today_only}] (later words for the same name win).

    "today only" / "ఈ రోజు స్పెషల్" before items makes the following items today-only until "daily" / "ప్రతి రోజు"; the same
    words right after a price (no colon) mean just that item.
    """
    source = _decimal_tokens(str(text or ""))
    parts = _MARKER.split(source)
    out: List[Dict[str, Any]] = []
    mode_today = False
    for index, part in enumerate(parts):
        if index % 2 == 1:  # a marker
            is_today = bool(_TODAY_RE.match(part.strip()))
            before = parts[index - 1].rstrip() if index > 0 else ""
            after = parts[index + 1].lstrip() if index + 1 < len(parts) else ""
            if is_today and out and re.search(r"\d\s*(?:/-|రూ\w*|rs\.?|rupees?)?$", before, re.IGNORECASE) and not after.startswith(":"):
                out[-1]["today_only"] = True  # "...250 today only" -> just that item
                continue
            mode_today = is_today
            continue
        # entries: words then a number (the price). Separators only help; "biryani 160 fry 300" works too.
        cleaned = re.sub(r"[,;\n।|]+", " , ", part)
        for m in re.finditer(r"([^\d,]+?)\s*(?:₹|rs\.?|రూ\.?|inr)?\s*(\d{1,6}(?:\.\d{1,2})?)\s*(?:/-|రూపాయలు|రూపాయి|rupees?)?", cleaned,
                             re.IGNORECASE):
            name, unit = _clean_name(m.group(1))
            price = _paise(m.group(2))
            if not name or price is None or not any(ch.isalpha() for ch in name):
                continue
            out.append({"name": name, "price_paise": price, "unit": unit or default_unit, "today_only": mode_today})
    seen: Dict[str, int] = {}
    unique: List[Dict[str, Any]] = []
    for item in out:
        key = normalize(item["name"])
        if key in seen:
            unique[seen[key]] = item
        else:
            seen[key] = len(unique)
            unique.append(item)
    return unique


# ------------------------------------------------------------------------------------------- the receptionist
CONFIRM_PHRASES = ("thats all", "that is all", "place order", "place the order", "confirm", "order it",
                   "అంతే", "ఇంతే", "చాలు", "కన్ఫర్మ్", "ఆర్డర్ చేయండి", "ఆర్డర్ చెయ్యండి", "ఆర్డర్ చేయి", "ఆర్డర్ పెట్టండి")
CLEAR_PHRASES = ("cancel", "clear", "start again", "క్యాన్సిల్", "అంతా తీసేయండి", "అన్నీ తీసేయండి", "మళ్ళీ మొదలు")
REMOVE_WORDS = {"remove", "delete", "తీసేయండి", "తీసేయి", "వద్దు", "తీసివేయండి"}
SPECIAL_WORDS = {"special", "specials", "స్పెషల్", "స్పెషల్స్"}
MENU_PHRASES = ("menu", "మెనూ", "ఏమున్నాయి", "ఏం ఉన్నాయి", "ఏమి ఉన్నాయి", "what do you have", "what's available", "show items",
                "list")
PRICE_WORDS = {"ధర", "రేటు", "ఎంత", "price", "cost", "rate", "how", "much"}
AVAILABLE_WORDS = {"ఉందా", "ఉన్నాయా", "ఉన్నదా", "available", "have", "stock", "దొరుకుతుందా"}
REPEAT_WORDS = {"మళ్ళీ", "మళ్లీ", "అదే", "same", "repeat", "last", "again", "usual", "ఎప్పటిలాగే", "ఎప్పటిలాగా"}
GREETING_WORDS = {"hi", "hello", "hai", "హాయ్", "హలో", "నమస్తే", "నమస్కారం"}
PEOPLE_WORDS = {"people", "persons", "members", "మందికి", "మంది", "మందిమి", "persons"}
PEOPLE_TOKENS = {"ఇద్దరికి": 2, "ముగ్గురికి": 3, "నలుగురికి": 4, "ఐదుగురికి": 5, "ఆరుగురికి": 6, "ఏడుగురికి": 7}


def _t(te: bool, en: str, tel: str) -> str:
    return tel if te else en


def rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


def _word_matches(query_word: str, item_word: str) -> bool:
    if query_word == item_word:
        return True
    shortest = min(len(query_word), len(item_word))
    if shortest < 3:
        return False
    common = 0
    for a, b in zip(query_word, item_word):
        if a != b:
            break
        common += 1
    if common >= max(3, int(0.75 * shortest)):
        return True
    # said in another script / spelled another way: "బిర్యానీ" = "biryani", "చికెన్" = "chicken" (sound skeletons)
    from app.services.name_sound import latin, same, sound

    a, b = sound(latin(query_word)), sound(latin(item_word))
    return len(a) >= 3 and len(b) >= 3 and (same(a, b) or same(b, a))


def _name_variants(item: Dict[str, Any]) -> List[List[str]]:
    """One word list per language of the item's name (English / Telugu): a sentence matches in either."""
    variants = []
    for key in ("name", "name_te"):
        words = [w for w in dict.fromkeys(tokens(item.get(key, ""))) if w not in _UNIT_WORDS and w not in _FILLER]
        if words:
            variants.append(words)
    return variants


def _item_words(item: Dict[str, Any]) -> List[str]:
    return [w for words in _name_variants(item) for w in words]


def _match_one(query: List[str], item: Dict[str, Any], blocked: Sequence[int] = ()) -> Optional[Tuple[float, List[int]]]:
    """Best (score, query positions) of this item in the sentence, ignoring positions already used by another item."""
    best: Optional[Tuple[float, List[int]]] = None
    for words in _name_variants(item):
        used: List[int] = []
        for w in words:
            for i, qw in enumerate(query):
                if qw in _FILLER or qw in NUMBER_WORDS or qw.isdigit() or i in used or i in blocked:
                    continue
                if _word_matches(qw, w):
                    used.append(i)
                    break
        if used:
            score = len(used) / len(words)
            if best is None or (score, len(used)) > (best[0], len(best[1])):
                best = (score, sorted(used))
    return best


def _match_items(query: List[str], menu: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Menu items the sentence talks about: each with the query positions it used, best first."""
    hits = []
    for item in menu:
        found = _match_one(query, item)
        if found:
            hits.append({"item": item, "score": found[0], "matched": len(found[1]), "positions": found[1]})
    hits.sort(key=lambda h: (-h["score"], -h["matched"], h["item"].get("price_paise", 0)))
    return hits


def _quantity(query: List[str], positions: List[int]) -> int:
    """The number next to an item's words ("2 biryani", "biryani two", "రెండు ప్లేట్లు బిర్యానీ"); default 1."""
    lo, hi = min(positions), max(positions)
    best: Optional[Tuple[int, int]] = None
    for i, q in enumerate(query):
        value = int(q) if q.isdigit() and len(q) <= 3 else NUMBER_WORDS.get(q)
        if value is None or not 1 <= value <= 50:
            continue
        distance = lo - i if i < lo else (i - hi if i > hi else 0)
        if distance > 3:
            continue
        if best is None or distance < best[0]:
            best = (distance, value)
    return best[1] if best else 1


def _line(item: Dict[str, Any], qty: int) -> Dict[str, Any]:
    return {"product_id": item["id"], "name": item["name"], "qty": qty, "price_paise": int(item.get("price_paise") or 0)}


def _describe(menu: Sequence[Dict[str, Any]], te: bool, limit: int = 8) -> str:
    shown = [f"{m['name']} {rupees(int(m['price_paise']))}" for m in menu[:limit]]
    more = len(menu) - limit
    tail = _t(te, f" and {more} more", f" ఇంకా {more}") if more > 0 else ""
    return ", ".join(shown) + tail


def assist(text: str, menu: Sequence[Dict[str, Any]], *, te: bool = True, cart: Optional[Sequence[Dict[str, Any]]] = None,
           last_items: Optional[Sequence[Dict[str, Any]]] = None, popular: Optional[Dict[str, int]] = None) -> Dict[str, Any]:
    """Reads one sentence. ``menu`` = items {id, name, name_te?, price_paise, today_only?, available?}.

    Returns {intent, reply, add: [{product_id, name, qty, price_paise}], remove: [product_id], suggest: [...],
    confirm: bool, clear: bool, name: str|None, options: [...]}. Never adds an unavailable item.
    """
    raw = str(text or "")
    q = tokens(raw)
    norm = " ".join(q)
    base: Dict[str, Any] = {"intent": "unknown", "reply": "", "add": [], "remove": [], "suggest": [], "confirm": False,
                            "clear": False, "name": None, "options": []}
    if not q:
        base["reply"] = _t(te, "Please tell me what you would like.", "మీకు ఏం కావాలో చెప్పండి.")
        return base
    live = [m for m in menu if m.get("available", True)]
    popular = popular or {}

    # name: "నా పేరు Ravi" / "my name is Ravi"
    m = re.search(r"(?:నా పేరు|my name is|name is)\s+([A-Za-zఀ-౿ ]{2,30})", raw, re.IGNORECASE)
    if m:
        base.update(intent="name", name=m.group(1).strip().title(),
                    reply=_t(te, f"Nice to meet you, {m.group(1).strip().title()}. What would you like?",
                             f"నమస్తే {m.group(1).strip()}! మీకు ఏం కావాలి?"))
        return base

    if any(p in norm for p in CLEAR_PHRASES):
        base.update(intent="clear", clear=True, reply=_t(te, "Cleared. Tell me again what you want.", "తీసేశాను. మళ్ళీ ఏం కావాలో చెప్పండి."))
        return base
    if any(p in norm for p in CONFIRM_PHRASES):
        if not cart:
            base["reply"] = _t(te, "Your list is empty. Tell me what you would like first.", "మీ లిస్ట్ ఖాళీగా ఉంది. ముందు ఏం కావాలో చెప్పండి.")
            base["intent"] = "confirm_empty"
            return base
        total = sum(int(c.get("price_paise", 0)) * int(c.get("qty", 1)) for c in cart)
        base.update(intent="confirm", confirm=True,
                    reply=_t(te, f"Placing your order, total about {rupees(total)}.", f"మీ ఆర్డర్ పెడుతున్నాను, మొత్తం సుమారు {rupees(total)}."))
        return base

    if set(q) & GREETING_WORDS and len(q) <= 3:
        base.update(intent="greeting", reply=_t(te, "Welcome! Ask for the menu, today's special, or just tell me what you want.",
                                               "స్వాగతం! మెనూ, ఈ రోజు స్పెషల్ అడగండి, లేదా ఏం కావాలో చెప్పండి."))
        return base

    hits = _match_items(q, live)
    strong = [h for h in hits if h["score"] >= 0.99]

    # remove
    if set(q) & REMOVE_WORDS and hits:
        base.update(intent="remove", remove=[hits[0]["item"]["id"]],
                    reply=_t(te, f"Removed {hits[0]['item']['name']}.", f"{hits[0]['item']['name']} తీసేశాను."))
        return base

    # specials
    if set(q) & SPECIAL_WORDS or "ఈ రోజు" in norm or "today" in q:
        specials = [m for m in live if m.get("today_only")]
        if specials and not strong:
            base.update(intent="special", options=[_line(m, 1) for m in specials],
                        reply=_t(te, "Today's special: " + _describe(specials, False), "ఈ రోజు స్పెషల్: " + _describe(specials, True)))
            return base
        if not specials and not strong and (set(q) & SPECIAL_WORDS):
            base.update(intent="special", reply=_t(te, "There is no special today. Here is the menu: " + _describe(live, False),
                                                   "ఈ రోజు ప్రత్యేకం ఏదీ లేదు. మెనూ: " + _describe(live, True)))
            return base

    # people: "for 4 people" / "నలుగురికి"
    people = next((PEOPLE_TOKENS[w] for w in q if w in PEOPLE_TOKENS), None)
    if people is None and (set(q) & PEOPLE_WORDS or "for" in q):
        number = next((int(w) for w in q if w.isdigit() and 1 <= int(w) <= 60), None)
        if number is not None and (set(q) & PEOPLE_WORDS or "for" in q):
            people = number
    if people and not strong and live:
        ranked = sorted(live, key=lambda m: (not m.get("today_only"), -popular.get(m["id"], 0), int(m.get("price_paise", 0))))
        k = max(1, min(3, len(ranked), people))
        picks = ranked[:k]
        base_qty, extra = divmod(people, k)
        lines = [_line(m, max(1, base_qty + (1 if i < extra else 0))) for i, m in enumerate(picks)]
        total = sum(l["price_paise"] * l["qty"] for l in lines)
        said = ", ".join(f"{l['name']} ×{l['qty']}" for l in lines)
        base.update(intent="suggest", suggest=lines,
                    reply=_t(te, f"For {people} people I suggest {said}, about {rupees(total)}. Add these?",
                             f"{people} మందికి ఇవి బాగుంటాయి: {said}, సుమారు {rupees(total)}. చేర్చమంటారా?"))
        return base

    # price / availability of a named item
    if hits and (set(q) & PRICE_WORDS or "how much" in norm):
        item = hits[0]["item"]
        base.update(intent="price", options=[_line(item, 1)],
                    reply=_t(te, f"{item['name']} is {rupees(int(item['price_paise']))}.", f"{item['name']} ధర {rupees(int(item['price_paise']))}."))
        return base
    if set(q) & AVAILABLE_WORDS or "do you have" in norm:
        if hits:
            item = hits[0]["item"]
            base.update(intent="available", options=[_line(item, 1)],
                        reply=_t(te, f"Yes, {item['name']} is available at {rupees(int(item['price_paise']))}.",
                                 f"అవును, {item['name']} ఉంది, ధర {rupees(int(item['price_paise']))}."))
            return base
        wanted = [w for w in q if w not in AVAILABLE_WORDS and w not in _FILLER and not w.isdigit()]
        sold = [m for m in menu if not m.get("available", True) and any(_word_matches(w, x) for w in wanted for x in _item_words(m))]
        if sold:
            base.update(intent="unavailable", reply=_t(te, f"Sorry, {sold[0]['name']} is finished for today.", f"క్షమించండి, {sold[0]['name']} ఈ రోజు అయిపోయింది."))
            return base

    # same as last time
    if set(q) & REPEAT_WORDS and last_items and not strong:
        usable = [l for l in last_items if any(m["id"] == l.get("product_id") for m in live)]
        if usable:
            lines = [_line(next(m for m in live if m["id"] == l["product_id"]), int(l.get("qty") or 1)) for l in usable]
            said = ", ".join(f"{l['name']} ×{l['qty']}" for l in lines)
            base.update(intent="repeat", add=lines, reply=_t(te, f"Same as last time: {said}. Anything else?", f"మునుపటిలాగే: {said}. ఇంకేమైనా?"))
            return base

    # menu
    if any(p in norm for p in MENU_PHRASES) and not strong:
        if not live:
            base["reply"] = _t(te, "Nothing is available right now.", "ఇప్పుడు ఏదీ అందుబాటులో లేదు.")
            return base
        base.update(intent="menu", options=[_line(m, 1) for m in live[:12]], reply=_t(te, "We have: " + _describe(live, False), "ఇవి ఉన్నాయి: " + _describe(live, True)))
        return base

    # order: items with quantities (greedy, each query word used once)
    if hits:
        top = hits[0]
        tied = [h for h in hits if h["positions"] == top["positions"] and h["score"] == top["score"]]
        if len(tied) > 1 and top["score"] < 0.99:  # "biryani" matches two different biryanis: ask which
            options = [_line(h["item"], 1) for h in tied[:5]]
            base.update(intent="clarify", options=options,
                        reply=_t(te, "Which one? " + ", ".join(f"{o['name']} {rupees(o['price_paise'])}" for o in options),
                                 "ఏది కావాలి? " + ", ".join(f"{o['name']} {rupees(o['price_paise'])}" for o in options)))
            return base
        consumed: set = set()
        add: List[Dict[str, Any]] = []
        for h in hits:
            found = _match_one(q, h["item"], consumed)
            if found is None:
                continue
            score, positions = found
            if score >= 0.99 or (h is top and score >= 0.5):
                add.append(_line(h["item"], _quantity(q, positions)))
                consumed |= set(positions)
        if add:
            said = ", ".join(f"{a['name']} ×{a['qty']}" for a in add)
            base.update(intent="order", add=add, reply=_t(te, f"Added {said}. Anything else? Say 'that's all' to order.",
                                                          f"చేర్చాను: {said}. ఇంకేమైనా? ఆర్డర్ చేయాలంటే 'అంతే' అనండి."))
            return base

    base["reply"] = _t(te, "I could not find that on our menu. Say 'menu' to hear what we have.",
                       "ఇది మా మెనూలో కనబడలేదు. ఏమున్నాయో వినాలంటే 'మెనూ' అనండి.")
    return base


def people_estimate(text: str) -> Optional[int]:
    """How many people a sentence talks about (for tests / the app), or None."""
    q = tokens(text)
    return next((PEOPLE_TOKENS[w] for w in q if w in PEOPLE_TOKENS), None) or next(
        (int(w) for w in q if w.isdigit() and 1 <= int(w) <= 60 and (set(q) & PEOPLE_WORDS or "for" in q)), None)


__all__ = ["parse_menu", "assist", "normalize", "tokens", "rupees", "people_estimate"]
