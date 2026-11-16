"""BBS arithmetic and cutting optimisation. Run: python -m unittest discover -s tests"""
import unittest

from app.services.bbs.engine import (
    Bar, bar_weight_kg, split_at_laps, stirrup_count, stirrups, unit_weight,
)
from app.services.bbs.optimiser import Piece, optimise


class EngineTests(unittest.TestCase):
    def test_unit_weight(self):
        self.assertAlmostEqual(unit_weight(12), 0.889, places=3)
        self.assertAlmostEqual(unit_weight(16), 1.580, places=3)

    def test_bent_bar_cut_length(self):
        # 2 × 90° bends: 300 + 5000 + 300 − 2 × 2 × 16
        b = Bar(mark="T1", member="B1", member_type="beam", location="", description="Top",
                dia=16, legs=[300, 5000, 300], bends=[90, 90])
        self.assertEqual(b.cut_length, 5536)
        self.assertEqual(b.shape[0], "21")

    def test_two_legged_stirrup(self):
        # 230×450 beam, 25 cover, 8 dia: a=180, b=400
        # 2(180+400) + 2×max(80,75) − 3×16 − 2×24 = 1160 + 160 − 48 − 48
        s = stirrups(mark="S1", member="B1", member_type="beam", location="", dia=8,
                     breadth=230, depth=450, cover=25, count=10)
        self.assertEqual(len(s), 1)
        self.assertEqual(s[0].cut_length, 1224)
        self.assertEqual(s[0].shape[0], "51")

    def test_four_legged_adds_inner_ring_and_missing_cover_is_flagged(self):
        s = stirrups(mark="S1", member="B1", member_type="beam", location="", dia=8,
                     breadth=450, depth=600, cover=None, count=10, legs=4)
        self.assertEqual(len(s), 2)
        self.assertTrue(any("Cover not stated" in f for f in s[0].flags))

    def test_stirrup_count(self):
        self.assertEqual(stirrup_count(4131, 200), 21)
        self.assertEqual(stirrup_count(1000, 100), 11)

    def test_lap_split(self):
        # 20 m bar from 12 m stock with 48×16 = 768 lap → 1 lap
        pieces, n = split_at_laps(20000, 12000, 768)
        self.assertEqual(n, 1)
        self.assertEqual(pieces, [12000, 8768])
        self.assertEqual(split_at_laps(8000, 12000, 768), ([8000], 0))

    def test_unknown_lap_leaves_bar_whole(self):
        self.assertEqual(split_at_laps(20000, 12000, None), ([20000], 0))

    def test_weight(self):
        b = Bar(mark="B", member="B1", member_type="beam", location="", description="",
                dia=12, legs=[6000], nos_per_member=3, members=2)
        self.assertAlmostEqual(bar_weight_kg(b), 6 * 6 * 144 / 162, places=2)


class OptimiserTests(unittest.TestCase):
    def test_every_piece_is_cut_and_nothing_extra(self):
        pieces = [Piece(4850, 7, "T1"), Piece(2100, 9, "E1"), Piece(1224, 40, "S1")]
        plan = optimise(12, pieces)
        cut = sorted(c for p in plan.patterns for _ in range(p.repeat) for c in p.cuts)
        expected = sorted([4850] * 7 + [2100] * 9 + [1224] * 40)
        self.assertEqual(cut, expected)
        # every pattern fits its bar
        self.assertTrue(all(sum(p.cuts) <= p.stock_length for p in plan.patterns))

    def test_optimised_beats_or_matches_uncut_ordering(self):
        pieces = [Piece(4850, 7), Piece(2100, 9), Piece(1224, 40), Piece(7300, 5)]
        plan = optimise(12, pieces)
        self.assertLessEqual(plan.new_bars, plan.baseline_bars)
        self.assertLessEqual(plan.wastage_pct, plan.baseline_wastage_pct)
        lower_bound = -(-sum(p.length * p.qty for p in pieces) // 12000)
        self.assertGreaterEqual(plan.new_bars, lower_bound)

    def test_perfect_fit(self):
        plan = optimise(16, [Piece(6000, 4), Piece(4000, 3)])
        self.assertEqual(plan.new_bars, 3)            # 2×(6+6) + 1×(4+4+4)
        self.assertEqual(plan.scrap_m, 0)

    def test_site_offcuts_used_before_new_bars(self):
        plan = optimise(12, [Piece(2500, 2)], offcuts=[5200])
        self.assertEqual(plan.new_bars, 0)
        self.assertEqual(plan.offcuts_used, 1)

    def test_leftover_classification(self):
        plan = optimise(12, [Piece(10500, 1), Piece(11500, 1)], min_reuse=1000)
        kinds = {p.leftover: p.leftover_kind for p in plan.patterns}
        self.assertEqual(kinds[1500], "reusable")
        self.assertEqual(kinds[500], "scrap")

    def test_longer_than_stock_is_reported(self):
        plan = optimise(20, [Piece(13000, 1), Piece(3000, 2)])
        self.assertEqual(len(plan.unfit), 1)


if __name__ == "__main__":
    unittest.main()


from app.services.bbs.reader import CALLOUT_RE, MARK_RE, STIRRUP_RE, _poly_legs  # noqa: E402
from app.services.bbs.export import _allocate  # noqa: E402


class ReaderParsingTests(unittest.TestCase):
    def test_callouts(self):
        m = CALLOUT_RE.match("2-12# Cont.")
        self.assertEqual((m["n"], m["dia"], bool(m["plus"])), ("2", "12", False))
        m = CALLOUT_RE.match("+3-16# Extra")
        self.assertEqual((m["n"], m["dia"], bool(m["plus"]), m["kind"].upper()), ("3", "16", True, "EXTRA"))
        m = CALLOUT_RE.match("3-12# Extra")          # extra without the '+'
        self.assertEqual(m["kind"].upper(), "EXTRA")

    def test_span_mark(self):
        m = MARK_RE.match("PB-19F(230X450)")
        self.assertEqual((m["mark"], m["b"], m["d"]), ("PB-19F", "230", "450"))
        self.assertEqual(MARK_RE.match("B-12A (450X450)")["mark"], "B-12A")

    def test_stirrup_text(self):
        m = STIRRUP_RE.search("4L-#8@200c/c")
        self.assertEqual((m["legs"], m["dia"], m["sp"]), ("4", "8", "200"))
        m = STIRRUP_RE.search("#10@100 C/C")
        self.assertEqual((m["legs"], m["dia"], m["sp"]), (None, "10", "100"))

    def test_polyline_legs_and_bends(self):
        # up 350, along 5000, down 270 (drawing units = mm)
        legs, bends = _poly_legs([(0, 0), (0, 350), (5000, 350), (5000, 80)], 1.0)
        self.assertEqual(legs, [350.0, 5000.0, 270.0])
        self.assertEqual(bends, [90, 90])

    def test_collinear_segments_merge_and_ticks_drop(self):
        legs, bends = _poly_legs([(0, 0), (2000, 0), (5000, 0), (5010, 5)], 1.0)
        self.assertEqual(legs, [5000.0])
        self.assertEqual(bends, [])


class AllocationTests(unittest.TestCase):
    def test_every_piece_goes_to_a_mark_once(self):
        lines = [
            {"mark": "A", "dia": 12, "total_nos": 5, "pieces": [4850]},
            {"mark": "B", "dia": 12, "total_nos": 3, "pieces": [4850]},
            {"mark": "C", "dia": 12, "total_nos": 4, "pieces": [2100]},
        ]
        plan = optimise(12, [Piece(4850, 8), Piece(2100, 4)])
        from dataclasses import asdict
        plans = {"12": asdict(plan)}
        alloc = _allocate(lines, plans)
        got = {}
        for per in alloc.values():
            for L, marks in per.items():
                for m, n in marks.items():
                    got[m] = got.get(m, 0) + n
        self.assertEqual(got, {"A": 5, "B": 3, "C": 4})
