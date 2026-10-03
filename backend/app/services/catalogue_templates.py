"""Ready-made seller catalogue templates (Grocery, Fruits & Vegetables,
Fashion).

A template is a starting list of GENERIC items (no brands, no prices, no
photos) that a seller picks from, then edits: price, size/unit, stock and an
optional photo of their own item. Nothing here is ever shown to buyers as a
listing -- items become listings only when the seller publishes them with
their own price (see routes/catalogue.py).

Names are given in English, Telugu and Hindi so the conversation language is
kept.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

# (key, en, te, hi, unit, sizes)
_Item = tuple[str, str, str, str, str, tuple[str, ...]]


def _category(key: str, en: str, te: str, hi: str, items: List[_Item]) -> Dict[str, Any]:
    return {
        "key": key,
        "name": {"en": en, "te": te, "hi": hi},
        "items": [
            {"key": f"{key}.{k}", "name": {"en": n_en, "te": n_te, "hi": n_hi}, "unit": unit, "sizes": list(sizes)}
            for k, n_en, n_te, n_hi, unit, sizes in items
        ],
    }


_GROCERY = [
    _category("rice_grains", "Rice & grains", "బియ్యం & ధాన్యాలు", "चावल और अनाज", [
        ("sona_masoori", "Sona Masoori rice", "సోనా మసూరి బియ్యం", "सोना मसूरी चावल", "kg", ("1 kg", "5 kg", "25 kg")),
        ("basmati", "Basmati rice", "బాస్మతి బియ్యం", "बासमती चावल", "kg", ("1 kg", "5 kg")),
        ("idli_rice", "Idli rice", "ఇడ్లీ బియ్యం", "इडली चावल", "kg", ("1 kg", "5 kg")),
        ("wheat", "Wheat", "గోధుమలు", "गेहूं", "kg", ("1 kg", "5 kg")),
        ("jowar", "Jowar", "జొన్నలు", "ज्वार", "kg", ("500 g", "1 kg")),
        ("ragi", "Ragi", "రాగులు", "रागी", "kg", ("500 g", "1 kg")),
    ]),
    _category("dals", "Dals & pulses", "పప్పులు", "दालें", [
        ("toor", "Toor dal", "కంది పప్పు", "तूर दाल", "kg", ("500 g", "1 kg")),
        ("moong", "Moong dal", "పెసర పప్పు", "मूंग दाल", "kg", ("500 g", "1 kg")),
        ("urad", "Urad dal", "మినప పప్పు", "उड़द दाल", "kg", ("500 g", "1 kg")),
        ("chana", "Chana dal", "శనగ పప్పు", "चना दाल", "kg", ("500 g", "1 kg")),
        ("masoor", "Masoor dal", "మసూర్ పప్పు", "मसूर दाल", "kg", ("500 g", "1 kg")),
        ("groundnut", "Groundnuts", "వేరుశనగలు", "मूंगफली", "kg", ("500 g", "1 kg")),
    ]),
    _category("oils_ghee", "Oils & ghee", "నూనెలు & నెయ్యి", "तेल और घी", [
        ("sunflower", "Sunflower oil", "సన్‌ఫ్లవర్ నూనె", "सूरजमुखी तेल", "L", ("1 L", "5 L")),
        ("groundnut_oil", "Groundnut oil", "వేరుశనగ నూనె", "मूंगफली तेल", "L", ("1 L", "5 L")),
        ("palm", "Palm oil", "పామాయిల్", "पाम तेल", "L", ("1 L",)),
        ("sesame", "Sesame oil", "నువ్వుల నూనె", "तिल का तेल", "L", ("500 ml", "1 L")),
        ("ghee", "Ghee", "నెయ్యి", "घी", "L", ("200 ml", "500 ml", "1 L")),
    ]),
    _category("spices", "Spices & masalas", "మసాలాలు", "मसाले", [
        ("chilli_powder", "Red chilli powder", "కారం పొడి", "लाल मिर्च पाउडर", "g", ("100 g", "250 g", "500 g")),
        ("turmeric", "Turmeric powder", "పసుపు", "हल्दी पाउडर", "g", ("100 g", "250 g")),
        ("coriander_powder", "Coriander powder", "ధనియాల పొడి", "धनिया पाउडर", "g", ("100 g", "250 g")),
        ("mustard", "Mustard seeds", "ఆవాలు", "राई", "g", ("100 g", "250 g")),
        ("cumin", "Cumin seeds", "జీలకర్ర", "जीरा", "g", ("100 g", "250 g")),
        ("tamarind", "Tamarind", "చింతపండు", "इमली", "g", ("250 g", "500 g")),
        ("garam_masala", "Garam masala", "గరం మసాలా", "गरम मसाला", "g", ("50 g", "100 g")),
    ]),
    _category("flours", "Flours & rava", "పిండ్లు & రవ్వ", "आटा और सूजी", [
        ("atta", "Wheat atta", "గోధుమ పిండి", "गेहूं का आटा", "kg", ("1 kg", "5 kg")),
        ("maida", "Maida", "మైదా", "मैदा", "kg", ("500 g", "1 kg")),
        ("rava", "Bombay rava", "బొంబాయి రవ్వ", "सूजी", "kg", ("500 g", "1 kg")),
        ("besan", "Besan", "శనగ పిండి", "बेसन", "kg", ("500 g", "1 kg")),
        ("rice_flour", "Rice flour", "బియ్యం పిండి", "चावल का आटा", "kg", ("500 g", "1 kg")),
    ]),
    _category("sugar_salt", "Sugar, salt & jaggery", "చక్కెర, ఉప్పు & బెల్లం", "चीनी, नमक और गुड़", [
        ("sugar", "Sugar", "చక్కెర", "चीनी", "kg", ("1 kg", "5 kg")),
        ("salt", "Iodised salt", "ఉప్పు", "नमक", "kg", ("1 kg",)),
        ("jaggery", "Jaggery", "బెల్లం", "गुड़", "kg", ("500 g", "1 kg")),
    ]),
    _category("tea_coffee", "Tea, coffee & beverages", "టీ, కాఫీ & పానీయాలు", "चाय, कॉफ़ी और पेय", [
        ("tea", "Tea powder", "టీ పొడి", "चाय पत्ती", "g", ("250 g", "500 g", "1 kg")),
        ("coffee", "Coffee powder", "కాఫీ పొడి", "कॉफ़ी पाउडर", "g", ("100 g", "200 g", "500 g")),
        ("milk_powder", "Milk powder", "పాల పొడి", "दूध पाउडर", "g", ("200 g", "500 g")),
    ]),
    _category("snacks", "Snacks & biscuits", "స్నాక్స్ & బిస్కెట్లు", "नमकीन और बिस्किट", [
        ("biscuits", "Biscuits", "బిస్కెట్లు", "बिस्किट", "pack", ("small pack", "family pack")),
        ("namkeen", "Namkeen / mixture", "మిక్చర్", "नमकीन", "g", ("200 g", "500 g")),
        ("poha", "Poha (atukulu)", "అటుకులు", "पोहा", "g", ("500 g", "1 kg")),
        ("vermicelli", "Vermicelli", "సేమియా", "सेवई", "g", ("200 g", "500 g")),
    ]),
    _category("personal_care", "Personal care", "వ్యక్తిగత సంరక్షణ", "व्यक्तिगत देखभाल", [
        ("bath_soap", "Bath soap", "స్నానపు సబ్బు", "नहाने का साबुन", "piece", ("1 piece", "pack of 4")),
        ("shampoo", "Shampoo", "షాంపూ", "शैम्पू", "ml", ("sachet", "180 ml", "340 ml")),
        ("toothpaste", "Toothpaste", "టూత్‌పేస్ట్", "टूथपेस्ट", "g", ("100 g", "200 g")),
        ("coconut_oil", "Coconut hair oil", "కొబ్బరి నూనె", "नारियल तेल", "ml", ("100 ml", "200 ml", "500 ml")),
    ]),
    _category("cleaning", "Cleaning & household", "శుభ్రత & ఇంటి సామాన్లు", "सफ़ाई और घरेलू", [
        ("detergent", "Detergent powder", "డిటర్జెంట్ పౌడర్", "डिटर्जेंट पाउडर", "kg", ("500 g", "1 kg", "4 kg")),
        ("dishwash", "Dishwash bar", "గిన్నెల సబ్బు", "बर्तन साबुन", "piece", ("1 piece", "pack of 3")),
        ("floor_cleaner", "Floor cleaner", "ఫ్లోర్ క్లీనర్", "फ़र्श क्लीनर", "L", ("500 ml", "1 L")),
        ("agarbatti", "Agarbatti", "అగరబత్తీలు", "अगरबत्ती", "pack", ("1 pack",)),
    ]),
]

_FRUITS_VEGETABLES = [
    _category("vegetables", "Vegetables", "కూరగాయలు", "सब्ज़ियाँ", [
        ("tomato", "Tomato", "టమాటా", "टमाटर", "kg", ("500 g", "1 kg")),
        ("onion", "Onion", "ఉల్లిపాయ", "प्याज़", "kg", ("1 kg", "5 kg")),
        ("potato", "Potato", "బంగాళాదుంప", "आलू", "kg", ("1 kg", "5 kg")),
        ("brinjal", "Brinjal", "వంకాయ", "बैंगन", "kg", ("500 g", "1 kg")),
        ("okra", "Okra (bhindi)", "బెండకాయ", "भिंडी", "kg", ("500 g", "1 kg")),
        ("green_chilli", "Green chilli", "పచ్చిమిర్చి", "हरी मिर्च", "g", ("100 g", "250 g")),
        ("carrot", "Carrot", "క్యారెట్", "गाजर", "kg", ("500 g", "1 kg")),
        ("cabbage", "Cabbage", "క్యాబేజీ", "पत्ता गोभी", "piece", ("1 piece",)),
    ]),
    _category("leafy", "Leafy greens", "ఆకుకూరలు", "पत्तेदार सब्ज़ियाँ", [
        ("coriander", "Coriander leaves", "కొత్తిమీర", "धनिया पत्ती", "bunch", ("1 bunch",)),
        ("curry_leaves", "Curry leaves", "కరివేపాకు", "करी पत्ता", "bunch", ("1 bunch",)),
        ("spinach", "Spinach", "పాలకూర", "पालक", "bunch", ("1 bunch",)),
        ("gongura", "Gongura", "గోంగూర", "गोंगुरा", "bunch", ("1 bunch",)),
    ]),
    _category("fruits", "Fruits", "పండ్లు", "फल", [
        ("banana", "Banana", "అరటి పండ్లు", "केला", "dozen", ("1 dozen",)),
        ("apple", "Apple", "ఆపిల్", "सेब", "kg", ("500 g", "1 kg")),
        ("mango", "Mango", "మామిడి పండు", "आम", "kg", ("1 kg", "5 kg")),
        ("papaya", "Papaya", "బొప్పాయి", "पपीता", "piece", ("1 piece",)),
        ("guava", "Guava", "జామ పండు", "अमरूद", "kg", ("500 g", "1 kg")),
        ("orange", "Orange", "నారింజ", "संतरा", "kg", ("1 kg",)),
    ]),
]

_FASHION = [
    _category("men", "Men's clothing", "పురుషుల దుస్తులు", "पुरुषों के कपड़े", [
        ("shirt", "Shirt", "షర్ట్", "शर्ट", "piece", ("S", "M", "L", "XL", "XXL")),
        ("tshirt", "T-shirt", "టీ-షర్ట్", "टी-शर्ट", "piece", ("S", "M", "L", "XL")),
        ("trousers", "Trousers", "ప్యాంట్", "पतलून", "piece", ("30", "32", "34", "36")),
        ("jeans", "Jeans", "జీన్స్", "जींस", "piece", ("30", "32", "34", "36")),
        ("lungi", "Lungi / dhoti", "లుంగీ / పంచె", "लुंगी / धोती", "piece", ("free size",)),
    ]),
    _category("women", "Women's clothing", "మహిళల దుస్తులు", "महिलाओं के कपड़े", [
        ("saree", "Saree", "చీర", "साड़ी", "piece", ("free size",)),
        ("kurti", "Kurti", "కుర్తీ", "कुर्ती", "piece", ("S", "M", "L", "XL")),
        ("churidar", "Churidar set", "చుడీదార్ సెట్", "चूड़ीदार सेट", "piece", ("S", "M", "L", "XL")),
        ("nightwear", "Nightwear", "నైట్ డ్రెస్", "नाइटवियर", "piece", ("M", "L", "XL")),
        ("blouse", "Readymade blouse", "రెడీమేడ్ బ్లౌజ్", "रेडीमेड ब्लाउज़", "piece", ("32", "34", "36", "38")),
    ]),
    _category("kids", "Kids' clothing", "పిల్లల దుస్తులు", "बच्चों के कपड़े", [
        ("kids_frock", "Frock", "ఫ్రాక్", "फ्रॉक", "piece", ("1-2 y", "3-4 y", "5-6 y")),
        ("kids_set", "Shirt & shorts set", "షర్ట్ & షార్ట్స్ సెట్", "शर्ट और शॉर्ट्स सेट", "piece", ("1-2 y", "3-4 y", "5-6 y")),
        ("school_uniform", "School uniform", "స్కూల్ యూనిఫాం", "स्कूल यूनिफॉर्म", "piece", ("by size",)),
    ]),
    _category("footwear_accessories", "Footwear & accessories", "చెప్పులు & యాక్సెసరీస్", "जूते-चप्पल और एक्सेसरीज़", [
        ("chappal", "Chappals", "చెప్పులు", "चप्पल", "pair", ("6", "7", "8", "9", "10")),
        ("shoes", "Shoes", "షూస్", "जूते", "pair", ("6", "7", "8", "9", "10")),
        ("belt", "Belt", "బెల్ట్", "बेल्ट", "piece", ("free size",)),
        ("handbag", "Handbag", "హ్యాండ్‌బ్యాగ్", "हैंडबैग", "piece", ("one size",)),
    ]),
]

TEMPLATES: Dict[str, Dict[str, Any]] = {
    "grocery": {"key": "grocery", "name": {"en": "Grocery (kirana)", "te": "కిరాణా", "hi": "किराना"},
                "category_tag": "grocery", "categories": _GROCERY},
    "fruits_vegetables": {"key": "fruits_vegetables",
                          "name": {"en": "Fruits & vegetables", "te": "పండ్లు & కూరగాయలు", "hi": "फल और सब्ज़ियाँ"},
                          "category_tag": "fruits_vegetables", "categories": _FRUITS_VEGETABLES},
    "fashion": {"key": "fashion", "name": {"en": "Fashion & clothing", "te": "బట్టలు & ఫ్యాషన్", "hi": "कपड़े और फ़ैशन"},
                "category_tag": "fashion", "categories": _FASHION},
}


def _count(template: Dict[str, Any]) -> int:
    return sum(len(c["items"]) for c in template["categories"])


def summaries() -> List[Dict[str, Any]]:
    return [
        {"key": t["key"], "name": t["name"], "categories": len(t["categories"]), "items": _count(t)}
        for t in TEMPLATES.values()
    ]


def template(key: str) -> Optional[Dict[str, Any]]:
    found = TEMPLATES.get(str(key or "").strip().casefold())
    if not found:
        return None
    return {**found, "items": _count(found)}


def item(template_key: str, item_key: str) -> Optional[Dict[str, Any]]:
    found = TEMPLATES.get(template_key)
    if not found:
        return None
    for category in found["categories"]:
        for entry in category["items"]:
            if entry["key"] == item_key:
                return {**entry, "category": category["key"], "category_name": category["name"]}
    return None
