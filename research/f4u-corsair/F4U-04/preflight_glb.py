#!/usr/bin/env python3
"""F4U-04: preflight an F4U Corsair g1 GLB against the Blender delivery request.

Reads the GLB directly (no Blender, no Godot) and checks the structural rules in docs/F4U-BLENDER-HANDOFF.md:
ASCII unique node names, identity root, unit node scales, `openrc_section` extras on every mesh and pivot, no
detachable ancestor capturing another section, required control pivots and gear helpers, paint-region materials,
embedded images, no cameras/lights/animation/compression extensions, triangle/surface/material budgets, span,
the stowed gear pose (no gear vertex more than 10 mm below the lowest airframe vertex, propeller excluded) and,
since F4U-18, outward-facing skins (Godot culls back faces, so an inside-out skin shows its far inner wall).

    python research/f4u-corsair/F4U-04/preflight_glb.py PATH/aircraft.glb [--report out.json]
    python research/f4u-corsair/F4U-04/preflight_glb.py PATH/aircraft.glb --profile f4u-g2
    python research/f4u-corsair/F4U-04/preflight_glb.py PATH/other.glb --profile generic [--gear-stowed]

`--profile f4u-g1` (default) applies every rule with the g1 budgets; `f4u-g2` applies them with the budgets of
request revision 4 (F4U-18). `--profile generic` keeps only aircraft-independent rules, so the
counting code can be checked against the accepted Avanti and Timber assets; `--gear-stowed` adds the stowed-gear
rule to it (the Avanti is exported stowed, the Timber has fixed gear). Exit status is 1 when any mandatory
check fails, 2 on unreadable input. Python standard library only. A pass is software preflight, not acceptance.
"""
import argparse
import json
import math
import re
import struct
import sys
from pathlib import Path

SECTIONS = {"core", "wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail", "engine",
            "propeller", "gear", "canopy"}
FORBIDDEN_EXTENSIONS = {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization",
                        "KHR_lights_punctual", "EXT_texture_webp", "KHR_texture_basisu"}
ROOT_NAME = "F4UCorsair"
# Parent -> child pairs requested in section 5 of the delivery request.
PIVOTS = {
    "aileron_left_hinge": "aileron_left", "aileron_right_hinge": "aileron_right",
    "flap_left_1_hinge": "flap_left_1", "flap_left_2_hinge": "flap_left_2", "flap_left_3_hinge": "flap_left_3",
    "flap_right_1_hinge": "flap_right_1", "flap_right_2_hinge": "flap_right_2", "flap_right_3_hinge": "flap_right_3",
    "elevator_hinge": "elevator", "rudder_hinge": "rudder",
    "thrust_frame": "propeller_spin", "propeller_spin": "propeller_rotor",
}
PIVOT_SECTIONS = {
    "aileron_left_hinge": "wing_left", "aileron_right_hinge": "wing_right",
    "flap_left_1_hinge": "wing_center", "flap_left_2_hinge": "wing_center", "flap_left_3_hinge": "wing_left",
    "flap_right_1_hinge": "wing_center", "flap_right_2_hinge": "wing_center", "flap_right_3_hinge": "wing_right",
    "elevator_hinge": "horizontal_tail", "rudder_hinge": "vertical_tail", "propeller_spin": "propeller",
}
FIXED_PARTS = {"fuselage_core": "core", "canopy_glass": "canopy", "wing_center_fixed": "wing_center",
               "wing_left_fixed": "wing_left", "wing_right_fixed": "wing_right",
               "stabilizer_fixed": "horizontal_tail", "fin_fixed": "vertical_tail", "cowl": "engine"}
GEAR_HELPERS = [f"gear_{kind}_{role}" for role in ("left", "right", "tail")
                for kind in ("compression", "spin", "wheel")] + ["gear_steer_tail"]
PAINT_MATERIALS = ["paint_body", "paint_wing", "paint_wing_tip", "paint_tail"]
SPAN_M = 12.5 / 4.5  # request revision 3: 1/4.5 of R59's 12.5 m span
SPAN_TOLERANCE_M = 0.010
# Budgets per tier: section 8 of the request for g1, revision 4 for g2.
BUDGETS = {
    "f4u-g1": {"triangle_ceiling": 150000, "triangle_target": 100000, "surfaces": 60, "materials": 24, "image_px": 2048},
    "f4u-g2": {"triangle_ceiling": 450000, "triangle_target": 350000, "surfaces": 70, "materials": 16, "image_px": 4096},
}
GEAR_STOWED_TOLERANCE_M = 0.010
# Outward-facing skins (F4U-18). The fuselage is measured about the thrust axis (the glTF Z axis through D0) and
# closed shells about their own centroid, as area shares. Accepted values: R59's fuselage 0.88, shells 0.86-1.00;
# the inside-out g1 fuselage measures 0.14. The cowl ring and wing centre (well liners) have no clear outside.
FUSELAGE = "fuselage_core"
CLOSED_SHELLS = ["wing_left_fixed", "wing_right_fixed", "stabilizer_fixed", "fin_fixed", "elevator", "rudder",
                 "aileron_left", "aileron_right"] + [f"flap_{side}_{i}" for side in ("left", "right") for i in (1, 2, 3)]
OUTWARD_MIN = 0.6
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
TYPE_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("not a glTF 2.0 binary of the declared length")
    offset, gltf, binary = 12, None, b""
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = chunk
        offset += 8 + chunk_length
    if gltf is None:
        raise ValueError("GLB has no JSON chunk")
    return gltf, binary


def accessor_values(gltf, binary, index):
    accessor = gltf["accessors"][index]
    fmt, size = COMPONENTS[accessor["componentType"]]
    width = TYPE_WIDTH[accessor["type"]]
    view = gltf["bufferViews"][accessor["bufferView"]]
    if view.get("buffer", 0) != 0 or "uri" in gltf["buffers"][0]:
        raise ValueError("accessor data is not in the GLB binary chunk")
    stride = view.get("byteStride") or size * width
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from("<" + fmt * width, binary, start + i * stride) for i in range(accessor["count"])]


def local_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    sx, sy, sz = node.get("scale", [1.0, 1.0, 1.0])
    rot = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
           [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
           [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    scale = (sx, sy, sz)
    return [[rot[r][0] * scale[0], rot[r][1] * scale[1], rot[r][2] * scale[2], (tx, ty, tz)[r]] for r in range(3)] + \
        [[0.0, 0.0, 0.0, 1.0]]


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def node_scale_ok(node):
    if "matrix" in node:
        m = local_matrix(node)
        columns = [[m[r][c] for r in range(3)] for c in range(3)]
        lengths = [math.sqrt(sum(v * v for v in col)) for col in columns]
        det = (columns[0][0] * (columns[1][1] * columns[2][2] - columns[2][1] * columns[1][2])
               - columns[1][0] * (columns[0][1] * columns[2][2] - columns[2][1] * columns[0][2])
               + columns[2][0] * (columns[0][1] * columns[1][2] - columns[1][1] * columns[0][2]))
        return all(abs(length - 1.0) < 1e-6 for length in lengths) and det > 0
    return all(abs(value - 1.0) < 1e-6 for value in node.get("scale", [1.0, 1.0, 1.0]))


def outward_share(gltf, binary, node, matrix, about_axis):
    """Area share of a mesh's triangles whose winding normal points away from the thrust axis or the centroid."""
    triangles = []
    for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
        points = [[matrix[r][0] * x + matrix[r][1] * y + matrix[r][2] * z + matrix[r][3] for r in range(3)]
                  for x, y, z in accessor_values(gltf, binary, primitive["attributes"]["POSITION"])]
        if "indices" in primitive:
            flat = [row[0] for row in accessor_values(gltf, binary, primitive["indices"])]
        else:
            flat = list(range(len(points)))
        triangles += [(points[flat[i]], points[flat[i + 1]], points[flat[i + 2]]) for i in range(0, len(flat) - 2, 3)]
    records = []
    for a, b, c in triangles:
        u = [b[k] - a[k] for k in range(3)]
        v = [c[k] - a[k] for k in range(3)]
        cross = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        area = 0.5 * math.sqrt(sum(value * value for value in cross))
        records.append((cross, [(a[k] + b[k] + c[k]) / 3 for k in range(3)], area))
    total = sum(area for _, _, area in records)
    if total <= 0:
        return None
    centroid = [sum(centre[k] * area for _, centre, area in records) / total for k in range(3)]
    outward = 0.0
    for cross, centre, area in records:
        away = [centre[0], centre[1], 0.0] if about_axis else [centre[k] - centroid[k] for k in range(3)]
        if sum(cross[k] * away[k] for k in range(3)) > 0:
            outward += area
    return outward / total


def png_size(blob):
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", blob[16:24])
    if blob[:2] == b"\xff\xd8":
        index = 2
        while index < len(blob):
            marker, length = blob[index + 1], struct.unpack(">H", blob[index + 2:index + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack(">HH", blob[index + 5:index + 9])
                return width, height
            index += 2 + length
    return None


def inspect(path, profile, gear_stowed=None):
    gltf, binary = read_glb(path)
    failures, warnings = [], []
    strict = profile in BUDGETS
    nodes = gltf.get("nodes", [])
    names = [node.get("name", "") for node in nodes]
    parent = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            parent[child] = index

    for index, name in enumerate(names):
        if not name or not name.isascii() or not re.fullmatch(r"[A-Za-z0-9_]+", name):
            failures.append(f"node {index} name {name!r} is not ASCII [A-Za-z0-9_]")
        elif re.search(r"_\d{3}$|\.\d{3}$", name) and strict:
            failures.append(f"node {name} ends with an automatic numeric suffix")
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        failures.append(f"duplicate node names: {duplicates}")
    for index, node in enumerate(nodes):
        if not node_scale_ok(node):
            failures.append(f"node {names[index]} has non-unit scale, reflection or shear")

    scene = gltf["scenes"][gltf.get("scene", 0)]
    roots = scene.get("nodes", [])
    if len(roots) != 1:
        failures.append(f"scene has {len(roots)} root nodes, expected one aircraft root")
    root = roots[0] if roots else None
    if root is not None:
        identity = local_matrix(nodes[root])
        if any(abs(identity[r][c] - (1.0 if r == c else 0.0)) > 1e-9 for r in range(4) for c in range(4)):
            failures.append(f"root {names[root]} is not an identity transform")
        if strict and names[root] != ROOT_NAME:
            failures.append(f"root is named {names[root]!r}, expected {ROOT_NAME!r}")

    for key, label in (("cameras", "cameras"), ("animations", "animations")):
        if gltf.get(key):
            failures.append(f"GLB contains {len(gltf[key])} {label}")
    used = set(gltf.get("extensionsUsed", []))
    bad_extensions = sorted(used & FORBIDDEN_EXTENSIONS)
    if bad_extensions:
        failures.append(f"forbidden extensions: {bad_extensions}")

    # Sections: every mesh node and every declared pivot carries a valid tag.
    sections = {}
    for index, node in enumerate(nodes):
        value = (node.get("extras") or {}).get("openrc_section")
        if value is not None:
            sections[index] = value
            if value not in SECTIONS:
                failures.append(f"node {names[index]} has invalid openrc_section {value!r}")
    for index, node in enumerate(nodes):
        if "mesh" in node and index not in sections:
            failures.append(f"mesh node {names[index]} has no openrc_section")
    if root is not None and root in sections:
        failures.append(f"root {names[root]} must stay untagged")

    def descendants(index):
        for child in nodes[index].get("children", []):
            yield child
            yield from descendants(child)

    for index, value in sections.items():
        if value == "core":
            continue
        for child in descendants(index):
            if child in sections and sections[child] not in (value,):
                failures.append(f"{value} node {names[index]} captures {sections[child]} node {names[child]}")

    by_name = {name: index for index, name in enumerate(names)}
    if strict:
        for pivot, child in PIVOTS.items():
            if pivot not in by_name or child not in by_name:
                failures.append(f"missing pivot pair {pivot} -> {child}")
            elif parent.get(by_name[child]) != by_name[pivot]:
                failures.append(f"{child} is not a child of {pivot}")
        for pivot, expected in PIVOT_SECTIONS.items():
            if pivot in by_name and sections.get(by_name[pivot]) != expected:
                failures.append(f"{pivot} section is {sections.get(by_name[pivot])!r}, expected {expected!r}")
        if "thrust_frame" in by_name and by_name["thrust_frame"] in sections:
            failures.append("thrust_frame must stay untagged")
        for part, expected in FIXED_PARTS.items():
            if part not in by_name:
                failures.append(f"missing fixed part {part}")
            elif sections.get(by_name[part]) != expected:
                failures.append(f"{part} section is {sections.get(by_name[part])!r}, expected {expected!r}")
        for helper in GEAR_HELPERS:
            if helper not in by_name:
                failures.append(f"missing gear helper {helper}")
            elif sections.get(by_name[helper]) != "gear":
                failures.append(f"gear helper {helper} is not tagged gear")
        material_names = {material.get("name", "") for material in gltf.get("materials", [])}
        for material in PAINT_MATERIALS:
            if material not in material_names:
                failures.append(f"missing paint-region material {material}")

    # Counts: triangles from indices or vertex count; surfaces are mesh-node x primitive.
    mesh_stats, triangles, surfaces = [], 0, 0
    for index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        count = 0
        primitives = gltf["meshes"][node["mesh"]]["primitives"]
        for primitive in primitives:
            if primitive.get("mode", 4) != 4:
                failures.append(f"mesh node {names[index]} has a non-triangle primitive")
                continue
            source = primitive.get("indices", primitive["attributes"]["POSITION"])
            count += gltf["accessors"][source]["count"] // 3
        mesh_stats.append({"node": names[index], "triangles": count, "surfaces": len(primitives),
                           "section": sections.get(index)})
        triangles += count
        surfaces += len(primitives)

    # World-space vertex bounds in glTF axes: +X right, +Y up, -Z nose.
    world = {}

    def visit(index, matrix):
        world[index] = multiply(matrix, local_matrix(nodes[index]))
        for child in nodes[index].get("children", []):
            visit(child, world[index])

    identity4 = [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]
    for start in roots:
        visit(start, identity4)
    low, high = [math.inf] * 3, [-math.inf] * 3
    lowest = {}
    for index, node in enumerate(nodes):
        if "mesh" not in node or index not in world:
            continue
        m = world[index]
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            for x, y, z in accessor_values(gltf, binary, primitive["attributes"]["POSITION"]):
                point = [m[r][0] * x + m[r][1] * y + m[r][2] * z + m[r][3] for r in range(3)]
                low = [min(a, b) for a, b in zip(low, point)]
                high = [max(a, b) for a, b in zip(high, point)]
                key = sections.get(index, "untagged")
                lowest[key] = min(lowest.get(key, math.inf), point[1])
    span = high[0] - low[0]
    length = high[2] - low[2]
    # Stowed gear: retracted carriers sit inside the wing and fuselage, so no gear vertex hangs below the airframe.
    airframe_low = min((v for key, v in lowest.items() if key not in ("gear", "propeller")), default=math.inf)
    if (strict if gear_stowed is None else gear_stowed) and "gear" in lowest:
        drop = airframe_low - lowest["gear"]
        if drop > GEAR_STOWED_TOLERANCE_M:
            failures.append(f"gear reaches {drop:.3f} m below the lowest airframe vertex: export the GLB with the gear "
                            "stowed (GearRetract frame 100)")

    images = []
    for image in gltf.get("images", []):
        if "uri" in image:
            failures.append(f"image {image.get('name', '?')} is external ({image['uri'][:40]})")
            continue
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        size = png_size(binary[start:start + view["byteLength"]])
        images.append({"name": image.get("name", ""), "mime": image.get("mimeType", ""), "size": size})
        image_px = BUDGETS.get(profile, BUDGETS["f4u-g1"])["image_px"]
        if size and max(size) > image_px:
            warnings.append(f"image {image.get('name', '?')} is {size[0]}x{size[1]}, above {image_px}")

    orientation = {}
    if strict:
        for name in [FUSELAGE] + CLOSED_SHELLS:
            if name in by_name and "mesh" in nodes[by_name[name]] and by_name[name] in world:
                share = outward_share(gltf, binary, nodes[by_name[name]], world[by_name[name]], name == FUSELAGE)
                if share is None:
                    continue
                orientation[name] = round(share, 3)
                if share < OUTWARD_MIN:
                    failures.append(f"{name} is inside out: only {share:.0%} of its area faces outward "
                                    f"(minimum {OUTWARD_MIN:.0%}); reverse its faces")

    materials = len(gltf.get("materials", []))
    if strict:
        budget = BUDGETS[profile]
        if triangles > budget["triangle_ceiling"]:
            failures.append(f"{triangles} triangles exceed the {budget['triangle_ceiling']} ceiling")
        elif triangles > budget["triangle_target"]:
            warnings.append(f"{triangles} triangles exceed the {budget['triangle_target']} target")
        if surfaces > budget["surfaces"]:
            warnings.append(f"{surfaces} surfaces exceed the {budget['surfaces']} target; the delivery must state why")
        if materials > budget["materials"]:
            warnings.append(f"{materials} materials exceed the {budget['materials']} target")
        if abs(span - SPAN_M) > SPAN_TOLERANCE_M:
            failures.append(f"span {span:.4f} m differs from {SPAN_M} m by more than {SPAN_TOLERANCE_M} m")

    return {
        "path": str(path), "profile": profile, "ok": not failures,
        "failures": failures, "warnings": warnings,
        "counts": {"nodes": len(nodes), "mesh_nodes": len(mesh_stats), "triangles": triangles,
                   "surfaces": surfaces, "materials": materials, "images": len(images)},
        "bounds_m": {"low": [round(v, 6) for v in low], "high": [round(v, 6) for v in high],
                     "span_x": round(span, 6), "length_z": round(length, 6),
                     "lowest_up_by_section": {key: round(v, 6) for key, v in sorted(lowest.items())}},
        "sections": sorted({value for value in sections.values()}),
        "extensions_used": sorted(used),
        "outward_share": orientation,
        "meshes": mesh_stats, "images": images,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("glb")
    parser.add_argument("--profile", choices=("f4u-g1", "f4u-g2", "generic"), default="f4u-g1")
    parser.add_argument("--gear-stowed", action="store_true", help="apply the stowed-gear rule in the generic profile")
    parser.add_argument("--report", help="write the full JSON report here")
    args = parser.parse_args()
    try:
        report = inspect(args.glb, args.profile, True if args.gear_stowed else None)
    except (OSError, ValueError, KeyError, struct.error) as error:
        print(f"preflight: cannot read {args.glb}: {error}", file=sys.stderr)
        return 2
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    counts, bounds = report["counts"], report["bounds_m"]
    print(f"{report['path']} [{report['profile']}]: {counts['triangles']} triangles, {counts['mesh_nodes']} mesh nodes, "
          f"{counts['surfaces']} surfaces, {counts['materials']} materials, {counts['images']} images; "
          f"span {bounds['span_x']:.4f} m, length {bounds['length_z']:.4f} m; sections {report['sections']}")
    for warning in report["warnings"]:
        print("WARN", warning)
    for failure in report["failures"]:
        print("FAIL", failure)
    print("PASS" if report["ok"] else f"FAILED ({len(report['failures'])} checks)")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
