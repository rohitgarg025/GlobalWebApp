"""Takeoff job lifecycle: upload → convert → floors_ready → analysing → done / failed.

Heavy steps run in a background thread. A 40 MB DWG expands to a ~180 MB DXF
and ~0.5 GB in memory, so only one drawing is processed at a time.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import threading
import time
from datetime import datetime
from pathlib import Path

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.db.models import TakeoffJob
from app.services.takeoff import claude_takeoff, drawing, measure
from app.services.takeoff.convert import ConversionError, to_dxf

log = logging.getLogger(__name__)

MAX_UPLOAD_BYTES = 80 * 1024 * 1024
KEEP_FILES_S = 3 * 24 * 3600
_heavy = threading.Semaphore(1)


def _root() -> Path:
    base = os.getenv("TAKEOFF_DIR") or str(Path(__file__).resolve().parents[3] / "temp" / "takeoff")
    p = Path(base)
    p.mkdir(parents=True, exist_ok=True)
    return p


def job_dir(job_id: int) -> Path:
    d = _root() / str(job_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def cleanup_old_files() -> None:
    now = time.time()
    for d in _root().iterdir():
        try:
            if d.is_dir() and now - d.stat().st_mtime > KEEP_FILES_S:
                shutil.rmtree(d, ignore_errors=True)
        except OSError:
            pass


def _set(db: Session, job: TakeoffJob, status: str, message: str | None = None) -> None:
    job.status = status
    job.message = message
    job.updated_at = datetime.utcnow()
    db.commit()


# ─── Upload & floor detection ──────────────────────────────────────────────


async def create_job(db: Session, file: UploadFile, user_name: str | None) -> TakeoffJob:
    name = os.path.basename(file.filename or "drawing")
    if not name.lower().endswith((".dwg", ".dxf")):
        raise HTTPException(422, "Upload an AutoCAD drawing (.dwg or .dxf).")
    cleanup_old_files()
    job = TakeoffJob(filename=name, created_by=user_name, status="uploaded")
    db.add(job)
    db.commit()
    db.refresh(job)

    dest = job_dir(job.id) / name
    size = 0
    with dest.open("wb") as out:
        while chunk := await file.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                out.close()
                shutil.rmtree(job_dir(job.id), ignore_errors=True)
                db.delete(job)
                db.commit()
                raise HTTPException(413, "Drawing is larger than 80 MB.")
            out.write(chunk)
    return job


def _dxf_path(job: TakeoffJob) -> Path:
    d = job_dir(job.id)
    dxf = next(iter(sorted(d.glob("*.dxf"))), None)
    if dxf:
        return dxf
    return to_dxf(d / job.filename, d)


def prepare(job_id: int) -> None:
    """Background: convert the drawing and list its floors."""
    db = SessionLocal()
    try:
        job = db.get(TakeoffJob, job_id)
        if not job:
            return
        with _heavy:
            _set(db, job, "converting", "Converting drawing…")
            try:
                dxf = _dxf_path(job)
                _set(db, job, "converting", "Reading drawing…")
                doc = drawing.load(str(dxf))
                skipped: list[str] = []
                floors = drawing.list_floors(doc, skipped)
            except ConversionError as e:
                _set(db, job, "failed", str(e))
                return
            except Exception:
                log.exception("takeoff prepare failed")
                _set(db, job, "failed", "This drawing couldn't be read. Try saving it as DXF from AutoCAD.")
                return
        if not floors:
            _set(db, job, "failed",
                 "No floor layouts found. Each floor plan should be on its own layout (paper space) tab.")
            return
        job.floors_json = json.dumps([{"layout": f.layout, "title": f.title} for f in floors])
        # Drop the original DWG once converted; the DXF is what we reuse.
        src = job_dir(job.id) / job.filename
        if src.suffix.lower() == ".dwg" and src.exists():
            src.unlink()
        msg = f"{len(floors)} floors found. Choose one to analyse."
        if skipped:
            msg += f" Skipped {len(skipped)} layout(s) with no plan content: {', '.join(skipped)}."
        _set(db, job, "floors_ready", msg)
    finally:
        db.close()


# ─── Analysis ──────────────────────────────────────────────────────────────


def start_analysis(db: Session, job: TakeoffJob, floor_layout: str, floor_height_m: float | None,
                   default_slab_mm: int | None = None) -> None:
    floors = json.loads(job.floors_json or "[]")
    match = next((f for f in floors if f["layout"] == floor_layout), None)
    if not match:
        raise HTTPException(422, "Choose one of the floors found in this drawing.")
    if job.status in ("converting", "analysing"):
        raise HTTPException(409, "This drawing is still being processed.")
    if floor_height_m is not None and not (2.0 <= floor_height_m <= 12.0):
        raise HTTPException(422, "Floor height should be between 2 and 12 m.")
    if default_slab_mm is not None and not (75 <= default_slab_mm <= 500):
        raise HTTPException(422, "Default slab thickness should be between 75 and 500 mm.")
    job.floor_layout = floor_layout
    job.floor_title = match["title"]
    job.floor_height_m = floor_height_m
    job.default_slab_mm = default_slab_mm
    job.members_json = job.ai_json = job.rows_json = None
    _set(db, job, "analysing", "Queued…")


def analyse(job_id: int) -> None:
    """Background: measure the chosen floor, ask Claude to interpret it, build rows."""
    db = SessionLocal()
    try:
        job = db.get(TakeoffJob, job_id)
        if not job:
            return
        with _heavy:
            try:
                _set(db, job, "analysing", "Measuring beams, columns and grid…")
                doc = drawing.load(str(_dxf_path(job)))
                floor = next(f for f in drawing.list_floors(doc) if f.layout == job.floor_layout)
                fd = drawing.extract_floor(doc, floor)
                png_path = job_dir(job.id) / f"floor_{abs(hash(floor.layout))}.png"
                drawing.render_floor_png(doc, floor, str(png_path))
                levels = claude_takeoff.level_texts(doc)
                del doc
            except Exception:
                log.exception("takeoff measure failed")
                _set(db, job, "failed", "Couldn't measure this floor from the drawing.")
                return

        _set(db, job, "analysing", "Claude is reading the drawing (a few minutes)…")
        try:
            ai, usage = claude_takeoff.interpret_floor(
                fd, png_path.read_bytes(), levels, default_slab_mm=job.default_slab_mm)
            members = measure.build_members(fd, ai, job.floor_height_m, job.default_slab_mm)
            # Takeoff-level problems (e.g. no slab measured) first, then drawing notes
            members["warnings"] = members.get("warnings", []) + fd.warnings
            job.members_json = json.dumps(members)
            job.ai_json = json.dumps({"notes": ai.get("notes", []), "missing_info": ai.get("missing_info", [])})
            job.rows_json = json.dumps({a: measure.build_rows(members, a) for a in measure.ACTIVITIES})
            job.input_tokens = (job.input_tokens or 0) + usage["input_tokens"]
            job.output_tokens = (job.output_tokens or 0) + usage["output_tokens"]
        except claude_takeoff.TakeoffAIError as e:
            _set(db, job, "failed", str(e))
            return
        except Exception:
            log.exception("takeoff analysis failed")
            _set(db, job, "failed", "Something went wrong while preparing the takeoff. Please retry.")
            return
        _set(db, job, "done", "Takeoff ready for review.")
    finally:
        db.close()


# ─── Views ─────────────────────────────────────────────────────────────────


def job_dict(job: TakeoffJob, full: bool = True) -> dict:
    d = {
        "id": job.id, "filename": job.filename, "status": job.status, "message": job.message,
        "floors": json.loads(job.floors_json or "[]"),
        "floor_layout": job.floor_layout, "floor_title": job.floor_title,
        "floor_height_m": job.floor_height_m, "default_slab_mm": job.default_slab_mm,
        "created_by": job.created_by,
        "created_at": job.created_at.isoformat() if job.created_at else None,
        "updated_at": job.updated_at.isoformat() if job.updated_at else None,
    }
    if full and job.status == "done":
        members = json.loads(job.members_json or "{}")
        rows = json.loads(job.rows_json or "{}")
        d.update({
            "activities": [{"id": k, **v} for k, v in measure.ACTIVITIES.items()],
            "rows": rows,
            "totals": {a: measure.totals(r) for a, r in rows.items()},
            "summary": {
                "slab_thickness_mm": members.get("slab_thickness_mm"),
                "floor_height_m": members.get("floor_height_m"),
                "height_source": members.get("height_source"),
                "beams": len(members.get("beams", [])),
                "columns": len(members.get("columns", [])),
                "slab_panels": len(members.get("slabs", [])),
                "warnings": members.get("warnings", []),
            },
            "ai": json.loads(job.ai_json or "{}"),
            "conventions": measure.CONVENTIONS,
            "usage": {"input_tokens": job.input_tokens, "output_tokens": job.output_tokens},
        })
    return d


def save_rows(db: Session, job: TakeoffJob, activity: str, rows: list[dict]) -> dict:
    if job.status != "done":
        raise HTTPException(409, "The takeoff isn't ready yet.")
    if activity not in measure.ACTIVITIES:
        raise HTTPException(422, "Unknown activity.")
    clean = []
    for i, r in enumerate(rows, start=1):
        def num(v):
            if v in (None, ""):
                return None
            try:
                return float(v)
            except (TypeError, ValueError):
                raise HTTPException(422, f"Row {i}: '{v}' is not a number.")
        nos = num(r.get("nos"))
        if nos is None:
            raise HTTPException(422, f"Row {i}: Nos is required.")
        clean.append({
            "id": str(r.get("id") or f"U{i:03d}"),
            "member_type": r.get("member_type") or "other",
            "mark": (r.get("mark") or "")[:40],
            "location": (r.get("location") or "")[:120],
            "description": (r.get("description") or "")[:200],
            "nos": nos, "l": num(r.get("l")), "b": num(r.get("b")), "d": num(r.get("d")),
            "req": "".join(k for k in "lbd" if k in str(r.get("req") or "")),
            "confidence": r.get("confidence") or "high",
            "remarks": (r.get("remarks") or "")[:400],
            "flag": r.get("flag") or None,
        })
    all_rows = json.loads(job.rows_json or "{}")
    all_rows[activity] = measure.with_qty(clean)
    job.rows_json = json.dumps(all_rows)
    db.commit()
    return job_dict(job)
