"""Validate the AV-31 Blender delivery and compile its presentation metadata."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ASSET = ROOT / "app/assets/aircraft/avanti-s-a200/avanti_s.glb"
TARGET = ROOT / "app/aircraft/avanti_s_blender_geometry.gd"
SECTIONS = {"core", "wing_left", "wing_right", "horizontal_tail", "vertical_tail", "canopy", "gear", "engine"}
GEAR_TARGETS = {
    "MainGear_L_Act_Cyl", "MainGear_L_Act_Piston", "MainGear_L_Pivot",
    "MainGear_R_Act_Cyl", "MainGear_R_Act_Piston", "MainGear_R_Pivot",
    "NoseGear_Act_Cyl", "NoseGear_Act_Piston", "NoseGear_Door_Act_ArmPivot",
    "NoseGear_Door_Act_Rod", "NoseGear_Door_Pivot", "NoseGear_Pivot",
}
GEAR_HELPERS = {
    "gear_compression_left", "gear_compression_right", "gear_compression_nose",
    "gear_wheel_left", "gear_wheel_right", "gear_wheel_nose",
    "gear_spin_left", "gear_spin_right", "gear_spin_nose", "gear_steer_nose",
}
GEAR_PIVOTS = {"left": "MainGear_L_Pivot", "right": "MainGear_R_Pivot", "nose": "NoseGear_Pivot"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quaternion_basis_wxyz(value):
    w, x, y, z = value
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def validate_gear(data, source, gltf, nodes, parent_by_child):
    gear = data.get("gear")
    assert isinstance(gear, dict) and gear.get("version") == 1
    bindings = gear.get("bindings")
    assert isinstance(bindings, dict) and set(bindings) == GEAR_TARGETS | GEAR_HELPERS
    assert source.get("gear_retraction", {}).get("sample_count") == 83
    retraction = gear.get("retraction")
    assert isinstance(retraction, dict) and retraction.get("source_action") == "GearRetract"
    assert retraction.get("source_action_frames") == {"stowed": 211, "down": 129}
    samples = retraction.get("samples")
    assert isinstance(samples, list) and len(samples) == 83

    for name, binding in bindings.items():
        assert isinstance(binding, dict) and binding.get("node") == name and name in nodes
        parent_index = parent_by_child.get(nodes[name]["_index"])
        assert parent_index is not None and gltf["nodes"][parent_index]["name"] == binding.get("parent"), (name, binding, parent_index)
        assert nodes[name].get("extras", {}).get("openrc_section") == "gear", name
        translation = binding.get("rest_translation")
        basis = binding.get("rest_basis")
        assert isinstance(translation, list) and len(translation) == 3 and all(math.isfinite(v) for v in translation)
        assert isinstance(basis, dict) and set(basis) == {"x", "y", "z"}
        actual_translation = nodes[name].get("translation", [0.0, 0.0, 0.0])
        assert max(abs(a - b) for a, b in zip(translation, actual_translation)) <= 2e-5, name
        actual_rotation = nodes[name].get("rotation", [0.0, 0.0, 0.0, 1.0])
        actual_basis = quaternion_basis_wxyz([actual_rotation[3], *actual_rotation[:3]])
        for axis_index, axis in enumerate("xyz"):
            assert max(abs(actual_basis[row][axis_index] - basis[axis][row]) for row in range(3)) <= 2e-5, (name, axis)

    for index, sample in enumerate(samples):
        assert isinstance(sample, dict) and abs(sample.get("extension", -1) - index / 82) <= 1e-10
        poses = sample.get("nodes")
        assert isinstance(poses, dict) and set(poses) == GEAR_TARGETS
        for name, pose in poses.items():
            translation, rotation = pose.get("translation"), pose.get("rotation_wxyz")
            assert isinstance(translation, list) and len(translation) == 3 and all(math.isfinite(v) for v in translation)
            assert isinstance(rotation, list) and len(rotation) == 4 and all(math.isfinite(v) for v in rotation)
            # Blender's source matrices are float32; exported unit quaternions can
            # retain ~2e-7 norm error after ten-decimal serialization.
            assert abs(sum(value * value for value in rotation) - 1.0) < 1e-6, (index, name)
        assert not set(poses) & GEAR_HELPERS, "wheel helpers must not be driven by GearRetract samples"

    first_poses = samples[0]["nodes"]
    for name, pose in first_poses.items():
        binding = bindings[name]
        assert max(abs(a - b) for a, b in zip(pose["translation"], binding["rest_translation"])) <= 2e-5, name
        basis = quaternion_basis_wxyz(pose["rotation_wxyz"])
        for axis_index, axis in enumerate("xyz"):
            assert max(abs(basis[row][axis_index] - binding["rest_basis"][axis][row]) for row in range(3)) <= 2e-5, (name, axis)

    interpolation = retraction.get("interpolation", {})
    assert interpolation.get("uniform_samples") == len(samples)
    assert interpolation.get("max_midpoint_vertex_error_m", math.inf) <= 0.001
    assert interpolation.get("max_midpoint_quaternion_error_deg", math.inf) <= 1.0
    assert source.get("gear_retraction", {}).get("max_midpoint_vertex_error_m") == interpolation["max_midpoint_vertex_error_m"]
    assert source.get("gear_retraction", {}).get("max_midpoint_quaternion_error_deg") == interpolation["max_midpoint_quaternion_error_deg"]

    wheels = gear.get("wheels")
    assert isinstance(wheels, dict) and set(wheels) == {"left", "right", "nose"}
    expected_ids = {"left": "contact_main_left", "right": "contact_main_right", "nose": "contact_nose"}
    expected_centers = {
        "left": (-0.32, -0.19212, 0.345),
        "right": (0.32, -0.19212, 0.345),
        "nose": (0.0, -0.201, -0.518),
    }
    for role, wheel in wheels.items():
        assert wheel.get("node") == "gear_wheel_" + role
        assert wheel.get("spin_node") == "gear_spin_" + role
        assert wheel.get("compression_node") == "gear_compression_" + role
        assert wheel.get("contact_id") == expected_ids[role]
        if role == "nose":
            assert wheel.get("steer_node") == "gear_steer_nose"
            assert bindings[wheel["steer_node"]]["parent"] == GEAR_PIVOTS[role]
        else:
            assert "steer_node" not in wheel
        assert bindings[wheel["compression_node"]]["parent"] == (wheel.get("steer_node", GEAR_PIVOTS[role]))
        assert bindings[wheel["node"]]["parent"] == wheel["compression_node"]
        assert bindings[wheel["spin_node"]]["parent"] == wheel["node"]
        radius = wheel.get("radius_m")
        assert math.isfinite(radius) and abs(radius - ({"left": 0.04338, "right": 0.04338, "nose": 0.03532}[role])) < 1e-7
        centers, contacts = wheel.get("center_model"), wheel.get("contact_model")
        assert isinstance(centers, list) and isinstance(contacts, list) and len(centers) == len(contacts) == len(samples)
        for center, contact in zip(centers, contacts):
            assert len(center) == len(contact) == 3 and all(math.isfinite(v) for v in center + contact)
            expected_contact = [center[0], center[1] - radius, center[2]]
            assert max(abs(a - b) for a, b in zip(contact, expected_contact)) < 2e-8, role
        assert max(abs(a - b) for a, b in zip(centers[-1], expected_centers[role])) <= 2e-5, (role, centers[-1])

    return gear


def validate():
    data = json.loads((HERE / "blender-geometry.json").read_text(encoding="utf-8"))
    source = json.loads((HERE / "source-manifest.json").read_text(encoding="utf-8"))
    assert data["revision"] == source["revision"]
    assert data["axes"] == {"nose": "-Z", "right": "+X", "up": "+Y"} and data["units"] == "m"
    assert digest(ASSET) == source["asset_sha256"], "GLB changed; re-export source and metadata together"
    assert digest(HERE / "source/avanti_s.blend") == source["source_blend_sha256"], "Master changed; re-export"
    assert digest(HERE / "source/geometry_blender.json") == source["source_geometry_sha256"], "Sidecar changed; re-export"
    assert hashlib.sha256((HERE / "export_blender.py").read_text(encoding="utf-8").encode("utf-8")).hexdigest() == source["exporter_lf_sha256"], "Exporter changed; re-export"
    raw = ASSET.read_bytes()
    assert raw[:4] == b"glTF" and struct.unpack_from("<II", raw, 4) == (2, len(raw))
    gltf = json.loads(raw[20:20 + struct.unpack_from("<I", raw, 12)[0]])
    assert not gltf.get("animations") and not gltf.get("cameras")
    assert all("uri" not in image for image in gltf.get("images", [])), "Textures must be embedded"
    names = [n["name"] for n in gltf["nodes"]]
    assert len(names) == len(set(names)), "Ambiguous node names"
    nodes = {n["name"]: {**n, "_index": index} for index, n in enumerate(gltf["nodes"])}
    parent_by_child = {}
    for parent_index, node in enumerate(gltf["nodes"]):
        for child_index in node.get("children", []):
            assert child_index not in parent_by_child, "Node has multiple parents"
            parent_by_child[child_index] = parent_index
    for node in gltf["nodes"]:
        if "mesh" in node or node["name"].endswith("_hinge"):
            assert node.get("extras", {}).get("openrc_section") in SECTIONS, node["name"]
        assert all(abs(v - 1) < 1e-5 for v in node.get("scale", [1, 1, 1])), node["name"]
    assert len(data["articulations"]) == 7
    for name, record in data["articulations"].items():
        assert name == record["node"] and name in nodes and record["surface_node"] in nodes
        assert record["app_sign"] in [-1, 1]
        assert set(record["rest_basis"]) == {"x", "y", "z"} and all(len(v) == 3 for v in record["rest_basis"].values())
        assert all(math.isfinite(x) for v in record["rest_basis"].values() for x in v)
        assert nodes[record["surface_node"]].get("mesh") is not None
    assert len(data["collision_probes"]) == 13
    assert len({p["id"] for p in data["collision_probes"]}) == 13
    assert all(len(p["model_position"]) == 3 and all(math.isfinite(v) for v in p["model_position"]) for p in data["collision_probes"])
    validate_gear(data, source, gltf, nodes, parent_by_child)
    assert source["game_triangles"] < 150000 and source["mesh_nodes"] == len(gltf["meshes"])
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = validate()
    output = "# Generated by assets/aircraft/avanti-s-a200/compile_blender.py; do not edit.\n"
    output += "# Presentation measurements only; physical validation is separate.\nextends RefCounted\n\nconst DATA := "
    output += json.dumps(data, ensure_ascii=False, indent="\t", allow_nan=False) + "\n"
    if args.check:
        assert TARGET.read_text(encoding="utf-8") == output, "Stale Blender geometry script; run compile_blender.py"
    else:
        TARGET.write_text(output, encoding="utf-8", newline="\n")
    print("AV-31 Blender asset/source/sections/metadata: PASS")


if __name__ == "__main__":
    main()
