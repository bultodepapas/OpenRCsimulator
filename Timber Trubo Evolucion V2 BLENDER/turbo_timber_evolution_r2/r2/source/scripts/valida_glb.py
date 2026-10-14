"""
Structural validator for the r2 game GLB (pure Python 3, no Blender needed).

  python3 valida_glb.py <aircraft.glb> [--r1 <r1 aircraft.glb>] [--json <report.json>]

Exit code 0 = every check passes, 1 = at least one check fails, 2 = the file cannot be read.
Checks (delivery spec r2): exact node tree, unique ASCII names without Blender '.001' suffixes, unit node
scales and no reflections, openrc_section on every mesh node and moving pivot with a value from the
vocabulary, root and thrust_frame untagged, rotor not under an engine-tagged node, no cameras / lights /
animations / textures / external buffers / compression extensions, material and surface budgets, and
(with --r1) pivot rest transforms identical to r1 within 0.1 mm / 0.01 deg.
"""
import json, math, struct, sys

SECTIONS = {"core", "wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail", "engine",
            "propeller", "gear", "canopy"}
ROOT = "TurboTimberEvolution"
TREE = {  # node: parent  (delivery spec r2, sec. 2)
    "fuselage_core": ROOT, "wing_left_fixed": ROOT, "wing_right_fixed": ROOT, "stabilizer_fixed": ROOT, "fin_fixed": ROOT,
    "cowl": ROOT, "canopy_glass": ROOT,
    "aileron_left_hinge": ROOT, "aileron_left": "aileron_left_hinge", "aileron_right_hinge": ROOT, "aileron_right": "aileron_right_hinge",
    "flap_left_hinge": ROOT, "flap_left": "flap_left_hinge", "flap_right_hinge": ROOT, "flap_right": "flap_right_hinge",
    "elevator_hinge": ROOT, "elevator": "elevator_hinge", "rudder_hinge": ROOT, "rudder": "rudder_hinge",
    "thrust_frame": ROOT, "propeller_spin": "thrust_frame", "propeller_rotor": "propeller_spin",
    "gear_left_suspension": ROOT, "gear_left_leg": "gear_left_suspension", "wheel_left_axle": "gear_left_suspension", "wheel_left": "wheel_left_axle",
    "gear_right_suspension": ROOT, "gear_right_leg": "gear_right_suspension", "wheel_right_axle": "gear_right_suspension", "wheel_right": "wheel_right_axle",
    "tailwheel_steer": ROOT, "tailwheel_fork": "tailwheel_steer", "tailwheel_axle": "tailwheel_steer", "tailwheel": "tailwheel_axle",
    "gear_cables": ROOT,
}
MOVING = ["aileron_left_hinge", "aileron_right_hinge", "flap_left_hinge", "flap_right_hinge", "elevator_hinge", "rudder_hinge",
          "propeller_spin", "gear_left_suspension", "wheel_left_axle", "gear_right_suspension", "wheel_right_axle",
          "tailwheel_steer", "tailwheel_axle"]
UNTAGGED = [ROOT, "thrust_frame"]
MESHES = [n for n in TREE if not n.endswith(("_hinge", "_axle", "_suspension", "_spin", "_steer")) and n != "thrust_frame"]


def leer(ruta):
    raw = open(ruta, "rb").read()
    mag, ver, ln = struct.unpack_from("<III", raw, 0)
    if mag != 0x46546C67 or ver != 2: raise ValueError("not a glTF 2.0 binary")
    jl, jt = struct.unpack_from("<II", raw, 12)
    if jt != 0x4E4F534A: raise ValueError("first chunk is not JSON")
    gl = json.loads(raw[20:20 + jl])
    bin_len = 0
    if len(raw) > 20 + jl:
        bl, bt = struct.unpack_from("<II", raw, 20 + jl); bin_len = bl if bt == 0x004E4942 else 0
    return gl, bin_len


def qmul(a, b):
    aw, ax, ay, az = a; bw, bx, by, bz = b
    return (aw*bw - ax*bx - ay*by - az*bz, aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx, aw*bz + ax*by - ay*bx + az*bw)


def qang(a, b):  # angle between two rotations (deg), atan2 form (acos loses precision near 0)
    w, x, y, z = qmul((a[0], -a[1], -a[2], -a[3]), b)
    return math.degrees(2*math.atan2(math.sqrt(x*x + y*y + z*z), abs(w)))


def nodo_q(n):  # glTF stores xyzw
    r = n.get("rotation", [0, 0, 0, 1]); return (r[3], r[0], r[1], r[2])


def validar(ruta, r1=None):
    gl, bin_len = leer(ruta)
    C = {}
    def ok(k, cond, det=None): C[k] = {"pass": bool(cond), **({"detail": det} if det is not None else {})}
    nodes = gl.get("nodes", [])
    names = [n.get("name", "") for n in nodes]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []): parent[c] = i
    by = {}
    for i, nm in enumerate(names): by.setdefault(nm, []).append(i)
    dups = sorted(k for k, v in by.items() if len(v) > 1)
    bad_names = [nm for nm in names if (not nm) or any(ord(ch) > 127 for ch in nm) or
                 (len(nm) > 4 and nm[-4] == "." and nm[-3:].isdigit()) or " " in nm]
    ok("names_unique_ascii_no_suffix", not dups and not bad_names, {"duplicates": dups, "invalid": bad_names})
    # scene roots
    sc = gl["scenes"][gl.get("scene", 0)]
    roots = [names[i] for i in sc["nodes"]]
    ok("single_root_TurboTimberEvolution", roots == [ROOT], roots)
    # tree
    got = {names[i]: names[parent[i]] for i in range(len(nodes)) if i in parent}
    missing = sorted(k for k in TREE if k not in by)
    extra = sorted(k for k in names if k not in TREE and k != ROOT)
    wrong = {k: {"parent": got.get(k), "expected": p} for k, p in TREE.items() if k in by and got.get(k) != p}
    ok("hierarchy_matches_spec_tree", not missing and not extra and not wrong, {"missing": missing, "unexpected": extra, "wrong_parent": wrong})
    # meshes on the right nodes
    with_mesh = sorted(names[i] for i, n in enumerate(nodes) if "mesh" in n)
    ok("mesh_nodes_match_spec", with_mesh == sorted(MESHES), {"mesh_nodes": with_mesh, "expected": sorted(MESHES)})
    # transforms
    sc_bad, refl, notnorm = [], [], []
    for i, n in enumerate(nodes):
        if "matrix" in n: sc_bad.append(names[i] + " (matrix)")
        s = n.get("scale", [1, 1, 1])
        if any(abs(x - 1) > 1e-6 for x in s): sc_bad.append(names[i])
        if s[0]*s[1]*s[2] < 0: refl.append(names[i])
        q = n.get("rotation", [0, 0, 0, 1])
        if abs(math.sqrt(sum(x*x for x in q)) - 1) > 1e-5: notnorm.append(names[i])
    ok("node_scales_unit", not sc_bad, sc_bad); ok("no_reflections", not refl, refl); ok("rotations_normalised", not notnorm, notnorm)
    root_i = by.get(ROOT, [None])[0]
    if root_i is not None:
        rn = nodes[root_i]
        ident = all(abs(a - b) < 1e-9 for a, b in zip(rn.get("translation", [0, 0, 0]), [0, 0, 0])) and \
            all(abs(a - b) < 1e-9 for a, b in zip(rn.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1]))
        ok("root_identity_D0", ident, {k: rn.get(k) for k in ("translation", "rotation", "scale")})
    # sections
    sec = {nm: (nodes[i].get("extras") or {}).get("openrc_section") for nm, ii in by.items() for i in ii[:1]}
    need = [k for k in MESHES + MOVING if k in by]
    miss_tag = sorted(k for k in need if sec.get(k) is None)
    bad_tag = {k: sec[k] for k in need if sec.get(k) is not None and (not isinstance(sec[k], str) or sec[k] not in SECTIONS)}
    tagged_untag = {k: sec.get(k) for k in UNTAGGED if sec.get(k) is not None}
    ok("openrc_section_present", not miss_tag, miss_tag)
    ok("openrc_section_valid", not bad_tag, bad_tag)
    ok("root_and_thrust_frame_untagged", not tagged_untag, tagged_untag)
    # one section per mesh node: a mesh's primitives all belong to that node, so a mesh shared by two nodes would weld
    mesh_users = {}
    for i, n in enumerate(nodes):
        if "mesh" in n: mesh_users.setdefault(n["mesh"], []).append(names[i])
    shared = {k: v for k, v in mesh_users.items() if len(v) > 1}
    ok("one_section_per_mesh", not shared, shared)
    # rotor must not be under an engine-tagged node
    def ancestors(nm):
        out, i = [], by[nm][0]
        while i in parent: i = parent[i]; out.append(names[i])
        return out
    if "propeller_rotor" in by:
        eng = [a for a in ancestors("propeller_rotor") if sec.get(a) == "engine"]
        ok("rotor_not_under_engine_tag", not eng, eng)
    # content restrictions
    ok("no_cameras", not gl.get("cameras")); ok("no_lights", "KHR_lights_punctual" not in json.dumps(gl.get("extensions", {})))
    ok("no_animations", not gl.get("animations"), len(gl.get("animations", [])))
    ok("no_textures_or_images", not gl.get("textures") and not gl.get("images"))
    ok("self_contained_buffers", all("uri" not in b for b in gl.get("buffers", [])) and bin_len > 0)
    comp = sorted(set(gl.get("extensionsUsed", [])) & {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization"})
    ok("no_compression", not comp, comp)
    mats = [m.get("name") for m in gl.get("materials", [])]
    ok("materials_le_10", len(mats) <= 10, mats)
    ok("materials_unique", len(set(mats)) == len(mats), mats)
    # counts
    acc = gl.get("accessors", [])
    tri, surf = {}, {}
    for i, n in enumerate(nodes):
        if "mesh" not in n: continue
        prims = gl["meshes"][n["mesh"]]["primitives"]
        surf[names[i]] = len(prims)
        tri[names[i]] = sum(acc[p["indices"]]["count"]//3 if "indices" in p else acc[p["attributes"]["POSITION"]]["count"]//3 for p in prims)
    T, S = sum(tri.values()), sum(surf.values())
    ok("triangles_le_64k", T <= 64000, T)
    C["surfaces_le_40"] = {"pass": S <= 40, "detail": S, "advisory": True}
    # pivots vs r1
    if r1:
        g1, _ = leer(r1); n1 = {n.get("name"): n for n in g1["nodes"]}
        d = {}
        for k in MOVING + ["thrust_frame"]:
            if k not in by or k not in n1: continue
            a, b = nodes[by[k][0]], n1[k]
            dt = math.dist(a.get("translation", [0, 0, 0]), b.get("translation", [0, 0, 0]))
            dq = qang(nodo_q(a), nodo_q(b))
            d[k] = {"translation_mm": round(dt*1000, 5), "rotation_deg": round(dq, 5)}
        pdiff = {}
        p1 = {}
        for i, n in enumerate(g1["nodes"]):
            for c in n.get("children", []): p1[g1["nodes"][c]["name"]] = n["name"]
        for k in MOVING + ["thrust_frame"]:
            if k in got and p1.get(k) != got.get(k): pdiff[k] = {"r2": got.get(k), "r1": p1.get(k)}
        ok("pivots_match_r1_rest", d and all(v["translation_mm"] < 0.1 and v["rotation_deg"] < 0.01 for v in d.values()) and len(d) == 14, d)
        ok("pivot_parents_match_r1", not pdiff, pdiff)
    fails = [k for k, v in C.items() if not v["pass"] and not v.get("advisory")]
    return {"file": ruta, "checks": C, "triangles": tri, "surfaces": surf, "total_triangles": T, "total_surfaces": S,
            "sections": sec, "failed": fails, "pass": not fails}


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0].startswith("-"): print(__doc__); sys.exit(2)
    r1 = a[a.index("--r1") + 1] if "--r1" in a else None
    try:
        rep = validar(a[0], r1)
    except Exception as e:
        print("ERROR", e); sys.exit(2)
    if "--json" in a: json.dump(rep, open(a[a.index("--json") + 1], "w"), indent=1)
    for k, v in rep["checks"].items(): print(("PASS " if v["pass"] else ("WARN " if v.get("advisory") else "FAIL ")) + k)
    print("RESULT", "PASS" if rep["pass"] else "FAIL " + ", ".join(rep["failed"]))
    sys.exit(0 if rep["pass"] else 1)
