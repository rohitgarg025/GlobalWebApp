"""Read a structural DXF: find floors, then measure members from geometry.

Everything here is deterministic. Beams and columns are measured from the
drawn geometry (not from text); labels are only associated to them. Slabs are
left to Claude to lay out by grid bay, using the labels and grid we extract.

Layer names vary between consultants, so layers are classified by keywords.
"""
from __future__ import annotations

import logging
import math
import re
import warnings as _warnings
from collections import Counter
from dataclasses import dataclass, field

import ezdxf
from ezdxf import bbox, recover
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

log = logging.getLogger(__name__)
logging.getLogger("ezdxf").setLevel(logging.ERROR)
_warnings.filterwarnings("ignore", category=RuntimeWarning, module="shapely")

SIZE_RE = re.compile(r"^\s*(\d{2,4})\s*[Xx×*]\s*(\d{2,4})\s*$")
SLAB_RE = re.compile(r"(\d{2,3})\s*T?HK|PT\s*SLAB", re.I)
MARK_RE = re.compile(r"^[A-Z]{0,4}\d{1,4}[A-Z]?$")

# $INSUNITS → metres per drawing unit
_UNIT_M = {1: 0.0254, 2: 0.3048, 4: 0.001, 5: 0.01, 6: 1.0}


def load(path: str):
    doc, auditor = recover.readfile(path)
    return doc


def units_to_m(doc) -> float:
    return _UNIT_M.get(doc.header.get("$INSUNITS", 4), 0.001)


# ─── Floors (paper-space layouts) ───────────────────────────────────────────


@dataclass
class Floor:
    layout: str
    title: str
    window: tuple[float, float, float, float]  # x0, y0, x1, y1 in model space


MIN_PLAN_OBJECTS = 50


def list_floors(doc, skipped: list[str] | None = None) -> list[Floor]:
    """One floor per paper-space layout: its largest viewport frames the plan.

    Layouts whose viewport frames fewer than MIN_PLAN_OBJECTS model-space
    objects (empty or pointing at nothing) are left out; their titles are
    appended to `skipped` when a list is passed.
    """
    anchors = [p for e in doc.modelspace() if (p := _anchor(e)) is not None]
    floors: list[Floor] = []
    for lay in doc.layouts:
        if lay.name.lower() == "model":
            continue
        vps = [v for v in lay.query("VIEWPORT") if v.dxf.get("id", 0) != 1 and v.dxf.view_height > 0]
        if not vps:
            continue
        vp = max(vps, key=lambda v: v.dxf.view_height)
        h = vp.dxf.view_height
        w = h * (vp.dxf.width / vp.dxf.height if vp.dxf.height else 1.0)
        c = vp.dxf.view_center_point
        title = lay.name.title()
        for t in lay.query("TEXT MTEXT"):
            s = _text(t)
            m = re.search(r"LAYOUT OF\s+(.+)", s, re.I)
            if m:
                title = m.group(1).strip().title()
                break
        win = (c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)
        n = sum(1 for x, y in anchors if win[0] <= x <= win[2] and win[1] <= y <= win[3])
        if n < MIN_PLAN_OBJECTS:
            if skipped is not None:
                skipped.append(title)
            continue
        floors.append(Floor(lay.name, title, win))
    # Stable, natural order (ground first where recognisable)
    order = ["basement", "ground", "first", "frist", "second", "third", "fourth", "fifth",
             "sixth", "seventh", "eighth", "ninth", "tenth", "terrace", "lmr"]
    def key(f: Floor):
        n = f.title.lower()
        return next((i for i, w in enumerate(order) if w in n), len(order)), n
    return sorted(floors, key=key)


# ─── Helpers ────────────────────────────────────────────────────────────────


def _text(e) -> str:
    try:
        return (e.dxf.text if e.dxftype() in ("TEXT", "ATTRIB") else e.plain_text()).strip()
    except Exception:
        return ""


def _xy(v) -> tuple[float, float]:
    return (v.x, v.y)


def _anchor(e) -> tuple[float, float] | None:
    t = e.dxftype()
    try:
        if t in ("TEXT", "MTEXT", "INSERT"):
            return _xy(e.dxf.insert)
        if t == "LINE":
            return _xy(e.dxf.start)
        if t == "LWPOLYLINE":
            p = e.get_points()[0]
            return (p[0], p[1])
        if t == "MLINE":
            return _xy(e.vertices[0].location)
        if t == "HATCH":
            path = e.paths[0]
            if hasattr(path, "vertices"):
                return _xy(path.vertices[0])
            return _xy(path.edges[0].start)
    except Exception:
        return None
    return None


def _layer_has(e, *words: str, exclude: tuple[str, ...] = ()) -> bool:
    name = e.dxf.layer.upper()
    return any(w in name for w in words) and not any(x in name for x in exclude)


def _seg_dist(p, a, b) -> float:
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2)) if l2 else 0.0
    return math.hypot(ax + dx * t - px, ay + dy * t - py)


def _hatch_polygons(e) -> list[Polygon]:
    out = []
    for path in e.paths:
        try:
            if hasattr(path, "vertices"):
                pts = [_xy(v) for v in path.vertices]
            else:
                pts = [_xy(ed.start) for ed in path.edges if hasattr(ed, "start")]
            if len(pts) >= 3:
                poly = Polygon(pts).buffer(0)
                if poly.area > 0:
                    out.append(poly)
        except Exception:
            continue
    return out


# ─── Floor extraction ───────────────────────────────────────────────────────


@dataclass
class Grid:
    label: str
    axis: str  # "x" → vertical line at x=pos; "y" → horizontal line at y=pos
    pos: float


@dataclass
class Beam:
    id: str
    breadth_mm: float
    depth_mm: float | None
    mark: str | None
    length_m: float        # centreline length
    clear_length_m: float  # minus portions inside columns
    location: str
    confidence: str        # high / medium / low
    evidence: str
    mid: tuple[float, float]
    nearby_sizes: list[str] = field(default_factory=list)


@dataclass
class Column:
    id: str
    breadth_mm: float
    depth_mm: float
    mark: str | None
    location: str
    size_label: str | None
    confidence: str


@dataclass
class TextLabel:
    text: str
    location: str
    x: float
    y: float


@dataclass
class Cutout:
    location: str
    length_m: float
    breadth_m: float
    x0: float
    y0: float
    x1: float
    y1: float


@dataclass
class FloorData:
    floor: Floor
    unit_m: float
    grids: list[Grid]
    beams: list[Beam]
    columns: list[Column]
    slab_labels: list[TextLabel]
    cutouts: list[Cutout]
    notes: list[str]
    warnings: list[str]
    auto_grid: bool = False


def _grids(msp, inside, unit_m) -> list[Grid]:
    """Grid lines + their bubble labels, from inserts/lines on GRID layers."""
    lines: list[tuple[tuple[float, float], tuple[float, float]]] = []
    labels: list[tuple[str, tuple[float, float]]] = []

    def take(ents):
        for e in ents:
            t = e.dxftype()
            if t == "INSERT":
                for a in e.attribs:
                    s = a.dxf.text.strip()
                    if s and len(s) <= 4:
                        labels.append((s, _xy(a.dxf.insert)))
                try:
                    take(list(e.virtual_entities()))
                except Exception:
                    pass
            elif t in ("LWPOLYLINE", "LINE"):
                if t == "LINE":
                    a, b = _xy(e.dxf.start), _xy(e.dxf.end)
                else:
                    pts = e.get_points()
                    if len(pts) != 2:
                        continue
                    a, b = (pts[0][0], pts[0][1]), (pts[1][0], pts[1][1])
                if math.dist(a, b) > 5000:
                    lines.append((a, b))
            elif t in ("TEXT", "MTEXT"):
                s = _text(e)
                if s and len(s) <= 4:
                    labels.append((s, _xy(e.dxf.insert)))

    grid_ents = [e for e in msp if _layer_has(e, "GRID") and (p := _anchor(e)) and inside(p)]
    take(grid_ents)

    grids: list[Grid] = []
    seen: set[tuple[str, str]] = set()
    for a, b in lines:
        vertical = abs(a[0] - b[0]) < abs(a[1] - b[1])
        axis = "x" if vertical else "y"
        pos = (a[0] + b[0]) / 2 if vertical else (a[1] + b[1]) / 2
        # nearest label to either end of the line
        best, bd = None, 1e18
        for s, p in labels:
            d = min(math.dist(p, a), math.dist(p, b))
            if d < bd:
                best, bd = s, d
        if best is None or bd > 8000 or (best, axis) in seen:
            continue
        seen.add((best, axis))
        grids.append(Grid(best, axis, pos))
    grids.sort(key=lambda g: (g.axis, g.pos if g.axis == "x" else -g.pos))
    return grids


def _auto_grid(segments, unit_m) -> list[Grid]:
    """Grid lines inferred from beam centrelines when the drawing has none.

    Beam runs that share an x (vertical) or y (horizontal) position within
    ~300 mm are clustered. A cluster becomes a grid line only if it carries
    beam over at least 15% of the building's extent (so secondary beams and
    stubs don't create 1 m bays), and lines closer than 2.5 m to a stronger
    one are dropped. Labelled X1… left→right and Y1… top→bottom so they
    can't be mistaken for the consultant's grid.
    """
    if not segments:
        return []
    tol, min_gap = 0.3 / unit_m, 2.5 / unit_m
    all_x = [c for (a, b), _ in segments for c in (a[0], b[0])]
    all_y = [c for (a, b), _ in segments for c in (a[1], b[1])]
    # a vertical line (axis x) spans the building's height, a horizontal one its width
    span = {"x": max(all_y) - min(all_y), "y": max(all_x) - min(all_x)}

    def lines(axis):
        runs = []
        for (a, b), _w in segments:
            dx, dy = abs(b[0] - a[0]), abs(b[1] - a[1])
            L = math.hypot(dx, dy)
            if L <= 0:
                continue
            if axis == "x" and dx <= 0.1 * dy:
                runs.append(((a[0] + b[0]) / 2, L))
            elif axis == "y" and dy <= 0.1 * dx:
                runs.append(((a[1] + b[1]) / 2, L))
        runs.sort()
        clusters: list[list[tuple[float, float]]] = []
        for pos, L in runs:
            if clusters and pos - clusters[-1][0][0] <= tol:
                clusters[-1].append((pos, L))
            else:
                clusters.append([(pos, L)])
        min_len = max(3.0 / unit_m, 0.15 * span[axis])
        cands = []
        for c in clusters:
            total = sum(L for _, L in c)
            if total >= min_len:
                cands.append((sum(p * L for p, L in c) / total, total))
        kept: list[tuple[float, float]] = []
        for pos, total in sorted(cands, key=lambda t: -t[1]):
            if all(abs(pos - k) >= min_gap for k, _ in kept):
                kept.append((pos, total))
        return sorted(p for p, _ in kept)

    xs = lines("x")
    ys = sorted(lines("y"), reverse=True)  # top first
    return ([Grid(f"X{i + 1}", "x", p) for i, p in enumerate(xs)]
            + [Grid(f"Y{i + 1}", "y", p) for i, p in enumerate(ys)])


def _natural(s: str):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def grid_ref(grids: list[Grid], x: float, y: float) -> str:
    """'03-04 / B-C' style bay reference for a point."""
    def bay(axis, v):
        gs = sorted((g for g in grids if g.axis == axis), key=lambda g: g.pos)
        if not gs:
            return "?"
        for i in range(len(gs) - 1):
            if gs[i].pos <= v <= gs[i + 1].pos:
                pair = sorted((gs[i].label, gs[i + 1].label), key=_natural)
                return f"{pair[0]}-{pair[1]}"
        nearest = min(gs, key=lambda g: abs(g.pos - v))
        return f"near {nearest.label}"
    return f"{bay('x', x)} / {bay('y', y)}"


def extract_floor(doc, floor: Floor) -> FloorData:
    msp = doc.modelspace()
    unit_m = units_to_m(doc)
    x0, y0, x1, y1 = floor.window

    def inside(p):
        return p is not None and x0 <= p[0] <= x1 and y0 <= p[1] <= y1

    ents = [e for e in msp if inside(_anchor(e))]
    warnings: list[str] = []

    mlines = [e for e in ents if e.dxftype() == "MLINE" and _layer_has(e, "BEAM", exclude=("SIZE", "NOS"))]
    segments = [seg for e in mlines if (seg := _mline_centre(e)) is not None]

    grids = _grids(msp, inside, unit_m)
    auto_grid = False
    if not grids and segments:
        grids = _auto_grid(segments, unit_m)
        auto_grid = bool(grids)
        if auto_grid:
            nx = sum(1 for g in grids if g.axis == "x")
            ny = sum(1 for g in grids if g.axis == "y")
            warnings.append(
                f"No grid in drawing: auto-grid X1–X{nx} / Y1–Y{ny} built from beam lines "
                "(locations refer to these, not the consultant's grid)."
            )
    if not grids:
        warnings.append("No grid lines found; locations are approximate.")

    texts = [e for e in ents if e.dxftype() in ("TEXT", "MTEXT")]

    # Columns: closed outlines / solid hatches on COLUMN layers
    col_polys: list[Polygon] = []
    for e in ents:
        if not _layer_has(e, "COLUMN", "COL ", "COL_", exclude=("SIZE", "NOS", "NO.", "DIM", "TEXT")):
            continue
        if e.dxftype() == "LWPOLYLINE" and (e.closed or len(e) >= 4):
            pts = [(p[0], p[1]) for p in e.get_points()]
            if len(pts) >= 3:
                poly = Polygon(pts).buffer(0)
                if poly.area > 0:
                    col_polys.append(poly)
        elif e.dxftype() == "HATCH":
            col_polys.extend(_hatch_polygons(e))
    col_union = unary_union(col_polys) if col_polys else Polygon()
    col_parts = [g for g in getattr(col_union, "geoms", [col_union]) if not g.is_empty]
    # Keep solid, roughly rectangular footprints: drops slivers, rings and
    # outlines of shafts/walls that happen to sit on a column layer.
    def _is_column(g):
        if not (0.02 / unit_m**2 <= g.area <= 6.0 / unit_m**2):
            return False
        rect = g.minimum_rotated_rectangle
        if rect.area <= 0 or g.area / rect.area < 0.75:
            return False
        xs = list(rect.exterior.coords)
        return max(math.dist(xs[0], xs[1]), math.dist(xs[1], xs[2])) * unit_m <= 3.0
    col_parts = [g for g in col_parts if _is_column(g)]

    col_marks = [(t, _text(t)) for t in texts if _layer_has(t, "COLUMN", "COL") and MARK_RE.match(_text(t) or "")]
    col_sizes = [(t, _text(t)) for t in texts if _layer_has(t, "COLUMN", "COL") and SIZE_RE.match(_text(t) or "")]

    columns: list[Column] = []
    for i, g in enumerate(col_parts):
        rect = g.minimum_rotated_rectangle
        xs = list(rect.exterior.coords)
        e1, e2 = math.dist(xs[0], xs[1]), math.dist(xs[1], xs[2])
        b_mm, d_mm = sorted((e1 * unit_m * 1000, e2 * unit_m * 1000))
        c = g.centroid
        mark = _nearest(col_marks, (c.x, c.y), 2.0 / unit_m)
        size = _nearest(col_sizes, (c.x, c.y), 3.0 / unit_m)
        conf = "high"
        if size:
            m = SIZE_RE.match(size)
            dims = sorted((int(m.group(1)), int(m.group(2))))
            if abs(dims[0] - round(b_mm)) > 15 or abs(dims[1] - round(d_mm)) > 15:
                conf = "medium"
        columns.append(Column(
            id=f"C{i + 1:03d}", breadth_mm=round(b_mm), depth_mm=round(d_mm), mark=mark,
            location=grid_ref(grids, c.x, c.y), size_label=size, confidence=conf,
        ))

    # Size labels with no column drawn nearby (reported for review)
    unmatched_col_sizes = Counter(
        s for t, s in col_sizes
        if not any(g.distance(Point(_xy(t.dxf.insert))) <= 1.5 / unit_m for g in col_parts)
    )

    # Beams: MLINEs on BEAM layers; element lines give the true outline
    size_labels = [(_xy(t.dxf.insert), _text(t)) for t in texts
                   if _layer_has(t, "BEAM") and SIZE_RE.match(_text(t) or "")]
    beam_marks = [(t, _text(t)) for t in texts
                  if _layer_has(t, "BEAM") and MARK_RE.match(_text(t) or "") and not SIZE_RE.match(_text(t))]
    beams: list[Beam] = []
    if not mlines:
        warnings.append("No beams drawn as multilines were found; beams must be added manually.")
    for seg in segments:
        (a, b), width_units = seg
        width_mm = round(width_units * unit_m * 1000)
        if width_mm < 80:
            continue
        line = LineString([a, b])
        clear = line.difference(col_union).length if col_parts else line.length
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)

        # Size label: nearest along the beam, preferring one whose width matches
        reach = max(1.5 / unit_m, 3 * width_units)
        near = sorted(
            ((_seg_dist(p, a, b), s) for p, s in size_labels),
            key=lambda x: x[0],
        )
        near = [(d, s) for d, s in near if d <= reach * 2][:6]
        match = next(((d, s) for d, s in near if abs(int(SIZE_RE.match(s).group(1)) - width_mm) <= 5), None)
        depth = None
        conf = "low"
        ev = "no size label near this beam"
        if match:
            d, s = match
            depth = int(SIZE_RE.match(s).group(2))
            conf = "high" if d <= 0.8 / unit_m else "medium"
            ev = f"label {s} {d * unit_m:.1f} m away, width matches drawn {width_mm} mm"
        elif near:
            ev = f"nearest label {near[0][1]} doesn't match drawn width {width_mm} mm"

        mark = _nearest(beam_marks, mid, 2.5 / unit_m, by_segment=(a, b))
        beams.append(Beam(
            id=f"B{len(beams) + 1:03d}", breadth_mm=width_mm, depth_mm=depth, mark=mark,
            length_m=round(line.length * unit_m, 3), clear_length_m=round(clear * unit_m, 3),
            location=grid_ref(grids, *mid), confidence=conf, evidence=ev, mid=mid,
            nearby_sizes=[s for _, s in near[:3]],
        ))

    # Slab thickness labels
    slab_labels = []
    for t in texts:
        s = _text(t)
        if s and _layer_has(t, "SLAB") and SLAB_RE.search(s):
            p = _xy(t.dxf.insert)
            slab_labels.append(TextLabel(s, grid_ref(grids, *p), p[0], p[1]))

    # Cut-outs / openings: bounding boxes of X-marks on CUTOUT/OPENING layers
    cut_geoms = []
    for e in ents:
        if not _layer_has(e, "CUTOUT", "CUT OUT", "OPENING", "SHAFT", "VOID"):
            continue
        try:
            ext = bbox.extents([e])
            if ext.has_data:
                cut_geoms.append(box(ext.extmin.x, ext.extmin.y, ext.extmax.x, ext.extmax.y))
        except Exception:
            continue
    cutouts = []
    for g in getattr(unary_union(cut_geoms), "geoms", [unary_union(cut_geoms)]) if cut_geoms else []:
        if g.is_empty:
            continue
        gx0, gy0, gx1, gy1 = g.bounds
        L, B = (gx1 - gx0) * unit_m, (gy1 - gy0) * unit_m
        if L * B < 0.1:  # IS 1200: openings ≤ 0.1 m² aren't deducted
            continue
        c = g.centroid
        cutouts.append(Cutout(grid_ref(grids, c.x, c.y), round(L, 3), round(B, 3), gx0, gy0, gx1, gy1))

    # Notes that may carry levels / heights / PT thickness
    notes = []
    for t in texts:
        s = " ".join(_text(t).split())
        if len(s) >= 6 and re.search(r"LVL|LEVEL|FFL|SFL|HEIGHT|\bHT\b|THK|NOTE|PT\b|[+-]\d+\.\d{2,3}", s, re.I):
            notes.append(s)
    notes = [s for s, _ in Counter(notes).most_common(80)]

    if unmatched_col_sizes:
        listed = ", ".join(f"{s} ×{n}" for s, n in unmatched_col_sizes.most_common(12))
        warnings.append(f"Column size labels with no column drawn nearby: {listed}")

    if not slab_labels:
        warnings.append("No slab thickness labels on this floor plan.")

    return FloorData(floor, unit_m, grids, beams, columns, slab_labels, cutouts, notes, warnings,
                     auto_grid=auto_grid)


def _mline_centre(e):
    """Centreline (a, b) and overall width, from the MLINE's element lines."""
    try:
        parts = [v for v in e.virtual_entities() if v.dxftype() == "LINE"]
    except Exception:
        parts = []
    if len(parts) >= 2:
        l1, l2 = parts[0], parts[-1]
        a1, b1 = _xy(l1.dxf.start), _xy(l1.dxf.end)
        a2, b2 = _xy(l2.dxf.start), _xy(l2.dxf.end)
        if math.dist(a1, a2) > math.dist(a1, b2):
            a2, b2 = b2, a2
        width = _seg_dist(a2, a1, b1)
        a = ((a1[0] + a2[0]) / 2, (a1[1] + a2[1]) / 2)
        b = ((b1[0] + b2[0]) / 2, (b1[1] + b2[1]) / 2)
        if math.dist(a, b) > 0 and width > 0:
            return (a, b), width
    v = e.vertices
    if len(v) < 2:
        return None
    return (_xy(v[0].location), _xy(v[-1].location)), abs(e.dxf.scale_factor)


def _nearest(items, p, max_d, by_segment=None):
    best, bd = None, max_d
    for t, s in items:
        q = _xy(t.dxf.insert)
        d = _seg_dist(q, *by_segment) if by_segment else math.dist(q, p)
        if d < bd:
            best, bd = s, d
    return best


# ─── Rendering (for Claude's visual read) ──────────────────────────────────


def render_floor_png(doc, floor: Floor, out_path: str, long_edge_px: int = 1568) -> str:
    x0, y0, x1, y1 = floor.window

    def inside(e):
        p = _anchor(e)
        return p is not None and x0 <= p[0] <= x1 and y0 <= p[1] <= y1

    msp = doc.modelspace()
    return render_window_png(doc, (e for e in msp if inside(e)), floor.window, out_path, long_edge_px)


def render_window_png(doc, entities, window, out_path: str, long_edge_px: int) -> str:
    """Draw `entities` black-on-white, cropped to `window` (x0, y0, x1, y1 in drawing units)."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from ezdxf.addons.drawing import Frontend, RenderContext
    from ezdxf.addons.drawing.config import BackgroundPolicy, ColorPolicy, Configuration
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

    x0, y0, x1, y1 = window
    w, h = x1 - x0, y1 - y0
    dpi = 100
    scale = long_edge_px / max(w, h)
    fig = plt.figure(figsize=(max(w * scale / dpi, 1), max(h * scale / dpi, 1)), dpi=dpi)
    ax = fig.add_axes([0, 0, 1, 1])
    cfg = Configuration(background_policy=BackgroundPolicy.WHITE, color_policy=ColorPolicy.BLACK)
    try:
        Frontend(RenderContext(doc), MatplotlibBackend(ax), config=cfg).draw_entities(entities)
        ax.set_xlim(x0, x1)
        ax.set_ylim(y0, y1)
        ax.set_aspect("equal")
        ax.axis("off")
        fig.savefig(out_path, dpi=dpi)
    finally:
        plt.close(fig)
    return out_path
