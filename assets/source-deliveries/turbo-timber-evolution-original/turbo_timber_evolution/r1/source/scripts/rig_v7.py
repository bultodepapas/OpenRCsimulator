"""Extras del rig v7: eje del motor con caida/derecha y helice girando, guias de CG (no salen en el render)."""
import bpy, math
from mathutils import Vector, Matrix, Euler
S = 0.001
PIEZAS_GIRO = ("helice", "spinner", "tornillos_spinner", "tuerca", "contraplaca", "eje_motor", "campana_motor")

def montar(cfg, avion, mandos, mats):
    m = cfg["motor"]; hub = Vector(m["buje"])*S
    R = Euler((0, math.radians(-m["caida"]), math.radians(-m["derecha"])), 'XYZ').to_matrix().to_4x4()
    eje = bpy.data.objects.new("Eje_motor", None); bpy.context.scene.collection.objects.link(eje)
    eje.empty_display_type = 'SINGLE_ARROW'; eje.empty_display_size = 0.08
    eje.parent = avion; eje.location = hub; eje.rotation_euler = R.to_euler()
    mandos["helice_rpm"] = 600.0
    mandos.id_properties_ui("helice_rpm").update(min=0, max=12000, soft_max=3000, description="Giro de la helice en la animacion (rpm visuales)")
    inv = R.inverted() @ Matrix.Translation(-hub)
    for n in PIEZAS_GIRO + ("interno_motor", "bancada_motor", "soporte_motor"):
        o = bpy.data.objects.get(n)
        if o is None: continue
        o.data.transform(inv); o.parent = eje; o.location = (0, 0, 0); o.rotation_euler = (0, 0, 0)
        if n in PIEZAS_GIRO:     # giro horario visto desde atras (helice tractora)
            d = o.driver_add("rotation_euler", 0).driver; d.type = 'SCRIPTED'
            v = d.variables.new(); v.name = "rpm"; v.type = 'SINGLE_PROP'
            v.targets[0].id = mandos; v.targets[0].data_path = '["helice_rpm"]'
            d.expression = "-frame/24*rpm/60*2*pi"
    # guias: CG estimado y rango recomendado, visibles en el visor y ocultas en el render
    col = bpy.data.collections.new("Guias_CG"); bpy.context.scene.collection.children.link(col)
    a = cfg["analisis"]["cg"]; mac = m["mac"]
    z_ala = 0.060      # dentro de la cabina, bajo el ala
    def guia(nombre, loc, malla):
        malla(); o = bpy.context.object; o.name = nombre
        for c in o.users_collection: c.objects.unlink(o)
        col.objects.link(o); o.parent = avion; o.location = loc
        o.hide_render = True; o.display_type = 'WIRE' if "rango" in nombre else 'SOLID'
        return o
    x0, x1 = a["cg_recomendado_mm"]
    b = guia("CG_rango_recomendado", Vector(((x0 + x1)/2*S, 0, z_ala)), lambda: bpy.ops.mesh.primitive_cube_add(size=1))
    b.scale = ((x1 - x0)*S, 0.30, 0.004)
    guia("CG_estimado", Vector((a["cg_con_bateria_en_su_bahia_mm"]*S, 0, z_ala)), lambda: bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012))
    for k in ("CG_rango_recomendado", "CG_estimado"):
        bpy.data.objects[k]["nota"] = "Estimado con masas supuestas: verificar en el banco antes de volar"
