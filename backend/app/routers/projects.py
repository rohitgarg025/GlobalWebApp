from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser
from app.services import project_service as svc
from app.services import quantity_sheet_service as floor_svc
from app.services.auth_deps import get_current_user, require_admin

router = APIRouter(prefix="/api", tags=["projects"])


class ProjectCreate(BaseModel):
    name: str
    code: str | None = None
    location: str | None = None
    client_name: str | None = None


class ProjectUpdate(BaseModel):
    name: str | None = None
    code: str | None = None
    location: str | None = None
    client_name: str | None = None
    status: str | None = None


@router.get("/projects")
def list_projects(
    include_archived: bool = Query(False),
    db: Session = Depends(get_db),
    _: AuthUser = Depends(get_current_user),
):
    return svc.list_projects(db, include_archived=include_archived)


@router.post("/projects", status_code=201)
def create_project(
    body: ProjectCreate,
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_admin),
):
    return svc.create_project(
        db,
        body.name,
        body.code,
        body.location,
        body.client_name,
        created_by=user.display_name or user.email,
    )


@router.patch("/projects/{project_id}")
def update_project(
    project_id: int,
    body: ProjectUpdate,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    return svc.update_project(
        db,
        project_id,
        body.name,
        body.code,
        body.location,
        body.client_name,
        body.status,
    )


@router.post("/projects/{project_id}/archive")
def archive_project(
    project_id: int,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    return svc.archive_project(db, project_id)


@router.delete("/projects/{project_id}", status_code=204)
def delete_project(
    project_id: int,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    svc.delete_project(db, project_id)


# ─── Floor management (admin writes, any auth user reads) ────────────────────

class FloorCreate(BaseModel):
    name: str
    display_order: int | None = None


class FloorReorder(BaseModel):
    floor_ids: list[int]


@router.get("/projects/{project_id}/floors")
def list_floors(
    project_id: int,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(get_current_user),
):
    return floor_svc.list_floors(db, project_id)


@router.post("/projects/{project_id}/floors", status_code=201)
def create_floor(
    project_id: int,
    body: FloorCreate,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    existing = floor_svc.list_floors(db, project_id)
    order = body.display_order if body.display_order is not None else len(existing)
    return floor_svc.create_floor(db, project_id, body.name.strip(), order)


@router.delete("/projects/floors/{floor_id}", status_code=204)
def delete_floor(
    floor_id: int,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    floor_svc.delete_floor(db, floor_id)


@router.put("/projects/{project_id}/floors/reorder")
def reorder_floors(
    project_id: int,
    body: FloorReorder,
    db: Session = Depends(get_db),
    _: AuthUser = Depends(require_admin),
):
    return floor_svc.reorder_floors(db, project_id, body.floor_ids)
