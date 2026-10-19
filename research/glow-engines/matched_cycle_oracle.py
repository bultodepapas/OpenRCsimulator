#!/usr/bin/env python3
"""Matched-work phase-resolved comparison for the candidate glow profiles.

The profile's mean-cycle work, fuel, heat and loss closure is conserved once per
opportunity. An explicit estimated phase waveform redistributes those exact
cycle quantities over crank angle. This isolates a software averaging question;
normalization is not physical engine validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import cycle_oracle as source  # Reuse only its detached profile/prop input helpers.

TAU = math.tau
RHO = 1.225
MIXTURE = 1.15
AIR_SPEED = 0.0
SAMPLE_HZ = 240
REFERENCE_SAMPLE_HZ = 960
DURATION_S = 1.4
TRANSIENT_EVENTS = [(0.0, 0.60), (0.40, 1.0), (0.90, 0.60)]
PHASE_CASES_DEG = [-10.0, 0.0, 20.0]
INERTIA_MULTIPLIERS = [0.5, 1.0, 2.0]
REFINEMENT_STEPS_DEG = [0.5, 0.25, 0.125]

ENGINES = {
    "glow_2t": {
        "profile": "app/data/glow/os_max_55ax_candidate.json",
        "installation": "app/data/glow/stik_55ax_2t.json",
        "aircraft": "app/data/aircraft/stik_glow_55ax_2t.json",
        "kernel": "app/physics/glow/two_stroke.gd",
        "cycle_angle_rad": TAU,
        "indicated_pulse_width_deg": 90.0,
        "pump_window_deg": [100.0, 260.0],
        "cycle_description": "360-degree two-stroke opportunity; firing-TDC phase origin",
    },
    "glow_4t": {
        "profile": "app/data/glow/os_fs_64v_candidate.json",
        "installation": "app/data/glow/stik_fs64v_4t.json",
        "aircraft": "app/data/aircraft/stik_glow_fs64v_4t.json",
        "kernel": "app/physics/glow/four_stroke.gd",
        "cycle_angle_rad": 2.0 * TAU,
        "indicated_pulse_width_deg": 100.0,
        "pump_window_deg": [145.0, 555.0],
        "cycle_description": "720-degree four-stroke opportunity; firing-TDC phase origin",
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quantity(container: dict[str, Any], name: str) -> float:
    return float(container[name]["value"])


def load_case(family: str) -> dict[str, Any]:
    config = ENGINES[family]
    paths = {key: ROOT / value for key, value in config.items() if key in ("profile", "installation", "aircraft", "kernel")}
    raw = {key: path.read_bytes() for key, path in paths.items()}
    profile = json.loads(raw["profile"])
    install = json.loads(raw["installation"])
    aircraft = json.loads(raw["aircraft"])
    prop = source.installation_prop(paths["installation"])
    inertia = quantity(aircraft["propulsion"]["propeller"], "rotating_inertia")
    return {
        "family": family,
        "config": config,
        "profile": profile,
        "install": install,
        "aircraft": aircraft,
        "prop": prop,
        "inertia": inertia,
        "paths": paths,
        "input_sha256": {key: hashlib.sha256(data).hexdigest() for key, data in raw.items()},
    }


def opening_for_command(case: dict[str, Any], command: float) -> float:
    """NITRO-06: the barrel's settled open-area fraction at a transmitter command (carburetor.py)."""
    idle_offset = carburetor.idle_offset(quantity(case["install"]["settings"], "idle_opening"))
    return carburetor.opening(command, idle_offset, quantity(case["install"]["settings"], "throttle_travel_exponent"))


def admission_at(case: dict[str, Any], opening: float, rpm: float) -> float:
    """NITRO-06: the charge per cycle the carburettor admits at this opening and speed, relative to wide open."""
    profile = case["profile"]
    parameters = profile["parameters"]
    two = case["family"] == "glow_2t"
    breathing = carburetor.sample_table(
        parameters["delivery_ratio" if two else "volumetric_efficiency"]["value"], rpm)
    capacity = carburetor.capacity_m3_s(quantity(case["install"]["settings"], "throttle_effective_area_m2"))
    return carburetor.admission(opening, rpm, breathing, parameters["displacement_m3"]["value"],
                                1.0 if two else 2.0, capacity)


def indicated_density_rad(phase_rad: float, family: str, phase_shift_deg: float) -> float:
    """Analytic, unit-area raised-cosine work pulse over a declared estimated window."""
    config = ENGINES[family]
    cycle = float(config["cycle_angle_rad"])
    width = math.radians(float(config["indicated_pulse_width_deg"]))
    x = (phase_rad - math.radians(phase_shift_deg)) % cycle
    if x >= width:
        return 0.0
    # Integral of sin^2(pi*x/width) over x in [0,width] is width/2.
    return 2.0 * math.sin(math.pi * x / width) ** 2 / width


def pumping_density_rad(phase_rad: float, family: str) -> float:
    """Analytic unit-area gas-exchange loss pulse, separate for each cycle family."""
    config = ENGINES[family]
    cycle = float(config["cycle_angle_rad"])
    start_deg, end_deg = config["pump_window_deg"]
    start = math.radians(float(start_deg))
    width = math.radians(float(end_deg) - float(start_deg))
    x = phase_rad % cycle
    if x < start or x >= start + width:
        return 0.0
    return 2.0 * math.sin(math.pi * (x - start) / width) ** 2 / width


def closure(case: dict[str, Any], rpm: float, opening: float) -> dict[str, float]:
    return source.family_inputs(case["profile"], rpm, admission=admission_at(case, opening, rpm), mixture=MIXTURE, rho=RHO)


def mean_root(case: dict[str, Any], opening: float) -> dict[str, float]:
    profile = case["profile"]
    parameters = source.interp_parameters(profile)
    op_max = quantity(profile["operation"], "max_rpm")
    lo = max(float(parameters["mechanical_torque_nm"][0][0]), 500.0)
    hi = min(float(parameters["mechanical_torque_nm"][-1][0]), op_max)

    def residual(rpm: float) -> float:
        values = closure(case, rpm, opening)
        prop = source.propeller_load(rpm, AIR_SPEED, RHO, case["prop"])
        if not prop["ideal_power_bound_pass"]:
            raise ValueError(f"installed propeller violates ideal-power lower bound at {rpm:.3f} RPM")
        return values["candidate_mean_shaft_torque_nm"] - float(prop["torque_nm"])

    points: list[tuple[float, float]] = []
    step = 100.0
    count = int(math.ceil((hi - lo) / step))
    for i in range(count + 1):
        rpm = min(hi, lo + i * step)
        points.append((rpm, residual(rpm)))
    roots: list[dict[str, float]] = []
    for (left, f_left), (right, f_right) in zip(points, points[1:]):
        if f_left <= 0.0 or f_right > 0.0:
            continue
        a, b = left, right
        fa = f_left
        for _ in range(48):
            mid = 0.5 * (a + b)
            fm = residual(mid)
            if fm > 0.0:
                a, fa = mid, fm
            else:
                b = mid
        rpm = 0.5 * (a + b)
        roots.append({"rpm": rpm, "residual_nm": residual(rpm)})
    if not roots:
        raise ValueError(f"no restoring mean root for {case['family']} at opening {opening:.6f}")
    return roots[-1]


def _speed_from_energy(energy_j: float, inertia: float) -> float:
    if energy_j <= 0.0:
        raise ValueError("cycle-resolved shaft energy reached zero")
    return math.sqrt(2.0 * energy_j / inertia)


def _profile_torque(case: dict[str, Any], phase_rad: float, rpm: float,
                    work: dict[str, float], phase_shift_deg: float) -> float:
    return (
        work["cycle_work_j"] * indicated_density_rad(phase_rad, case["family"], phase_shift_deg)
        - work["pumping_work_j"] * pumping_density_rad(phase_rad, case["family"])
        - work["mechanical_torque_nm"]
        - work["valve_torque_nm"]
    )


def integrate_one_cycle(case: dict[str, Any], *, start_rpm: float, opening: float,
                        max_step_deg: float, inertia_multiplier: float = 1.0,
                        phase_shift_deg: float = 0.0) -> dict[str, float]:
    """One independently integrated opportunity; returns its crank-map endpoint."""
    family = case["family"]
    cycle_angle = float(case["config"]["cycle_angle_rad"])
    step_max = math.radians(max_step_deg)
    inertia = case["inertia"] * inertia_multiplier
    omega = start_rpm * TAU / 60.0
    energy_start = 0.5 * inertia * omega * omega
    energy = energy_start
    phase = 0.0
    elapsed_s = 0.0
    engine_work_j = 0.0
    prop_work_j = 0.0
    rpm_min = start_rpm
    rpm_max = start_rpm
    work = closure(case, start_rpm, opening)
    angle_count = 0
    while phase < cycle_angle - 1e-12:
        dtheta = min(step_max, cycle_angle - phase)
        omega0 = _speed_from_energy(energy, inertia)
        rpm0 = omega0 * 60.0 / TAU
        theta_mid = phase + 0.5 * dtheta
        engine_tau0 = _profile_torque(case, theta_mid, rpm0, work, phase_shift_deg)
        prop0 = source.propeller_load(rpm0, AIR_SPEED, RHO, case["prop"])
        if not prop0["ideal_power_bound_pass"]:
            raise ValueError(f"ideal-power refusal at {rpm0:.6f} RPM")
        energy_mid = max(1e-12, energy + 0.5 * (engine_tau0 - float(prop0["torque_nm"])) * dtheta)
        rpm_mid = _speed_from_energy(energy_mid, inertia) * 60.0 / TAU
        engine_tau_mid = _profile_torque(case, theta_mid, rpm_mid, work, phase_shift_deg)
        prop_mid = source.propeller_load(rpm_mid, AIR_SPEED, RHO, case["prop"])
        if not prop_mid["ideal_power_bound_pass"]:
            raise ValueError(f"ideal-power refusal at {rpm_mid:.6f} RPM")
        omega_mid = rpm_mid * TAU / 60.0
        net_tau_mid = engine_tau_mid - float(prop_mid["torque_nm"])
        delta_energy = net_tau_mid * dtheta
        if energy + delta_energy <= 0.0:
            raise ValueError("periodic shaft map stopped inside the opportunity")
        elapsed_s += dtheta / omega_mid
        engine_work_j += engine_tau_mid * dtheta
        prop_work_j += float(prop_mid["torque_nm"]) * dtheta
        energy += delta_energy
        phase += dtheta
        angle_count += 1
        rpm_end = _speed_from_energy(energy, inertia) * 60.0 / TAU
        rpm_min = min(rpm_min, rpm0, rpm_mid, rpm_end)
        rpm_max = max(rpm_max, rpm0, rpm_mid, rpm_end)
    final_rpm = _speed_from_energy(energy, inertia) * 60.0 / TAU
    return {
        "start_rpm": start_rpm,
        "end_rpm": final_rpm,
        "map_delta_rpm": final_rpm - start_rpm,
        "time_average_rpm": cycle_angle / elapsed_s * 60.0 / TAU,
        "minimum_rpm": rpm_min,
        "maximum_rpm": rpm_max,
        "elapsed_s": elapsed_s,
        "angle_step_count": angle_count,
        "integrated_engine_work_j": engine_work_j,
        "profile_indicated_work_j": work["cycle_work_j"],
        "integrated_prop_work_j": prop_work_j,
        "profile_expected_net_shaft_work_j": (
            work["cycle_work_j"] - work["pumping_work_j"]
            - (work["mechanical_torque_nm"] + work["valve_torque_nm"]) * cycle_angle
        ),
        "integrated_pumping_work_j": work["pumping_work_j"],
        "profile_cycle_fuel_kg": work["burned_fuel_kg_cycle"],
        "profile_cycle_delivered_premix_kg": work["delivered_premix_kg_cycle"],
        "profile_chemical_heat_j": work["chemical_heat_j_cycle"],
        "energy_closure_residual_j": (energy - energy_start) - (engine_work_j - prop_work_j),
    }


def periodic_orbit(case: dict[str, Any], *, mean_rpm: float, opening: float,
                   max_step_deg: float, inertia_multiplier: float = 1.0,
                   phase_shift_deg: float = 0.0) -> dict[str, float]:
    """Find the stable cycle-start speed whose one-cycle energy map is periodic."""
    parameters = source.interp_parameters(case["profile"])
    rpm_min = max(float(parameters["mechanical_torque_nm"][0][0]), mean_rpm * 0.75)
    rpm_max = min(float(parameters["mechanical_torque_nm"][-1][0]), mean_rpm * 1.25,
                  quantity(case["profile"]["operation"], "max_rpm"))
    points = []
    for i in range(13):
        rpm = rpm_min + (rpm_max - rpm_min) * i / 12.0
        trace = integrate_one_cycle(case, start_rpm=rpm, opening=opening,
                                    max_step_deg=max_step_deg,
                                    inertia_multiplier=inertia_multiplier,
                                    phase_shift_deg=phase_shift_deg)
        points.append((rpm, trace["map_delta_rpm"]))
    brackets = [(a, b) for a, b in zip(points, points[1:]) if a[1] >= 0.0 and b[1] <= 0.0]
    if not brackets:
        raise ValueError(
            f"no stable periodic orbit bracket for {case['family']} at "
            f"inertia x{inertia_multiplier:g}, phase {phase_shift_deg:g} deg: {points}"
        )
    lo, hi = brackets[-1]
    a, fa = lo
    b, fb = hi
    for _ in range(28):
        mid = 0.5 * (a + b)
        trace = integrate_one_cycle(case, start_rpm=mid, opening=opening,
                                    max_step_deg=max_step_deg,
                                    inertia_multiplier=inertia_multiplier,
                                    phase_shift_deg=phase_shift_deg)
        fm = trace["map_delta_rpm"]
        if fm > 0.0:
            a, fa = mid, fm
        else:
            b, fb = mid, fm
    root_rpm = 0.5 * (a + b)
    trace = integrate_one_cycle(case, start_rpm=root_rpm, opening=opening,
                                max_step_deg=max_step_deg,
                                inertia_multiplier=inertia_multiplier,
                                phase_shift_deg=phase_shift_deg)
    return trace


def _opening_at(events: list[tuple[float, float]], time_s: float, case: dict[str, Any]) -> float:
    command = events[0][1]
    for when, value in events:
        if time_s + 1e-12 < when:
            break
        command = value
    return opening_for_command(case, command)


def simulate_phase(case: dict[str, Any], *, initial_rpm: float, duration_s: float,
                   sample_hz: int, max_step_deg: float, inertia_multiplier: float = 1.0,
                   phase_shift_deg: float = 0.0,
                   events: list[tuple[float, float]] | None = None) -> dict[str, Any]:
    """Independent crank-angle kinetic-energy integration with a cycle-held profile closure."""
    if duration_s * sample_hz != round(duration_s * sample_hz):
        raise ValueError("duration must contain an integer number of sample ticks")
    events = events or [(0.0, 1.0)]
    family = case["family"]
    config = case["config"]
    cycle_angle = float(config["cycle_angle_rad"])
    step_max = math.radians(max_step_deg)
    inertia = case["inertia"] * inertia_multiplier
    omega = initial_rpm * TAU / 60.0
    energy = 0.5 * inertia * omega * omega
    phase = 0.0
    time_s = 0.0
    current_opening = _opening_at(events, 0.0, case)
    current_cycle = closure(case, initial_rpm, current_opening)
    totals = {name: 0.0 for name in (
        "burned_fuel_kg", "delivered_premix_kg", "chemical_heat_j",
        "profile_indicated_work_j", "profile_net_shaft_work_j",
        "actual_engine_work_j", "prop_work_j", "ideal_power_refusals",
    )}
    rows: list[dict[str, float]] = []
    cycle_count = 0

    def count_opportunity(work: dict[str, float]) -> None:
        nonlocal cycle_count
        cycle_count += 1
        totals["burned_fuel_kg"] += work["burned_fuel_kg_cycle"]
        totals["delivered_premix_kg"] += work["delivered_premix_kg_cycle"]
        totals["chemical_heat_j"] += work["chemical_heat_j_cycle"]
        totals["profile_indicated_work_j"] += work["cycle_work_j"]
        angle = cycle_angle
        totals["profile_net_shaft_work_j"] += (
            work["cycle_work_j"] - work["pumping_work_j"]
            - (work["mechanical_torque_nm"] + work["valve_torque_nm"]) * angle
        )

    count_opportunity(current_cycle)
    ticks = int(round(duration_s * sample_hz))
    for tick in range(1, ticks + 1):
        target_t = tick / sample_hz
        rpm_time_integral = 0.0
        rpm_time = 0.0
        actual_work_tick = 0.0
        prop_work_tick = 0.0
        burned_before = totals["burned_fuel_kg"]
        delivered_before = totals["delivered_premix_kg"]
        guard = 0
        while time_s < target_t - 1e-13:
            guard += 1
            if guard > 100000:
                raise RuntimeError(
                    "angle integrator failed to reach the next sample: "
                    f"family={family} t={time_s:.17g} target={target_t:.17g} "
                    f"phase={phase:.17g} energy={energy:.17g}"
                )
            omega0 = _speed_from_energy(energy, inertia)
            rpm0 = omega0 * 60.0 / TAU
            next_boundary = cycle_angle - phase
            opening_now = _opening_at(events, time_s, case)
            max_dtheta = min(step_max, next_boundary)
            remaining_t = target_t - time_s
            dtheta = min(max_dtheta, omega0 * remaining_t)
            if dtheta <= 1e-14:
                dtheta = min(max_dtheta, 1e-10)
            prop0 = source.propeller_load(rpm0, AIR_SPEED, RHO, case["prop"])
            if not prop0["ideal_power_bound_pass"]:
                totals["ideal_power_refusals"] += 1
                raise ValueError(f"ideal-power refusal at {rpm0:.6f} RPM")
            # Explicit midpoint in crank angle; trim the rare reporting-boundary
            # step in-place so the next outer iteration retains progress.
            engine_tau0 = 0.0
            engine_tau_mid = 0.0
            prop_mid: dict[str, Any] = {}
            rpm_mid = rpm0
            omega_mid = omega0
            dt = 0.0
            for _trim in range(6):
                theta_mid = phase + 0.5 * dtheta
                engine_tau0 = _profile_torque(case, theta_mid, rpm0, current_cycle, phase_shift_deg)
                energy_mid = max(1e-12, energy + 0.5 * (engine_tau0 - float(prop0["torque_nm"])) * dtheta)
                rpm_mid = _speed_from_energy(energy_mid, inertia) * 60.0 / TAU
                engine_tau_mid = _profile_torque(case, theta_mid, rpm_mid, current_cycle, phase_shift_deg)
                prop_mid = source.propeller_load(rpm_mid, AIR_SPEED, RHO, case["prop"])
                if not prop_mid["ideal_power_bound_pass"]:
                    totals["ideal_power_refusals"] += 1
                    raise ValueError(f"ideal-power refusal at {rpm_mid:.6f} RPM")
                omega_mid = rpm_mid * TAU / 60.0
                dt = dtheta / omega_mid
                if dt <= remaining_t * (1.0 + 1e-12):
                    break
                dtheta *= remaining_t / dt
            else:
                raise RuntimeError("angle integrator could not trim to a reporting sample boundary")
            rpm_mid = _speed_from_energy(energy_mid, inertia) * 60.0 / TAU
            omega_mid = rpm_mid * TAU / 60.0
            net_tau_mid = engine_tau_mid - float(prop_mid["torque_nm"])
            delta_energy = net_tau_mid * dtheta
            if energy + delta_energy <= 0.0:
                raise ValueError("phase-resolved shaft stopped before the requested interval")
            actual_work_tick += engine_tau_mid * omega_mid * dt
            prop_work_tick += float(prop_mid["torque_nm"]) * omega_mid * dt
            rpm_time_integral += rpm_mid * dt
            rpm_time += dt
            totals["actual_engine_work_j"] += engine_tau_mid * omega_mid * dt
            totals["prop_work_j"] += float(prop_mid["torque_nm"]) * omega_mid * dt
            energy += delta_energy
            phase += dtheta
            time_s += dt
            if phase >= cycle_angle - 1e-11:
                phase = 0.0
                current_opening = _opening_at(events, time_s, case)
                rpm_boundary = _speed_from_energy(energy, inertia) * 60.0 / TAU
                current_cycle = closure(case, rpm_boundary, current_opening)
                count_opportunity(current_cycle)
        rows.append({
            "time_s": target_t,
            "rpm_end": _speed_from_energy(energy, inertia) * 60.0 / TAU,
            "rpm_mean": rpm_time_integral / rpm_time if rpm_time else _speed_from_energy(energy, inertia) * 60.0 / TAU,
            "engine_work_j": actual_work_tick,
            "prop_work_j": prop_work_tick,
            "burned_fuel_delta_kg": totals["burned_fuel_kg"] - burned_before,
            "delivered_fuel_delta_kg": totals["delivered_premix_kg"] - delivered_before,
        })
    return {
        "rows": rows,
        "totals": totals,
        "cycle_count": cycle_count,
        "duration_s": duration_s,
        "mean_rpm": sum(row["rpm_mean"] for row in rows) / len(rows),
        "minimum_rpm": min(row["rpm_end"] for row in rows),
        "maximum_rpm": max(row["rpm_end"] for row in rows),
    }


def _mean_rhs(case: dict[str, Any], time_s: float, state: list[float], events: list[tuple[float, float]]) -> list[float]:
    energy = state[0]
    inertia = case["inertia"]
    omega = _speed_from_energy(energy, inertia)
    rpm = omega * 60.0 / TAU
    opening = _opening_at(events, time_s, case)
    values = closure(case, rpm, opening)
    load = source.propeller_load(rpm, AIR_SPEED, RHO, case["prop"])
    if not load["ideal_power_bound_pass"]:
        raise ValueError(f"ideal-power refusal at {rpm:.6f} RPM")
    engine_tau = values["candidate_mean_shaft_torque_nm"]
    prop_tau = float(load["torque_nm"])
    return [
        (engine_tau - prop_tau) * omega,
        engine_tau * omega,
        prop_tau * omega,
        values["delivered_premix_flow_kg_s"],
        values["burned_fuel_flow_kg_s"],
        values["chemical_heat_j_cycle"] * values["opportunity_hz"],
    ]


def simulate_mean(case: dict[str, Any], *, initial_rpm: float, duration_s: float,
                  hz: int, events: list[tuple[float, float]]) -> dict[str, Any]:
    if duration_s * hz != round(duration_s * hz):
        raise ValueError("duration must contain an integer number of mean ticks")
    h = 1.0 / hz
    energy = 0.5 * case["inertia"] * (initial_rpm * TAU / 60.0) ** 2
    state = [energy, 0.0, 0.0, 0.0, 0.0, 0.0]
    rows: list[dict[str, float]] = []
    for i in range(int(round(duration_s * hz))):
        t = i * h
        k1 = _mean_rhs(case, t, state, events)
        s2 = [state[j] + 0.5 * h * k1[j] for j in range(6)]
        k2 = _mean_rhs(case, t + 0.5 * h, s2, events)
        s3 = [state[j] + 0.5 * h * k2[j] for j in range(6)]
        k3 = _mean_rhs(case, t + 0.5 * h, s3, events)
        s4 = [state[j] + h * k3[j] for j in range(6)]
        k4 = _mean_rhs(case, t + h, s4, events)
        state = [state[j] + (h / 6.0) * (k1[j] + 2.0 * k2[j] + 2.0 * k3[j] + k4[j]) for j in range(6)]
        if state[0] <= 0.0:
            raise ValueError("mean shaft stopped before the requested interval")
        rpm_start = _speed_from_energy(energy, case["inertia"]) * 60.0 / TAU
        rpm_end = _speed_from_energy(state[0], case["inertia"]) * 60.0 / TAU
        rows.append({
            "time_s": (i + 1) * h,
            "rpm_end": rpm_end,
            "rpm_mean": 0.5 * (rpm_start + rpm_end),
            "engine_work_j": state[1],
            "prop_work_j": state[2],
            "delivered_fuel_kg": state[3],
            "burned_fuel_kg": state[4],
            "chemical_heat_j": state[5],
        })
        energy = state[0]
    return {
        "rows": rows,
        "mean_rpm": sum(row["rpm_mean"] for row in rows) / len(rows),
        "totals": {"actual_engine_work_j": state[1], "prop_work_j": state[2],
                   "delivered_premix_kg": state[3], "burned_fuel_kg": state[4],
                   "chemical_heat_j": state[5]},
    }


def _relative_error(a: float, b: float) -> float:
    return (a - b) / max(abs(b), 1e-12)


def _trajectory_metrics(mean: dict[str, Any], phase: dict[str, Any]) -> dict[str, Any]:
    mrows, prows = mean["rows"], phase["rows"]
    rpm_errors = [abs(_relative_error(m["rpm_mean"], p["rpm_mean"])) for m, p in zip(mrows, prows)]
    metrics = {
        "mean_rpm_relative_error_fraction": _relative_error(mean["mean_rpm"], phase["mean_rpm"]),
        "mean_rpm_relative_error_percent": 100.0 * _relative_error(mean["mean_rpm"], phase["mean_rpm"]),
        "max_tick_mean_rpm_error_fraction": max(rpm_errors),
        "max_tick_mean_rpm_error_percent": 100.0 * max(rpm_errors),
        "prop_shaft_work_relative_error_fraction": _relative_error(mean["totals"]["prop_work_j"], phase["totals"]["prop_work_j"]),
        "engine_shaft_work_relative_error_fraction": _relative_error(mean["totals"]["actual_engine_work_j"], phase["totals"]["actual_engine_work_j"]),
        "delivered_fuel_relative_error_fraction": _relative_error(mean["totals"]["delivered_premix_kg"], phase["totals"]["delivered_premix_kg"]),
        "burned_fuel_relative_error_fraction": _relative_error(mean["totals"]["burned_fuel_kg"], phase["totals"]["burned_fuel_kg"]),
        "chemical_heat_relative_error_fraction": _relative_error(mean["totals"]["chemical_heat_j"], phase["totals"]["chemical_heat_j"]),
        "phase_event_count": phase["cycle_count"],
    }
    return metrics


def aggregate_phase_rows(rows: list[dict[str, float]], source_hz: int,
                         target_hz: int) -> list[dict[str, float]]:
    if source_hz % target_hz != 0:
        raise ValueError("reference sampling rate must be an integer multiple of target rate")
    factor = source_hz // target_hz
    if len(rows) % factor != 0:
        raise ValueError("phase reference rows do not cover whole target ticks")
    result = []
    for start in range(0, len(rows), factor):
        group = rows[start:start + factor]
        result.append({
            "time_s": group[-1]["time_s"],
            "rpm_end": group[-1]["rpm_end"],
            "rpm_mean": sum(row["rpm_mean"] for row in group) / factor,
            "engine_work_j": sum(row["engine_work_j"] for row in group),
            "prop_work_j": sum(row["prop_work_j"] for row in group),
            "burned_fuel_delta_kg": sum(row["burned_fuel_delta_kg"] for row in group),
            "delivered_fuel_delta_kg": sum(row["delivered_fuel_delta_kg"] for row in group),
        })
    return result


def threshold_time(rows: list[dict[str, float]], *, start_s: float, direction: str,
                   threshold_rpm: float) -> float | None:
    prior = None
    prior_t = None
    for row in rows:
        t = float(row["time_s"])
        rpm = float(row["rpm_mean"])
        if t < start_s - 1e-12:
            prior, prior_t = rpm, t
            continue
        crossed = (prior is not None and prior_t is not None and
                   ((prior < threshold_rpm <= rpm) if direction == "up"
                    else (prior > threshold_rpm >= rpm)))
        if crossed:
            fraction = (threshold_rpm - prior) / (rpm - prior) if rpm != prior else 0.0
            return prior_t + fraction * (t - prior_t)
        prior, prior_t = rpm, t
    return None


def phase_event_metrics(mean: dict[str, Any], phase: dict[str, Any],
                        low_root: float, high_root: float) -> dict[str, Any]:
    up_threshold = 0.5 * (low_root + high_root)
    up_mean = threshold_time(mean["rows"], start_s=0.40, direction="up", threshold_rpm=up_threshold)
    up_phase = threshold_time(phase["rows"], start_s=0.40, direction="up", threshold_rpm=up_threshold)
    down_threshold = up_threshold
    down_mean = threshold_time(mean["rows"], start_s=0.90, direction="down", threshold_rpm=down_threshold)
    down_phase = threshold_time(phase["rows"], start_s=0.90, direction="down", threshold_rpm=down_threshold)
    return {
        "definition": "first sampled 50%-of-low/high mean-root RPM crossing after each instantaneous throttle-command edge; no fuel/thermal threshold is modeled",
        "up_threshold_rpm": up_threshold,
        "down_threshold_rpm": down_threshold,
        "up_mean_time_s": up_mean,
        "up_phase_reference_time_s": up_phase,
        "up_absolute_error_s": abs(up_mean - up_phase) if up_mean is not None and up_phase is not None else None,
        "down_mean_time_s": down_mean,
        "down_phase_reference_time_s": down_phase,
        "down_absolute_error_s": abs(down_mean - down_phase) if down_mean is not None and down_phase is not None else None,
    }


def analyze_family(family: str) -> dict[str, Any]:
    case = load_case(family)
    full_opening = 1.0
    low_command = TRANSIENT_EVENTS[0][1]
    low_opening = opening_for_command(case, low_command)
    full_root = mean_root(case, full_opening)
    low_root = mean_root(case, low_opening)

    steady_rows = []
    for inertia_multiple in INERTIA_MULTIPLIERS:
        for phase_shift in PHASE_CASES_DEG:
            result = periodic_orbit(
                case, mean_rpm=full_root["rpm"], opening=full_opening,
                max_step_deg=0.25, inertia_multiplier=inertia_multiple,
                phase_shift_deg=phase_shift,
            )
            steady_rows.append({
                "rotor_inertia_multiplier": inertia_multiple,
                "phase_shift_deg": phase_shift,
                "candidate_mean_root_rpm": full_root["rpm"],
                "phase_periodic_start_rpm": result["start_rpm"],
                "phase_periodic_time_average_rpm": result["time_average_rpm"],
                "relative_difference_from_mean_root_fraction": _relative_error(result["time_average_rpm"], full_root["rpm"]),
                "cycle_rpm_ripple_fraction": (result["maximum_rpm"] - result["minimum_rpm"]) / result["time_average_rpm"],
                "periodic_map_residual_rpm": result["map_delta_rpm"],
                "angle_step_deg": 0.25,
            })

    angle_rows = []
    for angle_step in REFINEMENT_STEPS_DEG:
        phase = periodic_orbit(
            case, mean_rpm=full_root["rpm"], opening=full_opening,
            max_step_deg=angle_step,
        )
        angle_rows.append({"step_deg_max": angle_step,
                           "periodic_start_rpm": phase["start_rpm"],
                           "periodic_time_average_rpm": phase["time_average_rpm"],
                           "periodic_map_residual_rpm": phase["map_delta_rpm"],
                           "cycle_elapsed_s": phase["elapsed_s"],
                           "phase_minimum_rpm": phase["minimum_rpm"],
                           "phase_maximum_rpm": phase["maximum_rpm"],
                           "profile_cycle_work_j": phase["profile_indicated_work_j"],
                           "integrated_engine_work_j": phase["integrated_engine_work_j"],
                           "integrated_prop_work_j": phase["integrated_prop_work_j"],
                           "energy_closure_residual_j": phase["energy_closure_residual_j"],
                           "angle_step_count": phase["angle_step_count"]})
    fine_rpm = angle_rows[-1]["periodic_time_average_rpm"]
    for row in angle_rows:
        row["mean_rpm_error_vs_finest_fraction"] = _relative_error(row["periodic_time_average_rpm"], fine_rpm)

    reference = simulate_phase(
        case, initial_rpm=low_root["rpm"], duration_s=DURATION_S,
        sample_hz=REFERENCE_SAMPLE_HZ, max_step_deg=0.125,
        phase_shift_deg=0.0, events=TRANSIENT_EVENTS,
    )
    mean_by_hz = {}
    for hz in [240, 480, 960]:
        mean_by_hz[str(hz)] = simulate_mean(
            case, initial_rpm=low_root["rpm"], duration_s=DURATION_S,
            hz=hz, events=TRANSIENT_EVENTS,
        )
    reference_240 = {**reference, "rows": aggregate_phase_rows(
        reference["rows"], REFERENCE_SAMPLE_HZ, SAMPLE_HZ)}
    reference_240["mean_rpm"] = sum(r["rpm_mean"] for r in reference_240["rows"]) / len(reference_240["rows"])
    base_metrics = _trajectory_metrics(mean_by_hz["240"], reference_240)
    base_metrics["threshold_events"] = phase_event_metrics(
        mean_by_hz["240"], reference, low_root["rpm"], full_root["rpm"])
    refinement = []
    high = mean_by_hz["960"]
    for hz in [240, 480, 960]:
        m = mean_by_hz[str(hz)]
        aligned_errors = []
        for tick_240 in range(1, int(round(DURATION_S * SAMPLE_HZ)) + 1):
            mean_index = min(len(m["rows"]) - 1, int(round(tick_240 * hz / SAMPLE_HZ)) - 1)
            high_index = min(len(high["rows"]) - 1, int(round(tick_240 * 960 / SAMPLE_HZ)) - 1)
            aligned_errors.append(abs(_relative_error(
                m["rows"][mean_index]["rpm_mean"], high["rows"][high_index]["rpm_mean"])))
        refinement.append({"mean_step_hz": hz,
                           "mean_rpm_error_vs_960hz_fraction": abs(_relative_error(m["mean_rpm"], high["mean_rpm"])),
                           "max_aligned_tick_rpm_error_vs_960hz_fraction": max(aligned_errors)})
    return {
        "engine_id": case["profile"]["id"],
        "family": family,
        "inputs": {
            "paths": {key: path.relative_to(ROOT).as_posix() for key, path in case["paths"].items()},
            "sha256": case["input_sha256"],
            "profile_mean_kernel_sha256": sha256(case["paths"]["kernel"]),
            "propeller_kernel_sha256": sha256(ROOT / "app/physics/glow/propeller.gd"),
            "mean_profile_helper_sha256": sha256(Path(source.__file__).resolve()),
            "installed_rotor_inertia_kg_m2": case["inertia"],
            "installed_propeller_parameters": case["prop"],
            "supported_max_rpm": quantity(case["profile"]["operation"], "max_rpm"),
        },
        "operating_points": {
            "full_opening": full_opening,
            "full_static_mean_root_rpm": full_root["rpm"],
            "full_static_mean_root_residual_nm": full_root["residual_nm"],
            "low_command": low_command,
            "low_opening": low_opening,
            "low_static_mean_root_rpm": low_root["rpm"],
            "low_static_mean_root_residual_nm": low_root["residual_nm"],
        },
        "static_phase_sensitivity": {
            "scenario_rows": steady_rows,
            "rotor_inertia_multipliers": INERTIA_MULTIPLIERS,
            "combustion_phase_shifts_deg": PHASE_CASES_DEG,
            "interpretation": "Steady, fixed-carrier conditional orbit; exact candidate cycle work/fuel/heat/loss totals are redistributed by the declared estimated phase pulse. Values are numerical consequences of that hypothesis, not measured vibration/RPM ripple.",
        },
        "angle_grid_convergence": {
            "rows": angle_rows,
            "quadrature_budget_fraction": 1e-3,
            "steady_mean_rpm_relative_error_vs_mean_root_fraction": _relative_error(
                angle_rows[-1]["periodic_time_average_rpm"], full_root["rpm"]),
            "status": "evaluated",
        },
        "throttle_transient": {
            "events_command_fraction": [{"time_s": t, "command": c,
                                         "opening": opening_for_command(case, c)}
                                        for t, c in TRANSIENT_EVENTS],
            "duration_s": DURATION_S,
            "phase_reference": {"method": "independent crank-angle energy integration",
                                "max_angle_step_deg": 0.125,
                                "mean_sample_hz": REFERENCE_SAMPLE_HZ,
                                "comparison_rows_aggregated_to_hz": SAMPLE_HZ,
                                "cycle_count": reference["cycle_count"],
                                "totals": reference["totals"],
                                "mean_rpm": reference["mean_rpm"]},
            "mean_reduction_240hz_vs_phase": base_metrics,
            "mean_solver_refinement": refinement,
            "mean_reduction_rpm_budget_fraction": 0.001,
            "mean_reduction_shaft_work_fuel_budget_fraction": 0.005,
            "result_classification": {
                "steady_mean_rpm_relative_error_fraction": _relative_error(
                    angle_rows[-1]["periodic_time_average_rpm"], full_root["rpm"]),
                "steady_rpm_budget_pass": abs(_relative_error(
                    angle_rows[-1]["periodic_time_average_rpm"], full_root["rpm"])) <= 0.001,
                "transient_mean_rpm_budget_pass": abs(base_metrics["mean_rpm_relative_error_fraction"]) <= 0.001,
                "rpm_budget_pass": (
                    abs(_relative_error(angle_rows[-1]["periodic_time_average_rpm"], full_root["rpm"])) <= 0.001
                    and abs(base_metrics["mean_rpm_relative_error_fraction"]) <= 0.001
                ),
                "shaft_work_budget_pass": abs(base_metrics["prop_shaft_work_relative_error_fraction"]) <= 0.005,
                "fuel_budget_pass": abs(base_metrics["delivered_fuel_relative_error_fraction"]) <= 0.005,
                "temperature_budget": "NOT TESTED: temperature state and heat-transfer/cooling law are outside this shaft-only harness",
                "event_time_budget_pass": all(
                    x is not None and x <= 1.0 / SAMPLE_HZ
                    for x in [base_metrics["threshold_events"]["up_absolute_error_s"],
                              base_metrics["threshold_events"]["down_absolute_error_s"]]
                ),
            },
        },
        "closure_audit": {
            "method": "For each phase-resolved opportunity, the analytic indicated and pumping pulse densities integrate to one over the exact 360/720-degree cycle; mechanical and valve losses are uniform. The per-opportunity fuel, chemical heat, indicated work and pumping/mechanical/valve work are sampled from the candidate profile helper at cycle start, and totals are recorded before propeller work is coupled.",
            "waveform_integrals": {
                "indicated_work_j_per_opportunity": "exact profile cycle_work_j",
                "fuel_kg_per_opportunity": "exact profile burned_fuel_kg_cycle and delivered_premix_kg_cycle",
                "chemical_heat_j_per_opportunity": "exact profile chemical_heat_j_cycle",
                "pumping_loss_work_j_per_opportunity": "exact profile pumping_work_j",
                "mechanical_and_valve_loss_j_per_opportunity": "profile torque × family cycle angle",
            },
            "normalization_warning": "The estimated indicated phase pulse and gas-exchange loss windows are normalized to close the candidate mean energy ledger. That is deliberately a matched-work numerical probe and cannot validate those phase timings, pressure, fuel chemistry, cycle stability or actual engine output.",
        },
        "limitations": [
            "Fixed-carrier, zero axial airspeed. The annular installed propeller surrogate and its lower-bound gate are evaluated independently from production code.",
            "No cylinder pressure, burn law, port/valve flow, glow ignition, fuel transport, servo lag, mixture memory, temperature, cooling, firing/extinction, starter, tank depletion, aircraft acceleration, or reciprocating-mass dynamics is integrated.",
            "Throttle steps change admission instantly and phase integration holds a profile closure until the next cycle opportunity. This does not qualify lifecycle throttle-response accuracy.",
            "Plan RPM/work/fuel comparisons are conditional numerical budgets for the candidate closure and chosen phase waveform. Mean fuel and temperature event gates remain open outside the explicitly modeled opportunity counters.",
            "No engine or propeller measurements, held-out point, physical pilot trial, or audio/vibration claim is made.",
        ],
    }


def report() -> dict[str, Any]:
    engines = {family: analyze_family(family) for family in ENGINES}
    return {
        "format": "openrc-glow-matched-cycle-oracle v1",
        "generated_by": "research/glow-engines/matched_cycle_oracle.py",
        "source_sha256": sha256(Path(__file__).resolve()),
        "method": {
            "question": "How close is the 240 Hz mean shaft reduction to a separate high-resolution crank-angle integration when both use the exact same candidate profile work/fuel/heat/loss closure per 360/720-degree opportunity?",
            "mean_reduction": "A separate float64 RK4 energy ODE evaluates the candidate profile closure and installed propeller load at each integration stage, with opportunity frequency rpm/60 for 2T or rpm/120 for 4T.",
            "phase_reference": "An independent crank-angle kinetic-energy update integrates the normalized inferred torque waveform and continuous propeller load. Candidate cycle work, fuel, heat and loss quantities are held from cycle start to the next opportunity; each result includes fixed-step angle refinement.",
            "waveform": "Unit-integral raised-cosine indicated-work pulse over 90 crank degrees (2T) or 100 degrees (4T), delayed/advanced by declared phase scenarios; independent unit-integral sin-squared pump-loss window from the existing candidate loss work; uniform mechanical/valve torque loss.",
            "inertia": "Primary uses exact installed candidate rotor_inertia value. Sensitivity repeats the full-admission static orbit at 0.5x/1x/2x; no added piston/rod effective mass in the matched comparison.",
            "sampling": "Phase trajectory is sampled at 960 Hz for event crossing and aggregated to exact 240 Hz reporting intervals. Mean ODE refinement is at 240/480/960 Hz. Static crank-angle quadrature uses 0.5/0.25/0.125-degree maximum increments.",
        },
        "plan_budgets": {
            "mean_rpm_relative": 0.001,
            "delivered_shaft_work_relative": 0.005,
            "fuel_relative": 0.005,
            "temperature_k": 0.5,
            "event_time_s": 1.0 / 240.0,
            "basis": "RC_NITRO_ENGINE_REALISM_PLAN.md software/numerical acceptance; not physical accuracy tolerances",
        },
        "engines": engines,
        "overall_status": {
            "matched_work_averaging_test": "evaluated for installed static equilibrium and instantaneous throttle-step shaft/fuel cases",
            "temperature_and_fuel_lifecycle_gate": "OPEN: thermal, cooling, transport, exhaustion and extinction states are not represented by this model",
            "physical_validation": "NOT PERFORMED",
            "pilot_validation": "NOT PERFORMED",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write matched-cycle-oracle.json in the NITRO-02 dossier")
    args = parser.parse_args()
    result = report()
    encoded = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.write:
        out_path = ROOT / "docs/research/glow-engines/NITRO-02/matched-cycle-oracle.json"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(encoded, encoding="utf-8")
        print(f"Wrote {out_path}")
    else:
        print(encoded)


if __name__ == "__main__":
    main()
