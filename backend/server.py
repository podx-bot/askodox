from app.api.app_factory import create_app
from app.api.routes.connected_actions import router as connected_actions_router
from app.api.routes.public_home import router as public_home_router
from app.api.routes.universal_deals import router as universal_deals_router
from app.services.connected_action_service import ConnectedActionService
from app.services.scheduled_task_condition_evaluator import ScheduledTaskConditionEvaluator
from app.services.scheduled_task_delivery_service import ScheduledTaskDeliveryService
from app.services.scheduled_task_worker import ScheduledTaskRunner, ScheduledTaskWorker

app = create_app()
app.include_router(public_home_router)
app.include_router(universal_deals_router)
app.include_router(connected_actions_router)

container = app.state.container
container.connected_action_service = ConnectedActionService(container.settings.database_path)
container.scheduled_task_delivery_service = ScheduledTaskDeliveryService(
    container.settings.database_path
)
container.scheduled_task_condition_evaluator = ScheduledTaskConditionEvaluator(
    container.oasat_live_research_service
)
container.scheduled_task_worker = ScheduledTaskWorker(
    tasks=container.scheduled_task_service,
    deliveries=container.scheduled_task_delivery_service,
    condition_evaluator=container.scheduled_task_condition_evaluator,
)
container.scheduled_task_runner = ScheduledTaskRunner(container.scheduled_task_worker)


@app.on_event("startup")
async def start_scheduled_task_runner() -> None:
    container.scheduled_task_runner.start()


@app.on_event("shutdown")
async def stop_scheduled_task_runner() -> None:
    await container.scheduled_task_runner.stop()
