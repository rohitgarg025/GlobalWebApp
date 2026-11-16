import json
import shutil

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, Response, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser, TakeoffJob
from app.services.auth_deps import require_module
from app.services.modules import MODULE_QUANTITY_TAKEOFF
from app.services.takeoff import jobs
from app.services.takeoff.export import build_sheet
from app.services.takeoff.measure import ACTIVITIES

router = APIRouter(
    prefix="/api/quantity-takeoff",
    tags=["quantity-takeoff"],
    dependencies=[Depends(require_module(MODULE_QUANTITY_TAKEOFF))],
)


class AnalyseBody(BaseModel):
    floor_layout: str
    floor_height_m: float | None = None
    default_slab_mm: int | None = None


class RowsBody(BaseModel):
    activity: str
    rows: list[dict]


def _job(db: Session, job_id: int) -> TakeoffJob:
    job = db.get(TakeoffJob, job_id)
    if not job:
        raise HTTPException(404, "Takeoff not found")
    return job


@router.get("/jobs")
def list_jobs(db: Session = Depends(get_db)):
    rows = db.query(TakeoffJob).order_by(TakeoffJob.id.desc()).limit(50).all()
    return [jobs.job_dict(j, full=False) for j in rows]


@router.post("/jobs", status_code=201)
async def upload(
    background: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_QUANTITY_TAKEOFF)),
):
    job = await jobs.create_job(db, file, user.display_name or user.email)
    background.add_task(jobs.prepare, job.id)
    return jobs.job_dict(job)


@router.get("/jobs/{job_id}")
def get_job(job_id: int, db: Session = Depends(get_db)):
    return jobs.job_dict(_job(db, job_id))


@router.post("/jobs/{job_id}/analyse")
def analyse(job_id: int, body: AnalyseBody, background: BackgroundTasks, db: Session = Depends(get_db)):
    job = _job(db, job_id)
    jobs.start_analysis(db, job, body.floor_layout, body.floor_height_m, body.default_slab_mm)
    background.add_task(jobs.analyse, job.id)
    return jobs.job_dict(job)


@router.put("/jobs/{job_id}/rows")
def save_rows(job_id: int, body: RowsBody, db: Session = Depends(get_db)):
    return jobs.save_rows(db, _job(db, job_id), body.activity, body.rows)


@router.get("/jobs/{job_id}/export")
def export(
    job_id: int,
    activity: str = Query("concrete"),
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_QUANTITY_TAKEOFF)),
):
    job = _job(db, job_id)
    if job.status != "done":
        raise HTTPException(409, "The takeoff isn't ready yet.")
    if activity not in ACTIVITIES:
        raise HTTPException(422, "Unknown activity.")
    ai = json.loads(job.ai_json or "{}")
    data, filename = build_sheet(
        drawing_name=job.filename.rsplit(".", 1)[0],
        floor=job.floor_title or "",
        activity=activity,
        rows=json.loads(job.rows_json or "{}").get(activity, []),
        members=json.loads(job.members_json or "{}"),
        ai_notes=ai.get("notes", []),
        missing=ai.get("missing_info", []),
        prepared_by=user.display_name or user.email,
    )
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.delete("/jobs/{job_id}", status_code=204)
def delete_job(job_id: int, db: Session = Depends(get_db)):
    job = _job(db, job_id)
    shutil.rmtree(jobs.job_dir(job.id), ignore_errors=True)
    db.delete(job)
    db.commit()
