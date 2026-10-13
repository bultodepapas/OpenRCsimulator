#!/usr/bin/env python3
"""Generate an independent, deterministic linear quarter-car reference.

This is a synthetic numerical oracle, not a measured or physically validated
RC truck model.  The state is ``[zs, zu, vs, vu]`` with upward-positive
positions.  Static equilibrium is computed first, then the homogeneous
displacement equation ``xdot = A x`` is propagated with a scaled Taylor
matrix exponential and squaring.  No time-step integration scheme is used.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Iterable, Sequence


Matrix = tuple[tuple[float, ...], ...]
Vector = tuple[float, ...]

PARAMETERS = {
    "sprung_mass_kg": 1.2,
    "unsprung_mass_kg": 0.18,
    "suspension_stiffness_n_per_m": 900.0,
    "suspension_damping_n_s_per_m": 7.0,
    "tire_stiffness_n_per_m": 6500.0,
    "gravity_m_per_s2": 9.80665,
    "suspension_rest_length_m": 0.10,
    "tire_radius_m": 0.085,
}
SAMPLE_TIMES_S = (0.05, 0.1, 0.25, 0.5, 1.0)
INITIAL_PERTURBATION = {
    "z_s_m": 0.001,
    "z_u_m": 0.0002,
    "v_s_m_per_s": 0.0,
    "v_u_m_per_s": 0.0,
}
STATE_ORDER = ("z_s_m", "z_u_m", "v_s_m_per_s", "v_u_m_per_s")
DENSE_SAMPLE_COUNT = 5001
TAYLOR_NORM_LIMIT = 0.5
TAYLOR_TERM_TOLERANCE = 1.0e-17
MAX_TAYLOR_TERMS = 100


def _identity(size: int = 4) -> Matrix:
    return tuple(tuple(1.0 if row == col else 0.0 for col in range(size)) for row in range(size))


def _add(left: Matrix, right: Matrix) -> Matrix:
    return tuple(tuple(left[i][j] + right[i][j] for j in range(len(left))) for i in range(len(left)))


def _scale(matrix: Matrix, scalar: float) -> Matrix:
    return tuple(tuple(scalar * value for value in row) for row in matrix)


def _multiply(left: Matrix, right: Matrix) -> Matrix:
    size = len(left)
    return tuple(
        tuple(math.fsum(left[row][k] * right[k][col] for k in range(size)) for col in range(size))
        for row in range(size)
    )


def _matvec(matrix: Matrix, vector: Sequence[float]) -> Vector:
    return tuple(math.fsum(matrix[row][col] * vector[col] for col in range(len(vector))) for row in range(len(matrix)))


def _norm_inf(matrix: Matrix) -> float:
    return max(math.fsum(abs(value) for value in row) for row in matrix)


def _max_abs_matrix(matrix: Matrix) -> float:
    return max(abs(value) for row in matrix for value in row)


def matrix_exponential(matrix: Matrix) -> tuple[Matrix, dict[str, int | float]]:
    """Return exp(matrix) by scaling, Taylor expansion, then repeated squaring.

    The infinity norm is scaled to at most 0.5, where the Taylor series
    converges quickly.  The reported final term is an internal truncation
    diagnostic; the fixture also records semigroup residuals as an independent
    consistency check for the propagation.
    """
    norm = _norm_inf(matrix)
    if norm == 0.0:
        return _identity(), {"scaling_squarings": 0, "taylor_terms": 0, "final_taylor_term_norm_inf": 0.0}

    squarings = max(0, math.ceil(math.log2(norm / TAYLOR_NORM_LIMIT)))
    reduced = _scale(matrix, math.ldexp(1.0, -squarings))
    term = _identity()
    result = _identity()
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


def _system_matrix(damping_n_s_per_m: float) -> Matrix:
    ms = PARAMETERS["sprung_mass_kg"]
    mu = PARAMETERS["unsprung_mass_kg"]
    ks = PARAMETERS["suspension_stiffness_n_per_m"]
    kt = PARAMETERS["tire_stiffness_n_per_m"]
    c = damping_n_s_per_m
    return (
        (0.0, 0.0, 1.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
        (-ks / ms, ks / ms, -c / ms, c / ms),
        (ks / mu, -(ks + kt) / mu, c / mu, -c / mu),
    )


def _equilibrium() -> dict[str, float]:
    ms = PARAMETERS["sprung_mass_kg"]
    mu = PARAMETERS["unsprung_mass_kg"]
    ks = PARAMETERS["suspension_stiffness_n_per_m"]
    kt = PARAMETERS["tire_stiffness_n_per_m"]
    g = PARAMETERS["gravity_m_per_s2"]
    rest_length = PARAMETERS["suspension_rest_length_m"]
    tire_radius = PARAMETERS["tire_radius_m"]

    # Tire deflection carries both masses; suspension compression carries ms.
    zu = tire_radius - (ms + mu) * g / kt
    zs = zu + rest_length - ms * g / ks
    return {"z_s_m": zs, "z_u_m": zu}


def _initial_state(equilibrium: dict[str, float]) -> Vector:
    return (
        equilibrium["z_s_m"] + INITIAL_PERTURBATION["z_s_m"],
        equilibrium["z_u_m"] + INITIAL_PERTURBATION["z_u_m"],
        INITIAL_PERTURBATION["v_s_m_per_s"],
        INITIAL_PERTURBATION["v_u_m_per_s"],
    )


def _equilibrium_vector(equilibrium: dict[str, float]) -> Vector:
    return (equilibrium["z_s_m"], equilibrium["z_u_m"], 0.0, 0.0)


def _perturbation_vector() -> Vector:
    return (
        INITIAL_PERTURBATION["z_s_m"],
        INITIAL_PERTURBATION["z_u_m"],
        INITIAL_PERTURBATION["v_s_m_per_s"],
        INITIAL_PERTURBATION["v_u_m_per_s"],
    )


def _propagate(matrix: Matrix, initial_delta: Vector, time_s: float) -> tuple[Vector, dict[str, int | float]]:
    transition, diagnostics = matrix_exponential(_scale(matrix, time_s))
    return _matvec(transition, initial_delta), diagnostics


def _state_dict(state: Sequence[float]) -> dict[str, float]:
    return {name: value for name, value in zip(STATE_ORDER, state, strict=True)}


def _energy(state_delta: Sequence[float]) -> float:
    """Perturbation energy around static equilibrium for the undamped model."""
    ms = PARAMETERS["sprung_mass_kg"]
    mu = PARAMETERS["unsprung_mass_kg"]
    ks = PARAMETERS["suspension_stiffness_n_per_m"]
    kt = PARAMETERS["tire_stiffness_n_per_m"]
    ds, du, vs, vu = state_delta
    return 0.5 * ms * vs * vs + 0.5 * mu * vu * vu + 0.5 * ks * (ds - du) ** 2 + 0.5 * kt * du * du


def _dense_diagnostics(
    matrix: Matrix,
    initial_delta: Vector,
    equilibrium: dict[str, float],
    check_undamped_energy: bool,
) -> dict[str, float | int]:
    duration_s = max(SAMPLE_TIMES_S)
    intervals = DENSE_SAMPLE_COUNT - 1
    dt = duration_s / intervals
    step, _ = matrix_exponential(_scale(matrix, dt))
    delta = initial_delta
    min_tire_load = math.inf
    initial_energy = _energy(delta) if check_undamped_energy else 0.0
    max_energy_error = 0.0
    max_energy_relative_error = 0.0
    for index in range(DENSE_SAMPLE_COUNT):
        unsprung_z = equilibrium["z_u_m"] + delta[1]
        tire_load = PARAMETERS["tire_stiffness_n_per_m"] * (PARAMETERS["tire_radius_m"] - unsprung_z)
        min_tire_load = min(min_tire_load, tire_load)
        if check_undamped_energy:
            current_energy = _energy(delta)
            error = abs(current_energy - initial_energy)
            max_energy_error = max(max_energy_error, error)
            max_energy_relative_error = max(max_energy_relative_error, error / initial_energy)
        if index + 1 < DENSE_SAMPLE_COUNT:
            delta = _matvec(step, delta)
    result: dict[str, float | int] = {
        "dense_sample_count_including_initial": DENSE_SAMPLE_COUNT,
        "dense_sample_interval_s": dt,
        "minimum_tire_normal_load_n": min_tire_load,
        "minimum_contact_margin_n": min_tire_load,
    }
    if check_undamped_energy:
        result["maximum_undamped_energy_absolute_drift_j"] = max_energy_error
        result["maximum_undamped_energy_relative_drift"] = max_energy_relative_error
    return result


def _case(damping_n_s_per_m: float, equilibrium: dict[str, float], initial_delta: Vector) -> tuple[dict[str, object], dict[str, float]]:
    matrix = _system_matrix(damping_n_s_per_m)
    samples: list[dict[str, object]] = []
    max_semigroup_residual = 0.0
    max_semigroup_relative_residual = 0.0
    max_half_step_residual = 0.0
    max_scalings = 0
    max_taylor_terms = 0
    max_final_taylor_term = 0.0
    for time_s in SAMPLE_TIMES_S:
        delta, diag = _propagate(matrix, initial_delta, time_s)
        absolute_state = tuple(a + b for a, b in zip(_equilibrium_vector(equilibrium), delta, strict=True))
        samples.append({"time_s": time_s, "state": _state_dict(absolute_state)})

        whole, _ = matrix_exponential(_scale(matrix, time_s))
        third, _ = matrix_exponential(_scale(matrix, time_s / 3.0))
        thirds_composed = _multiply(_multiply(third, third), third)
        max_semigroup_residual = max(
            max_semigroup_residual,
            _max_abs_matrix(_add(whole, _scale(thirds_composed, -1.0))),
        )
        whole_norm = max(1.0, _max_abs_matrix(whole))
        max_semigroup_relative_residual = max(
            max_semigroup_relative_residual,
            _max_abs_matrix(_add(whole, _scale(thirds_composed, -1.0))) / whole_norm,
        )
        half, _ = matrix_exponential(_scale(matrix, time_s / 2.0))
        halves_composed = _multiply(half, half)
        max_half_step_residual = max(
            max_half_step_residual,
            _max_abs_matrix(_add(whole, _scale(halves_composed, -1.0))),
        )
        max_scalings = max(max_scalings, int(diag["scaling_squarings"]))
        max_taylor_terms = max(max_taylor_terms, int(diag["taylor_terms"]))
        max_final_taylor_term = max(max_final_taylor_term, float(diag["final_taylor_term_norm_inf"]))

    diagnostics = {
        "max_thirds_semigroup_matrix_residual_abs": max_semigroup_residual,
        "max_thirds_semigroup_matrix_residual_relative": max_semigroup_relative_residual,
        "max_halves_semigroup_matrix_residual_abs": max_half_step_residual,
        "max_scaling_squarings": max_scalings,
        "max_taylor_terms": max_taylor_terms,
        "max_final_taylor_term_norm_inf": max_final_taylor_term,
    }
    return {
        "suspension_damping_n_s_per_m": damping_n_s_per_m,
        "state_matrix_row_major": [list(row) for row in matrix],
        "samples": samples,
    }, diagnostics


def build_fixture() -> dict[str, object]:
    equilibrium = _equilibrium()
    initial_delta = _perturbation_vector()
    initial_state = _initial_state(equilibrium)
    case_results: dict[str, object] = {}
    case_diagnostics: dict[str, dict[str, float | int]] = {}
    for name, damping in (("damped", PARAMETERS["suspension_damping_n_s_per_m"]), ("undamped", 0.0)):
        result, diagnostics = _case(damping, equilibrium, initial_delta)
        case_results[name] = result
        case_diagnostics[name] = diagnostics

    dense_diagnostics = {
        "damped": _dense_diagnostics(
            _system_matrix(PARAMETERS["suspension_damping_n_s_per_m"]), initial_delta, equilibrium, False
        ),
        "undamped": _dense_diagnostics(_system_matrix(0.0), initial_delta, equilibrium, True),
    }
    undamped_energy_rel = float(dense_diagnostics["undamped"]["maximum_undamped_energy_relative_drift"])
    contact_floor = min(float(case["minimum_tire_normal_load_n"]) for case in dense_diagnostics.values())
    max_semigroup_residual_abs = max(
        float(case_diagnostics["damped"]["max_thirds_semigroup_matrix_residual_abs"]),
        float(case_diagnostics["undamped"]["max_thirds_semigroup_matrix_residual_abs"]),
    )
    max_semigroup_residual_relative = max(
        float(case_diagnostics["damped"]["max_thirds_semigroup_matrix_residual_relative"]),
        float(case_diagnostics["undamped"]["max_thirds_semigroup_matrix_residual_relative"]),
    )
    if contact_floor <= 0.0:
        raise ArithmeticError(f"linear oracle loses tire contact: minimum normal load is {contact_floor:.17g} N")
    if max_semigroup_residual_relative > 2.0e-11:
        raise ArithmeticError(f"matrix exponential relative semigroup residual is too large: {max_semigroup_residual_relative:.17g}")
    if undamped_energy_rel > 5.0e-10:
        raise ArithmeticError(f"undamped energy drift is too large: {undamped_energy_rel:.17g}")

    return {
        "schema_version": 1,
        "generator": "research/rc-monster-truck/generate_suspension_reference.py",
        "purpose": "synthetic linear quarter-car software reference; not physical validation",
        "method": {
            "equations": "xdot = A x for displacement from static equilibrium; x=[zs, zu, vs, vu]",
            "matrix_exponential": "scaled Taylor series with infinity-norm scaling to <=0.5, followed by repeated squaring",
            "taylor_term_relative_tolerance": TAYLOR_TERM_TOLERANCE,
            "scaled_matrix_infinity_norm_limit": TAYLOR_NORM_LIMIT,
            "time_integration": "none; each requested state is exp(A*t) times the initial displacement",
            "state_position_sign": "upward-positive",
        },
        "state_order": list(STATE_ORDER),
        "state_units": {
            "z_s_m": "m",
            "z_u_m": "m",
            "v_s_m_per_s": "m/s",
            "v_u_m_per_s": "m/s",
        },
        "parameters": PARAMETERS,
        "equilibrium": equilibrium,
        "initial_perturbation": INITIAL_PERTURBATION,
        "initial_state": _state_dict(initial_state),
        "sample_times_s": list(SAMPLE_TIMES_S),
        "cases": case_results,
        "verification": {
            "dense_contact_and_energy_check_case": "undamped",
            "dense_contact_checks": dense_diagnostics,
            "minimum_tire_normal_load_n": contact_floor,
            "minimum_contact_margin_n": contact_floor,
            "maximum_undamped_energy_absolute_drift_j": dense_diagnostics["undamped"]["maximum_undamped_energy_absolute_drift_j"],
            "maximum_undamped_energy_relative_drift": dense_diagnostics["undamped"]["maximum_undamped_energy_relative_drift"],
            "maximum_thirds_semigroup_matrix_residual_abs": max_semigroup_residual_abs,
            "maximum_thirds_semigroup_matrix_residual_relative": max_semigroup_residual_relative,
            "cases": case_diagnostics,
            "acceptance_limits": {
                "minimum_tire_normal_load_n_exclusive_lower_bound": 0.0,
                "maximum_thirds_semigroup_matrix_residual_relative": 2.0e-11,
                "maximum_undamped_energy_relative_drift": 5.0e-10,
            },
        },
    }


def render_fixture(fixture: dict[str, object]) -> bytes:
    return (json.dumps(fixture, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")


def _repository_root() -> Path:
    # This script is <repo>/research/rc-monster-truck/generate_suspension_reference.py.
    return Path(__file__).resolve().parents[2]


def _fixture_path() -> Path:
    return _repository_root() / "research" / "rc-monster-truck" / "fixtures" / "suspension_reference.json"


def _print_check_summary(fixture: dict[str, object]) -> None:
    verification = fixture["verification"]
    assert isinstance(verification, dict)
    print(
        "oracle checks passed: "
        f"relative thirds-semigroup residual <= {verification['maximum_thirds_semigroup_matrix_residual_relative']:.3e}; "
        f"undamped energy drift <= {verification['maximum_undamped_energy_relative_drift']:.3e}; "
        f"minimum tire load {verification['minimum_tire_normal_load_n']:.6f} N"
    )


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
            import difflib

            diff = difflib.unified_diff(actual_lines, expected_lines, fromfile=str(fixture_path), tofile="generated")
            sys.stderr.writelines(diff)
            print("fixture is stale; run generate_suspension_reference.py", file=sys.stderr)
            return 1
        _print_check_summary(fixture)
        print(f"fixture is current: {fixture_path}")
        return 0

    fixture_path.parent.mkdir(parents=True, exist_ok=True)
    fixture_path.write_bytes(generated)
    fixture = json.loads(generated)
    _print_check_summary(fixture)
    print(f"wrote fixture: {fixture_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
