"""BBS arithmetic, following IS 2502 / SP 34 site practice. All lengths in mm.

    unit weight          = d² / 162 kg/m
    cut length           = Σ drawn legs (outer dimensions) − bend deductions + hook allowances
    bend deduction       = 45° → 1d, 90° → 2d, 135° → 3d, 180° → 4d
    stirrup (closed)     = 2(a + b) + 2 × hook − 3 × 90° deduction − 2 × 135° deduction
                           a = B − 2c, b = D − 2c, hook = max(10d, 75)
    bars longer than stock are split at laps: n = ⌈(L − S) / (S − lap)⌉ laps

Nothing here guesses a parameter: lap lengths and covers are passed in, and
anything missing is reported through `flags` on the bar.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

BEND_DEDUCTION_D = {45: 1, 90: 2, 135: 3, 180: 4}


def unit_weight(dia_mm: float) -> float:
    """kg per metre of a round bar (steel density 7850 kg/m³)."""
    return dia_mm * dia_mm / 162.0


def bend_deduction(dia_mm: float, angle: int) -> float:
    return BEND_DEDUCTION_D.get(int(angle), 0) * dia_mm


def stirrup_hook(dia_mm: float) -> float:
    return max(10 * dia_mm, 75.0)


def shape_of(bends: list[int], hooks: int, closed: bool = False) -> tuple[str, str]:
    """(code, name). Codes follow the BS 8666 / IS 2502-style numbering most
    Indian site BBS sheets use."""
    if closed:
        return "51", "Stirrup / ring (closed, 135° hooks)"
    n = len([b for b in bends if b])
    if n == 0 and hooks == 0:
        return "00", "Straight"
    if n == 1:
        return "11", "L-bar (one bend)"
    if n == 2 and all(b == 90 for b in bends):
        return "21", "U-bar (both ends bent)"
    if any(b == 45 for b in bends):
        return "41", "Cranked bar"
    return "99", f"Bent bar ({n} bends)"


def split_at_laps(length: float, stock: float, lap: float | None) -> tuple[list[float], int]:
    """Pieces to cut for one bar of `length` from `stock`-long bars, lapping as needed.

    Returns (pieces, number_of_laps). If a lap is needed but `lap` is unknown,
    the bar is returned whole (the caller flags it)."""
    if length <= stock or not lap:
        return [length], 0
    if lap >= stock:
        return [length], 0
    n = math.ceil((length - stock) / (stock - lap))
    total = length + n * lap
    pieces = [stock] * n + [round(total - n * stock, 1)]
    return pieces, n


@dataclass
class Bar:
    """One line of the bar bending schedule."""
    mark: str                  # bar mark, e.g. "PB-19F/T1"
    member: str                # member mark(s), e.g. "PB-19F"
    member_type: str           # beam / column / slab / footing / wall / other
    location: str
    description: str           # e.g. "Top continuous", "Extra top at support", "Stirrup"
    dia: int
    legs: list[float]          # drawn straight segments, outer dimensions (mm)
    bends: list[int] = field(default_factory=list)   # bend angles between legs
    hooks: int = 0             # 135° stirrup-type hooks
    closed: bool = False       # closed stirrup / ring
    nos_per_member: int = 1
    members: int = 1
    confidence: str = "high"
    evidence: str = ""
    flags: list[str] = field(default_factory=list)

    @property
    def shape(self) -> tuple[str, str]:
        return shape_of(self.bends, self.hooks, self.closed)

    @property
    def cut_length(self) -> float:
        L = sum(self.legs)
        L -= sum(bend_deduction(self.dia, a) for a in self.bends)
        L += self.hooks * stirrup_hook(self.dia)
        return round(L, 1)

    @property
    def total_nos(self) -> int:
        return self.nos_per_member * self.members


def stirrups(*, mark: str, member: str, member_type: str, location: str, dia: int,
             breadth: float, depth: float, cover: float | None, count: int, members: int = 1,
             legs: int = 2, zone_note: str = "", confidence: str = "high") -> list[Bar]:
    """Closed stirrups with two 135° hooks for one zone.

    2-legged → one ring a × b. 4-legged → an outer ring a × b plus an inner
    ring over the middle bars, taken as a/2 wide (a common detailing
    arrangement; the line is flagged so the width can be checked).
    """
    flags = []
    if cover is None:
        flags.append("Cover not stated in drawing — confirm")
        cover = 0
    a = breadth - 2 * cover
    b = depth - 2 * cover

    def ring(suffix, width, extra_flags):
        return Bar(
            mark=f"{mark}{suffix}", member=member, member_type=member_type, location=location,
            description=f"Stirrup {legs}L{' (inner)' if suffix else ''} {zone_note}".strip(), dia=dia,
            legs=[width, b, width, b],
            bends=[90, 90, 90, 135, 135],   # 3 corners + the two 135° hook bends
            hooks=2, closed=True, nos_per_member=count, members=members,
            confidence=confidence, evidence=zone_note, flags=flags + extra_flags,
        )

    out = [ring("", a, [])]
    if legs >= 4:
        out.append(ring("i", round(a / 2, 1), ["Inner ring width taken as half the outer — check detail"]))
    return out


def stirrup_count(zone_length: float, spacing: float) -> int:
    """Stirrups in a zone of given length at given spacing (both ends included)."""
    if spacing <= 0:
        return 0
    return int(math.floor(zone_length / spacing)) + 1


def bar_weight_kg(bar: Bar, extra_lap_mm: float = 0.0) -> float:
    per_bar = (bar.cut_length + extra_lap_mm) / 1000.0
    return round(per_bar * bar.total_nos * unit_weight(bar.dia), 3)
