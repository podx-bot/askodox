"""India tax awareness + lawful tax planning (income tax and GST).

Every rule below carries the official source it was checked against and the
date it was checked (``VERIFIED_ON``). Calculations are deterministic and
explain themselves step by step; they are estimates for planning, never a
filing, and every answer recommends a qualified professional for
consequential cases.

Scope rules (master command 19):
- Lawful planning only. Questions that ask HOW to evade (fake invoices, false
  ITC, hiding income, bogus deductions) get awareness + consequences, never
  operational steps (``evasion_intent``).
- A missing GST invoice is not automatically illegal (unregistered / exempt /
  composition suppliers issue a bill of supply or no tax invoice).
- Years without verified rules are refused, never extrapolated.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

VERIFIED_ON = "2026-10-23"

SOURCES: Dict[str, Dict[str, str]] = {
    "itd_tax_rates": {
        "title": "Income Tax Department — Tax rates (AY 2026-27 and AY 2025-26)",
        "url": "https://www.incometaxindia.gov.in/w/tax-rates%E2%80%8B",
    },
    "itd_rebate_87a": {
        "title": "Income Tax Department — Rebate under section 87A for FY 2025-26",
        "url": "https://www.incometaxindia.gov.in/w/what-is-rebate-under-section-87a-for-f.y-2025-26-and-who-can-claim-it-",
    },
    "itd_employees": {
        "title": "Income Tax Department — Employees: benefits allowable (standard deduction)",
        "url": "https://www.incometaxindia.gov.in/w/employees-benefits-allowable",
    },
    "itd_regime_faq": {
        "title": "Income Tax e-filing — FAQs on New vs Old Tax Regime",
        "url": "https://www.incometax.gov.in/iec/foportal/sites/default/files/2024-07/New%20vs.%20Old%20Regime%20FAQs.pdf",
    },
    "pib_budget_2025": {
        "title": "PIB — No income tax on income up to Rs 12 lakh under new regime (Budget 2025-26)",
        "url": "https://www.pib.gov.in/PressReleasePage.aspx?PRID=2098406&reg=48&lang=2",
    },
    "finance_bill_2026_memo": {
        "title": "Finance Bill 2026 — Memorandum (no change in rates for tax year 2026-27)",
        "url": "https://www.indiabudget.gov.in/doc/memo.pdf",
    },
    "ita_2025": {
        "title": "Income-tax Act, 2025 in force from 1 April 2026 ('tax year')",
        "url": "https://www.india-briefing.com/news/income-tax-act-2025-implementation-guide-39140.html/",
    },
    "gst_56th_council": {
        "title": "PIB — Recommendations of the 56th GST Council (5% / 18% / 40% from 22 Sep 2025)",
        "url": "https://www.pib.gov.in/PressReleasePage.aspx?PRID=2163555&reg=48&lang=2",
    },
    "cbic_gst_update_2019": {
        "title": "CBIC — GST: An Update (June 2019): registration and composition limits",
        "url": "https://cbic-gst.gov.in/pdf/01062019-GST-An-Update.pdf",
    },
    "pib_msme_2019": {
        "title": "PIB — GST Council decisions for MSMEs (Rs 40 lakh goods option, 6% services composition)",
        "url": "https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1567975&reg=48&lang=2",
    },
    "cbic_composition_faq": {
        "title": "CBIC — FAQs on Composition Levy (conditions)",
        "url": "https://cbic-gst.gov.in/pdf/faq-manual/faq-composition-levy-revised.pdf",
    },
    "cgst_act": {
        "title": "CBIC — CGST Act, 2017 (section 24 compulsory registration; sections 122 and 132 penalties / offences)",
        "url": "https://cbic-gst.gov.in/pdf/CGST-Act-Updated-30092020.pdf",
    },
}

PROFESSIONAL_NOTE = ("Estimate for planning only, not a filing or professional advice. For a notice, a business "
                     "decision or a large amount, confirm with a chartered accountant / GST practitioner and the "
                     "official portal.")

# ------------------------------------------------------------------ income tax

INF = float("inf")

# Tax-year label "2025-26" = financial year 2025-26 (assessment year 2026-27,
# Income-tax Act 1961). "2026-27" = tax year 2026-27 under the Income-tax Act
# 2025; the Finance Bill 2026 memorandum states the rates are unchanged.
INCOME_TAX_YEARS: Dict[str, Dict[str, Any]] = {
    "2025-26": {
        "label": "FY 2025-26 (AY 2026-27)",
        "law": "Income-tax Act, 1961",
        "new_slabs": [(400000, 0.0), (800000, 0.05), (1200000, 0.10), (1600000, 0.15), (2000000, 0.20),
                      (2400000, 0.25), (INF, 0.30)],
        "new_rebate": {"limit": 1200000, "max": 60000, "marginal_relief": True},
        "new_standard_deduction": 75000,
        "old_slabs": {
            "below_60": [(250000, 0.0), (500000, 0.05), (1000000, 0.20), (INF, 0.30)],
            "60_to_80": [(300000, 0.0), (500000, 0.05), (1000000, 0.20), (INF, 0.30)],
            "80_plus": [(500000, 0.0), (1000000, 0.20), (INF, 0.30)],
        },
        "old_rebate": {"limit": 500000, "max": 12500, "marginal_relief": False},
        "old_standard_deduction": 50000,
        "status": "verified",
        "sources": ["itd_tax_rates", "itd_rebate_87a", "itd_employees", "pib_budget_2025", "itd_regime_faq"],
    },
}
INCOME_TAX_YEARS["2026-27"] = {
    **INCOME_TAX_YEARS["2025-26"],
    "label": "Tax year 2026-27 (FY 2026-27)",
    "law": "Income-tax Act, 2025",
    # Rates verified unchanged (Finance Bill 2026 memo); rebate and standard
    # deduction carried forward into the 2025 Act -- labelled as such.
    "status": "rates_verified_other_amounts_carried_forward",
    "sources": ["finance_bill_2026_memo", "ita_2025", "itd_tax_rates", "itd_rebate_87a", "itd_employees"],
}
CURRENT_TAX_YEAR = "2026-27"

# Surcharge: (income threshold, rate). New regime capped at 25 %.
SURCHARGE_OLD = [(5_00_00_000, 0.37), (2_00_00_000, 0.25), (1_00_00_000, 0.15), (50_00_000, 0.10)]
SURCHARGE_NEW = [(2_00_00_000, 0.25), (1_00_00_000, 0.15), (50_00_000, 0.10)]
CESS = 0.04


class TaxInputError(ValueError):
    pass


def _slab_tax(income: float, slabs: List[Tuple[float, float]]) -> Tuple[float, List[Dict[str, Any]]]:
    tax, lower, rows = 0.0, 0.0, []
    for upper, rate in slabs:
        if income <= lower:
            break
        part = min(income, upper) - lower
        if part > 0:
            tax += part * rate
            rows.append({"from": lower, "to": None if upper == INF else upper, "rate_percent": rate * 100,
                         "taxable": round(part, 2), "tax": round(part * rate, 2)})
        lower = upper
    return tax, rows


def _surcharge(income: float, tax: float, regime: str, slabs: List[Tuple[float, float]],
               rebate_rule: Dict[str, Any]) -> Tuple[float, Optional[str]]:
    table = SURCHARGE_NEW if regime == "new" else SURCHARGE_OLD
    for index, (threshold, rate) in enumerate(table):
        if income > threshold:
            lower_rate = table[index + 1][1] if index + 1 < len(table) else 0.0
            tax_at_threshold, _ = _slab_tax(threshold, slabs)
            ceiling = tax_at_threshold * (1 + lower_rate) + (income - threshold)
            full = tax * (1 + rate)
            if full > ceiling:  # marginal relief at the surcharge threshold
                return max(ceiling - tax, 0.0), f"marginal relief at Rs {threshold:,.0f}"
            return tax * rate, None
    return 0.0, None


def compute_income_tax(*, year: str = CURRENT_TAX_YEAR, regime: str = "new", salary_income: float = 0.0,
                       other_income: float = 0.0, deductions: float = 0.0, age_band: str = "below_60",
                       resident: bool = True) -> Dict[str, Any]:
    """Tax on income taxed at normal slab rates (salary, business, interest,
    rent after its own deductions). Capital gains and other special-rate
    income are NOT included and are said so."""
    rules = INCOME_TAX_YEARS.get(year)
    if rules is None:
        raise TaxInputError(f"No verified rules for {year}. Available: {', '.join(INCOME_TAX_YEARS)}.")
    if regime not in ("new", "old"):
        raise TaxInputError("regime must be 'new' or 'old'")
    if age_band not in rules["old_slabs"]:
        raise TaxInputError("age_band must be below_60, 60_to_80 or 80_plus")
    for name, value in (("salary_income", salary_income), ("other_income", other_income), ("deductions", deductions)):
        if value is None or value != value or value < 0:
            raise TaxInputError(f"{name} cannot be negative")
    notes: List[str] = []
    if regime == "new":
        standard = min(rules["new_standard_deduction"], salary_income)
        claimed = 0.0
        if deductions:
            notes.append("Chapter VI-A deductions such as 80C / 80D and HRA are not allowed in the new regime "
                         "(80CCD(2) employer NPS is an exception) -- the deductions you entered were ignored.")
        slabs = rules["new_slabs"]
        rebate_rule = rules["new_rebate"]
    else:
        standard = min(rules["old_standard_deduction"], salary_income)
        claimed = deductions
        if deductions:
            notes.append("Deductions are used exactly as you entered them; each has its own limit and proof "
                         "requirement (for example 80C up to Rs 1.5 lakh).")
        slabs = rules["old_slabs"][age_band if resident else "below_60"]
        if not resident and age_band != "below_60":
            notes.append("Higher basic exemption for senior citizens applies to residents only.")
        rebate_rule = rules["old_rebate"]
    gross = salary_income + other_income
    taxable = max(gross - standard - claimed, 0.0)
    slab_tax, rows = _slab_tax(taxable, slabs)
    rebate = 0.0
    if resident:
        if taxable <= rebate_rule["limit"]:
            rebate = min(slab_tax, rebate_rule["max"])
        elif rebate_rule["marginal_relief"] and slab_tax > taxable - rebate_rule["limit"]:
            rebate = slab_tax - (taxable - rebate_rule["limit"])
            notes.append(f"Marginal relief: tax limited to the income above Rs {rebate_rule['limit']:,.0f}.")
    else:
        notes.append("The rebate is for resident individuals only.")
    after_rebate = max(slab_tax - rebate, 0.0)
    surcharge, relief = _surcharge(taxable, after_rebate, regime, slabs, rebate_rule)
    if relief:
        notes.append(f"Surcharge {relief}.")
    cess = (after_rebate + surcharge) * CESS
    total = after_rebate + surcharge + cess
    return {
        "year": year,
        "year_label": rules["label"],
        "law": rules["law"],
        "regime": regime,
        "rule_status": rules["status"],
        "gross_income": round(gross, 2),
        "standard_deduction": round(standard, 2),
        "deductions_used": round(claimed, 2),
        "taxable_income": round(taxable, 2),
        "slabs": rows,
        "slab_tax": round(slab_tax, 2),
        "rebate": round(rebate, 2),
        "surcharge": round(surcharge, 2),
        "cess": round(cess, 2),
        "total_tax": round(total),
        "effective_rate_percent": round(total / gross * 100, 2) if gross else 0.0,
        "notes": notes + ["Capital gains and other special-rate income are not included in this estimate."],
        "sources": [{"id": s, **SOURCES[s]} for s in rules["sources"]],
        "verified_on": VERIFIED_ON,
        "professional_note": PROFESSIONAL_NOTE,
    }


def compare_regimes(**kwargs: Any) -> Dict[str, Any]:
    kwargs.pop("regime", None)
    new = compute_income_tax(regime="new", **kwargs)
    old = compute_income_tax(regime="old", **kwargs)
    better = "new" if new["total_tax"] < old["total_tax"] else "old" if old["total_tax"] < new["total_tax"] else "same"
    switching = ("Salaried taxpayers without business income can choose the regime every year in the return. "
                 "With business / professional income, leaving the new regime needs Form 10-IEA and the way "
                 "back is limited -- see the official FAQ.")
    return {"new": new, "old": old, "lower_tax": better,
            "difference": abs(new["total_tax"] - old["total_tax"]), "switching_rule": switching,
            "sources": [{"id": "itd_regime_faq", **SOURCES["itd_regime_faq"]}]}


# ------------------------------------------------------------------ GST

GST_RATE_STRUCTURE = {
    "effective_from": "2025-09-22",
    "slabs_percent": [0, 5, 18, 40],
    "summary": ("From 22 September 2025 most goods and services moved to two rates -- a 5% merit rate and an "
                "18% standard rate -- with a 40% rate for a few de-merit goods and services and Nil for some "
                "items. Tobacco / pan masala stay at their earlier rates plus compensation cess until the cess "
                "loans are repaid. A few special rates (for example on precious metals) continue."),
    "rate_rule": ("The rate depends on the exact HSN / SAC code of the item. ASKODOX never assigns a rate from "
                  "a product name -- check the CBIC rate notification for the HSN code."),
    "sources": ["gst_56th_council"],
}

# Aggregate-turnover registration thresholds (CBIC June 2019 update).
_GOODS_20L_STATES = {"arunachal pradesh", "manipur", "meghalaya", "mizoram", "nagaland", "puducherry", "sikkim",
                     "telangana", "tripura", "uttarakhand"}
_SERVICES_10L_STATES = {"manipur", "mizoram", "nagaland", "tripura"}
_COMPOSITION_75L_STATES = {"arunachal pradesh", "manipur", "meghalaya", "mizoram", "nagaland", "sikkim",
                           "tripura", "uttarakhand"}


def _state(value: str | None) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip().lower())


def gst_registration_check(*, turnover: float, supply: str, state: str) -> Dict[str, Any]:
    """Whether turnover alone requires GST registration. ``supply`` is goods,
    services or both (any services -> the services threshold)."""
    if turnover is None or turnover != turnover or turnover < 0:
        raise TaxInputError("turnover cannot be negative")
    if supply not in ("goods", "services", "both"):
        raise TaxInputError("supply must be goods, services or both")
    st = _state(state)
    if not st:
        raise TaxInputError("state is required (thresholds differ by state)")
    if supply == "goods":
        threshold = 2000000 if st in _GOODS_20L_STATES else 4000000
    else:
        threshold = 1000000 if st in _SERVICES_10L_STATES else 2000000
    required = turnover > threshold
    near = not required and turnover >= threshold * 0.8
    return {
        "threshold": threshold,
        "turnover": turnover,
        "registration_required_by_turnover": required,
        "approaching_threshold": near,
        "state": st,
        "supply": supply,
        "always_required_cases": ("Registration is compulsory regardless of turnover in some cases -- for example "
                                  "inter-State taxable supply of goods, casual taxable persons and certain "
                                  "e-commerce suppliers (CGST Act section 24)."),
        "no_invoice_note": ("A seller below the threshold, or selling exempt goods, may lawfully not charge GST; "
                            "a bill without GST is not automatically illegal."),
        "verify": "Thresholds as published by CBIC (June 2019); confirm the current limit for your State on the GST portal.",
        "sources": [{"id": s, **SOURCES[s]} for s in ("cbic_gst_update_2019", "pib_msme_2019", "cgst_act")],
        "verified_on": VERIFIED_ON,
        "professional_note": PROFESSIONAL_NOTE,
    }


COMPOSITION_RATES = {"trader": 1.0, "manufacturer": 1.0, "restaurant": 5.0, "services": 6.0}


def composition_check(*, turnover: float, business: str, state: str, interstate_outward: bool = False,
                      ecommerce_tcs: bool = False) -> Dict[str, Any]:
    if turnover is None or turnover != turnover or turnover < 0:
        raise TaxInputError("turnover cannot be negative")
    if business not in COMPOSITION_RATES:
        raise TaxInputError("business must be trader, manufacturer, restaurant or services")
    st = _state(state)
    if not st:
        raise TaxInputError("state is required")
    if business == "services":
        limit = 5000000
    else:
        limit = 7500000 if st in _COMPOSITION_75L_STATES else 15000000
    blockers = []
    if turnover > limit:
        blockers.append(f"Turnover above the Rs {limit:,.0f} limit.")
    if interstate_outward:
        blockers.append("Inter-State outward supplies are not allowed in the composition scheme.")
    if ecommerce_tcs:
        blockers.append("Supplies through an e-commerce operator that collects TCS are not allowed.")
    return {
        "eligible": not blockers,
        "blockers": blockers,
        "limit": limit,
        "rate_percent_of_turnover": COMPOSITION_RATES[business],
        "conditions": [
            "Issue a bill of supply, not a tax invoice; you cannot collect GST from customers.",
            "No input tax credit for you, and your buyers cannot claim credit on your bills.",
            "Some manufacturers (for example ice cream, pan masala, tobacco) are excluded.",
        ],
        "trade_off": ("Lower compliance and a flat rate on turnover, but no input tax credit -- often not worth it "
                      "if most customers are GST-registered businesses that want credit."),
        "sources": [{"id": s, **SOURCES[s]} for s in ("cbic_gst_update_2019", "pib_msme_2019", "cbic_composition_faq")],
        "verified_on": VERIFIED_ON,
        "professional_note": PROFESSIONAL_NOTE,
    }


def gst_amount(*, amount: float, rate_percent: float, inclusive: bool = False, interstate: bool = False) -> Dict[str, Any]:
    if amount is None or amount != amount or amount < 0:
        raise TaxInputError("amount cannot be negative")
    if rate_percent is None or rate_percent != rate_percent or not 0 <= rate_percent <= 40:
        raise TaxInputError("rate must be between 0 and 40 percent")
    rate = rate_percent / 100
    if inclusive:
        taxable = amount / (1 + rate)
    else:
        taxable = amount
    tax = taxable * rate
    split = {"igst": round(tax, 2)} if interstate else {"cgst": round(tax / 2, 2), "sgst": round(tax / 2, 2)}
    return {"taxable_value": round(taxable, 2), "gst": round(tax, 2), "total": round(taxable + tax, 2),
            "rate_percent": rate_percent, "split": split, "rate_rule": GST_RATE_STRUCTURE["rate_rule"],
            "sources": [{"id": "gst_56th_council", **SOURCES["gst_56th_council"]}]}


# ------------------------------------------------------------------ planning vs evasion

LAWFUL_PLANNING = [
    "Compare the new and old regime every year (salaried) before filing.",
    "In the old regime, claim only deductions you can prove (80C investments, 80D health insurance, HRA rent receipts).",
    "Employer NPS contribution (80CCD(2)) is allowed even in the new regime.",
    "Small businesses: check presumptive taxation and the GST composition scheme -- both trade lower paperwork for conditions.",
    "Registered businesses: claim input tax credit only on genuine purchases with a valid tax invoice that appears in your GSTR-2B.",
]

EVASION_AWARENESS = [
    {"practice": "Fake / bogus invoices to claim input tax credit",
     "warning_signs": "Supplier with no real stock or premises, invoices without matching goods movement or e-way bills.",
     "consequence": "Credit is reversed with interest and penalty; issuing or using fake invoices is an offence "
                    "under the CGST Act (section 132) with possible arrest and prosecution."},
    {"practice": "Selling without bills to hide turnover",
     "warning_signs": "Seller offers a lower price only for 'no bill'; no warranty or return is possible.",
     "consequence": "Tax, interest and penalty for the seller (CGST Act section 122); the buyer loses warranty, "
                    "proof of purchase and any input tax credit."},
    {"practice": "Hiding income or claiming deductions without proof",
     "warning_signs": "Advisers promising refunds with made-up HRA receipts, donations or loans.",
     "consequence": "Tax, interest and heavy penalties for under-reporting / mis-reporting, and prosecution in serious cases."},
]

_EVASION_PATTERNS = [
    # Asking to OBTAIN / MAKE false documents -- "is this a fake invoice?" is a victim's question.
    r"\b(make|create|generate|get|buy|issue|print|arrange|need)\w*\s+(me\s+)?(a\s+|some\s+)?(fake|bogus|dummy|false)\s+"
    r"(gst\s+)?(invoice|invoices|bill|bills|receipts?|rent receipts?)\b",
    r"\b(avoid|evade|escape|skip|dodge)\w*\s+(paying\s+)?(gst|income tax|tax)\b.*\b(without|not)\b.*\b(caught|notice|detected|traced)\b",
    r"\b(hide|conceal|not show)\w*\s+(my\s+)?(income|sales|turnover|cash)\b",
    r"\b(claim|get)\s+itc\s+(without|on fake|on bogus)\b",
    r"\bhow\s+to\s+(evade|cheat)\b",
    r"నకిలీ\s*(బిల్లు|బిల్లులు|ఇన్వాయిస్).{0,20}(ఎలా|తయారు|కావాలి|ఇవ్వండి)", r"పన్ను\s*ఎగ(గొట్ట|వేయ)",
]


def evasion_intent(text: str) -> bool:
    q = str(text or "").lower()
    return any(re.search(p, q) for p in _EVASION_PATTERNS)


def evasion_response() -> Dict[str, Any]:
    return {
        "refusal": ("ASKODOX does not explain how to evade tax or create false records. Here is how these schemes "
                    "are detected, what they cost, and lawful ways to reduce tax."),
        "awareness": EVASION_AWARENESS,
        "lawful_planning": LAWFUL_PLANNING,
        "sources": [{"id": "cgst_act", **SOURCES["cgst_act"]}, {"id": "itd_regime_faq", **SOURCES["itd_regime_faq"]}],
        "professional_note": PROFESSIONAL_NOTE,
    }


def overview(language: str = "en") -> Dict[str, Any]:
    year = INCOME_TAX_YEARS[CURRENT_TAX_YEAR]
    return {
        "current_tax_year": CURRENT_TAX_YEAR,
        "years": [{"year": key, "label": value["label"], "law": value["law"], "status": value["status"]}
                  for key, value in INCOME_TAX_YEARS.items()],
        "new_regime_slabs": [{"up_to": None if upper == INF else upper, "rate_percent": rate * 100}
                             for upper, rate in year["new_slabs"]],
        "new_regime_zero_tax_up_to": year["new_rebate"]["limit"],
        "salaried_standard_deduction_new": year["new_standard_deduction"],
        "gst": GST_RATE_STRUCTURE,
        "lawful_planning": LAWFUL_PLANNING,
        "sources": [{"id": k, **v} for k, v in SOURCES.items()],
        "verified_on": VERIFIED_ON,
        "professional_note": PROFESSIONAL_NOTE,
    }
