from app.services.session_tokens import issue_token, verify_token

SECRET = "test-secret-do-not-use-in-prod"


def test_issue_then_verify_round_trips_the_user_id():
    token = issue_token("app-phone-919876543210", SECRET, issued_at=1_000_000)
    assert verify_token(token, SECRET, now=1_000_000) == "app-phone-919876543210"


def test_verify_accepts_a_token_still_within_its_ttl():
    token = issue_token("app-phone-919876543210", SECRET, issued_at=1_000_000)
    ten_days_later = 1_000_000 + (10 * 24 * 60 * 60)
    assert verify_token(token, SECRET, now=ten_days_later) == "app-phone-919876543210"


def test_verify_rejects_a_token_past_its_default_ttl():
    token = issue_token("app-phone-919876543210", SECRET, issued_at=1_000_000)
    thirty_one_days_later = 1_000_000 + (31 * 24 * 60 * 60)
    assert verify_token(token, SECRET, now=thirty_one_days_later) is None


def test_verify_rejects_a_tampered_payload():
    token = issue_token("app-phone-919876543210", SECRET, issued_at=1_000_000)
    payload_b64, _, signature = token.partition(".")
    # Swap in a different (still validly-shaped) payload without re-signing --
    # this is exactly what a spoofing attempt looks like.
    forged_payload = issue_token("app-phone-911111111111", SECRET, issued_at=1_000_000).split(".")[0]
    forged_token = f"{forged_payload}.{signature}"
    assert verify_token(forged_token, SECRET, now=1_000_000) is None


def test_verify_rejects_a_token_signed_with_a_different_secret():
    token = issue_token("app-phone-919876543210", SECRET, issued_at=1_000_000)
    assert verify_token(token, "a-completely-different-secret", now=1_000_000) is None


def test_verify_rejects_malformed_tokens():
    assert verify_token("", SECRET) is None
    assert verify_token("not-a-real-token", SECRET) is None
    assert verify_token("only-one-part.", SECRET) is None
    assert verify_token(".only-a-signature", SECRET) is None
    assert verify_token(None, SECRET) is None  # type: ignore[arg-type]


def test_issue_token_rejects_a_blank_user_id():
    try:
        issue_token("", SECRET)
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for a blank app_user_id")


def test_issue_token_rejects_a_blank_secret():
    try:
        issue_token("app-phone-919876543210", "")
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for a blank secret")


def test_two_different_users_get_different_tokens_and_cannot_verify_as_each_other():
    token_a = issue_token("app-phone-911111111111", SECRET, issued_at=1_000_000)
    token_b = issue_token("app-phone-922222222222", SECRET, issued_at=1_000_000)
    assert token_a != token_b
    assert verify_token(token_a, SECRET, now=1_000_000) == "app-phone-911111111111"
    assert verify_token(token_b, SECRET, now=1_000_000) == "app-phone-922222222222"
