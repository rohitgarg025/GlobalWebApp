from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.services import quantity_sheet_service as svc

router = APIRouter(prefix="/api/quantity-sheet", tags=["quantity-sheet"])


# ─── Pydantic schemas ────────────────────────────────────────────────────────

class ProjectCreate(BaseModel):
    name: str


class FloorCreate(BaseModel):
    name: str
    display_order: int = 0


class FloorReorder(BaseModel):
    floor_ids: list[int]


class ActivityCreate(BaseModel):
    name: str
    unit: str


class EntryRow(BaseModel):
    activity_id: int
    floor_id: int
    total_estimated_qty: float
    estimate_actual_qty_till_date: float
    actual_qty: float
    justification: str | None = None
    baseline_change_reason: str | None = None


class SubmitRequest(BaseModel):
    month: str               # YYYY-MM
    submitted_by: str = "Unknown"
    rows: list[EntryRow]


# ─── Projects ────────────────────────────────────────────────────────────────

@router.get("/projects")
def list_projects(db: Session = Depends(get_db)):
    return svc.list_projects(db)


@router.post("/projects", status_code=201)
def create_project(body: ProjectCreate, db: Session = Depends(get_db)):
    return svc.create_project(db, body.name)


@router.delete("/projects/{project_id}", status_code=204)
def delete_project(project_id: int, db: Session = Depends(get_db)):
    svc.delete_project(db, project_id)


# ─── Floors ──────────────────────────────────────────────────────────────────

@router.get("/projects/{project_id}/floors")
def list_floors(project_id: int, db: Session = Depends(get_db)):
    return svc.list_floors(db, project_id)


@router.post("/projects/{project_id}/floors", status_code=201)
def create_floor(project_id: int, body: FloorCreate, db: Session = Depends(get_db)):
    return svc.create_floor(db, project_id, body.name, body.display_order)


@router.delete("/floors/{floor_id}", status_code=204)
def delete_floor(floor_id: int, db: Session = Depends(get_db)):
    svc.delete_floor(db, floor_id)


@router.put("/projects/{project_id}/floors/reorder")
def reorder_floors(project_id: int, body: FloorReorder, db: Session = Depends(get_db)):
    return svc.reorder_floors(db, project_id, body.floor_ids)


# ─── Activities ───────────────────────────────────────────────────────────────

@router.get("/activities")
def list_activities(db: Session = Depends(get_db)):
    return svc.list_activities(db)


@router.post("/activities", status_code=201)
def create_activity(body: ActivityCreate, db: Session = Depends(get_db)):
    return svc.create_activity(db, body.name, body.unit)


@router.delete("/activities/{activity_id}", status_code=204)
def delete_activity(activity_id: int, db: Session = Depends(get_db)):
    svc.delete_activity(db, activity_id)


# ─── Data ─────────────────────────────────────────────────────────────────────

@router.get("/projects/{project_id}/data")
def get_project_data(
    project_id: int,
    month: str = Query(..., description="YYYY-MM"),
    db: Session = Depends(get_db),
):
    return svc.get_project_data(db, project_id, month)


@router.post("/projects/{project_id}/submit")
def submit_entries(project_id: int, body: SubmitRequest, db: Session = Depends(get_db)):
    return svc.submit_entries(
        db,
        project_id=project_id,
        month=body.month,
        submitted_by=body.submitted_by,
        rows=[r.model_dump() for r in body.rows],
    )


# ─── Overruns ────────────────────────────────────────────────────────────────

@router.get("/overruns")
def get_overruns(
    project_id: int | None = Query(None),
    db: Session = Depends(get_db),
):
    return svc.get_overruns(db, project_id)


# ─── Cross-project comparison ─────────────────────────────────────────────────

@router.get("/compare")
def get_comparison(
    activity_id: int = Query(...),
    month: str = Query(..., description="YYYY-MM"),
    db: Session = Depends(get_db),
):
    return svc.get_comparison(db, activity_id, month)


# ─── Baseline history ─────────────────────────────────────────────────────────

@router.get("/baseline-history")
def get_baseline_history(
    project_id: int = Query(...),
    activity_id: int = Query(...),
    floor_id: int = Query(...),
    db: Session = Depends(get_db),
):
    return svc.get_baseline_history(db, project_id, activity_id, floor_id)


# ─── Excel export ─────────────────────────────────────────────────────────────

@router.get("/projects/{project_id}/export")
def export_excel(
    project_id: int,
    month: str = Query(..., description="YYYY-MM"),
    db: Session = Depends(get_db),
):
    data = svc.export_to_excel(db, project_id, month)
    filename = f"quantity_sheet_{project_id}_{month}.xlsx"
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
