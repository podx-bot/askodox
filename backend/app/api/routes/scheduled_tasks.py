from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.services.scheduled_task_service import ScheduledTaskService

router = APIRouter(prefix="/tasks", tags=["Scheduled Tasks"])


class ScheduledTaskCreateRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=128)
    title: str = Field(min_length=1, max_length=160)
    prompt: str = Field(min_length=1, max_length=4000)
    kind: str = Field(default="reminder")
    run_at: str = Field(min_length=1)
    recurrence: str = Field(default="once")
    timezone: str = Field(default="UTC", min_length=1, max_length=64)
    condition: dict | None = None


class ScheduledTaskCancelRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=128)


def _service(request: Request) -> ScheduledTaskService:
    service = getattr(request.app.state.container, "scheduled_task_service", None)
    if service is None:
        database_path = request.app.state.container.settings.database_path
        service = ScheduledTaskService(database_path)
        request.app.state.container.scheduled_task_service = service
    return service


@router.post("")
def create_scheduled_task(payload: ScheduledTaskCreateRequest, request: Request) -> dict:
    try:
        task = _service(request).create(
            user_id=payload.user_id,
            title=payload.title,
            prompt=payload.prompt,
            kind=payload.kind,
            run_at=payload.run_at,
            recurrence=payload.recurrence,
            timezone_name=payload.timezone,
            condition=payload.condition,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {"status": "success", "task": task}


@router.get("")
def list_scheduled_tasks(
    request: Request,
    user_id: str = Query(min_length=1, max_length=128),
    include_disabled: bool = False,
) -> dict:
    tasks = _service(request).list(user_id=user_id, include_disabled=include_disabled)
    return {"status": "success", "tasks": tasks, "count": len(tasks)}


@router.get("/{task_id}")
def get_scheduled_task(task_id: str, request: Request, user_id: str = Query(min_length=1, max_length=128)) -> dict:
    try:
        task = _service(request).get(task_id=task_id, user_id=user_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Task not found") from error
    return {"status": "success", "task": task}


@router.post("/{task_id}/cancel")
def cancel_scheduled_task(task_id: str, payload: ScheduledTaskCancelRequest, request: Request) -> dict:
    try:
        task = _service(request).cancel(task_id=task_id, user_id=payload.user_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Task not found") from error
    return {"status": "success", "task": task}
