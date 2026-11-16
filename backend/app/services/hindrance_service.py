"""Hindrance register CRUD for a project."""
from __future__ import annotations

from datetime import date, datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.models import PmActivity, PmHindrance
from app.services.project_service import get_project, require_active_project

HINDRANCE_TYPES = ("weather", "drawing", "material", "labour", "client", "other")
STATUSES = ("open", "closed")


def _iso(d: date | None) -> str | None:
    return d.isoformat() if d else None


def _parse_date(value) -> date | None:
    if value is None or value == "":
        return None
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value)[:10])


def _delay_days(start: date | None, end: date | None, explicit: int | None) -> int | None:
    if explicit is not None:
        return explicit
    if start and end:
        return max(0, (end - start).days + 1)
    return None


def _to_dict(h: PmHindrance, activity_code: str | None, activity_name: str | None) -> dict:
    return {
        "id": h.id,
        "project_id": h.project_id,
        "activity_id": h.activity_id,
        "activity_code": activity_code,
        "activity_name": activity_name,
        "raised_on": _iso(h.raised_on),
        "type": h.type,
        "description": h.description,
        "start_date": _iso(h.start_date),
        "end_date": _iso(h.end_date),
        "delay_days": h.delay_days,
        "status": h.status,
        "remarks": h.remarks,
        "raised_by": h.raised_by,
        "created_at": h.created_at.isoformat() if h.created_at else None,
    }


def _activity_label(db: Session, activity_id: int | None) -> tuple[str | None, str | None]:
    if not activity_id:
        return None, None
    act = db.query(PmActivity).filter_by(id=activity_id).first()
    if not act:
        return None, None
    return act.code, act.name


def list_hindrances(db: Session, project_id: int) -> list[dict]:
    get_project(db, project_id)
    rows = (
        db.query(PmHindrance)
        .filter_by(project_id=project_id)
        .order_by(PmHindrance.raised_on.desc(), PmHindrance.id.desc())
        .all()
    )
    out = []
    for h in rows:
        code, name = _activity_label(db, h.activity_id)
        out.append(_to_dict(h, code, name))
    return out


def create_hindrance(
    db: Session,
    project_id: int,
    raised_on,
    type: str,
    description: str,
    activity_id: int | None,
    start_date,
    end_date,
    delay_days: int | None,
    status: str,
    remarks: str | None,
    raised_by: str | None,
) -> dict:
    require_active_project(db, project_id)
    description = (description or "").strip()
    if not description:
        raise HTTPException(422, "Description is required")
    type = (type or "").strip().lower()
    if type not in HINDRANCE_TYPES:
        raise HTTPException(422, f"Type must be one of: {', '.join(HINDRANCE_TYPES)}")
    status = (status or "open").strip().lower()
    if status not in STATUSES:
        raise HTTPException(422, "Status must be open or closed")
    raised = _parse_date(raised_on) or date.today()
    start = _parse_date(start_date)
    end = _parse_date(end_date)
    if activity_id:
        act = db.query(PmActivity).filter_by(id=activity_id, project_id=project_id).first()
        if not act:
            raise HTTPException(400, "Linked activity not found on this project")
    row = PmHindrance(
        project_id=project_id,
        activity_id=activity_id,
        raised_on=raised,
        type=type,
        description=description,
        start_date=start,
        end_date=end,
        delay_days=_delay_days(start, end, delay_days),
        status=status,
        remarks=(remarks or "").strip() or None,
        raised_by=raised_by,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    code, name = _activity_label(db, row.activity_id)
    return _to_dict(row, code, name)


def update_hindrance(
    db: Session,
    hindrance_id: int,
    raised_on=None,
    type: str | None = None,
    description: str | None = None,
    activity_id: int | None = None,
    clear_activity: bool = False,
    start_date=None,
    end_date=None,
    delay_days: int | None = None,
    status: str | None = None,
    remarks: str | None = None,
) -> dict:
    row = db.query(PmHindrance).filter_by(id=hindrance_id).first()
    if not row:
        raise HTTPException(404, "Hindrance not found")
    require_active_project(db, row.project_id)
    if raised_on is not None:
        row.raised_on = _parse_date(raised_on) or row.raised_on
    if type is not None:
        type = type.strip().lower()
        if type not in HINDRANCE_TYPES:
            raise HTTPException(422, f"Type must be one of: {', '.join(HINDRANCE_TYPES)}")
        row.type = type
    if description is not None:
        description = description.strip()
        if not description:
            raise HTTPException(422, "Description is required")
        row.description = description
    if clear_activity:
        row.activity_id = None
    elif activity_id is not None:
        act = db.query(PmActivity).filter_by(id=activity_id, project_id=row.project_id).first()
        if not act:
            raise HTTPException(400, "Linked activity not found on this project")
        row.activity_id = activity_id
    if start_date is not None:
        row.start_date = _parse_date(start_date)
    if end_date is not None:
        row.end_date = _parse_date(end_date)
    if delay_days is not None:
        row.delay_days = delay_days
    else:
        row.delay_days = _delay_days(row.start_date, row.end_date, None)
    if status is not None:
        status = status.strip().lower()
        if status not in STATUSES:
            raise HTTPException(422, "Status must be open or closed")
        row.status = status
    if remarks is not None:
        row.remarks = remarks.strip() or None
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    code, name = _activity_label(db, row.activity_id)
    return _to_dict(row, code, name)


def delete_hindrance(db: Session, hindrance_id: int) -> None:
    row = db.query(PmHindrance).filter_by(id=hindrance_id).first()
    if not row:
        raise HTTPException(404, "Hindrance not found")
    db.delete(row)
    db.commit()
