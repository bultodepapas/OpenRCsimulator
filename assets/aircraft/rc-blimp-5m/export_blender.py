"""Reproducible GLB and physics-geometry exporter for the owner-delivered RC blimp skins.

Run inside Blender 5.2 on one immutable delivered scene:

    blender -b <delivered.blend> --factory-startup \
        --python assets/aircraft/rc-blimp-5m/export_blender.py -- \
        --skin <tiburon-blanco|historico|cromo-carbono-azul> --out <file.glb> \
        [--geometry <geometry.json>] [--report <report.json>] [--work-dir <dir>] \
        [--save-derived <derived.blend>]

Everything happens in memory; the source .blend is never saved. ``--work-dir`` receives the
baked texture files (default: a new temporary directory). ``--save-derived`` optionally saves a
copy of the processed scene (``save_as_mainfile(copy=True)``) to a path outside the repository.

The same file assembles ``source-manifest.json`` with plain Python (no Blender):

    python3 assets/aircraft/rc-blimp-5m/export_blender.py --assemble-manifest <out.json> \
        --zip-dir <dir with delivered zips> --source-dir assets/source-deliveries/rc-blimp-5m \
        --reports <r1.json> <r2.json> <r3.json> --geometries <g1.json> <g2.json> <g3.json> \
        --reference-skin tiburon-blanco
"""

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import tempfile
import time
import unicodedata

try:
    import bpy
    import bmesh
    import numpy as np
    from mathutils import Matrix, Quaternion, Vector
    from mathutils.bvhtree import BVHTree
    HAVE_BPY = True
except ImportError:  # manifest assembly runs without Blender
    HAVE_BPY = False

EXPORTER_VERSION = "rc-blimp-5m-export 1"
ENVELOPE_LENGTH_M = 5.0

SKINS = {
    "tiburon-blanco": "Tiburon_Blanco_V1.blend",
    "historico": "Zeppelin_Historico_V1.blend",
    "cromo-carbono-azul": "Zeppelin_Cromo_Carbono_Azul_V1.blend",
}

ENVELOPE_PREFIX = "Envolvente · perfil auditado"
DEMO_CTRL = "CTRL · INSPECCIÓN V6"
DEMO_PROP = "Activar demostración"
# Every numeric CTRL/ANIM value is set to rest (0) before anything is measured or exported.
REST_PROPS = (
    "Vector grados", "Deflexión grados", "Giro grados", "Paso visual grados",
    "Apertura visual grados", "Compresión visual grados", "Giro rueda grados",
    "Castor pasivo grados",
)

# Articulated GLB nodes: (CTRL empty, node, CTRL value property, travel in degrees).
ARTICULATIONS = (
    ("CTRL · vector lateral babor", "vector_port_hinge", "Vector grados", (0.0, 120.0)),
    ("CTRL · vector lateral estribor", "vector_starboard_hinge", "Vector grados", (0.0, 120.0)),
    ("CTRL · vector popa", "vector_stern_hinge", "Vector grados", (0.0, 90.0)),
    ("CTRL · rotor lateral babor", "rotor_port", "Giro grados", None),
    ("CTRL · rotor lateral estribor", "rotor_starboard", "Giro grados", None),
    ("CTRL · rotor popa axial", "rotor_stern_axial", "Giro grados", None),
    ("CTRL · rotor popa transversal", "rotor_stern_lateral", "Giro grados", None),
    ("CTRL · Aleta dorsal timón", "rudder_dorsal_hinge", "Deflexión grados", (-20.0, 20.0)),
    ("CTRL · Aleta babor timón", "fin_port_hinge", "Deflexión grados", (-20.0, 20.0)),
    ("CTRL · Aleta estribor timón", "fin_starboard_hinge", "Deflexión grados", (-20.0, 20.0)),
)
ROOT_NODE = "airship"

FINS = {  # geometry id -> (Spanish id, CTRL)
    "dorsal": ("dorsal", "CTRL · Aleta dorsal timón"),
    "port": ("babor", "CTRL · Aleta babor timón"),
    "starboard": ("estribor", "CTRL · Aleta estribor timón"),
}
ROTORS = {  # geometry id -> (CTRL, blade-name prefix)
    "port": ("CTRL · rotor lateral babor", "lateral babor · pala "),
    "starboard": ("CTRL · rotor lateral estribor", "lateral estribor · pala "),
    "stern_axial": ("CTRL · rotor popa axial", "popa axial · pala "),
    "stern_lateral": ("CTRL · rotor popa transversal", "popa transversal · pala "),
}
VECTORS = {  # geometry id -> (CTRL, travel, rotor id, sampled CTRL values)
    "port": ("CTRL · vector lateral babor", (0.0, 120.0), "port", (0, 45, 90, 120)),
    "starboard": ("CTRL · vector lateral estribor", (0.0, 120.0), "starboard", (0, 45, 90, 120)),
    "stern": ("CTRL · vector popa", (0.0, 90.0), "stern_axial", (0, 45, 90)),
}
GEAR = {"front": "Tren delantero V3 · neumático", "rear": "Tren trasero V3 · neumático"}
GONDOLA_COLLECTION = "04 · GÓNDOLA"
GLASS_MATERIAL_HINT = ("BSDF_TRANSPARENT", "BSDF_GLOSSY")

# Collections that are never runtime content even when render-enabled (demo, texts, reference,
# annotations, lights, cameras).
EXCLUDED_COLLECTION_PREFIXES = ("06D", "07", "08", "09", "10")

# Reduction rules, all at runtime scale (5 m envelope).
TINY_MAX_DIM_M = 0.002          # drop parts whose largest bounding-box side is below 2 mm
BEVEL_SKIP_M = 0.0005           # do not apply bevel modifiers narrower than 0.5 mm
DECIMATE_MIN_TRIS = 2000        # only meshes denser than this are decimated
DECIMATE_TOL_M = 0.00025        # max two-sided vertex deviation allowed by decimation (0.25 mm)
TRI_BUDGET = 300000

# Bake settings.
BAKE_SAMPLES = 16
BAKE_MARGIN_PX = 8
TEXEL_M = 0.0012                # target texel size at 5 m for smart-projected materials
TEX_MIN, TEX_MAX = 256, 1024
ENVELOPE_TEX = (2048, 1024)     # u along the hull, v around it
ENVELOPE_DATA_TEX = (1024, 512)
UNIFORM_COLOR_RANGE = 0.025     # p0.05..p99.95 range below which a bake collapses to a constant
UNIFORM_DATA_RANGE = 0.03
JPEG_QUALITY = 90
GLASS = dict(base=(0.045, 0.07, 0.095, 1.0), rough=0.05, metal=0.0, alpha=0.35)

BAKE_UV = "UVMap_bake"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ascii_slug(name):
    t = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    t = re.sub(r"[^A-Za-z0-9]+", "_", t).strip("_").lower()
    return t or "x"


def rnd(v, n=6):
    return [round(float(x), n) for x in v]


def read_glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, "not a glTF 2 GLB"
    clen, ctype = struct.unpack_from("<II", data, 12)
    assert ctype == 0x4E4F534A
    return json.loads(data[20:20 + clen].decode("utf-8")), len(data)


# ---------------------------------------------------------------------------------------------
# Manifest assembly (plain Python)
# ---------------------------------------------------------------------------------------------

def _flatten_numbers(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(_flatten_numbers(v, f"{prefix}/{k}" if prefix else str(k)))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out.update(_flatten_numbers(v, f"{prefix}[{i}]"))
    elif isinstance(obj, (int, float)) and not isinstance(obj, bool):
        out[prefix] = float(obj)
    return out


def assemble_manifest(args):
    reports = [json.load(open(p, encoding="utf-8")) for p in args.reports]
    geoms = [json.load(open(p, encoding="utf-8")) for p in args.geometries]
    gskins = [g["skin"] for g in geoms]
    ref = geoms[gskins.index(args.reference_skin)]
    ref_flat = _flatten_numbers({k: v for k, v in ref.items() if k != "source"})
    agreement = {}
    for g in geoms:
        if g is ref:
            continue
        flat = _flatten_numbers({k: v for k, v in g.items() if k != "source"})
        common = sorted(set(flat) & set(ref_flat))
        diffs = {k: abs(flat[k] - ref_flat[k]) for k in common}
        worst = sorted(diffs.items(), key=lambda kv: -kv[1])[:5]
        groups = {}
        for k, d in diffs.items():
            top = k.split("/")[0].split("[")[0]
            groups[top] = max(groups.get(top, 0.0), d)
        agreement[g["skin"]] = {
            "compared_numbers": len(common),
            "only_in_reference": sorted(set(ref_flat) - set(flat)),
            "only_in_skin": sorted(set(flat) - set(ref_flat)),
            "max_abs_difference_by_section": {k: round(v, 9) for k, v in sorted(groups.items())},
            "largest_differences": [[k, round(v, 9)] for k, v in worst],
        }
    zips = []
    if args.zip_dir and os.path.isdir(args.zip_dir):
        for name in sorted(os.listdir(args.zip_dir)):
            if name.lower().endswith(".zip"):
                p = os.path.join(args.zip_dir, name)
                zips.append({"file": name, "bytes": os.path.getsize(p), "sha256": sha256_file(p)})
    files = []
    for root, _dirs, names in os.walk(args.source_dir):
        for name in sorted(names):
            p = os.path.join(root, name)
            rel = os.path.relpath(p, args.source_dir).replace(os.sep, "/")
            if rel == "README.md":
                continue
            files.append({"path": rel, "bytes": os.path.getsize(p), "sha256": sha256_file(p)})
    exporter = os.path.abspath(__file__)
    manifest = {
        "schema": "openrc-airship-source-manifest v1",
        "asset": "rc-blimp-5m",
        "exporter": {"path": "assets/aircraft/rc-blimp-5m/export_blender.py", "version": EXPORTER_VERSION,
                     "sha256": sha256_file(exporter)},
        "delivered_zips": zips,
        "source_files": sorted(files, key=lambda f: f["path"]),
        "geometry": {"path": "assets/aircraft/rc-blimp-5m/geometry.json", "generated_from": args.reference_skin,
                     "cross_skin_agreement": agreement},
        "skins": {r["skin"]: r for r in reports},
        "reports_match_exporter": all(r.get("exporter_sha256") == sha256_file(exporter) for r in reports),
    }
    with open(args.assemble_manifest, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("manifest written", args.assemble_manifest)


# ---------------------------------------------------------------------------------------------
# Blender helpers
# ---------------------------------------------------------------------------------------------

def view_update():
    bpy.context.view_layer.update()


def set_values(values):
    """values: {object name: {property: value}}; tags the objects and re-evaluates drivers."""
    for name, props in values.items():
        o = bpy.data.objects[name]
        for k, v in props.items():
            o[k] = v
        o.update_tag()
    view_update()


def rest_pose():
    sc = bpy.context.scene
    sc.frame_set(sc.frame_start)
    vals = {}
    for o in bpy.data.objects:
        if o.name.startswith(("CTRL ·", "ANIM ·")):
            d = {k: 0.0 for k in REST_PROPS if k in o.keys()}
            if d:
                vals[o.name] = d
    vals.setdefault(DEMO_CTRL, {})[DEMO_PROP] = False
    set_values(vals)
    for ctrl, node, prop, _t in ARTICULATIONS:
        e = bpy.data.objects[ctrl].rotation_euler
        assert max(abs(a) for a in e) < 1e-9, f"{ctrl} not at rest: {tuple(e)}"


def pose(ctrl, prop, value):
    set_values({ctrl: {prop: float(value)}})


def render_collections():
    ok = set()

    def walk(lc, parent_ok):
        good = parent_ok and not lc.exclude and not lc.collection.hide_render
        if good:
            ok.add(lc.collection.name)
        for ch in lc.children:
            walk(ch, good)

    walk(bpy.context.view_layer.layer_collection, True)
    return ok


def export_candidates(report):
    ok = render_collections()
    out, skipped = [], {"hidden": 0, "camera_invisible": 0, "excluded_collection": 0}
    for o in bpy.context.scene.objects:
        if o.type not in ("MESH", "CURVE", "SURFACE", "FONT", "META"):
            continue
        cols = [c.name for c in o.users_collection if c.name in ok]
        if o.hide_render or not cols:
            skipped["hidden"] += 1
            continue
        if not getattr(o, "visible_camera", True):
            skipped["camera_invisible"] += 1
            continue
        if all(c.startswith(EXCLUDED_COLLECTION_PREFIXES) for c in cols):
            skipped["excluded_collection"] += 1
            continue
        out.append(o)
    report["source_objects"] = {"render_visible_geometry": len(out), "skipped": skipped}
    return sorted(out, key=lambda o: o.name)


def owner_node(o):
    ctrl_to_node = {c: n for c, n, _p, _t in ARTICULATIONS}
    p = o.parent
    while p is not None:
        if p.name in ctrl_to_node:
            return ctrl_to_node[p.name]
        p = p.parent
    return ROOT_NODE


def node_parent(ctrl_name):
    ctrl_to_node = {c: n for c, n, _p, _t in ARTICULATIONS}
    p = bpy.data.objects[ctrl_name].parent
    while p is not None:
        if p.name in ctrl_to_node:
            return ctrl_to_node[p.name]
        p = p.parent
    return ROOT_NODE


def world_arrays(o, dg):
    """Evaluated world-space vertex array and triangle index array (source units)."""
    oe = o.evaluated_get(dg)
    me = oe.to_mesh()
    me.calc_loop_triangles()
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    tri = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get("vertices", tri)
    tri = tri.reshape(-1, 3)
    mw = np.array(oe.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    oe.to_mesh_clear()
    return co, tri


def quat_delta_axis(q0, q1):
    """Axis (in q0's local frame) and angle of q0^-1 q1, angle in [0, pi]."""
    d = q0.inverted() @ q1
    axis, ang = d.to_axis_angle()
    if ang > math.pi:
        ang = 2 * math.pi - ang
        axis = -axis
    return Vector(axis).normalized(), ang


# ---------------------------------------------------------------------------------------------
# Frames
# ---------------------------------------------------------------------------------------------

class Frames:
    """Source (Blender, metres full scale) -> pre-export Blender space and physics FRD."""

    def __init__(self, s):
        self.s = s
        self.R90 = Matrix.Rotation(-math.pi / 2, 4, "Z")
        self.G = self.R90 @ Matrix.Scale(s, 4)

    def frd(self, p):
        return [-self.s * p[0], self.s * p[1], -self.s * p[2]]

    @staticmethod
    def frd_dir(d):
        v = Vector((-d[0], d[1], -d[2]))
        return v.normalized() if v.length else v

    @staticmethod
    def godot_dir(d):
        """Source world direction -> Godot/glTF direction (y, z, x)."""
        return Vector((d[1], d[2], d[0]))

    def godot(self, p):
        return Vector((self.s * p[1], self.s * p[2], self.s * p[0]))


# ---------------------------------------------------------------------------------------------
# Articulation analysis
# ---------------------------------------------------------------------------------------------

def articulation_axes(report):
    """Measure each CTRL's rotation axis by posing it, restoring rest afterwards."""
    out = {}
    for ctrl, node, prop, travel in ARTICULATIONS:
        o = bpy.data.objects[ctrl]
        rest_pose()
        q0 = o.matrix_world.to_quaternion()
        t0 = o.matrix_world.translation.copy()
        test = 10.0 if "Aleta" in ctrl else 30.0
        pose(ctrl, prop, test)
        q1 = o.matrix_world.to_quaternion()
        t1 = o.matrix_world.translation.copy()
        axis_local, ang = quat_delta_axis(q0, q1)
        axis_world = (q0 @ axis_local).normalized()
        assert abs(math.degrees(ang) - test) < 1e-3, (ctrl, math.degrees(ang))
        assert (t1 - t0).length < 1e-6, (ctrl, "pivot moved")
        out[node] = dict(ctrl=ctrl, prop=prop, travel=travel, axis_world_src=axis_world,
                         pivot_src=t0, test_deg=test, measured_deg=math.degrees(ang))
    rest_pose()
    report["articulation_axes_measured"] = {n: {"ctrl": v["ctrl"], "test_deg": v["test_deg"],
                                                "measured_deg": round(v["measured_deg"], 6)}
                                            for n, v in out.items()}
    return out


# ---------------------------------------------------------------------------------------------
# Physics geometry
# ---------------------------------------------------------------------------------------------

def section_areas(co, tri, xs):
    """Signed cross-section area of a closed outward-oriented triangle mesh at planes x = xs."""
    v0, v1, v2 = co[tri[:, 0]], co[tri[:, 1]], co[tri[:, 2]]
    n = np.cross(v1 - v0, v2 - v0)
    res = []
    for x in xs:
        d = np.stack([v0[:, 0] - x, v1[:, 0] - x, v2[:, 0] - x], axis=1)
        d[np.abs(d) < 1e-9] = 1e-9
        edges = [(0, 1), (1, 2), (2, 0)]
        verts = [v0, v1, v2]
        pts = np.full((len(tri), 3, 3), np.nan)
        cross_mask = np.zeros((len(tri), 3), dtype=bool)
        for k, (a, b) in enumerate(edges):
            da, db = d[:, a], d[:, b]
            m = (da * db) < 0
            t = np.where(m, da / np.where(m, da - db, 1.0), 0.0)
            pts[:, k, :] = verts[a] + (verts[b] - verts[a]) * t[:, None]
            cross_mask[:, k] = m
        sel = cross_mask.sum(axis=1) == 2
        if not sel.any():
            res.append(0.0)
            continue
        cm = cross_mask[sel]
        pp = pts[sel]
        idx = np.argsort(~cm, axis=1, kind="stable")[:, :2]
        P = pp[np.arange(len(pp)), idx[:, 0]]
        Q = pp[np.arange(len(pp)), idx[:, 1]]
        nn = n[sel]
        tng = Q - P
        sgn = tng[:, 2] * nn[:, 1] - tng[:, 1] * nn[:, 2]
        swap = sgn < 0
        P2 = np.where(swap[:, None], Q, P)
        Q2 = np.where(swap[:, None], P, Q)
        res.append(float(0.5 * np.sum(P2[:, 1] * Q2[:, 2] - P2[:, 2] * Q2[:, 1])))
    return res


def closed_mesh_props(co, tri):
    v0, v1, v2 = co[tri[:, 0]], co[tri[:, 1]], co[tri[:, 2]]
    det = np.einsum("ij,ij->i", v0, np.cross(v1, v2))
    vol = det.sum() / 6.0
    cen = (det[:, None] * (v0 + v1 + v2)).sum(axis=0) / (24.0 * vol)
    area = 0.5 * np.linalg.norm(np.cross(v1 - v0, v2 - v0), axis=1).sum()
    return float(vol), cen, float(area)


def compute_geometry(fr, axes, export_objs, report):
    dg = bpy.context.evaluated_depsgraph_get()
    s = fr.s
    g = {}
    env = next(o for o in bpy.data.objects if o.name.startswith(ENVELOPE_PREFIX))
    co, tri = world_arrays(env, dg)
    bm = bmesh.new()
    bm.from_object(env, dg)
    bm.transform(env.matrix_world)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    bm_vol = bm.calc_volume(signed=True)
    bm.free()
    vol, cen, area = closed_mesh_props(co, tri)
    x0, x1 = float(co[:, 0].min()), float(co[:, 0].max())
    L = x1 - x0
    n_st = 81
    xs = [x0 + L * i / (n_st - 1) for i in range(n_st)]
    inner = section_areas(co, tri, xs[1:-1])
    areas = [0.0] + inner + [0.0]
    profile = [[round(-s * x, 6), round(s * math.sqrt(max(a, 0.0) / math.pi), 6)] for x, a in zip(xs, areas)]
    fine_x = [x0 + L * i / 800 for i in range(801)]
    fine_a = [0.0] + section_areas(co, tri, fine_x[1:-1]) + [0.0]
    sec_vol = sum(0.5 * (fine_a[i] + fine_a[i + 1]) * (fine_x[i + 1] - fine_x[i]) for i in range(800))
    r_fine = [math.sqrt(max(a, 0.0) / math.pi) for a in fine_a]
    g["envelope"] = {
        "object": env.name,
        "volume_m3": round(bm_vol * s ** 3, 6),
        "volume_method": ("closed manifold mesh: bmesh calc_volume after modifiers "
                          f"(non-manifold edges {nonmanifold}, boundary edges {boundary})"),
        "volume_check_sections_m3": round(sec_vol * s ** 3, 6),
        "centroid_m": rnd(fr.frd(cen)),
        "surface_area_m2": round(area * s ** 2, 6),
        "max_diameter_m": round(s * max(co[:, 1].max() - co[:, 1].min(), co[:, 2].max() - co[:, 2].min()), 6),
        "max_equivalent_diameter_m": round(2 * s * max(r_fine), 6),
        "nose_x_m": round(-s * x0, 6),
        "tail_x_m": round(-s * x1, 6),
        "radius_profile_note": "[x_m FRD, sqrt(section_area/pi) m], 81 equally spaced stations nose to tail",
        "radius_profile": profile,
    }
    g["scale"] = s
    g["source_envelope_length_m"] = round(L, 6)
    g["envelope_length_m"] = ENVELOPE_LENGTH_M

    def r_env(xsrc):
        if xsrc <= fine_x[0] or xsrc >= fine_x[-1]:
            return 0.0
        i = min(int((xsrc - x0) / L * 800), 799)
        t = (xsrc - fine_x[i]) / (fine_x[i + 1] - fine_x[i])
        return r_fine[i] * (1 - t) + r_fine[i + 1] * t

    # Fins ---------------------------------------------------------------------------------
    fins = {}
    witnesses = []
    for fid, (es, ctrl) in FINS.items():
        fixed = bpy.data.objects[f"Aleta {es} · estabilizador"]
        moving = bpy.data.objects[f"Aleta {es} · timón móvil"]
        cf, tf = world_arrays(fixed, dg)
        cm, tm = world_arrays(moving, dg)
        allv = np.vstack([cf, cm])
        cov = np.cov((allv - allv.mean(axis=0)).T)
        w, vecs = np.linalg.eigh(cov)
        N = vecs[:, 0]
        ctrl_o = bpy.data.objects[ctrl]
        ref_y = np.array(ctrl_o.matrix_world.to_3x3().col[1])
        if N.dot(ref_y) < 0:
            N = -N
        p0 = allv.mean(axis=0)

        def planform(cc, tt):
            v0, v1, v2 = cc[tt[:, 0]], cc[tt[:, 1]], cc[tt[:, 2]]
            proj = 0.5 * np.maximum(0.0, np.cross(v1 - v0, v2 - v0) @ N)
            c = (v0 + v1 + v2) / 3.0
            rr = np.sqrt(c[:, 1] ** 2 + c[:, 2] ** 2)
            renv = np.array([r_env(x) for x in c[:, 0]])
            exposed = rr > renv
            return proj, c, exposed

        pf, cfc, ef = planform(cf, tf)
        pm, cmc, em = planform(cm, tm)
        a_fixed = float(pf[ef].sum())
        a_moving = float(pm[em].sum())
        a_fixed_total = float(pf.sum())
        wts = np.concatenate([pf * ef, pm * em])
        cc = np.vstack([cfc, cmc])
        cen_f = (cc * wts[:, None]).sum(axis=0) / wts.sum()
        cen_f = cen_f - ((cen_f - p0) @ N) * N
        rad = np.sqrt(allv[:, 1] ** 2 + allv[:, 2] ** 2)
        tip_i = int(np.argmax(rad))
        tip = allv[tip_i]
        span_dir = np.array([0.0, tip[1], tip[2]])
        span_dir -= span_dir.dot(N) * N
        span_dir /= np.linalg.norm(span_dir)
        r_root = r_env(cen_f[0])
        span = float(rad.max() - r_root)
        ax = axes[{"dorsal": "rudder_dorsal_hinge", "port": "fin_port_hinge", "starboard": "fin_starboard_hinge"}[fid]]
        # trailing edge: aft-most vertex of the moving surface, displaced by posing +10 deg
        te_i = int(np.argmax(cm[:, 0]))
        rest_pose()
        pose(ctrl, "Deflexión grados", 10.0)
        cm10, _ = world_arrays(moving, bpy.context.evaluated_depsgraph_get())
        rest_pose()
        disp = cm10[te_i] - cm[te_i]
        # trailing-edge corners of the moving surface (tip end and root end)
        rad_m = np.sqrt(cm[:, 1] ** 2 + cm[:, 2] ** 2)
        tip_band = rad_m > rad_m.max() - 0.15
        root_band = rad_m < rad_m.min() + 0.15
        te_tip = cm[np.where(tip_band)[0][np.argmax(cm[tip_band, 0])]]
        te_root = cm[np.where(root_band)[0][np.argmax(cm[root_band, 0])]]
        fins[fid] = {
            "fixed_object": fixed.name,
            "moving_object": moving.name,
            "fixed_area_m2": round(a_fixed * s * s, 6),
            "moving_area_m2": round(a_moving * s * s, 6),
            "area_note": ("one-side planform projected on the fin mid-plane; triangles whose centroid lies "
                          "inside the envelope radius are excluded"),
            "fixed_area_including_buried_root_m2": round(a_fixed_total * s * s, 6),
            "centroid_m": rnd(fr.frd(cen_f)),
            "span_dir": rnd(fr.frd_dir(span_dir)),
            "normal": rnd(fr.frd_dir(N)),
            "span_m": round(span * s, 6),
            "span_note": "tip radius from hull axis minus envelope radius at the planform-centroid station",
            "mean_chord_m": round((a_fixed + a_moving) / span * s, 6),
            "hinge_point_m": rnd(fr.frd(ax["pivot_src"])),
            "hinge_axis": rnd(fr.frd_dir(ax["axis_world_src"])),
            "te_dir_at_plus_10deg": rnd(fr.frd_dir(disp)),
            "te_point_m": rnd(fr.frd(cm[te_i])),
            "travel_deg": [-20.0, 20.0],
        }
        witnesses += [
            {"id": f"fin_{fid}_tip", "part": f"fin_{fid}", "point_m": rnd(fr.frd(tip))},
            {"id": f"fin_{fid}_te_tip", "part": f"fin_{fid}", "point_m": rnd(fr.frd(te_tip))},
            {"id": f"fin_{fid}_te_root", "part": f"fin_{fid}", "point_m": rnd(fr.frd(te_root))},
        ]
    g["fins"] = fins

    # Rotors -------------------------------------------------------------------------------
    rotors = {}
    node_of_rotor = {"port": "rotor_port", "starboard": "rotor_starboard",
                     "stern_axial": "rotor_stern_axial", "stern_lateral": "rotor_stern_lateral"}
    for rid, (ctrl, prefix) in ROTORS.items():
        c = bpy.data.objects[ctrl]
        ax = axes[node_of_rotor[rid]]
        hub = np.array(c.matrix_world.translation)
        a = np.array(ax["axis_world_src"])
        blades = sorted(o.name for o in export_objs if o.name.startswith(prefix) and o.type == "MESH")
        rmax = 0.0
        for bn in blades:
            bc, _ = world_arrays(bpy.data.objects[bn], dg)
            d = bc - hub
            rr = np.linalg.norm(d - np.outer(d @ a, a), axis=1)
            rmax = max(rmax, float(rr.max()))
        rotors[rid] = {
            "ctrl": ctrl,
            "hub_m": rnd(fr.frd(hub)),
            "axis_rest": rnd(fr.frd_dir(a)),
            "axis_note": ("slipstream direction for the delivered positive spin (+'Giro grados', the demo's "
                          "0->1800 deg sense); thrust on the vehicle is -axis_rest. Blade sections are "
                          "symmetric, so leading edge was inferred from the spin sense: the chord's +tangential "
                          "end sits on the -axis side (about 20 deg pitch at 0.7 R)"),
            "spin_axis_positive_ctrl": rnd(fr.frd_dir(a)),
            "radius_m": round(rmax * s, 6),
            "blade_count": len(blades),
            "documented_rpm": float(c.get("RPM documentadas", 0)),
            "documented_diameter_full_scale_m": float(c.get("Diámetro nominal m", 0)),
        }
        # disc extremes
        e1 = np.cross(a, [0.0, 0.0, 1.0])
        if np.linalg.norm(e1) < 1e-6:
            e1 = np.cross(a, [1.0, 0.0, 0.0])
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(a, e1)
        for k, (nm, vec) in enumerate((("a", e1), ("b", -e1), ("c", e2), ("d", -e2))):
            witnesses.append({"id": f"rotor_{rid}_disc_{nm}", "part": f"rotor_{rid}",
                              "point_m": rnd(fr.frd(hub + rmax * vec))})
    g["rotors"] = rotors

    # Vectors ------------------------------------------------------------------------------
    vectors = {}
    node_of_vector = {"port": "vector_port_hinge", "starboard": "vector_starboard_hinge", "stern": "vector_stern_hinge"}
    for vid, (ctrl, travel, rid, samples) in VECTORS.items():
        ax = axes[node_of_vector[vid]]
        rotor_ctrl = bpy.data.objects[ROTORS[rid][0]]
        rax_local = rotor_ctrl.matrix_world.to_quaternion().inverted() @ axes[node_of_rotor[rid]]["axis_world_src"]
        at = {}
        for v in samples:
            rest_pose()
            pose(ctrl, "Vector grados", v)
            q = rotor_ctrl.matrix_world.to_quaternion()
            at[str(v)] = rnd(fr.frd_dir(q @ rax_local))
        rest_pose()
        vectors[vid] = {
            "ctrl": ctrl,
            "pivot_m": rnd(fr.frd(ax["pivot_src"])),
            "axis": rnd(fr.frd_dir(ax["axis_world_src"])),
            "travel_deg": list(travel),
            "rotor": rid,
            "rotor_axis_at": at,
        }
    g["vectors"] = vectors

    # Gondola and gear ---------------------------------------------------------------------
    gmin = np.array([np.inf] * 3)
    gmax = -gmin
    gond_pts = []
    for o in export_objs:
        if any(c.name == GONDOLA_COLLECTION for c in o.users_collection):
            c, _ = world_arrays(o, dg)
            if len(c):
                gmin = np.minimum(gmin, c.min(axis=0))
                gmax = np.maximum(gmax, c.max(axis=0))
                gond_pts.append(c)
    gp = np.vstack(gond_pts)
    fa, fb = fr.frd(gmin), fr.frd(gmax)
    g["gondola"] = {"min_m": rnd(np.minimum(fa, fb)), "max_m": rnd(np.maximum(fa, fb)),
                    "note": f"all exported objects of collection '{GONDOLA_COLLECTION}' (cabin, glazing, doors)"}
    zlow = gp[:, 2].min()
    band = gp[gp[:, 2] < zlow + 0.08 * (gmax[2] - gmin[2])]
    for nm, pt in (("front", band[np.argmin(band[:, 0])]), ("aft", band[np.argmax(band[:, 0])]),
                   ("port", band[np.argmin(band[:, 1])]), ("starboard", band[np.argmax(band[:, 1])])):
        witnesses.append({"id": f"gondola_bottom_{nm}", "part": "gondola", "point_m": rnd(fr.frd(pt))})
    gear = {}
    for gid, name in GEAR.items():
        c, _ = world_arrays(bpy.data.objects[name], dg)
        low = c[np.argmin(c[:, 2])]
        gear[gid] = {"object": name, "contact_point_m": rnd(fr.frd(low)),
                     "wheel_radius_m": round(0.5 * s * float(c[:, 2].max() - c[:, 2].min()), 6)}
        witnesses.append({"id": f"gear_{gid}_contact", "part": f"gear_{gid}", "point_m": rnd(fr.frd(low))})
    g["gear"] = gear

    # Hull witnesses -----------------------------------------------------------------------
    hull = [{"id": "hull_nose", "part": "envelope", "point_m": rnd(fr.frd(co[np.argmin(co[:, 0])]))},
            {"id": "hull_tail", "part": "envelope", "point_m": rnd(fr.frd(co[np.argmax(co[:, 0])]))}]
    ring_dx = L / 300
    for k in range(1, 8):
        xk = x0 + L * k / 8
        ring = co[np.abs(co[:, 0] - xk) < ring_dx]
        if not len(ring):
            continue
        for nm, pt in (("top", ring[np.argmax(ring[:, 2])]), ("bottom", ring[np.argmin(ring[:, 2])]),
                       ("port", ring[np.argmin(ring[:, 1])]), ("starboard", ring[np.argmax(ring[:, 1])])):
            hull.append({"id": f"hull_s{k}_{nm}", "part": "envelope", "point_m": rnd(fr.frd(pt))})
    g["collision_witnesses"] = hull + witnesses
    rest_pose()
    return g


# ---------------------------------------------------------------------------------------------
# Work meshes, reduction
# ---------------------------------------------------------------------------------------------

def material_kind(mat):
    if mat is None or mat.node_tree is None:
        return "plain"
    types = {n.type for n in mat.node_tree.nodes}
    if "BSDF_PRINCIPLED" not in types and types & set(GLASS_MATERIAL_HINT):
        return "glass"
    out = mat.node_tree.get_output_node("CYCLES")
    root = linked_node(out.inputs["Surface"]) if out else None
    if root is None:
        return "plain"
    stack, seen = [root], set()
    proc = False
    while stack:
        n = stack.pop()
        if n is None or n.name in seen:
            continue
        seen.add(n.name)
        if n.type == "MIX_SHADER":
            proc = True
            stack += [linked_node(n.inputs[1]), linked_node(n.inputs[2])]
        elif n.type == "BSDF_PRINCIPLED":
            for k in ("Base Color", "Roughness", "Metallic", "Alpha", "Emission Color", "Emission Strength"):
                if n.inputs[k].is_linked:
                    proc = True
        else:
            return "unsupported"
    return "procedural" if proc else "plain"


def linked_node(sock):
    if sock is None or not sock.is_linked:
        return None
    n = sock.links[0].from_node
    while n.type == "REROUTE":
        if not n.inputs[0].is_linked:
            return None
        n = n.inputs[0].links[0].from_node
    return n


def is_glass_only(o):
    mats = [s.material for s in o.material_slots]
    return bool(mats) and all(material_kind(m) == "glass" for m in mats)


def build_work_objects(objs, s, report):
    view_update()
    saved = []
    bevel_skipped, solidify_skipped = 0, []
    for o in objs:
        for m in o.modifiers:
            saved.append((m, "show_viewport", m.show_viewport))
            m.show_viewport = m.show_render
            if (m.type == "BEVEL" and m.show_render and m.offset_type in ("OFFSET", "WIDTH", "DEPTH")
                    and m.width * max(o.matrix_world.to_scale()) * s < BEVEL_SKIP_M):
                m.show_viewport = False
                bevel_skipped += 1
            if m.type == "SOLIDIFY" and m.show_render and is_glass_only(o):
                m.show_viewport = False
                solidify_skipped.append(o.name)
        if o.type in ("CURVE", "SURFACE", "FONT") and getattr(o.data, "render_resolution_u", 0):
            saved.append((o.data, "resolution_u", o.data.resolution_u))
            o.data.resolution_u = o.data.render_resolution_u
    view_update()
    dg = bpy.context.evaluated_depsgraph_get()
    col = bpy.data.collections.new("OPENRC_WORK")
    bpy.context.scene.collection.children.link(col)
    works, tiny = [], []
    for o in objs:
        oe = o.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(oe, preserve_all_data_layers=True, depsgraph=dg)
        if len(me.polygons) == 0:
            bpy.data.meshes.remove(me)
            continue
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(o.matrix_world)
        wco = co @ mw[:3, :3].T + mw[:3, 3]
        dim = float((wco.max(axis=0) - wco.min(axis=0)).max()) * s
        if dim < TINY_MAX_DIM_M:
            tiny.append(o.name)
            bpy.data.meshes.remove(me)
            continue
        set_materials_keep_indices(me, [slot.material for slot in o.material_slots])
        for attr in list(me.color_attributes):
            me.color_attributes.remove(attr)
        src = o.data
        if hasattr(src, "texspace_location") and hasattr(me, "use_auto_texspace"):
            me.use_auto_texspace = False
            me.texspace_location = src.texspace_location
            me.texspace_size = src.texspace_size
        if any(m.type == "BEVEL" and m.show_render and not m.show_viewport for m in o.modifiers):
            me.set_sharp_from_angle(angle=math.radians(30.0))
        w = bpy.data.objects.new("W " + o.name, me)
        col.objects.link(w)
        w.matrix_world = o.matrix_world.copy()
        w["openrc_source"] = o.name
        w["openrc_owner"] = owner_node(o)
        works.append(w)
    for target, attr, value in saved:
        setattr(target, attr, value)
    view_update()
    report["reduction"] = {
        "tiny_removed_rule": f"largest bounding-box side < {TINY_MAX_DIM_M * 1000:.1f} mm at 5 m",
        "tiny_removed": tiny,
        "bevel_modifiers_not_applied": bevel_skipped,
        "bevel_rule": f"bevel width < {BEVEL_SKIP_M * 1000:.2f} mm at 5 m; sharp edges marked at 30 deg instead",
        "glass_solidify_not_applied": solidify_skipped,
    }
    return works


def set_materials_keep_indices(me, mats):
    """Replace a mesh's material list without touching face material indices (clear() resets them)."""
    mi = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mi)
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mi)
    me.update()


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def _mesh_bvh(me, mw):
    verts = [mw @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    return BVHTree.FromPolygons(verts, polys, all_triangles=False), verts


def _max_dist(bvh, verts, limit):
    m = 0.0
    for v in verts:
        hit = bvh.find_nearest(v)
        if hit[0] is None:
            return math.inf
        if hit[3] > m:
            m = hit[3]
            if m > limit:
                return m
    return m


def _material_areas(me):
    out = {}
    for poly in me.polygons:
        out[poly.material_index] = out.get(poly.material_index, 0.0) + poly.area
    return out


def _areas_kept(a0, a1, rel=0.10):
    return all(a1.get(k, 0.0) > 0.0 and abs(a1.get(k, 0.0) - v) <= rel * v for k, v in a0.items() if v > 0.0)


def decimate_dense(works, s, report):
    tol = DECIMATE_TOL_M / s
    col = works[0].users_collection[0]
    tmp = bpy.data.objects.new("OPENRC_DECIMATE_TMP", bpy.data.meshes.new("tmp"))
    col.objects.link(tmp)
    mod = tmp.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    vg = tmp.vertex_groups.new(name="openrc_keep_material_borders")
    mod.vertex_group = vg.name
    mod.vertex_group_factor = 100.0
    entries = []
    for w in sorted(works, key=lambda o: -tri_count(o.data)):
        t0 = tri_count(w.data)
        if t0 < DECIMATE_MIN_TRIS:
            continue
        me0 = w.data
        tmp.matrix_world = w.matrix_world
        bvh0, verts0 = _mesh_bvh(me0, w.matrix_world)
        # Vertices on a material border get weight 0, which makes their collapse very expensive, so
        # small coloured regions (blade bands, stripes) survive; a per-material area check backs it up.
        tmp.data = me0
        vmat = {}
        border = set()
        for poly in me0.polygons:
            for vi in poly.vertices:
                if vmat.setdefault(vi, poly.material_index) != poly.material_index:
                    border.add(vi)
        vg.add(list(range(len(me0.vertices))), 1.0, "REPLACE")
        if border:
            vg.add(sorted(border), 0.0, "REPLACE")
        area0 = _material_areas(me0)
        lo, hi = max(0.01, 300.0 / t0), 1.0
        best = None
        for _ in range(7):
            r = math.sqrt(lo * hi)
            tmp.data = me0
            mod.ratio = r
            view_update()
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            bvh1, verts1 = _mesh_bvh(me, w.matrix_world)
            dev = _max_dist(bvh1, verts0, tol)
            if dev <= tol:
                dev = max(dev, _max_dist(bvh0, verts1, tol))
            if dev <= tol and not _areas_kept(area0, _material_areas(me)):
                dev = math.inf
            if dev <= tol:
                if best is not None:
                    bpy.data.meshes.remove(best[0])
                best = (me, r, dev)
                hi = r
            else:
                bpy.data.meshes.remove(me)
                lo = r
        tmp.data = bpy.data.meshes["tmp"]
        if best is None:
            continue
        me, r, dev = best
        set_materials_keep_indices(me, list(me0.materials))
        if hasattr(me, "use_auto_texspace") and hasattr(me0, "texspace_location"):
            me.use_auto_texspace = False
            me.texspace_location = me0.texspace_location
            me.texspace_size = me0.texspace_size
        w.data = me
        bpy.data.meshes.remove(me0)
        entries.append({"object": w["openrc_source"], "tris_before": t0, "tris_after": tri_count(me),
                        "ratio": round(r, 4), "max_deviation_mm_at_5m": round(dev * s * 1000, 4)})
    bpy.data.objects.remove(tmp)
    report["reduction"]["decimation_rule"] = (
        f"collapse decimation of meshes with >= {DECIMATE_MIN_TRIS} triangles, smallest ratio (7-step "
        f"bisection) whose two-sided vertex deviation stays <= {DECIMATE_TOL_M * 1000:.2f} mm at 5 m; "
        "material-border vertices are protected (vertex-group weight 0, factor 100) and every material "
        "must keep its area within 10 %")
    report["reduction"]["decimated"] = entries
    return entries


# ---------------------------------------------------------------------------------------------
# Materials and baking
# ---------------------------------------------------------------------------------------------

CH_INPUT = {"base": "Base Color", "rough": "Roughness", "metal": "Metallic"}


def principled_consts(n):
    return {
        "base": tuple(n.inputs["Base Color"].default_value),
        "rough": float(n.inputs["Roughness"].default_value),
        "metal": float(n.inputs["Metallic"].default_value),
        "alpha": float(n.inputs["Alpha"].default_value),
        "emit_color": tuple(n.inputs["Emission Color"].default_value),
        "emit_strength": float(n.inputs["Emission Strength"].default_value),
    }


def _mix_sock(node, kind, which):
    ident = {"Factor": "Factor_Float", "A": f"A_{kind}", "B": f"B_{kind}", "Result": f"Result_{kind}"}[which]
    socks = node.outputs if which == "Result" else node.inputs
    return next(sk for sk in socks if sk.identifier == ident)


def channel_socket(nt, node, ch):
    """(socket, None) for a varying channel or (None, constant) for a constant one."""
    if node is None:
        return None, ((0.0, 0.0, 0.0, 1.0) if ch == "base" else 0.0)
    if node.type == "BSDF_PRINCIPLED":
        inp = node.inputs[CH_INPUT[ch]]
        if inp.is_linked:
            return inp.links[0].from_socket, None
        v = inp.default_value
        return None, (tuple(v) if ch == "base" else float(v))
    if node.type == "MIX_SHADER":
        a = channel_socket(nt, linked_node(node.inputs[1]), ch)
        b = channel_socket(nt, linked_node(node.inputs[2]), ch)
        fac = node.inputs[0]
        if a[0] is None and b[0] is None and a[1] == b[1]:
            return None, a[1]
        kind = "Color" if ch == "base" else "Float"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA" if ch == "base" else "FLOAT"
        mix.clamp_factor = True
        fs = _mix_sock(mix, kind, "Factor")
        if fac.is_linked:
            nt.links.new(fac.links[0].from_socket, fs)
        else:
            fs.default_value = fac.default_value
        for (sock, const), which in ((a, "A"), (b, "B")):
            tgt = _mix_sock(mix, kind, which)
            if sock is not None:
                nt.links.new(sock, tgt)
            else:
                tgt.default_value = const
        return _mix_sock(mix, kind, "Result"), None
    raise RuntimeError(f"unsupported shader node {node.type} in {nt.name}")


OBJ_CO_ATTR = "openrc_object_co"
GEN_CO_ATTR = "openrc_generated_co"


def localize_texcoords(nt):
    """Route object-space and generated coordinates through attributes stored on the bake proxy."""
    notes = []
    for n in list(nt.nodes):
        if n.type != "TEX_COORD":
            continue
        for out_name, attr in (("Object", OBJ_CO_ATTR), ("Generated", GEN_CO_ATTR)):
            if out_name == "Object" and n.object is not None:
                continue
            sock = n.outputs[out_name]
            if not sock.is_linked:
                continue
            a = nt.nodes.new("ShaderNodeAttribute")
            a.attribute_type = "GEOMETRY"
            a.attribute_name = attr
            for lk in list(sock.links):
                nt.links.new(a.outputs["Vector"], lk.to_socket)
            notes.append(f"{out_name} -> attribute {attr}")
        if n.outputs["Normal"].is_linked:
            notes.append("object-space Normal output used: evaluated in world space on the proxy")
    return notes


def build_bake_proxy(bake_objs, col):
    tmps = []
    render_names = {}
    for w in bake_objs:
        me = w.data.copy()
        n = len(me.vertices)
        co = np.empty(n * 3, dtype=np.float64)
        me.vertices.foreach_get("co", co)
        me.attributes.new(OBJ_CO_ATTR, "FLOAT_VECTOR", "POINT").data.foreach_set("vector", co.astype(np.float32))
        if hasattr(me, "texspace_location"):
            loc = np.array(me.texspace_location)
            size = np.array(me.texspace_size)
            size[size == 0] = 1.0
            gen = (co.reshape(-1, 3) - loc) / (2.0 * size) + 0.5
            me.attributes.new(GEN_CO_ATTR, "FLOAT_VECTOR", "POINT").data.foreach_set("vector", gen.ravel().astype(np.float32))
        rl = next((l.name for l in me.uv_layers if l.active_render and l.name != BAKE_UV), None)
        if rl:
            render_names[rl] = render_names.get(rl, 0) + 1
        me.transform(w.matrix_world)
        if w.matrix_world.determinant() < 0:
            me.flip_normals()
        t = bpy.data.objects.new("OPENRC_BAKE_PROXY", me)
        col.objects.link(t)
        tmps.append(t)
    view_update()
    with bpy.context.temp_override(active_object=tmps[0], object=tmps[0], selected_objects=tmps,
                                   selected_editable_objects=tmps):
        bpy.ops.object.join()
    proxy = tmps[0]
    me = proxy.data
    me.uv_layers.active = me.uv_layers[BAKE_UV]
    if render_names:
        me.uv_layers[max(render_names, key=render_names.get)].active_render = True
    else:
        me.uv_layers[BAKE_UV].active_render = True
    view_update()
    return proxy


class BakeMaterial:
    def __init__(self, mat):
        self.mat = mat
        nt = mat.node_tree
        self.out = nt.get_output_node("CYCLES")
        root = linked_node(self.out.inputs["Surface"])
        self.channels = {ch: channel_socket(nt, root, ch) for ch in ("base", "rough", "metal")}
        prin = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"]
        self.consts = principled_consts(prin[0]) if prin else None
        self.texcoord_notes = localize_texcoords(nt)
        self.emit = nt.nodes.new("ShaderNodeEmission")
        self.emit.inputs["Strength"].default_value = 1.0
        self.img_node = nt.nodes.new("ShaderNodeTexImage")
        for sock in (self.out.inputs.get("Displacement"), self.out.inputs.get("Volume")):
            if sock is not None and sock.is_linked:
                nt.links.remove(sock.links[0])
        nt.links.new(self.emit.outputs[0], self.out.inputs["Surface"])
        self.images = {}
        self.size = None
        self.result = {}

    def varying(self):
        return [ch for ch, (sock, _c) in self.channels.items() if sock is not None]

    def prepare_pass(self, ch, dummy):
        nt = self.mat.node_tree
        for lk in list(self.emit.inputs["Color"].links):
            nt.links.remove(lk)
        sock, const = self.channels[ch]
        if ch in self.images:
            if sock is not None:
                nt.links.new(sock, self.emit.inputs["Color"])
            self.img_node.image = self.images[ch]
        else:
            self.img_node.image = dummy
        nt.nodes.active = self.img_node


def set_dummy_active(mat, dummy):
    if mat is None or mat.node_tree is None:
        return
    nt = mat.node_tree
    n = nt.nodes.get("OPENRC_DUMMY")
    if n is None:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.name = "OPENRC_DUMMY"
        n.image = dummy
    nt.nodes.active = n


def pow2_size(area_m2):
    side = math.sqrt(max(area_m2, 1e-9) / 0.6) / TEXEL_M
    p = TEX_MIN
    while p < side and p < TEX_MAX:
        p *= 2
    return p


def envelope_uv(w):
    me = w.data
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(w.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    x0, x1 = co[:, 0].min(), co[:, 0].max()
    u_v = (co[:, 0] - x0) / (x1 - x0)
    r = np.hypot(co[:, 1], co[:, 2])
    th = np.arctan2(-co[:, 1], -co[:, 2])  # seam on the dorsal line (+Z)
    v_v = (th + np.pi) / (2 * np.pi)
    nl = len(me.loops)
    lv = np.empty(nl, dtype=np.int32)
    me.loops.foreach_get("vertex_index", lv)
    ls = np.empty(len(me.polygons), dtype=np.int32)
    lt = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    lu = u_v[lv].copy()
    lvv = v_v[lv].copy()
    pole = r[lv] < 1e-5 * (x1 - x0)
    span = np.zeros(len(ls))
    for f in range(len(ls)):
        a, b = ls[f], ls[f] + lt[f]
        idx = [i for i in range(a, b) if not pole[i]]
        if not idx:
            lvv[a:b] = 0.5
            continue
        ref = lvv[idx[0]]
        for i in idx:  # unwrap every loop to within half a turn of the face's first loop
            lvv[i] += round(ref - lvv[i])
        m = float(np.mean(lvv[idx]))
        for i in range(a, b):
            if pole[i]:
                lvv[i] = m
        shift = -math.floor(m)
        lvv[a:b] += shift
        span[f] = lvv[a:b].max() - lvv[a:b].min()
    regular = np.repeat(span < 0.25, lt)
    vmax = float(lvv[regular].max()) if regular.any() else 1.0
    lvv /= max(1.0, vmax)  # seam faces overhang 1.0 by at most one facet; squeeze them in
    np.clip(lvv, 0.0, 1.0, out=lvv)  # the few wide fan faces at the tips are clipped
    uv = np.stack([lu, lvv], axis=1).ravel()
    me.uv_layers[BAKE_UV].data.foreach_set("uv", uv)


def smart_project(objs, mat):
    bpy.ops.object.select_all(action="DESELECT")
    for w in objs:
        w.select_set(True)
        me = w.data
        idx = {i for i, s in enumerate(w.material_slots) if s.material == mat}
        sel = [p.material_index in idx for p in me.polygons]
        me.polygons.foreach_set("select", sel)
        vsel = [False] * len(me.vertices)
        for p, sflag in zip(me.polygons, sel):
            if sflag:
                for vi in p.vertices:
                    vsel[vi] = True
        me.vertices.foreach_set("select", vsel)
        me.edges.foreach_set("select", [vsel[e.vertices[0]] and vsel[e.vertices[1]] for e in me.edges])
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def img_stats(img, channels):
    px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    cov = px[:, 3] > 0.5
    if not cov.any():
        return None, 0.0
    vals = px[cov][:, :channels]
    lo = np.percentile(vals, 0.05, axis=0)
    hi = np.percentile(vals, 99.95, axis=0)
    return dict(mean=vals.mean(axis=0), range=float((hi - lo).max())), float(cov.mean())


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def bake_materials(works, skin, work_dir, report):
    sc = bpy.context.scene
    env_src = next(o for o in bpy.data.objects if o.name.startswith(ENVELOPE_PREFIX))
    env_w = next(w for w in works if w["openrc_source"] == env_src.name)
    env_mats = {s.material for s in env_w.material_slots if s.material}
    # Other users of an envelope material get an identical copy so the envelope owns its texture.
    copies = {}
    for w in works:
        if w is env_w:
            continue
        for slot_i, m in enumerate(w.data.materials):
            if m in env_mats:
                if m not in copies:
                    cp = m.copy()
                    cp.name = m.name + " · piezas"
                    copies[m] = cp
                w.data.materials[slot_i] = copies[m]
    used = {}  # material -> work objects with at least one face using it
    for w in works:
        me = w.data
        mi = np.empty(len(me.polygons), dtype=np.int32)
        me.polygons.foreach_get("material_index", mi)
        mats = {me.materials[i] if i < len(me.materials) else None for i in np.unique(mi).tolist()}
        for m in mats:
            used.setdefault(m, []).append(w)
    kinds = {m: material_kind(m) for m in used}
    proc = [m for m, k in kinds.items() if k == "procedural"]
    report["materials_source"] = {(m.name if m else "None"): k for m, k in sorted(kinds.items(), key=lambda kv: kv[0].name if kv[0] else "")}
    bake_objs = sorted({w for m in proc for w in used[m]}, key=lambda o: o.name)
    for w in bake_objs:
        me = w.data
        render_layer = next((l.name for l in me.uv_layers if l.active_render), None)
        uv = me.uv_layers.new(name=BAKE_UV)
        me.uv_layers.active = uv
        if render_layer:
            me.uv_layers[render_layer].active_render = True
    bms = {}
    for m in proc:
        bm_ = BakeMaterial(m)
        bms[m] = bm_
        objs = sorted(used[m], key=lambda o: o.name)
        if m in env_mats:
            envelope_uv(env_w)
            size = ENVELOPE_TEX
            dsize = ENVELOPE_DATA_TEX
        else:
            smart_project(objs, m)
            area = 0.0
            for w in objs:
                idx = {i for i, s in enumerate(w.material_slots) if s.material == m}
                sc_ = w.matrix_world.to_scale()
                area += sum(p.area for p in w.data.polygons if p.material_index in idx) * (sc_[0] * sc_[1])
            side = pow2_size(area * report["scale"] ** 2)
            size = dsize = (side, side)
        bm_.size = size
        for ch in bm_.varying():
            wh = size if ch == "base" else dsize
            img = bpy.data.images.new(f"bake_{ascii_slug(m.name)}_{ch}", wh[0], wh[1], alpha=True, float_buffer=False)
            img.colorspace_settings.name = "sRGB" if ch == "base" else "Non-Color"
            img.pixels.foreach_set(np.zeros(wh[0] * wh[1] * 4, dtype=np.float32))
            bm_.images[ch] = img
    dummy = bpy.data.images.new("openrc_bake_dummy", 8, 8, alpha=True)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = BAKE_SAMPLES
    sc.cycles.use_denoising = False
    sc.cycles.seed = 0
    sc.render.bake.margin = BAKE_MARGIN_PX
    sc.render.bake.margin_type = "EXTEND"
    t0 = time.time()
    # Cycles re-syncs the whole render scene for every selected object, so all baked parts are joined
    # into one world-space proxy; their object-space coordinates travel as an attribute.
    proxy = build_bake_proxy(bake_objs, env_w.users_collection[0])
    other_mats = {m for m in proxy.data.materials if m not in bms}
    hidden = [o for o in sc.objects if o.type in ("MESH", "CURVE", "SURFACE", "FONT", "META")
              and o is not proxy and not o.hide_render]
    for o in hidden:
        o.hide_render = True
    try:
        for ch in ("base", "rough", "metal"):
            if not any(ch in b.images for b in bms.values()):
                continue
            for b in bms.values():
                b.prepare_pass(ch, dummy)
            for m in other_mats:
                set_dummy_active(m, dummy)
            bpy.ops.object.select_all(action="DESELECT")
            proxy.select_set(True)
            bpy.context.view_layer.objects.active = proxy
            bpy.ops.object.bake(type="EMIT", uv_layer=BAKE_UV, margin=BAKE_MARGIN_PX, margin_type="EXTEND",
                                use_clear=False, target="IMAGE_TEXTURES", use_selected_to_active=False)
    finally:
        for o in hidden:
            o.hide_render = False
    pme = proxy.data
    bpy.data.objects.remove(proxy)
    bpy.data.meshes.remove(pme)
    bake_seconds = time.time() - t0
    # Decide textures vs constants, write files.
    os.makedirs(work_dir, exist_ok=True)
    results = {}
    for m, b in bms.items():
        res = {"size": list(b.size), "channels": {}, "texcoords": b.texcoord_notes}
        consts = {}
        for ch in ("base", "rough", "metal"):
            sock, const = b.channels[ch]
            if ch not in b.images:
                consts[ch] = const
                res["channels"][ch] = {"mode": "constant (unlinked)"}
                continue
            img = b.images[ch]
            st, coverage = img_stats(img, 3 if ch == "base" else 1)
            if st is None:
                raise RuntimeError(f"bake of {m.name}/{ch} wrote no pixels")
            thr = UNIFORM_COLOR_RANGE if ch == "base" else UNIFORM_DATA_RANGE
            if st["range"] < thr:
                mean = st["mean"]
                consts[ch] = tuple(srgb_to_linear(mean).tolist()) + (1.0,) if ch == "base" else float(mean[0])
                res["channels"][ch] = {"mode": "baked, uniform -> constant", "range": round(st["range"], 4),
                                       "coverage": round(coverage, 4)}
            else:
                res["channels"][ch] = {"mode": "texture", "range": round(st["range"], 4),
                                       "coverage": round(coverage, 4), "size": list(img.size)}
        tex = {}
        slug = f"{skin}_{ascii_slug(m.name)}"
        if res["channels"]["base"]["mode"] == "texture":
            path = os.path.join(work_dir, slug + "_basecolor.jpg")
            img = b.images["base"]
            img.file_format = "JPEG"
            img.filepath_raw = path
            try:
                img.save(filepath=path, quality=JPEG_QUALITY)
            except TypeError:
                sc.render.image_settings.quality = JPEG_QUALITY
                img.save()
            tex["base"] = path
        mr_chs = [ch for ch in ("rough", "metal") if res["channels"][ch]["mode"] == "texture"]
        if mr_chs:
            wh = b.images[mr_chs[0]].size
            n = wh[0] * wh[1]
            mr = np.ones((n, 4), dtype=np.float32)
            for ch, col in (("rough", 1), ("metal", 2)):
                if ch in mr_chs:
                    src = b.images[ch]
                    if tuple(src.size) != tuple(wh):
                        src.scale(wh[0], wh[1])
                    px = np.empty(n * 4, dtype=np.float32)
                    src.pixels.foreach_get(px)
                    mr[:, col] = px.reshape(-1, 4)[:, 0]
                else:
                    mr[:, col] = consts[ch]
            mimg = bpy.data.images.new(slug + "_mr", wh[0], wh[1], alpha=False, float_buffer=False)
            mimg.colorspace_settings.name = "Non-Color"
            mimg.pixels.foreach_set(mr.ravel())
            path = os.path.join(work_dir, slug + "_metallicroughness.png")
            mimg.file_format = "PNG"
            mimg.filepath_raw = path
            mimg.save()
            tex["mr"] = path
        res["files"] = {k: os.path.basename(v) for k, v in tex.items()}
        results[m] = (res, consts, tex)
    report["bake"] = {
        "engine": "Cycles CPU", "type": "EMIT (channel wired to an Emission shader, no lighting)",
        "proxy": ("all baked parts joined into one world-space proxy (one scene sync per pass); each part's "
                  "object-space and generated coordinates are stored as attributes and replace the "
                  "TexCoord Object/Generated outputs, so the shaders see the same coordinates"),
        "baked_parts": len(bake_objs),
        "samples": BAKE_SAMPLES, "margin_px": BAKE_MARGIN_PX, "margin_type": "EXTEND", "seconds": round(bake_seconds, 1),
        "uv": {"envelope": "cylindrical: u = hull station, v = angle around the X axis, seam on the dorsal line",
               "others": "smart UV project per material (66 deg, island margin 0.004), all users packed together"},
        "texel_target_mm_at_5m": TEXEL_M * 1000, "envelope_texture": list(ENVELOPE_TEX),
        "uniform_rule": f"bake collapses to a constant when its p0.05..p99.95 range is below "
                        f"{UNIFORM_COLOR_RANGE} (color) / {UNIFORM_DATA_RANGE} (data)",
        "normal_maps": "not baked: the procedural bump is sub-millimetre at 5 m",
        "materials": {m.name: r[0] for m, r in results.items()},
    }
    return kinds, bms, results, copies


def new_principled(name, base, rough, metal, alpha=1.0, emit=None, base_img=None, mr_img=None,
                   blend=False, double_sided=True):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    p.inputs["Base Color"].default_value = base
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["Alpha"].default_value = alpha
    if emit and emit[1] > 0:
        p.inputs["Emission Color"].default_value = emit[0]
        p.inputs["Emission Strength"].default_value = emit[1]
    uvn = None
    if base_img is not None or mr_img is not None:
        uvn = nt.nodes.new("ShaderNodeUVMap")
        uvn.uv_map = BAKE_UV
    if base_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = base_img
        nt.links.new(uvn.outputs["UV"], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    if mr_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = mr_img
        nt.links.new(uvn.outputs["UV"], t.inputs["Vector"])
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t.outputs["Color"], sep.inputs[0])
        nt.links.new(sep.outputs[1], p.inputs["Roughness"])
        nt.links.new(sep.outputs[2], p.inputs["Metallic"])
    m.use_backface_culling = not double_sided
    if blend:
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        if hasattr(m, "blend_method"):
            try:
                m.blend_method = "BLEND"
            except (TypeError, AttributeError):
                pass
    return m


def final_materials(skin, works, kinds, bms, results, report):
    cache, mapping = {}, {}
    images = {}

    def load(path):
        if path not in images:
            img = bpy.data.images.load(path)
            img.name = os.path.splitext(os.path.basename(path))[0]
            if path.endswith(".png"):
                img.colorspace_settings.name = "Non-Color"
            images[path] = img
        return images[path]

    out_report = {}
    for m, kind in kinds.items():
        name = ascii_slug(m.name) if m else "default"
        if kind == "glass":
            key = ("glass",)
            spec = dict(base=GLASS["base"], rough=GLASS["rough"], metal=GLASS["metal"], alpha=GLASS["alpha"],
                        blend=True, double_sided=True)
            note = "non-Principled glass replaced by Principled glass, alpha blend"
        elif kind == "procedural":
            res, consts, tex = results[m]
            bc = bms[m].consts or {}
            spec = dict(base=consts.get("base", (1, 1, 1, 1)) if "base" not in tex else (1, 1, 1, 1),
                        rough=consts.get("rough", 1.0) if "mr" not in tex else 1.0,
                        metal=consts.get("metal", 0.0) if "mr" not in tex else 1.0,
                        alpha=bc.get("alpha", 1.0),
                        emit=(bc.get("emit_color"), bc.get("emit_strength", 0.0)) if bc else None,
                        base_img=load(tex["base"]) if "base" in tex else None,
                        mr_img=load(tex["mr"]) if "mr" in tex else None,
                        double_sided=not m.use_backface_culling)
            key = ("proc", m.name)
            note = "baked"
        else:
            prin = [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"] if m and m.node_tree else []
            if prin:
                c = principled_consts(prin[0])
            else:
                c = dict(base=(0.5, 0.5, 0.5, 1.0), rough=0.5, metal=0.0, alpha=1.0, emit_color=(0, 0, 0, 1), emit_strength=0.0)
            spec = dict(base=c["base"], rough=c["rough"], metal=c["metal"], alpha=c["alpha"],
                        emit=(c["emit_color"], c["emit_strength"]), double_sided=not (m.use_backface_culling if m else False))
            key = ("plain", tuple(round(x, 4) for x in spec["base"]), round(spec["rough"], 4), round(spec["metal"], 4),
                   round(spec["alpha"], 4), round(c["emit_strength"], 4), tuple(round(x, 4) for x in c["emit_color"]),
                   spec["double_sided"])
            note = "plain Principled constants" if kind == "plain" else "unsupported shader -> grey Principled"
        if key not in cache:
            cache[key] = new_principled(f"{skin}_{name}", **spec)
        mapping[m] = cache[key]
        out_report[m.name if m else "None"] = {"kind": kind, "gltf_material": cache[key].name, "note": note}
    for w in works:
        for i, m in enumerate(w.data.materials):
            w.data.materials[i] = mapping.get(m)
        me = w.data
        has_tex = any(m is not None and any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes) for m in me.materials)
        for l in [l for l in me.uv_layers if l.name != BAKE_UV or not has_tex]:
            me.uv_layers.remove(l)
    report["materials"] = out_report
    return images


# ---------------------------------------------------------------------------------------------
# Hierarchy and export
# ---------------------------------------------------------------------------------------------

def build_hierarchy(fr, axes, works, report):
    col = bpy.data.collections.new("OPENRC_EXPORT")
    bpy.context.scene.collection.children.link(col)
    nodes = {}
    root = bpy.data.objects.new(ROOT_NODE, None)
    col.objects.link(root)
    root.matrix_world = Matrix.Identity(4)
    nodes[ROOT_NODE] = root
    world = {ROOT_NODE: Matrix.Identity(4)}
    for ctrl, node, prop, travel in ARTICULATIONS:  # parents precede children in this order
        t = bpy.data.objects[ctrl].matrix_world.translation
        world[node] = Matrix.Translation(fr.G @ t)
        e = bpy.data.objects.new(node, None)
        col.objects.link(e)
        par = node_parent(ctrl)
        e.parent = nodes[par]
        e.matrix_parent_inverse = Matrix.Identity(4)
        e.matrix_basis = world[par].inverted() @ world[node]
        ax = axes[node]
        local_axis = fr.godot_dir(ax["axis_world_src"])
        e["openrc_role"] = "articulation"
        e["openrc_source_ctrl"] = ascii_slug(ctrl)
        e["openrc_local_axis"] = rnd(local_axis)
        e["openrc_value_unit"] = "deg"
        if travel:
            e["openrc_travel_deg"] = list(travel)
        nodes[node] = e
    root["openrc_asset"] = "rc-blimp-5m"
    root["openrc_frame"] = "Godot: nose -Z, right +X, up +Y, metres; origin on the hull axis"
    root["openrc_scale"] = fr.s
    per_node = {}
    neg = 0
    for w in works:
        w.matrix_world = fr.G @ w.matrix_world
        if w.matrix_world.determinant() < 0:
            neg += 1
        per_node.setdefault(w["openrc_owner"], []).append(w)
    out = {}
    for node, ws in per_node.items():
        me = bpy.data.meshes.new(node + "_mesh")
        tgt = bpy.data.objects.new(node + "_mesh", me)
        col.objects.link(tgt)
        tgt.parent = nodes[node]
        tgt.matrix_parent_inverse = Matrix.Identity(4)
        tgt.matrix_basis = Matrix.Identity(4)
        view_update()
        for w in ws:
            for c in w.users_collection:
                c.objects.unlink(w)
            col.objects.link(w)
        with bpy.context.temp_override(active_object=tgt, object=tgt, selected_objects=ws + [tgt],
                                       selected_editable_objects=ws + [tgt]):
            bpy.ops.object.join()
        with bpy.context.temp_override(active_object=tgt, object=tgt):
            bpy.ops.object.material_slot_remove_unused()
        uv = tgt.data.uv_layers.get(BAKE_UV)
        if uv is not None:
            tgt.data.uv_layers.active = uv
            uv.active_render = True
        out[node] = tgt
    report["negative_scale_parts"] = neg
    return nodes, out


def export_glb(path, nodes, meshes):
    bpy.ops.object.select_all(action="DESELECT")
    for o in list(nodes.values()) + list(meshes.values()):
        o.select_set(True)
    bpy.context.view_layer.objects.active = nodes[ROOT_NODE]
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    opts = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                export_animations=False, export_cameras=False, export_lights=False, export_extras=True,
                export_draco_mesh_compression_enable=False, export_image_format="AUTO", export_jpeg_quality=JPEG_QUALITY,
                export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
                export_skins=False, export_morph=False, export_attributes=False)
    if "export_vertex_color" in props and "NONE" in [i.identifier for i in props["export_vertex_color"].enum_items]:
        opts["export_vertex_color"] = "NONE"
    opts = {k: v for k, v in opts.items() if k == "filepath" or k in props}
    bpy.ops.export_scene.gltf(**opts)
    return {k: v for k, v in opts.items() if k != "filepath"}


def glb_summary(path):
    gj, nbytes = read_glb_json(path)
    nodes = gj["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        chain = []
        while i is not None:
            chain.append(i)
            i = parent.get(i)
        M = Matrix.Identity(4)
        for j in reversed(chain):
            n = nodes[j]
            t = Vector(n.get("translation", [0, 0, 0]))
            r = n.get("rotation", [0, 0, 0, 1])
            q = Quaternion((r[3], r[0], r[1], r[2]))
            sc = n.get("scale", [1, 1, 1])
            M = M @ Matrix.LocRotScale(t, q, Vector(sc))
        return M

    tris, prims = 0, 0
    bmin = Vector((math.inf,) * 3)
    bmax = Vector((-math.inf,) * 3)
    per_mesh = {}
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        mesh = gj["meshes"][n["mesh"]]
        W = world(i)
        t_mesh = 0
        for p in mesh["primitives"]:
            prims += 1
            acc = gj["accessors"][p["indices"]]
            t_mesh += acc["count"] // 3
            pa = gj["accessors"][p["attributes"]["POSITION"]]
            for cx in (pa["min"][0], pa["max"][0]):
                for cy in (pa["min"][1], pa["max"][1]):
                    for cz in (pa["min"][2], pa["max"][2]):
                        v = W @ Vector((cx, cy, cz))
                        bmin = Vector(map(min, bmin, v))
                        bmax = Vector(map(max, bmax, v))
        per_mesh[n["name"]] = {"triangles": t_mesh, "primitives": len(mesh["primitives"])}
        tris += t_mesh
    images = []
    for im in gj.get("images", []):
        bv = gj["bufferViews"][im["bufferView"]]
        images.append({"name": im.get("name"), "mimeType": im.get("mimeType"), "bytes": bv["byteLength"]})
    return gj, {
        "bytes": nbytes, "sha256": sha256_file(path), "triangles": tris, "primitives_draw_calls": prims,
        "mesh_nodes": len(per_mesh), "per_mesh": per_mesh, "materials": len(gj.get("materials", [])),
        "textures": len(gj.get("textures", [])), "images": images,
        "bounds_godot_m": {"min": rnd(bmin), "max": rnd(bmax)},
        "extensions_used": gj.get("extensionsUsed", []),
        "alpha_modes": sorted({m.get("alphaMode", "OPAQUE") for m in gj.get("materials", [])}),
        "invalid_texcoord_refs": sum(1 for m in gj.get("materials", []) for k, v in m.get("pbrMetallicRoughness", {}).items()
                                     if k.endswith("Texture") and v.get("texCoord", 0) < 0),
    }, world


def glb_nodes_block(gj, world, fr, axes):
    nodes = gj["nodes"]
    names = [n.get("name") for n in nodes]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = names[i]
    out = []
    for node in [ROOT_NODE] + [a[1] for a in ARTICULATIONS]:
        i = names.index(node)
        n = nodes[i]
        entry = {"name": node, "parent": parent.get(i),
                 "rest_translation": rnd(n.get("translation", [0, 0, 0])),
                 "rest_rotation_quat_xyzw": rnd(n.get("rotation", [0, 0, 0, 1]))}
        if node in axes:
            ax = axes[node]
            W = world(i)
            local = fr.godot_dir(ax["axis_world_src"])
            # node frames are parallel to their parents at rest, so local == world at rest; keep the
            # general expression: local = R_world^-1 * world_axis
            wa = local
            la = (W.to_quaternion().inverted() @ wa).normalized()
            entry.update({"source_ctrl": ax["ctrl"], "ctrl_property": ax["prop"],
                          "local_axis": rnd(la), "godot_world_axis": rnd(wa),
                          "travel_deg": list(ax["travel"]) if ax["travel"] else None,
                          "positive_rule": "CTRL value +theta == rotate node by +theta (right-handed) about local_axis"})
        out.append(entry)
    return out


def main_blender(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--skin", required=True, choices=sorted(SKINS))
    ap.add_argument("--out", required=True)
    ap.add_argument("--geometry")
    ap.add_argument("--report")
    ap.add_argument("--work-dir")
    ap.add_argument("--save-derived")
    args = ap.parse_args(argv)
    src = bpy.data.filepath
    if os.path.basename(src) != SKINS[args.skin]:
        raise SystemExit(f"skin {args.skin} expects {SKINS[args.skin]}, got {os.path.basename(src)}")
    work_dir = args.work_dir or tempfile.mkdtemp(prefix="rc_blimp_bake_")
    t_start = time.time()
    report = {"skin": args.skin, "exporter_version": EXPORTER_VERSION,
              "exporter_sha256": sha256_file(os.path.abspath(__file__)),
              "source": {"file": os.path.basename(src), "bytes": os.path.getsize(src), "sha256": sha256_file(src)},
              "blender": bpy.app.version_string}
    rest_pose()
    dg = bpy.context.evaluated_depsgraph_get()
    env = next(o for o in bpy.data.objects if o.name.startswith(ENVELOPE_PREFIX))
    co, _ = world_arrays(env, dg)
    L = float(co[:, 0].max() - co[:, 0].min())
    s = ENVELOPE_LENGTH_M / L
    fr = Frames(s)
    report["scale"] = s
    report["source_envelope_length_m"] = L
    objs = export_candidates(report)
    axes = articulation_axes(report)
    geometry = compute_geometry(fr, axes, objs, report) if args.geometry else None
    rest_pose()
    works = build_work_objects(objs, s, report)
    report["triangles_before_decimation"] = sum(tri_count(w.data) for w in works)
    decimate_dense(works, s, report)
    report["triangles_after_decimation"] = sum(tri_count(w.data) for w in works)
    kinds, bms, results, _copies = bake_materials(works, args.skin, work_dir, report)
    final_images = final_materials(args.skin, works, kinds, bms, results, report)
    nodes, meshes = build_hierarchy(fr, axes, works, report)
    opts = export_glb(os.path.abspath(args.out), nodes, meshes)
    gj, summary, world = glb_summary(args.out)
    if summary["invalid_texcoord_refs"]:
        raise SystemExit("exported material references an unresolved UV map (texCoord < 0)")
    report["export_options"] = opts
    report["glb"] = summary
    report["glb"]["texture_sizes"] = {img.name: list(img.size) for img in final_images.values()}
    report["glb"]["within_triangle_budget"] = summary["triangles"] <= TRI_BUDGET
    report["seconds"] = round(time.time() - t_start, 1)
    if args.geometry:
        geometry_doc = {"schema": "openrc-airship-geometry v1", "asset": "rc-blimp-5m", "skin": args.skin,
                        "frame": ("physics body FRD: x forward (= -X blender), y right (= +Y blender), z down "
                                  "(= -Z blender); metres at 5 m scale; datum = scaled Blender origin on the hull axis"),
                        "source": report["source"],
                        "generator": {"path": "assets/aircraft/rc-blimp-5m/export_blender.py",
                                      "version": EXPORTER_VERSION, "sha256": report["exporter_sha256"]}}
        geometry_doc.update({k: geometry[k] for k in ("scale", "source_envelope_length_m", "envelope_length_m")})
        bmin_g, bmax_g = summary["bounds_godot_m"]["min"], summary["bounds_godot_m"]["max"]
        # Godot (X right, Y up, Z back) -> FRD (x = -Z, y = X, z = -Y)
        pmin = [-bmax_g[2], bmin_g[0], -bmax_g[1]]
        pmax = [-bmin_g[2], bmax_g[0], -bmin_g[1]]
        geometry_doc["bounds_m"] = {"min": rnd(pmin), "max": rnd(pmax), "note": "all exported GLB geometry at rest"}
        for k in ("envelope", "fins", "rotors", "vectors", "gondola", "gear", "collision_witnesses"):
            geometry_doc[k] = geometry[k]
        geometry_doc["glb_nodes"] = glb_nodes_block(gj, world, fr, axes)
        with open(args.geometry, "w", encoding="utf-8", newline="\n") as f:
            json.dump(geometry_doc, f, indent=1, ensure_ascii=False)
            f.write("\n")
    if args.report:
        with open(args.report, "w", encoding="utf-8", newline="\n") as f:
            json.dump(report, f, indent=1, ensure_ascii=False)
            f.write("\n")
    if args.save_derived:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.save_derived), copy=True)
    print("RC_BLIMP_EXPORT_OK", args.skin, summary["triangles"], summary["bytes"], f"{report['seconds']} s")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--assemble-manifest" in argv:
        ap = argparse.ArgumentParser()
        ap.add_argument("--assemble-manifest", required=True)
        ap.add_argument("--zip-dir")
        ap.add_argument("--source-dir", required=True)
        ap.add_argument("--reports", nargs="+", required=True)
        ap.add_argument("--geometries", nargs="+", required=True)
        ap.add_argument("--reference-skin", required=True)
        assemble_manifest(ap.parse_args(argv))
        return
    if not HAVE_BPY:
        raise SystemExit("run inside Blender (see module docstring)")
    main_blender(argv)


if __name__ == "__main__":
    main()
