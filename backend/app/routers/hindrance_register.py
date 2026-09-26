from datetime import date

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser
from app.services import hindrance_service as svc
from app.services import schedule_service as schedule_svc
from app.services.auth_deps import require_module
from app.services.modules import MODULE_HINDRANCE_REGISTER

router = APIRouter(
    prefix="/api/hindrance-register",
    tags=["hindrance-register"],
    dependencies=[Depends(require_module(MODULE_HINDRANCE_REGISTER))],
)


class HindranceCreate(BaseModel):
    raised_on: date | None = None
    type: str
    description: str
    activity_id: int | None = None
    start_date: date | None = None
    end_date: date | None = None
    delay_days: int | None = None
    status: str = "open"
    remarks: str | None = None


class HindranceUpdate(BaseModel):
    raised_on: date | None = None
    type: str | None = None
    description: str | None = None
    activity_id: int | None = None
    clear_activity: bool = False
    start_date: date | None = None
    end_date: date | None = None
    delay_days: int | None = None
    status: str | None = None
    remarks: str | None = None


@router.get("/projects/{project_id}/hindrances")
def list_hindrances(project_id: int, db: Session = Depends(get_db)):
    return svc.list_hindrances(db, project_id)


@router.get("/projects/{project_id}/activity-options")
def activity_options(project_id: int, db: Session = Depends(get_db)):
    return schedule_svc.activity_options(db, project_id)


@router.post("/projects/{project_id}/hindrances", status_code=201)
def create_hindrance(
    project_id: int,
    body: HindranceCreate,
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_HINDRANCE_REGISTER)),
):
    return svc.create_hindrance(
        db,
        project_id,
        body.raised_on,
        body.type,
        body.description,
        body.activity_id,
        body.start_date,
        body.end_date,
        body.delay_days,
        body.status,
        body.remarks,
        raised_by=user.display_name or user.email,
    )


@router.patch("/hindrances/{hindrance_id}")
def update_hindrance(hindrance_id: int, body: HindranceUpdate, db: Session = Depends(get_db)):
    return svc.update_hindrance(
        db,
        hindrance_id,
        raised_on=body.raised_on,
        type=body.type,
        description=body.description,
        activity_id=body.activity_id,
        clear_activity=body.clear_activity,
        start_date=body.start_date,
        end_date=body.end_date,
        delay_days=body.delay_days,
        status=body.status,
        remarks=body.remarks,
    )


@router.delete("/hindrances/{hindrance_id}", status_code=204)
def delete_hindrance(hindrance_id: int, db: Session = Depends(get_db)):
    svc.delete_hindrance(db, hindrance_id)
