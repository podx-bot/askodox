"""A text the person asked us to WRITE is shown whole in the chat, never cut inside card tabs (owner phone 2026-11-28)."""
from app.services import answer_card

LETTER = (
    "Here is your letter.\n[[more]]\nSubject: Leave request for 2 days\n\nDear Sir/Madam,\n"
    "I am not feeling well and would like to request leave for 2 days. I will rest and recover, and I will keep you "
    "informed about my health. I will also complete any pending work as soon as I return.\n\nThank you,\nRavi"
)


def test_leave_letter_is_no_card():
    assert answer_card.build(None, reply=LETTER, user_text="write a professional leave letter") is None


def test_letter_shape_alone_is_no_card():
    assert answer_card.is_written_document(LETTER, "")


def test_normal_advice_still_gets_a_card():
    reply = "Choose a 2.1 soundbar.\n[[more]]\n## Look for\n- HDMI ARC\n- Bluetooth\n" * 3
    assert not answer_card.is_written_document(reply, "best soundbar under 15000")
