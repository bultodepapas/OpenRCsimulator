"""Generate the separate, laboratory-only HX-700 electric 3D candidate data."""
import argparse
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DESIGN = (
    "docs/research/helicopter/HELI-25b/README.md: supplied HX-700 Blender "
    "generator design value; unvalidated and not a flight measurement"
)
SOURCE_INVENTORY = (
    "docs/research/helicopter/HELI-25b/README.md: supplied HX-700 Blender "
    "inventory/design data; geometry or dynamics not independently validated"
)
ESTIMATED = (
    "HELI-36a laboratory estimate for the HX-700 candidate; no aircraft-specific "
    "measurement or identified flight response"
)
GEOMETRY = (
    "docs/research/helicopter/HELI-25/README.md: measured supplied HX-700 GLB "
    "skid rail corners relative to the visual CG datum"
)

TAIL_RATIO = 4.92307710647583
MOTOR_RATIO = 9.636364
NOMINAL_RPM = 2100.0
NOMINAL_OMEGA = NOMINAL_RPM * 2.0 * math.pi / 60.0
MOTOR_POWER_W = 3500.0
MOTOR_TORQUE_NM = MOTOR_POWER_W / (MOTOR_RATIO * NOMINAL_OMEGA)


def q(value, unit, kind="estimated", source=ESTIMATED):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def block(values, source=ESTIMATED):
    return {key: q(value, unit, "estimated", source) for key, (value, unit) in values.items()}


def derive():
    main = block({
        "rho_kg_m3": (1.225, "kg/m3"),
        "rotor_radius_m": (0.70, "m"),
        "blade_chord_m": (0.056, "m"),
        "rotor_blade_count": (2, "1"),
        "blade_lift_curve_slope_per_rad": (5.7, "1/rad"),
        "blade_section_cd0": (0.014, "1"),
        "thrust_coefficient_max": (0.008, "1"),
        "blade_flapping_inertia_kg_m2": (0.042, "kg*m2"),
        # Effective flap response parameters for the current shared mean-rotor
        # approximation. They do not identify the supplied flybarless head.
        "gamma_flybar": (2.8, "1"),
        "flapback_k_mu": (0.18, "1"),
        "omega_nominal_rad_s": (NOMINAL_OMEGA, "rad/s"),
        "cyclic_longitudinal_gain_nominal_rad_per_rad": (4.5, "1"),
        "cyclic_lateral_gain_nominal_rad_per_rad": (4.5, "1"),
        "hub_spring_stiffness_nm_per_rad": (85.0, "N*m/rad"),
        "hub_position_body_frd_m": ([0.0, 0.0, -0.19], "m"),
        "rotation_sense": (1, "1"),
    })
    main["rho_kg_m3"] = q(1.225, "kg/m3", "manual", "ISA sea-level reference density")
    main["rotor_blade_count"] = q(2, "1", "derived", "Two main blades in supplied HX-700 model")
    main["omega_nominal_rad_s"] = q(
        NOMINAL_OMEGA, "rad/s", "derived",
        f"{NOMINAL_RPM:g} rpm × 2π/60 from {SOURCE_DESIGN}",
    )

    tail = block({
        "rho_kg_m3": (1.225, "kg/m3"),
        "main_rotor_radius_m": (0.70, "m"),
        "tail_rotor_radius_m": (0.105, "m"),
        "blade_chord_m": (0.025, "m"),
        "rotor_blade_count": (2, "1"),
        "blade_lift_curve_slope_per_rad": (5.0, "1/rad"),
        "blade_section_cd0": (0.018, "1"),
        "thrust_coefficient_max": (0.06, "1"),
        "tail_to_main_speed_ratio": (TAIL_RATIO, "1"),
        "hub_distance_aft_m": (0.92, "m"),
        "hub_height_above_cg_m": (0.08, "m"),
        "vertical_fin_area_m2": (0.015, "m2"),
        "trim_collective_rad": (0.09, "rad"),
        "wake_efficiency": (0.9, "1"),
        "rotation_sense": (1, "1"),
    })
    tail["rho_kg_m3"] = q(1.225, "kg/m3", "manual", "ISA sea-level reference density")
    tail["rotor_blade_count"] = q(2, "1", "derived", "Two tail blades in supplied HX-700 model")
    tail["tail_to_main_speed_ratio"] = q(
        TAIL_RATIO, "1", "estimated",
        "docs/research/helicopter/HELI-25b/inventory.json: supplied source generator "
        "gear ratio 4.92307710647583; design value, not a measured under-load ratio",
    )

    airframe = block({
        "rho_kg_m3": (1.225, "kg/m3"),
        "fuselage_drag_area_body_m2": ([0.09, 0.18, 0.14], "m2"),
        "fuselage_cp_body_frd_m": ([0.0, 0.0, 0.0], "m"),
        "vertical_fin_area_m2": (0.015, "m2"),
        "vertical_fin_lift_curve_slope_per_rad": (2.2, "1/rad"),
        "vertical_fin_cp_body_frd_m": ([-0.92, 0.0, -0.08], "m"),
        "horizontal_tail_area_m2": (0.008, "m2"),
        "horizontal_tail_lift_curve_slope_per_rad": (2.5, "1/rad"),
        "horizontal_tail_cp_body_frd_m": ([-0.72, 0.0, 0.0], "m"),
    })
    airframe["rho_kg_m3"] = q(1.225, "kg/m3", "manual", "ISA sea-level reference density")

    drive = block({
        "engine_torque_max_nm": (MOTOR_TORQUE_NM, "N*m"),
        "engine_power_max_w": (MOTOR_POWER_W, "W"),
        "engine_speed_ratio_to_main": (MOTOR_RATIO, "1"),
        "gear_efficiency": (0.92, "1"),
        "governor_target_main_rad_s": (NOMINAL_OMEGA, "rad/s"),
        "governor_gain_nm_per_rad_s": (0.12, "N*m*s/rad"),
        "shaft_loss_torque_nm": (0.10, "N*m"),
        "shaft_viscous_loss_nm_per_rad_s": (0.001, "N*m*s/rad"),
    })
    drive["engine_torque_max_nm"] = q(
        MOTOR_TORQUE_NM, "N*m", "derived",
        f"{MOTOR_POWER_W:g} W / ({MOTOR_RATIO:g} × {NOMINAL_RPM:g} rpm × 2π/60); "
        f"source design data from {SOURCE_DESIGN}",
    )
    drive["engine_power_max_w"] = q(MOTOR_POWER_W, "W", "estimated", SOURCE_DESIGN)
    drive["engine_speed_ratio_to_main"] = q(MOTOR_RATIO, "1", "estimated", SOURCE_DESIGN)
    drive["governor_target_main_rad_s"] = q(
        NOMINAL_OMEGA, "rad/s", "derived", f"{NOMINAL_RPM:g} rpm × 2π/60 from {SOURCE_DESIGN}",
    )

    electronics = block({
        "tail_collective_trim_rad": (0.09, "rad"),
        "tail_collective_min_rad": (-0.30, "rad"),
        "tail_collective_max_rad": (0.30, "rad"),
        "yaw_control_sign": (1, "1"),
        "yaw_deadzone": (0.025, "1"),
        "yaw_rate_kp_rad_per_rad_s": (0.025, "s"),
        "yaw_rate_ki_rad_per_rad": (0.006, "1"),
        "yaw_integrator_limit_rad": (0.15, "rad"),
        "body_rate_max_rad_s": ([6.0, 6.0, 4.0], "rad/s"),
        "body_rate_roll_cyclic_gain_rad_per_rad_s": (0.005, "s"),
        "body_rate_pitch_cyclic_gain_rad_per_rad_s": (0.005, "s"),
    })
    electronics["controller_law"] = "openrc-fbl-body-rate-electronics-v1"
    electronics["body_rate_max_rad_s"] = q(
        [6.0, 6.0, 4.0], "rad/s", "estimated",
        "HELI-36a laboratory FBL command envelope; provisional software input range, "
        "not measured or flight-qualified",
    )
    electronics["linkage"] = block({
        "collective_rad_per_unit": (0.24, "rad"),
        "longitudinal_rad_per_unit": (0.05, "rad"),
        "lateral_rad_per_unit": (0.05, "rad"),
        "collective_min_rad": (-0.24, "rad"),
        "collective_max_rad": (0.24, "rad"),
        "cyclic_max_rad": (0.05, "rad"),
    })
    electronics["curves_by_mode"] = {
        "3d": {
            "pitch": q([-1.0, -0.5, 0.0, 0.5, 1.0], "1", "estimated",
                       "HELI-36a symmetric laboratory collective curve; not a radio setup measurement"),
            "throttle": q([1.0, 1.0, 1.0, 1.0, 1.0], "1", "estimated",
                          "HELI-36a laboratory governed-flight command; no spool or powertrain validation"),
        },
    }

    main_spin_inertia = 2.0 * 0.042
    tail_spin_inertia = main_spin_inertia * 0.04 / (TAIL_RATIO * TAIL_RATIO)
    return {
        "format": "openrc-aircraft v2",
        "vehicle": "rotorcraft",
        "id": "hx700-electric-3d-experimental",
        "name": "HX-700 Electric 3D Experimental",
        "capabilities": ["main_rotor", "tail_rotor", "governor", "fbl_body_rate", "signed_collective", "skids"],
        "qualification": (
            "Laboratory-only independent HX-700 candidate data. The supplied model's "
            "5.2 kg, 2100 rpm and gearing are unvalidated design declarations; other "
            "aircraft dynamics and FBL gains are estimates. Shared mean-rotor and "
            "one-speed drive proxies have no HX-700 flight validation."
        ),
        "release_state": "laboratory_only",
        "main_rotor": main,
        "tail_rotor": tail,
        "airframe": airframe,
        "body": {
            "mass_kg": q(5.2, "kg", "estimated", SOURCE_DESIGN),
            "inertia_kg_m2": q([0.095, 0.24, 0.27, 0.0, 0.0, 0.0], "kg*m2", "estimated",
                               "HELI-36a estimate from the source-declared 5.2 kg class and visual proportions; no component mass/inertia inventory"),
        },
        "gravity_m_s2": q(9.80665, "m/s2", "manual", "standard gravity"),
        "shaft_elements": [
            {
                "inertia_kg_m2": q(main_spin_inertia, "kg*m2", "derived",
                                    "2 × estimated HX-700 blade flapping inertia; rigid-blade spin approximation"),
                "speed_ratio": q(1.0, "1", "derived", "main shaft"),
                "spin_axis_body_frd": q([0.0, 0.0, 1.0], "1", "derived", "FRD main rotor convention"),
            },
            {
                "inertia_kg_m2": q(tail_spin_inertia, "kg*m2", "estimated",
                                    "HELI-36a tail rotor inertia fraction and source-declared HX-700 tail ratio; not measured"),
                "speed_ratio": q(TAIL_RATIO, "1", "estimated", tail["tail_to_main_speed_ratio"]["source"]),
                "spin_axis_body_frd": q([0.0, 1.0, 0.0], "1", "derived", "FRD tail rotor convention"),
            },
        ],
        "drive": drive,
        "electronics": electronics,
        "integration": block({
            "flow_floor_m_s": (0.1, "m/s"),
            "fin_tail_wake_fraction": (0.15, "1"),
            "height_over_radius": (-1.0, "1"),
            "inflow_loss": (1.0, "1"),
            "inflow_instability": (0.0, "1"),
        }),
        "skids": {
            **block({"spring_n_m": (7000.0, "N/m"), "damping_n_s_m": (155.0, "N*s/m"),
                     "friction": (0.5, "1"), "slip_m_s": (0.15, "m/s")}),
            "points_body_frd_m": q(
                [0.0974, -0.0858, 0.1098, 0.0974, 0.0858, 0.1098,
                 -0.0974, -0.0858, 0.1098, -0.0974, 0.0858, 0.1098],
                "m", "derived", GEOMETRY,
            ),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check generated HX-700 data without writing")
    args = parser.parse_args()
    destination = ROOT / "app/data/aircraft/hx700_electric_3d_experimental.json"
    expected = json.dumps(derive(), indent=2) + "\n"
    if args.check:
        if not destination.is_file() or destination.read_text(encoding="utf-8") != expected:
            raise SystemExit(f"Generated HX-700 rotorcraft output is stale: {destination}")
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(expected, encoding="utf-8", newline="\n")
    print(f"{'checked' if args.check else 'generated'} {destination}")


if __name__ == "__main__":
    main()
