"""Ready-made seller catalogue templates (grocery, fruits & vegetables,
fashion, meat & poultry, pickles, tiles & marble, electronics, services) --
ONE data-driven engine: each template carries its own category attributes.

A template is a starting list of GENERIC items (no brands, no prices, no
photos) that a seller picks from, then edits: price, size/unit, stock and an
optional photo of their own item. Nothing here is ever shown to buyers as a
listing -- items become listings only when the seller publishes them with
their own price (see routes/catalogue.py).

Names are given in English, Telugu and Hindi so the conversation language is
kept.
"""
from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional

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


def _attr(key: str, en: str, te: str, hi: str, kind: str = "text", options: tuple[str, ...] = (),
          required: bool = False, *, group: str = "Details", unit: str | None = None, multi: bool = False,
          depends_on: tuple[str, tuple[str, ...]] | None = None, filterable: bool | None = None,
          minimum: float | None = None, maximum: float | None = None) -> Dict[str, Any]:
    """A category-specific detail the SELLER fills in (never pre-filled with a
    fact: options are choices to pick from, text stays empty).

    kind: text | choice | number. ``multi`` = several options may be chosen;
    ``depends_on`` = (attribute key, values) -- shown / kept only when that
    attribute has one of the values; ``filterable`` = buyers can filter on it
    (default: every choice / number attribute)."""
    spec: Dict[str, Any] = {"key": key, "label": {"en": en, "te": te, "hi": hi}, "kind": kind,
                            "options": list(options), "required": required, "group": group,
                            "multi": multi and kind == "choice",
                            "filterable": (kind in ("choice", "number")) if filterable is None else filterable}
    if unit:
        spec["unit"] = unit
    if depends_on:
        spec["depends_on"] = {"key": depends_on[0], "values": list(depends_on[1])}
    if minimum is not None:
        spec["min"] = minimum
    if maximum is not None:
        spec["max"] = maximum
    return spec


# Inherited by every product template (Amazon-style listing basics: pricing,
# wholesale, stock keeping, after-sale, negotiation). Children override by key.
_PRODUCT_BASE = [
    _attr("mrp", "MRP", "MRP", "MRP", "number", unit="₹", group="Pricing", minimum=0),
    _attr("sku", "SKU / product code", "SKU / ప్రొడక్ట్ కోడ్", "SKU / उत्पाद कोड", group="Stock", filterable=False),
    _attr("barcode", "Barcode / EAN", "బార్‌కోడ్", "बारकोड", group="Stock", filterable=False),
    _attr("wholesale", "Wholesale available", "హోల్‌సేల్ ఉంది", "थोक उपलब्ध", "choice", ("Yes", "No"), group="Pricing"),
    _attr("moq", "Minimum order quantity", "కనీస ఆర్డర్ పరిమాణం", "न्यूनतम ऑर्डर मात्रा", "number", group="Pricing",
          depends_on=("wholesale", ("Yes",)), minimum=1),
    _attr("wholesale_price", "Wholesale price", "హోల్‌సేల్ ధర", "थोक मूल्य", "number", unit="₹", group="Pricing",
          depends_on=("wholesale", ("Yes",)), minimum=0),
    _attr("negotiable", "Price negotiable", "ధర బేరం", "मोलभाव", "choice", ("Yes", "No"), group="Pricing"),
    _attr("returns", "Returns", "రిటర్న్స్", "वापसी", "choice", ("No returns", "Exchange only", "7-day return"),
          group="After sale"),
    _attr("delivery", "Delivery", "డెలివరీ", "डिलीवरी", "choice", ("Pickup", "Home delivery", "Courier"),
          group="Delivery", multi=True),
]

_SERVICE_BASE = [
    _attr("pricing", "Pricing", "ధర విధానం", "कीमत तरीका", "choice",
          ("Fixed price", "Starting from", "Per hour", "Quotation after visit"), group="Pricing"),
    _attr("visit", "Where", "ఎక్కడ", "कहाँ", "choice", ("At customer place", "At my shop", "Online"),
          group="Service", multi=True),
    _attr("service_area", "Service area", "సర్వీస్ ప్రాంతం", "सेवा क्षेत्र", group="Service", filterable=False),
    _attr("availability", "Available days / hours", "అందుబాటు రోజులు / సమయం", "उपलब्ध दिन / समय", group="Service",
          filterable=False),
    _attr("experience_years", "Experience", "అనుభవం", "अनुभव", "number", unit="years", group="Qualification",
          minimum=0, maximum=80),
]

_DELIVERY = _attr("delivery", "Delivery", "డెలివరీ", "डिलीवरी", "choice", ("Pickup only", "Home delivery", "Both"))
_SERVICE_AREA = _attr("service_area", "Service / delivery area", "సర్వీస్ / డెలివరీ ప్రాంతం", "सेवा / डिलीवरी क्षेत्र")

_MEAT = [
    _category("chicken", "Chicken", "చికెన్", "चिकन", [
        ("whole", "Whole chicken", "పూర్తి కోడి", "पूरा चिकन", "kg", ("1 kg", "2 kg")),
        ("curry_cut", "Chicken curry cut", "చికెన్ కర్రీ కట్", "चिकन करी कट", "kg", ("500 g", "1 kg", "2 kg")),
        ("boneless", "Boneless chicken", "బోన్‌లెస్ చికెన్", "बोनलेस चिकन", "kg", ("500 g", "1 kg")),
        ("country", "Country chicken (natu kodi)", "నాటు కోడి", "देसी मुर्गा", "kg", ("1 kg",)),
        ("eggs", "Eggs", "కోడి గుడ్లు", "अंडे", "dozen", ("6", "12", "30")),
    ]),
    _category("mutton_fish", "Mutton & fish", "మటన్ & చేపలు", "मटन और मछली", [
        ("mutton_curry", "Mutton curry cut", "మటన్ కర్రీ కట్", "मटन करी कट", "kg", ("500 g", "1 kg")),
        ("mutton_boneless", "Boneless mutton", "బోన్‌లెస్ మటన్", "बोनलेस मटन", "kg", ("500 g", "1 kg")),
        ("fish", "Fresh fish", "తాజా చేపలు", "ताज़ी मछली", "kg", ("500 g", "1 kg")),
        ("prawns", "Prawns", "రొయ్యలు", "झींगे", "kg", ("250 g", "500 g", "1 kg")),
    ]),
]

_PICKLES = [
    _category("veg_pickles", "Veg pickles", "వెజ్ పచ్చళ్లు", "शाकाहारी अचार", [
        ("avakaya", "Mango pickle (avakaya)", "ఆవకాయ", "आम का अचार", "g", ("250 g", "500 g", "1 kg")),
        ("gongura", "Gongura pickle", "గోంగూర పచ్చడి", "गोंगुरा अचार", "g", ("250 g", "500 g", "1 kg")),
        ("lemon", "Lemon pickle", "నిమ్మకాయ పచ్చడి", "नींबू का अचार", "g", ("250 g", "500 g")),
        ("tomato", "Tomato pickle", "టమాటా పచ్చడి", "टमाटर अचार", "g", ("250 g", "500 g")),
    ]),
    _category("nonveg_pickles", "Non-veg pickles", "నాన్-వెజ్ పచ్చళ్లు", "मांसाहारी अचार", [
        ("chicken_pickle", "Chicken pickle", "చికెన్ పచ్చడి", "चिकन अचार", "g", ("250 g", "500 g", "1 kg")),
        ("mutton_pickle", "Mutton pickle", "మటన్ పచ్చడి", "मटन अचार", "g", ("250 g", "500 g")),
        ("prawn_pickle", "Prawn pickle", "రొయ్యల పచ్చడి", "झींगा अचार", "g", ("250 g", "500 g")),
    ]),
]

_TILES = [
    _category("tiles", "Tiles", "టైల్స్", "टाइल्स", [
        ("floor_tiles", "Floor tiles", "ఫ్లోర్ టైల్స్", "फ़्लोर टाइल्स", "sq ft", ("600x600 mm", "800x800 mm", "600x1200 mm")),
        ("wall_tiles", "Wall tiles", "వాల్ టైల్స్", "वॉल टाइल्स", "sq ft", ("300x450 mm", "300x600 mm")),
        ("parking_tiles", "Parking tiles", "పార్కింగ్ టైల్స్", "पार्किंग टाइल्स", "sq ft", ("300x300 mm", "400x400 mm")),
    ]),
    _category("stone", "Marble & granite", "మార్బుల్ & గ్రానైట్", "मार्बल और ग्रेनाइट", [
        ("marble", "Marble", "మార్బుల్", "मार्बल", "sq ft", ("slab",)),
        ("granite", "Granite", "గ్రానైట్", "ग्रेनाइट", "sq ft", ("slab",)),
        ("kota", "Kota / Shahabad stone", "కోటా / షహాబాద్ రాయి", "कोटा / शाहाबाद पत्थर", "sq ft", ("2x2 ft",)),
    ]),
]

_ELECTRONICS = [
    _category("phones_computers", "Phones & computers", "ఫోన్లు & కంప్యూటర్లు", "फ़ोन और कंप्यूटर", [
        ("mobile", "Mobile phone", "మొబైల్ ఫోన్", "मोबाइल फ़ोन", "piece", ("one size",)),
        ("laptop", "Laptop", "ల్యాప్‌టాప్", "लैपटॉप", "piece", ("one size",)),
        ("accessory", "Charger / earphones", "చార్జర్ / ఇయర్‌ఫోన్స్", "चार्जर / ईयरफ़ोन", "piece", ("one size",)),
    ]),
    _category("appliances", "Home appliances", "గృహోపకరణాలు", "घरेलू उपकरण", [
        ("tv", "Television", "టీవీ", "टीवी", "piece", ("32 inch", "43 inch", "55 inch")),
        ("fridge", "Refrigerator", "ఫ్రిజ్", "फ्रिज", "piece", ("single door", "double door")),
        ("washing_machine", "Washing machine", "వాషింగ్ మెషిన్", "वॉशिंग मशीन", "piece", ("6 kg", "7 kg", "8 kg")),
        ("ac", "Air conditioner", "ఏసీ", "एसी", "piece", ("1 ton", "1.5 ton", "2 ton")),
    ]),
]

_SERVICES = [
    _category("home_services", "Home services", "ఇంటి సేవలు", "घरेलू सेवाएँ", [
        ("cleaning", "Home cleaning", "ఇంటి శుభ్రత", "घर की सफ़ाई", "visit", ("per visit",)),
        ("plumbing", "Plumbing", "ప్లంబింగ్", "प्लंबिंग", "visit", ("per visit",)),
        ("electrical", "Electrical repair", "ఎలక్ట్రికల్ రిపేర్", "बिजली मरम्मत", "visit", ("per visit",)),
        ("ac_service", "AC service", "ఏసీ సర్వీస్", "एसी सर्विस", "visit", ("per visit",)),
    ]),
    _category("personal_services", "Personal & learning", "వ్యక్తిగత & విద్య", "व्यक्तिगत और शिक्षा", [
        ("tuition", "Home tuition", "హోమ్ ట్యూషన్", "होम ट्यूशन", "hour", ("per hour", "per month")),
        ("beauty", "Beauty at home", "ఇంటి వద్ద బ్యూటీ", "घर पर ब्यूटी", "visit", ("per visit",)),
        ("tailoring", "Tailoring", "టైలరింగ్", "सिलाई", "piece", ("per piece",)),
    ]),
]


_FURNITURE = [
    _category("home_furniture", "Home furniture", "ఇంటి ఫర్నిచర్", "घर का फ़र्नीचर", [
        ("sofa", "Sofa", "సోఫా", "सोफ़ा", "piece", ("2 seater", "3 seater", "L-shape")),
        ("bed", "Bed", "మంచం", "बेड", "piece", ("single", "double", "queen", "king")),
        ("dining", "Dining table", "డైనింగ్ టేబుల్", "डाइनिंग टेबल", "piece", ("4 seater", "6 seater")),
        ("wardrobe", "Wardrobe", "బీరువా", "अलमारी", "piece", ("2 door", "3 door")),
        ("mattress", "Mattress", "పరుపు", "गद्दा", "piece", ("single", "double", "queen", "king")),
    ]),
]

_VEHICLES = [
    _category("vehicles", "Vehicles", "వాహనాలు", "वाहन", [
        ("bike", "Motorbike / scooter", "బైక్ / స్కూటర్", "बाइक / स्कूटर", "piece", ("one",)),
        ("car", "Car", "కారు", "कार", "piece", ("one",)),
        ("auto", "Auto rickshaw", "ఆటో", "ऑटो", "piece", ("one",)),
        ("tractor", "Tractor", "ట్రాక్టర్", "ट्रैक्टर", "piece", ("one",)),
    ]),
    _category("spare_parts", "Spare parts", "స్పేర్ పార్ట్స్", "स्पेयर पार्ट्स", [
        ("tyre", "Tyre", "టైర్", "टायर", "piece", ("by size",)),
        ("battery", "Battery", "బ్యాటరీ", "बैटरी", "piece", ("by model",)),
        ("engine_oil", "Engine oil", "ఇంజిన్ ఆయిల్", "इंजन ऑयल", "L", ("1 L", "3.5 L", "5 L")),
    ]),
]

_JEWELLERY_BEAUTY = [
    _category("jewellery", "Jewellery", "ఆభరణాలు", "आभूषण", [
        ("chain", "Chain", "గొలుసు", "चेन", "piece", ("by weight",)),
        ("bangles", "Bangles", "గాజులు", "चूड़ियाँ", "set", ("2.4", "2.6", "2.8")),
        ("earrings", "Earrings", "చెవిపోగులు", "झुमके", "pair", ("one size",)),
    ]),
    _category("beauty", "Beauty & personal care", "బ్యూటీ & వ్యక్తిగత సంరక్షణ", "ब्यूटी और पर्सनल केयर", [
        ("cream", "Face cream", "ఫేస్ క్రీమ్", "फ़ेस क्रीम", "g", ("50 g", "100 g")),
        ("hair_oil", "Hair oil", "జుట్టు నూనె", "बालों का तेल", "ml", ("100 ml", "200 ml", "500 ml")),
        ("soap", "Soap", "సబ్బు", "साबुन", "piece", ("75 g", "100 g", "125 g")),
    ]),
]

_AGRICULTURE = [
    _category("farm_produce", "Farm produce", "పంట ఉత్పత్తులు", "कृषि उपज", [
        ("paddy", "Paddy", "వరి ధాన్యం", "धान", "quintal", ("by quintal",)),
        ("cotton", "Cotton", "పత్తి", "कपास", "quintal", ("by quintal",)),
        ("chilli", "Dry chilli", "ఎండు మిర్చి", "सूखी मिर्च", "quintal", ("by quintal",)),
    ]),
    _category("farm_inputs", "Seeds & farm inputs", "విత్తనాలు & వ్యవసాయ సామగ్రి", "बीज और कृषि सामग्री", [
        ("seeds", "Seeds", "విత్తనాలు", "बीज", "kg", ("1 kg", "5 kg")),
        ("fertiliser", "Fertiliser", "ఎరువులు", "खाद", "kg", ("25 kg", "50 kg")),
        ("sprayer", "Sprayer", "స్ప్రేయర్", "स्प्रेयर", "piece", ("manual", "battery")),
    ]),
]

_PROPERTY = [
    _category("property", "Property", "ఆస్తి", "संपत्ति", [
        ("house_rent", "House for rent", "అద్దెకు ఇల్లు", "किराए पर घर", "month", ("1 BHK", "2 BHK", "3 BHK")),
        ("house_sale", "House for sale", "అమ్మకానికి ఇల్లు", "बिक्री के लिए घर", "piece", ("1 BHK", "2 BHK", "3 BHK")),
        ("plot", "Plot / land", "ప్లాట్ / భూమి", "प्लॉट / ज़मीन", "sq yd", ("by area",)),
        ("shop_rent", "Shop for rent", "అద్దెకు షాప్", "किराए पर दुकान", "month", ("by area",)),
    ]),
]

TEMPLATES: Dict[str, Dict[str, Any]] = {
    "product_base": {"key": "product_base", "name": {"en": "Any product (base)", "te": "ఏదైనా వస్తువు (బేస్)",
                                                     "hi": "कोई भी उत्पाद (बेस)"},
                     "category_tag": "product", "abstract": True, "categories": [], "attributes": _PRODUCT_BASE},
    "service_base": {"key": "service_base", "name": {"en": "Any service (base)", "te": "ఏదైనా సేవ (బేస్)",
                                                     "hi": "कोई भी सेवा (बेस)"},
                     "category_tag": "service", "abstract": True, "categories": [], "attributes": _SERVICE_BASE},
    "grocery": {"key": "grocery", "name": {"en": "Grocery (kirana)", "te": "కిరాణా", "hi": "किराना"},
                "category_tag": "grocery", "parent": "product_base", "categories": _GROCERY,
                "attributes": [_attr("brand", "Brand", "బ్రాండ్", "ब्रांड"),
                               _attr("pack", "Pack type", "ప్యాక్ రకం", "पैक प्रकार", "choice", ("Loose", "Packed"))]},
    "fruits_vegetables": {"key": "fruits_vegetables",
                          "name": {"en": "Fruits & vegetables", "te": "పండ్లు & కూరగాయలు", "hi": "फल और सब्ज़ियाँ"},
                          "category_tag": "fruits_vegetables", "parent": "product_base", "categories": _FRUITS_VEGETABLES,
                          "attributes": [_attr("grade", "Quality", "నాణ్యత", "गुणवत्ता", "choice", ("Regular", "Premium", "Organic"))]},
    "fashion": {"key": "fashion", "name": {"en": "Fashion & clothing", "te": "బట్టలు & ఫ్యాషన్", "hi": "कपड़े और फ़ैशन"},
                "category_tag": "fashion", "parent": "product_base", "categories": _FASHION,
                "attributes": [_attr("color", "Colour", "రంగు", "रंग", required=True),
                               _attr("fabric", "Fabric", "బట్ట", "कपड़ा", "choice",
                                     ("Cotton", "Polyester", "Silk", "Linen", "Denim", "Blend")),
                               _attr("fit", "Fit", "ఫిట్", "फ़िट", "choice", ("Regular", "Slim", "Loose"))]},
    "meat_poultry": {"key": "meat_poultry", "name": {"en": "Meat, chicken & fish", "te": "మాంసం, చికెన్ & చేపలు",
                                                     "hi": "मांस, चिकन और मछली"},
                     "category_tag": "meat", "parent": "product_base", "categories": _MEAT,
                     "attributes": [_attr("cut", "Cut", "కట్", "कट", "choice",
                                          ("Curry cut", "Boneless", "Biryani cut", "Whole", "Mince")),
                                    _attr("freshness", "Fresh / frozen", "తాజా / ఫ్రోజెన్", "ताज़ा / फ़्रोज़न", "choice",
                                          ("Fresh", "Frozen"), required=True),
                                    _attr("skin", "Skin", "చర్మం", "स्किन", "choice", ("With skin", "Skinless")), _SERVICE_AREA]},
    "pickles": {"key": "pickles", "name": {"en": "Pickles & podis", "te": "పచ్చళ్లు & పొడులు", "hi": "अचार और पोडी"},
                "category_tag": "pickles", "parent": "product_base", "categories": _PICKLES,
                "attributes": [_attr("spice", "Spice level", "కారం స్థాయి", "तीखापन", "choice", ("Mild", "Medium", "Hot")),
                               _attr("ingredients", "Main ingredients", "ముఖ్య పదార్థాలు", "मुख्य सामग्री", required=True),
                               _attr("oil", "Oil used", "వాడిన నూనె", "इस्तेमाल तेल", "choice",
                                     ("Groundnut", "Sesame", "Sunflower", "Mustard")),
                               _attr("packaging", "Packaging", "ప్యాకింగ్", "पैकिंग", "choice", ("Pouch", "Jar", "Bottle")),
                               _attr("shelf_life", "Shelf life", "నిల్వ కాలం", "शेल्फ़ लाइफ़")]},
    "tiles_marble": {"key": "tiles_marble", "name": {"en": "Tiles, marble & granite", "te": "టైల్స్, మార్బుల్ & గ్రానైట్",
                                                     "hi": "टाइल्स, मार्बल और ग्रेनाइट"},
                     "category_tag": "building_materials", "parent": "product_base", "categories": _TILES,
                     "attributes": [_attr("material", "Material", "మెటీరియల్", "सामग्री", "choice",
                                          ("Ceramic", "Vitrified", "Porcelain", "Marble", "Granite", "Natural stone"),
                                          required=True),
                                    _attr("color", "Colour", "రంగు", "रंग"),
                                    _attr("thickness", "Thickness", "మందం", "मोटाई"),
                                    _attr("finish", "Finish", "ఫినిష్", "फ़िनिश", "choice", ("Glossy", "Matt", "Rustic", "Polished")),
                                    _attr("coverage", "Coverage per box", "బాక్స్‌కు కవరేజ్", "प्रति बॉक्स कवरेज"), _SERVICE_AREA]},
    "electronics": {"key": "electronics", "name": {"en": "Electronics & appliances", "te": "ఎలక్ట్రానిక్స్ & ఉపకరణాలు",
                                                   "hi": "इलेक्ट्रॉनिक्स और उपकरण"},
                    "category_tag": "electronics", "parent": "product_base", "categories": _ELECTRONICS,
                    "attributes": [_attr("brand", "Brand", "బ్రాండ్", "ब्रांड", required=True),
                                   _attr("model", "Model", "మోడల్", "मॉडल"),
                                   _attr("storage", "Storage / capacity", "స్టోరేజ్ / సామర్థ్యం", "स्टोरेज / क्षमता"),
                                   _attr("condition", "Condition", "స్థితి", "स्थिति", "choice",
                                         ("New", "Refurbished", "Used"), required=True),
                                   _attr("warranty", "Warranty", "వారంటీ", "वारंटी")]},
    "services": {"key": "services", "name": {"en": "Services", "te": "సేవలు", "hi": "सेवाएँ"},
                 "category_tag": "services", "parent": "service_base", "categories": _SERVICES,
                 "attributes": [_attr("scope", "What is included", "ఏమేమి ఉంటాయి", "क्या शामिल है", required=True),
                                _attr("duration", "Usual duration", "సాధారణ సమయం", "सामान्य समय"),
                                _attr("availability", "Available days / hours", "అందుబాటు రోజులు / సమయం",
                                      "उपलब्ध दिन / समय"),
                                ]},
    "furniture": {"key": "furniture", "name": {"en": "Furniture & mattresses", "te": "ఫర్నిచర్ & పరుపులు",
                                               "hi": "फ़र्नीचर और गद्दे"},
                  "category_tag": "furniture", "parent": "product_base", "categories": _FURNITURE,
                  "attributes": [_attr("material", "Material", "మెటీరియల్", "सामग्री", "choice",
                                       ("Wood", "Engineered wood", "Metal", "Plastic", "Fabric", "Foam", "Coir"),
                                       required=True),
                                 _attr("color", "Colour / finish", "రంగు / ఫినిష్", "रंग / फ़िनिश"),
                                 _attr("dimensions", "Dimensions (L x W x H)", "కొలతలు", "माप", group="Specifications"),
                                 _attr("condition", "Condition", "స్థితి", "स्थिति", "choice", ("New", "Used"), required=True),
                                 _attr("installation", "Assembly", "అసెంబ్లీ", "असेंबली", "choice",
                                       ("Not needed", "Free", "Paid"), group="After sale")]},
    "vehicles_parts": {"key": "vehicles_parts", "name": {"en": "Vehicles & spare parts", "te": "వాహనాలు & స్పేర్ పార్ట్స్",
                                                         "hi": "वाहन और स्पेयर पार्ट्स"},
                       "category_tag": "vehicles", "parent": "product_base", "categories": _VEHICLES,
                       "attributes": [_attr("brand", "Brand", "బ్రాండ్", "ब्रांड", required=True),
                                      _attr("model", "Model", "మోడల్", "मॉडल"),
                                      _attr("condition", "Condition", "స్థితి", "स्थिति", "choice",
                                            ("New", "Used", "Refurbished"), required=True),
                                      _attr("year", "Year", "సంవత్సరం", "वर्ष", "number", group="Specifications",
                                            depends_on=("condition", ("Used", "Refurbished")), minimum=1950, maximum=2100),
                                      _attr("km_driven", "Kilometres driven", "నడిచిన కి.మీ.", "चले किलोमीटर", "number",
                                            unit="km", group="Specifications", depends_on=("condition", ("Used",)),
                                            minimum=0),
                                      _attr("fuel", "Fuel", "ఇంధనం", "ईंधन", "choice",
                                            ("Petrol", "Diesel", "CNG", "Electric", "Not applicable"),
                                            group="Specifications"),
                                      _attr("owners", "Owners", "యజమానులు", "मालिक", "number", group="Specifications",
                                            depends_on=("condition", ("Used",)), minimum=1, maximum=10),
                                      _attr("compatible_with", "Fits vehicles", "సరిపోయే వాహనాలు", "किन वाहनों में",
                                            group="Specifications")]},
    "jewellery_beauty": {"key": "jewellery_beauty", "name": {"en": "Jewellery & beauty", "te": "ఆభరణాలు & బ్యూటీ",
                                                             "hi": "आभूषण और ब्यूटी"},
                         "category_tag": "jewellery_beauty", "parent": "product_base", "categories": _JEWELLERY_BEAUTY,
                         "attributes": [_attr("metal", "Metal", "లోహం", "धातु", "choice",
                                              ("Gold", "Silver", "Imitation", "Not applicable"), required=True),
                                        _attr("purity", "Purity", "స్వచ్ఛత", "शुद्धता", "choice",
                                              ("22K", "18K", "925 silver"), depends_on=("metal", ("Gold", "Silver"))),
                                        _attr("weight_g", "Weight", "బరువు", "वज़न", "number", unit="g",
                                              depends_on=("metal", ("Gold", "Silver")), minimum=0),
                                        _attr("hallmark", "Hallmark / certificate", "హాల్‌మార్క్ / సర్టిఫికెట్",
                                              "हॉलमार्क / प्रमाणपत्र", depends_on=("metal", ("Gold", "Silver"))),
                                        _attr("brand", "Brand", "బ్రాండ్", "ब्रांड"),
                                        _attr("skin_type", "Suits skin / hair", "చర్మం / జుట్టుకు", "त्वचा / बाल",
                                              "choice", ("All", "Dry", "Oily", "Sensitive"), multi=True),
                                        _attr("expiry", "Best before / expiry", "ఎక్స్‌పైరీ", "समाप्ति",
                                              depends_on=("metal", ("Not applicable",)))]},
    "agriculture": {"key": "agriculture", "name": {"en": "Agriculture & farm", "te": "వ్యవసాయం", "hi": "कृषि"},
                    "category_tag": "agriculture", "parent": "product_base", "categories": _AGRICULTURE,
                    "attributes": [_attr("variety", "Variety / grade", "రకం / గ్రేడ్", "किस्म / ग्रेड", required=True),
                                   _attr("moisture", "Moisture", "తేమ", "नमी", "number", unit="%",
                                         group="Specifications", minimum=0, maximum=100),
                                   _attr("organic", "Organic", "సేంద్రియ", "जैविक", "choice", ("Yes", "No")),
                                   _attr("harvest", "Harvest month", "పంట నెల", "कटाई का महीना"),
                                   _attr("license", "Dealer licence no. (seeds / fertiliser)", "డీలర్ లైసెన్స్ నం.",
                                         "डीलर लाइसेंस नं.", group="Compliance", filterable=False)]},
    "property_rentals": {"key": "property_rentals", "name": {"en": "Property & rentals", "te": "ఆస్తి & అద్దెలు",
                                                             "hi": "संपत्ति और किराया"},
                         "category_tag": "property", "parent": "product_base", "categories": _PROPERTY,
                         "attributes": [_attr("area_sqft", "Area", "విస్తీర్ణం", "क्षेत्रफल", "number", unit="sq ft",
                                              required=True, minimum=1),
                                        _attr("furnishing", "Furnishing", "ఫర్నిషింగ్", "फ़र्निशिंग", "choice",
                                              ("Unfurnished", "Semi-furnished", "Furnished")),
                                        _attr("facing", "Facing", "దిశ", "दिशा", "choice", ("East", "West", "North", "South")),
                                        _attr("parking", "Parking", "పార్కింగ్", "पार्किंग", "choice", ("None", "Bike", "Car")),
                                        _attr("deposit", "Deposit", "డిపాజిట్", "जमा राशि", "number", unit="₹",
                                              minimum=0),
                                        _attr("tenants", "Preferred tenants", "కోరుకునే అద్దెదారులు", "पसंदीदा किरायेदार",
                                              "choice", ("Family", "Bachelors", "Anyone"), multi=True),
                                        _attr("approval", "Approval / documents", "అనుమతి / పత్రాలు", "स्वीकृति / दस्तावेज़",
                                              group="Compliance", filterable=False)]}
}


# Staff-editable copy (Command Center resource ``catalog_templates``): a row
# with the same key REPLACES the code default; DISABLED hides it; new keys add
# new business types without any app change. Set by routes/platform.py.
_SOURCE: Optional[Callable[[], list]] = None


def set_source(reader: Optional[Callable[[], list]]) -> None:
    global _SOURCE
    _SOURCE = reader


def _as_list(value: Any) -> List[Dict[str, Any]]:
    """Stored as an object keyed by each entry's own key (the Command Center
    JSON field); code defaults are lists. Order is kept either way."""
    if isinstance(value, dict):
        return [{"key": k, **v} if isinstance(v, dict) and "key" not in v else v
                for k, v in value.items() if isinstance(v, dict)]
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


def _keyed(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    return {str(e["key"]): e for e in entries if isinstance(e, dict) and e.get("key")}


def _registry() -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {k: v for k, v in TEMPLATES.items()}
    rows: list = []
    if _SOURCE is not None:
        try:
            rows = list(_SOURCE() or [])
        except Exception:
            rows = []
    for row in rows:
        data = row.get("data") or {}
        key = str(data.get("key") or "").strip().casefold()
        if not key:
            continue
        if row.get("archived") or str(row.get("status") or "ACTIVE").upper() != "ACTIVE":
            out.pop(key, None)
            continue
        en = str(data.get("label_en") or key)
        out[key] = {
            "key": key,
            "name": {"en": en, "te": str(data.get("label_te") or en), "hi": str(data.get("label_hi") or en)},
            "category_tag": str(data.get("category_tag") or key),
            "parent": str(data.get("parent") or "").strip().casefold() or None,
            "abstract": bool(data.get("abstract")),
            "categories": _as_list(data.get("categories")),
            "attributes": _as_list(data.get("attributes")),
        }
    return out


def _inherited(key: str, reg: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Parent attributes first, then the template's own; a child overrides a
    parent attribute with the same key (unlimited depth, cycle-safe)."""
    chain: List[Dict[str, Any]] = []
    seen: set = set()
    node = reg.get(key)
    while node and node["key"] not in seen:
        seen.add(node["key"])
        chain.append(node)
        node = reg.get(node.get("parent") or "")
    merged: Dict[str, Dict[str, Any]] = {}
    for node in reversed(chain):
        for spec in node.get("attributes") or []:
            if isinstance(spec, dict) and spec.get("key"):
                merged.pop(spec["key"], None)  # keep the child's position
                merged[spec["key"]] = spec
    return list(merged.values())


def _count(template: Dict[str, Any]) -> int:
    return sum(len(c["items"]) for c in template["categories"])


def summaries() -> List[Dict[str, Any]]:
    return [
        {"key": t["key"], "name": t["name"], "categories": len(t["categories"]), "items": _count(t),
         "attributes": len(_inherited(t["key"], reg))}
        for reg in [_registry()] for t in reg.values() if not t.get("abstract")
    ]


def template(key: str) -> Optional[Dict[str, Any]]:
    reg = _registry()
    found = reg.get(str(key or "").strip().casefold())
    if not found or found.get("abstract"):
        return None
    return {**found, "items": _count(found), "attributes": _inherited(found["key"], reg)}


def attributes(template_key: str) -> List[Dict[str, Any]]:
    return _inherited(str(template_key or "").strip().casefold(), _registry())


def _values(raw: Any) -> List[str]:
    items = raw if isinstance(raw, (list, tuple)) else str(raw or "").split(",")
    return [str(v).strip()[:80] for v in items if str(v).strip()]


def clean_attributes(template_key: str, values: Dict[str, Any] | None) -> tuple[Dict[str, str], List[str]]:
    """Only this template's (inherited) attribute keys; choices from their
    options (several when multi); numbers within their range; a dependent
    attribute only when its condition holds. Returns (kept values, missing
    REQUIRED keys whose condition holds)."""
    specs = attributes(template_key)
    kept: Dict[str, str] = {}
    missing: List[str] = []
    for spec in specs:
        dep = spec.get("depends_on") or {}
        if dep and kept.get(dep.get("key")) not in (dep.get("values") or []):
            continue  # not applicable for this item
        raw = (values or {}).get(spec["key"])
        kind, options = spec.get("kind"), spec.get("options") or []
        value = ""
        if kind == "choice":
            chosen = [v for v in _values(raw) if not options or v in options]
            value = ", ".join(chosen if spec.get("multi") else chosen[:1])
        elif kind == "number":
            try:
                number = float(str(raw).replace(",", "").strip())
            except (TypeError, ValueError):
                number = None
            if number is not None and not (("min" in spec and number < spec["min"]) or
                                           ("max" in spec and number > spec["max"])):
                value = f"{number:g}"
        else:
            value = str(raw or "").strip()[:80]
        if value:
            kept[spec["key"]] = value
        elif spec.get("required"):
            missing.append(spec["key"])
    return kept, missing


def attribute_summary(template_key: str, kept: Dict[str, str]) -> str:
    specs = {a["key"]: a for a in attributes(template_key)}

    def show(k: str, v: str) -> str:
        spec = specs.get(k) or {}
        unit = spec.get("unit")
        return f"{(spec.get('label') or {}).get('en', k)}: {v}{' ' + unit if unit and unit != '₹' else ''}"
    return " · ".join(show(k, v) for k, v in kept.items())


def filterable(template_key: str) -> List[Dict[str, Any]]:
    return [a for a in attributes(template_key) if a.get("filterable")]


def item(template_key: str, item_key: str) -> Optional[Dict[str, Any]]:
    found = _registry().get(template_key)
    if not found:
        return None
    for category in found["categories"]:
        for entry in category.get("items") or []:
            if entry.get("key") == item_key:
                return {**entry, "category": category.get("key"), "category_name": category.get("name")}
    return None


def seed_defaults(resources: Any) -> int:
    """Copy the code templates into the Command Center store once (never over
    staff edits) so every template is editable there."""
    if resources.repo.list("catalog_templates", include_archived=True):
        return 0
    for t in TEMPLATES.values():
        resources.create("catalog_templates", {
            "key": t["key"], "label_en": t["name"]["en"], "label_te": t["name"].get("te"),
            "label_hi": t["name"].get("hi"), "parent": t.get("parent") or "", "category_tag": t["category_tag"],
            "abstract": bool(t.get("abstract")), "attributes": _keyed(t.get("attributes") or []),
            "categories": _keyed(t.get("categories") or []),
        }, actor="system:seed", status="ACTIVE")
    return len(TEMPLATES)
