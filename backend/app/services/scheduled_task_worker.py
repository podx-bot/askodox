from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any, Callable

from app.services.scheduled_task_delivery_service import ScheduledTaskDeliveryService
from app.services.scheduled_task_service import ScheduledTaskService

ConditionEvaluator = Callable[[dict[str, Any]], bool]


class ScheduledTaskWorker:
    """Claims due scheduled tasks and delivers them safely into ASKODOX in-app inbox."""

    def __init__(
        self,
        *,
        tasks: ScheduledTaskService,
        deliveries: ScheduledTaskDeliveryService,
        condition_evaluator: ConditionEvaluator | None = None,
    ) -> None:
        self.tasks = tasks
        self.deliveries = deliveries
        self.condition_evaluator = condition_evaluator

    def run_once(self, *, now: datetime | None = None, limit: int = 100) -> dict[str, int]:
        instant = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        claimed = self.tasks.claim_due(now=instant, limit=limit)
        summary = {"claimed": len(claimed), "delivered": 0, "condition_false": 0, "failed": 0}

        for task in claimed:
            token = str(task["claim_token"])
            scheduled_for = str(task["scheduled_for"])
            status = "failed"
            try:
                if task["kind"] == "condition_watch":
                    if self.condition_evaluator is None:
                        raise RuntimeError("Condition evaluator is not configured")
                    if not bool(self.condition_evaluator(task)):
                        status = "condition_false"
                    else:
                        self.deliveries.deliver(task=task, scheduled_for=scheduled_for)
                        status = "delivered"
                else:
                    self.deliveries.deliver(task=task, scheduled_for=scheduled_for)
                    status = "delivered"
            except Exception:
                status = "failed"

            self.tasks.mark_run(
                task_id=str(task["id"]),
                status=status,
                ran_at=instant,
                claim_token=token,
            )
            summary[status] += 1

        return summary


class ScheduledTaskRunner:
    """Small lifecycle wrapper for continuous worker execution inside FastAPI."""

    def __init__(self, worker: ScheduledTaskWorker, *, interval_seconds: float = 30.0) -> None:
        self.worker = worker
        self.interval_seconds = max(5.0, interval_seconds)
        self._stop = asyncio.Event()
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._stop = asyncio.Event()
            self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        self._stop.set()
        task = self._task
        if task is None:
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        self._task = None

    async def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                await asyncio.to_thread(self.worker.run_once)
            except Exception:
                # The runner must survive a transient database/provider failure.
                pass
            try:
                await asyncio.wait_for(self._stop.wait(), timeout=self.interval_seconds)
            except asyncio.TimeoutError:
                continue
