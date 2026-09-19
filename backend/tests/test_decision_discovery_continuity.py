from app.services.conversation_os_runtime_service import ConversationOSRuntimeService
from app.services.decision_discovery_service import DecisionDiscoveryService


class Ledger:
    def __init__(self):
        self.state = {}

    def load_state(self, user_id):
        return self.state.get(user_id)

    def save_state(self, user_id, state, channel="whatsapp"):
        self.state[user_id] = state

    def append_turn(self, *args, **kwargs):
        return None


class Delegate:
    def __init__(self):
        self.messages = []

    def process(self, sender_mobile, message):
        self.messages.append(message)
        return "comparison-ready"


def test_decision_discovery_question_is_answered_once_then_continues():
    ledger = Ledger()
    delegate = Delegate()
    runtime = ConversationOSRuntimeService(
        delegate=delegate,
        ledger_repository=ledger,
        decision_discovery_service=DecisionDiscoveryService(),
    )

    question = runtime.process("u1", "Which mobile should I buy?")
    assert "matters most" in question
    assert delegate.messages == []

    answer = runtime.process("u1", "Lower price but reliable quality")
    assert answer == "comparison-ready"
    assert len(delegate.messages) == 1
    assert "Lower price but reliable quality" in delegate.messages[0]
    assert ledger.state["u1"].get("decision_discovery") == {}