"""Staff alerts when a store item goes bad (owner 2026-11-06).

When an item's stock turns OUT_OF_STOCK, its commission stops (INACTIVE), or its
commission rate drops below the floor (platform setting
`catalog.min_commission_rate`, default 1 %), the staff member who added it gets
ONE task in Staff Workspace -> Tasks plus a phone push. One open task per item
and problem (dedupe key), so a repeated feed or edit never spams.

This fires on every recorded change -- a staff edit, the console, a feed or CSV
import, a marketplace API refresh. It cannot see a store change nobody recorded:
Meesho has no product API and refuses our server, so its stock is only known
when someone re-reads or edits the item.
"""
from __future__ import annotations

from typing import Any, Dict, List

FLOOR_KEY = "catalog.min_commission_rate"
DEFAULT_FLOOR = 1.0


def _rate(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(str(value).replace("%", "").strip())
    except ValueError:
        return None


def floor() -> float:
    try:
        from app.services import platform_settings as ps

        value = _rate(ps.get(FLOOR_KEY, None))
    except Exception:
        value = None
    return DEFAULT_FLOOR if value is None else value


def problems(before: Dict[str, Any], after: Dict[str, Any]) -> List[Dict[str, str]]:
    """The NEW problems this change caused (an old problem is not repeated)."""
    title = str(after.get("title") or f"Item #{after.get('id')}")[:80]
    out: List[Dict[str, str]] = []
    if after.get("stock_status") == "OUT_OF_STOCK" and before.get("stock_status") != "OUT_OF_STOCK":
        out.append({"reason": "out_of_stock", "title": f"Stock అయిపోయింది: {title}",
                    "why": "ఈ item ఇప్పుడు OUT_OF_STOCK గా నమోదైంది. Customers కొనలేరు.",
                    "do": "Store లో stock వచ్చిందేమో చూడండి. రాకపోతే My items లో Pause / Expire చేయండి."})
    if after.get("commission_status") == "INACTIVE" and before.get("commission_status") != "INACTIVE":
        out.append({"reason": "commission_stopped", "title": f"Commission ఆగిపోయింది: {title}",
                    "why": "ఈ item కి commission INACTIVE అయింది. Sales వచ్చినా మనకు ఆదాయం రాదు.",
                    "do": "Partner తో commission link / rate చూసి My items -> Edit లో సరిచేయండి, లేదా Pause చేయండి."})
    limit = floor()
    now, was = _rate(after.get("verified_commission_rate")), _rate(before.get("verified_commission_rate"))
    if now is not None and now < limit and (was is None or was >= limit):
        out.append({"reason": "low_commission", "title": f"Commission {now:g}% ({limit:g}% కంటే తక్కువ): {title}",
                    "why": f"ఈ item commission {now:g}% కి తగ్గింది. కనీసం {limit:g}% ఉండాలి.",
                    "do": "Partner తో rate చూసి My items -> Edit లో సరిచేయండి, లేదా Pause చేయండి."})
    return out


def check(container: Any, before: Dict[str, Any], after: Dict[str, Any]) -> int:
    """Create (once) and push a task for each new problem. Best effort: never
    fails the change that triggered it. Returns how many tasks were created."""
    if not before or not after or after.get("deleted_at"):
        return 0
    found = problems(before, after)
    if not found:
        return 0
    try:
        from app.api.routes.platform import platform
        from app.api.routes.staff_workspace import alert_new_task, create_task_once

        pf = platform(container)
        owner = str(after.get("submitted_by") or "")
        created = 0
        for p in found:
            data = {"title": p["title"], "kind": "review_items", "why": p["why"], "expected_action": p["do"],
                    "priority": "high", "dedupe_key": f"item_health:{after.get('id')}:{p['reason']}",
                    "evidence": {"item_id": after.get("id"), "reason": p["reason"],
                                 "stock_status": after.get("stock_status"),
                                 "commission_status": after.get("commission_status"),
                                 "commission_rate": after.get("verified_commission_rate")}}
            if owner.startswith("staff-"):
                data["assignee_staff"] = owner
            else:
                data["assignee_role"] = "any"
            record, new = create_task_once(pf, data, actor="system:item_health")
            if new:
                created += 1
                alert_new_task(container, record)
        return created
    except Exception:
        return 0
