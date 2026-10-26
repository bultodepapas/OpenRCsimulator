"""Verificador de la entrega de juego de la Skywalker X8 (r1; libreas desde r2, skins desde r3).

Sale con codigo 1 si falla cualquier comprobacion obligatoria (0 si todo pasa).

  python verify_game.py source/aircraft_game.blend --glb export/aircraft.glb \
         --metadata metadata.json --json verification.json
  blender -b --factory-startup --python-exit-code 1 --python source/scripts/verify_game.py -- \
         source/aircraft_game.blend --glb export/aircraft.glb
  python verify_game.py source/aircraft_game.blend --glb export/aircraft_bolido.glb --livery bolido \
         --metadata metadata.json        (skin: mismas comprobaciones, imagenes y hash de esa librea)

Tolerancias de consistencia de exportacion: 0.1 mm en posiciones, 0.01 grados en ejes.
"""
import sys, os, json, math, struct, hashlib, argparse, re, itertools
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
ap = argparse.ArgumentParser()
ap.add_argument("blend")
ap.add_argument("--glb")
ap.add_argument("--metadata")
ap.add_argument("--json")
ap.add_argument("--livery", default=S.DEFAULT_LIVERY)
ap.add_argument("--parity-ref", help="GLB de la skin por defecto para la paridad del fuselaje "
                "(por defecto <paquete>/export/aircraft.glb cuando --livery no es la de por defecto)")
A = ap.parse_args(argv)
LIV_IMAGES = S.livery_images(A.livery)

POS_TOL = 1e-4          # 0.1 mm
ANG_TOL = 0.01          # grados
RESULT = dict(blend=os.path.basename(A.blend), livery=A.livery, checks=[], mandatory_failed=[],
              warnings=[])


def check(cid, ok, detail="", mandatory=True, data=None):
    rec = dict(id=cid, ok=bool(ok), mandatory=mandatory, detail=detail)
    if data is not None:
        rec["data"] = data
    RESULT["checks"].append(rec)
    if not ok:
        (RESULT["mandatory_failed"] if mandatory else RESULT["warnings"]).append(cid)
    print(f"[{'OK ' if ok else ('FALLA' if mandatory else 'AVISO')}] {cid}: {detail}")
    return ok


def finish():
    RESULT["passed"] = not RESULT["mandatory_failed"]
    if A.json:
        with open(A.json, "w") as f:
            json.dump(RESULT, f, indent=1, default=str)
    print("RESULTADO:", "TODO OK" if RESULT["passed"] else f"FALLA {RESULT['mandatory_failed']}")
    sys.exit(0 if RESULT["passed"] else 1)


bpy.ops.wm.open_mainfile(filepath=os.path.abspath(A.blend))
sc = bpy.context.scene
sc.frame_set(1)
ob = bpy.data.objects

# --------------------------------------------------------------------------------------- A
coll = bpy.data.collections.get(S.EXPORT_COLLECTION)
if not check("A1_export_collection", coll is not None, S.EXPORT_COLLECTION):
    finish()
stray = [o.name for o in ob if coll not in o.users_collection]
check("A2_only_export_content", not stray and all(o.type in ("MESH", "EMPTY") for o in ob),
      f"objetos fuera de la coleccion: {stray}; tipos: {sorted({o.type for o in ob})}")
names = [o.name for o in ob]
bad = [n for n in names if not n.isascii() or re.search(r"\.\d{3}$", n)]
check("A3_names_ascii_unique", not bad and len(set(names)) == len(names), f"malos: {bad}")
check("A4_self_contained", len(bpy.data.libraries) == 0 and all(
    im.packed_file for im in bpy.data.images),
    f"bibliotecas {len(bpy.data.libraries)}, imagenes {len(bpy.data.images)}")

# --------------------------------------------------------------------------------------- B
exp = {n: (p, t, s) for n, p, t, s in S.NODES}
missing = [n for n in exp if n not in ob]
extra = [n for n in names if n not in exp]
wrong = [n for n in exp if n in ob and ((ob[n].parent.name if ob[n].parent else None) != exp[n][0]
                                         or ob[n].type != exp[n][1])]
check("B1_hierarchy", not missing and not extra and not wrong,
      f"faltan {missing}, sobran {extra}, padre/tipo mal {wrong}")
tag_err = []
for n, (p, t, sec) in exp.items():
    if n not in ob:
        continue
    v = ob[n].get(S.SECTION_KEY)
    if sec is None and v is not None:
        tag_err.append(f"{n}: no debe llevar etiqueta ({v})")
    if sec is not None and v != sec:
        tag_err.append(f"{n}: {v!r} en vez de {sec!r}")
    if v is not None and v not in S.VOCABULARY:
        tag_err.append(f"{n}: {v!r} fuera del vocabulario")
for o in ob:
    if o.type == "MESH" and o.get(S.SECTION_KEY) not in S.VOCABULARY:
        tag_err.append(f"{o.name}: malla sin seccion valida")
check("B2_section_tags", not tag_err, "; ".join(tag_err) or "todas las mallas y pivotes moviles "
      "llevan una seccion valida; raiz y thrust_frame sin etiqueta")


def desc(o):
    out = []
    for c in o.children:
        out += [c] + desc(c)
    return out


mix = []
for o in ob:
    s0 = o.get(S.SECTION_KEY)
    if s0:
        for d in desc(o):
            if d.get(S.SECTION_KEY) not in (None, s0):
                mix.append(f"{o.name}>{d.name}")
check("B3_section_subtrees", not mix, f"subarboles mezclados: {mix}" if mix else
      "cada nodo etiquetado solo contiene su propia seccion (secciones como ramas hermanas)")
root = ob.get(S.ROOT)
check("B4_root_identity", root is not None and root.parent is None and
      (root.matrix_world - Matrix.Identity(4)).to_3x3().is_zero if False else
      root is not None and max(abs(a - b) for ra, rb in zip(root.matrix_world, Matrix.Identity(4))
                               for a, b in zip(ra, rb)) < 1e-9,
      "raiz en D0 con traslacion y rotacion nulas y escala 1")
if missing or wrong:
    finish()

# --------------------------------------------------------------------------------------- C
terr = []
for o in ob:
    if max(abs(a - b) for ra, rb in zip(o.matrix_parent_inverse, Matrix.Identity(4))
           for a, b in zip(ra, rb)) > 1e-9:
        terr.append(f"{o.name}: inversa de padre no identidad")
    m3 = o.matrix_basis.to_3x3()
    sc_ = o.matrix_basis.to_scale()
    if max(abs(v - 1) for v in sc_) > 1e-6:
        terr.append(f"{o.name}: escala {tuple(round(v, 6) for v in sc_)}")
    if m3.determinant() <= 0:
        terr.append(f"{o.name}: reflexion")
    if max(abs(a - b) for ra, rb in zip(m3 @ m3.transposed(), Matrix.Identity(3))
           for a, b in zip(ra, rb)) > 1e-6:
        terr.append(f"{o.name}: cizalla")
check("C1_transforms", not terr, "; ".join(terr) or "escalas (1,1,1), sin reflexion ni cizalla")

# --------------------------------------------------------------------------------------- D/E/F
REST = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}


def pose(**ang):
    for n, m in REST.items():
        ob[n].matrix_basis = m @ Matrix.Rotation(math.radians(ang.get(n, 0.0)), 4, "X")
    bpy.context.view_layer.update()


def world_verts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def bvh(o):
    me = o.data
    me.calc_loop_triangles()
    mw = o.matrix_world
    v = [mw @ p.co for p in me.vertices]
    return BVHTree.FromPolygons(v, [tuple(t.vertices) for t in me.loop_triangles])


def axis_world(n):
    return (ob[n].matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()


pose()
dir_err = []
for lr in ("left", "right"):
    piv, el = ob[f"elevon_{lr}_hinge"], ob[f"elevon_{lr}"]
    o_ = piv.matrix_world.translation
    ax = axis_world(piv.name)
    vs = world_verts(el)
    dist = [((p - o_) - ax * (p - o_).dot(ax)).length for p in vs]
    dmax = max(dist)
    te = [i for i, d in enumerate(dist) if d > 0.9 * dmax]
    z0 = sum(vs[i].z for i in te) / len(te)
    pose(**{piv.name: 10.0})
    vs1 = world_verts(el)
    z1 = sum(vs1[i].z for i in te) / len(te)
    if not z1 < z0 - 1e-3:
        dir_err.append(f"elevon_{lr}: +10 grados no baja el borde de salida ({z0:.4f}->{z1:.4f})")
    pose()
for lr in ("left", "right"):
    piv, dr = ob[f"camera_door_{lr}_hinge"], ob[f"camera_door_{lr}"]
    o_ = piv.matrix_world.translation
    ax = axis_world(piv.name)
    vs = world_verts(dr)
    dist = [((p - o_) - ax * (p - o_).dot(ax)).length for p in vs]
    dmax = max(dist)
    fe = [i for i, d in enumerate(dist) if d > 0.9 * dmax]
    z0 = sum(vs[i].z for i in fe) / len(fe)
    pose(**{piv.name: 30.0})
    vs1 = world_verts(dr)
    z1 = sum(vs1[i].z for i in fe) / len(fe)
    if not z1 < z0 - 1e-3:
        dir_err.append(f"camera_door_{lr}: +30 grados no abre ({z0:.4f}->{z1:.4f})")
    pose()
tax = axis_world("thrust_frame")
ang_thrust = math.degrees(tax.angle(Vector((0, 1, 0))))
if ang_thrust > ANG_TOL:
    dir_err.append(f"eje de empuje a {ang_thrust:.4f} grados de +Y")
# sentido del paso: con giro positivo (eje +X local, hacia la nariz) el angulo atan2(z, y) crece;
# el borde que va delante (angulo mayor dentro de cada pala) debe estar mas adelante en x
rot = ob["propeller_rotor"]
lv = [v.co.copy() for v in rot.data.vertices]
R = max(math.hypot(p.y, p.z) for p in lv)
band = [p for p in lv if 0.45 * R < math.hypot(p.y, p.z) < 0.75 * R]
far = max(band, key=lambda p: math.hypot(p.y, p.z))
th1 = math.atan2(far.z, far.y)
pitch_ok = True
pitch_data = []
for blade in ([p for p in band if math.cos(math.atan2(p.z, p.y) - th1) > 0],
              [p for p in band if math.cos(math.atan2(p.z, p.y) - th1) <= 0]):
    ang = [math.atan2(p.z, p.y) for p in blade]
    cx, cy = sum(math.cos(a) for a in ang), sum(math.sin(a) for a in ang)
    a0_ = math.atan2(cy, cx)
    rel = sorted(((math.remainder(a - a0_, 2 * math.pi), p) for a, p in zip(ang, blade)),
                 key=lambda t: t[0])
    k = max(3, len(rel) // 10)
    lead_ax = sum(p.x for _, p in rel[-k:]) / k
    trail_ax = sum(p.x for _, p in rel[:k]) / k
    pitch_data.append((round(lead_ax * 1000, 2), round(trail_ax * 1000, 2)))
    pitch_ok &= lead_ax > trail_ax
if not pitch_ok:
    dir_err.append("paso de la helice: el borde que va delante no esta adelantado (empujaria hacia atras)")
check("D1_positive_directions", not dir_err, "; ".join(dir_err) or
      "elevones + = borde de salida abajo; compuertas + = abren; eje de empuje +X = nariz; "
      "el paso de las palas empuja hacia la nariz con giro positivo")

meshes = [o for o in ob if o.type == "MESH"]
pose()
static = {o.name: bvh(o) for o in meshes}
neutral = {}
for a, b in itertools.combinations(sorted(static), 2):
    n = len(static[a].overlap(static[b]))
    if n:
        neutral[f"{a}|{b}"] = n
check("E0_neutral_no_interpenetration", not neutral,
      f"pares que se tocan en neutro: {neutral}" if neutral else
      "ningun par de mallas se cruza en la pose neutra")

envelope = {}
for lr in ("left", "right"):
    piv, el = f"elevon_{lr}_hinge", f"elevon_{lr}"
    others = [n for n in static if n != el]
    lo_s, hi_s, step = S.CLEARANCE_SWEEP_ELEVON
    hits = {}
    a = 0.0
    lim = {}
    for direction in (1, -1):
        a = 0.0
        first = None
        while abs(a) <= max(abs(lo_s), hi_s):
            pose(**{piv: a})
            t = bvh(ob[el])
            hit = [n for n in others if t.overlap(static[n])]
            if hit:
                first = (a, hit)
                break
            a += direction * step
        lim[direction] = first
    pose()
    up = lim[1][0] - step if lim[1] else hi_s
    dn = lim[-1][0] + step if lim[-1] else lo_s
    envelope[el] = dict(clear_deg=[dn, up], step_deg=step,
                        first_contact_positive=lim[1], first_contact_negative=lim[-1])
need = S.ELEVON_RANGES["mechanical_full_servo_travel"]
ok_env = all(e["clear_deg"][0] <= need[0] and e["clear_deg"][1] >= need[1] for e in envelope.values())
check("E1_elevon_clearance", ok_env, f"barrido de {S.CLEARANCE_SWEEP_ELEVON[0]} a "
      f"{S.CLEARANCE_SWEEP_ELEVON[1]} grados; libre: " + ", ".join(
          f"{k} {v['clear_deg']}" for k, v in envelope.items()) + f"; requerido {need}",
      data=envelope)
door_hits = {}
for a in range(0, int(S.DOOR_RANGE[1]) + 1, 5):
    for lr in ("left", "right"):
        piv, dr = f"camera_door_{lr}_hinge", f"camera_door_{lr}"
        pose(**{piv: float(a)})
        t = bvh(ob[dr])
        for n in static:
            if n != dr and t.overlap(static[n]):
                door_hits.setdefault(dr, []).append((a, n))
    pose(camera_door_left_hinge=float(a), camera_door_right_hinge=float(a))
    if bvh(ob["camera_door_left"]).overlap(bvh(ob["camera_door_right"])):
        door_hits.setdefault("both", []).append(a)
pose()
check("E2_door_clearance", not door_hits, f"0-{S.DOOR_RANGE[1]:.0f} grados cada 5: "
      + (str(door_hits) if door_hits else "sin cruces"))
prop_hits = []
for a in range(0, 360, 10):
    pose(propeller_spin=float(a))
    t = bvh(rot)
    for n in static:
        if n != rot.name and t.overlap(static[n]):
            prop_hits.append((a, n))
pose()
check("E3_propeller_clearance", not prop_hits, "vuelta completa cada 10 grados: "
      + (str(prop_hits[:6]) if prop_hits else "sin cruces"))

ret = []
for n in REST:
    pose(**{n: 23.0})
    pose()
    if max(abs(a - b) for ra, rb in zip(ob[n].matrix_basis, REST[n]) for a, b in zip(ra, rb)) > 1e-6:
        ret.append(n)
check("F1_return_to_neutral", not ret, f"no vuelven: {ret}" if ret else
      "todos los pivotes vuelven exactamente al reposo guardado")

# --------------------------------------------------------------------------------------- G
qual = {}
qerr = []
for o in meshes:
    o.data.calc_loop_triangles()            # los mismos triangulos que exporta glTF
    degen = sum(1 for t in o.data.loop_triangles if t.area < 1e-10)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    loose_v = sum(1 for v in bm.verts if not v.link_faces)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    # volumen con signo por isla (normales hacia afuera => positivo)
    seen, islands, neg = set(), 0, 0
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        vol = sum(t.verts[0].co.dot(t.verts[1].co.cross(t.verts[2].co)) for t in isl) / 6
        islands += 1
        neg += vol <= 0
    tris = len(bm.faces)
    bm.free()
    mats = sorted({o.data.materials[p.material_index].name for p in o.data.polygons})
    qual[o.name] = dict(triangles=tris, materials=mats, degenerate=degen, loose_verts=loose_v,
                        non_manifold_edges=nonman, islands=islands, inward_islands=neg,
                        smooth_faces=sum(p.use_smooth for p in o.data.polygons),
                        uv_layers=len(o.data.uv_layers))
    if degen or loose_v or neg:
        qerr.append(f"{o.name}: degenerados {degen}, vertices sueltos {loose_v}, islas hacia "
                    f"adentro {neg}")
check("G1_mesh_quality", not qerr, "; ".join(qerr) or
      "sin triangulos degenerados ni vertices sueltos; todas las islas cerradas hacia afuera",
      data=qual)
nm_total = sum(q["non_manifold_edges"] for q in qual.values())
check("G2_closed_shells", nm_total == 0, f"aristas no variedad: {nm_total}", mandatory=False)

# --------------------------------------------------------------------------------------- H/I
mats_used = sorted({m for q in qual.values() for m in q["materials"]})
surfaces = sum(len(q["materials"]) for q in qual.values())
tri_total = sum(q["triangles"] for q in qual.values())
merr = []
for m in bpy.data.materials:
    pb = [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"] if m.node_tree else []
    if len(pb) != 1:
        merr.append(f"{m.name}: no es un Principled unico")
    texn = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"] if m.node_tree else []
    if texn and m.name != S.LIVERY_MATERIAL:
        merr.append(f"{m.name}: textura fuera del atlas")
    if not m.use_backface_culling:
        merr.append(f"{m.name}: sin backface culling")
check("H1_materials_exportable", not merr, "; ".join(merr) or
      f"{len(bpy.data.materials)} materiales Principled con backface culling; solo "
      f"{S.LIVERY_MATERIAL} usa texturas")
# atlas de la libreria: 4 imagenes empaquetadas de 2048, UV en [0,1] en todas las caras pintadas
terr = []
imgs = list(bpy.data.images)
for im in imgs:
    if not im.packed_file:
        terr.append(f"{im.name}: no empaquetada")
    if tuple(im.size) != (S.LIVERY_RES_RUNTIME, S.LIVERY_RES_RUNTIME):
        terr.append(f"{im.name}: {tuple(im.size)}")
if sorted(im.name for im in imgs) != sorted(S.LIVERY_IMAGES):
    terr.append(f"imagenes {sorted(im.name for im in imgs)}")
uv_out = 0
liv_faces = 0
for o in meshes:
    names_ = [mm.name for mm in o.data.materials]
    if S.LIVERY_MATERIAL not in names_:
        continue
    if "UVMap" not in o.data.uv_layers:
        terr.append(f"{o.name}: sin UVMap")
        continue
    k_ = names_.index(S.LIVERY_MATERIAL)
    uvd = o.data.uv_layers["UVMap"].data
    for p in o.data.polygons:
        if p.material_index == k_:
            liv_faces += 1
            for li in p.loop_indices:
                u_, v_ = uvd[li].uv
                if not (-1e-6 <= u_ <= 1 + 1e-6 and -1e-6 <= v_ <= 1 + 1e-6):
                    uv_out += 1
if uv_out:
    terr.append(f"{uv_out} coordenadas UV fuera de [0,1]")
check("H4_livery_textures", not terr, "; ".join(terr) or
      f"{len(imgs)} imagenes empaquetadas de {S.LIVERY_RES_RUNTIME}x{S.LIVERY_RES_RUNTIME}; "
      f"{liv_faces} caras pintadas con UV dentro del atlas")
check("H2_material_budget", len(mats_used) <= 10, f"{len(mats_used)} materiales (objetivo <= 10)",
      mandatory=False)
check("H3_surface_budget", surfaces <= 40, f"{surfaces} superficies malla x material "
      "(objetivo <= 40)", mandatory=False)
check("I1_triangle_ceiling", tri_total <= 100000, f"{tri_total} triangulos (techo 100000)")
check("I2_triangle_target", 30000 <= tri_total <= 50000, f"{tri_total} triangulos "
      "(objetivo 30000-50000)", mandatory=False)
RESULT["counts"] = dict(triangles=tri_total, surfaces=surfaces, materials=len(mats_used),
                        textures=len(bpy.data.images), meshes=len(meshes),
                        nodes=len(names), per_mesh={k: dict(triangles=v["triangles"],
                                                            surfaces=len(v["materials"]))
                                                    for k, v in qual.items()})
RESULT["clearance"] = dict(elevons=envelope, doors_deg=S.DOOR_RANGE)

# guardar las referencias del .blend antes de abrir otra escena
REF = {}
for o in ob:
    REF[o.name] = dict(mw=[list(r) for r in o.matrix_world], parent=o.parent.name if o.parent else None,
                       section=o.get(S.SECTION_KEY), type=o.type)
    if o.type == "MESH":
        vs = world_verts(o)
        REF[o.name]["bbox"] = [[min(v[i] for v in vs) for i in range(3)],
                               [max(v[i] for v in vs) for i in range(3)]]
        REF[o.name]["tris"] = qual[o.name]["triangles"]
        REF[o.name]["mats"] = qual[o.name]["materials"]

# --------------------------------------------------------------------------------------- J
if A.glb:
    raw = open(A.glb, "rb").read()
    sha = hashlib.sha256(raw).hexdigest()
    RESULT["glb"] = dict(file=os.path.basename(A.glb), bytes=len(raw), sha256=sha)
    L = struct.unpack("<I", raw[12:16])[0]
    J = json.loads(raw[20:20 + L])
    jerr = []
    if J["asset"].get("version") != "2.0":
        jerr.append("no es glTF 2.0")
    for k in ("extensionsUsed", "extensionsRequired", "cameras", "animations", "skins"):
        if J.get(k):
            jerr.append(f"contiene {k}: {J.get(k)}")
    nodes = J["nodes"]
    jn = {n["name"]: n for n in nodes}
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[nodes[c]["name"]] = n["name"]
    scene_roots = [nodes[i]["name"] for i in J["scenes"][J.get("scene", 0)]["nodes"]]
    if scene_roots != [S.ROOT]:
        jerr.append(f"raices de escena {scene_roots}")
    for n, (p, t, sec) in exp.items():
        if n not in jn:
            jerr.append(f"falta nodo {n}")
            continue
        if parent.get(n) != p:
            jerr.append(f"{n}: padre {parent.get(n)} en vez de {p}")
        ex = (jn[n].get("extras") or {}).get(S.SECTION_KEY)
        if ex != sec:
            jerr.append(f"{n}: extras {ex!r} en vez de {sec!r}")
        if "scale" in jn[n] and max(abs(v - 1) for v in jn[n]["scale"]) > 1e-6:
            jerr.append(f"{n}: escala {jn[n]['scale']}")
        if (t == "MESH") != ("mesh" in jn[n]):
            jerr.append(f"{n}: tipo")
    if set(jn) - set(exp):
        jerr.append(f"nodos de mas {sorted(set(jn) - set(exp))}")
    prim = sum(len(m["primitives"]) for m in J["meshes"])
    if prim != surfaces:
        jerr.append(f"primitivas {prim} != superficies {surfaces}")
    gl_tris = {}
    for n in nodes:
        if "mesh" in n:
            m = J["meshes"][n["mesh"]]
            gl_tris[n["name"]] = sum(J["accessors"][p["indices"]]["count"] // 3 for p in m["primitives"])
    tri_diff = {k: (v, REF[k]["tris"]) for k, v in gl_tris.items() if v != REF[k]["tris"]}
    if tri_diff:
        jerr.append(f"triangulos distintos {tri_diff}")
    import skin_parity as SP_
    for mat_, slots_ in SP_.texture_bindings(J).items():
        for slot_, v_ in slots_.items():
            if v_["texCoord"] != 0:
                jerr.append(f"{mat_}.{slot_} usa TEXCOORD_{v_['texCoord']} (se espera 0)")
    for m in J.get("materials", []):
        if m.get("doubleSided"):
            jerr.append(f"material de dos caras {m['name']}")
    jimgs = J.get("images", [])
    if len(jimgs) != len(LIV_IMAGES):
        jerr.append(f"{len(jimgs)} imagenes en el GLB")
    want = sorted(os.path.splitext(f)[0] for f in LIV_IMAGES)
    if sorted(im.get("name", "") for im in jimgs) != want:
        jerr.append(f"imagenes {sorted(im.get('name') for im in jimgs)} en vez de {want}")
    for im in jimgs:
        if "uri" in im or "bufferView" not in im or im.get("mimeType") not in ("image/png", "image/jpeg"):
            jerr.append(f"imagen no embebida o de tipo raro: {im.get('name')}")
    lv = [m for m in J.get("materials", []) if m["name"] == S.LIVERY_MATERIAL]
    if not lv:
        jerr.append("falta el material del atlas")
    else:
        lv = lv[0]
        need = dict(baseColorTexture=lv.get("pbrMetallicRoughness", {}).get("baseColorTexture"),
                    metallicRoughnessTexture=lv.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture"),
                    normalTexture=lv.get("normalTexture"), occlusionTexture=lv.get("occlusionTexture"),
                    emissiveTexture=lv.get("emissiveTexture"))
        miss = [k for k, v in need.items() if v is None]
        if miss:
            jerr.append(f"al atlas le falta {miss}")
        if need["metallicRoughnessTexture"] and need["occlusionTexture"] and \
                J["textures"][need["metallicRoughnessTexture"]["index"]]["source"] != \
                J["textures"][need["occlusionTexture"]["index"]]["source"]:
            jerr.append("oclusion y metal/rugosidad no comparten la imagen ORM")
        if lv.get("emissiveFactor", [0, 0, 0]) != [1, 1, 1]:
            jerr.append(f"emissiveFactor {lv.get('emissiveFactor')} (se espera [1,1,1])")
        k_lv = J["materials"].index(lv)
        n_lv = 0
        for m in J["meshes"]:
            for p in m["primitives"]:
                if p.get("material") == k_lv:
                    n_lv += 1
                    falt = {"TEXCOORD_0", "TANGENT", "NORMAL"} - set(p["attributes"])
                    if falt:
                        jerr.append(f"{m['name']}: al atlas le faltan {sorted(falt)}")
        if n_lv != len(S.LIVERY_PARTS):
            jerr.append(f"{n_lv} primitivas con el atlas (se esperan {len(S.LIVERY_PARTS)})")
    check("J1_glb_contract", not jerr, "; ".join(jerr) or
          f"glTF 2.0 sin extensiones, camaras, luces ni animacion; {len(nodes)} nodos con "
          f"jerarquia y extras correctos; {prim} primitivas; triangulos iguales al .blend; "
          f"{len(jimgs)} imagenes embebidas; atlas con color, ORM, normales y emision; "
          f"{len(S.LIVERY_PARTS)} primitivas del atlas con UV, normales y tangentes")
    # reimportar en una escena limpia
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(A.glb))
    bpy.context.view_layer.update()
    ob2 = bpy.data.objects
    rerr = []
    max_dp = max_da = max_db = 0.0
    for n, ref in REF.items():
        o = ob2.get(n)
        if o is None:
            rerr.append(f"falta {n}")
            continue
        if (o.parent.name if o.parent else None) != ref["parent"]:
            rerr.append(f"{n}: padre {o.parent.name if o.parent else None}")
        if o.get(S.SECTION_KEY) != ref["section"]:
            rerr.append(f"{n}: seccion {o.get(S.SECTION_KEY)}")
        mw0 = Matrix(ref["mw"])
        mw1 = o.matrix_world
        max_dp = max(max_dp, (mw0.translation - mw1.translation).length)
        for i in range(3):
            a0 = mw0.to_3x3().col[i].normalized()
            a1 = mw1.to_3x3().col[i].normalized()
            max_da = max(max_da, math.degrees(a0.angle(a1, 0.0)))
        if ref["type"] == "MESH":
            vs = [mw1 @ v.co for v in o.data.vertices]
            bb = [[min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)]]
            max_db = max(max_db, max(abs(a - b) for r0, r1 in zip(bb, ref["bbox"]) for a, b in zip(r0, r1)))
            mats = sorted({o.data.materials[p.material_index].name for p in o.data.polygons})
            if mats != ref["mats"]:
                rerr.append(f"{n}: materiales {mats}")
    if A.metadata:
        Mt = json.load(open(A.metadata))
        LM = Mt.get("landmarks", {})

        def mv(n):
            o = ob2[n]
            return [o.matrix_world @ v.co for v in o.data.vertices]
        allv2 = [v for o in ob2 if o.type == "MESH" for v in mv(o.name)]
        got = {"nose_tip": max(mv("fuselage_core"), key=lambda v: v.y),
               "fuselage_tail": min(mv("fuselage_core"), key=lambda v: v.y),
               "spinner_tip": min(mv("propeller_rotor"), key=lambda v: v.y),
               "wingtip_left": min(mv("wing_left_fixed"), key=lambda v: v.x),
               "wingtip_right": max(mv("wing_right_fixed"), key=lambda v: v.x),
               "winglet_top_left": max(mv("wing_left_fixed"), key=lambda v: v.z),
               "winglet_top_right": max(mv("wing_right_fixed"), key=lambda v: v.z),
               "propeller_hub": ob2["thrust_frame"].matrix_world.translation,
               "lowest_point": min(allv2, key=lambda v: v.z),
               "highest_point": max(allv2, key=lambda v: v.z)}
        lm_dev = {}
        for k, v in got.items():
            if k in LM:
                lm_dev[k] = (Vector(LM[k]["blender_m"]) - v).length
                gd = Vector(LM[k]["godot_m"]) - Vector(S.to_godot(v))
                lm_dev[k] = max(lm_dev[k], gd.length)
        worst = max(lm_dev.values()) if lm_dev else 0.0
        RESULT["landmark_deviation_mm"] = {k: round(v * 1000, 5) for k, v in lm_dev.items()}
        if worst > POS_TOL or len(lm_dev) < len(got):
            rerr.append(f"marcas de metadata.json a {worst*1000:.4f} mm del GLB reimportado")
    if max_dp > POS_TOL or max_db > POS_TOL or max_da > ANG_TOL:
        rerr.append(f"desvio posicion {max_dp*1000:.4f} mm, caja {max_db*1000:.4f} mm, ejes {max_da:.5f} grados")
    check("J2_glb_reimport", not rerr, "; ".join(rerr) or
          f"reimportado en escena limpia: misma jerarquia, secciones y materiales"
          f"{'; marcas de metadata.json en tolerancia' if A.metadata else ''}; desvio maximo "
          f"{max_dp*1000:.4f} mm en pivotes, {max_db*1000:.4f} mm en cajas de malla, "
          f"{max_da:.5f} grados en ejes",
          data=dict(max_pivot_mm=max_dp * 1000, max_bbox_mm=max_db * 1000, max_axis_deg=max_da))

# --------------------------------------------------------------------------------------- L
# paridad del fuselaje de una skin contra la skin por defecto (r4)
if A.glb and A.livery != S.DEFAULT_LIVERY:
    import skin_parity as SP_
    ref_ = A.parity_ref or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(A.blend))),
                                        S.livery_glb(S.DEFAULT_LIVERY))
    if not os.path.exists(ref_):
        check("L1_skin_parity", False, f"falta la referencia {ref_}")
    else:
        pr_ = SP_.compare(ref_, A.glb)
        worst_ = {k: max((v.get(k + "_max_abs_diff") or 0.0) for v in pr_["per_mesh"].values())
                  for k in ("POSITION", "NORMAL", "TEXCOORD_0", "TANGENT")}
        check("L1_skin_parity", pr_["passed"], "; ".join(pr_["errors"][:6]) or
              f"igual a {os.path.basename(ref_)}: {pr_['nodes']} nodos, jerarquia, reposo, extras; "
              f"{pr_['mesh_nodes']} mallas con posiciones, normales, UV0 y tangentes identicas "
              f"(dif. max. {max(worst_.values()):.1e})", data=dict(max_abs_diff=worst_,
                                                                  reference=os.path.basename(ref_)))

# --------------------------------------------------------------------------------------- K
if A.metadata:
    M = json.load(open(A.metadata))
    kerr = []
    for name, art in M.get("articulations", {}).items():
        r = REF.get(name)
        if r is None:
            kerr.append(f"metadatos: pivote {name} no existe")
            continue
        mw = Matrix(r["mw"])
        p = Vector(art["pivot_blender_m"])
        a = Vector(art["axis_blender"])
        if (mw.translation - p).length > POS_TOL:
            kerr.append(f"{name}: pivote a {(mw.translation - p).length*1000:.3f} mm")
        if math.degrees(mw.to_3x3().col[0].normalized().angle(a.normalized(), 0)) > ANG_TOL:
            kerr.append(f"{name}: eje distinto")
    for sec in M.get("sections", []):
        for n in sec["nodes"]:
            if REF.get(n, {}).get("section") != sec["id"]:
                kerr.append(f"seccion {sec['id']}: {n}")
    LV = {l_["id"]: l_ for l_ in M.get("skins", [])}
    glb_ref = LV[A.livery]["glb"] if A.livery in LV else M.get("glb", {})
    if A.glb and glb_ref.get("sha256") not in (None, RESULT["glb"]["sha256"]):
        kerr.append(f"hash del GLB distinto al de metadata.json ({A.livery})")
    pkg_root = os.path.dirname(os.path.abspath(A.metadata))
    for t in [t_ for l_ in LV.values() for t_ in l_.get("runtime_textures", [])]:
        tp = os.path.join(pkg_root, t["file"])
        if not os.path.exists(tp):
            kerr.append(f"falta {t['file']}")
        elif hashlib.sha256(open(tp, "rb").read()).hexdigest() != t["sha256"]:
            kerr.append(f"hash distinto en {t['file']}")
    if M.get("counts", {}).get("textures_per_skin") not in (None, len(S.LIVERY_IMAGES)):
        kerr.append(f"metadata: {M['counts']['textures_per_skin']} texturas por skin")
    if [x["id"] for x in M.get("skins", [])] != list(S.SKIN_ORDER):
        kerr.append("metadata: orden de skins distinto de x8_game_spec.SKIN_ORDER")
    for x in M.get("skins", []):
        if len(x.get("label", "")) > 48 or x["id"] != x["id"].lower() or not x["id"].isascii():
            kerr.append(f"skin {x['id']}: id o etiqueta invalidos")
    check("K1_metadata_consistency", not kerr, "; ".join(kerr) or
          "pivotes, ejes, secciones, hash del GLB y texturas de metadata.json coinciden con el "
          ".blend, el GLB y textures/")

finish()
