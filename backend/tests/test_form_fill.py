from app.services.form_fill import fill

FIELDS = [
    {"key": "name", "label": "Customer name", "kind": "text"},
    {"key": "phone", "label": "Phone", "kind": "phone"},
    {"key": "advance", "label": "Advance", "kind": "number"},
    {"key": "method", "label": "Method", "kind": "choice", "options": ["cash", "upi", "card"]},
]


def test_model_answer_is_checked_against_each_box():
    answer = '{"name": "Rama", "phone": "81256 56812", "advance": "₹9,000", "method": "UPI", "ghost": "x"}'
    out = fill(FIELDS, "Rama 8125656812 advance 9000 upi", phrase=lambda p: "Sure: " + answer)
    assert out["values"] == {"name": "Rama", "phone": "8125656812", "advance": "9000", "method": "upi"} and out["used_ai"]


def test_bad_values_are_dropped_and_nothing_is_invented():
    out = fill(FIELDS, "hello", phrase=lambda p: '{"phone": "12345", "method": "bitcoin", "advance": "lots"}')
    assert out["values"] == {}


def test_rules_work_without_a_model():
    out = fill(FIELDS, "ఫోన్ 8125656812 అడ్వాన్స్ 9000")
    assert out["values"] == {"phone": "8125656812", "advance": "9000"} and not out["used_ai"]
    assert fill([FIELDS[0]], "Rama Krishna")["values"] == {"name": "Rama Krishna"}


def test_model_failure_falls_back_to_rules():
    def boom(prompt):
        raise RuntimeError("down")
    assert fill(FIELDS, "9000", phrase=boom)["values"] == {"advance": "9000"}
