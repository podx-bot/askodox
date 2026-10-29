"""Owner alerts (2026-10-29): a subject searched with no local supply, or one
the AI could not confirm / the user corrected, reaches staff with demand:view
as ONE notification + push per subject per day -- subjects only."""
from datetime import datetime, timezone

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.platform_repository import PlatformRepository
from app.services import governance as gov
from app.services import owner_alerts


def test_threshold_one_alert_per_subject_per_day_and_only_demand_staff(tmp_path):
    repo = PlatformRepository(str(tmp_path / "p.db"))
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    for _ in range(3):
        repo.record_event("search", detail={"subject": "Oppo Find X10", "results": 4, "local": 0})
    repo.record_event("search", detail={"subject": "tractor", "results": 0, "local": 0})  # below threshold
    for _ in range(2):
        repo.record_event("knowledge_gap", detail={"subject": "Activa 7", "reasons": ["user_correction"]})
    repo.record_event("search", detail={"subject": "rice", "results": 5, "local": 5})
    staff = [{"app_user_id": "app-phone-919811111111", "active": True, "permissions": ["demand:view"]},
             {"app_user_id": "app-phone-919822222222", "active": True, "permissions": ["catalog:view"]},
             {"app_user_id": "", "active": True, "permissions": ["demand:view"]}]

    class CC:
        def __init__(self):
            self.inner = cc

        def list_staff(self):
            return staff

        def notify_once(self, *a, **k):
            return cc.notify_once(*a, **k)

    sent = []
    at = datetime.now(timezone.utc)
    result = owner_alerts.run(repo, CC(), at=at, has_permission=gov.has_permission,
                              notify=lambda user, **kw: sent.append((user, kw["body"])) or 1)
    assert result == {"alerts": 2, "pushed": 2}
    assert {u for u, _ in sent} == {"app-phone-919811111111"}
    assert any("Oppo Find X10" in b and "3 సార్లు" in b for _, b in sent)
    assert any("Activa 7" in b and "AI 2" in b for _, b in sent)
    assert owner_alerts.run(repo, CC(), at=at, has_permission=gov.has_permission,
                            notify=lambda *a, **k: 1) == {"alerts": 0, "pushed": 0}, "once per day"
    titles = [n["title"] for n in cc.notifications()]
    assert len(titles) == 2 and not any("919" in t for t in titles)
