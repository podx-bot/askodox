from app.services.decision_discovery_service import DecisionDiscoveryService
from app.services.dynamic_role_profile_attachment_service import DynamicRoleProfileAttachmentService
from app.services.universal_action_contract import actions_for
from app.services.universal_category_flow_brain import UniversalCategoryFlowBrain
from app.services.universal_category_schema import UniversalCategorySchemaRegistry


class Users:
    def __init__(self):
        self.capabilities = set()

    def find_by_whatsapp_mobile(self, user_id):
        return {"registration_complete": 1}

    def has_capability(self, user_id, capability):
        return capability in self.capabilities

    def add_capability(self, user_id, capability, source=None):
        self.capabilities.add(capability)


class Sessions:
    def __init__(self):
        self.session = type("Session", (), {"data": {}})()

    def get(self, user_id):
        return self.session

    def save(self, user_id):
        return None


class Delegate:
    def process(self, sender_mobile, message):
        return "continued"


def test_phase_0_9_category_matrix_has_schema_actions_and_roles():
    matrix = {
        "COMMERCE": ("I want to buy a mobile", "ask_seller", "BUYER"),
        "SERVICES": ("I need an electrician", "request_quote", "SERVICE_CUSTOMER"),
        "JOBS": ("I need a job", "apply", "WORKER"),
        "DELIVERY": ("I need this parcel delivered", "request_delivery", "DELIVERY_CUSTOMER"),
        "APPOINTMENT": ("I need a doctor appointment", "request_slot", "SERVICE_CUSTOMER"),
        "PROPERTY": ("I want to buy a house", "schedule_viewing", "BUYER"),
        "FOOD": ("I want to buy biryani", "place_food_request", "BUYER"),
        "MOBILITY": ("I need a ride", "request_ride", "SERVICE_CUSTOMER"),
    }
    brain = UniversalCategoryFlowBrain()
    users = Users()
    attachment = DynamicRoleProfileAttachmentService(
        delegate=Delegate(),
        category_brain=brain,
        user_repository=users,
        session_registry=Sessions(),
    )
    discovery = DecisionDiscoveryService(brain)

    for category, (message, action_id, capability) in matrix.items():
        schema = UniversalCategorySchemaRegistry.resolve(category)
        assert schema.category == category
        assert actions_for(category, "NEED", "ACTIVE")[0].id == action_id
        attachment.process("app-matrix-user", message)
        assert capability in users.capabilities
        assert discovery.question_for(message) is None

    assert len(users.capabilities) >= 4
