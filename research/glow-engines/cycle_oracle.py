#!/usr/bin/env python3
"""Independent crank-angle pressure/work oracle for the two NITRO glow candidates.

This research program deliberately does not import the GDScript kernels or
calibration_report.py. It reads candidate profile/installation inputs, then
integrates a single-zone ideal-gas pressure trace over estimated port/valve
events. It is an engineering sensitivity study, not engine validation.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
PROFILE_DIR = ROOT / "app" / "data" / "glow"
DOC_DIR = ROOT / "docs" / "research" / "glow-engines" / "NITRO-02"
ENGINES = {
    "glow_2t": {
        "profile": "os_max_55ax_candidate.json",
        "installation": "stik_55ax_2t.json",
        "aircraft": "stik_glow_55ax_2t.json",
        "geometry": {"bore_m": 0.0230, "stroke_m": 0.0215,
                     "source": "https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm"},
        "nominal": {
            "compression_ratio": 8.0, "rod_to_crank_ratio": 3.5,
            "gamma": 1.34, "heat_to_gas_fraction": 0.52,
            "residual_mass_fraction": 0.10, "trapped_temperature_k": 350.0,
            "combustion_start_deg_btdc": 15.0, "burn_duration_deg": 40.0,
            "exhaust_open_deg_atdc": 100.0, "transfer_open_deg_atdc": 120.0,
            "transfer_close_deg_atdc": 240.0, "exhaust_close_deg_atdc": 260.0,
            "open_flow_shape": "linear blowdown; sin^2 scavenge-pressure pulse; ambient tail",
        },
        "bounds": {
            "compression_ratio": [6.5, 10.0], "rod_to_crank_ratio": [3.0, 5.0],
            "gamma": [1.32, 1.38], "heat_to_gas_fraction": [0.35, 0.75],
            "residual_mass_fraction": [0.05, 0.20], "trapped_temperature_k": [320.0, 390.0],
            "combustion_start_deg_btdc": [5.0, 25.0], "burn_duration_deg": [25.0, 60.0],
            "exhaust_open_deg_atdc": [90.0, 110.0], "transfer_open_deg_atdc": [110.0, 130.0],
            "transfer_close_deg_atdc": [230.0, 250.0], "exhaust_close_deg_atdc": [250.0, 270.0],
        },
    },
    "glow_4t": {
        "profile": "os_fs_64v_candidate.json",
        "installation": "stik_fs64v_4t.json",
        "aircraft": "stik_glow_fs64v_4t.json",
        "geometry": {"bore_m": 0.0250, "stroke_m": 0.0213,
                     "source": "https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html"},
        "nominal": {
            "compression_ratio": 8.0, "rod_to_crank_ratio": 3.5,
            "gamma": 1.34, "heat_to_gas_fraction": 0.62,
            "residual_mass_fraction": 0.08, "trapped_temperature_k": 330.0,
            "combustion_start_deg_btdc": 15.0, "burn_duration_deg": 45.0,
            "exhaust_open_deg_atdc": 145.0, "intake_open_deg_before_exhaust_tdc": 10.0,
            "exhaust_close_deg_after_exhaust_tdc": 10.0,
            "intake_close_deg_abdc": 35.0,
            "open_flow_shape": "exhaust back-pressure; linear overlap transition; ambient intake",
        },
        "bounds": {
            "compression_ratio": [6.5, 10.0], "rod_to_crank_ratio": [3.0, 5.0],
            "gamma": [1.32, 1.38], "heat_to_gas_fraction": [0.35, 0.80],
            "residual_mass_fraction": [0.03, 0.18], "trapped_temperature_k": [300.0, 370.0],
            "combustion_start_deg_btdc": [5.0, 25.0], "burn_duration_deg": [25.0, 65.0],
            "exhaust_open_deg_atdc": [130.0, 160.0], "intake_open_deg_before_exhaust_tdc": [5.0, 25.0],
            "exhaust_close_deg_after_exhaust_tdc": [0.0, 20.0], "intake_close_deg_abdc": [20.0, 55.0],
        },
    },
}

R_AIR = 287.0
TAU = math.tau
AMBIENT_PA = 101325.0
DEFAULT_AIRSPEED_M_S = 0.0
DEFAULT_RHO_KG_M3 = 1.225
DEFAULT_MIXTURE = 1.15
DEFAULT_ADMISSION = 1.0
DEFAULT_FIRING_FRACTION = 1.0
WIEBE_A = 6.907755278982137  # 99.9% of prescribed burn by end angle.
WIEBE_M = 2.0
ANGLE_STEPS_DEG = [20.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.25, 0.125, 0.0625]
INERTIA_SENSITIVITY_MULTIPLIERS = [0.5, 1.0, 2.0]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def qvalue(group: dict[str, Any], key: str) -> Any:
    return group[key]["value"]


def sample(table: list[list[float]], x: float) -> float:
    if x < table[0][0] - 1e-9 or x > table[-1][0] + 1e-9:
        raise ValueError(f"{x} outside table support [{table[0][0]}, {table[-1][0]}]")
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            f = (x - x0) / (x1 - x0)
            return float(y0 + (y1 - y0) * f)
    return float(table[-1][1])


def fuel_basis(profile: dict[str, Any]) -> dict[str, float]:
    f = {key: qvalue(profile["fuel"], key) for key in profile["fuel"]}
    nitro = f["nitromethane_volume_fraction"]
    oil = f["lubricant_volume_fraction"]
    volume = {
        "methanol": (1.0 - nitro - oil) * f["methanol_density_kg_m3"],
        "nitromethane": nitro * f["nitromethane_density_kg_m3"],
        "oil": oil * f["lubricant_density_kg_m3"],
    }
    combustible_mass = volume["methanol"] + volume["nitromethane"]
    total_mass = combustible_mass + volume["oil"]
    return {
        "oil_fraction": volume["oil"] / total_mass,
        "stoich_air_fuel_ratio": (
            volume["methanol"] * f["methanol_stoich_air_fuel_ratio"]
            + volume["nitromethane"] * f["nitromethane_stoich_air_fuel_ratio"]
        ) / combustible_mass,
        "lhv_j_kg": (
            volume["methanol"] * f["methanol_lhv_j_kg"]
            + volume["nitromethane"] * f["nitromethane_lhv_j_kg"]
        ) / combustible_mass,
    }


def interp_parameters(profile: dict[str, Any]) -> dict[str, Any]:
    return {key: qvalue(profile["parameters"], key) for key in profile["parameters"]}


def family_inputs(profile: dict[str, Any], rpm: float, *, admission: float = DEFAULT_ADMISSION,
                  mixture: float = DEFAULT_MIXTURE, rho: float = DEFAULT_RHO_KG_M3,
                  firing_fraction: float = DEFAULT_FIRING_FRACTION) -> dict[str, float]:
    """Reconstruct the candidate mean-cycle mass and shaft terms without importing its code."""
    p = interp_parameters(profile)
    op = {key: qvalue(profile["operation"], key) for key in profile["operation"]}
    fuel = fuel_basis(profile)
    disp = float(p["displacement_m3"])
    oil_fraction = fuel["oil_fraction"]
    afr = fuel["stoich_air_fuel_ratio"]
    if profile["family"] == "glow_2t":
        delivery = sample(p["delivery_ratio"], rpm)
        trap = sample(p["trapping_efficiency"], rpm)
        air_delivered = rho * disp * admission * delivery
        air_charge = air_delivered * trap
        gross_premix = air_delivered * mixture / afr / (1.0 - oil_fraction)
        trapped_premix = gross_premix * trap
        gross_combustible_trapped = gross_premix * (1.0 - oil_fraction) * trap
        oxygen_limited = air_charge / afr
        pump_work = sample(p["scavenge_pressure_pa"], rpm) * disp * delivery * admission
        pump_torque = pump_work / TAU
        opportunity_hz = rpm / 60.0
    elif profile["family"] == "glow_4t":
        ve = sample(p["volumetric_efficiency"], rpm)
        air_charge = rho * disp * admission * ve
        gross_premix = air_charge * mixture / afr / (1.0 - oil_fraction)
        trapped_premix = gross_premix
        gross_combustible_trapped = gross_premix * (1.0 - oil_fraction)
        oxygen_limited = air_charge / afr
        pump_work = (sample(p["pumping_pressure_pa"], rpm) +
                     float(p["intake_pressure_drop_pa"]) * (1.0 - admission)) * disp
        pump_torque = pump_work / (2.0 * TAU)
        opportunity_hz = rpm / 120.0
    else:
        raise ValueError(f"unsupported family {profile['family']}")

    combustion_efficiency = sample(p["combustion_efficiency"], mixture)
    burned = min(gross_combustible_trapped, oxygen_limited) * combustion_efficiency * firing_fraction
    indicated_efficiency = sample(p["indicated_efficiency"], rpm)
    cycle_work = burned * fuel["lhv_j_kg"] * indicated_efficiency
    angle = TAU if profile["family"] == "glow_2t" else 2.0 * TAU
    mechanical = sample(p["mechanical_torque_nm"], rpm)
    valve = sample(p["valve_torque_nm"], rpm) if profile["family"] == "glow_4t" else 0.0
    return {
        "rpm": rpm, "admission": admission, "mixture": mixture, "rho_kg_m3": rho,
        "air_delivered_kg_cycle": air_delivered if profile["family"] == "glow_2t" else air_charge,
        "air_charge_kg_cycle": air_charge, "trapped_premix_kg_cycle": trapped_premix,
        "delivered_premix_kg_cycle": gross_premix,
        "burned_fuel_kg_cycle": burned, "chemical_heat_j_cycle": burned * fuel["lhv_j_kg"],
        "cycle_work_j": cycle_work, "opportunity_hz": opportunity_hz,
        "candidate_indicated_work_rate_w": cycle_work * opportunity_hz,
        "burned_fuel_flow_kg_s": burned * opportunity_hz,
        "delivered_premix_flow_kg_s": gross_premix * opportunity_hz,
        "indicated_mean_torque_nm": cycle_work / angle,
        "mechanical_torque_nm": mechanical, "pumping_work_j": pump_work,
        "pumping_torque_nm": pump_torque, "valve_torque_nm": valve,
        "candidate_mean_shaft_torque_nm": cycle_work / angle - mechanical - pump_torque - valve,
        "indicated_efficiency": indicated_efficiency,
        "combustion_efficiency": combustion_efficiency,
        "fuel_lhv_j_kg": fuel["lhv_j_kg"], "stoich_air_fuel_ratio": afr,
        "oil_fraction": oil_fraction,
    }


def volume_m3(theta_deg: float, displacement_m3: float, bore_m: float, stroke_m: float,
              compression_ratio: float, rod_to_crank_ratio: float) -> float:
    crank = 0.5 * stroke_m
    rod = crank * rod_to_crank_ratio
    area = math.pi * bore_m * bore_m / 4.0
    theta = math.radians(theta_deg)
    root = math.sqrt(max(0.0, rod * rod - crank * crank * math.sin(theta) ** 2))
    piston_travel = crank * (1.0 - math.cos(theta)) + rod - root
    clearance = displacement_m3 / (compression_ratio - 1.0)
    return clearance + area * piston_travel


def dvolume_dtheta_m3_rad(theta_deg: float, displacement_m3: float, bore_m: float, stroke_m: float,
                          compression_ratio: float, rod_to_crank_ratio: float) -> float:
    del displacement_m3, compression_ratio  # displacement/CR affect volume, not its derivative.
    crank = 0.5 * stroke_m
    rod = crank * rod_to_crank_ratio
    area = math.pi * bore_m * bore_m / 4.0
    theta = math.radians(theta_deg)
    root = math.sqrt(max(1e-30, rod * rod - crank * crank * math.sin(theta) ** 2))
    derivative_m_per_rad = crank * math.sin(theta) + (
        crank * crank * math.sin(theta) * math.cos(theta) / root
    )
    return area * derivative_m_per_rad


def effective_rotor_inertia_kg_m2(theta_deg: float, profile: dict[str, Any],
                                  rotating_inertia_kg_m2: float,
                                  reciprocating_mass_override_kg: float | None = None) -> float:
    """Add the profile's estimated equivalent piston mass to installed rotor inertia.

    The slider-crank piston speed is dy/dtheta * omega, with dy/dtheta obtained
    from dV/dtheta / bore area. The report's profile reciprocating mass is an
    estimate, and this equivalent-mass approximation omits rod angular kinetic
    energy and any connecting-rod mass distribution.
    """
    p = interp_parameters(profile)
    bore = float(p["bore_m"])
    stroke = float(p["stroke_m"])
    displacement = float(p["displacement_m3"])
    rod_ratio = float(p["rod_to_crank_radius_ratio"])
    recip_mass = (float(p["reciprocating_mass_kg"])
                  if reciprocating_mass_override_kg is None
                  else float(reciprocating_mass_override_kg))
    area = math.pi * bore * bore / 4.0
    dvolume = dvolume_dtheta_m3_rad(theta_deg, displacement, bore, stroke,
                                    8.0, rod_ratio)
    piston_travel_derivative_m_rad = dvolume / area
    return rotating_inertia_kg_m2 + recip_mass * piston_travel_derivative_m_rad ** 2


def wiebe_fraction(theta_deg: float, start_deg: float, duration_deg: float,
                   a: float = WIEBE_A, m: float = WIEBE_M) -> float:
    if theta_deg <= start_deg:
        return 0.0
    if theta_deg >= start_deg + duration_deg:
        return 1.0
    x = (theta_deg - start_deg) / duration_deg
    end = 1.0 - math.exp(-a)
    return (1.0 - math.exp(-a * x ** (m + 1.0))) / end


def cycle_angles(family: str, assumptions: dict[str, Any]) -> dict[str, float]:
    if family == "glow_2t":
        epo = float(assumptions["exhaust_open_deg_atdc"])
        tpo = float(assumptions["transfer_open_deg_atdc"])
        tpc = float(assumptions["transfer_close_deg_atdc"])
        epc = float(assumptions["exhaust_close_deg_atdc"])
        return {"start": epc, "end": epc + 360.0, "tdc": 360.0,
                "epo": epo + 360.0, "tpo": tpo + 360.0,
                "tpc": tpc + 360.0, "epc_next": epc + 360.0}
    if family == "glow_4t":
        # Intake BDC is 540 degrees after firing TDC in the selected 720-degree
        # cycle; IVC follows it by the stated ABDC angle.
        i_close = 540.0 + float(assumptions["intake_close_deg_abdc"])
        e_open = float(assumptions["exhaust_open_deg_atdc"])
        i_open = 360.0 - float(assumptions["intake_open_deg_before_exhaust_tdc"])
        e_close = 360.0 + float(assumptions["exhaust_close_deg_after_exhaust_tdc"])
        return {"start": i_close, "end": i_close + 720.0, "tdc": 720.0,
                "evo": e_open + 720.0, "ivo": i_open + 720.0,
                "evc": e_close + 720.0, "ivc_next": i_close + 720.0}
    raise ValueError(f"unsupported family {family}")


def boundary_pressure_gauge(family: str, theta: float, p_open: float, angles: dict[str, float]) -> float:
    if family == "glow_2t":
        epo, tpo, tpc, epc = angles["epo"], angles["tpo"], angles["tpc"], angles["epc_next"]
        if theta < tpo:
            # Blowdown from measured-in-model cylinder pressure at EPO, held as a boundary.
            return max(0.0, p_open * (1.0 - (theta - epo) / max(1e-9, tpo - epo)))
        if theta < tpc:
            x = (theta - tpo) / max(1e-9, tpc - tpo)
            return max(0.0, p_open * math.sin(math.pi * x) ** 2)
        if theta < epc:
            return 0.0
        return 0.0
    evo, ivo, evc, ivc = angles["evo"], angles["ivo"], angles["evc"], angles["ivc_next"]
    if theta < ivo:
        return p_open
    if theta < evc:
        x = (theta - ivo) / max(1e-9, evc - ivo)
        return p_open * (1.0 - x)
    if theta < ivc:
        return 0.0
    return 0.0


def iterate_angles(start: float, end: float, requested_step_deg: float,
                   events: list[float]) -> list[tuple[float, float]]:
    if requested_step_deg <= 0.0:
        raise ValueError("step must be positive")
    edges = sorted({start, end, *(e for e in events if start < e < end)})
    intervals: list[tuple[float, float]] = []
    for left, right in zip(edges, edges[1:]):
        n_full = int((right - left) // requested_step_deg)
        theta = left
        for _ in range(n_full):
            nxt = min(right, theta + requested_step_deg)
            intervals.append((theta, nxt))
            theta = nxt
        if right - theta > 1e-10:
            intervals.append((theta, right))
    return intervals


def simulate_cycle(profile: dict[str, Any], family: str, rpm: float, step_deg: float,
                   assumptions: dict[str, Any] | None = None) -> dict[str, Any]:
    if rpm <= 0.0:
        raise ValueError("rpm must be positive")
    engine = ENGINES[family]
    assumptions = dict(engine["nominal"] if assumptions is None else assumptions)
    p = interp_parameters(profile)
    inp = family_inputs(profile, rpm)
    angles = cycle_angles(family, assumptions)
    disp = float(p["displacement_m3"])
    geom = {key: qvalue(profile["parameters"], key) for key in [
        "bore_m", "stroke_m", "rod_to_crank_radius_ratio", "reciprocating_mass_kg"
    ]}
    bore = float(geom["bore_m"])
    stroke = float(geom["stroke_m"])
    cr = float(assumptions["compression_ratio"])
    rod_ratio = float(assumptions["rod_to_crank_ratio"])
    gamma = float(assumptions["gamma"])
    cv = R_AIR / (gamma - 1.0)
    rho = DEFAULT_RHO_KG_M3
    fuel = fuel_basis(profile)
    fresh_mass = inp["air_charge_kg_cycle"] + inp["trapped_premix_kg_cycle"]
    residual_fraction = float(assumptions["residual_mass_fraction"])
    gas_mass = fresh_mass / (1.0 - residual_fraction)
    trapped_temp = float(assumptions["trapped_temperature_k"])
    heat_to_gas = float(assumptions["heat_to_gas_fraction"])
    heat_total = inp["burned_fuel_kg_cycle"] * fuel["lhv_j_kg"] * heat_to_gas
    start = angles["start"]
    end = angles["end"]
    tdc = angles["tdc"]
    burn_start = tdc - float(assumptions["combustion_start_deg_btdc"])
    burn_end = burn_start + float(assumptions["burn_duration_deg"])
    if family == "glow_2t":
        events = [start, burn_start, burn_end, angles["epo"], angles["tpo"], angles["tpc"], end]
        scavenge_pa = sample(p["scavenge_pressure_pa"], rpm)
        p_open = scavenge_pa
    else:
        events = [start, burn_start, burn_end, angles["evo"], angles["ivo"], angles["evc"], end]
        # The candidate full-admission pumping table is used as the exhaust receiver rise.
        p_open = sample(p["pumping_pressure_pa"], rpm)

    def vol(deg: float) -> float:
        return volume_m3(deg, disp, bore, stroke, cr, rod_ratio)

    start_volume = vol(start)
    temperature = trapped_temp
    start_pressure = gas_mass * R_AIR * temperature / start_volume
    blowdown_gauge_at_evo = None
    if family == "glow_2t":
        blowdown_gauge_at_evo = None
    cycle_work = 0.0
    closed_work = 0.0
    open_work = 0.0
    q_added = 0.0
    closed_energy_residual = 0.0
    peak_pressure = start_pressure
    peak_temperature = temperature
    torque_steps: list[dict[str, float]] = []
    intervals = iterate_angles(start, end, step_deg, events)
    previous_closed = False
    for theta0, theta1 in intervals:
        mid = 0.5 * (theta0 + theta1)
        delta_rad = math.radians(theta1 - theta0)
        v0, v1 = vol(theta0), vol(theta1)
        dv = v1 - v0
        is_closed = (mid < angles["epo"] if family == "glow_2t" else
                     (mid < angles["evo"] or mid > angles["ivc_next"]))
        # The selected full cycle has one closed compression/combustion/expansion interval.
        if is_closed:
            x0 = wiebe_fraction(theta0, burn_start, float(assumptions["burn_duration_deg"]))
            x1 = wiebe_fraction(theta1, burn_start, float(assumptions["burn_duration_deg"]))
            q_step = heat_total * max(0.0, x1 - x0)
            vmid = 0.5 * (v0 + v1)
            a = (R_AIR / (2.0 * cv)) * dv / vmid
            t_new = (temperature * (1.0 - a) + q_step / (gas_mass * cv)) / (1.0 + a)
            if not math.isfinite(t_new) or t_new <= 0.0:
                raise ArithmeticError(f"invalid closed-cycle temperature at {mid} deg")
            p_avg = gas_mass * R_AIR * (temperature + t_new) / (2.0 * vmid)
            w_step = (p_avg - AMBIENT_PA) * dv
            closed_energy_residual += gas_mass * cv * (t_new - temperature) - q_step + p_avg * dv
            temperature = t_new
            q_added += q_step
            closed_work += w_step
            peak_pressure = max(peak_pressure, gas_mass * R_AIR * temperature / v1)
            peak_temperature = max(peak_temperature, temperature)
            if family == "glow_2t" and abs(theta1 - angles["epo"]) < 1e-8:
                blowdown_gauge_at_evo = max(0.0, gas_mass * R_AIR * temperature / v1 - AMBIENT_PA)
            p_gauge_avg = p_avg - AMBIENT_PA
        else:
            # Open-system flow is represented by bounded pressure reservoirs; mass/enthalpy
            # exchange is not solved. State is reset from the profile charge at the next closure.
            p_boundary = p_open
            if family == "glow_2t":
                if mid < angles["tpo"]:
                    p_boundary = float(blowdown_gauge_at_evo or 0.0) * (
                        1.0 - (mid - angles["epo"]) / (angles["tpo"] - angles["epo"])
                    )
                elif mid < angles["tpc"]:
                    x = (mid - angles["tpo"]) / (angles["tpc"] - angles["tpo"])
                    p_boundary = p_open * math.sin(math.pi * x) ** 2
                else:
                    p_boundary = 0.0
            else:
                if mid < angles["ivo"]:
                    p_boundary = p_open
                elif mid < angles["evc"]:
                    x = (mid - angles["ivo"]) / (angles["evc"] - angles["ivo"])
                    p_boundary = p_open * (1.0 - x)
                else:
                    p_boundary = 0.0
            p_gauge_avg = max(0.0, p_boundary)
            w_step = p_gauge_avg * dv
            open_work += w_step
        cycle_work += w_step
        torque_steps.append({"theta_mid_deg": mid, "dtheta_rad": delta_rad,
                             "gas_torque_nm": w_step / delta_rad,
                             "work_j": w_step})
    cycle_angle = TAU if family == "glow_2t" else 2.0 * TAU
    return {
        "family": family, "rpm": rpm, "cycle_angle_rad": cycle_angle,
        "cycle_angle_deg": end - start, "step_requested_deg": step_deg,
        "step_count": len(intervals), "cycle_work_j": closed_work,
        "net_pv_cycle_work_j": cycle_work,
        "closed_compression_combustion_expansion_work_j": closed_work,
        "open_gas_exchange_pv_work_j": open_work,
        "heat_released_to_gas_j": q_added, "heat_release_fraction_of_profile_chemical_j": (
            q_added / inp["chemical_heat_j_cycle"] if inp["chemical_heat_j_cycle"] else 0.0
        ),
        "thermodynamic_indicated_efficiency_estimate": (
            closed_work / inp["chemical_heat_j_cycle"] if inp["chemical_heat_j_cycle"] else 0.0
        ),
        "net_pv_efficiency_estimate": (
            cycle_work / inp["chemical_heat_j_cycle"] if inp["chemical_heat_j_cycle"] else 0.0
        ),
        "candidate_kernel_cycle_work_j": inp["cycle_work_j"],
        "cycle_work_delta_vs_candidate_j": closed_work - inp["cycle_work_j"],
        "cycle_work_delta_vs_candidate_fraction": (
            closed_work / inp["cycle_work_j"] - 1.0 if inp["cycle_work_j"] else None
        ),
        "air_charge_kg_cycle": inp["air_charge_kg_cycle"],
        "burned_fuel_kg_cycle": inp["burned_fuel_kg_cycle"],
        "trapped_total_gas_mass_kg": gas_mass,
        "geometry_used": {"bore_m": bore, "stroke_m": stroke,
                          "rod_to_crank_radius_ratio": rod_ratio,
                          "profile_reciprocating_mass_kg": float(geom["reciprocating_mass_kg"])},
        "assumed_start_pressure_pa": start_pressure,
        "peak_pressure_pa": peak_pressure,
        "peak_temperature_k": peak_temperature,
        "closed_energy_first_law_residual_j": closed_energy_residual,
        "torque_steps": torque_steps,
    }


def unlocked_phase_sampling_audit(reference_trace: dict[str, Any],
                                  requested_steps_deg: list[float] | None = None,
                                  phase_offsets: int = 16) -> list[dict[str, Any]]:
    """Quantify phase-sensitive, uniform-angle midpoint sampling of the pressure waveform.

    This intentionally does not align coarse samples to port/valve/burn events.
    It linearly interpolates a fine reference torque waveform, integrates a
    uniform coarse midpoint grid, and sweeps grid phase. It is a quadrature
    aliasing probe for the declared waveform, not the simulator's variable-time
    step or an empirical engine waveform.
    """
    steps = requested_steps_deg or [20.0, 10.0, 5.0, 2.0, 1.0, 0.5]
    cycle_deg = float(reference_trace["cycle_angle_deg"])
    cycle_rad = float(reference_trace["cycle_angle_rad"])
    source_steps = reference_trace["torque_steps"]
    start = float(source_steps[0]["theta_mid_deg"] - math.degrees(float(source_steps[0]["dtheta_rad"])) / 2.0)
    points = sorted((float(row["theta_mid_deg"]) - start,
                    float(row["gas_torque_nm"])) for row in source_steps)
    phases = [point[0] for point in points]
    torques = [point[1] for point in points]

    def torque_at(phase: float) -> float:
        x = phase % cycle_deg
        i = bisect.bisect_right(phases, x)
        if i == 0:
            x0, y0 = phases[-1] - cycle_deg, torques[-1]
            x1, y1 = phases[0], torques[0]
            x = x if x >= x0 else x + cycle_deg
        elif i >= len(phases):
            x0, y0 = phases[-1], torques[-1]
            x1, y1 = phases[0] + cycle_deg, torques[0]
        else:
            x0, y0 = phases[i - 1], torques[i - 1]
            x1, y1 = phases[i], torques[i]
        fraction = (x - x0) / (x1 - x0)
        return y0 + (y1 - y0) * fraction

    reference_work = float(reference_trace["net_pv_cycle_work_j"])
    results = []
    for requested in steps:
        bins = max(1, int(round(cycle_deg / requested)))
        h = cycle_deg / bins
        offset_rows = []
        for i in range(phase_offsets):
            offset = h * i / phase_offsets
            work = sum(torque_at(offset + (j + 0.5) * h) for j in range(bins)) * math.radians(h)
            offset_rows.append({"phase_offset_deg": offset,
                                "estimated_net_pv_work_j": work,
                                "error_fraction_vs_fine_reference": work / reference_work - 1.0})
        errors = [float(row["error_fraction_vs_fine_reference"]) for row in offset_rows]
        results.append({
            "requested_step_deg": requested,
            "uniform_bin_step_deg": h,
            "samples_per_cycle": bins,
            "phase_offsets_tested": phase_offsets,
            "max_abs_work_error_fraction": max(abs(error) for error in errors),
            "rms_work_error_fraction": math.sqrt(sum(error * error for error in errors) / len(errors)),
            "min_work_error_fraction": min(errors),
            "max_work_error_fraction": max(errors),
            "phase_rows": offset_rows,
        })
    return results


def propeller_load(rpm: float, axial_speed: float, rho: float, prop: dict[str, float]) -> dict[str, float | bool]:
    """Independent 12-annulus uniform-chord model plus the ideal forward-power lower bound."""
    omega = rpm * TAU / 60.0
    radius = 0.5 * prop["diameter_m"]
    dr = radius * 0.8 / 12.0
    thrust = 0.0
    torque = 0.0
    for i in range(12):
        r = radius * 0.2 + (i + 0.5) * dr
        tangential = omega * r
        speed2 = tangential * tangential + axial_speed * axial_speed
        if speed2 <= 0.0:
            continue
        speed = math.sqrt(speed2)
        phi = math.atan2(axial_speed, tangential)
        beta = math.atan2(prop["pitch_m"], TAU * r)
        alpha = beta - phi - prop.get("zero_lift_angle_rad", 0.0)  # EX-14f: from the zero-lift line
        cl = max(-1.25, min(1.25, prop["lift_slope"] * math.sin(2.0 * alpha) / 2.0))
        cd = prop["cd0"] + prop["induced_drag"] * cl * cl + 1.2 * math.sin(alpha) ** 2
        area_pressure = 0.5 * rho * speed2 * prop["chord_m"] * dr * prop["blades"]
        lift = area_pressure * cl
        drag = area_pressure * cd
        thrust += (lift * tangential - drag * axial_speed) / speed
        torque += (lift * axial_speed + drag * tangential) * r / speed
    shaft_power = torque * omega
    ideal_power = 0.0
    ratio = None
    bound_pass = True
    if thrust > 0.0 and axial_speed >= 0.0:
        area = math.pi * prop["diameter_m"] ** 2 / 4.0
        disk_speed = 0.5 * (axial_speed + math.sqrt(axial_speed ** 2 + 2.0 * thrust / (rho * area)))
        ideal_power = thrust * disk_speed
        ratio = shaft_power / ideal_power if ideal_power > 0.0 else None
        bound_pass = ratio is not None and ratio >= 1.0 - 1e-10
    return {"thrust_n": thrust, "torque_nm": torque, "shaft_power_w": shaft_power,
            "ideal_actuator_disk_power_w": ideal_power, "shaft_to_ideal_power_ratio": ratio,
            "ideal_power_bound_pass": bound_pass}


def installation_prop(path: Path) -> dict[str, float]:
    install = json.loads(path.read_text(encoding="utf-8"))
    prop = install["propeller"]
    out = {key: float(qvalue(prop, key)) for key in [
        "diameter_m", "pitch_m", "chord_m", "blades", "lift_slope", "cd0", "induced_drag"
    ]}
    if "zero_lift_angle_rad" in prop:  # EX-14f optional cambered section
        out["zero_lift_angle_rad"] = float(qvalue(prop, "zero_lift_angle_rad"))
    return out


def candidate_mean(profile: dict[str, Any], prop: dict[str, float], rpm: float,
                   axial_speed: float = DEFAULT_AIRSPEED_M_S,
                   rho: float = DEFAULT_RHO_KG_M3) -> dict[str, Any]:
    values = family_inputs(profile, rpm)
    load = propeller_load(rpm, axial_speed, rho, prop)
    return {**values, "propeller_torque_nm": load["torque_nm"],
            "propeller_load": load,
            "mean_cycle_residual_nm": values["candidate_mean_shaft_torque_nm"] - float(load["torque_nm"])}


def root_scan(residual: Callable[[float], float | None], lo: float, hi: float,
              step: float = 400.0, iterations: int = 24) -> list[dict[str, float]]:
    points: list[tuple[float, float | None]] = []
    n = int(math.ceil((hi - lo) / step))
    for i in range(n + 1):
        rpm = min(hi, lo + i * step)
        try:
            value = residual(rpm)
        except (ValueError, ArithmeticError, OverflowError):
            value = None
        if value is not None and not math.isfinite(value):
            value = None
        points.append((rpm, value))
    roots: list[dict[str, float]] = []
    for (left_rpm, left), (right_rpm, right) in zip(points, points[1:]):
        if left is None or right is None or not (left > 0.0 and right <= 0.0):
            continue
        a, b, fa = left_rpm, right_rpm, left
        for _ in range(iterations):
            mid = 0.5 * (a + b)
            fm = residual(mid)
            if fm is None or not math.isfinite(fm):
                b = mid
            elif fm > 0.0:
                a, fa = mid, fm
            else:
                b = mid
        root = 0.5 * (a + b)
        final = residual(root)
        roots.append({"rpm": root, "residual": float(final or 0.0),
                      "left_positive_right_nonpositive": 1.0})
    return roots


def angle_mean_root(profile: dict[str, Any], family: str, prop: dict[str, float],
                    assumptions: dict[str, Any], step_deg: float = 1.0,
                    axial_speed: float = DEFAULT_AIRSPEED_M_S,
                    rho: float = DEFAULT_RHO_KG_M3) -> list[dict[str, float]]:
    p = interp_parameters(profile)
    min_rpm = float(p["mechanical_torque_nm"][0][0])
    max_rpm = float(p["mechanical_torque_nm"][-1][0])
    angle = TAU if family == "glow_2t" else 2.0 * TAU
    cache: dict[float, float] = {}

    def residual(rpm: float) -> float:
        key = round(rpm, 5)
        if key not in cache:
            trace = simulate_cycle(profile, family, rpm, step_deg, assumptions)
            inp = family_inputs(profile, rpm)
            gas_mean = float(trace["net_pv_cycle_work_j"]) / angle
            if family == "glow_2t":
                losses = inp["mechanical_torque_nm"] + inp["pumping_torque_nm"]
            else:
                losses = inp["mechanical_torque_nm"] + inp["valve_torque_nm"]
            load = propeller_load(rpm, axial_speed, rho, prop)
            if not load["ideal_power_bound_pass"]:
                raise ValueError("annular load violates ideal actuator-disk lower bound")
            cache[key] = gas_mean - losses - float(load["torque_nm"])
        return cache[key]

    return root_scan(residual, min_rpm, max_rpm, step=400.0, iterations=18)


def mean_profile_roots(profile: dict[str, Any], prop: dict[str, float],
                       axial_speed: float = DEFAULT_AIRSPEED_M_S,
                       rho: float = DEFAULT_RHO_KG_M3) -> list[dict[str, float]]:
    p = interp_parameters(profile)
    lo = float(p["mechanical_torque_nm"][0][0])
    hi = float(p["mechanical_torque_nm"][-1][0])
    return root_scan(lambda rpm: candidate_mean(profile, prop, rpm, axial_speed, rho)[
        "mean_cycle_residual_nm"], lo, hi, step=200.0, iterations=20)


def periodic_cycle_map(trace: dict[str, Any], profile: dict[str, Any], family: str,
                       prop: dict[str, float], inertia_kg_m2: float, initial_rpm: float,
                       axial_speed: float = DEFAULT_AIRSPEED_M_S,
                       rho: float = DEFAULT_RHO_KG_M3,
                       reciprocating_mass_override_kg: float | None = None) -> dict[str, Any]:
    if inertia_kg_m2 <= 0.0 or initial_rpm <= 0.0:
        raise ValueError("inertia and initial RPM must be positive")
    omega0 = initial_rpm * TAU / 60.0
    steps = trace["torque_steps"]
    angle_start = float(steps[0]["theta_mid_deg"] - math.degrees(float(steps[0]["dtheta_rad"])) / 2.0)
    cycle_deg = float(trace["cycle_angle_deg"])
    cycle_angle = float(trace["cycle_angle_rad"])
    inertia_start = effective_rotor_inertia_kg_m2(
        angle_start, profile, inertia_kg_m2, reciprocating_mass_override_kg)
    energy0 = 0.5 * inertia_start * omega0 * omega0
    energy = energy0
    elapsed_s = 0.0
    min_rpm = initial_rpm
    max_rpm = initial_rpm
    effective_inertia_min = inertia_start
    effective_inertia_max = inertia_start
    p = interp_parameters(profile)
    for row in steps:
        theta0 = float(row["theta_mid_deg"] - math.degrees(float(row["dtheta_rad"])) / 2.0)
        theta_mid = float(row["theta_mid_deg"])
        step_rad = float(row["dtheta_rad"])
        inertia_here = effective_rotor_inertia_kg_m2(
            theta0, profile, inertia_kg_m2, reciprocating_mass_override_kg)
        inertia_mid = effective_rotor_inertia_kg_m2(
            theta_mid, profile, inertia_kg_m2, reciprocating_mass_override_kg)
        effective_inertia_min = min(effective_inertia_min, inertia_here, inertia_mid)
        effective_inertia_max = max(effective_inertia_max, inertia_here, inertia_mid)
        omega = math.sqrt(max(0.0, 2.0 * energy / inertia_here))
        rpm = omega * 60.0 / TAU
        if rpm <= 0.0:
            return {"ok": False, "stopped": True, "stop_theta_deg": theta_mid,
                    "start_rpm": initial_rpm, "net_cycle_energy_j": energy - energy0}

        def torque_at(test_energy: float, test_inertia: float) -> tuple[float, float, bool]:
            test_omega = math.sqrt(max(0.0, 2.0 * test_energy / test_inertia))
            test_rpm = test_omega * 60.0 / TAU
            load = propeller_load(test_rpm, axial_speed, rho, prop)
            if not load["ideal_power_bound_pass"]:
                return float("nan"), test_rpm, False
            mech = sample(p["mechanical_torque_nm"], test_rpm)
            if family == "glow_2t":
                pump = sample(p["scavenge_pressure_pa"], test_rpm) * float(p["displacement_m3"])
                pump *= sample(p["delivery_ratio"], test_rpm) / TAU
            else:
                # 4T gas-exchange PV work is already present in the trace.
                pump = 0.0
            valve = sample(p["valve_torque_nm"], test_rpm) if family == "glow_4t" else 0.0
            cycle_phase = ((theta_mid - angle_start) / cycle_deg) * TAU
            if family == "glow_2t":
                pump *= 1.0 + 0.20 * math.cos(cycle_phase)
            else:
                valve *= 1.0 + 0.20 * math.cos(cycle_phase)
            return float(row["gas_torque_nm"]) - mech - pump - valve - float(load["torque_nm"]), test_rpm, True

        tau0, _, ok = torque_at(energy, inertia_here)
        if not ok or not math.isfinite(tau0):
            return {"ok": False, "stopped": False, "reason": "ideal-power-bound refusal",
                    "start_rpm": initial_rpm, "net_cycle_energy_j": energy - energy0}
        e_mid = energy + 0.5 * tau0 * step_rad
        if e_mid <= 0.0:
            return {"ok": False, "stopped": True, "stop_theta_deg": theta_mid,
                    "start_rpm": initial_rpm, "net_cycle_energy_j": -energy0}
        tau_mid, rpm_mid, ok = torque_at(e_mid, inertia_mid)
        if not ok or not math.isfinite(tau_mid):
            return {"ok": False, "stopped": False, "reason": "ideal-power-bound refusal",
                    "start_rpm": initial_rpm, "net_cycle_energy_j": energy - energy0}
        energy += tau_mid * step_rad
        if energy <= 0.0 or not math.isfinite(energy):
            return {"ok": False, "stopped": True, "stop_theta_deg": theta_mid,
                    "start_rpm": initial_rpm, "net_cycle_energy_j": energy - energy0}
        omega_mid = math.sqrt(2.0 * e_mid / inertia_mid)
        elapsed_s += step_rad / omega_mid
        min_rpm = min(min_rpm, rpm_mid)
        max_rpm = max(max_rpm, rpm_mid)
    inertia_end = effective_rotor_inertia_kg_m2(
        angle_start + cycle_deg, profile, inertia_kg_m2, reciprocating_mass_override_kg)
    end_rpm = math.sqrt(2.0 * energy / inertia_end) * 60.0 / TAU
    time_average_rpm = cycle_angle / elapsed_s * 60.0 / TAU
    return {"ok": True, "stopped": False, "start_rpm": initial_rpm, "end_rpm": end_rpm,
            "time_average_rpm": time_average_rpm, "min_rpm": min_rpm, "max_rpm": max_rpm,
            "cycle_time_s": elapsed_s, "net_cycle_energy_j": energy - energy0,
            "cycle_work_from_pressure_j": trace["net_pv_cycle_work_j"],
            "installed_rotor_inertia_kg_m2": inertia_kg_m2,
            "profile_reciprocating_mass_kg": (
                float(p["reciprocating_mass_kg"])
                if reciprocating_mass_override_kg is None
                else float(reciprocating_mass_override_kg)),
            "effective_inertia_min_kg_m2": effective_inertia_min,
            "effective_inertia_max_kg_m2": effective_inertia_max,
            "effective_inertia_ripple_fraction": effective_inertia_max / effective_inertia_min - 1.0,
            "ideal_power_bound_refusals": 0}


def dynamic_orbit_roots(profile: dict[str, Any], family: str, prop: dict[str, float],
                        assumptions: dict[str, Any], inertia_kg_m2: float,
                        step_deg: float, axial_speed: float = DEFAULT_AIRSPEED_M_S,
                        rho: float = DEFAULT_RHO_KG_M3,
                        reciprocating_mass_override_kg: float | None = None) -> list[dict[str, Any]]:
    p = interp_parameters(profile)
    lo = max(1000.0, float(p["mechanical_torque_nm"][0][0]))
    hi = float(p["mechanical_torque_nm"][-1][0])
    cache: dict[float, dict[str, Any]] = {}

    def outcome(rpm: float) -> dict[str, Any]:
        key = round(rpm, 3)
        if key not in cache:
            trace = simulate_cycle(profile, family, rpm, step_deg, assumptions)
            cache[key] = periodic_cycle_map(trace, profile, family, prop, inertia_kg_m2,
                                            rpm, axial_speed, rho,
                                            reciprocating_mass_override_kg)
        return cache[key]

    def residual(rpm: float) -> float | None:
        result = outcome(rpm)
        if not result.get("ok"):
            if result.get("stopped"):
                return -1e6
            return None
        return float(result["net_cycle_energy_j"])

    points = []
    n = int(math.ceil((hi - lo) / 400.0))
    for i in range(n + 1):
        rpm = min(hi, lo + i * 400.0)
        val = residual(rpm)
        points.append((rpm, val))
    roots: list[dict[str, Any]] = []
    for (left, fl), (right, fr) in zip(points, points[1:]):
        if fl is None or fr is None or not (fl > 0.0 and fr <= 0.0):
            continue
        a, b = left, right
        for _ in range(16):
            mid = 0.5 * (a + b)
            fm = residual(mid)
            if fm is None or fm <= 0.0:
                b = mid
            else:
                a = mid
        root = 0.5 * (a + b)
        result = outcome(root)
        roots.append({"rpm": root, **result})
    return roots


def run_family(family: str) -> dict[str, Any]:
    config = ENGINES[family]
    profile_path = PROFILE_DIR / config["profile"]
    install_path = PROFILE_DIR / config["installation"]
    aircraft_path = ROOT / "app" / "data" / "aircraft" / config["aircraft"]
    profile_raw = profile_path.read_bytes()
    profile = json.loads(profile_raw)
    install_raw = install_path.read_bytes()
    install = json.loads(install_raw)
    aircraft_raw = aircraft_path.read_bytes()
    aircraft = json.loads(aircraft_raw)
    rotating_inertia = float(qvalue(aircraft["propulsion"]["propeller"], "rotating_inertia"))
    prop = installation_prop(install_path)
    if profile["family"] != family or install["family"] != family:
        raise ValueError(f"family mismatch for {family}")
    rated_rpm = float(qvalue(profile["operation"], "rated_rpm"))
    recommended_engine_rpm = float(qvalue(profile["operation"], "recommended_max_rpm"))
    generated_search_support_rpm = float(qvalue(profile["operation"], "max_rpm"))
    installed_prop_rpm_limit = float(qvalue(install["propeller"], "max_rpm"))
    installed_prop_name = str(aircraft["propulsion"]["propeller"]["name"])
    nominal = dict(config["nominal"])
    nominal["rod_to_crank_ratio"] = float(qvalue(profile["parameters"], "rod_to_crank_radius_ratio"))
    profile_geometry = {key: profile["parameters"][key] for key in [
        "bore_m", "stroke_m", "rod_to_crank_radius_ratio", "reciprocating_mass_kg"
    ]}
    convergence = []
    traces: dict[float, dict[str, Any]] = {}
    for step in ANGLE_STEPS_DEG:
        trace = simulate_cycle(profile, family, rated_rpm, step, nominal)
        traces[step] = trace
        convergence.append({
            "step_deg_max": step, "steps": trace["step_count"],
            "cycle_work_j": trace["cycle_work_j"],
            "cycle_work_error_vs_finest_fraction": None,
            "net_pv_cycle_work_j": trace["net_pv_cycle_work_j"],
            "net_pv_cycle_work_error_vs_finest_fraction": None,
            "peak_pressure_pa": trace["peak_pressure_pa"],
            "energy_residual_j": trace["closed_energy_first_law_residual_j"],
            "samples_across_wiebe_burn": float(nominal["burn_duration_deg"]) / step,
        })
    finest_work = float(traces[ANGLE_STEPS_DEG[-1]]["cycle_work_j"])
    finest_net_work = float(traces[ANGLE_STEPS_DEG[-1]]["net_pv_cycle_work_j"])
    finest_peak = float(traces[ANGLE_STEPS_DEG[-1]]["peak_pressure_pa"])
    for row in convergence:
        row["cycle_work_error_vs_finest_fraction"] = (
            float(row["cycle_work_j"]) / finest_work - 1.0 if finest_work else None
        )
        row["net_pv_cycle_work_error_vs_finest_fraction"] = (
            float(row["net_pv_cycle_work_j"]) / finest_net_work - 1.0 if finest_net_work else None
        )
        row["peak_pressure_error_vs_finest_fraction"] = (
            float(row["peak_pressure_pa"]) / finest_peak - 1.0 if finest_peak else None
        )

    finest = traces[ANGLE_STEPS_DEG[-1]]
    unlocked_phase_sampling = unlocked_phase_sampling_audit(finest)
    p = interp_parameters(profile)
    prop_at_speed = propeller_load(rated_rpm, DEFAULT_AIRSPEED_M_S, DEFAULT_RHO_KG_M3, prop)
    profile_roots = mean_profile_roots(profile, prop)
    thermo_roots = angle_mean_root(profile, family, prop, nominal, step_deg=1.0)
    candidate_mean_root = profile_roots[-1]["rpm"] if profile_roots else None
    thermodynamic_mean_root = thermo_roots[-1]["rpm"] if thermo_roots else None
    if candidate_mean_root is not None:
        candidate_root_point = candidate_mean(profile, prop, candidate_mean_root)
    else:
        candidate_root_point = None
    if thermodynamic_mean_root is not None:
        oracle_root_trace = simulate_cycle(profile, family, thermodynamic_mean_root, 0.25, nominal)
        oracle_root_inputs = family_inputs(profile, thermodynamic_mean_root)
        oracle_root_mean_point = {
            "rpm": thermodynamic_mean_root,
            "cycle_work_j": oracle_root_trace["cycle_work_j"],
            "net_pv_cycle_work_j": oracle_root_trace["net_pv_cycle_work_j"],
            "pressure_work_rate_w_at_mean_rpm": oracle_root_trace["cycle_work_j"] * oracle_root_inputs["opportunity_hz"],
            "net_pv_work_rate_w_at_mean_rpm": oracle_root_trace["net_pv_cycle_work_j"] * oracle_root_inputs["opportunity_hz"],
            "burned_fuel_flow_kg_s_at_mean_rpm": oracle_root_inputs["burned_fuel_flow_kg_s"],
            "mean_pressure_torque_nm": oracle_root_trace["net_pv_cycle_work_j"] / finest["cycle_angle_rad"],
            "vs_profile_candidate_kernel_work_fraction": (
                oracle_root_trace["cycle_work_j"] / oracle_root_inputs["cycle_work_j"] - 1.0
            ),
        }
    else:
        oracle_root_mean_point = None

    orbit_by_inertia = []
    inertia_scenarios = [rotating_inertia * multiplier for multiplier in INERTIA_SENSITIVITY_MULTIPLIERS]
    for multiplier, inertia in zip(INERTIA_SENSITIVITY_MULTIPLIERS, inertia_scenarios):
        roots = dynamic_orbit_roots(profile, family, prop, nominal, inertia,
                                    step_deg=0.5)
        for root in roots:
            mean_inputs = family_inputs(profile, float(root["time_average_rpm"]))
            root["burned_fuel_flow_kg_s_at_time_average_rpm"] = mean_inputs["burned_fuel_flow_kg_s"]
            root["delivered_premix_flow_kg_s_at_time_average_rpm"] = mean_inputs["delivered_premix_flow_kg_s"]
            root["pressure_work_rate_w_at_time_average_rpm"] = (
                float(root["cycle_work_from_pressure_j"]) * mean_inputs["opportunity_hz"]
            )
        orbit_by_inertia.append({"installed_inertia_multiplier": multiplier,
                                 "inertia_kg_m2": inertia,
                                 "periodic_orbit_roots": roots,
                                 "selected_restoring_orbit": roots[-1] if roots else None})

    # Perturb the profile's equivalent piston mass around the primary orbit at
    # its selected speed. These are one-cycle comparisons, not re-solved roots.
    primary_orbit = orbit_by_inertia[1]["selected_restoring_orbit"]
    reciprocating_mass_sensitivity = []
    if primary_orbit:
        primary_rpm = float(primary_orbit["rpm"])
        primary_trace = simulate_cycle(profile, family, primary_rpm, 0.5, nominal)
        baseline_mass_map = periodic_cycle_map(
            primary_trace, profile, family, prop, rotating_inertia, primary_rpm)
        profile_recip_mass = float(qvalue(profile["parameters"], "reciprocating_mass_kg"))
        for multiplier in [0.4, 2.0]:
            perturbed_mass = profile_recip_mass * multiplier
            result = periodic_cycle_map(
                primary_trace, profile, family, prop, rotating_inertia, primary_rpm,
                reciprocating_mass_override_kg=perturbed_mass)
            reciprocating_mass_sensitivity.append({
                "profile_mass_multiplier": multiplier,
                "reciprocating_mass_kg": perturbed_mass,
                "one_cycle_map_at_primary_initial_rpm": result,
                "net_cycle_energy_delta_vs_profile_mass_j": (
                    result.get("net_cycle_energy_j") - baseline_mass_map.get("net_cycle_energy_j")
                    if result.get("ok") and baseline_mass_map.get("ok") else None
                ),
                "equilibrium_re_solved": False,
            })

    # Resolution-dependent periodic maps expose angular sampling sensitivity of the
    # crank-energy solve, at the middle (unmeasured) inertia scenario.
    resolution_rows = []
    mid_inertia = rotating_inertia
    for step in [4.0, 2.0, 1.0, 0.5, 0.25, 0.125]:
        roots = dynamic_orbit_roots(profile, family, prop, nominal, mid_inertia, step)
        selected = roots[-1] if roots else None
        resolution_rows.append({"step_deg_max": step,
                                "selected_restoring_orbit": selected,
                                "root_count": len(roots)})
    fine_orbit = next((r["selected_restoring_orbit"] for r in resolution_rows
                       if r["step_deg_max"] == 0.125), None)
    if fine_orbit:
        for row in resolution_rows:
            orbit = row["selected_restoring_orbit"]
            row["time_average_rpm_error_vs_0_125deg_fraction"] = (
                orbit["time_average_rpm"] / fine_orbit["time_average_rpm"] - 1.0
                if orbit and fine_orbit["time_average_rpm"] else None
            )

    sensitivity_fields = ["compression_ratio", "gamma", "heat_to_gas_fraction",
                          "residual_mass_fraction", "trapped_temperature_k",
                          "combustion_start_deg_btdc", "burn_duration_deg"]
    if family == "glow_2t":
        sensitivity_fields += ["exhaust_open_deg_atdc", "transfer_open_deg_atdc",
                               "transfer_close_deg_atdc", "exhaust_close_deg_atdc"]
    else:
        sensitivity_fields += ["exhaust_open_deg_atdc", "intake_open_deg_before_exhaust_tdc",
                               "exhaust_close_deg_after_exhaust_tdc", "intake_close_deg_abdc"]
    sensitivity = []
    for field in sensitivity_fields:
        lo, hi = config["bounds"][field]
        for label, value in [("low", lo), ("high", hi)]:
            case = dict(nominal)
            case[field] = value
            trace = simulate_cycle(profile, family, rated_rpm, 0.5, case)
            sensitivity.append({"parameter": field, "case": label, "value": value,
                                "cycle_work_j": trace["cycle_work_j"],
                                "delta_vs_nominal_fraction": trace["cycle_work_j"] / finest_work - 1.0,
                                "peak_pressure_pa": trace["peak_pressure_pa"]})
    work_scenarios = [row["cycle_work_j"] for row in sensitivity]
    nominal_trace = simulate_cycle(profile, family, rated_rpm, 0.25, nominal)
    profile_rating = family_inputs(profile, rated_rpm)
    if family == "glow_2t":
        raw_events = {"EPO_deg_ATDC": nominal["exhaust_open_deg_atdc"],
                      "TPO_deg_ATDC": nominal["transfer_open_deg_atdc"],
                      "TPC_deg_ATDC": nominal["transfer_close_deg_atdc"],
                      "EPC_deg_ATDC": nominal["exhaust_close_deg_atdc"]}
    else:
        raw_events = {"EVO_deg_ATDC": nominal["exhaust_open_deg_atdc"],
                      "IVO_deg_before_exhaust_TDC": nominal["intake_open_deg_before_exhaust_tdc"],
                      "EVC_deg_after_exhaust_TDC": nominal["exhaust_close_deg_after_exhaust_tdc"],
                      "IVC_deg_ABDC": nominal["intake_close_deg_abdc"]}

    return {
        "engine_id": profile["id"], "family": family,
        "manufacturer_geometry_and_profile_estimates": profile_geometry,
        "inputs": {
            "profile_path": profile_path.relative_to(ROOT).as_posix(), "profile_sha256": hashlib.sha256(profile_raw).hexdigest(),
            "installation_path": install_path.relative_to(ROOT).as_posix(), "installation_sha256": hashlib.sha256(install_raw).hexdigest(),
            "aircraft_path": aircraft_path.relative_to(ROOT).as_posix(), "aircraft_sha256": hashlib.sha256(aircraft_raw).hexdigest(),
            "installed_rotor_inertia_kg_m2": rotating_inertia,
            "installed_rotor_inertia_source": aircraft["propulsion"]["propeller"]["rotating_inertia"],
            "reciprocating_mass_source": profile["parameters"]["reciprocating_mass_kg"],
            "family_kernel_path": f"app/physics/glow/{'two_stroke.gd' if family == 'glow_2t' else 'four_stroke.gd'}",
            "family_kernel_sha256": sha256(ROOT / "app" / "physics" / "glow" / ("two_stroke.gd" if family == "glow_2t" else "four_stroke.gd")),
            "propeller_kernel_path": "app/physics/glow/propeller.gd",
            "propeller_kernel_sha256": sha256(ROOT / "app" / "physics" / "glow" / "propeller.gd"),
            "profile_status": profile["status"],
            "assumed_installed_propeller_parameters": prop,
            "fixed_carrier_axial_speed_m_s": DEFAULT_AIRSPEED_M_S,
            "air_density_kg_m3": DEFAULT_RHO_KG_M3,
            "mixture_equivalence_ratio": DEFAULT_MIXTURE,
            "admission": DEFAULT_ADMISSION,
            "firing_fraction": DEFAULT_FIRING_FRACTION,
            "mean_model_cycle_frequency_hz_at_rated": profile_rating["opportunity_hz"],
            "profile_rated_rpm": rated_rpm,
            "profile_recommended_engine_max_rpm": recommended_engine_rpm,
            "generated_profile_search_support_max_rpm_not_runtime_cap": generated_search_support_rpm,
            "installed_propeller_name": installed_prop_name,
            "installed_propeller_rpm_limit": install["propeller"]["max_rpm"],
        },
        "provenance": {
            "engine_displacement_bore_stroke": "O.S. manufacturer dimensions from the linked product page; displacement checked against bore×stroke.",
            "compression_ratio_rod_ratio_port_valve_events_gamma_heat_transfer_residual_temperature": "Not published for these candidate engines; explicit engineering assumptions and ranges below.",
            "fuel_formula": "Candidate profile fuel properties use AIAA-2016-5011 Table 1 for Omega 10% (72% methanol, 10% nitromethane, 18% castor oil by volume), the same blend tested with O.S. MAX-55AX 2-cycle and O.S. FS 56-a 4-cycle engines. Fuel properties alone are borrowed; the paper's engine-output results are not used as calibration targets, and FS 56-a is not FS-64V.",
            "combustion_law": "Normalized single-Wiebe prescribed mass-burn fraction, used as an assumed heat-release shape; not inferred from measured cylinder pressure.",
            "profile_comparison": "The source candidate kernel computes cycle work as burned fuel × LHV × a generated indicated-efficiency table. The pressure oracle instead integrates a crank-angle first-law pressure-volume path; disagreement compares two inferred closures, not measurement error.",
            "dynamic_comparison": "The periodic crank-energy map uses the independent pressure trace plus exact installed candidate prop parameters and RPM-varying annular load. It is a fixed-carrier software experiment; no in-flight, prop-map or physical-engine validation is implied.",
        },
        "nominal_assumptions": nominal,
        "explicit_one_factor_sensitivity_bounds": config["bounds"],
        "nominal_port_or_valve_events": raw_events,
        "rated_point": {
            "rpm": rated_rpm,
            "rpm_constraint_check": {
                "profile_recommended_engine_max_rpm": recommended_engine_rpm,
                "installed_propeller_max_rpm": installed_prop_rpm_limit,
                "within_both_recommended_limits": rated_rpm <= min(recommended_engine_rpm, installed_prop_rpm_limit),
                "interpretation": "A rating point above the installed propeller limit is retained as a manufacturer engine reference point, not a valid installed operating prediction.",
            },
            "profile_candidate_mean_cycle": profile_rating,
            "pressure_oracle_indicated_work_rate_w": nominal_trace["cycle_work_j"] * profile_rating["opportunity_hz"],
            "pressure_oracle_net_pv_work_rate_w": nominal_trace["net_pv_cycle_work_j"] * profile_rating["opportunity_hz"],
            "candidate_profile_burned_fuel_flow_kg_s": profile_rating["burned_fuel_flow_kg_s"],
            "candidate_profile_delivered_premix_flow_kg_s": profile_rating["delivered_premix_flow_kg_s"],
            "thermodynamic_pressure_oracle": {k: v for k, v in nominal_trace.items() if k != "torque_steps"},
            "fixed_carrier_propeller_at_rated": prop_at_speed,
            "one_factor_work_sensitivity_min_j": min(work_scenarios),
            "one_factor_work_sensitivity_max_j": max(work_scenarios),
            "sensitivity_interpretation": "Unweighted one-factor scenario endpoints; not a confidence interval or physical bound.",
        },
        "mean_root_comparisons": {
            "assumption": "Full admission, static 0 m/s carrier, 1.225 kg/m^3; restoring roots only.",
            "rpm_limit_checks": {
                "profile_recommended_engine_max_rpm": recommended_engine_rpm,
                "installed_propeller_max_rpm": installed_prop_rpm_limit,
                "profile_candidate_mean_root_within_both": (
                    bool(profile_roots) and profile_roots[-1]["rpm"] <= min(recommended_engine_rpm, installed_prop_rpm_limit)),
                "pressure_oracle_mean_root_within_both": (
                    bool(thermo_roots) and thermo_roots[-1]["rpm"] <= min(recommended_engine_rpm, installed_prop_rpm_limit)),
                "periodic_orbit_time_average_within_both": (
                    bool(orbit_by_inertia[1]["selected_restoring_orbit"])
                    and orbit_by_inertia[1]["selected_restoring_orbit"]["time_average_rpm"]
                    <= min(recommended_engine_rpm, installed_prop_rpm_limit)),
            },
            "inertia_sensitivity_method": "Primary periodic orbit uses the aircraft configuration's installed rotating_inertia value. Sensitivity cases use 0.5× and 2× that estimate; rotating mass distribution and crank contribution are not measured. The profile's separate estimated equivalent piston mass is included as angle-dependent inertia, with one-cycle 1%-to-5%-of-dry-mass perturbations around the primary speed (not re-solved equilibria).",
            "profile_candidate_mean_cycle_roots": profile_roots,
            "profile_candidate_mean_cycle_selected_root": candidate_root_point,
            "pressure_oracle_angle_mean_roots": thermo_roots,
            "pressure_oracle_angle_mean_selected_point": oracle_root_mean_point,
            "cycle_resolved_periodic_orbit_by_inertia": orbit_by_inertia,
            "reciprocating_mass_one_cycle_sensitivity": reciprocating_mass_sensitivity,
            "resolution_sweep_at_mid_inertia": resolution_rows,
            "averaging_error_scope": "At each declared inferred pressure/flow/timing/inertia hypothesis, compare the angle-averaged pressure-work balance to the periodic crank-energy solution using the same pressure-work cycle and installed prop load. The profile-root difference additionally includes different inferred engine work/loss closures; neither comparison establishes empirical accuracy.",
        },
        "quadrature_and_anti_alias_audit": {
            "reference_step_deg": ANGLE_STEPS_DEG[-1],
            "event_aligned_pressure_work_resolution_sweep": convergence,
            "unlocked_uniform_phase_sampling_of_fine_pressure_torque": unlocked_phase_sampling,
            "dynamic_periodic_resolution_sweep": resolution_rows,
            "interpretation": "The event-aligned sweep tests crank-angle quadrature resolution. The separate phase sweep intentionally does not align coarse uniform samples to events and quantifies phase-sensitive midpoint integration error for the fine prescribed waveform. This does not prove that a runtime physics step aliases a real engine waveform.",
        },
        "one_factor_sensitivity_rows": sensitivity,
        "status": {
            "numerical_first_law_closure": "checked for closed portions only",
            "independent_thermodynamic_convergence": "evaluated by step refinement; see sweep",
            "mean_reduction_comparison": "computed for the stated inferred hypotheses only",
            "physical_engine_validation": "NOT PERFORMED",
            "physical_propeller_validation": "NOT PERFORMED",
            "independent_held_out_validation": "NOT PERFORMED",
            "experienced_pilot_validation": "NOT PERFORMED",
        },
    }


def report() -> dict[str, Any]:
    return {
        "format": "openrc-glow-crank-angle-oracle v1",
        "generated_by": "research/glow-engines/cycle_oracle.py",
        "source_sha256": sha256(Path(__file__).resolve()),
        "method": {
            "closed_system": "Slider-crank cylinder volume and 1-zone ideal-gas first-law update, conservative midpoint pressure work; heat-release interval follows normalized Wiebe law.",
            "two_stroke": "One 360-degree ported cycle. EPC-trapped charge is compressed/combusted/expanded to EPO; estimated exhaust blowdown, transfer-pressure interval and exhaust tail close the gas-exchange path; crankcase scavenge pump loss remains separate.",
            "four_stroke": "One 720-degree true four-stroke cycle. IVC-trapped charge is compressed/combusted/expanded to EVO; separate exhaust/intake valve-open boundary-pressure path closes the cycle; open-system mass/enthalpy exchange is not solved.",
            "energy_state": "Cycle-resolved kinetic energy uses d(0.5*J_eff(theta)*omega^2)/d(theta)=net torque; J_eff adds the profile's estimated equivalent piston mass times slider-crank (dy/dtheta)^2 to the aircraft configuration's installed rotor inertia. Prop load is reevaluated at instantaneous angular speed and integrated with a midpoint energy update. Rod angular kinetic energy and connecting-rod distribution are omitted.",
            "combustion_waveform_during_speed_ripple": "A full pressure/torque waveform is generated at each candidate mean RPM, then held fixed over that one-cycle energy map. Instantaneous propeller and table-based mechanical/pump/valve losses vary with RPM; charge, fuel, and combustion do not adapt within the cycle. This is a conditional averaging-error experiment, not a transient engine model.",
            "propeller_load": "Independent reproduction of current 12-annulus, uniform-chord installed-prop surrogate, followed by the ideal actuator-disk lower-bound refusal for positive static thrust.",
            "phase_alias_probe": "Coarse uniform-angle midpoint sampling of a 0.0625-degree reference pressure-torque waveform, with 16 grid-phase offsets; linear interpolation only supplies sample values. This reports numerical alias sensitivity for an inferred waveform and is not a measurement or runtime fixed-dt test.",
            "fixed_carrier": "The carrier is held at zero axial speed. This isolates an installed prop/engine pair and is not free-flight behavior.",
        },
        "primary_method_references": [
            {"title": "Computer simulation of a four stroke spark ignition engine", "url": "https://www.sciencedirect.com/science/article/pii/S0196890401000929", "use": "Single-zone crank-angle heat-release and pressure-volume work method precedent; model/measurements are not imported."},
            {"title": "Modelling Methodology of a Spark-Ignition Engine and Experimental Validation: Part I: Single-Zone Combustion Model", "url": "https://saemobilus.sae.org/papers/modelling-methodology-a-spark-ignition-engine-experimental-validation-part-i-single-zone-combustion-model-2002-01-2193", "use": "Crank-angle-resolved single-zone combustion formulation; engine-specific measured calibration is not imported."},
            {"title": "Mathematical modeling of the two-stroke crankcase scavenged spark ignition engine working process", "url": "https://doi.org/10.1016/j.ecmx.2021.100086", "use": "Supports treating two-stroke port exchange and scavenging as distinct from the closed compression/expansion segment; its multi-zone flow method is more detailed than this reduced estimate."},
            {"title": "Simulation of a Crankcase Scavenged, Two-Stroke, SI Engine and Comparisons with Experimental Data", "url": "https://saemobilus.sae.org/papers/simulation-a-crankcase-scavenged-two-stroke-si-engine-comparisons-experimental-data-690135", "use": "Coupled crankcase/cylinder/inlet control-volume precedent; highlights what this single-zone port-boundary oracle omits."},
            {"title": "O.S. MAX-55AX manufacturer specifications", "url": "https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm", "use": "Bore, stroke, displacement and engine identity for the 2T candidate."},
            {"title": "O.S. FS-64V manufacturer specifications", "url": "https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html", "use": "Bore, stroke, displacement and engine identity for the 4T candidate."},
            {"title": "Development And Analysis of a Group 1 UAV Series Hybrid Power System with Two Engine Options (AIAA 2016-5011)", "url": "https://doi.org/10.2514/6.2016-5011", "use": "Table 1 gives Omega 10% fuel properties for the same blend tested with O.S. MAX-55AX (2-cycle) and O.S. FS 56-a (4-cycle). The paper's engine-output data are not imported as calibration targets here; FS 56-a is not FS-64V."},
        ],
        "limitations": [
            "Neither manufacturer publishes these candidates' compression ratio, connecting-rod ratio, port/valve timing, in-cylinder pressure trace, heat-transfer history, residual fraction or engine rotating inertia.",
            "Open-system scavenging/intake/exhaust boundary pressures are imposed estimates; mass exchange, short-circuit fuel loss, crankcase dynamics, exhaust resonance, variable properties, wall heat transfer and glow ignition kinetics are not solved.",
            "AIAA-2016-5011 reports O.S. MAX-55AX 2-cycle and O.S. FS 56-a 4-cycle engine results using the Omega 10% blend. Its Table 1 fuel properties are borrowed; its engine-output results are not imported as calibration targets in this pressure oracle, and FS 56-a is not FS-64V.",
            "The profile root and pressure-oracle root use different candidate closures. Only the within-oracle angle-mean versus periodic-map comparison tests the mean reduction numerically for the declared waveform; no result proves actual engine accuracy.",
            "The annular propeller method preserves estimated uniform chord/section coefficients. Its dynamic evaluation and ideal-power lower bound do not constitute a measured propeller map or aircraft data.",
        ],
        "engines": {family: run_family(family) for family in ENGINES},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write cycle-oracle.json in the NITRO-02 dossier")
    args = parser.parse_args()
    result = report()
    encoded = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.write:
        DOC_DIR.mkdir(parents=True, exist_ok=True)
        (DOC_DIR / "cycle-oracle.json").write_text(encoded, encoding="utf-8")
        print(f"Wrote {DOC_DIR / 'cycle-oracle.json'}")
    else:
        print(encoded)


if __name__ == "__main__":
    main()
