"""
Verificacion de ida y vuelta (round trip) del GLB de juego + vistas previas con luz plana.

  python3 verifica_glb.py --pkg <paquete>

1. Escena limpia de Blender, importa export/aircraft.glb y compara con _export_data.json (lo medido
   antes de exportar): jerarquia, materiales, conteo de triangulos/superficies, caja envolvente,
   landmarks, pivotes, ejes, pose neutra (mallas con transformacion identidad bajo su pivote y
   pivotes en su orientacion de reposo).
2. Higiene de malla sobre lo importado: caras de area nula, caras duplicadas, aristas no-manifold,
   normales inconsistentes, superficies coplanares superpuestas de distinto material (z-fighting).
3. Importa export/aircraft_demo.glb y comprueba que trae la animacion de referencia.
4. Vistas previas (Workbench, luz de estudio plana, colores de material): frente, lado, arriba, abajo,
   3/4, y una hoja de extremos de mando (+max / -max de cada articulacion).
Escribe <pkg>/previews/*.png y <pkg>/verification.json
"""
import bpy, bmesh, math, json, os, sys
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

BASE = os.path.dirname(os.path.abspath(__file__))
PKG = sys.argv[sys.argv.index("--pkg") + 1]
REF = json.load(open(os.path.join(BASE, "_export_data.json")))
PREV = os.path.join(PKG, "previews"); os.makedirs(PREV, exist_ok=True)
TOL = 1e-4      # 0.1 mm

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(PKG, "export", "aircraft.glb"))
bpy.context.view_layer.update()
objs = list(bpy.context.scene.objects)
mallas = [o for o in objs if o.type == 'MESH']
res = {"file": "export/aircraft.glb", "blender_version": bpy.app.version_string, "checks": {}}
C = res["checks"]

def ok(nombre, cond, detalle=None):
    C[nombre] = {"pass": bool(cond), **({"detail": detalle} if detalle is not None else {})}

# ---- jerarquia ----
jer = {o.name: (o.parent.name if o.parent else None) for o in objs}
res["hierarchy"] = jer
esperado = {k: v["parent"] for k, v in REF["articulations"].items()}
faltan = [k for k in esperado if k not in jer]
padres_mal = {k: (jer.get(k), p) for k, p in esperado.items() if k in jer and jer[k] != p}
ok("hierarchy_pivots_present", not faltan, faltan)
ok("hierarchy_parents_match", not padres_mal, padres_mal)
malla_padre = {o.name: o.parent.name if o.parent else None for o in mallas}
res["mesh_parent"] = malla_padre

# ---- materiales y conteos ----
mats = sorted({s.material.name for o in mallas for s in o.material_slots if s.material})
res["materials"] = mats
ok("materials_match", mats == sorted({m for c in REF["mesh_counts"].values() for m in c["materials"]}), mats)
tri = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in mallas}
sup = {o.name: len({p.material_index for p in o.data.polygons}) for o in mallas}
ok("triangles_match", sum(tri.values()) == REF["total_triangles"], {"imported": sum(tri.values()), "exported": REF["total_triangles"]})
ok("surfaces_match", sum(sup.values()) == REF["total_surfaces"], {"imported": sum(sup.values()), "exported": REF["total_surfaces"]})
ok("budget_triangles_le_100k", sum(tri.values()) <= 100000, sum(tri.values()))
ok("budget_surfaces_le_40", sum(sup.values()) <= 40, sum(sup.values()))
res["mesh_counts"] = {n: {"triangles": tri[n], "surfaces": sup[n]} for n in tri}

# ---- caja envolvente y landmarks ----
P = [o.matrix_world @ v.co for o in mallas for v in o.data.vertices]
bb = dict(min=[min(p[i] for p in P) for i in range(3)], max=[max(p[i] for p in P) for i in range(3)])
d_bb = max(abs(bb[k][i] - REF["bbox_export"][k][i]) for k in bb for i in range(3))
ok("bbox_match_0p1mm", d_bb < TOL, {"max_dev_m": d_bb, "imported": bb})
def dev(a, b): return (Vector(a) - Vector(b)).length
lm = {}
for k, n in (("left_main_wheel_center", "wheel_left_axle"), ("right_main_wheel_center", "wheel_right_axle"),
             ("tailwheel_center", "tailwheel_axle")):
    lm[k] = dev(bpy.data.objects[n].matrix_world.translation, REF["landmarks_export"][k])
af = [bpy.data.objects["airframe"].matrix_world @ v.co for v in bpy.data.objects["airframe"].data.vertices]
lm["left_wingtip"] = dev(min(af, key=lambda v: v.x), REF["landmarks_export"]["left_wingtip"])
lm["right_wingtip"] = dev(max(af, key=lambda v: v.x), REF["landmarks_export"]["right_wingtip"])
pr = [bpy.data.objects["propeller_rotor"].matrix_world @ v.co for v in bpy.data.objects["propeller_rotor"].data.vertices]
lm["nose_spinner_tip"] = dev(max(pr, key=lambda v: v.y), REF["landmarks_export"]["nose_spinner_tip"])
ok("landmarks_match_0p1mm", max(lm.values()) < TOL, {k: round(v*1000, 4) for k, v in lm.items()})

# ---- pivotes, ejes y pose neutra ----
pv_dev, eje_dev, q_dev = {}, {}, {}
for k, a in REF["articulations"].items():
    o = bpy.data.objects.get(k)
    if not o: continue
    pv_dev[k] = dev(o.matrix_world.translation, a["pivot_m"])
    x = (o.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    eje_dev[k] = math.degrees(x.angle(Vector(a["axis"])))
    q = o.matrix_basis.to_quaternion(); q0 = Quaternion(REF["rest_local_quaternion_wxyz"][k])
    q_dev[k] = math.degrees(q.rotation_difference(q0).angle)
ok("pivot_positions_match_0p1mm", max(pv_dev.values()) < TOL, {k: round(v*1000, 4) for k, v in pv_dev.items()})
ok("pivot_axes_match_0p01deg", max(eje_dev.values()) < 0.01, {k: round(v, 5) for k, v in eje_dev.items()})
ok("neutral_pose_rest_rotation", max(q_dev.values()) < 0.01, {k: round(v, 5) for k, v in q_dev.items()})
ident = {o.name: max(abs(x) for r in (o.matrix_basis - Matrix.Identity(4)) for x in r) < 1e-6 for o in mallas}
ok("meshes_identity_under_pivot", all(ident.values()), [n for n, v in ident.items() if not v])
ex = {o.name: dict(o.items()) for o in objs if o.type == 'EMPTY' and "articulation" in o.keys()}
ok("articulation_extras_survive", len(ex) == len([k for k in REF["articulations"] if k != "thrust_frame"]),
   sorted(ex))
# ---- signos: +10 grados en cada articulacion mueve la pieza hacia donde dice "positive" ----
def punto_lejano(piv, malla):
    o = bpy.data.objects[malla]; ax = piv.matrix_world.to_3x3() @ Vector((1, 0, 0)); p0 = piv.matrix_world.translation
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    return max(pts, key=lambda p: ((p - p0) - ax*(p - p0).dot(ax)).length)
def mover(n, malla, grados, punto=None):
    piv = bpy.data.objects[n]; q0 = piv.rotation_quaternion.copy(); bpy.context.view_layer.update()
    pw = punto if punto is not None else punto_lejano(piv, malla)
    local = piv.matrix_world.inverted() @ pw
    piv.rotation_quaternion = q0 @ Quaternion((1, 0, 0), math.radians(grados)); bpy.context.view_layer.update()
    p1 = piv.matrix_world @ local
    piv.rotation_quaternion = q0; bpy.context.view_layer.update()
    return p1 - pw
SIGNOS = {  # articulacion: (malla, componente export 0=x 1=y 2=z, signo esperado, punto o None, descripcion)
    "aileron_left_hinge": ("aileron_left", 2, -1, None, "trailing edge moves down"),
    "aileron_right_hinge": ("aileron_right", 2, -1, None, "trailing edge moves down"),
    "flap_left_hinge": ("flap_left", 2, -1, None, "trailing edge moves down"),
    "flap_right_hinge": ("flap_right", 2, -1, None, "trailing edge moves down"),
    "elevator_hinge": ("elevator", 2, -1, None, "trailing edge moves down"),
    "rudder_hinge": ("rudder", 0, 1, None, "trailing edge moves to the pilot's right"),
    "tailwheel_steer": ("tailwheel_fork", 0, 1, bpy.data.objects["tailwheel_axle"].matrix_world.translation.copy(), "trailing wheel moves right"),
    "gear_left_suspension": ("gear_left_leg", 0, -1, bpy.data.objects["wheel_left_axle"].matrix_world.translation.copy(), "left wheel moves outboard (left)"),
    "gear_right_suspension": ("gear_right_leg", 0, 1, bpy.data.objects["wheel_right_axle"].matrix_world.translation.copy(), "right wheel moves outboard (right)"),
    "wheel_left_axle": ("wheel_left", 1, 1, bpy.data.objects["wheel_left_axle"].matrix_world.translation + Vector((0, 0, 0.05)), "top of tire moves forward"),
    "wheel_right_axle": ("wheel_right", 1, 1, bpy.data.objects["wheel_right_axle"].matrix_world.translation + Vector((0, 0, 0.05)), "top of tire moves forward"),
    "tailwheel_axle": ("tailwheel", 1, 1, bpy.data.objects["tailwheel_axle"].matrix_world.translation + Vector((0, 0, 0.01)), "top of tire moves forward"),
    "propeller_spin": ("propeller_rotor", 0, 1, bpy.data.objects["propeller_spin"].matrix_world.translation + Vector((0, 0, 0.1)), "top blade moves right = clockwise seen from behind"),
}
sg = {}
for n, (malla, comp, s, punto, desc) in SIGNOS.items():
    dmov = mover(n, malla, 10.0, punto)
    sg[n] = {"expected": desc, "displacement_export_mm_at_plus10deg": [round(c*1000, 2) for c in dmov], "pass": (dmov[comp]*s) > 0}
res["sign_checks"] = sg
ok("positive_directions_match_metadata", all(x["pass"] for x in sg.values()), {k: v["pass"] for k, v in sg.items()})
res["imported_extras"] = {k: {kk: (vv if isinstance(vv, (int, float, str)) else str(vv)) for kk, vv in v.items()} for k, v in ex.items()}

# ---- higiene de malla ----
hig = {}
for o in mallas:
    bm = bmesh.new(); bm.from_mesh(o.data); bm.transform(o.matrix_world)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)      # glTF parte vertices por normal/UV
    bm.faces.ensure_lookup_table()
    cero = sum(1 for f in bm.faces if f.calc_area() < 1e-12)          # < 1 um2: degenerada
    astilla = sum(1 for f in bm.faces if 1e-12 <= f.calc_area() < 1e-10)
    claves = {}
    for f in bm.faces:
        claves.setdefault(tuple(sorted(v.index for v in f.verts)), []).append(f.index)
    dup = sum(len(v) - 1 for v in claves.values() if len(v) > 1)
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    # normales: cuantas cambian si Blender las recalcula de forma consistente
    n0 = [f.normal.copy() for f in bm.faces]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    inv = sum(1 for f, n in zip(bm.faces, n0) if f.normal.dot(n) < 0)
    hig[o.name] = dict(zero_area_faces=cero, sliver_faces_lt_100um2=astilla, duplicate_faces=dup, non_manifold_edges=nm, inconsistent_normals=inv)
    bm.free()
res["mesh_hygiene"] = hig
ok("no_zero_area_faces", sum(h["zero_area_faces"] for h in hig.values()) == 0)
ok("no_duplicate_faces", sum(h["duplicate_faces"] for h in hig.values()) == 0)
ok("normals_consistent", sum(h["inconsistent_normals"] for h in hig.values()) == 0,
   {k: v["inconsistent_normals"] for k, v in hig.items() if v["inconsistent_normals"]})

# z-fighting: caras casi coplanares y superpuestas (< 0.1 mm) de material distinto
def caras_por_material():
    g = {}
    for o in mallas:
        mw = o.matrix_world
        for p in o.data.polygons:
            m = o.material_slots[p.material_index].material.name
            g.setdefault(m, []).append(([mw @ o.data.vertices[i].co for i in p.vertices], (mw.to_3x3() @ p.normal).normalized(), p.area))
    return g
G = caras_por_material(); arboles = {}
for m, caras in G.items():
    vs, fs = [], []
    for pts, _, _ in caras:
        fs.append(list(range(len(vs), len(vs) + len(pts)))); vs += pts
    arboles[m] = BVHTree.FromPolygons(vs, fs)
zf, contacto = {}, {}
for m, caras in G.items():
    for otro, arbol in arboles.items():
        if otro == m: continue
        n = na = 0; area = area_a = 0.0
        for pts, nor, a in caras:
            if a < 1e-9: continue
            c = sum(pts, Vector()) / len(pts)
            # rayos cortos a traves de la cara (centro + 3 puntos hacia los vertices): solo es superposicion
            # coplanar si TODOS encuentran otra superficie paralela a < 0.05 mm; si solo algunos, las dos
            # superficies se cruzan en angulo (linea de interseccion nitida, no z-fighting)
            muestras = [c] + [c.lerp(p, 0.66) for p in pts[:3]]
            hs = [arbol.ray_cast(q + nor*0.00005, -nor, 0.0001) for q in muestras]
            if any(h[0] is None for h in hs): continue
            if all(h[1].dot(nor) > 0.995 for h in hs): n += 1; area += a            # misma orientacion: z-fighting visible
            elif all(h[1].dot(nor) < -0.995 for h in hs): na += 1; area_a += a      # caras enfrentadas: contacto interno oculto
        if n: zf[f"{m}|{otro}"] = {"faces": n, "area_mm2": round(area*1e6, 2)}
        if na: contacto[f"{m}|{otro}"] = {"faces": na, "area_mm2": round(area_a*1e6, 2)}
res["hidden_back_to_back_contacts"] = contacto
res["coplanar_overlaps"] = zf
area_zf = sum(x["area_mm2"] for x in zf.values())
ok("no_coplanar_overlaps", area_zf < 10.0, {"residual_mm2": round(area_zf, 2), "pairs": zf,
   "rule": "pass if the total same-direction coplanar area is under 10 mm2 (sub-pixel at game distances)"})

# ---- GLB de demostracion ----
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(PKG, "export", "aircraft_demo.glb"))
import struct
raw = open(os.path.join(PKG, "export", "aircraft_demo.glb"), "rb").read()
ln = struct.unpack_from("<I", raw, 12)[0]; gl = json.loads(raw[20:20 + ln])
nodos = [n.get("name") for n in gl["nodes"]]
animaciones = [{"name": a.get("name"), "channels": len(a["channels"]),
                "nodes": sorted({nodos[c["target"]["node"]] for c in a["channels"]})} for a in gl.get("animations", [])]
res["demo"] = {"file": "export/aircraft_demo.glb", "animations": animaciones}
ok("demo_animation_present", len(animaciones) == 1 and len(animaciones[0]["nodes"]) == 13, animaciones)

json.dump(res, open(os.path.join(PKG, "verification.json"), "w"), indent=1, default=str)
print(json.dumps({k: v["pass"] for k, v in C.items()}, indent=1))

# ---------------- vistas previas ----------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(PKG, "export", "aircraft.glb"))
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True; sh.object_outline_color = (0.1, 0.1, 0.1)
sh.show_cavity = False; sh.show_shadows = False; sh.show_specular_highlight = True
sc.display.render_aa = '16'
sh.background_type = 'VIEWPORT'; sh.background_color = (0.86, 0.88, 0.91)
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.82, 0.84, 0.87)
sc.render.film_transparent = False
sc.render.resolution_x, sc.render.resolution_y = 1400, 900
cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
centro = Vector([(REF["bbox_export"]["min"][i] + REF["bbox_export"]["max"][i])/2 for i in range(3)])

def cam_mira(loc, objetivo, up=(0, 0, 1)):
    d = (Vector(loc) - Vector(objetivo)).normalized(); u = Vector(up)
    x = u.cross(d).normalized(); y = d.cross(x)
    return Matrix((x, y, d)).transposed().to_quaternion()

def foto(nombre, loc, objetivo, ortho=None, lens=50, res=(1400, 900)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam.location = loc; cam.rotation_mode = 'QUATERNION'; cam.rotation_quaternion = cam_mira(loc, objetivo)
    if ortho: cam_d.type = 'ORTHO'; cam_d.ortho_scale = ortho
    else: cam_d.type = 'PERSP'; cam_d.lens = lens
    cam_d.clip_end = 50
    sc.render.filepath = os.path.join(PREV, nombre + ".png")
    bpy.ops.render.render(write_still=True)

c = centro
foto("front", c + Vector((0, 5, 0)), c, ortho=1.75)
foto("side_right", c + Vector((5, 0, 0)), c, ortho=1.35)
foto("top", c + Vector((0, 0.001, 5)), c, ortho=1.75)
foto("underside", c + Vector((0, 0.001, -5)), c, ortho=1.75)
foto("three_quarter", c + Vector((2.2, 2.4, 1.3)), c, lens=80)
foto("three_quarter_rear", c + Vector((-2.2, -2.6, 1.2)), c, lens=80)

# hoja de extremos de mando
def girar(n, grados):
    o = bpy.data.objects[n]
    o.rotation_quaternion = Quaternion(REF["rest_local_quaternion_wxyz"][n]) @ Quaternion((1, 0, 0), math.radians(grados))
def neutro():
    for n in REF["articulations"]:
        if n in REF["rest_local_quaternion_wxyz"] and bpy.data.objects.get(n):
            o = bpy.data.objects[n]; o.rotation_mode = 'QUATERNION'
            o.rotation_quaternion = Quaternion(REF["rest_local_quaternion_wxyz"][n])
neutro()
A = {k: v["range_deg"] for k, v in REF["articulations"].items() if v.get("range_deg") and v["range_deg"][0] is not None}
casos = [("neutral", {}),
         ("aileron_left_+22_right_-22 (roll right input)", {"aileron_left_hinge": A["aileron_left_hinge"][1], "aileron_right_hinge": A["aileron_right_hinge"][0]}),
         ("aileron_left_-22_right_+22 (roll left input)", {"aileron_left_hinge": A["aileron_left_hinge"][0], "aileron_right_hinge": A["aileron_right_hinge"][1]}),
         ("flaps_+40", {"flap_left_hinge": 40, "flap_right_hinge": 40}),
         ("elevator_+22 (TE down)", {"elevator_hinge": A["elevator_hinge"][1]}),
         ("elevator_-22 (TE up)", {"elevator_hinge": A["elevator_hinge"][0]}),
         ("rudder_+30 (TE right) + tailwheel", {"rudder_hinge": 30, "tailwheel_steer": 30}),
         ("rudder_-30 (TE left) + tailwheel", {"rudder_hinge": -30, "tailwheel_steer": -30}),
         ("gear_suspension_+12 (both legs)", {"gear_left_suspension": 12, "gear_right_suspension": 12})]
loc34 = c + Vector((-1.6, -2.2, 1.5))
for i, (et, ajustes) in enumerate(casos):
    neutro()
    for n, g in ajustes.items(): girar(n, g)
    bpy.context.view_layer.update()
    if et.startswith("gear"):
        foto(f"_ctrl_{i}", c + Vector((0, 3.2, -0.25)), c + Vector((0, 0, -0.12)), ortho=0.8, res=(900, 600))
    else:
        foto(f"_ctrl_{i}", loc34, c, lens=78, res=(900, 600))
neutro()
json.dump([e for e, _ in casos], open(os.path.join(PREV, "_ctrl_labels.json"), "w"))
print("PREVIEWS OK")
