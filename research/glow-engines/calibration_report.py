"""Build reproducible, inference-only reports from the current glow candidates.

This is an algebraic profile audit, not a curve fitter: it checks the
manufacturer rated-power identity and exposes candidate-model outputs and local
sensitivities. No measured shaft-torque points are read or manufactured here;
one RPM-only prop configuration conditions a clearly labeled chord surrogate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PROFILE_DIR = ROOT / "app" / "data" / "glow"
DOSSIER_DIR = ROOT / "docs" / "research" / "glow-engines"
PROFILE_NAMES = {
    "glow_2t": "os_max_55ax_candidate.json",
    "glow_4t": "os_fs_64v_candidate.json",
}
MANUFACTURER_PRACTICAL_RPM = {
    "glow_2t": [2000.0, 17000.0],
    "glow_4t": [2400.0, 11000.0],
}
DOSSIER_NAMES = {
    "glow_2t": "NITRO-2T/calibration_report.json",
    "glow_4t": "NITRO-4T/calibration_report.json",
}
PS_W = 735.49875
TAU = math.tau


def qvalue(group: dict[str, Any], key: str) -> Any:
    return group[key]["value"]


def sample(table: list[list[float]], x: float) -> float:
    if x < table[0][0] or x > table[-1][0]:
        raise ValueError(f"query {x} is outside profile support [{table[0][0]}, {table[-1][0]}]")
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            f = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * f
    return table[-1][1]


def fuel_basis(profile: dict[str, Any]) -> dict[str, float]:
    f = {k: qvalue(profile["fuel"], k) for k in profile["fuel"]}
    nitro = f["nitromethane_volume_fraction"]
    oil = f["lubricant_volume_fraction"]
    if nitro + oil >= 1:
        raise ValueError("profile fuel has no methanol volume remaining")
    component_mass_per_m3 = {
        "methanol": (1.0 - nitro - oil) * f["methanol_density_kg_m3"],
        "nitromethane": nitro * f["nitromethane_density_kg_m3"],
        "oil": oil * f["lubricant_density_kg_m3"],
    }
    total_density = sum(component_mass_per_m3.values())
    combustible_mass = component_mass_per_m3["methanol"] + component_mass_per_m3["nitromethane"]
    oil_fraction = component_mass_per_m3["oil"] / total_density
    afr = (
        component_mass_per_m3["methanol"] * f["methanol_stoich_air_fuel_ratio"]
        + component_mass_per_m3["nitromethane"] * f["nitromethane_stoich_air_fuel_ratio"]
    ) / combustible_mass
    lhv = (
        component_mass_per_m3["methanol"] * f["methanol_lhv_j_kg"]
        + component_mass_per_m3["nitromethane"] * f["nitromethane_lhv_j_kg"]
    ) / combustible_mass
    return {
        "total_premix_density_kg_m3": total_density,
        "oil_mass_fraction_of_premix": oil_fraction,
        "combustible_stoichiometric_air_fuel_ratio": afr,
        "combustible_lhv_j_kg": lhv,
        "methanol_mass_per_premix_m3_kg": component_mass_per_m3["methanol"],
        "nitromethane_mass_per_premix_m3_kg": component_mass_per_m3["nitromethane"],
        "oil_mass_per_premix_m3_kg": component_mass_per_m3["oil"],
    }


def evaluate(
    profile: dict[str, Any],
    rpm: float,
    admission: float = 1.0,
    mixture: float | None = None,
    firing_fraction: float = 1.0,
    charge_scale: float = 1.0,
    indicated_efficiency_scale: float = 1.0,
    losses_scale: float = 1.0,
) -> dict[str, float]:
    """Independent scalar reconstruction of the documented mean-cycle equations."""
    if not 0.0 <= admission <= 1.0 or not 0.0 <= firing_fraction <= 1.0:
        raise ValueError("admission and firing fraction must be in [0, 1]")
    p = {k: qvalue(profile["parameters"], k) for k in profile["parameters"]}
    op = {k: qvalue(profile["operation"], k) for k in profile["operation"]}
    basis = fuel_basis(profile)
    mixture = op["nominal_mixture"] if mixture is None else mixture
    oil_fraction = basis["oil_mass_fraction_of_premix"]
    stoich = basis["combustible_stoichiometric_air_fuel_ratio"]
    lhv = basis["combustible_lhv_j_kg"]
    density = op["reference_dry_density_kg_m3"]
    displacement = p["displacement_m3"]
    angle = TAU if profile["family"] == "glow_2t" else 2.0 * TAU
    omega = TAU * rpm / 60.0

    if profile["family"] == "glow_2t":
        delivery = sample(p["delivery_ratio"], rpm)
        trap = sample(p["trapping_efficiency"], rpm)
        air_per_cycle = density * displacement * admission * delivery * trap * charge_scale
        pump_pressure = sample(p["scavenge_pressure_pa"], rpm)
        pumping_torque = pump_pressure * displacement * delivery * admission / angle
        valve_torque = 0.0
        opportunity_hz = rpm / 60.0
    elif profile["family"] == "glow_4t":
        ve = sample(p["volumetric_efficiency"], rpm)
        air_per_cycle = density * displacement * admission * ve * charge_scale
        intake_drop = p["intake_pressure_drop_pa"]
        pump_pressure = sample(p["pumping_pressure_pa"], rpm) + intake_drop * (1.0 - admission)
        pumping_torque = pump_pressure * displacement / angle
        valve_torque = sample(p["valve_torque_nm"], rpm)
        opportunity_hz = rpm / 120.0
    else:
        raise ValueError(f"unsupported family: {profile['family']}")

    mechanical_torque = sample(p["mechanical_torque_nm"], rpm)
    gross_premix_cycle = air_per_cycle * mixture / stoich / (1.0 - oil_fraction)
    gross_combustible_cycle = gross_premix_cycle * (1.0 - oil_fraction)
    stoich_combustible_cycle = air_per_cycle / stoich
    combustion_efficiency = sample(p["combustion_efficiency"], mixture)
    indicated_efficiency = min(1.0, sample(p["indicated_efficiency"], rpm) * indicated_efficiency_scale)
    burned_combustible_cycle = (
        min(gross_combustible_cycle, stoich_combustible_cycle)
        * combustion_efficiency
        * firing_fraction
    )
    cycle_work = burned_combustible_cycle * lhv * indicated_efficiency
    indicated_torque = cycle_work / angle
    mechanical_torque *= losses_scale
    pumping_torque *= losses_scale
    valve_torque *= losses_scale
    shaft_torque = indicated_torque - mechanical_torque - pumping_torque - valve_torque
    delivered_flow = gross_premix_cycle * opportunity_hz
    burned_flow = burned_combustible_cycle * opportunity_hz
    unburned_flow = max(0.0, delivered_flow - burned_flow)
    return {
        "rpm": rpm,
        "admission": admission,
        "mixture_equivalence": mixture,
        "indicated_torque_nm": indicated_torque,
        "mechanical_torque_nm": mechanical_torque,
        "pumping_torque_nm": pumping_torque,
        "valve_torque_nm": valve_torque,
        "brake_shaft_torque_nm": shaft_torque,
        "brake_shaft_power_w": shaft_torque * omega,
        "cycle_work_j": cycle_work,
        "opportunity_frequency_hz": opportunity_hz,
        "nominal_firing_frequency_hz": opportunity_hz * firing_fraction if burned_flow > 0 else 0.0,
        "delivered_premix_kg_s": delivered_flow,
        "burned_combustible_kg_s": burned_flow,
        "unburned_premix_kg_s": unburned_flow,
        "delivered_premix_ml_min": delivered_flow / basis["total_premix_density_kg_m3"] * 60.0e6,
    }


def annular_static_prop_torque(
    rpm: float,
    diameter_m: float,
    pitch_m: float,
    chord_m: float,
    air_density_kg_m3: float,
    lift_slope: float,
    cd0: float,
    induced_drag: float,
    blades: int = 2,
) -> float:
    """Mirror the repository's 12-annulus, no-induction blade-element load law."""
    radius = 0.5 * diameter_m
    omega = rpm * TAU / 60.0
    dr = radius * 0.8 / 12.0
    torque = 0.0
    for i in range(12):
        r = radius * 0.2 + (i + 0.5) * dr
        tangential = omega * r
        speed_sq = tangential * tangential
        if speed_sq == 0.0:
            continue
        beta = math.atan2(pitch_m, TAU * r)
        alpha = beta
        cl = max(-1.25, min(1.25, lift_slope * math.sin(2.0 * alpha) / 2.0))
        cd = cd0 + induced_drag * cl * cl + 1.2 * math.sin(alpha) ** 2
        area_pressure = 0.5 * air_density_kg_m3 * speed_sq * chord_m * dr * blades
        drag = area_pressure * cd
        torque += drag * r
    return torque


def static_balance_roots(
    profile: dict[str, Any],
    diameter_m: float,
    pitch_m: float,
    chord_m: float,
    air_density_kg_m3: float,
    section: dict[str, float],
    lower_rpm: float,
    upper_rpm: float,
) -> list[float]:
    def balance(rpm: float) -> float:
        engine = evaluate(profile, rpm)["brake_shaft_torque_nm"]
        propeller = annular_static_prop_torque(
            rpm, diameter_m, pitch_m, chord_m, air_density_kg_m3,
            section["lift_slope_per_rad"], section["cd0"], section["induced_drag"], int(section["blades"]),
        )
        return engine - propeller

    roots: list[float] = []
    step = 25.0
    x0 = lower_rpm
    y0 = balance(x0)
    while x0 < upper_rpm:
        x1 = min(upper_rpm, x0 + step)
        y1 = balance(x1)
        if y0 == 0.0 or y0 * y1 < 0.0 or y1 == 0.0:
            a, b = x0, x1
            fa, fb = y0, y1
            if fa != 0.0 and fb != 0.0:
                for _ in range(60):
                    mid = 0.5 * (a + b)
                    fm = balance(mid)
                    if fa * fm <= 0.0:
                        b, fb = mid, fm
                    else:
                        a, fa = mid, fm
            root = x0 if y0 == 0.0 else (x1 if y1 == 0.0 else 0.5 * (a + b))
            if not roots or abs(root - roots[-1]) > 1e-4:
                roots.append(root)
        x0, y0 = x1, y1
    return roots


def fit_single_prop_rpm_anchor(profile: dict[str, Any]) -> dict[str, Any]:
    """Conditionally scale a guessed chord to one O.S. static-RPM observation."""
    if profile["family"] != "glow_2t":
        raise ValueError("the O.S. APC 12x7 field anchor applies only to the MAX-55AX dossier")
    reference_rpm = 10330.0
    reference_density = qvalue(profile["operation"], "reference_dry_density_kg_m3")
    engine_q = evaluate(profile, reference_rpm)["brake_shaft_torque_nm"]
    diameter = 12.0 * 0.0254
    pitch = 7.0 * 0.0254
    chord = 0.025
    section = {"lift_slope_per_rad": 5.5, "cd0": 0.022, "induced_drag": 0.06, "blades": 2}
    prop_q = annular_static_prop_torque(
        reference_rpm, diameter, pitch, chord, reference_density,
        section["lift_slope_per_rad"], section["cd0"], section["induced_drag"], section["blades"],
    )
    if prop_q <= 0.0 or engine_q <= 0.0:
        raise ValueError("single-point chord fit requires positive candidate and propeller torques")
    scale = engine_q / prop_q
    inferred_chord = chord * scale
    fitted_prop_q = annular_static_prop_torque(
        reference_rpm, diameter, pitch, inferred_chord, reference_density,
        section["lift_slope_per_rad"], section["cd0"], section["induced_drag"], section["blades"],
    )

    lower, upper = 2000.0, min(17000.0, float(qvalue(profile["operation"], "max_rpm")))
    roots: list[dict[str, Any]] = []
    for root in static_balance_roots(profile, diameter, pitch, inferred_chord, reference_density, section, lower, upper):
        h = min(1.0, root - lower, upper - root)
        slope = 0.0
        if h > 0.0:
            lo_q = evaluate(profile, root - h)["brake_shaft_torque_nm"] - annular_static_prop_torque(
                root - h, diameter, pitch, inferred_chord, reference_density,
                section["lift_slope_per_rad"], section["cd0"], section["induced_drag"], int(section["blades"]),
            )
            hi_q = evaluate(profile, root + h)["brake_shaft_torque_nm"] - annular_static_prop_torque(
                root + h, diameter, pitch, inferred_chord, reference_density,
                section["lift_slope_per_rad"], section["cd0"], section["induced_drag"], int(section["blades"]),
            )
            slope = (hi_q - lo_q) / (2.0 * h)
        roots.append({
            "rpm": round(root, 6),
            "net_torque_slope_nm_per_rpm": round(slope, 9),
            "locally_stable_by_scalar_shaft_test": slope < 0.0,
            "anchor_or_candidate_prediction": "anchor by construction" if abs(root - reference_rpm) < 1e-3 else "candidate prediction",
        })

    # A second O.S.-recommended APC size is shown only as a model scenario. Its
    # chord is scaled with diameter from the fitted 12-inch estimate; no 13x6
    # observation supports or validates this geometrical-similarity assumption.
    second_diameter = 13.0 * 0.0254
    second_pitch = 6.0 * 0.0254
    second_chord = inferred_chord * 13.0 / 12.0
    second_limit = min(17000.0, float(qvalue(profile["operation"], "max_rpm")), 190000.0 / 13.0)
    second_roots = static_balance_roots(
        profile, second_diameter, second_pitch, second_chord, reference_density, section, lower, second_limit,
    )
    second_prop = {
        "configuration": "APC Sport LP13060 13x6",
        "manufacturer_prop_rpm_ceiling": round(190000.0 / 13.0, 2),
        "assumed_chord_mm_from_diameter_similarity": round(second_chord * 1000.0, 5),
        "static_candidate_balance_roots_rpm": [round(x, 2) for x in second_roots],
        "evidence_status": "unobserved surrogate prediction; same section coefficients and chord/diameter ratio assumed from the fitted 12x7 prop",
        "warning": "The O.S. 12x7 RPM point does not validate the different 13x6 geometry or its static equilibrium.",
    }

    variants = []
    for label, changed in [
        ("section_lift_slope_4_5", {"lift_slope_per_rad": 4.5}),
        ("section_lift_slope_6_5", {"lift_slope_per_rad": 6.5}),
        ("section_cd0_0_015", {"cd0": 0.015}),
        ("section_cd0_0_035", {"cd0": 0.035}),
        ("density_minus_10pct", {"density_scale": 0.9}),
        ("density_plus_10pct", {"density_scale": 1.1}),
    ]:
        alt = section | {k: v for k, v in changed.items() if k != "density_scale"}
        density = reference_density * changed.get("density_scale", 1.0)
        alt_q = annular_static_prop_torque(
            reference_rpm, diameter, pitch, chord, density,
            alt["lift_slope_per_rad"], alt["cd0"], alt["induced_drag"], alt["blades"],
        )
        variants.append({
            "case": label,
            "exact_fit_chord_mm": round(chord * engine_q / alt_q * 1000.0, 5),
            "meaning": "one changed assumed prop/air input; this is not a statistical interval",
        })

    return {
        "status": "conditional one-point fit; not an independent validation",
        "reference": {
            "engine": "O.S. MAX-55AX",
            "propeller": "APC Sport 12x7 LP12070 (identified in the O.S. field article)",
            "observed_peak_rpm": reference_rpm,
            "ambient_temperature_c": 3.0,
            "source": "https://www.os-engines.co.jp/web_content/202102/index1.html",
            "not_reported": ["shaft torque", "thrust", "barometric pressure", "propeller chord distribution", "propeller pitch/twist distribution"],
        },
        "method": "At observed static RPM, scale only a guessed uniform chord so the 12-annulus no-induced-velocity propeller torque equals the current full-admission candidate engine torque. The load law mirrors app/physics/glow/propeller.gd; engine torque is linearly interpolated from the live profile.",
        "assumed_propeller_geometry_and_sections": {
            "diameter_m": diameter,
            "pitch_m": pitch,
            "starting_uniform_chord_mm": chord * 1000.0,
            "blades": section["blades"],
            "lift_slope_per_rad": section["lift_slope_per_rad"],
            "cd0": section["cd0"],
            "induced_drag": section["induced_drag"],
            "static_prop_air_density_kg_m3": reference_density,
            "density_note": "profile reference density is used because the O.S. article reports temperature but not barometric pressure; actual test density is unknown",
        },
        "conditional_fit": {
            "candidate_engine_torque_at_anchor_nm": engine_q,
            "starting_chord_prop_torque_at_anchor_nm": prop_q,
            "chord_scale_factor": scale,
            "implied_uniform_chord_mm": inferred_chord * 1000.0,
            "post_fit_torque_residual_nm": engine_q - fitted_prop_q,
            "residual_interpretation": "zero by construction; cannot verify the engine torque or propeller map",
        },
        "static_balance_roots_after_chord_fit": roots,
        "second_recommended_prop_scenario": second_prop,
        "one_at_a_time_assumption_sensitivity": variants,
        "limits": [
            "O.S. reported only a peak-RPM observation for one APC 12x7 setup; RPM alone does not identify engine torque, propeller torque, thrust, or blade geometry.",
            "The inferred uniform chord is conditional on the candidate engine curve, reference air density, section coefficients, zero axial flow, and this simplified no-induction load law.",
            "The exact anchor agreement is a one-point parameter fit, not a measured torque match, held-out prediction, full static map, advancing-flight validation, or APC blade-shape reconstruction.",
        ],
    }


def annular_prop_performance(
    rpm: float,
    axial_speed_m_s: float,
    diameter_m: float,
    pitch_m: float,
    chord_m: float,
    air_density_kg_m3: float,
    section: dict[str, float],
) -> dict[str, float]:
    """Mirror the runtime's 12-annulus no-induction glow propeller surrogate."""
    radius = diameter_m / 2.0
    omega = rpm * TAU / 60.0
    dr = radius * 0.8 / 12.0
    thrust = torque = 0.0
    for i in range(12):
        r = radius * 0.2 + (i + 0.5) * dr
        tangential = omega * r
        speed_sq = tangential * tangential + axial_speed_m_s * axial_speed_m_s
        if speed_sq == 0.0:
            continue
        speed = math.sqrt(speed_sq)
        phi = math.atan2(axial_speed_m_s, tangential)
        beta = math.atan2(pitch_m, TAU * r)
        alpha = beta - phi
        cl = max(-1.25, min(1.25, section["lift_slope_per_rad"] * math.sin(2.0 * alpha) / 2.0))
        cd = section["cd0"] + section["induced_drag"] * cl * cl + 1.2 * math.sin(alpha) ** 2
        area_pressure = 0.5 * air_density_kg_m3 * speed_sq * chord_m * dr * section["blades"]
        lift = area_pressure * cl
        drag = area_pressure * cd
        thrust += (lift * tangential - drag * axial_speed_m_s) / speed
        torque += (lift * axial_speed_m_s + drag * tangential) * r / speed
    return {
        "thrust_n": thrust,
        "torque_nm": torque,
        "shaft_power_w": torque * omega,
        "thrust_power_w": thrust * axial_speed_m_s,
        "advance_ratio": axial_speed_m_s / (max(rpm, 1.0) / 60.0 * diameter_m),
    }


def prop_balance_roots(
    profile: dict[str, Any],
    diameter_m: float,
    pitch_m: float,
    chord_m: float,
    axial_speed_m_s: float,
    air_density_kg_m3: float,
    section: dict[str, float],
    engine_sensitivity: dict[str, float] | None = None,
) -> list[dict[str, Any]]:
    """Return torque-balance roots and restoring/non-restoring classifications."""
    engine_sensitivity = engine_sensitivity or {}
    torque_curve = qvalue(profile["parameters"], "mechanical_torque_nm")
    operation = {k: qvalue(profile["operation"], k) for k in profile["operation"]}
    lower = max(0.0, float(torque_curve[0][0]))
    upper = min(float(torque_curve[-1][0]), float(operation["max_rpm"]))

    def net_torque(rpm: float) -> float:
        engine = evaluate(profile, rpm, **engine_sensitivity)["brake_shaft_torque_nm"]
        prop = annular_prop_performance(
            rpm, axial_speed_m_s, diameter_m, pitch_m, chord_m,
            air_density_kg_m3, section,
        )["torque_nm"]
        return engine - prop

    roots: list[float] = []
    step = 25.0
    x0 = lower
    y0 = net_torque(x0)
    while x0 < upper:
        x1 = min(upper, x0 + step)
        y1 = net_torque(x1)
        root: float | None = None
        if y0 == 0.0:
            root = x0
        elif y1 == 0.0:
            root = x1
        elif y0 * y1 < 0.0:
            a, b, fa = x0, x1, y0
            for _ in range(60):
                mid = 0.5 * (a + b)
                fm = net_torque(mid)
                if fa * fm <= 0.0:
                    b = mid
                else:
                    a, fa = mid, fm
            root = 0.5 * (a + b)
        if root is not None and (not roots or abs(root - roots[-1]) > 1e-3):
            roots.append(root)
        x0, y0 = x1, y1

    family = profile["family"]
    practical_low, practical_high = MANUFACTURER_PRACTICAL_RPM[family]
    out: list[dict[str, Any]] = []
    for root in roots:
        h = max(0.1, root * 1e-5)
        lo = max(lower, root - h)
        hi = min(upper, root + h)
        slope = (net_torque(hi) - net_torque(lo)) / (hi - lo) if hi > lo else 0.0
        prop = annular_prop_performance(
            root, axial_speed_m_s, diameter_m, pitch_m, chord_m,
            air_density_kg_m3, section,
        )
        engine = evaluate(profile, root, **engine_sensitivity)
        out.append({
            "rpm": root,
            "stable_restoring_root": slope < 0.0,
            "net_torque_slope_nm_per_rpm": slope,
            "engine_torque_nm": engine["brake_shaft_torque_nm"],
            **prop,
            "within_o_s_practical_rpm_range": practical_low <= root <= practical_high,
        })
    return out


def paired_propeller_inference(profile: dict[str, Any]) -> dict[str, Any]:
    """Build paired static/advancing operating scenarios without inventing data."""
    family = profile["family"]
    is_two_stroke = family == "glow_2t"
    section = {"lift_slope_per_rad": 5.5, "cd0": 0.022, "induced_drag": 0.06, "blades": 2.0}
    reference_density = float(qvalue(profile["operation"], "reference_dry_density_kg_m3"))
    two_stroke_anchor_rpm = 10330.0
    diameter_12 = 12.0 * 0.0254
    pitch_7 = 7.0 * 0.0254
    starting_prop_torque = annular_prop_performance(
        two_stroke_anchor_rpm, 0.0, diameter_12, pitch_7, 0.025,
        reference_density, section,
    )["torque_nm"]
    if is_two_stroke:
        anchor_engine_torque = evaluate(profile, two_stroke_anchor_rpm)["brake_shaft_torque_nm"]
        chord_12 = 0.025 * anchor_engine_torque / starting_prop_torque
        chord_14 = None
        chord_14_alt = None
    else:
        # No matched FS-64V prop RPM point exists. This 30 mm wide-chord geometry
        # is an explicit screening assumption; the alternative transfers the
        # 12x7 inferred chord/diameter ratio and is retained as sensitivity.
        chord_14 = 0.030
        chord_14_alt = (0.025 * evaluate(
            json.loads((PROFILE_DIR / PROFILE_NAMES["glow_2t"]).read_text(encoding="utf-8")),
            two_stroke_anchor_rpm,
        )["brake_shaft_torque_nm"] / starting_prop_torque) * (14.0 / 12.0)
        chord_12 = None

    if is_two_stroke:
        propellers = [
            {
                "configuration_id": "max55ax_apc_sport_12x7",
                "name": "APC Sport 12x7 LP12070",
                "diameter_in": 12.0, "pitch_in": 7.0,
                "prop_mass_oz": 1.52, "prop_mass_g_derived": 43.09127515,
                "shaft_bore_in": 0.25, "shaft_bore_mm": 6.35,
                "propeller_source": "https://www.apcprop.com/product/12x7/",
                "observed_engine_prop_source": "https://www.os-engines.co.jp/web_content/202102/index1.html",
                "apc_glow_rpm_ceiling": 190000.0 / 12.0,
                "nominal_chord_m": chord_12,
                "chord_basis": "conditional one-point fit to O.S. field RPM observation",
                "anchor_rpm": two_stroke_anchor_rpm,
                "refit_chord_in_uncertainty_cases": True,
                "installed_default_recommendation": True,
            },
            {
                "configuration_id": "max55ax_apc_sport_13x6",
                "name": "APC Sport 13x6 LP13060",
                "diameter_in": 13.0, "pitch_in": 6.0,
                "prop_mass_oz": 1.69, "prop_mass_g_derived": 47.91069408125,
                "shaft_bore_in": 0.25, "shaft_bore_mm": 6.35,
                "propeller_source": "https://www.apcprop.com/product/13x6/",
                "observed_engine_prop_source": None,
                "apc_glow_rpm_ceiling": 190000.0 / 13.0,
                "nominal_chord_m": chord_12 * 13.0 / 12.0,
                "chord_basis": "unobserved configuration: 12x7 fitted chord/diameter ratio transferred",
                "anchor_rpm": None,
                "refit_chord_in_uncertainty_cases": True,
                "installed_default_recommendation": False,
            },
        ]
    else:
        propellers = [
            {
                "configuration_id": "fs64v_apc_sport_13x6",
                "name": "APC Sport 13x6 LP13060",
                "diameter_in": 13.0, "pitch_in": 6.0,
                "prop_mass_oz": 1.69, "prop_mass_g_derived": 47.91069408125,
                "shaft_bore_in": 0.25, "shaft_bore_mm": 6.35,
                "propeller_source": "https://www.apcprop.com/product/13x6/",
                "observed_engine_prop_source": None,
                "apc_glow_rpm_ceiling": 190000.0 / 13.0,
                "nominal_chord_m": chord_14 * 13.0 / 14.0,
                "chord_basis": "scaled from 30 mm Master Airscrew 14x6 screening geometry; no APC blade chord data",
                "anchor_rpm": None,
                "refit_chord_in_uncertainty_cases": False,
                "installed_default_recommendation": False,
                "alternative_chord_m": chord_14_alt * 13.0 / 14.0,
            },
            {
                "configuration_id": "fs64v_master_airscrew_k_14x6",
                "name": "Master Airscrew K Series 14x6",
                "diameter_in": 14.0, "pitch_in": 6.0,
                "prop_mass_oz": 2.05, "prop_mass_g_manufacturer": 58.1,
                "shaft_bore_in": 0.25, "shaft_bore_mm": 6.35,
                "propeller_source": "https://www.masterairscrew.com/products/k-series-14x6-propeller",
                "observed_engine_prop_source": "https://www.os-engines.co.jp/web_content/202210/index_1.html",
                "apc_glow_rpm_ceiling": None,
                "manufacturer_max_recommended_rpm": 165000.0 / 14.0,
                "rpm_limit_basis": "Generic Master Airscrew plastic-prop safety instruction: 165000 divided by diameter in inches; applied provisionally because the K-series product page specifies glass-fiber reinforced composite but no SKU-specific RPM ceiling",
                "rpm_limit_source": "https://www.masterairscrew.com/pages/downloads",
                "nominal_chord_m": chord_14,
                "chord_basis": "explicit unmeasured 30 mm wide-chord screening assumption, not fitted to an FS-64V RPM datum",
                "anchor_rpm": None,
                "refit_chord_in_uncertainty_cases": False,
                "installed_default_recommendation": True,
                "alternative_chord_m": chord_14_alt,
            },
        ]

    # These deliberately combine favorable/adverse ends of separate inferred
    # terms. They expose sensitivity; they are not probability bounds or CIs.
    corners = [
        {
            "name": "lower_candidate_torque_and_heavier_prop_load",
            "engine": {"indicated_efficiency_scale": 0.9, "charge_scale": 0.9, "losses_scale": 1.5},
            "section": section | {"lift_slope_per_rad": 6.5, "cd0": 0.035, "induced_drag": 0.12},
            "density_scale": 1.1,
        },
        {
            "name": "higher_candidate_torque_and_lighter_prop_load",
            "engine": {"indicated_efficiency_scale": 1.1, "charge_scale": 1.1, "losses_scale": 0.5},
            "section": section | {"lift_slope_per_rad": 4.5, "cd0": 0.015, "induced_drag": 0.03},
            "density_scale": 0.9,
        },
    ]
    predictions: list[dict[str, Any]] = []
    for prop in propellers:
        diameter = prop["diameter_in"] * 0.0254
        pitch = prop["pitch_in"] * 0.0254
        nominal_chord = float(prop["nominal_chord_m"])
        if prop["name"].startswith("APC Sport"):
            prop["manufacturer_max_recommended_rpm"] = 190000.0 / prop["diameter_in"]
            prop["rpm_limit_basis"] = "APC glow/Sport propeller limit: 190000 divided by diameter in inches"
            prop["rpm_limit_source"] = "https://www.apcprop.com/technical-information/rpm-limits/"
        effective_limit = min(
            float(MANUFACTURER_PRACTICAL_RPM[family][1]),
            float(prop["manufacturer_max_recommended_rpm"])
            if prop.get("manufacturer_max_recommended_rpm") is not None
            else float("inf"),
        )
        speed_rows: list[dict[str, Any]] = []
        uncertainty_rows: list[dict[str, Any]] = []
        for axial_speed in [0.0, 10.0, 20.0, 30.0]:
            nominal_roots = prop_balance_roots(
                profile, diameter, pitch, nominal_chord, axial_speed,
                reference_density, section,
            )
            nominal_stable = [row for row in nominal_roots if row["stable_restoring_root"]]
            corner_roots: list[dict[str, Any]] = []
            for corner in corners:
                density = reference_density * corner["density_scale"]
                case_chord = nominal_chord
                if prop["refit_chord_in_uncertainty_cases"] and is_two_stroke:
                    anchor_torque = evaluate(profile, two_stroke_anchor_rpm, **corner["engine"])["brake_shaft_torque_nm"]
                    anchor_load = annular_prop_performance(
                        two_stroke_anchor_rpm, 0.0, diameter, pitch, 0.025,
                        density, corner["section"],
                    )["torque_nm"]
                    case_chord = 0.025 * anchor_torque / anchor_load
                    if prop["diameter_in"] != 12.0:
                        case_chord *= prop["diameter_in"] / 12.0
                elif not is_two_stroke and "alternative_chord_m" in prop:
                    # Include both explicit FS64 geometry priors in the envelope.
                    for geometry_chord in [nominal_chord, float(prop["alternative_chord_m"])]:
                        corner_roots.extend(prop_balance_roots(
                            profile, diameter, pitch, geometry_chord, axial_speed,
                            density, corner["section"], corner["engine"],
                        ))
                    continue
                corner_roots.extend(prop_balance_roots(
                    profile, diameter, pitch, case_chord, axial_speed,
                    density, corner["section"], corner["engine"],
                ))
            stable_corner_roots = [row for row in corner_roots if row["stable_restoring_root"]]
            stable_sensitivity_roots = stable_corner_roots + nominal_stable
            envelope: dict[str, Any] = {
                "axial_speed_m_s": axial_speed,
                "sensitivity_case_count_excluding_nominal": len(corners) * (2 if not is_two_stroke and "alternative_chord_m" in prop else 1),
                "nominal_case_included_in_min_max": True,
                "stable_root_count_including_nominal": len(stable_sensitivity_roots),
                "interpretation": "min/max over deliberately combined engineering scenarios; not statistical uncertainty or a validated flight envelope",
            }
            if stable_sensitivity_roots:
                for source_key, target_key in [
                    ("rpm", "rpm"), ("thrust_n", "thrust_n"),
                    ("torque_nm", "torque_nm"), ("shaft_power_w", "shaft_power_w"),
                ]:
                    vals = [float(row[source_key]) for row in stable_sensitivity_roots]
                    envelope[target_key] = [rounded(min(vals)), rounded(max(vals))]
            else:
                envelope["prediction"] = "no restoring equilibrium found in profile support for these corner assumptions"
            uncertainty_rows.append(envelope)
            chosen = nominal_stable[-1] if nominal_stable else None
            row: dict[str, Any] = {
                "axial_speed_m_s": axial_speed,
                "static_condition": axial_speed == 0.0,
                "nominal_uniform_chord_m": nominal_chord,
                "nominal_all_roots": [{k: rounded(v) if isinstance(v, float) else v for k, v in root.items()} for root in nominal_roots],
                "nominal_stable_full_admission_equilibrium": (
                    {k: rounded(v) if isinstance(v, float) else v for k, v in chosen.items()}
                    if chosen is not None else None
                ),
                "assumption_envelope": envelope,
            }
            if prop["anchor_rpm"] is not None and axial_speed == 0.0:
                row["anchor_status"] = "static RPM root is constrained to the O.S. single observation by construction"
            speed_rows.append(row)
        predictions.append({
            **prop,
            "diameter_m": diameter,
            "pitch_m": pitch,
            "direct_fit_check": "1/4-in prop bore matches the O.S. 1/4-28 shaft/nut size; verify actual hub centering and clamping on the test article",
            "engine_rpm_guidance": {
                "o_s_published_practical_rpm": MANUFACTURER_PRACTICAL_RPM[family],
                "profile_numeric_support_rpm": [
                    float(qvalue(profile["parameters"], "mechanical_torque_nm")[0][0]),
                    float(qvalue(profile["parameters"], "mechanical_torque_nm")[-1][0]),
                ],
                "profile_recommended_max_rpm": float(qvalue(profile["operation"], "recommended_max_rpm")),
                "effective_recommended_rpm_for_configuration": effective_limit,
            },
            "section_assumptions": section,
            "reference_air_density_kg_m3": reference_density,
            "static_and_advancing_full_admission_predictions": speed_rows,
            "model_limits": [
                "Uses the engine candidate curve and the runtime's 12-annulus no-induced-velocity uniform-chord surrogate.",
                "The real propeller's radial chord, twist, airfoil, Reynolds correction, induced flow, rotating inertia and production variation are unavailable.",
                "Advancing cases are axial-speed scenarios at 10, 20 and 30 m/s, not aircraft telemetry or validated flight points.",
                "Static RPM, thrust and torque for unobserved combinations are engineering inferences, not measurements.",
            ],
        })

    candidate_static_rpm = {
        prop["configuration_id"]: (
            round(float(prop["static_and_advancing_full_admission_predictions"][0]["nominal_stable_full_admission_equilibrium"]["rpm"]), 2)
            if prop["static_and_advancing_full_admission_predictions"][0]["nominal_stable_full_admission_equilibrium"] is not None
            else None
        )
        for prop in predictions
    }

    return {
        "status": "paired propeller load inference; no propeller is physically calibrated or held out",
        "method": "Full-admission engine/propeller torque roots; runtime-matched blade-element surrogate; one measured OS 2T RPM anchor only.",
        "nominal_axial_scenarios_m_s": [0.0, 10.0, 20.0, 30.0],
        "common_section_assumptions": section,
        "uncertainty_method": {
            "cases": corners,
            "meaning": "conservative paired assumptions combining profile efficiency/charge/loss sensitivity, air density and section coefficients. The reported min/max are scenario sensitivity envelopes, not probability intervals, confidence intervals or physical bounds.",
        },
        "profile_recommendations": (
            {
                "installed_default": "APC Sport 12x7 LP12070",
                "installed_default_evidence": "one O.S. MAX-55AX static RPM observation at 10,330 RPM; candidate surrogate chord 21.1364169121 mm is an exact one-point fit under 1.225 kg/m3 and assumed section coefficients",
                "alternate": "APC Sport 13x6 LP13060; use 22.8977849881 mm only as a same-c/D scenario, not a measured chord",
                "numeric_operating_guidance": "candidate static root 10,330 RPM for the 12x7 by construction; candidate static root about 9,651 RPM for the unobserved 13x6. Keep APC ceilings 15,833 and 14,615 RPM as prop-specific limits; 13x6 high-airspeed root must be checked against its 14,615 RPM ceiling.",
                "candidate_static_rpm_by_configuration_id": candidate_static_rpm,
                "recommended_max_rpm_by_configuration_id": {
                    "max55ax_apc_sport_12x7": round(190000.0 / 12.0, 2),
                    "max55ax_apc_sport_13x6": round(190000.0 / 13.0, 2),
                },
                "effective_recommended_rpm_by_configuration_id": {
                    "max55ax_apc_sport_12x7": min(17000.0, 190000.0 / 12.0),
                    "max55ax_apc_sport_13x6": min(17000.0, 190000.0 / 13.0),
                },
                "engine_profile_change": "No torque-knot update is justified by fitting an assumed propeller chord to an RPM-only engine observation. Preserve manufacturer rating and keep physical fit pending matched torque data.",
            }
            if is_two_stroke else {
                "installed_default": "Master Airscrew K Series 14x6",
                "installed_default_evidence": "O.S. recommends scale 14x6 and its qualitative FS-64V flight review reports a 14x6; brand and RPM were not recorded",
                "numeric_geometry_prior": "30.0 mm uniform chord at 14x6, explicitly unmeasured; scale c/D to 27.8571428571 mm at 13x6",
                "alternate_geometry_sensitivity": "24.6591530641 mm at 14x6 and 22.8977849881 mm at 13x6 if the 2T fitted c/D is transferred; neither is manufacturer blade geometry",
                "numeric_operating_guidance": "Nominal static roots are reported per prop; keep the O.S. recommended maximum at 11,000 RPM. Retain profile numerical support to 15,000 RPM only for unloading-flight model scenarios with an over-recommendation flag.",
                "candidate_static_rpm_by_configuration_id": candidate_static_rpm,
                "manufacturer_recommended_max_rpm": 11000.0,
                "manufacturer_max_recommended_rpm_by_configuration_id": {
                    "fs64v_apc_sport_13x6": 190000.0 / 13.0,
                    "fs64v_master_airscrew_k_14x6": 165000.0 / 14.0,
                },
                "effective_recommended_rpm_by_configuration_id": {
                    "fs64v_apc_sport_13x6": min(11000.0, 190000.0 / 13.0),
                    "fs64v_master_airscrew_k_14x6": min(11000.0, 165000.0 / 14.0),
                },
                "profile_numerical_support_max_rpm": float(qvalue(profile["operation"], "max_rpm")),
                "engine_profile_change": "The 14x6/13x6 predictions do not identify a new FS-64V torque curve. Preserve 0.72788955 Nm at the 1.14 PS/11,000 RPM rated point; require independent bench data before changing knots.",
            }
        ),
        "propellers": predictions,
    }


def rounded(value: float, digits: int = 8) -> float:
    return round(float(value), digits)


def report(profile_path: Path) -> dict[str, Any]:
    raw = profile_path.read_bytes()
    profile = json.loads(raw)
    family = profile["family"]
    if family not in PROFILE_NAMES:
        raise ValueError(f"unexpected family {family!r} in {profile_path}")
    op = {k: qvalue(profile["operation"], k) for k in profile["operation"]}
    p = {k: qvalue(profile["parameters"], k) for k in profile["parameters"]}
    manufacturer_lower, manufacturer_upper = MANUFACTURER_PRACTICAL_RPM[family]
    profile_lower = float(p["mechanical_torque_nm"][0][0])
    profile_upper = float(p["mechanical_torque_nm"][-1][0])
    lower_rpm = max(manufacturer_lower, profile_lower)
    upper_rpm = min(manufacturer_upper, profile_upper)
    if upper_rpm < lower_rpm:
        raise ValueError(f"{profile['id']} profile does not overlap its manufacturer's practical RPM range")
    rated_rpm = op["rated_rpm"]
    rating = evaluate(profile, rated_rpm)
    residual = rating["brake_shaft_power_w"] - op["rated_power_w"]
    # All RPM-indexed tables share this axis. Do not add the separately indexed
    # mixture-efficiency x values to the speed curve.
    knot_rpms = [float(x) for x, _ in p["mechanical_torque_nm"]]
    wot_points = [evaluate(profile, rpm) for rpm in knot_rpms if rpm > 0.0]
    curve = []
    for point in wot_points:
        row = {k: rounded(v, 7) for k, v in point.items()}
        row["within_o_s_practical_rpm_range"] = manufacturer_lower <= point["rpm"] <= manufacturer_upper
        curve.append(row)
    dense = [evaluate(profile, float(r)) for r in range(int(lower_rpm), int(upper_rpm) + 1, 25)]
    peak_torque = max(dense, key=lambda row: row["brake_shaft_torque_nm"])
    peak_power = max(dense, key=lambda row: row["brake_shaft_power_w"])
    middle_rpm = (lower_rpm + rated_rpm) / 2.0
    sensitivities = []
    for rpm in [middle_rpm, rated_rpm]:
        base = evaluate(profile, rpm)
        cases = []
        for label, kwargs in [
            ("indicated_efficiency_minus_10pct", {"indicated_efficiency_scale": 0.9}),
            ("indicated_efficiency_plus_10pct", {"indicated_efficiency_scale": 1.1}),
            ("fresh_charge_minus_10pct", {"charge_scale": 0.9}),
            ("fresh_charge_plus_10pct", {"charge_scale": 1.1}),
            ("all_candidate_shaft_losses_minus_50pct", {"losses_scale": 0.5}),
            ("all_candidate_shaft_losses_plus_50pct", {"losses_scale": 1.5}),
        ]:
            altered = evaluate(profile, rpm, **kwargs)
            cases.append({
                "case": label,
                "candidate_brake_torque_nm": rounded(altered["brake_shaft_torque_nm"]),
                "delta_from_candidate_nm": rounded(altered["brake_shaft_torque_nm"] - base["brake_shaft_torque_nm"]),
                "candidate_brake_power_w": rounded(altered["brake_shaft_power_w"]),
            })
        sensitivities.append({"rpm": rpm, "baseline": {
            "brake_torque_nm": rounded(base["brake_shaft_torque_nm"]),
            "brake_power_w": rounded(base["brake_shaft_power_w"]),
        }, "one_at_a_time_cases": cases})

    partial_load = []
    for admission in [0.25, 0.5, 0.75, 1.0]:
        point = evaluate(profile, rated_rpm, admission=admission)
        partial_load.append({k: rounded(v, 7) for k, v in point.items()})

    rated_torque = op["rated_power_w"] / (TAU * rated_rpm / 60.0)
    propeller_report = paired_propeller_inference(profile)
    return {
        "format": "openrc-glow-inference-audit v1",
        "engine_id": profile["id"],
        "family": family,
        "profile_status": profile["status"],
        "interpretation": "generated candidate inference; never a measured or held-out data fit",
        "profile_path": profile_path.relative_to(ROOT).as_posix(),
        "profile_sha256": hashlib.sha256(raw).hexdigest(),
        "rating_constraint": {
            "source": "O.S. manufacturer rated-power/RPM point retained in the candidate profile",
            "rated_rpm": rated_rpm,
            "rated_power_w": op["rated_power_w"],
            "torque_derived_from_rating_nm": rounded(rated_torque),
            "candidate_reconstructed_power_w": rounded(rating["brake_shaft_power_w"]),
            "candidate_power_residual_w": rounded(residual, 12),
            "candidate_reconstructed_torque_nm": rounded(rating["brake_shaft_torque_nm"]),
            "identity_check": "PASS" if abs(residual) <= max(1.0e-8, op["rated_power_w"] * 1.0e-10) else "FAIL",
            "meaning": "algebraic closure of generated assumptions; not calibration against independent measurements",
        },
        "rpm_domain": {
            "o_s_published_practical_rpm": [manufacturer_lower, manufacturer_upper],
            "profile_recommended_max_rpm": op.get("recommended_max_rpm"),
            "profile_numerical_max_rpm": op.get("max_rpm"),
            "profile_table_rpm_support": [profile_lower, profile_upper],
            "profile_knots_outside_o_s_practical_range": [
                x for x in knot_rpms if x > 0.0 and (x < manufacturer_lower or x > manufacturer_upper)
            ],
            "profile_knots_above_recommended_max_rpm": (
                [x for x in knot_rpms if x > float(op["recommended_max_rpm"])]
                if "recommended_max_rpm" in op else []
            ),
            "peak_search_range_rpm": [lower_rpm, upper_rpm],
            "manufacturer_source": (
                "https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm"
                if family == "glow_2t"
                else "https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html"
            ),
            "warning": "Candidate support beyond the published practical range is shown for audit but is not a manufacturer-approved operating envelope.",
        },
        "fuel_basis_from_profile": {k: rounded(v, 8) for k, v in fuel_basis(profile).items()},
        "candidate_wot_knot_curve": curve,
        "candidate_derived_peaks": {
            "method": "25 RPM scan through linearly interpolated profile tables inside the manufacturer's practical RPM envelope",
            "not_a_measured_peak": True,
            "torque_peak": {k: rounded(v, 7) for k, v in peak_torque.items()},
            "power_peak": {k: rounded(v, 7) for k, v in peak_power.items()},
        },
        "rated_rpm_effective_admission_scenarios": {
            "meaning": "static candidate-kernel sensitivity only; admission is not transmitter position and no transient is simulated",
            "points": partial_load,
        },
        "one_at_a_time_assumption_sensitivity": {
            "meaning": "local perturbation experiment on inferred inputs; values are not confidence intervals, empirical uncertainty bands, or retuned profiles",
            "points": sensitivities,
        },
        "single_point_propeller_anchor_inference": fit_single_prop_rpm_anchor(profile) if family == "glow_2t" else None,
        "paired_propeller_inference": propeller_report,
        "profile_recommendations": propeller_report["profile_recommendations"],
        "validation_status": {
            "profile_structure": "JSON parses and the report's required fields are present; a full runtime/schema validation is not performed here",
            "rated_knot_reconstruction": "checked by this report; this verifies candidate algebraic consistency only",
            "engine_specific_curve_fit": "NOT PERFORMED: no matched multi-point MAX-55AX or FS-64V torque/flow dataset",
            "propeller_map_fit": "NOT PERFORMED: the MAX-55AX 12x7 datum is RPM-only and only conditions a uniform-chord surrogate; no matched FS-64V RPM datum or Ct/Cp map exists",
            "paired_static_advancing_scenarios": "computed from candidates and inferred uniform-chord assumptions; not measurements, held-out propeller tests or aircraft-flight validation",
            "independent_held_out_validation": "NOT PERFORMED",
            "physical_engine_validation": "NOT PERFORMED",
            "experienced_pilot_validation": "NOT PERFORMED",
            "aiaa_2016_5011": "external comparison only: MAX-55AX part-load installed-hybrid data; FS-a56 is not FS-64V; no points are imported as a fit target here",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write refreshed JSON reports into both dossier folders")
    args = parser.parse_args()
    reports: dict[str, dict[str, Any]] = {}
    for family, name in PROFILE_NAMES.items():
        reports[family] = report(PROFILE_DIR / name)
    if args.write:
        for family, value in reports.items():
            path = DOSSIER_DIR / DOSSIER_NAMES[family]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
        print("Wrote current-profile inference reports for both engine families.")
    else:
        print(json.dumps(reports, indent=2, ensure_ascii=False, allow_nan=False))


if __name__ == "__main__":
    main()
