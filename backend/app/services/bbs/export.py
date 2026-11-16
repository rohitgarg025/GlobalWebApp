"""Excel output: BBS (IS 2502 format), dia summary, cutting plan, offcut register, issues."""
from __future__ import annotations

from collections import Counter
from datetime import datetime
from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HEAD = PatternFill("solid", fgColor="F1F3F6")
TOTAL = PatternFill("solid", fgColor="DCE6F2")
FLAG = PatternFill("solid", fgColor="FFF4E5")
thin = Side(style="thin", color="D9DDE3")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
BOLD = Font(bold=True)


def _header(ws, row, cols):
    for c, (label, width) in enumerate(cols, start=1):
        cell = ws.cell(row=row, column=c, value=label)
        cell.font, cell.fill, cell.border = BOLD, HEAD, BORDER
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        ws.column_dimensions[get_column_letter(c)].width = width
    ws.row_dimensions[row].height = 30


def _title(ws, title, meta):
    ws["A1"] = title
    ws["A1"].font = Font(bold=True, size=14)
    for i, (k, v) in enumerate(meta, start=2):
        ws.cell(row=i, column=1, value=k).font = Font(color="666666", size=9)
        ws.cell(row=i, column=3, value=v)
    return len(meta) + 3


def _allocate(lines: list[dict], plans: dict) -> dict:
    """Assign each cut piece to a bar mark, pattern by pattern (first marks first),
    so the cutting plan says which BBS line every piece is for.
    Returns {(dia, pattern index): {length: Counter(mark → pieces)}}."""
    from collections import defaultdict
    queue: dict[tuple[int, int], list[list]] = defaultdict(list)   # (dia, length) → [[mark, remaining]]
    for ln in lines:
        if not ln.get("dia") or not ln.get("total_nos"):
            continue
        for piece in ln.get("pieces") or []:
            queue[(int(ln["dia"]), int(round(piece)))].append([ln["mark"], int(ln["total_nos"])])
    out = {}
    for dia, p in plans.items():
        for k, pat in enumerate(p.get("patterns", [])):
            per_len: dict[int, Counter] = defaultdict(Counter)
            for _ in range(pat["repeat"]):
                for L in pat["cuts"]:
                    q = queue.get((int(dia), int(L)), [])
                    while q and q[0][1] == 0:
                        q.pop(0)
                    if q:
                        q[0][1] -= 1
                        per_len[L][q[0][0]] += 1
            out[(int(dia), k)] = per_len
    return out


def build(*, drawing: str, lines: list[dict], plans: dict, summary: dict, notes: dict,
          settings: dict, issues: list[str], prepared_by: str | None) -> tuple[bytes, str]:
    wb = Workbook()
    lap = settings.get("lap_factor")
    meta = [
        ("Drawing", drawing),
        ("Steel", notes.get("steel_grade") or "not stated"),
        ("Concrete", notes.get("concrete_grade") or "not stated"),
        ("Lap length", f"{lap} × Ø" if lap else "NOT SET — bars longer than stock are not lapped"),
        ("Beam cover", f"{settings.get('cover_beam_mm')} mm" if settings.get("cover_beam_mm") else "NOT SET"),
        ("Stock bar", f"{settings.get('default_stock_mm', 12000) / 1000:g} m"
                      + (" (per-dia overrides)" if settings.get("stock_mm") else "")),
        ("Identical blocks", settings.get("multiplier", 1)),
        ("Prepared", f"{datetime.now():%d/%m/%Y %H:%M}" + (f" by {prepared_by}" if prepared_by else "")),
    ]

    # ── BBS ──
    ws = wb.active
    ws.title = "BBS"
    r0 = _title(ws, "BAR BENDING SCHEDULE", meta)
    ws.cell(row=r0 - 1, column=1, value="Read from the drawing by software; verify against the drawing "
            "before issue to site.").font = Font(italic=True, color="B45309", size=9)
    cols = [("S.No", 6), ("Bar mark", 12), ("Member", 26), ("Location", 22), ("Description", 26),
            ("Dia (mm)", 7), ("Shape code", 7), ("Shape", 22), ("a", 8), ("b", 8), ("c", 8), ("d", 8),
            ("Cut length (mm)", 10), ("Nos / member", 8), ("Members", 8), ("Total nos", 8), ("Laps / bar", 7),
            ("Total length (m)", 10), ("Unit wt (kg/m)", 8), ("Weight (kg)", 10), ("Remarks", 50)]
    _header(ws, r0, cols)
    ws.freeze_panes = ws.cell(row=r0 + 1, column=3)
    r = r0 + 1
    first = r
    for ln in lines:
        legs = (ln.get("legs") or []) + [None] * 4
        vals = [ln["sno"], ln["mark"], ln["member"], ln["location"], ln["description"], ln["dia"] or None,
                ln["shape_code"], ln["shape"], *[round(x) if x else None for x in legs[:4]],
                ln["cut_length"], ln["nos_per_member"], ln["members"], None, ln["laps_per_bar"],
                ln["total_length_m"], ln["unit_wt"] or None, None, "; ".join(ln.get("flags") or [])]
        for c, v in enumerate(vals, start=1):
            cell = ws.cell(row=r, column=c, value=v)
            cell.border = BORDER
        ws.cell(row=r, column=16, value=f"=N{r}*O{r}").border = BORDER            # total nos
        if ln["dia"]:
            u = ws.cell(row=r, column=19, value=f"=F{r}^2/162")                  # exact unit weight
            u.border, u.number_format = BORDER, "0.000"
        w = ws.cell(row=r, column=20, value=f"=ROUND(R{r}*S{r},3)")              # weight = length × unit wt
        w.border, w.number_format = BORDER, "0.000"
        ws.cell(row=r, column=18).number_format = "0.000"
        if ln.get("flags") or ln.get("confidence") == "low":
            for c in range(1, len(cols) + 1):
                ws.cell(row=r, column=c).fill = FLAG
        r += 1
    ws.cell(row=r, column=17, value="TOTAL").font = BOLD
    t = ws.cell(row=r, column=18, value=f"=SUM(R{first}:R{r - 1})")
    t.font, t.number_format = BOLD, "0.000"
    t = ws.cell(row=r, column=20, value=f"=SUM(T{first}:T{r - 1})")
    t.font, t.number_format = BOLD, "0.000"
    for c in range(1, len(cols) + 1):
        ws.cell(row=r, column=c).fill = TOTAL

    # ── Summary ──
    sm = wb.create_sheet("Summary")
    r0 = _title(sm, "STEEL SUMMARY BY DIAMETER", meta[:1])
    scols = [("Dia (mm)", 9), ("Required length (m)", 14), ("Required weight (kg)", 14), ("Required (MT)", 12),
             ("12 m bars to buy (optimised)", 16), ("Purchase weight (kg)", 14), ("Scrap %", 9),
             ("Bars if cut without plan", 16), ("Scrap % without plan", 14), ("Bars saved", 11),
             ("Reusable offcuts (m)", 14)]
    _header(sm, r0, scols)
    r = r0 + 1
    first = r
    for row in summary.get("by_dia", []):
        vals = [row["dia"], row["length_m"], row["weight_kg"], None, row["bars_to_buy"], row["purchase_kg"],
                row["wastage_pct"], row["uncut_bars"], row["uncut_wastage_pct"], None, row["reusable_m"]]
        for c, v in enumerate(vals, start=1):
            sm.cell(row=r, column=c, value=v).border = BORDER
        sm.cell(row=r, column=4, value=f"=ROUND(C{r}/1000,3)").border = BORDER
        sm.cell(row=r, column=10, value=f"=H{r}-E{r}").border = BORDER
        r += 1
    sm.cell(row=r, column=1, value="TOTAL").font = BOLD
    for c, col in ((2, "B"), (3, "C"), (4, "D"), (5, "E"), (6, "F"), (8, "H"), (10, "J"), (11, "K")):
        cell = sm.cell(row=r, column=c, value=f"=SUM({col}{first}:{col}{r - 1})")
        cell.font, cell.fill = BOLD, TOTAL

    # ── Cutting plan ──
    cp = wb.create_sheet("Cutting Plan")
    r0 = _title(cp, "OPTIMISED CUTTING PLAN", [("Rule", f"Offcuts ≥ {settings.get('min_reuse_mm', 1000) / 1000:g} m "
                                                "go to the offcut register; shorter leftovers are scrap.")])
    ccols = [("Dia", 6), ("Stock", 10), ("Source", 9), ("No. of bars", 9), ("Cut each bar into (mm)", 36),
             ("Pieces go to bar marks (total pieces)", 70), ("Leftover per bar (mm)", 12), ("Leftover is", 10)]
    _header(cp, r0, ccols)
    alloc = _allocate(lines, plans)
    r = r0 + 1
    for dia, p in sorted(plans.items(), key=lambda kv: int(kv[0])):
        for k, pat in enumerate(p.get("patterns", [])):
            cuts = Counter(pat["cuts"])
            desc = " + ".join(f"{n} × {L}" for L, n in sorted(cuts.items(), reverse=True))
            parts = []
            for L, marks in sorted(alloc.get((int(dia), k), {}).items(), reverse=True):
                top = ", ".join(f"{m} ×{n}" for m, n in marks.most_common(4))
                more = len(marks) - 4
                parts.append(f"{L}: {top}" + (f" +{more} more" if more > 0 else ""))
            vals = [int(dia), f"{pat['stock_length'] / 1000:g} m", pat["source"], pat["repeat"], desc,
                    " | ".join(parts)[:400], pat["leftover"], pat["leftover_kind"]]
            for c, v in enumerate(vals, start=1):
                cp.cell(row=r, column=c, value=v).border = BORDER
            if pat["leftover_kind"] == "scrap" and pat["leftover"] > 0:
                cp.cell(row=r, column=8).fill = FLAG
            r += 1
        cp.cell(row=r, column=1, value=f"{dia} mm").font = BOLD
        cp.cell(row=r, column=4, value=p.get("new_bars")).font = BOLD
        cp.cell(row=r, column=5, value=f"{p.get('new_bars')} new bars (+{p.get('offcuts_used', 0)} site offcuts); "
                                       f"scrap {p.get('wastage_pct')}% — without plan {p.get('baseline_bars')} bars, "
                                       f"{p.get('baseline_wastage_pct')}% scrap").font = BOLD
        for c in range(1, len(ccols) + 1):
            cp.cell(row=r, column=c).fill = TOTAL
        r += 2

    # ── Offcut register ──
    oc = wb.create_sheet("Offcut Register")
    r0 = _title(oc, "OFFCUT REGISTER (reusable pieces to store on site)", [])
    ocols = [("Dia", 6), ("Length (mm)", 12), ("Nos", 8), ("Total (m)", 10), ("Weight (kg)", 10)]
    _header(oc, r0, ocols)
    r = r0 + 1
    for dia, p in sorted(plans.items(), key=lambda kv: int(kv[0])):
        cnt = Counter()
        for pat in p.get("patterns", []):
            if pat["leftover_kind"] == "reusable":
                cnt[pat["leftover"]] += pat["repeat"]
        for L, n in sorted(cnt.items(), reverse=True):
            vals = [int(dia), L, n, round(L * n / 1000, 3), round(L * n / 1000 * int(dia) ** 2 / 162, 2)]
            for c, v in enumerate(vals, start=1):
                oc.cell(row=r, column=c, value=v).border = BORDER
            r += 1

    # ── Issues ──
    iss = wb.create_sheet("Issues & Assumptions")
    iss.column_dimensions["A"].width = 140
    line = 1
    for title, items in (
        ("Drawing notes read", [f"Steel: {notes.get('steel_grade')}", f"Concrete: {notes.get('concrete_grade')}",
                                f"Lap table ({notes.get('lap_table_label') or 'lap'}): " +
                                ", ".join(f"{k} → {v}Ø" for k, v in (notes.get('lap_table') or {}).items()),
                                "Covers: " + ", ".join(f"{k} {v} mm" for k, v in (notes.get('covers_mm') or {}).items())]
         + list(notes.get("issues") or [])),
        ("Items the software could not complete", issues),
        ("Flagged BBS lines", [f"{ln['mark']} ({ln['member']}): {'; '.join(ln['flags'])}" for ln in lines if ln.get("flags")]),
        ("Conventions", ["Cut length = drawn outer dimensions − bend deductions (45° 1d, 90° 2d, 135° 3d) + hooks.",
                         "Stirrups: closed, two 135° hooks of max(10d, 75 mm); count = zone ÷ spacing + 1.",
                         "Unit weight = d²/162 kg/m.",
                         "Bars longer than the stock length are split at laps of (lap factor × Ø), staggered on site."]),
    ):
        iss.cell(row=line, column=1, value=title).font = Font(bold=True, size=12)
        line += 1
        for it in items or ["—"]:
            iss.cell(row=line, column=1, value=f"• {it}")
            line += 1
        line += 1

    buf = BytesIO()
    wb.save(buf)
    safe = "".join(ch if ch.isalnum() else "_" for ch in drawing).strip("_")[:60]
    return buf.getvalue(), f"BBS_{safe}.xlsx"
