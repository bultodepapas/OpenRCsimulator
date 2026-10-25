"""Renders de la librea BOLIDO en Cycles (solo imagenes; no modifica el .blend del juego).

  python render_bolido.py source/aircraft_game.blend textures/bolido/source previews/renders/bolido <escena> [muestras] [%]

Escenas: reentrada (plasma y bordes al rojo sobre el limbo de la Tierra), estudio (3/4 en hangar),
planta (desde arriba), panza (losetas desde abajo con luz rasante), nariz (primer plano del
cono de carbono, las losetas y la flecha de rescate), pista (en el lecho seco de un lago al
amanecer, recien aterrizado).
El material de render usa las fuentes 4096 y suma lo que glTF no lleva: incandescencia
(mascara heat, solo en reentrada), colores de revenido por pelicula delgada y barniz.
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Vector, Matrix, Euler
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND, SRC, OUT, SCENE = os.path.abspath(argv[0]), os.path.abspath(argv[1]), os.path.abspath(argv[2]), argv[3]
SPP = int(argv[4]) if len(argv) > 4 else 96
PCT = int(argv[5]) if len(argv) > 5 else 100
PRE = "x8_bolido_"
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=BLEND)
sc = bpy.context.scene
ob = bpy.data.objects
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_adaptive_sampling = True
sc.cycles.adaptive_threshold = 0.02
sc.cycles.use_denoising = True
sc.cycles.denoiser = "OPENIMAGEDENOISE"
sc.cycles.max_bounces = 6
sc.cycles.glossy_bounces = 3
sc.cycles.transmission_bounces = 4
sc.cycles.volume_bounces = 1
sc.cycles.caustics_reflective = False
sc.cycles.caustics_refractive = False
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.render.resolution_percentage = PCT
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Punchy"
sc.render.film_transparent = False


def img(name, cs):
    p = os.path.join(SRC, PRE + name)
    if not os.path.exists(p):
        return None
    im = bpy.data.images.load(p)
    im.colorspace_settings.name = cs
    return im


def livery_render(emit=3.0, heat=0.0, normal_strength=1.3):
    m = bpy.data.materials.new("x8_bolido_render")
    m.use_nodes = True
    nt = m.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])

    def tex(name, cs, interp="Cubic"):
        im = img(name, cs)
        if im is None:
            return None
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = im
        t.interpolation = interp
        return t
    nt.links.new(tex("base_color.png", "sRGB").outputs[0], b.inputs["Base Color"])
    nt.links.new(tex("roughness.png", "Non-Color").outputs[0], b.inputs["Roughness"])
    nt.links.new(tex("metallic.png", "Non-Color").outputs[0], b.inputs["Metallic"])
    tn = tex("normal.png", "Non-Color", "Linear")
    if tn is not None:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.uv_map = "UVMap"
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(tn.outputs[0], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], b.inputs["Normal"])
        nt.links.new(nm.outputs[0], b.inputs["Coat Normal"])
    # emision: luces de navegacion + incandescencia de reentrada
    te = tex("emission.png", "sRGB")
    ems = nt.nodes.new("ShaderNodeMix")
    ems.data_type = "RGBA"
    ems.blend_type = "ADD"
    ems.inputs["Factor"].default_value = 1.0
    sc_e = nt.nodes.new("ShaderNodeMix")
    sc_e.data_type = "RGBA"
    sc_e.blend_type = "MULTIPLY"
    sc_e.inputs["Factor"].default_value = 1.0
    nt.links.new(te.outputs[0], sc_e.inputs["A"])
    sc_e.inputs["B"].default_value = (emit, emit, emit, 1)
    nt.links.new(sc_e.outputs["Result"], ems.inputs["A"])
    th = tex("heat.png", "Non-Color")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0, 0, 0, 1)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (1.0, 0.93, 0.8, 1)
    for pos, col in ((0.2, (0.03, 0.002, 0.0)), (0.45, (0.22, 0.02, 0.002)), (0.7, (0.9, 0.2, 0.02)),
                     (0.88, (1.0, 0.55, 0.16))):
        e = cr.elements.new(pos)
        e.color = (*col, 1)
    nt.links.new(th.outputs[0], ramp.inputs["Fac"])
    hm = nt.nodes.new("ShaderNodeMix")
    hm.data_type = "RGBA"
    hm.blend_type = "MULTIPLY"
    hm.inputs["Factor"].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], hm.inputs["A"])
    hm.inputs["B"].default_value = (heat, heat, heat, 1)
    nt.links.new(hm.outputs["Result"], ems.inputs["B"])
    nt.links.new(ems.outputs["Result"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 1.0
    ir = tex("iridescence.png", "Non-Color")
    mth = nt.nodes.new("ShaderNodeMapRange")
    mth.inputs["From Min"].default_value = 0.0
    mth.inputs["From Max"].default_value = 1.0
    mth.inputs["To Min"].default_value = 0.0
    mth.inputs["To Max"].default_value = 420.0
    nt.links.new(ir.outputs[0], mth.inputs["Value"])
    nt.links.new(mth.outputs["Result"], b.inputs["Thin Film Thickness"])
    b.inputs["Thin Film IOR"].default_value = 2.0
    co = tex("coat.png", "Non-Color")
    cm = nt.nodes.new("ShaderNodeMath")
    cm.operation = "MULTIPLY"
    cm.inputs[1].default_value = 0.6
    nt.links.new(co.outputs[0], cm.inputs[0])
    nt.links.new(cm.outputs[0], b.inputs["Coat Weight"])
    b.inputs["Coat Roughness"].default_value = 0.05
    b.inputs["Specular IOR Level"].default_value = 0.5
    return m


def apply_render_material(**kw):
    m = livery_render(**kw)
    for name in S.LIVERY_PARTS:
        me = ob[name].data
        for i, mm in enumerate(me.materials):
            if mm and mm.name == "x8_livery":
                me.materials[i] = m
    return m


REST = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}


def pose(**ang):
    for n, mtx in REST.items():
        ob[n].matrix_basis = mtx @ Matrix.Rotation(math.radians(ang.get(n, 0.0)), 4, "X")


def spin_blur(deg_per_frame=70.0):
    n = "propeller_spin"
    o = ob[n]
    o.rotation_mode = "QUATERNION"
    for f, a in ((1, 0.0), (2, deg_per_frame)):
        o.matrix_basis = REST[n] @ Matrix.Rotation(math.radians(a), 4, "X")
        o.keyframe_insert("rotation_quaternion", frame=f)
    sc.render.use_motion_blur = deg_per_frame > 0
    sc.render.motion_blur_shutter = 0.5
    sc.frame_set(1)


root = ob[S.ROOT]
# angulo de la helice con las palas horizontales (para la escena en tierra)
_rv = [v.co for v in ob["propeller_rotor"].data.vertices]
_tip = max(_rv, key=lambda v: v.y * v.y + v.z * v.z)
PROP_FLAT = -math.degrees(math.atan2(_tip.z, _tip.y))


def place_aircraft(loc=(0, 0, 0), rot_deg=(0, 0, 0)):
    root.matrix_world = Matrix.Translation(loc) @ Euler(tuple(math.radians(a) for a in rot_deg),
                                                        "XYZ").to_matrix().to_4x4()
    bpy.context.view_layer.update()


def camera(loc, target, lens=50, dof=None, fstop=4.0, clip_end=2000):
    cam = bpy.data.objects.new("CAM", bpy.data.cameras.new("CAM"))
    sc.collection.objects.link(cam)
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.data.clip_end = clip_end
    if dof:
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = dof
        cam.data.dof.aperture_fstop = fstop
    sc.camera = cam
    return cam


def light(kind, loc, rot, energy, color=(1, 1, 1), size=1.0, angle=None, aim=None, shape="DISK"):
    ld = bpy.data.lights.new(kind + "_L", kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
        ld.shape = shape
    if kind == "SUN" and angle is not None:
        ld.angle = math.radians(angle)
    lo = bpy.data.objects.new(kind + "_L", ld)
    sc.collection.objects.link(lo)
    lo.location = loc
    lo.rotation_euler = Euler(tuple(math.radians(a) for a in rot))
    if aim is not None:
        lo.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return lo


def world_gradient(horizon, zenith, strength=1.0, ground=None, stars=0.0):
    w = sc.world or bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.5
    cr.elements[0].color = (*(ground or horizon), 1)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (*zenith, 1)
    e = cr.elements.new(0.53)
    e.color = (*horizon, 1)
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -1
    mp.inputs["From Max"].default_value = 1
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mp.inputs["Value"])
    nt.links.new(mp.outputs["Result"], ramp.inputs["Fac"])
    col = ramp.outputs["Color"]
    if stars > 0:                                  # campo de estrellas
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.inputs["Scale"].default_value = 420.0
        vo.inputs["Randomness"].default_value = 1.0
        nt.links.new(tc.outputs["Generated"], vo.inputs["Vector"])
        st = nt.nodes.new("ShaderNodeMapRange")
        st.inputs["From Min"].default_value = 0.02
        st.inputs["From Max"].default_value = 0.0
        st.inputs["To Max"].default_value = stars
        nt.links.new(vo.outputs["Distance"], st.inputs["Value"])
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        pw.inputs[1].default_value = 6.0
        nt.links.new(st.outputs["Result"], pw.inputs[0])
        rnd = nt.nodes.new("ShaderNodeMath")
        rnd.operation = "MULTIPLY"
        nt.links.new(pw.outputs[0], rnd.inputs[0])
        nt.links.new(vo.outputs["Color"], rnd.inputs[1])
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        add.inputs["Factor"].default_value = 1.0
        nt.links.new(col, add.inputs["A"])
        nt.links.new(rnd.outputs[0], add.inputs["B"])
        col = add.outputs["Result"]
    nt.links.new(col, bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs[0])


def compositor_glow(threshold=0.6, size=7, strength=0.9):
    sc.use_nodes = True
    try:
        tree = sc.compositing_node_group
        if tree is None:
            tree = bpy.data.node_groups.new("Compositor", "CompositorNodeTree")
            sc.compositing_node_group = tree
        for n_ in list(tree.nodes):
            tree.nodes.remove(n_)
        rl = tree.nodes.new("CompositorNodeRLayers")
        gl = tree.nodes.new("CompositorNodeGlare")
        out = tree.nodes.new("NodeGroupOutput")
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        for k, v in (("Type", "Bloom"), ("Threshold", threshold), ("Size", size / 9.0),
                     ("Strength", strength)):
            if k in gl.inputs:
                try:
                    gl.inputs[k].default_value = v
                except Exception:
                    pass
        if hasattr(gl, "glare_type"):
            gl.glare_type = "BLOOM"
        tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
        tree.links.new(gl.outputs["Image"], out.inputs[0])
    except Exception as e:
        print("compositor:", e)


def floor(z=-0.32, color=(0.02, 0.021, 0.024), rough=0.7, size=60, mat=None):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    fl = bpy.context.active_object
    if mat is None:
        mat = bpy.data.materials.new("piso")
        mat.use_nodes = True
        fb = mat.node_tree.nodes["Principled BSDF"]
        fb.inputs["Base Color"].default_value = (*color, 1)
        fb.inputs["Roughness"].default_value = rough
    fl.data.materials.append(mat)
    return fl


def render(name):
    sc.render.filepath = os.path.join(OUT, name + ".png")
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("RENDER", sc.render.filepath)


def emission_shell(src_names, offset, color, strength, facing_power=2.0, name="PLASMA"):
    """Copias de las mallas infladas a lo largo de la normal con emision en el borde (rim)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = facing_power
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    # mas fuerte en las caras que miran contra el flujo (abajo y adelante del avion)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    vt = nt.nodes.new("ShaderNodeVectorTransform")
    vt.vector_type = "NORMAL"
    vt.convert_from = "WORLD"
    vt.convert_to = "OBJECT"
    nt.links.new(geo.outputs["Normal"], vt.inputs["Vector"])
    sp = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vt.outputs["Vector"], sp.inputs[0])
    dot = nt.nodes.new("ShaderNodeMath")
    dot.operation = "MULTIPLY_ADD"
    dot.inputs[1].default_value = -0.8
    dot.inputs[2].default_value = 0.25
    nt.links.new(sp.outputs["Z"], dot.inputs[0])
    dy = nt.nodes.new("ShaderNodeMath")
    dy.operation = "MULTIPLY_ADD"
    dy.inputs[1].default_value = 0.6
    nt.links.new(sp.outputs["Y"], dy.inputs[0])
    nt.links.new(dot.outputs[0], dy.inputs[2])
    cl = nt.nodes.new("ShaderNodeClamp")
    nt.links.new(dy.outputs[0], cl.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], mul.inputs[0])
    nt.links.new(cl.outputs[0], mul.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    sm = nt.nodes.new("ShaderNodeMath")
    sm.operation = "MULTIPLY"
    sm.inputs[1].default_value = strength
    nt.links.new(mul.outputs[0], sm.inputs[0])
    nt.links.new(sm.outputs[0], em.inputs["Strength"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    ad = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(tr.outputs[0], ad.inputs[0])
    nt.links.new(em.outputs[0], ad.inputs[1])
    nt.links.new(ad.outputs[0], out.inputs["Surface"])
    m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    shells = []
    for nme in src_names:
        o = ob[nme]
        c = o.copy()
        c.data = o.data.copy()
        c.name = name + "_" + nme
        sc.collection.objects.link(c)
        c.matrix_world = o.matrix_world.copy()
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        c.data.materials.clear()
        c.data.materials.append(m)
        md = c.modifiers.new("inflar", "DISPLACE")
        md.strength = offset
        md.mid_level = 0.0
        c.visible_shadow = False
        shells.append(c)
    return shells


def plasma_volume(src_names, offset, color, strength, name="CAPA"):
    """Capa de plasma: copia de las mallas inflada a lo largo de la normal y rellena con un volumen
    emisivo. El brillo crece con el camino recorrido dentro de la capa: mas brillante en el borde
    (como el plasma real), sin contornos duros."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    # mas caliente adelante (el aire llega desde -X del mundo): gradiente sobre X mundial
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sp = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sp.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -0.3
    mr.inputs["From Max"].default_value = 0.75
    mr.inputs["To Min"].default_value = strength * 1.7
    mr.inputs["To Max"].default_value = strength * 0.15
    nt.links.new(sp.outputs["X"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], em.inputs["Strength"])
    nt.links.new(em.outputs[0], out.inputs["Volume"])
    objs = []
    for nme in src_names:
        o = ob[nme]
        c = o.copy()
        c.data = o.data.copy()
        c.name = name + "_" + nme
        sc.collection.objects.link(c)
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        c.data.materials.clear()
        c.data.materials.append(m)
        md = c.modifiers.new("inflar", "DISPLACE")
        md.strength = offset
        md.mid_level = 0.0
        c.visible_shadow = False
        objs.append(c)
    return objs


def volume_trail(loc, rot_deg, scale, color, density, name="ESTELA"):
    """Estela de plasma: cono de volumen emisivo con ruido estirado a lo largo del eje -Y local."""
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=1.0, radius2=0.08, depth=2.0, location=loc,
                                    rotation=tuple(math.radians(a) for a in rot_deg))
    co = bpy.context.active_object
    co.name = name
    co.scale = scale
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Density"].default_value = 0.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sp = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sp.inputs[0])
    # a lo largo del cono: z local de -1 (base, junto al avion) a +1 (punta, lejos)
    along = nt.nodes.new("ShaderNodeMapRange")
    along.inputs["From Min"].default_value = -1.0
    along.inputs["From Max"].default_value = 1.0
    along.inputs["To Min"].default_value = 1.0
    along.inputs["To Max"].default_value = 0.0
    nt.links.new(sp.outputs["Z"], along.inputs["Value"])
    rad = nt.nodes.new("ShaderNodeVectorMath")
    rad.operation = "LENGTH"
    cmb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sp.outputs["X"], cmb.inputs["X"])
    nt.links.new(sp.outputs["Y"], cmb.inputs["Y"])
    nt.links.new(cmb.outputs[0], rad.inputs[0])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["From Min"].default_value = 0.0
    rr.inputs["From Max"].default_value = 0.9
    rr.inputs["To Min"].default_value = 1.0
    rr.inputs["To Max"].default_value = 0.0
    nt.links.new(rad.outputs["Value"], rr.inputs["Value"])
    noi = nt.nodes.new("ShaderNodeTexNoise")
    noi.inputs["Scale"].default_value = 3.5
    noi.inputs["Detail"].default_value = 8.0
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (5.5, 5.5, 0.22)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs[0], noi.inputs["Vector"])
    nr = nt.nodes.new("ShaderNodeMapRange")
    nr.inputs["From Min"].default_value = 0.42
    nr.inputs["From Max"].default_value = 0.75
    nt.links.new(noi.outputs["Fac"], nr.inputs["Value"])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    nt.links.new(along.outputs["Result"], m1.inputs[0])
    nt.links.new(rr.outputs["Result"], m1.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.6
    nt.links.new(m1.outputs[0], pw.inputs[0])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], m2.inputs[0])
    nt.links.new(nr.outputs["Result"], m2.inputs[1])
    m3 = nt.nodes.new("ShaderNodeMath")
    m3.operation = "MULTIPLY"
    m3.inputs[1].default_value = density
    nt.links.new(m2.outputs[0], m3.inputs[0])
    nt.links.new(m3.outputs[0], pv.inputs["Emission Strength"])
    pv.inputs["Emission Color"].default_value = (*color, 1)
    nt.links.new(pv.outputs[0], out.inputs["Volume"])
    co.data.materials.append(m)
    co.visible_shadow = False
    return co


def earth(R=60000.0, h=3500.0, sun_dir=(0.6, 1.0, 0.18)):
    """Tierra de noche con el limbo iluminado por el amanecer y una capa de atmosfera."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=256, ring_count=128, radius=R, location=(0, 0, -R - h))
    e = bpy.context.active_object
    e.name = "TIERRA"
    for p in e.data.polygons:
        p.use_smooth = True
    m = bpy.data.materials.new("tierra")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz_ = nt.nodes.new("ShaderNodeTexNoise")
    nz_.inputs["Scale"].default_value = 60.0
    nz_.inputs["Detail"].default_value = 12.0
    nz_.inputs["Roughness"].default_value = 0.62
    nt.links.new(tc.outputs["Object"], nz_.inputs["Vector"])
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.52
    cr.color_ramp.elements[0].color = (0.004, 0.012, 0.03, 1)
    cr.color_ramp.elements[1].position = 0.68
    cr.color_ramp.elements[1].color = (0.75, 0.78, 0.82, 1)
    nt.links.new(nz_.outputs["Fac"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.7
    # luces de ciudades: puntos calidos donde no hay nubes
    vo = nt.nodes.new("ShaderNodeTexVoronoi")
    vo.inputs["Scale"].default_value = 2600.0
    nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
    ct = nt.nodes.new("ShaderNodeMapRange")
    ct.inputs["From Min"].default_value = 0.08
    ct.inputs["From Max"].default_value = 0.0
    nt.links.new(vo.outputs["Distance"], ct.inputs["Value"])
    land = nt.nodes.new("ShaderNodeTexNoise")
    land.inputs["Scale"].default_value = 9.0
    land.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], land.inputs["Vector"])
    lm = nt.nodes.new("ShaderNodeMapRange")
    lm.inputs["From Min"].default_value = 0.5
    lm.inputs["From Max"].default_value = 0.58
    nt.links.new(land.outputs["Fac"], lm.inputs["Value"])
    cl_ = nt.nodes.new("ShaderNodeMapRange")
    cl_.inputs["From Min"].default_value = 0.6
    cl_.inputs["From Max"].default_value = 0.5
    nt.links.new(nz_.outputs["Fac"], cl_.inputs["Value"])
    a1 = nt.nodes.new("ShaderNodeMath")
    a1.operation = "MULTIPLY"
    nt.links.new(ct.outputs["Result"], a1.inputs[0])
    nt.links.new(lm.outputs["Result"], a1.inputs[1])
    a2 = nt.nodes.new("ShaderNodeMath")
    a2.operation = "MULTIPLY"
    nt.links.new(a1.outputs[0], a2.inputs[0])
    nt.links.new(cl_.outputs["Result"], a2.inputs[1])
    a3 = nt.nodes.new("ShaderNodeMath")
    a3.operation = "MULTIPLY"
    a3.inputs[1].default_value = 0.35
    nt.links.new(a2.outputs[0], a3.inputs[0])
    b.inputs["Emission Color"].default_value = (1.0, 0.62, 0.28, 1)
    nt.links.new(a3.outputs[0], b.inputs["Emission Strength"])
    e.data.materials.append(m)
    # atmosfera: cascara con brillo en el borde
    bpy.ops.mesh.primitive_uv_sphere_add(segments=256, ring_count=128, radius=R * 1.012, location=(0, 0, -R - h))
    at = bpy.context.active_object
    at.name = "ATMOSFERA"
    for p in at.data.polygons:
        p.use_smooth = True
    ma = bpy.data.materials.new("atmosfera")
    ma.use_nodes = True
    nt = ma.node_tree
    for n_ in list(nt.nodes):
        nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.08
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 3.0
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    cr2 = nt.nodes.new("ShaderNodeValToRGB")
    cr2.color_ramp.elements[0].position = 0.0
    cr2.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1)
    cr2.color_ramp.elements[1].position = 1.0
    cr2.color_ramp.elements[1].color = (1.0, 0.55, 0.25, 1)
    e2 = cr2.color_ramp.elements.new(0.55)
    e2.color = (0.08, 0.32, 1.0, 1)
    nt.links.new(pw.outputs[0], cr2.inputs["Fac"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 6.0
    nt.links.new(cr2.outputs["Color"], em.inputs["Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    ad = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(tr.outputs[0], ad.inputs[0])
    nt.links.new(em.outputs[0], ad.inputs[1])
    nt.links.new(ad.outputs[0], out.inputs["Surface"])
    at.data.materials.append(ma)
    at.visible_shadow = False
    return e, at


# ------------------------------------------------------------------ escenas
if SCENE == "reentrada":
    sc.cycles.adaptive_threshold = 0.03
    apply_render_material(emit=6.0, heat=12.0, normal_strength=1.4)
    # trayectoria: -X del mundo; actitud: nariz 34 grados arriba de la trayectoria, leve alabeo
    place_aircraft((0, 0, 0), (34, -12, 90))
    pose(elevon_left_hinge=-6, elevon_right_hinge=-6)
    spin_blur(0.0)
    world_gradient((0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 1.0, ground=(0.0, 0.0, 0.0), stars=4.0)
    earth(R=60000.0, h=2600.0)
    light("AREA", (-0.6, 0.0, -3.2), (0, 0, 0), 140, (0.35, 0.52, 1.0), size=6.0, aim=(0.0, 0.0, 0.0))   # luz de la Tierra
    light("SUN", (0, 0, 10), (-35, 0, 60), 0.35, (0.75, 0.82, 1.0), angle=2.0)
    hull = ["fuselage_core", "canopy_hatch", "wing_left_fixed", "wing_right_fixed", "elevon_left",
            "elevon_right"]
    plasma_volume(hull, 0.018, (1.0, 0.42, 0.12), 0.7, "CAPA1")
    plasma_volume(hull, 0.045, (1.0, 0.26, 0.2), 0.35, "CAPA2")
    plasma_volume(hull, 0.09, (0.8, 0.2, 0.6), 0.22, "CAPA3")
    # estela detras (la trayectoria va hacia -X: la estela apunta a +X)
    volume_trail((3.75, 0.0, 0.3), (0, 90, 0), (0.62, 0.5, 3.0), (1.0, 0.45, 0.32), 3.0)
    camera((-2.3, -1.38, -0.36), (0.12, 0.1, -0.4), lens=32, dof=2.7, fstop=8, clip_end=200000)
    compositor_glow(threshold=0.5, size=9, strength=1.0)
    render("x8_bolido_reentrada")
elif SCENE in ("estudio", "planta"):
    apply_render_material(emit=3.0)
    place_aircraft((0, 0, 0), (0, 0, 0))
    spin_blur(0.0)
    world_gradient((0.10, 0.105, 0.115), (0.02, 0.022, 0.026), 0.7, ground=(0.012, 0.012, 0.014))
    floor(-0.32, (0.05, 0.05, 0.052), 0.55)
    light("AREA", (0.0, -0.1, 3.2), (0, 0, 0), 520, (1.0, 0.98, 0.95), size=3.5, shape="RECTANGLE")
    light("AREA", (2.6, 2.4, 1.2), (65, 0, 133), 200, (0.9, 0.93, 1.0), size=2.0)
    light("AREA", (-2.6, -1.6, 0.9), (70, 0, -60), 150, (1.0, 0.88, 0.75), size=1.6)
    light("AREA", (-2.4, 1.8, 0.4), (80, 0, -125), 120, (0.75, 0.82, 1.0), size=1.6)
    if SCENE == "planta":
        camera((0.95, -2.75, 2.65), (0.0, -0.16, -0.05), lens=40, dof=3.75, fstop=11)
        render("x8_bolido_planta")
    else:
        camera((-1.95, 1.30, 0.70), (0.25, -0.30, -0.06), lens=42, dof=2.65, fstop=8)
        render("x8_bolido_estudio")
elif SCENE == "panza":
    apply_render_material(emit=3.0)
    place_aircraft((0, 0, 0), (0, 8, 0))
    spin_blur(0.0)
    world_gradient((0.30, 0.31, 0.33), (0.08, 0.09, 0.11), 0.8, ground=(0.03, 0.03, 0.035))
    light("AREA", (-1.6, 1.2, -0.9), (0, 0, 0), 260, (1.0, 0.96, 0.9), size=1.4, aim=(0.1, -0.2, 0.0))
    light("AREA", (1.8, -1.6, -0.5), (0, 0, 0), 120, (0.75, 0.82, 1.0), size=2.0, aim=(0.0, -0.2, 0.0))
    camera((0.55, 0.65, -1.95), (-0.05, -0.20, 0.0), lens=40, dof=2.1, fstop=8)
    render("x8_bolido_panza")
elif SCENE == "nariz":
    apply_render_material(emit=3.0)
    place_aircraft()
    spin_blur(0.0)
    world_gradient((0.06, 0.065, 0.075), (0.012, 0.013, 0.016), 1.0)
    light("AREA", (0.55, 0.85, 0.55), (0, 0, 0), 40, (1.0, 0.97, 0.92), size=0.6, aim=(0.0, 0.2, 0.0))
    light("AREA", (-0.6, 0.6, -0.1), (0, 0, 0), 14, (0.65, 0.75, 1.0), size=0.6, aim=(0.0, 0.2, 0.0))
    light("AREA", (0.0, -0.3, 0.9), (0, 0, 0), 18, (1.0, 1.0, 1.0), size=1.0, aim=(0.0, 0.1, 0.0))
    camera((0.34, 0.68, 0.24), (0.0, 0.18, 0.02), lens=70, dof=0.62, fstop=5.6)
    compositor_glow(threshold=0.8, size=6, strength=0.6)
    render("x8_bolido_nariz")
elif SCENE == "pista":
    apply_render_material(emit=3.0)
    place_aircraft((0, 0, 0.047), (0, 0, 0))
    pose(elevon_left_hinge=8, elevon_right_hinge=8)
    sc.render.use_motion_blur = False
    world_gradient((1.0, 0.58, 0.34), (0.08, 0.16, 0.38), 1.0, ground=(0.25, 0.18, 0.12))
    m = bpy.data.materials.new("lecho")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    vo = nt.nodes.new("ShaderNodeTexVoronoi")
    vo.feature = "DISTANCE_TO_EDGE"
    vo.inputs["Scale"].default_value = 3.2
    tcl = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tcl.outputs["Object"], vo.inputs["Vector"])
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.0
    cr.color_ramp.elements[0].color = (0.16, 0.12, 0.085, 1)
    cr.color_ramp.elements[1].position = 0.012
    cr.color_ramp.elements[1].color = (0.58, 0.48, 0.37, 1)
    nt.links.new(vo.outputs["Distance"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    bu = nt.nodes.new("ShaderNodeBump")
    bu.inputs["Strength"].default_value = 0.6
    bu.inputs["Distance"].default_value = 0.01
    nt.links.new(vo.outputs["Distance"], bu.inputs["Height"])
    nt.links.new(bu.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.95
    floor(-0.0, mat=m, size=400)
    light("SUN", (-3.0, 2.6, 1.0), (0, 0, 0), 3.4, (1.0, 0.72, 0.48), angle=0.8, aim=(0, 0, 0))
    pose(elevon_left_hinge=8, elevon_right_hinge=8, propeller_spin=PROP_FLAT)
    camera((-1.75, 2.15, 0.30), (0.25, -0.30, 0.04), lens=35, dof=2.9, fstop=8)
    compositor_glow(threshold=0.9, size=6, strength=0.5)
    render("x8_bolido_pista")
else:
    raise SystemExit("escena desconocida " + SCENE)
