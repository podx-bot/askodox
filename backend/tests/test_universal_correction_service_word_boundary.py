"""Regression coverage for round 16: _explicit_target's role-keyword gate
used to match its trigger words as bare substrings, not whole words.

UniversalCorrectionService._explicit_target()'s role-keyword gate checked
`any(w in low for w in (..., "all", ...))` -- plain substring containment.
"all" is one of those trigger words, and it is also a substring of the
common correction MARKERS word "actually" (a-c-t-u-a-l-l-y). So any
message containing "actually" (or another MARKERS word) together with a
bare 1-6 digit -- which _role_value() reads as a role number even with no
real role keyword present -- was misread as an explicit role-change
command. For example "actually 2 people are coming" incorrectly resolved
to "the user wants to be a Seller" (role 2), with no role keyword
anywhere in the message.

This was found (and deliberately left unfixed, out of scope) while
investigating round 15's separate in-app-e2e-smoke.yml CI failure -- see
test_universal_correction_service.py for that fix. It does not affect
that fix; the two bugs are independent and this file covers only this
one, per round 16's explicit scope.

Fixed by matching each keyword as a whole word (word-boundary regex)
instead of a bare substring -- the same approach _role_value() already
used for its own "ALL" match.
"""
from app.services.universal_correction_service import UniversalCorrectionService


def _service() -> UniversalCorrectionService:
    return UniversalCorrectionService(delegate=None)


def test_all_no_longer_matches_inside_actually():
    assert _service().detect("actually 2 people are coming") is None


def test_all_no_longer_matches_inside_other_marker_words_with_a_bare_digit():
    # "actually" and "corrections" both contain "all"/"all"-adjacent letters
    # in ways worth covering directly, alongside a bare 1-6 digit that
    # _role_value() would otherwise read as a role number.
    assert _service().detect("actually 5 is fine") is None
    assert _service().detect("sorry, actually 3 works better") is None


def test_genuine_all_roles_command_still_works():
    intent = _service().detect("actually I want all roles")
    assert intent is not None
    assert intent.target == "roles"
    assert intent.value == "ALL"


def test_genuine_single_role_correction_still_works():
    intent = _service().detect("change my role to seller, I want to sell products")
    assert intent is not None
    assert intent.target == "roles"
    assert intent.value == "SELLER"


def test_genuine_role_word_at_start_or_end_of_message_still_matches():
    # Word-boundary matching must not require interior whitespace on both
    # sides -- start-of-string and end-of-string are valid boundaries too.
    assert _service().detect("seller, please correct my role") is not None
    assert _service().detect("please correct my role, I am a buyer") is not None


def test_bare_digit_with_a_marker_but_no_real_role_keyword_is_still_ignored():
    assert _service().detect("sorry, I need 2 more boxes") is None
    assert _service().detect("wrong, 2 boxes needed") is None
