"""Read reinforcement details from a structural DXF.

Deterministic first: the code finds each continuous beam drawn in elevation,
its supports, span marks, drawn bars (legs and bends), bar callouts and
stirrup zones, and associates them by position. Anything it can't pair with
confidence is returned as an `issue` for Claude / the user to resolve.

Conventions seen in Indian consultant drawings (and handled here):
  * beam elevation outline as a closed polyline ("beam cover" style layer)
  * columns drawn under the beam as supports
  * span marks under each span: "PB-19F(230X450)", "B-12A (450X450)"
  * callouts above the beam = top steel, below = bottom steel
      "2-12# Cont."  → continuous bars      "+3-16# Extra" → extra bars
  * extra bars drawn as short polylines over supports (their true extent)
  * stirrup zones as dimensions: "#8@200c/c", "4L-#8@200c/c"
  * general notes: steel grade, lap table (grade → n×Ø), cover table
"""
from __future__ import annotations

import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field

from app.services.takeoff.drawing import _anchor, _text, _xy, load, units_to_m  # noqa: F401

CALLOUT_RE = re.compile(
    r"^\s*(?P<plus>\+)?\s*(?P<n>\d{1,2})\s*(?:-|–|x|X)?\s*#?\s*(?P<dia>\d{1,2})\s*#?\s*(?:mm)?\s*"
    r"(?P<kind>CONT\.?|CONTINUOUS|EXTRA|EXT\.?)?\b",
    re.I,
)
MARK_RE = re.compile(r"^\s*(?P<mark>[A-Z]{1,4}\s*-\s*\d+[A-Z]?)\s*\(\s*(?P<b>\d{2,4})\s*[Xx×]\s*(?P<d>\d{2,4})\s*\)")
STIRRUP_RE = re.compile(r"(?:(?P<legs>\d)\s*[lL]\s*-\s*)?[#Ø]?\s*(?P<dia>\d{1,2})\s*@\s*(?P<sp>\d{2,4})", re.I)


# ─── Notes: steel grade, lap table, covers ─────────────────────────────────


@dataclass
class DrawingNotes:
    steel_grade: str | None = None
    concrete_grade: str | None = None
    lap_table: dict[str, int] = field(default_factory=dict)   # "M-20" → 48 (× Ø)
    lap_table_label: str | None = None                        # e.g. "Ldt"
    covers_mm: dict[str, int] = field(default_factory=dict)   # "columns" → 40
    raw: list[str] = field(default_factory=list)
    issues: list[str] = field(default_factory=list)


def read_notes(doc) -> DrawingNotes:
    """General notes are usually in paper space; model space is searched too."""
    notes = DrawingNotes()
    texts = []
    for lay in doc.layouts:
        for t in lay.query("TEXT MTEXT"):
            s = " ".join(_text(t).split())
            if s:
                p = _xy(t.dxf.insert)
                texts.append((lay.name, p[0], p[1], s))

    joined = " ".join(s for *_, s in texts)
    m = re.search(r"Fe\s*-?\s*(\d{3})\s*D?|STRENGTH\s+(\d{3})\s*N", joined, re.I)
    if m:
        notes.steel_grade = f"Fe{m.group(1) or m.group(2)}"
    m = re.search(r"GRADE OF CONCRETE SHALL BE\s+(M\s*-?\s*\d{2})", joined, re.I)
    if m:
        notes.concrete_grade = m.group(1).replace(" ", "").upper().replace("M", "M-").replace("--", "-")

    # Lap table: rows of "M-20 … 48Ø" laid out as a small table next to "CONC.GRADE"
    for lay, x, y, s in texts:
        if re.fullmatch(r"CONC\.?\s*GRADE", s, re.I):
            rows = [(tx, ty, ts) for l2, tx, ty, ts in texts
                    if l2 == lay and 0 <= y - ty <= 40 * _row_h(texts, lay, x, y) and abs(tx - x) < 60 * _row_h(texts, lay, x, y)]
            grades = sorted([(ty, tx, ts) for tx, ty, ts in rows if re.fullmatch(r"M\s*-?\s*\d{2}", ts, re.I)], reverse=True)
            factors = sorted([(ty, tx, ts) for tx, ty, ts in rows
                              if re.fullmatch(r"\d{2}\s*(%%C|Ø|D|Φ|φ|DIA)", ts, re.I)], reverse=True)
            label = next((ts for tx, ty, ts in rows if ts.upper() in ("LDT", "LD", "LAP", "LAP LENGTH") and abs(ty - y) < 3 * _row_h(texts, lay, x, y)), None)
            used = set()
            for gy, gx, g in grades:
                cand = min((f for f in factors if f not in used), key=lambda f: abs(f[0] - gy), default=None)
                if cand is None or abs(cand[0] - gy) > 2 * _row_h(texts, lay, x, y):
                    continue
                used.add(cand)
                key = g.replace(" ", "").upper().replace("M", "M-").replace("--", "-")
                val = int(re.match(r"\d{2}", cand[2]).group())
                if key in notes.lap_table and notes.lap_table[key] != val:
                    notes.issues.append(f"Lap table lists {key} twice ({notes.lap_table[key]}Ø and {val}Ø) — confirm which applies.")
                    key = f"{key} (2)"
                notes.lap_table[key] = val
            notes.lap_table_label = label
            if notes.lap_table:
                break

    # Covers: "FOOTING 2"(50MM.)", "COLUMNS 1 1/2"(40MM.)", …
    member_words = {
        "footing": r"FOOTING", "columns": r"COLUMN", "beams": r"\bBEAM", "slab": r"SLAB\s*&\s*ROOF|^SLAB$",
        "walls": r"WALLS", "water tank": r"WATER TANK",
    }
    for lay, x, y, s in texts:
        for key, pat in member_words.items():
            if re.search(pat, s, re.I) and len(s) < 30 and key not in notes.covers_mm:
                h = _row_h(texts, lay, x, y)
                vals = sorted(
                    (abs(ty - y), tx, int(mm.group(1))) for l2, tx, ty, ts in texts
                    if l2 == lay and tx > x and abs(ty - y) <= 1.5 * h and tx - x < 60 * h
                    for mm in [re.search(r"\((\d{2})\s*MM", ts, re.I)] if mm
                )
                if vals:
                    # value on the label's own row wins; otherwise the nearest row
                    notes.covers_mm[key] = vals[0][2]
    if not notes.lap_table:
        notes.issues.append("No lap-length table found in the drawing notes.")
    if notes.concrete_grade and notes.lap_table and notes.concrete_grade not in notes.lap_table:
        notes.issues.append(
            f"Concrete is {notes.concrete_grade} but the lap table only lists "
            f"{', '.join(notes.lap_table)} — choose the lap to use.")
    if "beams" not in notes.covers_mm:
        notes.issues.append("Clear cover for beams is not stated in the notes — enter it.")
    notes.raw = sorted({s for *_, s in texts if len(s) > 60 and re.search(r"LAP|COVER|GRADE|STEEL|Fe", s, re.I)})[:12]
    return notes


def _row_h(texts, lay, x, y) -> float:
    """Typical text row pitch near a point (used to scale table searches)."""
    ys = sorted(ty for l2, tx, ty, _ in texts if l2 == lay and abs(tx - x) < 200 and 0 < y - ty < 200)
    gaps = [b - a for a, b in zip(ys, ys[1:]) if b - a > 0.5]
    return (sorted(gaps)[len(gaps) // 2] if gaps else 5.0)


# ─── Beam elevations ───────────────────────────────────────────────────────


@dataclass
class DrawnBar:
    id: str
    position: str            # top / bottom
    x0: float
    x1: float
    y: float
    legs: list[float]        # mm
    bends: list[int]
    spans_full: bool         # runs (almost) the whole beam


@dataclass
class Callout:
    text: str
    n: int
    dia: int
    kind: str                # cont / extra
    position: str            # top / bottom
    x: float
    y: float


@dataclass
class StirrupZone:
    text: str
    dia: int
    spacing: int
    legs: int
    length: float            # mm, zone length from the dimension
    x0: float
    x1: float


@dataclass
class Span:
    mark: str
    b: int
    d: int
    x0: float                # clear span, support face to support face
    x1: float


@dataclass
class BeamStrip:
    id: str
    x0: float
    x1: float
    y_bot: float
    y_top: float
    spans: list[Span]
    supports: list[tuple[float, float]]
    bars: list[DrawnBar]
    callouts: list[Callout]
    stirrups: list[StirrupZone]
    issues: list[str] = field(default_factory=list)

    @property
    def length(self) -> float:
        return self.x1 - self.x0

    @property
    def marks(self) -> list[str]:
        return [s.mark for s in self.spans]


def _poly_legs(pts, scale):
    """Legs (mm) and bend angles of a polyline, merging collinear segments."""
    segs = []
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b) * scale
        if L < 1:
            continue
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        if segs and abs(((ang - segs[-1][1] + 180) % 360) - 180) < 8:
            segs[-1][0] += L
        else:
            segs.append([L, ang])
    legs = [round(s[0], 1) for s in segs]
    bends = []
    for s1, s2 in zip(segs, segs[1:]):
        turn = abs(((s2[1] - s1[1] + 180) % 360) - 180)
        bends.append(45 if turn < 67 else 90 if turn < 112 else 135 if turn < 157 else 180)
    # short end bits under 40 mm are drafting noise (chamfered corners)
    while len(legs) > 1 and legs[0] < 40:
        legs.pop(0)
        bends.pop(0)
    while len(legs) > 1 and legs[-1] < 40:
        legs.pop()
        bends.pop()
    return legs, bends


def read_beams(doc) -> list[BeamStrip]:
    msp = doc.modelspace()
    scale = units_to_m(doc) * 1000  # drawing units → mm

    outlines = []
    steel = []
    supports = []
    texts = []
    rings = []
    for e in msp:
        L = e.dxf.layer.upper()
        t = e.dxftype()
        if t == "LWPOLYLINE":
            pts = [(p[0], p[1]) for p in e.get_points()]
            if len(pts) < 2:
                continue
            if "COVER" in L and "BEAM" in L and (e.closed or math.dist(pts[0], pts[-1]) < 5):
                outlines.append(pts)
            elif "STEEL" in L and "SLAB" not in L:
                steel.append(pts)
            elif "COLUMN" in L or L in ("COL",):
                supports.append(pts)
        elif t in ("TEXT", "MTEXT"):
            s = " ".join(_text(e).split())
            if s:
                texts.append((s, _xy(e.dxf.insert)))
        elif t == "DIMENSION" and ("RING" in L or "STIRR" in L):
            txt = (e.dxf.get("text") or "").replace("\\P", " ")
            txt = re.sub(r"\{\\[^;]*;|\\f[^;]*;|[{}]", "", txt)
            m = STIRRUP_RE.search(txt)
            if m:
                p1, p2 = e.dxf.get("defpoint2"), e.dxf.get("defpoint3")
                xs = sorted([p1.x, p2.x]) if p1 is not None and p2 is not None else [e.dxf.defpoint.x] * 2
                rings.append(StirrupZone(txt.strip(), int(m.group("dia")), int(m.group("sp")),
                                         int(m.group("legs") or 2), round(e.get_measurement() * scale),
                                         xs[0], xs[1]))
                rings[-1].y = (p1.y if p1 is not None else e.dxf.defpoint.y)  # type: ignore[attr-defined]

    # Beam bands first, so every label can go to its single nearest beam
    bands = []
    for pts in outlines:
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        x0, x1, yb, yt = min(xs), max(xs), min(ys), max(ys)
        if yt - yb > 0 and x1 - x0 >= 3 * (yt - yb):
            bands.append((x0, x1, yb, yt))

    def nearest_band(tx, ty):
        best, bd = None, None
        for k, (x0, x1, yb, yt) in enumerate(bands):
            depth = yt - yb
            if not (x0 - depth <= tx <= x1 + depth):
                continue
            dy = ty - yt if ty > yt else (yb - ty if ty < yb else 0)
            if dy <= 5 * depth and (bd is None or dy < bd):
                best, bd = k, dy
        return best

    label_band = {}
    for idx, (s_, (tx, ty)) in enumerate(texts):
        if MARK_RE.match(s_) or CALLOUT_RE.match(s_):
            label_band[idx] = nearest_band(tx, ty)

    strips: list[BeamStrip] = []
    for i, pts in enumerate(outlines):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        x0, x1, yb, yt = min(xs), max(xs), min(ys), max(ys)
        depth = yt - yb
        if x1 - x0 < 3 * depth or depth <= 0:
            continue  # not a beam elevation
        pad = 2.5 * depth
        strip = BeamStrip(f"S{i + 1:03d}", x0, x1, yb, yt, [], [], [], [], [])

        # supports: column outlines touching the beam soffit within its length
        sup = []
        for c in supports:
            cx, cy = [p[0] for p in c], [p[1] for p in c]
            if min(cx) >= x0 - 5 and max(cx) <= x1 + 5 and max(cy) >= yb - 0.3 * depth and min(cy) < yb:
                sup.append((min(cx), max(cx)))
        strip.supports = sorted(set(sup))

        # span marks below the beam
        band_idx = next((k for k, b in enumerate(bands) if b == (x0, x1, yb, yt)), None)
        marks = []
        for idx, (s, (tx, ty)) in enumerate(texts):
            m = MARK_RE.match(s)
            if m and label_band.get(idx) == band_idx and ty < yb:
                marks.append((tx, m.group("mark").replace(" ", ""), int(m.group("b")), int(m.group("d"))))
        faces = [x0] + [v for a, b in strip.supports for v in (a, b)] + [x1]
        bays = []
        edges = sorted(set([x0, x1] + [v for s in strip.supports for v in s]))
        # clear spans are the gaps between consecutive supports (or beam ends)
        ranges = []
        cur = x0
        for a, b in strip.supports:
            if a - cur > depth * 0.5:
                ranges.append((cur, a))
            cur = max(cur, b)
        if x1 - cur > depth * 0.5:
            ranges.append((cur, x1))
        for tx, mark, b, d in sorted(marks):
            rng = min(ranges, key=lambda r: 0 if r[0] <= tx <= r[1] else min(abs(tx - r[0]), abs(tx - r[1])),
                      default=(x0, x1))
            bays.append(Span(mark, b, d, rng[0], rng[1]))
        strip.spans = bays
        if not bays:
            strip.issues.append("No span marks found under this beam.")

        # drawn bars inside the beam band
        mid = (yb + yt) / 2
        for j, bp in enumerate(steel):
            bx, by = [p[0] for p in bp], [p[1] for p in bp]
            if not (min(bx) >= x0 - depth and max(bx) <= x1 + depth and yb - 0.2 * depth <= min(by) and max(by) <= yt + 0.2 * depth):
                continue
            # position from the longest horizontal run
            best = max(zip(bp, bp[1:]), key=lambda s: abs(s[1][0] - s[0][0]))
            yline = (best[0][1] + best[1][1]) / 2
            legs, bends = _poly_legs(bp, scale)
            strip.bars.append(DrawnBar(
                f"{strip.id}-b{j}", "top" if yline > mid else "bottom", min(bx), max(bx), yline,
                legs, bends, (max(bx) - min(bx)) >= 0.9 * (x1 - x0),
            ))

        # callouts above / below
        for idx, (s, (tx, ty)) in enumerate(texts):
            m = CALLOUT_RE.match(s)
            if not m or label_band.get(idx) != band_idx:
                continue
            if ty > yt:
                pos = "top"
            elif ty < yb:
                pos = "bottom"
            else:
                continue
            kind = "extra" if (m.group("plus") or (m.group("kind") or "").upper().startswith("EXT")) else "cont"
            strip.callouts.append(Callout(s, int(m.group("n")), int(m.group("dia")), kind, pos, tx, ty))

        # stirrup zones dimensioned along this beam
        for z in rings:
            zy = getattr(z, "y", None)
            if zy is not None and yb - pad <= zy <= yt + pad and z.x0 >= x0 - depth and z.x1 <= x1 + depth:
                strip.stirrups.append(z)
        if not strip.stirrups:
            strip.issues.append("No stirrup zones dimensioned on this beam — enter stirrup dia and spacing.")
        strips.append(strip)
    return strips


# ─── (de)serialisation, so a job can rebuild the BBS without re-reading the drawing ───


def _plain(v):
    """NumPy scalars (from geometry maths) → plain Python, so json can store them."""
    if isinstance(v, dict):
        return {k: _plain(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_plain(x) for x in v]
    if hasattr(v, "item") and not isinstance(v, (str, bytes)):
        return v.item()
    return v


def strips_to_json(strips: list[BeamStrip]) -> list[dict]:
    from dataclasses import asdict
    return [_plain(asdict(s)) for s in strips]


def strips_from_json(data: list[dict]) -> list[BeamStrip]:
    out = []
    for d in data:
        out.append(BeamStrip(
            id=d["id"], x0=d["x0"], x1=d["x1"], y_bot=d["y_bot"], y_top=d["y_top"],
            spans=[Span(**s) for s in d["spans"]],
            supports=[tuple(s) for s in d["supports"]],
            bars=[DrawnBar(**b) for b in d["bars"]],
            callouts=[Callout(**c) for c in d["callouts"]],
            stirrups=[StirrupZone(**z) for z in d["stirrups"]],
            issues=list(d.get("issues", [])),
        ))
    return out


def notes_to_json(n: DrawingNotes) -> dict:
    from dataclasses import asdict
    return _plain(asdict(n))
