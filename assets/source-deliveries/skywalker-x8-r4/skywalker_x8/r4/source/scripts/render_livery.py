"""Renders de la librea ABISAL en Cycles (solo imagenes; no modifica el .blend del juego).

  python render_livery.py source/aircraft_game.blend textures/source previews/renders <escena> [muestras]

Escenas: noche (vuelo nocturno sobre el mar), estudio (3/4 con luz suave), planta (desde
arriba y atras), boca (primer plano de
la nariz), panza (desde abajo al atardecer), ojo (winglet), cola (helice y advertencias).
El material de render usa las fuentes 4096 y suma lo que glTF no lleva: pelicula delgada
(iridiscencia de las escamas), barniz en ojos y fotoforos y emision con intensidad alta.
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
sc.cycles.transmission_bounces = 2
sc.cycles.caustics_reflective = False
sc.cycles.caustics_refractive = False
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.render.resolution_percentage = PCT
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Punchy"
sc.render.film_transparent = False

# ------------------------------------------------------------------ material de render


def img(name, cs):
    im = bpy.data.images.load(os.path.join(SRC, name))
    im.colorspace_settings.name = cs
    return im


def livery_render(emit):
    m = bpy.data.materials.new("x8_livery_render")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])

    def tex(name, cs):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img(name, cs)
        t.interpolation = "Cubic" if "normal" not in name else "Linear"
        return t
    nt.links.new(tex("x8_abisal_base_color.png", "sRGB").outputs[0], b.inputs["Base Color"])
    nt.links.new(tex("x8_abisal_roughness.png", "Non-Color").outputs[0], b.inputs["Roughness"])
    nt.links.new(tex("x8_abisal_metallic.png", "Non-Color").outputs[0], b.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = "UVMap"
    nm.inputs["Strength"].default_value = 1.6
    nt.links.new(tex("x8_abisal_normal.png", "Non-Color").outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], b.inputs["Normal"])
    nt.links.new(nm.outputs[0], b.inputs["Coat Normal"])
    nt.links.new(tex("x8_abisal_emission.png", "sRGB").outputs[0], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = emit
    ir = tex("x8_abisal_iridescence.png", "Non-Color")
    mth = nt.nodes.new("ShaderNodeMapRange")              # solo los bordes de las escamas
    mth.inputs["From Min"].default_value = 0.3
    mth.inputs["From Max"].default_value = 1.0
    mth.inputs["To Min"].default_value = 0.0
    mth.inputs["To Max"].default_value = 560.0
    nt.links.new(ir.outputs[0], mth.inputs["Value"])
    nt.links.new(mth.outputs["Result"], b.inputs["Thin Film Thickness"])
    b.inputs["Thin Film IOR"].default_value = 1.45
    co = tex("x8_abisal_coat.png", "Non-Color")
    nt.links.new(co.outputs[0], b.inputs["Coat Weight"])
    b.inputs["Coat Roughness"].default_value = 0.03
    b.inputs["Specular IOR Level"].default_value = 0.55
    return m


def apply_render_material(emit):
    m = livery_render(emit)
    for name in S.LIVERY_PARTS:
        me = ob[name].data
        for i, mm in enumerate(me.materials):
            if mm and mm.name == "x8_livery":
                me.materials[i] = m


# ------------------------------------------------------------------ pose de vuelo
REST = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}


def pose(**ang):
    for n, mtx in REST.items():
        ob[n].matrix_basis = mtx @ Matrix.Rotation(math.radians(ang.get(n, 0.0)), 4, "X")


def spin_blur(deg_per_frame=70.0):
    """La helice gira entre el fotograma 1 y 2; el desenfoque de movimiento hace el disco."""
    n = "propeller_spin"
    o = ob[n]
    o.rotation_mode = "QUATERNION"
    for f, a in ((1, 0.0), (2, deg_per_frame)):
        o.matrix_basis = REST[n] @ Matrix.Rotation(math.radians(a), 4, "X")
        o.keyframe_insert("rotation_quaternion", frame=f)
    for fc in (o.animation_data.action.fcurves if hasattr(o.animation_data.action, "fcurves") else []):
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
    sc.render.use_motion_blur = True
    sc.render.motion_blur_shutter = 0.5
    sc.frame_set(1)


root = ob[S.ROOT]


def place_aircraft(loc=(0, 0, 0), rot_deg=(0, 0, 0)):
    root.matrix_world = Matrix.Translation(loc) @ Euler(tuple(math.radians(a) for a in rot_deg),
                                                        "XYZ").to_matrix().to_4x4()


def camera(loc, target, lens=50, dof=None, fstop=4.0):
    cam = bpy.data.objects.new("CAM", bpy.data.cameras.new("CAM"))
    sc.collection.objects.link(cam)
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.data.clip_end = 2000
    if dof:
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = dof
        cam.data.dof.aperture_fstop = fstop
    sc.camera = cam
    return cam


def light(kind, loc, rot, energy, color=(1, 1, 1), size=1.0, angle=None, aim=None):
    ld = bpy.data.lights.new(kind + "_L", kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
        ld.shape = "DISK"
    if kind == "SUN" and angle is not None:
        ld.angle = math.radians(angle)
    lo = bpy.data.objects.new(kind + "_L", ld)
    sc.collection.objects.link(lo)
    lo.location = loc
    lo.rotation_euler = Euler(tuple(math.radians(a) for a in rot))
    if aim is not None:                       # apuntar la luz a un punto
        lo.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return lo


def world_gradient(horizon, zenith, strength=1.0, ground=None):
    w = sc.world or bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
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
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs[0])


def ocean(z=-25.0, size=400.0, color=(0.004, 0.012, 0.02)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    pl = bpy.context.active_object
    pl.name = "OCEANO"
    md = pl.modifiers.new("Oceano", "OCEAN")
    md.resolution = 12
    md.spatial_size = 60
    md.wave_scale = 0.6
    md.choppiness = 1.1
    md.wind_velocity = 9
    md.repeat_x = md.repeat_y = 7
    md.size = 1.0
    m = bpy.data.materials.new("agua")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.06
    b.inputs["IOR"].default_value = 1.33
    pl.data.materials.append(m)
    for p in pl.data.polygons:
        p.use_smooth = True
    return pl


def compositor_glow(threshold=0.6, mix=0.0, size=7):
    sc.use_nodes = True
    try:
        tree = sc.compositing_node_group
        if tree is None:
            tree = bpy.data.node_groups.new("Compositor", "CompositorNodeTree")
            sc.compositing_node_group = tree
        for n in list(tree.nodes):
            tree.nodes.remove(n)
        rl = tree.nodes.new("CompositorNodeRLayers")
        gl = tree.nodes.new("CompositorNodeGlare")
        out = tree.nodes.new("NodeGroupOutput")
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        for k, v in (("Type", "Bloom"), ("Threshold", threshold), ("Size", size / 9.0),
                     ("Strength", 0.9)):
            if k in gl.inputs:
                try:
                    gl.inputs[k].default_value = v
                except Exception:
                    pass
        if hasattr(gl, "glare_type"):
            gl.glare_type = "BLOOM"
        tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
        tree.links.new(gl.outputs["Image"], out.inputs[0])
    except Exception as e:                       # API antigua del compositor
        print("compositor:", e)
        tree = sc.node_tree
        for n in list(tree.nodes):
            tree.nodes.remove(n)
        rl = tree.nodes.new("CompositorNodeRLayers")
        gl = tree.nodes.new("CompositorNodeGlare")
        gl.glare_type = "FOG_GLOW"
        gl.threshold = threshold
        gl.size = size
        cp = tree.nodes.new("CompositorNodeComposite")
        tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
        tree.links.new(gl.outputs["Image"], cp.inputs["Image"])


def render(name):
    sc.render.filepath = os.path.join(OUT, name + ".png")
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("RENDER", sc.render.filepath)


# ------------------------------------------------------------------ escenas
if SCENE == "noche":
    apply_render_material(emit=12.0)
    place_aircraft((0, 0, 0), (0, -22, 12))
    pose(elevon_left_hinge=7, elevon_right_hinge=-7)
    spin_blur(80)
    world_gradient((0.060, 0.090, 0.150), (0.004, 0.007, 0.016), 1.0, ground=(0.006, 0.010, 0.018))
    ocean(-14.0, size=600)
    light("SUN", (0, 0, 10), (-64, 0, -135), 2.6, (0.62, 0.74, 1.0), angle=0.9)
    light("AREA", (0.3, 0.2, -2.6), (180, 0, 0), 90, (0.18, 0.42, 0.85), size=5)
    light("AREA", (-2.4, 2.6, 2.4), (0, 0, 0), 120, (0.5, 0.65, 1.0), size=3, aim=(0, -0.2, 0))
    camera((-2.35, 2.15, 1.35), (0.05, -0.32, -0.18), lens=42, dof=3.3, fstop=5.6)
    compositor_glow(threshold=0.45, size=8)
    render("x8_abisal_noche")
elif SCENE in ("estudio", "planta"):
    apply_render_material(emit=2.0)
    place_aircraft((0, 0, 0), (0, 0, 0))
    spin_blur(0.0)
    sc.render.use_motion_blur = False
    world_gradient((0.09, 0.095, 0.11), (0.015, 0.017, 0.022), 0.6, ground=(0.01, 0.01, 0.012))
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.32))
    fl = bpy.context.active_object
    fm = bpy.data.materials.new("piso")
    fm.use_nodes = True
    fb = fm.node_tree.nodes["Principled BSDF"]
    fb.inputs["Base Color"].default_value = (0.012, 0.013, 0.016, 1)
    fb.inputs["Roughness"].default_value = 0.8
    fl.data.materials.append(fm)
    light("AREA", (0.0, -0.1, 3.2), (0, 0, 0), 520, (1.0, 0.97, 0.93), size=3.5)
    light("AREA", (2.6, 2.4, 1.2), (65, 0, 133), 220, (0.85, 0.9, 1.0), size=2.0)
    light("AREA", (-2.6, -1.6, 0.9), (70, 0, -60), 160, (1.0, 0.85, 0.7), size=1.6)
    light("AREA", (-2.4, 1.8, 0.4), (80, 0, -125), 140, (0.7, 0.8, 1.0), size=1.6)
    if SCENE == "planta":
        camera((0.95, -2.75, 2.65), (0.0, -0.16, -0.05), lens=40, dof=3.75, fstop=11)
        render("x8_abisal_planta")
    else:
        camera((-1.95, 1.30, 0.70), (0.25, -0.30, -0.06), lens=42, dof=2.65, fstop=8)
        render("x8_abisal_estudio")
elif SCENE == "boca":
    apply_render_material(emit=5.0)
    place_aircraft()
    sc.render.use_motion_blur = False
    world_gradient((0.02, 0.03, 0.05), (0.004, 0.006, 0.012), 1.0)
    light("AREA", (0.30, 0.75, -0.22), (0, 0, 0), 22, (1.0, 0.95, 0.9), size=0.35,
          aim=(0.0, 0.28, 0.0))
    light("AREA", (-0.45, 0.55, 0.35), (0, 0, 0), 14, (0.4, 0.7, 1.0), size=0.5,
          aim=(0.0, 0.2, 0.02))
    light("AREA", (0.0, 0.05, 0.8), (0, 0, 0), 10, (0.55, 0.65, 1.0), size=0.8,
          aim=(0.0, 0.2, 0.0))
    camera((0.20, 0.66, -0.045), (0.0, 0.27, -0.002), lens=80, dof=0.43, fstop=4)
    compositor_glow(threshold=0.6, size=7)
    render("x8_abisal_boca")
elif SCENE == "panza":
    apply_render_material(emit=6.0)
    place_aircraft((0, 0, 0), (0, 10, 0))
    spin_blur(80)
    world_gradient((0.55, 0.28, 0.16), (0.05, 0.08, 0.18), 1.2, ground=(0.03, 0.03, 0.04))
    light("SUN", (0, 0, 10), (95, 0, 30), 2.2, (1.0, 0.62, 0.38), angle=1.0)
    light("AREA", (0.0, 0.0, -3.0), (180, 0, 0), 60, (0.35, 0.45, 0.6), size=5)
    camera((0.75, 0.85, -2.05), (0.0, -0.18, 0.0), lens=40, dof=2.3, fstop=8)
    compositor_glow(threshold=0.7, size=7)
    render("x8_abisal_panza")
elif SCENE == "ojo":
    apply_render_material(emit=4.0)
    place_aircraft()
    sc.render.use_motion_blur = False
    world_gradient((0.03, 0.04, 0.07), (0.005, 0.007, 0.015), 1.0)
    light("AREA", (1.7, -0.3, 0.5), (0, 0, 0), 30, (0.95, 0.95, 1.0), size=0.8, aim=(1.015, -0.538, 0.113))
    light("AREA", (1.3, -1.2, -0.2), (0, 0, 0), 12, (0.4, 0.6, 1.0), size=0.6, aim=(1.015, -0.538, 0.113))
    camera((1.47, -0.40, -0.07), (1.012, -0.545, 0.113), lens=85, dof=0.52, fstop=2.8)
    compositor_glow(threshold=0.6, size=7)
    render("x8_abisal_ojo")
elif SCENE == "cola":
    apply_render_material(emit=4.0)
    place_aircraft()
    spin_blur(60)
    world_gradient((0.05, 0.06, 0.08), (0.01, 0.012, 0.02), 1.0)
    light("AREA", (-0.8, -1.2, 0.9), (50, 0, -140), 80, (1.0, 0.93, 0.85), size=1.0)
    light("AREA", (0.9, -0.9, 0.3), (70, 0, 140), 30, (0.4, 0.6, 1.0), size=0.8)
    camera((-0.55, -1.25, 0.42), (0.0, -0.5, 0.02), lens=60, dof=0.95, fstop=4)
    compositor_glow(threshold=0.6, size=7)
    render("x8_abisal_cola")
else:
    raise SystemExit("escena desconocida " + SCENE)
