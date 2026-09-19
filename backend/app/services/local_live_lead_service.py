"""Local-first buyer leads with automatic online fallback."""
from __future__ import annotations

import re
from typing import Any


class LocalLiveLeadService:
    """Coordinates existing universal demand, targeting, catalog and consent state."""

    _BUDGET_RE = re.compile(r"(?:₹|rs\.?|inr\s*)\s*([\d,]+)|([\d,]+)\s*(?:లోపు|లో|under|below)", re.I)
    _PRICE_RE = re.compile(r"(?:₹|rs\.?|inr\s*)\s*([\d,]+)", re.I)
    _BRANDS = ("samsung", "apple", "oneplus", "xiaomi", "redmi", "vivo", "oppo", "realme", "motorola", "google")
    _BUYER_HINTS = ("buy", "want", "need", "show", "compare", "price", "recommend", "కావాలి", "చూపించు", "కొనాలి", "ధర")

    def __init__(self, demand_repository, notification_repository, notification_service,
                 targeting_service, catalog_repository, affiliate_provider_config, profile_source,
                 signal_repository=None):
        self.demands = demand_repository
        self.notifications = notification_repository
        self.notification_service = notification_service
        self.targeting = targeting_service
        self.catalog = catalog_repository
        self.affiliates = affiliate_provider_config
        self.profile_source = profile_source
        self.signals = signal_repository

    def process(self, buyer_id: str, message: str) -> str | None:
        text = " ".join(str(message or "").split())
        existing = self.demands.latest_active_for_user(buyer_id)
        if not self._is_buyer_request(text) and not self._is_followup(text, existing):
            return self._seller_response_or_buyer_updates(buyer_id, text)
        facts = self._facts(text, buyer_id)
        if existing and self._is_followup(text, existing):
            facts["subject"] = existing.get("subject")
            facts["category"] = existing.get("category") or "mobile phone"
            facts["brand"] = existing.get("brand") or facts.get("brand")
            facts["location_text"] = existing.get("location_text") or facts.get("location_text")
            facts["latitude"] = existing.get("latitude") or facts.get("latitude")
            facts["longitude"] = existing.get("longitude") or facts.get("longitude")
        if existing and self._same_product_context(existing, facts):
            self.demands.update_active_fields(int(existing["id"]), facts)
            request = self.demands.get(int(existing["id"])) or {**existing, **facts}
        else:
            request = {"user_id": buyer_id, "side": "NEED", "domain": "PRODUCT", "source": "in_app_live_lead", **facts}
            request["id"] = self.demands.create(request)
            request = self.demands.get(request["id"]) or request

        local = self._local_results(request)
        plan = self.targeting.build_plan(request, already_contacted_user_ids=self.notifications.contacted_user_ids(request["id"]))
        if plan.get("waves"):
            self.notification_service.dispatch_plan(request, plan)
        online = self._online_results(request)
        responses = self.notifications.list_seller_responses_for_buyer(buyer_id, request["id"])
        return self._render(request, local, responses, online, bool(plan.get("waves")))

    def _seller_response_or_buyer_updates(self, user_id: str, text: str) -> str | None:
        targeted = self.notifications.latest_sent_request_for_target(user_id)
        if targeted and self._looks_like_response(text):
            fields = self._parse_response(text)
            self.notifications.record_seller_response(
                targeted["request_id"], user_id, fields["model"], fields["price"],
                fields["availability"], fields["details"],
            )
            return "✅ Seller response saved. The buyer will see it in Local Seller Responses after consent remains satisfied."
        responses = self.notifications.list_seller_responses_for_buyer(user_id)
        if responses:
            return "\n".join(self._response_line(row) for row in responses)
        return None

    def _local_results(self, request):
        query = " ".join(str(request.get(key) or "") for key in ("brand", "subject", "category"))
        rows = self.catalog.search_active(query, limit=20) if self.catalog is not None else []
        wanted_budget = request.get("budget")
        result = []
        for row in rows:
            price = row.get("price")
            if wanted_budget is not None and price is not None and float(price) > float(wanted_budget):
                continue
            result.append(row)
        return result

    def _online_results(self, request):
        category = str(request.get("category") or "mobile phone").casefold()
        return self.affiliates.active_for_category(category) if self.affiliates is not None else []

    def _render(self, request, local, responses, online, leads_sent):
        lines = []
        if local:
            lines.append("Local matches first:")
            lines.extend(f"- {row.get('seller_name') or 'Local seller'}: {row.get('subject')} ₹{row.get('price')}" for row in local[:5])
        if responses:
            lines.append("Local Seller Responses:")
            lines.extend(self._response_line(row) for row in responses)
        if online:
            lines.append("Online options:")
            lines.extend(f"- {row.get('provider_id') or 'Verified affiliate'}" for row in online[:5])
        if leads_sent:
            lines.append("I also notified relevant nearby registered sellers. Their responses will update Local Seller Responses here.")
        if not local and not responses and not online and not leads_sent:
            if self.signals is not None:
                self.signals.claim(
                    f"unmet-live-lead:{request.get('id')}",
                    "PRODUCT",
                    str(request.get("subject") or "product"),
                    str(request.get("location_text") or ""),
                    1,
                )
            lines.append("No verified local or online match is available yet. I logged this unmet demand for follow-up.")
        return "\n".join(lines)

    @staticmethod
    def _response_line(row):
        return f"- model: {row.get('response_model') or 'not specified'}; price: ₹{row.get('response_price') or 'not specified'}; availability: {row.get('response_availability') or 'not specified'}; {row.get('response_details') or ''}".strip()

    def _facts(self, text, buyer_id):
        budget_match = self._BUDGET_RE.search(text)
        budget_text = next((value for value in budget_match.groups() if value), None) if budget_match else None
        brand = next((brand for brand in self._BRANDS if brand in text.casefold()), None)
        category = "mobile phone" if any(term in text.casefold() for term in ("mobile", "phone", "ఫోన్")) else "product"
        location = self._profile_location(buyer_id)
        return {"subject": " ".join(x for x in (brand, category) if x), "category": category, "brand": brand or "", "price": float(budget_text.replace(",", "")) if budget_text else None, "budget": float(budget_text.replace(",", "")) if budget_text else None, "location_text": location.get("label", ""), "latitude": location.get("latitude"), "longitude": location.get("longitude"), "constraints": {"brand": brand or "", "buyer_message": text}}

    def _profile_location(self, buyer_id):
        for profile in self.profile_source() or []:
            if str(profile.get("user_id")) == str(buyer_id):
                return {"label": profile.get("location") or profile.get("location_label") or "", "latitude": profile.get("latitude"), "longitude": profile.get("longitude")}
        return {}

    @staticmethod
    def _same_product_context(existing, facts):
        return str(existing.get("domain")) == "PRODUCT" and str(existing.get("subject")).casefold() == str(facts.get("subject")).casefold()

    @classmethod
    def _is_buyer_request(cls, text):
        lowered = text.casefold()
        return (any(hint in lowered for hint in cls._BUYER_HINTS) or any(term in lowered for term in ("under", "below", "లోపు"))) and any(term in lowered for term in ("mobile", "phone", "ఫోన్", "product"))

    @classmethod
    def _is_followup(cls, text, existing):
        if not existing or str(existing.get("domain") or "").upper() != "PRODUCT":
            return False
        lowered = text.casefold()
        return bool(cls._PRICE_RE.search(text) or any(term in lowered for term in ("under", "below", "లోపు", "budget", "brand", "near", "దగ్గర")))

    @staticmethod
    def _looks_like_response(text):
        lowered = text.casefold()
        return bool(LocalLiveLeadService._PRICE_RE.search(text) or any(word in lowered for word in ("stock", "available", "availability", "ఉంది", "ధర")))

    @classmethod
    def _parse_response(cls, text):
        match = cls._PRICE_RE.search(text)
        price = float(match.group(1).replace(",", "")) if match else None
        availability = "in stock" if any(x in text.casefold() for x in ("stock", "available", "ఉంది")) else "seller reported availability"
        model = text.split(",", 1)[0].strip()[:120]
        return {"model": model, "price": price, "availability": availability, "details": text[:500]}