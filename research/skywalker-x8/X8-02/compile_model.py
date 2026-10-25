#!/usr/bin/env python3
"""X8-02: compile the delivered Skywalker X8 r4 game model for the shared imported-scene builder.

Reads only frozen inputs: the delivery identity (assets/aircraft/skywalker-x8/source-manifest.json), the delivered
metadata and both skin GLBs, and their runtime copies in app/assets (install_assets.py). Writes the geometry source
that model-bindings.json declares, assets/aircraft/skywalker-x8/model-geometry.json, and the same data as generated
GDScript, app/aircraft/skywalker_x8_geometry.gd.

Rest transforms come from the GLB itself, so they equal what Godot imports; each pivot and hinge axis must agree with
the delivered metadata. The elevons' app sign is derived from the geometry: turning a hinge by a positive angle about
its local +X must move the elevon's trailing edge the way the delivery declares (down), and the app convention is
trailing edge up, so the sign is -1. The camera-door pivots are not a supported mechanism role: they are recorded,
left static and unbound.

    python3 research/skywalker-x8/X8-02/compile_model.py           # writes both outputs
    python3 research/skywalker-x8/X8-02/compile_model.py --check   # fails if either is stale

Python standard library only. Presentation data only; the physics model is X8-06.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/f4u-corsair/F4U-04"))
import preflight_glb as glb_geometry  # noqa: E402  (stdlib glTF reader shared with F4U-04/05)

ASSET_DIR = ROOT / "assets/aircraft/skywalker-x8"
MANIFEST = ASSET_DIR / "source-manifest.json"
RUNTIME_DIR = ROOT / "app/assets/aircraft/skywalker-x8"
DEFAULT_SKIN = "abisal"
OUT_JSON = ASSET_DIR / "model-geometry.json"
OUT_GD = ROOT / "app/aircraft/skywalker_x8_geometry.gd"
SCRIPT = "research/skywalker-x8/X8-02/compile_model.py"
ROOT_NODE = "SkywalkerX8"
ELEVONS = {"elevon_left_hinge": "elevon_left", "elevon_right_hinge": "elevon_right"}
DOORS = {"camera_door_left_hinge": "camera_door_left", "camera_door_right_hinge": "camera_door_right"}
# The app's surface convention: positive = trailing edge up (app/physics/control_surfaces.gd).
APP_POSITIVE = "trailing edge up"
TOLERANCE = 1e-6  # GLB float32 values against the delivery's metadata


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime_glb(skin):
    return RUNTIME_DIR / ("skywalker_x8.glb" if skin == DEFAULT_SKIN else f"skywalker_x8_{skin}.glb")


def basis_columns(xyzw):
    """Godot Basis columns (x, y, z) of a glTF quaternion [x, y, z, w]."""
    x, y, z, w = xyzw
    rows = ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))
    return {axis: [rows[r][c] for r in range(3)] for c, axis in enumerate("xyz")}


def node_shape(gltf):
    """Per node: hierarchy, rest transform, section tag and the bounds of its mesh positions (F4U-16's airframe test)."""
    shape = {}
    for node in gltf["nodes"]:
        bounds = None
        if "mesh" in node:
            accessors = [gltf["accessors"][p["attributes"]["POSITION"]] for p in gltf["meshes"][node["mesh"]]["primitives"]]
            bounds = [min(a["min"][i] for a in accessors) for i in range(3)] + [max(a["max"][i] for a in accessors) for i in range(3)]
        shape[node["name"]] = {"children": sorted(gltf["nodes"][c]["name"] for c in node.get("children", [])),
                               "transform": [node.get(k) for k in ("translation", "rotation", "scale", "matrix")],
                               "extras": node.get("extras"), "bounds": bounds}
    return shape


def triangle_count(gltf):
    return sum(gltf["accessors"][p["indices"]]["count"] // 3 for m in gltf["meshes"] for p in m["primitives"])


def rotate_x(vertex, degrees):
    """A vertex turned about its frame's +X by `degrees` (right-handed)."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    x, y, z = vertex
    return (x, c * y - s * z, s * y + c * z)


def transform(matrix, vertex):
    return [sum(matrix[r][c] * vertex[c] for c in range(3)) + matrix[r][3] for r in range(3)]


def trailing_edge_sense(gltf, binary, nodes, hinge):
    """Model-frame height change of the elevon's aftmost vertices when its hinge turns +1 degree about local +X."""
    child = nodes[ELEVONS[hinge]]
    assert "translation" not in child and "rotation" not in child and "matrix" not in child, "elevon mesh must sit at its hinge"
    vertices = sorted({v for primitive in gltf["meshes"][child["mesh"]]["primitives"]
                       for v in glb_geometry.accessor_values(gltf, binary, primitive["attributes"]["POSITION"])})
    rest = glb_geometry.local_matrix(nodes[hinge])
    model = [transform(rest, v) for v in vertices]
    aft = max(p[2] for p in model)
    edge = [v for v, p in zip(vertices, model) if p[2] >= aft - 0.002]  # the trailing-edge strip (2 mm)
    before = sum(transform(rest, v)[1] for v in edge) / len(edge)
    after = sum(transform(rest, rotate_x(v, 1.0))[1] for v in edge) / len(edge)
    return after - before, len(edge)


def compile_skins(manifest, meta, gltf):
    """Both delivered skins in the author's order, default first, with the author's labels. Each runtime copy must be
    the frozen GLB, and each skin the same airframe as the default (node names, hierarchy, rest transforms, section tags,
    mesh bounds, triangle count); materials and textures differ."""
    frozen = manifest["skin_glbs"]
    assert list(frozen) == meta["skin_order"] and meta["skin_order"][0] == meta["default_skin"] == DEFAULT_SKIN
    labels = {skin["id"]: skin["label"] for skin in meta["skins"]}
    shape = node_shape(gltf)
    out = []
    for skin, record in frozen.items():
        path = runtime_glb(skin)
        assert sha256(path) == record["sha256"], f"{path.name} must be the delivered {record['path']} (install_assets.py)"
        other, _ = glb_geometry.read_glb(path)
        assert node_shape(other) == shape, f"skin {skin} is not the same airframe as {DEFAULT_SKIN}"
        assert triangle_count(other) == triangle_count(gltf), skin
        assert labels[skin] == record["label"]
        out.append({"id": skin, "label": labels[skin], "path": "res://" + path.relative_to(ROOT / "app").as_posix(),
                    "glb_sha256": record["sha256"]})
    return out


def compile_model():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    keys = manifest["key_files"]
    for role in ("glb", "metadata", "blend", "license"):
        assert sha256(delivery / keys[role]["path"]) == keys[role]["sha256"], f"delivery {role} differs from source-manifest.json"
    glb_path = runtime_glb(DEFAULT_SKIN)
    assert sha256(glb_path) == keys["glb"]["sha256"], "app GLB must be the delivered aircraft.glb byte for byte"
    meta = json.loads((delivery / keys["metadata"]["path"]).read_text(encoding="utf-8"))

    gltf, binary = glb_geometry.read_glb(glb_path)
    assert not gltf.get("animations") and not gltf.get("cameras") and not gltf.get("extensionsUsed")
    names = [n["name"] for n in gltf["nodes"]]
    assert len(names) == len(set(names)), "ambiguous node names"
    nodes = {n["name"]: n for n in gltf["nodes"]}
    parent = {gltf["nodes"][c]["name"]: n["name"] for n in gltf["nodes"] for c in n.get("children", [])}
    root = nodes[ROOT_NODE]
    assert gltf["scenes"][gltf.get("scene", 0)]["nodes"] == [names.index(ROOT_NODE)] and ROOT_NODE not in parent
    assert not any(k in root for k in ("translation", "rotation", "scale", "matrix")), "root must be the identity at D0"

    def rest(name):
        node = nodes[name]
        assert "matrix" not in node and all(abs(v - 1) < 1e-6 for v in node.get("scale", [1, 1, 1])), name
        return {"node": name, "parent": parent[name], "rest_translation": node.get("translation", [0.0, 0.0, 0.0]),
                "rest_basis": basis_columns(node.get("rotation", [0.0, 0.0, 0.0, 1.0]))}

    def agrees(record, name):
        """The GLB pivot and local +X equal the delivered metadata (Godot frame)."""
        pivot = nodes[name].get("translation", [0.0, 0.0, 0.0])
        axis = basis_columns(nodes[name]["rotation"])["x"]
        assert max(abs(a - b) for a, b in zip(pivot, record["pivot_godot_m"])) < TOLERANCE, f"{name} pivot"
        assert max(abs(a - b) for a, b in zip(axis, record["axis_godot"])) < TOLERANCE, f"{name} hinge axis"
        assert record["parent"] == parent[name] == ROOT_NODE, name

    # Elevons: the author's hinges, combined servo travel and clearance; the app sign follows from the geometry.
    articulations = {}
    sense = {}
    for name, surface in ELEVONS.items():
        record = meta["articulations"][name]
        agrees(record, name)
        assert record["child"] == surface and parent[surface] == name and record["positive_direction"] == "trailing edge down"
        ranges = {r["name"]: r["deg"] for r in record["ranges"]}
        travel = ranges["mechanical_full_servo_travel"]
        assert travel == ranges["combined_full_stick_default_mix"], "combined stick travel is the full servo travel"
        clearance = record["clearance_envelope_deg"]["free"]
        assert clearance[0] < travel[0] < 0.0 < travel[1] < clearance[1], f"{name}: travel outside its clearance"
        rise, count = trailing_edge_sense(gltf, binary, nodes, name)
        assert rise < -1e-4, f"{name}: +1 degree about local +X must lower the trailing edge (rise {rise:.6f} m)"
        sense[name] = {"trailing_edge_rise_m_per_plus_1_deg": round(rise, 9), "trailing_edge_vertices": count}
        articulations[name] = dict(rest(name), surface_node=surface, range_deg=list(travel), app_sign=-1,
                                   positive=record["positive_direction"], section=nodes[name]["extras"]["openrc_section"],
                                   clearance_deg=list(clearance), axis_model=record["axis_godot"],
                                   hinge_line_model=record["hinge_line_godot_m"],
                                   range_source=f"{manifest['delivery_revision']} metadata.json mechanical_full_servo_travel "
                                                f"(= combined_full_stick_default_mix; model-derived linkage, not hardware)")
        assert articulations[name]["section"] == record["section"]
    articulations["propeller_spin"] = dict(rest("propeller_spin"), surface_node="propeller_rotor",
                                           positive=meta["articulations"]["propeller_spin"]["positive_direction"].split(";")[0],
                                           section="propeller")
    assert parent["propeller_spin"] == "thrust_frame" and parent["propeller_rotor"] == "propeller_spin"
    hub = meta["landmarks"]["propeller_hub"]["godot_m"]
    thrust = dict(rest("thrust_frame"), spin_node="propeller_spin", axis_local="+X",
                  propeller_diameter={"value": meta["dimensions"]["propeller_diameter_m"]["value"], "unit": "m", "kind": "measured",
                                      "source": f"{manifest['delivery_revision']} metadata.json: propeller_rotor vertices (12 in nominal)"},
                  layout="pusher: the propeller turns aft of the wing; thrust points at the nose")
    assert parent["thrust_frame"] == ROOT_NODE and max(abs(a - b) for a, b in zip(thrust["rest_translation"], hub)) < TOLERANCE
    x_axis = thrust["rest_basis"]["x"]
    assert abs(x_axis[2] + 1.0) < 1e-6, "thrust_frame local +X must point at the nose (-Z)"

    # Camera doors: delivered hinge pivots that no shared mechanism role drives (README section 8). Recorded only.
    unbound = {}
    for name, door in DOORS.items():
        record = meta["articulations"][name]
        agrees(record, name)
        assert record["child"] == door and parent[door] == name
        unbound[name] = dict(rest(name), surface_node=door, range_deg=record["ranges"][0]["deg"],
                             positive=record["positive_direction"], section=nodes[name]["extras"]["openrc_section"],
                             status="static and unbound: not a supported mechanism role (canopy, tailhook, cowl_flaps)")

    sections = {}
    for section in meta["sections"]:
        for name in section["nodes"]:
            assert nodes[name].get("extras", {}).get("openrc_section") == section["id"], name
            sections[name] = section["id"]
    untagged = sorted(n for n in names if "mesh" in nodes[n] and n not in sections)
    assert not untagged, f"untagged meshes {untagged}"

    landmarks = {name: {"model_m": record["godot_m"], "evidence": record["evidence"]} for name, record in meta["landmarks"].items()}
    le = meta["landmarks"]["wing_root_leading_edge_right"]["godot_m"]
    datum = {
        "origin": "D0: symmetry plane x wing leading edge at the orange root-rib station (s = 236 mm) x thrust-axis height "
                  "(delivery README section 6; metadata datum_D0); not the CG",
        "physics_le_frame": "[x_aft, y_right, z_up] = [z, x, y]; a physics file whose LE datum is D0 gives AirplaneBuilder.datum() = (0, 0)",
        "root_rib_leading_edge_model_m": [[-le[0], le[1], le[2]], le],
        "root_rib_leading_edge_from_d0_le_frame_m": [le[2], le[0], le[1]],
        "root_rib_leading_edge_note": "the physical LE datum (landmarks wing_root_leading_edge_left/right) lies 0.8 mm aft of and 7.0 mm above D0, "
                                      "at y = +-0.2376 m",
    }

    mix = meta["control_mixing"]
    data = {
        "schema": "openrc-skywalker-x8-model v1",
        "catalog_id": manifest["catalog_id"],
        "revision": manifest["visual_revision"],
        "source_alias": f"Skywalker X8 {manifest['delivery_revision']} game model (author delivery derived from master {manifest['master']['revision']})",
        "status": f"Imported {manifest['delivery_revision']} presentation: two elevons, a pusher propeller, no gear; no physics yet (X8-06).",
        "generator": SCRIPT,
        "units": "m",
        "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "datum": datum,
        "inputs": {"glb_sha256": keys["glb"]["sha256"], "metadata_sha256": keys["metadata"]["sha256"],
                   "blend_sha256": keys["blend"]["sha256"], "license_sha256": keys["license"]["sha256"]},
        "dimensions": {"span_m": meta["dimensions"]["span_including_winglets_m"]["value"],
                       "length_m": meta["dimensions"]["length_nose_to_spinner_tip_m"]["value"],
                       "height_m": meta["dimensions"]["height_m"]["value"],
                       "propeller_diameter_m": meta["dimensions"]["propeller_diameter_m"]["value"],
                       "triangles": triangle_count(gltf)},
        "landmarks": landmarks,
        "articulations": articulations,
        "elevon_presentation": {
            "app_convention": f"surface angles in degrees, + = {APP_POSITIVE} (app/physics/control_surfaces.gd)",
            "render": "elevon_right = elevator + aileron_right, elevon_left = elevator + aileron_left (app/aircraft/imported_model.gd role_degrees); "
                      "the exact inverse of elevator = (eR + eL) / 2, aileron_right = (eR - eL) / 2, aileron_left = (eL - eR) / 2",
            "app_sign": "-1: delivery + is trailing edge down; a +1 degree hinge turn lowers each trailing edge (trailing_edge_check)",
            "trailing_edge_check": sense,
            "delivery_mixing": {"convention": mix["convention"], "formula": mix["formula"], "default_rates": mix["default_rates"]},
        },
        "unbound_pivots": unbound,
        "sections": sections,
        "thrust": thrust,
        "liveries": compile_skins(manifest, meta, gltf),
    }
    return data


def main():
    data = compile_model()
    text = json.dumps(data, indent=1, ensure_ascii=False, allow_nan=False) + "\n"
    script = (f"# Generated by {SCRIPT}; do not edit.\n"
              "# Presentation measurements only; physical validation is separate.\nextends RefCounted\n\nconst DATA := "
              + json.dumps(data, ensure_ascii=False, indent="\t", allow_nan=False) + "\n")
    if "--check" in sys.argv:
        stale = [p for p, t in ((OUT_JSON, text), (OUT_GD, script)) if not p.exists() or p.read_text(encoding="utf-8") != t]
        if stale:
            sys.exit("stale: " + ", ".join(p.name for p in stale) + f" (run {SCRIPT})")
        print("model-geometry.json and skywalker_x8_geometry.gd are up to date")
        return
    OUT_JSON.write_text(text, encoding="utf-8", newline="\n")
    OUT_GD.write_text(script, encoding="utf-8", newline="\n")
    print(f"wrote {OUT_JSON.relative_to(ROOT).as_posix()} and {OUT_GD.relative_to(ROOT).as_posix()}: "
          f"{len(data['articulations'])} articulations, {len(data['liveries'])} liveries")


if __name__ == "__main__":
    main()
