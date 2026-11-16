"""One-dimensional cutting-stock optimisation per bar diameter.

Goal: cut every required piece while buying the least new steel. Existing
site offcuts are used first (they're already paid for). Leftovers of at least
`min_reuse` mm go to the offcut register for later use; shorter ones are scrap
and count as wastage.

Method: column generation (LP relaxation with GLOP, bounded-knapsack pricing),
then an integer solve over the generated patterns with SCIP. A first-fit-
decreasing heuristic runs too; the better of the two plans is returned. All
lengths are integer millimetres (rebar is sheared, so no kerf allowance).
"""
from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import dataclass, field

from ortools.linear_solver import pywraplp


@dataclass
class Piece:
    length: int      # mm
    qty: int
    ref: str = ""    # bar mark(s) this piece belongs to


@dataclass
class Pattern:
    stock_length: int
    source: str                    # "new" or "offcut"
    cuts: list[int]                # piece lengths cut from one stock bar
    repeat: int = 1
    leftover: int = 0
    leftover_kind: str = "scrap"   # "reusable" or "scrap"
    refs: list[str] = field(default_factory=list)


@dataclass
class DiaPlan:
    dia: int
    stock_length: int
    patterns: list[Pattern]
    new_bars: int
    offcuts_used: int
    required_m: float
    purchased_m: float
    scrap_m: float
    reusable_m: float
    wastage_pct: float             # scrap ÷ steel cut from (new + offcuts)
    method: str
    baseline_bars: int             # uncut site ordering: each mark cut from fresh bars
    baseline_scrap_m: float
    baseline_wastage_pct: float
    unfit: list[Piece] = field(default_factory=list)   # longer than stock (should have been lapped)

    @property
    def bars_saved(self) -> int:
        return self.baseline_bars - self.new_bars


# ─── helpers ────────────────────────────────────────────────────────────────


def _knapsack(values: list[float], lengths: list[int], bounds: list[int], cap: int):
    """Bounded knapsack for pattern pricing, solved in C++ by OR-Tools.

    Items are expanded into copies (at most cap // length each), and the
    fractional dual values are scaled to integers. Returns (value, counts)."""
    from ortools.algorithms.python import knapsack_solver as ks

    SCALE = 1_000_000
    item_of: list[int] = []
    vals: list[int] = []
    wts: list[int] = []
    for i, (v, L, b) in enumerate(zip(values, lengths, bounds)):
        if v <= 1e-9 or L > cap or b <= 0:
            continue
        for _ in range(min(b, cap // L)):
            item_of.append(i)
            vals.append(int(round(v * SCALE)))
            wts.append(L)
    counts = [0] * len(values)
    if not vals:
        return 0.0, counts
    solver = ks.KnapsackSolver(ks.SolverType.KNAPSACK_DYNAMIC_PROGRAMMING_SOLVER, "pricing")
    solver.init(vals, [wts], [cap])
    solver.solve()
    for j, i in enumerate(item_of):
        if solver.best_solution_contains(j):
            counts[i] += 1
    return sum(values[i] * c for i, c in enumerate(counts)), counts


def _ffd(demand: dict[int, int], stocks: list[tuple[int, str, int | None]]):
    """First-fit decreasing over available stock (offcuts first, then new)."""
    pieces = sorted((L for L, q in demand.items() for _ in range(q)), reverse=True)
    bins: list[list] = []   # [stock_len, source, remaining, cuts]
    avail = [[L, src, n] for L, src, n in stocks]
    for p in pieces:
        placed = False
        for b in bins:
            if b[2] >= p:
                b[2] -= p
                b[3].append(p)
                placed = True
                break
        if placed:
            continue
        # open the smallest stock bar that fits (offcuts preferred)
        for s in sorted(avail, key=lambda s: (s[1] != "offcut", s[0])):
            if s[0] >= p and (s[2] is None or s[2] > 0):
                if s[2] is not None:
                    s[2] -= 1
                bins.append([s[0], s[1], s[0] - p, [p]])
                break
        else:
            return None
    return [(b[0], b[1], b[3]) for b in bins]


# ─── main entry ─────────────────────────────────────────────────────────────


def optimise(dia: int, pieces: list[Piece], stock_length: int = 12000,
             offcuts: list[int] | None = None, min_reuse: int = 1000,
             time_limit_s: int = 20) -> DiaPlan:
    offcuts = [int(o) for o in (offcuts or []) if o > 0]
    unfit = [p for p in pieces if p.length > stock_length]
    demand: dict[int, int] = defaultdict(int)
    refs: dict[int, set] = defaultdict(set)
    for p in pieces:
        if p.length <= stock_length and p.qty > 0:
            demand[int(round(p.length))] += int(p.qty)
            if p.ref:
                refs[int(round(p.length))].add(p.ref)

    baseline_bars, baseline_scrap = _baseline(pieces, stock_length)
    if not demand:
        return DiaPlan(dia, stock_length, [], 0, 0, 0, 0, 0, 0, 0, "none",
                       baseline_bars, baseline_scrap / 1000, 0, unfit)

    # stock types: each distinct offcut length (limited count) + unlimited new bars
    off_counts = Counter(offcuts)
    stocks: list[tuple[int, str, int | None]] = [(L, "offcut", n) for L, n in off_counts.items()]
    stocks.append((stock_length, "new", None))

    exact = _column_generation(demand, stocks, time_limit_s)
    heur = _ffd(demand, stocks)
    candidates = []
    if exact is not None:
        candidates.append(("optimised (column generation + integer solve)", exact))
    if heur is not None:
        candidates.append(("first-fit decreasing", heur))

    def score(sol):
        new = sum(L for L, src, _ in sol if src == "new")
        scrap = sum(max(0, L - sum(c)) for L, src, c in sol
                    if 0 < L - sum(c) < min_reuse)
        return (new, scrap)

    method, sol = min(candidates, key=lambda c: score(c[1]))
    sol = _trim_surplus(sol, demand)

    # group identical bars into patterns
    grouped: dict[tuple, int] = Counter()
    for L, src, cuts in sol:
        grouped[(L, src, tuple(sorted(cuts, reverse=True)))] += 1
    patterns = []
    for (L, src, cuts), rep in sorted(grouped.items(), key=lambda kv: (kv[0][1] != "new", -kv[1])):
        left = L - sum(cuts)
        patterns.append(Pattern(
            stock_length=L, source=src, cuts=list(cuts), repeat=rep, leftover=left,
            leftover_kind="reusable" if left >= min_reuse else "scrap",
            refs=sorted({r for c in cuts for r in refs.get(c, [])}),
        ))

    new_bars = sum(p.repeat for p in patterns if p.source == "new")
    offcuts_used = sum(p.repeat for p in patterns if p.source == "offcut")
    cut_from = sum(p.stock_length * p.repeat for p in patterns)
    scrap = sum(p.leftover * p.repeat for p in patterns if p.leftover_kind == "scrap")
    reusable = sum(p.leftover * p.repeat for p in patterns if p.leftover_kind == "reusable")
    required = sum(L * q for L, q in demand.items())
    return DiaPlan(
        dia=dia, stock_length=stock_length, patterns=patterns,
        new_bars=new_bars, offcuts_used=offcuts_used,
        required_m=round(required / 1000, 3),
        purchased_m=round(new_bars * stock_length / 1000, 3),
        scrap_m=round(scrap / 1000, 3), reusable_m=round(reusable / 1000, 3),
        wastage_pct=round(100 * scrap / cut_from, 2) if cut_from else 0.0,
        method=method,
        baseline_bars=baseline_bars, baseline_scrap_m=round(baseline_scrap / 1000, 3),
        baseline_wastage_pct=round(100 * baseline_scrap / (baseline_bars * stock_length), 2)
        if baseline_bars else 0.0,
        unfit=unfit,
    )


def _baseline(pieces: list[Piece], stock: int) -> tuple[int, float]:
    """Uncut site practice: each bar mark cut separately from fresh stock bars."""
    bars = 0
    scrap = 0.0
    for p in pieces:
        if p.length > stock or p.qty <= 0:
            continue
        per_bar = max(1, stock // int(p.length))
        n = math.ceil(p.qty / per_bar)
        bars += n
        full, rem = divmod(p.qty, per_bar)
        scrap += full * (stock - per_bar * p.length)
        if rem:
            scrap += stock - rem * p.length
    return bars, scrap


def _trim_surplus(sol, demand):
    """The integer model may cut a few more pieces than needed; drop the extras
    (they simply stay as a longer leftover on that bar)."""
    produced = Counter(c for _, _, cuts in sol for c in cuts)
    surplus = {L: produced[L] - q for L, q in demand.items() if produced[L] > q}
    out = []
    for L, src, cuts in sol:
        keep = []
        for c in sorted(cuts):
            if surplus.get(c, 0) > 0:
                surplus[c] -= 1
            else:
                keep.append(c)
        if keep:
            out.append((L, src, keep))
    return out


def _column_generation(demand: dict[int, int], stocks, time_limit_s: int):
    lengths = sorted(demand, reverse=True)
    qty = [demand[L] for L in lengths]
    # cost: new steel counts fully; offcuts are nearly free (already on site)
    cost = {(L, src): (L if src == "new" else 0.01 * L) for L, src, _ in stocks}

    # initial patterns: as many of one length as fit, per stock type
    patterns: list[tuple[int, str, list[int]]] = []
    for L, src, _ in stocks:
        for i, pl in enumerate(lengths):
            if pl <= L:
                counts = [0] * len(lengths)
                counts[i] = min(L // pl, qty[i])
                patterns.append((L, src, counts))
    if not patterns:
        return None

    for _ in range(200):
        lp = pywraplp.Solver.CreateSolver("GLOP")
        x = [lp.NumVar(0, lp.infinity(), "") for _ in patterns]
        rows = []
        for i in range(len(lengths)):
            rows.append(lp.Add(sum(p[2][i] * x[j] for j, p in enumerate(patterns)) >= qty[i]))
        avail_rows = {}
        for L, src, n in stocks:
            if n is not None:
                avail_rows[(L, src)] = lp.Add(
                    sum(x[j] for j, p in enumerate(patterns) if (p[0], p[1]) == (L, src)) <= n)
        lp.Minimize(sum(cost[(p[0], p[1])] * x[j] for j, p in enumerate(patterns)))
        if lp.Solve() != pywraplp.Solver.OPTIMAL:
            return None
        duals = [r.dual_value() for r in rows]
        added = False
        for L, src, n in stocks:
            av_dual = avail_rows[(L, src)].dual_value() if (L, src) in avail_rows else 0.0
            val, counts = _knapsack(duals, lengths, qty, L)
            reduced = cost[(L, src)] - val - av_dual
            if reduced < -1e-6 and any(counts):
                pat = (L, src, counts)
                if pat not in patterns:
                    patterns.append(pat)
                    added = True
        if not added:
            break

    ip = pywraplp.Solver.CreateSolver("SCIP")
    if ip is None:
        return None
    ip.SetTimeLimit(time_limit_s * 1000)
    y = [ip.IntVar(0, sum(qty), "") for _ in patterns]
    for i in range(len(lengths)):
        ip.Add(sum(p[2][i] * y[j] for j, p in enumerate(patterns)) >= qty[i])
    for L, src, n in stocks:
        if n is not None:
            ip.Add(sum(y[j] for j, p in enumerate(patterns) if (p[0], p[1]) == (L, src)) <= n)
    ip.Minimize(sum(cost[(p[0], p[1])] * y[j] for j, p in enumerate(patterns)))
    status = ip.Solve()
    if status not in (pywraplp.Solver.OPTIMAL, pywraplp.Solver.FEASIBLE):
        return None
    sol = []
    for j, p in enumerate(patterns):
        for _ in range(int(round(y[j].solution_value()))):
            cuts = [lengths[i] for i, c in enumerate(p[2]) for _ in range(c)]
            sol.append((p[0], p[1], cuts))
    return sol
