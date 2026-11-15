"""Spoken menu parsing + the receptionist's reading of one customer sentence."""
from app.services.pos_menu_voice import assist, parse_menu, people_estimate

MENU = [
    {"id": "p1", "name": "Chicken Biryani", "name_te": "చికెన్ బిర్యానీ", "price_paise": 16000, "available": True},
    {"id": "p2", "name": "Mutton Biryani", "name_te": "మటన్ బిర్యానీ", "price_paise": 25000, "available": True, "today_only": True},
    {"id": "p3", "name": "Chicken Fry", "name_te": "చికెన్ ఫ్రై", "price_paise": 30000, "available": True},
    {"id": "p4", "name": "Veg Curry", "name_te": "వెజ్ కర్రీ", "price_paise": 9000, "available": False},
]


def test_parse_english_and_telugu_menu():
    items = parse_menu("chicken biryani 160, fry 300")
    assert [(i["name"], i["price_paise"], i["today_only"]) for i in items] == [("Chicken biryani", 16000, False), ("Fry", 30000, False)]
    te = parse_menu("చికెన్ దమ్ బిర్యానీ ప్లేట్ 160 ఫ్రై 300 కందిపప్పు కేజీ ౧౨౦")
    assert [(i["name"], i["price_paise"], i["unit"]) for i in te] == [
        ("చికెన్ దమ్ బిర్యానీ", 16000, "plate"), ("ఫ్రై", 30000, "plate"), ("కందిపప్పు", 12000, "kg")]


def test_today_only_markers():
    items = parse_menu("biryani 160, fry 300, ఈ రోజు స్పెషల్: mutton biryani 250, haleem 120, daily: tea 10")
    flags = {i["name"]: i["today_only"] for i in items}
    assert flags == {"Biryani": False, "Fry": False, "Mutton biryani": True, "Haleem": True, "Tea": False}
    single = parse_menu("biryani 160 today only, fry 300")
    assert {i["name"]: i["today_only"] for i in single} == {"Biryani": True, "Fry": False}


def test_same_name_later_wins_and_garbage_is_skipped():
    items = parse_menu("biryani 150, biryani 160, hello there, 500")
    assert [(i["name"], i["price_paise"]) for i in items] == [("Biryani", 16000)]


def test_order_with_quantity_telugu_and_english():
    r = assist("రెండు చికెన్ ఫ్రై", MENU, te=True)
    assert r["intent"] == "order" and r["add"][0]["product_id"] == "p3" and r["add"][0]["qty"] == 2
    r = assist("2 chicken biryani and one chicken fry", MENU, te=False)
    assert {(a["product_id"], a["qty"]) for a in r["add"]} == {("p1", 2), ("p3", 1)}


def test_ambiguous_biryani_asks_which():
    r = assist("biryani", MENU, te=False)
    assert r["intent"] == "clarify" and {o["product_id"] for o in r["options"]} == {"p1", "p2"}


def test_price_available_and_finished():
    assert "₹300" in assist("chicken fry price", MENU, te=False)["reply"]
    assert assist("చికెన్ ఫ్రై ఉందా", MENU, te=True)["intent"] == "available"
    gone = assist("is veg curry available", MENU, te=False)
    assert gone["intent"] == "unavailable" and not gone["add"]
    assert assist("veg curry", MENU, te=False)["add"] == []  # an unavailable item is never added


def test_special_menu_people_repeat_confirm():
    assert assist("today special", MENU, te=False)["options"][0]["product_id"] == "p2"
    s = assist("నలుగురికి ఏం బాగుంటుంది", MENU, te=True)
    assert s["intent"] == "suggest" and sum(l["qty"] for l in s["suggest"]) == 4
    assert people_estimate("for 6 people") == 6
    assert assist("menu", MENU, te=False)["intent"] == "menu"
    rep = assist("same as last time", MENU, te=False, last_items=[{"product_id": "p1", "qty": 2}, {"product_id": "p4", "qty": 1}])
    assert rep["intent"] == "repeat" and [(a["product_id"], a["qty"]) for a in rep["add"]] == [("p1", 2)]
    cart = [{"product_id": "p1", "qty": 2, "price_paise": 16000}]
    c = assist("అంతే", MENU, te=True, cart=cart)
    assert c["confirm"] and "320" in c["reply"]
    assert assist("that's all", MENU, te=False, cart=[])["intent"] == "confirm_empty"


def test_name_remove_unknown():
    assert assist("my name is Ravi", MENU, te=False)["name"] == "Ravi"
    assert assist("remove chicken fry", MENU, te=False)["remove"] == ["p3"]
    assert assist("pizza", MENU, te=False)["intent"] == "unknown"
