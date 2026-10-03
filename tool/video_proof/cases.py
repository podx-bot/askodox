"""The real-content video proof: one search per kind of need, in English and
Telugu. Subjects are what the app's assistant extracts from the message."""

# (label, language, what the customer types, extracted subject, category, intent, next step to follow)
CASES = [
    ("electronics", "en", "Samsung 43 inch TV review videos", "samsung 43 inch tv", "product", "buy", "find_local"),
    ("electronics-te", "te", "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో", "samsung 43 inch tv", "product", "buy", "deals"),
    ("phone", "en", "Redmi Note 13 Pro review video", "redmi note 13 pro", "product", "buy", "deals"),
    ("vehicle", "en", "Tata Nexon review video", "tata nexon", "product", "buy", "find_local"),
    ("service", "en", "AC service video", "ac service", "service", "service", "local_service"),
    ("home-service", "en", "kitchen sink plumbing repair video", "plumbing repair", "service", "service", "local_service"),
    ("food", "en", "Hyderabadi biryani review video", "hyderabadi biryani", "product", "buy", "find_local"),
    ("travel", "en", "Araku valley trip review video", "araku valley trip", "product", "buy", "reviews"),
    ("used-item", "en", "used Royal Enfield Classic 350 review video", "used royal enfield classic 350", "product", "buy", "find_local"),
    ("deal", "en", "iPhone 15 offer review video", "iphone 15", "product", "buy", "deals"),
    ("service-te", "te", "ఏసీ సర్వీస్ వీడియో", "ac service", "service", "service", "local_service"),
]

PRODUCTION = "https://podx-ai-connect-production-3279.up.railway.app"
LOCATION = {"label": "Vijayawada", "latitude": 16.5062, "longitude": 80.648, "radius_km": 10}


def discover_body(text: str, subject: str, category: str, intent: str, language: str) -> dict:
    return {"user_id": "", "raw_text": text, "intent": intent, "subject": subject, "category": category,
            "quantity": None, "unit": None, "price": None, "location": LOCATION, "dynamic_fields": {},
            "trace": {"language": language, "source": "video-real-content-proof"}}
