"""ASKODOX POS -- India GST arithmetic for invoices (pure functions).

Money is integer PAISE, quantities are integer MILLI-units (1 kg = 1000),
rates are BASIS POINTS (18% = 1800). All arithmetic uses ``Decimal`` with
ROUND_HALF_UP to the paisa; floats never touch money.

What this module decides and what it never decides:
- It splits tax into CGST + SGST (or UTGST) for an intra-State supply and IGST
  for an inter-State one, from the place of supply the CASHIER chose (the
  default is the business's own State -- the usual case for an over-the-counter
  sale). It does not decide a legal place of supply for complex cases
  (bill-to / ship-to, services with special rules): the cashier or accountant
  chooses and the reason is printed in the audit trail.
- It never invents an HSN / SAC code or a GST rate: both come from the
  business's own product entry. It only checks the SHAPE of a code.
- A composition taxable person issues a BILL OF SUPPLY and collects no tax;
  an unregistered business issues a plain bill with no GST.

Rules are versioned and sourced (``RULES``); every invoice stores the rule
version it was computed with so an old invoice is never re-computed with new
rules.
"""
from __future__ import annotations

import re
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Dict, Iterable, List, Optional

RULES_VERSION = "pos-gst-2026-10-23"

SOURCES = {
    "rule46": "https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule46_v1.00.html",
    "rule49": "https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule49_v1.00.html",
    "rule5": "https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter2/rule5_v1.00.html",
    "rule53": "https://cggst.com/wp-content/uploads/2023/07/Rule-53-1.pdf",
    "hsn_digits": "https://www.gstcouncil.gov.in/sites/default/files/2024-05/notfctn-78-central-tax-english-2020.pdf",
    "einvoice_5cr": "https://www.pib.gov.in/PressReleasePage.aspx?PRID=1990977",
    "state_codes": "https://tutorial.gst.gov.in/downloads/news/for_publishing_monthly_gst_data_for_apr_2026.pdf",
}

RULES: Dict[str, Any] = {
    "version": RULES_VERSION,
    "verified_on": "2026-10-23",
    "serial_max_chars": 16,                # Rule 46(b) / 49(b) / 53(1A)
    "b2c_details_threshold_paise": 50_000_00,  # Rule 46(e) proviso: unregistered recipient, value >= Rs 50,000
    "hsn_digits": {"upto_5cr": 4, "above_5cr": 6},  # Notification 78/2020-CT (from 01.04.2021)
    "einvoice_threshold_paise": 5_00_00_000_00,     # aggregate turnover > Rs 5 crore (from 01.08.2023)
    "composition_bill_heading": "composition taxable person, not eligible to collect tax on supplies",  # Rule 5(1)(f)
    "sources": SOURCES,
}

# GST State / UT codes (first two digits of a GSTIN).
STATE_CODES: Dict[str, str] = {
    "01": "Jammu and Kashmir", "02": "Himachal Pradesh", "03": "Punjab", "04": "Chandigarh",
    "05": "Uttarakhand", "06": "Haryana", "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh",
    "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh", "13": "Nagaland", "14": "Manipur",
    "15": "Mizoram", "16": "Tripura", "17": "Meghalaya", "18": "Assam", "19": "West Bengal",
    "20": "Jharkhand", "21": "Odisha", "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat",
    "26": "Dadra and Nagar Haveli and Daman and Diu", "27": "Maharashtra", "29": "Karnataka", "30": "Goa",
    "31": "Lakshadweep", "32": "Kerala", "33": "Tamil Nadu", "34": "Puducherry",
    "35": "Andaman and Nicobar Islands", "36": "Telangana", "37": "Andhra Pradesh", "38": "Ladakh",
    "97": "Other Territory",
}

# Union Territories without a legislature levy UTGST instead of SGST.
UTGST_CODES = frozenset({"04", "26", "31", "35", "38", "97"})

TAX_CATEGORIES = ("taxable", "exempt", "nil_rated", "non_gst", "zero_rated_lut")
ALLOWED_RATES_BP = frozenset({0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000})

_GSTIN_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_GSTIN_SHAPE = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")
_SERIAL = re.compile(r"^[A-Za-z0-9/\-]{1,16}$")
_HSN = re.compile(r"^[0-9]{4}([0-9]{2}){0,2}$")
_ONE = Decimal("1")


class TaxError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _paise(value: Decimal) -> int:
    return int(value.quantize(_ONE, rounding=ROUND_HALF_UP))


def gstin_check_char(first14: str) -> str:
    """Checksum character of a GSTIN (mod-36 weighted sum)."""
    total = 0
    for i, ch in enumerate(first14):
        value = _GSTIN_CHARS.index(ch) * (2 if i % 2 else 1)
        total += value // 36 + value % 36
    return _GSTIN_CHARS[(36 - total % 36) % 36]


def validate_gstin(gstin: str) -> Dict[str, Any]:
    """Shape + State code + checksum. A valid GSTIN is not proof that the
    registration is active -- that needs the GST portal."""
    value = str(gstin or "").strip().upper()
    if not _GSTIN_SHAPE.match(value):
        return {"valid": False, "reason": "shape", "gstin": value}
    if value[:2] not in STATE_CODES:
        return {"valid": False, "reason": "state_code", "gstin": value}
    if gstin_check_char(value[:14]) != value[14]:
        return {"valid": False, "reason": "checksum", "gstin": value}
    return {"valid": True, "gstin": value, "state_code": value[:2], "state": STATE_CODES[value[:2]],
            "pan": value[2:12], "active_status": "not_checked"}


def check_hsn(code: str, *, is_service: bool = False, turnover_above_5cr: bool = False) -> Dict[str, Any]:
    """Shape check only. ASKODOX never suggests or changes a classification."""
    value = re.sub(r"\s", "", str(code or ""))
    if not value:
        return {"ok": False, "reason": "missing"}
    if not _HSN.match(value):
        return {"ok": False, "reason": "shape"}
    if is_service and not value.startswith("99"):
        return {"ok": False, "reason": "sac_starts_99"}
    need = RULES["hsn_digits"]["above_5cr" if turnover_above_5cr else "upto_5cr"]
    return {"ok": True, "code": value, "digits": len(value), "enough_digits": len(value) >= need, "required_digits": need}


def check_serial(serial: str) -> bool:
    return bool(_SERIAL.match(str(serial or "")))


def financial_year(date_iso: str) -> str:
    """'2026-10-23' -> '2627' (Indian FY April-March)."""
    year, month = int(date_iso[0:4]), int(date_iso[5:7])
    start = year if month >= 4 else year - 1
    return f"{start % 100:02d}{(start + 1) % 100:02d}"


def series_label(prefix: str, fy: str, number: int) -> str:
    """Invoice number, e.g. ``A/2627/000123``. Raises when it would exceed 16 characters."""
    label = f"{prefix}/{fy}/{number:06d}" if number < 1_000_000 else f"{prefix}/{fy}/{number}"
    if not check_serial(label):
        raise TaxError("serial_too_long", f"Invoice number '{label}' exceeds 16 characters; use a shorter series prefix.")
    return label


def line_tax(*, qty_milli: int, unit_price_paise: int, discount_paise: int = 0, rate_bp: int = 0,
             cess_bp: int = 0, price_includes_tax: bool = False, category: str = "taxable",
             mode: str = "intra", collect_tax: bool = True) -> Dict[str, int]:
    """Tax for one line. ``mode`` = intra (CGST+SGST/UTGST halves) or inter (IGST).

    ``collect_tax`` False (composition / unregistered business) -> no tax at all; an
    inclusive price is then simply the value of supply.
    """
    if qty_milli <= 0:
        raise TaxError("qty", "Quantity must be more than zero.")
    if unit_price_paise < 0 or discount_paise < 0:
        raise TaxError("amount", "Price and discount cannot be negative.")
    if category not in TAX_CATEGORIES:
        raise TaxError("category", f"Unknown tax category '{category}'.")
    if rate_bp not in ALLOWED_RATES_BP:
        raise TaxError("rate", f"GST rate {rate_bp / 100}% is not a configured GST rate.")
    if cess_bp < 0 or cess_bp > 30000:
        raise TaxError("cess", "Cess rate out of range.")
    gross = _paise(Decimal(qty_milli) * Decimal(unit_price_paise) / Decimal(1000))
    if discount_paise > gross:
        raise TaxError("discount", "Discount is more than the line value.")
    value = gross - discount_paise
    taxed = collect_tax and category == "taxable" and (rate_bp > 0 or cess_bp > 0)
    if not taxed:
        return {"gross_paise": gross, "discount_paise": discount_paise, "taxable_paise": value, "cgst_paise": 0,
                "sgst_paise": 0, "igst_paise": 0, "cess_paise": 0, "tax_paise": 0, "total_paise": value}
    rate = Decimal(rate_bp) / Decimal(10000)
    cess_rate = Decimal(cess_bp) / Decimal(10000)
    if price_includes_tax:
        taxable = _paise(Decimal(value) / (_ONE + rate + cess_rate))
    else:
        taxable = value
    if mode == "intra":
        half = _paise(Decimal(taxable) * rate / 2)
        cgst, sgst, igst = half, half, 0
    elif mode == "inter":
        cgst, sgst, igst = 0, 0, _paise(Decimal(taxable) * rate)
    else:
        raise TaxError("mode", "mode must be intra or inter")
    cess = _paise(Decimal(taxable) * cess_rate)
    tax = cgst + sgst + igst + cess
    if price_includes_tax:
        # The customer pays exactly the shown price: rounding lands on the taxable value.
        taxable = value - tax
    return {"gross_paise": gross, "discount_paise": discount_paise, "taxable_paise": taxable, "cgst_paise": cgst,
            "sgst_paise": sgst, "igst_paise": igst, "cess_paise": cess, "tax_paise": tax, "total_paise": taxable + tax}


def supply_mode(business_state: str, place_of_supply: Optional[str]) -> str:
    pos = place_of_supply or business_state
    if pos not in STATE_CODES:
        raise TaxError("place_of_supply", "Unknown place of supply State code.")
    return "intra" if pos == business_state else "inter"


def document_type(registration_type: str, lines: Iterable[Dict[str, Any]]) -> str:
    """tax_invoice | bill_of_supply | bill (unregistered business)."""
    if registration_type == "unregistered":
        return "bill"
    if registration_type == "composition":
        return "bill_of_supply"
    # Zero-rated supplies (exports / SEZ under LUT) are taxable supplies at 0: tax invoice.
    taxable = any(l.get("category", "taxable") in ("taxable", "zero_rated_lut") for l in lines)
    return "tax_invoice" if taxable else "bill_of_supply"


def invoice_totals(lines: List[Dict[str, Any]], *, registration_type: str, business_state: str,
                   place_of_supply: Optional[str] = None, round_off: bool = False) -> Dict[str, Any]:
    """Compute every line + invoice totals. ``lines`` items carry the product's own
    ``rate_bp`` / ``cess_bp`` / ``category`` / ``price_includes_tax``."""
    if not lines:
        raise TaxError("empty", "Add at least one item.")
    collect = registration_type == "regular"
    mode = supply_mode(business_state, place_of_supply)
    out_lines = []
    for raw in lines:
        tax = line_tax(qty_milli=int(raw["qty_milli"]), unit_price_paise=int(raw["unit_price_paise"]),
                       discount_paise=int(raw.get("discount_paise") or 0), rate_bp=int(raw.get("rate_bp") or 0),
                       cess_bp=int(raw.get("cess_bp") or 0), price_includes_tax=bool(raw.get("price_includes_tax")),
                       category=str(raw.get("category") or "taxable"), mode=mode, collect_tax=collect)
        out_lines.append({**raw, **tax})
    keys = ("gross_paise", "discount_paise", "taxable_paise", "cgst_paise", "sgst_paise", "igst_paise", "cess_paise",
            "tax_paise", "total_paise")
    totals = {k: sum(l[k] for l in out_lines) for k in keys}
    rounding = 0
    if round_off:
        rupees = _paise(Decimal(totals["total_paise"]) / Decimal(100)) * 100
        rounding = rupees - totals["total_paise"]
    totals["round_off_paise"] = rounding
    totals["grand_total_paise"] = totals["total_paise"] + rounding
    state_tax = "utgst" if (place_of_supply or business_state) in UTGST_CODES else "sgst"
    return {"lines": out_lines, "totals": totals, "mode": mode, "state_tax_label": state_tax,
            "place_of_supply": place_of_supply or business_state,
            "document_type": document_type(registration_type, lines), "rules_version": RULES_VERSION}


def rate_summary(lines: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Per-rate taxable / tax totals (printed under the invoice and used by reports)."""
    rows: Dict[tuple, Dict[str, Any]] = {}
    for line in lines:
        key = (int(line.get("rate_bp") or 0), str(line.get("category") or "taxable"))
        row = rows.setdefault(key, {"rate_bp": key[0], "category": key[1], "taxable_paise": 0, "cgst_paise": 0,
                                    "sgst_paise": 0, "igst_paise": 0, "cess_paise": 0})
        for k in ("taxable_paise", "cgst_paise", "sgst_paise", "igst_paise", "cess_paise"):
            row[k] += int(line.get(k) or 0)
    return [rows[k] for k in sorted(rows)]


def recipient_requirements(*, recipient_gstin: Optional[str], total_paise: int, mode: str) -> List[str]:
    """Which recipient details the invoice must carry (Rule 46 (d)/(e))."""
    need: List[str] = []
    if recipient_gstin:
        need += ["name", "address"]
    elif total_paise >= RULES["b2c_details_threshold_paise"]:
        need += ["name", "address", "delivery_address", "state_code"]
    if mode == "inter":
        need.append("state_code")
    return sorted(set(need))
