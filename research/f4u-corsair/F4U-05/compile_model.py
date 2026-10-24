#!/usr/bin/env python3
"""F4U-05: compile the delivered Corsair model (g1.13 since F4U-15) for the shared imported-scene builder.

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
WING_FOLD = ASSET_DIR / "wing-fold-r59.json"
RUNTIME_GLB = ROOT / "app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb"
DEFAULT_LIVERY = "midnight"  # aircraft.glb, the delivery's default paint (D3)
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


def triangle_count(gltf):
    return sum(gltf["accessors"][p["indices"]]["count"] // 3 for m in gltf["meshes"] for p in m["primitives"])


def node_shape(gltf):
    """Per node: hierarchy, rest transform, section tag and the bounds of its mesh positions."""
    shape = {}
    for node in gltf["nodes"]:
        bounds = None
        if "mesh" in node:
            lows, highs = zip(*((gltf["accessors"][p["attributes"]["POSITION"]]["min"], gltf["accessors"][p["attributes"]["POSITION"]]["max"])
                               for p in gltf["meshes"][node["mesh"]]["primitives"]))
            bounds = [min(v[i] for v in lows) for i in range(3)] + [max(v[i] for v in highs) for i in range(3)]
        shape[node["name"]] = {"children": sorted(gltf["nodes"][c]["name"] for c in node.get("children", [])),
                               "transform": [node.get(k) for k in ("translation", "rotation", "scale", "matrix")],
                               "extras": node.get("extras"), "bounds": bounds}
    return shape


def same_shape(a, b):
    if a.keys() != b.keys():
        return False
    for name, left in a.items():
        right = b[name]
        if left["children"] != right["children"] or left["transform"] != right["transform"] or left["extras"] != right["extras"]:
            return False
        if (left["bounds"] is None) != (right["bounds"] is None) or (left["bounds"] and any(abs(x - y) > 1e-6 for x, y in zip(left["bounds"], right["bounds"]))):
            return False
    return True


def compile_liveries(manifest, meta, gltf):
    """F4U-16: the delivered liveries in the author's order, default first, with the author's names. Each runtime
    copy must be the frozen GLB, and each livery the same airframe as the default: node names, hierarchy, rest
    transforms, crash-section tags, mesh bounds and triangle count. Materials, textures and surface splits may differ."""
    frozen = manifest["livery_glbs"]
    names = {livery["id"]: livery["name"] for livery in meta["liveries"]}
    order = [record["id"] for record in meta["primary_livery_deliveries"]]
    assert order[0] == DEFAULT_LIVERY and sorted(order) == sorted(frozen), "delivered livery list differs from source-manifest.json"
    assert all(frozen[r["id"]]["path"] == r["glb"] for r in meta["primary_livery_deliveries"])
    shape = node_shape(gltf)
    out = []
    for livery in order:
        path = RUNTIME_GLB if livery == DEFAULT_LIVERY else RUNTIME_GLB.with_name(f"f4u_corsair_{livery}.glb")
        assert sha256(path) == frozen[livery]["sha256"], f"{path.name} must be the delivered {frozen[livery]['path']} (install_liveries.py)"
        other = read_glb(path)
        assert same_shape(shape, node_shape(other)), f"livery {livery} is not the same airframe as {DEFAULT_LIVERY}"
        assert triangle_count(other) == triangle_count(gltf), livery
        out.append({"id": livery, "label": names[livery], "path": "res://" + path.relative_to(ROOT / "app").as_posix(),
                    "glb_sha256": frozen[livery]["sha256"]})
    return out


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
                                      "source": f"{manifest['delivery_revision']} metadata.json: three-blade visual propeller"})
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

    # F4U-10: the smoke anchor at the delivered left middle exhaust stack (the F4U-1D's low cowl-flank stacks). The
    # Moki's collector ring exit is not modelled; the visible stack is where a viewer expects the exhaust.
    bx, by, bz = meta["landmarks_blender_m"]["detail_lenses_and_exhaust_exits"]["R43 | Escape unido -1 2"]
    direction = [-0.4, -0.8, 0.45]
    norm = math.sqrt(sum(v * v for v in direction))
    exhausts = [{"position": [bx, bz, -by], "direction": [round(v / norm, 6) for v in direction], "radius_m": 0.008,
                 "kind": "glow_prop", "pump": True,
                 "source": f"{manifest['delivery_revision']} metadata landmark 'R43 | Escape unido -1 2' (left middle stack exit); direction estimated outboard, down and aft"}]

    # F4U-17: R59's wing fold (extract_wing_fold.py) in the model frame. The game model has no fold pivot: each outer
    # panel is its crash section (panel mesh, aileron hinge, outer flap hinge) directly under the root, which the
    # builder folds in place, so node paths and paint targets stay unchanged.
    fold_src = json.loads(WING_FOLD.read_text(encoding="utf-8"))
    assert fold_src["source"]["sha256"] == meta["master_sha256"], "wing-fold-r59.json was not read from the delivery's master"
    d0, scale = meta["D0_r59_m"], meta["scale_factor"]

    def r59_to_model(p):
        return [scale * p[1], scale * (p[2] - d0[2]), scale * (p[0] - d0[0])]

    sections = {n["name"]: n.get("extras", {}).get("openrc_section") for n in gltf["nodes"]}
    lamps = meta["landmarks_blender_m"]["detail_lenses_and_exhaust_exits"]
    folds = {}
    for side, record in sorted(fold_src["sides"].items()):
        members = sorted(n for n, section in sections.items() if section == f"wing_{side}" and parent.get(n) == ROOT_NODE)
        assert members == sorted([f"wing_{side}_fixed", f"aileron_{side}_hinge", f"flap_{side}_3_hinge"]), members
        assert max(record["check_folded_light_error_m"], record["check_folded_basis_error"]) < 1e-5, "R59 fold check failed"
        lx, ly, lz = lamps["Luz de posicion R8 | " + ("izquierda" if side == "left" else "derecha")]
        lamp_gap = math.dist(r59_to_model(record["light"]), [lx, lz, -ly])
        assert lamp_gap < 0.005, f"{side} navigation lamp: R59 mapped {lamp_gap:.4f} m from the delivered landmark"
        ax, ay, az = record["axis"]
        folds[side] = {"members": members, "pivot": [round(v, 9) for v in r59_to_model(record["pivot"])],
                       "axis": [round(v, 9) for v in (ay, az, ax)], "sign": record["sign"],
                       "max_angle_deg": fold_src["max_angle_deg"], "lock_release_fraction": record["lock_release_fraction"],
                       "travel_fraction": record["travel_fraction"], "time_s": 8.0,
                       "time_source": "estimated: one hydraulic fold or spread cycle of an RC Corsair (the CARF kit's optional wing fold); R59's rig carries no timing",
                       "navigation_lamp_check_m": round(lamp_gap, 6),
                       "check_lamp_spread": [round(v, 9) for v in r59_to_model(record["light"])],
                       "check_lamp_folded": [round(v, 9) for v in r59_to_model(record["light_folded"])],
                       "source": f"R59 {fold_src['source']['sha256'][:12]} R51 pivot and CONTROL ALAS angulo_maximo "
                                 f"(assets/aircraft/f4u-corsair-250/wing-fold-r59.json), mapped by D0 and the 1:4.5 scale"}

    data = {
        "schema": "openrc-f4u-model v1",
        "catalog_id": manifest["catalog_id"],
        "revision": manifest["visual_revision"],
        "source_alias": f"F4U Corsair {manifest['delivery_revision']} game model (author delivery derived from master {manifest['master']['revision']})",
        "status": f"Imported {manifest['delivery_revision']} presentation with sampled GearRetract; flaps follow the session; experimental physics (F4U-07).",
        "generator": SCRIPT,
        "units": "m",
        "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "datum": {"origin": "D0: symmetry plane x wing-root leading-edge station x thrust-axis height (delivery request section 4)",
                  "physics_le_frame": "[x_aft, y_right, z_up] = [z, x, y]"},
        "inputs": {"glb_sha256": keys["glb"]["sha256"], "metadata_sha256": keys["metadata"]["sha256"],
                   "blend_sha256": keys["blend"]["sha256"], "gear_samples_sha256": hashlib.sha256(SAMPLES.read_bytes()).hexdigest(),
                   "wing_fold_sha256": hashlib.sha256(WING_FOLD.read_bytes()).hexdigest()},
        "dimensions": {"span_m": meta["span_m"], "length_m": meta["length_m"], "propeller_diameter_m": meta["propeller_diameter_m"],
                       "scale_factor": meta["scale_factor"]},
        "articulations": articulations,
        "thrust": thrust,
        "exhausts": exhausts,
        "folds": folds,
        "liveries": compile_liveries(manifest, meta, gltf),
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
