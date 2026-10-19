#!/usr/bin/env python3
"""Build the MONSTER CAR 2 ground-vehicle data from the supplied source files.

The chassis geometry and mass inventory are model-derived estimates, not
physical measurements. Powertrain values are explicit simulation estimates
because the delivered source has no manufacturer engine curve, usable fuel
capacity, clutch map, or measured brake/tire data.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import struct
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SPEC = ROOT / "assets/vehicles/monster-car-2/datos_simulacion_1.json"
DEFAULT_GLB = ROOT / "assets/vehicles/monster-car-2/monster_truck_nitro_1.glb"
DEFAULT_COLLISION_GLB = ROOT / "assets/source-deliveries/monster-car-2/monster_truck_colisiones_1.glb"
DEFAULT_OUTPUT = ROOT / "app/data/vehicles/ground/monster_car_2.json"
RUNTIME_SPEC_PATH = "assets/vehicles/monster-car-2/datos_simulacion_1.json"
RUNTIME_GLB_PATH = "assets/vehicles/monster-car-2/monster_truck_nitro_1.glb"
COLLISION_PROBE_NAMES = [
    "COL_Parachoques_Del",
    "COL_Parachoques_Tras",
    "COL_Chasis_Placa",
    "COL_Motor",
    "COL_Mamparo_Del",
    "COL_Mamparo_Tras",
]
ROOF_PROBE_NAME = "COL_Carroceria"
SIDE_PROBE_NAME = "COL_Carroceria"
POWERTRAIN_ESTIMATES = {
    "engine_displacement_cm3": (4.6, "cm^3"),
    "engine_idle_rpm": (4500.0, "rpm"),
    "engine_max_rpm": (38000.0, "rpm"),
    "engine_rotor_inertia_kg_m2": (0.0001, "kg m^2"),
    "engine_drag_torque_nm": (0.015, "N m"),
    "engine_viscous_drag_nm_s_per_rad": (0.000003, "N m s/rad"),
    "idle_torque_nm": (0.045, "N m"),
    "idle_governor_gain_nm_s_per_rad": (0.002, "N m s/rad"),
    "clutch_engage_start_rpm": (8500.0, "rpm"),
    "clutch_engage_full_rpm": (12000.0, "rpm"),
    "clutch_capacity_nm": (0.62, "N m"),
    "clutch_slip_stiffness_nm_s_per_rad": (0.0025, "N m s/rad"),
    "gear_efficiency": (0.82, "1"),
    "initial_fuel_mass_kg": (0.1, "kg"),
    "fuel_specific_consumption_kg_per_j": (6.0e-7, "kg/J"),
}
TORQUE_CURVE_RPM = [0, 4000, 8000, 12000, 16000, 20000, 24000, 28000, 32000, 36000, 40000]
TORQUE_CURVE_NM = [0.0, 0.12, 0.25, 0.37, 0.47, 0.54, 0.58, 0.60, 0.58, 0.43, 0.0]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def quantity(value: Any, unit: str, kind: str, source: str) -> dict[str, Any]:
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def glb_document(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        raise ValueError(f"Not a binary glTF file: {path}")
    version, declared_length = struct.unpack_from("<II", raw, 4)
    if version != 2 or declared_length != len(raw):
        raise ValueError(f"Unsupported or malformed GLB header: {path}")
    offset = 12
    document = None
    while offset + 8 <= len(raw):
        length, chunk_type = struct.unpack_from("<II", raw, offset)
        offset += 8
        chunk = raw[offset : offset + length]
        offset += length
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8"))
            break
    if not isinstance(document, dict):
        raise ValueError(f"GLB has no JSON chunk: {path}")
    return document


def multiply(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [
        [sum(a[row][inner] * b[inner][column] for inner in range(4)) for column in range(4)]
        for row in range(4)
    ]


def node_matrix(node: dict[str, Any]) -> list[list[float]]:
    if "matrix" in node:
        values = node["matrix"]
        return [[float(values[column * 4 + row]) for column in range(4)] for row in range(4)]
    translation = [float(value) for value in node.get("translation", [0, 0, 0])]
    scale = [float(value) for value in node.get("scale", [1, 1, 1])]
    x, y, z, w = [float(value) for value in node.get("rotation", [0, 0, 0, 1])]
    rotation = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    result = [[0.0] * 4 for _ in range(4)]
    for row in range(3):
        for column in range(3):
            result[row][column] = rotation[row][column] * scale[column]
        result[row][3] = translation[row]
    result[3][3] = 1.0
    return result


def collision_node_bounds(path: Path) -> dict[str, tuple[list[float], list[float]]]:
    document = glb_document(path)
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    accessors = document.get("accessors", [])
    parents: dict[int, int] = {}
    for parent_index, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[int(child)] = parent_index
    worlds: dict[int, list[list[float]]] = {}

    def world(index: int) -> list[list[float]]:
        if index not in worlds:
            local = node_matrix(nodes[index])
            worlds[index] = multiply(world(parents[index]), local) if index in parents else local
        return worlds[index]

    result: dict[str, tuple[list[float], list[float]]] = {}
    for node_index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        name = str(node.get("name", ""))
        mesh = meshes[int(node["mesh"])]
        transformed: list[list[float]] = []
        matrix = world(node_index)
        for primitive in mesh.get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None:
                continue
            accessor = accessors[int(position_index)]
            if "min" not in accessor or "max" not in accessor:
                raise ValueError(f"Position accessor lacks bounds for {name}")
            minimum = [float(value) for value in accessor["min"]]
            maximum = [float(value) for value in accessor["max"]]
            for point in itertools.product(*zip(minimum, maximum)):
                transformed.append(
                    [
                        sum(matrix[row][column] * point[column] for column in range(3)) + matrix[row][3]
                        for row in range(3)
                    ]
                )
        if transformed:
            result[name] = (
                [min(point[axis] for point in transformed) for axis in range(3)],
                [max(point[axis] for point in transformed) for axis in range(3)],
            )
    return result


def source_statement(spec_sha: str, detail: str) -> str:
    return f"Derived from supplied estimated geometry data SHA-256 {spec_sha}; {detail}. The source is a model-based estimate, not a physical measurement."


def build(spec_path: Path, glb_path: Path, collision_path: Path) -> dict[str, Any]:
    source = json.loads(spec_path.read_text(encoding="utf-8"))
    if source.get("ejes_blender", "").split(";")[0] != "X adelante, Y izquierda, Z arriba":
        raise ValueError("The source geometry axes do not match the documented Blender frame")
    spec_hash = sha256(spec_path)
    glb_hash = sha256(glb_path)
    collision_hash = sha256(collision_path)
    geometry = source["geometria"]
    corners = source["esquinas"]
    masses = source["masas"]
    spring_data = source["resortes_sugeridos"]["por_eje"]
    # Keep a positive 0.5 mm rest offset because the v1 loader requires the
    # wheel centers to sit strictly below its selected chassis datum.
    datum_up_m = float(geometry["altura_eje_reposo"]) + 0.0005
    tire_radius_m = float(geometry["radio_rueda"])

    # Preserve the supplied +X-forward/+Y-left/+Z-up geometry in the runtime
    # FRD frame. The solver chassis datum is placed at the rest axle height,
    # making the source wheel centers 0.5 mm down from that datum.
    wheel_order = ["Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der"]
    wheel_points = [corners[name]["puntos"]["W"] for name in wheel_order]
    corner_x = [float(point[0]) for point in wheel_points]
    corner_y = [-float(point[1]) for point in wheel_points]
    corner_z = [datum_up_m - float(point[2]) for point in wheel_points]
    sprung_cg = [float(value) for value in masses["cg_suspendida_m"]]
    cg_forward = sprung_cg[0]
    cg_right = -sprung_cg[1]
    cg_height = sprung_cg[2] - datum_up_m
    inertia_source = masses["inercia_suspendida_kg_m2"]
    inertia = [
        float(inertia_source[0][0]),
        float(inertia_source[1][1]),
        float(inertia_source[2][2]),
        -float(inertia_source[0][1]),
        -float(inertia_source[0][2]),
        float(inertia_source[1][2]),
    ]

    front_ratio = float(spring_data["Del"]["relacion_palanca_reposo"])
    rear_ratio = float(spring_data["Tras"]["relacion_palanca_reposo"])
    front_damping = spring_data["Del"]["amortiguador_N_s_m"]
    rear_damping = spring_data["Tras"]["amortiguador_N_s_m"]
    wheel_damping = 0.5 * (
        0.5 * (float(front_damping["compresion"]) + float(front_damping["extension"])) * front_ratio**2
        + 0.5 * (float(rear_damping["compresion"]) + float(rear_damping["extension"])) * rear_ratio**2
    )
    spring_rate = 0.5 * (
        float(spring_data["Del"]["rigidez_en_rueda_N_m"])
        + float(spring_data["Tras"]["rigidez_en_rueda_N_m"])
    )
    unsprung = masses["no_suspendida"]
    unsprung_mean = 0.25 * sum(float(unsprung[name]["masa_no_suspendida_kg"]) for name in wheel_order)
    lower_arm = corners["Del_Izq"]["puntos"]
    arm_inner = abs(float(lower_arm["L0"][1]))
    arm_length = abs(float(lower_arm["W"][1]) - float(lower_arm["L0"][1]))

    collision_bounds = collision_node_bounds(collision_path)
    hull_centers: list[float] = []
    hull_radii: list[float] = []
    probe_radius = 0.02
    for name in COLLISION_PROBE_NAMES:
        if name not in collision_bounds:
            raise ValueError(f"Collision GLB is missing required hull source {name}")
        minimum, maximum = collision_bounds[name]
        # GLB source axes are +X forward, +Y up, +Z right. Probe centers sit
        # just above each selected mesh's lowest vertex by their sphere radius.
        source_x = 0.5 * (minimum[0] + maximum[0])
        source_right = 0.5 * (minimum[2] + maximum[2])
        lowest_source_up = minimum[1]
        center_down_from_datum = datum_up_m - lowest_source_up - probe_radius
        hull_centers.extend([source_x, source_right, center_down_from_datum])
        hull_radii.append(probe_radius)

    if ROOF_PROBE_NAME not in collision_bounds:
        raise ValueError(f"Collision GLB is missing required roof source {ROOF_PROBE_NAME}")
    shell_min, shell_max = collision_bounds[ROOF_PROBE_NAME]
    shell_center_x = 0.5 * (shell_min[0] + shell_max[0])
    shell_center_right = 0.5 * (shell_min[2] + shell_max[2])
    shell_mid_up = 0.5 * (shell_min[1] + shell_max[1])
    # One roof sphere preserves shell contact during a roof-first rollover.
    roof_center_down = datum_up_m - shell_max[1] + probe_radius
    hull_centers.extend([shell_center_x, shell_center_right, roof_center_down])
    hull_radii.append(probe_radius)
    # Two side points place the shell's outer faces into the same contact
    # solver, avoiding a body that can pass through the road while lying over.
    for source_right in [shell_min[2] + probe_radius, shell_max[2] - probe_radius]:
        hull_centers.extend([shell_center_x, source_right, datum_up_m - shell_mid_up])
        hull_radii.append(probe_radius)

    # The source has a wheel steering table with different inside/outside
    # angles. The shared solver uses parallel front steering, so use their
    # mean as its single maximum angle.
    steer_table = source["direccion"]["tabla"]
    max_steer_rad = max(
        0.5 * (abs(float(row["rueda_izq_grados"])) + abs(float(row["rueda_der_grados"])))
        for row in steer_table
    ) * math.pi / 180.0
    transmission = source["transmision"]
    gear_ratio = float(transmission["relacion_diferencial"]) * float(transmission["relacion_1a_marcha"])

    spec_source = f"{RUNTIME_SPEC_PATH} SHA-256 {spec_hash}"
    model_estimate = source_statement(spec_hash, "mass inventory and inertia are estimated from the supplied Blender geometry/material assumptions")
    suspension_source = source_statement(spec_hash, "wheel spring rates and shock damping values are model-derived recommendations")
    collision_source = (
        f"Derived nine hull probe centers from supplied collision GLB `assets/source-deliveries/monster-car-2/monster_truck_colisiones_1.glb` "
        f"SHA-256 {collision_hash}; chassis probes follow the lowest vertex of named source meshes, plus one roof and two lateral shell points; each uses an estimated 20 mm contact sphere."
    )
    geometry_source = {
        "spec_path": RUNTIME_SPEC_PATH,
        "spec_sha256": spec_hash,
        "glb_path": RUNTIME_GLB_PATH,
        "glb_sha256": glb_hash,
        # This is the canonical imported app-local basis after the visual
        # adapter's fixed source-to-app rotation.
        "asset_frame": {"right": "+X", "up": "+Y", "forward": "-Z"},
        "physics_frame": {"forward": "+X", "right": "+Y", "down": "+Z"},
        "rights_status": "User-supplied geometry and scripts are included in the repository with their original source hashes recorded.",
    }
    parameters: dict[str, Any] = {}

    def add(name: str, value: Any, unit: str, kind: str, provenance: str) -> None:
        parameters[name] = quantity(value, unit, kind, provenance)

    sprung_mass_kg = float(masses["masa_suspendida_kg"])
    nominal_gravity_m_per_s2 = 9.80665
    suspension_preload_n = sprung_mass_kg * nominal_gravity_m_per_s2 / 4.0
    add("sprung_mass_kg", sprung_mass_kg, "kg", "estimated", model_estimate)
    add("unsprung_mass_kg", unsprung_mean, "kg", "estimated", source_statement(spec_hash, "average of the four geometry-derived unsprung corner masses; front/rear differences are collapsed to the solver's symmetric per-wheel value"))
    add("sprung_inertia_kg_m2", inertia, "kg m^2", "derived", source_statement(spec_hash, "suspended inertia tensor transformed into FRD using S = diag(1,-1,-1), flattened as [Jxx,Jyy,Jzz,Jxy,Jxz,Jyz] about the estimated sprung CG"))
    tire_mass = 0.228 + 0.1044
    wheel_inertia = 0.65 * tire_mass * tire_radius_m**2
    add("wheel_spin_inertia_kg_m2", wheel_inertia, "kg m^2", "estimated", source_statement(spec_hash, "per-wheel tire and rim inventory mass with a 0.65 annular-mass factor; no wheel spin test was supplied"))
    add("gravity_m_per_s2", nominal_gravity_m_per_s2, "m/s^2", "borrowed", "Standard nominal terrestrial gravitational acceleration.")
    add("corner_x_datum_frd_m", corner_x, "m", "derived", source_statement(spec_hash, "source wheel-center X coordinates ordered FL, FR, RL, RR"))
    add("corner_y_datum_frd_m", corner_y, "m", "derived", source_statement(spec_hash, "source wheel-center Y coordinates converted from left-positive to FRD right-positive and ordered FL, FR, RL, RR"))
    add("corner_z_datum_frd_m", corner_z, "m", "derived", source_statement(spec_hash, "source wheel-center Z coordinates transformed to down-positive from a chassis datum at the 0.087 m rest axle height"))
    add("cg_forward_from_datum_m", cg_forward, "m", "derived", source_statement(spec_hash, "suspended CG X coordinate translated to the chosen rest-axle datum"))
    add("cg_right_from_datum_m", cg_right, "m", "derived", source_statement(spec_hash, "suspended CG Y coordinate sign-converted to FRD right-positive"))
    add("cg_height_above_chassis_datum_m", cg_height, "m", "derived", source_statement(spec_hash, "suspended CG height minus the chosen 0.087 m rest-axle datum"))
    add("arm_inner_offset_m", arm_inner, "m", "derived", source_statement(spec_hash, "absolute lateral coordinate of the front lower-arm inboard pivot L0"))
    add("arm_length_m", arm_length, "m", "derived", source_statement(spec_hash, "lateral distance from the lower-arm pivot L0 to the wheel center W"))
    add("wheel_center_rest_below_chassis_datum_m", corner_z[0], "m", "derived", source_statement(spec_hash, "mean rest wheel-center height converted to the selected chassis datum"))
    add("tire_radius_m", tire_radius_m, "m", "derived", source_statement(spec_hash, "supplied rest tire radius"))
    add("suspension_stiffness_n_per_m", spring_rate, "N/m", "derived", suspension_source + " Averaged front/rear wheel rates." )
    add(
        "suspension_preload_n",
        suspension_preload_n,
        "N",
        "derived",
        source_statement(
            spec_hash,
            "constant per-corner preload set to one quarter of the estimated 4.952 kg sprung mass times standard nominal gravity, supporting the supplied ride datum; it remains constant when laboratory gravity or spring scale changes, so zero gravity lets the suspension extend toward its droop stop",
        ),
    )
    add("suspension_damping_n_s_per_m", wheel_damping, "N s/m", "derived", source_statement(spec_hash, "average front/rear shock compression/rebound damping multiplied by the square of each supplied 0.273 motion ratio; compression and rebound asymmetry is collapsed to one effective wheel coefficient"))
    add("tire_stiffness_n_per_m", 6000.0, "N/m", "estimated", "Simulation estimate; no tire vertical-load, pressure, or deflection test was supplied.")
    add("tire_damping_n_s_per_m", 20.0, "N s/m", "estimated", "Simulation estimate; no tire damping measurement was supplied.")
    add("tire_slip_relaxation_s", 0.04, "s", "estimated", "Simulation estimate; no tire slip-relaxation test was supplied.")
    add("travel_droop_m", abs(float(geometry["recorrido_rueda"]["extension"])), "m", "derived", source_statement(spec_hash, "absolute wheel droop travel"))
    add("travel_bump_m", float(geometry["recorrido_rueda"]["compresion"]), "m", "derived", source_statement(spec_hash, "wheel compression travel"))
    add("bump_stop_stiffness_n_per_m", 34000.0, "N/m", "estimated", source_statement(spec_hash, "simulation linearization informed by the model's 80.8 N maximum elastomer force at 2.36 mm crush; actual progressive bumper curve is not represented"))
    add("bump_stop_damping_n_s_per_m", 80.0, "N s/m", "estimated", "Simulation estimate; no bump-stop damping test was supplied.")
    add("droop_stop_stiffness_n_per_m", 10000.0, "N/m", "estimated", "Simulation estimate; no droop-stop force or stiffness measurement was supplied.")
    add("droop_stop_damping_n_s_per_m", 80.0, "N s/m", "estimated", "Simulation estimate; no droop-stop damping test was supplied.")
    peak_wheel_torque = 0.6 * gear_ratio * float(POWERTRAIN_ESTIMATES["gear_efficiency"][0]) / 4.0
    add("drive_torque_per_wheel_nm", peak_wheel_torque, "N m", "derived", "Derived placeholder from the estimated engine peak torque, source model gear ratio, and estimated gear efficiency; NitroDynamics replaces it each tick with clutch output torque." )
    add("brake_torque_per_wheel_nm", 1.2, "N m", "estimated", "Simulation estimate for four-wheel mechanical braking; the supplied source contains no brake torque or stopping test.")
    add("brake_front_fraction", 0.5, "1", "estimated", "Simulation estimate; no brake split or differential brake measurements were supplied.")
    add("reverse_torque_fraction", 0.0, "1", "derived", "The supplied transmission describes a single first gear and no reverse; NitroDynamics disables reverse drive.")
    add("drive_torque_fade_rad_s", 1.0e12, "rad/s", "derived", "Neutralized in NitroDynamics; the estimated combustion curve and centrifugal clutch, not the shared electric torque fade, define propulsion.")
    add("rolling_resistance_coefficient", 0.035, "1", "estimated", "Simulation estimate; no measured rolling-resistance test was supplied.")
    add("tire_friction_scale", 0.9, "1", "estimated", "Simulation estimate; no tire compound or surface friction test was supplied.")
    add("max_steer_angle_rad", max_steer_rad, "rad", "derived", source_statement(spec_hash, "mean of maximum inside/outside source steering-table angles because the shared solver uses parallel front steering"))
    add("steer_servo_natural_frequency_rad_s", 18.0, "rad/s", "estimated", "Simulation estimate; no steering-servo response measurement was supplied.")
    add("steer_servo_damping_ratio", 0.9, "1", "estimated", "Simulation estimate; no steering-servo response measurement was supplied.")
    add("hull_probe_centers_datum_frd_m", hull_centers, "m", "derived", collision_source)
    add("hull_probe_radii_m", hull_radii, "m", "estimated", collision_source)
    add("hull_contact_stiffness_n_per_m", 15000.0, "N/m", "estimated", "Simulation estimate for the shared point-sphere hull contact solver; no chassis contact test was supplied.")
    add("hull_contact_damping_n_s_per_m", 150.0, "N s/m", "estimated", "Simulation estimate; no chassis contact damping test was supplied.")
    add("hull_contact_friction_scale", 0.6, "1", "estimated", "Simulation estimate; no chassis-contact friction test was supplied.")

    powertrain_parameters: dict[str, Any] = {}
    for name, (value, unit) in POWERTRAIN_ESTIMATES.items():
        if name == "gear_efficiency":
            provenance = "Simulation estimate; source gear ratios are model values and no drivetrain efficiency test was supplied."
            kind = "estimated"
        elif name == "initial_fuel_mass_kg":
            provenance = "Simulation estimate of a 100 g starting fuel load. The source models a 118.1 g fuel-tank component but does not specify usable fuel volume, liquid mass, or whether that component includes its contents."
            kind = "estimated"
        else:
            provenance = "Simulation estimate for a generic 4.6 cm^3 single-cylinder nitro engine and centrifugal clutch; the supplied source contains no engine manufacturer, measured RPM curve, clutch map, or fuel-consumption test."
            kind = "estimated"
        powertrain_parameters[name] = quantity(value, unit, kind, provenance)
    powertrain_parameters["gear_ratio"] = quantity(
        gear_ratio,
        "1",
        "derived",
        source_statement(spec_hash, "product of the supplied 3.3077 differential and 2.6 first-gear ratios; the source labels these as adjustable model values, not product specifications"),
    )
    powertrain_parameters["engine_curve_rpm"] = quantity(
        TORQUE_CURVE_RPM,
        "rpm",
        "estimated",
        "Simulation estimate for a generic 4.6 cm^3 nitro engine; no measured or manufacturer torque curve was supplied. Curve is a compact smooth approximation, not measured dynamometer data.",
    )
    powertrain_parameters["engine_curve_torque_nm"] = quantity(
        TORQUE_CURVE_NM,
        "N m",
        "estimated",
        "Simulation estimate for a generic 4.6 cm^3 nitro engine; no measured or manufacturer torque curve was supplied. Curve is a compact smooth approximation, not measured dynamometer data.",
    )

    return {
        "format": "openrc-ground-vehicle",
        "version": 1,
        "id": "monster-car-2",
        "name": "MONSTER CAR 2",
        "description": "Simulation model for the supplied nitro 4WD monster truck. Chassis geometry, mass inventory, and suspension values come from the supplied authored estimate; engine, clutch, fuel, tire, and brake dynamics remain clearly labeled estimates because no physical measurements or engine datasheet were supplied.",
        "drive_configuration": "nitro_4wd",
        "geometry_source": geometry_source,
        "parameters": parameters,
        "powertrain": {
            "kind": "nitro_single_speed_centrifugal_clutch",
            "parameters": powertrain_parameters,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC, help="source datos_simulacion_1.json")
    parser.add_argument("--glb", type=Path, default=DEFAULT_GLB, help="packaged source vehicle GLB")
    parser.add_argument("--collision-glb", type=Path, default=DEFAULT_COLLISION_GLB, help="source collision GLB used for hull probes")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="generated app vehicle JSON")
    parser.add_argument("--check", action="store_true", help="verify the generated JSON matches the checked-in output")
    args = parser.parse_args()
    for path in [args.spec, args.glb, args.collision_glb]:
        if not path.is_file():
            parser.error(f"source file does not exist: {path}")
    encoded = (json.dumps(build(args.spec, args.glb, args.collision_glb), indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if args.check:
        if not args.output.is_file() or args.output.read_bytes() != encoded:
            print(f"Generated vehicle data differs from {args.output}", file=sys.stderr)
            return 1
        print(f"Vehicle data is reproducible: {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(encoded)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
