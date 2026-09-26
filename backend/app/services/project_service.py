"""Company-wide project master. Writes are admin-only at the router layer."""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.models import (
    Project,
    QsFloor,
    QsBaseline,
    QsMonthlyEntry,
    PmActivity,
    PmHindrance,
)


def project_to_dict(p: Project) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "code": p.code,
        "location": p.location,
        "client_name": p.client_name,
        "status": p.status,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "created_by": p.created_by,
    }


def get_project(db: Session, project_id: int) -> Project:
    proj = db.query(Project).filter_by(id=project_id).first()
    if not proj:
        raise HTTPException(404, "Project not found")
    return proj


def require_active_project(db: Session, project_id: int) -> Project:
    proj = get_project(db, project_id)
    if proj.status != "active":
        raise HTTPException(400, "Project is archived")
    return proj


def list_projects(db: Session, include_archived: bool = False) -> list[dict]:
    q = db.query(Project)
    if not include_archived:
        q = q.filter(Project.status == "active")
    rows = q.order_by(Project.name).all()
    return [project_to_dict(r) for r in rows]


def create_project(
    db: Session,
    name: str,
    code: str | None,
    location: str | None,
    client_name: str | None,
    created_by: str | None,
) -> dict:
    name = (name or "").strip()
    if not name:
        raise HTTPException(422, "Project name is required")
    if db.query(Project).filter_by(name=name).first():
        raise HTTPException(400, f"Project '{name}' already exists")
    code = (code or "").strip() or None
    if code and db.query(Project).filter_by(code=code).first():
        raise HTTPException(400, f"Project code '{code}' already exists")
    proj = Project(
        name=name,
        code=code,
        location=(location or "").strip() or None,
        client_name=(client_name or "").strip() or None,
        status="active",
        created_by=created_by,
    )
    db.add(proj)
    db.commit()
    db.refresh(proj)
    return project_to_dict(proj)


def update_project(
    db: Session,
    project_id: int,
    name: str | None,
    code: str | None,
    location: str | None,
    client_name: str | None,
    status: str | None,
) -> dict:
    proj = get_project(db, project_id)
    if name is not None:
        name = name.strip()
        if not name:
            raise HTTPException(422, "Project name is required")
        clash = db.query(Project).filter(Project.name == name, Project.id != project_id).first()
        if clash:
            raise HTTPException(400, f"Project '{name}' already exists")
        proj.name = name
    if code is not None:
        code = code.strip() or None
        if code:
            clash = db.query(Project).filter(Project.code == code, Project.id != project_id).first()
            if clash:
                raise HTTPException(400, f"Project code '{code}' already exists")
        proj.code = code
    if location is not None:
        proj.location = location.strip() or None
    if client_name is not None:
        proj.client_name = client_name.strip() or None
    if status is not None:
        if status not in ("active", "archived"):
            raise HTTPException(422, "Status must be active or archived")
        proj.status = status
    db.commit()
    db.refresh(proj)
    return project_to_dict(proj)


def archive_project(db: Session, project_id: int) -> dict:
    return update_project(db, project_id, None, None, None, None, "archived")


def delete_project(db: Session, project_id: int) -> None:
    proj = get_project(db, project_id)
    has_children = (
        db.query(QsFloor).filter_by(project_id=project_id).first()
        or db.query(QsBaseline).filter_by(project_id=project_id).first()
        or db.query(QsMonthlyEntry).filter_by(project_id=project_id).first()
        or db.query(PmActivity).filter_by(project_id=project_id).first()
        or db.query(PmHindrance).filter_by(project_id=project_id).first()
    )
    if has_children:
        raise HTTPException(
            409,
            "Project has related data. Archive it instead of deleting.",
        )
    db.delete(proj)
    db.commit()
