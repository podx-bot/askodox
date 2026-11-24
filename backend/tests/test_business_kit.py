"""Business Kit (owner 2026-11-24): ONE registry of shop categories -> sub-categories (editable in the Command Center),
mixed shops (main + more picks), the shop kind following the main pick, pages from the union of ways of working, and
customer questions answered from the owner's own answers (never guessed; unanswered ones reach the owner)."""

import pytest

from app.services import business_kit, catalogue_templates
from app.services.platform_schema import POS_SHOP_KINDS
from app.services.pos_frontdesk import PosFrontDesk
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import TEMPLATES, PosStore
from app.services.shop_follows import ShopFollows

OWNER = "app-phone-9400000401"
CUSTOMER = "app-phone-9400000402"

# Every key a shop may already have stored from the first category list (2026-11-14): they must keep working.
OLD_KEYS = {
    "meat_fish": ["chicken", "mutton", "fish", "prawns", "eggs"],
    "grocery": ["kirana", "supermarket", "rice_grains", "oil_ghee", "dry_fruits"],
    "veg_fruits": ["vegetables", "fruits", "flowers"],
    "dairy_bakery": ["milk", "sweets", "bakery", "tea_snacks"],
    "food": ["tiffin", "meals", "biryani", "fast_food", "juice", "catering"],
    "clothing": ["clothes", "sarees", "readymade", "footwear", "tailor"],
    "mobile_electronics": ["mobile_shop", "mobile_repair", "electronics", "computer"],
    "home_hardware": ["hardware", "paints", "electrical", "plumbing_items", "furniture"],
    "beauty": ["salon", "beauty_parlour", "cosmetics"],
    "health": ["medical_shop", "clinic", "lab", "optical"],
    "vehicles": ["bike_repair", "car_repair", "spare_parts", "tyres", "wash"],
    "farming": ["fertilizers", "pesticides", "farm_tools", "dairy_farm"],
    "services": ["electrician", "plumber", "carpenter", "cleaning", "laundry", "photography"],
    "education": ["tuition", "coaching", "school", "stationery"],
    "transport": ["cab", "auto", "travels", "goods"],
    "events": ["function_hall", "decoration", "tent_house", "sound_light"],
}


@pytest.fixture(autouse=True)
def _defaults_only():
    business_kit.set_source(None)
    yield
    business_kit.set_source(None)


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    pushes = []
    desk = PosFrontDesk(store, PosRestaurant(store), notify=lambda u, t, b, r, k: pushes.append((u, t, b, r, k)),
                        pay_to=lambda owner, amount, note, ref: [])
    shop = store.create_business(OWNER, {"name": "Sri Sai Tailors", "state_code": "37", "template": "kirana"})["id"]
    return store, ShopFollows(store.db_path), desk, shop, pushes


def test_registry_covers_every_old_key_and_every_setting_is_real():
    cats = business_kit.categories()
    subs = [s for c in cats for s in c["subs"]]
    assert len(cats) >= 23 and len(subs) >= 200
    assert len({s["key"] for s in subs}) == len(subs), "sub-category keys are unique"
    assert not {c["key"] for c in cats} & {s["key"] for s in subs}, "a category key is never a sub-category key"
    for cat, keys in OLD_KEYS.items():
        assert business_kit.category(cat), cat
        for key in keys:
            assert business_kit.sub(key), key  # labels of stored keys keep working
    for s in subs:
        assert s["kind"] in TEMPLATES, s["key"]
        assert not s["catalogue"] or catalogue_templates.template(s["catalogue"]), s["key"]
        assert s["flows"] and set(s["flows"]) <= set(business_kit.FLOWS), s["key"]
        assert s["try_on"] in business_kit.TRY_ON_KINDS
        assert s["en"] and s["te"] and s["asks"], s["key"]
    assert tuple(POS_SHOP_KINDS) == tuple(TEMPLATES), "the Command Center kind list follows the POS kinds"
    for kind, key in business_kit.KIND_DEFAULT_SUB.items():
        assert kind in TEMPLATES and business_kit.sub(key), kind
    # what the owner named: mixed shops, building, real estate, hotel rooms, try-on
    for key in ("motors_pumps", "geysers_water_heaters", "real_estate_agent_broker", "hotel_lodge", "resort_homestay",
                "building_contractor", "cakes"):
        assert business_kit.sub(key), key
    assert business_kit.sub("clothes")["try_on"] == "on_me" and business_kit.sub("paints")["try_on"] == "in_home"


def test_command_center_rows_add_change_and_hide_without_an_app_update():
    rows = [
        {"status": "ACTIVE", "data": {"key": "pets", "label_en": "Pets", "label_te": "పెంపుడు జంతువులు", "order": 1}},
        {"status": "ACTIVE", "data": {"key": "pet_grooming", "parent": "pets", "label_en": "Pet grooming",
                                      "label_te": "పెట్ గ్రూమింగ్", "flows": ["3"], "shop_kind": "salon",
                                      "customer_questions": "ఇంటికి వస్తారా?\nఒక్కసారికి ఎంత?"}},
        {"status": "ACTIVE", "data": {"key": "chicken", "parent": "meat_fish", "label_en": "Chicken (broiler)",
                                      "label_te": "బ్రాయిలర్ చికెన్"}},
        {"status": "DISABLED", "data": {"key": "dry_fish", "parent": "meat_fish", "label_en": "Dry fish"}},
    ]
    business_kit.set_source(lambda: rows, key="cc-test")
    pets = business_kit.category("pets")
    assert pets and [s["key"] for s in pets["subs"]] == ["pet_grooming"]
    groom = business_kit.sub("pet_grooming")
    assert groom["flows"] == ["3"] and groom["kind"] == "salon" and groom["asks"] == ["ఇంటికి వస్తారా?", "ఒక్కసారికి ఎంత?"]
    chicken = business_kit.sub("chicken")
    assert chicken["en"] == "Chicken (broiler)" and chicken["flows"] == ["1"] and chicken["asks"], "edits keep the rest"
    assert business_kit.sub("dry_fish") is None
    assert business_kit.shop_kit("pets", "pet_grooming")["page_family"] == "service"


def test_mixed_shop_gets_the_union_of_its_ways_of_working():
    hotel = business_kit.shop_kit("food", "meals", "sweets,bakery,cakes,not_a_key,meals")
    assert hotel["subs"] == ["meals", "sweets", "bakery", "cakes"], "unknown keys and the main pick are dropped"
    assert hotel["flows"] == ["1", "2", "4"] and hotel["page_family"] == "food" and hotel["kind"] == "restaurant"
    furniture = business_kit.shop_kit("home_needs", "furniture", ["plumbing_items", "motors_pumps", "geysers_water_heaters"])
    assert furniture["page_family"] == "retail" and "4" in furniture["flows"] and furniture["try_on"] == ["in_home"]
    estate = business_kit.shop_kit("real_estate", "real_estate_agent_broker")
    assert estate["page_family"] == "service" and estate["flows"] == ["6"]
    old_shop = business_kit.shop_kit("", "", "", "kirana")
    assert old_shop["main"] == "kirana" and old_shop["inferred"] and old_shop["page_family"] == "retail"
    assert business_kit.shop_kit("", "", "", "general")["main"] is None
    assert business_kit.shop_kit("health", "medical_shop")["high_stakes"]
    salon = business_kit.shop_kit("", "", "", "salon")  # bookings first, products on the side
    assert salon["flows"] == ["1", "3"] and salon["page_family"] == "service"
    shop = business_kit.shop_kit("clothing", "clothes", "tailor")  # a clothes shop that also stitches
    assert shop["page_family"] == "retail" and shop["flows"] == ["1", "4"]


def test_picking_the_main_category_sets_the_shop_kind_and_catalogue(env):
    store, follows, _, shop, _ = env
    saved = follows.save_profile(shop, OWNER, {"category": "food", "subcategory": "meals", "more": "sweets, bakery"})
    assert saved["kit"]["subs"] == ["meals", "sweets", "bakery"] and saved["kit"]["page_family"] == "food"
    assert [m["key"] for m in saved["profile"]["more"]] == ["sweets", "bakery"]
    biz = store.business(shop, OWNER)
    assert biz["template"] == "restaurant" and biz["kit"]["flows"] == ["1", "2", "4"]
    assert next(b for b in store.my_businesses(OWNER) if b["id"] == shop)["kit"]["page_family"] == "food"
    # the owner changes what the shop is -> the kind + ready list follow
    follows.save_profile(shop, OWNER, {"category": "clothing", "subcategory": "tailor"})
    biz = store.business(shop, OWNER)
    assert biz["template"] == "clothing" and biz["catalogue_template"] == "fashion"
    assert biz["kit"]["page_family"] == "service"
    # same main pick again: an owner's own later choices are left alone
    with store._connect() as conn:
        conn.execute("UPDATE pos_businesses SET catalogue_template = 'grocery' WHERE id = ?", (shop,))
    follows.save_profile(shop, OWNER, {"category": "clothing", "subcategory": "tailor", "hours": "9-9"})
    assert store.business(shop, OWNER)["catalogue_template"] == "grocery"


def test_customer_questions_are_answered_from_the_owners_own_answer(env):
    store, follows, desk, shop, pushes = env
    follows.save_profile(shop, OWNER, {"category": "clothing", "subcategory": "tailor", "more": "sarees"})
    listed = follows.questions(shop, OWNER)
    keys = {q["key"]: q for q in listed["questions"]}
    fall = next(k for k, q in keys.items() if "fall pico" in q["question"])
    assert all(q["answer"] == "" for q in listed["questions"])
    # not answered yet: said honestly, and the owner is told ONCE that day
    reply = desk.shop_answer(shop, "fall pico chesi istara? చీర fall pico చేసి ఇస్తారా", True)
    assert "ఇంకా ASKODOX లో పెట్టలేదు" in reply and len(pushes) == 1
    assert pushes[0][0] == OWNER and pushes[0][3] == f"/me/business/{shop}/profile?qa=1"
    desk.shop_answer(shop, "fall pico చేసి ఇస్తారా", True)
    assert len(pushes) == 1, "once a day per question"
    assert follows.questions(shop, OWNER)["waiting"] == 1
    # the owner answers once -> every customer gets it
    follows.save_answers(shop, OWNER, {fall: "అవును, ₹100, మరుసటి రోజు", "not.a.question": "x"})
    assert desk.shop_answer(shop, "చీరకి fall pico చేసి ఇస్తారా?", True) == "💬 అవును, ₹100, మరుసటి రోజు"
    assert follows.questions(shop, OWNER)["waiting"] == 0
    # a customer's own question (no usual question fits) also reaches the owner, who can answer it
    reply = desk.shop_answer(shop, "do you stitch school uniforms in bulk?", False)
    assert "We have told the shop" in reply and len(pushes) == 2
    own = next(q for q in follows.questions(shop, OWNER)["questions"] if q["source"] == "customer")
    follows.save_answers(shop, OWNER, {own["key"]: "Yes, from 20 pieces."})
    assert desk.shop_answer(shop, "Do you stitch school uniforms in bulk?", False) == "💬 Yes, from 20 pieces."
    # words that ask nothing stay quiet; only the owner sees / answers
    assert desk.shop_answer(shop, "Sri Sai Tailors", False) == ""
    with pytest.raises(Exception):
        follows.questions(shop, CUSTOMER)
    with pytest.raises(Exception):
        follows.save_answers(shop, CUSTOMER, {fall: "no"})


def test_a_question_about_a_menu_item_is_left_to_the_menu(env):
    store, follows, desk, _, pushes = env
    hotel = store.create_business(OWNER, {"name": "Murali Hotel", "state_code": "37", "template": "restaurant",
                                          "invoice_prefix": "MH"})["id"]
    store.add_product(hotel, OWNER, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 16000})
    follows.save_profile(hotel, OWNER, {"category": "food", "subcategory": "biryani"})
    assert desk.shop_answer(hotel, "chicken biryani fresh ga undha?", False) == ""
    assert pushes == []


def test_matching_reads_word_forms_in_any_script():
    cands = [{"question": "ఇంటికి వచ్చి sample తీస్తారా?", "answer": "a"},
             {"question": "report ఎప్పుడు?", "answer": "b"}]
    assert business_kit.match_question("ఇంటికీ వచ్చి sample తీస్తారు", cands)["answer"] == "a"
    assert business_kit.match_question("report eppudu vastundi", cands)["answer"] == "b"
    assert business_kit.match_question("ఎంత?", cands) is None
    assert not business_kit.looks_like_question("Murali Hotel")
    assert business_kit.looks_like_question("రేపు సాయంత్రం తెరిచి ఉంటుందా ?")
