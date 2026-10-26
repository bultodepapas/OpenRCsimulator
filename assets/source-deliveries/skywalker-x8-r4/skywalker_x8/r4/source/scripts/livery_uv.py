"""Paso 1 de la librea "Abisal": regiones, material unico pintado y atlas UV.

  python livery_uv.py source/aircraft_game.blend          (modifica el .blend en su sitio)

* Guarda en cada cara dos atributos de dominio FACE (los usa el horneado y quedan como mascaras
  editables): x8_part (pieza) y x8_region (0 piel, 1 cinta de bisagra, 2 tapa de servo,
  3 plastico naranja, 4 helice).
* Las caras exteriores pasan al material x8_livery (un solo atlas); el interior, el metal, el
  vidrio, la campana del motor y los equipos siguen con sus materiales planos.
* Despliega todas las caras pintadas en un solo atlas (Smart UV Project + Pack Islands).
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND = os.path.abspath(argv[0])
bpy.ops.wm.open_mainfile(filepath=BLEND)
ob = bpy.data.objects

PARTS = S.LIVERY_PARTS
REGION_OF = {"x8_epo_white": 0, "x8_black": 1, "x8_servo_cover": 2, "x8_orange": 3}
liv = bpy.data.materials.get("x8_livery") or bpy.data.materials.new("x8_livery")
liv.use_backface_culling = True
nt = liv.node_tree
b = nt.nodes.get("Principled BSDF")
b.inputs["Base Color"].default_value = (0.03, 0.04, 0.07, 1)

objs = []
for name, pid in PARTS.items():
    o = ob[name]
    me = o.data
    for an in ("x8_part", "x8_region"):
        if an in me.attributes:
            me.attributes.remove(me.attributes[an])
    a_part = me.attributes.new("x8_part", "FLOAT", "FACE")
    a_reg = me.attributes.new("x8_region", "FLOAT", "FACE")
    names = [m.name for m in me.materials]
    if "x8_livery" not in names:
        me.materials.append(liv)
        names.append("x8_livery")
    k = names.index("x8_livery")
    regs, parts = [], []
    for p in me.polygons:
        mn = names[p.material_index]
        r = REGION_OF.get(mn)
        if name == "propeller_rotor" and mn == "x8_black":
            r = 4
        if r is not None:
            p.material_index = k
        regs.append(float(r if r is not None else -1))
        parts.append(float(pid))
    a_reg.data.foreach_set("value", regs)
    a_part.data.foreach_set("value", parts)
    # quitar las ranuras que quedaron sin uso
    used = {names[p.material_index] for p in me.polygons}
    keep = [n for n in names if n in used]
    idx = [keep.index(names[p.material_index]) for p in me.polygons]
    me.materials.clear()
    for n in keep:
        me.materials.append(bpy.data.materials[n])
    me.polygons.foreach_set("material_index", idx)
    me.update()
    objs.append(o)
for m in list(bpy.data.materials):
    if m.users == 0:
        bpy.data.materials.remove(m)

# atlas: solo las caras pintadas
for o in ob:
    o.select_set(False)
for o in objs:
    o.select_set(True)
    me = o.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    names = [m.name for m in me.materials]
    for p in me.polygons:
        p.select = names[p.material_index] == "x8_livery"
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.mode_set(mode="EDIT")
bpy.context.scene.tool_settings.use_uv_select_sync = True
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.002, area_weight=0.0,
                         correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, scale=True, margin_method="FRACTION", margin=0.003,
                        shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")
for o in ob:
    o.select_set(False)

# densidad de texeles resultante
cov = area = 0.0
for o in objs:
    me = o.data
    me.calc_loop_triangles()
    uv = me.uv_layers["UVMap"].data
    names = [m.name for m in me.materials]
    for t in me.loop_triangles:
        if names[t.material_index] != "x8_livery":
            continue
        a, b_, c = (uv[l].uv.copy() for l in t.loops)
        cov += abs((b_ - a).cross(c - a)) / 2
        area += t.area
print(f"UV: cobertura {cov:.3f}, area pintada {area:.3f} m2, "
      f"{(area / (cov * 2048 * 2048)) ** 0.5 * 1000:.2f} mm/texel a 2048, "
      f"{(area / (cov * 4096 * 4096)) ** 0.5 * 1000:.2f} mm/texel a 4096")
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("GUARDADO", BLEND)
