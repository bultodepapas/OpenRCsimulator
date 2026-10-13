#!/usr/bin/env python3
"""Generate an independent linear four-corner, seven-DOF support reference.

This deterministic fixture is a synthetic software oracle, not physical truck
calibration.  It propagates a 14-state quarter-car assembly with a scaled
Taylor matrix exponential and repeated squaring; it does not use RK4.
"""

from __future__ import annotations

import argparse
import difflib
import json
import math
import sys
from pathlib import Path
from typing import Iterable, Sequence

from generate_suspension_reference import _add, _matvec, _max_abs_matrix, _multiply, _norm_inf, _scale


PARAMETERS = {
    "sprung_mass_kg": 4.8,
    "unsprung_mass_kg": 0.18,  # per wheel
    "suspension_stiffness_n_per_m": 900.0,  # per corner
    "suspension_damping_n_s_per_m": 7.0,  # per corner
    "tire_stiffness_n_per_m": 6500.0,  # per wheel
    "gravity_m_per_s2": 9.80665,
    "suspension_rest_length_m": 0.10,
    "tire_radius_m": 0.085,
    "roll_inertia_kg_m2": 0.192,
    "pitch_inertia_kg_m2": 0.15552,
    "front_axle_x_m": 0.18,
    "rear_axle_x_m": -0.18,
    "half_track_m": 0.20,
}
WHEEL_NAMES = ("fl", "fr", "rl", "rr")
POSITION_STATE_ORDER = (
    "z_body_m",
    "roll_rad",
    "pitch_rad",
    "z_u_fl_m",
    "z_u_fr_m",
    "z_u_rl_m",
    "z_u_rr_m",
)
RATE_STATE_ORDER = (
    "v_z_body_m_per_s",
    "roll_rate_rad_per_s",
    "pitch_rate_rad_per_s",
    "v_u_fl_m_per_s",
    "v_u_fr_m_per_s",
    "v_u_rl_m_per_s",
    "v_u_rr_m_per_s",
)
STATE_ORDER = POSITION_STATE_ORDER + RATE_STATE_ORDER
POSITION_STATE_UNITS = ("m", "rad", "rad", "m", "m", "m", "m")
RATE_STATE_UNITS = ("m/s", "rad/s", "rad/s", "m/s", "m/s", "m/s", "m/s")
STATE_UNITS = POSITION_STATE_UNITS + RATE_STATE_UNITS
SAMPLE_TIMES_S = (0.05, 0.1, 0.25, 0.5, 1.0)
INITIAL_POSITION_PERTURBATION = (0.0005, 0.0007, -0.0009, 0.00005, -0.00004, 0.00003, -0.00002)
DENSE_SAMPLE_COUNT = 5001
TAYLOR_NORM_LIMIT = 0.5
TAYLOR_TERM_TOLERANCE = 1.0e-17
MAX_TAYLOR_TERMS = 100


def _identity(size: int) -> tuple[tuple[float, ...], ...]:
    return tuple(tuple(1.0 if row == col else 0.0 for col in range(size)) for row in range(size))


def _matrix_exponential(matrix: tuple[tuple[float, ...], ...]) -> tuple[tuple[tuple[float, ...], ...], dict[str, int | float]]:
    """General-size scaling/Taylor/squaring using the suspension oracle's primitives."""
    size = len(matrix)
    norm = _norm_inf(matrix)
    if norm == 0.0:
        return _identity(size), {"scaling_squarings": 0, "taylor_terms": 0, "final_taylor_term_norm_inf": 0.0}

    squarings = max(0, math.ceil(math.log2(norm / TAYLOR_NORM_LIMIT)))
    reduced = _scale(matrix, math.ldexp(1.0, -squarings))
    term = _identity(size)
    result = _identity(size)
    term_count = 0
    for order in range(1, MAX_TAYLOR_TERMS + 1):
        term = _scale(_multiply(term, reduced), 1.0 / order)
        result = _add(result, term)
        term_count = order
        if _norm_inf(term) <= TAYLOR_TERM_TOLERANCE * max(1.0, _norm_inf(result)):
            break
    else:
        raise ArithmeticError(f"Taylor matrix exponential did not converge in {MAX_TAYLOR_TERMS} terms")

    for _ in range(squarings):
        result = _multiply(result, result)
    return result, {
        "scaling_squarings": squarings,
        "taylor_terms": term_count,
        "final_taylor_term_norm_inf": _norm_inf(term),
    }


def _wheel_mount_rows() -> tuple[tuple[float, ...], ...]:
    """Rows B=[1,y,-x] for FL, FR, RL, RR in the stated body convention."""
    half_track = PARAMETERS["half_track_m"]
    front_x = PARAMETERS["front_axle_x_m"]
    rear_x = PARAMETERS["rear_axle_x_m"]
    coordinates = (
        (front_x, half_track),
        (front_x, -half_track),
        (rear_x, half_track),
        (rear_x, -half_track),
    )
    return tuple((1.0, y, -x) for x, y in coordinates)


def _spring_rows() -> tuple[tuple[float, ...], ...]:
    """C maps generalized positions to body-mount height minus wheel height."""
    rows: list[tuple[float, ...]] = []
    for wheel, mount in enumerate(_wheel_mount_rows()):
        row = [0.0] * 7
        row[0:3] = mount
        row[3 + wheel] = -1.0
        rows.append(tuple(row))
    return tuple(rows)


def _stiffness_matrix() -> tuple[tuple[float, ...], ...]:
    rows = _spring_rows()
    ks = PARAMETERS["suspension_stiffness_n_per_m"]
    kt = PARAMETERS["tire_stiffness_n_per_m"]
    result = [[0.0] * 7 for _ in range(7)]
    for row in rows:
        for i in range(7):
            for j in range(7):
                result[i][j] += ks * row[i] * row[j]
    for wheel in range(4):
        result[3 + wheel][3 + wheel] += kt
    return tuple(tuple(row) for row in result)


def _damping_matrix(damping_n_s_per_m: float) -> tuple[tuple[float, ...], ...]:
    rows = _spring_rows()
    result = [[0.0] * 7 for _ in range(7)]
    for row in rows:
        for i in range(7):
            for j in range(7):
                result[i][j] += damping_n_s_per_m * row[i] * row[j]
    return tuple(tuple(row) for row in result)


def _mass_diagonal() -> tuple[float, ...]:
    return (
        PARAMETERS["sprung_mass_kg"],
        PARAMETERS["roll_inertia_kg_m2"],
        PARAMETERS["pitch_inertia_kg_m2"],
        PARAMETERS["unsprung_mass_kg"],
        PARAMETERS["unsprung_mass_kg"],
        PARAMETERS["unsprung_mass_kg"],
        PARAMETERS["unsprung_mass_kg"],
    )


def _system_matrix(damping_n_s_per_m: float) -> tuple[tuple[float, ...], ...]:
    stiffness = _stiffness_matrix()
    damping = _damping_matrix(damping_n_s_per_m)
    mass = _mass_diagonal()
    matrix = [[0.0] * 14 for _ in range(14)]
    for i in range(7):
        matrix[i][7 + i] = 1.0
        for j in range(7):
            matrix[7 + i][j] = -stiffness[i][j] / mass[i]
            matrix[7 + i][7 + j] = -damping[i][j] / mass[i]
    return tuple(tuple(row) for row in matrix)


def _equilibrium_state() -> tuple[float, ...]:
    sprung_mass = PARAMETERS["sprung_mass_kg"]
    unsprung_mass = PARAMETERS["unsprung_mass_kg"]
    gravity = PARAMETERS["gravity_m_per_s2"]
    suspension_stiffness = PARAMETERS["suspension_stiffness_n_per_m"]
    tire_stiffness = PARAMETERS["tire_stiffness_n_per_m"]
    rest_length = PARAMETERS["suspension_rest_length_m"]
    tire_radius = PARAMETERS["tire_radius_m"]
    tire_sag = (sprung_mass / 4.0 + unsprung_mass) * gravity / tire_stiffness
    hub_height = tire_radius - tire_sag
    body_height = hub_height + rest_length - sprung_mass * gravity / (4.0 * suspension_stiffness)
    return (body_height, 0.0, 0.0, hub_height, hub_height, hub_height, hub_height, *(0.0 for _ in range(7)))


def _equilibrium_force_residual() -> dict[str, object]:
    state = _equilibrium_state()
    rows = _wheel_mount_rows()
    ks = PARAMETERS["suspension_stiffness_n_per_m"]
    kt = PARAMETERS["tire_stiffness_n_per_m"]
    g = PARAMETERS["gravity_m_per_s2"]
    rest_length = PARAMETERS["suspension_rest_length_m"]
    tire_radius = PARAMETERS["tire_radius_m"]
    spring_forces: list[float] = []
    tire_forces: list[float] = []
    for wheel in range(4):
        mount_height = math.fsum(rows[wheel][axis] * state[axis] for axis in range(3))
        compression = rest_length - mount_height + state[3 + wheel]
        spring_forces.append(ks * compression)
        tire_forces.append(kt * (tire_radius - state[3 + wheel]))
    mu = PARAMETERS["unsprung_mass_kg"]
    hub_residuals = [tire_forces[i] - spring_forces[i] - mu * g for i in range(4)]
    body_roll = math.fsum(rows[i][1] * spring_forces[i] for i in range(4))
    body_pitch = math.fsum(rows[i][2] * spring_forces[i] for i in range(4))
    body_vertical = math.fsum(spring_forces) - PARAMETERS["sprung_mass_kg"] * g
    return {
        "body_vertical_force_n": body_vertical,
        "body_roll_moment_nm": body_roll,
        "body_pitch_moment_nm": body_pitch,
        "hub_vertical_force_by_corner_n": {name: value for name, value in zip(WHEEL_NAMES, hub_residuals, strict=True)},
    }


def _initial_delta() -> tuple[float, ...]:
    return tuple(INITIAL_POSITION_PERTURBATION) + (0.0,) * 7


def _initial_state() -> tuple[float, ...]:
    equilibrium = _equilibrium_state()
    delta = _initial_delta()
    return tuple(a + b for a, b in zip(equilibrium, delta, strict=True))


def _energy(delta: Sequence[float]) -> float:
    """Perturbation energy about the flat, symmetric equilibrium."""
    q = delta[:7]
    velocity = delta[7:]
    kinetic = 0.5 * math.fsum(mass * speed * speed for mass, speed in zip(_mass_diagonal(), velocity, strict=True))
    spring_stiffness = PARAMETERS["suspension_stiffness_n_per_m"]
    tire_stiffness = PARAMETERS["tire_stiffness_n_per_m"]
    spring_strain = [math.fsum(c * value for c, value in zip(row, q, strict=True)) for row in _spring_rows()]
    spring_energy = 0.5 * spring_stiffness * math.fsum(value * value for value in spring_strain)
    tire_energy = 0.5 * tire_stiffness * math.fsum(q[3 + wheel] ** 2 for wheel in range(4))
    return kinetic + spring_energy + tire_energy


def _sample_state(
    matrix: tuple[tuple[float, ...], ...], delta: Sequence[float], time_s: float
) -> tuple[tuple[float, ...], dict[str, int | float]]:
    transition, diagnostics = _matrix_exponential(_scale(matrix, time_s))
    return _matvec(transition, delta), diagnostics


def _contact_diagnostics(
    matrix: tuple[tuple[float, ...], ...],
    initial_delta: Sequence[float],
    equilibrium: Sequence[float],
) -> dict[str, object]:
    duration_s = max(SAMPLE_TIMES_S)
    dt = duration_s / float(DENSE_SAMPLE_COUNT - 1)
    step, _ = _matrix_exponential(_scale(matrix, dt))
    delta = tuple(initial_delta)
    minima = [math.inf] * 4
    for index in range(DENSE_SAMPLE_COUNT):
        for wheel in range(4):
            hub_z = equilibrium[3 + wheel] + delta[3 + wheel]
            load = PARAMETERS["tire_stiffness_n_per_m"] * (PARAMETERS["tire_radius_m"] - hub_z)
            minima[wheel] = min(minima[wheel], load)
        if index + 1 < DENSE_SAMPLE_COUNT:
            delta = _matvec(step, delta)
    return {
        "dense_sample_count_including_initial": DENSE_SAMPLE_COUNT,
        "dense_sample_interval_s": dt,
        "minimum_tire_normal_load_by_corner_n": {name: value for name, value in zip(WHEEL_NAMES, minima, strict=True)},
        "minimum_tire_normal_load_n": min(minima),
    }


def _case(damping_n_s_per_m: float, equilibrium: Sequence[float], initial_delta: Sequence[float]) -> tuple[dict[str, object], dict[str, float | int]]:
    matrix = _system_matrix(damping_n_s_per_m)
    samples: list[dict[str, object]] = []
    max_semigroup_absolute = 0.0
    max_semigroup_relative = 0.0
    max_squarings = 0
    max_terms = 0
    max_final_term = 0.0
    for time_s in SAMPLE_TIMES_S:
        delta_at_time, diagnostics = _sample_state(matrix, initial_delta, time_s)
        state = tuple(a + b for a, b in zip(equilibrium, delta_at_time, strict=True))
        samples.append({"time_s": time_s, "state": list(state)})

        whole, _ = _matrix_exponential(_scale(matrix, time_s))
        third, _ = _matrix_exponential(_scale(matrix, time_s / 3.0))
        composed = _multiply(_multiply(third, third), third)
        residual = _add(whole, _scale(composed, -1.0))
        absolute_residual = _max_abs_matrix(residual)
        max_semigroup_absolute = max(max_semigroup_absolute, absolute_residual)
        max_semigroup_relative = max(max_semigroup_relative, absolute_residual / max(1.0, _max_abs_matrix(whole)))
        max_squarings = max(max_squarings, int(diagnostics["scaling_squarings"]))
        max_terms = max(max_terms, int(diagnostics["taylor_terms"]))
        max_final_term = max(max_final_term, float(diagnostics["final_taylor_term_norm_inf"]))

    return {
        "suspension_damping_n_s_per_m": damping_n_s_per_m,
        "state_matrix_row_major": [list(row) for row in matrix],
        "samples": samples,
    }, {
        "max_thirds_semigroup_matrix_residual_abs": max_semigroup_absolute,
        "max_thirds_semigroup_matrix_residual_relative": max_semigroup_relative,
        "max_scaling_squarings": max_squarings,
        "max_taylor_terms": max_terms,
        "max_final_taylor_term_norm_inf": max_final_term,
    }


def build_fixture() -> dict[str, object]:
    equilibrium = _equilibrium_state()
    initial_delta = _initial_delta()
    case_data: dict[str, object] = {}
    case_diagnostics: dict[str, dict[str, float | int]] = {}
    for name, damping in (("damped", PARAMETERS["suspension_damping_n_s_per_m"]), ("undamped", 0.0)):
        case_data[name], case_diagnostics[name] = _case(damping, equilibrium, initial_delta)

    contact_checks = {
        "damped": _contact_diagnostics(_system_matrix(PARAMETERS["suspension_damping_n_s_per_m"]), initial_delta, equilibrium),
        "undamped": _contact_diagnostics(_system_matrix(0.0), initial_delta, equilibrium),
    }
    undamped_matrix = _system_matrix(0.0)
    energy_step, _ = _matrix_exponential(_scale(undamped_matrix, max(SAMPLE_TIMES_S) / (DENSE_SAMPLE_COUNT - 1)))
    delta = initial_delta
    energy_initial = _energy(delta)
    max_energy_absolute_drift = 0.0
    max_energy_relative_drift = 0.0
    for index in range(DENSE_SAMPLE_COUNT):
        error = abs(_energy(delta) - energy_initial)
        max_energy_absolute_drift = max(max_energy_absolute_drift, error)
        max_energy_relative_drift = max(max_energy_relative_drift, error / energy_initial)
        if index + 1 < DENSE_SAMPLE_COUNT:
            delta = _matvec(energy_step, delta)

    minimum_contact = min(float(check["minimum_tire_normal_load_n"]) for check in contact_checks.values())
    equilibrium_residual = _equilibrium_force_residual()
    equilibrium_magnitudes = [
        abs(float(equilibrium_residual["body_vertical_force_n"])),
        abs(float(equilibrium_residual["body_roll_moment_nm"])),
        abs(float(equilibrium_residual["body_pitch_moment_nm"])),
        *(abs(float(value)) for value in equilibrium_residual["hub_vertical_force_by_corner_n"].values()),
    ]
    max_equilibrium_residual = max(equilibrium_magnitudes)
    max_semigroup_relative = max(
        float(case_diagnostics["damped"]["max_thirds_semigroup_matrix_residual_relative"]),
        float(case_diagnostics["undamped"]["max_thirds_semigroup_matrix_residual_relative"]),
    )
    if minimum_contact <= 0.0:
        raise ArithmeticError(f"linear support oracle loses contact: minimum tire load is {minimum_contact:.17g} N")
    if max_equilibrium_residual > 1.0e-11:
        raise ArithmeticError(f"flat symmetric equilibrium residual is too large: {max_equilibrium_residual:.17g}")
    if max_semigroup_relative > 5.0e-11:
        raise ArithmeticError(f"matrix exponential relative semigroup residual is too large: {max_semigroup_relative:.17g}")
    if max_energy_relative_drift > 5.0e-10:
        raise ArithmeticError(f"undamped energy drift is too large: {max_energy_relative_drift:.17g}")

    return {
        "schema_version": 1,
        "generator": "research/rc-monster-truck/generate_support_reference.py",
        "purpose": "synthetic linear four-corner 7-DOF software reference; not physical validation",
        "method": {
            "equations": "M qddot + D qdot + K q = 0 for displacement from static equilibrium",
            "generalized_position_order": list(POSITION_STATE_ORDER),
            "body_mount_height": "z_body + y*roll - x*pitch, with x forward and y left",
            "spring_rows": "C=[B,-I4], B=[1,y,-x] in FL,FR,RL,RR order",
            "stiffness": "K = ks*C^T*C + kt*diag(0,0,0,1,1,1,1)",
            "damping": "D = c*C^T*C",
            "mass_matrix": "diagonal [Ms,Iroll,Ipitch,mu,mu,mu,mu]",
            "matrix_exponential": "scaled Taylor series with infinity-norm scaling to <=0.5, followed by repeated squaring",
            "time_integration": "none; each requested state is exp(A*t) times initial displacement",
            "contact_model": "linear tire spring; fixture accepted only while all dense-sampled tire normal loads remain positive",
            "unsprung_mass_scope": "unsprung_mass_kg is per wheel",
            "coordinate_signs": "upward-positive z; positive roll raises left mounts; positive pitch lowers forward mounts",
        },
        "position_state_order": list(POSITION_STATE_ORDER),
        "position_state_units": list(POSITION_STATE_UNITS),
        "rate_state_order": list(RATE_STATE_ORDER),
        "rate_state_units": list(RATE_STATE_UNITS),
        "state_order": list(STATE_ORDER),
        "state_units": list(STATE_UNITS),
        "parameters": PARAMETERS,
        "wheel_order": list(WHEEL_NAMES),
        "wheel_mount_rows_body": [list(row) for row in _wheel_mount_rows()],
        "spring_rows_C": [list(row) for row in _spring_rows()],
        "equilibrium_state": list(equilibrium),
        "initial_position_perturbation": list(INITIAL_POSITION_PERTURBATION),
        "initial_state": list(_initial_state()),
        "sample_times_s": list(SAMPLE_TIMES_S),
        "cases": case_data,
        "verification": {
            "flat_equilibrium_force_residual": equilibrium_residual,
            "maximum_flat_equilibrium_residual_abs_n_or_nm": max_equilibrium_residual,
            "dense_contact_checks": contact_checks,
            "minimum_tire_normal_load_n": minimum_contact,
            "maximum_undamped_energy_absolute_drift_j": max_energy_absolute_drift,
            "maximum_undamped_energy_relative_drift": max_energy_relative_drift,
            "maximum_thirds_semigroup_matrix_residual_relative": max_semigroup_relative,
            "cases": case_diagnostics,
            "acceptance_limits": {
                "minimum_tire_normal_load_n_exclusive_lower_bound": 0.0,
                "maximum_flat_equilibrium_residual_abs_n_or_nm": 1.0e-11,
                "maximum_thirds_semigroup_matrix_residual_relative": 5.0e-11,
                "maximum_undamped_energy_relative_drift": 5.0e-10,
            },
        },
    }


def render_fixture(fixture: dict[str, object]) -> bytes:
    return (json.dumps(fixture, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")


def _repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _fixture_path() -> Path:
    return _repository_root() / "research" / "rc-monster-truck" / "fixtures" / "support_reference.json"


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the committed fixture differs from generated bytes")
    args = parser.parse_args(argv)
    fixture_path = _fixture_path()
    fixture = build_fixture()
    generated = render_fixture(fixture)
    if args.check:
        if not fixture_path.is_file():
            print(f"missing generated fixture: {fixture_path}", file=sys.stderr)
            return 1
        actual = fixture_path.read_bytes()
        if actual != generated:
            expected_lines = generated.decode("utf-8").splitlines(keepends=True)
            actual_lines = actual.decode("utf-8", errors="replace").splitlines(keepends=True)
            sys.stderr.writelines(difflib.unified_diff(actual_lines, expected_lines, fromfile=str(fixture_path), tofile="generated"))
            print("fixture is stale; run generate_support_reference.py", file=sys.stderr)
            return 1
        print(
            "oracle checks passed: "
            f"relative thirds-semigroup residual <= {fixture['verification']['maximum_thirds_semigroup_matrix_residual_relative']:.3e}; "
            f"undamped energy drift <= {fixture['verification']['maximum_undamped_energy_relative_drift']:.3e}; "
            f"minimum tire load {fixture['verification']['minimum_tire_normal_load_n']:.6f} N"
        )
        print(f"fixture is current: {fixture_path}")
        return 0

    fixture_path.parent.mkdir(parents=True, exist_ok=True)
    fixture_path.write_bytes(generated)
    print(
        "oracle checks passed: "
        f"relative thirds-semigroup residual <= {fixture['verification']['maximum_thirds_semigroup_matrix_residual_relative']:.3e}; "
        f"undamped energy drift <= {fixture['verification']['maximum_undamped_energy_relative_drift']:.3e}; "
        f"minimum tire load {fixture['verification']['minimum_tire_normal_load_n']:.6f} N"
    )
    print(f"wrote fixture: {fixture_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
