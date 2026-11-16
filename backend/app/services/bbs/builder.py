"""Turn what the reader found (beam strips) + confirmed settings into BBS lines.

Every assumption is written onto the line (`flags`) so the checker sees it:
  * drawn bars are measured as drawn (legs and bends from the polyline)
  * a callout with no drawn bar → length taken from the beam, flagged
  * a drawn bar with no callout → count/dia unknown, flagged, not weighed
  * stirrup zones → count from zone length ÷ spacing + 1
  * bars longer than stock → split at laps using the chosen lap factor
"""
from __future__ import annotations

from collections import Counter
from dataclasses import asdict, dataclass, field

from app.services.bbs.engine import Bar, split_at_laps, stirrup_count, stirrups, unit_weight
from app.services.bbs.reader import BeamStrip


@dataclass
class Settings:
    lap_factor: int | None = None          # lap = factor × Ø (from the drawing's lap table)
    cover_beam_mm: int | None = None       # clear cover to main bars / stirrups in beams
    stock_mm: dict[int, int] = field(default_factory=dict)   # dia → stock length
    default_stock_mm: int = 12000
    min_reuse_mm: int = 1000
    offcuts_mm: dict[int, list[int]] = field(default_factory=dict)  # dia → existing site offcuts
    multiplier: int = 1                    # identical blocks/wings built from this drawing

    def stock_for(self, dia: int) -> int:
        return int(self.stock_mm.get(dia) or self.default_stock_mm)


def _member_label(strip: BeamStrip) -> str:
    marks = strip.marks
    if not marks:
        return strip.id
    if len(marks) <= 4:
        return ", ".join(marks)
    return f"{marks[0]} … {marks[-1]} ({len(marks)} spans)"


def _size(strip: BeamStrip) -> tuple[int, int] | None:
    sizes = Counter((s.b, s.d) for s in strip.spans)
    return sizes.most_common(1)[0][0] if sizes else None


def build_beam_bars(strips: list[BeamStrip], st: Settings) -> tuple[list[Bar], list[str]]:
    bars: list[Bar] = []
    issues: list[str] = []
    for strip in strips:
        member = _member_label(strip)
        size = _size(strip)
        loc = f"Beam line {strip.id}"
        seq = Counter()

        def mark(prefix):
            seq[prefix] += 1
            return f"{strip.id}-{prefix}{seq[prefix]}"

        for pos in ("top", "bottom"):
            conts = [c for c in strip.callouts if c.position == pos and c.kind == "cont"]
            extras = [c for c in strip.callouts if c.position == pos and c.kind == "extra"]
            drawn = [b for b in strip.bars if b.position == pos]
            full = [b for b in drawn if b.spans_full]
            partial = [b for b in drawn if not b.spans_full]
            used_extra = set()

            # continuous bars
            if conts:
                spec = Counter((c.n, c.dia) for c in conts)
                (n, dia), _ = spec.most_common(1)[0]
                flags = []
                if len(spec) > 1:
                    flags.append("Continuous callouts differ between spans: "
                                 + ", ".join(f"{a}-{b}#" for a, b in spec) + " — check curtailment")
                if full:
                    b = full[0]
                    legs, bends, conf, ev = b.legs, b.bends, "high", "measured from drawn bar"
                else:
                    # not drawn: straight run over the beam less end cover, bent into supports
                    cover = st.cover_beam_mm or 0
                    depth_leg = (size[1] - 2 * cover) if size else 0
                    legs = [depth_leg, strip.length - 2 * cover, depth_leg] if depth_leg else [strip.length - 2 * cover]
                    bends = [90, 90] if depth_leg else []
                    conf, ev = "low", "bar not drawn — length taken from beam length"
                    flags.append("Continuous bar not drawn; length and end bends assumed from the beam")
                bars.append(Bar(
                    mark=mark("T" if pos == "top" else "B"), member=member, member_type="beam", location=loc,
                    description=f"{pos.title()} continuous", dia=dia, legs=legs, bends=bends,
                    nos_per_member=n, confidence=conf, evidence=ev, flags=flags,
                ))
            elif full:
                b = full[0]
                bars.append(Bar(
                    mark=mark("T" if pos == "top" else "B"), member=member, member_type="beam", location=loc,
                    description=f"{pos.title()} continuous", dia=0, legs=b.legs, bends=b.bends,
                    nos_per_member=0, confidence="low", evidence="drawn bar without a callout",
                    flags=["No callout for this drawn bar — enter number and dia"],
                ))

            # extra bars over supports / at mid-span
            for b in partial:
                cx = (b.x0 + b.x1) / 2
                depth = (strip.y_top - strip.y_bot)
                cands = [(abs(c.x - cx), k, c) for k, c in enumerate(extras)
                         if k not in used_extra and b.x0 - depth <= c.x <= b.x1 + depth]
                if cands:
                    _, k, c = min(cands, key=lambda t: t[0])
                    used_extra.add(k)
                    bars.append(Bar(
                        mark=mark("TE" if pos == "top" else "BE"), member=member, member_type="beam",
                        location=f"{loc}, x≈{(cx - strip.x0) / 1000:.1f} m",
                        description=f"Extra {pos}", dia=c.dia, legs=b.legs, bends=b.bends,
                        nos_per_member=c.n, confidence="high", evidence=f"drawn bar + callout '{c.text}'",
                    ))
                else:
                    bars.append(Bar(
                        mark=mark("TE" if pos == "top" else "BE"), member=member, member_type="beam",
                        location=f"{loc}, x≈{(cx - strip.x0) / 1000:.1f} m",
                        description=f"Extra {pos} (no callout)", dia=0, legs=b.legs, bends=b.bends,
                        nos_per_member=0, confidence="low", evidence="drawn bar without a callout",
                        flags=["No callout for this drawn bar — enter number and dia"],
                    ))
            for k, c in enumerate(extras):
                if k not in used_extra:
                    issues.append(f"{member}: '{c.text}' ({pos}) at x≈{(c.x - strip.x0) / 1000:.1f} m "
                                  "has no drawn bar — length unknown, add it manually.")

        # stirrups
        if strip.stirrups:
            for z in strip.stirrups:
                zmid = (z.x0 + z.x1) / 2
                span = next((s for s in strip.spans if s.x0 - 1 <= zmid <= s.x1 + 1), None)
                b_d = (span.b, span.d) if span else size
                if not b_d:
                    issues.append(f"{member}: stirrup zone '{z.text}' — beam size unknown.")
                    continue
                n = stirrup_count(z.length, z.spacing)
                bars.extend(stirrups(
                    mark=mark("S"), member=span.mark if span else member, member_type="beam",
                    location=loc, dia=z.dia, breadth=b_d[0], depth=b_d[1], cover=st.cover_beam_mm,
                    count=n, legs=z.legs, zone_note=f"{z.text} over {z.length / 1000:.2f} m",
                ))
        else:
            issues.append(f"{member}: no stirrup zones dimensioned — add stirrups manually.")

    for b in bars:
        b.members = max(1, int(st.multiplier or 1))
    for b in bars:
        if b.dia and b.cut_length > 0 and st.lap_factor is None and b.cut_length > st.stock_for(b.dia):
            b.flags.append("Longer than stock but lap length not set — choose the lap in settings")
    return bars, issues


# ─── BBS lines & cutting pieces ────────────────────────────────────────────


def bbs_lines(bars: list[Bar], st: Settings) -> list[dict]:
    from app.services.bbs.reader import _plain
    return _plain(_bbs_lines(bars, st))


def _bbs_lines(bars: list[Bar], st: Settings) -> list[dict]:
    out = []
    for i, b in enumerate(bars, start=1):
        cut = b.cut_length
        stock = st.stock_for(b.dia) if b.dia else st.default_stock_mm
        lap = st.lap_factor * b.dia if (st.lap_factor and b.dia) else None
        pieces, laps = split_at_laps(cut, stock, lap) if b.dia else ([cut], 0)
        length_each = sum(pieces)                      # includes lap overlap steel
        total_m = length_each * b.total_nos / 1000
        code, shape = b.shape
        weight = round(total_m * unit_weight(b.dia), 3) if b.dia else 0.0
        out.append({
            "sno": i, "mark": b.mark, "member": b.member, "member_type": b.member_type,
            "location": b.location, "description": b.description, "dia": b.dia,
            "shape_code": code, "shape": shape, "legs": b.legs, "bends": b.bends, "hooks": b.hooks,
            "closed": b.closed, "cut_length": cut, "nos_per_member": b.nos_per_member,
            "members": b.members, "total_nos": b.total_nos, "laps_per_bar": laps,
            "lap_mm": lap, "pieces": pieces, "total_length_m": round(total_m, 3),
            "unit_wt": round(unit_weight(b.dia), 3) if b.dia else 0, "weight_kg": weight,
            "confidence": b.confidence, "evidence": b.evidence, "flags": list(b.flags),
        })
    return out


def pieces_by_dia(lines: list[dict]) -> dict[int, list[tuple[int, int, str]]]:
    by: dict[int, list[tuple[int, int, str]]] = {}
    for ln in lines:
        if not ln["dia"] or not ln["total_nos"] or ln["cut_length"] <= 0:
            continue
        for p in ln["pieces"]:
            by.setdefault(int(ln["dia"]), []).append((int(round(p)), int(ln["total_nos"]), ln["mark"]))
    return by


def settings_from_dict(d: dict) -> Settings:
    return Settings(
        lap_factor=d.get("lap_factor"),
        cover_beam_mm=d.get("cover_beam_mm"),
        stock_mm={int(k): int(v) for k, v in (d.get("stock_mm") or {}).items() if v},
        default_stock_mm=int(d.get("default_stock_mm") or 12000),
        min_reuse_mm=int(d.get("min_reuse_mm") or 1000),
        offcuts_mm={int(k): [int(x) for x in v] for k, v in (d.get("offcuts_mm") or {}).items()},
        multiplier=max(1, int(d.get("multiplier") or 1)),
    )


def settings_to_dict(s: Settings) -> dict:
    return asdict(s)
