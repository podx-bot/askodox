"""Universal category hierarchy: domain -> category -> subcategory -> deeper,
each node with aliases (any language), attributes and CAPABILITIES (the
actions ASKODOX may offer). A child inherits its parent's capabilities and
attributes and may add or remove some; ``mobility_kind`` / ``advisor_category``
are inherited from the nearest ancestor that sets them.

Nodes live in the Command Center resource ``taxonomy_nodes`` (staff add or
change categories without code); ``DEFAULT_NODES`` seeds an empty store once.
Resolution is pure text matching (no model call): the deepest node whose alias
appears in the user's words wins, and "I can deliver / I want to work as ..."
turns the same node into a provider action.
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional

CAPABILITIES = ("search", "compare", "request", "order", "book", "quote", "pre_order", "request_delivery",
                "request_ride", "carpool", "join_as_partner", "list_item", "apply_job", "post_job", "upload_video",
                "ask_video", "advice", "contact_after_accept")

# (key, parent, label, aliases, capabilities, extra)
_D = [
    # domains
    ("product", None, "Products", ["buy", "product", "కొనాలి", "खरीद"], ["search", "compare", "order", "pre_order",
                                                                         "list_item", "upload_video", "ask_video"], {}),
    ("service", None, "Services", ["service", "repair", "సర్వీస్"], ["search", "compare", "book", "quote",
                                                                      "upload_video", "ask_video"], {}),
    ("food", None, "Food & restaurants", ["food", "restaurant", "biryani", "meals", "tiffin", "ఫుడ్", "భోజనం"],
     ["search", "order", "request_delivery"], {"mobility_kind": "food", "advisor_category": "food"}),
    ("grocery", None, "Grocery", ["grocery", "groceries", "vegetables", "కిరాణా", "కూరగాయలు"],
     ["search", "order", "request_delivery"], {"mobility_kind": "grocery", "advisor_category": "grocery"}),
    ("job", None, "Jobs", ["job", "jobs", "vacancy", "hiring", "ఉద్యోగం"], ["search", "apply_job", "post_job"], {}),
    ("travel", None, "Travel", ["travel", "trip", "tour", "ప్రయాణం"], ["search", "book", "request_ride"], {}),
    ("hotel", "travel", "Hotels & stays", ["hotel", "room", "lodge", "stay", "హోటల్"], ["book", "compare"],
     {"advisor_category": "hotel"}),
    ("insurance", None, "Insurance", ["insurance", "బీమా"], ["compare", "quote", "advice"], {"high_stakes": True}),
    ("loan", None, "Loans", ["loan", "లోన్", "రుణం"], ["compare", "quote", "advice"], {"high_stakes": True}),
    ("credit_card", None, "Credit cards", ["credit card", "క్రెడిట్ కార్డ్"], ["compare", "advice"],
     {"high_stakes": True}),
    ("investment", None, "Investments", ["investment", "mutual fund", "invest"], ["compare", "advice"],
     {"high_stakes": True}),
    ("health", None, "Health", ["doctor", "hospital", "clinic", "dentist", "వైద్యుడు", "డాక్టర్"], ["search", "book",
                                                                                                   "advice"],
     {"high_stakes": True}),
    ("education", None, "Education", ["tuition", "course", "coaching", "school", "college", "ట్యూషన్"],
     ["search", "compare", "book"], {}),
    ("real_estate", None, "Real estate", ["flat", "house", "plot", "rent", "apartment", "ఇల్లు", "అద్దె"],
     ["search", "compare", "list_item", "upload_video"], {}),
    ("used", "product", "Used items", ["used", "second hand", "old", "పాత"], ["search", "list_item"], {}),
    # delivery hierarchy
    ("delivery", None, "Delivery", ["delivery", "deliver", "delivered", "డెలివరీ", "डिलीवरी"],
     ["request_delivery", "join_as_partner", "contact_after_accept"], {"mobility_kind": "local_delivery"}),
    ("food_delivery", "delivery", "Food delivery", ["food delivery", "deliver food", "ఫుడ్ డెలివరీ"],
     ["order"], {"mobility_kind": "food"}),
    ("grocery_delivery", "delivery", "Grocery delivery", ["grocery delivery", "deliver groceries",
                                                          "కిరాణా డెలివరీ"], ["order"], {"mobility_kind": "grocery"}),
    ("parcel", "delivery", "Parcel", ["parcel", "courier", "పార్సెల్", "కొరియర్", "पार्सल"], [],
     {"mobility_kind": "parcel"}),
    ("documents", "parcel", "Documents", ["document", "documents", "papers", "డాక్యుమెంట్"], [],
     {"mobility_kind": "documents"}),
    ("local_delivery", "delivery", "Local delivery", ["local delivery", "లోకల్ డెలివరీ"], [],
     {"mobility_kind": "local_delivery"}),
    ("shop_delivery", "delivery", "Shop / business delivery", ["shop delivery", "business delivery",
                                                               "store delivery", "షాప్ డెలివరీ"], [],
     {"mobility_kind": "product"}),
    ("pickup_drop", "delivery", "Pickup & drop", ["pickup and drop", "pick up and drop", "pickup & drop",
                                                  "పికప్ డ్రాప్"], [], {"mobility_kind": "pickup_drop"}),
    # rides
    ("ride", None, "Rides", ["ride", "taxi", "cab", "రైడ్", "టాక్సీ", "క్యాబ్", "टैक्सी"],
     ["request_ride", "join_as_partner", "contact_after_accept"], {"mobility_kind": "ride_taxi"}),
    ("ride_auto", "ride", "Auto", ["auto", "auto rickshaw", "ఆటో", "ऑटो"], [], {"mobility_kind": "ride_auto"}),
    ("ride_bike", "ride", "Bike taxi", ["bike taxi", "bike ride", "rapido", "బైక్ టాక్సీ"], [],
     {"mobility_kind": "ride_bike"}),
    ("ride_airport", "ride", "Airport", ["airport", "ఎయిర్‌పోర్ట్"], [], {"mobility_kind": "ride_airport"}),
    ("ride_outstation", "ride", "Outstation", ["outstation", "ఔట్‌స్టేషన్"], [],
     {"mobility_kind": "ride_outstation"}),
    ("driver_only", "ride", "Driver only", ["driver only", "acting driver", "driver for my car"], [],
     {"mobility_kind": "driver_only"}),
    ("carpool", "ride", "Carpool", ["carpool", "car pool", "share a ride", "కార్‌పూల్"], ["carpool"],
     {"mobility_kind": "carpool", "removes": ["request_ride"]}),
]

DEFAULT_NODES: List[Dict[str, Any]] = [
    {"key": k, "parent": p, "label": label, "aliases": aliases, "capabilities": caps,
     "attributes": extra.get("attributes", []), "mobility_kind": extra.get("mobility_kind"),
     "advisor_category": extra.get("advisor_category"), "removes": extra.get("removes", []),
     "high_stakes": bool(extra.get("high_stakes"))}
    for k, p, label, aliases, caps, extra in _D
]

# "I can deliver", "I want to work as a driver" -> the provider side of the same node.
_PROVIDER = re.compile(
    r"\b(i can|i will|i'?d like to|i want to|want to|join as|work as|become a|register as)\b.{0,30}"
    r"\b(deliver|delivery|drive|driver|partner|rider|courier)\b"
    r"|నేను .{0,20}(డెలివరీ|డ్రైవర్|డ్రైవ్)|(డెలివరీ|డ్రైవర్) (గా )?(పని|చేస్తాను|చేయగలను)", re.IGNORECASE)


def _norm(text: str) -> str:
    return " " + re.sub(r"\s+", " ", re.sub(r"[^\w\s&]", " ", str(text or "").lower())).strip() + " "


class Taxonomy:
    def __init__(self, nodes: Iterable[Dict[str, Any]]):
        self.nodes: Dict[str, Dict[str, Any]] = {}
        for n in nodes:
            key = str(n.get("key") or "").strip()
            if key:
                self.nodes[key] = dict(n)

    def path(self, key: str) -> List[Dict[str, Any]]:
        out, seen = [], set()
        node = self.nodes.get(key)
        while node and node["key"] not in seen:
            seen.add(node["key"])
            out.append(node)
            node = self.nodes.get(node.get("parent") or "")
        return list(reversed(out))

    def effective(self, key: str) -> Dict[str, Any]:
        """Capabilities / attributes inherited down the path; nearest wins for scalars."""
        chain = self.path(key)
        caps: List[str] = []
        attrs: List[str] = []
        scalars: Dict[str, Any] = {}
        for node in chain:
            for c in node.get("capabilities") or []:
                if c not in caps:
                    caps.append(c)
            for c in node.get("removes") or []:
                if c in caps:
                    caps.remove(c)
            for a in node.get("attributes") or []:
                if a not in attrs:
                    attrs.append(a)
            for s in ("mobility_kind", "advisor_category"):
                if node.get(s):
                    scalars[s] = node[s]
            if node.get("high_stakes"):
                scalars["high_stakes"] = True
        return {"key": key, "label": chain[-1]["label"] if chain else key,
                "path": [{"key": n["key"], "label": n["label"]} for n in chain],
                "capabilities": caps, "attributes": attrs, "mobility_kind": scalars.get("mobility_kind"),
                "advisor_category": scalars.get("advisor_category"),
                "high_stakes": bool(scalars.get("high_stakes"))}

    def match(self, text: str) -> Optional[str]:
        """The deepest (then longest-alias) node named in the text."""
        words = _norm(text)
        best: Optional[tuple] = None
        for key, node in self.nodes.items():
            for alias in node.get("aliases") or []:
                a = _norm(alias).strip()
                if not a:
                    continue
                hit = f" {a} " in words if a.isascii() else a in words
                if hit:
                    score = (len(self.path(key)), len(a))
                    if best is None or score > best[0]:
                        best = (score, key)
        return best[1] if best else None

    def resolve(self, text: str) -> Dict[str, Any]:
        key = self.match(text)
        provider = bool(_PROVIDER.search(str(text or "")))
        if key is None:
            return {"matched": False, "role": "provider" if provider else "customer", "actions": []}
        eff = self.effective(key)
        caps = eff["capabilities"]
        if provider:
            actions = [c for c in caps if c in ("join_as_partner", "list_item", "post_job", "upload_video")]
        else:
            actions = [c for c in caps if c not in ("join_as_partner", "list_item", "post_job")]
        return {"matched": True, "role": "provider" if provider else "customer", **eff, "actions": actions}


def taxonomy_from_records(records: Iterable[Dict[str, Any]]) -> Taxonomy:
    nodes = [{**(r.get("data") or {}), "key": (r.get("data") or {}).get("key")}
             for r in records if r.get("status") == "ACTIVE" and not r.get("archived")]
    return Taxonomy(nodes or DEFAULT_NODES)


def seed_defaults(resources: Any) -> int:
    """Seed the Command Center store once (never over staff edits)."""
    if resources.repo.list("taxonomy_nodes", include_archived=True):
        return 0
    for node in DEFAULT_NODES:
        data = {k: v for k, v in node.items() if v not in (None, [], False) or k in ("key", "label")}
        resources.create("taxonomy_nodes", data, actor="system:seed", status="ACTIVE")
    return len(DEFAULT_NODES)
