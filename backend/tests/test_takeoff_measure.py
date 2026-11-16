"""Quantity rules for the takeoff module. Run: python -m unittest discover -s tests"""
import re
import unittest
from io import BytesIO

from openpyxl import load_workbook

from app.services.takeoff.drawing import Floor, FloorData, Grid, _auto_grid
from app.services.takeoff.export import build_sheet
from app.services.takeoff.measure import build_members, build_rows, row_qty, totals


def _members(**over):
    m = {
        "slab_thickness_mm": 150, "floor_height_m": 3.6, "height_source": "entered by user",
        "slabs": [{"id": "S1", "location": "01-02 / A-B", "length_m": 6.0, "breadth_m": 5.0,
                   "thickness_mm": 150, "is_pt": False, "description": "", "confidence": "high",
                   "evidence": "150THK"}],
        "deductions": [{"id": "D1", "location": "01-02 / A-B", "length_m": 2.0, "breadth_m": 1.5,
                        "thickness_mm": 150, "description": "Shaft", "confidence": "high"}],
        "beams": [
            {"id": "B1", "mark": "B1", "breadth_mm": 300, "depth_mm": 600, "clear_length_m": 5.4,
             "location": "01-02 / A", "grid": "A", "confidence": "high", "evidence": "label"},
            {"id": "B2", "mark": "B1", "breadth_mm": 300, "depth_mm": 600, "clear_length_m": 4.6,
             "location": "02-03 / A", "grid": "A", "confidence": "high", "evidence": "label"},
            {"id": "B3", "mark": None, "breadth_mm": 230, "depth_mm": None, "clear_length_m": 3.0,
             "location": "01-02 / B", "grid": "B", "confidence": "low", "evidence": "none"},
        ],
        "columns": [
            {"id": "C1", "mark": "C1", "breadth_mm": 300, "depth_mm": 600, "location": "01 / A",
             "confidence": "high", "evidence": "outline"},
            {"id": "C2", "mark": "C2", "breadth_mm": 300, "depth_mm": 600, "location": "02 / A",
             "confidence": "high", "evidence": "outline"},
        ],
    }
    m.update(over)
    return m


def _by(rows, t):
    return [r for r in rows if r["member_type"] == t]


class RowQtyTests(unittest.TestCase):
    def test_blank_dimensions_count_as_one(self):
        self.assertEqual(row_qty({"nos": 2, "l": 3, "b": None, "d": ""}), 6)

    def test_deduction_is_negative(self):
        self.assertEqual(row_qty({"nos": -1, "l": 2, "b": 1.5, "d": 0.15}), -0.45)


class ConcreteTests(unittest.TestCase):
    def setUp(self):
        self.rows = build_rows(_members(), "concrete")

    def test_slab_and_deduction(self):
        self.assertEqual(_by(self.rows, "slab")[0]["qty"], 4.5)          # 6 × 5 × 0.15
        self.assertEqual(_by(self.rows, "deduction")[0]["qty"], -0.45)   # 2 × 1.5 × 0.15

    def test_beams_grouped_by_grid_and_measured_below_slab(self):
        b = [r for r in _by(self.rows, "beam") if r["mark"] == "B1"]
        self.assertEqual(len(b), 1)
        self.assertEqual(b[0]["l"], 10.0)            # spans combined along grid A
        self.assertEqual(b[0]["d"], 0.45)            # 600 − 150 slab
        self.assertEqual(b[0]["qty"], 1.35)          # 10 × 0.3 × 0.45

    def test_unknown_beam_depth_is_flagged_and_not_billed(self):
        b = [r for r in _by(self.rows, "beam") if r["mark"] == ""][0]
        self.assertIsNone(b["d"])
        self.assertIn("Depth unknown", b["flag"])
        self.assertEqual(b["qty"], 0)  # never L × B passed off as a volume

    def test_columns_to_slab_soffit(self):
        c = _by(self.rows, "column")[0]
        self.assertEqual((c["nos"], c["d"]), (2, 3.45))   # 3.6 − 0.15
        self.assertEqual(c["qty"], round(2 * 0.3 * 0.6 * 3.45, 3))

    def test_missing_floor_height_is_flagged(self):
        rows = build_rows(_members(floor_height_m=None), "concrete")
        self.assertIn("Floor height unknown", _by(rows, "column")[0]["flag"])

    def test_totals_fold_deductions_into_slabs(self):
        t = totals(self.rows)
        self.assertEqual(t["by_type"]["slab"], 4.05)


class FormworkTests(unittest.TestCase):
    def setUp(self):
        self.rows = build_rows(_members(), "formwork")

    def test_slab_soffit(self):
        self.assertEqual(_by(self.rows, "slab")[0]["qty"], 30.0)

    def test_beam_two_sides_below_slab(self):
        b = [r for r in _by(self.rows, "beam") if r["mark"] == "B1"][0]
        self.assertEqual(b["qty"], round(2 * 10 * 0.45, 3))

    def test_column_perimeter_times_clear_height(self):
        c = _by(self.rows, "column")[0]
        self.assertEqual(c["qty"], round(2 * (2 * (0.3 + 0.6)) * 3.45, 3))


class PanelFromGridTests(unittest.TestCase):
    def test_grid_range_gives_centre_to_centre_size(self):
        fd = FloorData(
            floor=Floor("L", "First Floor", (0, 0, 1, 1)), unit_m=0.001,
            grids=[Grid("01", "x", 0), Grid("02", "x", 6000), Grid("A", "y", 10000), Grid("B", "y", 5000)],
            beams=[], columns=[], slab_labels=[], cutouts=[], notes=[], warnings=[],
        )
        ai = {"slab_panels": [{"x_from": "02", "x_to": "01", "y_from": "A", "y_to": "B",
                               "length_m": None, "breadth_m": None, "location": None,
                               "thickness_mm": 200, "is_pt": False}]}
        m = build_members(fd, ai, 3.3)
        s = m["slabs"][0]
        self.assertEqual((s["length_m"], s["breadth_m"], s["location"]), (6.0, 5.0, "01-02 / A-B"))


class ExportTests(unittest.TestCase):
    def test_formulas_reproduce_row_quantities(self):
        rows = build_rows(_members(), "concrete")
        data, _ = build_sheet(drawing_name="T", floor="First Floor", activity="concrete", rows=rows,
                              members=_members(), ai_notes=[], missing=[], prepared_by="test")
        ws = load_workbook(BytesIO(data))["Measurement Sheet"]
        found = []
        for r in range(1, ws.max_row + 1):
            f = ws.cell(r, 10).value
            if isinstance(f, str) and f.startswith("=ROUND("):
                # concrete rows need L, B and D: multiplied directly, blank → 0
                self.assertEqual(f, f"=ROUND(F{r}*G{r}*H{r}*I{r},3)")
                vals = [ws.cell(r, c).value for c in (6, 7, 8, 9)]
                q = vals[0]
                for v in vals[1:]:
                    q *= 0 if v in (None, "") else v
                found.append(round(q, 3))
        self.assertEqual(sorted(found), sorted(r["qty"] for r in rows))
        subtotal_refs = [ws.cell(r, 10).value for r in range(1, ws.max_row + 1)
                         if isinstance(ws.cell(r, 10).value, str) and ws.cell(r, 10).value.startswith("=SUM")]
        self.assertEqual(len(subtotal_refs), 3)  # slabs, beams, columns
        self.assertTrue(all(re.match(r"=SUM\(J\d+:J\d+\)", s) for s in subtotal_refs))


def _fd(grids=(), **over):
    base = dict(floor=Floor("L", "Ground Floor", (0, 0, 1, 1)), unit_m=0.001, grids=list(grids),
                beams=[], columns=[], slab_labels=[], cutouts=[], notes=[], warnings=[])
    base.update(over)
    return FloorData(**base)


_GRID = [Grid("X1", "x", 0), Grid("X2", "x", 6000), Grid("Y1", "y", 5000), Grid("Y2", "y", 0)]
_PANEL = {"x_from": "X1", "x_to": "X2", "y_from": "Y1", "y_to": "Y2", "length_m": None, "breadth_m": None,
          "location": None, "thickness_mm": None, "is_pt": False, "confidence": "low"}
_OPENING = {"x_from": None, "x_to": None, "y_from": None, "y_to": None, "length_m": 2.0, "breadth_m": 2.0,
            "location": "core", "thickness_mm": None, "description": "Lift"}


class AutoGridTests(unittest.TestCase):
    def test_primary_beam_lines_become_grid(self):
        segs = []
        for x in (0, 6000, 12000):                  # three long vertical beam lines
            segs.append((((x, 0), (x, 10000)), 300))
        for y in (0, 10000):                        # two long horizontal lines
            segs.append((((0, y), (12000, y)), 300))
        segs.append((((3000, 0), (3000, 800)), 230))       # short stub: ignored
        segs.append((((6400, 0), (6400, 10000)), 230))     # paired beam 0.4 m away: merged
        g = _auto_grid(segs, 0.001)
        xs = [x for x in g if x.axis == "x"]
        ys = [y for y in g if y.axis == "y"]
        self.assertEqual([x.label for x in xs], ["X1", "X2", "X3"])
        self.assertEqual([round(x.pos) for x in xs], [0, 6000, 12000])
        self.assertEqual([y.label for y in ys], ["Y1", "Y2"])
        self.assertGreater(ys[0].pos, ys[1].pos)            # Y1 is the top line


class SlabFallbackTests(unittest.TestCase):
    def test_no_panels_means_no_deductions_and_a_warning(self):
        m = build_members(_fd(_GRID), {"slab_panels": [], "slab_deductions": [_OPENING]}, 3.3)
        self.assertEqual(m["deductions"], [])
        self.assertTrue(any("No slab measured" in w for w in m["warnings"]))
        self.assertTrue(any("not deducted" in w for w in m["warnings"]))

    def test_default_thickness_is_used_and_flagged(self):
        m = build_members(_fd(_GRID), {"slab_panels": [_PANEL], "slab_deductions": [_OPENING]}, 3.3, 175)
        self.assertEqual(m["slabs"][0]["thickness_mm"], 175)
        self.assertEqual(len(m["deductions"]), 1)
        slab = _by(build_rows(m, "concrete"), "slab")[0]
        self.assertEqual(slab["qty"], round(6 * 5 * 0.175, 3))
        self.assertIn("default", slab["flag"])

    def test_drawing_thickness_beats_default(self):
        m = build_members(_fd(_GRID), {"slab_panels": [{**_PANEL, "thickness_mm": 200}]}, 3.3, 175)
        self.assertEqual((m["slabs"][0]["thickness_mm"], m["slabs"][0]["thickness_source"]), (200, "drawing"))

    def test_unknown_thickness_gives_zero_volume_but_formwork_area(self):
        m = build_members(_fd(_GRID), {"slab_panels": [_PANEL], "slab_deductions": [_OPENING]}, 3.3)
        rows = build_rows(m, "concrete")
        self.assertEqual(_by(rows, "slab")[0]["qty"], 0)
        # the opening must not be deducted at a guessed thickness (slab total can't go negative)
        self.assertEqual(_by(rows, "deduction")[0]["qty"], 0)
        self.assertEqual(totals(rows)["by_type"]["slab"], 0)
        self.assertEqual(_by(build_rows(m, "formwork"), "slab")[0]["qty"], 30.0)


if __name__ == "__main__":
    unittest.main()
