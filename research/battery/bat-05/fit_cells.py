#!/usr/bin/env python3
"""BAT-05: fit cell equivalent-circuit templates to two free datasets and write fit_results.json.

Usage (data folders are untrusted inputs; nothing is imported or executed from them):
  python3 -I research/battery/bat-05/fit_cells.py <galeotti_dir> <hg2_dir> [--out PATH]

  galeotti_dir  references/battery-energy/galeotti-lipo-dataset   (Galeotti et al. 2023, CC BY 4.0)
  hg2_dir       references/battery-energy/kollmeyer-hg2-dataset   (Kollmeyer et al., CC BY 4.0)

Method, held-out results and caveats: docs/research/battery/BAT-05/README.md.
Law and formats: docs/research/battery/BAT-04/specification.md. Pinned: NumPy 1.26.4, SciPy 1.11.4.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares
from scipy.signal import lfilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))  # research/battery: our own reference law (never a data folder)
import ecm_reference as ecm  # noqa: E402

RG = 8.314462618  # J/(mol·K)
SOC_KNOTS = (0.0, 0.01, 0.02, 0.035, 0.05, 0.075, 0.1, 0.125, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55,
             0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.975, 1.0)
LIPO_R_KNOTS = (0.0, 0.1, 0.25, 0.5, 0.75, 1.0)
TEMPERATURE_KNOTS_K = (273.15, 283.15, 298.15, 313.15)
HG2_TESTS = (("585", 273.15), ("575", 283.15), ("549", 298.15), ("555", 313.15))
HG2_REPEAT_PAIR = ("551", "552")      # two 1C capacity tests at 25 °C, two days apart: repeatability margin
GALEOTTI_CELLS = ("a18937dc", "8779fdf1", "7a0914fb", "c6cb2854", "9256326a")
TEMPLATE_CELL = "a18937dc"
AGING_CYCLES = ("0", "45", "90", "270", "540")
REST_S = 300.0               # Galeotti partial-discharge relaxation (EIS time not recorded)
REST_SENSITIVITY_S = 450.0
TAU_FLOOR_S = 1.0            # faster dynamics lumped into R0 (1 s LiPo sampling; plan §9 stiffness guard)
TAU_CEILING_S = 5000.0
OCV_SMOOTHING_V = 0.05       # weight of the OCV second-difference penalty (LiPo)
HG2_GRID_S = 0.1             # HPPC simulation grid (= HPPC sampling)
HG2_CELL_MASS_KG = 0.048     # LG HG2 product specification Rev 5: weight max 48.0 g
SCORE_MIN_SOC = 0.2          # selection metric: loaded-voltage RMSE above 20 % SOC (plan §10 acceptance band)
SIM_MAX_STEP_S = 1.0         # validation simulator sub-step
CP_PUBLISHED_RANGE = (800.0, 1400.0)   # whole-cell c_p, Steinhardt et al. 2022 Table 6 (cylindrical and pouch)
GALEOTTI = {
    "dataset": "Galeotti et al. 2023, LiPo battery LP-503562-IS-3 EIS, capacity, ECM data, Mendeley Data "
               "doi:10.17632/stcppt2r68.1 (article Data in Brief 50:109561, doi:10.1016/j.dib.2023.109561)",
    "license": "CC BY 4.0",
}
KOLLMEYER = {
    "dataset": "Kollmeyer et al., LG 18650HG2 Li-ion battery data (McMaster University), Mendeley Data "
               "doi:10.17632/b5mj79w5w9.2",
    "license": "CC BY 4.0",
}


# ---------------------------------------------------------------------------------------------
# Inputs and integrity
# ---------------------------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclass
class InputRegister:
    galeotti_dir: Path
    hg2_dir: Path
    used: dict = field(default_factory=dict)  # (dataset_key, rel) -> entry

    def __post_init__(self) -> None:
        g = json.loads((self.galeotti_dir / "fetched.json").read_text(encoding="utf-8"))
        self.galeotti_hashes = {(e["folder"][:8], e["file"]): (e["folder"], e["sha256"]) for e in g}
        k = json.loads((self.hg2_dir / "fetched.json").read_text(encoding="utf-8"))
        self.hg2_hashes = {e["local"]: e["sha256"] for e in k}

    def galeotti(self, cell: str, name: str) -> Path:
        path = self.galeotti_dir / cell / name
        folder, expected = self.galeotti_hashes[(cell, name)]
        actual = sha256_file(path)
        if actual != expected:
            raise SystemExit(f"sha256 mismatch for {path}")
        self.used[("galeotti", f"{folder}/{name}")] = {
            "dataset": GALEOTTI["dataset"], "file": f"{folder}/{name}", "sha256": actual, "license": GALEOTTI["license"]}
        return path

    def hg2(self, name: str) -> Path:
        path = self.hg2_dir / name
        actual = sha256_file(path)
        if actual != self.hg2_hashes[name]:
            raise SystemExit(f"sha256 mismatch for {path}")
        self.used[("hg2", name)] = {"dataset": KOLLMEYER["dataset"], "file": name, "sha256": actual,
                                    "license": KOLLMEYER["license"]}
        return path

    def entries(self, prefix: str | None = None) -> list:
        return [v for (key, _), v in sorted(self.used.items()) if prefix is None or key == prefix]


def load_galeotti(path: Path) -> tuple:
    """Columns: time [s], current [A] (negative = discharge), voltage [V]. Returns t, I_discharge, V."""
    data = np.loadtxt(path)
    return data[:, 0].copy(), -data[:, 1], data[:, 2].copy()


def _clock(text: str) -> float:
    h, m, s = text.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def load_hg2(path: Path) -> dict:
    """Kollmeyer CSV: header block, then 'Time Stamp,...' and a units row. Current negative = discharge."""
    with path.open(newline="", encoding="latin-1") as fh:
        rows = list(csv.reader(fh))
    head = next(k for k, r in enumerate(rows) if r and r[0] == "Time Stamp")
    names = rows[head]
    cols = {n: i for i, n in enumerate(names) if n}
    body = [r for r in rows[head + 2:] if len(r) > cols["Capacity"] and r[cols["Prog Time"]]]
    out = {
        "t": np.array([_clock(r[cols["Prog Time"]]) for r in body]),
        "step_time": np.array([_clock(r[cols["Step Time"]]) for r in body]),
        "step": np.array([int(float(r[cols["Step"]])) for r in body]),
        "status": [r[cols["Status"]] for r in body],
        "v": np.array([float(r[cols["Voltage"]]) for r in body]),
        "i": -np.array([float(r[cols["Current"]]) for r in body]),
        "temp_c": np.array([float(r[cols["Temperature"]]) for r in body]),
        "ah": np.array([float(r[cols["Capacity"]]) for r in body]),
    }
    return out


def step_segments(d: dict) -> list:
    """Contiguous runs of equal step number: (start, end, status, duration, mean discharge current)."""
    st = d["step"]
    cut = np.flatnonzero(np.diff(st) != 0) + 1
    starts, ends = np.r_[0, cut], np.r_[cut, len(st)]
    return [(int(s), int(e), d["status"][s], float(d["t"][e - 1] - d["t"][s]), float(d["i"][s:e].mean()))
            for s, e in zip(starts, ends)]


def rms(x) -> float:
    x = np.asarray(x, dtype=float)
    return float(np.sqrt(np.mean(x * x))) if x.size else float("nan")


def error_stats(err, z=None) -> dict:
    """RMSE, max |e| and bias over all samples; score_rmse_v over the samples with z >= SCORE_MIN_SOC."""
    err = np.asarray(err, dtype=float)
    out = {"rmse_v": rms(err), "max_abs_v": float(np.max(np.abs(err))), "mean_v": float(np.mean(err)),
           "samples": int(err.size)}
    if z is not None:
        sel = err[np.asarray(z) >= SCORE_MIN_SOC]
        out["score_rmse_v"] = rms(sel)
        out["score_max_abs_v"] = float(np.max(np.abs(sel))) if sel.size else float("nan")
    return out


def isotonic_increasing(y, w=None) -> np.ndarray:
    """Pool-adjacent-violators least-squares nondecreasing fit."""
    y = np.asarray(y, dtype=float)
    w = np.ones_like(y) if w is None else np.asarray(w, dtype=float)
    vals, wts, cnt = [], [], []
    for yi, wi in zip(y, w):
        vals.append(yi); wts.append(wi); cnt.append(1)
        while len(vals) > 1 and vals[-2] > vals[-1]:
            wsum = wts[-2] + wts[-1]
            v = (vals[-2] * wts[-2] + vals[-1] * wts[-1]) / wsum
            c = cnt[-2] + cnt[-1]
            vals[-2:], wts[-2:], cnt[-2:] = [v], [wsum], [c]
    return np.repeat(vals, cnt)


# ---------------------------------------------------------------------------------------------
# Cell simulation for fitting (exact exponential update under zero-order-hold current)
# ---------------------------------------------------------------------------------------------

def simulate_tables(tables: dict, t, current, temp_k, z0: float, q_ref_ah: float, r_scale: float = 1.0) -> dict:
    """Simulate one cell on a sample grid with the template tables (bilinear in z, T), loop form.

    Current I_i holds over (t_{i-1}, t_i]; RC states use the exact exponential update with the
    parameters at the start of each sub-step (<= SIM_MAX_STEP_S; temperature linear between samples).
    Returns voltages at t, the heat rate and z.
    """
    soc = tables["soc_knots"]; tk = tables["temperature_knots_k"]
    t = np.asarray(t, float); current = np.asarray(current, float); temp_k = np.asarray(temp_k, float)
    n = len(t)
    nb = len(tables["rc"])
    v_rc = np.zeros(nb)
    out_v = np.empty(n); heat = np.empty(n); zs = np.empty(n)
    q = 0.0
    prev_t = 0.0
    z_prev = z0
    ocv_t = ecm.Table(tuple(soc), tuple(tk), tuple(tuple(r) for r in tables["ocv"]))
    r0_t = ecm.Table(tuple(soc), tuple(tk), tuple(tuple(r) for r in tables["r0"]))
    rc_t = [(ecm.Table(tuple(soc), tuple(tk), tuple(tuple(r) for r in b["r"])),
             ecm.Table(tuple(soc), tuple(tk), tuple(tuple(r) for r in b["tau"]))) for b in tables["rc"]]
    prev_temp = temp_k[0]
    for i in range(n):
        h_total = t[i] - prev_t
        cur = current[i]
        n_sub = max(1, int(math.ceil(h_total / SIM_MAX_STEP_S - 1e-9)))
        h = h_total / n_sub
        for j in range(n_sub):
            temp_j = prev_temp + (temp_k[i] - prev_temp) * (j / n_sub)
            for k, (rt, tt) in enumerate(rc_t):
                r = r_scale * ecm.lookup(rt, z_prev, temp_j)
                a = math.exp(-h / ecm.lookup(tt, z_prev, temp_j))
                v_rc[k] = v_rc[k] * a + r * cur * (1.0 - a)
            q += cur * h
            z_prev = z0 - q / (3600.0 * q_ref_ah)
        z = z_prev
        temp = temp_k[i]
        r0 = r_scale * ecm.lookup(r0_t, z, temp)
        out_v[i] = ecm.lookup(ocv_t, z, temp) - r0 * cur - float(v_rc.sum())
        heat[i] = cur * cur * r0 + sum(v_rc[k] ** 2 / (r_scale * ecm.lookup(rc_t[k][0], z, temp)) for k in range(nb))
        zs[i] = z
        prev_t = t[i]
        prev_temp = temp
    return {"v": out_v, "heat_w": heat, "z": zs}


# ---------------------------------------------------------------------------------------------
# LiPo (Galeotti, BAK LP-503562, 25 °C)
# ---------------------------------------------------------------------------------------------

@dataclass
class Segment:
    t: np.ndarray
    current: np.ndarray
    v: np.ndarray
    h: np.ndarray
    q_ah: np.ndarray       # charge extracted since run start at each sample
    q0_ah: float
    rest_before_s: float | None


@dataclass
class Run:
    name: str
    segments: list
    q_ref_ah: float
    r_scale: float


def make_run(name: str, parts: list, q_ref_ah: float, r_scale: float, rest_s: float) -> Run:
    segs, q0 = [], 0.0
    for k, (t, cur, v) in enumerate(parts):
        h = np.diff(np.r_[0.0, t])   # current onset assumed at t = 0 (first sample at about 0.43 s)
        q = q0 + np.cumsum(cur * h) / 3600.0
        segs.append(Segment(t, cur, v, h, q, q0, None if k == 0 else rest_s))
        q0 = float(q[-1])
    return Run(name, segs, q_ref_ah, r_scale)


def galeotti_pulses(reg: InputRegister, cell: str, cycle: str) -> list:
    names = sorted(f.name for f in (reg.galeotti_dir / cell).iterdir()
                   if f.name.startswith(f"1_{cycle}_") and f.name.endswith("_pardisch.csv"))
    parts = [(n, load_galeotti(reg.galeotti(cell, n))) for n in names]
    parts.sort(key=lambda p: -p[1][2][0])      # chronological order = decreasing starting voltage
    return parts


def extracted_ah(t, cur) -> float:
    return float(np.sum(cur * np.diff(np.r_[0.0, t])) / 3600.0)


class LipoModel:
    """OCV on SOC_KNOTS (monotone by construction); R0 and the RC resistances each constant or on LIPO_R_KNOTS;
    one SOC-independent tau per branch."""

    def __init__(self, branches: int, r0_soc: bool, rc_soc: bool):
        self.k = branches
        self.r0_soc, self.rc_soc = r0_soc, rc_soc
        self.zo = np.array(SOC_KNOTS)
        self.zr = np.array(LIPO_R_KNOTS)
        self.n0 = len(self.zr) if r0_soc else 1
        self.nk = len(self.zr) if rc_soc else 1

    @property
    def label(self) -> str:
        if self.r0_soc and (self.rc_soc or self.k == 0):
            tail = "Rz"
        elif self.rc_soc:
            tail = "R0const-RCz"
        else:
            tail = "Rconst"
        return f"K{self.k}-{tail}"

    @property
    def parameters(self) -> int:
        return len(self.zo) + self.n0 + self.k * (self.nk + 1)

    def unpack(self, th):
        m = len(self.zo)
        ocv = th[0] + np.r_[0.0, np.cumsum(th[1:m])]
        i = m
        r0 = th[i:i + self.n0]; i += self.n0
        br = []
        for _ in range(self.k):
            r = th[i:i + self.nk]; i += self.nk
            br.append((r, math.exp(th[i]))); i += 1
        return ocv, r0, br

    def tau_index(self, b: int) -> int:
        return len(self.zo) + self.n0 + b * (self.nk + 1) + self.nk

    def r_of(self, r, z):
        z = np.asarray(z, dtype=float)
        return np.interp(np.clip(z, 0.0, 1.0), self.zr, r) if len(r) > 1 else np.full_like(z, r[0])

    def simulate(self, th, run: Run) -> list:
        ocv, r0, br = self.unpack(th)
        v_state = [0.0] * self.k
        out = []
        for seg in run.segments:
            if seg.rest_before_s is not None:
                v_state = [v * math.exp(-seg.rest_before_s / tau) for v, (_, tau) in zip(v_state, br)]
            z = 1.0 - seg.q_ah / run.q_ref_ah
            z_prev = np.r_[1.0 - seg.q0_ah / run.q_ref_ah, z[:-1]]
            v = np.interp(np.clip(z, 0, 1), self.zo, ocv) - run.r_scale * self.r_of(r0, z) * seg.current
            new_state = []
            for (r, tau), v_init in zip(br, v_state):
                x = run.r_scale * self.r_of(r, z_prev) * seg.current
                a0 = math.exp(-seg.h[0] / tau)
                y = np.empty_like(x)
                y[0] = v_init * a0 + x[0] * (1.0 - a0)
                if len(x) > 1:
                    a = math.exp(-float(np.mean(seg.h[1:])) / tau)
                    y[1:], _ = lfilter([1.0 - a], [1.0, -a], x[1:], zi=[a * y[0]])
                v = v - y
                new_state.append(float(y[-1]))
            v_state = new_state
            out.append(v)
        return out

    def errors_z(self, th, run: Run) -> tuple:
        """Model minus data and z for the samples inside the template domain (z >= 0)."""
        errs, zs = [], []
        for seg, vm in zip(run.segments, self.simulate(th, run)):
            z = 1.0 - seg.q_ah / run.q_ref_ah
            mask = z >= 0.0
            errs.append((vm - seg.v)[mask]); zs.append(z[mask])
        return np.concatenate(errs), np.concatenate(zs)

    def errors(self, th, run: Run) -> np.ndarray:
        return self.errors_z(th, run)[0]

    def initial(self, ocv_guess):
        ocv0 = np.maximum.accumulate(ocv_guess(self.zo))
        th = [ocv0[0]] + list(np.maximum(np.diff(ocv0), 1e-4))
        lb = [2.0] + [0.0] * (len(self.zo) - 1)
        ub = [4.5] + [1.0] * (len(self.zo) - 1)
        th += [0.08] * self.n0; lb += [1e-4] * self.n0; ub += [1.0] * self.n0
        for _ in range(self.k):
            th += [0.04] * self.nk + [0.0]; lb += [1e-5] * self.nk + [math.log(TAU_FLOOR_S)]
            ub += [1.0] * self.nk + [math.log(TAU_CEILING_S)]
        return np.array(th), np.array(lb), np.array(ub)

    def fit(self, runs: list, ocv_guess) -> dict:
        th0, lb, ub = self.initial(ocv_guess)
        starts = {0: [()], 1: [(10.0,), (60.0,)], 2: [(3.0, 60.0), (20.0, 600.0), (30.0, 150.0)]}[self.k]
        best = None
        for taus in starts:
            th = th0.copy()
            for b, tau in enumerate(taus):
                th[self.tau_index(b)] = math.log(tau)
            sol = least_squares(lambda p: self._residual(p, runs), th, bounds=(lb, ub), x_scale="jac",
                                max_nfev=600)
            if best is None or sol.cost < best.cost:
                best = sol
        ocv, r0, br = self.unpack(best.x)
        br = sorted(br, key=lambda x: x[1])            # branches by increasing tau
        return {"theta": best.x, "ocv": ocv, "r0": r0, "branches": br, "cost": float(best.cost),
                "nfev": int(best.nfev), "status": int(best.status),
                "tau_at_bound": [bool(abs(math.log(tau) - lb[self.tau_index(0)]) < 1e-6 or
                                      abs(math.log(tau) - ub[self.tau_index(0)]) < 1e-6) for _, tau in br]}

    def _residual(self, th, runs):
        res = np.concatenate([self.errors(th, r) for r in runs])
        ocv, _, _ = self.unpack(th)
        return np.r_[res, OCV_SMOOTHING_V * np.diff(ocv, 2)]

    def tables(self, fitted: dict) -> dict:
        z = np.array(SOC_KNOTS)
        return {
            "ocv": [list(fitted["ocv"])],
            "r0": [list(self.r_of(fitted["r0"], z))],
            "rc": [{"r": [list(self.r_of(r, z))], "tau": [[tau] * len(z)]} for r, tau in fitted["branches"]],
        }


def lipo_candidates() -> list:
    """Candidate structures ordered by complexity (fewest parameters first within each K)."""
    out = [LipoModel(0, False, False), LipoModel(0, True, False)]
    for k in (1, 2):
        out += [LipoModel(k, False, False), LipoModel(k, False, True), LipoModel(k, True, True)]
    return out


def lipo_section(reg: InputRegister) -> dict:
    cells = {}
    for cell in GALEOTTI_CELLS:
        std = load_galeotti(reg.galeotti(cell, "0_0_1_stddischarge.csv"))
        cells[cell] = {
            "std": std, "q_ref_ah": extracted_ah(std[0], std[1]),
            "s0": load_galeotti(reg.galeotti(cell, "2_0_stressdischarge.csv")),
            "s1": load_galeotti(reg.galeotti(cell, "2_1_stressdischarge.csv")),
            "pulses": galeotti_pulses(reg, cell, "0"),
        }
    a = cells[TEMPLATE_CELL]
    q_a = a["q_ref_ah"]

    def runs_for(cell: str, rest_s: float = REST_S) -> dict:
        c = cells[cell]
        q, scale = c["q_ref_ah"], q_a / c["q_ref_ah"]   # template resistance normalised R ∝ 1/Q (§2)
        return {
            "pulses": make_run(f"{cell}/1_0_*_pardisch", [p[1] for p in c["pulses"]], q, scale, rest_s),
            "std": make_run(f"{cell}/0_0_1_stddischarge", [c["std"]], q, scale, rest_s),
            "s0": make_run(f"{cell}/2_0_stressdischarge", [c["s0"]], q, scale, rest_s),
            "s1": make_run(f"{cell}/2_1_stressdischarge", [c["s1"]], q, scale, rest_s),
        }

    ra = runs_for(TEMPLATE_CELL)
    fit_runs = [ra["pulses"], ra["s0"]]
    held_out = [ra["std"], ra["s1"]]
    for cell in GALEOTTI_CELLS:
        if cell != TEMPLATE_CELL:
            r = runs_for(cell)
            held_out += [r["pulses"], r["std"], r["s0"], r["s1"]]

    std_run = ra["std"].segments[0]
    z_std = 1.0 - std_run.q_ah / q_a

    def ocv_guess(z):
        return np.interp(z, z_std[::-1], std_run.v[::-1]) + 0.12

    # Repeatability margin: same cell, same protocol, consecutive stress discharges (2_0 vs 2_1),
    # RMS difference at equal extracted charge over the scored band (z >= SCORE_MIN_SOC).
    s0, s1 = ra["s0"].segments[0], ra["s1"].segments[0]
    q_common = np.linspace(0.0, (1.0 - SCORE_MIN_SOC) * q_a, 400)
    margin = rms(np.interp(q_common, s0.q_ah, s0.v) - np.interp(q_common, s1.q_ah, s1.v))

    candidates = []
    for model in lipo_candidates():
        fitted = model.fit(fit_runs, ocv_guess)
        fit_err, fit_z = zip(*[model.errors_z(fitted["theta"], r) for r in fit_runs])
        held = {r.name: error_stats(*model.errors_z(fitted["theta"], r)) for r in held_out}
        score = float(np.mean([h["score_rmse_v"] for h in held.values()]))
        same_cell = float(np.mean([held[r.name]["score_rmse_v"] for r in held_out[:2]]))
        candidates.append({"model": model, "fitted": fitted,
                           "fit": error_stats(np.concatenate(fit_err), np.concatenate(fit_z)), "held_out": held,
                           "score_v": score, "same_cell_score_v": same_cell, "parameters": model.parameters})
    # A candidate with a time constant on its search bound is reported but not eligible (degenerate branch).
    eligible = [c for c in candidates if not any(c["fitted"]["tau_at_bound"])]
    best_score = min(c["score_v"] for c in eligible)
    chosen = next(c for c in eligible if c["score_v"] <= best_score + margin)   # ordered by complexity

    model, fitted = chosen["model"], chosen["fitted"]
    # Parameter spread across the five cells (same structure, each cell's own pulses + stress cycle 0).
    spread = {}
    for cell in GALEOTTI_CELLS:
        r = runs_for(cell)
        r_unscaled = [Run(x.name, x.segments, x.q_ref_ah, 1.0) for x in (r["pulses"], r["s0"])]
        f = model.fit(r_unscaled, ocv_guess)
        spread[cell] = summarize_lipo(model, f, cells[cell]["q_ref_ah"])
        spread[cell]["fit"] = error_stats(np.concatenate([model.errors(f["theta"], x) for x in r_unscaled]))
        spread[cell]["tau_at_bound"] = f["tau_at_bound"]
    # Rest-duration sensitivity for the template cell.
    rs = runs_for(TEMPLATE_CELL, REST_SENSITIVITY_S)
    f_rest = model.fit([rs["pulses"], rs["s0"]], ocv_guess)
    rest_sens = summarize_lipo(model, f_rest, q_a)
    rest_sens["rest_s"] = REST_SENSITIVITY_S
    rest_sens["held_out_same_cell"] = {x.name: error_stats(*model.errors_z(f_rest["theta"], x))
                                       for x in (rs["std"], rs["s1"])}

    # Two-rate (1 A vs 3 A) resistance at equal extracted charge, model-free, for the report.
    std_seg, s0_seg = ra["std"].segments[0], ra["s0"].segments[0]
    two_rate = []
    for zq in (0.9, 0.75, 0.5, 0.25, 0.1):
        qq = (1.0 - zq) * q_a
        two_rate.append({"z": zq, "r_two_rate_ohm": float((np.interp(qq, std_seg.q_ah, std_seg.v)
                                                            - np.interp(qq, s0_seg.q_ah, s0_seg.v)) / 2.0)})

    tables = model.tables(fitted)
    # Consistency of the SOC floor: model voltage at z = 0 under the 1 A reference discharge.
    sim_std = model.simulate(fitted["theta"], ra["std"])[0]
    z_end = 1.0 - std_run.q_ah / q_a
    v_at_floor = float(np.interp(0.0, z_end[::-1], sim_std[::-1]))

    return {
        "cells": cells, "runs": ra, "q_ref_ah": q_a, "margin_v": margin, "candidates": candidates,
        "chosen": chosen, "model": model, "fitted": fitted, "tables": tables, "spread": spread,
        "rest_sensitivity": rest_sens, "two_rate": two_rate, "v_model_at_floor_1a": v_at_floor,
        "fit_runs": [r.name for r in fit_runs], "held_out_runs": [r.name for r in held_out],
    }


def summarize_lipo(model: LipoModel, fitted: dict, q_ref_ah: float) -> dict:
    out = {"q_ref_ah": q_ref_ah, "ocv_v_at_0p5": float(np.interp(0.5, model.zo, fitted["ocv"])),
           "r0_ohm_at_0p5": float(model.r_of(fitted["r0"], np.array([0.5]))[0])}
    for b, (r, tau) in enumerate(fitted["branches"], start=1):
        out[f"r{b}_ohm_at_0p5"] = float(model.r_of(r, np.array([0.5]))[0])
        out[f"tau{b}_s"] = float(tau)
    return out


def lipo_aging(reg: InputRegister, lipo: dict) -> list:
    """Capacity and apparent-resistance trend of the template cell with cycling (evidence only)."""
    model, fitted = lipo["model"], lipo["fitted"]
    rows = []
    cell_dir = reg.galeotti_dir / TEMPLATE_CELL
    for cyc in AGING_CYCLES:
        row = {"cycle": int(cyc)}
        std_name = f"0_{cyc}_1_stddischarge.csv"
        if (cell_dir / std_name).exists():
            t, cur, v = load_galeotti(reg.galeotti(TEMPLATE_CELL, std_name))
            row["capacity_1a_ah"] = extracted_ah(t, cur)
            row["v_at_0p43s_1a"] = float(v[0])
        pulses = galeotti_pulses(reg, TEMPLATE_CELL, cyc)
        row["ladder_charge_ah"] = float(sum(extracted_ah(p[1][0], p[1][1]) for p in pulses))
        # Apparent resistance at each pulse start: (OCV_cycle0(z) - V(0.43 s)) / I, z on the ladder's own charge.
        q_cycle = row.get("capacity_1a_ah", row["ladder_charge_ah"])
        q0, r_app, recov = 0.0, [], []
        prev_end = None
        for _, (t, cur, v) in pulses:
            z = 1.0 - q0 / q_cycle
            if 0.15 <= z <= 0.95:
                r_app.append((float(np.interp(z, model.zo, fitted["ocv"])) - float(v[0])) / float(cur[0]))
                if prev_end is not None:
                    recov.append(float(v[0] - prev_end))
            prev_end = float(v[-1])
            q0 += extracted_ah(t, cur)
        row["apparent_r_ohm_median"] = float(np.median(r_app)) if r_app else None
        row["rest_recovery_v_median"] = float(np.median(recov)) if recov else None
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------------------------
# Li-ion (Kollmeyer, LG HG2, 0/10/25/40 °C)
# ---------------------------------------------------------------------------------------------

def hg2_c20(reg: InputRegister, tid: str) -> dict:
    d = load_hg2(reg.hg2(f"{tid}_C20DisCh.csv"))
    m = (d["step"] == 22) & (np.array(d["status"]) == "DCH")
    ah = -d["ah"][m]
    q = float(ah[-1])
    z = 1.0 - ah / q
    return {"q_ah": q, "z": z[::-1], "v": d["v"][m][::-1], "i": float(d["i"][m].mean()),
            "temp_k": float(d["temp_c"][m].mean() + 273.15), "v_end": float(d["v"][m][-1]),
            "last_sample": (float(d["t"][-1]), float(d["temp_c"][-1] + 273.15), d["status"][-1])}


def hg2_windows(d: dict, q_ah: float) -> list:
    """One window per HPPC SOC level: preceding 0.9 A SOC step + 1 h rest + pulse block."""
    segs = step_segments(d)
    soc_steps = [k for k, s in enumerate(segs) if s[2] == "DCH" and s[3] > 100.0]
    bounds = [None] + soc_steps
    windows = []
    for j, b in enumerate(bounds):
        s0 = 0 if b is None else segs[b][0]
        e0 = segs[soc_steps[j]][0] if j < len(soc_steps) else len(d["t"])
        pulses = [s for s in segs if s[0] >= s0 and s[1] <= e0 and s[2] == "DCH" and 9.0 < s[3] < 11.0]
        if len(pulses) < 2:
            continue
        steps = []
        for s, e, _, _, _ in pulses:
            steps.append((d["v"][s - 1] - d["v"][s]) / (d["i"][s] - d["i"][s - 1]))
            steps.append((d["v"][e] - d["v"][e - 1]) / (d["i"][e - 1] - d["i"][e]))
        z_level = 1.0 + d["ah"][pulses[0][0] - 1] / q_ah
        windows.append({"s0": s0, "e0": e0, "z_level": float(z_level), "z_start": float(1.0 + d["ah"][s0] / q_ah),
                        "r0_steps_ohm": [float(x) for x in steps], "r0_ohm": float(np.median(steps)),
                        "temp_k": float(d["temp_c"][s0:e0].mean() + 273.15),
                        "pulse_currents_a": [float(d["i"][s:e].mean()) for s, e, _, _, _ in pulses]})
    return windows


class Hg2Window:
    """Fast simulator of one HPPC window on a uniform grid (ZOH current, exact RC update)."""

    def __init__(self, d: dict, w: dict, c20: dict):
        s0, e0 = w["s0"], w["e0"]
        self.tt = d["t"][s0:e0] - d["t"][s0]
        self.v = d["v"][s0:e0]
        cur = d["i"][s0:e0]
        n = int(math.ceil(self.tt[-1] / HG2_GRID_S)) + 1
        grid = np.arange(n) * HG2_GRID_S
        idx = np.clip(np.searchsorted(self.tt, grid - 1e-6), 0, len(self.tt) - 1)
        self.ig = cur[idx]
        zg = w["z_start"] - np.cumsum(self.ig) * HG2_GRID_S / 3600.0 / c20["q_ah"]
        self.ocv_shape = np.interp(zg, c20["z"], c20["v"])
        self.gi = np.clip(np.round(self.tt / HG2_GRID_S).astype(int), 0, n - 1)
        self.r0 = w["r0_ohm"]
        # Sensitivity only: sqrt of the time each sample represents (equal weight per second of record).
        self.time_weight = np.sqrt(np.clip(np.gradient(self.tt), 0.05, 60.0)) if len(self.tt) > 1 else np.ones(1)

    def model(self, offset: float, r0: float, branches: list) -> np.ndarray:
        vg = self.ocv_shape + offset - r0 * self.ig
        for r, tau in branches:
            a = math.exp(-HG2_GRID_S / tau)
            vg = vg - lfilter([r * (1.0 - a)], [1.0, -a], self.ig)
        return vg[self.gi]


def fit_window(win: Hg2Window, k: int, fixed_tau: list | None = None, time_weighted: bool = False) -> dict:
    lt_lo, lt_hi = math.log(TAU_FLOOR_S), math.log(TAU_CEILING_S)
    if k == 0:
        p0, lb, ub = [0.0, 0.03], [-0.3, 1e-4], [0.3, 1.0]

        def unpack(p):
            return p[0], p[1], []
    elif fixed_tau is None:
        if k == 1:
            p0, lb, ub = [0.0, 0.01, math.log(20.0)], [-0.3, 1e-6, lt_lo], [0.3, 1.0, lt_hi]

            def unpack(p):
                return p[0], win.r0, [(p[1], math.exp(p[2]))]
        else:
            p0 = [0.0, 0.005, math.log(3.0), 0.02, math.log(60.0)]
            lb, ub = [-0.3, 1e-6, lt_lo, 1e-6, lt_lo], [0.3, 1.0, lt_hi, 1.0, lt_hi]

            def unpack(p):
                return p[0], win.r0, [(p[1], math.exp(p[2])), (p[3], math.exp(p[4]))]
    else:
        p0, lb, ub = [0.0] + [0.01] * k, [-0.3] + [1e-6] * k, [0.3] + [1.0] * k

        def unpack(p):
            return p[0], win.r0, [(p[1 + b], fixed_tau[b]) for b in range(k)]
    weight = win.time_weight if time_weighted else 1.0
    sol = least_squares(lambda p: (win.model(*unpack(p)) - win.v) * weight, np.array(p0), bounds=(lb, ub),
                        x_scale="jac", max_nfev=400)
    offset, r0, br = unpack(sol.x)
    br = sorted(br, key=lambda x: x[1])
    err = win.model(offset, r0, br) - win.v
    return {"offset_v": float(offset), "r0_ohm": float(r0), "branches": [(float(r), float(t)) for r, t in br],
            "rmse_v": rms(err), "samples": int(err.size)}


def arrhenius(points: list) -> dict:
    """Pooled fit ln R = a_z + Ea/(Rg·T) over (z, T, R) points with a separate intercept per z."""
    zs = sorted({p[0] for p in points})
    rows, rhs = [], []
    for z, temp, r in points:
        rows.append([1.0 if z == zz else 0.0 for zz in zs] + [1.0 / (RG * temp)])
        rhs.append(math.log(r))
    a, b = np.array(rows), np.array(rhs)
    coef, *_ = np.linalg.lstsq(a, b, rcond=None)
    resid = b - a @ coef
    dof = max(len(b) - len(coef), 1)
    s2 = float(resid @ resid) / dof
    cov = s2 * np.linalg.inv(a.T @ a)
    centered = b - np.array([np.mean([math.log(p[2]) for p in points if p[0] == z]) for z, _, _ in points])
    r2 = 1.0 - float(resid @ resid) / float(centered @ centered) if float(centered @ centered) > 0 else float("nan")
    per_z = []
    for z in zs:
        sub = [(t, r) for zz, t, r in points if zz == z]
        x = np.array([1.0 / (RG * t) for t, _ in sub]); y = np.log([r for _, r in sub])
        slope = float(np.polyfit(x, y, 1)[0])
        per_z.append({"z": z, "ea_j_per_mol": slope})
    return {"ea_j_per_mol": float(coef[-1]), "ea_standard_error_j_per_mol": float(math.sqrt(cov[-1, -1])),
            "r2_within_z": r2, "rms_log_residual": float(math.sqrt(float(resid @ resid) / len(b))),
            "points": len(points), "per_z": per_z}


def hg2_dis_run(reg: InputRegister, tid: str, kind: str) -> dict:
    """A held-out constant-current discharge: time since step start, current, voltage, cell temperature."""
    d = load_hg2(reg.hg2(f"{tid}_{kind}.csv"))
    step = 28 if kind == "Dis_0p5C" else 34
    m = (d["step"] == step) & (np.array(d["status"]) == "DCH")
    t = d["step_time"][m]
    out = {"t": t, "i": d["i"][m], "v": d["v"][m], "temp_k": d["temp_c"][m] + 273.15,
           "prog_start_s": float(d["t"][m][0] - t[0]),
           "last_sample": (float(d["t"][-1]), float(d["temp_c"][-1] + 273.15), d["status"][-1])}
    # Cell temperature before the discharge: last rest sample preceding it, when the file has it.
    before = d["t"] < out["prog_start_s"]
    out["temp_before_k"] = float(d["temp_c"][before][-1] + 273.15) if before.any() else None
    return out


def hg2_section(reg: InputRegister) -> dict:
    tests = {}
    for tid, t_knot in HG2_TESTS:
        d = load_hg2(reg.hg2(f"{tid}_HPPC.csv"))
        c20 = hg2_c20(reg, tid)
        wins = hg2_windows(d, c20["q_ah"])
        sims = [Hg2Window(d, w, c20) for w in wins]
        dis = {kind: hg2_dis_run(reg, tid, kind) for kind in ("Dis_0p5C", "Dis_2C")}
        # The rest that precedes the 2C discharge is recorded at the end of the 0.5C file (same program).
        # Likewise the rest before the 0.5C discharge closes the C/20 file.
        for kind, prev in (("Dis_2C", dis["Dis_0p5C"]["last_sample"]), ("Dis_0p5C", c20["last_sample"])):
            t_last, temp_last, status_last = prev
            gap = dis[kind]["prog_start_s"] - t_last
            if dis[kind]["temp_before_k"] is None and status_last == "PAU" and 0.0 <= gap <= 600.0:
                dis[kind]["temp_before_k"] = temp_last
        tests[tid] = {"t_knot": t_knot, "c20": c20, "windows": wins, "sims": sims, "dis": dis}

    # Repeatability margin from two 1C capacity tests of the same cell at 25 °C.
    reps = []
    for tid in HG2_REPEAT_PAIR:
        d = load_hg2(reg.hg2(f"{tid}_Cap_1C.csv"))
        m = np.array(d["status"]) == "DCH"
        reps.append((-d["ah"][m], d["v"][m]))
    q_common = np.linspace(0.05, (1.0 - SCORE_MIN_SOC) * tests["549"]["c20"]["q_ah"], 400)
    margin = rms(np.interp(q_common, *reps[0]) - np.interp(q_common, *reps[1]))

    candidates = [hg2_candidate(tests, k) for k in (0, 1, 2)]
    sensitivity = {f"K{k}_time_weighted": hg2_candidate(tests, k, time_weighted=True)["score_v"] for k in (1, 2)}
    best = min(c["score_v"] for c in candidates)
    chosen = next(c for c in candidates if c["score_v"] <= best + margin)
    return {"tests": tests, "candidates": candidates, "chosen": chosen, "margin_v": margin,
            "sensitivity": sensitivity}


def hg2_candidate(tests: dict, k: int, time_weighted: bool = False) -> dict:
    """Fit K branches at every temperature, build the template tables and score them on the held-out discharges."""
    per_t = {}
    for tid, info in tests.items():
        free = [fit_window(s, k, time_weighted=time_weighted) for s in info["sims"]]
        if k == 0:
            fixed_tau, final = [], free
        else:
            usable = [f for f, w in zip(free, info["windows"]) if w["z_level"] >= 0.1]
            fixed_tau = [float(np.median([f["branches"][b][1] for f in usable])) for b in range(k)]
            final = [fit_window(s, k, fixed_tau, time_weighted) for s in info["sims"]]
        per_t[tid] = {"free": free, "final": final, "tau_s": fixed_tau}
    tables_meas = {tid: hg2_level_tables(tests[tid], per_t[tid], k) for tid in tests}
    ea = hg2_arrhenius(tests, tables_meas, k)
    tables = hg2_template_tables(tests, tables_meas, ea, k)
    held = {}
    for tid, info in tests.items():
        for kind, run in info["dis"].items():
            # Scored: normalised by the session's own C/20 capacity at that temperature (removes the capacity
            # fade of the test campaign, see README); also reported with the 25 °C template capacity.
            sim_s = simulate_tables(tables, run["t"], run["i"], run["temp_k"], 1.0, info["c20"]["q_ah"])
            held[f"{tid}_{kind}"] = error_stats(sim_s["v"] - run["v"], sim_s["z"])
            sim = simulate_tables(tables, run["t"], run["i"], run["temp_k"], 1.0, tests["549"]["c20"]["q_ah"])
            held[f"{tid}_{kind}_template_capacity"] = error_stats(sim["v"] - run["v"], sim["z"])
    fit_err = [f["rmse_v"] for tid in tests for f in per_t[tid]["final"]]
    score = float(np.mean([v["score_rmse_v"] for key, v in held.items() if not key.endswith("_template_capacity")]))
    return {"k": k, "per_t": per_t, "tables_measured": tables_meas, "arrhenius": ea, "tables": tables,
            "held_out": held, "score_v": score, "fit_window_rmse_mean_v": float(np.mean(fit_err))}


def hg2_level_tables(info: dict, fits: dict, k: int) -> dict:
    """Per-level resistances at the measured cell temperature, then OCV from C/20 with an R correction."""
    z_lv = np.array([w["z_level"] for w in info["windows"]])
    order = np.argsort(z_lv)
    z_lv = z_lv[order]
    if k == 0:
        r0 = np.array([f["r0_ohm"] for f in fits["final"]])[order]
    else:
        r0 = np.array([w["r0_ohm"] for w in info["windows"]])[order]
    rk = [np.array([f["branches"][b][0] for f in fits["final"]])[order] for b in range(k)]
    temp = float(np.mean([w["temp_k"] for w in info["windows"]]))
    c20 = info["c20"]
    r_dc = np.interp(c20["z"], z_lv, r0 + sum(rk) if k else r0)
    pseudo = c20["v"] + c20["i"] * r_dc
    ocv_iso = isotonic_increasing(pseudo)
    z = np.array(SOC_KNOTS)
    return {
        "z_levels": z_lv, "temp_k": temp,
        "ocv": np.interp(z, c20["z"], ocv_iso),
        "r0": np.interp(z, z_lv, r0), "rk": [np.interp(z, z_lv, r) for r in rk], "tau": list(fits["tau_s"]),
        "level_r0": r0, "level_rk": rk,
        "ocv_correction_max_v": float(np.max(c20["i"] * r_dc)),
        "isotonic_max_adjust_v": float(np.max(np.abs(ocv_iso - pseudo))),
    }


def hg2_arrhenius(tests: dict, tables: dict, k: int) -> dict:
    zc = (0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)
    out = {}
    names = ["r0"] + [f"r{b + 1}" for b in range(k)]
    for name in names:
        pts = []
        for tid in tests:
            tb = tables[tid]
            vals = tb["level_r0"] if name == "r0" else tb["level_rk"][int(name[1:]) - 1]
            for z in zc:
                pts.append((z, tb["temp_k"], float(np.interp(z, tb["z_levels"], vals))))
        out[name] = arrhenius(pts)
    return out


def hg2_template_tables(tests: dict, tables: dict, ea: dict, k: int) -> dict:
    """Rows at the knot temperatures: resistances shifted from the measured cell temperature by Arrhenius."""
    order = [tid for tid, _ in HG2_TESTS]
    rows = {"ocv": [], "r0": [], "rc": [{"r": [], "tau": []} for _ in range(k)]}
    for tid in order:
        tb, t_knot = tables[tid], tests[tid]["t_knot"]
        shift = lambda name: math.exp(ea[name]["ea_j_per_mol"] / RG * (1.0 / t_knot - 1.0 / tb["temp_k"]))
        rows["ocv"].append(list(tb["ocv"]))
        rows["r0"].append(list(tb["r0"] * shift("r0")))
        for b in range(k):
            rows["rc"][b]["r"].append(list(tb["rk"][b] * shift(f"r{b + 1}")))
            rows["rc"][b]["tau"].append([tb["tau"][b]] * len(SOC_KNOTS))
    rows["soc_knots"] = list(SOC_KNOTS)
    rows["temperature_knots_k"] = list(TEMPERATURE_KNOTS_K)
    return rows


def hg2_thermal(hg2: dict) -> dict:
    """Identify C_th = m·c_p and hA from the 2C temperature rise (heat from the fitted model, entropic heat omitted)."""
    chosen, tests = hg2["chosen"], hg2["tests"]
    q_ref = tests["549"]["c20"]["q_ah"]
    runs = []
    for tid, info in tests.items():
        run = info["dis"]["Dis_2C"]
        sim = simulate_tables(chosen["tables"], run["t"], run["i"], run["temp_k"], 1.0, q_ref)
        t_amb = run["temp_before_k"] if run["temp_before_k"] is not None else float(run["temp_k"][0])
        runs.append({"tid": tid, "t": run["t"], "temp": run["temp_k"], "heat": sim["heat_w"], "t_amb": t_amb,
                     "amb_source": "rest before discharge" if run["temp_before_k"] is not None else "first sample"})

    def predict(c_th, ha, r):
        # Exact update over each sampling interval with the interval-end heat held (ZOH).
        temp = np.empty_like(r["temp"]); x = r["t_amb"]; prev = 0.0
        for i, (tt, q) in enumerate(zip(r["t"], r["heat"])):
            h = tt - prev
            a = math.exp(-ha / c_th * h)
            x = r["t_amb"] + q / ha + (x - r["t_amb"] - q / ha) * a
            temp[i] = x; prev = tt
        return temp

    def resid(p):
        return np.concatenate([predict(math.exp(p[0]), math.exp(p[1]), r) - r["temp"] for r in runs])

    sol = least_squares(resid, np.array([math.log(45.0), math.log(0.05)]), x_scale="jac")
    jac = sol.jac
    dof = max(sol.fun.size - 2, 1)
    cov = float(sol.fun @ sol.fun) / dof * np.linalg.inv(jac.T @ jac)
    c_th, ha = math.exp(sol.x[0]), math.exp(sol.x[1])
    rel_se = [math.sqrt(cov[0, 0]), math.sqrt(cov[1, 1])]          # log-parameters: relative standard errors
    corr = float(cov[0, 1] / math.sqrt(cov[0, 0] * cov[1, 1]))
    per_run = []
    for r in runs:
        s = least_squares(lambda p: predict(math.exp(p[0]), math.exp(p[1]), r) - r["temp"], sol.x, x_scale="jac")
        per_run.append({"test": r["tid"], "c_th_j_per_k": math.exp(s.x[0]), "ha_w_per_k": math.exp(s.x[1]),
                        "rise_k": float(r["temp"].max() - r["t_amb"]), "t_amb_k": r["t_amb"],
                        "t_amb_source": r["amb_source"], "rmse_k": rms(s.fun)})
    # Held out: 0.5C runs with the joint C_th, hA.
    held = {}
    for tid, info in tests.items():
        run = info["dis"]["Dis_0p5C"]
        sim = simulate_tables(chosen["tables"], run["t"], run["i"], run["temp_k"], 1.0, q_ref)
        t_amb = run["temp_before_k"] if run["temp_before_k"] is not None else float(run["temp_k"][0])
        r = {"t": run["t"], "temp": run["temp_k"], "heat": sim["heat_w"], "t_amb": t_amb}
        held[tid] = {"rmse_k": rms(predict(c_th, ha, r) - r["temp"]), "rise_k": float(r["temp"].max() - t_amb)}
    cp = c_th / HG2_CELL_MASS_KG
    # Accept only a statistically resolved value inside the published whole-cell range; otherwise the
    # identified C_th describes the test fixture (thermocouple, soldered 10 AWG leads), not the cell.
    identifiable = rel_se[0] < 0.15 and CP_PUBLISHED_RANGE[0] <= cp <= CP_PUBLISHED_RANGE[1]
    return {"c_th_j_per_k": c_th, "ha_w_per_k": ha, "c_th_relative_se": rel_se[0], "ha_relative_se": rel_se[1],
            "correlation": corr, "rmse_k": rms(sol.fun), "cell_mass_kg": HG2_CELL_MASS_KG, "cp_j_per_kg_k": cp,
            "identifiable": bool(identifiable), "per_run": per_run, "held_out_0p5c": held}


# ---------------------------------------------------------------------------------------------
# Template assembly and reference-law cross-check
# ---------------------------------------------------------------------------------------------

def lipo_template_tables(lipo: dict, hg2: dict) -> dict:
    """25 °C LiPo tables; other temperature rows borrow the HG2 Arrhenius factors (OCV and tau unchanged)."""
    base = lipo["tables"]
    ea = hg2["chosen"]["arrhenius"]
    k = len(base["rc"])
    t_ref = 298.15
    rows = {"soc_knots": list(SOC_KNOTS), "temperature_knots_k": list(TEMPERATURE_KNOTS_K), "ocv": [], "r0": [],
            "rc": [{"r": [], "tau": []} for _ in range(k)], "ea_used": {}}
    # Each LiPo RC branch borrows the activation energy of the HG2 branch with the nearest time constant at
    # 25 °C (same physical process band); R0 borrows the HG2 R0 activation energy.
    hg2_tau = [row[0] for row in (b["tau"][TEMPERATURE_KNOTS_K.index(298.15)] for b in hg2["chosen"]["tables"]["rc"])]
    names = []
    for b in range(k):
        tau_l = base["rc"][b]["tau"][0][0]
        names.append(f"r{1 + int(np.argmin([abs(math.log(tau_l / x)) for x in hg2_tau]))}" if hg2_tau else "r0")
    rows["ea_used"]["r0"] = "r0"
    for t_knot in TEMPERATURE_KNOTS_K:
        f0 = math.exp(ea["r0"]["ea_j_per_mol"] / RG * (1.0 / t_knot - 1.0 / t_ref))
        rows["ocv"].append(list(base["ocv"][0]))
        rows["r0"].append([x * f0 for x in base["r0"][0]])
        for b in range(k):
            name = names[b]
            fb = math.exp(ea[name]["ea_j_per_mol"] / RG * (1.0 / t_knot - 1.0 / t_ref))
            rows["ea_used"][f"branch{b + 1}"] = name
            rows["rc"][b]["r"].append([x * fb for x in base["rc"][b]["r"][0]])
            rows["rc"][b]["tau"].append(list(base["rc"][b]["tau"][0]))
    return rows


def as_template_dict(tables: dict, template_id: str, chemistry: str, q_ref_ah: float) -> dict:
    """Minimal template (fit-side) for the reference law; build_batteries.py writes the published one."""
    def q(v, unit):
        return {"value": v, "unit": unit, "kind": "derived", "source": "BAT-05 fit"}
    return {
        "format": ecm.CELL_FORMAT, "id": template_id, "display_name": template_id, "chemistry": chemistry,
        "tier": "A", "generator": "fit", "provenance": {"fit_report": "", "inputs": []},
        "reference_capacity_ah": q(q_ref_ah, "Ah"), "soc_knots": q(list(tables["soc_knots"]), "1"),
        "temperature_knots_k": q(list(tables["temperature_knots_k"]), "K"),
        "ocv_v": q([list(r) for r in tables["ocv"]], "V"), "r0_ohm": q([list(r) for r in tables["r0"]], "ohm"),
        "rc_branches": [{"r_ohm": q([list(r) for r in b["r"]], "ohm"), "tau_s": q([list(r) for r in b["tau"]], "s")}
                        for b in tables["rc"]],
        "specific_heat_j_per_kg_k": q(1000.0, "J/(kg·K)"),
        "limits": {"v_max": q(4.2, "V"), "v_cutoff": q(2.75, "V"), "v_damage_floor": q(2.5, "V"),
                   "t_min_k": q(253.15, "K"), "t_max_k": q(333.15, "K")},
    }


def reference_replay(tables: dict, template_id: str, chemistry: str, q_ref_ah: float, t, cur, temp_k, v_meas,
                     dt: float = 1.0) -> dict:
    """Replay a measured discharge through the independent §4 law (RK4) with prescribed cell temperature."""
    tpl = as_template_dict(tables, template_id, chemistry, q_ref_ah)
    pack = ecm.normalize(ecm.single_cell_pack(tpl), tpl)
    t = np.asarray(t, float)
    t_end = float(math.ceil(t[-1]))

    def current_at(x):  # ZOH backward: the sample at or after x
        k = int(np.searchsorted(t, x + 1e-9))
        return float(cur[min(k, len(cur) - 1)])

    def temp_at(x):
        return float(np.interp(x, t, temp_k))

    out = ecm.simulate_current(pack, ecm.Session(), current_at, t_end, dt, prescribed_temperature=temp_at)
    st = np.array([s.t for s in out["samples"]])
    sv = np.array([s.voltage_v for s in out["samples"]])
    v_ref = np.interp(t, st, sv)
    fast = simulate_tables(tables, t, cur, temp_k, 1.0, q_ref_ah)
    connected = t < (out["exhausted_at"] if out["exhausted_at"] is not None else np.inf) - dt
    return {"reference_vs_measured": error_stats((v_ref - v_meas)[connected], fast["z"][connected]),
            "reference_vs_fit_simulator_max_abs_v": float(np.max(np.abs(v_ref - fast["v"])[connected])),
            "exhausted_at_s": out["exhausted_at"], "compared_samples": int(connected.sum())}


# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------

def rounded(x):
    if isinstance(x, float):
        return float(f"{x:.12g}") if math.isfinite(x) else None
    if isinstance(x, (np.floating,)):
        return rounded(float(x))
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, np.ndarray):
        return [rounded(v) for v in x.tolist()]
    if isinstance(x, dict):
        return {str(k): rounded(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [rounded(v) for v in x]
    return x


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("galeotti_dir", type=Path)
    ap.add_argument("hg2_dir", type=Path)
    ap.add_argument("--out", type=Path, default=HERE / "fit_results.json")
    args = ap.parse_args()
    reg = InputRegister(args.galeotti_dir.resolve(), args.hg2_dir.resolve())

    lipo = lipo_section(reg)
    aging = lipo_aging(reg, lipo)
    hg2 = hg2_section(reg)
    thermal = hg2_thermal(hg2)
    lipo_tables = lipo_template_tables(lipo, hg2)
    hg2_tables = hg2["chosen"]["tables"]
    q_hg2 = hg2["tests"]["549"]["c20"]["q_ah"]

    # Cross-check: chosen templates replayed through the independent reference law (held-out runs).
    a = lipo["runs"]
    replay = {}
    for key in ("std", "s1"):
        seg = a[key].segments[0]
        replay[f"lipo/{a[key].name}"] = reference_replay(
            lipo_tables, "lipo-fit", "lipo", lipo["q_ref_ah"], seg.t, seg.current, np.full(seg.t.size, 298.15),
            seg.v)
    for tid, _ in HG2_TESTS:
        for kind in ("Dis_0p5C", "Dis_2C"):
            run = hg2["tests"][tid]["dis"][kind]
            replay[f"hg2/{tid}_{kind}"] = reference_replay(hg2_tables, "hg2-fit", "liion", q_hg2, run["t"], run["i"],
                                                           run["temp_k"], run["v"], dt=1.0)

    chosen_l = lipo["chosen"]
    results = {
        "format": "openrc-bat05-fit-results v1",
        "generator": "research/battery/bat-05/fit_cells.py",
        "software": {"python": sys.version.split()[0], "numpy": np.__version__,
                     "scipy": __import__("scipy").__version__},
        "settings": {"soc_knots": list(SOC_KNOTS), "lipo_r_knots": list(LIPO_R_KNOTS),
                     "temperature_knots_k": list(TEMPERATURE_KNOTS_K), "rest_s": REST_S,
                     "tau_floor_s": TAU_FLOOR_S, "tau_ceiling_s": TAU_CEILING_S,
                     "ocv_smoothing_weight": OCV_SMOOTHING_V, "hg2_grid_s": HG2_GRID_S,
                     "score_min_soc": SCORE_MIN_SOC, "sim_max_step_s": SIM_MAX_STEP_S,
                     "selection_rule": "score = mean over held-out runs of the loaded-voltage RMSE at SOC >= "
                                       "score_min_soc; choose the least complex candidate with score <= best score "
                                       "+ repeatability margin (RMS difference of two repeated discharges of the "
                                       "same cell in the same band); complexity order K0 < K1 < K2, then constant R "
                                       "< SOC-dependent RC resistances < SOC-dependent R0 and RC resistances"},
        "inputs": {"lipo": reg.entries("galeotti"), "liion": reg.entries("hg2")},
        "lipo": {
            "cell": TEMPLATE_CELL, "reference_capacity_ah": lipo["q_ref_ah"],
            "reference_capacity_source": f"{TEMPLATE_CELL}/0_0_1_stddischarge.csv, 1 A to 2.75 V",
            "fit_runs": lipo["fit_runs"], "held_out_runs": lipo["held_out_runs"],
            "repeatability_margin_v": lipo["margin_v"],
            "candidates": [{"label": c["model"].label, "branches": c["model"].k,
                            "r0_soc_dependent": c["model"].r0_soc, "rc_soc_dependent": c["model"].rc_soc,
                            "tau_at_bound": c["fitted"]["tau_at_bound"],
                            "parameters": c["parameters"], "fit": c["fit"], "held_out_score_v": c["score_v"],
                            "held_out_same_cell_score_v": c["same_cell_score_v"], "held_out": c["held_out"],
                            "summary": summarize_lipo(c["model"], c["fitted"], lipo["q_ref_ah"]),
                            "optimizer": {"cost": c["fitted"]["cost"], "nfev": c["fitted"]["nfev"],
                                          "status": c["fitted"]["status"]}}
                           for c in lipo["candidates"]],
            "chosen": chosen_l["model"].label,
            "cell_spread": lipo["spread"], "rest_sensitivity": lipo["rest_sensitivity"],
            "two_rate_resistance": lipo["two_rate"], "model_v_at_soc0_under_1a": lipo["v_model_at_floor_1a"],
            "aging": aging,
            "tables": lipo_tables,
        },
        "liion": {
            "reference_capacity_ah": q_hg2,
            "reference_capacity_source": "549_C20DisCh.csv step 22, C/20 to 2.8 V at 25 °C",
            "repeatability_margin_v": hg2["margin_v"],
            "tests": {tid: {"knot_k": info["t_knot"], "c20_capacity_ah": info["c20"]["q_ah"],
                            "c20_current_a": info["c20"]["i"], "c20_temp_k": info["c20"]["temp_k"],
                            "levels": [{"z": w["z_level"], "temp_k": w["temp_k"], "r0_ohm": w["r0_ohm"],
                                        "r0_steps_ohm": w["r0_steps_ohm"], "pulse_currents_a": w["pulse_currents_a"]}
                                       for w in info["windows"]]}
                      for tid, info in hg2["tests"].items()},
            "candidates": [{"branches": c["k"], "held_out_score_v": c["score_v"],
                            "fit_window_rmse_mean_v": c["fit_window_rmse_mean_v"], "held_out": c["held_out"],
                            "arrhenius": c["arrhenius"],
                            "per_test": {tid: {"tau_s": v["tau_s"],
                                               "levels_free_tau": [{"rmse_v": f["rmse_v"], "branches": f["branches"],
                                                                    "offset_v": f["offset_v"], "r0_ohm": f["r0_ohm"]}
                                                                   for f in v["free"]],
                                               "levels_final": [{"rmse_v": f["rmse_v"], "branches": f["branches"],
                                                                 "offset_v": f["offset_v"], "r0_ohm": f["r0_ohm"]}
                                                                for f in v["final"]],
                                               "measured_temp_k": c["tables_measured"][tid]["temp_k"],
                                               "ocv_correction_max_v": c["tables_measured"][tid]["ocv_correction_max_v"],
                                               "isotonic_max_adjust_v": c["tables_measured"][tid]["isotonic_max_adjust_v"]}
                                         for tid, v in c["per_t"].items()}}
                           for c in hg2["candidates"]],
            "chosen_branches": hg2["chosen"]["k"],
            "sensitivity_time_weighted_score_v": hg2["sensitivity"],
            "arrhenius": hg2["chosen"]["arrhenius"],
            "thermal": thermal,
            "tables": hg2_tables,
        },
        "reference_replay": replay,
    }
    text = json.dumps(rounded(results), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    args.out.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {args.out} ({len(text)} bytes)")
    print(f"LiPo chosen {chosen_l['model'].label}; HG2 chosen K={hg2['chosen']['k']}; "
          f"thermal cp={thermal['cp_j_per_kg_k']:.0f} J/(kg·K) identifiable={thermal['identifiable']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
