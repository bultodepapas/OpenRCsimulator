#!/usr/bin/env python3
"""Build the versioned MT8 ground-vehicle estimate from delivered geometry JSON.

This generator reads only the delivered mt8_spec.json and hashes the delivered
GLB as provenance. It does not execute the package's Blender scripts and does
not copy the visual asset into the application.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SPEC = ROOT / "RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/mt8_spec.json"
DEFAULT_GLB = ROOT / "RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/MT8_Bisonte.glb"
DEFAULT_OUT = ROOT / "app/data/vehicles/ground/mt8_bisonte.json"
FORMAT = "openrc-ground-vehicle"
VERSION = 1
VEHICLE_ID = "mt8-bisonte-electric-4wd-estimate-v1"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def q(value: Any, unit: str, kind: str, source: str) -> dict[str, Any]:
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def quantity_source(spec_rel: str, spec_hash: str, detail: str) -> str:
    return f"Derived from {spec_rel} SHA-256 {spec_hash}: {detail}"


def build(spec_path: Path, glb_path: Path) -> dict[str, Any]:
    spec_bytes = spec_path.read_bytes()
    spec = json.loads(spec_bytes)
    spec_hash = hashlib.sha256(spec_bytes).hexdigest()
    glb_hash = sha256(glb_path)
    spec_rel = spec_path.resolve().relative_to(ROOT).as_posix()
    glb_rel = glb_path.resolve().relative_to(ROOT).as_posix()

    if spec.get("units") != "m" or spec.get("frame") != {
        "right": "+X",
        "up": "+Y",
        "forward": "-Z",
    }:
        raise ValueError("unexpected delivered geometry units or axes")
    corners = spec.get("corners", {})
    if set(corners) != {"FL", "FR", "RL", "RR"}:
        raise ValueError("geometry spec must contain FL, FR, RL, RR")

    # Convert the supplied geometry frame (+X right, +Y up, -Z forward) into
    # body FRD (+X forward, +Y right, +Z down), the physics kernel convention.
    corner_x = [-float(corners[name]["wheel_center_rest"][2]) for name in ("FL", "FR", "RL", "RR")]
    corner_y = [float(corners[name]["wheel_center_rest"][0]) for name in ("FL", "FR", "RL", "RR")]
    corner_z = [-float(corners[name]["wheel_center_rest"][1]) for name in ("FL", "FR", "RL", "RR")]

    probe_centers: list[float] = []
    probe_radii: list[float] = []
    collision_boxes = spec.get("collision_boxes", {})
    expected_probes = ["COL_Bumper_F", "COL_Bumper_R", "COL_Chassis", "COL_Roof", "COL_Side_L", "COL_Side_R"]
    if set(collision_boxes) != set(expected_probes):
        raise ValueError("geometry spec collision proxy inventory changed")
    for name in expected_probes:
        box = collision_boxes[name]
        asset_x, asset_y, asset_z = (float(v) for v in box["center"])
        size_x, size_y, size_z = (float(v) for v in box["size"])
        # Hull probes are conservative vertical-radius proxies. The geometry
        # is estimated from the delivered low-complexity collision boxes.
        probe_centers.extend([-asset_z, asset_x, -asset_y])
        probe_radii.append(size_y * 0.5)

    geom = quantity_source(spec_rel, spec_hash, "the delivered blockout coordinate frame and named geometry values")
    estimate = "Engineering estimate for an electric 4WD simulation baseline; no physical weighing, spring, tire, torque, or handling measurements were supplied."
    geometry_source = (
        f"{geom}; converted from asset +X-right/+Y-up/-Z-forward to body FRD "
        "+X-forward/+Y-right/+Z-down."
    )
    parameters = {
        "sprung_mass_kg": q(4.8, "kg", "estimated", estimate),
        "unsprung_mass_kg": q(0.18, "kg", "estimated", f"{estimate} Per wheel; includes wheel-end hardware estimate."),
        "sprung_inertia_kg_m2": q(
            [0.067, 0.160, 0.115, 0.0, 0.0, 0.0],
            "kg m^2",
            "estimated",
            f"{estimate} Symmetric entries [Jxx,Jyy,Jzz,Jxy,Jxz,Jyz] about sprung CG, using the delivered chassis/body envelope as a scale reference.",
        ),
        "wheel_spin_inertia_kg_m2": q(0.0015, "kg m^2", "estimated", f"{estimate} Per wheel; wheel-end spin inertia placeholder."),
        "gravity_m_per_s2": q(9.80665, "m/s^2", "borrowed", "Standard nominal terrestrial gravitational acceleration."),
        "corner_x_datum_frd_m": q(corner_x, "m", "derived", geometry_source + " Ordered FL, FR, RL, RR from each wheel_center_rest.z."),
        "corner_y_datum_frd_m": q(corner_y, "m", "derived", geometry_source + " Ordered FL, FR, RL, RR from each wheel_center_rest.x."),
        "corner_z_datum_frd_m": q(corner_z, "m", "derived", geometry_source + " Ordered FL, FR, RL, RR; down-positive wheel centers at rest."),
        "cg_forward_from_datum_m": q(0.0, "m", "estimated", f"{estimate} Centered longitudinal CG placeholder; no component mass inventory is supplied."),
        "cg_right_from_datum_m": q(0.0, "m", "estimated", f"{estimate} Centered lateral CG placeholder; no component mass inventory is supplied."),
        "cg_height_above_chassis_datum_m": q(0.065, "m", "estimated", f"{estimate} Virtual low-mounted electric mass layout: CG 65 mm above the supplied chassis underside datum, reduced from the original 95 mm estimate. RCV handling launch tests at 5.2 Nm/wheel and 120 rad/s found 95 mm flipped, 80 mm stayed upright and 65 mm retained more pitch margin. Hull and rendering offsets are derived from this CG; mass and CG-relative inertia remain estimates. This is not a measured battery layout, and the 125 mm ride-origin dimension is not a CG measurement. See docs/research/rc-monster-truck/RCV-handling/README.md."),
        "arm_inner_offset_m": q(float(abs(corners["FL"]["arm_lower_pivot"][0])), "m", "derived", quantity_source(spec_rel, spec_hash, "corners.FL.arm_lower_pivot.x magnitude; suspension inner pivot offset")),
        "arm_length_m": q(float(spec["arm_length"]), "m", "derived", quantity_source(spec_rel, spec_hash, "arm_length")),
        "wheel_center_rest_below_chassis_datum_m": q(sum(corner_z) / len(corner_z), "m", "derived", geometry_source + " Mean of the four supplied wheel_center_rest heights."),
        "tire_radius_m": q(float(spec["tire_radius"]), "m", "derived", quantity_source(spec_rel, spec_hash, "tire_radius")),
        "suspension_stiffness_n_per_m": q(900.0, "N/m", "estimated", estimate),
        "suspension_damping_n_s_per_m": q(45.0, "N s/m", "estimated", estimate),
        "tire_stiffness_n_per_m": q(6500.0, "N/m", "estimated", estimate),
        "tire_damping_n_s_per_m": q(28.0, "N s/m", "estimated", estimate),
        "tire_slip_relaxation_s": q(0.04, "s", "estimated", estimate),
        "travel_droop_m": q(float(spec["travel_droop"]), "m", "derived", quantity_source(spec_rel, spec_hash, "travel_droop")),
        "travel_bump_m": q(float(spec["travel_bump"]), "m", "derived", quantity_source(spec_rel, spec_hash, "travel_bump")),
        "bump_stop_stiffness_n_per_m": q(8000.0, "N/m", "estimated", estimate),
        "bump_stop_damping_n_s_per_m": q(80.0, "N s/m", "estimated", estimate),
        "droop_stop_stiffness_n_per_m": q(10000.0, "N/m", "estimated", estimate),
        "droop_stop_damping_n_s_per_m": q(80.0, "N s/m", "estimated", estimate),
        "drive_torque_per_wheel_nm": q(5.2, "N m", "estimated", f"{estimate} Equal-torque electric 4WD approximation; RCV handling revision raises stall torque from 4.2 to 5.2 Nm per wheel. See docs/research/rc-monster-truck/RCV-handling/README.md."),
        "brake_torque_per_wheel_nm": q(1.35, "N m", "estimated", f"{estimate} Nominal mean per-wheel capacity; four times this value is the total brake torque budget, allocated by brake_front_fraction. RCV handling tests at 11.87 m/s found 2.0 Nm pitched over, while 1.2 through 1.65 Nm stopped in similar times; 1.35 Nm retains pitch margin with 85/15 axle allocation. See docs/research/rc-monster-truck/RCV-handling/README.md."),
        "brake_front_fraction": q(0.85, "1", "estimated", f"{estimate} Fixed virtual axle brake allocation: 85 percent front, 15 percent rear, preserving four times the nominal per-wheel torque budget. Chosen from RCV handling tests to reduce premature rear lock; no yaw or slip feedback. This estimated independent-axle brake arrangement is not a measured Traxxas or central-driveline specification. See docs/research/rc-monster-truck/RCV-handling/README.md."),
        "reverse_torque_fraction": q(0.60, "1", "estimated", estimate),
        "drive_torque_fade_rad_s": q(120.0, "rad/s", "estimated", f"{estimate} Linear torque fade reaches zero at this wheel speed; 0.100 m tires imply 12 m/s unloaded rolling speed and the four curves imply 624 W peak mechanical power. This is not a measured motor curve, battery model or guaranteed road speed."),
        "rolling_resistance_coefficient": q(0.035, "1", "estimated", estimate),
        "tire_friction_scale": q(0.90, "1", "estimated", estimate),
        "max_steer_angle_rad": q(math.radians(float(spec["steer_max_deg"])), "rad", "derived", quantity_source(spec_rel, spec_hash, "steer_max_deg converted to radians")),
        "steer_servo_natural_frequency_rad_s": q(18.0, "rad/s", "estimated", estimate),
        "steer_servo_damping_ratio": q(0.90, "1", "estimated", estimate),
        "hull_probe_centers_datum_frd_m": q(probe_centers, "m", "derived", geometry_source + " Centers from the six supplied COL_* proxy boxes, flattened as FRD triplets."),
        "hull_probe_radii_m": q(probe_radii, "m", "derived", quantity_source(spec_rel, spec_hash, "half of each COL_* proxy box vertical (+Y) dimension, used as simple hull contact probes")),
        "hull_contact_stiffness_n_per_m": q(15000.0, "N/m", "estimated", estimate),
        "hull_contact_damping_n_s_per_m": q(150.0, "N s/m", "estimated", estimate),
        "hull_contact_friction_scale": q(0.60, "1", "estimated", estimate),
    }

    return {
        "format": FORMAT,
        "version": VERSION,
        "id": VEHICLE_ID,
        "name": "MT8 Bisonte, electric 4WD estimate",
        "description": (
            "Simulation-only estimated electric 4WD baseline scaled from the delivered MT8 blockout geometry. "
            "Mass, inertia, suspension, tire, drivetrain, and servo values are estimates, not measured vehicle data."
        ),
        "drive_configuration": "electric_4wd",
        "geometry_source": {
            "spec_path": spec_rel,
            "spec_sha256": spec_hash,
            "glb_path": glb_rel,
            "glb_sha256": glb_hash,
            "asset_frame": {"right": "+X", "up": "+Y", "forward": "-Z"},
            "physics_frame": {"forward": "+X", "right": "+Y", "down": "+Z"},
            "rights_status": "User confirmed the supplied model and scripts may be included and modified; original source paths and hashes remain recorded.",
        },
        "parameters": parameters,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--glb", type=Path, default=DEFAULT_GLB)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare deterministic generated bytes with --out without creating or modifying files",
    )
    args = parser.parse_args()
    if not args.spec.is_file() or not args.glb.is_file():
        parser.error("delivered geometry spec and GLB must both exist for provenance")
    try:
        document = build(args.spec, args.glb)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    # Encode explicitly so generated output is byte-identical on Windows and
    # Unix. Path.write_text() uses platform newline translation on Windows.
    generated = (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if args.check:
        try:
            current = args.out.read_bytes()
        except OSError as exc:
            print(f"stale generated vehicle data: cannot read {args.out}: {exc}", file=sys.stderr)
            return 1
        if current != generated:
            print(f"stale generated vehicle data: {args.out}", file=sys.stderr)
            return 1
        print(f"generated vehicle data is current: {args.out}")
        return 0
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(generated)
    print(f"wrote {args.out} (spec {document['geometry_source']['spec_sha256']}, GLB {document['geometry_source']['glb_sha256']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
