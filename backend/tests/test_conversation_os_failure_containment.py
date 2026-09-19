from app.services.conversation_os_runtime_service import ConversationOSRuntimeService


class Delegate:
    def __init__(self):
        self.messages = []

    def process(self, sender_mobile, message):
        self.messages.append(message)
        return "solution-ok"


class BrokenLedger:
    def load_state(self, user_id):
        raise RuntimeError("ledger unavailable")


def test_ledger_failure_delegates_raw_request_without_fabricating_result():
    delegate = Delegate()
    runtime = ConversationOSRuntimeService(delegate=delegate, ledger_repository=BrokenLedger())

    result = runtime.process("fallback-user", "Need a plumber service")

    assert result == "solution-ok"
    assert delegate.messages == ["Need a plumber service"]
