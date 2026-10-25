"""Put the prop + spinner combos from props_library.blend on the engine (on its O.S. 905 mount):

blender -b engine_se_bancada.blend -P mount_props.py -- --lib props_library.blend --save out.blend
        [--show A] [--check check.json]

Each combo: backplate on the drive hub's prop face (HUB_Y[1] = -61.6), prop on the backplate, washer + nut
(Dubro) or washer + Tru-Turn spinner nut + 10-32 bolt; all parented to ENG_Crankshaft (they turn with it).
The engine's own sample prop / spinner (E61_Prop) and its prop washer / nut are hidden.
Checks: interference with the engine / mount, the prop disc's clearance to everything behind it, the nut's
thread engagement on the 5/16-24 crankshaft thread, the cone's clearance over the nut / bolt.
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(k, d=None):
    return A[A.index(k) + 1] if k in A else d


LIB = opt("--lib")
SAVE = opt("--save")
SHOW = opt("--show", "A")
CHECK = opt("--check")
MM = 0.001
HUB_FACE = -61.6
COMBOS = {"A": ("APC_12x6", "TT_Std_2-1/2", 18.0), "B": ("MA_3B_11x7", "DB_3B_2-3/4", 90.0),
          "C": ("APC_11x7", "DB_2-1/2", 18.0), "D": ("MA_Scimitar_11x7", "TT_Ult_2-1/4", 18.0)}
NAMES = {"A": "COMBO_A_APC12x6_TruTurn2-5", "B": "COMBO_B_MA3B11x7_Dubro2-75", "C": "COMBO_C_APC11x7_Dubro2-5",
         "D": "COMBO_D_MAScimitar11x7_TTUltimate2-25"}


def lc_find(lc, name):
    if lc.collection.name == name:
        return lc
    for c in lc.children:
        r = lc_find(c, name)
        if r:
            return r
    return None


def set_visible(cname, vis):
    c = bpy.data.collections.get(cname)
    if c is None:
        return
    c.hide_render = not vis
    lc = lc_find(bpy.context.view_layer.layer_collection, cname)
    if lc:
        lc.exclude = not vis
        if vis:          # nested collections (prop / spinner / hardware) come in excluded when appended
            stack = list(lc.children)
            while stack:
                x = stack.pop()
                x.exclude = False
                stack += list(x.children)


def append_collections(names):
    with bpy.data.libraries.load(LIB, link=False) as (src, dst):
        dst.collections = [n for n in src.collections if n in names]
    return {c.name: c for c in dst.collections if c}


def crank_angle():
    ck = bpy.data.objects["ENG_Crankshaft"]
    bpy.context.view_layer.update()
    m = ck.matrix_world.to_3x3()
    x = m @ Vector((1, 0, 0))
    return math.degrees(math.atan2(x.z, x.x)), ck


def mount():
    tag = lambda s: s.replace("/", "_")
    want = []
    for ck, (pk, sk, _) in COMBOS.items():
        want += [f"HELICE_{pk}", f"SPINNER_{tag(sk)}", f"HERRAJES_{ck}_{tag(sk)}"]
    cols = append_collections(want)
    top = bpy.data.collections.new("HELICES_Spinners")
    bpy.context.scene.collection.children.link(top)
    ang0, crank = crank_angle()
    for ck, (pk, sk, phase) in COMBOS.items():
        cc = bpy.data.collections.new(NAMES[ck])
        top.children.link(cc)
        emp = bpy.data.objects.new(f"{NAMES[ck]}_Eje", None)
        emp.empty_display_type = "SINGLE_ARROW"
        emp.empty_display_size = 0.03
        cc.objects.link(emp)
        emp.parent = crank
        emp.matrix_parent_inverse = Matrix.Identity(4)
        # crank local frame = engine frame shifted to the axis; blade 0 at `phase` deg seen from the front
        emp.location = (0.0, HUB_FACE * MM, 0.0)
        emp.rotation_euler = (0.0, math.radians(-(phase - ang0)), 0.0)
        for cn in (f"HELICE_{pk}", f"SPINNER_{tag(sk)}", f"HERRAJES_{ck}_{tag(sk)}"):
            c = cols.get(cn)
            if c is None:
                raise RuntimeError("missing " + cn)
            cc.children.link(c)
            for o in c.objects:
                if o.parent is None:          # ROOT_ empties
                    o.parent = emp
                    o.matrix_parent_inverse = Matrix.Identity(4)
                    o.location = (0, 0, 0)
        spin = bpy.data.objects[f"SPIN_{tag(sk)}_Cono"]
        bpy.data.objects[f"ROOT_{pk}"].location = (0, -spin["bp_t"] * MM, 0)
    # the engine's sample prop set and its washer / nut give way to the combos
    set_visible("E61_Prop", False)
    for n in ("ENG_Prop_Washer", "ENG_Prop_Nut"):
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True
            o.hide_viewport = True
    for ck in COMBOS:
        set_visible(NAMES[ck], ck == SHOW)
    bpy.context.view_layer.update()


# ----------------------------------------------------------------------------- checks
def world(ob):
    """World matrix through the parent chain of basis matrices for the combo parts (their collections may be
    excluded from the view layer, where matrix_world is not re-evaluated); the crank is always evaluated."""
    if not ob.name.startswith(("PROP_", "SPIN_", "HW_", "ROOT_", "COMBO_")):
        return ob.matrix_world.copy()
    m = Matrix.Identity(4)
    o = ob
    while o is not None and o.name.startswith(("PROP_", "SPIN_", "HW_", "ROOT_", "COMBO_")):
        m = o.matrix_parent_inverse @ o.matrix_basis @ m if o.parent else o.matrix_basis @ m
        o = o.parent
    return (o.matrix_world @ m) if o is not None else m


def mesh_world(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = world(ob)
    vs = [(mw @ v.co) / MM for v in me.vertices]
    me.calc_loop_triangles()
    ts = [tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    return vs, ts


def engine_objects():
    out = []
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render or o.name.startswith(("PROP_", "SPIN_", "HW_")):
            continue
        if any(c.hide_render for c in o.users_collection):
            continue
        if not o.name.startswith(("ENG_", "CARB_", "MUF_", "BANC_")):
            continue
        out.append(o)
    return out


def check_combo(ck, E, ET):
    pk, sk, _ = COMBOS[ck]
    tag = sk.replace("/", "_")
    for k in COMBOS:
        set_visible(NAMES[k], k == ck)
    bpy.context.view_layer.update()
    combo = [o for o in bpy.data.collections[NAMES[ck]].all_objects if o.type == "MESH"]
    axis_z = bpy.data.objects["ENG_Crankshaft"].matrix_world.translation.z / MM
    rep = {"interference": {}, "contacts": []}
    expected = {("SPIN_", "ENG_Drive_Hub"), ("HW_", "ENG_Crankshaft_Thread")}
    for o in combo:
        v, t = mesh_world(o)
        tr = BVHTree.FromPolygons(v, t)
        lo = Vector([min(p[i] for p in v) for i in range(3)])
        hi = Vector([max(p[i] for p in v) for i in range(3)])
        for n, (ev, et) in E.items():
            if not any(lo[i] - 1 <= max(p[i] for p in ev) and min(p[i] for p in ev) <= hi[i] + 1 for i in range(3)):
                continue
            ov = tr.overlap(ET[n])
            if ov:
                key = f"{o.name} x {n}"
                if any(o.name.startswith(a) and n.startswith(b) for a, b in expected):
                    rep["contacts"].append(key)
                else:
                    rep["interference"][key] = len(ov)
    # prop disc: rearmost blade point per radius vs everything behind it
    prop = bpy.data.objects[f"PROP_{pk}"]
    pv, _ = mesh_world(prop)
    env = {}
    for p in pv:
        rho = math.hypot(p.x, p.z - axis_z)
        b = int(rho)
        env[b] = max(env.get(b, -1e9), p.y)
    R = max(env)
    best = (1e9, None)
    for n, (ev, _) in E.items():
        for p in ev:
            rho = math.hypot(p.x, p.z - axis_z)
            b = int(rho)
            if 16 <= b <= R and b in env and p.y > env[b] - 30:
                d = p.y - env[b]
                if d < best[0]:
                    best = (d, n, round(rho, 1))
    rep["prop_disc_clearance_mm"] = dict(min=round(best[0], 1), part=best[1], radius_mm=best[2], R_mm=R)
    # thread engagement: overlap along Y of the nut's hex with the crankshaft thread
    th = bpy.data.objects["ENG_Crankshaft_Thread"]
    tv, _ = mesh_world(th)
    t_min = min(p.y for p in tv)
    nut = next(o for o in combo if o.name.startswith(f"HW_{ck}_Tuerca") and "Nyloc" not in o.name)
    nv, _ = mesh_world(nut)
    nut_rear = max(p.y for p in nv)
    hex_front = nut_rear - 6.5
    eng = max(0.0, nut_rear - max(hex_front, t_min))
    rep["thread"] = dict(engaged_mm=round(eng, 2), threads=round(eng / (25.4 / 24), 1),
                         nut_rear_y=round(nut_rear, 2), thread_end_y=round(t_min, 2))
    # cone over the nut / bolt: smallest gap
    cone = bpy.data.objects[f"SPIN_{tag}_Cono"]
    cv, ct = mesh_world(cone)
    tc = BVHTree.FromPolygons(cv, ct)
    gaps = {}
    for o in combo:
        if o.name.startswith("HW_"):
            v, _ = mesh_world(o)
            gaps[o.name] = round(min(tc.find_nearest(p)[3] for p in v), 2)
    rep["hardware_to_cone_mm"] = gaps
    # spinner rear edge to the engine front housing (axial gap)
    bp = bpy.data.objects[f"SPIN_{tag}_Placa"]
    bv, _ = mesh_world(bp)
    fh = bpy.data.objects.get("ENG_Front_Housing")
    fv, _ = mesh_world(fh)
    rep["backplate_rear_y"] = round(max(p.y for p in bv), 2)
    rep["front_housing_front_y"] = round(min(p.y for p in fv), 2)
    return rep


def main():
    mount()
    out = {}
    if CHECK:
        eng = engine_objects()
        E = {o.name: mesh_world(o) for o in eng}
        ET = {n: BVHTree.FromPolygons(v, t) for n, (v, t) in E.items()}
        print("engine parts", len(E), sum(len(v) for v, t in E.values()), flush=True)
        for ck in COMBOS:
            out[ck] = check_combo(ck, E, ET)
            print(ck, json.dumps(out[ck])[:600], flush=True)
        for ck in COMBOS:
            set_visible(NAMES[ck], ck == SHOW)
        json.dump(out, open(CHECK, "w"), indent=1)
    if SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=SAVE)
    print("@@JSON@@" + json.dumps({k: v.get("interference") for k, v in out.items()}), flush=True)


main()
