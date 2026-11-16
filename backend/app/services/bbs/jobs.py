"""BBS job lifecycle: upload → reading → needs_settings → computing → done / failed."""
from __future__ import annotations

import json
import logging
import os
import shutil
import threading
from datetime import datetime
from pathlib import Path

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.db.models import BbsJob
from app.services.bbs import builder, reader
from app.services.bbs.optimiser import Piece, optimise
from app.services.takeoff.convert import ConversionError, to_dxf

log = logging.getLogger(__name__)
MAX_UPLOAD_BYTES = 80 * 1024 * 1024
_heavy = threading.Semaphore(1)


def _root() -> Path:
    base = os.getenv("BBS_DIR") or str(Path(__file__).resolve().parents[3] / "temp" / "bbs")
    p = Path(base)
    p.mkdir(parents=True, exist_ok=True)
    return p


def job_dir(job_id: int) -> Path:
    d = _root() / str(job_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def _set(db: Session, job: BbsJob, status: str, message: str | None = None) -> None:
    job.status = status
    job.message = message
    job.updated_at = datetime.utcnow()
    db.commit()


async def create_job(db: Session, file: UploadFile, user_name: str | None) -> BbsJob:
    name = os.path.basename(file.filename or "drawing")
    if not name.lower().endswith((".dwg", ".dxf")):
        raise HTTPException(422, "Upload an AutoCAD reinforcement drawing (.dwg or .dxf).")
    job = BbsJob(filename=name, created_by=user_name, status="uploaded")
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


def default_settings(notes: dict) -> dict:
    """Pre-fill only what the drawing states; everything else stays empty for the user."""
    lap = notes.get("lap_table") or {}
    grade = notes.get("concrete_grade")
    return {
        "lap_factor": lap.get(grade) if grade in lap else None,
        "cover_beam_mm": (notes.get("covers_mm") or {}).get("beams"),
        "stock_mm": {}, "default_stock_mm": 12000, "min_reuse_mm": 1000,
        "offcuts_mm": {}, "multiplier": 1,
    }


def prepare(job_id: int) -> None:
    """Background: convert, read the notes and the beam details."""
    db = SessionLocal()
    try:
        job = db.get(BbsJob, job_id)
        if not job:
            return
        with _heavy:
            _set(db, job, "reading", "Converting and reading the drawing…")
            try:
                d = job_dir(job.id)
                dxf = to_dxf(d / job.filename, d)
                doc = reader.load(str(dxf))
                notes = reader.read_notes(doc)
                strips = reader.read_beams(doc)
                del doc
            except ConversionError as e:
                _set(db, job, "failed", str(e))
                return
            except Exception:
                log.exception("bbs read failed")
                _set(db, job, "failed", "This drawing couldn't be read. Try saving it as DXF from AutoCAD.")
                return
        if not strips:
            _set(db, job, "failed",
                 "No beam reinforcement details found. The reader looks for beam elevations "
                 "(outline + bars + callouts like '2-12# Cont.').")
            return
        n = reader.notes_to_json(notes)
        job.notes_json = json.dumps(n)
        job.strips_json = json.dumps(reader.strips_to_json(strips))
        job.settings_json = json.dumps(default_settings(n))
        spans = sum(len(s.spans) for s in strips)
        _set(db, job, "needs_settings",
             f"Found {len(strips)} beam lines ({spans} spans). Confirm the lap, cover and stock settings.")
        src = job_dir(job.id) / job.filename
        if src.suffix.lower() == ".dwg" and src.exists():
            src.unlink()
    finally:
        db.close()


def start_compute(db: Session, job: BbsJob, settings: dict) -> None:
    if job.status in ("reading", "computing"):
        raise HTTPException(409, "This drawing is still being processed.")
    if not job.strips_json:
        raise HTTPException(409, "The drawing hasn't been read yet.")
    s = builder.settings_from_dict(settings)
    if s.lap_factor is not None and not (20 <= s.lap_factor <= 80):
        raise HTTPException(422, "Lap factor should be between 20 and 80 × Ø.")
    if s.cover_beam_mm is not None and not (15 <= s.cover_beam_mm <= 75):
        raise HTTPException(422, "Beam cover should be between 15 and 75 mm.")
    if not (3000 <= s.default_stock_mm <= 18000) or any(not (3000 <= v <= 18000) for v in s.stock_mm.values()):
        raise HTTPException(422, "Stock bar length should be between 3 m and 18 m.")
    if not (100 <= s.min_reuse_mm <= 6000):
        raise HTTPException(422, "Minimum reusable offcut should be between 0.1 m and 6 m.")
    job.settings_json = json.dumps(builder.settings_to_dict(s))
    job.lines_json = None
    _set(db, job, "computing", "Building the bar bending schedule…")


def compute(job_id: int, keep_lines: bool = False) -> None:
    """Background: BBS lines (unless editing) → cutting plan per dia."""
    db = SessionLocal()
    try:
        job = db.get(BbsJob, job_id)
        if not job:
            return
        try:
            st = builder.settings_from_dict(json.loads(job.settings_json or "{}"))
            if keep_lines and job.lines_json:
                lines = json.loads(job.lines_json)
                issues = json.loads(job.issues_json or "[]")
            else:
                strips = reader.strips_from_json(json.loads(job.strips_json))
                bars, issues = builder.build_beam_bars(strips, st)
                lines = builder.bbs_lines(bars, st)
                issues = sorted(set(issues + [f"{s.id}: {i}" for s in strips for i in s.issues
                                              if "stirrup" not in i.lower()]))
            _set(db, job, "computing", "Optimising cutting plan…")
            plans = {}
            for dia, ps in sorted(builder.pieces_by_dia(lines).items()):
                plan = optimise(dia, [Piece(L, q, m) for L, q, m in ps], st.stock_for(dia),
                                offcuts=st.offcuts_mm.get(dia), min_reuse=st.min_reuse_mm,
                                time_limit_s=15)
                plans[str(dia)] = _plan_dict(plan)
            job.lines_json = json.dumps(lines)
            job.issues_json = json.dumps(issues)
            job.plan_json = json.dumps(plans)
        except Exception:
            log.exception("bbs compute failed")
            _set(db, job, "failed", "Something went wrong while building the BBS. Please retry.")
            return
        _set(db, job, "done", "Bar bending schedule and cutting plan ready.")
    finally:
        db.close()


def _plan_dict(p) -> dict:
    from dataclasses import asdict
    d = asdict(p)
    d["bars_saved"] = p.bars_saved
    return d


def save_lines(db: Session, job: BbsJob, lines: list[dict]) -> None:
    """Accept edited lines, recompute their arithmetic server-side, then re-optimise."""
    if job.status != "done":
        raise HTTPException(409, "The BBS isn't ready yet.")
    st = builder.settings_from_dict(json.loads(job.settings_json or "{}"))
    from app.services.bbs.engine import split_at_laps, unit_weight
    clean = []
    for i, ln in enumerate(lines, start=1):
        try:
            dia = int(ln.get("dia") or 0)
            cut = float(ln.get("cut_length") or 0)
            nos = int(ln.get("nos_per_member") or 0)
            members = int(ln.get("members") or 1)
        except (TypeError, ValueError):
            raise HTTPException(422, f"Line {i}: dia, cut length, nos and members must be numbers.")
        if dia and dia not in (6, 8, 10, 12, 16, 20, 25, 28, 32, 36, 40):
            raise HTTPException(422, f"Line {i}: {dia} mm is not a standard bar size.")
        lap = st.lap_factor * dia if (st.lap_factor and dia) else None
        pieces, laps = split_at_laps(cut, st.stock_for(dia) if dia else st.default_stock_mm, lap) if dia else ([cut], 0)
        total_nos = nos * members
        total_m = sum(pieces) * total_nos / 1000
        clean.append({
            **ln, "sno": i, "dia": dia, "cut_length": round(cut, 1), "nos_per_member": nos, "members": members,
            "total_nos": total_nos, "laps_per_bar": laps, "lap_mm": lap, "pieces": pieces,
            "total_length_m": round(total_m, 3), "unit_wt": round(unit_weight(dia), 3) if dia else 0,
            "weight_kg": round(total_m * unit_weight(dia), 3) if dia else 0.0,
            "flags": [f for f in (ln.get("flags") or []) if isinstance(f, str)][:6],
        })
    job.lines_json = json.dumps(clean)
    _set(db, job, "computing", "Re-optimising cutting plan…")


def job_dict(job: BbsJob, full: bool = True) -> dict:
    d = {
        "id": job.id, "filename": job.filename, "status": job.status, "message": job.message,
        "created_by": job.created_by,
        "created_at": job.created_at.isoformat() if job.created_at else None,
    }
    if not full:
        return d
    d["notes"] = json.loads(job.notes_json or "{}")
    d["settings"] = json.loads(job.settings_json or "{}")
    if job.status == "done":
        lines = json.loads(job.lines_json or "[]")
        plans = json.loads(job.plan_json or "{}")
        d["lines"] = lines
        d["issues"] = json.loads(job.issues_json or "[]")
        d["plans"] = plans
        d["summary"] = summary(lines, plans)
    return d


def summary(lines: list[dict], plans: dict) -> dict:
    by = {}
    for ln in lines:
        if not ln.get("dia"):
            continue
        k = str(ln["dia"])
        e = by.setdefault(k, {"dia": ln["dia"], "length_m": 0.0, "weight_kg": 0.0})
        e["length_m"] += ln["total_length_m"]
        e["weight_kg"] += ln["weight_kg"]
    rows = []
    for k, e in sorted(by.items(), key=lambda kv: int(kv[0])):
        p = plans.get(k, {})
        stock_m = (p.get("stock_length") or 12000) / 1000
        rows.append({
            **{kk: round(v, 3) if isinstance(v, float) else v for kk, v in e.items()},
            "bars_to_buy": p.get("new_bars"), "uncut_bars": p.get("baseline_bars"),
            "purchase_kg": round((p.get("new_bars") or 0) * stock_m * (e["dia"] ** 2 / 162), 1),
            "wastage_pct": p.get("wastage_pct"), "uncut_wastage_pct": p.get("baseline_wastage_pct"),
            "reusable_m": p.get("reusable_m"),
        })
    total_kg = sum(r["weight_kg"] for r in rows)
    return {
        "by_dia": rows,
        "total_kg": round(total_kg, 1),
        "total_mt": round(total_kg / 1000, 3),
        "bars_to_buy": sum(r["bars_to_buy"] or 0 for r in rows),
        "uncut_bars": sum(r["uncut_bars"] or 0 for r in rows),
        "purchase_mt": round(sum(r["purchase_kg"] for r in rows) / 1000, 3),
        "flagged": sum(1 for ln in lines if ln.get("flags")),
    }
