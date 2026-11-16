import json
import shutil

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Response, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser, BbsJob
from app.services.auth_deps import require_module
from app.services.bbs import export, jobs
from app.services.modules import MODULE_BBS

router = APIRouter(
    prefix="/api/bbs",
    tags=["bbs"],
    dependencies=[Depends(require_module(MODULE_BBS))],
)


class SettingsBody(BaseModel):
    lap_factor: int | None = None
    cover_beam_mm: int | None = None
    default_stock_mm: int = 12000
    stock_mm: dict[str, int] = {}
    min_reuse_mm: int = 1000
    offcuts_mm: dict[str, list[int]] = {}
    multiplier: int = 1


class LinesBody(BaseModel):
    lines: list[dict]


def _job(db: Session, job_id: int) -> BbsJob:
    job = db.get(BbsJob, job_id)
    if not job:
        raise HTTPException(404, "BBS not found")
    return job


@router.get("/jobs")
def list_jobs(db: Session = Depends(get_db)):
    return [jobs.job_dict(j, full=False) for j in db.query(BbsJob).order_by(BbsJob.id.desc()).limit(50)]


@router.post("/jobs", status_code=201)
async def upload(
    background: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_BBS)),
):
    job = await jobs.create_job(db, file, user.display_name or user.email)
    background.add_task(jobs.prepare, job.id)
    return jobs.job_dict(job)


@router.get("/jobs/{job_id}")
def get_job(job_id: int, db: Session = Depends(get_db)):
    return jobs.job_dict(_job(db, job_id))


@router.post("/jobs/{job_id}/compute")
def compute(job_id: int, body: SettingsBody, background: BackgroundTasks, db: Session = Depends(get_db)):
    job = _job(db, job_id)
    jobs.start_compute(db, job, body.model_dump())
    background.add_task(jobs.compute, job.id)
    return jobs.job_dict(job)


@router.put("/jobs/{job_id}/lines")
def save_lines(job_id: int, body: LinesBody, background: BackgroundTasks, db: Session = Depends(get_db)):
    job = _job(db, job_id)
    jobs.save_lines(db, job, body.lines)
    background.add_task(jobs.compute, job.id, True)
    return jobs.job_dict(job)


@router.get("/jobs/{job_id}/export")
def export_xlsx(job_id: int, db: Session = Depends(get_db),
                user: AuthUser = Depends(require_module(MODULE_BBS))):
    job = _job(db, job_id)
    if job.status != "done":
        raise HTTPException(409, "The BBS isn't ready yet.")
    lines = json.loads(job.lines_json or "[]")
    plans = json.loads(job.plan_json or "{}")
    data, filename = export.build(
        drawing=job.filename.rsplit(".", 1)[0], lines=lines, plans=plans,
        summary=jobs.summary(lines, plans), notes=json.loads(job.notes_json or "{}"),
        settings=json.loads(job.settings_json or "{}"), issues=json.loads(job.issues_json or "[]"),
        prepared_by=user.display_name or user.email,
    )
    return Response(content=data,
                    media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": f'attachment; filename="{filename}"'})


@router.delete("/jobs/{job_id}", status_code=204)
def delete_job(job_id: int, db: Session = Depends(get_db)):
    job = _job(db, job_id)
    shutil.rmtree(jobs.job_dir(job.id), ignore_errors=True)
    db.delete(job)
    db.commit()
