"""Version history: what changed in the app and on which date (admins only).

Entries live in app/release_notes.json, newest first. "date" is the day the change went live;
null means it is in the code but not deployed yet — set the date when it is deployed.
"""
import json
from pathlib import Path

from fastapi import APIRouter, Depends

from app.services.auth_deps import require_admin

router = APIRouter(prefix="/api", tags=["release-notes"])

NOTES_FILE = Path(__file__).resolve().parent.parent / "release_notes.json"


def load_notes() -> list[dict]:
    notes = json.loads(NOTES_FILE.read_text(encoding="utf-8"))
    # not-yet-live entries first, then newest date first (stable for same-day entries)
    return sorted(notes, key=lambda n: n.get("date") or "9999-99-99", reverse=True)


@router.get("/release-notes", dependencies=[Depends(require_admin)])
def release_notes() -> list[dict]:
    return load_notes()
