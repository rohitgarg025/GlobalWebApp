"""DWG → DXF conversion via LibreDWG's `dwg2dxf` CLI; DXF files pass straight through."""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

CONVERT_TIMEOUT_S = 300


class ConversionError(Exception):
    pass


def to_dxf(src: Path, work_dir: Path) -> Path:
    suffix = src.suffix.lower()
    if suffix == ".dxf":
        return src
    if suffix != ".dwg":
        raise ConversionError("Only .dwg and .dxf drawings are supported.")

    exe = shutil.which("dwg2dxf")
    if exe is None:
        raise ConversionError(
            "The DWG converter isn't installed on the server. "
            "Save the drawing as DXF in AutoCAD and upload that instead."
        )
    out = work_dir / (src.stem + ".dxf")
    try:
        proc = subprocess.run(
            [exe, "-y", "-o", str(out), str(src)],
            capture_output=True,
            text=True,
            timeout=CONVERT_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired as exc:
        raise ConversionError("Converting the DWG took too long.") from exc

    # dwg2dxf prints recoverable warnings for newer object types and still
    # writes a usable file; only a missing/empty output is a failure.
    if not out.exists() or out.stat().st_size == 0:
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-3:]
        raise ConversionError(
            "This DWG couldn't be converted"
            + (f" ({' '.join(tail)})" if tail else "")
            + ". In AutoCAD use Save As → AutoCAD 2018 DXF and upload the DXF."
        )
    return out
