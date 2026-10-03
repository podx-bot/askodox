"""Editable starting configuration for the Universal Advisor.

Seeded ONCE into the Command Center (``advisor_categories`` and
``advisor_questions``); from then on the stored records are the source of
truth and staff change them without a release.

A category is matched from the AI-detected category first, then from the
HEAD noun of what the person asked for ("car phone holder" -> holder ->
accessories, not cars), then from any alias. Its ``decision_fields`` say
which details change the decision there, and whether each must be known
before final recommendations ("required") -- so "budget" is required for a
TV or a flat, optional for a phone holder, and never asked for a doctor.
"""
from __future__ import annotations

from typing import Any, Dict, List


def _f(field: str, required: bool = False, priority: int = 500) -> Dict[str, Any]:
    return {"field": field, "required": required, "priority": priority}


# key, label, aliases (AI category names + head nouns, any language), fields
DEFAULT_CATEGORIES: List[Dict[str, Any]] = [
    {"key": "phones", "label": "Mobile phones", "group": "ecommerce",
     "aliases": ["phone", "phones", "mobile", "mobiles", "smartphone", "smartphones", "iphone", "mobile phone",
                 "mobile phones", "ఫోన్", "మొబైల్", "फोन", "मोबाइल"],
     "decision_fields": [_f("budget", True, 900), _f("usage", False, 700), _f("brand", False, 600)]},
    {"key": "tv", "label": "Televisions", "group": "ecommerce",
     "aliases": ["tv", "tvs", "television", "televisions", "smart tv", "led tv", "టీవీ", "टीवी"],
     "decision_fields": [_f("budget", True, 900), _f("size", False, 800)]},
    {"key": "computers", "label": "Laptops & computers", "group": "ecommerce",
     "aliases": ["laptop", "laptops", "computer", "computers", "pc", "desktop", "macbook", "ల్యాప్‌టాప్", "लैपटॉप"],
     "decision_fields": [_f("budget", True, 900), _f("usage", False, 800)]},
    {"key": "appliances", "label": "Home appliances", "group": "ecommerce",
     "aliases": ["appliance", "appliances", "home appliances", "washing machine", "fridge", "refrigerator", "ac",
                 "air conditioner", "cooler", "microwave", "geyser", "water heater", "chimney", "mixer", "grinder",
                 "mixer grinder", "inverter", "water purifier", "ro", "vacuum cleaner", "ఫ్రిజ్", "ఏసీ", "फ्रिज"],
     "decision_fields": [_f("budget", True, 900), _f("capacity", False, 700)]},
    {"key": "footwear", "label": "Footwear", "group": "ecommerce",
     "aliases": ["footwear", "shoe", "shoes", "sneaker", "sneakers", "sandal", "sandals", "slipper", "slippers",
                 "chappal", "chappals", "boots", "heels", "షూస్", "చెప్పులు", "जूते", "चप्पल"],
     "decision_fields": [_f("budget", True, 900), _f("usage", False, 800), _f("size", False, 700)]},
    {"key": "fashion", "label": "Clothing & fashion", "group": "ecommerce",
     "aliases": ["fashion", "clothing", "clothes", "apparel", "dress", "dresses", "saree", "sarees", "kurti", "kurtis",
                 "kurta", "shirt", "shirts", "t-shirt", "tshirt", "jeans", "trousers", "lehenga", "top", "tops",
                 "చీర", "డ్రెస్", "साड़ी", "कपड़े"],
     "decision_fields": [_f("budget", True, 850), _f("size", False, 700), _f("usage", False, 600)]},
    {"key": "furniture", "label": "Furniture", "group": "ecommerce",
     "aliases": ["furniture", "sofa", "sofas", "bed", "beds", "mattress", "mattresses", "table", "tables", "chair",
                 "chairs", "wardrobe", "almirah", "dining table", "సోఫా", "सोफा"],
     "decision_fields": [_f("budget", True, 900), _f("size", False, 700), _f("material", False, 600)]},
    {"key": "accessories", "label": "Accessories & small items", "group": "ecommerce",
     "aliases": ["accessory", "accessories", "holder", "హోల్డర్", "case", "cover", "కవర్", "charger", "cable", "stand", "mount",
                 "screen guard", "tempered glass", "earphones", "earbuds", "headphones", "power bank", "keychain",
                 "bag", "bags", "wallet", "watch strap"],
     "decision_fields": [_f("budget", False, 500), _f("model", False, 600)]},
    {"key": "beauty", "label": "Beauty & personal care", "group": "ecommerce",
     "aliases": ["beauty", "cosmetics", "skincare", "skin care", "personal care", "sunscreen", "cream", "serum",
                 "face wash", "shampoo", "lipstick", "perfume", "moisturizer", "makeup"],
     "decision_fields": [_f("usage", False, 700), _f("budget", False, 600)]},
    {"key": "kitchen_home", "label": "Kitchen & home", "group": "ecommerce",
     "aliases": ["kitchen", "cookware", "utensils", "tawa", "pan", "pressure cooker", "cooker", "bottle", "home decor",
                 "decor", "bedsheet", "curtains", "storage"],
     "decision_fields": [_f("budget", False, 600), _f("size", False, 500)]},
    {"key": "automobile", "label": "Cars & bikes", "group": "automobile",
     "aliases": ["car", "cars", "bike", "bikes", "scooter", "scooty", "motorcycle", "vehicle", "vehicles", "suv",
                 "automobile", "కారు", "బైక్", "कार", "बाइक"],
     "decision_fields": [_f("budget", True, 900), _f("condition", True, 850), _f("model", False, 600)]},
    {"key": "grocery", "label": "Grocery", "group": "grocery_food",
     "aliases": ["grocery", "groceries", "kirana", "rice", "dal", "oil", "atta", "vegetables", "fruits", "milk",
                 "sugar", "spices", "కిరాణా", "కూరగాయలు", "किराना"],
     "decision_fields": [_f("quantity", True, 800), _f("timing", False, 500)]},
    {"key": "food", "label": "Food & restaurants", "group": "grocery_food",
     "aliases": ["food", "restaurant", "restaurants", "biryani", "pizza", "meals", "tiffin", "dinner", "lunch",
                 "breakfast", "chicken", "mutton", "fish", "prawns", "catering", "బిర్యానీ", "చికెన్", "खाना"],
     "decision_fields": [_f("quantity", False, 700), _f("timing", False, 600)]},
    {"key": "hotel", "label": "Hotels & stays", "group": "travel",
     "aliases": ["hotel", "hotels", "room", "rooms", "stay", "resort", "lodge", "homestay", "హోటల్", "होटल"],
     "decision_fields": [_f("travel_dates", True, 900), _f("guests", True, 850), _f("budget", False, 700)]},
    {"key": "travel", "label": "Bus, train & flights", "group": "travel",
     "aliases": ["bus", "buses", "flight", "flights", "train", "trains", "ticket", "tickets", "travel", "trip",
                 "cab", "taxi", "బస్", "ఫ్లైట్", "टिकट"],
     "decision_fields": [_f("travel_dates", True, 900), _f("guests", False, 700)]},
    {"key": "insurance", "label": "Insurance", "group": "finance", "high_stakes": True,
     "aliases": ["insurance", "health insurance", "term insurance", "life insurance", "car insurance", "policy",
                 "బీమా", "बीमा"],
     "decision_fields": [_f("coverage", True, 900), _f("guests", False, 700)]},
    {"key": "loans", "label": "Loans & credit cards", "group": "finance", "high_stakes": True,
     "aliases": ["loan", "loans", "personal loan", "home loan", "car loan", "gold loan", "credit card", "credit cards",
                 "లోన్", "రుణం", "लोन", "क्रेडिट कार्ड"],
     "broad_aliases": ["loan", "loans", "credit card", "credit cards", "లోన్", "రుణం", "लोन", "क्रेडिट कार्ड"],
     "decision_fields": [_f("goal", True, 900), _f("income", False, 700)]},
    {"key": "investment", "label": "Investments", "group": "finance", "high_stakes": True,
     "aliases": ["investment", "investments", "invest", "mutual fund", "mutual funds", "sip", "fixed deposit", "fd",
                 "stocks", "shares", "gold", "పెట్టుబడి", "निवेश"],
     "broad_aliases": ["investment", "investments", "invest", "పెట్టుబడి", "निवेश"],
     "decision_fields": [_f("goal", True, 900), _f("duration", False, 700)]},
    {"key": "healthcare", "label": "Doctors & clinics", "group": "health", "high_stakes": True,
     "aliases": ["doctor", "doctors", "hospital", "hospitals", "clinic", "clinics", "dentist", "physiotherapy",
                 "physiotherapist", "specialist", "డాక్టర్", "ఆసుపత్రి", "डॉक्टर", "अस्पताल"],
     "broad_aliases": ["doctor", "doctors", "hospital", "hospitals", "clinic", "clinics", "specialist", "డాక్టర్", "ఆసుపత్రి", "डॉक्टर", "अस्पताल"],
     "decision_fields": [_f("requirement", True, 900), _f("timing", False, 700)]},
    {"key": "pharmacy", "label": "Pharmacy", "group": "health", "high_stakes": True,
     "aliases": ["pharmacy", "medicine", "medicines", "medical store", "syrup", "capsules", "మందులు", "दवा"],
     "decision_fields": [_f("quantity", False, 600)]},
    {"key": "diagnostics", "label": "Diagnostics & lab tests", "group": "health", "high_stakes": True,
     "aliases": ["blood test", "lab test", "diagnostics", "scan", "x-ray", "xray", "mri", "ct scan", "ultrasound",
                 "health checkup", "టెస్ట్", "जांच"],
     "broad_aliases": ["diagnostics", "lab test", "scan", "health checkup", "టెస్ట్", "जांच"],
     "decision_fields": [_f("requirement", True, 850), _f("timing", False, 700)]},
    {"key": "education", "label": "Education & courses", "group": "education",
     "aliases": ["course", "courses", "coaching", "tuition", "tuitions", "class", "classes", "training", "school",
                 "college", "exam preparation", "కోర్సు", "ట్యూషన్", "कोचिंग"],
     "broad_aliases": ["course", "courses", "coaching", "tuition", "tuitions", "class", "classes", "training", "కోర్సు", "ట్యూషన్", "कोचिंग"],
     "decision_fields": [_f("goal", True, 850), _f("timing", False, 600), _f("budget", False, 500)]},
    {"key": "jobs", "label": "Jobs", "group": "jobs",
     "aliases": ["job", "jobs", "vacancy", "vacancies", "hiring", "opening", "openings", "ఉద్యోగం", "नौकरी"],
     "decision_fields": [_f("experience", True, 800)]},
    {"key": "real_estate", "label": "Real estate", "group": "real_estate",
     "aliases": ["flat", "flats", "house", "houses", "plot", "plots", "apartment", "apartments", "villa", "land",
                 "property", "rent", "rental", "bhk", "ఇల్లు", "ఫ్లాట్", "मकान"],
     "broad_aliases": ["property", "rent", "rental", "ఇల్లు", "मकान"],
     "decision_fields": [_f("property_type", True, 900), _f("budget", True, 880)]},
    {"key": "home_services", "label": "Home services & repairs", "group": "home_services",
     "aliases": ["plumber", "electrician", "carpenter", "painter", "painting", "cleaning", "pest control", "repair",
                 "repairs", "installation", "service", "servicing", "maid", "cook", "ప్లంబర్", "రిపేర్", "मरम्मत"],
     "broad_aliases": ["repair", "repairs", "service", "servicing", "installation", "రిపేర్", "मरम्मत"],
     "decision_fields": [_f("timing", True, 850), _f("requirement", False, 700)]},
    {"key": "logistics", "label": "Parcel, delivery & movers", "group": "logistics",
     "aliases": ["parcel", "courier", "delivery", "shifting", "movers", "packers", "transport", "truck", "pickup",
                 "పార్సెల్", "कूरियर"],
     "decision_fields": [_f("timing", True, 850), _f("quantity", False, 700)]},
    {"key": "used", "label": "Used & second-hand", "group": "used",
     "aliases": ["used", "second hand", "second-hand", "pre-owned", "refurbished"],
     "decision_fields": [_f("budget", True, 900), _f("condition", False, 600)]},
    {"key": "b2b", "label": "Wholesale & B2B", "group": "b2b",
     "aliases": ["wholesale", "bulk", "manufacturer", "manufacturers", "supplier", "suppliers", "distributor",
                 "dealer", "dealership", "b2b", "హోల్‌సేల్", "थोक"],
     "decision_fields": [_f("quantity", True, 900), _f("budget", False, 700), _f("timing", False, 600)]},
    {"key": "entertainment", "label": "Events & entertainment", "group": "entertainment",
     "aliases": ["movie", "movies", "movie ticket", "movie tickets", "concert tickets", "show tickets", "concert", "event", "events", "show", "party hall", "function hall", "game",
                 "సినిమా", "फिल्म"],
     "decision_fields": [_f("timing", True, 850), _f("guests", False, 700)]},
    {"key": "saas", "label": "Software & SaaS", "group": "saas",
     "aliases": ["software", "saas", "crm", "erp", "app", "website", "billing software", "accounting software",
                 "pos", "hosting"],
     "broad_aliases": ["software", "saas", "app", "website"],
     "decision_fields": [_f("goal", True, 850), _f("guests", False, 600), _f("budget", False, 500)]},
]

ADVISOR_FIELD_KEYS = ("budget", "brand", "usage", "size", "quantity", "condition", "model", "variant", "timing",
                      "location", "quality", "material", "capacity", "duration", "guests", "travel_dates",
                      "experience", "property_type", "income", "coverage", "requirement", "goal")

# One generic question per field (category "any"); categories may override
# the wording with their own record (same field, category = key).
DEFAULT_FIELD_QUESTIONS: List[Dict[str, Any]] = [
    {"field": "budget", "answer_type": "money", "question_en": "What budget do you have in mind?",
     "question_te": "మీ బడ్జెట్ ఎంత అనుకుంటున్నారు?", "question_hi": "आपका बजट कितना है?",
     "why": "Budget changes which options are worth showing first."},
    {"field": "usage", "answer_type": "text", "question_en": "What will you mainly use it for?",
     "question_te": "దీన్ని ముఖ్యంగా దేనికి వాడతారు?", "question_hi": "इसे मुख्य रूप से किसके लिए इस्तेमाल करेंगे?",
     "why": "The use decides which features matter."},
    {"field": "brand", "answer_type": "text", "question_en": "Any brand you prefer?",
     "question_te": "ఏదైనా బ్రాండ్ ఇష్టమా?", "question_hi": "कोई पसंदीदा ब्रांड?", "why": ""},
    {"field": "size", "answer_type": "text", "question_en": "Which size do you need?",
     "question_te": "ఏ సైజు కావాలి?", "question_hi": "कौन सा साइज़ चाहिए?", "why": ""},
    {"field": "quantity", "answer_type": "text", "question_en": "How much / how many do you need?",
     "question_te": "ఎంత / ఎన్ని కావాలి?", "question_hi": "कितना / कितने चाहिए?", "why": "Quantity decides price and who can supply."},
    {"field": "condition", "answer_type": "choice", "question_en": "New or used?", "question_te": "కొత్తదా లేక వాడినదా?",
     "question_hi": "नया या पुराना?", "choices": ["New", "Used"],
     "why": "Used items need inspection, papers and history."},
    {"field": "model", "answer_type": "text", "question_en": "Which model is it for?",
     "question_te": "ఏ మోడల్ కోసం?", "question_hi": "किस मॉडल के लिए?", "why": "Fit depends on the model."},
    {"field": "timing", "answer_type": "text", "question_en": "When do you need it -- today, tomorrow or later?",
     "question_te": "ఎప్పుడు కావాలి -- ఈరోజు, రేపు లేదా తర్వాత?", "question_hi": "कब चाहिए -- आज, कल या बाद में?",
     "choices": ["Today", "Tomorrow", "This week"], "why": "Urgency decides who is available."},
    {"field": "capacity", "answer_type": "text", "question_en": "What capacity or size suits your home?",
     "question_te": "మీ ఇంటికి ఎంత కెపాసిటీ సరిపోతుంది?", "question_hi": "आपके घर के लिए कितनी क्षमता?", "why": ""},
    {"field": "material", "answer_type": "text", "question_en": "Any material you prefer?",
     "question_te": "ఏ మెటీరియల్ ఇష్టం?", "question_hi": "कौन सा मटीरियल पसंद है?", "why": ""},
    {"field": "travel_dates", "answer_type": "date", "question_en": "For which dates?", "question_te": "ఏ తేదీలకు?",
     "question_hi": "किन तारीखों के लिए?", "why": "Availability and price depend on the dates."},
    {"field": "guests", "answer_type": "number", "question_en": "For how many people?", "question_te": "ఎంతమందికి?",
     "question_hi": "कितने लोगों के लिए?", "why": ""},
    {"field": "coverage", "answer_type": "text", "question_en": "What should it cover, and for whom?",
     "question_te": "ఏ కవరేజ్ కావాలి, ఎవరికి?", "question_hi": "किसका कवर चाहिए और किसके लिए?",
     "why": "Coverage and members decide which plans are comparable."},
    {"field": "goal", "answer_type": "text", "question_en": "What is the main goal you want this for?",
     "question_te": "దీని ముఖ్య ఉద్దేశం ఏమిటి?", "question_hi": "इसका मुख्य उद्देश्य क्या है?",
     "why": "The goal decides which options are even suitable."},
    {"field": "income", "answer_type": "text",
     "question_en": "Roughly what monthly income range should I consider? (Only a range -- no documents.)",
     "question_te": "నెలవారీ ఆదాయం సుమారుగా ఏ పరిధిలో ఉంది? (పరిధి మాత్రమే, పత్రాలు వద్దు.)",
     "question_hi": "मासिक आय लगभग किस सीमा में है? (सिर्फ़ सीमा, कोई दस्तावेज़ नहीं।)",
     "why": "Eligibility depends on it; ASKODOX never asks for PAN/Aadhaar here."},
    {"field": "duration", "answer_type": "text", "question_en": "For how long do you plan to keep it?",
     "question_te": "ఎంత కాలం కోసం?", "question_hi": "कितने समय के लिए?", "why": ""},
    {"field": "requirement", "answer_type": "text", "question_en": "What exactly do you need help with?",
     "question_te": "సరిగ్గా దేనికి సహాయం కావాలి?", "question_hi": "ठीक-ठीक किस चीज़ में मदद चाहिए?",
     "why": "It decides which specialist or service fits."},
    {"field": "experience", "answer_type": "text", "question_en": "How much experience do you have?",
     "question_te": "మీకు ఎంత అనుభవం ఉంది?", "question_hi": "आपके पास कितना अनुभव है?", "why": ""},
    {"field": "property_type", "answer_type": "choice", "question_en": "Buy or rent -- and what type (flat, house, plot)?",
     "question_te": "కొనడమా లేక అద్దెకా -- ఏ రకం (ఫ్లాట్, ఇల్లు, ప్లాట్)?",
     "question_hi": "खरीदना या किराए पर -- कौन सा प्रकार (फ्लैट, मकान, प्लॉट)?", "why": ""},
    {"field": "quality", "answer_type": "text", "question_en": "Any quality or grade you prefer?",
     "question_te": "ఏ క్వాలిటీ కావాలి?", "question_hi": "कौन सी क्वालिटी चाहिए?", "why": ""},
]

# Category-specific wording (same field).
DEFAULT_CATEGORY_QUESTIONS: List[Dict[str, Any]] = [
    {"category": "footwear", "field": "usage", "answer_type": "choice",
     "question_en": "What will you mostly use them for -- running, standing all day, office or casual?",
     "question_te": "వీటిని ఎక్కువగా దేనికి వాడతారు -- పరుగు, రోజంతా నిలబడటం, ఆఫీస్ లేదా క్యాజువల్?",
     "question_hi": "इन्हें ज़्यादातर किसके लिए पहनेंगे -- दौड़, पूरे दिन खड़े रहना, ऑफिस या कैज़ुअल?",
     "choices": ["Running", "Standing all day", "Office", "Casual"],
     "why": "Comfort, cushioning and grip matter more for long standing; weight for running."},
    {"category": "tv", "field": "size", "answer_type": "choice", "question_en": "Which screen size suits your room?",
     "question_te": "మీ గదికి ఏ స్క్రీన్ సైజు సరిపోతుంది?", "question_hi": "आपके कमरे के लिए कौन सा स्क्रीन साइज़?",
     "choices": ["32 inch", "43 inch", "55 inch"], "why": "Viewing distance decides the useful size."},
    {"category": "real_estate", "field": "budget", "answer_type": "money",
     "question_en": "What budget (or monthly rent) are you looking at?", "question_te": "మీ బడ్జెట్ (లేదా నెల అద్దె) ఎంత?",
     "question_hi": "बजट (या मासिक किराया) कितना है?", "why": "Budget and locality decide which listings are realistic."},
    {"category": "loans", "field": "goal", "answer_type": "text",
     "question_en": "What is the loan or card for, and roughly how much?", "question_te": "లోన్ / కార్డ్ దేనికి, సుమారుగా ఎంత?",
     "question_hi": "लोन / कार्ड किसलिए और लगभग कितना?", "why": "Purpose and amount decide comparable offers."},
    {"category": "healthcare", "field": "requirement", "answer_type": "text",
     "question_en": "Which kind of doctor or care do you need? (In an emergency call 108.)",
     "question_te": "ఏ రకమైన డాక్టర్ / వైద్యం కావాలి? (అత్యవసరమైతే 108కి కాల్ చేయండి.)",
     "question_hi": "किस तरह के डॉक्टर / इलाज की ज़रूरत है? (आपात स्थिति में 108 पर कॉल करें।)",
     "why": "It decides which specialist fits; ASKODOX does not diagnose."},
    {"category": "saas", "field": "guests", "answer_type": "number", "question_en": "How many people will use it?",
     "question_te": "ఎంతమంది వాడతారు?", "question_hi": "कितने लोग इस्तेमाल करेंगे?",
     "why": "Plans are priced per user or team size."},
    {"category": "automobile", "field": "condition", "answer_type": "choice", "question_en": "New or used?",
     "question_te": "కొత్తదా లేక వాడినదా?", "question_hi": "नई या पुरानी?", "choices": ["New", "Used"],
     "why": "Used vehicles need inspection, papers and service history."},
]


HIGH_STAKES_NOTE = {
    "en": "ASKODOX helps you find and compare options; it gives no guarantee of approval, eligibility, outcome or "
          "returns. Please confirm with a qualified professional or the provider before deciding.",
    "te": "ASKODOX ఎంపికలను కనుగొని పోల్చడంలో సహాయపడుతుంది; ఆమోదం, అర్హత, ఫలితం లేదా రాబడికి హామీ ఇవ్వదు. నిర్ణయించే "
          "ముందు అర్హత గల నిపుణుడిని లేదా ప్రొవైడర్‌ను సంప్రదించండి.",
    "hi": "ASKODOX विकल्प खोजने और तुलना करने में मदद करता है; मंज़ूरी, पात्रता, परिणाम या रिटर्न की कोई गारंटी नहीं। "
          "फ़ैसले से पहले किसी योग्य विशेषज्ञ या प्रदाता से पुष्टि करें।",
}


def category_records() -> List[Dict[str, Any]]:
    """DEFAULT_CATEGORIES in the stored shape (required / optional field lists, in priority order)."""
    out = []
    for index, cat in enumerate(DEFAULT_CATEGORIES):
        fields = sorted(cat["decision_fields"], key=lambda f: -int(f["priority"]))
        out.append({
            "key": cat["key"], "label": cat["label"], "group": cat.get("group", ""), "aliases": list(cat["aliases"]),
            "broad_aliases": list(cat.get("broad_aliases") or []),
            "required_fields": [f["field"] for f in fields if f["required"]],
            "optional_fields": [f["field"] for f in fields if not f["required"]],
            "high_stakes": bool(cat.get("high_stakes")), "priority": 500,
        })
    return out


def question_records() -> List[Dict[str, Any]]:
    """Generic per-field questions (category 'any') + category wording."""
    rows = [{"category": "any", "keywords": [], "required": False, "priority": 500, "choices": [], **q}
            for q in DEFAULT_FIELD_QUESTIONS]
    rows += [{"keywords": [], "required": False, "priority": 600, "choices": [], **q} for q in DEFAULT_CATEGORY_QUESTIONS]
    return rows
