#!/usr/bin/env python3
"""Generate a visual-to-physics equipment and landing-gear handoff.

All source lengths are read from the model JSON and physics inventory. The
result is a coordinate audit of provisional visual placements, not a physical
installation or taxi validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_GEOMETRY = ROOT / "assets/aircraft/ugly-stik-60/geometry.json"
DEFAULT_PHYSICS = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
DEFAULT_BUILDER = ROOT / "app/aircraft/ugly_stik_model.gd"
DEFAULT_RENDER_ADAPTER = ROOT / "app/render/airplane.gd"
DEFAULT_OUTPUT = ROOT / "research/ugly-stik/model-v3/equipment-handoff.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def subtract(a: list[float], b: list[float]) -> list[float]:
    return [x - y for x, y in zip(a, b)]


def model_to_le(point: list[float], leading_z: float, shaft_y: float) -> list[float]:
    """Model (+X right,+Y up,-Z nose) to LE [x_aft,y_right,z_up]."""
    return [point[2] - leading_z, point[0], point[1] - shaft_y]


def le_to_model(point: list[float], leading_z: float, shaft_y: float) -> list[float]:
    return [point[1], shaft_y + point[2], leading_z + point[0]]


def le_to_body(point: list[float], cg_le: list[float]) -> list[float]:
    """LE frame to body FRD about CG: x-forward, y-right, z-down."""
    return [cg_le[0] - point[0], point[1] - cg_le[1], cg_le[2] - point[2]]


def rotate_x(point: list[float], angle: float) -> list[float]:
    c, s = math.cos(angle), math.sin(angle)
    return [point[0], c * point[1] - s * point[2], s * point[1] + c * point[2]]


def inventory_by_prefix(data: dict[str, Any], prefix: str) -> dict[str, Any] | None:
    for item in data.get("inventory", []):
        if item.get("name", "").lower().startswith(prefix.lower()):
            return item
    return None


def make_handoff(geometry: dict[str, Any], physics: dict[str, Any], builder_path: Path,
                 render_adapter_path: Path, geometry_path: Path, physics_path: Path) -> dict[str, Any]:
    wing = geometry["wing"]
    equipment = geometry["equipment"]
    leading_z = float(wing["leading_z"])
    shaft_y = float(equipment["shaft_y"])
    cg_le = [float(v) for v in physics["balance"]["plan_cg"]["value"]]
    cg_model = le_to_model(cg_le, leading_z, shaft_y)

    main_radius = float(equipment["main_wheel_diameter"]) / 2.0
    nose_radius = float(equipment["nose_wheel_diameter"]) / 2.0
    main_z = float(equipment["main_axle_z"])
    nose_z = float(equipment["nose_axle_z"])
    wheel_y = float(equipment["wheel_y"])
    half_track = float(equipment["main_track"]) / 2.0

    wheels: dict[str, dict[str, Any]] = {}
    wheel_inputs = {
        "main_left": (-half_track, main_z, main_radius),
        "main_right": (half_track, main_z, main_radius),
        "nose": (0.0, nose_z, nose_radius),
    }
    for name, (x, z, radius) in wheel_inputs.items():
        axle_model = [x, wheel_y, z]
        contact_model = [x, wheel_y - radius, z]
        axle_le = model_to_le(axle_model, leading_z, shaft_y)
        contact_le = model_to_le(contact_model, leading_z, shaft_y)
        wheels[name] = {
            "axle_center_model_m": axle_model,
            "nominal_ground_contact_model_m": contact_model,
            "radius_m": radius,
            "axle_center_le_m": axle_le,
            "nominal_ground_contact_le_m": contact_le,
            "axle_center_body_cg_frd_m": le_to_body(axle_le, cg_le),
            "nominal_ground_contact_body_cg_frd_m": le_to_body(contact_le, cg_le),
            "spin_axis_model_unit": [1.0, 0.0, 0.0],
            "placement_evidence": "estimated visual placement; wheel size is selected from Jensen plan callouts",
        }

    # Equalize the two axle tires' lowest points under a rigid X rotation.
    pitch_denominator = nose_z - main_z
    pitch = math.asin(-(nose_radius - main_radius) / pitch_denominator)
    c, s = math.cos(pitch), math.sin(pitch)
    ground_y = c * wheel_y - s * main_z - main_radius
    nose_contact_y = c * wheel_y - s * nose_z - nose_radius
    prop_center_model = [0.0, shaft_y, float(equipment["prop_z"])]
    prop_center_after_pitch = rotate_x(prop_center_model, pitch)
    prop_radius = float(equipment["prop_diameter"]) / 2.0
    prop_low_y = prop_center_after_pitch[1] - prop_radius * c

    inventory_names = {
        "engine": "engine O.S. MAX-61FX",
        "propeller": "propeller APC 12x6 Sport",
        "nose_gear": "nose gear and 2.75 in wheel",
        "main_gear": "main gear and 3 in wheels",
    }
    inventory = {
        key: inventory_by_prefix(physics, prefix)
        for key, prefix in inventory_names.items()
    }

    engine_z = (float(equipment["firewall_z"]) + float(equipment["prop_z"])) / 2.0
    engine_crank_model = [0.0, shaft_y, engine_z]
    engine_crank_le = model_to_le(engine_crank_model, leading_z, shaft_y)
    prop_le = model_to_le(prop_center_model, leading_z, shaft_y)
    physics_prop_diameter = physics.get("propulsion", {}).get("propeller", {}).get("diameter", {}).get("value")
    gear_evidence = geometry.get("evidence", {}).get("equipment.other", {})
    wheel_evidence = geometry.get("evidence", {}).get("equipment.wheels", {})
    engine_evidence = geometry.get("evidence", {}).get("equipment.engine", {})
    main_gear_inventory_position = inventory["main_gear"]["position"]["value"] if inventory["main_gear"] else None
    main_axle_midpoint_le = [main_z - leading_z, 0.0, wheel_y - shaft_y]
    main_inventory_delta = subtract(main_gear_inventory_position, main_axle_midpoint_le) if main_gear_inventory_position else None

    return {
        "schema": "openrc-ugly-stik-equipment-handoff-v1",
        "aircraft_id": geometry["id"],
        "evidence_kind": "coordinate audit of estimated visual placements and current physics reference data",
        "sources": {
            "geometry": {"path": str(geometry_path.relative_to(ROOT) if geometry_path.is_relative_to(ROOT) else geometry_path), "sha256": sha256(geometry_path)},
            "physics": {"path": str(physics_path.relative_to(ROOT) if physics_path.is_relative_to(ROOT) else physics_path), "sha256": sha256(physics_path)},
            "visual_builder": {"path": str(builder_path.relative_to(ROOT) if builder_path.is_relative_to(ROOT) else builder_path), "sha256": sha256(builder_path)},
            "render_adapter": {"path": str(render_adapter_path.relative_to(ROOT) if render_adapter_path.is_relative_to(ROOT) else render_adapter_path), "sha256": sha256(render_adapter_path)},
        },
        "frames": {
            "visual_model": {"axes": {"right": "+X", "up": "+Y", "nose": "-Z"}, "origin": geometry.get("datum", "see geometry source")},
            "physics_le": {"axes": ["x_aft", "y_right", "z_up"], "origin": "wing leading edge at fuselage centerline; z=0 on thrust line"},
            "physics_body_cg_frd": {"axes": ["x_forward", "y_right", "z_down"], "origin": "plan CG"},
            "model_to_le_formula": "[z_model - wing.leading_z, x_model, y_model - equipment.shaft_y]",
            "le_to_body_formula": "[cg_x_aft - x_aft, y_right - cg_y, cg_z_up - z_up]",
            "le_to_model_formula": "[y_right, equipment.shaft_y + z_up, wing.leading_z + x_aft]",
            "cg_le_m": cg_le,
            "cg_visual_model_m": cg_model,
            "runtime_transform": "app/render/frames.gd: cg_in_model_frame() and root_transform(); root origin is translated so cg_visual_model lands on the physics CG position",
        },
        "engine_and_propeller": {
            "visual_engine_class": geometry.get("engine_class", ".61 nitro"),
            "visual_engine_identity": "generic single-cylinder .61 envelope; brand/model not selected",
            "visual_engine_evidence": engine_evidence,
            "physics_engine_inventory_entry": inventory["engine"]["name"] if inventory["engine"] else None,
            "physics_engine_entry_role": "provisional mass/inertia inventory entry; it does not identify the visual engine as this exact product",
            "physics_engine_inventory_mass": inventory["engine"]["mass"] if inventory["engine"] else None,
            "engine_visual_crank_center_model_m": engine_crank_model,
            "engine_visual_crank_center_le_m": engine_crank_le,
            "engine_physics_inventory_position_le_m": inventory["engine"]["position"]["value"] if inventory["engine"] else None,
            "engine_crank_minus_inventory_center_le_m": subtract(engine_crank_le, inventory["engine"]["position"]["value"]) if inventory["engine"] else None,
            "mount": {"visual_envelope": "simplified beam mount and fasteners; see builder source", "firewall_to_prop_plane_m": float(equipment["firewall_z"]) - float(equipment["prop_z"])},
            "muffler": "simplified side-mounted visual muffler/header; clearance is not checked against a selected commercial engine installation",
            "propeller_visual_center_model_m": prop_center_model,
            "propeller_visual_center_le_m": prop_le,
            "propeller_physics_inventory_position_le_m": inventory["propeller"]["position"]["value"] if inventory["propeller"] else None,
            "propeller_visual_minus_inventory_center_le_m": subtract(prop_le, inventory["propeller"]["position"]["value"]) if inventory["propeller"] else None,
            "propeller_placement_evidence": gear_evidence,
            "propeller_diameter_visual_m": float(equipment["prop_diameter"]),
            "propeller_diameter_physics_m": physics_prop_diameter,
            "prop_swept_disk": {"axis_model_unit": [0.0, 0.0, 1.0], "normal": "parallel to visual Z; thrust points along -Z", "ground_clearance_three_wheel_pose_m": prop_low_y - ground_y},
        },
        "landing_gear": {
            "wheels": wheels,
            "main_track_m": float(equipment["main_track"]),
            "wheel_size_evidence": wheel_evidence,
            "wheel_position_evidence": gear_evidence,
            "wheel_spin_axis": "parallel to visual +X for all three wheels; axis line is unoriented geometrically",
            "nose_steering_axis": {"model_point_m": [0.0, wheel_y, nose_z], "model_direction_unit": [0.0, 1.0, 0.0]},
            "physics_inventory_centroid_comparison": {
                "nose_gear_position_le_m": inventory["nose_gear"]["position"]["value"] if inventory["nose_gear"] else None,
                "nose_gear_inventory_minus_visual_axle_le_m": subtract(inventory["nose_gear"]["position"]["value"], wheels["nose"]["axle_center_le_m"]) if inventory["nose_gear"] else None,
                "main_gear_position_le_m": inventory["main_gear"]["position"]["value"] if inventory["main_gear"] else None,
                "visual_main_axle_midpoint_le_m": main_axle_midpoint_le,
                "main_gear_inventory_minus_visual_axle_midpoint_le_m": main_inventory_delta,
                "main_gear_lateral_envelope_physics_m": inventory["main_gear"].get("size", {}).get("value", [None, None, None])[1] if inventory["main_gear"] else None,
                "main_gear_note": "physics inventory point is a component mass centroid on centerline, not a wheel axle; its lateral size is an envelope. Do not move the visual wheels to match its centroid.",
            },
            "rigid_three_wheel_rest_pose": {
                "root_rotation_x_rad": pitch,
                "root_rotation_x_deg": math.degrees(pitch),
                "local_ground_plane_y_m": ground_y,
                "nose_contact_residual_m": nose_contact_y - ground_y,
                "propeller_disk_clearance_to_ground_m": prop_low_y - ground_y,
                "assumptions": ["undeformed circular tires", "parallel axles", "no suspension, tire compliance, steering scrub, or contact dynamics"],
            },
            "gear_render_contract": {
                "status": "implemented visual contract; no physics-to-render hookup",
                "builder_result": "build() returns gear dictionary keys left, right, nose, steering; left/right/nose are wheel pivots and steering is the nose steering pivot",
                "adapter": "app/render/airplane.gd: apply_gear(airplane, wheel_angles: Dictionary, steering_rad: float)",
                "input_units": "radians",
                "physics_integration": "caller supplies wheel angle and steering angle; model adapter does not create contact forces or infer wheel speed",
                "raw_angle_convention": "adapter assigns wheel_angles directly to local rotation.x and steering_rad directly to local rotation.y",
                "mapping_from_physics_convention": "If wheel angle is defined positive for forward travel along nose -Z, send -angle to rotation.x. If steering is positive for yaw right, send -steering_rad to rotation.y because +Y rotates nose -Z toward -X (left).",
                "mesh_contract": "preserve gear_left, gear_right, nosewheel names and current wheel centers; pivots are for visual articulation only",
            },
        },
        "limits": [
            "All coordinates are the current visual model's local frame until app/render/frames.gd applies the root transform.",
            "Wheel sizes are selected from drawing callouts; axle/gear locations and propeller placement are estimated visual geometry.",
            "The generic .61 engine, mount, muffler and 12-inch swept disk are not checked against a chosen engine, mount, fuel tank, cowl or firewall hardware drawing.",
            "Ground contact and propeller clearance are rigid-body calculations on the rendered dimensions, not physical validation or taxi dynamics.",
            "Physics inventory positions are mass centroids; they are not automatically visual hardpoints.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--geometry", type=Path, default=DEFAULT_GEOMETRY)
    parser.add_argument("--physics", type=Path, default=DEFAULT_PHYSICS)
    parser.add_argument("--builder", type=Path, default=DEFAULT_BUILDER)
    parser.add_argument("--render-adapter", type=Path, default=DEFAULT_RENDER_ADAPTER)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    geometry = json.loads(args.geometry.read_text())
    physics = json.loads(args.physics.read_text())
    result = make_handoff(geometry, physics, args.builder, args.render_adapter, args.geometry, args.physics)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
