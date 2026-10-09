"""Arma la escena del Turbo Timber Evolution en Blender, guarda el .blend y renderiza 3 vistas."""
import bpy, math, json, os, sys
from mathutils import Vector

BASE = os.path.dirname(os.path.abspath(__file__))
STL = os.path.join(BASE, "stl_v12")
OUT = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else BASE
SAMPLES = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 96
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'

# ---------- materiales ----------
def material(nombre, color, rough=0.4, metal=0.0, coat=0.0, alpha=1.0, transm=0.0):
    m = bpy.data.materials.new(nombre); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = coat
    if transm and "Transmission Weight" in b.inputs: b.inputs["Transmission Weight"].default_value = transm
    m.diffuse_color = (*color, 1)
    return m

MATS = {
    "blanco":     material("Blanco",     (0.86, 0.86, 0.85), 0.40, coat=0.1),
    "rojo":       material("Rojo",       (0.45, 0.006, 0.004), 0.45, coat=0.05),
    "negro":      material("Negro",      (0.015, 0.015, 0.018), 0.35, coat=0.2),
    "negro_mate": material("NegroMate",  (0.02, 0.02, 0.02), 0.6),
    "vidrio":     material("Vidrio",     (0.01, 0.015, 0.02), 0.04, coat=1.0),
    "metal":      material("Aluminio",   (0.75, 0.75, 0.76), 0.28, metal=1.0),
    "gris":       material("Gris",       (0.18, 0.18, 0.19), 0.45),
    "gris_claro": material("GrisClaro",  (0.45, 0.46, 0.48), 0.45),
    "cromo":      material("Cromo",      (0.85, 0.85, 0.86), 0.12, metal=1.0),
    "espuma":     material("EspumaNegra",(0.018, 0.018, 0.018), 0.9),
    "gris_oscuro":material("GrisOscuro", (0.06, 0.06, 0.065), 0.5),
    "dorado":     material("Dorado",     (0.85, 0.62, 0.25), 0.25, metal=1.0),
    "laton":      material("Laton",      (0.80, 0.58, 0.22), 0.30, metal=1.0),
    "bateria":    material("Bateria",    (0.10, 0.25, 0.60), 0.4),
    "madera":     material("Contrachapado", (0.62, 0.45, 0.26), 0.6),
    "plastico":   material("PlasticoCapota", (0.88, 0.88, 0.87), 0.22, coat=0.25),
    "nylon_negro":   material("NylonNegro",   (0.022, 0.022, 0.024), 0.62),
    "spinner_negro": material("SpinnerNegro", (0.015, 0.015, 0.017), 0.30, coat=0.15),
    "aluminio":      material("AluminioCP",   (0.55, 0.56, 0.58), 0.30, metal=1.0),
    "led_rojo":   material("LedRojo",    (0.9, 0.05, 0.03), 0.2),
    "led_verde":  material("LedVerde",   (0.1, 0.9, 0.2), 0.2),
}
for k in ("led_rojo", "led_verde"):
    b = MATS[k].node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = b.inputs["Base Color"].default_value
    b.inputs["Emission Strength"].default_value = 3.0
for k, v in (("nylon_negro", 0.25), ("spinner_negro", 0.3)):
    MATS[k].node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = v
# textura de espuma en los neumaticos (relieve con ruido)
nt = MATS["espuma"].node_tree; _r = nt.nodes.new("ShaderNodeTexNoise"); _r.inputs["Scale"].default_value = 900
_b = nt.nodes.new("ShaderNodeBump"); _b.inputs["Strength"].default_value = 0.35
nt.links.new(_r.outputs["Fac"], _b.inputs["Height"]); nt.links.new(_b.outputs["Normal"], nt.nodes["Principled BSDF"].inputs["Normal"])
MATS["espuma"].node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.2
# vidrio gris translucido como el de las fotos
b = MATS["vidrio"].node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.20, 0.23, 0.26, 1); b.inputs["Roughness"].default_value = 0.08

# ---------- importar piezas ----------
avion = bpy.data.objects.new("TurboTimber_Evolution", None)
sc.collection.objects.link(avion)
cfg = json.load(open(os.path.join(STL, "escena.json"))); mats = cfg["materiales"]
for nombre, mat in mats.items():
    bpy.ops.wm.stl_import(filepath=os.path.join(STL, nombre + ".stl"))
    o = bpy.context.selected_objects[0]
    o.name = nombre
    o.scale = (0.001,) * 3                 # mm -> m (escala real)
    o.data.materials.append(MATS[mat])
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    o.parent = avion

# actitud de tres puntos: rueda principal y rueda de cola tocando el suelo
main = Vector(cfg["contactos_mm"]["principal"])*0.001; cola = Vector(cfg["contactos_mm"]["cola"])*0.001
ang = math.atan2(cola.y - main.y, cola.x - main.x)
avion.rotation_euler = (0, ang, 0)
zc = -(-main.x*math.sin(ang) + main.y*math.cos(ang))
avion.location = (0, 0, zc)
print("actitud en tierra (grados):", math.degrees(ang))
sys.path.insert(0, BASE)
import rig_mandos
MANDOS_OBJ, BISAGRAS = rig_mandos.montar(cfg, avion, MATS)
import rig_tren
TREN_OBJ = rig_tren.montar_tren(cfg, avion, MATS, STL)
import rig_v7
cfg["analisis"] = json.load(open(os.path.join(BASE, "analisis.json")))
rig_v7.montar(cfg, avion, MANDOS_OBJ, MATS)

# ---------- suelo, luz, mundo ----------
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
suelo = bpy.context.object; suelo.name = "Suelo"; suelo.is_shadow_catcher = True
suelo.data.materials.append(material("Suelo", (0.90, 0.90, 0.90), 0.7))

w = bpy.data.worlds.new("Cielo"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]
sky = w.node_tree.nodes.new("ShaderNodeTexGradient")
ramp = w.node_tree.nodes.new("ShaderNodeValToRGB")
mapn = w.node_tree.nodes.new("ShaderNodeMapping"); coord = w.node_tree.nodes.new("ShaderNodeTexCoord")
mapn.inputs["Rotation"].default_value = (0, -math.pi/2, 0)
ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
ramp.color_ramp.elements[1].color = (0.92, 0.94, 0.97, 1)
L = w.node_tree.links
L.new(coord.outputs["Generated"], mapn.inputs["Vector"]); L.new(mapn.outputs["Vector"], sky.inputs["Vector"])
L.new(sky.outputs["Fac"], ramp.inputs["Fac"]); L.new(ramp.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.6

bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), math.radians(-15), math.radians(-35)))
sol = bpy.context.object; sol.data.energy = 3.0; sol.data.angle = math.radians(3); sol.name = "Sol"
bpy.ops.object.light_add(type='AREA', location=(-2.5, -2.5, 2.5))
rel = bpy.context.object; rel.data.energy = 400; rel.data.size = 3; rel.name = "Relleno"
rel.rotation_euler = (Vector((0.2, 0, 0.3)) - rel.location).to_track_quat('-Z', 'Y').to_euler()

# ---------- camaras ----------
def camara(nombre, loc, objetivo, lente=50, arriba=None):
    bpy.ops.object.camera_add(location=loc)
    c = bpy.context.object; c.name = nombre; c.data.lens = lente
    d = (Vector(objetivo) - Vector(loc)).normalized()
    if arriba is None:
        c.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    else:                                   # orientacion con vector "arriba" propio
        from mathutils import Matrix
        der = d.cross(Vector(arriba)).normalized(); up = der.cross(d).normalized()
        c.rotation_euler = Matrix((der, up, -d)).transposed().to_euler()
    return c

vistas = {
    "tres_cuartos": camara("Cam_TresCuartos", (-1.02, -1.08, 0.50), (0.30, 0.22, 0.17), 24),
    "lateral":      camara("Cam_Lateral",     (0.27, 3.0, 0.30),  (0.27, 0, 0.22), 60),
    "superior":     camara("Cam_Superior",    (1.45, 1.25, 1.75), (0.1, 0, 0.2), 42),
    "vuelo_superior": camara("Cam_VueloSuperior", (-0.05, -0.95, 3.3), (0.22, 0.0, 0.22), 60, arriba=(-0.6, 1.0, 0.0)),
}

TREN = [n for n in mats if any(t in n for t in ('neum', 'buje', 'pata', 'tren', 'rueda', 'resorte', 'cable', 'perno', 'collarin', 'arandela', 'tuerca', 'ojal'))]
# v11: reflector oscuro invisible para la camara: da las bandas oscuras del cromo (escape, campana)
bpy.ops.mesh.primitive_plane_add(size=3, location=(-0.4, 0.0, 1.6), rotation=(math.radians(180), 0, 0))
_ref = bpy.context.object; _ref.name = "Reflector_oscuro"
_ref.data.materials.append(material("ReflectorOscuro", (0.02, 0.02, 0.025), 1.0))
_ref.visible_camera = False; _ref.visible_diffuse = False; _ref.visible_shadow = False
for _y in (-1.4, 1.4):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0.0, _y, 0.18), rotation=(math.radians(90), 0, 0))
    _f = bpy.context.object; _f.name = "Franja_reflejo"; _f.scale = (2.5, 0.06, 1)
    _f.data.materials.append(MATS["negro"]); _f.visible_camera = False; _f.visible_diffuse = False; _f.visible_shadow = False
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.view_settings.view_transform = 'AgX'
try: sc.view_settings.look = 'AgX - Punchy'
except Exception as e: print('look', e)
sc.render.film_transparent = True   # fondo transparente: el suelo solo recoge sombras
sc.camera = vistas["tres_cuartos"]

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "turbo_timber_evolution_v12.blend"))
if "--norender" not in sys.argv:
    solo = sys.argv[sys.argv.index("--vistas") + 1].split(",") if "--vistas" in sys.argv else list(vistas)
    for k, c in vistas.items():
        if k not in solo: continue
        vuelo = (k == "vuelo_superior")                 # en vuelo: sin suelo, sin sombra y sin tren (como la foto)
        suelo.hide_render = vuelo
        for n in TREN:
            if n in bpy.data.objects: bpy.data.objects[n].hide_render = vuelo
        sc.render.resolution_x, sc.render.resolution_y = (1200, 1200) if vuelo else (1600, 1000)
        sc.camera = c
        sc.render.filepath = os.path.join(OUT, f"render_{k}.png")
        bpy.ops.render.render(write_still=True)
        print("render", k)
    sc.camera = vistas["tres_cuartos"]
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "turbo_timber_evolution_v12.blend"))
