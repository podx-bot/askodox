from app.services.conversation_os_runtime_service import ConversationOSRuntimeService


class Ledger:
    def __init__(self):
        self.state = {}

    def load_state(self, user_id):
        return self.state.get(user_id)

    def save_state(self, user_id, state, channel="whatsapp"):
        self.state[user_id] = state

    def append_turn(self, *args, **kwargs):
        return None


class Memory:
    def __init__(self):
        self.items = ["I prefer Telugu replies"]

    def process(self, user_id, message):
        if message == "Clear my memory":
            self.items = []
            return "Cleared 1 saved memory item."
        return None

    def context(self, user_id, limit=10):
        return [{"memory_value": value} for value in self.items]


class Delegate:
    def __init__(self):
        self.last_message = ""

    def process(self, sender_mobile, message):
        self.last_message = message
        return "ok"


def test_cleared_memory_is_not_reinjected_from_ledger():
    ledger = Ledger()
    memory = Memory()
    delegate = Delegate()
    runtime = ConversationOSRuntimeService(delegate, ledger, user_memory_service=memory)

    runtime.process("u1", "Explain this")
    assert "I prefer Telugu replies" in delegate.last_message
    assert memory.process("u1", "Clear my memory")
    runtime.process("u1", "Explain this again")
    assert "I prefer Telugu replies" not in delegate.last_message
