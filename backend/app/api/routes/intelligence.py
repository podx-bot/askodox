"""Round 2 intelligence APIs (deterministic, no paid AI calls).

GET  /api/intel/tax                  rules overview + sources (current tax year, GST structure)
POST /api/intel/tax/income           income-tax estimate (one regime or both compared)
POST /api/intel/gst/registration     does turnover require GST registration (by State)
POST /api/intel/gst/composition      composition-scheme eligibility + trade-off
POST /api/intel/gst/amount           GST on an amount (CGST+SGST or IGST)
GET  /api/intel/fraud                scam checklists (titles)
GET  /api/intel/fraud/{scheme_id}    one checklist with official reporting channels
POST /api/intel/tricks/{calculator}  smart-trick calculators over the user's own numbers

Public like discovery, rate-limited per client; nothing personal is stored.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services import fraud_awareness, rate_limit, smart_tricks, tax_intelligence

router = APIRouter(prefix="/api/intel", tags=["Intelligence"])


def _limit(request: Request) -> None:
    rate_limit.check(request, "intel", limit=60)


class IncomeTaxRequest(BaseModel):
    year: str = Field(default=tax_intelligence.CURRENT_TAX_YEAR, max_length=10)
    regime: str = Field(default="compare", pattern="^(new|old|compare)$")
    salary_income: float = Field(default=0, ge=0, le=1e12)
    other_income: float = Field(default=0, ge=0, le=1e12)
    deductions: float = Field(default=0, ge=0, le=1e12)
    age_band: str = Field(default="below_60", pattern="^(below_60|60_to_80|80_plus)$")
    resident: bool = True


class GstRegistrationRequest(BaseModel):
    turnover: float = Field(ge=0, le=1e13)
    supply: str = Field(pattern="^(goods|services|both)$")
    state: str = Field(min_length=2, max_length=60)


class CompositionRequest(BaseModel):
    turnover: float = Field(ge=0, le=1e13)
    business: str = Field(pattern="^(trader|manufacturer|restaurant|services)$")
    state: str = Field(min_length=2, max_length=60)
    interstate_outward: bool = False
    ecommerce_tcs: bool = False


class GstAmountRequest(BaseModel):
    amount: float = Field(ge=0, le=1e13)
    rate_percent: float = Field(ge=0, le=40)
    inclusive: bool = False
    interstate: bool = False


class TrickRequest(BaseModel):
    values: Dict[str, Any] = Field(default_factory=dict)
    options: Optional[List[Dict[str, Any]]] = Field(default=None, max_length=10)


def _bad(error: Exception) -> HTTPException:
    return HTTPException(status_code=422, detail=str(error))


@router.get("/tax")
def tax_overview(request: Request, language: str = "en") -> dict:
    _limit(request)
    return {"status": "success", **tax_intelligence.overview(language)}


@router.post("/tax/income")
def income_tax(payload: IncomeTaxRequest, request: Request) -> dict:
    _limit(request)
    args = payload.model_dump(exclude={"regime"})
    try:
        if payload.regime == "compare":
            return {"status": "success", "comparison": tax_intelligence.compare_regimes(**args)}
        return {"status": "success", "result": tax_intelligence.compute_income_tax(regime=payload.regime, **args)}
    except tax_intelligence.TaxInputError as error:
        raise _bad(error) from error


@router.post("/gst/registration")
def gst_registration(payload: GstRegistrationRequest, request: Request) -> dict:
    _limit(request)
    try:
        return {"status": "success", "result": tax_intelligence.gst_registration_check(**payload.model_dump())}
    except tax_intelligence.TaxInputError as error:
        raise _bad(error) from error


@router.post("/gst/composition")
def gst_composition(payload: CompositionRequest, request: Request) -> dict:
    _limit(request)
    try:
        return {"status": "success", "result": tax_intelligence.composition_check(**payload.model_dump())}
    except tax_intelligence.TaxInputError as error:
        raise _bad(error) from error


@router.post("/gst/amount")
def gst_amount(payload: GstAmountRequest, request: Request) -> dict:
    _limit(request)
    try:
        return {"status": "success", "result": tax_intelligence.gst_amount(**payload.model_dump())}
    except tax_intelligence.TaxInputError as error:
        raise _bad(error) from error


@router.get("/fraud")
def fraud_list(request: Request, language: str = "en") -> dict:
    _limit(request)
    return {"status": "success", "schemes": fraud_awareness.list_schemes(language),
            "verified_on": fraud_awareness.VERIFIED_ON}


@router.get("/fraud/{scheme_id}")
def fraud_detail(scheme_id: str, request: Request, language: str = "en") -> dict:
    _limit(request)
    found = fraud_awareness.scheme(scheme_id, language)
    if found is None:
        raise HTTPException(status_code=404, detail="unknown scheme")
    return {"status": "success", "scheme": found}


@router.post("/tricks/{calculator}")
def trick(calculator: str, payload: TrickRequest, request: Request) -> dict:
    _limit(request)
    fn = smart_tricks.CALCULATORS.get(calculator)
    if fn is None:
        raise HTTPException(status_code=404, detail="unknown calculator")
    try:
        if calculator in ("unit_price", "total_cost"):
            if not payload.options:
                raise smart_tricks.TrickInputError("options are required")
            extra = {"years": payload.values.get("years")} if calculator == "total_cost" else {}
            result = fn(payload.options, **extra)
        else:
            result = fn(**payload.values)
    except smart_tricks.TrickInputError as error:
        raise _bad(error) from error
    except TypeError as error:
        raise HTTPException(status_code=422, detail="missing or unknown values for this calculator") from error
    return {"status": "success", "result": result}
