"""Owner 2026-11-19: bulk items pasted from Excel / Sheets / CSV -- any shop type, any column order with a header."""
from app.services.pos_menu_table import parse


def test_header_in_any_order_with_unit_and_category():
    got = parse("Category,Item Name,Unit,MRP\nGrocery,Sugar 1kg,pcs,45\nOil,Sunflower Oil,ltr,\"1,250.50\"\n,No price,pcs,")
    assert got == [
        {"name": "Sugar 1kg", "price_paise": 4500, "unit": "pcs", "today_only": False, "menu_group": "Grocery"},
        {"name": "Sunflower Oil", "price_paise": 125050, "unit": "l", "today_only": False, "menu_group": "Oil"},
    ]


def test_tabs_without_header_from_a_sheet():
    got = parse("Saree cotton\t850\nKurta\t499\tpiece", "pcs")
    assert [(i["name"], i["price_paise"], i["unit"]) for i in got] == [("Saree cotton", 85000, "pcs"), ("Kurta", 49900, "pcs")]


def test_telugu_header_and_plain_text_is_not_a_table():
    got = parse("పేరు,ధర\nచికెన్ బిర్యానీ,180", "plate")
    assert got[0]["name"] == "చికెన్ బిర్యానీ" and got[0]["price_paise"] == 18000 and got[0]["unit"] == "plate"
    assert parse("tea 10 coffee 15") is None
