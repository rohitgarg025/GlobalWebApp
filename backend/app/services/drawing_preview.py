"""Render a DWG's whole model space to PNG. Run as a child process by drawing_service.

Usage: python -m app.services.drawing_preview <drawing.dwg> <out.png> <long_edge_px>
"""
import sys
import tempfile
from pathlib import Path

from ezdxf import bbox

from app.services.takeoff.convert import to_dxf
from app.services.takeoff.drawing import load, render_window_png


def main(src: str, out: str, long_edge_px: int) -> int:
    with tempfile.TemporaryDirectory() as work:
        doc = load(str(to_dxf(Path(src), Path(work))))
        msp = doc.modelspace()
        ext = bbox.extents(msp, fast=True)
        if not ext.has_data or ext.size.x <= 0 or ext.size.y <= 0:
            print("drawing has no visible model-space content", file=sys.stderr)
            return 1
        pad_x, pad_y = ext.size.x * 0.01, ext.size.y * 0.01
        window = (ext.extmin.x - pad_x, ext.extmin.y - pad_y, ext.extmax.x + pad_x, ext.extmax.y + pad_y)
        tmp = Path(out).with_suffix(".part.png")
        render_window_png(doc, msp, window, str(tmp), long_edge_px)
        tmp.replace(out)  # only a complete picture ever appears at `out`
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], int(sys.argv[3])))
