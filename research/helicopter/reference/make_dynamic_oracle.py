"""Build/check the compact transient-inflow reference oracle (stdlib only)."""

from __future__ import annotations

import argparse
import difflib
import json
import math
from pathlib import Path
import sys
from typing import Any

from dynamic_inflow import derivative, evaluate, lag_time_constant
from johnson_inflow import target as steady_target


HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "dynamic_oracle.json"
BASE_TICK_S = 1.0 / 240.0
DURATION_S = 32.0 * BASE_TICK_S
SAMPLE_STRIDE_TICKS = 2
SAMPLE_COUNT = 17
DENSE_STEP_S = 1.0e-5
ERROR_TOLERANCE_MPS = 1.0e-3
_PI = math.pi


def _hover_speed(thrust_n: float, density_kg_m3: float, radius_m: float) -> float:
    if thrust_n == 0.0:
        return 0.0
    return math.sqrt(abs(thrust_n) / (2.0 * density_kg_m3 * _PI * radius_m**2))


def _controls_at(profile: dict[str, Any], time_s: float) -> dict[str, float]:
    kind = profile["interpolation"]
    if kind == "step":
        side = "before" if time_s < profile["step_time_s"] else "after"
        return {key: float(value) for key, value in profile[side].items()}
    if kind == "linear":
        start_s = float(profile["start_time_s"])
        end_s = float(profile["end_time_s"])
        if end_s <= start_s:
            raise ValueError("linear profile must have increasing time")
        fraction = min(1.0, max(0.0, (time_s - start_s) / (end_s - start_s)))
        start = profile["start"]
        end = profile["end"]
        return {
            key: float(start[key]) + (float(end[key]) - float(start[key])) * fraction
            for key in ("thrust_n", "climb_mps", "crossflow_mps")
        }
    raise ValueError(f"unknown profile interpolation: {kind}")


def _event_override(
    fixture: dict[str, Any], event: dict[str, Any], time_side: str
) -> dict[str, float]:
    """Return exact one-sided controls at a known forcing or source event."""
    if event.get("event_kind") == "forcing_step":
        return {
            key: float(value)
            for key, value in fixture["profile"][time_side].items()
        }
    controls = _controls_at(fixture["profile"], float(event["time_s"]))
    constants = fixture["constants"]
    hover = _hover_speed(
        controls["thrust_n"],
        float(constants["density_kg_m3"]),
        float(constants["radius_m"]),
    )
    increasing = event["direction"] == "increasing"
    before_sign = -1.0 if increasing else 1.0
    side_sign = before_sign if time_side == "before" else -before_sign
    normalized_crossflow = float(event["threshold_normalized"]) + (
        side_sign * float(event["epsilon_normalized"])
    )
    controls["crossflow_mps"] = hover * normalized_crossflow
    return controls


def _integration_events(fixture: dict[str, Any]) -> list[dict[str, Any]]:
    """Known integration events, including piecewise-constant profile steps."""
    events = list(fixture.get("event_splits", []))
    profile = fixture["profile"]
    if profile["interpolation"] == "step":
        events.append(
            {
                "time_s": float(profile["step_time_s"]),
                "event_kind": "forcing_step",
            }
        )
    return events


def _with_override(
    controls: dict[str, float], override: dict[str, float] | None
) -> dict[str, float]:
    if override is None:
        return controls
    return {**controls, **override}


def _rhs(
    fixture: dict[str, Any],
    time_s: float,
    vi_mps: float,
    override: dict[str, float] | None = None,
) -> tuple[float, float, float]:
    constants = fixture["constants"]
    controls = _with_override(_controls_at(fixture["profile"], time_s), override)
    result = evaluate(
        vi_mps,
        controls["thrust_n"],
        constants["density_kg_m3"],
        constants["radius_m"],
        controls["climb_mps"],
        controls["crossflow_mps"],
        constants["velocity_floor_mps"],
        height_over_radius=constants["height_over_radius"],
        loss=constants["loss"],
        instability=constants["instability"],
    )
    if not result["ok"]:
        raise ValueError(str(result.get("error", "dynamic inflow evaluation failed")))

    if constants["effective_flow_mode"] == "fixed":
        lag = derivative(
            vi_mps,
            float(result["target_mps"]),
            constants["radius_m"],
            constants["fixed_effective_speed_mps"],
            constants["velocity_floor_mps"],
        )
        if not lag["ok"]:
            raise ValueError(str(lag.get("error", "dynamic inflow derivative failed")))
        return (
            float(lag["rate_mps2"]),
            float(lag["tau_s"]),
            float(result["target_mps"]),
        )
    return (
        float(result["rate_mps2"]),
        float(result["tau_s"]),
        float(result["target_mps"]),
    )


def _rk4_step(
    fixture: dict[str, Any],
    time_s: float,
    vi_mps: float,
    step_s: float,
    start_override: dict[str, float] | None = None,
    end_override: dict[str, float] | None = None,
) -> float:
    k1 = _rhs(fixture, time_s, vi_mps, start_override)[0]
    k2 = _rhs(fixture, time_s + 0.5 * step_s, vi_mps + 0.5 * step_s * k1)[0]
    k3 = _rhs(fixture, time_s + 0.5 * step_s, vi_mps + 0.5 * step_s * k2)[0]
    k4 = _rhs(
        fixture,
        time_s + step_s,
        vi_mps + step_s * k3,
        end_override,
    )[0]
    return vi_mps + (step_s / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)


def rk4_trajectory(
    fixture: dict[str, Any],
    step_s: float,
    split_events: bool = False,
    local_quarters: bool = False,
) -> list[tuple[float, float]]:
    """Integrate at fixed output ticks, optionally splitting known seams.

    Event splitting is an oracle qualification method that is given the exact
    fixture crossing time. It does not model a runtime event detector.
    """
    duration_s = float(fixture["duration_s"])
    if step_s <= 0.0 or not math.isfinite(step_s):
        raise ValueError("step_s must be finite and positive")
    count = int(round(duration_s / step_s))
    if not math.isclose(count * step_s, duration_s, rel_tol=0.0, abs_tol=2.0e-13):
        raise ValueError("step_s must divide fixture duration")
    if local_quarters and not split_events:
        raise ValueError("local seam refinement requires known-event splitting")
    events = _integration_events(fixture) if split_events else []
    state = float(fixture["initial_vi_mps"])
    trajectory = [(0.0, state)]
    for index in range(count):
        start_s = index * step_s
        end_s = (index + 1) * step_s
        interior_events = [
            event for event in events
            if start_s < float(event["time_s"]) < end_s
        ]
        if len(interior_events) > 1:
            raise ValueError("at most one known event may fall inside a tick")

        if local_quarters and any(
            end_s >= float(event["time_s"]) - step_s - 1.0e-14
            and start_s <= float(event["time_s"]) + step_s + 1.0e-14
            for event in events
        ):
            if interior_events:
                event = interior_events[0]
                event_s = float(event["time_s"])
                boundaries = [
                    start_s,
                    start_s + 0.5 * (event_s - start_s),
                    event_s,
                    event_s + 0.5 * (end_s - event_s),
                    end_s,
                ]
            else:
                boundaries = [
                    start_s + (end_s - start_s) * substep / 4.0
                    for substep in range(5)
                ]
        elif interior_events:
            event_s = float(interior_events[0]["time_s"])
            boundaries = [start_s, event_s, end_s]
        else:
            boundaries = [start_s, end_s]

        for sub_start_s, sub_end_s in zip(boundaries, boundaries[1:]):
            start_event = next(
                (
                    event
                    for event in events
                    if math.isclose(
                        sub_start_s, float(event["time_s"]), rel_tol=0.0, abs_tol=1.0e-14
                    )
                ),
                None,
            )
            end_event = next(
                (
                    event
                    for event in events
                    if math.isclose(
                        sub_end_s, float(event["time_s"]), rel_tol=0.0, abs_tol=1.0e-14
                    )
                ),
                None,
            )
            state = _rk4_step(
                fixture,
                sub_start_s,
                state,
                sub_end_s - sub_start_s,
                start_override=(
                    _event_override(fixture, start_event, "after")
                    if start_event is not None
                    else None
                ),
                end_override=(
                    _event_override(fixture, end_event, "before")
                    if end_event is not None
                    else None
                ),
            )
        trajectory.append((end_s, state))
    return trajectory


def _analytic_target_step(
    fixture: dict[str, Any], sample_times: list[float]
) -> list[float]:
    profile = fixture["profile"]
    constants = fixture["constants"]
    switch_s = float(profile["step_time_s"])
    after = profile["after"]
    target_result = steady_target(
        after["thrust_n"],
        constants["density_kg_m3"],
        constants["radius_m"],
        after["climb_mps"],
        after["crossflow_mps"],
        height_over_radius=constants["height_over_radius"],
        loss=constants["loss"],
        instability=constants["instability"],
    )
    if not target_result["ok"]:
        raise ValueError(str(target_result.get("error", "target step failed")))
    target_mps = float(target_result["velocity"])
    tau_s = lag_time_constant(
        constants["radius_m"],
        constants["fixed_effective_speed_mps"],
        constants["velocity_floor_mps"],
    )
    initial = float(fixture["initial_vi_mps"])
    return [
        initial
        if time_s <= switch_s
        else target_mps + (initial - target_mps) * math.exp(-(time_s - switch_s) / tau_s)
        for time_s in sample_times
    ]


def dense_trajectory(
    fixture: dict[str, Any],
    sample_times: list[float],
    max_step_s: float = DENSE_STEP_S,
) -> list[float]:
    """Compute the independent dense midpoint/exponential-convolution path.

    Each microstep predicts the midpoint state, evaluates the target and lag
    there, then integrates the frozen-coefficient first-order equation exactly.
    Known target seams split a microstep at their supplied time. Constant-flow
    target steps use their closed-form exponential answer instead.
    """
    if fixture["kind"] == "target_step_exact":
        return _analytic_target_step(fixture, sample_times)
    if max_step_s <= 0.0 or not math.isfinite(max_step_s):
        raise ValueError("max_step_s must be finite and positive")

    events = _integration_events(fixture)
    state = float(fixture["initial_vi_mps"])
    time_s = 0.0
    outputs: list[float] = []
    for sample_s in sample_times:
        if sample_s < time_s - 1.0e-14:
            raise ValueError("sample_times must be increasing")
        while time_s < sample_s - 1.0e-14:
            next_event = next(
                (
                    float(event["time_s"])
                    for event in events
                    if time_s < float(event["time_s"]) < sample_s
                ),
                None,
            )
            step_s = min(max_step_s, sample_s - time_s)
            event_at_start = next(
                (
                    event
                    for event in events
                    if math.isclose(time_s, float(event["time_s"]), abs_tol=1.0e-14)
                ),
                None,
            )
            if next_event is not None:
                step_s = min(step_s, next_event - time_s)
            midpoint_s = time_s + 0.5 * step_s
            start_override = (
                _event_override(fixture, event_at_start, "after")
                if event_at_start is not None
                else None
            )
            start_rate = _rhs(fixture, time_s, state, start_override)[0]
            midpoint_state = state + 0.5 * step_s * start_rate
            midpoint_rate, tau_s, target_mps = _rhs(
                fixture, midpoint_s, midpoint_state
            )
            del midpoint_rate
            state = target_mps + (state - target_mps) * math.exp(-step_s / tau_s)
            time_s += step_s
            if abs(time_s - sample_s) <= 1.0e-13:
                time_s = sample_s
        outputs.append(state)
    return outputs


def _base_constants(
    *,
    instability: float,
    effective_flow_mode: str = "fixed",
    fixed_speed_mps: float = 4.0,
) -> dict[str, Any]:
    omega = 2.0 * _PI * 1595.0 / 60.0
    return {
        "density_kg_m3": 1.225,
        "radius_m": 0.7,
        "velocity_floor_mps": 0.25,
        "height_over_radius": -1.0,
        "loss": 1.0,
        "instability": instability,
        "omega_rad_s": omega,
        "effective_flow_mode": effective_flow_mode,
        "fixed_effective_speed_mps": fixed_speed_mps,
    }


def _target_at_controls(
    constants: dict[str, Any], controls: dict[str, float]
) -> tuple[float, float]:
    result = steady_target(
        controls["thrust_n"],
        constants["density_kg_m3"],
        constants["radius_m"],
        controls["climb_mps"],
        controls["crossflow_mps"],
        height_over_radius=constants["height_over_radius"],
        loss=constants["loss"],
        instability=constants["instability"],
    )
    if not result["ok"]:
        raise ValueError(str(result.get("error", "steady target failed")))
    return float(result["velocity"]), float(result["hover"])


def _seam_fixture(
    name: str,
    boundary_name: str,
    threshold: float,
    direction: str,
    crossing_s: float,
    slope_norm_per_s: float,
    z: float,
    instability: float,
    description: str,
) -> dict[str, Any]:
    constants = _base_constants(instability=instability)
    hover = _hover_speed(80.4, constants["density_kg_m3"], constants["radius_m"])
    start_norm = threshold + (
        -slope_norm_per_s * crossing_s
        if direction == "increasing"
        else slope_norm_per_s * crossing_s
    )
    end_norm = start_norm + (
        slope_norm_per_s * DURATION_S
        if direction == "increasing"
        else -slope_norm_per_s * DURATION_S
    )
    profile = {
        "interpolation": "linear",
        "start_time_s": 0.0,
        "end_time_s": DURATION_S,
        "start": {
            "thrust_n": 80.4,
            "climb_mps": z * hover,
            "crossflow_mps": start_norm * hover,
        },
        "end": {
            "thrust_n": 80.4,
            "climb_mps": z * hover,
            "crossflow_mps": end_norm * hover,
        },
    }
    event = {
        "time_s": crossing_s,
        "control": "crossflow_mps",
        "threshold_normalized": threshold,
        "boundary": boundary_name,
        "direction": direction,
        "epsilon_normalized": 1.0e-10,
    }
    fixture: dict[str, Any] = {
        "name": name,
        "kind": "source_seam_sweep",
        "description": description,
        "duration_s": DURATION_S,
        "constants": constants,
        "profile": profile,
        "event_splits": [event],
        "initial_vi_mps": 0.0,
    }
    fixture["initial_vi_mps"] = _target_at_controls(
        constants, _controls_at(profile, 0.0)
    )[0]
    return fixture


def build_fixtures() -> list[dict[str, Any]]:
    constants = _base_constants(instability=0.0)
    hover = _hover_speed(80.4, constants["density_kg_m3"], constants["radius_m"])
    fixtures: list[dict[str, Any]] = [
        {
            "name": "hover_target_step",
            "kind": "target_step_exact",
            "description": (
                "Hover target changes from zero thrust to 80.4 N at 17.3 ms; "
                "fixed effective flow gives the closed-form exponential wake buildup."
            ),
            "duration_s": DURATION_S,
            "constants": constants,
            "profile": {
                "interpolation": "step",
                "step_time_s": 0.0173,
                "before": {
                    "thrust_n": 0.0,
                    "climb_mps": 0.0,
                    "crossflow_mps": 0.0,
                },
                "after": {
                    "thrust_n": 80.4,
                    "climb_mps": 0.0,
                    "crossflow_mps": 0.0,
                },
            },
            "event_splits": [],
            "initial_vi_mps": 0.0,
        },
        _seam_fixture(
            "C_increasing",
            "C",
            0.75,
            "increasing",
            0.0373,
            0.8,
            -1.428,
            0.0,
            "Crossflow rises through the literal baseline cutoff C at z=-1.428, f=0.",
        ),
        _seam_fixture(
            "C_decreasing",
            "C",
            0.75,
            "decreasing",
            0.0373,
            0.8,
            -1.428,
            0.0,
            "Crossflow falls through the literal baseline cutoff C at z=-1.428, f=0.",
        ),
        _seam_fixture(
            "M_increasing",
            "M",
            0.95,
            "increasing",
            0.03873,
            0.5,
            -1.3,
            1.0,
            "Crossflow rises through the literal VRS cutoff M at z=-1.3, f=1.",
        ),
        _seam_fixture(
            "M_decreasing",
            "M",
            0.95,
            "decreasing",
            0.03873,
            0.5,
            -1.3,
            1.0,
            "Crossflow falls through the literal VRS cutoff M at z=-1.3, f=1.",
        ),
    ]

    feedback_constants = _base_constants(
        instability=0.6, effective_flow_mode="feedback", fixed_speed_mps=4.0
    )
    feedback_start = {
        "thrust_n": 80.4,
        "climb_mps": 0.0,
        "crossflow_mps": 1.5,
    }
    feedback_end = {
        "thrust_n": 80.4,
        "climb_mps": 1.0,
        "crossflow_mps": 2.8,
    }
    feedback_profile = {
        "interpolation": "linear",
        "start_time_s": 0.0,
        "end_time_s": DURATION_S,
        "start": feedback_start,
        "end": feedback_end,
    }
    feedback_fixture: dict[str, Any] = {
        "name": "feedback_flow_ramp",
        "kind": "feedback_flow_ramp",
        "description": (
            "Smooth climb/crossflow ramp exercises stage flow "
            "hypot(crossflow, vi + climb) in the lag time constant."
        ),
        "duration_s": DURATION_S,
        "constants": feedback_constants,
        "profile": feedback_profile,
        "event_splits": [],
        "initial_vi_mps": _target_at_controls(feedback_constants, feedback_start)[0],
    }
    fixtures.append(feedback_fixture)

    # Keep local names clear and assert the hover scale used by every normalized
    # source-seam profile is derived from its dimensional thrust definition.
    del hover
    return fixtures


def _event_target_values(fixture: dict[str, Any]) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    for event in _integration_events(fixture):
        left_controls = _event_override(fixture, event, "before")
        right_controls = _event_override(fixture, event, "after")
        left_target, _ = _target_at_controls(fixture["constants"], left_controls)
        right_target, _ = _target_at_controls(fixture["constants"], right_controls)
        entry = {
            "time_s": round(float(event["time_s"]), 12),
            "event_kind": event.get("event_kind", "steady_law_seam"),
            "left_limit_target_mps": round(left_target, 12),
            "right_limit_target_mps": round(right_target, 12),
        }
        if event.get("event_kind") == "forcing_step":
            entry["control"] = "profile_controls"
        else:
            entry.update(
                {
                    "control": event["control"],
                    "threshold_normalized": event["threshold_normalized"],
                    "epsilon_normalized": event["epsilon_normalized"],
                    "boundary": event["boundary"],
                    "direction": event["direction"],
                }
            )
        values.append(entry)
    return values


def _sample_times() -> list[float]:
    sample_stride_s = SAMPLE_STRIDE_TICKS * BASE_TICK_S
    return [index * sample_stride_s for index in range(SAMPLE_COUNT)]


def _round(value: float) -> float:
    return round(value, 12)


def _fixture_errors(fixture: dict[str, Any]) -> dict[str, dict[str, Any]]:
    dense_stride_s = BASE_TICK_S / 4.0
    count = int(round(float(fixture["duration_s"]) / dense_stride_s))
    dense_times = [index * dense_stride_s for index in range(count + 1)]
    dense_states = dense_trajectory(fixture, dense_times)
    result: dict[str, dict[str, Any]] = {}
    methods = (
        ("rk4_240hz_unsplit", BASE_TICK_S, 4, False),
        ("rk4_480hz_unsplit", BASE_TICK_S / 2.0, 2, False),
        ("rk4_960hz_unsplit", BASE_TICK_S / 4.0, 1, False),
        ("rk4_240hz_known_event_splits", BASE_TICK_S, 4, True),
        ("rk4_240hz_local_quarters", BASE_TICK_S, 4, True),
    )
    for name, step_s, stride, split in methods:
        trajectory = rk4_trajectory(
            fixture,
            step_s,
            split_events=split,
            local_quarters=name == "rk4_240hz_local_quarters",
        )
        errors = [
            abs(trajectory[index][1] - dense_states[index * stride])
            for index in range(len(trajectory))
        ]
        max_index = max(range(len(errors)), key=errors.__getitem__)
        result[name] = {
            "max_abs_error_mps": _round(errors[max_index]),
            "time_s": _round(trajectory[max_index][0]),
            "fixture": fixture["name"],
        }
    return result


def build_oracle() -> dict[str, Any]:
    fixtures = build_fixtures()
    sample_times = _sample_times()
    output_fixtures: list[dict[str, Any]] = []
    for fixture in fixtures:
        samples_vi = dense_trajectory(fixture, sample_times)
        omega_r = (
            fixture["constants"]["omega_rad_s"] * fixture["constants"]["radius_m"]
        )
        output_fixtures.append(
            {
                "name": fixture["name"],
                "kind": fixture["kind"],
                "description": fixture["description"],
                "duration_s": _round(fixture["duration_s"]),
                "constants": fixture["constants"],
                "initial_vi_mps": _round(fixture["initial_vi_mps"]),
                "profile": fixture["profile"],
                "event_splits": _event_target_values(fixture),
                "samples": [
                    {
                        "time_s": _round(time_s),
                        "expected_vi_mps": _round(vi),
                        "expected_lambda": _round(vi / omega_r),
                    }
                    for time_s, vi in zip(sample_times, samples_vi)
                ],
            }
        )

    dynamic_fixtures = fixtures
    fixture_errors = {
        fixture["name"]: _fixture_errors(fixture) for fixture in dynamic_fixtures
    }
    errors_by_method: dict[str, dict[str, Any]] = {}
    method_names = (
        "rk4_240hz_unsplit",
        "rk4_480hz_unsplit",
        "rk4_960hz_unsplit",
        "rk4_240hz_known_event_splits",
        "rk4_240hz_local_quarters",
    )
    for method in method_names:
        candidates = [fixture_errors[fixture["name"]][method] for fixture in dynamic_fixtures]
        errors_by_method[method] = max(
            candidates, key=lambda entry: entry["max_abs_error_mps"]
        )
        errors_by_method[method]["passes_1e-3_mps"] = (
            errors_by_method[method]["max_abs_error_mps"] <= ERROR_TOLERANCE_MPS
        )

    seam_fixtures = [
        fixture for fixture in dynamic_fixtures if fixture["kind"] == "source_seam_sweep"
    ]
    seam_errors: dict[str, dict[str, Any]] = {}
    for method in method_names:
        candidates = [fixture_errors[fixture["name"]][method] for fixture in seam_fixtures]
        seam_errors[method] = max(
            candidates, key=lambda entry: entry["max_abs_error_mps"]
        )
        seam_errors[method]["passes_1e-3_mps"] = (
            seam_errors[method]["max_abs_error_mps"] <= ERROR_TOLERANCE_MPS
        )

    total_samples = sum(len(fixture["samples"]) for fixture in output_fixtures)
    return {
        "format": "openrc-dynamic-inflow-oracle-v1",
        "model": (
            "Johnson steady mean-inflow target plus an unvalidated first-order "
            "dimensional induced-velocity lag"
        ),
        "units": {
            "time": "s",
            "induced_velocity": "m/s, positive down the wake axis for positive thrust",
            "lambda": "vi/(omega*radius), dimensionless; diagnostic only",
            "climb": "m/s, positive upward",
            "crossflow": "m/s magnitude",
        },
        "equations": {
            "state": "dvi/dt = (target_mps - vi_mps) / tau_s",
            "time_constant": "tau_s = 0.849 * radius_m / (4 * max(effective_speed_mps, velocity_floor_mps))",
            "feedback_effective_speed": "hypot(crossflow_mps, vi_mps + climb_mps)",
            "fixed_target_response": "vi(t) = target + (vi0-target)*exp(-(t-t0)/tau)",
            "lag_provenance": "selected model approximation; not a Johnson transient law",
        },
        "qualification": {
            "base_step_s": _round(BASE_TICK_S),
            "tested_refinements_s": [
                _round(BASE_TICK_S),
                _round(BASE_TICK_S / 2.0),
                _round(BASE_TICK_S / 4.0),
            ],
            "error_tolerance_mps": ERROR_TOLERANCE_MPS,
            "comparison": "maximum absolute vi error at integrator output ticks against dense midpoint/exponential-convolution reference; the exact hover step uses its analytic exponential",
            "all_integrated_fixtures": errors_by_method,
            "source_seam_sweeps": seam_errors,
            "localized_refinement": {
                "window": "only macrosteps intersecting [event-h, event+h]",
                "substeps_per_affected_macrostep_max": 4,
                "right_hand_side_evaluations_per_affected_macrostep_max": 16,
                "crossing_tick": "split at the exact event time; subdivide each half into two equal segments, with one-sided endpoint targets; neighboring affected ticks use four equal quarters",
            },
            "per_fixture": fixture_errors,
            "event_split_scope": "fixtures provide known forcing-step/crossing times and one-sided endpoints; this is not session event-detector readiness",
        },
        "sample_count": total_samples,
        "reference_step_s": DENSE_STEP_S,
        "fixtures": output_fixtures,
    }


def _render(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check without writing")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args(argv)
    expected = _render(build_oracle())
    path = args.output
    if args.check:
        actual = path.read_text(encoding="utf-8") if path.exists() else ""
        if actual != expected:
            diff = difflib.unified_diff(
                actual.splitlines(),
                expected.splitlines(),
                fromfile=str(path),
                tofile="generated dynamic oracle",
                lineterm="",
            )
            sys.stderr.write("\n".join(diff) + "\n")
            print(f"dynamic oracle check: STALE ({path.name})", file=sys.stderr)
            return 1
        print(f"dynamic oracle check: OK ({path.name})")
        return 0
    path.write_text(expected, encoding="utf-8", newline="\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

