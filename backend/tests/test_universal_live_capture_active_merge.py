from types import SimpleNamespace

from app.services.universal_live_capture_service import UniversalLiveCaptureService


class FakeDemands:
    def __init__(self):
        self.rows = []
        self.create_count = 0

    def latest_active_for_user(self, user_id):
        rows = [row for row in self.rows if row["user_id"] == str(user_id) and row["status"] == "ACTIVE"]
        return dict(rows[-1]) if rows else None

    def create(self, request):
        self.create_count += 1
        row = dict(request)
        row.update({"id": self.create_count, "status": "ACTIVE"})
        self.rows.append(row)
        return row["id"]

    def get(self, demand_id):
        for row in self.rows:
            if row["id"] == int(demand_id):
                return dict(row)
        return None

    def update_active_fields(self, demand_id, fields):
        for row in self.rows:
            if row["id"] == int(demand_id) and row["status"] == "ACTIVE":
                row.update(fields)
                return True
        return False


class FakeUsers:
    def find_by_whatsapp_mobile(self, _mobile):
        return {"registration_complete": 1}


class FakeSessions:
    def get(self, _mobile):
        return SimpleNamespace(step=SimpleNamespace(name="MAIN_MENU"))


class FakeMatcher:
    def find_matches(self, _request, limit=10):
        return []


class FakeTargeting:
    def handle_no_match(self, _request):
        return "NO_MATCH"


class FakeNotifications:
    def notify_matches(self, *_args, **_kwargs):
        return "MATCH"


def make_service(demands):
    return UniversalLiveCaptureService(
        extractor=None,
        demand_repository=demands,
        matcher=FakeMatcher(),
        targeting_service=FakeTargeting(),
        notification_service=FakeNotifications(),
        notification_repository=None,
        user_repository=FakeUsers(),
        session_registry=FakeSessions(),
    )


def request(subject="Chicken Boneless", quantity=10):
    return {
        "side": "NEED",
        "domain": "PRODUCT",
        "subject": subject,
        "quantity": quantity,
        "unit": "kg",
        "confidence": 0.95,
    }


def test_same_context_structured_input_updates_existing_active_id():
    demands = FakeDemands()
    service = make_service(demands)

    service.process_structured("9000000000", request(quantity=10), source="text")
    first_id = demands.rows[0]["id"]
    service.process_structured(
        "9000000000",
        {**request(quantity=12), "constraints": {"variant": "boneless"}},
        source="image",
        media_ref="img-1",
    )

    assert demands.create_count == 1
    assert len(demands.rows) == 1
    assert demands.rows[0]["id"] == first_id
    assert demands.rows[0]["quantity"] == 12
    assert demands.rows[0]["source"] == "image"
    assert demands.rows[0]["media_ref"] == "img-1"
    assert demands.rows[0]["constraints"] == {"variant": "boneless"}


def test_different_subject_is_not_silently_merged():
    demands = FakeDemands()
    service = make_service(demands)

    service.process_structured("9000000000", request("chicken"), source="text")
    service.process_structured("9000000000", request("mutton"), source="text")

    assert demands.create_count == 2
    assert [row["subject"] for row in demands.rows] == ["chicken", "mutton"]
