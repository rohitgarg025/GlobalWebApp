from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthUser
from app.services import drawing_service as svc
from app.services.auth_deps import require_module
from app.services.modules import MODULE_DRAWING_REGISTER

router = APIRouter(
    prefix="/api/drawing-register",
    tags=["drawing-register"],
    dependencies=[Depends(require_module(MODULE_DRAWING_REGISTER))],
)

_MEDIA = {"PDF": "application/pdf", "DWG": "application/acad"}


@router.get("/projects/{project_id}/drawings")
def list_drawings(project_id: int, db: Session = Depends(get_db)):
    return svc.list_drawings(db, project_id)


@router.post("/projects/{project_id}/drawings", status_code=201)
async def create_drawing(
    project_id: int,
    background: BackgroundTasks,
    file: UploadFile = File(...),
    number: str = Form(...),
    title: str = Form(...),
    discipline: str = Form(...),
    remarks: str | None = Form(None),
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_DRAWING_REGISTER)),
):
    drawing, rev = await svc.create_drawing(
        db, project_id, file, number, title, discipline, remarks, user.display_name or user.email,
    )
    if rev.preview_status == "pending":
        background.add_task(svc.render_preview, rev.id)
    return drawing


@router.post("/drawings/{drawing_id}/revisions", status_code=201)
async def add_revision(
    drawing_id: int,
    background: BackgroundTasks,
    file: UploadFile = File(...),
    remarks: str | None = Form(None),
    db: Session = Depends(get_db),
    user: AuthUser = Depends(require_module(MODULE_DRAWING_REGISTER)),
):
    drawing, rev = await svc.add_revision(db, drawing_id, file, remarks, user.display_name or user.email)
    if rev.preview_status == "pending":
        background.add_task(svc.render_preview, rev.id)
    return drawing


@router.get("/drawings/{drawing_id}")
def get_drawing(drawing_id: int, db: Session = Depends(get_db)):
    return svc.get_drawing(db, drawing_id)


@router.get("/revisions/{revision_id}/file")
def revision_file(revision_id: int, inline: bool = False, db: Session = Depends(get_db)):
    rev = svc.get_revision(db, revision_id)
    path = svc.revision_path(rev)
    if not path.exists():
        raise HTTPException(404, "The file for this revision is missing on the server.")
    return FileResponse(
        path,
        media_type=_MEDIA.get(rev.fmt, "application/octet-stream"),
        filename=rev.filename,
        content_disposition_type="inline" if inline else "attachment",
    )


@router.get("/revisions/{revision_id}/preview")
def revision_preview(revision_id: int, db: Session = Depends(get_db)):
    rev = svc.get_revision(db, revision_id)
    path = svc.preview_path(rev)
    if rev.preview_status != "ready" or not path.exists():
        raise HTTPException(404, "No preview for this revision.")
    return FileResponse(path, media_type="image/png")
