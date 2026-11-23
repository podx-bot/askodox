"""Sort a shop's existing menu into sections + veg / non-veg / egg with ONE model reading of the item names
(owner 2026-11-17: "73 items have no section"). Nothing is saved here: the owner sees the preview, fixes any line and
then saves. The model only reads the names it is given; an item it cannot place keeps what it had."""

from __future__ import annotations

import json
import re
from typing import Any, Callable, Dict, List

PROMPT = (
    "You sort the items of ONE shop's menu. For each numbered item name (any language), give the menu section it "
    "belongs to and whether it is veg, nonveg or egg. Use at most 8 short sections that suit THIS menu, written the "
    "way Indian menus print them in English (e.g. Biryani, Starters, Curries, Rice, Rotis, Drinks, Desserts, Tiffins) "
    "-- the same spelling for every item of one section. food = veg / nonveg / egg only when the name makes it clear "
    "(chicken, mutton, fish, prawn, egg, paneer, dal ...), else leave it empty. Answer with ONE short line per item and "
    "nothing else, exactly number|section|food -- e.g. 3|Biryani|nonveg or 7|Drinks| -- no JSON, no notes.\nItems:\n"
)


_PREFIX = re.compile(r"^\s*(?:no\.?\s*)?(\d{1,4})\s*[).:\-]\s*(.+)$", re.I)


def clean_name(name: str) -> tuple:
    """"68) Haravara Chicken" -> ("Haravara Chicken", 68). A photo-read menu keeps the printed number in the name."""
    match = _PREFIX.match(str(name or ""))
    if not match or not match.group(2).strip():
        return str(name or "").strip(), None
    return match.group(2).strip(), int(match.group(1))


_PRINTED_NO = re.compile(r"^\s*(?:no\.?\s*)?(\d{1,4})\s*(?:[).:]|-(?=\s))\s*(\S.*)$", re.I)


def printed_number(name: str) -> tuple:
    """Stricter than ``clean_name`` (for automatic cleaning): "117) Fish Biryani" / "12. Tea" / "5 - Dosa" ->
    (name, number); "7-Up", "500 ml Coke", "2 Idli" are left alone."""
    match = _PRINTED_NO.match(str(name or ""))
    if not match:
        return str(name or "").strip(), None
    return match.group(2).strip(), int(match.group(1))


def _key(group: str) -> str:
    return re.sub(r"[^a-z0-9\u0c00-\u0c7f]+", "", group.lower()).rstrip("s")


def sort_menu(items: List[Dict[str, Any]], write_text: Callable[..., str], chunk: int = 25,
              workers: int = 6) -> Dict[str, Any]:
    """items: [{id, name, menu_group, food_type}] -> preview rows (the old values kept where the model is silent).

    Owner 2026-11-18: 193 items took longer than the phone waited ("no internet"). The parts are now read AT THE SAME
    TIME (``workers``) and spellings of one section are merged afterwards ("Biryani" / "Biryanis" / "biryani").
    Owner 2026-11-22/23 (three 503s in the deploy log, "claude answer cut at max_tokens" on all 4 parts of a 150+ item
    menu): parts are 25 items, the answer is one short line per item, a CUT answer still gives every line it finished,
    and the items no part answered are asked once more -- one cut part never makes the whole menu unreadable."""
    from concurrent.futures import ThreadPoolExecutor

    numbered = [(n + 1, it) for n, it in enumerate(items)]

    def read(part: List[tuple]) -> Dict[int, Dict[str, Any]]:
        # Every item keeps ONE number in every part and in the second reading, so an answer can only land on the
        # item it names.
        listing = "\n".join(f"{n}. {clean_name(it.get('name'))[0][:80]}" for n, it in part)
        try:
            return _parse(write_text(PROMPT + listing, max_tokens=40 * len(part) + 200) or "")
        except Exception:
            return {}

    def read_all(chosen: List[tuple]) -> Dict[int, Dict[str, Any]]:
        parts = [chosen[i:i + chunk] for i in range(0, len(chosen), chunk)]
        if not parts:
            return {}
        with ThreadPoolExecutor(max_workers=max(1, min(workers, len(parts)))) as pool:
            answers = list(pool.map(read, parts))
        got: Dict[int, Dict[str, Any]] = {}
        for part, found in zip(parts, answers):
            for n, _ in part:
                row = found.get(n)
                if row and str(row.get("group") or "").strip():
                    got[n] = row
        return got

    found_by_no = read_all(numbered)
    missing = [(n, it) for n, it in numbered if n not in found_by_no]
    if missing:
        # one more reading for the items no part answered (a cut answer, a failed part)
        found_by_no.update(read_all(missing))
    read_any = bool(found_by_no)
    out: List[Dict[str, Any]] = []
    groups: List[str] = []
    spelled: Dict[str, str] = {}
    for n, it in numbered:
        got = found_by_no.get(n, {})
        raw_group = re.sub(r"\s+", " ", str(got.get("group") or "")).strip()[:40]
        if raw_group and raw_group not in groups:
            groups.append(raw_group)
        group = spelled.setdefault(_key(raw_group), raw_group) if raw_group else str(it.get("menu_group") or "")
        food = str(got.get("food") or "").lower().replace("-", "").replace(" ", "")
        food = food if food in ("veg", "nonveg", "egg") else str(it.get("food_type") or "")
        if group and group not in groups:
            groups.append(group)
        name, number = clean_name(it.get("name"))
        out.append({"id": it["id"], "name": name, "item_no": number,
                    "menu_group": group, "food_type": food,
                    "changed": group != (it.get("menu_group") or "") or food != (it.get("food_type") or "")
                    or name != str(it.get("name") or "").strip()})
    # One spelling per section: the title-cased one the model used most.
    best: Dict[str, str] = {}
    for g in groups:
        k = _key(g)
        if k not in best or (g[:1].isupper() and not best[k][:1].isupper()):
            best[k] = g
    for r in out:
        if r["menu_group"]:
            r["menu_group"] = best.get(_key(r["menu_group"]), r["menu_group"])
    groups = list(dict.fromkeys(best.get(_key(g), g) for g in groups))
    counts = {g: sum(1 for r in out if r["menu_group"] == g) for g in groups}
    return {"items": out, "groups": groups, "counts": counts, "read": read_any}


def _parse(raw: str) -> Dict[int, Dict[str, Any]]:
    """Every row the model FINISHED, even when the answer was cut: short lines "3|Biryani|nonveg" (the asked shape) and
    {"i": 3, "group": .., "food": ..} objects (the older shape, read one object at a time)."""
    out: Dict[int, Dict[str, Any]] = {}
    text = raw or ""
    for match in re.finditer(r"\{[^{}]*\}", text):
        try:
            row = json.loads(match.group(0))
        except ValueError:
            continue
        if isinstance(row, dict) and "i" in row:
            try:
                out[int(row.get("i"))] = {"group": row.get("group") or "", "food": row.get("food") or ""}
            except (TypeError, ValueError):
                continue
    lines = [ln for ln in text.splitlines() if ln.strip()]
    for k, line in enumerate(lines):
        if "|" not in line:
            continue
        cells = [c.strip().strip("`*\"'") for c in line.strip().split("|")]
        if cells and not cells[0]:
            cells = cells[1:]  # "| 3 | Biryani | nonveg |"
        number = re.sub(r"\D", "", cells[0]) if cells else ""
        if not number or len(cells) < 2 or not cells[1]:
            continue
        if len(cells) < 3 and k == len(lines) - 1 and not text.endswith("\n"):
            continue  # the answer stopped in the middle of this line: "25|Bir" is not a section
        out.setdefault(int(number), {"group": cells[1], "food": cells[2] if len(cells) > 2 else ""})
    return out


class MenuSortJobs:
    """Owner 2026-11-23: "stay on this page for 1-2 minutes" is gone. The reading runs in the background (one at a
    time per shop); the phone may leave and come back, and gets a notification when it is ready. Results live in this
    process for ``keep_s`` (the preview is never saved until the owner taps Save)."""

    def __init__(self, keep_s: int = 1800, clock: Callable[[], float] = None) -> None:
        import threading
        import time

        self._lock = threading.Lock()
        self._jobs: Dict[str, Dict[str, Any]] = {}
        self.keep_s = keep_s
        self.clock = clock or time.time

    def _view(self, job: Dict[str, Any]) -> Dict[str, Any]:
        out: Dict[str, Any] = {"status": job["status"],
                               "seconds": int((job.get("finished_at") or self.clock()) - job["started_at"])}
        if job["status"] == "done":
            out.update(job.get("result") or {})
        return out

    def get(self, business_id: str) -> Dict[str, Any]:
        with self._lock:
            job = self._jobs.get(business_id)
            if job and job.get("finished_at") and self.clock() - job["finished_at"] > self.keep_s:
                self._jobs.pop(business_id, None)
                job = None
            return self._view(job) if job else {"status": "none"}

    def clear(self, business_id: str) -> None:
        with self._lock:
            self._jobs.pop(business_id, None)

    def start(self, business_id: str, run: Callable[[], Dict[str, Any]],
              on_done: Callable[[Dict[str, Any]], None] = None, wait: bool = False) -> Dict[str, Any]:
        """Starts a reading unless one is running for this shop (that one is returned). ``wait`` (tests) runs it now."""
        import threading

        with self._lock:
            job = self._jobs.get(business_id)
            if job and job["status"] == "running":
                return self._view(job)
            job = {"status": "running", "started_at": self.clock()}
            self._jobs[business_id] = job

        def work() -> None:
            try:
                result = run() or {}
                status = "done" if result.get("read") else "failed"
            except Exception:
                result, status = {}, "failed"
            with self._lock:
                job.update(status=status, result=result, finished_at=self.clock())
            if on_done:
                try:
                    on_done(self._view(job))
                except Exception:
                    pass  # a push problem never loses the result

        if wait:
            work()
        else:
            threading.Thread(target=work, daemon=True).start()
        return self._view(job)
