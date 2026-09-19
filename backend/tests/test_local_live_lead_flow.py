import sqlite3

from app.repositories.universal_demand_repository import UniversalDemandRepository
from app.repositories.universal_notification_repository import UniversalNotificationRepository
from app.repositories.demand_signal_repository import DemandSignalRepository
from app.services.in_app_universal_notification_service import InAppUniversalNotificationService
from app.services.local_live_lead_service import LocalLiveLeadService
from app.services.phase_6_9_assistant_service import AffiliateProviderConfig
from app.services.universal_matcher import UniversalMatcher
from app.services.universal_targeting_service import UniversalTargetingService


class FakeWhatsApp:
    def send_text_message(self, mobile, body):
        return {"success": True, "provider_message_id": f"fake:{mobile}"}


class Catalog:
    def __init__(self, rows):
        self.rows = rows

    def search_active(self, query, limit=20):
        return list(self.rows)[:limit]


def build(tmp_path, catalog_rows=()):
    db = str(tmp_path / "live-lead.db")
    demand = UniversalDemandRepository(db)
    notifications = UniversalNotificationRepository(db)
    profiles = [
        {"user_id": "app-buyer", "role": "BUYER", "latitude": 16.51, "longitude": 80.65, "location": "Vijayawada"},
        {"user_id": "app-seller", "role": "SELLER", "category": "mobile phones", "latitude": 16.54, "longitude": 80.67},
    ]
    targeting = UniversalTargetingService(
        profile_source=lambda: profiles,
        subject_similarity=UniversalMatcher._subject_similarity,
        distance_km=UniversalMatcher._distance_km,
    )
    transport = InAppUniversalNotificationService(
        notification_repository=notifications,
        whatsapp_service=FakeWhatsApp(),
        contact_resolver=lambda user_id: {"name": user_id, "mobile": user_id},
    )
    affiliates = AffiliateProviderConfig()
    service = LocalLiveLeadService(
        demand_repository=demand,
        notification_repository=notifications,
        notification_service=transport,
        targeting_service=targeting,
        catalog_repository=Catalog(catalog_rows),
        affiliate_provider_config=affiliates,
        profile_source=lambda: profiles,
    )
    service.signals = DemandSignalRepository(db)
    return service, demand, notifications, affiliates, profiles


def test_telugu_local_lead_targets_category_seller_and_renders_late_response(tmp_path):
    service, demand, notifications, affiliates, profiles = build(tmp_path)
    first = service.process("app-buyer", "₹15,000 లోపు Samsung mobile కావాలి, నా దగ్గరలో చూపించు")

    assert "nearby registered sellers" in first
    request = demand.latest_active_for_user("app-buyer")
    assert request["subject"] == "samsung mobile phone"
    assert request["latitude"] == 16.51
    target = notifications.latest_sent_request_for_target("app-seller")
    assert target["request_id"] == request["id"]
    row = notifications._connect().execute(
        "SELECT lead_message FROM universal_notifications WHERE request_id=? AND target_user_id=?",
        (request["id"], "app-seller"),
    ).fetchone()
    assert "Samsung mobile phone" in row["lead_message"]
    assert "₹15,000" in row["lead_message"]

    seller_prompt = service.process("app-seller", "hello")
    assert "Respond with model, price and availability" in seller_prompt

    seller_reply = service.process("app-seller", "Samsung A15, ₹12,000, in stock")
    assert "Seller response saved" in seller_reply
    buyer_view = service.process("app-buyer", "show Samsung mobile")
    assert "Local Seller Responses" in buyer_view
    assert "Samsung A15" in buyer_view
    assert "₹12000" in buyer_view

    interest = notifications.get_interest(request["id"], "app-seller")
    assert interest["contact_shared"] == 0


def test_zero_local_catalog_shows_affiliate_without_asking_permission(tmp_path):
    service, demand, notifications, affiliates, profiles = build(tmp_path)
    affiliates.register("amazon", category="mobile phone", route="affiliate")
    # No seller profile in this case: online options must not wait for a local response.
    profiles.pop()

    reply = service.process("app-buyer", "Samsung mobile under ₹15000 near me")

    assert "Online options" in reply
    assert "amazon" in reply
    assert "Do you want" not in reply
    assert notifications.list_seller_responses_for_buyer("app-buyer") == []


def test_budget_followup_reuses_buyer_context_and_unmet_demand_is_logged(tmp_path):
    service, demand, notifications, affiliates, profiles = build(tmp_path)
    service.profile_source = lambda: [profiles[0]]

    first = service.process("app-buyer", "Samsung mobile కావాలి")
    followup = service.process("app-buyer", "under ₹15000")

    request = demand.latest_active_for_user("app-buyer")
    assert request["subject"] == "samsung mobile phone"
    assert request["price"] == 15000
    assert "No verified local or online match" in followup
    assert service.signals.count() == 1
