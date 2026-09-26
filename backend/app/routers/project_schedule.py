from datetime import date

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser
from app.services import schedule_service as svc
from app.services.auth_deps import require_module
from app.services.modules import MODULE_PROJECT_SCHEDULE

router = APIRouter(
    prefix="/api/project-schedule",
    tags=["project-schedule"],
    dependencies=[Depends(require_module(MODULE_PROJECT_SCHEDULE))],
)


class ActivityCreate(BaseModel):
    name: str
    code: str
    row_type: str = "activity"  # activity | group
    duration_days: int | None = None  # groups roll up from children
    start_date: date | None = None
    parent_id: int | None = None
    floor_id: int | None = None
    predecessor_id: int | None = None
    lag_days: int = 0
    quantity: float | None = None
    unit: str | None = None


class ActivityUpdate(BaseModel):
    name: str | None = None
    code: str | None = None
    duration_days: int | None = None
    start_date: date | None = None
    start_mode: str | None = None
    predecessor_id: int | None = None
    lag_days: int | None = None
    quantity: float | None = None
    unit: str | None = None
    clear_predecessor: bool = False
    clear_quantity: bool = False
    parent_id: int | None = None
    clear_parent: bool = False
    floor_id: int | None = None


class ReorderBody(BaseModel):
    activity_ids: list[int]


@router.get("/projects/{project_id}/schedule")
def get_schedule(project_id: int, db: Session = Depends(get_db)):
    return svc.get_schedule(db, project_id)


@router.post("/projects/{project_id}/activities", status_code=201)
def create_activity(
    project_id: int,
    body: ActivityCreate,
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_PROJECT_SCHEDULE)),
):
    return svc.create_activity(
        db,
        project_id,
        body.name,
        body.code,
        body.duration_days,
        body.start_date,
        body.predecessor_id,
        body.lag_days,
        body.quantity,
        body.unit,
        created_by=user.display_name or user.email,
        row_type=body.row_type,
        parent_id=body.parent_id,
        floor_id=body.floor_id,
    )


@router.patch("/activities/{activity_id}")
def update_activity(activity_id: int, body: ActivityUpdate, db: Session = Depends(get_db)):
    return svc.update_activity(
        db,
        activity_id,
        name=body.name,
        code=body.code,
        duration_days=body.duration_days,
        start_date=body.start_date,
        start_mode=body.start_mode,
        predecessor_id=body.predecessor_id,
        lag_days=body.lag_days,
        quantity=body.quantity,
        unit=body.unit,
        clear_predecessor=body.clear_predecessor,
        clear_quantity=body.clear_quantity,
        parent_id=body.parent_id,
        clear_parent=body.clear_parent,
        floor_id=body.floor_id,
    )


@router.delete("/activities/{activity_id}", status_code=204)
def delete_activity(activity_id: int, db: Session = Depends(get_db)):
    svc.delete_activity(db, activity_id)


@router.put("/projects/{project_id}/activities/reorder")
def reorder(project_id: int, body: ReorderBody, db: Session = Depends(get_db)):
    return svc.reorder_activities(db, project_id, body.activity_ids)
