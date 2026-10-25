"""Vistas mas cercanas a 1920 x 1080 (y una a 2560 x 1440) con el material de juego de cada skin (r4).

  python check_views.py source/aircraft_game.blend checks/views [--spp 16]

No hay vistas de simulador suministradas para este avion: se usan tres vistas PROVISIONALES
(taller 3/4, inspeccion de la nariz y persecucion) con distancia y campo de vision registrados.
Cada skin se renderiza con las mismas camaras, la misma luz y el mismo ajuste de color, usando
el material x8_livery con las texturas de juego (2048) tal como van en el GLB, para comparar
acabados (un mapa de normales perdido o una rugosidad cambiada se ven aqui). Se calcula el
tamano del pixel sobre el avion frente al tamano del texel del atlas. Cycles no es el renderer
del simulador: esto valida textura y geometria, no la importacion en Godot.
"""
import sys, os, json, math, platform
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Vector
import x8_game_spec as S
import export_glb as E

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND, OUT = os.path.abspath(argv[0]), os.path.abspath(argv[1])
SPP = int(argv[argv.index("--spp") + 1]) if "--spp" in argv else 16
PCT = int(argv[argv.index("--pct") + 1]) if "--pct" in argv else 100      # solo para pruebas
os.makedirs(OUT, exist_ok=True)
TEXEL_MM = 0.87                                   # densidad del atlas de juego (metadata.json)
VIEWS = [
    dict(id="workshop_3q", purpose="provisional Workshop/Home 3/4 view, whole aircraft in frame",
         target=None, distance_m=2.8, azimuth_deg=-35, elevation_deg=25, hfov_deg=50, res=(1920, 1080)),
    dict(id="inspection_nose", purpose="provisional closest inspection view (nose, hatch, markings)",
         target=(0.0, 0.17, 0.03), distance_m=0.9, azimuth_deg=30, elevation_deg=30, hfov_deg=40,
         res=(1920, 1080)),
    dict(id="chase", purpose="provisional flight chase view", target=None, distance_m=3.5,
         azimuth_deg=180, elevation_deg=15, hfov_deg=70, res=(1920, 1080)),
    dict(id="inspection_nose", purpose="same closest view at 2560 x 1440", target=(0.0, 0.17, 0.03),
         distance_m=0.9, azimuth_deg=30, elevation_deg=30, hfov_deg=40, res=(2560, 1440)),
]


def cpu():
    try:
        for l in open("/proc/cpuinfo"):
            if l.startswith("model name"):
                return l.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor()


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SPP
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "None"
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("VW")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.34, 0.37, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    for loc, en, sz in (((0.0, 0.2, 3.0), 380, 3.0), ((-2.5, 2.0, 1.2), 180, 2.0), ((2.6, -1.8, 0.9), 120, 2.0)):
        ld = bpy.data.lights.new("VL", "AREA")
        ld.energy, ld.size = en, sz
        lo = bpy.data.objects.new("VL", ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("VCAM", bpy.data.cameras.new("VCAM"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.sensor_width = 36.0
    cam.data.clip_start = 0.01
    return sc, cam


def bbox_center():
    pts = [o.matrix_world @ Vector(c) for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return (lo + hi) / 2


rec = []
for skin in S.SKIN_ORDER:
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    bpy.context.scene.frame_set(1)
    E.swap_livery(skin)
    sc, cam = setup_scene()
    ctr = bbox_center()
    for v in VIEWS:
        tgt = Vector(v["target"]) if v["target"] else ctr
        az, el = math.radians(v["azimuth_deg"]), math.radians(v["elevation_deg"])
        # azimut 0 = delante de la nariz (+Y); negativo = hacia la izquierda del piloto
        d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
        cam.location = tgt + d * v["distance_m"]
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 18.0 / math.tan(math.radians(v["hfov_deg"]) / 2)
        sc.render.resolution_x, sc.render.resolution_y = v["res"]
        sc.render.resolution_percentage = PCT
        name = f"{skin}_{v['id']}_{v['res'][1]}p"
        sc.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
        px_mm = 2 * v["distance_m"] * math.tan(math.radians(v["hfov_deg"]) / 2) / v["res"][0] * 1000
        vfov = 2 * math.degrees(math.atan(math.tan(math.radians(v["hfov_deg"]) / 2) * v["res"][1] / v["res"][0]))
        rec.append(dict(skin=skin, view=v["id"], purpose=v["purpose"], file=f"checks/views/{name}.png",
                        resolution=list(v["res"]), camera_m=[round(c, 4) for c in cam.location],
                        target_m=[round(c, 4) for c in tgt], distance_m=v["distance_m"],
                        hfov_deg=v["hfov_deg"], vfov_deg=round(vfov, 2), pose="neutral rest pose",
                        pixel_footprint_at_target_mm=round(px_mm, 3),
                        atlas_texel_mm=TEXEL_MM, texels_per_pixel=round(px_mm / TEXEL_MM, 3)))
        print("VISTA", name, round(px_mm, 3), "mm/px")
R = dict(renderer=f"Cycles CPU, {SPP} samples + OpenImageDenoise, AgX (no look), Blender {bpy.app.version_string}",
         material="x8_livery runtime textures (2048, as embedded in the GLBs); same lights and "
                  "exposure for every skin",
         hardware=f"{cpu()}, {os.cpu_count()} CPU threads available to the container",
         status="provisional views: OpenRC camera distances and fields of view were not supplied",
         views=rec)
json.dump(R, open(os.path.join(OUT, "views.json"), "w"), indent=1)
print("VISTAS", len(rec))
