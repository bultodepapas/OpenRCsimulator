#!/usr/bin/env python3
"""TT-02: build geometry.json for the Turbo Timber Evolution from three provenance-bearing inputs.

  * the author's r1 metadata.json (pivots, axes, rest transforms, ranges, landmarks, component stations), identified by
    SHA-256 through source-manifest.json (TT-01);
  * mesh-measurements.json, written by research/timber/tt02/measure_mesh.gd from the scene Godot imports (planform
    slices, extents, extreme vertices, wheel and propeller radii);
  * manual.json, the hand-edited manufacturer anchors (span, length, masses, CG, throws in millimetres).

Model axes: metres, +X right, +Y up, -Z nose; the datum D0 (origin) is the symmetry plane x the wing-root leading-edge
station x the thrust-axis height, exactly as the r1 export. Structural positions for the aircraft contract convert as
[x_aft, y_right, z_up] = [z_model, x_model, y_model].

    python3 assets/aircraft/turbo-timber-evolution/build_geometry.py          # writes geometry.json
    python3 assets/aircraft/turbo-timber-evolution/build_geometry.py --check  # fails if geometry.json is stale
"""
import hashlib
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MANIFEST = HERE / "source-manifest.json"
MEASUREMENTS = HERE / "mesh-measurements.json"
MANUAL = HERE / "manual.json"
TARGET = HERE / "geometry.json"
CATALOG_ID = "eflite-turbo-timber-evolution"
SCRIPT = "assets/aircraft/turbo-timber-evolution/build_geometry.py"
MEASURED = "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json)"
AUTHOR = "r1/metadata.json (author's CAD export)"
CLEAN_WING_Y_EXTENT = 0.05  # a slice with more vertical extent than this contains the fuselage, not a wing section
CLEAN_TAIL_Y_EXTENT = 0.02
CLEAN_FIN_X_EXTENT = 0.02
## apply_surfaces() receives degrees positive trailing-edge UP (ailerons, elevator) and RIGHT (rudder); r1 pivots are
## positive trailing-edge DOWN (ailerons, flaps, elevator) and RIGHT (rudder). Flaps are positive down in both.
APP_SIGN = {"aileron_left_hinge": -1.0, "aileron_right_hinge": -1.0, "elevator_hinge": -1.0, "rudder_hinge": 1.0,
            "flap_left_hinge": 1.0, "flap_right_hinge": 1.0}
APP_KEY = {"aileron_left_hinge": "aileron_left", "aileron_right_hinge": "aileron_right", "elevator_hinge": "elevator",
           "rudder_hinge": "rudder", "flap_left_hinge": "flap_left", "flap_right_hinge": "flap_right"}


def r(x, nd=6):
    return round(float(x), nd)


def q(value, unit, kind, source):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def norm(a):
    return math.sqrt(sum(x * x for x in a))


def point_line_distance(point, origin, axis):
    return norm(cross(sub(point, origin), axis)) / norm(axis)


def throw_angle_deg(d_m, r_m):
    return math.degrees(2.0 * math.asin(min(1.0, d_m / (2.0 * r_m))))


def linear_fit(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return slope, my - slope * mx


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    metadata_path = delivery / manifest["key_files"]["metadata"]["path"]
    if sha256(metadata_path) != manifest["key_files"]["metadata"]["sha256"]:
        sys.exit("r1 metadata.json does not match source-manifest.json: run research/timber/tt01/manifest.py and review")
    md = json.loads(metadata_path.read_text(encoding="utf-8"))
    mm = json.loads(MEASUREMENTS.read_text(encoding="utf-8"))
    if mm["glb_sha256"] != manifest["key_files"]["glb"]["sha256"]:
        sys.exit("mesh-measurements.json describes another GLB than source-manifest.json")
    man = json.loads(MANUAL.read_text(encoding="utf-8"))
    revision = manifest["visual_revision"]
    meshes = mm["meshes"]
    pivots = mm["pivots"]
    arts = md["articulations"]

    # ---- wing: constant-chord rectangular panel with rounded tips (right side; the model is mirrored) ----
    wing_rows = {row["station"]: row["groups"] for row in mm["slices"]["wing"]["rows"]}
    clean = []
    for x in sorted(k for k in wing_rows if k >= 0):
        g = wing_rows[x]
        if "airframe_skin" not in g:
            continue
        a = g["airframe_skin"]
        if a["max"][1] - a["min"][1] > CLEAN_WING_Y_EXTENT:
            continue  # fuselage/cabin inside the band
        control = g.get("aileron_right") or g.get("flap_right")
        te = control["aft"] if control else a["aft"]
        clean.append({"x": x, "le": a["fore"], "te": te, "te_fixed_z": a["max"][2], "y_min": a["min"][1], "y_max": a["max"][1],
                      "control": "aileron" if "aileron_right" in g else ("flap" if "flap_right" in g else None)})
    panel = [s for s in clean if s["control"]]          # constant-chord stations carrying a flap or an aileron
    tip = [s for s in clean if not s["control"] and s["x"] > panel[-1]["x"]]
    le_z = sorted(s["le"][2] for s in panel)[len(panel) // 2]
    te_z = sorted(s["te"][2] for s in panel)[len(panel) // 2]
    chord = te_z - le_z
    hinge_z = arts["aileron_right_hinge"]["pivot_sim_m"][2]
    aileron = meshes["aileron_right"]["extents_root"]
    flap = meshes["flap_right"]["extents_root"]
    skin = mm["extents"]["skin"]
    span_skin = skin["max"][0] - skin["min"][0]
    span_all = mm["extents"]["all"]["max"][0] - mm["extents"]["all"]["min"][0]
    # Chord distribution for the area: the panel chord from the centreline to the last panel station, then the measured
    # tip stations, then zero at the skin tip. Trapezoid integration, both halves.
    stations = [(0.0, chord)] + [(s["x"], s["te"][2] - s["le"][2]) for s in panel] + [(s["x"], s["te"][2] - s["le"][2]) for s in tip] + [(skin["max"][0], 0.0)]
    half_area = sum((x1 - x0) * (c0 + c1) / 2.0 for (x0, c0), (x1, c1) in zip(stations, stations[1:]))
    dihedral_slope, _ = linear_fit([s["x"] for s in panel], [s["le"][1] for s in panel])
    incidence_apparent = [math.degrees(math.atan2(s["le"][1] - s["te"][1], s["te"][2] - s["le"][2])) for s in panel]
    y_extent = [s["y_max"] - s["y_min"] for s in panel]
    aileron_pivot = pivots["aileron_right_hinge"]
    aileron_station = next(s for s in panel if s["control"] == "aileron")
    flap_station = next(s for s in panel if s["control"] == "flap")
    r_aileron = point_line_distance(aileron_station["te"], aileron_pivot["root_origin"], aileron_pivot["root_axis_x"])
    r_flap = point_line_distance(flap_station["te"], pivots["flap_right_hinge"]["root_origin"], pivots["flap_right_hinge"]["root_axis_x"])
    fuselage_half_width_at_wing = max(max(abs(row["groups"]["airframe_skin"]["min"][0]), abs(row["groups"]["airframe_skin"]["max"][0]))
                                      for row in mm["slices"]["fuselage"]["rows"] if 0.06 - 1e-9 <= row["station"] <= 0.16 + 1e-9 and "airframe_skin" in row["groups"])
    wing = {
        "planform": "rectangular, constant chord from the fuselage side to the last aileron station, rounded tips; the model is mirrored about x = 0",
        "span": q(r(span_all, 6), "m", "measured", MEASURED + ": outermost vertices, nav-light lenses included (manual: 1.555 m)"),
        "span_skin": q(r(span_skin, 6), "m", "measured", MEASURED + ": outermost white skin vertices (lenses excluded)"),
        "le_z": q(r(le_z), "m", "measured", MEASURED + ": median leading-edge z of the constant-chord stations (datum D0 is the root LE station)"),
        "te_z": q(r(te_z), "m", "measured", MEASURED + ": median trailing-edge z of the flap/aileron stations"),
        "chord": q(r(chord), "m", "measured", MEASURED + ": te_z - le_z, constant over the flap and aileron stations"),
        "mac": q(r(chord), "m", "derived", "rectangular panel: MAC = chord (r1 metadata: 0.213 m from the CAD)"),
        "area": q(r(2.0 * half_area), "m2", "derived", SCRIPT + ": trapezoid integral of the measured chord over the span, fuselage carry-through at the panel chord, rounded tips from the tip slices (r1 CAD: 0.329 m2)"),
        "area_rectangular": q(r(span_all * chord), "m2", "derived", "span x chord, no tip rounding"),
        "panel_x": [r(panel[0]["x"], 3), r(panel[-1]["x"], 3)],
        "fuselage_half_width_at_wing": q(r(fuselage_half_width_at_wing, 4), "m", "measured", MEASURED + ": largest airframe-skin half-width of the fuselage slices between z = 0.06 and 0.16 m"),
        "hinge_z": q(r(hinge_z), "m", "measured", AUTHOR + ": aileron and flap pivots share z = 0.157726 m"),
        "hinge_fraction": q(r((hinge_z - le_z) / chord, 4), "1", "derived", "(hinge_z - le_z) / chord"),
        "control_chord_aft_of_hinge": q(r(te_z - hinge_z), "m", "measured", "te_z - hinge_z"),
        "control_nose_ahead_of_hinge": q(r(hinge_z - aileron["min"][2]), "m", "measured", MEASURED + ": rounded control-surface nose ahead of the pivot"),
        "aileron_x": [r(aileron["min"][0]), r(aileron["max"][0])],
        "flap_x": [r(flap["min"][0]), r(flap["max"][0])],
        "dihedral_deg": q(r(math.degrees(math.atan(dihedral_slope)), 3), "deg", "measured", MEASURED + ": slope of the leading-edge y over the panel stations (author: 2 deg)"),
        "incidence_deg": q(2.0, "deg", "estimated", AUTHOR + ": 2 deg chord incidence built into the export; the measured LE-nose-to-TE line is %.2f-%.2f deg (nose radius above the chord line)" % (min(incidence_apparent), max(incidence_apparent))),
        "section_y_extent": q(r(sum(y_extent) / len(y_extent)), "m", "measured", MEASURED + ": mean vertical extent of the panel sections (thickness plus the incidence tilt of the chord)"),
        "thickness_ratio_upper_bound": q(r(sum(y_extent) / len(y_extent) / chord, 4), "1", "derived", "section_y_extent / chord; the true t/c is lower because the tilted chord contributes to the extent"),
        "stations": [[r(s["x"], 3), r(s["le"][2]), r(s["te"][2]), r(s["le"][1]), r(s["te"][1])] for s in panel + tip],
        "stations_columns": ["x", "le_z", "te_z", "le_y", "te_y"],
        "tip_stations": [[r(s["x"], 3), r(s["le"][2]), r(s["te"][2])] for s in tip],
    }
    # ---- horizontal tail ----
    tail_rows = {row["station"]: row["groups"] for row in mm["slices"]["tail"]["rows"]}
    tail_clean = []
    for x in sorted(k for k in tail_rows if k > 0):
        g = tail_rows[x]
        if "airframe_skin" not in g or "elevator" not in g:
            continue
        a = g["airframe_skin"]
        if a["max"][1] - a["min"][1] > CLEAN_TAIL_Y_EXTENT:
            continue
        tail_clean.append({"x": x, "le": a["fore"], "te": g["elevator"]["aft"], "te_fixed_z": a["max"][2], "y_min": a["min"][1], "y_max": a["max"][1]})
    tx = [s["x"] for s in tail_clean]
    le_slope, le_0 = linear_fit(tx, [s["le"][2] for s in tail_clean])
    te_slope, te_0 = linear_fit(tx, [s["te"][2] for s in tail_clean])
    elevator = meshes["elevator"]["extents_root"]
    half_span_t = elevator["max"][0]
    tail_area = 2.0 * ((te_0 - le_0) * half_span_t + (te_slope - le_slope) * half_span_t ** 2 / 2.0)
    stab_hinge = pivots["elevator_hinge"]
    r_elevator_root = point_line_distance(tail_clean[0]["te"], stab_hinge["root_origin"], stab_hinge["root_axis_x"])
    r_elevator_tip = point_line_distance(tail_clean[-1]["te"], stab_hinge["root_origin"], stab_hinge["root_axis_x"])
    tail = {
        "planform": "one-piece elevator behind a swept-leading-edge stabilizer; linear fits over the clean stations, carry-through at the centreline",
        "span": q(r(2.0 * half_span_t), "m", "measured", MEASURED + ": elevator mesh x extent (the stabilizer slice disappears between x = 0.29 and 0.30 m)"),
        "y": q(r(stab_hinge["root_origin"][1]), "m", "measured", AUTHOR + ": elevator hinge height"),
        "hinge_z": q(r(stab_hinge["root_origin"][2]), "m", "measured", AUTHOR + ": elevator pivot"),
        "le_z_centreline": q(r(le_0), "m", "derived", "linear fit of the stabilizer leading edge extrapolated to x = 0"),
        "te_z_centreline": q(r(te_0), "m", "derived", "linear fit of the elevator trailing edge extrapolated to x = 0"),
        "root_chord": q(r(te_0 - le_0), "m", "derived", "centreline chord from the fits"),
        "tip_chord": q(r((te_0 + te_slope * half_span_t) - (le_0 + le_slope * half_span_t)), "m", "derived", "chord at the elevator tip from the fits"),
        "le_sweep_deg": q(r(math.degrees(math.atan(le_slope)), 3), "deg", "measured", MEASURED + ": leading-edge slope"),
        "te_sweep_deg": q(r(math.degrees(math.atan(te_slope)), 3), "deg", "measured", MEASURED + ": elevator trailing-edge slope (negative = forward)"),
        "area": q(r(tail_area), "m2", "derived", SCRIPT + ": planform between the fitted edges from the centreline to the tip, both sides (r1 CAD: 0.0756 m2)"),
        "elevator_chord_aft_of_hinge_root": q(r(r_elevator_root), "m", "measured", "distance from the hinge axis to the trailing edge at x = %.2f m" % tail_clean[0]["x"]),
        "elevator_chord_aft_of_hinge_tip": q(r(r_elevator_tip), "m", "measured", "distance from the hinge axis to the trailing edge at x = %.2f m" % tail_clean[-1]["x"]),
        "section_y_extent": q(r(sum(s["y_max"] - s["y_min"] for s in tail_clean) / len(tail_clean)), "m", "measured", MEASURED + ": mean vertical extent of the stabilizer sections"),
        "tail_arm_quarter_chords": q(r((le_0 + (te_0 - le_0) / 4.0) - (le_z + chord / 4.0)), "m", "derived", "stabilizer centreline quarter chord minus wing quarter chord (r1 CAD Lt: 0.612 m)"),
        "stations": [[r(s["x"], 3), r(s["le"][2]), r(s["te_fixed_z"]), r(s["te"][2])] for s in tail_clean],
        "stations_columns": ["x", "le_z", "fixed_te_z", "elevator_te_z"],
    }
    # ---- fin and rudder ----
    fin_rows = {row["station"]: row["groups"] for row in mm["slices"]["fin"]["rows"]}
    fin_clean = []
    for y in sorted(fin_rows):
        g = fin_rows[y]
        if "airframe_skin" not in g or "rudder" not in g:
            continue
        a = g["airframe_skin"]
        if a["max"][0] - a["min"][0] > CLEAN_FIN_X_EXTENT:
            continue
        fin_clean.append({"y": y, "le": a["fore"], "te": g["rudder"]["aft"], "te_fixed_z": a["max"][2]})
    fy = [s["y"] for s in fin_clean]
    fin_slope, fin_0 = linear_fit(fy, [s["le"][2] for s in fin_clean])
    rudder = meshes["rudder"]["extents_root"]
    rudder_hinge = pivots["rudder_hinge"]
    fin_top = mm["extents"]["all"]["max"][1]
    fin_root_y = fin_clean[0]["y"]
    rudder_te_z = mm["extremes"]["maxz"]["root"][2]
    r_rudder = point_line_distance(mm["extremes"]["maxz"]["root"], rudder_hinge["root_origin"], rudder_hinge["root_axis_x"])
    chord_at = lambda y: rudder_te_z - (fin_0 + fin_slope * y)
    fin_area = (chord_at(fin_root_y) + chord_at(fin_top)) / 2.0 * (fin_top - fin_root_y)
    fin = {
        "planform": "swept fin with dorsal fillet, straight vertical rudder trailing edge; the rudder extends below the fuselage top to the tailwheel wire",
        "top_y": q(r(fin_top), "m", "measured", MEASURED + ": highest vertex of the model (rudder/fin tip)"),
        "root_y": q(r(fin_root_y), "m", "measured", MEASURED + ": first horizontal slice clear of the fuselage"),
        "hinge_z": q(r(rudder_hinge["root_origin"][2]), "m", "measured", AUTHOR + ": rudder pivot"),
        "rudder_te_z": q(r(rudder_te_z), "m", "measured", MEASURED + ": aft-most rudder vertex"),
        "rudder_y": [r(rudder["min"][1]), r(rudder["max"][1])],
        "le_sweep_deg": q(r(math.degrees(math.atan(fin_slope)), 3), "deg", "measured", MEASURED + ": fin leading-edge slope dz/dy"),
        "le_z_at_root": q(r(fin_0 + fin_slope * fin_root_y), "m", "derived", "fitted leading edge at root_y"),
        "root_chord": q(r(chord_at(fin_root_y)), "m", "derived", "rudder_te_z - fitted leading edge at root_y"),
        "tip_chord": q(r(chord_at(fin_top)), "m", "derived", "rudder_te_z - fitted leading edge at top_y"),
        "area_above_fuselage": q(r(fin_area), "m2", "derived", SCRIPT + ": trapezoid between root_y and top_y"),
        "rudder_chord_aft_of_hinge": q(r(r_rudder), "m", "measured", "distance from the hinge axis to the aft-most rudder vertex"),
        "rudder_area": q(r(r_rudder * (rudder["max"][1] - rudder["min"][1])), "m2", "derived", "rudder chord aft of hinge x rudder height"),
        "stations": [[r(s["y"], 3), r(s["le"][2]), r(s["te_fixed_z"]), r(s["te"][2])] for s in fin_clean],
        "stations_columns": ["y", "le_z", "fixed_te_z", "rudder_te_z"],
    }
    # ---- fuselage stations (airframe skin inside |x| <= 0.09 m) ----
    fus = []
    for row in mm["slices"]["fuselage"]["rows"]:
        g = row["groups"].get("airframe_skin")
        if not g:
            continue
        z = row["station"]
        fus.append([r(z, 3), r(max(abs(g["min"][0]), abs(g["max"][0]))), r(g["min"][1]), r(g["max"][1]),
                    bool(le_z - 0.005 <= z <= te_z + 0.005), bool(z >= tail["le_z_centreline"]["value"] - 0.01)])
    fuselage = {
        "stations": fus,
        "stations_columns": ["z", "half_width", "y_bottom", "y_top", "inside_wing_chord", "inside_tail"],
        "note": "airframe skin slices (glazing, lenses and grey brackets excluded) limited to |x| <= 0.09 m; stations inside the wing chord include the wing carry-through and stations inside the tail include the fin/stabilizer roots",
        "cowl_front_z": q(r(meshes["airframe"]["extents_root"]["min"][2]), "m", "measured", MEASURED + ": front of the airframe mesh (cowl)"),
        "aft_end_z": q(r(meshes["airframe"]["skin_extents_root"]["max"][2]), "m", "measured", MEASURED + ": aft-most airframe skin vertex (fin trailing edge ahead of the rudder)"),
    }
    # ---- articulations: pivots, axes, rest transforms, ranges and the app mapping ----
    articulations = {}
    for name, a in arts.items():
        p = pivots[name]
        rng = a["range"]
        articulations[name] = {
            "node": a["node"], "parent": p["parent"], "mesh_node": a["mesh_node"], "members": a["members_description"],
            "pivot": p["root_origin"], "axis": p["root_axis_x"],
            "rest_translation": p["origin"], "rest_basis": p["basis"], "rest_quaternion_xyzw": p["quaternion_xyzw"],
            "range_deg": None if rng.get("continuous") else [rng["min"], rng["max"]],
            "range_kind": "continuous" if rng.get("continuous") else rng["evidence"],
            "range_source": rng["source"],
            "positive": a["positive_direction"], "driven_by": a["driven_by"],
            "app_key": APP_KEY.get(name), "app_sign": APP_SIGN.get(name),
        }
        if "radius_m" in a:
            articulations[name]["radius"] = q(a["radius_m"]["value"], "m", "estimated", AUTHOR + ": " + a["radius_m"]["source"])
        if "coupling" in a:
            articulations[name]["coupling"] = a["coupling"]
    thrust_p = pivots["thrust_frame"]
    d = thrust_p["root_axis_x"]
    rotor = mm["radial"]["propeller_rotor"]
    thrust = {
        "node": "thrust_frame", "fixed": True, "parent": thrust_p["parent"],
        "origin": q(thrust_p["root_origin"], "m", "measured", AUTHOR + ": propeller hub, CAD x = -251.5 mm"),
        "direction": q(d, "1", "measured", MEASURED + ": thrust_frame local +X in the root frame"),
        "rest_basis": thrust_p["basis"], "rest_translation": thrust_p["origin"], "rest_quaternion_xyzw": thrust_p["quaternion_xyzw"],
        "downthrust_deg": q(r(math.degrees(math.asin(-d[1])), 3), "deg", "measured", MEASURED + " (author: 2 deg estimated, typical for the type)"),
        "right_thrust_deg": q(r(math.degrees(math.atan2(d[0], -d[2])), 3), "deg", "measured", MEASURED + " (author: 2 deg estimated, typical for the type)"),
        "spin_node": "propeller_spin", "spin_rest_translation": pivots["propeller_spin"]["origin"],
        "rotation_sense": md["thrust"]["rotation_sense"],
        "propeller_radius": q(rotor["radius"], "m", "measured", MEASURED + ": largest radial distance of a rotor vertex from the thrust axis (author estimate 0.1381 m; manual 11 in = 0.1397 m)"),
        "spinner_tip": q(rotor["axial_max_point_root"], "m", "measured", MEASURED + ": rotor vertex furthest along the thrust axis"),
        "rotor_axial_extent": [rotor["axial_min"], rotor["axial_max"]],
    }
    # ---- landing gear ----
    wl, wr, tw = pivots["wheel_left_axle"], pivots["wheel_right_axle"], pivots["tailwheel_axle"]
    r_main = mm["radial"]["wheel_left"]["radius"]
    r_tail = mm["radial"]["tailwheel"]["radius"]
    contacts = {
        "main_left": [wl["root_origin"][0], r(wl["root_origin"][1] - r_main), wl["root_origin"][2]],
        "main_right": [wr["root_origin"][0], r(wr["root_origin"][1] - r_main), wr["root_origin"][2]],
        "tail": [tw["root_origin"][0], r(tw["root_origin"][1] - r_tail), tw["root_origin"][2]],
    }
    ground = math.degrees(math.atan2(contacts["tail"][1] - contacts["main_left"][1], contacts["tail"][2] - contacts["main_left"][2]))
    landing_gear = {
        "type": md["landing_gear"]["type"],
        "wheel_centres": {"main_left": wl["root_origin"], "main_right": wr["root_origin"], "tail": tw["root_origin"]},
        "main_wheel_radius": q(r_main, "m", "measured", MEASURED + ": largest radial vertex distance of wheel_left about its axle (author estimate 0.058 m)"),
        "tail_wheel_radius": q(r_tail, "m", "measured", MEASURED + ": largest radial vertex distance of tailwheel about its axle (author estimate 0.014 m)"),
        "main_wheel_width": q(r(mm["radial"]["wheel_left"]["axial_max"] - mm["radial"]["wheel_left"]["axial_min"]), "m", "measured", MEASURED),
        "track": q(r(wr["root_origin"][0] - wl["root_origin"][0]), "m", "measured", "right minus left axle x (r1 CAD: 0.264 m)"),
        "contacts_neutral": contacts,
        "contacts_measured_bottom_y": {"main_left": meshes["wheel_left"]["extents_root"]["min"][1], "main_right": meshes["wheel_right"]["extents_root"]["min"][1], "tail": meshes["tailwheel"]["extents_root"]["min"][1]},
        "three_point_attitude_deg": q(r(ground, 3), "deg", "derived", "line through the main and tail contact points (r1 CAD: 9.8 deg)"),
        "suspension": {
            "pivots": {"left": pivots["gear_left_suspension"]["root_origin"], "right": pivots["gear_right_suspension"]["root_origin"]},
            "axes": {"left": pivots["gear_left_suspension"]["root_axis_x"], "right": pivots["gear_right_suspension"]["root_axis_x"]},
            "travel_deg": q(md["landing_gear"]["suspension_travel_deg"]["value"], "deg", "estimated", AUTHOR + ": " + md["landing_gear"]["suspension_travel_deg"]["source"]),
            "spring_stiffness": "unknown (author); the simulator's contact stiffness is a model input (TT-07)",
            "cable_endpoints": md["landing_gear"]["cable_endpoints_sim_m"],
        },
        "steering": {"pivot": pivots["tailwheel_steer"]["root_origin"], "axis": pivots["tailwheel_steer"]["root_axis_x"], "range_deg": [arts["tailwheel_steer"]["range"]["min"], arts["tailwheel_steer"]["range"]["max"]],
                     "positive": arts["tailwheel_steer"]["positive_direction"], "coupling": arts["tailwheel_steer"]["coupling"]},
        "brakes": "none",
    }
    # ---- control throws: manual millimetres to hinge angles at the assumed stations ----
    t = man["throws_mm"]
    def throws(d_mm, r_m):
        return q(r(throw_angle_deg(d_mm / 1000.0, r_m), 3), "deg", "derived", "2 asin(d / 2r) with d = %g mm, r = %.4f m" % (d_mm, r_m))
    controls = {
        "convention": man["throw_measurement"]["convention"],
        "stations": dict(man["throw_measurement"]["stations"], kind=man["throw_measurement"]["kind"], source=man["throw_measurement"]["source"]),
        "manual_mm": {k: v for k, v in t.items() if k in ("aileron", "elevator", "rudder", "flap")},
        "manual_source": t["source"],
        "aileron": {"r": q(r(r_aileron), "m", "measured", "hinge axis to the trailing edge at x = %.2f m" % aileron_station["x"]),
                    "high_deg": throws(t["aileron"]["high"], r_aileron), "low_deg": throws(t["aileron"]["low"], r_aileron),
                    "authored_range_deg": arts["aileron_right_hinge"]["range"]["max"], "differential_authored": arts["aileron_right_hinge"]["mixing"]["differential"]["value"],
                    "note": "constant chord: the angle does not change along the aileron; the manual gives symmetric up/down travel, the authored 0.7 differential is not applied"},
        "elevator": {"r": q(r(r_elevator_root), "m", "measured", "hinge axis to the trailing edge at x = %.2f m (root)" % tail_clean[0]["x"]),
                     "high_deg": throws(t["elevator"]["high"], r_elevator_root), "low_deg": throws(t["elevator"]["low"], r_elevator_root),
                     "high_deg_at_tip": throws(t["elevator"]["high"], r_elevator_tip), "authored_range_deg": arts["elevator_hinge"]["range"]["max"],
                     "note": "the tapered elevator gives a larger angle for the same millimetres at the tip; the root station is the assumption"},
        "rudder": {"r": q(r(r_rudder), "m", "measured", "hinge axis to the aft-most rudder vertex"),
                   "high_deg": throws(t["rudder"]["high"], r_rudder), "low_deg": throws(t["rudder"]["low"], r_rudder),
                   "authored_range_deg": arts["rudder_hinge"]["range"]["max"]},
        "flap": {"r": q(r(r_flap), "m", "measured", "hinge axis to the trailing edge at x = %.2f m" % flap_station["x"]),
                 "half_deg": throws(t["flap"]["half"], r_flap), "full_deg": throws(t["flap"]["full"], r_flap),
                 "authored_range_deg": [arts["flap_right_hinge"]["range"]["min"], arts["flap_right_hinge"]["range"]["max"]],
                 "elevator_mix": "16 % (half) / 30 % (full) down elevator per the manual: a radio setup value, not geometry"},
    }
    # ---- landmarks: author values and the imported-scene measurement side by side ----
    L = md["landmarks"]
    ex = mm["extremes"]
    measured_landmarks = {
        "left_wingtip": ex["minx"]["root"], "right_wingtip": ex["maxx"]["root"],
        "nose_spinner_tip": rotor["axial_max_point_root"], "tail_rudder_trailing_edge": ex["maxz"]["root"],
        "left_main_wheel_center": wl["root_origin"], "right_main_wheel_center": wr["root_origin"], "tailwheel_center": tw["root_origin"],
        "propeller_hub": thrust_p["root_origin"], "datum_D0": [0.0, 0.0, 0.0],
    }
    landmarks = {}
    for key, rec in L.items():
        mv = measured_landmarks[key]
        # Wingtips are defined by their outermost x only: several lens vertices share that x at different y/z.
        axes = [0] if key.endswith("wingtip") else [0, 1, 2]
        landmarks[key] = {"author": rec["sim_m"], "measured": mv, "compared_axes": axes,
                          "difference_mm": r(1000.0 * max(abs(rec["sim_m"][i] - mv[i]) for i in axes), 3),
                          "definition": rec.get("definition", "")}
    forward = ex["minz"]
    dimensions = {
        "span": wing["span"], "span_skin": wing["span_skin"],
        "length": q(r(ex["maxz"]["root"][2] - forward["root"][2]), "m", "measured", MEASURED + ": rudder trailing edge minus spinner tip along z (manual: 1.040 m)"),
        "height": q(r(mm["extents"]["all"]["max"][1] - mm["extents"]["all"]["min"][1]), "m", "measured", MEASURED + ": fin top minus main-wheel bottom at neutral suspension"),
        "bbox": {"min": mm["extents"]["all"]["min"], "max": mm["extents"]["all"]["max"]},
        "forward_extent_vertex": {"mesh": forward["mesh"], "surface": forward["surface"], "material": forward["material"], "root": forward["root"], "local": forward["local"],
                                  "finding": "the spinner tip of propeller_rotor (author landmark); the -0.2913 m extent reported by the TT-00-R1 probe came from the axis-aligned bounding box of the 2 deg/2 deg tilted rotor, not from a vertex"},
        "manual_span": man["span_m"], "manual_length": man["length_m"],
    }
    discrepancies = {
        "span_mm": q(r(1000.0 * (span_all - man["span_m"]["value"]), 3), "mm", "derived", "measured span (lenses included) minus the manual span"),
        "length_mm": q(r(1000.0 * (dimensions["length"]["value"] - man["length_m"]["value"]), 3), "mm", "derived", "measured length minus the manual length; the author attributes most of it to the nose/cowl ahead of the wing (r2 request); kept as delivered (decision D4)"),
        "area_vs_r1_cad_percent": q(r(100.0 * (wing["area"]["value"] / md["dimensions"]["model"]["wing_area_m2"]["value"] - 1.0), 3), "%", "derived", "measured planform area against the author's CAD 0.329 m2"),
        "propeller_radius_mm": q(r(1000.0 * (rotor["radius"] - md["dimensions"]["model"]["propeller_radius_m"]["value"]), 3), "mm", "derived", "measured blade-tip radius minus the author's estimate (0.1381 m); the manual propeller is 11 in = 0.1397 m radius"),
        "silhouette_overlay": "pending owner review: r1 side/top previews over the manual three-view (TT-02 evidence lists the files)",
    }
    # ---- r1 component stations: positions only, never a mass budget ----
    components = [{"name": c["name"], "mass_kg_r1_estimate": c["mass"]["value"], "z_model": r(c["x_cad_mm"] / 1000.0, 4)} for c in md["mass_properties"]["components"]]
    materials = {}
    for mesh in meshes.values():
        for s in mesh["surfaces"]:
            materials.setdefault(s["material"], {"albedo": s["albedo"], "emission": s["emission"], "transparency": s["transparency"], "class": s["material_class"]})
    scene = {
        "imported_root": mm["scene_root"]["name"], "aircraft_node": md["datum"]["root_node"].split(" ")[0],
        "mesh_nodes": {name: {"parent": m["parent"], "triangles": m["triangles"], "surfaces": len(m["surfaces"]), "materials": [s["material"] for s in m["surfaces"]], "local_identity": m["local_identity"]} for name, m in sorted(meshes.items())},
        "materials": dict(sorted(materials.items())),
        "counts": dict(mm["counts"], surfaces=mm["totals"]["surfaces"], triangles=mm["totals"]["triangles"]),
        "compressed_vertex_attributes": all(s["compressed_attributes"] for m in meshes.values() for s in m["surfaces"]),
        "godot": mm["godot"],
    }
    out = {
        "schema": "openrc-timber-geometry v1",
        "revision": revision,
        "catalog_id": CATALOG_ID,
        "source_alias": manifest["source_alias"],
        "status": "visual preview geometry of the author's r1 export; dimensions measured on the Godot-imported scene, ranges and installation angles estimated by the author; not calibrated, not flyable",
        "generator": SCRIPT,
        "inputs": {
            "manifest": "assets/aircraft/turbo-timber-evolution/source-manifest.json",
            "glb_sha256": manifest["key_files"]["glb"]["sha256"], "metadata_sha256": manifest["key_files"]["metadata"]["sha256"],
            "measurements": {"generator": mm["generator"], "godot": mm["godot"], "format": mm["format"]},
            "manual": "assets/aircraft/turbo-timber-evolution/manual.json",
            "hardware_revision": man["hardware_revision"],
        },
        "units": "m",
        "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "datum": {"id": "D0", "definition": md["datum"]["definition"], "position": [0.0, 0.0, 0.0],
                  "contract_frame": "aircraft contract positions [x_aft, y_right, z_up] = [z_model, x_model, y_model]; the root LE datum of the data file is D0, so AirplaneBuilder.datum() = (0, 0)"},
        "scene": scene,
        "dimensions": dimensions,
        "landmarks": landmarks,
        "articulations": articulations,
        "thrust": thrust,
        "wing": wing,
        "tail": tail,
        "fin": fin,
        "fuselage": fuselage,
        "landing_gear": landing_gear,
        "controls": controls,
        "manual": {k: man[k] for k in ("span_m", "length_m", "mass_empty_kg", "mass_flying_kg", "cg_aft_of_root_le_m", "cg_tolerance_m", "propeller", "motor", "battery", "servos")},
        "r1_component_stations": {"note": "author's class-typical component estimates (1.46 kg total) as stations only; the manual's 2.190 kg flying mass is the TT-07 target (TT-00-R1 section 2)", "components": components},
        "discrepancies": discrepancies,
        "evidence": {
            "pivots": {"kind": "measured", "source": MEASURED + "; agree with " + AUTHOR + " within 1e-6 m and 1e-6 in axis components"},
            "planform": {"kind": "measured", "source": MEASURED + ": plane slices of the white/red/black skin and the control-surface meshes"},
            "ranges": {"kind": "estimated", "source": AUTHOR + ": authored approximations, no manual available to the modeller"},
            "throws": {"kind": "derived", "source": "manual millimetres (manual.json) converted at the assumed stations (controls.stations)"},
            "installation_angles": {"kind": "estimated", "source": AUTHOR + ": 2 deg incidence, dihedral, down and right thrust typical for the type; the export carries them, so they are measured in the mesh but not validated against the aircraft"},
            "length": {"kind": "measured", "source": "76.6 mm longer than the manual; unresolved (TT-02 discrepancies)"},
        },
    }
    text = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != text:
            sys.exit("stale geometry.json: run build_geometry.py")
        print("Timber geometry.json is up to date (revision %s)" % revision)
    else:
        TARGET.write_text(text, encoding="utf-8")
        print("wrote %s (revision %s, span %.4f m, chord %.4f m, area %.4f m2, tail %.4f m2, fin %.4f m2)" % (
            TARGET.relative_to(ROOT), revision, span_all, chord, 2.0 * half_area, tail_area, fin_area))


if __name__ == "__main__":
    main()
