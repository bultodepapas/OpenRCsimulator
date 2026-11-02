"""Real-time GLB of the engine (game / web viewer), from the built model:

  1. exterior parts only: flat ID renders from 26 directions; parts never seen are dropped (internals),
  2. one mesh per atlas group (body, head, carb, muffler, drive), evaluated in world space,
  3. low poly = planar dissolve + collapse decimation to a triangle budget, smooth by angle,
  4. smart UV + pack (blender-retopology-uv), one atlas per group,
  5. high -> low bake of the procedural aged materials (blender-texture-baking): base colour, roughness, metallic,
     tangent normal (bump + the detail lost to decimation), AO, packed ORM,
  6. one PBR material per group, base of the mounting lugs on z = 0, export GLB (blender-export-pipelines).

blender -b engine.blend -P export_rt.py -- --out f.glb [--budget 150000] [--res 2048] [--tex DIR] [--save f.blend]
"""
import json
import math
import os
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

S = os.environ.get("BLENDER_SKILLS", "/home/claude/ext/blender-skills-src/skills")
for sub in ("blender-texture-baking", "blender-retopology-uv", "blender-export-pipelines"):
    sys.path.insert(0, os.path.join(S, sub, "scripts"))
import bake_maps  # noqa: E402
import export_asset  # noqa: E402
import uv_pack  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


OUT = arg("--out")
BUDGET = int(arg("--budget", 150000))
RES = int(arg("--res", 2048))
MAXS = float(arg("--max-seconds", 0))      # stop cleanly before a new group once this much time is used
T_START = time.time()
TEX = arg("--tex", os.path.join(os.path.dirname(OUT), "textures_rt"))
os.makedirs(TEX, exist_ok=True)
sc = bpy.context.scene
log = {"t0": time.time()}
root = bpy.data.objects["Glow_Engine_61"]
root["crank_deg"] = 0.0
if "cutaway" in root.keys():
    root["cutaway"] = 0.0
root.update_tag()
bpy.context.view_layer.update()

# ------------------------------------------------------------------ 1. visibility
cands = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(("ENG_", "MUF_", "CARB_"))
         and not o.name.startswith(("ENG_Spinner", "ENG_Prop_Blades"))
         and all(not c.hide_render for c in o.users_collection)]
keep_hide = {o.name: o.hide_render for o in bpy.data.objects}
for o in bpy.data.objects:
    o.hide_render = o not in cands
for i, o in enumerate(cands):
    o.color = ((0.05 + 0.9 * (i % 12) / 11) ** 2.2, (0.05 + 0.9 * ((i // 12) % 12) / 11) ** 2.2,
               (0.05 + 0.9 * (i // 144) / 11) ** 2.2, 1.0)
r = sc.render
r.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.color_type = "FLAT", "OBJECT"
sh.show_cavity = sh.show_shadows = sh.show_object_outline = False
sc.display.render_aa = "OFF"
r.film_transparent = True
r.resolution_x = r.resolution_y = 640
r.resolution_percentage = 100
vs_keep = (sc.view_settings.view_transform, sc.view_settings.look, sc.view_settings.exposure, sc.view_settings.gamma)
try:
    sc.view_settings.view_transform = "Raw"
except TypeError:
    sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure, sc.view_settings.gamma = 0.0, 1.0


def to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


RAW = sc.view_settings.view_transform == "Raw"
# expected 8-bit code of every candidate's flat colour (decoded by nearest code, so either transform works)
codes = np.array([[round(255 * (v if RAW else to_srgb(v))) for v in o.color[:3]] for o in cands])
r.dither_intensity = 0.0
pts = [o.matrix_world @ Vector(c) for o in cands for c in o.bound_box]
lo_b = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi_b = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
ctr, rad = (lo_b + hi_b) / 2, (hi_b - lo_b).length / 2
cd = bpy.data.cameras.new("RT_Vis")
cd.type, cd.ortho_scale, cd.clip_start, cd.clip_end = "ORTHO", 2.1 * rad, 0.001, 10 * rad
cam = bpy.data.objects.new("RT_Vis", cd)
sc.collection.objects.link(cam)
sc.camera = cam
seen = np.zeros(len(cands), int)
dirs = [Vector((x, y, z)).normalized() for x in (-1, 0, 1) for y in (-1, 0, 1) for z in (-1, 0, 1) if (x, y, z) != (0, 0, 0)]
tmp = os.path.join(TEX, "_vis.png")
for d in dirs:
    cam.location = ctr + d * 3 * rad
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y" if abs(d.z) < 0.99 else "X").to_euler()
    r.filepath = tmp
    bpy.ops.render.render(write_still=True)
    im = np.asarray(bpy.data.images.load(tmp, check_existing=False).pixels[:]).reshape(640, 640, 4)
    px = np.round(im[..., :3] * 255).astype(int)[im[..., 3] > 0.5]
    if len(px):
        cols_, cnt_ = np.unique(px, axis=0, return_counts=True)
        for cval, c in zip(cols_, cnt_):
            dd = np.abs(codes - cval).max(1)
            k = int(dd.argmin())
            if dd[k] <= 1:
                seen[k] += c
for img in list(bpy.data.images):
    if img.filepath == tmp:
        bpy.data.images.remove(img)
os.remove(tmp)
vis = [o for i, o in enumerate(cands) if seen[i] >= 4]
log["dropped_hidden"] = sorted(o.name for i, o in enumerate(cands) if seen[i] < 4)
for o in bpy.data.objects:
    o.hide_render = keep_hide.get(o.name, o.hide_render)
sc.view_settings.view_transform, sc.view_settings.look, sc.view_settings.exposure, sc.view_settings.gamma = vs_keep
bpy.data.objects.remove(cam)

# ------------------------------------------------------------------ 2. groups
GROUPS = [  # name, prefixes, share of the triangle budget, atlas resolution factor
    ("Head", ("ENG_Head", "ENG_GlowPlug", "ENG_Gasket_Head", "ENG_Head_Bolt", "ENG_Screw_Head"), 0.17, 0.5),
    ("Carb", ("CARB_",), 0.20, 0.5),
    ("Muffler", ("MUF_",), 0.18, 0.5),
    ("Drive", ("ENG_Drive", "ENG_Prop", "ENG_Crankshaft_Thread", "ENG_Thrust", "ENG_Woodruff", "ENG_Crankshaft"), 0.07, 0.25),
    ("Body", ("ENG_",), 0.38, 1.0),
]


def group_of(name):
    for g, pre, _, _ in GROUPS:
        if name.startswith(pre):
            return g
    return "Body"


dg = bpy.context.evaluated_depsgraph_get()
col = bpy.data.collections.new("RT_Export")
sc.collection.children.link(col)
highs, lows = {}, {}
for g, _, share, rf in GROUPS:
    members = [o for o in vis if group_of(o.name) == g]
    if not members:
        continue
    bm = bmesh.new()
    mats, mat_index = [], {}
    for o in members:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
        me.transform(o.matrix_world)
        remap = []
        for m in me.materials:
            if m not in mat_index:
                mat_index[m] = len(mats)
                mats.append(m)
            remap.append(mat_index[m])
        for p in me.polygons:
            p.material_index = remap[p.material_index] if remap else 0
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    high_tris = sum(len(f.verts) - 2 for f in bm.faces)
    lm = bpy.data.meshes.new(f"RT_{g}")
    bm.to_mesh(lm)
    bm.free()
    for m in mats:
        lm.materials.append(m)
    highs[g] = [o.name for o in members]     # the original parts are the bake source (their own object space)
    for o in members:
        o.hide_set(False)
        o.hide_select = False
    # ---------------------------------------------------------------- 3. low poly
    lo_ob = bpy.data.objects.new(f"RT_{g}", lm)
    col.objects.link(lo_ob)
    lbm = bmesh.new()
    lbm.from_mesh(lm)
    bmesh.ops.remove_doubles(lbm, verts=lbm.verts[:], dist=2e-6)
    bmesh.ops.dissolve_limit(lbm, angle_limit=math.radians(0.6), verts=lbm.verts[:], edges=lbm.edges[:],
                             delimit={"MATERIAL"})
    bmesh.ops.triangulate(lbm, faces=lbm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    lbm.to_mesh(lm)
    lbm.free()
    target = int(BUDGET * share)
    tris = len(lm.polygons)
    if tris > target:
        md = lo_ob.modifiers.new("Decimate", "DECIMATE")
        md.decimate_type, md.ratio, md.use_collapse_triangulate = "COLLAPSE", target / tris, True
        md.delimit = {"MATERIAL", "SEAM", "SHARP"}
        bpy.context.view_layer.objects.active = lo_ob
        dg2 = bpy.context.evaluated_depsgraph_get()
        nm = bpy.data.meshes.new_from_object(lo_ob.evaluated_get(dg2), depsgraph=dg2)
        lo_ob.modifiers.clear()
        old = lo_ob.data
        lo_ob.data = nm
        bpy.data.meshes.remove(old)
        nm.name = f"RT_{g}"
        lm = nm
    lm.shade_smooth()
    lm.set_sharp_from_angle(angle=math.radians(35))
    lows[g] = lo_ob
    log[g] = {"parts": len(members), "high_tris": high_tris,
              "low_tris": sum(len(p.vertices) - 2 for p in lm.polygons), "atlas": int(RES * rf)}

# ------------------------------------------------------------------ 4. UVs
for g, lo_ob in lows.items():
    while lo_ob.data.uv_layers:
        lo_ob.data.uv_layers.remove(lo_ob.data.uv_layers[0])
    res_uv = uv_pack.run(objects=[lo_ob.name], method="smart", angle=70.0, res=log[g]["atlas"], margin_px=2)
    log[g]["uv"] = {k: v for k, v in (res_uv or {}).items() if k in ("ok", "efficiency", "islands", "texel_density")}

def orm_pack(g, rs, res1, res2):
    """ORM (glTF: R occlusion, G roughness, B metallic) from the baked maps; saved next to them."""
    def px(path):
        im = bpy.data.images.load(path if os.path.isabs(path) else bpy.path.abspath(path), check_existing=True)
        arr = np.empty(rs * rs * 4, np.float32)
        im.pixels.foreach_get(arr)
        return arr.reshape(-1, 4)
    ao, rg, mt = px(res2["maps"]["ao"]), px(res1["maps"]["roughness"]), px(res1["maps"]["metallic"])
    orm = np.stack([0.35 + 0.65 * ao[:, 0], rg[:, 0], mt[:, 0], np.ones(rs * rs, np.float32)], -1).ravel()
    oimg = bpy.data.images.new(f"T_Engine61_{g}_ORM", rs, rs, alpha=False, is_data=True)
    oimg.colorspace_settings.name = "Non-Color"
    oimg.pixels.foreach_set(orm)
    oimg.filepath_raw, oimg.file_format = os.path.join(TEX, f"T_Engine61_{g}_ORM.png"), "PNG"
    oimg.save()
    return oimg


# ------------------------------------------------------------------ 5. bake high -> low
for g, lo_ob in lows.items():
    rs = log[g]["atlas"]
    lo_mats = list(lo_ob.data.materials)
    lo_ob.data.materials.clear()
    bm_ = bpy.data.materials.new(f"M_RT_{g}")
    lo_ob.data.materials.append(bm_)
    for p in lo_ob.data.polygons:
        p.material_index = 0
    t0 = time.time()
    done = all(os.path.exists(os.path.join(TEX, f"T_Engine61_{g}_{k}.png")) for k in ("BC", "N", "ORM"))
    if done and "--rebake" not in a:
        # resumable: a group baked by an earlier run is reused (the low poly and its UVs are rebuilt identically)
        log[g]["bake_s"] = "reused"
        oimg = bpy.data.images.load(os.path.join(TEX, f"T_Engine61_{g}_ORM.png"), check_existing=True)
        oimg.colorspace_settings.name = "Non-Color"
    else:
        if MAXS and time.time() - T_START > MAXS:
            print(f"@@PARTIAL@@ stopping before {g}: time budget used; run again to continue", flush=True)
            sys.exit(3)
        res1 = bake_maps.run(low=lo_ob.name, high=highs[g], maps=["basecolor", "roughness", "metallic", "normal"], res=rs,
                             samples=6, margin_px=4, extrusion=0.0006, out=TEX, name=f"Engine61_{g}", device="CPU")
        res2 = bake_maps.run(low=lo_ob.name, high=highs[g], maps=["ao"], res=rs, samples=24, margin_px=8,
                             extrusion=0.0006, out=TEX, name=f"Engine61_{g}", device="CPU")
        log[g]["bake_s"] = round(time.time() - t0, 1)
        oimg = orm_pack(g, rs, res1, res2)
    # ---- material
    nt = bm_.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = bpy.data.images.load(os.path.join(TEX, f"T_Engine61_{g}_BC.png"), check_existing=True)
    tc.location = (-700, 300)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = oimg
    to.location = (-700, 0)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 0)
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = bpy.data.images.load(os.path.join(TEX, f"T_Engine61_{g}_N.png"), check_existing=True)
    tn.image.colorspace_settings.name = "Non-Color"
    tn.location = (-700, -300)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-400, -300)
    nt.links.new(tn.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    # occlusion for glTF: the exporter reads the R channel through a "glTF Material Output" group
    grp = bpy.data.node_groups.get("glTF Material Output")
    if grp is None:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = grp
    gn.location = (-100, -500)
    nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])

# ------------------------------------------------------------------ 6. assemble + export
zmin = min((lo.matrix_world @ v.co).z for lo in lows.values() for v in lo.data.vertices)
rt_root = bpy.data.objects.new("Glow_Engine_61_RT", None)
col.objects.link(rt_root)
for lo in lows.values():
    lo.parent = rt_root
rt_root.location = (0.0, 0.0, -zmin)      # mounting-lug base on the ground plane
bpy.context.view_layer.update()
res = export_asset.run(preset="gltf", objects=[rt_root.name], out=OUT, no_anim=True)
log["export"] = {k: v for k, v in (res or {}).items() if k in ("ok", "out", "bytes", "warnings")}
log["total_tris"] = sum(log[g]["low_tris"] for g in lows)
log["base_offset_mm"] = round(-zmin * 1000, 2)
log["seconds"] = round(time.time() - log.pop("t0"), 1)
if arg("--save"):
    bpy.ops.wm.save_as_mainfile(filepath=arg("--save"), compress=True)
json.dump(log, open(os.path.join(TEX, "rt_report.json"), "w"), indent=1)
print("@@JSON@@" + json.dumps(log, default=str))
