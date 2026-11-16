"""Measurement rows (IS 1200 style) from measured members + Claude's interpretation.

Every quantity is computed here, never by the model:

    qty = nos × L × B × D      (a blank dimension counts as 1; deductions use negative nos)

Conventions (stated on the sheet):
  * Slabs are measured c/c of grids by panel; the slab runs over the beams.
  * Beams are measured between column faces, for their depth below the slab.
  * Columns are measured from floor to the slab soffit (floor height − slab thickness).
  * Formwork: slab soffit c/c (covers beam soffits), two beam sides below the
    slab, column perimeter × clear height. Openings ≤ 0.1 m² are not deducted.
"""
from __future__ import annotations

import math
import re
from collections import Counter, defaultdict

from app.services.takeoff.drawing import FloorData, Grid, _natural

ACTIVITIES = {
    "concrete": {"label": "Concrete (RCC)", "unit": "m³"},
    "formwork": {"label": "Formwork / Shuttering", "unit": "m²"},
}

CONVENTIONS = [
    "Quantities measured as per IS 1200 (Part 2 concrete, Part 5 formwork) conventions.",
    "Slabs measured centre-to-centre of grids by panel; slab taken over the beams.",
    "Beams measured between column faces, for their depth below the slab.",
    "Columns measured from floor level to the slab soffit (floor height − slab thickness).",
    "Formwork: slab soffit c/c of grids (includes beam soffits), two sides of each beam below the slab, "
    "column perimeter × clear height.",
    "Openings of 0.1 m² or less are not deducted.",
]


def row_qty(r: dict) -> float:
    """Nos × L × B × D. A blank dimension counts as 1 unless the row lists it
    in `req` (dimensions the item needs), in which case the quantity is 0 —
    an unknown slab thickness must never turn an area into a volume."""
    req = r.get("req") or ""
    q = float(r.get("nos") or 0)
    for k in ("l", "b", "d"):
        v = r.get(k)
        if v in (None, ""):
            if k in req:
                return 0.0
            continue
        q *= float(v)
    return round(q, 3)


def with_qty(rows: list[dict]) -> list[dict]:
    return [{**r, "qty": row_qty(r)} for r in rows]


def _grid_pos(grids: list[Grid], label: str, axis: str) -> float | None:
    for g in grids:
        if g.axis == axis and g.label.strip().upper() == str(label).strip().upper():
            return g.pos
    return None


def _nearest_gridline(grids: list[Grid], beam) -> str:
    """'Grid B (03-04)' when a beam runs along a grid line, else its bay."""
    (x, y) = beam.mid
    # orientation isn't stored; infer from which grid axis it hugs
    best = None
    for g in grids:
        d = abs((x if g.axis == "x" else y) - g.pos)
        if best is None or d < best[0]:
            best = (d, g)
    return best[1] if best else None


def _slab_thickness_mode(fd: FloorData) -> int | None:
    vals = []
    for s in fd.slab_labels:
        m = re.search(r"(\d{2,3})\s*T?HK", s.text, re.I)
        if m:
            vals.append(int(m.group(1)))
    return Counter(vals).most_common(1)[0][0] if vals else None


def build_members(fd: FloorData, ai: dict, floor_height_m: float | None,
                  default_slab_mm: int | None = None) -> dict:
    """Merge geometry with Claude's interpretation into a members bundle.

    Slab thickness per panel: the drawing (label or note, via Claude) → the
    surveyor's default → unknown. The floor's typical thickness (used for beam
    depth below slab and column clear height) falls back the same way, then
    to 150 mm with a warning.
    """
    unit_m = fd.unit_m
    warnings: list[str] = []
    drawing_t = ai.get("typical_slab_thickness_mm") or _slab_thickness_mode(fd)
    t_slab = drawing_t or default_slab_mm or 150
    if not drawing_t and not default_slab_mm:
        warnings.append("Slab thickness not found; 150 mm assumed for beam depths below slab and column heights.")
    height = floor_height_m or ai.get("floor_to_floor_height_m")

    fixes = {f["beam_id"]: f for f in ai.get("beam_fixes", [])}
    excluded = set(ai.get("exclude_beam_ids", []))

    beams = []
    for b in fd.beams:
        if b.id in excluded:
            continue
        f = fixes.get(b.id)
        depth, conf, ev = b.depth_mm, b.confidence, b.evidence
        mark = b.mark
        if f:
            depth = f.get("depth_mm") or depth
            mark = f.get("mark") or mark
            conf = "medium"
            ev = f"Claude: {f.get('reason', 'size resolved from drawing')}"
        g = _nearest_gridline(fd.grids, b)
        beams.append({
            "id": b.id, "mark": mark, "breadth_mm": b.breadth_mm, "depth_mm": depth,
            "clear_length_m": b.clear_length_m, "location": b.location,
            "grid": g.label if g and abs(((b.mid[0] if g.axis == "x" else b.mid[1]) - g.pos) * unit_m) <= 1.0 else None,
            "confidence": conf, "evidence": ev,
        })

    columns = [{
        "id": c.id, "mark": c.mark, "breadth_mm": c.breadth_mm, "depth_mm": c.depth_mm,
        "location": c.location, "confidence": c.confidence,
        "evidence": f"drawn outline {c.breadth_mm}×{c.depth_mm}"
                    + (f"; label {c.size_label}" if c.size_label else ""),
    } for c in fd.columns]

    for x in ai.get("extra_members", []):
        if x.get("member_type") == "column" and x.get("breadth_mm") and x.get("depth_mm"):
            for i in range(int(x.get("count") or 1)):
                columns.append({
                    "id": f"AI-C{len(columns) + 1:03d}", "mark": x.get("mark"),
                    "breadth_mm": x["breadth_mm"], "depth_mm": x["depth_mm"],
                    "location": x.get("location") or "—", "confidence": "low",
                    "evidence": f"Claude: {x.get('reason', 'labelled but not drawn')}",
                })

    slabs = []
    for i, p in enumerate(ai.get("slab_panels", [])):
        L, B, where = _panel_dims(fd, p)
        if not L or not B:
            continue
        thk = p.get("thickness_mm") or drawing_t
        source = "drawing" if thk else None
        if not thk and default_slab_mm:
            thk, source = default_slab_mm, "default"
        slabs.append({
            "id": f"S{i + 1:03d}", "location": where, "length_m": L, "breadth_m": B,
            "thickness_mm": thk, "thickness_source": source, "is_pt": bool(p.get("is_pt")),
            "description": p.get("description") or "", "confidence": p.get("confidence") or "medium",
            "evidence": p.get("evidence") or "",
        })

    deductions = []
    if not slabs:
        n_open = len(ai.get("slab_deductions", []))
        reason = "; ".join(w for w in fd.warnings if "grid" in w.lower() or "slab" in w.lower())
        warnings.append("No slab measured on this floor" + (f" ({reason})" if reason else "") +
                        ". Add slab rows manually or re-analyse with a default slab thickness.")
        if n_open:
            warnings.append(f"{n_open} opening(s) found but not deducted, because no slab was measured.")
    for i, p in enumerate(ai.get("slab_deductions", []) if slabs else []):
        L, B, where = _panel_dims(fd, p)
        if not L or not B or L * B <= 0.1:
            continue
        deductions.append({
            "id": f"D{i + 1:03d}", "location": where, "length_m": L, "breadth_m": B,
            # same thickness priority as the slab it's cut from; never the 150 mm fallback
            "thickness_mm": p.get("thickness_mm") or drawing_t or default_slab_mm,
            "description": p.get("description") or "Opening", "confidence": p.get("confidence") or "medium",
        })

    return {
        "slab_thickness_mm": t_slab,
        "floor_height_m": height,
        "height_source": "entered by user" if floor_height_m else (
            f"Claude: {ai.get('height_evidence')}" if ai.get("floor_to_floor_height_m") else None),
        "beams": beams, "columns": columns, "slabs": slabs, "deductions": deductions,
        "warnings": warnings,
    }


def _panel_dims(fd: FloorData, p: dict):
    """Panel size from grid labels (c/c), or explicit dimensions."""
    L, B = p.get("length_m"), p.get("breadth_m")
    xf, xt, yf, yt = p.get("x_from"), p.get("x_to"), p.get("y_from"), p.get("y_to")
    where = p.get("location") or ""
    if xf and xt and yf and yt:
        ax, bx = _grid_pos(fd.grids, xf, "x"), _grid_pos(fd.grids, xt, "x")
        ay, by = _grid_pos(fd.grids, yf, "y"), _grid_pos(fd.grids, yt, "y")
        if None not in (ax, bx, ay, by):
            gL = abs(bx - ax) * fd.unit_m
            gB = abs(by - ay) * fd.unit_m
            L = L or round(gL, 3)
            B = B or round(gB, 3)
        xs = sorted((str(xf), str(xt)), key=_natural)
        ys = sorted((str(yf), str(yt)), key=_natural)
        where = where or f"{xs[0]}-{xs[1]} / {ys[0]}-{ys[1]}"
    return (float(L) if L else None), (float(B) if B else None), where


def build_rows(members: dict, activity: str) -> list[dict]:
    """Measurement rows for one activity. Beams are grouped by size along each grid line."""
    t = (members.get("slab_thickness_mm") or 150) / 1000
    H = members.get("floor_height_m")
    clear_h = round(H - t, 3) if H else None
    rows: list[dict] = []

    def add(member_type, mark, location, description, nos, l, b, d, conf, remarks, flag=None):
        # Dimensions each item genuinely needs (others are "not applicable" → 1)
        if activity == "concrete":
            req = "lbd"
        else:
            req = "lb" if member_type in ("slab", "deduction") else "ld"
        missing = [k.upper() for k in req if (l, b, d)["lbd".index(k)] in (None, "")]
        if missing and not flag:
            flag = f"{'/'.join(missing)} missing — quantity is 0 until entered"
        rows.append({
            "id": f"R{len(rows) + 1:03d}", "member_type": member_type, "mark": mark or "",
            "location": location, "description": description, "nos": nos,
            "l": l, "b": b, "d": d, "req": req, "confidence": conf, "remarks": remarks, "flag": flag,
        })

    # Slabs
    for s in members["slabs"]:
        thk = s["thickness_mm"] / 1000 if s["thickness_mm"] else None
        desc = (f"{'PT slab' if s['is_pt'] else 'RCC slab'} "
                f"{s['thickness_mm'] if s['thickness_mm'] else '?'} thk") + (
            f" — {s['description']}" if s["description"] else "")
        flag = None
        if not thk:
            flag = "Slab thickness unknown — enter D" if activity == "concrete" else None
        elif s.get("thickness_source") == "default":
            flag = "Thickness from default — confirm against slab schedule"
        if activity == "concrete":
            add("slab", "", s["location"], desc, 1, s["length_m"], s["breadth_m"], thk, s["confidence"],
                s["evidence"], flag)
        else:
            add("slab", "", s["location"], desc + " (soffit)", 1, s["length_m"], s["breadth_m"], None,
                s["confidence"], s["evidence"], flag)
    for dd in members["deductions"]:
        thk = dd["thickness_mm"] / 1000 if dd["thickness_mm"] else None
        add("deduction", "", dd["location"], f"Less: {dd['description']}", -1, dd["length_m"], dd["breadth_m"],
            thk if activity == "concrete" else None, dd["confidence"], "Opening > 0.1 m²")

    # Beams grouped by (size, grid line/bay, mark)
    groups: dict[tuple, list[dict]] = defaultdict(list)
    for b in members["beams"]:
        where = f"Grid {b['grid']}" if b["grid"] else b["location"]
        groups[(b["breadth_mm"], b["depth_mm"], b["mark"] or "", where)].append(b)
    for (bw, bd, mark, where), items in sorted(groups.items(), key=lambda kv: (kv[0][0], kv[0][1] or 0, kv[0][3])):
        L = round(sum(x["clear_length_m"] for x in items), 3)
        conf = min((x["confidence"] for x in items), key=["low", "medium", "high"].index)
        depth_below = round((bd / 1000) - t, 3) if bd else None
        flag = None
        if not bd:
            flag = "Depth unknown — enter D"
        elif not (100 <= bw <= 1000 and 200 <= bd <= 2000):
            flag = "Unusual beam size — check"
        elif depth_below is not None and depth_below <= 0:
            flag = "Beam not deeper than slab — check"
        size = f"{bw}×{bd}" if bd else f"{bw}×?"
        desc = f"Beam {size}" + (f" ({len(items)} spans)" if len(items) > 1 else "")
        ev = "; ".join(sorted({x["evidence"] for x in items}))[:300]
        if activity == "concrete":
            add("beam", mark, where, desc + " below slab", 1, L, bw / 1000, depth_below, conf, ev, flag)
        else:
            add("beam", mark, where, desc + " — 2 sides below slab", 2, L, None, depth_below, conf, ev, flag)

    # Columns grouped by size (drawn vs. Claude-proposed kept apart); marks listed
    cgroups: dict[tuple, list[dict]] = defaultdict(list)
    for c in members["columns"]:
        cgroups[(c["breadth_mm"], c["depth_mm"], c["id"].startswith("AI-"))].append(c)
    for (cb, cd, proposed), items in sorted(cgroups.items(), key=lambda kv: (kv[0][2], kv[0][0] * kv[0][1])):
        conf = min((x["confidence"] for x in items), key=["low", "medium", "high"].index)
        marks = sorted({x["mark"] for x in items if x["mark"]}, key=_natural)
        mark = ", ".join(marks[:6]) + (f" +{len(marks) - 6}" if len(marks) > 6 else "")
        locs = sorted({x["location"] for x in items})
        where = locs[0] if len(locs) == 1 else f"{len(locs)} locations"
        flag = None if clear_h else "Floor height unknown — enter height"
        if min(cb, cd) < 200:
            flag = flag or "Column smaller than 200 mm — check"
        if proposed:
            flag = flag or "Labelled but not drawn — confirm count"
        ev = (f"{len(items)} {'proposed by Claude' if proposed else 'drawn'}; "
              + "; ".join(sorted({x['evidence'] for x in items}))[:250])
        if activity == "concrete":
            add("column", mark, where, f"Column {cb}×{cd}", len(items), cb / 1000, cd / 1000, clear_h, conf, ev, flag)
        else:
            per = round(2 * (cb + cd) / 1000, 3)
            add("column", mark, where, f"Column {cb}×{cd} — perimeter", len(items), per, None, clear_h, conf, ev, flag)

    return with_qty(rows)


def totals(rows: list[dict]) -> dict:
    by = defaultdict(float)
    for r in rows:
        by[r["member_type"] if r["member_type"] != "deduction" else "slab"] += r.get("qty", row_qty(r))
    return {"by_type": {k: round(v, 3) for k, v in by.items()}, "grand_total": round(sum(by.values()), 3)}
