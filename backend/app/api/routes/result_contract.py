"""Result Diagnostics: what ONE query understood, called, returned and the
app actually rendered (Command Center), plus the app's render report."""
from __future__ import annotations

from typing import Dict, List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _require
from app.services import result_orchestrator

router = APIRouter(tags=["result-contract"])


class RenderedReport(BaseModel):
    trace_key: str = Field(min_length=6, max_length=64)
    sections: List[str] = Field(default_factory=list, max_length=20)
    hidden: Dict[str, str] = Field(default_factory=dict)


@router.post("/api/results/rendered")
def results_rendered(payload: RenderedReport, request: Request) -> dict:
    """The app says which sections it drew (no personal data: section
    names + reasons only). Unknown trace keys are ignored."""
    from app.services import rate_limit

    rate_limit.check(request, "results_rendered", limit=120)
    if len(payload.hidden) > 20:
        raise HTTPException(status_code=422, detail="too many reasons")
    ok = result_orchestrator.record_rendered(request.app.state.container, payload.trace_key, payload.sections,
                                             payload.hidden)
    return {"ok": ok}


@router.get("/admin/cc/results/diagnostics")
def result_diagnostics(request: Request, trace_key: str = "", q: str = "", limit: int = 20) -> dict:
    _require(request, "requests:view")
    return {"items": result_orchestrator.diagnostics(request.app.state.container, trace_key=trace_key, query=q,
                                                     limit=limit),
            "contract_version": result_orchestrator.CONTRACT_VERSION,
            "section_kinds": list(result_orchestrator.SECTION_KINDS)}
