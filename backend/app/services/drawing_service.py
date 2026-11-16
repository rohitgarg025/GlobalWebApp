"""Drawing register: drawings per project, each with numbered revisions (R0, R1, …).

Files are kept on disk under <root>/<drawing_id>/<rev_no>/<filename>; the newest revision is
current and older ones stay downloadable as superseded. DWG revisions get a PNG preview
rendered in the background.
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import threading
import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.db.models import Drawing, DrawingRevision, Project

log = logging.getLogger(__name__)

MAX_UPLOAD_BYTES = 100 * 1024 * 1024
DISCIPLINES = ("Architectural", "Structural", "MEP", "Civil")
FORMATS = {".pdf": "PDF", ".dwg": "DWG"}
PREVIEW_NAME = "preview.png"
PREVIEW_LONG_EDGE_PX = 2000
PREVIEW_TIMEOUT_S = 240
_heavy = threading.Semaphore(1)


def _root() -> Path:
    base = os.getenv("DRAWINGS_DIR")
    if not base and os.getenv("DB_PATH"):
        # keep drawings on the same persistent disk as the database
        base = str(Path(os.environ["DB_PATH"]).parent / "drawings")
    p = Path(base or Path(__file__).resolve().parents[2] / "temp" / "drawings")
    p.mkdir(parents=True, exist_ok=True)
    return p


def _rev_dir(rev: DrawingRevision) -> Path:
    return _root() / str(rev.drawing_id) / str(rev.rev_no)


def revision_path(rev: DrawingRevision) -> Path:
    return _rev_dir(rev) / rev.filename


def preview_path(rev: DrawingRevision) -> Path:
    return _rev_dir(rev) / PREVIEW_NAME


def _label(rev_no: int) -> str:
    return f"R{rev_no}"


# ─── Reads ──────────────────────────────────────────────────────────────


def _rev_dict(rev: DrawingRevision, current: bool) -> dict:
    return {
        "id": rev.id,
        "rev": _label(rev.rev_no),
        "rev_no": rev.rev_no,
        "filename": rev.filename,
        "fmt": rev.fmt,
        "size_bytes": rev.size_bytes,
        "remarks": rev.remarks,
        "uploaded_by": rev.uploaded_by,
        "uploaded_at": rev.uploaded_at.isoformat() if rev.uploaded_at else None,
        "preview_status": rev.preview_status,
        "status": "current" if current else "superseded",
    }


def _drawing_dict(d: Drawing, revs: list[DrawingRevision]) -> dict:
    revs = sorted(revs, key=lambda r: r.rev_no, reverse=True)
    return {
        "id": d.id,
        "project_id": d.project_id,
        "number": d.number,
        "title": d.title,
        "discipline": d.discipline,
        "created_at": d.created_at.isoformat() if d.created_at else None,
        "created_by": d.created_by,
        "revisions": [_rev_dict(r, i == 0) for i, r in enumerate(revs)],
    }


def list_drawings(db: Session, project_id: int) -> list[dict]:
    drawings = db.query(Drawing).filter(Drawing.project_id == project_id).all()
    if not drawings:
        return []
    revs: dict[int, list[DrawingRevision]] = {}
    for r in db.query(DrawingRevision).filter(DrawingRevision.drawing_id.in_([d.id for d in drawings])):
        revs.setdefault(r.drawing_id, []).append(r)
    out = [_drawing_dict(d, revs.get(d.id, [])) for d in drawings]
    # most recently revised first, like the register on site
    out.sort(key=lambda d: (d["revisions"][0]["uploaded_at"] or "") if d["revisions"] else "", reverse=True)
    return out


def get_drawing(db: Session, drawing_id: int) -> dict:
    d = _drawing(db, drawing_id)
    return _drawing_dict(d, db.query(DrawingRevision).filter(DrawingRevision.drawing_id == d.id).all())


def get_revision(db: Session, revision_id: int) -> DrawingRevision:
    rev = db.get(DrawingRevision, revision_id)
    if not rev:
        raise HTTPException(404, "Revision not found")
    return rev


def _drawing(db: Session, drawing_id: int) -> Drawing:
    d = db.get(Drawing, drawing_id)
    if not d:
        raise HTTPException(404, "Drawing not found")
    return d


# ─── Uploads ────────────────────────────────────────────────────────────


def _format_of(filename: str) -> str:
    fmt = FORMATS.get(Path(filename).suffix.lower())
    if not fmt:
        raise HTTPException(422, "Only .pdf and .dwg files can be uploaded.")
    return fmt


async def _receive(file: UploadFile) -> tuple[Path, int]:
    """Stream the upload to a holding file, enforcing the size cap."""
    incoming = _root() / "_incoming"
    incoming.mkdir(exist_ok=True)
    tmp = incoming / uuid.uuid4().hex
    size = 0
    try:
        with tmp.open("wb") as out:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "Drawing is larger than 100 MB.")
                out.write(chunk)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    if size == 0:
        tmp.unlink(missing_ok=True)
        raise HTTPException(422, "The file is empty.")
    return tmp, size


def _store(db: Session, rev: DrawingRevision, tmp: Path) -> None:
    """Commit the revision row, then move the file into place; undo the row if the move fails."""
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        tmp.unlink(missing_ok=True)
        raise HTTPException(409, "Someone else just uploaded this revision. Refresh and try again.")
    dest = revision_path(rev)
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(tmp), dest)
    except Exception:
        tmp.unlink(missing_ok=True)
        db.delete(rev)
        db.commit()
        raise


async def create_drawing(
    db: Session, project_id: int, file: UploadFile, number: str, title: str,
    discipline: str, remarks: str | None, user_name: str | None,
) -> tuple[dict, DrawingRevision]:
    if not db.get(Project, project_id):
        raise HTTPException(404, "Project not found")
    number = (number or "").strip().upper()
    title = (title or "").strip()
    if not number or not title:
        raise HTTPException(422, "Drawing number and name are required.")
    if discipline not in DISCIPLINES:
        raise HTTPException(422, f"Discipline must be one of: {', '.join(DISCIPLINES)}.")
    filename = os.path.basename(file.filename or "")
    fmt = _format_of(filename)
    if db.query(Drawing).filter(Drawing.project_id == project_id, Drawing.number == number).first():
        raise HTTPException(409, f"Drawing number {number} already exists in this project.")

    tmp, size = await _receive(file)
    d = Drawing(project_id=project_id, number=number, title=title, discipline=discipline,
                created_by=user_name)
    db.add(d)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        tmp.unlink(missing_ok=True)
        raise HTTPException(409, f"Drawing number {number} already exists in this project.")
    rev = DrawingRevision(
        drawing_id=d.id, rev_no=0, filename=filename, fmt=fmt, size_bytes=size,
        remarks=(remarks or "").strip() or "Issued for construction", uploaded_by=user_name,
        preview_status="pending" if fmt == "DWG" else "none",
    )
    db.add(rev)
    _store(db, rev, tmp)
    return get_drawing(db, d.id), rev


async def add_revision(
    db: Session, drawing_id: int, file: UploadFile, remarks: str | None, user_name: str | None,
) -> tuple[dict, DrawingRevision]:
    d = _drawing(db, drawing_id)
    filename = os.path.basename(file.filename or "")
    fmt = _format_of(filename)
    tmp, size = await _receive(file)
    last = (db.query(DrawingRevision.rev_no).filter(DrawingRevision.drawing_id == d.id)
            .order_by(DrawingRevision.rev_no.desc()).first())
    rev = DrawingRevision(
        drawing_id=d.id, rev_no=(last[0] + 1) if last else 0, filename=filename, fmt=fmt,
        size_bytes=size, remarks=(remarks or "").strip() or "Revised", uploaded_by=user_name,
        preview_status="pending" if fmt == "DWG" else "none",
    )
    db.add(rev)
    _store(db, rev, tmp)
    return get_drawing(db, d.id), rev


# ─── DWG preview ────────────────────────────────────────────────────────


def render_preview(revision_id: int) -> None:
    """Background task: render a DWG revision's picture in a child process.

    A separate process with a time limit keeps a huge drawing (a 25 MB master plan can take
    many minutes and close to 1 GB) from stalling or exhausting the server; it just ends up
    without a preview.
    """
    db = SessionLocal()
    try:
        rev = db.get(DrawingRevision, revision_id)
        if not rev or rev.fmt != "DWG":
            return
        status = "failed"
        try:
            with _heavy:
                proc = subprocess.run(
                    [sys.executable, "-m", "app.services.drawing_preview",
                     str(revision_path(rev)), str(preview_path(rev)), str(PREVIEW_LONG_EDGE_PX)],
                    cwd=Path(__file__).resolve().parents[2], capture_output=True, text=True,
                    timeout=PREVIEW_TIMEOUT_S,
                )
            if proc.returncode == 0 and preview_path(rev).exists():
                status = "ready"
            else:
                log.warning("preview failed for drawing revision %s: %s",
                            revision_id, (proc.stderr or "").strip()[-500:])
        except subprocess.TimeoutExpired:
            log.warning("preview timed out for drawing revision %s", revision_id)
        rev.preview_status = status
        db.commit()
    finally:
        db.close()
