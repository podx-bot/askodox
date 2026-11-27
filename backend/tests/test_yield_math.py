"""Buy in one form, sell in another: the shared vectors (also run by the Flutter test) and the design's own sample."""
import json
import pathlib

import pytest

from app.services import yield_math as m

VECTORS = json.loads((pathlib.Path(__file__).resolve().parents[2] / "test" / "fixtures" / "yield_vectors.json")
                     .read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", VECTORS["cases"], ids=lambda c: c["name"])
def test_batch_vectors(case):
    e = case["expect"]
    total = m.total_paise(case["live_g"], case["rate_p"], case["extras_p"])
    y = m.yield_bp(case["live_g"], case["out_g"])
    cost = m.cost_per_kg(total, case["byproduct_p"], case["out_g"])
    assert m.goods_paise(case["live_g"], case["rate_p"]) == e["goods_p"]
    assert total == e["total_p"] and y == e["yield_bp"] and cost == e["cost_p"]
    form = m.form_cost(cost, case["form_yield_bp"]) if cost is not None and case["form_yield_bp"] else None
    assert form == e["form_cost_p"]
    base = form if form is not None else cost
    if base is None:
        assert e["profit_p"] is None and e["margin_bp"] is None and e["rise_p"] is None
    else:
        assert m.profit(case["sell_p"], base) == (e["profit_p"], e["margin_bp"])
        assert m.rise_effect(case["delta_p"], y) == e["rise_p"]


@pytest.mark.parametrize("day", VECTORS["days"], ids=lambda d: d["name"])
def test_day_vectors(day):
    e = day["expect"]
    expected = m.expected_grams(day["opening_g"], day["made_g"], day["sold_g"])
    assert expected == e["expected_g"] and day["actual_g"] - expected == e["diff_g"]
    assert m.diff_value(day["actual_g"] - expected, day["cost_p"]) == e["diff_value_p"]
    assert m.day_profit(day["sold_g"], day["sell_p"], day["cost_p"], day["other_p"]) == (e["sales_p"], e["spent_p"], e["profit_p"])


def test_the_design_sample_by_hand():
    # 100 kg live at Rs 100 + transport Rs 300 + unloading Rs 200 = Rs 10,500; 70 kg dressed = 70%; Rs 150 a kg.
    total = m.total_paise(100_000, 10_000, [30_000, 20_000])
    assert total == 1_050_000 and m.yield_bp(100_000, 70_000) == 7000
    cost = m.cost_per_kg(total, 0, 70_000)
    assert cost == 15_000 and m.profit(18_000, cost) == (3_000, 1667)  # Rs 30 a kg, 16.67% of the selling rate
    assert m.rise_effect(200, 7000) == 286  # the buying rate up Rs 2 -> the dressed kg up about Rs 3
    # day: 5.0 + 70.0 - 66.2 = 8.8 should be there; 8.1 on the scale = 0.7 kg short, worth Rs 105 at cost
    assert m.expected_grams(5_000, 70_000, 66_200) == 8_800 and m.diff_value(8_100 - 8_800, cost) == 10_500
    assert m.day_profit(66_200, 18_000, cost, 50_000) == (1_191_600, 993_000, 148_600)


def test_rounding_and_empty_inputs():
    assert m.round_div(5, 2) == 3 and m.round_div(-5, 2) == -3 and m.round_div(4, 3) == 1 and m.round_div(0, 7) == 0
    with pytest.raises(ValueError):
        m.round_div(1, 0)
    assert m.yield_bp(0, 10) is None and m.yield_bp(10, 0) is None
    assert m.cost_per_kg(1000, 0, 0) is None and m.form_cost(15_000, 0) is None and m.rise_effect(200, 0) is None
    assert m.profit(0, 15_000) == (-15_000, None)
    assert m.cost_per_kg(1000, 5000, 1000) == 0  # by-products can bring the cost to zero, never below
    assert m.total_paise(1000, 10_000, [-500]) == 10_000  # a negative extra is not a discount
