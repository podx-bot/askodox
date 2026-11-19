"""Supplier BILL PHOTO -> one review screen -> stock, items, supplier ledger and input GST (owner 2026-11-19).

"One photo of the bill should fill supplier, items, stock, catalogue and GST; the app asks only about what is missing;
the job finishes in one or two steps."

Step 1 ``preview``: the photo is read (any language, printed or hand-written). Nothing is saved. Every line is matched to
the shop's own item by name; a line that matches nothing is a NEW item. What the photo does not clearly show stays empty
and is listed under ``ask`` -- the reader never guesses a number.
Step 2 ``save``: the owner's confirmed list is recorded with the SAME ``record_purchase`` every hand-typed bill uses
(stock moves, batches / expiry, supplier ledger, input tax, audit). A missing supplier / item is created first, found
again by name on a retry (so a repeated tap never makes two).

The GST rate printed on the bill is the SUPPLIER's classification, shown for the owner to confirm; a rate that is not a
legal slab is dropped to "choose" rather than rounded.
"""
from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional, Sequence, Tuple

from app.services import pos_tax
from app.services.pos_store import UNITS, PosError

MAX_PHOTOS = 4
MAX_LINES = 300

PROMPT = (
    "You read a photo of a PURCHASE BILL / invoice a shop received from its supplier or distributor (printed or "
    "hand-written, any Indian language or English). Return ONLY JSON: {\"supplier\": {\"name\": string or null, "
    "\"gstin\": string or null, \"phone\": string or null}, \"bill_no\": string or null, \"bill_date\": \"YYYY-MM-DD\" "
    "or null, \"total\": number or null, \"lines\": [{\"name\": string, \"qty\": number or null, \"unit\": string or "
    "null, \"cost\": number or null, \"gst_percent\": number or null, \"mrp\": number or null, \"batch\": string or "
    "null, \"expiry\": \"YYYY-MM-DD\" or null}]}. Rules: supplier = the SELLER printed at the top (not the buyer); "
    "one line per item row, name as printed; qty = the quantity bought; cost = the price of ONE unit BEFORE GST (if "
    "only the line amount is printed, divide it by qty; if the bill says prices include tax, remove the tax); "
    "gst_percent = the GST % printed for that line (CGST + SGST together, or IGST), null if not printed; mrp = the "
    "MRP printed for that item, else null; expiry = the expiry date printed for that item (use the last day of the "
    "month when only month / year is printed), else null; total = the final bill amount. A value that is not clearly "
    "readable is null -- NEVER guess. Skip headings, bank details, terms and tax summary rows."
)

_UNIT_WORDS = {"pcs": "pcs", "pc": "pcs", "piece": "pcs", "pieces": "pcs", "nos": "pcs", "no": "pcs", "unit": "pcs",
               "kg": "kg", "kgs": "kg", "g": "g", "gm": "g", "gms": "g", "gram": "g", "l": "l", "ltr": "l",
               "litre": "l", "ml": "ml", "box": "box", "case": "box", "cs": "box", "pkt": "pack", "pack": "pack",
               "packet": "pack", "btl": "pcs", "bottle": "pcs", "dozen": "dozen", "dz": "dozen", "plate": "plate"}


def norm(name: Any) -> str:
    return re.sub(r"[^\w]+", " ", str(name or "").lower(), flags=re.UNICODE).strip()


def _number(value: Any) -> Optional[float]:
    try:
        if value is None or isinstance(value, bool):
            return None
        out = float(str(value).replace(",", "").replace("₹", "").replace("Rs.", "").replace("%", "").strip())
    except (TypeError, ValueError):
        return None
    return out if out >= 0 else None


def _date(value: Any) -> str:
    text = str(value or "").strip()
    return text if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text) else ""


def _unit(value: Any) -> str:
    unit = _UNIT_WORDS.get(str(value or "").strip().lower().rstrip("."), "pcs")
    return unit if unit in UNITS else "pcs"


def read_bill(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    """[(bytes, mime)] -> the bill as plain data. ``read`` False = the reader gave nothing (never raises)."""
    photos = [(data, mime) for data, mime in list(images)[:MAX_PHOTOS] if data]
    empty = {"read": False, "supplier": {"name": "", "gstin": "", "phone": ""}, "bill_no": "", "bill_date": "",
             "total_paise": None, "lines": []}
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return empty

    def one(photo: Tuple[bytes, str]) -> Any:
        try:
            try:
                payload, _calls = image_service.analyze_with_prompt([photo], PROMPT, max_models=2,
                                                                    allow_second_provider=True, fast=True)
            except TypeError:
                payload, _calls = image_service.analyze_with_prompt([photo], PROMPT, max_models=2,
                                                                    allow_second_provider=True)
        except Exception:
            return None
        return payload if isinstance(payload, dict) else None

    if len(photos) == 1:
        pages = [one(photos[0])]
    else:
        with ThreadPoolExecutor(max_workers=len(photos)) as pool:
            pages = list(pool.map(one, photos))
    pages = [p for p in pages if p]
    if not pages:
        return empty
    out = dict(empty, read=True, supplier=dict(empty["supplier"]))
    for page in pages:  # a long bill photographed in parts: the header from the first page that has it
        supplier = page.get("supplier") if isinstance(page.get("supplier"), dict) else {}
        for key in ("name", "gstin", "phone"):
            if not out["supplier"][key] and supplier.get(key):
                out["supplier"][key] = re.sub(r"\s+", " ", str(supplier[key])).strip()[:80]
        if not out["bill_no"] and page.get("bill_no"):
            out["bill_no"] = re.sub(r"\s+", " ", str(page["bill_no"])).strip()[:40]
        if not out["bill_date"]:
            out["bill_date"] = _date(page.get("bill_date"))
        total = _number(page.get("total"))
        if total:
            out["total_paise"] = int(round(total * 100))  # the last page carries the final amount
        for entry in page.get("lines") if isinstance(page.get("lines"), list) else []:
            if not isinstance(entry, dict) or len(out["lines"]) >= MAX_LINES:
                continue
            name = re.sub(r"\s+", " ", str(entry.get("name") or "")).strip()[:80]
            if len(norm(name)) < 2:
                continue
            qty, cost, gst, mrp = (_number(entry.get(k)) for k in ("qty", "cost", "gst_percent", "mrp"))
            rate_bp = int(round(gst * 100)) if gst is not None else None
            out["lines"].append({
                "name": name, "unit": _unit(entry.get("unit")),
                "qty_milli": int(round(qty * 1000)) if qty else None,
                "cost_paise": int(round(cost * 100)) if cost is not None else None,
                "rate_bp": rate_bp if rate_bp in pos_tax.ALLOWED_RATES_BP else None,
                "mrp_paise": int(round(mrp * 100)) if mrp else None,
                "batch_no": re.sub(r"\s+", " ", str(entry.get("batch") or "")).strip()[:40],
                "expiry_date": _date(entry.get("expiry")),
            })
    out["supplier"]["gstin"] = out["supplier"]["gstin"].upper().replace(" ", "")
    return out


class PosBillPhoto:
    def __init__(self, store: Any, purchases: Any) -> None:
        self.store = store
        self.purchases = purchases

    def _catalogue(self, business_id: str, user: str) -> Tuple[Dict[str, Dict[str, Any]], List[Dict[str, Any]]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            products = {norm(r["name"]): dict(r) for r in conn.execute(
                "SELECT id, name, unit, rate_bp, price_paise, track_batches FROM pos_products WHERE business_id = ? AND"
                " active = 1", (business_id,))}
            suppliers = [dict(r) for r in conn.execute(
                "SELECT id, name, gstin FROM pos_suppliers WHERE business_id = ?", (business_id,))]
        return products, suppliers

    @staticmethod
    def _find_supplier(suppliers: List[Dict[str, Any]], name: str, gstin: str) -> Optional[Dict[str, Any]]:
        for s in suppliers:
            if gstin and (s["gstin"] or "") == gstin:
                return s
        key = norm(name)
        for s in suppliers:
            if key and norm(s["name"]) == key:
                return s
        return None

    def preview(self, business_id: str, user: str, images: Sequence[Tuple[bytes, str]], image_service: Any) -> Dict[str, Any]:
        products, suppliers = self._catalogue(business_id, user)
        bill = read_bill(image_service, images)
        found = self._find_supplier(suppliers, bill["supplier"]["name"], bill["supplier"]["gstin"])
        gstin_ok = bool(bill["supplier"]["gstin"]) and pos_tax.validate_gstin(bill["supplier"]["gstin"])["valid"]
        if not gstin_ok:
            bill["supplier"]["gstin"] = ""
        ask: List[str] = []
        if not found and not bill["supplier"]["name"]:
            ask.append("supplier")
        if not bill["bill_no"]:
            ask.append("bill_no")
        for n, line in enumerate(bill["lines"]):
            match = products.get(norm(line["name"]))
            line["product_id"] = match["id"] if match else None
            line["new"] = match is None
            if match:
                line["unit"] = match["unit"]
                if line["rate_bp"] is None:
                    line["rate_bp"] = match["rate_bp"]
            # a NEW item needs the shop's selling price: the MRP when printed, otherwise the owner types it
            line["price_paise"] = match["price_paise"] if match else line["mrp_paise"]
            missing = [k for k in ("qty_milli", "cost_paise") if line[k] is None]
            if line["new"] and line["price_paise"] is None:
                missing.append("price_paise")
            if line["rate_bp"] is None:
                line["rate_bp"] = 0
                if gstin_ok or (found and found["gstin"]):
                    missing.append("rate_bp")
            line["ask"] = missing
            if missing:
                ask.append(f"line:{n}")
        return {**bill, "supplier_id": found["id"] if found else None,
                "supplier_name": found["name"] if found else bill["supplier"]["name"],
                "ask": ask, "new_items": sum(1 for line in bill["lines"] if line["new"])}

    def save(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        products, suppliers = self._catalogue(business_id, user)
        raw_lines = list(data.get("lines") or [])
        if not raw_lines or len(raw_lines) > MAX_LINES:
            raise PosError(400, "lines", "Add 1-300 lines.")
        bill_no = re.sub(r"\s+", " ", str(data.get("supplier_bill_no") or "")).strip()
        if not bill_no:
            raise PosError(400, "supplier_bill_no", "Enter the supplier's bill number.")
        # every line is checked BEFORE anything is created, so a mistake never leaves half the bill behind
        for n, raw in enumerate(raw_lines, start=1):
            name = str(raw.get("name") or "").strip()
            if int(raw.get("qty_milli") or 0) <= 0 or raw.get("cost_paise") is None or int(raw["cost_paise"]) < 0:
                raise PosError(400, "line", f"Line {n} ({name}): enter the quantity and the cost.")
            if int(raw.get("rate_bp") or 0) not in pos_tax.ALLOWED_RATES_BP:
                raise PosError(400, "rate", f"Line {n} ({name}): choose the GST rate.")
            if not raw.get("product_id") and norm(name) not in products:
                if len(norm(name)) < 2:
                    raise PosError(400, "name", f"Line {n}: enter the item name.")
                if raw.get("price_paise") is None or int(raw["price_paise"]) <= 0:
                    raise PosError(400, "price", f"Line {n} ({name}): new item -- enter your selling price.")
        supplier_id = data.get("supplier_id")
        if not supplier_id:
            info = data.get("supplier") if isinstance(data.get("supplier"), dict) else {}
            found = self._find_supplier(suppliers, str(info.get("name") or ""), str(info.get("gstin") or "").upper())
            if found is None:
                found = self.purchases.add_supplier(business_id, user, {
                    "name": info.get("name"), "gstin": info.get("gstin") or None, "phone": info.get("phone") or ""})
            supplier_id = found["id"]
        lines, created = [], 0
        for raw in raw_lines:
            product_id = raw.get("product_id")
            name = str(raw.get("name") or "").strip()
            expiry = _date(raw.get("expiry_date"))
            if not product_id:
                match = products.get(norm(name))
                if match is None:
                    match = self.store.add_product(business_id, user, {
                        "name": name, "unit": _unit(raw.get("unit")), "price_paise": int(raw["price_paise"]),
                        "rate_bp": int(raw.get("rate_bp") or 0), "track_stock": True, "track_batches": bool(expiry)})
                    products[norm(name)] = match
                    created += 1
                product_id = match["id"]
                tracked = bool(match.get("track_batches"))
            else:
                tracked = any(p["id"] == product_id and p["track_batches"] for p in products.values())
            batch = re.sub(r"\s+", " ", str(raw.get("batch_no") or "")).strip()[:40]
            line = {"product_id": product_id, "qty_milli": int(raw["qty_milli"]), "cost_paise": int(raw["cost_paise"]),
                    "rate_bp": int(raw.get("rate_bp") or 0)}
            if tracked:
                line["batch_no"] = batch or bill_no  # the bill number stands in when the bill prints no batch
                if expiry:
                    line["expiry_date"] = expiry
            lines.append(line)
        out = self.purchases.record_purchase(business_id, user, {
            "client_txn_id": data.get("client_txn_id"), "supplier_id": supplier_id, "supplier_bill_no": bill_no,
            "bill_date": _date(data.get("bill_date")) or None, "lines": lines,
            "supplier_total_paise": data.get("supplier_total_paise")})
        out["created_items"] = created
        out["product_ids"] = [line["product_id"] for line in lines]
        return out
