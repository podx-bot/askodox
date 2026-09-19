from types import SimpleNamespace

from app.services.dynamic_role_profile_attachment_service import DynamicRoleProfileAttachmentService
from app.services.universal_category_flow_brain import UniversalCategoryFlowBrain


class FakeUsers:
    def __init__(self):
        self.user = {"registration_complete": 1}
        self.capabilities = set()

    def find_by_whatsapp_mobile(self, user_id):
        return self.user

    def has_capability(self, user_id, capability):
        return capability in self.capabilities

    def add_capability(self, user_id, capability, source=None):
        self.capabilities.add(capability)


class FakeSessionRegistry:
    def __init__(self):
        self.session = SimpleNamespace(data={}, step=None)

    def get(self, user_id):
        return self.session

    def save(self, user_id):
        return None


class FakeDelegate:
    def process(self, sender_mobile, message):
        return "continued"


def test_one_account_accumulates_capabilities_from_current_intent():
    users = FakeUsers()
    service = DynamicRoleProfileAttachmentService(
        delegate=FakeDelegate(),
        category_brain=UniversalCategoryFlowBrain(),
        user_repository=users,
        session_registry=FakeSessionRegistry(),
    )

    for message in (
        "I want to buy a mobile",
        "I want to sell my old mobile",
        "I need an electrician",
        "I provide AC repair service",
        "I need a job",
        "I can deliver parcels",
        "I need this parcel delivered",
    ):
        assert service.process("app-multi-role", message) == "continued"

    assert users.capabilities == {
        "BUYER",
        "SELLER",
        "SERVICE_CUSTOMER",
        "SERVICE_PROVIDER",
        "WORKER",
        "DELIVERY_PARTNER",
        "DELIVERY_CUSTOMER",
    }