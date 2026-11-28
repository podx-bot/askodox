"""ANSWER AUDIT (owner 2026-11-28): every KIND of question people ask must come back neat, whole and in the form asked.

One table, many kinds of question (not the ones that failed once). Each row = what the person asks + a typical reply of
the shape the brain writes. The audit checks the SHAPE the app draws: written things are never cut, short chats stay
bubbles, long advice becomes a card whose headline is the answer, nothing is cut mid-word, no fixed 'not searched' text.
A new kind of question = add one row. (Real-AI answers are audited by `conversation-trace.yml` on staging; the cloud
sandbox cannot reach the model providers.)"""
import pytest

from app.services import answer_card

LONG = " ".join(["This is one full sentence of the written text."] * 12)

# (kind, user words, reply, expect) -- expect: "bubble" (no card), "whole" (written text shown whole, no card), "card"
ROWS = [
    ("greeting", "hi", "Hello! How can I help?", "bubble"),
    ("one fact", "capital of France", "Paris.", "bubble"),
    ("maths", "what is 18% of 2400", "432.", "bubble"),
    ("leave letter", "write a professional leave letter for 2 days",
     "Here is your letter.\n[[more]]\nSubject: Leave request\n\nDear Sir/Madam,\n" + LONG + "\n\nThank you,\nRavi", "whole"),
    ("email", "draft an email to my landlord about the leak", "Subject: Water leak\n\nDear Landlord,\n" + LONG, "whole"),
    ("whatsapp message", "write a message to my team about Monday meeting",
     "Hi team,\n" + LONG + "\nThanks,\nRavi", "whole"),
    ("contractor letter", "write a letter to contractor about delay in works",
     "Dear Sir,\nSubject: Delay in works\n" + LONG, "whole"),
    ("application", "rayi leave application", "To,\nThe Principal\n\nSubject: Leave application\n\nDear Sir,\n" + LONG, "whole"),
    ("telugu letter", "ఒక లేఖ రాయి", "ప్రియమైన అమ్మకు,\n" + LONG, "whole"),
    ("how to", "how to link Aadhaar with PAN",
     "Link it on the income tax site.\n[[more]]\n## Steps\n1. Open the site\n2. Pay the fee\n3. Submit\n## Papers\n- PAN\n- Aadhaar", "card"),
    ("comparison", "which is better, 2.1 or 3.1 soundbar",
     "A 3.1 gives clearer dialogue.\n[[more]]\n## 2.1\n- Simple\n## 3.1\n- Centre speaker\n- Clearer voices", "card"),
    ("health advice", "I have fever for 3 days what to do",
     "See a doctor today.\n[[more]]\n## Do\n- Rest\n- Fluids\n## Go now if\n- [risk] Fever above 104\n- [risk] Breathing trouble", "card"),
    ("scam check", "is this sms real: your account blocked click link",
     "This looks like a scam.\n[[more]]\n## Why\n- Link to unknown site\n- Urgent threat", "card"),
]


@pytest.mark.parametrize("kind,user,reply,expect", ROWS, ids=[r[0] for r in ROWS])
def test_shape_for_each_kind(kind, user, reply, expect):
    card = answer_card.build(None, reply=reply, user_text=user)
    if expect in ("bubble", "whole"):
        assert card is None, f"{kind}: must not be drawn as a card"
    else:
        assert card is not None, f"{kind}: long advice needs a card"
        assert card["headline"].strip(), f"{kind}: card needs a headline = the answer"
        assert not card["headline"].rstrip().endswith(("-", ",", ":")), f"{kind}: headline cut"


def test_written_things_keep_every_line():
    """The whole text is still in the reply the chat shows (nothing shortened by the card path)."""
    reply = "Dear Sir,\n" + LONG + "\nThank you"
    assert answer_card.without_mark(reply).endswith("Thank you")


def test_no_fixed_not_searched_text_in_server_replies():
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[1] / "app"
    hits = [p for p in root.rglob("*.py") if "haven't searched yet" in p.read_text(encoding="utf-8", errors="ignore")]
    assert not hits, hits
