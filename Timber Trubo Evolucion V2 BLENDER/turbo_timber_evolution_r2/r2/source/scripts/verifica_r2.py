"""
r2 verifier: structural validation + Blender re-import consistency, signs, clearance sweeps, hygiene,
demo, section separability; then previews. Exits nonzero if any required check fails.

  python3 verifica_r2.py --pkg <r2 dir> [--glb <file>] [--structure-only] [--no-previews] [--out <json>]
                          [--master-stl <dir of master STLs, sidecar mm>]
(python3 with the bpy 5.2 module; with a Blender binary: blender -b --python verifica_r2.py -- <same args>)

Default output: <pkg>/verification.json and <pkg>/previews/*.png. With --glb a disposable copy can be checked
(used by pruebas_negativas.py); --structure-only stops after the structural and pivot checks.
"""
import sys, os, json, math, struct
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
argv = [a for a in sys.argv[1:] if a != "--"]
# (with a Blender binary the script args follow "--"; plain python3 passes them directly)
def arg(k, d=None): return argv[argv.index(k) + 1] if k in argv else d
PKG = os.path.abspath(arg("--pkg", os.path.join(HERE, "..", "..")))
GLB = os.path.abspath(arg("--glb", os.path.join(PKG, "export", "aircraft.glb")))
R1 = os.path.join(PKG, "source", "inputs", "r1_aircraft.glb")
OUT = arg("--out", os.path.join(PKG, "verification.json"))
SOLO_ESTRUCTURA = "--structure-only" in argv
PREVIEWS = not SOLO_ESTRUCTURA and "--no-previews" not in argv and "--glb" not in argv
MASTER = arg("--master-stl")
import valida_glb as VG

res = {"file": os.path.relpath(GLB, PKG) if GLB.startswith(PKG) else GLB, "checks": {}}
C = res["checks"]
def ok(nombre, cond, detalle=None, advisory=False):
    C[nombre] = {"pass": bool(cond), **({"detail": detalle} if detalle is not None else {}), **({"advisory": True} if advisory else {})}
def terminar():
    fails = [k for k, v in C.items() if not v["pass"] and not v.get("advisory")]
    res["failed"] = fails; res["pass"] = not fails
    json.dump(res, open(OUT, "w"), indent=1, default=str)
    for k, v in C.items(): print(("PASS " if v["pass"] else ("WARN " if v.get("advisory") else "FAIL ")) + k)
    print("RESULT", "PASS" if not fails else "FAIL " + ", ".join(fails))
    sys.exit(0 if not fails else 1)

# ------------------------------------------------------------ 1. structure (pure glTF JSON)
try:
    S = VG.validar(GLB, R1 if os.path.exists(R1) else None)
except Exception as e:
    ok("glb_readable", False, str(e)); terminar()
res["structure"] = {k: v for k, v in S.items() if k != "checks"}
for k, v in S["checks"].items(): C["structure:" + k] = v

import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
REF = json.load(open(os.path.join(PKG, "source", "_export_data.json")))
TOL = 1e-4
res["blender_version"] = bpy.app.version_string
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
bpy.context.view_layer.update()
objs = list(bpy.context.scene.objects)
O = {o.name: o for o in objs}
mallas = [o for o in objs if o.type == 'MESH']
def dev(a, b): return (Vector(a) - Vector(b)).length

# ------------------------------------------------------------ 2. pivots: count, re-import consistency
moving = VG.MOVING
presentes = [n for n in moving if n in O and O[n].type == 'EMPTY']
ok("moving_pivots_13", len(presentes) == 13, {"present": len(presentes), "missing": [n for n in moving if n not in presentes]})
pv, ax_d, q_d = {}, {}, {}
for n, a in REF["pivots"].items():
    o = O.get(n)
    if o is None: continue
    pv[n] = dev(o.matrix_world.translation, a["pivot_m"])
    x = (o.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    ax_d[n] = math.degrees(x.angle(Vector(a["axis"]), 0.0))
    q = o.matrix_basis.to_quaternion(); q0 = Quaternion(a["rest_local_quaternion_wxyz"])
    q_d[n] = math.degrees(q.rotation_difference(q0).angle)
falt = [n for n in REF["pivots"] if n not in O]
ok("reimport_pivot_positions_0p1mm", not falt and max(pv.values(), default=1) < TOL, {"missing": falt, "mm": {k: round(v*1000, 5) for k, v in pv.items()}})
ok("reimport_pivot_axes_0p01deg", not falt and max(ax_d.values(), default=1) < 0.01, {k: round(v, 5) for k, v in ax_d.items()})
ok("reimport_rest_rotation_0p01deg", not falt and max(q_d.values(), default=1) < 0.01, {k: round(v, 5) for k, v in q_d.items()})
ident = [o.name for o in mallas if max(abs(x) for r in (o.matrix_basis - Matrix.Identity(4)) for x in r) > 1e-6]
ok("meshes_identity_under_pivot", not ident, ident)
sc_bad = [o.name for o in objs if any(abs(s - 1) > 1e-6 for s in o.matrix_world.to_scale())]
ok("world_scales_unit", not sc_bad, sc_bad)
ex = {o.name: {k: (o[k] if isinstance(o[k], (int, float, str)) else str(list(o[k])) if hasattr(o[k], "__len__") else str(o[k])) for k in o.keys()}
      for o in objs if o.type == 'EMPTY'}
res["imported_extras"] = ex
ok("articulation_extras_survive", all("articulation" in ex.get(n, {}) and "openrc_section" in ex.get(n, {}) for n in moving),
   {n: sorted(ex.get(n, {})) for n in moving})
mesh_sec = {o.name: o.get("openrc_section") for o in mallas}
ok("mesh_sections_survive_reimport", all(v in VG.SECTIONS for v in mesh_sec.values()) and set(mesh_sec) == set(VG.MESHES), mesh_sec)
if SOLO_ESTRUCTURA: terminar()

# ------------------------------------------------------------ 3. counts, bbox, landmarks
tri = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in mallas}
sup = {o.name: len({p.material_index for p in o.data.polygons}) for o in mallas}
res["mesh_counts"] = {n: {"triangles": tri[n], "surfaces": sup[n], "section": mesh_sec[n]} for n in tri}
ok("reimport_triangles_match", sum(tri.values()) == REF["total_triangles"], {"imported": sum(tri.values()), "exported": REF["total_triangles"]})
ok("reimport_surfaces_match", sum(sup.values()) == REF["total_surfaces"], {"imported": sum(sup.values()), "exported": REF["total_surfaces"]})
T = sum(tri.values())
ok("budget_triangles_target_30_50k", 30000 <= T <= 50000, T, advisory=True)
ok("budget_triangles_le_64k", T <= 64000, T)
ok("budget_surfaces_le_40", sum(sup.values()) <= 40, {"surfaces": sum(sup.values()),
   "reason_if_over": "one glTF primitive per material per section mesh: 20 section meshes are required by the crash split"}, advisory=True)
mats = sorted({s.material.name for o in mallas for s in o.material_slots if s.material})
ok("materials_le_10_shared", len(mats) <= 10 and mats == REF["materials"], mats)
cull = {m.name: m.use_backface_culling for m in bpy.data.materials if m.name in mats}
ok("backface_culling_on", all(cull.values()), cull)
def pts(n): o = O[n]; return [o.matrix_world @ v.co for v in o.data.vertices]
P = [p for o in mallas for p in pts(o.name)]
bb = dict(min=[min(p[i] for p in P) for i in range(3)], max=[max(p[i] for p in P) for i in range(3)])
ok("reimport_bbox_0p1mm", max(abs(bb[k][i] - REF["bbox_export"][k][i]) for k in bb for i in range(3)) < TOL, bb)
wl, wr, prop, rud = pts("wing_left_fixed"), pts("wing_right_fixed"), pts("propeller_rotor"), pts("rudder")
LM = {"left_wingtip": min(wl, key=lambda v: v.x), "right_wingtip": max(wr, key=lambda v: v.x),
      "nose_spinner_tip": max(prop, key=lambda v: v.y), "tail_rudder_trailing_edge": min(rud, key=lambda v: v.y),
      "wing_root_leading_edge": max([v for v in wl + wr if abs(v.x) < 0.003], key=lambda v: v.y),
      "left_main_wheel_center": O["wheel_left_axle"].matrix_world.translation, "right_main_wheel_center": O["wheel_right_axle"].matrix_world.translation,
      "tailwheel_center": O["tailwheel_axle"].matrix_world.translation, "propeller_hub": O["propeller_spin"].matrix_world.translation,
      "left_main_wheel_contact": min(pts("wheel_left"), key=lambda v: v.z), "right_main_wheel_contact": min(pts("wheel_right"), key=lambda v: v.z),
      "tailwheel_contact": min(pts("tailwheel"), key=lambda v: v.z)}
lmd = {k: round(dev(v, REF["landmarks_export"][k])*1000, 5) for k, v in LM.items()}
ok("reimport_landmarks_0p1mm", max(lmd.values()) < 0.1, lmd)
span = LM["right_wingtip"].x - LM["left_wingtip"].x; length = LM["nose_spinner_tip"].y - LM["tail_rudder_trailing_edge"].y
res["dimensions"] = {"span_m": round(span, 5), "length_m": round(length, 5), "r1_span_m": 1.5479, "r1_length_m": 1.1166,
                     "manual_span_m": 1.555, "manual_length_m": 1.040, "rescaled": False}
ok("span_length_consistent_with_r1_1mm", abs(span - 1.5479) < 0.001 and abs(length - 1.1166) < 0.002, res["dimensions"], advisory=True)

# ------------------------------------------------------------ 4. signs (+10 deg moves the part as metadata says)
def rot(n, g, q0=None):
    o = O[n]; o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = (q0 or Quaternion(REF["pivots"][n]["rest_local_quaternion_wxyz"])) @ Quaternion((1, 0, 0), math.radians(g))
def neutro():
    for n in REF["pivots"]:
        if n in O: rot(n, 0)
    bpy.context.view_layer.update()
def desplaz(n, malla, g, punto=None):
    neutro(); piv = O[n]; p0 = piv.matrix_world.translation; ax = piv.matrix_world.to_3x3() @ Vector((1, 0, 0))
    pw = punto if punto is not None else max(pts(malla), key=lambda p: ((p - p0) - ax*(p - p0).dot(ax)).length)
    loc = piv.matrix_world.inverted() @ pw
    rot(n, g); bpy.context.view_layer.update(); p1 = piv.matrix_world @ loc; neutro(); return p1 - pw
W = lambda n: O[n].matrix_world.translation.copy()
neutro()
SIGNOS = {"aileron_left_hinge": ("aileron_left", 2, -1, None, "TE down"), "aileron_right_hinge": ("aileron_right", 2, -1, None, "TE down"),
          "flap_left_hinge": ("flap_left", 2, -1, None, "TE down"), "flap_right_hinge": ("flap_right", 2, -1, None, "TE down"),
          "elevator_hinge": ("elevator", 2, -1, None, "TE down"), "rudder_hinge": ("rudder", 0, 1, None, "TE to the pilot's right"),
          "tailwheel_steer": ("tailwheel_fork", 0, 1, W("tailwheel_axle"), "trailing wheel to the right (follows rudder)"),
          "gear_left_suspension": ("gear_left_leg", 0, -1, W("wheel_left_axle"), "left wheel outboard"),
          "gear_right_suspension": ("gear_right_leg", 0, 1, W("wheel_right_axle"), "right wheel outboard"),
          "wheel_left_axle": ("wheel_left", 1, 1, W("wheel_left_axle") + Vector((0, 0, .05)), "top of tyre forward = forward roll"),
          "wheel_right_axle": ("wheel_right", 1, 1, W("wheel_right_axle") + Vector((0, 0, .05)), "top of tyre forward = forward roll"),
          "tailwheel_axle": ("tailwheel", 1, 1, W("tailwheel_axle") + Vector((0, 0, .01)), "top of tyre forward = forward roll"),
          "propeller_spin": ("propeller_rotor", 0, 1, W("propeller_spin") + Vector((0, 0, .1)), "top blade to the right = clockwise seen from behind")}
sg = {}
for n, (m, comp, s, p, desc) in SIGNOS.items():
    d = desplaz(n, m, 10.0, p)
    sg[n] = {"expected": desc, "displacement_mm_at_plus10deg_blender": [round(c*1000, 2) for c in d], "pass": d[comp]*s > 0}
res["sign_checks"] = sg
ok("positive_directions", all(v["pass"] for v in sg.values()), {k: v["pass"] for k, v in sg.items()})

# ------------------------------------------------------------ 5. clearance sweeps (BVH triangle overlap)
NEI = {"aileron_left": ["wing_left_fixed", "flap_left"], "aileron_right": ["wing_right_fixed", "flap_right"],
       "flap_left": ["wing_left_fixed", "aileron_left", "fuselage_core"], "flap_right": ["wing_right_fixed", "aileron_right", "fuselage_core"],
       "elevator": ["stabilizer_fixed", "fuselage_core", "fin_fixed", "rudder"], "rudder": ["fin_fixed", "stabilizer_fixed", "fuselage_core", "elevator"],
       "tailwheel_fork": ["fuselage_core", "rudder"], "tailwheel": ["fuselage_core", "rudder"],
       "gear_left_leg": ["fuselage_core"], "gear_right_leg": ["fuselage_core"], "wheel_left": ["fuselage_core", "gear_left_leg"],
       "wheel_right": ["fuselage_core", "gear_right_leg"], "propeller_rotor": ["cowl", "fuselage_core"]}
def miembros(n):
    out = []
    def rec(o):
        for c in o.children:
            if c.type == 'MESH': out.append(c.name)
            rec(c)
    rec(O[n]); return out
def bvh(nombres):
    vs, fs = [], []
    for nm in nombres:
        o = O[nm]; mw = o.matrix_world; off = len(vs)
        vs += [mw @ v.co for v in o.data.vertices]; fs += [[off + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(vs, fs, epsilon=0.0)
def embebidas(est, nombres):
    """moving faces that are mounting hardware buried in the static foam at rest (gear wire in its bracket):
    they intersect it or their centre lies inside it. They are excluded from the sweep (hidden either way)."""
    out = set(); i = 0
    for nm in nombres:
        o = O[nm]; mw = o.matrix_world; n3 = mw.to_3x3()
        for p in o.data.polygons:
            c = mw @ p.center; h = est.find_nearest(c, 0.05)
            if h[0] is not None and (c - h[0]).dot(h[1]) < 0: out.add(i)
            i += 1
    return out
EMBED_ZONE = {"gear_left_suspension", "gear_right_suspension", "tailwheel_steer"}   # wire legs held in foam brackets
COUPLED = {"tailwheel_steer": "rudder_hinge"}     # the tailwheel wire is driven by the rudder: swept together
def barrido(n, angulos, otros_pivotes=None):
    mov = miembros(n); vec = sorted({x for m in mov for x in NEI.get(m, []) if x not in mov})
    if n in COUPLED: vec = [v for v in vec if v not in miembros(COUPLED[n])]
    neutro()
    for k, g in (otros_pivotes or {}).items(): rot(k, g)
    bpy.context.view_layer.update()
    est = bvh(vec); base = set(est.overlap(bvh(mov)))
    emb = (embebidas(est, mov) if n in EMBED_ZONE else set()) | {b for a, b in base}
    hits = {}
    for g in angulos:
        rot(n, g)
        if n in COUPLED: rot(COUPLED[n], g)
        bpy.context.view_layer.update()
        nuevos = {(a, b) for a, b in set(est.overlap(bvh(mov))) - base if b not in emb}
        hits[round(g, 2)] = len(nuevos)
    neutro()
    return mov, vec, (len(base), len(emb)), hits
def envolvente(hits):
    a = sorted(hits); pos = [g for g in a if g >= 0]; neg = [g for g in reversed(a) if g <= 0]
    hi = lo = 0.0
    for g in pos:
        if hits[g]: break
        hi = g
    for g in neg:
        if hits[g]: break
        lo = g
    return [lo, hi]
def rango(a, b, paso=1.0, extra=()):
    n = int(round((b - a)/paso)); return sorted(set([round(a + i*paso, 3) for i in range(n + 1)] + [a, b, 0.0] + list(extra)))
SWEEP = {  # node: (authored range, simulator range or None, extra angles)
    "aileron_left_hinge": ([-22, 22], [-34.5, 34.5], ()), "aileron_right_hinge": ([-22, 22], [-34.5, 34.5], ()),
    "elevator_hinge": ([-22, 22], [-17.8, 17.8], ()), "rudder_hinge": ([-30, 30], [-18.2, 18.2], ()),
    "flap_left_hinge": ([0, 40], None, (20.7, 36.6)), "flap_right_hinge": ([0, 40], None, (20.7, 36.6)),
    "tailwheel_steer": ([-30, 30], None, ()), "gear_left_suspension": ([0, 12], None, ()), "gear_right_suspension": ([0, 12], None, ()),
    "propeller_spin": ([0, 360], None, ()), "wheel_left_axle": ([0, 360], None, ()), "wheel_right_axle": ([0, 360], None, ()),
    "tailwheel_axle": ([0, 360], None, ())}
cl = {}
for n, (au, si, extra) in SWEEP.items():
    lo = min(au[0], si[0] if si else au[0]); hi = max(au[1], si[1] if si else au[1])
    paso = 10.0 if hi - lo >= 360 else 1.0
    mov, vec, nb, hits = barrido(n, rango(lo, hi, paso, extra + tuple(au) + (tuple(si) if si else ())))
    env = envolvente(hits)
    inside = lambda r: env[0] <= r[0] + 1e-6 and env[1] >= r[1] - 1e-6
    cl[n] = {"moving": mov, "against": vec, "rest_contact_pairs_ignored": nb[0], "embedded_mount_faces_excluded": nb[1],
             **({"coupled_with": COUPLED[n]} if n in COUPLED else {}), "swept_deg": [lo, hi], "step_deg": paso,
             "clear_envelope_deg": env, "authored_range_deg": au, "authored_clear": inside(au),
             "simulator_range_deg": si, "simulator_clear": inside(si) if si else None,
             "interfering_angles_deg": [g for g, v in hits.items() if v]}
    if extra: cl[n]["steps_checked_deg"] = {str(g): ("clear" if not hits.get(round(g, 2)) else f"{hits[round(g, 2)]} new triangle pairs") for g in extra}
# combined corners: rudder with elevator, rudder with tailwheel (they share the hinge line)
comb = {}
for e in (-22, 22):
    mov, vec, nb, hits = barrido("rudder_hinge", [-30, 30], {"elevator_hinge": e})
    comb[f"rudder_+-30_with_elevator_{e:+d}"] = {str(k): v for k, v in hits.items()}
for t in (-30, 30):
    mov, vec, nb, hits = barrido("rudder_hinge", [t], {"tailwheel_steer": t})
    comb[f"rudder_{t:+d}_with_tailwheel_{t:+d}"] = {str(k): v for k, v in hits.items()}
res["clearance"] = {"method": "Blender BVH triangle-triangle overlap of the moving meshes against their neighbours; "
                              "pairs already touching at rest (hinge-line contacts) and moving faces buried in the static foam at rest (gear wire in its bracket) "
                              "are ignored; tailwheel_steer is swept together with rudder_hinge (the wire is rudder-driven); "
                              "envelope = widest interval around 0 with no new overlap",
                    "per_articulation": cl, "combined_new_pairs": comb,
                    "note": "ranges are reported, not clamped: the GLB carries no limits, the simulator applies its own"}
ok("clearance_authored_ranges", all(v["authored_clear"] for v in cl.values()), {k: v["clear_envelope_deg"] for k, v in cl.items()}, advisory=True)
ok("clearance_sweep_ran", len(cl) == 13, len(cl))

# ------------------------------------------------------------ 6. sections and closures
secs = {}
for o in objs:
    if o.get("openrc_section"): secs.setdefault(o["openrc_section"], []).append(o.name)
res["sections"] = secs
# separability: every section mesh is its own node with its own mesh data and one section tag (checked structurally);
# vertices of different sections may coincide along a seam (outer skin at a cut) but are never shared/welded
from collections import defaultdict
datos_compartidos = defaultdict(list)
for o in mallas: datos_compartidos[o.data.name].append(o.name)
compart = {k: v for k, v in datos_compartidos.items() if len(v) > 1}
grid = defaultdict(set)
for o in mallas:
    for v in o.data.vertices:
        p = o.matrix_world @ v.co; grid[(round(p.x*1e6), round(p.y*1e6), round(p.z*1e6))].add(o.name)
seam = defaultdict(int)
for v in grid.values():
    if len({mesh_sec[n] for n in v}) > 1: seam["|".join(sorted(v))] += 1
ok("sections_separable", not compart and all(isinstance(mesh_sec[o.name], str) for o in mallas),
   {"shared_mesh_data": compart, "coincident_seam_vertices_not_welded": dict(seam)})
JUNTAS = [("wing_left_fixed", "wing_right_fixed"), ("wing_left_fixed", "fuselage_core"), ("wing_right_fixed", "fuselage_core"),
          ("cowl", "fuselage_core"), ("stabilizer_fixed", "fuselage_core"), ("fin_fixed", "fuselage_core"), ("fin_fixed", "stabilizer_fixed")]
def caras_cierre(a, b, d=0.0006):
    arbol = bvh([b]); o = O[a]; mw = o.matrix_world; n3 = mw.to_3x3()
    out = []
    for p in o.data.polygons:
        c = mw @ p.center; h = arbol.find_nearest(c, d)
        if h[0] is not None and h[1].dot((n3 @ p.normal).normalized()) < -0.95: out.append(p.index)
    return out
clos = {}
for a, b in JUNTAS:
    for x, y in ((a, b), (b, a)):
        f = caras_cierre(x, y)
        area = sum(O[x].data.polygons[i].area for i in f)
        gap = []; cont = 0.0
        arbol = bvh([y])
        for i in f:
            c = O[x].matrix_world @ O[x].data.polygons[i].center; h = arbol.find_nearest(c, 0.001)
            if h[0] is not None:
                gap.append(h[3])
                pol = O[x].data.polygons[i]; vs_ = [O[x].matrix_world @ O[x].data.vertices[j].co for j in pol.vertices]
                ms = [c.lerp(q, 0.66) for q in vs_[:3]]          # face-to-face contact only if the whole face touches
                if h[3] < 0.00005 and all((lambda r: r[0] is not None and r[3] < 0.00005)(arbol.find_nearest(m_, 0.001)) for m_ in ms):
                    cont += pol.area*1e6
        clos[f"{x}|{y}"] = {"faces": len(f), "area_cm2": round(area*1e4, 2), "material": sorted({O[x].material_slots[O[x].data.polygons[i].material_index].material.name for i in f}),
                            "separation_mm_min_max": [round(min(gap)*1000, 3), round(max(gap)*1000, 3)] if gap else None,
                            "contact_lt_0p05mm_mm2": round(cont, 1)}
res["closures"] = clos
# a joint is closed if at least one side carries closure faces; fin/stabilizer do not touch (the fin sits on the fuselage
# ahead of the stabilizer slot) and are reported only
junta = {f"{a}|{b}": clos[f"{a}|{b}"]["faces"] + clos[f"{b}|{a}"]["faces"] for a, b in JUNTAS}
NO_CONTACT_OK = {"fin_fixed|stabilizer_fixed", "wing_left_fixed|wing_right_fixed"}   # wing roots meet inside the fuselage saddle
ok("closure_faces_at_joints", all(v > 0 for k, v in junta.items() if k not in NO_CONTACT_OK), junta)
ok("closure_faces_hidden_separation", all(v["contact_lt_0p05mm_mm2"] < 100 for v in clos.values() if v["faces"]),
   {k: {"min_max_mm": v["separation_mm_min_max"], "area_lt_0p05mm_mm2": v["contact_lt_0p05mm_mm2"]} for k, v in clos.items()})

# ------------------------------------------------------------ 7. hygiene and z-fighting
hig = {}
for o in mallas:
    bm = bmesh.new(); bm.from_mesh(o.data); bm.transform(o.matrix_world)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7); bm.faces.ensure_lookup_table()
    cero = sum(1 for f in bm.faces if f.calc_area() < 1e-12)
    claves = defaultdict(int)
    for f in bm.faces: claves[tuple(sorted(v.index for v in f.verts))] += 1
    dup = sum(v - 1 for v in claves.values() if v > 1)
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    hig[o.name] = dict(zero_area_faces=cero, duplicate_faces=dup, non_manifold_edges=nm)
    bm.free()
res["mesh_hygiene"] = hig
ok("no_degenerate_faces", sum(h["zero_area_faces"] for h in hig.values()) == 0, {k: v["zero_area_faces"] for k, v in hig.items() if v["zero_area_faces"]})
ok("no_duplicate_faces", sum(h["duplicate_faces"] for h in hig.values()) == 0, {k: v["duplicate_faces"] for k, v in hig.items() if v["duplicate_faces"]})
ok("non_manifold_edges_reported", True, {k: v["non_manifold_edges"] for k, v in hig.items() if v["non_manifold_edges"]}, advisory=True)
G = defaultdict(list)
for o in mallas:
    mw = o.matrix_world
    for p in o.data.polygons:
        G[o.material_slots[p.material_index].material.name].append(([mw @ o.data.vertices[i].co for i in p.vertices], (mw.to_3x3() @ p.normal).normalized(), p.area))
arb = {}
for m, caras in G.items():
    vs, fs = [], []
    for q, _, _ in caras: fs.append(list(range(len(vs), len(vs) + len(q)))); vs += q
    arb[m] = BVHTree.FromPolygons(vs, fs)
zf = {}
for m, caras in G.items():
    for otro, a in arb.items():
        if otro == m: continue
        n = 0; area = 0.0
        for q, nor, ar in caras:
            if ar < 1e-9: continue
            c = sum(q, Vector())/len(q); ms = [c] + [c.lerp(p, .66) for p in q[:3]]
            hs = [a.ray_cast(s + nor*0.00005, -nor, 0.0001) for s in ms]
            if all(h[0] is not None and h[1].dot(nor) > 0.995 for h in hs): n += 1; area += ar
        if n: zf[f"{m}|{otro}"] = {"faces": n, "area_mm2": round(area*1e6, 2)}
res["coplanar_overlaps"] = zf
azf = sum(v["area_mm2"] for v in zf.values())
ok("no_flicker_coplanar_overlaps", azf < 10.0, {"residual_mm2": round(azf, 2), "pairs": zf, "rule": "same-direction coplanar area of different materials < 10 mm2"})

# ------------------------------------------------------------ 8. demo GLB: one control at a time
demo = os.path.join(PKG, "export", "aircraft_demo.glb")
if os.path.exists(demo) and "--glb" not in argv:
    raw = open(demo, "rb").read(); jl = struct.unpack_from("<I", raw, 12)[0]; gl = json.loads(raw[20:20 + jl]); binc = raw[28 + jl:]
    def datos(ai):
        a = gl["accessors"][ai]; bv = gl["bufferViews"][a["bufferView"]]; off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        k = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        return [struct.unpack_from(f"<{k}f", binc, off + i*4*k) for i in range(a["count"])]
    nombres = [n.get("name") for n in gl["nodes"]]
    act = {}
    for an in gl.get("animations", []):
        for ch in an["channels"]:
            s = an["samplers"][ch["sampler"]]; t = [x[0] for x in datos(s["input"])]; v = datos(s["output"])
            mov = [i for i in range(1, len(v)) if max(abs(a - b) for a, b in zip(v[i], v[i - 1])) > 1e-6]
            if mov: act[nombres[ch["target"]["node"]]] = (t[mov[0] - 1], t[mov[-1]])
    ov = [(a, b) for a in act for b in act if a < b and act[a][0] < act[b][1] - 1e-6 and act[b][0] < act[a][1] - 1e-6]
    res["demo"] = {"file": "export/aircraft_demo.glb", "animations": [a.get("name") for a in gl.get("animations", [])],
                   "active_intervals_s": {k: [round(x, 3) for x in v] for k, v in act.items()}, "overlapping": ov,
                   "cameras": len(gl.get("cameras", [])), "lights": "KHR_lights_punctual" in json.dumps(gl.get("extensions", {}))}
    ok("demo_animates_13_pivots", len(act) == 13, sorted(act))
    ok("demo_one_control_at_a_time", not ov, ov)
if "--glb" in argv: terminar()

# ------------------------------------------------------------ 9. previews
if PREVIEWS:
    import numpy as np
    PREV = os.path.join(PKG, "previews"); os.makedirs(PREV, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'; sh = sc.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True; sh.object_outline_color = (0.1, 0.1, 0.1)
    sh.show_cavity = False; sh.show_shadows = False; sc.display.render_aa = '16'
    sh.background_type = 'VIEWPORT'; sh.background_color = (0.86, 0.88, 0.91)
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.82, 0.84, 0.87)
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
    centro = Vector([(bb["min"][i] + bb["max"][i])/2 for i in range(3)])
    def mira(loc, obj, up=(0, 0, 1)):
        d = (Vector(loc) - Vector(obj)).normalized(); u = Vector(up)
        if abs(d.dot(u)) > 0.999: u = Vector((0, 1, 0))
        x = u.cross(d).normalized(); y = d.cross(x); return Matrix((x, y, d)).transposed().to_quaternion()
    def foto(nombre, loc, obj, ortho=None, lens=50, r=(1400, 900)):
        sc.render.resolution_x, sc.render.resolution_y = r
        cam.location = loc; cam.rotation_mode = 'QUATERNION'; cam.rotation_quaternion = mira(loc, obj)
        if ortho: cam_d.type = 'ORTHO'; cam_d.ortho_scale = ortho
        else: cam_d.type = 'PERSP'; cam_d.lens = lens
        cam_d.clip_end = 50; sc.render.filepath = os.path.join(PREV, nombre + ".png"); bpy.ops.render.render(write_still=True)
        return sc.render.filepath
    c = centro; neutro()
    foto("front", c + Vector((0, 5, 0)), c, ortho=1.75); foto("side_right", c + Vector((5, 0, 0)), c, ortho=1.35)
    foto("top", c + Vector((0, 0, 5)), c, ortho=1.75); foto("underside", c + Vector((0, 0, -5)), c, ortho=1.75)
    foto("three_quarter", c + Vector((2.2, 2.4, 1.3)), c, lens=80); foto("three_quarter_rear", c + Vector((-2.2, -2.6, 1.2)), c, lens=80)
    # control extremes sheet
    from PIL import Image, ImageDraw
    casos = [("neutral", {}), ("ailerons L+22 / R-22", {"aileron_left_hinge": 22, "aileron_right_hinge": -22}),
             ("ailerons sim L+34.5 / R-34.5", {"aileron_left_hinge": 34.5, "aileron_right_hinge": -34.5}),
             ("flaps 20.7", {"flap_left_hinge": 20.7, "flap_right_hinge": 20.7}), ("flaps 36.6", {"flap_left_hinge": 36.6, "flap_right_hinge": 36.6}),
             ("flaps 40", {"flap_left_hinge": 40, "flap_right_hinge": 40}),
             ("elevator +22 (TE down)", {"elevator_hinge": 22}), ("elevator -22 (TE up)", {"elevator_hinge": -22}),
             ("rudder +30 (TE right) + tailwheel +30", {"rudder_hinge": 30, "tailwheel_steer": 30}),
             ("rudder -30 (TE left) + tailwheel -30", {"rudder_hinge": -30, "tailwheel_steer": -30}),
             ("main suspension +12 (outboard)", {"gear_left_suspension": 12, "gear_right_suspension": 12}),
             ("propeller +60 / wheels +90", {"propeller_spin": 60, "wheel_left_axle": 90, "wheel_right_axle": 90, "tailwheel_axle": 90})]
    tiles = []
    for i, (et, aj) in enumerate(casos):
        neutro()
        for n, g in aj.items(): rot(n, g)
        bpy.context.view_layer.update()
        if et.startswith("main"): f = foto(f"_c{i}", c + Vector((0, 3.2, -0.25)), c + Vector((0, 0, -0.12)), ortho=0.8, r=(700, 470))
        else: f = foto(f"_c{i}", c + Vector((-1.6, -2.2, 1.5)), c, lens=78, r=(700, 470))
        im = Image.open(f).convert("RGB"); ImageDraw.Draw(im).text((12, 10), et, fill=(0, 0, 0)); tiles.append(im); os.remove(f)
    neutro()
    sheet = Image.new("RGB", (700*3, 470*4), (255, 255, 255))
    for i, im in enumerate(tiles): sheet.paste(im, ((i % 3)*700, (i//3)*470))
    sheet.save(os.path.join(PREV, "control_extremes.png"))
    # exploded sections with closure faces highlighted (preview-only material, not exported)
    hl = bpy.data.materials.new("closure_highlight"); hl.diffuse_color = (0.0, 0.75, 0.9, 1.0)
    for k, v in clos.items():
        x, y = k.split("|"); idx = caras_cierre(x, y); o = O[x]
        if hl.name not in [m.name for m in o.data.materials if m]: o.data.materials.append(hl)
        j = [m.name if m else None for m in o.data.materials].index(hl.name)
        for i in idx: o.data.polygons[i].material_index = j
    OFF = {"core": (0, 0, 0), "wing_left": (-0.30, 0, 0.16), "wing_right": (0.30, 0, 0.16), "horizontal_tail": (0, -0.22, 0.02),
           "vertical_tail": (0, -0.30, 0.22), "engine": (0, 0.20, 0), "propeller": (0, 0.40, 0), "gear": (0, 0, -0.20), "canopy": (0, 0.03, 0.20)}
    root = O["TurboTimberEvolution"]
    guard = {}
    for ch in root.children:
        s = ch.get("openrc_section") or ("propeller" if ch.name == "thrust_frame" else None)
        if s: guard[ch.name] = ch.location.copy(); ch.location = ch.location + Vector(OFF[s])
    bpy.context.view_layer.update()
    foto("exploded_sections", c + Vector((2.4, 2.6, 1.6)), c, lens=62, r=(1600, 1050))
    foto("exploded_sections_rear", c + Vector((-2.4, -2.6, 1.0)), c, lens=62, r=(1600, 1050))
    for n, l in guard.items(): O[n].location = l
    bpy.context.view_layer.update()
    # master vs game silhouettes (side / top / front), optional: needs the master STLs (CAD sidecar mm)
    if MASTER:
        sh.light = 'FLAT'; sh.color_type = 'SINGLE'; sh.single_color = (0, 0, 0); sh.show_object_outline = False
        sh.background_color = (1, 1, 1); sc.display.render_aa = 'OFF'
        vistas = {"side": (Vector((5, 0, 0)), 1.35), "top": (Vector((0, 0, 5)), 1.75), "front": (Vector((0, 5, 0)), 1.75)}
        def sil(tag):
            out = {}
            for v, (d, s) in vistas.items():
                f = foto(f"_sil_{tag}_{v}", c + d, c, ortho=s, r=(1400, 900)); im = np.asarray(Image.open(f).convert("L")) < 128; os.remove(f); out[v] = im
            return out
        O["gear_cables"].hide_render = True      # regenerated in Blender, not a master CAD part
        game = sil("game")
        for o in mallas: o.hide_render = True
        import mapa_r2 as MP
        CAD2EXP = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))) @ Matrix.Scale(0.001, 4)
        # wing and tail marking layers (0.35-0.85 mm thick in the master) are base colour in the game: compared without them
        partes = sorted({p for _, mm, _ in MP.OBJECTS.values() for _, p, _ in mm} - set(MP.PAINTED_DECALS))
        cargadas = []
        for p in partes:
            f = os.path.join(MASTER, p + ".stl")
            if not os.path.exists(f): continue
            bpy.ops.wm.stl_import(filepath=f); ob = bpy.context.selected_objects[0]; ob.data.transform(CAD2EXP); cargadas.append(ob)
        # the master rest pose has the propeller at its CAD clocking; the game rotor is identical geometry
        master = sil("master")
        resu = {}; tiles = []
        for v in vistas:
            a, b = game[v], master[v]; inter = (a & b).sum(); uni = (a | b).sum()
            def dil(m):
                o = m.copy()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)): o |= np.roll(np.roll(m, dx, 0), dy, 1)
                return o
            beyond = int((a & ~dil(b)).sum() + (b & ~dil(a)).sum())
            px = vistas[v][1]/1400.0
            resu[v] = {"iou": round(float(inter/uni), 5), "game_only_px": int((a & ~b).sum()), "master_only_px": int((b & ~a).sum()),
                       "mismatch_beyond_1px": beyond, "mismatch_beyond_1px_fraction": round(beyond/float(uni), 5), "pixel_mm": round(px*1000, 3)}
            rgb = np.full(a.shape + (3,), 255, np.uint8); rgb[a & b] = (90, 90, 90); rgb[a & ~b] = (230, 30, 30); rgb[b & ~a] = (20, 90, 230)
            im = Image.fromarray(rgb); ImageDraw.Draw(im).text((12, 10), f"{v}: IoU {resu[v]['iou']}  grey both / red game only / blue master only", fill=(0, 0, 0)); tiles.append(im)
        sheet = Image.new("RGB", (1400, 900*3), (255, 255, 255))
        for i, im in enumerate(tiles): sheet.paste(im, (0, 900*i))
        sheet.save(os.path.join(PREV, "silhouette_master_vs_game.png"))
        res["silhouette_master_vs_game"] = {"rule": "pass if under 1 % of the silhouette pixels differ by more than one pixel (about 1 mm); the wing seen edge-on from the front is the tightest case (0.3 mm chordal tessellation + <=0.25 mm decimation)", "master": "full-resolution master STL export of the same CAD parts without marking layers (stl_v17, CAD sidecar frame)", "parts_loaded": len(cargadas), "views": resu}
        ok("silhouette_master_vs_game_within_1px", all(v["mismatch_beyond_1px_fraction"] < 0.01 for v in resu.values()), resu)
    res["previews"] = sorted(f for f in os.listdir(PREV) if f.endswith(".png"))
terminar()
