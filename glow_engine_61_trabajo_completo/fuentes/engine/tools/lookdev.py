"""Look-dev + render driver for the glow engine, built on the EL4CTEO blender-skills scripts.

  setup : hard-surface stack (apply_stack, render preset) on every part, studio turntable rig with
          cyclorama (turntable), gradient studio world for metal reflections, then save.
  render: Cycles stills through render_batch (frames = turntable angles), muffler on/off.
"""
import json
import math
import os
import sys

import bpy

S = os.environ.get("BLENDER_SKILLS", "/home/claude/ext/blender-skills-src/skills")
for sub in ("blender-hardsurface-modeling", "blender-lighting-lookdev", "blender-rendering"):
    sys.path.insert(0, os.path.join(S, sub, "scripts"))
import apply_stack  # noqa: E402
import render_batch  # noqa: E402
import turntable  # noqa: E402

MARK = "@@JSON@@"


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"stage": "setup", "save": None, "frames": "16", "out": "//render/shot_####", "muffler": "on",
         "samples": 128, "percent": 100, "res": (1600, 1200), "elevation": 18.0}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-")
        if k == "res":
            o["res"] = (int(a[i + 1]), int(a[i + 2]))
            i += 3
            continue
        o[k] = a[i + 1]
        i += 2
    return o


STACK = [  # (bevel width m, angle deg, segments, objects) - tuned per part against qa_check
    (0.00030, 60, 2, ["MUF_Can"]),
    (0.000315, 50, 2, ["ENG_Backplate"]),
    (0.000245, 50, 2, ["ENG_Cylinder_Fins"]),
    (0.00021, 50, 2, ["ENG_Head"]),
    (0.00010, 60, 2, ["ENG_Prop_Nut"]),
    (0.00020, 30, 3, ["ENG_Drive_Hub", "ENG_Prop_Washer"]),
    (0.00008, 45, 2, ["CARB_Barrel_Cap"]),
    (0.00010, 45, 2, ["CARB_SideNeedle_Holder", "CARB_SideNeedle_Ring"]),
    (0.00012, 60, 2, ["CARB_Barrel_End", "CARB_Arm_Hub", "CARB_Stop_Plate", "CARB_Top_Nut", "CARB_Barrel_Washer", "CARB_Barrel", "CARB_Barrel_Seal", "CARB_Arm_Hub", "CARB_Collar", "CARB_Spigot",
                      "CARB_Needle_Holder", "CARB_Needle_Sleeve", "CARB_Throttle_Arm", "CARB_Needle_LockNut",
                      "CARB_Mount_Screw_1", "CARB_Mount_Screw_2"]),
]
# ENG_Crankcase and CARB_Body: no bevel modifier. Their primitives are pre-rounded in bmesh and every
# bevel setting tried left self-overlaps at the boolean seams (qa_check z-fighting): smooth-by-angle only.
NO_BEVEL = ("ENG_Crankcase", "CARB_Body", "MUF_Can", "ENG_Head", "ENG_Cylinder_Fins", "ENG_Front_Housing",
            "ENG_Backplate", "ENG_Drive_Hub")  # pre-rounded in bmesh; boolean-heavy parts (hub: fine serrations)
WELD = {"CARB_Needle_Holder": 1e-5, "ENG_Head": 1e-5}


def studio_world(sc):
    """Soft grey gradient: dark floor, bright sky. Metals need something to reflect."""
    w = sc.world
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    for n in [n for n in nt.nodes if n.type in ("TEX_COORD", "SEPXYZ", "MAP_RANGE", "VALTORGB")]:
        nt.nodes.remove(n)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mr.inputs["From Min"].default_value = -0.3
    mr.inputs["From Max"].default_value = 1.0
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.0, (0.004, 0.004, 0.0045, 1)
    el[1].position, el[1].color = 1.0, (0.55, 0.56, 0.58, 1)
    mid = el.new(0.5)
    mid.color = (0.035, 0.035, 0.037, 1)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35


def setup(o):
    sc = bpy.context.scene
    rep = {}
    for w, ang, seg, names in STACK:
        names = [n for n in names if n in bpy.data.objects]
        if not names:  # an empty list would make apply_stack fall back to every visible mesh
            continue
        rep.update(apply_stack.run(objects=names, preset="render", width=w, segments=seg, angle=ang)["objects"])
    no_bevel = list(NO_BEVEL)
    root = bpy.data.objects.get("Glow_Engine_61")
    if root is not None and root.get("variant") == "standard":
        no_bevel.append("ENG_Head")  # deep grooves: any bevel width collapses into zero-area faces
    for n in no_bevel:
        if n in bpy.data.objects:
            ob = bpy.data.objects[n]
            for m in [m for m in ob.modifiers if m.name.startswith("HS_")]:
                ob.modifiers.remove(m)
            ob.data.set_sharp_from_angle(angle=math.radians(30))
    for n, th in WELD.items():  # merge the sub-0.01 mm slivers the bevel leaves on these parts
        ob = bpy.data.objects.get(n)
        if ob is not None and "HS_WeightedNormal" in ob.modifiers:
            w = ob.modifiers.new("HS_Weld", "WELD")
            w.merge_threshold = th
            ob.modifiers.move(len(ob.modifiers) - 1, [m.name for m in ob.modifiers].index("HS_WeightedNormal"))
    # threaded fasteners: no bevel (0.1 mm bevels on 0.08 mm thread facets make degenerate geometry); crisp edges
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.name.startswith(("ENG_Screw_", "MUF_Bolt_", "ENG_Head_Screw_")):
            ob.data.set_sharp_from_angle(angle=math.radians(40))
    for ob in bpy.data.objects:  # section booleans (cutaway) evaluate after the bevel/normal stack
        cut = [m.name for m in ob.modifiers if m.name.startswith("CUT_")]
        for name in cut:
            ob.modifiers.move(list(ob.modifiers).index(ob.modifiers[name]), len(ob.modifiers) - 1)
    sc.render.resolution_x, sc.render.resolution_y = o["res"]
    assets = [ob.name for ob in bpy.data.objects if ob.type == "MESH" and ob.name.startswith(("ENG_", "MUF_", "CARB_"))]
    tt = turntable.run(objects=assets, rig="studio", frames=120, lens=float(o.get("lens", 115)), backdrop=True,
                       elevation=float(o["elevation"]))
    studio_world(sc)
    cam = bpy.data.objects[tt["camera"]]
    # tighter framing for stills: dolly in toward the pivot (the camera stays parented)
    piv = bpy.data.objects[tt["pivot"]]
    bpy.context.view_layer.update()
    k = float(o.get("dolly", 0.78))
    mw = cam.matrix_world.copy()
    c = piv.matrix_world.translation
    mw.translation = c + (mw.translation - c) * k
    cam.matrix_world = mw
    # extra still camera: high three-quarter view from the front-left (shows the head fins)
    cd = bpy.data.cameras.new("CAM_Top34")
    cd.lens, cd.clip_start, cd.clip_end = cam.data.lens, cam.data.clip_start, cam.data.clip_end
    cd.dof.use_dof, cd.dof.focus_object, cd.dof.aperture_fstop = True, piv, float(o.get("fstop", 11.0))
    ct = bpy.data.objects.new("CAM_Top34", cd)
    az, el = math.radians(35), math.radians(48)
    from mathutils import Vector
    dist = (cam.matrix_world.translation - c).length * 1.18
    ct.location = c + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
    ct.rotation_euler = (c - ct.location).to_track_quat("-Z", "Y").to_euler()
    bpy.data.collections["LD_Lookdev"].objects.link(ct)
    # optional close perspective hero camera: --hero "azimuth_deg,elevation_deg,lens_mm,distance_factor"
    if o.get("hero"):
        az_h, el_h, lens_h, k_h = (float(v) for v in o["hero"].split(","))
        chd = bpy.data.cameras.new("CAM_Hero")
        chd.lens, chd.clip_start, chd.clip_end = lens_h, cam.data.clip_start / 4, cam.data.clip_end
        chd.dof.use_dof, chd.dof.focus_object, chd.dof.aperture_fstop = True, piv, float(o.get("fstop", 11.0)) * 1.5
        ch = bpy.data.objects.new("CAM_Hero", chd)
        a_, e_ = math.radians(az_h), math.radians(el_h)
        ch.location = c + Vector((math.sin(a_) * math.cos(e_), -math.cos(a_) * math.cos(e_), math.sin(e_))) * dist * k_h
        ch.rotation_euler = (c - ch.location).to_track_quat("-Z", "Y").to_euler()
        bpy.data.collections["LD_Lookdev"].objects.link(ch)
    # darker studio sweep so the metals have contrast to reflect
    bd = bpy.data.objects.get("LD_Backdrop")
    if bd:
        bsdf = next(n for n in bd.data.materials[0].node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        g = float(o.get("backdrop", 0.06))
        bsdf.inputs["Base Color"].default_value = (g, g, g, 1)
        bsdf.inputs["Roughness"].default_value = 0.55
    cam.data.dof.use_dof = True
    cam.data.dof.focus_object = bpy.data.objects[tt["pivot"]]
    cam.data.dof.aperture_fstop = float(o.get("fstop", 11.0))
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    sc.view_settings.exposure = float(o.get("exposure", -1.3))
    sc.cycles.max_bounces, sc.cycles.glossy_bounces = 12, 6
    sc.cycles.sample_clamp_indirect = 8.0
    sc.frame_set(16)
    tris = sum(apply_stack.bx.mesh_tris(bpy.data.objects[n]) for n in assets)
    sc.frame_set(int(o.get("frame", 16)))
    if o["save"]:
        bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(o["save"]))
    return {"ok": True, "stack_objects": len(rep), "turntable": tt, "tris_evaluated": tris,
            "saved": o["save"]}


def render(o):
    sc = bpy.context.scene
    if "exposure" in o:
        sc.view_settings.exposure = float(o["exposure"])
    if "world" in o:
        next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Strength"].default_value = float(o["world"])
    if "lights" in o:
        for ob in bpy.data.objects:
            if ob.type == "LIGHT" and ob.name.startswith("LD_"):
                ob.data.energy *= float(o["lights"])
    show = o["muffler"] == "on"
    muf = bpy.data.collections.get("E61_Muffler") or bpy.data.collections.get("Muffler")
    if muf:
        muf.hide_render = not show
    for ob in bpy.data.objects:
        if ob.name.startswith("MUF_"):
            ob.hide_render = not show
    return render_batch.run(engine="CYCLES", preset="final", samples=int(o["samples"]), res=o["res"],
                            percent=int(o["percent"]), out=o["out"], format="PNG", frames=o["frames"],
                            cameras=[o["camera"]] if o.get("camera") else None,
                            view="Khronos PBR Neutral", device="CPU")


if __name__ == "__main__":
    o = args()
    try:
        res = setup(o) if o["stage"] == "setup" else render(o)
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        res = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    print(MARK + json.dumps(res, default=str), flush=True)
