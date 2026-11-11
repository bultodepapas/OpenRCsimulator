"""DR-29: deterministic OpenRacer CAD -> GLB adapter for the openrc-fpv5 visual.

Run with Blender 5.2.2 (headless):

    blender --background --factory-startup --python build_fpv5_glb.py -- \
        <OpenRacer checkout root> <output.glb> [--measure <measure.json>]

Inputs (OpenRacer @ 15477b200a569dad9d4107e77fdb7cac5acfffd9, GPL-3.0):
    cad/Carbon/2.5mm_BottomPlate.dxf        bottom plate, 2.5 mm (README thickness)
    cad/Carbon/2.5mm_MidPlate.dxf           top plate under the canopy, 2.5 mm
    cad/Carbon/Arms/5mm_Arm_Fatty4Holes.dxf one arm, 5 mm; cut four times
    cad/AnalogSmoothClassic/Canopy.stl      printed canopy (Y-up, nose -Z, mm)

The DXF parts are 2D outlines in millimetres ($INSUNITS = 4); they are extruded by the plate thicknesses
documented in the OpenRacer README. Nothing that is not in the download is modelled: motors, propellers,
electronics, camera, battery, standoffs, screws and the optional braces are absent. Empties mark where the
application attaches its own rotor presentation.

Frames. DXF: X right, Y front (the canopy nose overhang and the arm/plate holes fix this), Z up.
Blender: identical (X right, Y front, Z up). The glTF exporter's +Y-up conversion maps Blender (x, y, z) to
glTF (x, z, -y), so the GLB is +Y up with the nose along -Z and right = +X, matching app/render/frames.gd
(render x = east/right, y = up, z = -north/-forward). The canopy STL is Y-up with its nose on -Z, so
STL (x, y, z) -> Blender (x, -z, y).

Origin: geometric centre of the four motor-mount centres, in the motor-mount plane (top face of the arms).
Stack (Blender Z, mm): bottom plate -7.5..-5, arms -5..0, top plate 0..2.5, canopy legs at +2.5.
"""
import hashlib
import json
import math
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

MM = 0.001
BOTTOM_PLATE = "cad/Carbon/2.5mm_BottomPlate.dxf"
TOP_PLATE = "cad/Carbon/2.5mm_MidPlate.dxf"
ARM = "cad/Carbon/Arms/5mm_Arm_Fatty4Holes.dxf"
CANOPY = "cad/AnalogSmoothClassic/Canopy.stl"
LICENSE = "LICENSE"
README = "README.md"
PLATE_T = 2.5  # mm, OpenRacer README "Top and Bottom plates: 2.5mm"
ARM_T = 5.0  # mm, OpenRacer README "Arms: 5mm"
CANOPY_TARGET_TRIS = 30000
SAGITTA_MM = 0.03
SHARP_ANGLE_DEG = 30.0
PROP_DIAMETERS_MM = {"5.0in": 127.0, "5.1in": 129.54}
# Rotor order: 1 rear-right, 2 front-right, 3 rear-left, 4 front-left. The DXF arm lies in the rear-right
# quadrant; the other arms are the same part rotated about Z (counter-clockwise, degrees).
ARM_ROTATIONS = {1: 0, 2: 90, 3: 270, 4: 180}


# ---------------------------------------------------------------- DXF (LINE, ARC, CIRCLE, LWPOLYLINE)
def _dxf_entities(path):
    with open(path, "r", encoding="latin-1") as fh:
        lines = [line.strip() for line in fh.read().splitlines()]
    pairs = [(lines[i], lines[i + 1]) for i in range(0, len(lines) - 1, 2)]
    units = None
    for i, (code, value) in enumerate(pairs):
        if code == "9" and value == "$INSUNITS":
            units = int(pairs[i + 1][1])
    out, cur, inside = [], None, False
    for i, (code, value) in enumerate(pairs):
        if code == "2" and value == "ENTITIES" and pairs[i - 1] == ("0", "SECTION"):
            inside = True
            continue
        if not inside:
            continue
        if code == "0":
            if cur is not None:
                out.append(cur)
            if value == "ENDSEC":
                break
            cur = {"type": value, "codes": []}
        elif cur is not None:
            cur["codes"].append((code, value))
    return units, out


def _first(ent, code, default=0.0):
    for c, v in ent["codes"]:
        if c == code:
            return float(v)
    return default


def _arc_points(cx, cy, r, a0, a1, ocs_sign):
    """Points from a0 to a1 (radians, counter-clockwise in OCS); OCS extrusion -Z mirrors X (arbitrary axis)."""
    sweep = a1 - a0
    n = max(2, int(math.ceil(abs(sweep) / (2.0 * math.acos(max(-1.0, 1.0 - SAGITTA_MM / r))))))
    pts = []
    for k in range(n + 1):
        a = a0 + sweep * k / n
        pts.append((ocs_sign * (cx + r * math.cos(a)), cy + r * math.sin(a)))
    return pts


def _bulge_points(p0, p1, bulge):
    if abs(bulge) < 1e-12:
        return [p0, p1]
    theta = 4.0 * math.atan(bulge)
    chord = math.dist(p0, p1)
    r = chord / (2.0 * math.sin(abs(theta) / 2.0))
    mx, my = (p0[0] + p1[0]) / 2.0, (p0[1] + p1[1]) / 2.0
    dx, dy = (p1[0] - p0[0]) / chord, (p1[1] - p0[1]) / chord
    h = r * math.cos(abs(theta) / 2.0)
    side = 1.0 if bulge > 0 else -1.0
    cx, cy = mx - side * dy * h, my + side * dx * h
    a0 = math.atan2(p0[1] - cy, p0[0] - cx)
    sweep = theta
    n = max(2, int(math.ceil(abs(sweep) / (2.0 * math.acos(max(-1.0, 1.0 - SAGITTA_MM / r))))))
    return [(cx + r * math.cos(a0 + sweep * k / n), cy + r * math.sin(a0 + sweep * k / n)) for k in range(n + 1)]


def dxf_loops(path):
    """Return (closed loops as point lists in mm, circles [(cx, cy, r)], diagnostics)."""
    units, ents = _dxf_entities(path)
    if units != 4:
        raise SystemExit("%s: $INSUNITS=%s, expected 4 (millimetres)" % (path, units))
    open_paths, circles, closed = [], [], []
    for e in ents:
        t = e["type"]
        sign = _first(e, "230", 1.0)
        if t == "LINE":
            open_paths.append([(_first(e, "10"), _first(e, "20")), (_first(e, "11"), _first(e, "21"))])
        elif t == "ARC":
            a0, a1 = math.radians(_first(e, "50")), math.radians(_first(e, "51"))
            while a1 <= a0:
                a1 += 2.0 * math.pi
            open_paths.append(_arc_points(_first(e, "10"), _first(e, "20"), _first(e, "40"), a0, a1, sign))
        elif t == "CIRCLE":
            circles.append((sign * _first(e, "10"), _first(e, "20"), _first(e, "40")))
        elif t == "LWPOLYLINE":
            verts, flags = [], 0
            for c, v in e["codes"]:
                if c == "70":
                    flags = int(v)
                elif c == "10":
                    verts.append([float(v), 0.0, 0.0])
                elif c == "20":
                    verts[-1][1] = float(v)
                elif c == "42":
                    verts[-1][2] = float(v)
            pts = []
            count = len(verts) if flags & 1 else len(verts) - 1
            for i in range(count):
                a, b = verts[i], verts[(i + 1) % len(verts)]
                seg = _bulge_points((sign * a[0], a[1]), (sign * b[0], b[1]), a[2] * sign)
                pts.extend(seg if not pts else seg[1:])
            if flags & 1:
                closed.append(pts[:-1])
            else:
                open_paths.append(pts)
        else:
            raise SystemExit("%s: unsupported entity %s" % (path, t))
    # Chain open paths by matching endpoints.
    tol = 1e-3
    remaining = list(open_paths)
    while remaining:
        loop = list(remaining.pop(0))
        progress = True
        while progress and math.dist(loop[0], loop[-1]) > tol:
            progress = False
            for i, seg in enumerate(remaining):
                if math.dist(loop[-1], seg[0]) <= tol:
                    loop.extend(seg[1:])
                elif math.dist(loop[-1], seg[-1]) <= tol:
                    loop.extend(list(reversed(seg))[1:])
                else:
                    continue
                remaining.pop(i)
                progress = True
                break
        if math.dist(loop[0], loop[-1]) > tol:
            raise SystemExit("%s: open outline (gap %.4f mm at %s)" % (path, math.dist(loop[0], loop[-1]), loop[-1]))
        closed.append(loop[:-1])
    # Concentric circles (countersinks) keep the smallest, through-hole radius.
    kept = {}
    for cx, cy, r in circles:
        key = (round(cx, 3), round(cy, 3))
        kept[key] = min(r, kept.get(key, r))
    dropped = len(circles) - len(kept)
    circles = [(k[0], k[1], kept[k]) for k in sorted(kept)]
    for cx, cy, r in circles:
        n = max(12, int(math.ceil(2.0 * math.pi / (2.0 * math.acos(1.0 - SAGITTA_MM / r)))))
        closed.append([(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)])
    depth = [sum(1 for j, other in enumerate(closed) if j != i and _inside(loop[0], other)) for i, loop in enumerate(closed)]
    if max(depth) > 1 or depth.count(0) != 1:
        raise SystemExit("%s: unexpected loop nesting %s" % (path, depth))
    diag = {"entities": len(ents), "loops": len(closed), "holes": depth.count(1), "countersink_circles_dropped": dropped}
    return closed, circles, diag


def _inside(p, poly):
    x, y = p
    hit = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def _rotate(loops, degrees):
    c, s = round(math.cos(math.radians(degrees))), round(math.sin(math.radians(degrees)))
    return [[(c * x - s * y, s * x + c * y) for x, y in loop] for loop in loops]


def extrude_loops(name, loops, z0, thickness):
    """2D outline + holes (even-odd) -> closed solid mesh spanning z0..z0+thickness (mm in, metres out)."""
    cu = bpy.data.curves.new(name + "_curve", "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = thickness * MM / 2.0
    for loop in loops:
        sp = cu.splines.new("POLY")
        sp.points.add(len(loop) - 1)
        for i, (x, y) in enumerate(loop):
            sp.points[i].co = (x * MM, y * MM, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    me.transform(Matrix.Translation((0.0, 0.0, (z0 + thickness / 2.0) * MM)))
    me.name = name
    return me


# ---------------------------------------------------------------- STL
def read_stl(path):
    with open(path, "rb") as fh:
        data = fh.read()
    n = struct.unpack_from("<I", data, 80)[0]
    if 84 + 50 * n != len(data):
        raise SystemExit("%s: not a binary STL" % path)
    tris = [struct.unpack_from("<9f", data, 84 + 50 * i + 12) for i in range(n)]
    return tris


def stl_mesh(name, tris, z_offset_mm):
    """STL (Y-up, nose -Z, mm) -> Blender (Z-up, nose +Y, metres); welded, consistent normals."""
    bm = bmesh.new()
    index = {}
    for t in tris:
        face = []
        for k in range(3):
            x, y, z = t[3 * k], t[3 * k + 1], t[3 * k + 2]
            key = (x, y, z)
            v = index.get(key)
            if v is None:
                v = bm.verts.new((x * MM, -z * MM, (y + z_offset_mm) * MM))
                index[key] = v
            face.append(v)
        if len({id(v) for v in face}) == 3:
            try:
                bm.faces.new(face)
            except ValueError:
                pass  # duplicate face
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def finish_mesh(me):
    """Triangulate and mark sharp edges above SHARP_ANGLE_DEG; faces smooth so the exporter splits only there."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    limit = math.radians(SHARP_ANGLE_DEG)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) != 2 or e.calc_face_angle(0.0) > limit)
    bm.to_mesh(me)
    bm.free()
    return len(me.polygons)


def material(name, rgb, metallic, roughness):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:  # Blender 5.x creates the node tree; older builds need use_nodes
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return mat


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _arm_width(outer, angle_deg, stations):
    """Width of the arm outline perpendicular to its axis at distances (mm) from the frame centre."""
    u = (math.cos(math.radians(angle_deg)), math.sin(math.radians(angle_deg)))
    nrm = (-u[1], u[0])
    out = {}
    for s in stations:
        o = (u[0] * s, u[1] * s)
        ts = []
        for i in range(len(outer)):
            a, b = outer[i], outer[(i + 1) % len(outer)]
            da = (a[0] - o[0]) * u[0] + (a[1] - o[1]) * u[1]
            db = (b[0] - o[0]) * u[0] + (b[1] - o[1]) * u[1]
            if (da > 0) != (db > 0):
                f = da / (da - db)
                p = (a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]))
                ts.append((p[0] - o[0]) * nrm[0] + (p[1] - o[1]) * nrm[1])
        out[str(s)] = round(max(ts) - min(ts), 3) if len(ts) >= 2 else None
    return out


def camera_opening(canopy_me):
    """Locate the camera side-screw axis of the canopy's front camera bay.

    Rays are cast across the canopy along -X (Blender) on a 0.25 mm grid over the front half (Y > 0). A ray
    that hits nothing although the canopy surrounds it on all four sides within 3 mm passes through a pair of
    coaxial side holes: the M2 side-mount holes the camera pivots on. Returns ((x=0, y, z) mm of that axis
    centre, hole area mm2, cluster count). The lens sits forward of this pivot by a camera-dependent offset."""
    bvh = BVHTree.FromPolygons([v.co for v in canopy_me.vertices], [p.vertices[:] for p in canopy_me.polygons])
    step = 0.25
    ys = [i * step for i in range(0, 4 * 42)]
    zs = [3.0 + i * step for i in range(0, 4 * 36)]
    hit = {}
    for y in ys:
        for z in zs:
            hit[(y, z)] = bvh.ray_cast(Vector((0.05, y * MM, z * MM)), Vector((-1.0, 0.0, 0.0)), 1.0)[0] is not None
    window = int(3.0 / step)
    misses = []
    for i, y in enumerate(ys):
        for j, z in enumerate(zs):
            if hit[(y, z)]:
                continue
            row = [hit.get((ys[k], z)) for k in range(max(0, i - window), min(len(ys), i + window + 1))]
            col = [hit.get((y, zs[k])) for k in range(max(0, j - window), min(len(zs), j + window + 1))]
            if any(row[:window]) and any(row[-window:]) and any(col[:window]) and any(col[-window:]):
                misses.append((y, z))
    clusters = []
    for p in misses:
        for c in clusters:
            if any(abs(p[0] - q[0]) <= 2 * step and abs(p[1] - q[1]) <= 2 * step for q in c):
                c.append(p)
                break
        else:
            clusters.append([p])
    if not clusters:
        return None
    best = max(clusters, key=lambda c: (len(c), sum(q[0] for q in c)))
    cy = sum(q[0] for q in best) / len(best)
    cz = sum(q[1] for q in best) / len(best)
    return (0.0, round(cy, 2), round(cz, 2)), len(best) * step * step, len(clusters)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        raise SystemExit("usage: blender --background --factory-startup --python build_fpv5_glb.py -- <src> <out.glb> [--measure m.json]")
    src, out = argv[0].replace("\\", "/").rstrip("/"), argv[1]
    measure_path = argv[argv.index("--measure") + 1] if "--measure" in argv else None

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    # Carbon parts.
    bottom, _, d_bottom = dxf_loops(src + "/" + BOTTOM_PLATE)
    top, _, d_top = dxf_loops(src + "/" + TOP_PLATE)
    arm, arm_circles, d_arm = dxf_loops(src + "/" + ARM)
    hub_hole = max(arm_circles, key=lambda c: c[2])
    pattern = [c for c in arm_circles if abs(math.dist(c[:2], hub_hole[:2]) - 8.0) < 0.05]
    meshes = [extrude_loops("bottom_plate", bottom, -ARM_T - PLATE_T, PLATE_T), extrude_loops("top_plate", top, 0.0, PLATE_T)]
    hubs = {}
    for rotor, deg in sorted(ARM_ROTATIONS.items()):
        meshes.append(extrude_loops("arm_%d" % rotor, _rotate(arm, deg), -ARM_T, ARM_T))
        (hx, hy), = _rotate([[hub_hole[:2]]], deg)[0]
        hubs[rotor] = (hx, hy)
    centre = (sum(h[0] for h in hubs.values()) / 4.0, sum(h[1] for h in hubs.values()) / 4.0)
    if math.hypot(*centre) > 1e-6:
        raise SystemExit("hub centroid is not at the plate centre: %s" % (centre,))

    bm = bmesh.new()
    for me in meshes:
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    carbon_me = bpy.data.meshes.new("frame_carbon")
    bm.to_mesh(carbon_me)
    bm.free()
    carbon_tris = finish_mesh(carbon_me)

    # Canopy.
    tris = read_stl(src + "/" + CANOPY)
    canopy_src = stl_mesh("canopy_source", tris, PLATE_T)
    canopy_src_tris = len(canopy_src.polygons)
    cam = camera_opening(canopy_src)
    cverts = [v.co / MM for v in canopy_src.vertices]
    canopy_bbox = [[round(min(v[a] for v in cverts), 3) for a in range(3)], [round(max(v[a] for v in cverts), 3) for a in range(3)]]
    clearance = {}
    for rotor, (hx, hy) in hubs.items():
        best = min(cverts, key=lambda v: math.hypot(v.x - hx, v.y - hy))
        dist = math.hypot(best.x - hx, best.y - hy)
        clearance[str(rotor)] = {
            "plan_distance_to_nearest_canopy_point_mm": round(dist, 3),
            "nearest_canopy_point_height_above_mount_plane_mm": round(best.z, 3),
            "radial_margin_mm": {k: round(dist - d / 2.0, 3) for k, d in PROP_DIAMETERS_MM.items()},
        }

    ob_tmp = bpy.data.objects.new("canopy_tmp", canopy_src)
    scene.collection.objects.link(ob_tmp)
    mod = ob_tmp.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = CANOPY_TARGET_TRIS / float(canopy_src_tris)
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    canopy_me = bpy.data.meshes.new_from_object(ob_tmp.evaluated_get(dg))
    canopy_me.name = "canopy"
    bpy.data.objects.remove(ob_tmp)
    bpy.data.meshes.remove(canopy_src)
    canopy_tris = finish_mesh(canopy_me)

    # Scene: materials, root, meshes, empties.
    carbon_me.materials.append(material("carbon_fibre", (0.025, 0.025, 0.028), 0.0, 0.35))
    canopy_me.materials.append(material("printed_tpu", (0.80, 0.12, 0.06), 0.0, 0.65))
    root = bpy.data.objects.new("airframe_root", None)
    scene.collection.objects.link(root)

    def child(name, data, loc_mm=(0.0, 0.0, 0.0)):
        ob = bpy.data.objects.new(name, data)
        scene.collection.objects.link(ob)
        ob.parent = root
        ob.location = (loc_mm[0] * MM, loc_mm[1] * MM, loc_mm[2] * MM)
        if data is None:
            ob.empty_display_type = "PLAIN_AXES"
            ob.empty_display_size = 0.01
        return ob

    child("frame_carbon", carbon_me)
    child("canopy", canopy_me)
    for rotor in sorted(hubs):
        child("motor_%d" % rotor, None, (hubs[rotor][0], hubs[rotor][1], 0.0))
    for rotor in sorted(hubs):
        child("propeller_%d" % rotor, None, (hubs[rotor][0], hubs[rotor][1], 0.0))
    if cam is not None:
        child("camera_mount", None, cam[0])
    else:
        raise SystemExit("camera opening not found")

    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_extras=False,
    )

    if measure_path:
        hub_list = [hubs[r] for r in (1, 2, 3, 4)]
        diag_a = math.dist(hubs[1], hubs[4])  # rear-right to front-left
        diag_b = math.dist(hubs[2], hubs[3])  # front-right to rear-left
        right_pair = math.dist(hubs[1], hubs[2])
        left_pair = math.dist(hubs[3], hubs[4])
        front_pair = math.dist(hubs[2], hubs[4])
        rear_pair = math.dist(hubs[1], hubs[3])
        adjacent = [right_pair, left_pair, front_pair, rear_pair]
        allv = [v.co / MM for v in carbon_me.vertices] + [v.co / MM for v in canopy_me.vertices]
        bbox = [[round(min(v[a] for v in allv), 3) for a in range(3)], [round(max(v[a] for v in allv), 3) for a in range(3)]]
        arm_outer = max(arm, key=lambda l: len(l) and abs(sum(l[i][0] * l[(i + 1) % len(l)][1] - l[(i + 1) % len(l)][0] * l[i][1] for i in range(len(l)))))

        def godot(p):  # Blender mm -> glTF/Godot metres
            return [round(p[0] * MM, 6), round(p[2] * MM, 6), round(-p[1] * MM, 6)]

        data = {
            "sources": {rel: {"sha256": sha256(src + "/" + rel), "bytes": __import__("os").path.getsize(src + "/" + rel)}
                        for rel in (BOTTOM_PLATE, TOP_PLATE, ARM, CANOPY, LICENSE, README)},
            "dxf": {"bottom_plate": d_bottom, "top_plate": d_top, "arm": d_arm},
            "arm_hub_hole_mm": {"centre": [round(hub_hole[0], 3), round(hub_hole[1], 3)], "radius": hub_hole[2],
                                "pattern_holes": len(pattern), "pattern_diameter_mm": 16.0},
            "hubs_blender_mm": {str(r): [round(hubs[r][0], 3), round(hubs[r][1], 3), 0.0] for r in hubs},
            "nodes_godot_m": dict(
                [("motor_%d" % r, godot((hubs[r][0], hubs[r][1], 0.0))) for r in hubs]
                + [("propeller_%d" % r, godot((hubs[r][0], hubs[r][1], 0.0))) for r in hubs]
                + [("camera_mount", godot(cam[0])), ("airframe_root", [0.0, 0.0, 0.0])]
            ),
            "camera_mount_method": "centre of the coaxial camera side-screw holes of the canopy camera bay (pivot axis), x = 0",
            "camera_side_hole_area_mm2": round(cam[1], 2),
            "camera_side_hole_clusters_found": cam[2],
            "geometry_mm": {
                "motor_diagonals": [round(diag_a, 3), round(diag_b, 3)],
                "adjacent_spacing": {"right_pair": round(right_pair, 3), "left_pair": round(left_pair, 3),
                                     "front_pair": round(front_pair, 3), "rear_pair": round(rear_pair, 3)},
                "front_to_back_vs_left_to_right_mm": round((right_pair + left_pair) / 2 - (front_pair + rear_pair) / 2, 3),
                "hub_radius_from_centre": [round(math.hypot(*h), 3) for h in hub_list],
                "arm_thickness": ARM_T,
                "arm_thickness_source": "OpenRacer README 'Arms: 5mm' (DXF is 2D)",
                "plate_thickness": PLATE_T,
                "arm_width_perpendicular_at_radius": _arm_width(arm_outer, -45.0, [35, 45, 55, 65, 80, 90]),
                "bounding_box_godot_m": {
                    "min": [min(a, b) for a, b in zip(godot(bbox[0]), godot(bbox[1]))],
                    "max": [max(a, b) for a, b in zip(godot(bbox[0]), godot(bbox[1]))],
                },
                "bounding_box_size_xyz_blender": [round(bbox[1][a] - bbox[0][a], 3) for a in range(3)],
                "canopy_bbox_blender": canopy_bbox,
                "prop_clearance": {k: {"adjacent_tip_gap": [round(s - d, 3) for s in adjacent],
                                       "diagonal_tip_gap": round(min(diag_a, diag_b) - d, 3)}
                                   for k, d in PROP_DIAMETERS_MM.items()},
                "prop_to_canopy_plan_view": clearance,
            },
            "triangles": {"canopy_source": canopy_src_tris, "canopy_out": canopy_tris, "carbon_out": carbon_tris,
                          "total_out": canopy_tris + carbon_tris},
            "canopy_decimate_ratio": round(CANOPY_TARGET_TRIS / float(canopy_src_tris), 6),
            "blender": bpy.app.version_string,
            "output": {"path": out, "sha256": sha256(out), "bytes": __import__("os").path.getsize(out)},
        }
        with open(measure_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
    print("DR-29 build done:", out)


main()
