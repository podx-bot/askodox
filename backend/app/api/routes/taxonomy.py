"""Universal category hierarchy API (see app/services/taxonomy.py).

GET /api/taxonomy/resolve?q=   the deepest category named in the words, its
                               path, inherited capabilities and the actions to
                               offer (customer or provider side)
GET /api/taxonomy/tree         every ACTIVE node with its effective capabilities
Public and rate-limited: it reads only staff-configured categories.
"""
from __future__ import annotations

from fastapi import APIRouter, Request

router = APIRouter(prefix="/api/taxonomy", tags=["taxonomy"])


def taxonomy(container):
    from app.api.routes.platform import platform
    from app.services.taxonomy import taxonomy_from_records

    return taxonomy_from_records(platform(container).resources.repo.list("taxonomy_nodes"))


@router.get("/resolve")
def resolve(request: Request, q: str = "") -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "taxonomy", limit=60)
    return taxonomy(request.app.state.container).resolve(q[:300])


@router.get("/tree")
def tree(request: Request) -> dict:
    tax = taxonomy(request.app.state.container)
    return {"items": [tax.effective(k) | {"parent": (tax.nodes[k].get("parent") or None)} for k in tax.nodes]}
