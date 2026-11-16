"""IS 1200-style measurement sheet (xlsx) with live Excel formulas."""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime
from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

from app.services.takeoff.measure import ACTIVITIES, CONVENTIONS

HEADER_BG = "F1F3F6"
GROUP_BG = "E8EEF7"
TOTAL_BG = "DCE6F2"
FLAG_BG = "FFF4E5"
GRID = "D9DDE3"

COLS = [
    ("S.No", 6), ("Member", 10), ("Mark", 9), ("Location", 18), ("Description", 38),
    ("Nos", 7), ("L (m)", 9), ("B (m)", 9), ("D/H (m)", 9), ("Qty", 11), ("Unit", 6), ("Remarks", 48),
]
TYPE_ORDER = ["slab", "deduction", "beam", "column", "footing", "wall", "staircase", "other"]
TYPE_LABEL = {"slab": "SLABS", "deduction": "SLABS", "beam": "BEAMS", "column": "COLUMNS",
              "footing": "FOOTINGS", "wall": "WALLS", "staircase": "STAIRCASE", "other": "OTHERS"}


def build_sheet(*, drawing_name: str, floor: str, activity: str, rows: list[dict], members: dict,
                ai_notes: list[str], missing: list[str], prepared_by: str | None) -> tuple[bytes, str]:
    act = ACTIVITIES[activity]
    unit = act["unit"]
    wb = Workbook()
    ws = wb.active
    ws.title = "Measurement Sheet"

    thin = Side(style="thin", color=GRID)
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    bold = Font(bold=True)

    ws["A1"] = f"MEASUREMENT SHEET — {act['label'].upper()}"
    ws["A1"].font = Font(bold=True, size=14)
    meta = [
        ("Drawing", drawing_name),
        ("Floor / level", floor),
        ("Activity", f"{act['label']} ({unit})"),
        ("Floor height", f"{members.get('floor_height_m')} m ({members.get('height_source') or 'not stated'})"
         if members.get("floor_height_m") else "Not stated — enter in column heights"),
        ("Typical slab thickness", f"{members.get('slab_thickness_mm')} mm"),
        ("Prepared", f"{datetime.now():%d/%m/%Y %H:%M}" + (f" by {prepared_by}" if prepared_by else "")),
    ]
    for i, (k, v) in enumerate(meta, start=2):
        ws.cell(row=i, column=1, value=k).font = Font(color="666666", size=9)
        ws.cell(row=i, column=3, value=v).font = Font(size=10)
    warn = ws.cell(row=len(meta) + 2, column=1,
                   value="AI-assisted takeoff: geometry measured from the drawing, interpretation by Claude. "
                         "Verify before use in billing.")
    warn.font = Font(italic=True, color="B45309", size=9)

    head = len(meta) + 4
    for c, (label, width) in enumerate(COLS, start=1):
        cell = ws.cell(row=head, column=c, value=label)
        cell.font, cell.border = bold, border
        cell.fill = PatternFill("solid", fgColor=HEADER_BG)
        cell.alignment = Alignment(horizontal="center", vertical="center")
        ws.column_dimensions[get_column_letter(c)].width = width
    ws.freeze_panes = ws.cell(row=head + 1, column=1)

    groups: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        groups[TYPE_LABEL.get(r["member_type"], "OTHERS")].append(r)
    ordered = sorted(groups.items(), key=lambda kv: min(
        TYPE_ORDER.index(r["member_type"]) if r["member_type"] in TYPE_ORDER else 99 for r in kv[1]))

    r_i = head + 1
    sno = 0
    subtotal_cells = []
    for label, items in ordered:
        g = ws.cell(row=r_i, column=1, value=label)
        g.font = bold
        for c in range(1, len(COLS) + 1):
            ws.cell(row=r_i, column=c).fill = PatternFill("solid", fgColor=GROUP_BG)
            ws.cell(row=r_i, column=c).border = border
        r_i += 1
        first = r_i
        items = sorted(items, key=lambda r: (r["member_type"] == "deduction", r["id"]))
        for r in items:
            sno += 1
            vals = [sno, r["member_type"].title(), r.get("mark") or "", r.get("location") or "",
                    r.get("description") or "", r.get("nos"), r.get("l"), r.get("b"), r.get("d")]
            for c, v in enumerate(vals, start=1):
                cell = ws.cell(row=r_i, column=c, value=v)
                cell.border = border
                if c >= 6:
                    cell.number_format = "0.000" if c > 6 else "0"
            # Qty = Nos × L × B × D (live formula). Dimensions the item needs are
            # multiplied directly (blank → 0); the rest count as 1 when blank.
            req = r.get("req") or ""
            terms = [f"F{r_i}"]
            for key, col in (("l", "G"), ("b", "H"), ("d", "I")):
                ref = f"{col}{r_i}"
                terms.append(ref if key in req else f'IF({ref}="",1,{ref})')
            q = ws.cell(row=r_i, column=10, value=f"=ROUND({'*'.join(terms)},3)")
            q.number_format = "0.000"
            q.border = border
            ws.cell(row=r_i, column=11, value=unit).border = border
            remarks = " | ".join(x for x in [
                r.get("flag"), f"confidence: {r.get('confidence')}" if r.get("confidence") else None,
                r.get("remarks")] if x)
            rc = ws.cell(row=r_i, column=12, value=remarks)
            rc.border = border
            rc.alignment = Alignment(wrap_text=False)
            if r.get("flag") or r.get("confidence") == "low":
                for c in range(1, len(COLS) + 1):
                    ws.cell(row=r_i, column=c).fill = PatternFill("solid", fgColor=FLAG_BG)
            r_i += 1
        # Subtotal
        ws.cell(row=r_i, column=5, value=f"Total {label.lower()}").font = bold
        st = ws.cell(row=r_i, column=10, value=f"=SUM(J{first}:J{r_i - 1})")
        st.font, st.number_format = bold, "0.000"
        ws.cell(row=r_i, column=11, value=unit).font = bold
        for c in range(1, len(COLS) + 1):
            ws.cell(row=r_i, column=c).fill = PatternFill("solid", fgColor=TOTAL_BG)
            ws.cell(row=r_i, column=c).border = border
        subtotal_cells.append(f"J{r_i}")
        r_i += 2

    ws.cell(row=r_i, column=5, value="GRAND TOTAL").font = Font(bold=True, size=12)
    gt = ws.cell(row=r_i, column=10, value="=" + "+".join(subtotal_cells) if subtotal_cells else 0)
    gt.font, gt.number_format = Font(bold=True, size=12), "0.000"
    ws.cell(row=r_i, column=11, value=unit).font = Font(bold=True, size=12)

    # Notes & assumptions
    ns = wb.create_sheet("Notes & Assumptions")
    ns.column_dimensions["A"].width = 120
    line = 1

    def section(title, items):
        nonlocal line
        ns.cell(row=line, column=1, value=title).font = Font(bold=True, size=12)
        line += 1
        for it in items or ["—"]:
            ns.cell(row=line, column=1, value=f"• {it}").alignment = Alignment(wrap_text=True)
            line += 1
        line += 1

    section("Measurement conventions", CONVENTIONS)
    section("Notes from drawing review (Claude)", ai_notes)
    section("Information missing from the drawing", missing)
    flagged = [f"{r['id']} {r['description']} @ {r['location']}: {r['flag']}" for r in rows if r.get("flag")]
    section("Rows flagged for checking", flagged)

    buf = BytesIO()
    wb.save(buf)
    safe = "".join(ch if ch.isalnum() else "_" for ch in f"{drawing_name}_{floor}_{activity}").strip("_")
    return buf.getvalue(), f"MS_{safe[:80]}.xlsx"
