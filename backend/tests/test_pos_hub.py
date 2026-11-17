import json
from tests.test_pos_frontdesk import OWNER, env  # noqa: F401  (fixture)

from app.services import pos_hub


def test_find_item_exact_contained_and_ambiguous():
    items = [{"id": "1", "name": "Chicken 65"}, {"id": "2", "name": "Chicken Biryani"}, {"id": "3", "name": "Mutton Biryani"}]
    assert pos_hub.find_item(items, "chicken 65")["id"] == "1"
    assert pos_hub.find_item(items, "mutton biryani")["id"] == "3"
    assert pos_hub.find_item(items, "biryani") is None  # two biryanis: ask, never guess
    assert pos_hub.find_item(items, "paneer") is None


def test_read_and_plan_keep_changes_behind_confirm():
    def model(prompt, max_tokens=0):
        return json.dumps({"action": "item_price", "item": "Chicken 65", "price": 220})
    intent = pos_hub.read("chicken 65 dhara 220", "menu", model)
    plan = pos_hub.plan(intent, [{"id": "1", "name": "Chicken 65", "price_paise": 20000}], {}, te=True)
    assert plan["confirm"] == {"action": "item_price", "product_id": "1", "price_paise": 22000,
                               "summary": plan["confirm"]["summary"]}
    assert "₹200" in plan["confirm"]["summary"] and "₹220" in plan["confirm"]["summary"]


def test_unknown_page_or_action_is_never_acted_on():
    intent = pos_hub.read("x", "hub", lambda p, max_tokens=0: json.dumps({"action": "open", "page": "admin.delete"}))
    assert intent["action"] == "unknown"
    intent = pos_hub.read("x", "hub", lambda p, max_tokens=0: json.dumps({"action": "drop_table"}))
    assert intent["action"] == "unknown"
    assert "confirm" not in pos_hub.plan(intent, [], {}, te=False)


def test_answer_uses_only_the_shops_numbers():
    numbers = {"sales": {"paise": 1845000, "bills": 41}, "split": {"cash_paise": 920000, "online_paise": 695000},
               "dues": {"paise": 230000, "people": 6}, "orders": {"new": 3, "cooking": 5}}
    text = pos_hub.answer_text(numbers, te=False)
    assert "₹18,450" in text and "41 bills" in text and "₹2,300" in text


def test_summary_and_confirmed_change_on_a_real_shop(env):  # noqa: F811
    from tests.test_pos_frontdesk import env as _env  # noqa: F401
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    with store._connect() as conn:
        numbers = pos_hub.summary(conn, biz)
    assert numbers["menu"]["items"] >= 2 and numbers["orders"]["new"] == 0
    pos_hub.run({"action": "item_off", "product_id": biryani}, store=store, desk=desk, business_id=biz, user=OWNER)
    menu = {m["id"]: m for m in desk.menu_admin(biz, OWNER)["items"]}
    assert menu[biryani]["available"] is False
    pos_hub.run({"action": "item_price", "product_id": fry, "price_paise": 12300}, store=store, desk=desk,
                business_id=biz, user=OWNER)
    assert desk.menu_admin(biz, OWNER)["items"] and any(m["price_paise"] == 12300 for m in desk.menu_admin(biz, OWNER)["items"])
    import pytest
    from app.services.pos_store import PosError
    with pytest.raises(PosError):
        pos_hub.run({"action": "delete_everything"}, store=store, desk=desk, business_id=biz, user=OWNER)


def test_spoken_expense_waits_for_confirm_then_lands_in_the_cashbook(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    intent = pos_hub.read("kooragayalu 1200 karchu", "money", lambda p, max_tokens=0: json.dumps(
        {"action": "add_expense", "price": 1200, "category": "stock", "note": "vegetables"}))
    plan = pos_hub.plan(intent, [], {}, te=False)
    assert plan["confirm"]["amount_paise"] == 120000 and "vegetables" in plan["confirm"]["summary"]
    pos_hub.run(plan["confirm"], store=store, desk=desk, business_id=biz, user=OWNER)
    from app.services.pos_cashbook import PosCashbook
    assert PosCashbook(store).month(biz, OWNER)["expense_paise"] == 120000
