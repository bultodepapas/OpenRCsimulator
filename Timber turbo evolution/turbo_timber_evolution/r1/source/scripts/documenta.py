"""
Escribe metadata.json y export-map.json del paquete de juego a partir de lo medido en la escena de
exportacion (_export_data.json), la verificacion (verification.json) y los datos del CAD v12.
  python3 documenta.py --pkg <paquete>
"""
import json, os, sys, math
BASE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, BASE)
import mapa
PKG = sys.argv[sys.argv.index("--pkg") + 1]
D = json.load(open(os.path.join(BASE, "_export_data.json")))
V = json.load(open(os.path.join(PKG, "verification.json")))
META = json.load(open(os.path.join(BASE, "..", "modelo_v12.py.brep", "ok.json")))
ESC = json.load(open(os.path.join(BASE, "..", "stl_v12", "escena.json")))
A = json.load(open(os.path.join(BASE, "..", "analisis.json")))
AT = json.load(open(os.path.join(BASE, "..", "auditoria_tren.json")))
X_BA = META["X_BA"]

def ev(value, unit, evidence, source, uncertainty=None, note=None):
    d = {"value": value, "unit": unit, "evidence": evidence, "source": source}
    if uncertainty is not None: d["uncertainty"] = uncertainty
    if note: d["note"] = note
    return d
def sim_cad(p):        # CAD sidecar mm -> simulador m
    return [round(p[1]/1000, 6), round(p[2]/1000, 6), round(p[0]/1000, 6)]
def exp_cad(p):        # CAD sidecar mm -> Blender export m
    return [round(p[1]/1000, 6), round(-p[0]/1000, 6), round(p[2]/1000, 6)]
MEDIDO = "measured on the exported mesh (Blender, before export; re-checked after GLB re-import)"
CAD = "derived from the parametric CAD v12 (modelo_v12.py)"
FOTO = "user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"

m = {}
m["schema"] = "openrc-aircraft-delivery (draft letter, provisional fields)"
m["aircraft"] = {
    "id": "eflite_turbo_timber_evolution", "revision": "r1", "display_name": "Turbo Timber Evolution (game build)",
    "status": "first delivery: neutral export + 4 primary controls + flaps + propeller pivot + wheel/suspension pivots",
    "configuration": {
        "variant": "landplane, stock tundra-style foam main wheels, steerable tailwheel",
        "floats": ev(False, None, "manual", "modeler decision", note="no floats modeled or exported"),
        "slats": ev(False, None, "manual", "modeler decision",
                    note="no leading-edge slats; only the small grey slat brackets (soportes_slat) are modeled, as fixed airframe parts; their real function is uncertain"),
        "flaps": "present, exported at 0 deg (neutral) with their own hinge",
        "lights": "nav/strobe lenses modeled as emissive materials; no light objects exported",
        "motor": ev("15-size outrunner (~160 g)", None, "estimated", "typical for this class; not from a manual"),
        "propeller": ev("3-blade, ~11x7 equivalent, radius 138.1 mm", None, "estimated", "photo proportions"),
        "battery": ev("4S 3200 mAh (~340 g)", None, "estimated", "typical for this class; not from a manual"),
        "livery": "red/white/black scheme approximated with solid materials; no logos, no text, no textures",
    },
}
m["units"] = {"length": "m", "angle_metadata": "deg", "angle_runtime": "rad (glTF quaternions)", "mass": "kg"}
m["frames"] = {
    "simulator": {"description": "glTF / OpenRC Simulator frame", "units": "m", "x": "+X right (pilot view)", "y": "+Y up",
                  "z": "nose points -Z (so +Z is aft)", "handedness": "right-handed", "left_right": "pilot view (sitting in the cockpit, looking forward)"},
    "blender_export": {"description": "authoring frame of export/aircraft.glb inside Blender (exporter applies +Y-up conversion)",
                       "units": "m", "x": "+X right", "y": "+Y forward (nose)", "z": "+Z up",
                       "to_simulator": "sim = (bx, bz, -by)"},
    "cad": {"description": "frame of the parametric CAD and of metadata fields named *_cad_mm", "units": "mm",
            "x": "+X aft", "y": "+Y right wing", "z": "+Z up", "origin": "datum D0",
            "to_blender_export": "b = (y, -x, z) / 1000", "to_simulator": "sim = (y, z, x) / 1000"},
    "cad_photo": {"description": "older CAD working frame used for photo matching; x measured aft from the propeller plane",
                  "relation": f"x_photo = x_cad + {X_BA} mm (y, z identical)"},
}
m["datum"] = {"id": "D0", "position_sim_m": [0, 0, 0],
              "definition": "symmetry plane  x  wing-root leading-edge station  x  CAD thrust-axis height (motor shaft line before down/right thrust)",
              "why": "stable geometric points that do not move when masses or CG change; CG is given separately below",
              "root_node": "TurboTimberEvolution (identity transform, at D0)"}
m["pose"] = {"export_pose": "neutral body pose: no ground presentation offset, no presentation pitch",
             "kept_built_in_angles": {"wing_incidence_deg": ev(2.0, "deg", "estimated", FOTO),
                                      "wing_dihedral_deg": ev(2.0, "deg", "estimated", FOTO),
                                      "downthrust_deg": ev(ESC["motor"]["caida"], "deg", "estimated", "typical for the type; not measured"),
                                      "right_thrust_deg": ev(ESC["motor"]["derecha"], "deg", "estimated", "typical for the type; not measured")},
             "three_point_ground_attitude_deg": ev(A["helice"]["actitud_3_puntos_grados"], "deg", "derived", CAD + " (wheel + tailwheel contact)",
                                                   note="NOT applied to the export; for the simulator to place the aircraft on the ground")}

# dimensiones
L = D["landmarks_sim"]; span = D["span_m"]; length = D["length_m"]
m["dimensions"] = {
    "model": {"span_m": ev(span, "m", "measured", MEDIDO, note="outermost wingtip vertices (nav-light lenses included)"),
              "length_m": ev(length, "m", "measured", MEDIDO, note="spinner tip to rudder trailing edge, along the body axis"),
              "bbox_sim_m": {"min": [D["bbox_export"]["min"][0], D["bbox_export"]["min"][2], -D["bbox_export"]["max"][1]],
                             "max": [D["bbox_export"]["max"][0], D["bbox_export"]["max"][2], -D["bbox_export"]["min"][1]]},
              "wing_area_m2": ev(A["cg"]["superficie_alar_dm2"]/100, "m2", "derived", CAD),
              "mac_m": ev(A["cg"]["mac_mm"]/1000, "m", "derived", CAD),
              "propeller_radius_m": ev(A["helice"]["radio_mm"]/1000, "m", "estimated", FOTO),
              "main_wheel_radius_m": ev(ESC["tren"]["radio_rueda"]/1000, "m", "estimated", FOTO),
              "tailwheel_radius_m": ev(ESC["tren"]["rueda_cola"]["radio"]/1000, "m", "estimated", FOTO),
              "main_gear_track_m": ev(AT["estabilidad"]["trocha_mm"]/1000, "m", "derived", CAD)},
    "reference": {"span_m": ev(1.555, "m", "borrowed", "integration-team letter (reference listing)"),
                  "length_m": ev(1.040, "m", "borrowed", "integration-team letter (reference listing)")},
    "reconciliation": {
        "span_difference_mm": round(span*1000 - 1555, 1),
        "length_difference_mm": round(length*1000 - 1040, 1),
        "scale_changed": False,
        "explanation": [
            "Span agrees within 0.5 %, so the model is NOT uniformly mis-scaled; scaling by 1040/1117 would shrink the span to ~1.44 m.",
            "The length excess is concentrated ahead of the wing: matching the top-view and side photos puts the wing-root leading edge "
            "about 42-56 mm closer to the propeller plane than the model has it (photo frame x 186-200 mm vs 242 mm in the model), "
            "i.e. the nose/cowl section is about 50-60 mm too long.",
            "The remaining ~15-25 mm is within the uncertainty of where the reference measures length (spinner tip vs cowl, rudder TE vs fuselage end) "
            "and of photo perspective.",
            "Not corrected in r1 on purpose: moving the wing forward changes the CG/main-wheel relationship of the model (the estimated CG would sit "
            "almost over the axle). A fix needs either the manufacturer's CG/dimension drawing or a long-lens, perpendicular side photo with a scale.",
        ],
        "recommended_fix": "shorten the fuselage between firewall and wing LE by ~50-60 mm (non-uniform), then re-verify CG and gear position",
    },
}
m["landmarks"] = {k: {"sim_m": v, "blender_export_m": D["landmarks_export"][k], "evidence": "measured", "source": MEDIDO}
                  for k, v in L.items()}
m["landmarks"]["left_wingtip"]["definition"] = "outermost vertex of the left wing (pilot's left)"
m["landmarks"]["right_wingtip"]["definition"] = "outermost vertex of the right wing (pilot's right)"
m["landmarks"]["nose_spinner_tip"]["definition"] = "most forward vertex of the spinner (propeller_rotor mesh)"
m["landmarks"]["tail_rudder_trailing_edge"]["definition"] = "most aft vertex of the rudder at neutral"
for k in ("left_main_wheel_center", "right_main_wheel_center", "tailwheel_center"):
    m["landmarks"][k]["definition"] = "axle-pivot origin (wheel center) at neutral suspension"
# contactos con el suelo (pose neutra, ruedas sin carga)
cp = ESC["contactos_mm"]
m["ground_contacts_neutral"] = {
    "left_main_wheel_bottom_sim_m": [L["left_main_wheel_center"][0], round(L["left_main_wheel_center"][1] - ESC["tren"]["radio_rueda"]/1000, 6), L["left_main_wheel_center"][2]],
    "right_main_wheel_bottom_sim_m": [L["right_main_wheel_center"][0], round(L["right_main_wheel_center"][1] - ESC["tren"]["radio_rueda"]/1000, 6), L["right_main_wheel_center"][2]],
    "tailwheel_bottom_sim_m": [0.0, round(L["tailwheel_center"][1] - ESC["tren"]["rueda_cola"]["radio"]/1000, 6), L["tailwheel_center"][2]],
    "evidence": "derived", "source": CAD}

# articulaciones
mando_ref = {"aileron_left_hinge": "aileron_left", "aileron_right_hinge": "aileron_right", "flap_left_hinge": "flap_left",
             "flap_right_hinge": "flap_right", "elevator_hinge": "elevator", "rudder_hinge": "rudder", "tailwheel_steer": "tailwheel_fork",
             "tailwheel_axle": "tailwheel", "propeller_spin": "propeller_rotor", "gear_left_suspension": "gear_left_leg",
             "gear_right_suspension": "gear_right_leg", "wheel_left_axle": "wheel_left", "wheel_right_axle": "wheel_right"}
import struct
_raw = open(os.path.join(PKG, "export", "aircraft.glb"), "rb").read()
_gl = json.loads(_raw[20:20 + struct.unpack_from("<I", _raw, 12)[0]])
GLTF_NODE = {n.get("name"): n for n in _gl["nodes"]}
arts = {}
for k, a in D["articulations"].items():
    if k == "thrust_frame": continue
    rol = mando_ref[k]
    r = a.get("range_deg") or [None, None]
    arts[k] = {
        "id": k, "node": k, "parent_node": a["parent"], "mesh_node": rol,
        "members_cad": mapa.ROLES[rol][0], "members_description": mapa.ROLES[rol][1],
        "pivot_sim_m": a["pivot_sim"], "pivot_blender_export_m": a["pivot_m"],
        "axis_sim": a["axis_sim"], "axis_blender_export": a["axis"], "axis_frame": "aircraft root frame (same orientation as the frame named in the key)",
        "axis_local": "+X of the pivot node", "rotation_rule": "right-hand rule about the axis; angle 0 = rest orientation",
        "rest_local_rotation_gltf_xyzw": [round(c, 6) for c in GLTF_NODE[k].get("rotation", [0, 0, 0, 1])],
        "rest_local_translation_gltf_m": [round(c, 6) for c in GLTF_NODE[k].get("translation", [0, 0, 0])],
        "rest_local_quaternion_wxyz_blender": D["rest_local_quaternion_wxyz"][k],
        "rest_note": "the glTF node carries the rest rotation; apply the control angle as rest * axisAngle(+X local, angle)",
        "positive_direction": a["positive"],
        "range": ({"min": r[0], "max": r[1], "unit": "deg", "evidence": "estimated" if r[0] is not None else None,
                   "source": a["range_source"]} if r[0] is not None else {"continuous": True, "source": a["range_source"]}),
        "driven_by": a["driven_by"],
    }
    for extra in ("radius_m",):
        if extra in a: arts[k][extra] = ev(a[extra], "m", "estimated", FOTO)
arts["aileron_left_hinge"]["mixing"] = arts["aileron_right_hinge"]["mixing"] = {
    "differential": ev(ESC["mandos"]["diferencial"], "ratio down/up", "estimated", "authored, typical for the type"),
    "note": "roll right: right aileron TE up (negative), left aileron TE down (positive)"}
arts["tailwheel_steer"]["coupling"] = {"follows": "rudder_hinge", "ratio": 1.0, "note": "tailwheel wire rides in the rudder; coaxial hinge line"}
m["articulations"] = arts
m["articulation_summary"] = {"primary_controls": ["aileron_left_hinge", "aileron_right_hinge", "elevator_hinge", "rudder_hinge"],
                             "secondary": ["flap_left_hinge", "flap_right_hinge", "tailwheel_steer"],
                             "continuous": ["propeller_spin", "wheel_left_axle", "wheel_right_axle", "tailwheel_axle"],
                             "suspension": ["gear_left_suspension", "gear_right_suspension"]}
tf = D["articulations"]["thrust_frame"]
m["thrust"] = {"thrust_frame_node": "thrust_frame", "fixed": True,
               "origin_sim_m": tf["pivot_sim"], "direction_sim": tf["axis_sim"],
               "downthrust_deg": ev(ESC["motor"]["caida"], "deg", "estimated", "typical for the type"),
               "right_thrust_deg": ev(ESC["motor"]["derecha"], "deg", "estimated", "typical for the type"),
               "propeller_plane_origin": "propeller hub (CAD x = -251.5 mm from D0)",
               "rotating_child": "propeller_spin (spinner, 3 blades, backplate, outrunner bell)",
               "rotation_sense": "clockwise seen from behind (normal tractor) = positive about the thrust direction"}
# tren
cab = ESC["tren"]["cables"]
m["landing_gear"] = {
    "type": "two wire-sprung legs hinged on fuselage pins, crossed cables with tension springs between each leg and the opposite fuselage eyelet",
    "suspension_travel_deg": ev(12.0, "deg", "estimated", CAD + " (spring stretch audit)"),
    "spring_stretch_at_full_travel_mm": ev(AT["resorte"]["estiramiento_mm"], "mm", "derived", CAD),
    "spring_stiffness": ev(None, "N/m", "estimated", "unknown; not provided", note="simulator should tune; geometry only"),
    "cables_cosmetic": "gear_cables mesh is static in the rest pose; endpoints below let the simulator re-draw it if legs move",
    "cable_endpoints_sim_m": {k: {"fuselage_eyelet": sim_cad(c["ojal"]), "leg_anchor_rest": sim_cad(c["anclaje"]),
                                  "anchored_to_leg": "gear_left_suspension" if c["pata"] == "izq" else "gear_right_suspension",
                                  "rigid_cable_length_m": c["largo_cable"]/1000, "spring_length_rest_m": c["largo_resorte"]/1000}
                              for k, c in cab.items()},
    "wheel_axis_note": "wheel_*_axle rotate about their own +X (pointing to the pilot's left) so forward rolling is positive; steering (tailwheel_steer) and suspension are separate parent nodes",
}
# masas y CG (parciales, estimadas)
cg = A["cg"]
m["mass_properties"] = {
    "status": "PARTIAL and ESTIMATED. Not a weighed aircraft. Use for first flights only.",
    "total_mass": ev(round(cg["masa_total_g"]/1000, 3), "kg", "estimated", "sum of component estimates below", "+/- 15 %"),
    "cg": {"position_cad_mm": [cg["cg_con_bateria_en_su_bahia_mm"], 0.0, cg["altura_cg_mm"]],
           "position_sim_m": sim_cad([cg["cg_con_bateria_en_su_bahia_mm"], 0.0, cg["altura_cg_mm"]]),
           "percent_mac": ev(cg["cg_pct_mac"], "% MAC", "derived", "component estimates", "+/- 5 % MAC"),
           "recommended_range_aft_of_LE_mm": ev(cg["cg_recomendado_mm"], "mm", "estimated", "25-30 % MAC rule of thumb, not the manual"),
           "note": "CG kept as data, not as the model origin"},
    "components": [{"name": c["pieza"], "mass": ev(round(c["masa_g"]/1000, 4), "kg", "estimated", "class-typical values"),
                    "x_cad_mm": round(c["x_mm"], 1)} for c in cg["desglose"]],
    "inertia": ev(None, "kg m2", "estimated", "not provided in r1", note="can be derived from the component list if needed"),
    "wing_loading": ev(cg["carga_alar_g_dm2"], "g/dm2", "derived", "estimated mass / model wing area"),
    "tail_volume_horizontal": ev(A["cola"]["Vh"], None, "derived", CAD),
}
# mallas y presupuesto
m["meshes"] = {"nodes": D["mesh_counts"], "total_triangles": D["total_triangles"], "total_surfaces": D["total_surfaces"],
               "budget": {"triangles_max": 100000, "surfaces_max": 40, "status": "provisional targets from the letter; both met"},
               "materials": sorted({x for c in D["mesh_counts"].values() for x in c["materials"]}),
               "material_notes": {"glass": "only transparent material (alpha 0.45, blend)", "light_red/light_green": "emissive nav-light lenses",
                                  "foam": "tire foam, rough dark", "metal": "wire, axles, spinner backplate, exhaust stacks"}}
m["hygiene"] = {k: V["checks"][k] for k in V["checks"] if k.startswith(("no_", "normals"))}
m["hygiene"]["residual_coplanar_overlaps"] = V.get("coplanar_overlaps")
m["hygiene"]["hidden_back_to_back_contacts"] = "decal shells touching the skin face-to-face (opposite normals, culled from outside); not visible"
m["export"] = {"file": "export/aircraft.glb", "demo_file": "export/aircraft_demo.glb (same model + one 'control_demo' animation)",
               "tool": f"Blender {D['blender_version']} (bpy module) glTF 2.0 exporter",
               "settings": {"export_format": "GLB", "export_yup": True, "export_apply": True, "export_extras": True,
                            "export_animations": "False (aircraft.glb) / True, merged to one animation (aircraft_demo.glb)",
                            "export_cameras": False, "export_lights": False, "use_selection": "EXPORT_aircraft collection only"},
               "script": "source/scripts/exporta_juego.py", "extras": "every articulation node carries its id, axis, positive sense, range and range source as glTF extras"}
m["generators"] = {"cad": "build123d 0.13.0 on Python 3.13 (source/scripts/modelo_v12.py, tren_aterrizaje_v12.py, helice_spinner.py)",
                   "retessellation": "source/scripts/retesela.py (tolerance 0.3 mm, 0.35 rad) + decal overlap resolution",
                   "export": "source/scripts/exporta_juego.py", "verification": "source/scripts/verifica_glb.py",
                   "metadata": "source/scripts/documenta.py", "mapping": "source/scripts/mapa.py"}
m["verification"] = {"file": "verification.json", "summary": {k: v["pass"] for k, v in V["checks"].items()}}
json.dump(m, open(os.path.join(PKG, "metadata.json"), "w"), indent=1, ensure_ascii=False)

# export-map.json
em = {"description": "CAD part -> exported node; what was merged, excluded or regenerated",
      "nodes": {}, "excluded_cad_parts": mapa.EXCLUIDAS, "material_palette_cad_to_export": mapa.PALETA,
      "material_overrides": {k: v for k, v in mapa.MATERIAL_FORZADO.items()},
      "material_override_reason": "control horns merged into white to keep the surface count under 40",
      "decal_overlap_resolution": json.load(open(os.path.join(BASE, "stl_juego", "_informe.json")))["calcomanias"],
      "decal_offset_rule": "decal shells pushed out 0.12 mm x priority level along vertex normals (glazing/gear brackets 0.12 mm, red belly 0.05 mm) to avoid coplanar z-fighting"}
pivote_de = {v: k for k, v in mando_ref.items()}
for rol, (piezas, desc) in mapa.ROLES.items():
    em["nodes"][rol] = {"cad_parts": piezas, "description": desc, "parent_pivot": pivote_de.get(rol, "TurboTimberEvolution"),
                        "moves": rol in pivote_de, "markings_included": [p for p in piezas if p in mapa.CALCOS],
                        "horns_included": [p for p in piezas if p.startswith("cuerno_")],
                        "materials": D["mesh_counts"][rol]["materials"], "triangles": D["mesh_counts"][rol]["triangles"]}
em["nodes"]["gear_cables"]["regenerated"] = "2 cables (r 0.6 mm, 6 sides) + 2 springs (r 4 mm, 10 sides) from the CAD endpoints; replaces 765,356 CAD spring triangles"
json.dump(em, open(os.path.join(PKG, "export-map.json"), "w"), indent=1, ensure_ascii=False)
print("DOC OK")
