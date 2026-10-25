"""Contrato de la version de juego de la Skywalker X8 (r1): nombres, jerarquia, secciones,
materiales, resolucion y convenciones. Lo usan build_game.py, export_glb.py, make_demo.py,
make_previews.py y verify_game.py; no depende de bpy.
"""
import math

REVISION = "r4"
ROOT = "SkywalkerX8"
EXPORT_COLLECTION = "EXPORT_aircraft"
SECTION_KEY = "openrc_section"
VOCABULARY = ("core", "wing_left", "wing_right", "wing_center", "horizontal_tail",
              "vertical_tail", "engine", "propeller", "gear", "canopy")

# (nombre, padre, tipo, seccion). Tipo: MESH o EMPTY. Seccion None = sin etiqueta.
NODES = [
    (ROOT, None, "EMPTY", None),
    ("fuselage_core", ROOT, "MESH", "core"),
    ("bay_equipment", ROOT, "MESH", "core"),
    ("canopy_hatch", ROOT, "MESH", "canopy"),
    ("wing_left_fixed", ROOT, "MESH", "wing_left"),
    ("wing_right_fixed", ROOT, "MESH", "wing_right"),
    ("motor_mount", ROOT, "MESH", "engine"),
    ("elevon_left_hinge", ROOT, "EMPTY", "wing_left"),
    ("elevon_left", "elevon_left_hinge", "MESH", "wing_left"),
    ("elevon_right_hinge", ROOT, "EMPTY", "wing_right"),
    ("elevon_right", "elevon_right_hinge", "MESH", "wing_right"),
    ("camera_door_left_hinge", ROOT, "EMPTY", "core"),
    ("camera_door_left", "camera_door_left_hinge", "MESH", "core"),
    ("camera_door_right_hinge", ROOT, "EMPTY", "core"),
    ("camera_door_right", "camera_door_right_hinge", "MESH", "core"),
    ("thrust_frame", ROOT, "EMPTY", None),
    ("propeller_spin", "thrust_frame", "EMPTY", "propeller"),
    ("propeller_rotor", "propeller_spin", "MESH", "propeller"),
]
NODE_INDEX = {n[0]: n for n in NODES}

# Pivotes moviles: eje = +X local, angulo 0 = reposo guardado: rest * Rx(angulo)
ARTICULATIONS = {
    "elevon_left_hinge": dict(child="elevon_left", positive="trailing edge down",
                              kind="elevon"),
    "elevon_right_hinge": dict(child="elevon_right", positive="trailing edge down",
                               kind="elevon"),
    "camera_door_left_hinge": dict(child="camera_door_left",
                                   positive="door opens (free edge swings down and inboard)",
                                   kind="door"),
    "camera_door_right_hinge": dict(child="camera_door_right",
                                    positive="door opens (free edge swings down and inboard)",
                                    kind="door"),
    "propeller_spin": dict(child="propeller_rotor",
                           positive="clockwise viewed from behind looking toward the nose "
                                    "(right-handed about +X = thrust direction); this is the "
                                    "direction that puts the blade leading edge first",
                           kind="propeller"),
}

# Teselado del juego (el maestro usa nu=90, body=70, wing=64, outer=(8,16,34), elevon=48,
# blade=(26,24), cav=(61,64), tape=70, cyl=48)
GAME_RES = dict(nu=30, body=40, wing=24, outer=(4, 8, 16), elevon=20, blade=(12, 12),
                cav=(21, 18), tape=24, cyl=24, prop_pitch_sign=-1.0, joint_clear=0.1)

# Materiales del juego (Principled exportable, color plano)
MATERIALS = {
    "x8_epo_white": dict(color=(0.80, 0.805, 0.79), rough=0.58, metal=0.0),
    "x8_foam_interior": dict(color=(0.60, 0.60, 0.58), rough=0.75, metal=0.0),
    "x8_orange": dict(color=(0.95, 0.30, 0.02), rough=0.38, metal=0.0),
    "x8_black": dict(color=(0.025, 0.025, 0.028), rough=0.40, metal=0.0),
    "x8_metal": dict(color=(0.75, 0.75, 0.77), rough=0.25, metal=1.0),
    "x8_motor_bell": dict(color=(0.55, 0.06, 0.04), rough=0.30, metal=0.9),
    "x8_glass": dict(color=(0.01, 0.01, 0.012), rough=0.05, metal=0.0),
    "x8_battery": dict(color=(0.85, 0.75, 0.10), rough=0.45, metal=0.0),
    "x8_electronics": dict(color=(0.10, 0.32, 0.60), rough=0.50, metal=0.0),
    "x8_servo_cover": dict(color=(0.55, 0.57, 0.60), rough=0.35, metal=0.0),
}
MASTER_TO_GAME_MATERIAL = {
    "EPO_Blanco": "x8_epo_white", "Compuerta_EPO": "x8_epo_white",
    "EPO_Interior": "x8_foam_interior", "Contrachapado": "x8_foam_interior",
    "Plastico_Naranja": "x8_orange", "Cuerno_Naranja": "x8_orange", "Paracaidas": "x8_orange",
    "Motor_Negro": "x8_black", "Helice_Negra": "x8_black", "Caja_Servo": "x8_black",
    "Cinta_Bisagra": "x8_black", "Fibra_Carbono": "x8_black", "Camara_Mapeo": "x8_black",
    "Campana_Motor": "x8_motor_bell", "Acero": "x8_metal", "Iman_Neodimio": "x8_metal",
    "Ventana_Camara": "x8_glass", "Bateria_LiPo": "x8_battery",
    "Equipo_Electronico": "x8_electronics", "Tapa_Servo_Plastico": "x8_servo_cover",
}

# Rango de mandos (grados). Fuente: rig del maestro v3 (x8_logica_mandos.cadena) con la
# configuracion por defecto (expo 0.25, mezcla profundidad 0.70, alabeo 0.85, servo +-45 grados)
ELEVON_RANGES = {
    "pitch_only_full_stick": [-19.46, 19.48],
    "roll_only_full_stick": [-23.24, 23.28],
    "combined_full_stick_default_mix": [-26.76, 26.85],
    "mechanical_full_servo_travel": [-26.76, 26.85],
}
DOOR_RANGE = [0.0, 110.0]
CLEARANCE_SWEEP_ELEVON = (-40.0, 40.0, 1.0)

# Marcos
FRAME_TEXT = {
    "blender_game_scene": "+X right wing (pilot's right), +Y nose (forward), +Z up; metres; "
                          "origin = D0",
    "glb_godot": "+X right, +Y up, -Z nose; godot = (blender.x, blender.z, -blender.y)",
    "master_v3_blender": "X = -s (left wing at +X), Y aft, Z up, origin at x = 440 mm from the "
                         "nose (nominal CG); mm tables: x aft from nose, s right, z up",
}


def to_godot(v):
    return (v[0], v[2], -v[1])


def r6(v):
    return [round(float(c), 6) for c in v]

# ---------------------------------------------------------------- r2: librea "Abisal"
# piezas pintadas en el atlas (id que se hornea en la mascara de piezas)
LIVERY_PARTS = {"fuselage_core": 1, "canopy_hatch": 2, "wing_left_fixed": 3, "wing_right_fixed": 4,
                "elevon_left": 5, "elevon_right": 6, "camera_door_left": 7,
                "camera_door_right": 8, "propeller_rotor": 9}
LIVERY_RES_SOURCE = 4096      # resolucion de pintura (fuentes y renders)
LIVERY_RES_RUNTIME = 2048     # atlas que va dentro del GLB
LIVERY_MATERIAL = "x8_livery"
# r3: dos libreas sobre el mismo atlas UV. La primera es la del .blend y de export/aircraft.glb;
# las demas son "skins": sus cuatro texturas entran en los mismos huecos del material x8_livery.
LIVERIES = {
    # orden = orden de entrega; la primera es la skin por defecto (export/aircraft.glb)
    "abisal": dict(painter="livery_paint.py", render="render_livery.py", default=True,
                   label="ABISAL - deep-sea anglerfish",
                   description="Original deep-sea anglerfish scheme: blue-black iridescent "
                               "scales, photophores, fin rays, mouth with fangs and lure, false "
                               "eyes on the winglets, worn like a working UAV.",
                   title="ABISAL (deep-sea anglerfish)"),
    "bolido": dict(painter="livery_paint_bolido.py", render="render_bolido.py", default=False,
                   label="BOLIDO - re-entry heat shield",
                   description="Original re-entry-demonstrator scheme: black ceramic tiles "
                               "below, quilted blankets above, carbon-carbon leading edges, "
                               "heat stains and flight-test markings.",
                   title="BOLIDO (re-entry demonstrator, ceramic heat-shield tiles)"),
}
DEFAULT_LIVERY = next(k for k, v in LIVERIES.items() if v["default"])
SKIN_ORDER = list(LIVERIES)                     # primera = por defecto
LIVERY_SLOTS = ("base_color.jpg", "orm.png", "normal.png", "emission.jpg")
LIVERY_UV = "TEXCOORD_0 (UVMap)"                # todas las texturas del atlas usan este canal
SHARED_AO = "textures/shared/x8_airframe_occlusion.png"   # canal R del ORM, comun a las skins


def livery_images(name=DEFAULT_LIVERY):
    return tuple(f"x8_{name}_{k}" for k in LIVERY_SLOTS)


def livery_glb(name):
    """r4: la skin por defecto es export/aircraft.glb; las demas, export/<skin_id>.glb."""
    return "export/aircraft.glb" if LIVERIES[name]["default"] else f"export/{name}.glb"


LIVERY_IMAGES = livery_images(DEFAULT_LIVERY)

# ---------------------------------------------------------------- r4: revision base fijada
BASELINE = dict(
    revision="r3", package="skywalker_x8_r3.zip (delivered 2026-10-22)",
    files={"source/aircraft_game.blend": "ec5c99beb45fd27059c272d2570e81487ab472abffd21f2ab92936c3fdc267e8",
           "export/aircraft.glb": "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac",
           "export/aircraft_bolido.glb": "9cd46993ca116917e9062996c7ed9f4cd8b20933473732b5de1e373b658d8aba"})
MASTER_SHA256 = "6b70daf46dc6414ad04b5e656ac96bb2916e463ff7e686accda4dcad41237156"   # maestro v3.1
