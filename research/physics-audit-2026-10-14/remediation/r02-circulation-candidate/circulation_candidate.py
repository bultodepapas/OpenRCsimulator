#!/usr/bin/env python3
"""Research-only attached-flow circulation / Kutta–Joukowski candidate.

This file intentionally does not import or alter the production runtime.  The
candidate is restricted to a planar, unswept wing represented by straight
horseshoe panels, with positive axial flow and attached linear sections.
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
from typing import Callable, Sequence


ROOT = Path(__file__).resolve().parents[4]
INPUT_PATH = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/yaw_r02_input_export-v1.json"
D11F_PATH = ROOT / "research/aero/d11f/wing_yaw_damping.py"
OUT_PATH = Path(__file__).with_name("candidate-results-v1.json")

V_MPS = 15.0
RHO_KG_M3 = 1.225
RATE_STEP_RAD_S = 0.05
ALPHA_DEG = (0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0)
FAR_M = 1.0e5

GAUSS_LEGENDRE: dict[int, tuple[tuple[float, ...], tuple[float, ...]]] = {
    1: ((0.0,), (2.0,)),
    2: ((-0.5773502691896257, 0.5773502691896257), (1.0, 1.0)),
    4: (
        (-0.8611363115940526, -0.3399810435848563,
         0.3399810435848563, 0.8611363115940526),
        (0.3478548451374538, 0.6521451548625461,
         0.6521451548625461, 0.3478548451374538),
    ),
    8: (
        (-0.9602898564975363, -0.7966664774136267,
         -0.5255324099163290, -0.1834346424956498,
         0.1834346424956498, 0.5255324099163290,
         0.7966664774136267, 0.9602898564975363),
        (0.1012285362903763, 0.2223810344533745,
         0.3137066458778873, 0.3626837833783620,
         0.3626837833783620, 0.3137066458778873,
         0.2223810344533745, 0.1012285362903763),
    ),
}


class DomainError(ValueError):
    """The input lies outside the candidate's stated mathematical domain."""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def solve_linear(a: Sequence[Sequence[float]], b: Sequence[float]) -> list[float]:
    n = len(b)
    if len(a) != n or any(len(row) != n for row in a):
        raise ValueError("linear system must be square")
    m = [list(row) + [float(b[i])] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(m[row][col]))
        if abs(m[pivot][col]) <= 1.0e-14:
            raise ValueError(f"singular matrix at column {col}")
        m[col], m[pivot] = m[pivot], m[col]
        for row in range(col + 1, n):
            factor = m[row][col] / m[col][col]
            for k in range(col, n + 1):
                m[row][k] -= factor * m[col][k]
    out = [0.0] * n
    for row in range(n - 1, -1, -1):
        out[row] = (m[row][n] - sum(m[row][k] * out[k] for k in range(row + 1, n))) / m[row][row]
    return out


def inverse(a: Sequence[Sequence[float]]) -> list[list[float]]:
    n = len(a)
    columns = [solve_linear(a, [1.0 if i == j else 0.0 for i in range(n)]) for j in range(n)]
    return [[columns[j][i] for j in range(n)] for i in range(n)]


def matvec(a: Sequence[Sequence[float]], x: Sequence[float]) -> list[float]:
    return [sum(row[j] * x[j] for j in range(len(x))) for row in a]


def vector_max_abs(x: Sequence[float]) -> float:
    return max((abs(v) for v in x), default=0.0)


def matrix_max_abs_gap(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    return max(abs(a[i][j] - b[i][j]) for i in range(len(a)) for j in range(len(a)))


def vortex_segment_z(px: float, py: float, x1: float, y1: float,
                     x2: float, y2: float) -> float:
    """Vertical velocity per unit circulation of one finite vortex segment."""
    r1x, r1y = px - x1, py - y1
    r2x, r2y = px - x2, py - y2
    cross = r1x * r2y - r1y * r2x
    if abs(cross) < 1.0e-14:
        return 0.0
    n1 = math.hypot(r1x, r1y)
    n2 = math.hypot(r2x, r2y)
    dot = (x2 - x1) * (r1x / n1 - r2x / n2) + (y2 - y1) * (r1y / n1 - r2y / n2)
    return dot / (4.0 * math.pi * cross)


def horseshoe_velocity_z(px: float, py: float, edge_a: float, edge_b: float,
                         far: float = FAR_M) -> float:
    """Full bound segment plus two trailing legs at a 3/4-chord collocation point."""
    return (
        vortex_segment_z(px, py, far, edge_a, 0.0, edge_a)
        + vortex_segment_z(px, py, 0.0, edge_a, 0.0, edge_b)
        + vortex_segment_z(px, py, 0.0, edge_b, far, edge_b)
    )


def trailing_velocity_z(px: float, py: float, edge_a: float, edge_b: float,
                        far: float = FAR_M) -> float:
    """Trailing legs only, used at the bound line for the KJ force closure."""
    return (
        vortex_segment_z(px, py, far, edge_a, 0.0, edge_a)
        + vortex_segment_z(px, py, 0.0, edge_b, far, edge_b)
    )


def make_mesh(span_m: float, chords_m: Sequence[float]) -> dict[str, list[float]]:
    n = len(chords_m)
    if n == 0 or any(not math.isfinite(c) or c <= 0.0 for c in chords_m):
        raise ValueError("each panel needs a finite positive chord")
    edges = [-0.5 * span_m + span_m * i / n for i in range(n + 1)]
    ys = [0.5 * (edges[i] + edges[i + 1]) for i in range(n)]
    return {"edges_m": edges, "y_centres_m": ys, "chords_m": list(chords_m)}


def induced_angle_kernel(mesh: dict[str, list[float]]) -> list[list[float]]:
    """K_ij: induced angle at control i per CL_j, excluding only the local 2-D term.

    The source chord c_j appears here.  The diagonal correction is the same
    1/(2π) self term removed by AircraftData.strip_influence and D11f.
    """
    edges, ys, chords = mesh["edges_m"], mesh["y_centres_m"], mesh["chords_m"]
    n = len(ys)
    out = [[0.0] * n for _ in range(n)]
    for i in range(n):
        x_control = 0.5 * chords[i]
        for j in range(n):
            w_z = horseshoe_velocity_z(x_control, ys[i], edges[j], edges[j + 1])
            out[i][j] = -0.5 * chords[j] * w_z - (1.0 / (2.0 * math.pi) if i == j else 0.0)
    return out


def effective_map(k_map: Sequence[Sequence[float]], a0_per_rad: float) -> list[list[float]]:
    n = len(k_map)
    operator = [[(1.0 if i == j else 0.0) + a0_per_rad * k_map[i][j]
                 for j in range(n)] for i in range(n)]
    return inverse(operator)


def equivalent_zero_incidence(k_map: Sequence[Sequence[float]], a0_per_rad: float,
                              strip_cl0: Sequence[float]) -> list[float]:
    """Recover α0 satisfying c0 = a0 E α0; α0 is equivalent, not measured camber."""
    n = len(k_map)
    static_operator = [[(1.0 if i == j else 0.0) / a0_per_rad + k_map[i][j]
                        for j in range(n)] for i in range(n)]
    return matvec(static_operator, strip_cl0)


def candidate_circulation(k_map: Sequence[Sequence[float]], e_map: Sequence[Sequence[float]],
                          chords_m: Sequence[float], a0_per_rad: float,
                          u_mps: Sequence[float], w_mps: Sequence[float],
                          alpha_zero_rad: Sequence[float], incidence_rad: Sequence[float] | None = None
                          ) -> dict[str, list[float]]:
    """Attached positive-u dimensional source solve: g=a0 E (w + u(α0+incidence))."""
    n = len(u_mps)
    if (len(w_mps) != n or len(alpha_zero_rad) != n or len(chords_m) != n
            or len(k_map) != n or len(e_map) != n):
        raise ValueError("all panel vectors and maps must have the same order")
    incidence = list(incidence_rad) if incidence_rad is not None else [0.0] * n
    if len(incidence) != n:
        raise ValueError("incidence vector has the wrong order")
    if not all(math.isfinite(x) for x in (*u_mps, *w_mps, *alpha_zero_rad, *incidence)):
        raise DomainError("candidate requires finite panel inputs")
    if any(u <= 0.0 for u in u_mps):
        raise DomainError("candidate refuses stagnant or reverse axial flow: every u_i must be > 0")
    source = [w_mps[i] + u_mps[i] * (alpha_zero_rad[i] + incidence[i]) for i in range(n)]
    g = [a0_per_rad * x for x in matvec(e_map, source)]
    cl = [g[i] / u_mps[i] for i in range(n)]
    gamma_m2_s = [0.5 * chords_m[i] * g[i] for i in range(n)]
    return {"g_mps": g, "cl": cl, "gamma_m2_s": gamma_m2_s}


def direct_rate_dependent_cl(k_map: Sequence[Sequence[float]], a0_per_rad: float,
                             u_mps: Sequence[float], w_mps: Sequence[float],
                             alpha_zero_rad: Sequence[float], incidence_rad: Sequence[float] | None = None
                             ) -> list[float]:
    """Independent D11f form, with its rate-dependent u_j/u_i operator."""
    n = len(u_mps)
    if any(u <= 0.0 for u in u_mps):
        raise DomainError("D11f comparison requires every u_i > 0")
    incidence = list(incidence_rad) if incidence_rad is not None else [0.0] * n
    operator = [[(1.0 if i == j else 0.0) / a0_per_rad
                 + k_map[i][j] * u_mps[j] / u_mps[i] for j in range(n)] for i in range(n)]
    rhs = [w_mps[i] / u_mps[i] + alpha_zero_rad[i] + incidence[i] for i in range(n)]
    return solve_linear(operator, rhs)


def wake_downwash_at_bound(mesh: dict[str, list[float]], gamma_m2_s: Sequence[float],
                           y_m: float) -> float:
    """D11f downwash sign at the bound line; omit the singular bound segment."""
    edges = mesh["edges_m"]
    z_velocity = sum(trailing_velocity_z(0.0, y_m, edges[j], edges[j + 1]) * gamma_m2_s[j]
                     for j in range(len(gamma_m2_s)))
    return -z_velocity


def integrate_bound_forces(mesh: dict[str, list[float]], gamma_m2_s: Sequence[float],
                           flow_at_y: Callable[[float], tuple[float, float]], rho_kg_m3: float,
                           quadrature_order: int = 1, cd0_comparator: float | None = None) -> dict[str, float]:
    """Integrate piecewise-constant bound Γ with sampled local KJ force and optional D11f profile term.

    Coordinates and force signs follow D11f: x is aft, y right, z up.  A
    reported yaw moment is Σ y F_x, matching the production comparison after
    the R11 body-axis sign conversion.  `cd0_comparator` is only the frozen
    D11f profile-force assumption, not an asserted wing-section coefficient.
    """
    if quadrature_order not in GAUSS_LEGENDRE:
        raise ValueError("quadrature_order must be one of 1, 2, 4, 8")
    if len(gamma_m2_s) != len(mesh["chords_m"]):
        raise ValueError("one Γ is required per panel")
    nodes, weights = GAUSS_LEGENDRE[quadrature_order]
    edges, chords = mesh["edges_m"], mesh["chords_m"]
    sums = {"fx_kj_n": 0.0, "fz_kj_n": 0.0, "yaw_kj_nm": 0.0,
            "fx_profile_n": 0.0, "yaw_profile_nm": 0.0,
            "power_kj_body_w": 0.0, "power_profile_body_w": 0.0}
    for i, gamma in enumerate(gamma_m2_s):
        width = edges[i + 1] - edges[i]
        for node, gauss_weight in zip(nodes, weights):
            y = 0.5 * (edges[i] + edges[i + 1]) + 0.5 * width * node
            dy_weight = 0.5 * width * gauss_weight
            u, w = flow_at_y(y)
            if not math.isfinite(u) or not math.isfinite(w):
                raise DomainError("force quadrature received a non-finite velocity")
            w_down = wake_downwash_at_bound(mesh, gamma_m2_s, y)
            fx_kj = -rho_kg_m3 * gamma * (w - w_down) * dy_weight
            fz_kj = rho_kg_m3 * gamma * u * dy_weight
            sums["fx_kj_n"] += fx_kj
            sums["fz_kj_n"] += fz_kj
            sums["yaw_kj_nm"] += y * fx_kj
            # The airframe velocity is opposite this D11f air-on-wing flow vector.
            sums["power_kj_body_w"] -= fx_kj * u + fz_kj * w
            if cd0_comparator is not None:
                fx_profile = (0.5 * rho_kg_m3 * (u * u + w * w) * chords[i]
                              * cd0_comparator * dy_weight)
                sums["fx_profile_n"] += fx_profile
                sums["yaw_profile_nm"] += y * fx_profile
                sums["power_profile_body_w"] -= fx_profile * u
    sums["yaw_total_nm"] = sums["yaw_kj_nm"] + sums["yaw_profile_nm"]
    sums["power_total_body_w"] = sums["power_kj_body_w"] + sums["power_profile_body_w"]
    return sums


def yaw_flow(alpha_rad: float, rate_rad_s: float, speed_mps: float) -> Callable[[float], tuple[float, float]]:
    return lambda y: (speed_mps * math.cos(alpha_rad) - rate_rad_s * y,
                      speed_mps * math.sin(alpha_rad))


def section_flows(mesh: dict[str, list[float]], alpha_rad: float,
                  rate_rad_s: float, speed_mps: float) -> tuple[list[float], list[float]]:
    flow = yaw_flow(alpha_rad, rate_rad_s, speed_mps)
    ys = mesh["y_centres_m"]
    u = [flow(y)[0] for y in ys]
    w = [flow(y)[1] for y in ys]
    return u, w


def require_geometric_attached(u_mps: Sequence[float], w_mps: Sequence[float],
                               attached_limit_rad: float) -> None:
    if any(u <= 0.0 for u in u_mps):
        raise DomainError("attached candidate requires strictly positive chordwise speed")
    max_angle = max(abs(math.atan2(w, u)) for u, w in zip(u_mps, w_mps))
    if max_angle >= attached_limit_rad:
        raise DomainError("candidate refuses a geometric section angle at/above the supplied attached limit")


def load_d11f():
    spec = importlib.util.spec_from_file_location("preserved_d11f_reference", D11F_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot import preserved D11f source")
    module = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module


def fixed_e_r02_cl(data: dict, e_map: Sequence[Sequence[float]], a0: float,
                   alpha_rad: float, rate_rad_s: float, speed_mps: float) -> tuple[list[float], dict]:
    mesh = make_mesh(float(data["geometry"]["span_m"]),
                     [float(data["geometry"]["mean_chord_m"])] * len(data["geometry"]["station_y_m"]))
    ys = mesh["y_centres_m"]
    u, w = section_flows(mesh, alpha_rad, rate_rad_s, speed_mps)
    vp = [math.hypot(u[i], w[i]) for i in range(len(ys))]
    angles = [math.atan2(w[i], u[i]) for i in range(len(ys))]
    max_speed = max(vp)
    weights = [vp[i] / max_speed for i in range(len(ys))]
    intercept = list(map(float, data["geometry"]["strip_cl0"]))
    out = []
    for i in range(len(ys)):
        out.append(intercept[i] + a0 * sum(e_map[i][j] * angles[j]
                    * (1.0 if i == j else weights[j]) for j in range(len(ys))))
    return out, {"u": u, "w": w, "vp": vp, "angles": angles, "source_weight": weights,
                 "y": ys, "mesh": mesh}


def r02_yaw_moment(data: dict, e_map: Sequence[Sequence[float]], a0: float,
                   alpha_rad: float, rate_rad_s: float, rho: float, speed: float) -> dict[str, float]:
    cl, flow = fixed_e_r02_cl(data, e_map, a0, alpha_rad, rate_rad_s, speed)
    aero = data["aero"]
    area = float(data["geometry"]["area_m2"]) / len(cl)
    parts = {"profile": 0.0, "induced": 0.0, "lift_projection": 0.0}
    for i, y in enumerate(flow["y"]):
        fx_profile = -0.5 * rho * area * float(aero["CD0"]) * flow["vp"][i] * flow["u"][i]
        fx_induced = (-0.5 * rho * area * float(aero["k_induced_whole_aircraft"])
                      * (cl[i] - float(aero["CL_minD"])) ** 2 * flow["vp"][i] * flow["u"][i])
        fx_lift = 0.5 * rho * area * flow["vp"][i] * cl[i] * flow["w"][i]
        parts["profile"] += -y * fx_profile
        parts["induced"] += -y * fx_induced
        parts["lift_projection"] += -y * fx_lift
    parts["total"] = sum(parts.values())
    return parts


def cnr_from_moment(moment: Callable[[float], float], rho: float,
                    speed: float, span: float, area: float, h: float = RATE_STEP_RAD_S) -> float:
    denominator = 0.5 * rho * speed * speed * area * span * span / (2.0 * speed)
    return (moment(h) - moment(-h)) / (2.0 * h) / denominator


def circulation_yaw_cnr(mesh: dict[str, list[float]], k_map: Sequence[Sequence[float]],
                        e_map: Sequence[Sequence[float]], a0: float,
                        alpha_zero: Sequence[float], alpha_rad: float, rho: float,
                        speed: float, quadrature_order: int, cd0: float | None) -> float:
    def moment(rate: float) -> float:
        u, w = section_flows(mesh, alpha_rad, rate, speed)
        solved = candidate_circulation(k_map, e_map, mesh["chords_m"], a0, u, w, alpha_zero)
        return integrate_bound_forces(mesh, solved["gamma_m2_s"], yaw_flow(alpha_rad, rate, speed),
                                      rho, quadrature_order, cd0)["yaw_total_nm"]
    return cnr_from_moment(moment, rho, speed, mesh["edges_m"][-1] - mesh["edges_m"][0],
                           sum((mesh["edges_m"][i + 1] - mesh["edges_m"][i]) * mesh["chords_m"][i]
                               for i in range(len(mesh["chords_m"]))))


def test_direct_identity(mesh: dict[str, list[float]], k_map: Sequence[Sequence[float]],
                         e_map: Sequence[Sequence[float]], a0: float,
                         alpha_zero: Sequence[float]) -> float:
    maximum = 0.0
    for alpha_deg in ALPHA_DEG:
        for rate in (-1.0, -0.05, 0.0, 0.05, 1.0):
            u, w = section_flows(mesh, math.radians(alpha_deg), rate, V_MPS)
            require_geometric_attached(u, w, math.radians(12.13))
            candidate = candidate_circulation(k_map, e_map, mesh["chords_m"], a0, u, w, alpha_zero)["cl"]
            direct = direct_rate_dependent_cl(k_map, a0, u, w, alpha_zero)
            maximum = max(maximum, vector_max_abs([candidate[i] - direct[i] for i in range(len(u))]))
    return maximum


def panel_refinement(data: dict, alpha_zero_constant: float) -> list[dict[str, float | int]]:
    rows = []
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["mean_chord_m"])
    a0 = float(data["geometry"]["strip_slope_per_rad"])
    for n_side in (3, 6, 12, 24, 48):
        mesh = make_mesh(span, [chord] * (2 * n_side))
        k_map = induced_angle_kernel(mesh)
        e_map = effective_map(k_map, a0)
        alpha_zero = [alpha_zero_constant] * len(mesh["chords_m"])
        alpha = math.radians(4.0)
        rows.append({
            "panels_per_semispan": n_side,
            "total_panels": len(mesh["chords_m"]),
            "k_j_only_Cnr_alpha4": circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero,
                                                          alpha, RHO_KG_M3, V_MPS, 8, None),
            "with_D11f_profile_assumption_Cnr_alpha4": circulation_yaw_cnr(
                mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, 8,
                float(data["aero"]["CD0"])),
        })
    return rows


def quadrature_refinement(data: dict, alpha_zero_constant: float) -> list[dict[str, float | int]]:
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["mean_chord_m"])
    a0 = float(data["geometry"]["strip_slope_per_rad"])
    mesh = make_mesh(span, [chord] * 48)
    k_map = induced_angle_kernel(mesh)
    e_map = effective_map(k_map, a0)
    alpha_zero = [alpha_zero_constant] * len(mesh["chords_m"])
    alpha = math.radians(4.0)
    return [{
        "gauss_order_per_panel": order,
        "k_j_only_Cnr_alpha4": circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero,
                                                      alpha, RHO_KG_M3, V_MPS, order, None),
        "with_D11f_profile_assumption_Cnr_alpha4": circulation_yaw_cnr(
            mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, order,
            float(data["aero"]["CD0"])),
    } for order in (1, 2, 4, 8)]


def velocity_density_similarity(data: dict, alpha_zero_constant: float) -> dict:
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["mean_chord_m"])
    a0 = float(data["geometry"]["strip_slope_per_rad"])
    mesh = make_mesh(span, [chord] * 48)
    k_map = induced_angle_kernel(mesh)
    e_map = effective_map(k_map, a0)
    alpha_zero = [alpha_zero_constant] * len(mesh["chords_m"])
    alpha = math.radians(4.0)
    rate = 0.05
    base = integrate_bound_forces(
        mesh,
        candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                              *section_flows(mesh, alpha, rate, V_MPS), alpha_zero)["gamma_m2_s"],
        yaw_flow(alpha, rate, V_MPS), RHO_KG_M3, 8, float(data["aero"]["CD0"]))
    scaled_speed = 2.0 * V_MPS
    scaled = integrate_bound_forces(
        mesh,
        candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                              *section_flows(mesh, alpha, 2.0 * rate, scaled_speed), alpha_zero)["gamma_m2_s"],
        yaw_flow(alpha, 2.0 * rate, scaled_speed), 1.7, 8, float(data["aero"]["CD0"]))
    expected_ratio = (1.7 / RHO_KG_M3) * 4.0
    tested = ("fx_kj_n", "fz_kj_n", "yaw_kj_nm", "fx_profile_n", "yaw_profile_nm")
    ratios = {name: scaled[name] / base[name] for name in tested if base[name] != 0.0}
    return {"base_rho_kg_m3": RHO_KG_M3, "scaled_rho_kg_m3": 1.7,
            "velocity_and_yaw_rate_scale": 2.0, "expected_force_and_moment_ratio": expected_ratio,
            "observed_ratios": ratios,
            "maximum_absolute_ratio_error": max(abs(ratio - expected_ratio) for ratio in ratios.values())}


def run() -> dict:
    data = json.loads(INPUT_PATH.read_text(encoding="utf-8"))
    geom, aero = data["geometry"], data["aero"]
    span = float(geom["span_m"])
    area = float(geom["area_m2"])
    chord = float(geom["mean_chord_m"])
    a0 = float(geom["strip_slope_per_rad"])
    ys_export = list(map(float, geom["station_y_m"]))
    cl0 = list(map(float, geom["strip_cl0"]))
    mesh = make_mesh(span, [chord] * len(ys_export))
    if max(abs(mesh["y_centres_m"][i] - ys_export[i]) for i in range(len(ys_export))) > 1.0e-12:
        raise AssertionError("exported station centers do not match uniform-span candidate mesh")
    k_map = induced_angle_kernel(mesh)
    e_map = effective_map(k_map, a0)
    e_export = list(map(float, geom["induced_map_E"]))
    n = len(cl0)
    e_gap = max(abs(e_map[i][j] - e_export[i * n + j]) for i in range(n) for j in range(n))
    alpha_zero = equivalent_zero_incidence(k_map, a0, cl0)
    alpha_zero_mean = sum(alpha_zero) / n
    alpha_zero_spread = max(alpha_zero) - min(alpha_zero)
    direct_identity_error = test_direct_identity(mesh, k_map, e_map, a0, alpha_zero)

    # The variable-chord fixture verifies c_j in K and c_i in Γ; it makes no aircraft-data claim.
    tapered_chords = [0.40 - 0.20 * abs(y) / (0.5 * span) for y in mesh["y_centres_m"]]
    tapered = make_mesh(span, tapered_chords)
    tapered_k = induced_angle_kernel(tapered)
    tapered_e = effective_map(tapered_k, a0)
    tapered_alpha0 = [0.02] * len(tapered_chords)
    tapered_u, tapered_w = section_flows(tapered, math.radians(4.0), 0.05, V_MPS)
    tapered_cl = candidate_circulation(tapered_k, tapered_e, tapered["chords_m"], a0,
                                       tapered_u, tapered_w, tapered_alpha0)["cl"]
    tapered_direct = direct_rate_dependent_cl(tapered_k, a0,
                                              tapered_u, tapered_w, tapered_alpha0)
    tapered_identity_error = vector_max_abs([tapered_cl[i] - tapered_direct[i] for i in range(n)])
    tapered_gamma_units_check = all(abs(tapered_e[i][j]) < math.inf for i in range(n) for j in range(n))

    d11f = load_d11f()
    # Exact independent reference check for D11f's authored six-panel, zero-camber case.
    d11f_mesh = make_mesh(float(d11f.b), [float(d11f.c)] * int(d11f.n))
    d11f_k = induced_angle_kernel(d11f_mesh)
    d11f_a0 = float(d11f.a0)
    d11f_e = effective_map(d11f_k, d11f_a0)
    zero_alpha0 = [0.0] * int(d11f.n)
    d11f_force_rows = []
    for alpha_deg in (2.0, 4.0, 8.0, 10.0):
        alpha = math.radians(alpha_deg)
        for rate in (-RATE_STEP_RAD_S, RATE_STEP_RAD_S):
            u, w = section_flows(d11f_mesh, alpha, rate, V_MPS)
            solved = candidate_circulation(d11f_k, d11f_e, d11f_mesh["chords_m"],
                                           d11f_a0, u, w, zero_alpha0)
            ref_total = RHO_KG_M3 * d11f.loads(alpha, rate)[1]
            q1 = integrate_bound_forces(d11f_mesh, solved["gamma_m2_s"],
                                        yaw_flow(alpha, rate, V_MPS), RHO_KG_M3, 1, float(d11f.CD0))
            d11f_force_rows.append({"alpha_deg": alpha_deg, "rate_rad_s": rate,
                                    "candidate_total_yaw_nm": q1["yaw_total_nm"],
                                    "d11f_total_yaw_nm": ref_total,
                                    "absolute_error_nm": abs(q1["yaw_total_nm"] - ref_total)})
    d11f_match_error = max(row["absolute_error_nm"] for row in d11f_force_rows)

    # Same production geometry and equivalent intercept, but candidate KJ force plus the D11f-only CD0 comparison term.
    cnr_rows = []
    for alpha_deg in ALPHA_DEG:
        alpha = math.radians(alpha_deg)
        require_geometric_attached(*section_flows(mesh, alpha, RATE_STEP_RAD_S, V_MPS),
                                   float(aero["a1_attached_rad"]))
        candidate_cnr_kj = circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero, alpha,
                                                RHO_KG_M3, V_MPS, 1, None)
        candidate_cnr_with_comparator_profile = circulation_yaw_cnr(
            mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, 1,
            float(aero["CD0"]))
        r02 = cnr_from_moment(
            lambda rate: r02_yaw_moment(data, e_map, a0, alpha, rate, RHO_KG_M3, V_MPS)["total"],
            RHO_KG_M3, V_MPS, span, area)
        cnr_rows.append({"alpha_deg": alpha_deg, "R02_fixed_E_polar_Cnr": r02,
                         "candidate_KJ_only_Cnr": candidate_cnr_kj,
                         "candidate_KJ_plus_D11f_profile_assumption_Cnr": candidate_cnr_with_comparator_profile})

    # Uniform-flow sign check: symmetric circulation, nonzero wake downwash, positive induced drag,
    # and nonpositive power delivered by the aerodynamic force to the airframe.
    uniform_mesh = make_mesh(span, [chord] * 48)
    uniform_k = induced_angle_kernel(uniform_mesh)
    uniform_e = effective_map(uniform_k, a0)
    alpha_uniform = math.radians(4.0)
    u_uniform, w_uniform = section_flows(uniform_mesh, alpha_uniform, 0.0, V_MPS)
    uniform_gamma = candidate_circulation(uniform_k, uniform_e, uniform_mesh["chords_m"],
                                          a0, u_uniform, w_uniform,
                                          [alpha_zero_mean] * len(u_uniform))["gamma_m2_s"]
    uniform_loads = integrate_bound_forces(uniform_mesh, uniform_gamma,
                                           yaw_flow(alpha_uniform, 0.0, V_MPS),
                                           RHO_KG_M3, 8, float(aero["CD0"]))
    uniform_induced_drag = 0.0
    uniform_downwash_min = math.inf
    for i, gamma in enumerate(uniform_gamma):
        y = uniform_mesh["y_centres_m"][i]
        width = uniform_mesh["edges_m"][i + 1] - uniform_mesh["edges_m"][i]
        w_down = wake_downwash_at_bound(uniform_mesh, uniform_gamma, y)
        uniform_downwash_min = min(uniform_downwash_min, w_down)
        uniform_induced_drag += RHO_KG_M3 * gamma * w_down * width

    # Similarity scaling includes both speed and yaw rate, keeping angles and nondimensional rate fixed.
    similarity = velocity_density_similarity(data, alpha_zero_mean)

    # Singular and separated-flow counterexamples are recorded, not regularized into a new law.
    alpha_zero_flow = 0.0
    critical_rate = V_MPS / max(abs(y) for y in mesh["y_centres_m"])
    u_zero_flow = [V_MPS - critical_rate * (1.0 - 1.0e-6) * y for y in mesh["y_centres_m"]]
    w_zero_flow = [0.0] * len(u_zero_flow)
    near_zero = candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                                      u_zero_flow, w_zero_flow, alpha_zero)
    exact_zero_rejection = ""
    try:
        candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                              [0.0] + u_zero_flow[1:], w_zero_flow, alpha_zero)
    except DomainError as exc:
        exact_zero_rejection = str(exc)
    reverse_rejection = ""
    try:
        candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                              [-1.0] + u_zero_flow[1:], w_zero_flow, alpha_zero)
    except DomainError as exc:
        reverse_rejection = str(exc)
    stalled_rejection = ""
    try:
        u_stall, w_stall = section_flows(mesh, math.radians(15.0), 0.0, V_MPS)
        require_geometric_attached(u_stall, w_stall, float(aero["a1_attached_rad"]))
    except DomainError as exc:
        stalled_rejection = str(exc)

    # Synthetic tapered panel sweep and convergence are implementation checks only.
    refinement = panel_refinement(data, alpha_zero_mean)
    quad_refinement = quadrature_refinement(data, alpha_zero_mean)

    return {
        "schema": "r02-attached-circulation-candidate-v1",
        "interpretation": "Research candidate and software/model-form comparison only; not a promoted runtime law or physical validation.",
        "identity": {
            "candidate_source_sha256": sha256(Path(__file__).resolve()),
            "production_input_export_sha256": sha256(INPUT_PATH),
            "production_aircraft_sha256": data["aircraft_input"]["sha256"],
            "production_aero_source_sha256": data["aero_source_sha256"],
            "D11f_source_sha256": sha256(D11F_PATH),
        },
        "model": {
            "span_m": span, "area_m2": area, "chord_m": chord,
            "panel_count": n, "strip_slope_per_rad": a0,
            "equivalent_alpha_zero_rad": alpha_zero,
            "equivalent_alpha_zero_mean_rad": alpha_zero_mean,
            "equivalent_alpha_zero_spread_rad": alpha_zero_spread,
            "alpha_zero_semantics": "M_static * production strip_cl0; equivalent intercept reconstructed from the existing fitted R02 strips, not measured airfoil camber/incidence",
            "CD0_semantics": "production value is a whole-aircraft polar; used only as the inherited D11f comparison profile term, not asserted as measured wing-section CD0",
            "geometry_operator": "K_ij=-0.5*c_j*horseshoe_z_ij-δ_ij/(2π), E=(I+a0*K)^-1; collocation uses the full horseshoe at each 3/4-chord point",
            "dimensional_source": "g_i=u_i*CL_i; g=a0*E*(w+u*(alpha_zero+incidence)); Gamma_i=0.5*c_i*g_i",
            "force_closure": "Kutta–Joukowski on each piecewise-constant bound Γ panel; trailing-leg-only downwash at spanwise force quadrature points; no separate section CL/induced-drag force is added",
            "coordinates": "D11f comparison frame: x aft, y right, z up; yaw is Σ y*Fx; body-power sign is negative force dot the D11f air-on-wing velocity",
        },
        "domain": {
            "positive_axial": "strictly every collocation u_i>0; exact zero/reverse is refused, with no epsilon floor",
            "section_flow": "planar u,w only; no spanwise local velocity, sweep, sideslip, rotor wake, or 3-D bound-vortex closure",
            "attached": "user/admission condition; the Stik sweep checks geometric atan2(w,u) below its existing R02 a1; no stall or dynamic-stall model is present",
            "rates": "the equality proof is per panel for arbitrary positive u_i and w_i inside this linear attached horseshoe model; sampled evidence uses yaw rate only",
            "force_quadrature": "circulation is panelwise at 3/4-chord collocation; force is integrated over each bound span segment with 1/2/4/8-point Gauss-Legendre samples",
        },
        "checks": {
            "production_export_E_max_abs_error": e_gap,
            "direct_rate_dependent_matrix_vs_dimensional_g_max_abs_CL_error": direct_identity_error,
            "variable_chord_direct_matrix_vs_g_max_abs_CL_error": tapered_identity_error,
            "variable_chord_fixture_has_finite_E": tapered_gamma_units_check,
            "zero_camber_D11f_midpoint_total_yaw_max_abs_error_Nm": d11f_match_error,
            "zero_camber_D11f_midpoint_rows": d11f_force_rows,
            "uniform_induced_downwash_min_mps": uniform_downwash_min,
            "uniform_KJ_induced_drag_positive_N": uniform_induced_drag,
            "uniform_KJ_plus_profile_power_on_airframe_W": uniform_loads["power_total_body_w"],
            "uniform_KJ_power_on_airframe_W": uniform_loads["power_kj_body_w"],
            "velocity_density_similarity": similarity,
        },
        "yaw_cnr_model_form_sweep": cnr_rows,
        "panel_refinement_alpha4": refinement,
        "force_quadrature_refinement_alpha4_48_panels": quad_refinement,
        "counterexamples_and_refusals": {
            "near_zero_positive_axial_rate_rad_s": critical_rate * (1.0 - 1.0e-6),
            "near_zero_positive_axial_u_min_mps": min(u_zero_flow),
            "near_zero_positive_axial_max_abs_CL_algebraic_only": vector_max_abs(near_zero["cl"]),
            "near_zero_gamma_max_abs_m2_s": vector_max_abs(near_zero["gamma_m2_s"]),
            "near_zero_note": "Illustrates poor conditioning as one panel approaches u=0; no validity claim, and exact u=0 is refused.",
            "exact_zero_rejection": exact_zero_rejection,
            "reverse_flow_rejection": reverse_rejection,
            "15deg_stall_limit_rejection": stalled_rejection,
        },
    }


def main() -> None:
    result = run()
    OUT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUT_PATH), "checks": result["checks"],
                      "identity": result["identity"]}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
