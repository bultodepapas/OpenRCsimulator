"""
Writes metadata.json and export-map.json of the r2 package from what was measured in the export scene
(source/_export_data.json), the verification (verification.json), the r1 metadata and the export map (mapa_r2.py).

  python3 documenta_r2.py --pkg <r2 dir>
"""
import json, os, sys, copy, hashlib, fnmatch, platform
BASE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, BASE)
import mapa_r2 as MP
PKG = os.path.abspath(sys.argv[sys.argv.index("--pkg") + 1])
SRC = os.path.join(PKG, "source")
D = json.load(open(os.path.join(SRC, "_export_data.json")))
V = json.load(open(os.path.join(PKG, "verification.json")))
R1 = json.load(open(os.path.join(SRC, "inputs", "r1_metadata.json")))
REP = json.load(open(os.path.join(SRC, "stl_juego_r2", "_report.json")))
OKJ = json.load(open(os.path.join(SRC, "inputs", "ok.json")))
NEG = os.path.join(SRC, "verification_negative", "negative_tests.json")
NEG = json.load(open(NEG)) if os.path.exists(NEG) else None
MEAS = "measured on the exported mesh (transformed vertices, Blender, before export; re-checked after GLB re-import)"
def ev(value, unit, evidence, source, note=None, **k):
    d = {"value": value, "unit": unit, "evidence": evidence, "source": source, **k}
    if note: d["note"] = note
    return d
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
sim = lambda v: [round(v[0], 6), round(v[2], 6), round(-v[1], 6)]

m = copy.deepcopy(R1)
m["schema"] = "openrc-aircraft-delivery r2 (delivery specification 2026-10-13, revision 2)"
a = m["aircraft"]
a["revision"] = "r2"
a["status"] = ("r2: airframe split into crash sections (openrc_section), r1 pivots kept unchanged (names, parents, rest transforms), "
               "closure faces at section joints, master v15 exterior + v17 markings and 10-size rotor")
a["configuration"]["motor"] = ev("10-size outrunner (bell modelled; stator/windings hidden, not exported)", None, "estimated",
                                 "master v17 research: product listings of the type (10-size, ~800 Kv)")
a["configuration"]["slats"]["note"] = "no slats exported; the small grey slat brackets stay on the fixed wing sections as fixed parts"
a["configuration"]["floats"]["note"] = "no floats modelled or exported"
a["configuration"]["flaps"] = "present, exported at 0 deg with their own hinges; simulator steps 0 / 20.7 / 36.6 deg"
a["configuration"]["ground_attitude"] = "none: the export is the neutral body pose (no ground pitch, neutral controls)"

# ---------------- dimensions and landmarks (r2 measurement)
L = D["landmarks_export"]
dm = m["dimensions"]
dm["model"]["span_m"] = ev(D["span_m"], "m", "measured", MEAS, "outermost wingtip vertices (master v15 wingtip)")
dm["model"]["length_m"] = ev(D["length_m"], "m", "measured", MEAS, "spinner tip to rudder trailing edge along the body axis")
dm["model"]["bbox_sim_m"] = {"min": [D["bbox_export"]["min"][0], D["bbox_export"]["min"][2], -D["bbox_export"]["max"][1]],
                             "max": [D["bbox_export"]["max"][0], D["bbox_export"]["max"][2], -D["bbox_export"]["min"][1]]}
dm["model"]["propeller_diameter_m"] = ev(D["dimensions"]["propeller_diameter_m"], "m", "measured", MEAS, "blade tip circle about the propeller_spin axis")
dm["model"].pop("propeller_radius_m", None)
dm["model"]["main_wheel_radius_m"] = ev(D["dimensions"]["wheel_radius_main_m"], "m", "measured", MEAS, "max radial distance from wheel_left_axle")
dm["model"]["tailwheel_radius_m"] = ev(D["dimensions"]["wheel_radius_tail_m"], "m", "measured", MEAS)
dm["r1_measured"] = {"span_m": 1.5479, "length_m": 1.1166, "source": "r1 metadata (master v12)"}
dm["reconciliation"] = {"scale_changed": False, "span_difference_to_r1_mm": round((D["span_m"] - 1.5479)*1000, 1),
                        "length_difference_to_r1_mm": round((D["length_m"] - 1.1166)*1000, 1),
                        "span_difference_to_manual_mm": round((D["span_m"] - 1.555)*1000, 1),
                        "length_difference_to_manual_mm": round((D["length_m"] - 1.040)*1000, 1),
                        "explanation": "not rescaled (delivery spec). The span is 2.4 mm shorter than r1 because the r2 sections come from the "
                                       "master v15 wingtip (r1 used v12); the length differs by "
                                       f"{round((D['length_m'] - 1.1166)*1000, 1)} mm: v17 spinner (-0.8 mm) and the rudder trailing edge, which "
                                       "is now the foam edge itself (r1 measured the marking shell standing proud of it). The manual "
                                       "length (1.040 m) is a listing value whose measuring stations are unknown."}
DEF = {"left_wingtip": "outermost vertex of wing_left_fixed (pilot's left)", "right_wingtip": "outermost vertex of wing_right_fixed",
       "nose_spinner_tip": "foremost vertex of propeller_rotor", "tail_rudder_trailing_edge": "aftmost vertex of rudder",
       "wing_root_leading_edge": "foremost wing vertex within 3 mm of the symmetry plane", "left_main_wheel_center": "wheel_left_axle origin",
       "right_main_wheel_center": "wheel_right_axle origin", "tailwheel_center": "tailwheel_axle origin", "propeller_hub": "propeller_spin origin",
       "datum_D0": "root node origin", "left_main_wheel_contact": "lowest vertex of wheel_left (neutral, no ground)",
       "right_main_wheel_contact": "lowest vertex of wheel_right", "tailwheel_contact": "lowest vertex of tailwheel"}
m["landmarks"] = {k: {"sim_m": D["landmarks_sim"][k], "blender_export_m": D["landmarks_export"][k], "evidence": "measured", "source": MEAS,
                      "definition": DEF.get(k, k)} for k in D["landmarks_export"]}
m["ground_contacts_neutral"] = {"left_main_wheel_bottom_sim_m": D["landmarks_sim"]["left_main_wheel_contact"],
                                "right_main_wheel_bottom_sim_m": D["landmarks_sim"]["right_main_wheel_contact"],
                                "tailwheel_bottom_sim_m": D["landmarks_sim"]["tailwheel_contact"], "evidence": "measured", "source": MEAS}
m["hinge_lines"] = {n: {"pivot_sim_m": p["pivot_sim"], "axis_sim": p["axis_sim"]} for n, p in D["pivots"].items()
                    if n.endswith("_hinge")}
m["thrust"]["axis_sim"] = D["pivots"]["thrust_frame"]["axis_sim"]
m["thrust"]["origin_sim_m"] = D["pivots"]["thrust_frame"]["pivot_sim"]

ESC = json.load(open(os.path.join(SRC, "inputs", "escena.json")))
lg = m["landing_gear"]
sc_ = lambda p: [round(p[1]/1000, 6), round(p[2]/1000, 6), round(p[0]/1000, 6)]
lg["cable_endpoints_sim_m"] = {k: {"fuselage_eyelet": sc_(c["ojal"]), "anchor_rest": sc_(c["anclaje"]),
                                   "rigid_cable_length_m": c["largo_cable"]/1000.0} for k, c in ESC["tren"]["cables"].items()}
lg["cable_source"] = "master v17 escena.json (the cosmetic gear_cables mesh is rebuilt from these points, rest pose only)"
lg["suspension_clearance_note"] = ("the modelled leg link meets its foam bracket beyond about 6 deg; the 0-12 deg range is kept "
                                   "(reported in articulations.*.clearance, not clamped)")

# ---------------- articulations: r1 entries + r2 members, section, both ranges, clearance
CL = V["clearance"]["per_articulation"]
SIM = {"aileron_left_hinge": 34.5, "aileron_right_hinge": 34.5, "elevator_hinge": 17.8, "rudder_hinge": 18.2}
POS = {"tailwheel_steer": "trailing wheel to the pilot's right (follows the rudder)", "gear_left_suspension": "leg swings outboard (left)",
       "gear_right_suspension": "leg swings outboard (right)"}
for n, ar in m["articulations"].items():
    p = D["pivots"][n]
    ar["frame"] = "rest_local: parent-relative rest transform of the node; angle applied as rest * rot(+X local, angle)"
    ar["mesh_members"] = p["members"]
    ar["members_cad"] = [x[1] for x in MP.OBJECTS[p["members"][0]][1]] if p["members"] and p["members"][0] in MP.OBJECTS else ar.get("members_cad")
    ar["openrc_section"] = p["section"]
    ar["pivot_sim_m"] = p["pivot_sim"]; ar["pivot_blender_export_m"] = p["pivot_m"]; ar["axis_sim"] = p["axis_sim"]; ar["axis_blender_export"] = p["axis"]
    ar["rest_local_quaternion_wxyz_blender"] = p["rest_local_quaternion_wxyz"]
    ar["unchanged_from_r1"] = True
    if n in POS: ar["positive_direction"] = POS[n]
    if n in SIM:
        r = ar["range"]; ar["range_authored"] = dict(r); ar["range_authored"]["source"] = "authored approximation (r1 value, unchanged)"
        ar["range_simulator"] = {"min": -SIM[n], "max": SIM[n], "unit": "deg", "evidence": "borrowed",
                                 "source": "OpenRC Simulator manual linear travel converted at an assumed measurement station (delivery spec r2, sec. 4)",
                                 "approximate": True}
    if n.startswith("flap"):
        ar["range_authored"] = dict(ar["range"]); ar["simulator_steps_deg"] = {"value": [0.0, 20.7, 36.6], "unit": "deg", "evidence": "borrowed",
                                                                               "source": "delivery spec r2, sec. 4"}
    if n == "tailwheel_steer":
        ar["range"] = {"min": -30.0, "max": 30.0, "unit": "deg", "evidence": "estimated", "source": "delivery spec r2 / authored (follows rudder)"}
    c = CL.get(n)
    if c:
        ar["clearance"] = {"clear_envelope_deg": c["clear_envelope_deg"], "swept_deg": c["swept_deg"], "step_deg": c["step_deg"],
                           "authored_range_clear": c["authored_clear"], "simulator_range_clear": c["simulator_clear"],
                           "interfering_angles_deg": c["interfering_angles_deg"], "against": c["against"],
                           **({"steps_checked_deg": c["steps_checked_deg"]} if "steps_checked_deg" in c else {}),
                           **({"coupled_with": c["coupled_with"]} if "coupled_with" in c else {}),
                           "note": "reported, not clamped"}
m["articulations"]["thrust_frame"] = {"id": "thrust_frame", "node": "thrust_frame", "parent_node": "TurboTimberEvolution", "moving": False,
                                      "openrc_section": None, "pivot_sim_m": D["pivots"]["thrust_frame"]["pivot_sim"],
                                      "axis_sim": D["pivots"]["thrust_frame"]["axis_sim"],
                                      "rest_local_quaternion_wxyz_blender": D["pivots"]["thrust_frame"]["rest_local_quaternion_wxyz"],
                                      "note": "fixed frame (thrust line, 2 deg down / 2 deg right); untagged by rule; parent of propeller_spin"}

# ---------------- crash sections
m["sections"] = [{"name": s, "nodes": sorted(D["sections"].get(s, [])),
                  "meshes": sorted(o for o in D["sections"].get(s, []) if o in D["mesh_counts"]),
                  "triangles": sum(D["mesh_counts"][o]["triangles"] for o in D["sections"].get(s, []) if o in D["mesh_counts"])}
                 for s in MP.SECTIONS]
m["sections_rules"] = {"property": "openrc_section (string, glTF node extras)", "vocabulary": list(MP.SECTIONS),
                       "untagged": ["TurboTimberEvolution", "thrust_frame"],
                       "one_section_per_mesh": True, "welds_across_sections": False,
                       "unused_vocabulary": [s for s in MP.SECTIONS if not D["sections"].get(s)],
                       "unused_note": "wing_center is not used: the wing is two plug-in halves meeting on the symmetry plane, no centre section",
                       "cuts": {"cowl_joint": {"sidecar_x_mm": MP.X_COWL_CUT, "blender_y_m": -MP.X_COWL_CUT/1000.0,
                                               "parts_cut": sorted({c["part"] for c in REP["cuts"]})}},
                       "closures": {"rule": "faces of a section lying on another section (within 0.3 mm, facing it) are split off, painted the plain "
                                            "unpainted-foam colour (material 'white') and set 0.2 mm inside their own piece",
                                    "faces_per_joint": D["informe"]["closure_faces"], "verified": V.get("closures")}}

# ---------------- meshes, counts
m["meshes"] = {"nodes": D["mesh_counts"], "total_triangles": D["total_triangles"], "total_surfaces": D["total_surfaces"],
               "materials": D["materials"], "textures": 0,
               "budget": {"triangles_target": [30000, 50000], "triangles_acceptable": 64000, "surfaces_max": 40, "materials_max": 10},
               "surfaces_over_budget_reason": ("49 glTF primitives > 40: the crash split needs 21 separate meshes (one per section part) and each "
                                               "mesh needs one primitive per material it shows (wings 5: white foam, red/black paint, dark-grey brackets, "
                                               "nav lens). Merging colours would remove the paint scheme; textures were avoided by request (base colour "
                                               "only). All 10 materials are shared across meshes."),
               "decimation": D["informe"]["decimation"], "decal_offset_mm": D["informe"]["decal_offset_mm"],
               "painted_base_colour": D["informe"].get("painted"), "marking_shell_seating": D["informe"].get("marking_seating")}
m.pop("hygiene", None)
m["hygiene"] = {k: V["checks"][k] for k in ("no_degenerate_faces", "no_duplicate_faces", "no_flicker_coplanar_overlaps", "backface_culling_on") if k in V["checks"]}
m["hygiene"]["non_manifold_edges"] = {"value": V["checks"].get("non_manifold_edges_reported", {}).get("detail"),
                                      "note": "open edges come from single-sided marking sheets (their hidden underside is removed) and from the "
                                              "split-off closure faces; every foam shell is closed"}

# ---------------- mass: placeholder only
mp = m["mass_properties"]
mp["status"] = "NON-FLIGHT PLACEHOLDER. The 1.46 kg ledger below is a modelling estimate and must not be used as flight data."
mp["total_mass"]["evidence"] = "estimated"; mp["total_mass"]["placeholder"] = True
mp["selected_reference_mass"] = ev(2.190, "kg", "borrowed", "manual reference selected by the integration team (delivery spec r2)",
                                   "use this value (with the simulator's own CG/inertia) for flight; r2 geometry does not define mass, CG or inertia")
mp["geometry_creates_mass_values"] = False

# ---------------- export, generators, verification
glb = os.path.join(PKG, "export", "aircraft.glb"); demo = os.path.join(PKG, "export", "aircraft_demo.glb")
m["export"] = {"file": "export/aircraft.glb", "sha256": sha(glb), "bytes": os.path.getsize(glb),
               "demo_file": "export/aircraft_demo.glb", "demo_sha256": sha(demo),
               "demo_animation": "one 'control_demo' animation, one control at a time (timeline in source/_export_data.json)",
               "tool": f"Blender {D['blender_version']} (bpy module) + glTF 2.0 exporter io_scene_gltf2 5.2.40",
               "settings": {"export_format": "GLB", "use_active_collection": "EXPORT_aircraft", "export_yup": True, "export_apply": True,
                            "export_extras": True, "export_materials": "EXPORT", "export_animations": False, "export_cameras": False,
                            "export_lights": False, "export_draco_mesh_compression_enable": False},
               "scripts": {"build": "source/scripts/exporta_r2.py --pkg .", "re-export from .blend": "source/scripts/exporta_desde_blend.py"},
               "frame_conversion": "godot = (blender.x, blender.z, -blender.y)"}
m["generators"] = {"cad": "build123d 0.13.0, Python 3.13 (master v15/v17 BREP caches; not shipped: CAD rebuild from this package is UNSUPPORTED)",
                   "retessellation": "source/scripts/retesela_r2.py (needs the master caches; output shipped in source/stl_juego_r2)",
                   "export": "source/scripts/exporta_r2.py", "re_export": "source/scripts/exporta_desde_blend.py",
                   "verification": "source/scripts/verifica_r2.py + source/scripts/valida_glb.py + source/scripts/pruebas_negativas.py",
                   "metadata": "source/scripts/documenta_r2.py", "mapping": "source/scripts/mapa_r2.py",
                   "python": platform.python_version(), "blender": D["blender_version"], "gltf_exporter": "5.2.40"}
m["verification"] = {"file": "verification.json", "pass": V["pass"], "failed": V["failed"],
                     "summary": {k: v["pass"] for k, v in V["checks"].items()},
                     "advisory_not_passed": [k for k, v in V["checks"].items() if v.get("advisory") and not v["pass"]],
                     "negative_tests": (NEG and {"pass": NEG["pass"], "cases": {c["case"]: c["rejected"] for c in NEG["cases"]}})}
json.dump(m, open(os.path.join(PKG, "metadata.json"), "w"), indent=1)

# ---------------- export map: every source part exactly once
v17 = set(OKJ["materiales"])
parts = sorted(v17 | {p for _, mm, _ in MP.OBJECTS.values() for _, p, _ in mm})
uso = {}
for o, (s, mm, desc) in MP.OBJECTS.items():
    for ver, p, cut in mm: uso.setdefault(p, []).append({"node": o, "section": s, "cache": ver, "cut": cut})
em = {"description": "every source part of the master (v17 part list + v15 exterior solids) accounted for exactly once",
      "sources": {"v15": "master v15 BREP cache (closed exterior foam solids)", "v17": "master v17 BREP cache (markings as 0.35 mm skins, 10-size rotor)"},
      "parts": {}, "nodes": {}}
for p in parts:
    if p in uso:
        u = uso[p]
        k = "cut" if any(x["cut"] for x in u) else ("simplified" if any(p.startswith(d) for d in MP.DECALS) else "included")
        em["parts"][p] = {"status": k, "to": u, "material": MP.MATERIAL_OVERRIDE.get(p) or MP.PALETTE.get(REP["materials_cad"].get(p) or
                          next((REP["materials_cad"][x] for x in REP["materials_cad"] if x.startswith(p + "@")), None), None)}
        if p in MP.PAINTED_DECALS:
            em["parts"][p]["status"] = "painted"
            em["parts"][p]["note"] = ("base colour: the foam part it covers is split in CAD by this marking (higher priority first); the piece "
                                      "keeps this colour, hidden walls between pieces are removed and the pieces welded; no marking shell is exported")
        elif p in MP.DECALS: em["parts"][p]["note"] = "marking shell: hidden underside removed, lifted 0.12 mm x priority, seated >= 0.1 mm above the foam"
        dec = D["informe"]["decimation"]["parts"]
        for x in dec:
            if x.split("@")[0] == p and dec[x]["ratio"] < 1: em["parts"][p]["decimated"] = dec[x]
    else:
        pat = [k for k in MP.EXCLUDED if fnmatch.fnmatch(p, k)]
        em["parts"][p] = {"status": "excluded", "reason": MP.EXCLUDED[pat[0]] if pat else "UNMAPPED"}
cuenta = {}
for p, v in em["parts"].items(): cuenta[v["status"]] = cuenta.get(v["status"], 0) + 1
em["counts"] = cuenta
em["unmapped"] = [p for p, v in em["parts"].items() if v.get("reason") == "UNMAPPED"]
for o, (s, mm, desc) in MP.OBJECTS.items():
    em["nodes"][o] = {"section": s, "description": desc, "parent": D["mesh_counts"][o]["parent"],
                      "members": [p if c is None else f"{p}@{c}" for _, p, c in mm] or ["(generated in Blender from escena.json cable data)"],
                      "triangles": D["mesh_counts"][o]["triangles"], "materials": D["mesh_counts"][o]["materials"]}
em["generated"] = {"gear_cables": "low-poly cables (6 sides) and springs (10 sides) rebuilt from escena.json; replace cable_*/resorte_*"}
em["material_palette_cad_to_export"] = MP.PALETTE; em["material_overrides"] = MP.MATERIAL_OVERRIDE
em["retessellation"] = {"script": "source/scripts/retesela_r2.py", "tolerance_mm": REP["tol_mm"], "angular_tolerance_rad": REP["tol_ang_rad"],
                        "cuts": REP["cuts"], "decal_skinning": REP.get("skinned"), "decal_overlaps": REP["overlaps"]}
json.dump(em, open(os.path.join(PKG, "export-map.json"), "w"), indent=1)
print("METADATA OK", cuenta, "unmapped", em["unmapped"])
