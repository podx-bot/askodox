"""Work Mode team routes (see services/work_teams.py). Every call needs sign-in."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services.work_teams import TeamError, WorkTeams

router = APIRouter(prefix="/api/work/team", tags=["work-mode"])


def teams(container: Any) -> WorkTeams:
    service = getattr(container, "work_teams", None)
    path = container.settings.database_path
    if service is None or service.db_path != path:
        service = WorkTeams(path)
        container.work_teams = service
    return service


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except TeamError as error:
        raise HTTPException(status_code=error.status, detail=error.code) from None


class CreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    team_name: str = Field(default="", max_length=60)
    job: str = Field(min_length=1, max_length=40)
    size: str = Field(default="medium", max_length=10)
    wear: str = Field(default="lungi", max_length=10)


class JoinIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)
    name: str = Field(min_length=1, max_length=40)
    wear: str = Field(default="lungi", max_length=10)


class StepsIn(BaseModel):
    day: str = Field(min_length=10, max_length=10)
    steps: int = Field(ge=0, le=1_000_000)


@router.get("")
def mine(request: Request, day: str = "") -> dict:
    from app.services import rate_limit
    from app.services.work_teams import _now

    user_id = _authenticated_app_user(request)
    rate_limit.check(request, "work-team-read", limit=120)
    return _call(teams(request.app.state.container).mine, user_id, day=day or _now().date().isoformat())


@router.post("")
def create(payload: CreateIn, request: Request) -> dict:
    from app.services import rate_limit

    user_id = _authenticated_app_user(request)
    rate_limit.check(request, "work-team-write", limit=20)
    return _call(teams(request.app.state.container).create, user_id, name=payload.name, team_name=payload.team_name,
                 job=payload.job, size=payload.size, wear=payload.wear)


@router.post("/join")
def join(payload: JoinIn, request: Request) -> dict:
    from app.services import rate_limit

    user_id = _authenticated_app_user(request)
    rate_limit.check(request, "work-team-join", limit=20)
    return _call(teams(request.app.state.container).join, user_id, code=payload.code, name=payload.name,
                 wear=payload.wear)


@router.put("/steps")
def steps(payload: StepsIn, request: Request) -> dict:
    from app.services import rate_limit

    user_id = _authenticated_app_user(request)
    rate_limit.check(request, "work-team-steps", limit=120)
    return _call(teams(request.app.state.container).report_steps, user_id, day=payload.day, steps=payload.steps)


@router.post("/leave")
def leave(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    return teams(request.app.state.container).leave(user_id)
