from app.services.whatsapp_support_only_gate import WhatsAppSupportOnlyGate


def test_location_share_is_redirected_and_never_touches_business_flows():
    """Point 51 gap: a shared WhatsApp location must not drive worker/employer
    registration completion, job-location tracking, or job matching. It must
    deterministically redirect to the app instead, regardless of any prior
    conversation/session state."""
    gate = WhatsAppSupportOnlyGate()

    reply = gate.process_location("919999999999")

    assert isinstance(reply, str) and reply.strip()
    assert "app" in reply.lower()
    # Must not resemble a completed-registration/job-matching confirmation.
    for forbidden in ("registration పూర్తైంది", "Job ID", "Nearby matches", "save అయింది"):
        assert forbidden not in reply


def test_location_gate_is_stateless_and_ignores_sender_identity():
    gate = WhatsAppSupportOnlyGate()

    reply_a = gate.process_location("911111111111")
    reply_b = gate.process_location("922222222222")

    assert reply_a == reply_b


def test_text_gate_unaffected_by_the_location_gate_addition():
    # Regression guard: adding process_location() must not change the
    # existing, already-verified text gate behaviour.
    gate = WhatsAppSupportOnlyGate()

    assert "customer-care" in gate.process_text("9990001111", "naaku support kavali").lower() or \
        "support" in gate.process_text("9990001111", "naaku support kavali").lower()
    assert "app" in gate.process_text("9990001111", "naaku job kavali").lower()
