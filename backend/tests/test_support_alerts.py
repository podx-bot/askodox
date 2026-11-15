"""Customer Care tickets reach the owner by email + phone notification (owner 2026-11-15, pani D)."""
from app.services import governance as gov
from app.services import support_alerts


def test_owner_email_default_and_env():
    assert support_alerts.owner_email({}) == "admin@askodox.com"
    assert support_alerts.owner_email({"ASKODOX_OWNER_EMAIL": "owner@example.com"}) == "owner@example.com"
    assert support_alerts.owner_email({"ASKODOX_OWNER_EMAIL": "not-an-email"}) == "admin@askodox.com"


def test_ticket_sends_one_email_and_one_push_per_support_staff():
    emails, pushes = [], []

    def email(channel, **kw):
        emails.append((channel, kw))
        return {"status": "MOCK_DELIVERED"}

    def push(user, **kw):
        pushes.append((user, kw))
        return 1

    staff = support_alerts.support_staff([
        {"active": True, "app_user_id": "app-phone-1", "permissions": ["support:manage"]},
        {"active": True, "app_user_id": "app-phone-2", "permissions": ["support:view"]},
        {"active": True, "app_user_id": "app-phone-3", "permissions": ["catalog:view"]},
        {"active": False, "app_user_id": "app-phone-4", "permissions": ["support:manage"]},
        {"active": True, "app_user_id": "", "permissions": ["support:manage"]},
    ], gov.has_permission)
    assert [s["app_user_id"] for s in staff] == ["app-phone-1", "app-phone-2"]
    out = support_alerts.send(case_id=42, category="TECHNICAL", issue="Payment sound not coming 9876543210",
                              critical=False, email=email, push=push, staff=staff, to="admin@askodox.com")
    assert out == {"email": "MOCK_DELIVERED", "pushed": 2}
    channel, kw = emails[0]
    assert channel == "email" and kw["to"] == "admin@askodox.com" and "#42" in kw["title"]
    assert kw["event"] == "support_ticket"
    assert all(p[1]["event_key"] == "support_ticket:42" for p in pushes), "one push per ticket per person"


def test_alert_failures_never_raise():
    def boom(*a, **k):
        raise RuntimeError("smtp down")

    out = support_alerts.send(case_id=7, category="", issue="x", critical=True, email=boom, push=boom,
                              staff=[{"app_user_id": "u"}], to="admin@askodox.com")
    assert out == {"email": "error", "pushed": 0}
    assert "అత్యవసరం" in support_alerts.alert_text(7, "", "x", True)["title"]
