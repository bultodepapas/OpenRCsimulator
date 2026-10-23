#!/usr/bin/env python3
"""F4U-05: compile the g1.3 Corsair model for the shared imported-scene builder.

Reads only frozen inputs: the delivery identity (assets/aircraft/f4u-corsair-250/source-manifest.json), the
delivered metadata and GLB, the runtime GLB copy in app/assets, and the GearRetract samples taken from the
delivered game source (gear-samples.json, sample_gear.py). Writes the geometry source that model-bindings.json
declares, assets/aircraft/f4u-corsair-250/model-geometry.json, and the same data as generated GDScript,
app/aircraft/f4u_corsair_geometry.gd.

Rest transforms come from the GLB itself, so they equal what Godot imports. The rig's first sample must equal
the GLB's stowed carriers, its last the delivered down-pose wheel centres; the samples must reproduce Blender's
action between them within 1 mm and 1 degree.

    python research/f4u-corsair/F4U-05/compile_model.py           # writes both outputs
    python research/f4u-corsair/F4U-05/compile_model.py --check   # fails if either is stale

Python standard library only. Presentation data only; the physics model is research/f4u-corsair/F4U-07.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSET_DIR = ROOT / "assets/aircraft/f4u-corsair-250"
MANIFEST = ASSET_DIR / "source-manifest.json"
SAMPLES = ASSET_DIR / "gear-samples.json"
RUNTIME_GLB = ROOT / "app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb"
OUT_JSON = ASSET_DIR / "model-geometry.json"
OUT_GD = ROOT / "app/aircraft/f4u_corsair_geometry.gd"
SCRIPT = "research/f4u-corsair/F4U-05/compile_model.py"
ROOT_NODE = "F4UCorsair"
TOLERANCE = 2e-5  # the shared builder's rest tolerance (imported_model.gd, retractable_model.gd)
# App-command sign per control, as the Timber (same authoring: local +X, trailing edge down positive).
APP_SIGN = {"aileron": -1, "elevator": -1, "rudder": 1, "flap": 1}
WHEELS = {
    "left": {"node": "gear_wheel_left", "spin_node": "gear_spin_left", "compression_node": "gear_compression_left", "contact_id": "contact_main_left"},
    "right": {"node": "gear_wheel_right", "spin_node": "gear_spin_right", "compression_node": "gear_compression_right", "contact_id": "contact_main_right"},
    "tail": {"node": "gear_wheel_tail", "spin_node": "gear_spin_tail", "compression_node": "gear_compression_tail", "steer_node": "gear_steer_tail", "contact_id": "contact_tail"},
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_glb(path):
    raw = path.read_bytes()
    assert raw[:4] == b"glTF" and struct.unpack_from("<II", raw, 4) == (2, len(raw)), path
    return json.loads(raw[20:20 + struct.unpack_from("<I", raw, 12)[0]])


def basis_columns(xyzw):
    """Godot Basis columns (x, y, z) of a glTF quaternion [x, y, z, w]."""
    x, y, z, w = xyzw
    rows = ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))
    return {axis: [rows[r][c] for r in range(3)] for c, axis in enumerate("xyz")}


def quaternion_angle(a_wxyz, b_xyzw):
    """Rotation angle between two unit quaternions, 2 atan2(|a - b|, |a + b|): stable where acos(dot) is not."""
    a = a_wxyz
    b = [b_xyzw[3], b_xyzw[0], b_xyzw[1], b_xyzw[2]]
    if sum(x * y for x, y in zip(a, b)) < 0:
        b = [-x for x in b]
    return 2 * math.atan2(math.dist(a, b), math.hypot(*(x + y for x, y in zip(a, b))))


def compile_model():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    keys = manifest["key_files"]
    for role in ("glb", "metadata", "blend"):
        assert sha256(delivery / keys[role]["path"]) == keys[role]["sha256"], f"delivery {role} differs from source-manifest.json"
    assert sha256(RUNTIME_GLB) == keys["glb"]["sha256"], "app GLB must be the delivered aircraft.glb byte for byte"
    meta = json.loads((delivery / keys["metadata"]["path"]).read_text(encoding="utf-8"))
    gear_src = json.loads(SAMPLES.read_text(encoding="utf-8"))
    assert gear_src["source_blend_sha256"] == keys["blend"]["sha256"], "gear-samples.json was not taken from the frozen game source"
    assert gear_src["frames"] == {"stowed": meta["gear"]["runtime_export_frame"], "down": meta["gear"]["landmark_frame"]}

    gltf = read_glb(RUNTIME_GLB)
    assert not gltf.get("animations") and not gltf.get("cameras")
    names = [n["name"] for n in gltf["nodes"]]
    assert len(names) == len(set(names)), "ambiguous node names"
    nodes = {n["name"]: n for n in gltf["nodes"]}
    parent = {gltf["nodes"][c]["name"]: n["name"] for n in gltf["nodes"] for c in n.get("children", [])}

    def rest(name):
        node = nodes[name]
        assert "matrix" not in node and all(abs(v - 1) < 1e-6 for v in node.get("scale", [1, 1, 1])), name
        return {"node": name, "parent": parent[name], "rest_translation": node.get("translation", [0.0, 0.0, 0.0]),
                "rest_basis": basis_columns(node.get("rotation", [0.0, 0.0, 0.0, 1.0]))}

    # Controls: the author's hinges, ranges and positive senses; app signs as the Timber.
    articulations = {}
    for record in meta["articulations"]:
        name = record["node"]
        kind = name.split("_")[0]
        surface = record["member_meshes"]
        assert len(surface) == 1 and parent[surface[0]] == name and record["parent"] == parent[name] == ROOT_NODE, name
        articulations[name] = dict(rest(name), surface_node=surface[0], range_deg=list(record["checked_range_degrees"]),
                                   app_sign=APP_SIGN[kind], positive=record["positive"].replace("_", " "),
                                   section=nodes[name]["extras"]["openrc_section"])
    assert len(articulations) == 10
    articulations["propeller_spin"] = dict(rest("propeller_spin"), surface_node="propeller_rotor",
                                           positive="clockwise viewed from behind toward the nose", section="propeller")
    thrust = dict(rest("thrust_frame"), spin_node="propeller_spin", axis_local="+X",
                  propeller_diameter={"value": meta["propeller_diameter_m"], "unit": "m", "kind": "measured",
                                      "source": "g1.3 metadata.json: three-blade visual propeller"})
    assert parent["propeller_spin"] == "thrust_frame" and parent["propeller_rotor"] == "propeller_spin"
    x_axis = thrust["rest_basis"]["x"]
    assert abs(x_axis[2] + 1.0) < 1e-6, "thrust_frame local +X must point at the nose (-Z)"

    # Gear: carriers sampled from GearRetract, helpers bound at their GLB rest.
    carriers = {c["node"] for c in meta["gear"]["carriers"]}
    assert set(gear_src["carriers"]) == carriers, "sampled carriers differ from the delivered metadata"
    helpers = set(meta["gear"]["helpers"])
    samples = gear_src["samples"]
    assert len(samples) == meta["gear"]["samples"] == 101
    for index, sample in enumerate(samples):
        assert abs(sample["extension"] - index / (len(samples) - 1)) < 1e-12 and set(sample["nodes"]) == carriers
    # Sample 0 is the stowed pose the GLB was exported at. After checking that Blender's evaluation agrees, write
    # it from the GLB's own numbers: the runtime compares the bound scene with it through float32 acos(dot).
    for name in carriers:
        glb_node, first = nodes[name], samples[0]["nodes"][name]
        translation, rotation = glb_node.get("translation", [0.0, 0.0, 0.0]), glb_node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        assert max(abs(a - b) for a, b in zip(first["translation"], translation)) <= 1e-6, name
        assert quaternion_angle(first["rotation_wxyz"], rotation) <= 1e-6, name
        samples[0]["nodes"][name] = {"translation": list(translation), "rotation_wxyz": [rotation[3], rotation[0], rotation[1], rotation[2]]}
    bindings = {name: rest(name) for name in sorted(carriers | helpers)}
    for name in bindings:
        assert nodes[name]["extras"]["openrc_section"] == "gear", name
    interpolation = gear_src["interpolation"]
    assert interpolation["max_midpoint_vertex_error_m"] <= 0.001 and interpolation["max_midpoint_rotation_error_deg"] <= 1.0

    wheels = {}
    for role, spec in WHEELS.items():
        meta_wheel = meta["wheels"][role]
        centres = gear_src["wheel_centres_model"][role]
        cx, cy, cz = meta_wheel["center"]  # Blender export frame, gear down
        assert max(abs(a - b) for a, b in zip(centres[-1], (cx, cz, -cy))) <= TOLERANCE, f"{role} down centre disagrees with metadata"
        for key in ("spin_node", "compression_node", "steer_node"):
            if key in spec:
                assert spec[key] in helpers, spec[key]
                assert (spec[key] in carriers) == (key == "compression_node" and role != "tail"), f"{spec[key]} sampling"
        radius = meta_wheel["radius_m"]
        wheels[role] = dict(spec, radius_m=radius, center_model=centres,
                            contact_model=[[c[0], round(c[1] - radius, 10), c[2]] for c in centres])

    data = {
        "schema": "openrc-f4u-model v1",
        "catalog_id": manifest["catalog_id"],
        "revision": manifest["visual_revision"],
        "source_alias": f"F4U Corsair {manifest['delivery_revision']} game model (author delivery derived from master {manifest['master']['revision']})",
        "status": "Imported g1.3 presentation with sampled GearRetract; flaps follow the session; physics staged separately (F4U-07); not in the catalog.",
        "generator": SCRIPT,
        "units": "m",
        "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "datum": {"origin": "D0: symmetry plane x wing-root leading-edge station x thrust-axis height (delivery request section 4)",
                  "physics_le_frame": "[x_aft, y_right, z_up] = [z, x, y]"},
        "inputs": {"glb_sha256": keys["glb"]["sha256"], "metadata_sha256": keys["metadata"]["sha256"],
                   "blend_sha256": keys["blend"]["sha256"], "gear_samples_sha256": hashlib.sha256(SAMPLES.read_bytes()).hexdigest()},
        "dimensions": {"span_m": meta["span_m"], "length_m": meta["length_m"], "propeller_diameter_m": meta["propeller_diameter_m"],
                       "scale_factor": meta["scale_factor"]},
        "articulations": articulations,
        "thrust": thrust,
        "gear": {
            "version": 1,
            "bindings": bindings,
            "retraction": {
                "source_action": gear_src["action"],
                "source_action_frames": gear_src["frames"],
                "pose_space": gear_src["pose_space"],
                "sampled_compression": "the main oleo sliders are carriers (22.2 mm travel during the cycle); presentation compression offsets their sampled pose",
                "interpolation": interpolation,
                "samples": samples,
            },
            "wheels": wheels,
        },
    }
    return data


def main():
    data = compile_model()
    text = json.dumps(data, indent=1, ensure_ascii=False, allow_nan=False) + "\n"
    script = ("# Generated by research/f4u-corsair/F4U-05/compile_model.py; do not edit.\n"
              "# Presentation measurements only; physical validation is separate.\nextends RefCounted\n\nconst DATA := "
              + json.dumps(data, ensure_ascii=False, indent="\t", allow_nan=False) + "\n")
    if "--check" in sys.argv:
        stale = [p for p, t in ((OUT_JSON, text), (OUT_GD, script)) if not p.exists() or p.read_text(encoding="utf-8") != t]
        if stale:
            sys.exit("stale: " + ", ".join(p.name for p in stale) + f" (run {SCRIPT})")
        print("model-geometry.json and f4u_corsair_geometry.gd are up to date")
        return
    OUT_JSON.write_text(text, encoding="utf-8", newline="\n")
    OUT_GD.write_text(script, encoding="utf-8", newline="\n")
    print(f"wrote {OUT_JSON.relative_to(ROOT).as_posix()} and {OUT_GD.relative_to(ROOT).as_posix()}: "
          f"{len(data['articulations'])} articulations, {len(data['gear']['bindings'])} gear bindings, {len(data['gear']['retraction']['samples'])} samples")


if __name__ == "__main__":
    main()
