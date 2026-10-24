"""Smart Tricks & Savings: deterministic money maths over the user's OWN
numbers (no invented prices, offers, discounts or availability).

Each calculator returns the numbers, a plain verdict, the assumptions, and
what would change the verdict. Verified offers come only from the existing
benefits engine (``benefits_engine``); this module never fabricates one.
"""
from __future__ import annotations

import math
from typing import Any, Dict, List


class TrickInputError(ValueError):
    pass


def _num(name: str, value: Any, *, minimum: float = 0.0, allow_zero: bool = True) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise TrickInputError(f"{name} must be a number") from error
    if math.isnan(number) or math.isinf(number) or number < minimum or (not allow_zero and number == 0):
        raise TrickInputError(f"{name} must be {'more than' if not allow_zero else 'at least'} {minimum:g}")
    return number


EVIDENCE_RULE = ("Computed only from the numbers you entered. ASKODOX does not invent prices, discounts or "
                 "availability; check current prices before deciding.")


def unit_price(options: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Compare pack sizes: [{name, price, quantity, unit}] -> cheapest per unit."""
    if not options or len(options) < 2:
        raise TrickInputError("give at least two options to compare")
    if len(options) > 10:
        raise TrickInputError("compare at most 10 options")
    units = {str(o.get("unit") or "").strip().lower() for o in options}
    if len(units) != 1 or not next(iter(units)):
        raise TrickInputError("all options need the same unit (for example kg or litre)")
    rows = []
    for o in options:
        price = _num("price", o.get("price"), allow_zero=False)
        qty = _num("quantity", o.get("quantity"), allow_zero=False)
        rows.append({"name": str(o.get("name") or "option")[:60], "price": price, "quantity": qty,
                     "per_unit": round(price / qty, 4)})
    rows.sort(key=lambda r: r["per_unit"])
    best, worst = rows[0], rows[-1]
    saving_percent = round((worst["per_unit"] - best["per_unit"]) / worst["per_unit"] * 100, 1)
    return {"unit": next(iter(units)), "ranked": rows, "cheapest": best["name"],
            "saving_vs_costliest_percent": saving_percent,
            "watch_out": ["A bigger pack saves money only if you use it before it expires or spoils.",
                          "Check that the quality / brand is the same before comparing."],
            "evidence_rule": EVIDENCE_RULE}


def buy_vs_rent(*, purchase_price: float, resale_value: float, yearly_upkeep: float, rent_per_month: float,
                months_needed: float) -> Dict[str, Any]:
    price = _num("purchase_price", purchase_price, allow_zero=False)
    resale = _num("resale_value", resale_value)
    upkeep = _num("yearly_upkeep", yearly_upkeep)
    rent = _num("rent_per_month", rent_per_month, allow_zero=False)
    months = _num("months_needed", months_needed, allow_zero=False)
    if resale > price:
        raise TrickInputError("resale value cannot be more than the purchase price")
    own_cost = price - resale + upkeep * months / 12
    rent_cost = rent * months
    monthly_own = upkeep / 12
    breakeven = None if rent <= monthly_own else round((price - resale) / (rent - monthly_own), 1)
    verdict = "buy" if own_cost < rent_cost else "rent" if rent_cost < own_cost else "same"
    return {"own_cost": round(own_cost), "rent_cost": round(rent_cost), "cheaper": verdict,
            "difference": round(abs(own_cost - rent_cost)), "breakeven_months": breakeven,
            "assumptions": ["Resale value is your own estimate; a lower resale makes buying worse.",
                            "Money tied up in the purchase could earn interest elsewhere (not included)."],
            "evidence_rule": EVIDENCE_RULE}


def repair_vs_replace(*, repair_cost: float, replacement_price: float, age_years: float,
                      expected_life_years: float, yearly_running_cost_old: float = 0.0,
                      yearly_running_cost_new: float = 0.0) -> Dict[str, Any]:
    repair = _num("repair_cost", repair_cost)
    replace = _num("replacement_price", replacement_price, allow_zero=False)
    age = _num("age_years", age_years)
    life = _num("expected_life_years", expected_life_years, allow_zero=False)
    old_run = _num("yearly_running_cost_old", yearly_running_cost_old)
    new_run = _num("yearly_running_cost_new", yearly_running_cost_new)
    remaining = max(life - age, 0.0)
    # Cost per remaining year of the repaired item vs the new item's cost per year of its life.
    repaired_per_year = (repair / remaining + old_run) if remaining > 0 else math.inf
    new_per_year = replace / life + new_run
    share = repair / replace
    verdict = "repair" if repaired_per_year < new_per_year else "replace"
    reasons = [f"Repair costs {share * 100:.0f}% of a new one."]
    if remaining <= 0:
        reasons.append("It is already past its expected life.")
    return {"repair_cost_per_remaining_year": None if math.isinf(repaired_per_year) else round(repaired_per_year),
            "new_cost_per_year": round(new_per_year), "suggestion": verdict, "repair_share_percent": round(share * 100, 1),
            "remaining_life_years": round(remaining, 1), "reasons": reasons,
            "assumptions": ["Expected life is your estimate (check the manufacturer / a technician).",
                            "Safety problems (gas, electrical, brakes) are a reason to replace regardless of cost."],
            "evidence_rule": EVIDENCE_RULE}


def total_cost_of_ownership(options: List[Dict[str, Any]], *, years: float) -> Dict[str, Any]:
    """[{name, price, yearly_running, yearly_maintenance, resale_after}] over ``years``."""
    span = _num("years", years, allow_zero=False)
    if not options or len(options) < 2 or len(options) > 6:
        raise TrickInputError("compare between 2 and 6 options")
    rows = []
    for o in options:
        price = _num("price", o.get("price"), allow_zero=False)
        running = _num("yearly_running", o.get("yearly_running", 0))
        maintenance = _num("yearly_maintenance", o.get("yearly_maintenance", 0))
        resale = _num("resale_after", o.get("resale_after", 0))
        total = price + (running + maintenance) * span - resale
        rows.append({"name": str(o.get("name") or "option")[:60], "total": round(total),
                     "per_year": round(total / span)})
    rows.sort(key=lambda r: r["total"])
    return {"years": span, "ranked": rows, "lowest_total": rows[0]["name"],
            "difference_to_next": rows[1]["total"] - rows[0]["total"],
            "watch_out": ["The cheapest to buy is not always the cheapest to own (fuel / power, service, resale)."],
            "evidence_rule": EVIDENCE_RULE}


def bulk_buy(*, unit_price_small: float, unit_price_bulk: float, units_needed: float, bulk_units: float,
             monthly_use: float, shelf_life_months: float) -> Dict[str, Any]:
    small = _num("unit_price_small", unit_price_small, allow_zero=False)
    bulk = _num("unit_price_bulk", unit_price_bulk, allow_zero=False)
    needed = _num("units_needed", units_needed, allow_zero=False)
    pack = _num("bulk_units", bulk_units, allow_zero=False)
    use = _num("monthly_use", monthly_use, allow_zero=False)
    shelf = _num("shelf_life_months", shelf_life_months, allow_zero=False)
    usable = min(pack, use * shelf)
    wasted = max(pack - usable, 0.0)
    bulk_cost = bulk * pack
    small_cost_for_usable = small * usable
    saving = small_cost_for_usable - bulk_cost
    return {"bulk_cost": round(bulk_cost), "same_quantity_small_packs": round(small_cost_for_usable),
            "saving": round(saving), "worth_it": saving > 0, "expected_waste_units": round(wasted, 2),
            "units_needed": needed,
            "assumptions": ["Waste = what you cannot use before the shelf life ends at your usage rate."],
            "evidence_rule": EVIDENCE_RULE}


CALCULATORS = {
    "unit_price": unit_price,
    "buy_vs_rent": buy_vs_rent,
    "repair_vs_replace": repair_vs_replace,
    "total_cost": total_cost_of_ownership,
    "bulk_buy": bulk_buy,
}
