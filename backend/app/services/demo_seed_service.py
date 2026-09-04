"""Controlled TEST/DEMO data seeding for ASKODOX end-to-end validation.

All records created here are marked with ``demo:`` sources, so production reads
exclude them automatically. Reset deletes only TEST/DEMO rows.
"""

from __future__ import annotations

from typing import Any, Dict, List


class DemoSeedService:
    """Create deterministic Party A ↔ Party B demo pairs for core flows."""

    DEFAULT_LOCATION = {
        "latitude": 16.5062,
        "longitude": 80.6480,
        "location_text": "Vijayawada demo zone",
    }

    PAIRS: tuple[tuple[str, Dict[str, Any], Dict[str, Any]], ...] = (
        (
            "commerce",
            {"user_id": "app-demo-buyer", "side": "NEED", "domain": "PRODUCT", "subject": "chicken"},
            {"user_id": "app-demo-seller", "side": "OFFER", "domain": "PRODUCT", "subject": "chicken"},
        ),
        (
            "service",
            {"user_id": "app-demo-service-seeker", "side": "NEED", "domain": "SERVICE", "subject": "electrician"},
            {"user_id": "app-demo-service-provider", "side": "OFFER", "domain": "SERVICE", "subject": "electrician"},
        ),
        (
            "job",
            {"user_id": "app-demo-job-seeker", "side": "OFFER", "domain": "WORK", "subject": "computer operator"},
            {"user_id": "app-demo-employer", "side": "NEED", "domain": "WORKERS", "subject": "computer operator"},
        ),
        (
            "ride",
            {"user_id": "app-demo-passenger", "side": "NEED", "domain": "RIDE", "subject": "Vijayawada to Gannavaram"},
            {"user_id": "app-demo-driver", "side": "OFFER", "domain": "RIDE", "subject": "Vijayawada to Gannavaram"},
        ),
        (
            "parcel",
            {"user_id": "app-demo-parcel-sender", "side": "NEED", "domain": "PARCEL", "subject": "Vijayawada to Gannavaram parcel"},
            {"user_id": "app-demo-delivery-partner", "side": "OFFER", "domain": "PARCEL", "subject": "Vijayawada to Gannavaram parcel"},
        ),
        (
            "appointments",
            {"user_id": "app-demo-appointment-customer", "side": "NEED", "domain": "SERVICE", "subject": "doctor appointment tomorrow"},
            {"user_id": "app-demo-appointment-provider", "side": "OFFER", "domain": "SERVICE", "subject": "doctor appointment tomorrow"},
        ),
        (
            "catering",
            {"user_id": "app-demo-catering-customer", "side": "NEED", "domain": "SERVICE", "subject": "catering for 100 guests"},
            {"user_id": "app-demo-caterer", "side": "OFFER", "domain": "SERVICE", "subject": "catering for 100 guests"},
        ),
        (
            "local_discovery",
            {"user_id": "app-demo-local-seeker", "side": "NEED", "domain": "PRODUCT", "subject": "nearby local seller"},
            {"user_id": "app-demo-local-business", "side": "OFFER", "domain": "PRODUCT", "subject": "nearby local seller"},
        ),
    )

    def __init__(self, repository) -> None:
        self.repository = repository

    def reset(self) -> int:
        return int(self.repository.delete_test_records())

    def seed(self, reset_first: bool = True) -> Dict[str, Any]:
        deleted = self.reset() if reset_first else 0
        created: Dict[str, Dict[str, int]] = {}

        for name, party_a, party_b in self.PAIRS:
            a_record = self._record(name, "party-a", party_a)
            b_record = self._record(name, "party-b", party_b)
            created[name] = {
                "party_a_id": self.repository.create(a_record),
                "party_b_id": self.repository.create(b_record),
            }

        return {
            "deleted": deleted,
            "created_count": sum(len(pair) for pair in created.values()),
            "pairs": created,
        }

    def _record(self, flow: str, party: str, values: Dict[str, Any]) -> Dict[str, Any]:
        return {
            **values,
            **self.DEFAULT_LOCATION,
            "source": f"demo:{flow}:{party}",
            "status": "ACTIVE",
            "constraints": {"demo_flow": flow, "demo_party": party},
        }

    def active_demo_records(self) -> List[Dict[str, Any]]:
        return self.repository.list_active(limit=500, test_mode=True)
