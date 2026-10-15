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
import sys
from pathlib import Path
from typing import Callable, Sequence

import numpy as np
import scipy
from scipy.linalg import inv as scipy_inverse
from scipy.linalg import solve as scipy_solve
from scipy.special import roots_legendre


ROOT = Path(__file__).resolve().parents[4]
INPUT_PATH = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/yaw_r02_input_export-v1.json"
D11F_PATH = ROOT / "research/aero/d11f/wing_yaw_damping.py"
AERO_SOURCE_PATH = ROOT / "app/physics/aero.gd"
AIRCRAFT_DATA_PATH = ROOT / "app/physics/aircraft_data.gd"
REQUIREMENTS_PATH = Path(__file__).with_name("requirements-v3.txt")
OUT_PATH = Path(__file__).with_name("candidate-results-v3.json")

V_MPS = 15.0
RHO_KG_M3 = 1.225
RATE_STEP_RAD_S = 0.05
ALPHA_DEG = (0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0)
FAR_M = 1.0e5
SUPPORTED_GAUSS_ORDERS = (1, 2, 4, 8, 16, 32)
GAUSS_LEGENDRE = {
    order: tuple(tuple(float(x) for x in values) for values in roots_legendre(order))
    for order in SUPPORTED_GAUSS_ORDERS
}


class DomainError(ValueError):
    """The input lies outside the candidate's stated mathematical domain."""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _finite_vector(values: Sequence[float]) -> bool:
    return all(math.isfinite(float(value)) for value in values)


def _validate_square_map(matrix: Sequence[Sequence[float]], order: int, name: str) -> None:
    if order <= 0 or len(matrix) != order or any(len(row) != order for row in matrix):
        raise ValueError(f"{name} must be a nonempty square map matching panel order")
    if any(not _finite_vector(row) for row in matrix):
        raise DomainError(f"{name} entries must be finite")


def _validate_mesh(mesh: dict[str, Sequence[float]]) -> int:
    try:
        edges = mesh["edges_m"]
        centres = mesh["y_centres_m"]
        chords = mesh["chords_m"]
    except (KeyError, TypeError) as exc:
        raise ValueError("mesh must provide edges_m, y_centres_m, and chords_m") from exc
    order = len(chords)
    if order <= 0 or len(edges) != order + 1 or len(centres) != order:
        raise ValueError("mesh edge, centre, and chord counts are inconsistent")
    if not (_finite_vector(edges) and _finite_vector(centres) and _finite_vector(chords)):
        raise DomainError("mesh geometry must be finite")
    if any(float(chord) <= 0.0 for chord in chords):
        raise DomainError("each panel chord must be positive")
    for i in range(order):
        left, right = float(edges[i]), float(edges[i + 1])
        if not right > left:
            raise DomainError("panel span edges must be strictly increasing")
        midpoint = 0.5 * (left + right)
        if not math.isclose(float(centres[i]), midpoint, rel_tol=0.0, abs_tol=1.0e-12):
            raise DomainError("panel centers must match their span-edge midpoints")
    return order


def _validate_density(rho_kg_m3: float) -> None:
    if not math.isfinite(rho_kg_m3) or rho_kg_m3 < 0.0:
        raise DomainError("air density must be finite and nonnegative")


def _validate_positive_slope(a0_per_rad: float) -> None:
    if not math.isfinite(a0_per_rad) or a0_per_rad <= 0.0:
        raise DomainError("attached section slope must be finite and positive")


def _rejection_message(operation: Callable[[], object]) -> str:
    try:
        operation()
    except ValueError as exc:
        return str(exc)
    return ""


def solve_linear(a: Sequence[Sequence[float]], b: Sequence[float]) -> list[float]:
    n = len(b)
    _validate_square_map(a, n, "linear-system matrix")
    if not _finite_vector(b):
        raise DomainError("linear-system right-hand side must be finite")
    if len(a) != n:
        raise ValueError("linear system must be square")
    try:
        solved = scipy_solve(np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64),
                             assume_a="gen", check_finite=True)
    except (ValueError, np.linalg.LinAlgError) as exc:
        raise DomainError("attached influence system is singular or invalid") from exc
    result = [float(value) for value in solved]
    if not _finite_vector(result):
        raise DomainError("attached influence solve produced a non-finite result")
    return result


def inverse(a: Sequence[Sequence[float]]) -> list[list[float]]:
    n = len(a)
    _validate_square_map(a, n, "matrix to invert")
    try:
        inverted = scipy_inverse(np.asarray(a, dtype=np.float64), check_finite=True)
    except (ValueError, np.linalg.LinAlgError) as exc:
        raise DomainError("attached influence map is singular or invalid") from exc
    result = [[float(value) for value in row] for row in inverted]
    if any(not _finite_vector(row) for row in result):
        raise DomainError("matrix inverse produced a non-finite result")
    return result


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
    if not math.isfinite(span_m) or span_m <= 0.0:
        raise DomainError("wing span must be finite and positive")
    if n == 0 or not _finite_vector(chords_m) or any(float(c) <= 0.0 for c in chords_m):
        raise DomainError("each panel needs a finite positive chord")
    edges = [-0.5 * span_m + span_m * i / n for i in range(n + 1)]
    ys = [0.5 * (edges[i] + edges[i + 1]) for i in range(n)]
    mesh = {"edges_m": edges, "y_centres_m": ys, "chords_m": [float(c) for c in chords_m]}
    _validate_mesh(mesh)
    return mesh


def induced_angle_kernel(mesh: dict[str, list[float]]) -> list[list[float]]:
    """K_ij: induced angle at control i per CL_j, excluding only the local 2-D term.

    The source chord c_j appears here.  The diagonal correction is the same
    1/(2π) self term removed by AircraftData.strip_influence and D11f.
    """
    n = _validate_mesh(mesh)
    edges, ys, chords = mesh["edges_m"], mesh["y_centres_m"], mesh["chords_m"]
    out = [[0.0] * n for _ in range(n)]
    for i in range(n):
        x_control = 0.5 * chords[i]
        for j in range(n):
            w_z = horseshoe_velocity_z(x_control, ys[i], edges[j], edges[j + 1])
            out[i][j] = -0.5 * chords[j] * w_z - (1.0 / (2.0 * math.pi) if i == j else 0.0)
    return out


def effective_map(k_map: Sequence[Sequence[float]], a0_per_rad: float) -> list[list[float]]:
    n = len(k_map)
    _validate_square_map(k_map, n, "induced-angle map")
    _validate_positive_slope(a0_per_rad)
    operator = [[(1.0 if i == j else 0.0) + a0_per_rad * k_map[i][j]
                 for j in range(n)] for i in range(n)]
    return inverse(operator)


def equivalent_zero_incidence(k_map: Sequence[Sequence[float]], a0_per_rad: float,
                              strip_cl0: Sequence[float]) -> list[float]:
    """Recover α0 satisfying c0 = a0 E α0; α0 is equivalent, not measured camber."""
    n = len(k_map)
    _validate_square_map(k_map, n, "induced-angle map")
    _validate_positive_slope(a0_per_rad)
    if len(strip_cl0) != n or not _finite_vector(strip_cl0):
        raise DomainError("strip CL0 must be finite and match the panel order")
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
    if n <= 0:
        raise ValueError("candidate requires at least one panel")
    if (len(w_mps) != n or len(alpha_zero_rad) != n or len(chords_m) != n
            or len(k_map) != n or len(e_map) != n):
        raise ValueError("all panel vectors and maps must have the same order")
    _validate_square_map(k_map, n, "induced-angle map")
    _validate_square_map(e_map, n, "effective influence map")
    _validate_positive_slope(a0_per_rad)
    incidence = list(incidence_rad) if incidence_rad is not None else [0.0] * n
    if len(incidence) != n:
        raise ValueError("incidence vector has the wrong order")
    if not all(_finite_vector(values) for values in (u_mps, w_mps, alpha_zero_rad, incidence, chords_m)):
        raise DomainError("candidate requires finite panel inputs")
    if any(u <= 0.0 for u in u_mps):
        raise DomainError("candidate refuses stagnant or reverse axial flow: every u_i must be > 0")
    if any(float(chord) <= 0.0 for chord in chords_m):
        raise DomainError("candidate requires a positive receiving-panel chord")
    source = [w_mps[i] + u_mps[i] * (alpha_zero_rad[i] + incidence[i]) for i in range(n)]
    g = [a0_per_rad * x for x in matvec(e_map, source)]
    cl = [g[i] / u_mps[i] for i in range(n)]
    gamma_m2_s = [0.5 * chords_m[i] * g[i] for i in range(n)]
    if not all(_finite_vector(values) for values in (g, cl, gamma_m2_s)):
        raise DomainError("candidate circulation solve produced a non-finite result")
    return {"g_mps": g, "cl": cl, "gamma_m2_s": gamma_m2_s}


def direct_rate_dependent_cl(k_map: Sequence[Sequence[float]], a0_per_rad: float,
                             u_mps: Sequence[float], w_mps: Sequence[float],
                             alpha_zero_rad: Sequence[float], incidence_rad: Sequence[float] | None = None
                             ) -> list[float]:
    """Independent D11f form, with its rate-dependent u_j/u_i operator."""
    n = len(u_mps)
    if n <= 0 or len(w_mps) != n or len(alpha_zero_rad) != n:
        raise ValueError("D11f comparison vectors must have one entry per panel")
    _validate_square_map(k_map, n, "induced-angle map")
    _validate_positive_slope(a0_per_rad)
    incidence = list(incidence_rad) if incidence_rad is not None else [0.0] * n
    if len(incidence) != n:
        raise ValueError("incidence vector has the wrong order")
    if not all(_finite_vector(values) for values in (u_mps, w_mps, alpha_zero_rad, incidence)):
        raise DomainError("D11f comparison inputs must be finite")
    if any(u <= 0.0 for u in u_mps):
        raise DomainError("D11f comparison requires every u_i > 0")
    operator = [[(1.0 if i == j else 0.0) / a0_per_rad
                 + k_map[i][j] * u_mps[j] / u_mps[i] for j in range(n)] for i in range(n)]
    rhs = [w_mps[i] / u_mps[i] + alpha_zero_rad[i] + incidence[i] for i in range(n)]
    return solve_linear(operator, rhs)


def wake_downwash_at_bound(mesh: dict[str, list[float]], gamma_m2_s: Sequence[float],
                           y_m: float) -> float:
    """D11f downwash sign at the bound line; omit the singular bound segment."""
    n = _validate_mesh(mesh)
    if len(gamma_m2_s) != n or not _finite_vector(gamma_m2_s):
        raise DomainError("finite circulation must have one value per panel")
    if not math.isfinite(y_m):
        raise DomainError("downwash query must have a finite span location")
    edges = mesh["edges_m"]
    z_velocity = sum(trailing_velocity_z(0.0, y_m, edges[j], edges[j + 1]) * gamma_m2_s[j]
                     for j in range(len(gamma_m2_s)))
    return -z_velocity


def integrate_bound_forces(mesh: dict[str, list[float]], gamma_m2_s: Sequence[float],
                           flow_at_y: Callable[[float], tuple[float, float]], rho_kg_m3: float,
                           quadrature_order: int = 1, cd0_comparator: float | None = None) -> dict[str, float]:
    """Integrate piecewise-constant bound Γ with sampled flow and panel-centroid induced wash.

    Coordinates and force signs follow D11f: x is aft, y right, z up.  A
    reported yaw moment is Σ y F_x, matching the production comparison after
    the R11 body-axis sign conversion.  `cd0_comparator` is only the frozen
    D11f profile-force assumption, not an asserted wing-section coefficient.
    """
    n = _validate_mesh(mesh)
    if quadrature_order not in GAUSS_LEGENDRE:
        raise ValueError("quadrature_order must be one of 1, 2, 4, 8, 16, 32")
    _validate_density(rho_kg_m3)
    if len(gamma_m2_s) != n or not _finite_vector(gamma_m2_s):
        raise ValueError("one Γ is required per panel")
    if cd0_comparator is not None and (not math.isfinite(cd0_comparator) or cd0_comparator < 0.0):
        raise DomainError("profile-comparison coefficient must be finite and nonnegative")
    nodes, weights = GAUSS_LEGENDRE[quadrature_order]
    edges, chords = mesh["edges_m"], mesh["chords_m"]
    sums = {"fx_kj_n": 0.0, "fz_kj_n": 0.0, "yaw_kj_nm": 0.0,
            "fx_profile_n": 0.0, "yaw_profile_nm": 0.0,
            "power_kj_body_w": 0.0, "power_profile_body_w": 0.0}
    for i, gamma in enumerate(gamma_m2_s):
        width = edges[i + 1] - edges[i]
        # The discrete trailing legs are singular at their endpoints on the bound line.
        # Hold their induced downwash at the panel center (D11f strip semantics); sample
        # external/local flow at each force point. This is a finite discrete closure, not
        # a continuum self-wake solution.
        panel_y = 0.5 * (edges[i] + edges[i + 1])
        panel_w_down = wake_downwash_at_bound(mesh, gamma_m2_s, panel_y)
        if not math.isfinite(panel_w_down):
            raise DomainError("induced panel-center downwash must be finite")
        for node, gauss_weight in zip(nodes, weights):
            y = 0.5 * (edges[i] + edges[i + 1]) + 0.5 * width * node
            dy_weight = 0.5 * width * gauss_weight
            u, w = flow_at_y(y)
            if not math.isfinite(u) or not math.isfinite(w):
                raise DomainError("force quadrature received a non-finite velocity")
            if u <= 0.0:
                raise DomainError("force quadrature is restricted to strictly positive axial velocity")
            fx_kj = -rho_kg_m3 * gamma * (w - panel_w_down) * dy_weight
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
    if not all(math.isfinite(value) for value in sums.values()):
        raise DomainError("force quadrature produced a non-finite load")
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


def symmetric_state_checks(mesh: dict[str, list[float]], k_map: Sequence[Sequence[float]],
                           e_map: Sequence[Sequence[float]], a0: float,
                           alpha_zero: Sequence[float], alpha_rad: float,
                           speed_mps: float, rho_kg_m3: float) -> dict[str, float]:
    """Check mirrored circulation, wake, local x-force, and integrated yaw at r=0."""
    u, w = section_flows(mesh, alpha_rad, 0.0, speed_mps)
    gamma = candidate_circulation(k_map, e_map, mesh["chords_m"], a0, u, w,
                                  alpha_zero)["gamma_m2_s"]
    nodes, weights = GAUSS_LEGENDRE[16]
    edges = mesh["edges_m"]
    panel_fx: list[float] = []
    downwash_centres: list[float] = []
    for i in range(len(gamma)):
        left, right = edges[i], edges[i + 1]
        width = right - left
        fx = 0.0
        panel_w_down = wake_downwash_at_bound(mesh, gamma, 0.5 * (left + right))
        for node, weight in zip(nodes, weights):
            y = 0.5 * (left + right) + 0.5 * width * node
            dy_weight = 0.5 * width * weight
            local_u, local_w = yaw_flow(alpha_rad, 0.0, speed_mps)(y)
            fx += -rho_kg_m3 * gamma[i] * (local_w - panel_w_down) * dy_weight
        panel_fx.append(fx)
        centre = 0.5 * (left + right)
        downwash_centres.append(wake_downwash_at_bound(mesh, gamma, centre))
    loads = integrate_bound_forces(mesh, gamma, yaw_flow(alpha_rad, 0.0, speed_mps),
                                   rho_kg_m3, 16)
    n = len(gamma)
    return {
        "max_mirrored_gamma_gap_m2_s": max(abs(gamma[i] - gamma[n - 1 - i]) for i in range(n)),
        "max_mirrored_center_downwash_gap_mps": max(abs(downwash_centres[i] - downwash_centres[n - 1 - i])
                                                      for i in range(n)),
        "max_mirrored_panel_kj_fx_gap_N": max(abs(panel_fx[i] - panel_fx[n - 1 - i]) for i in range(n)),
        "absolute_integrated_kj_yaw_Nm": abs(loads["yaw_kj_nm"]),
        "absolute_integrated_total_yaw_Nm": abs(loads["yaw_total_nm"]),
    }


def uniform_kj_energy_identity(mesh: dict[str, list[float]], gamma: Sequence[float],
                               alpha_rad: float, speed_mps: float, rho_kg_m3: float,
                               quadrature_order: int = 32) -> dict[str, float]:
    """Integrate the induced force/power identity with the same bound-line samples."""
    n = _validate_mesh(mesh)
    _validate_density(rho_kg_m3)
    if quadrature_order not in GAUSS_LEGENDRE:
        raise ValueError("unsupported Gauss-Legendre order")
    if len(gamma) != n or not _finite_vector(gamma):
        raise DomainError("finite circulation must have one value per panel")
    if not all(math.isfinite(value) for value in (alpha_rad, speed_mps)) or speed_mps <= 0.0:
        raise DomainError("energy identity requires finite angle and positive speed")
    nodes, weights = GAUSS_LEGENDRE[quadrature_order]
    edges = mesh["edges_m"]
    u = speed_mps * math.cos(alpha_rad)
    if u <= 0.0:
        raise DomainError("uniform energy identity requires positive chordwise velocity")
    induced_drag_n = 0.0
    induced_power_w = 0.0
    for i, circulation in enumerate(gamma):
        left, right = edges[i], edges[i + 1]
        width = right - left
        panel_downwash = wake_downwash_at_bound(mesh, gamma, 0.5 * (left + right))
        for node, weight in zip(nodes, weights):
            y = 0.5 * (left + right) + 0.5 * width * node
            dy_weight = 0.5 * width * weight
            downwash = panel_downwash
            induced_drag_n += rho_kg_m3 * circulation * downwash * dy_weight
            induced_power_w -= rho_kg_m3 * circulation * u * downwash * dy_weight
    return {"induced_drag_N": induced_drag_n,
            "induced_power_on_airframe_W": induced_power_w,
            "minus_u_times_induced_drag_W": -u * induced_drag_n}


def exact_linear_yaw_profile_loads(mesh: dict[str, list[float]], alpha_rad: float,
                                   rate_rad_s: float, speed_mps: float,
                                   rho_kg_m3: float, cd0: float) -> dict[str, float]:
    """Exact quadratic-velocity profile integral and yaw arm for the linear yaw field."""
    _validate_mesh(mesh)
    _validate_density(rho_kg_m3)
    if not math.isfinite(cd0) or cd0 < 0.0:
        raise DomainError("profile-comparison coefficient must be finite and nonnegative")
    if not all(math.isfinite(value) for value in (alpha_rad, rate_rad_s, speed_mps)) or speed_mps <= 0.0:
        raise DomainError("profile integral requires finite angles/rate and positive speed")
    u0 = speed_mps * math.cos(alpha_rad)
    w = speed_mps * math.sin(alpha_rad)
    for left, right in zip(mesh["edges_m"], mesh["edges_m"][1:]):
        if min(u0 - rate_rad_s * left, u0 - rate_rad_s * right) <= 0.0:
            raise DomainError("analytic profile integral is restricted to positive axial flow")
    fx_n = yaw_nm = 0.0
    for i, chord in enumerate(mesh["chords_m"]):
        left, right = mesh["edges_m"][i], mesh["edges_m"][i + 1]
        speed_squared_integral = ((u0 * u0 + w * w) * (right - left)
                                  - u0 * rate_rad_s * (right * right - left * left)
                                  + rate_rad_s * rate_rad_s * (right ** 3 - left ** 3) / 3.0)
        y_speed_squared_integral = ((u0 * u0 + w * w) * (right * right - left * left) / 2.0
                                    - 2.0 * u0 * rate_rad_s * (right ** 3 - left ** 3) / 3.0
                                    + rate_rad_s * rate_rad_s * (right ** 4 - left ** 4) / 4.0)
        scale = 0.5 * rho_kg_m3 * cd0 * chord
        fx_n += scale * speed_squared_integral
        yaw_nm += scale * y_speed_squared_integral
    return {"fx_profile_N": fx_n, "yaw_profile_Nm": yaw_nm}


def trailing_edge_endpoint_probe(mesh: dict[str, list[float]], gamma: Sequence[float],
                                 edge_index: int) -> dict:
    """Show pointwise bound-line downwash near a discrete trailing-filament jump."""
    edge_y = mesh["edges_m"][edge_index]
    jump = gamma[edge_index - 1] - gamma[edge_index]
    rows = []
    for eps in (1.0e-4, 1.0e-6, 1.0e-8, 1.0e-10):
        left = wake_downwash_at_bound(mesh, gamma, edge_y - eps)
        right = wake_downwash_at_bound(mesh, gamma, edge_y + eps)
        rows.append({"epsilon_m": eps, "left_downwash_mps": left,
                     "right_downwash_mps": right,
                     "epsilon_times_left_m2_s": eps * left,
                     "epsilon_times_right_m2_s": eps * right})
    return {"shared_edge_index": edge_index, "edge_y_m": edge_y,
            "adjacent_circulation_jump_m2_s": jump,
            "pointwise_downwash_samples": rows}


def require_geometric_attached(u_mps: Sequence[float], w_mps: Sequence[float],
                               attached_limit_rad: float) -> None:
    if len(u_mps) <= 0 or len(w_mps) != len(u_mps):
        raise ValueError("attached-flow vectors must have the same nonzero panel order")
    if not math.isfinite(attached_limit_rad) or attached_limit_rad <= 0.0:
        raise DomainError("attached-angle limit must be finite and positive")
    if not _finite_vector(u_mps) or not _finite_vector(w_mps):
        raise DomainError("attached-flow vectors must be finite")
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
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["area_m2"]) / span
    mesh = make_mesh(span, [chord] * len(data["geometry"]["station_y_m"]))
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
    chord = float(data["geometry"]["area_m2"]) / span
    a0 = float(data["geometry"]["strip_slope_per_rad"])
    for n_side in (3, 6, 12, 24, 48, 96):
        mesh = make_mesh(span, [chord] * (2 * n_side))
        k_map = induced_angle_kernel(mesh)
        e_map = effective_map(k_map, a0)
        alpha_zero = [alpha_zero_constant] * len(mesh["chords_m"])
        alpha = math.radians(4.0)
        rows.append({
            "panels_per_semispan": n_side,
            "total_panels": len(mesh["chords_m"]),
            "force_quadrature_order": 16,
            "k_j_only_Cnr_alpha4": circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero,
                                                          alpha, RHO_KG_M3, V_MPS, 16, None),
            "with_D11f_profile_assumption_Cnr_alpha4": circulation_yaw_cnr(
                mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, 16,
                float(data["aero"]["CD0"])),
        })
    return rows


def quadrature_refinement(data: dict, alpha_zero_constant: float) -> list[dict[str, float | int]]:
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["area_m2"]) / span
    a0 = float(data["geometry"]["strip_slope_per_rad"])
    mesh = make_mesh(span, [chord] * 96)
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
    } for order in (1, 2, 4, 8, 16, 32)]


def velocity_density_similarity(data: dict, alpha_zero_constant: float) -> dict:
    span = float(data["geometry"]["span_m"])
    chord = float(data["geometry"]["area_m2"]) / span
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
    aero_source_sha = sha256(AERO_SOURCE_PATH)
    if aero_source_sha != data["aero_source_sha256"]:
        raise AssertionError("R11 input export aero source identity does not match the live source")
    span = float(geom["span_m"])
    area = float(geom["area_m2"])
    chord = area / span
    reported_mean_chord = float(geom["mean_chord_m"])
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
    endpoint_u, endpoint_w = section_flows(mesh, math.radians(4.0), 0.0, V_MPS)
    endpoint_gamma = candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                                           endpoint_u, endpoint_w, alpha_zero)["gamma_m2_s"]
    endpoint_singularity = trailing_edge_endpoint_probe(mesh, endpoint_gamma, 2)

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
    tapered_solution = candidate_circulation(tapered_k, tapered_e, tapered["chords_m"], a0,
                                              tapered_u, tapered_w, tapered_alpha0)
    tapered_gamma_identity_error = max(abs(tapered_solution["gamma_m2_s"][i]
                                           - 0.5 * tapered["chords_m"][i] * tapered_solution["g_mps"][i])
                                       for i in range(n))
    tapered_finite_e_check = all(math.isfinite(tapered_e[i][j]) for i in range(n) for j in range(n))

    d11f = load_d11f()
    # Exact independent reference check for D11f's authored six-panel, zero-camber case.
    d11f_span_m = float(d11f.b)
    d11f_chord = float(d11f.c)
    d11f_mesh = make_mesh(d11f_span_m, [d11f_chord] * int(d11f.n))
    d11f_k = induced_angle_kernel(d11f_mesh)
    d11f_a0 = float(d11f.a0)
    d11f_e = effective_map(d11f_k, d11f_a0)
    zero_alpha0 = [0.0] * int(d11f.n)
    d11f_force_rows = []
    for alpha_deg in (2.0, 4.0, 8.0, 10.0, 11.0):
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
        candidate_cnr_kj_q1 = circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero, alpha,
                                                   RHO_KG_M3, V_MPS, 1, None)
        candidate_cnr_profile_q1 = circulation_yaw_cnr(
            mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, 1,
            float(aero["CD0"]))
        candidate_cnr_kj_q16 = circulation_yaw_cnr(mesh, k_map, e_map, a0, alpha_zero, alpha,
                                                    RHO_KG_M3, V_MPS, 16, None)
        candidate_cnr_profile_q16 = circulation_yaw_cnr(
            mesh, k_map, e_map, a0, alpha_zero, alpha, RHO_KG_M3, V_MPS, 16,
            float(aero["CD0"]))
        r02 = cnr_from_moment(
            lambda rate: r02_yaw_moment(data, e_map, a0, alpha, rate, RHO_KG_M3, V_MPS)["total"],
            RHO_KG_M3, V_MPS, span, area)
        cnr_rows.append({"alpha_deg": alpha_deg, "R02_fixed_E_polar_Cnr": r02,
                         "candidate_KJ_only_Cnr_q1_D11f_midpoint_lane": candidate_cnr_kj_q1,
                         "candidate_KJ_plus_profile_Cnr_q1_D11f_midpoint_lane": candidate_cnr_profile_q1,
                         "candidate_KJ_only_Cnr_q16_line_integral": candidate_cnr_kj_q16,
                         "candidate_KJ_plus_D11f_profile_assumption_Cnr_q16_line_integral": candidate_cnr_profile_q16})

    # Nonuniform flow-point check: order-2 line quadrature exactly integrates the
    # quadratic-velocity profile force and cubic-yaw-moment integrand for linear yaw flow.
    sample_mesh = make_mesh(span, [chord] * len(ys_export))
    sample_k = induced_angle_kernel(sample_mesh)
    sample_e = effective_map(sample_k, a0)
    sample_alpha = math.radians(4.0)
    sample_rate = 0.05
    sample_u, sample_w = section_flows(sample_mesh, sample_alpha, sample_rate, V_MPS)
    sample_gamma = candidate_circulation(sample_k, sample_e, sample_mesh["chords_m"], a0,
                                         sample_u, sample_w, alpha_zero)["gamma_m2_s"]
    comparator_cd0 = float(aero["CD0"])
    profile_exact = exact_linear_yaw_profile_loads(sample_mesh, sample_alpha, sample_rate,
                                                   V_MPS, RHO_KG_M3, comparator_cd0)
    local_flow_quadrature = {}
    for order in (1, 2, 4, 8):
        sampled = integrate_bound_forces(sample_mesh, sample_gamma,
                                         yaw_flow(sample_alpha, sample_rate, V_MPS),
                                         RHO_KG_M3, order, comparator_cd0)
        local_flow_quadrature[str(order)] = {
            "profile_force_N": sampled["fx_profile_n"],
            "profile_yaw_Nm": sampled["yaw_profile_nm"],
            "profile_force_abs_error_N": abs(sampled["fx_profile_n"] - profile_exact["fx_profile_N"]),
            "profile_yaw_abs_error_Nm": abs(sampled["yaw_profile_nm"] - profile_exact["yaw_profile_Nm"]),
            "kj_force_z_N": sampled["fz_kj_n"],
            "kj_yaw_Nm": sampled["yaw_kj_nm"],
        }

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
                                           RHO_KG_M3, 32, float(aero["CD0"]))
    uniform_energy_identity = uniform_kj_energy_identity(uniform_mesh, uniform_gamma,
                                                        alpha_uniform, V_MPS, RHO_KG_M3, 32)
    uniform_symmetry = symmetric_state_checks(uniform_mesh, uniform_k, uniform_e, a0,
                                              [alpha_zero_mean] * len(uniform_gamma),
                                              alpha_uniform, V_MPS, RHO_KG_M3)
    uniform_induced_drag = uniform_energy_identity["induced_drag_N"]
    uniform_downwash_min = math.inf
    for i, gamma in enumerate(uniform_gamma):
        y = uniform_mesh["y_centres_m"][i]
        w_down = wake_downwash_at_bound(uniform_mesh, uniform_gamma, y)
        uniform_downwash_min = min(uniform_downwash_min, w_down)

    # Similarity scaling includes both speed and yaw rate, keeping angles and nondimensional rate fixed.
    similarity = velocity_density_similarity(data, alpha_zero_mean)

    # Singular and separated-flow counterexamples are recorded, not regularized into a new law.
    alpha_zero_flow = 0.0
    critical_rate = V_MPS / max(abs(y) for y in mesh["y_centres_m"])
    u_zero_flow = [V_MPS - critical_rate * (1.0 - 1.0e-6) * y for y in mesh["y_centres_m"]]
    w_zero_flow = [0.0] * len(u_zero_flow)
    near_zero = candidate_circulation(k_map, e_map, mesh["chords_m"], a0,
                                      u_zero_flow, w_zero_flow, alpha_zero)
    force_zero_u_rejection = ""
    try:
        integrate_bound_forces(mesh, endpoint_gamma, lambda _y: (0.0, 0.0), RHO_KG_M3, 2)
    except DomainError as exc:
        force_zero_u_rejection = str(exc)
    force_reverse_u_rejection = _rejection_message(
        lambda: integrate_bound_forces(mesh, endpoint_gamma, lambda _y: (-0.01, 0.0), RHO_KG_M3, 2))
    force_nonfinite_u_rejection = _rejection_message(
        lambda: integrate_bound_forces(mesh, endpoint_gamma,
                                       lambda _y: (float("nan"), 0.0), RHO_KG_M3, 2))
    negative_density_rejection = ""
    try:
        integrate_bound_forces(mesh, endpoint_gamma, yaw_flow(math.radians(4.0), 0.0, V_MPS), -0.1, 2)
    except DomainError as exc:
        negative_density_rejection = str(exc)
    nonfinite_density_rejection = _rejection_message(
        lambda: integrate_bound_forces(mesh, endpoint_gamma,
                                       yaw_flow(math.radians(4.0), 0.0, V_MPS), float("nan"), 2))
    zero_density_loads = integrate_bound_forces(
        mesh, endpoint_gamma, yaw_flow(math.radians(4.0), 0.0, V_MPS), 0.0, 2)
    zero_density_max_abs_load = max(abs(value) for value in zero_density_loads.values())
    bad_map_rejection = _rejection_message(lambda: candidate_circulation(
        k_map, e_map[:-1], mesh["chords_m"], a0, endpoint_u, endpoint_w, alpha_zero))
    bad_chord_rejection = _rejection_message(lambda: candidate_circulation(
        k_map, e_map, [0.0] + mesh["chords_m"][1:], a0, endpoint_u, endpoint_w, alpha_zero))
    nonfinite_collocation_u_rejection = _rejection_message(lambda: candidate_circulation(
        k_map, e_map, mesh["chords_m"], a0,
        [float("nan")] + endpoint_u[1:], endpoint_w, alpha_zero))
    bad_mesh_rejection = _rejection_message(lambda: integrate_bound_forces(
        {**mesh, "edges_m": mesh["edges_m"][:-1]}, endpoint_gamma,
        yaw_flow(math.radians(4.0), 0.0, V_MPS), RHO_KG_M3, 2))
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
        "schema": "r02-attached-circulation-candidate-v3",
        "interpretation": "Research candidate and software/model-form comparison only; not a promoted runtime law or physical validation.",
        "identity": {
            "candidate_source_sha256": sha256(Path(__file__).resolve()),
            "python_version": sys.version.split()[0],
            "python_executable": sys.executable,
            "numpy_version": np.__version__,
            "scipy_version": scipy.__version__,
            "production_input_export_sha256": sha256(INPUT_PATH),
            "production_aircraft_sha256": data["aircraft_input"]["sha256"],
            "production_aero_source_sha256": aero_source_sha,
            "production_aircraft_data_source_sha256": sha256(AIRCRAFT_DATA_PATH),
            "D11f_source_sha256": sha256(D11F_PATH),
            "requirements_v3_sha256": sha256(REQUIREMENTS_PATH),
        },
        "model": {
            "span_m": span, "area_m2": area, "production_strip_chord_area_over_span_m": chord,
            "exported_rounded_mean_chord_m": reported_mean_chord,
            "geometry_lanes": {
                "production_export": {
                    "span_m": span, "area_m2": area, "strip_chord_m": chord,
                    "chord_definition": "source wing area divided by span; export mean_chord_m is rounded and is reported separately",
                },
                "D11f_authored": {
                    "span_m": d11f_span_m, "chord_m": d11f_chord,
                    "chord_definition": "literal D11f reference input; kept separate from the production S/b chord",
                },
            },
            "panel_count": n, "strip_slope_per_rad": a0,
            "equivalent_alpha_zero_rad": alpha_zero,
            "equivalent_alpha_zero_mean_rad": alpha_zero_mean,
            "equivalent_alpha_zero_spread_rad": alpha_zero_spread,
            "alpha_zero_semantics": "M_static * production strip_cl0; equivalent intercept reconstructed from the existing fitted R02 strips, not measured airfoil camber/incidence",
            "CD0_semantics": "production value is a whole-aircraft polar; used only as the inherited D11f comparison profile term, not asserted as measured wing-section CD0",
            "geometry_operator": "K_ij=-0.5*c_j*horseshoe_z_ij-δ_ij/(2π), E=(I+a0*K)^-1; collocation uses the full horseshoe at each 3/4-chord point",
            "dimensional_source": "g_i=u_i*CL_i; g=a0*E*(w+u*(alpha_zero+incidence)); Gamma_i=0.5*c_i*g_i",
            "force_closure": "Kutta–Joukowski on each piecewise-constant bound Γ panel; trailing-leg-only induced downwash is evaluated at each panel center to avoid bound-line endpoint singularities, while external flow is sampled along the bound segment; no separate section CL/induced-drag force is added",
            "coordinates": "D11f comparison frame: x aft, y right, z up; yaw is Σ y*Fx; body-power sign is negative force dot the D11f air-on-wing velocity",
        },
        "domain": {
            "positive_axial": "strictly every collocation u_i>0; exact zero/reverse is refused, with no epsilon floor",
            "section_flow": "planar u,w only; no spanwise local velocity, sweep, sideslip, rotor wake, or 3-D bound-vortex closure",
            "attached": "user/admission condition; the Stik sweep checks geometric atan2(w,u) below its existing R02 a1; no stall or dynamic-stall model is present",
            "rates": "the equality proof is per panel for arbitrary positive u_i and w_i inside this linear attached horseshoe model; sampled evidence uses yaw rate only",
            "force_quadrature": "circulation is panelwise at 3/4-chord collocation; external/local flow is sampled along the bound span with Gauss-Legendre quadrature, while the induced trailing-leg downwash is evaluated once at each panel center to avoid endpoint singularities",
        },
        "checks": {
            "production_export_E_max_abs_error": e_gap,
            "direct_rate_dependent_matrix_vs_dimensional_g_max_abs_CL_error": direct_identity_error,
            "variable_chord_direct_matrix_vs_g_max_abs_CL_error": tapered_identity_error,
            "variable_chord_gamma_equals_half_chord_times_g_max_abs_error_m2_s": tapered_gamma_identity_error,
            "variable_chord_fixture_has_finite_E": tapered_finite_e_check,
            "zero_camber_D11f_midpoint_total_yaw_max_abs_error_Nm": d11f_match_error,
            "zero_camber_D11f_midpoint_rows": d11f_force_rows,
            "uniform_induced_downwash_min_mps": uniform_downwash_min,
            "uniform_KJ_induced_drag_positive_N": uniform_induced_drag,
            "uniform_KJ_plus_profile_power_on_airframe_W": uniform_loads["power_total_body_w"],
            "uniform_KJ_power_on_airframe_W": uniform_loads["power_kj_body_w"],
            "uniform_KJ_power_identity_abs_error_W": abs(uniform_loads["power_kj_body_w"]
                                                          - uniform_energy_identity["induced_power_on_airframe_W"]),
            "uniform_KJ_power_vs_minus_u_drag_abs_error_W": abs(uniform_energy_identity["induced_power_on_airframe_W"]
                                                               - uniform_energy_identity["minus_u_times_induced_drag_W"]),
            "uniform_induced_drag_and_power_identity": uniform_energy_identity,
            "uniform_zero_yaw_symmetry": uniform_symmetry,
            "nonuniform_local_flow_quadrature": {
                "alpha_deg": 4.0, "yaw_rate_rad_s": sample_rate,
                "profile_cd0_semantics": "borrowed whole-aircraft CD0 used only to demonstrate quadratic-velocity/profile-force quadrature; not a section coefficient",
                "analytic_profile_integral": profile_exact,
                "sampled_orders": local_flow_quadrature,
            },
            "velocity_density_similarity": similarity,
        },
        "yaw_cnr_model_form_sweep": cnr_rows,
        "panel_refinement_alpha4": refinement,
        "force_quadrature_refinement_alpha4_96_panels": quad_refinement,
        "superseded_v1_pointwise_endpoint_probe": {
            "source_sha256": sha256(Path(__file__).with_name("circulation_candidate.py")),
            "diagnostic": endpoint_singularity,
            "interpretation": "The original pointwise self-wake quadrature is retained in candidate-results-v1 but rejected for continuum inference: trailing-leg velocity on the bound line grows as a panel-edge circulation jump divided by distance. Version 2 holds this discrete induced downwash at the panel center; it does not supply a continuous finite-core wake law.",
        },
        "refinement_note": "Panel and line-quadrature sweeps are numerical convergence diagnostics, not physical validation; report values directly and do not treat the coarsest production-strip match as a continuum result.",
        "counterexamples_and_refusals": {
            "near_zero_positive_axial_rate_rad_s": critical_rate * (1.0 - 1.0e-6),
            "near_zero_positive_axial_u_min_mps": min(u_zero_flow),
            "near_zero_positive_axial_max_abs_CL_algebraic_only": vector_max_abs(near_zero["cl"]),
            "near_zero_gamma_max_abs_m2_s": vector_max_abs(near_zero["gamma_m2_s"]),
            "near_zero_note": "Illustrates poor conditioning as one panel approaches u=0; no validity claim, and exact u=0 is refused.",
            "exact_zero_rejection": exact_zero_rejection,
            "reverse_flow_rejection": reverse_rejection,
            "force_quadrature_zero_axial_rejection": force_zero_u_rejection,
            "force_quadrature_reverse_axial_rejection": force_reverse_u_rejection,
            "force_quadrature_nonfinite_axial_rejection": force_nonfinite_u_rejection,
            "negative_density_rejection": negative_density_rejection,
            "nonfinite_density_rejection": nonfinite_density_rejection,
            "zero_density_maximum_absolute_load": zero_density_max_abs_load,
            "mismatched_map_size_rejection": bad_map_rejection,
            "nonpositive_chord_rejection": bad_chord_rejection,
            "nonfinite_collocation_axial_rejection": nonfinite_collocation_u_rejection,
            "inconsistent_mesh_size_rejection": bad_mesh_rejection,
            "15deg_stall_limit_rejection": stalled_rejection,
        },
    }


def validate_internal_checks(result: dict) -> None:
    """Fail the reproducible probe if its algebra, sign, symmetry, or quadrature checks regress."""
    checks = result["checks"]
    limits = {
        "direct_rate_dependent_matrix_vs_dimensional_g_max_abs_CL_error": 1.0e-12,
        "variable_chord_direct_matrix_vs_g_max_abs_CL_error": 1.0e-12,
        "variable_chord_gamma_equals_half_chord_times_g_max_abs_error_m2_s": 1.0e-15,
        "production_export_E_max_abs_error": 1.0e-12,
        "zero_camber_D11f_midpoint_total_yaw_max_abs_error_Nm": 1.0e-12,
        "uniform_KJ_power_identity_abs_error_W": 1.0e-12,
        "uniform_KJ_power_vs_minus_u_drag_abs_error_W": 1.0e-12,
    }
    for name, limit in limits.items():
        value = float(checks[name])
        if not math.isfinite(value) or value > limit:
            raise AssertionError(f"{name}={value} exceeds internal numeric limit {limit}")
    if float(checks["uniform_KJ_induced_drag_positive_N"]) <= 0.0:
        raise AssertionError("uniform attached KJ case must have positive induced drag")
    if float(checks["uniform_KJ_power_on_airframe_W"]) >= 0.0:
        raise AssertionError("uniform induced KJ power on the airframe must be negative")
    symmetry = checks["uniform_zero_yaw_symmetry"]
    for name in ("max_mirrored_gamma_gap_m2_s", "max_mirrored_center_downwash_gap_mps",
                 "max_mirrored_panel_kj_fx_gap_N", "absolute_integrated_total_yaw_Nm"):
        if float(symmetry[name]) > 1.0e-10:
            raise AssertionError(f"uniform symmetry check {name}={symmetry[name]} exceeds 1e-10")
    if float(checks["velocity_density_similarity"]["maximum_absolute_ratio_error"]) > 1.0e-8:
        raise AssertionError("force/moment density-velocity similarity check failed")
    quadrature = checks["nonuniform_local_flow_quadrature"]["sampled_orders"]
    for name in ("profile_force_abs_error_N", "profile_yaw_abs_error_Nm"):
        if float(quadrature["2"][name]) > 1.0e-12:
            raise AssertionError(f"two-point local-flow quadrature did not reproduce analytic {name}")
    if float(quadrature["1"]["profile_yaw_abs_error_Nm"]) < 1.0e-5:
        raise AssertionError("midpoint fixture no longer detects lost local q-squared moment integration")
    endpoint = result["superseded_v1_pointwise_endpoint_probe"]["diagnostic"]["pointwise_downwash_samples"]
    if abs(float(endpoint[-1]["left_downwash_mps"])) < 1.0e5 * abs(float(endpoint[0]["left_downwash_mps"])):
        raise AssertionError("v1 pointwise downwash did not show the expected panel-edge singular growth")
    for side in ("left", "right"):
        coefficient_before = float(endpoint[-2][f"epsilon_times_{side}_m2_s"])
        coefficient_after = float(endpoint[-1][f"epsilon_times_{side}_m2_s"])
        if abs(coefficient_after - coefficient_before) > 1.0e-5 * abs(coefficient_after):
            raise AssertionError("v1 pointwise edge coefficient failed its 1/distance diagnostic")
    for label in ("exact_zero_rejection", "reverse_flow_rejection",
                  "force_quadrature_zero_axial_rejection", "force_quadrature_reverse_axial_rejection",
                  "force_quadrature_nonfinite_axial_rejection", "negative_density_rejection",
                  "nonfinite_density_rejection", "mismatched_map_size_rejection",
                  "nonpositive_chord_rejection", "nonfinite_collocation_axial_rejection",
                  "inconsistent_mesh_size_rejection",
                  "15deg_stall_limit_rejection"):
        if not result["counterexamples_and_refusals"][label]:
            raise AssertionError(f"candidate domain refusal missing: {label}")
    if float(result["counterexamples_and_refusals"]["zero_density_maximum_absolute_load"]) != 0.0:
        raise AssertionError("finite zero-density limit should produce zero integrated loads")


def main() -> None:
    result = run()
    validate_internal_checks(result)
    OUT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUT_PATH), "checks": result["checks"],
                      "identity": result["identity"]}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
