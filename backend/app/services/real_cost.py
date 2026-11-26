"""Real cost of a choice (owner 2026-11-26): the cheaper price somewhere far is only cheaper after the trip is paid.

A TV is Rs 10,000 here and Rs 9,500 in the city -- but the city trip costs petrol, two people's meals, a little extra
spending and half a day. Biryani is Rs 200 to pick up, Rs 220 delivered, Rs 250 from a better place. This module does
the sum the way a practical friend would: every option gets ONE total (price + delivery fee + the trip), the options
are ranked by it, and the answer says how much the best one really saves and the break-even (how much cheaper the far
price must be before the trip is worth it).

Category-free: it knows nothing about TVs or biryani, only prices, distance, people and a few labelled assumptions.
Assumptions (petrol price, mileage, meal cost, speed) are ESTIMATES the person's own words override; every result
carries them so the answer can say what it assumed. Money is integer paise inside, rupees at the edges. Pure -- no
database, no network.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

# Estimates only (India, 2026): the person's own numbers always win. Shown in every result under "assumed".
DEFAULT_ASSUMPTIONS: Dict[str, float] = {
    "petrol_per_litre": 105.0,      # Rs / litre
    "bike_km_per_litre": 45.0,
    "car_km_per_litre": 14.0,
    "auto_per_km": 14.0,            # Rs / km for the whole auto
    "bus_per_km_per_person": 2.0,   # Rs / km / person
    "meal_per_person": 120.0,       # Rs per meal when the trip needs one
    "city_speed_kmph": 28.0,
    "time_value_per_hour": 0.0,     # Rs / hour / person -- 0 = time is shown, never priced, unless the person says
}

MODES = ("bike", "car", "auto", "bus", "walk", "none")
MAX_OPTIONS = 5
TIE_PERCENT = 3.0   # inside this share of the cheaper total (or Rs 50) the money does not decide
TIE_RUPEES = 50.0


class RealCostError(ValueError):
    """A bad input; the route turns it into a 422 with this message."""


def _paise(rupees: float) -> int:
    return int(round(rupees * 100))


def _rupees(paise: int) -> float:
    return round(paise / 100, 2)


def _num(value: Any, name: str, *, low: float = 0.0, high: float = 1e8) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise RealCostError(f"{name} must be a number")
    if number != number or number < low or number > high:
        raise RealCostError(f"{name} is out of range")
    return number


def assumptions(overrides: Optional[Dict[str, Any]] = None) -> Dict[str, float]:
    merged = dict(DEFAULT_ASSUMPTIONS)
    for key, value in (overrides or {}).items():
        if key not in DEFAULT_ASSUMPTIONS or value in (None, ""):
            continue
        merged[key] = _num(value, key, low=0.0, high=1e6)
    if merged["bike_km_per_litre"] <= 0 or merged["car_km_per_litre"] <= 0 or merged["city_speed_kmph"] <= 0:
        raise RealCostError("mileage and speed must be above zero")
    return merged


def trip_cost_paise(mode: str, km: float, people: int, a: Dict[str, float]) -> int:
    """What moving the person (or people) the whole way costs, in paise. `km` = the whole trip, there and back."""
    if mode in ("walk", "none") or km <= 0:
        return 0
    if mode == "bike":
        return _paise(km / a["bike_km_per_litre"] * a["petrol_per_litre"])
    if mode == "car":
        return _paise(km / a["car_km_per_litre"] * a["petrol_per_litre"])
    if mode == "auto":
        return _paise(km * a["auto_per_km"])
    if mode == "bus":
        return _paise(km * a["bus_per_km_per_person"] * max(1, people))
    raise RealCostError("mode must be one of " + ", ".join(MODES))


def _option(raw: Dict[str, Any], a: Dict[str, float], index: int) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise RealCostError("each option must be an object")
    label = str(raw.get("label") or f"Option {index + 1}")[:60]
    price = _paise(_num(raw.get("price"), "price"))
    fee = _paise(_num(raw.get("delivery_fee", 0), "delivery_fee"))
    one_way = _num(raw.get("one_way_km", 0), "one_way_km", high=3000)
    round_trip = raw.get("round_trip", True) is not False
    km = one_way * (2 if round_trip else 1)
    mode = str(raw.get("mode") or ("bike" if km > 0 else "none")).lower()
    if mode not in MODES:
        raise RealCostError("mode must be one of " + ", ".join(MODES))
    people = int(_num(raw.get("people", 1), "people", low=1, high=20))
    meals = int(_num(raw.get("meals", 0), "meals", high=100))      # meals bought on the trip, all people together
    extras = _paise(_num(raw.get("extras", 0), "extras"))            # parking, tea, shopping on the way, ...
    hours = km / a["city_speed_kmph"] + _num(raw.get("extra_hours", 0), "extra_hours", high=48)
    travel = trip_cost_paise(mode, km, people, a)
    meals_paise = _paise(meals * a["meal_per_person"])
    time_paise = _paise(hours * people * a["time_value_per_hour"])
    total = price + fee + travel + meals_paise + extras + time_paise
    return {
        "label": label,
        "price": _rupees(price), "delivery_fee": _rupees(fee), "travel": _rupees(travel),
        "meals": _rupees(meals_paise), "extras": _rupees(extras), "time_value": _rupees(time_paise),
        "trip_km": round(km, 1), "hours": round(hours, 1), "people": people, "mode": mode,
        "extra_on_top": _rupees(total - price), "total": _rupees(total), "_total_paise": total,
    }


def compare(options: List[Dict[str, Any]], overrides: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Rank the options by their real total. The best is the lowest total; a near-tie says money does not decide."""
    if not isinstance(options, list) or not 2 <= len(options) <= MAX_OPTIONS:
        raise RealCostError(f"give 2 to {MAX_OPTIONS} options to compare")
    a = assumptions(overrides)
    rows = [_option(o, a, i) for i, o in enumerate(options)]
    ranked = sorted(rows, key=lambda r: (r["_total_paise"], r["trip_km"]))
    best, runner = ranked[0], ranked[1]
    gap = (runner["_total_paise"] - best["_total_paise"]) / 100
    tie = gap <= max(TIE_RUPEES, runner["total"] * TIE_PERCENT / 100)
    # The lowest sticker price is not always the best total -- say so when it differs.
    sticker = min(rows, key=lambda r: r["price"])
    # Break-even for each option against the best-priced near option: how much cheaper its sticker price must be.
    nearest = min(rows, key=lambda r: (r["trip_km"], r["_total_paise"]))
    for r in rows:
        r["break_even_discount"] = round(max(0.0, r["extra_on_top"] - nearest["extra_on_top"]), 2)
    for r in rows:
        r.pop("_total_paise", None)
    return {
        "options": rows,
        "best": best["label"],
        "best_total": best["total"],
        "saves_vs_next": round(gap, 2),
        "money_decides": not tie,
        "sticker_winner_differs": sticker["label"] != best["label"],
        "nearest": nearest["label"],
        "assumed": a,
        "estimate": True,
    }


def summary(result: Dict[str, Any], te: bool = False) -> str:
    """One plain verdict line + the working, in the person's language (te / en)."""
    rows = {r["label"]: r for r in result["options"]}
    best = rows[result["best"]]
    near = rows[result["nearest"]]
    gap = result["saves_vs_next"]
    if not result["money_decides"]:
        return (f"ఖర్చు దాదాపు సమానం (తేడా ₹{gap:,.0f} లోపే) -- దగ్గరదే తీసుకోండి: సమయం, అలసట మిగులుతాయి."
                if te else
                f"The money is about equal (under Rs {gap:,.0f} apart) -- take the nearer one and keep the time and effort.")
    if best["label"] == near["label"]:
        far = max(result["options"], key=lambda r: r["trip_km"])
        return (f"{best['label']} బెటర్: అన్నీ కలిపి ₹{best['total']:,.0f}. దూరం వెళ్తే ప్రయాణానికే ₹{far['extra_on_top'] - far['delivery_fee']:,.0f} "
                f"అదనం, అంతా కలిపి ₹{gap:,.0f} ఎక్కువ అవుతుంది." if te else
                f"{best['label']} is better: Rs {best['total']:,.0f} all in. Going far adds about "
                f"Rs {far['extra_on_top'] - far['delivery_fee']:,.0f} for the trip and ends Rs {gap:,.0f} dearer.")
    return (f"{best['label']} బెటర్: అన్నీ కలిపి ₹{best['total']:,.0f}, దగ్గరదానికంటే ₹{gap:,.0f} తక్కువ (ప్రయాణం, భోజనం కలిపి)." if te else
            f"{best['label']} wins even after the trip: Rs {best['total']:,.0f} all in, Rs {gap:,.0f} less than the next best.")


def assumption_sentence() -> str:
    """The typical figures, in one line, for the brain's prompt -- built from DEFAULT_ASSUMPTIONS so the two never drift."""
    a = DEFAULT_ASSUMPTIONS
    return (f"(petrol about Rs {a['petrol_per_litre']:g} a litre, a bike about {a['bike_km_per_litre']:g} km a litre, "
            f"a car about {a['car_km_per_litre']:g}, an auto about Rs {a['auto_per_km']:g} a km, a meal about "
            f"Rs {a['meal_per_person']:g} a person, city speed about {a['city_speed_kmph']:g} km an hour)")
