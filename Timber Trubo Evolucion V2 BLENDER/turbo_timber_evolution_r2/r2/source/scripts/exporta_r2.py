"""
Turbo Timber Evolution r2 game build for OpenRC Simulator: builds source/aircraft_game.blend and the GLBs.

  python3 exporta_r2.py --pkg <r2 package dir>

Inputs (all inside the package, so this runs from a clean copy without CAD):
  source/stl_juego_r2/         lightweight tessellation of the master (retesela_r2.py output) + _report.json
  source/inputs/ok.json        hinge lines, control throws (CAD cache metadata of master v17)
  source/inputs/escena.json    gear rig, tailwheel, motor/thrust data (master v17)
  source/inputs/r1_aircraft.glb  the accepted r1 file: pivot names, parents and rest transforms are copied from it

Authoring frame (Blender): metres, +X right, +Y forward (nose), +Z up. The glTF exporter (+Y up) writes the
simulator frame: +X right, +Y up, nose toward -Z, i.e. godot = (blender.x, blender.z, -blender.y).
CAD sidecar (mm, X aft, Y right, Z up) -> Blender: (y, -x, z) / 1000.
"""
import bpy, bmesh, math, json, os, sys
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

PKG = os.path.abspath(sys.argv[sys.argv.index("--pkg") + 1])
SRC = os.path.join(PKG, "source")
sys.path.insert(0, os.path.join(SRC, "scripts"))
import mapa_r2 as MP
STL = os.path.join(SRC, "stl_juego_r2")
REP = json.load(open(os.path.join(STL, "_report.json")))
META = json.load(open(os.path.join(SRC, "inputs", "ok.json")))
ESC = json.load(open(os.path.join(SRC, "inputs", "escena.json")))
R1GLB = os.path.join(SRC, "inputs", "r1_aircraft.glb")

CAD2EXP = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))) @ Matrix.Scale(0.001, 4)
def p_cad(p): return (CAD2EXP @ Vector((p[0], p[1], p[2], 1.0))).xyz
def a_sim(v): return [round(v[0], 6), round(v[2], 6), round(-v[1], 6)]

# ------------------------------------------------------------------ r1 pivots (names, parents, rest transforms)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=R1GLB)
bpy.context.view_layer.update()
R1 = {}
for o in bpy.context.scene.objects:
    if o.type == 'EMPTY':
        R1[o.name] = dict(parent=o.parent.name if o.parent else None, basis=o.matrix_basis.copy(), world=o.matrix_world.copy(),
                          extras={k: o[k] for k in o.keys() if not k.startswith("_")})
R1_MESH_PARENT = {o.name: o.parent.name if o.parent else None for o in bpy.context.scene.objects if o.type == 'MESH'}

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
col = bpy.data.collections.new("EXPORT_aircraft"); sc.collection.children.link(col)

# ------------------------------------------------------------------ materials (the ten r1 materials)
def material(nombre, color, rough, metal=0.0, alpha=1.0, emis=0.0):
    m = bpy.data.materials.new(nombre); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal; b.inputs["Alpha"].default_value = alpha
    if emis:
        b.inputs["Emission Color"].default_value = (*color, 1); b.inputs["Emission Strength"].default_value = emis
    if alpha < 1.0:
        try: m.surface_render_method = 'BLENDED'
        except Exception: m.blend_method = 'BLEND'
    m.use_backface_culling = True            # closed shells and outward-only marking sheets: single-sided
    m.diffuse_color = (*color, alpha)
    return m
MAT = {"white": material("white", (0.85, 0.85, 0.84), 0.40), "red": material("red", (0.45, 0.012, 0.008), 0.42),
       "black": material("black", (0.018, 0.018, 0.02), 0.50), "light_grey": material("light_grey", (0.45, 0.46, 0.48), 0.45),
       "dark_grey": material("dark_grey", (0.06, 0.06, 0.065), 0.50), "metal": material("metal", (0.80, 0.80, 0.82), 0.25, metal=1.0),
       "glass": material("glass", (0.20, 0.23, 0.26), 0.08, alpha=0.45), "foam": material("foam", (0.02, 0.02, 0.02), 0.95),
       "light_red": material("light_red", (0.9, 0.05, 0.03), 0.3, emis=3.0), "light_green": material("light_green", (0.1, 0.9, 0.2), 0.3, emis=3.0)}

# ------------------------------------------------------------------ import and clean
def limpiar_bm(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-10], context='FACES_ONLY')
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-10], context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')

def importar(clave, decimate=True):
    bpy.ops.wm.stl_import(filepath=os.path.join(STL, clave + ".stl"))
    o = bpy.context.selected_objects[0]; o.name = "src_" + clave.replace("@", "_")
    o.data.transform(CAD2EXP); o.data.update()
    base = clave.split("@")[0].split("%")[0]
    mat = MP.MATERIAL_OVERRIDE.get(base) or MP.PALETTE[REP["materials_cad"][clave]]
    o.data.materials.clear(); o.data.materials.append(MAT[mat])
    bm = bmesh.new(); bm.from_mesh(o.data); limpiar_bm(bm)
    # OCC writes outward-wound triangles; normals are only recomputed on closed shells (on an open boolean result
    # a recomputation can flip a whole side)
    if all(e.is_manifold for e in bm.edges): bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()
    o["src_part"] = clave
    if decimate and base not in MP.DECALS and len(o.data.polygons) >= DECIMATE_MIN_TRIS: decimar(o, clave)
    return o

def importar_pintado(sustrato, piezas):
    """foam part split in CAD by its markings (base colour, no decal shell): the pieces are imported, the hidden
    walls between pieces are deleted, the pieces are welded into one surface with material borders, and the
    result is decimated with the colour borders locked."""
    objs = [importar(k, decimate=False) for k in ([sustrato] if sustrato in REP["triangles"] else []) + piezas]
    borrar = {}
    for o in objs:
        otros = bvh_de([x for x in objs if x is not o])
        if otros is None: continue
        me = o.data; me.update(); sel = []
        for f in me.polygons:
            h = otros.find_nearest(f.center, 0.00003)
            if h[0] is not None and h[1].dot(f.normal) < -0.95: sel.append(f.index)
        borrar[o.name] = sel
    paredes = 0
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
        sel = [bm.faces[i] for i in borrar.get(o.name, [])]; paredes += len(sel)
        bmesh.ops.delete(bm, geom=sel, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')
        bm.to_mesh(o.data); bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]; bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
    abiertas = sum(1 for e in bm.edges if not e.is_manifold)
    bm.to_mesh(o.data); bm.free()
    o["src_part"] = sustrato
    n0 = len(o.data.polygons)
    if n0 >= DECIMATE_MIN_TRIS: decimar(o, sustrato + " (painted)", bloquear_bordes=True)
    INFORME.setdefault("painted", {})[sustrato] = dict(pieces=piezas, hidden_walls_removed=paredes, open_edges_after_weld=abiertas,
                                                       triangles_before_decimation=n0, triangles=len(o.data.polygons))
    return o

# budget: dense parts are reduced with an edge-collapse decimation. The two-way surface deviation against the
# tessellated master is measured; a ratio is accepted only if it stays under DECIMATE_MAX_DEV (else the next, milder
# ratio is tried, else the part is kept as tessellated). Markings are never decimated.
DECIMATE_RATIOS, DECIMATE_MIN_TRIS, DECIMATE_MAX_DEV = (0.5, 0.7), 600, 0.00025
INFORME_DEC = {}
def borde_material(me):
    """total length of edges between faces of different materials + open edges (m)"""
    bm = bmesh.new(); bm.from_mesh(me); L = 0.0
    for e in bm.edges:
        f = e.link_faces
        if len(f) != 2 or f[0].material_index != f[1].material_index: L += e.calc_length()
    bm.free(); return L

def decimar(o, clave, bloquear_bordes=False):
    bm0 = bmesh.new(); bm0.from_mesh(o.data); ref = BVHTree.FromBMesh(bm0); n0 = len(bm0.faces)
    original = o.data.copy(); intentos = []
    L0 = borde_material(o.data) if bloquear_bordes else None
    for r in DECIMATE_RATIOS:
        m = o.modifiers.new("decimate", 'DECIMATE'); m.decimate_type = 'COLLAPSE'; m.ratio = r; m.use_collapse_triangulate = True
        if bloquear_bordes:
            vg = o.vertex_groups.get("libre") or o.vertex_groups.new(name="libre")
            bmv = bmesh.new(); bmv.from_mesh(o.data)
            fijos = {v.index for e in bmv.edges for v in e.verts
                     if len(e.link_faces) != 2 or e.link_faces[0].material_index != e.link_faces[1].material_index}
            bmv.free()
            vg.add([i for i in range(len(o.data.vertices)) if i not in fijos], 1.0, 'REPLACE')
            m.vertex_group = "libre"; m.vertex_group_factor = 1000.0
        bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier=m.name)
        bm = bmesh.new(); bm.from_mesh(o.data); limpiar_bm(bm); bm.to_mesh(o.data)
        nuevo = BVHTree.FromBMesh(bm)
        d = max(max(ref.find_nearest(v.co)[3] for v in bm.verts), max(nuevo.find_nearest(v.co)[3] for v in bm0.verts))
        intentos.append(dict(ratio=r, triangles=len(bm.faces), max_deviation_mm=round(d*1000, 3))); bm.free()
        borde_ok = True
        if bloquear_bordes:
            L1 = borde_material(o.data); intentos[-1]["border_length_change"] = round(L1/L0 - 1, 4) if L0 else 0
            borde_ok = abs(L1 - L0) <= 0.01*L0
        if d <= DECIMATE_MAX_DEV and borde_ok:
            INFORME_DEC[clave] = dict(triangles_before=n0, triangles_after=len(o.data.polygons), ratio=r, max_deviation_mm=round(d*1000, 3)); break
        o.data = original.copy()
    else:
        INFORME_DEC[clave] = dict(triangles_before=n0, triangles_after=n0, ratio=1.0, max_deviation_mm=0.0, rejected=intentos)
    bm0.free()

def bvh_de(objs):
    vs, fs = [], []
    for o in objs:
        mw = o.matrix_world; off = len(vs)
        vs += [mw @ v.co for v in o.data.vertices]
        fs += [[off + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(vs, fs) if fs else None

INFORME = {"decal_underside_faces_removed": {}, "closure_faces": {}, "decal_offset_mm": {}, "decimation": None}
def preparar_calco(o, sustrato_bvh):
    """keep the visible top of a 0.35 mm marking skin: delete faces that lie on the substrate facing into it,
    then lift the sheet 0.12 mm per priority level so stacked colours never share a plane"""
    bm = bmesh.new(); bm.from_mesh(o.data); bm.normal_update()
    quitar = []
    if sustrato_bvh is not None:
        for f in bm.faces:
            c = f.calc_center_median(); hit = sustrato_bvh.find_nearest(c, 0.0001)
            if hit[0] is not None and hit[1].dot(f.normal) < -0.9: quitar.append(f)
    bmesh.ops.delete(bm, geom=quitar, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')
    bm.normal_update()
    eps = 0.00012*max(1, MP.priority(o["src_part"].split("@")[0]))
    for v in bm.verts: v.co += v.normal*eps
    bm.to_mesh(o.data); bm.free()
    INFORME["decal_underside_faces_removed"][o["src_part"]] = len(quitar)
    INFORME["decal_offset_mm"][o["src_part"]] = round(eps*1000, 3)

CALCO_HOLGURA = 0.0001       # every marking sheet ends at least 0.1 mm above the foam it covers
def asentar_calcos(nombre, sustrato, calcos):
    """the foam and the marking sheet are tessellated independently, so on tight curves (wing leading edge) a foam
    facet can poke through the sheet. Under a sheet only: foam vertices are pulled in and sheet vertices pushed out
    until the sheet is CALCO_HOLGURA above the foam along the foam normal. Movements are reported."""
    mov_s, mov_c = [], []
    for it in range(3):
        bc = bvh_de(calcos); bs = bvh_de(sustrato)
        for o in sustrato:
            o.data.update(); n_s = 0
            for v in o.data.vertices:
                n = v.normal; h = bc.ray_cast(v.co - n*0.002, n, 0.004)
                if h[0] is None or h[1].dot(n) < 0.5: continue      # only a sheet facing the same way (not the far side of a thin TE)
                off = h[3] - 0.002
                if off < CALCO_HOLGURA:
                    d = CALCO_HOLGURA - off; v.co -= n*d; mov_s.append(d); n_s += 1
            o.data.update()
        bs = bvh_de(sustrato)
        for o in calcos:
            o.data.update()
            for v in o.data.vertices:
                h = bs.find_nearest(v.co, 0.003)
                if h[0] is None or h[1].dot(v.normal) < 0.3: continue
                off = (v.co - h[0]).dot(h[1])
                if off < CALCO_HOLGURA:
                    d = CALCO_HOLGURA - off; v.co += h[1]*d; mov_c.append(d)
            o.data.update()
    # residual check: foam face centres and edge midpoints that are still above a sheet covering them
    bc = bvh_de(calcos); malas = 0; muestras = 0
    for o in sustrato:
        me = o.data; me.update()
        pts = [(p.center, p.normal) for p in me.polygons]
        pts += [((me.vertices[e.vertices[0]].co + me.vertices[e.vertices[1]].co)/2,
                 (me.vertices[e.vertices[0]].normal + me.vertices[e.vertices[1]].normal).normalized()) for e in me.edges]
        for c, n in pts:
            h = bc.ray_cast(c - n*0.002, n, 0.004)
            if h[0] is None or h[1].dot(n) < 0.5: continue
            muestras += 1
            if h[3] - 0.002 < 0.00002: malas += 1
    INFORME.setdefault("marking_seating", {})[nombre] = dict(covered_foam_samples=muestras, foam_samples_above_sheet=malas,
        foam_vertices_pulled_in=len(mov_s), foam_max_mm=round(max(mov_s, default=0)*1000, 3),
        sheet_vertices_pushed_out=len(mov_c), sheet_max_mm=round(max(mov_c, default=0)*1000, 3), clearance_mm=CALCO_HOLGURA*1000)

def unir(objs, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1: bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active; o.name = nombre; o.data.name = nombre + "_mesh"
    for k in list(o.keys()): del o[k]
    bm = bmesh.new(); bm.from_mesh(o.data); limpiar_bm(bm); bm.to_mesh(o.data); bm.free()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    for c in o.users_collection: c.objects.unlink(o)
    col.objects.link(o)
    return o

OBJ = {}
for nombre, (sec, miembros, desc) in MP.OBJECTS.items():
    if not miembros: continue
    claves = [m[1] if m[2] is None else f"{m[1]}@{m[2]}" for m in miembros]
    def grupo(k):          # painted pieces "<k>#<marking>" and tessellation chunks "<k>%<id>" of a source part
        return sorted(x for x in REP["triangles"] if x.startswith(k + "#") or x.startswith(k + "%"))
    claves = [k for k in claves if k in REP["triangles"] or grupo(k)]
    objs = [importar_pintado(k, grupo(k)) if grupo(k) else importar(k) for k in claves]
    sustrato = [o for o in objs if o["src_part"].split("@")[0] in MP.SUBSTRATE.get(nombre, [])]
    bv = bvh_de(sustrato)
    calcos = [o for o in objs if o["src_part"].split("@")[0] in MP.DECALS]
    for o in calcos: preparar_calco(o, bv)
    if calcos and sustrato: asentar_calcos(nombre, sustrato, calcos)
    OBJ[nombre] = unir(objs, nombre)
    OBJ[nombre]["openrc_section"] = sec

INFORME["decimation"] = dict(method="Blender Decimate COLLAPSE", ratios_tried=DECIMATE_RATIOS, max_deviation_mm=DECIMATE_MAX_DEV*1000, min_triangles=DECIMATE_MIN_TRIS, parts=INFORME_DEC)

# low-poly cables and springs (rest pose only), as in r1
def cilindro(a, b, r, lados, nombre):
    a, b = Vector(a), Vector(b); d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=lados, radius=r, depth=d.length, location=(a + b)/2)
    o = bpy.context.object; o.name = nombre
    o.rotation_mode = 'QUATERNION'; o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    bpy.context.view_layer.update(); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.materials.append(MAT["metal"]); o["src_part"] = nombre; return o
cables = []
for nom, c in ESC["tren"]["cables"].items():
    F, E = p_cad(c["ojal"]), p_cad(c["anclaje"]); u = (E - F).normalized(); Lw = c["largo_cable"]/1000.0
    cables.append(cilindro(F, F + u*Lw, 0.0006, 6, f"cable_{nom}"))
    cables.append(cilindro(F + u*Lw, E, 0.0040, 10, f"spring_{nom}"))
OBJ["gear_cables"] = unir(cables, "gear_cables"); OBJ["gear_cables"]["openrc_section"] = "gear"

# ------------------------------------------------------------------ closure faces at section joints
# faces of a fixed section that lie on another section's surface (wing roots, cowl joint, tail attachments)
# are the faces a detached piece would show. They are split off, given the plain foam colour (white) and set
# 0.2 mm inside their own piece, so two coincident joint faces never share a plane.
JUNTAS = [("wing_left_fixed", "wing_right_fixed"), ("wing_left_fixed", "fuselage_core"), ("wing_right_fixed", "fuselage_core"),
          ("cowl", "fuselage_core"), ("stabilizer_fixed", "fuselage_core"), ("fin_fixed", "fuselage_core"),
          ("fin_fixed", "stabilizer_fixed")]
def cierres(a, b):
    for x, y in ((a, b), (b, a)):
        o = OBJ[x]; arbol = bvh_de([OBJ[y]])
        bm = bmesh.new(); bm.from_mesh(o.data); bm.normal_update()
        sel = []
        for f in bm.faces:
            hit = arbol.find_nearest(f.calc_center_median(), 0.0003)
            if hit[0] is not None and hit[1].dot(f.normal) < -0.95: sel.append(f)
        if sel:
            res = bmesh.ops.split(bm, geom=sel)
            nuevas = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
            vs = {v for f in nuevas for v in f.verts}
            nf = {}
            for f in nuevas:
                for v in f.verts: nf.setdefault(v, Vector()); nf[v] += f.normal
            for v in vs: v.co -= nf[v].normalized()*0.0002
            idx = list(o.data.materials).index(MAT["white"]) if MAT["white"].name in [m.name for m in o.data.materials] else None
            if idx is None:
                o.data.materials.append(MAT["white"]); idx = len(o.data.materials) - 1
            for f in nuevas: f.material_index = idx
        bm.to_mesh(o.data); bm.free()
        INFORME["closure_faces"][f"{x}|{y}"] = len(sel)
for a, b in JUNTAS: cierres(a, b)

# ------------------------------------------------------------------ hierarchy: r1 pivots, new section meshes
def vacio(nombre, padre, basis, props):
    e = bpy.data.objects.new(nombre, None); col.objects.link(e)
    e.empty_display_type = 'ARROWS'; e.empty_display_size = 0.03
    if padre is not None: e.parent = padre; e.matrix_parent_inverse = Matrix.Identity(4)
    e.matrix_basis = basis; e.rotation_mode = 'QUATERNION'; e.rotation_quaternion = basis.to_quaternion()
    for k, v in props.items(): e[k] = v
    return e
NODOS = {}
orden = ["TurboTimberEvolution"]
while len(orden) < len(R1):
    for n, d in R1.items():
        if n not in orden and d["parent"] in orden: orden.append(n)
for n in orden:
    d = R1[n]
    props = dict(d["extras"])
    if n in MP.PIVOT_SECTION: props["openrc_section"] = MP.PIVOT_SECTION[n]
    for k in ("openrc_section",):
        if n in ("TurboTimberEvolution", "thrust_frame") and k in props: del props[k]
    NODOS[n] = vacio(n, NODOS.get(d["parent"]), d["basis"], props)
bpy.context.view_layer.update()
root = NODOS["TurboTimberEvolution"]
MALLA_PIVOTE = {"aileron_left": "aileron_left_hinge", "aileron_right": "aileron_right_hinge", "flap_left": "flap_left_hinge",
                "flap_right": "flap_right_hinge", "elevator": "elevator_hinge", "rudder": "rudder_hinge",
                "propeller_rotor": "propeller_spin", "gear_left_leg": "gear_left_suspension", "wheel_left": "wheel_left_axle",
                "gear_right_leg": "gear_right_suspension", "wheel_right": "wheel_right_axle", "tailwheel_fork": "tailwheel_steer",
                "tailwheel": "tailwheel_axle"}
def colgar(malla, pivote):
    bpy.context.view_layer.update()
    malla.data.transform(pivote.matrix_world.inverted() @ malla.matrix_world)
    malla.parent = pivote; malla.matrix_parent_inverse = Matrix.Identity(4); malla.matrix_basis = Matrix.Identity(4)
for n, o in OBJ.items():
    colgar(o, NODOS[MALLA_PIVOTE.get(n, "TurboTimberEvolution")])
bpy.context.view_layer.update()
# r2 extras on pivots: simulator-side throws next to the authored ones (both sources kept)
SIM_THROW = {"aileron_left_hinge": 34.5, "aileron_right_hinge": 34.5, "elevator_hinge": 17.8, "rudder_hinge": 18.2}
for n, v in SIM_THROW.items():
    NODOS[n]["sim_range_deg_approx"] = v
    NODOS[n]["sim_range_source"] = "OpenRC Simulator: manual linear travel at an assumed measurement station (delivery spec r2, sec. 4)"
NODOS["flap_left_hinge"]["sim_flap_steps_deg"] = [0.0, 20.7, 36.6]; NODOS["flap_right_hinge"]["sim_flap_steps_deg"] = [0.0, 20.7, 36.6]

# ------------------------------------------------------------------ measurements for metadata and verification
def tri(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
def superficies(o): return len({p.material_index for p in o.data.polygons})
mallas = [o for o in col.objects if o.type == 'MESH']
conteo = {o.name: dict(triangles=tri(o), surfaces=superficies(o), section=o["openrc_section"], parent=o.parent.name,
                       materials=[o.data.materials[i].name for i in sorted({p.material_index for p in o.data.polygons})]) for o in mallas}
def pts(nombres):
    out = []
    for n in nombres:
        o = bpy.data.objects[n]; out += [o.matrix_world @ v.co for v in o.data.vertices]
    return out
P_all = pts([o.name for o in mallas])
wl, wr = pts(["wing_left_fixed"]), pts(["wing_right_fixed"])
prop = pts(["propeller_rotor"]); rud = pts(["rudder"])
lm = {"left_wingtip": min(wl, key=lambda v: v.x), "right_wingtip": max(wr, key=lambda v: v.x),
      "nose_spinner_tip": max(prop, key=lambda v: v.y), "tail_rudder_trailing_edge": min(rud, key=lambda v: v.y),
      "wing_root_leading_edge": max([v for v in wl + wr if abs(v.x) < 0.003], key=lambda v: v.y),
      "left_main_wheel_center": NODOS["wheel_left_axle"].matrix_world.translation.copy(),
      "right_main_wheel_center": NODOS["wheel_right_axle"].matrix_world.translation.copy(),
      "tailwheel_center": NODOS["tailwheel_axle"].matrix_world.translation.copy(),
      "propeller_hub": NODOS["propeller_spin"].matrix_world.translation.copy(), "datum_D0": Vector((0, 0, 0))}
def contacto(rueda):
    vs = pts([rueda]); return min(vs, key=lambda v: v.z)
lm.update(left_main_wheel_contact=contacto("wheel_left"), right_main_wheel_contact=contacto("wheel_right"), tailwheel_contact=contacto("tailwheel"))
def radio(rueda, eje):
    o = bpy.data.objects[rueda]; c = NODOS[eje].matrix_world.translation; ax = NODOS[eje].matrix_world.to_3x3() @ Vector((1, 0, 0))
    return max(((p - c) - ax*(p - c).dot(ax)).length for p in pts([rueda]))
dims = dict(wheel_radius_main_m=round(radio("wheel_left", "wheel_left_axle"), 5), wheel_radius_tail_m=round(radio("tailwheel", "tailwheel_axle"), 5),
            propeller_diameter_m=round(2*max(((p - lm["propeller_hub"]) - (NODOS["propeller_spin"].matrix_world.to_3x3() @ Vector((1, 0, 0))) *
                                              (p - lm["propeller_hub"]).dot(NODOS["propeller_spin"].matrix_world.to_3x3() @ Vector((1, 0, 0)))).length
                                             for p in prop), 5))
xs = [v.x for v in P_all]; ys = [v.y for v in P_all]; zs = [v.z for v in P_all]
piv = {}
for n, e in NODOS.items():
    if n == "TurboTimberEvolution": continue
    ax = (e.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    q = e.matrix_basis.to_quaternion()
    piv[n] = dict(parent=e.parent.name, pivot_m=[round(c, 6) for c in e.matrix_world.translation], pivot_sim=a_sim(e.matrix_world.translation),
                  axis=[round(c, 6) for c in ax], axis_sim=a_sim(ax), rest_local_quaternion_wxyz=[round(q.w, 6), round(q.x, 6), round(q.y, 6), round(q.z, 6)],
                  members=[o.name for o in e.children if o.type == 'MESH'], section=e.get("openrc_section"))
secciones = {}
for o in [x for x in col.objects if x.get("openrc_section")]:
    secciones.setdefault(o["openrc_section"], []).append(o.name)
datos = dict(landmarks_export={k: [round(c, 6) for c in v] for k, v in lm.items()}, landmarks_sim={k: a_sim(v) for k, v in lm.items()},
             bbox_export=dict(min=[min(xs), min(ys), min(zs)], max=[max(xs), max(ys), max(zs)]),
             span_m=round(lm["right_wingtip"].x - lm["left_wingtip"].x, 4), length_m=round(lm["nose_spinner_tip"].y - lm["tail_rudder_trailing_edge"].y, 4),
             dimensions=dims, pivots=piv, sections=secciones, mesh_counts=conteo,
             total_triangles=sum(c["triangles"] for c in conteo.values()), total_surfaces=sum(c["surfaces"] for c in conteo.values()),
             materials=sorted({m for c in conteo.values() for m in c["materials"]}), informe=INFORME,
             r1_mesh_parent=R1_MESH_PARENT, blender_version=bpy.app.version_string)
os.makedirs(os.path.join(SRC, "scripts"), exist_ok=True)
json.dump(datos, open(os.path.join(PKG, "source", "_export_data.json"), "w"), indent=1)

# ------------------------------------------------------------------ blend usability: text block and view
txt = bpy.data.texts.new("README_export")
txt.write("""Turbo Timber Evolution r2 - game asset (OpenRC Simulator: Turbo Lumber Evolution)
Export: only the collection EXPORT_aircraft, glTF 2.0 binary (.glb), +Y up, custom properties ON.
  blender -b source/aircraft_game.blend --python source/scripts/exporta_desde_blend.py -- export/aircraft.glb
  (or File > Export > glTF 2.0 with the settings listed in README.md section 'Export')
Frames: Blender +X right, +Y nose, +Z up (m). GLB/Godot +X right, +Y up, nose -Z: godot = (x, z, -y).
Root TurboTimberEvolution = D0 (symmetry plane x wing-root LE station x CAD thrust-axis height), identity.
Pivots: local +X = hinge axis, angle 0 = saved rest; apply rest * rot(+X, angle).
Controls: aileron_left_hinge, aileron_right_hinge, flap_left_hinge, flap_right_hinge, elevator_hinge, rudder_hinge,
  tailwheel_steer, tailwheel_axle, wheel_left_axle, wheel_right_axle, gear_left_suspension, gear_right_suspension,
  propeller_spin (under thrust_frame). Positive: TE down / rudder TE right / prop clockwise from behind / wheels forward.
Crash sections: custom property openrc_section on every exported mesh and moving pivot.
""")
def preparar_vista():
    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type == 'VIEW_3D':
                for sp in area.spaces:
                    if sp.type == 'VIEW_3D':
                        r3 = sp.region_3d
                        r3.view_location = Vector(((min(xs) + max(xs))/2, (min(ys) + max(ys))/2, (min(zs) + max(zs))/2))
                        r3.view_rotation = (Matrix.Rotation(math.radians(-35), 3, 'Z') @ Matrix.Rotation(math.radians(62), 3, 'X')).to_quaternion()
                        r3.view_distance = 2.6; r3.view_perspective = 'PERSP'
                        sp.shading.type = 'SOLID'; sp.shading.color_type = 'MATERIAL'
            if area.type == 'TEXT_EDITOR':
                for sp in area.spaces:
                    if sp.type == 'TEXT_EDITOR': sp.text = txt
preparar_vista()
for o in bpy.data.objects:
    if o.name.startswith("src_"): bpy.data.objects.remove(o)
sc.frame_set(1)

def exportar(ruta, anim):
    vl = bpy.context.view_layer
    vl.active_layer_collection = vl.layer_collection.children["EXPORT_aircraft"]
    bpy.ops.export_scene.gltf(filepath=ruta, export_format='GLB', use_active_collection=True, export_yup=True,
                              export_apply=True, export_extras=True, export_animations=anim, export_cameras=False,
                              export_lights=False, export_materials='EXPORT')
os.makedirs(os.path.join(PKG, "export"), exist_ok=True)
exportar(os.path.join(PKG, "export", "aircraft.glb"), False)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "aircraft_game.blend"), relative_remap=True, compress=True)

# ------------------------------------------------------------------ articulation demo (reference only)
sc.render.fps = 24; f0 = 1
# one control at a time: each block starts and ends at rest and no two blocks overlap in time
DEMO = [("aileron_left_hinge", (0, 22, 0, -22, 0)), ("aileron_right_hinge", (0, 22, 0, -22, 0)),
        ("flap_left_hinge", (0, 20.7, 36.6, 40, 0)), ("flap_right_hinge", (0, 20.7, 36.6, 40, 0)),
        ("elevator_hinge", (0, 22, 0, -22, 0)), ("rudder_hinge", (0, 30, 0, -30, 0)), ("tailwheel_steer", (0, 30, 0, -30, 0)),
        ("gear_left_suspension", (0, 12, 0)), ("gear_right_suspension", (0, 12, 0)),
        ("propeller_spin", tuple(90*k for k in range(9))), ("wheel_left_axle", tuple(90*k for k in range(5))),
        ("wheel_right_axle", tuple(90*k for k in range(5))), ("tailwheel_axle", tuple(90*k for k in range(5)))]
DEMO_TIMELINE = {}
for n, angs in DEMO:
    o = NODOS[n]; q0 = o.rotation_quaternion.copy(); paso = 6 if n.endswith(("_spin", "_axle")) else 12
    for k, a in enumerate(angs):
        o.rotation_quaternion = q0 @ Quaternion((1, 0, 0), math.radians(a)); o.keyframe_insert("rotation_quaternion", frame=f0 + paso*k)
    # hold rest outside the block so other blocks never move this pivot
    o.rotation_quaternion = q0; o.keyframe_insert("rotation_quaternion", frame=1); o.keyframe_insert("rotation_quaternion", frame=f0)
    DEMO_TIMELINE[n] = dict(frames=[f0, f0 + paso*(len(angs) - 1)], angles_deg=list(angs))
    f0 += paso*(len(angs) - 1) + 6
for a in bpy.data.actions:
    for fc in getattr(a, "fcurves", []):
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
sc.frame_start, sc.frame_end = 1, f0
exportar(os.path.join(PKG, "export", "aircraft_demo.glb"), True)
def fusionar_animaciones(ruta, nombre="control_demo"):
    import struct
    raw = open(ruta, "rb").read()
    ln = struct.unpack_from("<I", raw, 12)[0]; gl = json.loads(raw[20:20 + ln]); resto = raw[20 + ln:]
    anims = gl.get("animations", [])
    if len(anims) <= 1: return
    canales, muestras = [], []
    for a in anims:
        off = len(muestras); muestras += a["samplers"]
        for c in a["channels"]:
            c = dict(c); c["sampler"] += off; canales.append(c)
    gl["animations"] = [{"name": nombre, "channels": canales, "samplers": muestras}]
    js = json.dumps(gl, separators=(",", ":")).encode(); js += b" " * ((4 - len(js) % 4) % 4)
    cuerpo = struct.pack("<II", len(js), 0x4E4F534A) + js + resto
    open(ruta, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(cuerpo)) + cuerpo)
fusionar_animaciones(os.path.join(PKG, "export", "aircraft_demo.glb"))
datos["demo_timeline_frames_24fps"] = DEMO_TIMELINE
json.dump(datos, open(os.path.join(PKG, "source", "_export_data.json"), "w"), indent=1)
print("EXPORT OK", datos["total_triangles"], datos["total_surfaces"], datos["span_m"], datos["length_m"], INFORME["closure_faces"])
