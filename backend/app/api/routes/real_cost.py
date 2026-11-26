"""Real cost of a choice (owner 2026-11-26): near vs far, pickup vs delivery -- one total per option.

Pure arithmetic (app/services/real_cost.py): no sign-in needed, nothing stored, rate limited like other public calls.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services import rate_limit, real_cost

router = APIRouter(tags=["Real cost"])


class RealCostIn(BaseModel):
    options: List[Dict[str, Any]] = Field(min_length=2, max_length=real_cost.MAX_OPTIONS)
    assumptions: Optional[Dict[str, Any]] = None
    language: str = Field(default="en", max_length=5)


@router.post("/api/real-cost/compare")
def compare(body: RealCostIn, request: Request) -> dict:
    rate_limit.check(request, "real_cost", limit=60)
    try:
        result = real_cost.compare(body.options, body.assumptions)
    except real_cost.RealCostError as error:
        raise HTTPException(status_code=422, detail=str(error))
    result["summary"] = real_cost.summary(result, te=body.language.lower().startswith("te"))
    return result
