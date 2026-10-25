"""Genera metadata.json y export-map.json del paquete.

  python make_metadata.py <aircraft_game.blend> <aircraft.glb> <aircraft_demo.glb> \
         <maestro Skywalker_X8.blend> <raiz del paquete>

Todas las medidas salen de vertices transformados del .blend de juego (no de cajas rotadas).
"""
import sys, os, json, math, hashlib, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Vector, Matrix
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
GAME, GLB, DEMO, MASTER, PKG = (os.path.abspath(a) for a in argv[:5])


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def r(v, n=6):
    return [round(float(c), n) for c in v]


def point(v, src, note="", evidence="model measurement"):
    return dict(blender_m=r(v), godot_m=r(S.to_godot(v)), evidence=evidence, source=src, note=note)


# ------------------------------------------------------------------ inventario del maestro
bpy.ops.wm.open_mainfile(filepath=MASTER)
MASTER_OBJS = sorted((o.name, o.type) for o in bpy.data.objects)

# ------------------------------------------------------------------ escena de juego
bpy.ops.wm.open_mainfile(filepath=GAME)
sc = bpy.context.scene
sc.frame_set(1)
ob = bpy.data.objects
INFO = json.loads(bpy.data.texts["build_info.json"].as_string())
D0 = INFO["D0_master_mm"]


def wverts(name):
    o = ob[name]
    return [o.matrix_world @ v.co for v in o.data.vertices]


core = wverts("fuselage_core")
rotor = wverts("propeller_rotor")
wl, wr = wverts("wing_left_fixed"), wverts("wing_right_fixed")
allv = [v for o in ob if o.type == "MESH" for v in wverts(o.name)]
x_root = (236.0 + 1.5 + INFO["game_resolution"]["joint_clear"]) / 1000
L = {}
L["D0"] = point(Vector((0, 0, 0)), "definition", "symmetry plane; leading edge of the wing at the "
                "orange root rib station (s = 236 mm); thrust-axis (motor shaft) height",
                evidence="datum")
L["nose_tip"] = point(max(core, key=lambda v: v.y), "fuselage_core vertices (max +Y)")
L["fuselage_tail"] = point(min(core, key=lambda v: v.y), "fuselage_core vertices (min Y)")
L["spinner_tip"] = point(min(rotor, key=lambda v: v.y), "propeller_rotor vertices (min Y)",
                         "pusher: the spinner points aft")
L["wingtip_left"] = point(min(wl, key=lambda v: v.x), "wing_left_fixed vertices (min X)",
                          "outermost point, winglet included")
L["wingtip_right"] = point(max(wr, key=lambda v: v.x), "wing_right_fixed vertices (max X)",
                           "outermost point, winglet included")
L["winglet_top_left"] = point(max(wl, key=lambda v: v.z), "wing_left_fixed vertices (max Z)")
L["winglet_top_right"] = point(max(wr, key=lambda v: v.z), "wing_right_fixed vertices (max Z)")
for side, vs, sg in (("left", wl, -1), ("right", wr, 1)):
    rs = [v for v in vs if abs(v.x - sg * x_root) < 5e-5]
    L[f"wing_root_leading_edge_{side}"] = point(
        max(rs, key=lambda v: v.y), f"wing_{side}_fixed root section vertices (s = "
        f"{x_root*1000:.1f} mm), max +Y", "root skin section just outboard of the orange rib")
hub = ob["thrust_frame"].matrix_world.translation
L["propeller_hub"] = point(hub, "thrust_frame origin")
loc_rot = [v.co for v in ob["propeller_rotor"].data.vertices]
prop_R = max(math.hypot(v.y, v.z) for v in loc_rot)
L["lowest_point"] = point(min(allv, key=lambda v: v.z), "all exported mesh vertices (min Z)")
L["highest_point"] = point(max(allv, key=lambda v: v.z), "all exported mesh vertices (max Z)")
x_d0 = D0["x_from_nose"]
L["cg_reference_manufacturer_430mm"] = point(Vector((0, (x_d0 - 430) / 1000, 0)),
                                             "Skywalker spec sheet: CG 430-440 mm from the nose",
                                             "reference station only, not a measurement of this "
                                             "aircraft; height not specified", "manual value")
L["cg_reference_manufacturer_440mm"] = point(Vector((0, (x_d0 - 440) / 1000, 0)),
                                             "Skywalker spec sheet / Gryte et al. 2018: 440 mm",
                                             "reference station only", "manual value")

ART = {}
for name, a in S.ARTICULATIONS.items():
    piv = ob[name]
    child = ob[a["child"]]
    mw = piv.matrix_world
    ax = (mw.to_3x3() @ Vector((1, 0, 0))).normalized()
    lv = [v.co for v in child.data.vertices]
    rec = dict(
        child=child.name, parent=piv.parent.name, section=piv.get(S.SECTION_KEY),
        frame="root SkywalkerX8 (D0), metres",
        pivot_blender_m=r(mw.translation), pivot_godot_m=r(S.to_godot(mw.translation)),
        axis_blender=r(ax, 8), axis_godot=r(S.to_godot(ax), 8),
        rest_local=dict(translation_m=r(piv.matrix_basis.translation),
                        rotation_quaternion_wxyz=r(piv.matrix_basis.to_quaternion(), 8),
                        matrix_rows=[r(row, 8) for row in piv.matrix_basis]),
        rotation_rule="local = rest * rotation_about_local_X(angle); angle 0 = saved rest",
        positive_direction=a["positive"])
    if a["kind"] == "elevon":
        near = [v for v in lv if abs(v.y) < 0.003]
        t0, t1 = min(v.x for v in near), max(v.x for v in near)
        rec["hinge_line_blender_m"] = [r(mw @ Vector((t0, 0, 0))), r(mw @ Vector((t1, 0, 0)))]
        rec["hinge_line_godot_m"] = [r(S.to_godot(mw @ Vector((t0, 0, 0)))),
                                     r(S.to_godot(mw @ Vector((t1, 0, 0))))]
        rec["mesh_members_from_master"] = ["X8_Elevon_*", "X8_Cuerno_* (control horn)",
                                           "hinge-tape region and slot cover (black)"]
        c515 = 70.0 + (58.0 - 70.0) * (515.0 - 242.0) / (878.0 - 242.0)
        rec["ranges"] = [
            dict(name=k, deg=v, unit="degree", evidence="model-derived (linkage geometry), not "
                 "measured on hardware", source="master v3.1 rig, x8_logica_mandos.cadena, default "
                 "radio config (expo 0.25, pitch mix 0.70, roll mix 0.85, servo +-45 deg)")
            for k, v in S.ELEVON_RANGES.items()]
        rec["linear_travel_at_link_station"] = dict(
            station_s_mm=515.0, elevon_chord_mm=round(c515, 2),
            te_travel_mm_at_mechanical_limits=[round(c515 * math.sin(math.radians(d)), 1)
                                               for d in S.ELEVON_RANGES["mechanical_full_servo_travel"]],
            evidence="derived: chord x sin(angle) at the pushrod station; no measured mm throws "
                     "exist for this model")
    elif a["kind"] == "door":
        t0, t1 = min(v.x for v in lv), max(v.x for v in lv)
        rec["hinge_line_blender_m"] = [r(mw @ Vector((t0, 0, 0))), r(mw @ Vector((t1, 0, 0)))]
        rec["ranges"] = [dict(name="open", deg=S.DOOR_RANGE, unit="degree",
                              evidence="model design value, clearance-verified",
                              source="master v3.1 DOOR_DEG; 110 deg keeps an 80 deg camera cone clear")]
        rec["mesh_members_from_master"] = ["X8_Compuerta_Camara_*"]
        rec["mechanism_support"] = ("not one of the shared auxiliary mechanism roles (canopy, "
                                    "tailhook, cowl flaps); delivered as a hinge-style pivot rotating "
                                    "about local +X, closed at rest; needs integration review before "
                                    "any runtime use")
    else:
        rec["ranges"] = [dict(name="spin", deg="continuous", unit="degree",
                              evidence="free rotation", source="pusher propeller")]
        rec["propeller_diameter_m"] = round(2 * prop_R, 5)
        rec["propeller_nominal"] = "12x8 in folding (manufacturer sheet): 0.3048 m"
        rec["thrust_axis_direction_blender"] = r(ax, 8)
        rec["thrust_axis_direction_godot"] = r(S.to_godot(ax), 8)
        rec["thrust_angles_deg"] = dict(down=0.0, right=0.0, evidence="model (motor axis parallel "
                                                                       "to the root chord datum)")
        rec["mesh_members_from_master"] = ["X8_Pala_1", "X8_Pala_2", "X8_Buje_Helice",
                                           "X8_Cono_Helice", "X8_Motor_Campana (outrunner bell)",
                                           "X8_Eje (shaft)"]
    ART[name] = rec

ver_path = os.path.join(PKG, "verification.json")
if os.path.exists(ver_path):
    V = json.load(open(ver_path))
    for k, e in V.get("clearance", {}).get("elevons", {}).items():
        ART[f"{k}_hinge"]["clearance_envelope_deg"] = dict(
            free=e["clear_deg"], step=e["step_deg"],
            note="first contact beyond these angles; reported, not clamped")

sections = {}
for n, p, t, sec in S.NODES:
    if sec:
        sections.setdefault(sec, []).append(n)
counts = {}
tri_total = surf = 0
for o in ob:
    if o.type == "MESH":
        o.data.calc_loop_triangles()
        mats = sorted({o.data.materials[p.material_index].name for p in o.data.polygons})
        counts[o.name] = dict(triangles=len(o.data.loop_triangles), surfaces=len(mats),
                              materials=mats)
        tri_total += len(o.data.loop_triangles)
        surf += len(mats)

# ------------------------------------------------------------------ materiales y libreas (r2, r3)
from PIL import Image as _PIL
TEXROOT = os.path.join(PKG, "textures")
used_mats = sorted({mn for v in counts.values() for mn in v["materials"]})
MATS = []
for mn in used_mats:
    if mn == S.LIVERY_MATERIAL:
        MATS.append(dict(name=mn, base_color=f"texture {S.LIVERY_IMAGES[0]} (default livery)",
                         roughness=f"texture {S.LIVERY_IMAGES[1]} (G)",
                         metallic=f"texture {S.LIVERY_IMAGES[1]} (B)",
                         textures=list(S.LIVERY_IMAGES), uv_map="UVMap (TEXCOORD_0)",
                         skins={k: list(S.livery_images(k)) for k in S.LIVERIES}))
    else:
        v = S.MATERIALS[mn]
        MATS.append(dict(name=mn, base_color=list(v["color"]), roughness=v["rough"],
                         metallic=v["metal"], textures=None))
uv_area = uv_cov = 0.0
for nme in S.LIVERY_PARTS:
    me = ob[nme].data
    me.calc_loop_triangles()
    uvd = me.uv_layers["UVMap"].data
    mnames = [m.name for m in me.materials]
    for t in me.loop_triangles:
        if mnames[t.material_index] == S.LIVERY_MATERIAL:
            a_, b_, c_ = (uvd[l].uv.copy() for l in t.loops)
            uv_cov += abs((b_ - a_).cross(c_ - a_)) / 2
            uv_area += t.area
ATLAS = dict(uv_coverage=round(uv_cov, 4), painted_area_m2=round(uv_area, 4),
             mm_per_texel_runtime=round((uv_area / (uv_cov * S.LIVERY_RES_RUNTIME ** 2)) ** 0.5
                                        * 1000, 3),
             mm_per_texel_source=round((uv_area / (uv_cov * S.LIVERY_RES_SOURCE ** 2)) ** 0.5
                                       * 1000, 3),
             unwrap="Smart UV Project (angle 1.15 rad) + Pack Islands (concave, margin 0.003)",
             material=S.LIVERY_MATERIAL, uv_map="UVMap", painted_parts=list(S.LIVERY_PARTS),
             regions={"0": "skin", "1": "hinge tape", "2": "servo cover", "3": "orange plastic "
                      "(root ribs, control horns)", "4": "propeller blades and spinner"},
             region_attributes="face attributes x8_part / x8_region on each painted mesh",
             shared_by_all_liveries=True)
SLOT_USE = {"base_color.jpg": ("baseColorTexture", "sRGB", "RGB albedo, JPEG q92"),
            "orm.png": ("occlusionTexture (R) + metallicRoughnessTexture (G rough, B metal)",
                        "linear", "R = 0.25 + 0.75 x baked AO, G roughness, B metallic"),
            "normal.png": ("normalTexture", "linear", "tangent space, MikkTSpace, +Y up "
                           "(glTF/OpenGL); tangents exported in the GLB"),
            "emission.jpg": ("emissiveTexture (emissiveFactor 1,1,1)", "sRGB",
                             "emissive colour; black = no emission")}
INFO_LIV = {
    "abisal": dict(
        title="ABISAL", revision_added="r2",
        concept="Deep-sea anglerfish skin on a flying wing: blue-black body with iridescent scales "
                "on the back, silver-violet belly with rows of photophores, segmented fin rays on "
                "the wings with a violet trailing edge, a bioluminescent lateral line, an open mouth "
                "with fangs and a glowing lure on the nose, false eyes on the winglets, coral gill "
                "slits at the wing root; worn like a working UAV (chipped edges showing EPO foam, "
                "belly scrapes and grass stains, insects on leading edges, dirt in seams, hand "
                "prints, a tape repair, faded technical stencils).",
        invented_texts=["ABISAL", "X8-08", "ABISAL-08", "Spanish stencils"],
        emission="bioluminescence (lateral line, photophores, lure, eye rings, prop tips)",
        render_only=["iridescence of the scales (thin film)", "clear coat on eyes, photophores "
                     "and lure", "emission strength above 1 and bloom", "4096 source resolution"]),
    "bolido": dict(
        title="BOLIDO", revision_added="r3",
        concept="Re-entry demonstrator inspired by the Space Shuttle thermal protection system: "
                "black reaction-cured-glass ceramic tiles on the underside (22 mm, laid along the "
                "body axis, the leading-edge sweep and the hinge line), each tile with its own age "
                "tone, part number and waterproofing holes, replaced tiles in fresh gloss black; "
                "white 44 mm tiles at the black/white transition; cream quilted insulation "
                "blankets on top; grey carbon-carbon nose cap and leading-edge panels with T-seals; "
                "white felt on the elevons; a temper-coloured metal heat shield around the motor. "
                "Use: plasma bleaching and flow streaks on the belly (strongest at the nose and "
                "leading edges), tobacco-brown heat stains on the blankets, chipped tiles showing "
                "white silica, one missing tile with the felt pad, primer and adhesive exposed, "
                "protruding gap fillers, grease-pencil inspection rings, photogrammetry targets, "
                "rescue arrows, Spanish stencils and unlit navigation-light lenses (red left, "
                "green right, white tail; no lamp system is installed).",
        invented_texts=["BOLIDO", "VR-08", "DEMOSTRADOR DE REENTRADA", "mission emblem "
                        "'BOLIDO - VUELO 08 - REENTRADA'", "Spanish stencils"],
        emission="none (emissive texture is black; the r3 always-on lens glow was removed in r4)",
        render_only=["incandescence of nose, leading edges and belly (textures/bolido/source/"
                     "x8_bolido_heat.png)", "plasma sheath and wake (render scene objects)",
                     "temper colours as thin film on the motor shield", "clear coat on new tiles "
                     "and lenses", "4096 source resolution"],
        inspiration=["Space Shuttle thermal protection system (HRSI/LRSI tiles, FIB blankets, "
                     "RCC, gap fillers) as described on Wikipedia and seen in NASA photographs "
                     "of Endeavour and Columbia; no NASA markings or insignia are reproduced"]),
}




def skin_block(name):
    d = os.path.join(TEXROOT, name)
    meta = S.LIVERIES[name]
    rt = []
    for slot, f in zip(S.LIVERY_SLOTS, S.livery_images(name)):
        pth = os.path.join(d, f)
        rt.append(dict(file=f"textures/{name}/{f}", glb_image=os.path.splitext(f)[0],
                       size=list(_PIL.open(pth).size), colorspace=SLOT_USE[slot][1],
                       gltf_slot=SLOT_USE[slot][0], uv_channel=S.LIVERY_UV,
                       content=SLOT_USE[slot][2], bytes=os.path.getsize(pth), sha256=sha(pth)))
    srcd = os.path.join(d, "source")
    src = [dict(file=f"textures/{name}/source/{f}", size=list(_PIL.open(os.path.join(srcd, f)).size),
                sha256=sha(os.path.join(srcd, f)))
           for f in sorted(os.listdir(srcd)) if os.path.isfile(os.path.join(srcd, f))]
    lay = os.path.join(srcd, "layers")
    layers = [dict(file=f"textures/{name}/source/layers/{f}", sha256=sha(os.path.join(lay, f)))
              for f in sorted(os.listdir(lay))] if os.path.isdir(lay) else []
    masks = sorted(f"textures/{name}/source/masks/{f}" for f in os.listdir(os.path.join(srcd, "masks")))
    gp = os.path.join(PKG, S.livery_glb(name))
    rdir = os.path.join(PKG, "previews", "renders", name)
    lens = os.path.join(srcd, "masks", "light_lenses.json")
    info = INFO_LIV[name]
    return dict(
        id=name, label=meta["label"], description=meta["description"], default=meta["default"],
        revision_added=info["revision_added"], concept=info["concept"],
        glb=dict(path=S.livery_glb(name), sha256=sha(gp), bytes=os.path.getsize(gp)),
        runtime_textures=rt,
        material_bindings={S.LIVERY_MATERIAL: dict(
            uv_map=S.LIVERY_UV,
            slots={x["gltf_slot"]: dict(image=x["glb_image"], uv=S.LIVERY_UV, colorspace=x["colorspace"])
                   for x in rt},
            occlusion_source=S.SHARED_AO + " (shared by every skin, ORM red channel)",
            emissive_factor=[1, 1, 1], normal_scale=1.0, occlusion_strength=1.0),
            **{m["name"]: "flat colour, no textures (identical in every skin)" for m in MATS
               if m["name"] != S.LIVERY_MATERIAL}},
        editable_sources=dict(
            layers=layers, layer_rule="base colour = paint_base, then markings, then insignia "
                                      "('over', straight alpha); rebuild with paint_layers.py compose --write",
            maps=src, masks=masks),
        emission=info["emission"],
        unlit_light_lenses=(lambda d: dict(status=d["status"], anchors=[
            dict(node=a["node"], intended_group=a["group"] + " (not wired: no lamp installed)",
                 colour=a["color"], position_blender_m=a["position_blender_m"],
                 position_godot_m=[round(v, 5) for v in S.to_godot(a["position_blender_m"])],
                 lens_radius_mm=a["lens_radius_mm"]) for a in d["anchors"]]))(json.load(open(lens)))
        if os.path.exists(lens) else None,
        render_only=info["render_only"],
        invented_texts=info["invented_texts"],
        inspiration=info.get("inspiration", []),
        provenance="Original procedural paint by the package author (painter script "
                   f"source/scripts/{meta['painter']}); fonts DejaVu (free licence) rasterised into "
                   "pixels; no third-party images, logos, insignia or registrations.",
        pipeline=[f"python source/scripts/{meta['painter']} <work> textures/{name}/source",
                  f"python source/scripts/{meta['painter']} <work> textures/{name}/source --no-markings",
                  f"python source/scripts/paint_layers.py split textures/{name}/source {name}",
                  f"python source/scripts/livery_bake_textures.py source/aircraft_game.blend <work> "
                  f"textures/{name} --livery {name}" + ("" if meta["default"] else " --no-material"),
                  "python source/scripts/export_all.py source/aircraft_game.blend export/"],
        renders=sorted(f"previews/renders/{name}/{f}" for f in os.listdir(rdir)
                       if f.endswith(".png")) if os.path.isdir(rdir) else [],
        workbench_previews=f"previews/{name}/",
        verification=None)


SKINS = [skin_block(k) for k in S.SKIN_ORDER]
# memoria de texturas por skin (4 imagenes 2048^2)
_px = S.LIVERY_RES_RUNTIME ** 2
_mip = 4 / 3
TEX_MEMORY = dict(
    per_skin_uncompressed_rgba8_with_mips_MiB=round(4 * _px * 4 * _mip / 2 ** 20, 1),
    per_skin_vram_compressed_estimate_MiB=round((3 * _px * 0.5 + _px * 1.0) * _mip / 2 ** 20, 1),
    estimate_basis="uncompressed: 4 images x 2048^2 x 4 bytes x 4/3 (mipmaps). Compressed: three "
                   "4-bit-per-pixel blocks (BC1/ETC2 class: base colour, ORM, emission) and one "
                   "8-bit-per-pixel normal map (BC5/RGTC class), with mipmaps. Estimate only: the "
                   "real import format and cost must be measured in Godot (pending integration).",
    fleet_glb_bytes=sum(x["glb"]["bytes"] for x in SKINS),
    per_skin_glb_bytes={x["id"]: x["glb"]["bytes"] for x in SKINS})

# anclas de marcas y regiones de pintura de la skin por defecto (taller)
from mathutils.bvhtree import BVHTree as _BVH


def _surface_anchor(obj, origin, direction, up, size_mm, label):
    o = ob[obj]
    me = o.data
    mw = o.matrix_world
    vs = [mw @ v.co for v in me.vertices]
    tree = _BVH.FromPolygons(vs, [tuple(p.vertices) for p in me.polygons])
    hit = tree.ray_cast(Vector(origin), Vector(direction).normalized())
    if hit[0] is None:
        return None
    nrm = hit[1].normalized()
    upv = (Vector(up) - nrm * Vector(up).dot(nrm)).normalized()
    return dict(id=label, node=obj, position_blender_m=r(hit[0], 5), position_godot_m=r(S.to_godot(hit[0]), 5),
                normal_blender=r(nrm, 4), text_up_blender=r(upv, 4), max_size_mm=size_mm)


MARK_ANCHORS = [a for a in (
    _surface_anchor("wing_left_fixed", (-0.56, (D0["x_from_nose"] - 560) / 1000, 0.5), (0, 0, -1),
                    (-0.4, 1, 0), [320, 110], "registration_wing_left_top"),
    _surface_anchor("wing_right_fixed", (0.56, (D0["x_from_nose"] - 560) / 1000, 0.5), (0, 0, -1),
                    (0.4, 1, 0), [320, 110], "registration_wing_right_top"),
    _surface_anchor("wing_left_fixed", (-0.60, (D0["x_from_nose"] - 600) / 1000, -0.5), (0, 0, 1),
                    (-0.4, 1, 0), [300, 90], "registration_wing_left_underside"),
    _surface_anchor("wing_left_fixed", (-1.3, (D0["x_from_nose"] - 860) / 1000, (125 - D0["z"]) / 1000),
                    (1, 0, 0), (0, 0, 1), [90, 70], "marking_winglet_left_outer"),
    _surface_anchor("wing_right_fixed", (1.3, (D0["x_from_nose"] - 860) / 1000, (125 - D0["z"]) / 1000),
                    (-1, 0, 0), (0, 0, 1), [90, 70], "marking_winglet_right_outer"),
) if a]
PAINT_TARGETS = dict(
    skin=S.DEFAULT_LIVERY, material=S.LIVERY_MATERIAL, uv=S.LIVERY_UV,
    painted_parts=list(S.LIVERY_PARTS),
    region_attribute="face attribute x8_region on each painted mesh: 0 skin, 1 hinge tape, "
                     "2 servo cover, 3 orange plastic (root ribs, control horns), 4 propeller",
    part_attribute="face attribute x8_part: " + ", ".join(f"{v} {k}" for k, v in S.LIVERY_PARTS.items()),
    note="Workshop paint slots and registration markings apply to the default skin only; "
         "alternate skins are not promised arbitrary repainting.")
span = L["wingtip_right"]["blender_m"][0] - L["wingtip_left"]["blender_m"][0]
length = L["nose_tip"]["blender_m"][1] - L["spinner_tip"]["blender_m"][1]
height = L["highest_point"]["blender_m"][2] - L["lowest_point"]["blender_m"][2]
META = dict(
    format="skywalker-x8 game delivery metadata v1 (structure modelled on the OpenRC aircraft "
           "delivery specification; not an openrc-aircraft v2 physics file)",
    aircraft=dict(source_name="Skywalker X8", simulator_display_name=None,
                  note_display_name="to be chosen by the simulator team / owner",
                  revision=S.REVISION, configuration=dict(
                      description="UAV: mapping camera behind two articulated ventral doors, "
                                  "parachute pack inside the bay, magnetic top hatch that can "
                                  "separate (section canopy); controls, doors and propeller "
                                  "neutral; battery centre 228 mm from the nose; skins abisal (default) and bolido",
                      elevons="neutral", camera_doors="closed", hatch="closed",
                      landing_gear="none (hand/catapult launch, belly landing)")),
    tools=dict(blender="5.2.2 LTS", blender_build_hash="d13f752e3b9c",
               blender_build_date="2026-09-15", gltf_io="Khronos glTF Blender I/O 5.2.40",
               runtime="Python bpy module 5.2.2 (pip) on Linux x86_64",
               note="the blender -b commands in README.md are the equivalent invocation; the "
                    "delivery was produced and verified with the bpy module build above"),
    units="metre", frames=S.FRAME_TEXT,
    conversion=dict(
        godot_from_blender="godot = (blender.x, blender.z, -blender.y), applied once by the "
                           "Y-up glTF export",
        blender_from_master_mm="blender = (s, x_D0 - x, z - z_D0) / 1000 with x aft from the "
                               "nose, s to the right, z up (master tables, mm)",
        godot_from_master_mm="godot = (s, z - z_D0, x - x_D0) / 1000",
        master_blender_to_game="game = Rz(180 deg) * (master - D0_master)"),
    datum_D0=dict(definition=INFO["D0_definition"],
                  master_mm=dict(x_from_nose=round(D0["x_from_nose"], 3), s=0.0,
                                 z=round(D0["z"], 3)),
                  note="D0 is not the CG. Root node has zero translation/rotation and unit scale.",
                  incidence_dihedral_washout="preserved from the master (root incidence 0, "
                                             "dihedral 1.5 deg, washout -2.5 deg at the tip)",
                  ground_attitude="not baked"),
    landmarks=L,
    dimensions=dict(
        span_including_winglets_m=dict(value=round(span, 5), evidence="model measurement",
                                       source="wingtip landmarks"),
        length_nose_to_spinner_tip_m=dict(value=round(length, 5), evidence="model measurement"),
        height_m=dict(value=round(height, 5), evidence="model measurement"),
        span_manufacturer_m=dict(value=2.120, evidence="manual value",
                                 source="Skywalker official three-view"),
        span_ntnu_m=dict(value=2.10, evidence="published", source="Gryte et al., ICUAS 2018"),
        fuselage_length_manufacturer_m=dict(value=0.790, evidence="manual value",
                                            source="Skywalker official three-view"),
        wing_area_manufacturer_m2=dict(value=0.80, evidence="manual value",
                                       source="Skywalker spec sheet (80 dm2)"),
        wing_area_planform_digitised_m2=dict(value=0.742, evidence="model measurement",
                                             source="master planform digitised from the "
                                                    "official views"),
        propeller_diameter_m=dict(value=round(2 * prop_R, 5), evidence="model measurement",
                                  source="propeller_rotor vertices"),
        note="scale preserved from the master; no rescaling to manual values"),
    physical=dict(
        mass_flying_manufacturer_kg=dict(value=[2.5, 3.0], unit="kg", evidence="manual value",
                                         source="Skywalker spec sheet"),
        mass_empty_kit_kg=dict(value=0.880, evidence="manual value (as used by the master)",
                               source="Skywalker manual"),
        mass_ledger_estimate_kg=dict(
            value=2.532, evidence="estimate - NON-FLIGHT PLACEHOLDER",
            source="master v3.1 component list (camera + parachute configuration)",
            warning="not flight-ready mass data; do not derive inertia or CG from it"),
        cg_manufacturer_from_nose_mm=dict(value=[430, 440], evidence="manual value"),
        cg_ledger_estimate_from_nose_mm=dict(value=435.2, evidence="estimate - NON-FLIGHT "
                                             "PLACEHOLDER", source="x8_logica_tapas.py"),
        inertia=None, strength=None,
        note="geometry volume, material names and crash-section labels do not define mass, CG, "
             "inertia or strength; the simulator team owns flight-data derivation"),
    control_mixing=dict(
        surfaces="two elevons (no separate ailerons, elevator, rudder or flaps)",
        convention="angles in degrees of surface rotation, + = trailing edge down",
        formula="elevon_left = roll - pitch ; elevon_right = -roll - pitch "
                "(pitch + = nose up, roll + = right wing down)",
        default_rates="pitch 0.70, roll 0.85 of the servo travel inside the mix (master radio "
                      "configuration); ArduPilot SERVO1/2_FUNCTION 77/78"),
    sections=[dict(id=k, nodes=v) for k, v in sections.items()],
    articulations=ART,
    materials=MATS,
    atlas=ATLAS,
    skins=SKINS,
    skin_order=[x["id"] for x in SKINS],
    default_skin=S.DEFAULT_LIVERY,
    shared_maps=[dict(file=S.SHARED_AO, use="ORM red channel (glTF occlusion) of every skin",
                      sha256=sha(os.path.join(PKG, S.SHARED_AO)))],
    texture_memory=TEX_MEMORY,
    default_skin_paint_targets=PAINT_TARGETS,
    default_skin_marking_anchors=MARK_ANCHORS,
    lights=dict(installed=False, groups=[],
                note="The X8 UAV configuration of the master has no lamp system; no simulator light "
                     "groups (navigation, strobe, landing, orientation) are declared. BOLIDO paints "
                     "unlit lens shapes (anchors under skins[].unlit_light_lenses); ABISAL has "
                     "decorative always-on bioluminescent emission, which is paint, not a lamp."),
    mechanisms=dict(
        conventional_controls=["elevon_left_hinge", "elevon_right_hinge"],
        propeller="propeller_spin (rotor separate from the fixed motor_mount)",
        auxiliary_unsupported=["camera_door_left_hinge", "camera_door_right_hinge"],
        canopy="canopy_hatch is a detachable section only (no opening mechanism)",
        landing_gear="not applicable (none)", retracts="not applicable", wing_folds="not applicable",
        tailhook="not applicable", cowl_flaps="not applicable"),
    counts=dict(triangles=tri_total, mesh_nodes=len(counts), surfaces=surf, materials=len(MATS),
                textures_per_skin=len(bpy.data.images), skins=len(SKINS), per_mesh=counts),
    glb=dict(path="export/aircraft.glb", sha256=sha(GLB), bytes=os.path.getsize(GLB)),
    demo_glb=dict(path="previews/demo/aircraft_demo.glb", sha256=sha(DEMO), bytes=os.path.getsize(DEMO),
                  animation="demo (24 fps, 560 frames): elevons, doors, propeller, exploded "
                            "sections; reference only"),
    master_reference=dict(file="Skywalker_X8/Skywalker_X8.blend (master v3.1)",
                          sha256=sha(MASTER),
                          generator="source/scripts/x8_skywalker_blender.py",
                          generator_sha256=sha(os.path.join(HERE, "x8_skywalker_blender.py"))),
    known_limits=[
        "Servo arms and pushrods are not exported: the simulator drives only the hinge, so a "
        "static linkage would misalign when the elevons move (silhouette difference below the "
        "wing at s = +-515 mm).",
        "Servos ES3054 inside the wing bays, magnets, tabs, latch pin, spring, carbon tubes and "
        "fasteners are hidden in flight and are not exported.",
        "Hinge tape, servo covers and orange plastic are painted regions of the x8_livery atlas "
        "(face attribute x8_region) plus a 2 mm slot cover on each elevon; no separate shells "
        "and no coplanar decal geometry.",
        "The magnetic hatch is tagged canopy so it can separate; the X8 has no glazing.",
        "Wing/centre-body joint: 0.1 mm hidden separation on each side of the orange rib.",
        "No landing gear, tail surfaces, flaps or rudder exist on this aircraft.",
        "Mass and CG values are manual values or non-flight estimates only.",
        "Elevon positive-deflection clearance ends at about 31 deg (game tessellation of the "
        "35 deg lower chamfer); the authored range is +-26.8 deg.",
        "Liveries: everything listed as render_only (ABISAL iridescence and coat; BOLIDO "
        "incandescence, plasma sheath, temper-colour thin film) exists only in the Cycles "
        "renders; the GLBs use core glTF (no KHR_materials_* extensions).",
        "Liveries: emission is exported at factor 1.0; glow is an engine-side setting.",
        "ABISAL: the FPV window (x8_glass) interrupts the row of teeth on the nose.",
        "Liveries: interior foam, metal, glass, motor bell, motor mount and bay equipment keep "
        "flat materials in every skin.",
        "Liveries: wear, dirt and markings are baked into each atlas (one look per skin); there "
        "is no clean variant or runtime decal layer.",
        "BOLIDO: the tile grid uses planar projections per zone (belly, sides, nose front, each "
        "wing along its leading edge, each elevon along its hinge, winglets); where two zones "
        "meet, tiles end at a closeout line, as on real heat shields, and on the strongly curved "
        "nose sides tiles are slightly stretched.",
        "BOLIDO is a visual concept: the paint does not imply real thermal protection; mass and "
        "aerodynamics are those of the foam X8.",
    ],
)
json.dump(META, open(os.path.join(PKG, "metadata.json"), "w"), indent=1)

# ------------------------------------------------------------------ mapa de exportacion
RULES = [
    (r"^X8_Fuselaje_Central$", "included", "fuselage_core", "retessellated (game resolution); "
     "hollow bay, hatch opening and camera-door openings kept; side caps = closure faces"),
    (r"^X8_Ventana_Camara$", "included", "fuselage_core", "FPV window, bevel 2 segments"),
    (r"^X8_Bisagra_Piano_(Der|Izq)$", "included", "fuselage_core", "door hinge pins (r 0.4 mm)"),
    (r"^X8_(Bateria_6S_5000|Bandeja_Bateria|Camara_FPV_VTX|Controlador_Vuelo|"
     r"Receptor_Telemetria|GPS_Brujula|ESC_60A|Paracaidas_Paquete|Camara_Mapeo|"
     r"Camara_Mapeo_Objetivo|Amortiguador_Camara_\d|Servo_Pestillo_9g|Servo_Compuertas_9g)$",
     "simplified", "bay_equipment", "box geometry, bevel 1 segment; visible through the doors or "
     "when the hatch separates"),
    (r"^X8_Tapa_Principal$", "included", "canopy_hatch", "magnetic top hatch"),
    (r"^X8_Ala_(Der|Izq)$", "included", "wing_*_fixed", "retessellated; servo-bay boolean not "
     "applied (cover is a material region)"),
    (r"^X8_Punta_Winglet_(Der|Izq)$", "included", "wing_*_fixed", "outer panel + winglet"),
    (r"^X8_Costilla_Raiz_(Der|Izq)$", "included", "wing_*_fixed", "orange root rib (closes the "
     "wing root)"),
    (r"^X8_Elevon_(Der|Izq)$", "included", "elevon_*", "retessellated"),
    (r"^X8_Cuerno_(Der|Izq)$", "included", "elevon_*", "control horn moves with the elevon"),
    (r"^X8_Compuerta_Camara_(Der|Izq)$", "included", "camera_door_*", "ventral door half"),
    (r"^X8_(Soporte_Motor|Motor_Estator)$", "included", "motor_mount", "fixed motor parts"),
    (r"^X8_(Pala_\d|Buje_Helice|Cono_Helice|Motor_Campana|Eje)$", "included", "propeller_rotor",
     "rotating hardware (outrunner bell and shaft included)"),
    (r"^X8_Cinta_Bisagra_(Ala|Elevon)_(Der|Izq)$", "simplified", "wing_*_fixed / elevon_*",
     "hinge tape shell replaced by a painted region (x8_region 1) of the x8_livery atlas + "
     "slot cover"),
    (r"^X8_Tapa_Servo_(Der|Izq)$", "simplified", "wing_*_fixed", "servo cover shell replaced by "
     "a painted region (x8_region 2) of the x8_livery atlas"),
    (r"^X8_Hueco_Bahia_(Der|Izq)$", "excluded", None, "boolean cutter (helper)"),
    (r"^X8_Volumen_Bahia$", "excluded", None, "bay volume helper (cutter / display)"),
    (r"^X8_(Servo_ES3054|Brazo_Servo|Varilla)_(Der|Izq)$", "excluded", None,
     "servo and linkage: hidden in the bay or would misalign because only the hinge is driven"),
    (r"^X8_(Iman|Placa)_(Tapa|Fuselaje)_\d$", "excluded", None, "hidden magnet hardware"),
    (r"^X8_(Apoyo_Iman_\d|Lengueta_Tapa_[DI]|Taco_Lengueta_[DI]|Enganche_Tapa|Pestillo|"
     r"Paracaidas_Resorte|Tubo_Carbono_\d|Bandeja_Bateria_Ext)$", "excluded", None,
     "hidden fasteners/internal structure, or not installed in this configuration"),
    (r"^X8_(Perilla_Cierre|Perilla_Agarre|Perilla_Eje|Leva_Cierre|Tope_Cierre_(Der|Izq)|"
     r"Poste_Cierre_(Der|Izq))$", "excluded", None, "rotary lock: not installed in the parachute "
     "configuration (the latch pin holds the hatch)"),
    (r"^X8_(LED_\w+|Rotulo_\w+|Marcador_CG|Palanca|Palanca_Base)$", "excluded", None,
     "logic/demo indicator, not aircraft geometry"),
    (r"^X8_(Eje_Bisagra|Eje_Servo|Agujero_Brazo|Agujero_Cuerno|Bisagra_Compuerta)_(Der|Izq)$",
     "excluded", None, "master pivot/helper empty; replaced by the game pivots"),
    (r"^X8_(Pivote_Tapa|Eje_Cierre|Guia_Pestillo|Rotor|Mando_RC|Mezclador|Logica_Tapas|Estado)$",
     "excluded", None, "master rig/logic empty; game pivots are elevon_*_hinge, "
     "camera_door_*_hinge, thrust_frame, propeller_spin"),
    (r"^Skywalker_X8$", "excluded", None, "master root (origin at x = 440 mm); replaced by the "
     "game root SkywalkerX8 at D0"),
    (r"^(Cam_.*|Pivote_Giro|Sol|Relleno|Contra|Bajo|Suelo)$", "excluded", None,
     "studio camera/light/floor"),
]
emap, unmatched, multi = [], [], []
for name, typ in MASTER_OBJS:
    hits = [rl for rl in RULES if re.match(rl[0], name)]
    if len(hits) != 1:
        (unmatched if not hits else multi).append(name)
        continue
    _, status, target, why = hits[0]
    if target and "*" in target:
        side = "left" if name.endswith("Izq") else "right"
        target = target.replace("*", side)
    emap.append(dict(source=name, type=typ, status=status, target=target, reason=why))
added = [dict(node=n, origin="created for the game asset") for n in
         ("SkywalkerX8", "elevon_left_hinge", "elevon_right_hinge", "camera_door_left_hinge",
          "camera_door_right_hinge", "thrust_frame", "propeller_spin", "bay_equipment (merge)",
          "elevon slot covers (inside elevon_*)",
          "x8_livery atlas material, UVMap and face attributes x8_part/x8_region (r2)")]
EXPORT_MAP = dict(master=os.path.basename(MASTER), master_sha256=sha(MASTER),
                  master_objects=len(MASTER_OBJS), accounted=len(emap),
                  unmatched=unmatched, matched_more_than_once=multi,
                  summary={s_: sum(1 for e in emap if e["status"] == s_)
                           for s_ in ("included", "simplified", "excluded")},
                  parts=emap, added_in_game=added)
json.dump(EXPORT_MAP, open(os.path.join(PKG, "export-map.json"), "w"), indent=1)
print("metadata: triangulos", tri_total, "superficies", surf, "envergadura", round(span, 4),
      "largo", round(length, 4))
print("export-map:", EXPORT_MAP["summary"], "sin regla:", unmatched, "doble:", multi)
if unmatched or multi:
    sys.exit(1)
