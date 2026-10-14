"""Generate the local experimental X-Cell/HX-700 rotorcraft preset. No mesh generation."""
import json
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = "https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf"
ESTIMATE = "docs/research/helicopter/HELI-16/README.md: explicit research trainer estimates"

def q(value, unit, kind="estimated", source=ESTIMATE):
    return dict(value=value, unit=unit, kind=kind, source=source)

def block(values, sourced=False):
    return {key: q(value, unit, "borrowed" if sourced else "estimated", SOURCE if sourced else ESTIMATE)
            for key, (value, unit) in values.items()}

def derive():
    main = block({
        "rho_kg_m3": (1.225, "kg/m3"), "rotor_radius_m": (.775, "m"), "blade_chord_m": (.058, "m"),
        "rotor_blade_count": (2, "1"), "blade_lift_curve_slope_per_rad": (5.5, "1/rad"),
        "blade_section_cd0": (.024, "1"), "thrust_coefficient_max": (.0055, "1"),
        "blade_flapping_inertia_kg_m2": (.038, "kg*m2"), "gamma_flybar": (.8, "1"), "flapback_k_mu": (.2, "1"),
        "omega_nominal_rad_s": (167, "rad/s"), "cyclic_longitudinal_gain_nominal_rad_per_rad": (4.2, "1"),
        "cyclic_lateral_gain_nominal_rad_per_rad": (4.2, "1"), "hub_spring_stiffness_nm_per_rad": (54, "N*m/rad"),
        "hub_position_body_frd_m": ([0, 0, -.235], "m"), "rotation_sense": (1, "1"),
    }, True)
    tail = block({
        "rho_kg_m3": (1.225, "kg/m3"), "main_rotor_radius_m": (.775, "m"), "tail_rotor_radius_m": (.13, "m"),
        "blade_chord_m": (.029, "m"), "rotor_blade_count": (2, "1"), "blade_lift_curve_slope_per_rad": (5, "1/rad"),
        "blade_section_cd0": (.024, "1"), "thrust_coefficient_max": (.05, "1"), "tail_to_main_speed_ratio": (4.66, "1"),
        "hub_distance_aft_m": (.91, "m"), "hub_height_above_cg_m": (.08, "m"), "vertical_fin_area_m2": (.012, "m2"),
        "trim_collective_rad": (.1, "rad"), "wake_efficiency": (.9, "1"), "rotation_sense": (1, "1"),
    }, True)
    tail["wake_efficiency"] = q(.9, "1")
    tail["rotation_sense"] = q(1, "1")
    main["rotation_sense"] = q(1, "1", "derived", "HELI-05 FRD convention: positive relative main spin about +Z")
    airframe = block({
        "rho_kg_m3": (1.225, "kg/m3"), "fuselage_drag_area_body_m2": ([.1, .22, .15], "m2"),
        "fuselage_cp_body_frd_m": ([0, 0, 0], "m"), "vertical_fin_area_m2": (.012, "m2"),
        "vertical_fin_lift_curve_slope_per_rad": (2, "1/rad"), "vertical_fin_cp_body_frd_m": ([-.91, 0, -.08], "m"),
        "horizontal_tail_area_m2": (.01, "m2"), "horizontal_tail_lift_curve_slope_per_rad": (3, "1/rad"),
        "horizontal_tail_cp_body_frd_m": ([-.71, 0, 0], "m"),
    }, True)
    airframe["horizontal_tail_cp_body_frd_m"] = q([-.71, 0, 0], "m")
    airframe["fuselage_cp_body_frd_m"] = q([0, 0, 0], "m")
    drive = block({
        "engine_torque_max_nm": (1.2, "N*m"), "engine_power_max_w": (1800, "W"),
        "engine_speed_ratio_to_main": (8.3, "1"), "gear_efficiency": (.9, "1"),
        "governor_target_main_rad_s": (167, "rad/s"), "governor_gain_nm_per_rad_s": (.08, "N*m*s/rad"),
        "shaft_loss_torque_nm": (.08, "N*m"), "shaft_viscous_loss_nm_per_rad_s": (.001, "N*m*s/rad"),
    })
    electronics = block({
        "tail_collective_trim_rad": (.1, "rad"), "tail_collective_min_rad": (-.3, "rad"), "tail_collective_max_rad": (.3, "rad"),
        "yaw_control_sign": (1, "1"), "yaw_deadzone": (.025, "1"), "yaw_max_rate_rad_s": (1.5, "rad/s"),
        "yaw_heading_gain_per_s": (2, "1/s"), "yaw_rate_kp_rad_per_rad_s": (.05, "s"),
        "yaw_rate_ki_rad_per_rad": (.02, "1"), "yaw_integrator_limit_rad": (.15, "rad"),
        "trainer_max_tilt_rad": (.35, "rad"), "trainer_roll_attitude_gain_per_s": (3, "1/s"),
        "trainer_pitch_attitude_gain_per_s": (3, "1/s"), "trainer_roll_rate_limit_rad_s": (1.5, "rad/s"),
        "trainer_pitch_rate_limit_rad_s": (1.5, "rad/s"), "trainer_roll_cyclic_gain_rad_per_rad_s": (.03, "s"),
        "trainer_pitch_cyclic_gain_rad_per_rad_s": (.03, "s"),
    })
    electronics["linkage"] = block({
        "collective_rad_per_unit": (.22, "rad"), "longitudinal_rad_per_unit": (.06, "rad"), "lateral_rad_per_unit": (.06, "rad"),
        "collective_min_rad": (-.22, "rad"), "collective_max_rad": (.22, "rad"), "cyclic_max_rad": (.06, "rad"),
    })
    electronics["curves_by_mode"] = {
        "normal": {"pitch": q([-.2, .1, .45, .7, 1], "1"), "throttle": q([.85]*5, "1")},
        "idle_up": {"pitch": q([-1, -.5, 0, .5, 1], "1"), "throttle": q([1]*5, "1")},
    }
    return {
        "format": "openrc-aircraft v2", "vehicle": "rotorcraft", "id": "xcell-60-research",
        "name": "RC Helicopter Research Trainer", "capabilities": ["main_rotor", "tail_rotor", "governor", "trainer", "skids"],
        "qualification": "Experimental research surrogate: X-Cell .60 equations, HX-700 flybarless visual. No aircraft-specific flight validation.",
        "main_rotor": main, "tail_rotor": tail, "airframe": airframe,
        "body": block({"mass_kg": (8.2,"kg"), "inertia_kg_m2": ([.18,.34,.28,0,0,0],"kg*m2")}, True),
        "gravity_m_s2": q(9.80665,"m/s2","manual","standard gravity"),
        "shaft_elements": [
            dict(inertia_kg_m2=q(.076,"kg*m2","derived","2 * published blade flapping inertia; rigid radial-blade estimate"), speed_ratio=q(1,"1","derived","main shaft"), spin_axis_body_frd=q([0,0,1],"1","derived","FRD main rotor convention")),
            dict(inertia_kg_m2=q(.076*.05/4.66**2,"kg*m2"), speed_ratio=q(4.66,"1","borrowed",SOURCE), spin_axis_body_frd=q([0,1,0],"1")),
        ],
        "drive": drive, "electronics": electronics,
        "integration": block({"flow_floor_m_s": (.1,"m/s"), "fin_tail_wake_fraction": (.2,"1"), "height_over_radius": (-1,"1"), "inflow_loss": (1,"1"), "inflow_instability": (0,"1")}),
        "skids": {**block({"spring_n_m": (10000,"N/m"), "damping_n_s_m": (190,"N*s/m"), "friction": (.5,"1"), "slip_m_s": (.15,"m/s")}),
            "points_body_frd_m": q([.0974,-.0858,.1098,.0974,.0858,.1098,-.0974,-.0858,.1098,-.0974,.0858,.1098],"m","derived","HELI-25: measured supplied HX-700 GLB rail corners, CG datum up 0.110 m")},
    }

def schema_for(node):
    if isinstance(node, dict) and set(node) == {"value", "unit", "kind", "source"}:
        value = {"type": "number"} if not isinstance(node["value"], list) else {
            "type": "array", "items": {"type": "number"}, "minItems": len(node["value"]), "maxItems": len(node["value"])}
        return {"type": "object", "additionalProperties": False, "required": list(node), "properties": {
            "value": value, "unit": {"const": node["unit"]}, "kind": {"enum": ["manual", "measured", "borrowed", "estimated", "derived"]},
            "source": {"type": "string", "minLength": 1}}}
    if isinstance(node, dict):
        return {"type": "object", "additionalProperties": False, "required": list(node), "properties": {k: schema_for(v) for k,v in node.items()}}
    if isinstance(node, list):
        if node and isinstance(node[0], dict):
            return {"type": "array", "items": schema_for(node[0]), "minItems": 1}
        return {"const": node}
    return {"const": node}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check generated preset and schema without changing files")
    args = parser.parse_args()
    path = ROOT / "app/data/aircraft/xcell_60_research.json"
    schema = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "openrc-rotorcraft-v2", **schema_for(derive())}
    outputs = {path: derive(), ROOT / "app/data/schema/openrc-rotorcraft-v2.schema.json": schema}
    for destination, payload in outputs.items():
        expected = json.dumps(payload, indent=2) + "\n"
        if args.check:
            if not destination.is_file() or destination.read_text(encoding="utf-8") != expected:
                raise SystemExit(f"Generated rotorcraft output is stale: {destination}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(expected, encoding="utf-8", newline="\n")
        print(f"{'checked' if args.check else 'generated'} {destination}")
