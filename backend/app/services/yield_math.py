"""Buy in one form, sell in another (owner 2026-11-27, phase 6): live birds -> dressed meat, a goat -> mutton, fish ->
cleaned fish, paddy -> rice, a cloth roll -> pieces. Pure integer arithmetic: grams, paise, rates in paise per kg,
shares in basis points. Twin of `lib/features/yield/yield_math.dart`; both must pass `test/fixtures/yield_vectors.json`
-- change the two together. Every number here comes from the owner's own entries; nothing is a preset.
"""
from __future__ import annotations

from typing import List, Optional, Tuple


def round_div(n: int, d: int) -> int:
    """n / d to the nearest whole, halves away from zero. d > 0."""
    if d <= 0:
        raise ValueError("divisor must be positive")
    return (abs(n) * 2 + d) // (2 * d) * (1 if n >= 0 else -1)


def goods_paise(live_grams: int, rate_paise: int) -> int:
    """What the goods cost: weight x rate per kg."""
    return round_div(live_grams * rate_paise, 1000)


def total_paise(live_grams: int, rate_paise: int, extras_paise: List[int]) -> int:
    """Goods + the other costs of bringing them in (transport, unloading ...)."""
    return goods_paise(live_grams, rate_paise) + sum(max(0, int(e)) for e in extras_paise)


def yield_bp(live_grams: int, out_grams: int) -> Optional[int]:
    """What came out of what went in, in basis points (7000 = 70%). None until both are weighed."""
    if live_grams <= 0 or out_grams <= 0:
        return None
    return round_div(out_grams * 10000, live_grams)


def cost_per_kg(total: int, byproduct_paise: int, out_grams: int) -> Optional[int]:
    """The real cost of one sellable kg: (everything spent - what the by-products brought) / what came out."""
    if out_grams <= 0:
        return None
    return round_div(max(0, total - max(0, byproduct_paise)) * 1000, out_grams)


def form_cost(cost: int, form_yield_bp: int) -> Optional[int]:
    """A further form (skinless, boneless) cut from the sellable kg: its cost per kg by the owner's own yield."""
    if form_yield_bp <= 0:
        return None
    return round_div(cost * 10000, form_yield_bp)


def profit(sell_paise: int, cost: int) -> Tuple[int, Optional[int]]:
    """Profit per kg and its share of the selling rate in basis points (None with no selling rate)."""
    gain = sell_paise - cost
    return gain, (round_div(gain * 10000, sell_paise) if sell_paise > 0 else None)


def rise_effect(delta_paise: int, y_bp: int) -> Optional[int]:
    """The buying rate moves by delta: the sellable kg's cost moves by this much."""
    if y_bp <= 0:
        return None
    return round_div(delta_paise * 10000, y_bp)


def expected_grams(opening: int, made: int, sold: int) -> int:
    return opening + made - sold


def diff_value(diff_grams: int, cost: int) -> int:
    """What a stock difference is worth at cost (always shown as a positive amount)."""
    return round_div(abs(diff_grams) * cost, 1000)


def day_profit(sold_grams: int, sell_paise: int, cost: int, other_paise: int) -> Tuple[int, int, int]:
    """(sales, cost of what was sold, profit) for a day."""
    sales = round_div(sold_grams * sell_paise, 1000)
    spent = round_div(sold_grams * cost, 1000)
    return sales, spent, sales - spent - max(0, other_paise)
