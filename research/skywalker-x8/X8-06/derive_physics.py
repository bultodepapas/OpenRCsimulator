#!/usr/bin/env python3
"""X8-06: generate the Skywalker X8 physics data (openrc-aircraft v2) from its sources.

Outputs, never hand-edited:
  app/data/aircraft/moonrunner_x99.json                 ideal 22.2 V bus (catalog battery mode "ideal")
  app/data/aircraft/battery/moonrunner_x99_6s_pack.json the same airframe on the finite 6S 5000 mAh pack_ecm (default)

Inputs, all frozen in the repository:
  * the r4 delivery (assets/source-deliveries/skywalker-x8-r4/, identity in assets/aircraft/skywalker-x8/
    source-manifest.json): the drawn model for the crash hull and landmarks, and the author's parametric planform
    (x8_skywalker_blender.py: leading/trailing-edge tables digitised from the official three-view, winglet, elevons,
    washout, dihedral) for strip stations, elevon coverage and winglet area;
  * the NTNU Skywalker X8 studies (docs/research/skywalker-x8/X8-01/README.md): Løw-Hansen et al. 2026 clean
    flight-identified coefficients (S05, CC BY 4.0), Gryte et al. 2018 wind tunnel (S01), bifilar inertia (S12);
  * UIUC APC 12x6E measured propeller tables (references/rc-propellers-12x6/uiuc, local copies with SHA256SUMS);
  * the generated 6S 5000 mAh LiPo class pack (app/data/batteries/packs/lipo-6s1p-5000-30c-class.json).

Frames: the LE frame is the delivery's datum D0 (symmetry plane, wing leading edge at the root rib, thrust-axis
height), [x_aft, y_right, z_up] in metres; the author's tables give x from the nose, so x_le = (x - 299.581 mm).

    python3 research/skywalker-x8/X8-06/derive_physics.py           # writes both files
    python3 research/skywalker-x8/X8-06/derive_physics.py --check   # fails if either is stale

Python standard library plus numpy (as GP-07). Not flight validated: see docs/X8-PLAN.md.
"""
import copy
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/f4u-corsair/F4U-04"))
import preflight_glb as glb  # noqa: E402  (stdlib glTF reader shared with F4U-04/05 and X8-02)

trapz = getattr(np, "trapezoid", None) or np.trapz  # numpy 2 renamed trapz

SCRIPT = "research/skywalker-x8/X8-06/derive_physics.py"
MANIFEST = ROOT / "assets/aircraft/skywalker-x8/source-manifest.json"
DELIVERY = ROOT / "assets/source-deliveries/skywalker-x8-r4/skywalker_x8/r4"
OUTPUT = ROOT / "app/data/aircraft/moonrunner_x99.json"
PACK_OUTPUT = ROOT / "app/data/aircraft/battery/moonrunner_x99_6s_pack.json"
PACK_ID = "lipo-6s1p-5000-30c-class"
PACK_FILE = ROOT / "app/data/batteries/packs" / (PACK_ID + ".json")
UIUC = ROOT / "references/rc-propellers-12x6/uiuc"
EVIDENCE = "docs/research/skywalker-x8/X8-01/README.md"

X_D0_MM = 299.581           # D0 behind the nose (delivery metadata datum_D0)
Z_D0_MM = 1.0               # D0 height in the author's master coordinates
N_STATIONS = 3              # Aero.WING_STATIONS_PER_SIDE

# --- Sources (ids from the X8-01 source table) ------------------------------------------------------------------
S05 = "Løw-Hansen et al. 2026, Aeronautical Journal doi:10.1017/aer.2026.10234, Tables 11-12 clean X8 (S05, CC BY 4.0)"
S01 = "Gryte et al. 2018, ICUAS doi:10.1109/ICUAS.2018.8453370, Table V wind tunnel (S01)"
S12 = "Gryte 2020 PhD thesis (NTNU) Table 6.1 bifilar-pendulum X8 inertia (S12)"
S11 = "Gryte 2015 MSc thesis (NTNU) Tables 6.2/H.1 measured X8 part masses (S11)"
AUTHOR = "r4 delivery source/scripts/x8_skywalker_blender.py (author's parametric master from the Skywalker three-view)"
LEDGER = AUTHOR + " COMPONENTS/FIXED_MASSES ledger"
RETAIL = "Skywalker X8 retail listings (S20-S24): 2120 mm, 80 dm2, flying weight 2.5-3.0 kg, max AUW 3.5 kg, CG 430-440 mm"

# NTNU coefficient reference: S 0.75 m2, b 2.10 m, c-bar 0.36 m (S05). The contract's chord is S/b.
S_REF = 0.75
B_REF = 2.10
C_REF = S_REF / B_REF
C_NTNU = 0.36
R_C = C_NTNU / C_REF        # pitch-moment and q-hat conversion to the S/b chord
# Moment reference (ARP): the NTNU flight CG is unpublished. 425 mm from the nose (Winter 2019's model CG) puts the
# flight-identified aerodynamic centre (-Cma/CLa = 7.5 % c-bar aft) at 452 mm, within 1 mm of the independent
# tunnel neutral point (~451 mm, S01 transferred). Estimated.
ARP_MM = 425.0
# Target balance: the middle of the manufacturer's 430-440 mm range (the author's ledger: 435 mm).
CG_TARGET_MM = 435.0


def q(value, unit, kind, source):
    if isinstance(value, float):
        value = round(value, 12) + 0.0
    elif isinstance(value, list):
        value = [round(v, 12) + 0.0 if isinstance(v, float) else v for v in value]
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def le_x(x_nose_mm):
    return (x_nose_mm - X_D0_MM) / 1000.0


# --- The author's planform (mm, x aft of the nose, s right of the centreline) ---------------------------------------
LE_S = [0, 10, 24, 40, 59, 77, 92, 102, 110, 116, 124, 130, 135, 142, 148, 155, 160, 166,
        174, 184, 195, 209, 228, 260, 294, 330, 390, 490, 590, 690, 790, 890, 935, 1000]
LE_X = [0, 0.45, 2.6, 7.3, 17, 32, 48, 63, 79, 94, 110, 125, 141, 156, 172, 187, 202, 218,
        233, 249, 264, 280, 295, 311, 327, 345.8, 374.5, 422.4, 470.2, 518.0, 565.8, 613.6, 635.2, 666.3]
TE_S = [0, 10, 26, 41, 58, 81, 115, 142, 190, 240, 290, 340, 390, 440, 490, 540, 590, 640,
        690, 740, 790, 840, 890, 935, 1000]
TE_X = [796, 794.5, 788, 773, 758, 742, 727, 718, 714, 713.5, 714.6, 716.1, 719.8, 724.7,
        731.0, 739.3, 747.0, 755.3, 763.1, 771.8, 779.3, 788.8, 797.5, 806, 818]
PLAN = dict(s_joint=236.0, s_tip=935.0, z0=8.0, dihedral=1.5, washout=-2.5, wl_radius=45.0, wl_cant=28.0,
            wl_len=180.0, elev_s0=242.0, elev_s1=878.0, elev_c0=70.0, elev_c1=58.0, gap=2.0, rib_w=3.0)


def edge_x(table_s, table_x, s_mm):
    return float(np.interp(s_mm, table_s, table_x))


def planform_check():
    """Projected area (m2) of the author's planform (both sides), the delivery's 0.742 m2 witness."""
    s = np.linspace(0.0, 1000.0, 20001)
    chord = np.interp(s, TE_S, TE_X) - np.interp(s, LE_S, LE_X)
    return 2.0 * float(trapz(chord, s)) * 1e-6


def winglet():
    """Projected side area (m2) of one winglet and its area centroid (x_le, z_le), from the author's formulas."""
    td = math.tan(math.radians(PLAN["dihedral"]))
    s0, ramp = PLAN["s_joint"] + PLAN["rib_w"] / 2.0, 100.0
    d = PLAN["s_tip"] - s0
    z_tip = PLAN["z0"] + td * (d - ramp / 2.0)
    pht, phw, r = math.atan(td), math.radians(90.0 - PLAN["wl_cant"]), PLAN["wl_radius"]
    cz = z_tip + r * math.cos(pht)
    end_z = cz - r * math.cos(phw)
    h_top = end_z + PLAN["wl_len"] * math.sin(phw) - z_tip
    h = np.linspace(0.0, h_top, 4001)
    hr = np.clip(h / h_top, 0.0, 1.0)
    le = 969.0 - 299.0 * (1.0 - hr ** 1.6) ** (1.0 / 1.6)
    te = 905.0 + (980.0 - 905.0) * hr
    chord = te - le
    area = float(trapz(chord, h))
    x_qc = float(trapz(chord * (le + 0.25 * chord), h)) / area
    z_c = float(trapz(chord * h, h)) / area
    return area * 1e-6, le_x(x_qc), (z_tip + z_c - Z_D0_MM) / 1000.0, h_top / 1000.0


# --- Strip geometry, replicated from AircraftData.station_ys/station_edges (tapered reference planform) -----------------
def station_edges(span, chords):
    h = span / 2.0
    cr, slope = chords[0], (chords[1] - chords[0]) / h
    total = cr * h + slope * h * h / 2.0
    right = [0.0]
    for k in range(N_STATIONS):
        target = total * (k + 1) / N_STATIONS
        right.append(h if k == N_STATIONS - 1 else (-cr + math.sqrt(cr * cr + 2.0 * slope * target)) / slope)
    return right


def station_centres(span, chords):
    h = span / 2.0
    cr, slope = chords[0], (chords[1] - chords[0]) / h
    area = lambda y: cr * y + slope * y * y / 2.0
    moment = lambda y: cr * y * y / 2.0 + slope * y ** 3 / 3.0
    edges = station_edges(span, chords)
    return [(moment(edges[k + 1]) - moment(edges[k])) / (area(edges[k + 1]) - area(edges[k])) for k in range(N_STATIONS)]


# --- Drawn model: world vertices per mesh node, LE frame ---------------------------------------------------------------
def drawn_parts():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    path = DELIVERY / manifest["key_files"]["glb"]["path"]
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != manifest["key_files"]["glb"]["sha256"]:
        raise SystemExit("X8-06: the delivery GLB differs from its frozen identity")
    gltf, binary = glb.read_glb(path)
    nodes = gltf["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    parts = {}
    for i, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        matrix, j = glb.local_matrix(node), i
        while j in parent:
            j = parent[j]
            matrix = glb.multiply(glb.local_matrix(nodes[j]), matrix)
        pts = []
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            for v in glb.accessor_values(gltf, binary, primitive["attributes"]["POSITION"]):
                g = [sum(matrix[r][c] * v[c] for c in range(3)) + matrix[r][3] for r in range(3)]
                pts.append((g[2], g[0], g[1]))  # Godot (x right, y up, z aft) -> LE (x aft, y right, z up)
        parts[node["name"]] = np.asarray(pts, float)
    return parts, manifest


# --- Crash hull (GP-07 method on the drawn model) ------------------------------------------------------------------------
# id, label, part, direction (LE frame), mirrored. Left/right features mirror y.
HULL_FEATURES = [
    ("probe_nose", "nose", "fuselage_core", (-1, 0, 0), False),
    ("probe_nose_{s}", "nose", "fuselage_core", (-1, 0.7, 0.3), True),
    ("probe_nose_{s}_low", "nose", "fuselage_core", (-1, 0.7, -0.6), True),
    ("probe_canopy_front", "canopy", "fuselage_core", (-0.6, 0, 1), False),
    ("probe_canopy", "canopy", "canopy_hatch", (0, 0, 1), False),
    ("probe_belly_front", "belly", "fuselage_core", (-0.4, 0, -1), False),
    ("probe_belly", "belly", "fuselage_core", (0, 0, -1), False),
    ("probe_engine", "engine", "motor_mount", (0.4, 0, -1), False),
    ("probe_tail", "tail_end", "fuselage_core", (1, 0, -0.2), False),
    ("probe_belly_aft", "belly", "fuselage_core", (0.25, 0, -1), False),
    ("probe_wing_{s}_root_le", "{s}_wing_root", "wing_{s}_fixed", (-1, 0.15, -0.3), True),
    ("probe_wing_{s}_mid_le", "{s}_wing_root", "wing_{s}_fixed", (-1, 0.45, -0.3), True),
    ("probe_wing_{s}_bottom", "{s}_wing_root", "wing_{s}_fixed", (0, 0.02, -1), True),
    ("probe_elevon_{s}_te", "{s}_wing_root", "elevon_{s}", (1, 0.2, -0.3), True),
    ("probe_winglet_{s}_top", "{s}_wing_tip", "wing_{s}_fixed", (0.2, 0.5, 1), True),
    ("probe_winglet_{s}_outer", "{s}_wing_tip", "wing_{s}_fixed", (-0.3, 1, 0.5), True),
    ("probe_winglet_{s}_knuckle", "{s}_wing_tip", "wing_{s}_fixed", (0.2, 1, -0.4), True),
    ("probe_wing_{s}_tip_le", "{s}_wing_tip", "wing_{s}_fixed", (-0.3, 1, -1.2), True),
    ("probe_wing_{s}_tip_te", "{s}_wing_tip", "wing_{s}_fixed", (1, 0.6, -1), True),
]
HULL_EXCLUDED = ("propeller_rotor",)  # the spinning disc is the E3d2 strike test, not a contact force
MIN_SPACING_M = 0.02
HULL_TOLERANCE_M = 0.015
DIRECTIONS = 6000


def fibonacci_sphere(n):
    i = np.arange(n) + 0.5
    phi = np.arccos(1.0 - 2.0 * i / n)
    theta = math.pi * (1.0 + 5.0 ** 0.5) * i
    return np.stack([np.cos(theta) * np.sin(phi), np.sin(theta) * np.sin(phi), np.cos(phi)], axis=1)


def hull(parts):
    feats = []
    for fid, label, part, direction, mirrored in HULL_FEATURES:
        for side, sign in ([("left", -1.0), ("right", 1.0)] if mirrored else [("", 1.0)]):
            pts = parts[part.format(s=side)]
            u = np.asarray((direction[0], sign * direction[1], direction[2]), float)
            p = pts[int(np.argmax(pts @ (u / np.linalg.norm(u))))]
            point = [round(float(v), 4) + 0.0 for v in p]
            if any(np.linalg.norm(np.subtract(f["point"], point)) < MIN_SPACING_M for f in feats):
                continue
            feats.append({"id": fid.format(s=side), "label": label.format(s=side), "point": point})
    dirs = fibonacci_sphere(DIRECTIONS)
    names = [k for k in parts if k not in HULL_EXCLUDED]
    drawn = np.concatenate([parts[k] for k in names])
    owner = np.concatenate([[k] * len(parts[k]) for k in names])
    projection = drawn @ dirs.T
    drawn_max = projection.max(axis=0)
    added = 0
    while True:
        hull_max = (np.asarray([f["point"] for f in feats]) @ dirs.T).max(axis=0)
        gaps = drawn_max - hull_max
        gap = float(gaps.max())
        if gap <= HULL_TOLERANCE_M:
            return feats, gap
        if added >= 12:
            raise SystemExit("X8-06: the drawn X8 still sinks %.1f mm through its hull after %d fill points" % (1000 * gap, added))
        # Greedy fill (GP-07a): the drawn point that the worst attitude touches first, mirrored, named by its part.
        worst = int(np.argmax(gaps))
        index = int(np.argmax(projection[:, worst]))
        point = drawn[index]
        for sign in ([1.0] if abs(point[1]) < MIN_SPACING_M else [1.0, -1.0]):
            mirrored = [round(float(point[0]), 4) + 0.0, round(float(sign * point[1]), 4) + 0.0, round(float(point[2]), 4) + 0.0]
            side = "" if abs(point[1]) < MIN_SPACING_M else ("right" if mirrored[1] > 0 else "left")
            label = _hull_label(str(owner[index]), mirrored)
            region = {"nose": "nose_{s}", "belly": "belly_{s}", "canopy": "canopy_{s}",
                      "engine": "engine_{s}", "tail_end": "tail_{s}"}.get(label, "wing_{s}")
            if label.endswith("_wing_tip") and mirrored[2] > 0.08:
                region = "winglet_{s}"
            feats.append({"id": "probe_%s_fill_%d" % (region.format(s=side).rstrip("_"), added + 1),
                          "label": label, "point": mirrored})
        added += 1


def _hull_label(part, point):
    """Crash-presentation name (CR-01d vocabulary) of a fill point from its drawn part and position."""
    side = "right" if point[1] > 0 else "left"
    if part.startswith("wing_") or part.startswith("elevon_"):
        # Wing-tip names need |y| >= 0.45 b (test_crash_hull_labels.gd). The winglets belong to the wing sections, so a
        # winglet strike names its wing tip (the crash presentation then releases that wing, not a missing fin).
        return "%s_wing_tip" % side if abs(point[1]) >= 0.45 * B_REF else "%s_wing_root" % side
    if part == "motor_mount":
        return "engine"
    if part == "canopy_hatch":
        return "canopy"
    if point[0] > 0.45:
        return "tail_end"
    if point[0] < -0.2:
        return "nose"
    return "canopy" if point[2] > 0.03 else "belly"


# --- Mass inventory --------------------------------------------------------------------------------------------------
def inventory(pack, cg_target_x):
    """Measured airframe parts (S11), the author's equipment ledger and the pack; the battery slides on its tray
    (the author's 175.5-338.5 mm range) to the target CG, as an X8 is balanced."""
    est = lambda value, unit, source: q(value, unit, "estimated", source)
    s = np.linspace(PLAN["s_joint"] + PLAN["rib_w"] / 2.0, PLAN["s_tip"], 2001)
    chord = np.interp(s, TE_S, TE_X) - np.interp(s, LE_S, LE_X)
    mid = np.interp(s, LE_S, LE_X) + 0.42 * chord
    wing_x = le_x(float(trapz(chord * mid, s) / trapz(chord, s)))
    wing_y = float(trapz(chord * s, s) / trapz(chord, s)) / 1000.0
    td = math.tan(math.radians(PLAN["dihedral"]))
    wing_z = (PLAN["z0"] + td * (wing_y * 1000.0 - PLAN["s_joint"]) + 18.0 - Z_D0_MM) / 1000.0  # winglet lifts it
    s_body = np.linspace(0.0, PLAN["s_joint"], 1001)
    chord_body = np.interp(s_body, TE_S, TE_X) - np.interp(s_body, LE_S, LE_X)
    mid_body = np.interp(s_body, LE_S, LE_X) + 0.45 * chord_body
    body_x = le_x(float(trapz(chord_body * mid_body, s_body) / trapz(chord_body, s_body)))
    wing_mass = 0.459
    rows = [
        ("wing_left", "left wing panel, winglet and elevon (EPO)", wing_mass, [wing_x, -wing_y, wing_z],
         [0.27, 0.70, 0.04], "measured", S11 + ": left 464 g / right 454 g incl. winglet, mean 459 g; centroid of the author's outer-panel planform"),
        ("wing_right", "right wing panel, winglet and elevon (EPO)", wing_mass, [wing_x, wing_y, wing_z],
         [0.27, 0.70, 0.04], "measured", S11 + ": mean of both wings; mirrored"),
        ("body_main", "centre body, hatch and root ribs (painted EPO)", 0.439, [body_x, 0.0, 0.012],
         [0.70, 0.47, 0.10], "measured", S11 + ": painted body 439 g; centroid of the author's centre-body planform"),
        ("spars_main", "carbon wing spars and joiners", 0.040, [le_x(470.0), 0.0, 0.006],
         [0.03, 1.30, 0.012], "estimated", "two carbon tubes about 1.3 m at ~15 g/m plus joiners; not weighed"),
        ("motor_main", "520 Kv outrunner (3530/4250 class)", 0.190, [le_x(818.0), 0.0, 0.0],
         [0.045, 0.042, 0.042], "estimated", LEDGER + ": 190 g at 818 mm (motor 4250 500 Kv class)"),
        ("propeller_main", "APC 12x6E pusher propeller and adapter", 0.030, [le_x(846.0), 0.0, 0.0],
         [0.010, 0.30, 0.025], "estimated", LEDGER + ": 12 in propeller and adapter 30 g at 846 mm"),
        ("motor_mount", "motor mount plate", 0.020, [le_x(790.0), 0.0, 0.0],
         [0.006, 0.05, 0.05], "estimated", "plywood/plastic pusher mount; not weighed"),
        ("esc_main", "60 A ESC", 0.060, [le_x(662.0), 0.0, -0.020],
         [0.070, 0.030, 0.015], "estimated", LEDGER + ": ESC 60 A, 60 g at 662 mm"),
        ("flight_controller", "autopilot / flight controller", 0.030, [le_x(455.0), 0.0, -0.025],
         [0.052, 0.036, 0.015], "estimated", LEDGER + ": 30 g at 455 mm"),
        ("receiver_telemetry", "receiver and telemetry radio", 0.018, [le_x(420.0), 0.0, -0.025],
         [0.040, 0.022, 0.010], "estimated", LEDGER + ": 18 g at 420 mm; its 55 mm side offset is dropped for a symmetric CG (fleet convention, 0.3 mm)"),
        ("gps_compass", "GPS and compass", 0.030, [le_x(640.0), 0.0, 0.040],
         [0.028, 0.028, 0.010], "estimated", LEDGER + ": 30 g at 640 mm under the top skin"),
        ("fpv_camera", "FPV camera and video transmitter", 0.030, [le_x(52.0), 0.0, 0.005],
         [0.022, 0.022, 0.024], "estimated", LEDGER + ": 30 g at 52 mm"),
        ("mapping_camera", "mapping camera", 0.240, [le_x(539.0), 0.0, -0.022],
         [0.102, 0.058, 0.041], "estimated", LEDGER + ": 240 g at 539 mm above the ventral doors"),
        ("parachute_pack", "recovery parachute pack", 0.150, [le_x(370.0), 0.0, 0.010],
         [0.088, 0.080, 0.055], "estimated", LEDGER + ": 150 g at 370 mm under the hatch"),
        ("servo_elevon_left", "left elevon servo (17 g digital)", 0.017, [le_x(558.0), -0.515, 0.012],
         [0.023, 0.012, 0.024], "estimated", LEDGER + ": 17 g ES3054-class servo at 515 mm span, servo bay 558 mm"),
        ("servo_elevon_right", "right elevon servo (17 g digital)", 0.017, [le_x(558.0), 0.515, 0.012],
         [0.023, 0.012, 0.024], "estimated", LEDGER + ": mirrored"),
        ("wiring_main", "wiring, connectors and magnets", 0.060, [le_x(420.0), 0.0, -0.010],
         [0.30, 0.10, 0.03], "estimated", LEDGER + ": 60 g at 420 mm"),
    ]
    battery_mass = float(pack["mass_kg"]["value"])
    battery_box = [float(v) for v in pack["dimensions_m"]["value"]]
    total = sum(r[2] for r in rows) + battery_mass
    moment = sum(r[2] * r[3][0] for r in rows)
    battery_x = (cg_target_x * total - moment) / battery_mass
    lo, hi = le_x(175.5), le_x(338.5)
    if battery_x > hi:
        raise SystemExit("X8-06: the battery cannot reach the target CG on its tray (%.1f mm)" % (battery_x * 1000 + X_D0_MM))
    if battery_x < lo:
        # The measured wings sit aft of the CG: with the pack at the front of its tray the build still needs nose weight,
        # as X8 builders report. Lead in the nose, at the FPV camera's station, closes the balance.
        battery_x = lo
        nose_x = le_x(80.0)
        ballast = (cg_target_x * (total) - moment - battery_mass * battery_x) / (nose_x - cg_target_x)
        rows.append(("nose_ballast", "nose ballast (lead) to the manual CG", ballast, [nose_x, 0.0, -0.005],
                     [0.02, 0.03, 0.01], "derived", "balance: with the pack at the front of its tray (175.5 mm) the measured "
                     "airframe needs %.0f g of lead 80 mm from the nose for the %.0f mm CG; owner builds may move or omit it"
                     % (1000 * ballast, CG_TARGET_MM)))
    rows.append(("battery_main", pack["display_name"], battery_mass, [battery_x, 0.0, -0.022], battery_box, "derived",
                 "%s mass and box; centre %.1f mm from the nose on the author's tray (175.5-338.5 mm) for the %.0f mm target CG"
                 % (PACK_ID, battery_x * 1000 + X_D0_MM, CG_TARGET_MM)))
    items = []
    for item_id, name, mass, pos, size, kind, source in rows:
        item = {"id": item_id, "name": name, "mass": q(mass, "kg", "measured" if kind == "measured" else ("derived" if kind == "derived" else "estimated"), source),
                "position": q([float(v) for v in pos], "m", "derived" if kind != "estimated" else "estimated", source + "; D0 structural frame"),
                "size": q([float(v) for v in size], "m", "estimated", source + "; aligned box inertia envelope")}
        if item_id == "battery_main":
            item["energy_source"] = "lipo"
        items.append(item)
    return items


def inertia(items):
    """About the inventory CG, body FRD, point masses with aligned boxes ([Jxx, Jyy, Jzz, Jxy, Jxz, Jyz])."""
    m = np.array([i["mass"]["value"] for i in items])
    p = np.array([i["position"]["value"] for i in items])
    s = np.array([i["size"]["value"] for i in items])
    cg = (m[:, None] * p).sum(axis=0) / m.sum()
    r = np.stack([-(p[:, 0] - cg[0]), p[:, 1] - cg[1], -(p[:, 2] - cg[2])], axis=1)
    box = m[:, None] / 12.0 * np.stack([s[:, 1] ** 2 + s[:, 2] ** 2, s[:, 0] ** 2 + s[:, 2] ** 2, s[:, 0] ** 2 + s[:, 1] ** 2], axis=1)
    jxx = float((m * (r[:, 1] ** 2 + r[:, 2] ** 2)).sum() + box[:, 0].sum())
    jyy = float((m * (r[:, 0] ** 2 + r[:, 2] ** 2)).sum() + box[:, 1].sum())
    jzz = float((m * (r[:, 0] ** 2 + r[:, 1] ** 2)).sum() + box[:, 2].sum())
    jxz = float(-(m * r[:, 0] * r[:, 2]).sum())
    return cg, float(m.sum()), [jxx, jyy, jzz, 0.0, jxz, 0.0]


# --- Propeller: UIUC APC 12x6E (Volume 4, measured) --------------------------------------------------------------------
# The UIUC files live in the ignored references/ folder, so the measured rows are carried here (as the aircraft JSON
# carries them) and checked against the local copies when present. Columns: static [rpm, CT, CP]; tunnel [J, CT, CP].
UIUC_FILES = {
    "apce_12x6_static_0629od.txt": "e392a17a430ad2796172f21ee0106152375b298636584b33ba23f836a3a6c96c",
    "apce_12x6_0635od_6044.txt": "7e969b7089fc74ac373cefde1fd7c1297938b79457dd1efb6e0876d9fbde6d85",
}
STATIC_TOP = [7546.667, 0.105460, 0.033643]  # the highest measured static rpm, nearest the X8's operating rpm
TUNNEL_6044 = [
    [0.333913, 0.071653, 0.034510], [0.359762, 0.065770, 0.033095], [0.373361, 0.061892, 0.031991],
    [0.392495, 0.056601, 0.030368], [0.413002, 0.051841, 0.028904], [0.433129, 0.046902, 0.027258],
    [0.452355, 0.042453, 0.025746], [0.473059, 0.037347, 0.023903], [0.494232, 0.032514, 0.022177],
    [0.515098, 0.027579, 0.020350], [0.533862, 0.023112, 0.018630], [0.554337, 0.018253, 0.016692],
    [0.573423, 0.013719, 0.014801], [0.592478, 0.009348, 0.012900], [0.614674, 0.004821, 0.010874],
    [0.633612, -0.000128, 0.008654], [0.653931, -0.005268, 0.006382],
]


def uiuc_rows(name, columns):
    rows = []
    for line in (UIUC / name).read_text().splitlines()[1:]:
        values = [float(x) for x in line.split()]
        rows.append([values[c] for c in columns])
    return rows


def propeller_tables():
    if all((UIUC / f).exists() for f in UIUC_FILES):
        for name, digest in UIUC_FILES.items():
            if hashlib.sha256((UIUC / name).read_bytes()).hexdigest() != digest:
                raise SystemExit("X8-06: local UIUC copy %s differs from the pinned bytes" % name)
        static = uiuc_rows("apce_12x6_static_0629od.txt", (0, 1, 2))
        tunnel = [r for i, r in enumerate(uiuc_rows("apce_12x6_0635od_6044.txt", (0, 1, 2)))
                  if i == 0 or r[0] > uiuc_rows("apce_12x6_0635od_6044.txt", (0, 1, 2))[i - 1][0]]
        if static[-1] != STATIC_TOP or tunnel != TUNNEL_6044:
            raise SystemExit("X8-06: carried UIUC rows differ from the local copies")
    ct = [[0.0, STATIC_TOP[1]]] + [[j, c] for j, c, _ in TUNNEL_6044]
    cp = [[0.0, STATIC_TOP[2]]] + [[j, p] for j, _, p in TUNNEL_6044]
    source = ("UIUC propeller database Vol. 4 APC 12x6E (thin electric), measured: static %s (sha256 %s…, %d rpm row) and "
              "tunnel %s at 6044 rpm (sha256 %s…, repeated end rows dropped); local copy references/rc-propellers-12x6/uiuc. "
              "A pusher APC 12x6EP is the mirror image (same CT/CP); the X8 turns ~10,000 rpm (higher Reynolds number than "
              "the 6044 rpm run); J 0-%.3f bridged linearly" % ("apce_12x6_static_0629od.txt", UIUC_FILES["apce_12x6_static_0629od.txt"][:12],
              STATIC_TOP[0], "apce_12x6_0635od_6044.txt", UIUC_FILES["apce_12x6_0635od_6044.txt"][:12], TUNNEL_6044[0][0]))
    return ct, cp, source


# --- Aircraft ---------------------------------------------------------------------------------------------------------------
def build():
    pack_bytes = PACK_FILE.read_bytes()
    pack = json.loads(pack_bytes.decode("utf-8"))
    parts, manifest = drawn_parts()
    feats, hull_gap = hull(parts)
    area_plan = planform_check()
    wl_area, wl_x, wl_z, wl_h = winglet()

    tip_chord = 0.17
    root_chord = 2.0 * S_REF / B_REF - tip_chord
    centres = station_centres(B_REF, [root_chord, tip_chord])
    edges = station_edges(B_REF, [root_chord, tip_chord])
    station_x, coverage, twist = [], [], []
    e0, e1 = PLAN["elev_s0"] + PLAN["gap"], PLAN["elev_s1"]
    for k in range(N_STATIONS):
        s_mm = centres[k] * 1000.0
        le, te = edge_x(LE_S, LE_X, s_mm), edge_x(TE_S, TE_X, s_mm)
        station_x.append(le_x(le + 0.25 * (te - le)))
        a, b = edges[k] * 1000.0, edges[k + 1] * 1000.0
        coverage.append(max(0.0, min(b, e1) - max(a, e0)) / (b - a))
        frac = np.clip((s_mm - PLAN["s_joint"]) / (PLAN["s_tip"] - PLAN["s_joint"]), 0.0, 1.0)
        twist.append(math.radians(PLAN["washout"]) * float(frac))
    mean_twist = sum(twist) / N_STATIONS
    incidence = [t - mean_twist for t in twist]
    s_elev = np.linspace(e0, e1, 801)
    local = np.interp(s_elev, TE_S, TE_X) - np.interp(s_elev, LE_S, LE_X)
    elevon_chord = PLAN["elev_c0"] + (PLAN["elev_c1"] - PLAN["elev_c0"]) * (s_elev - e0) / (e1 - e0)
    chord_fraction = float(trapz(elevon_chord, s_elev) / trapz(local, s_elev))

    cg_target = le_x(CG_TARGET_MM)
    items = inventory(pack, cg_target)
    cg, mass, j = inertia(items)
    cg = [round(float(v), 9) + 0.0 for v in cg]
    arp = [le_x(ARP_MM), 0.0, (PLAN["z0"] - Z_D0_MM) / 1000.0]

    # Winglets as one centreline vertical element (both fins together; linear in sideslip and rates).
    fin_area = 2.0 * wl_area
    fin_arm = wl_x - arp[0]
    cnb, cyb, clb = 0.0198, -0.2700, -0.0644
    fin_slope = cnb / (fin_area / S_REF * fin_arm / B_REF)
    body_cy = cyb + fin_slope * fin_area / S_REF
    wing_body_cl = clb + fin_slope * fin_area / S_REF * (wl_z - arp[2]) / B_REF

    # Drag polar: CD = CD0 + k·CL², k from span efficiency, CD0 through NTNU's flight drag at its trim point.
    aspect = B_REF ** 2 / S_REF
    k_induced = 1.0 / (math.pi * 0.85 * aspect)
    cl_trim = 0.246
    cd_trim = 0.0411 - 0.0032 * cl_trim + 0.0373 * cl_trim ** 2
    cd0 = cd_trim - k_induced * cl_trim ** 2

    vs = math.sqrt(2.0 * mass * 9.80665 / (1.225 * S_REF * 1.05))
    start_speed = 1.6 * vs
    ct, cp, prop_source = propeller_tables()
    hub = [le_x(846.0), 0.0, 0.0]

    der = lambda value, unit, source: q(value, unit, "derived", SCRIPT + ": " + source)
    est = lambda value, unit, source: q(value, unit, "estimated", source)
    bor = lambda value, unit, source: q(value, unit, "borrowed", source)
    def b(value, unit, source):
        return bor(value, unit, source)

    coefficients = {
        "CL0": b(0.1523, "1", S05 + ": CL0"),
        "CLa": b(4.3993, "1/rad", S05 + ": CLα"),
        "CLq": der(0.444 * R_C, "1/rad", S05 + " CLq 0.444 (±31 %) × c̄ 0.36/(S/b) for q̂ on the S/b chord"),
        "CLde": b(0.5011, "1/rad", S05 + ": CLδe, δe = (δel+δer)/2, trailing edge down"),
        "CLda_each": der(0.0, "1/rad", "elevons: the symmetric part is δe (CLde); no separate aileron lift term"),
        "CD0": der(cd0, "1", "CD0 + k·CL² through " + S05 + " flight drag 0.0411 − 0.0032·CL + 0.0373·CL² at its trim CL 0.246 (L/D 5.8), k below"),
        "CL_minD": der(0.0, "1", "symmetric drag polar about CL 0 (fitted minimum-drag CL 0.043 is within the fit noise)"),
        "k_induced": der(k_induced, "1", "1/(π·e·AR), AR = b²/S = %.2f, span efficiency e 0.85 estimated (swept wing with winglets); the flight fit's 0.0373 is below the theoretical bound" % aspect),
        "CDda_each": est(0.006, "1/rad", S01 + " CDδe 0.0633/rad² linearised at ~11°, halved per elevon; estimated"),
        "CDdr": der(0.0, "1/rad", "no rudder"),
        "CDde": est(0.012, "1/rad", S01 + " CDδe 0.0633/rad² linearised at ~11°; estimated"),
        "CYb": b(cyb, "1/rad", S05 + ": CYβ (winglets + body; split below)"),
        "CYp": b(-0.1920, "1/rad", S05 + ": CYp"),
        "CYr": b(0.108, "1/rad", "Løw-Hansen et al. 2025 (S04) Table 8 CYr; the 2026 clean value 0.539 is five times XFLR5's 0.084 (S01) and 2024's 0.186, treated as an outlier"),
        "CYdr": der(0.0, "1/rad", "no rudder"),
        "Clb": b(clb, "1/rad", S05 + ": Clβ (winglets + wing-body sweep; split below)"),
        "Clp": b(-0.2124, "1/rad", S05 + ": Clp"),
        "Clr": b(0.1135, "1/rad", S05 + ": Clr"),
        "Clda_right": der(-0.0865 / 2.0, "1/rad", S05 + " Clδa 0.0865 with δa = (δel−δer)/2: per-elevon antisymmetric right term −Clδa/2"),
        "Clda_left": der(0.0865 / 2.0, "1/rad", S05 + " Clδa 0.0865: left term +Clδa/2"),
        "Cldr": der(0.0, "1/rad", "no rudder"),
        "Cm0": der(0.0067 * R_C, "1", S05 + " Cm0 0.0067 × c̄ 0.36/(S/b), about the ARP (estimated NTNU flight CG)"),
        "Cma": der(-0.3307 * R_C, "1/rad", S05 + " Cmα −0.3307 × c̄/(S/b)"),
        "Cmq": der(-0.8042 * R_C ** 2, "1/rad", S05 + " Cmq −0.8042 × (c̄/(S/b))²"),
        "Cmde": der(-0.2316 * R_C, "1/rad", S05 + " Cmδe −0.2316 × c̄/(S/b)"),
        "Cmda_each": der(0.0, "1/rad", "elevons: the symmetric part is δe (Cmde)"),
        "Cnb": b(cnb, "1/rad", S05 + ": Cnβ (the winglets carry it; no body yaw term)"),
        "Cnp": b(-0.0204, "1/rad", S05 + ": Cnp"),
        "Cnr": b(-0.1069, "1/rad", S05 + ": Cnr"),
        "Cnda_right": der(0.0043 / 2.0, "1/rad", S05 + " Cnδa −0.0043 with δa = (δel−δer)/2: right term −Cnδa/2"),
        "Cnda_left": der(-0.0043 / 2.0, "1/rad", S05 + " Cnδa −0.0043: left term +Cnδa/2"),
        "Cndr": der(0.0, "1/rad", "no rudder"),
    }
    station = "equal-area strips of the S/b-consistent trapezoid (root %.4f m, tip %.2f m), root → tip" % (root_chord, tip_chord)
    surfaces = {
        "wing_station_incidence": der(incidence, "rad", AUTHOR + " washout −2.5° linear from the root rib to the tip at the strips' centroids; zero mean (CL0 carries it)"),
        "body_cy_beta": der(body_cy, "1/rad", "CYβ minus the winglets' side force (the centre body and swept wing carry the rest)"),
        "body_crossflow_area": est(0.057, "m2", "Allen-Perkins crossflow η·c_d·S_side: centre-body side area 0.79 m × ~0.10 m (" + AUTHOR + "), c_d 1.2, η 0.6; estimated"),
        "wing_body_cl_beta": der(wing_body_cl, "1/rad", "Clβ minus the winglets' rolling term: the swept wing's dihedral effect"),
        "attached_limit": est(8.0, "deg", "fleet value (Ugly Stik, Turbo Lumber): local attached-flow/oracle boundary"),
        "tail_local_limit": est(12.0, "deg", "fleet value (Ugly Stik, Turbo Lumber): fin attached-flow limit"),
        "tail_stall_end": est(24.0, "deg", "fleet value (Ugly Stik, Turbo Lumber): fin flat-plate transition end"),
        "tail_CD0": est(0.012, "1", "fleet value (Ugly Stik, Turbo Lumber): fin profile drag, symmetric winglet section"),
        "tail_k": est(0.08, "1", "fleet value (Ugly Stik, Turbo Lumber): fin induced drag"),
        "tail_CD90": est(1.2, "1", "fleet value (Ugly Stik): flat-plate normal force of the winglets"),
        "vertical": {
            "area": der(fin_area, "m2", "both winglets' projected side areas from the author's winglet formulas (LE/TE, %.0f mm high, 28° cant)" % (1000 * wl_h)),
            "position": der([wl_x, 0.0, wl_z], "m", "winglets' area-weighted quarter-chord station and mid-height, one centreline element"),
            "lift_slope": der(fin_slope, "1/rad", "solved so the winglets carry " + S05 + " Cnβ 0.0198 at their arm (no body yaw term); low-aspect canted fins"),
            "control_effectiveness": der(0.0, "1", "no rudder: the X8's winglets are fixed"),
            "incidence": der(0.0, "rad", AUTHOR + ": winglets without toe"),
        },
        "tailless": {
            "station_x": der(station_x, "m", AUTHOR + " planform quarter chord at the " + station + "; the loader shifts all stations together to the oracle's neutral point"),
            "elevon_coverage": der(coverage, "1", AUTHOR + " elevons from %.0f to %.0f mm span over the %s" % (e0, e1, station)),
            "elevon_chord_fraction": der(chord_fraction, "1", AUTHOR + " elevon chord 70→58 mm over the local planform chord, span-averaged"),
        },
    }
    raw = {
        "format": "openrc-aircraft v2",
        "physical_identity_version": 1,
        "id": "moonrunner-x99",
        "description": "EPO flying wing inspired by the Skywalker X8 (2.12 m, elevons, winglets, electric pusher, no gear) in the r4 delivery's UAV build. NTNU flight-identified aerodynamics, measured part masses and inertia reference, estimated electric drive. Experimental; not flight validated.",
        "convention_id": "openrc-le-frd-v1",
        "capabilities": {"controls": "elevon", "gear": "locked_up", "propulsion_layout": "single_pusher",
                         "energy": "fixed_voltage", "damage": "tolerant_hull", "flaps": "not_simulated",
                         "airframe_layout": "tailless"},
        "frames": {"le_frame": "D0 (r4 delivery): [x_aft, y_right, z_up] = [Godot z, Godot x, Godot y], metres; root-rib leading edge at thrust-axis height",
                   "body": "FRD about inventory CG"},
        "reference": {
            "wing_area": b(S_REF, "m2", S05 + ": reference area (planform witness %.3f m² in the author's tables, retail 0.80 m²)" % area_plan),
            "wing_span": b(B_REF, "m", S05 + ": reference span (retail 2.12 m)"),
            "mean_chord": der(C_REF, "m", "S/b"),
            "aero_reference_point": est(arp, "m", "estimated NTNU flight CG: %.0f mm from the nose (Winter 2019 model CG) puts the flight-identified AC 27 mm aft, at the tunnel neutral point (~451 mm, S01); wing chord plane height" % ARP_MM),
            "planform": "tapered",
            "root_chord": der(root_chord, "m", "S/b-consistent trapezoid for the strip split: 2S/b − tip"),
            "tip_chord": der(tip_chord, "m", AUTHOR + " tip chord ~171 mm at 935 mm span; NTNU scan 177 mm at 1050 mm"),
        },
        "balance": {
            "plan_cg": der(cg, "m", "inventory CG: %.0f mm from the nose (manual 430-440 mm, mid-range); vertical from the inventory" % CG_TARGET_MM),
            "firewall": est([le_x(790.0), 0.0, 0.0], "m", "pusher motor mount plate, " + AUTHOR),
            "configuration": "x8-uav-mapping-6s-v1",
            "cg_tolerance": est(0.001, "m", "reference build tolerance (fleet value)"),
            "cg_range": {"forward": q(le_x(430.0), "m", "manual", RETAIL + " (forward limit)"),
                         "aft": q(le_x(440.0), "m", "manual", RETAIL + " (aft limit)")},
        },
        "inventory": items,
        "start": {"level_speed": der(start_speed, "m/s", "1.6 × clean 1-g stall (%.1f m/s) at %.2f kg, CL_max 1.05 (fleet practice, Turbo Lumber)" % (vs, mass))},
        "controls": {
            "surface_ids": {"elevon_left": "surface_elevon_left", "elevon_right": "surface_elevon_right"},
            "max_throw": {
                "aileron": est(23.26, "deg", AUTHOR + " radio mix: roll share 0.85 of the servo travel, 23.26° per elevon at full roll (r4 rig)"),
                "elevator": est(19.47, "deg", AUTHOR + " radio mix: pitch share 0.70, 19.47° at full pitch (r4 rig); NTNU flew ±19° (S05)"),
                "elevon": est(26.76, "deg", AUTHOR + " full servo travel −26.76/+26.85°; the smaller magnitude clips both directions"),
            },
            "servo_full_throw_time": est(0.075, "s", "17 g digital elevon servo (ES3054 class, ~0.10 s/60° at 4.8 V) turning 45° for full travel (" + AUTHOR + " servo_throw); estimated"),
            "rates": {"normal": {
                "aileron": est(1.0, "1", "full mixed throw on the normal rate; X8 manual unavailable (403)"),
                "elevator": est(1.0, "1", "full mixed throw on the normal rate; X8 manual unavailable (403)"),
                "aileron_expo": est(0.3, "1", "common flying-wing setup expo; not from an X8 manual"),
                "elevator_expo": est(0.3, "1", "common flying-wing setup expo; not from an X8 manual"),
            }},
        },
        "aero": {
            "source": "NTNU Skywalker X8 flight identification (S05) on the tailless strip law; see " + EVIDENCE,
            "conventions": {
                "alpha_beta": "rad",
                "rates": "p_hat = p·b/(2V), q_hat = q·c/(2V), r_hat = r·b/(2V)",
                "elevator": "per radian of the elevons' symmetric part (δel+δer)/2, positive = trailing edge DOWN (dCm/dElev < 0)",
                "aileron": "per radian of each elevon's antisymmetric part, positive = trailing edge DOWN; right and left listed separately",
                "rudder": "none: rudderless winglets, every rudder term is 0",
                "drag": "CD = CD0 + k·(CL - CL_minD)² + sum |dCD/dδ·δ|",
                "axes": "lift, drag, side force in wind axes; roll, pitch, yaw moments in body axes about the aero reference point",
            },
            "coefficients": coefficients,
            "reference_coefficients": {"CLadot": est(0.0, "1/rad", "not identified for the X8; reference only, no consumer")},
            "envelope": {
                "CL_max": est(1.05, "1", S01 + " lift linear to ~12°; CFD clean CLmax 1.1 at 18° (Winter 2019, S06)"),
                "CL_min": est(-0.70, "1", "reflexed thin section inverted; unmeasured"),
                "stall_blend_width": est(8.0, "deg", "attached-to-flat-plate width; unmeasured"),
                "CD90": est(1.2, "1", "low-aspect flat plate normal force (fleet value)"),
                "sideslip_blend": est([15, 25], "deg", S01 + " tunnel β ±15° linear; fleet blend end"),
            },
            "surfaces": surfaces,
        },
        "propulsion": {
            "kind": "electric_prop",
            "motor": {
                "kv_rpm_per_volt": q(520, "rpm/V", "manual", "Skywalker X8 PNP 3530 520 Kv motor (retail listing S21)"),
                "resistance_scope": "motor_winding_equivalent",
                "resistance_ohm": est(0.06, "ohm", "35-42 mm 500 Kv-class outrunner winding resistance (comparable catalogue motors 0.045-0.07 Ω); not measured"),
                "no_load_current_a": est(1.0, "A", "500 Kv-class outrunner no-load current near 10 V; not measured"),
                "no_load_context": {
                    "voltage_v": est(22.2, "V", "6S nominal"),
                    "rpm": der((22.2 - 0.06 * 1.0) * 520, "rpm", "Kv·(V − R·I0)"),
                    "temperature_c": est(25.0, "°C", "context only; no thermal model"),
                },
            },
            "battery": {"kind": "fixed_voltage", "voltage_v": est(22.2, "V", "6S nominal fixed bus (ideal-bus configuration); no sag or depletion")},
            "esc": {"kind": "ideal_motoring", "command_mapping": "identity"},
            "propeller": {
                "diameter": q(0.3048, "m", "manual", "APC 12x6E(P) nominal 12 in (Skywalker kit recommendation 12x6E, S20/S22); drawn propeller 0.3049 m"),
                "ct_table": q(ct, "1", "borrowed", prop_source),
                "cp_table": q(cp, "1", "borrowed", prop_source),
                "rotating_inertia": est(2.2e-4, "kg·m2", "APC 12x6E (~32 g, ~1.5e-4 kg·m²) plus adapter and outrunner bell; not measured (NTNU 14x8: 3.46e-4, S03)"),
                "thrust_angles": q([0.0, 0.0], "deg", "measured", AUTHOR + ": motor axis along the body axis, no down or side thrust"),
                "thrust_line_offset": der([hub[0] - cg[0], hub[1] - cg[1], hub[2] - cg[2]], "m", "delivery propeller hub (846 mm from the nose, thrust-axis height) minus inventory CG; pusher aft of the CG"),
            },
            "id": "propulsion_main",
        },
        "crash_hull": q([f["point"] for f in feats], "m", "derived",
                        SCRIPT + ": the drawn r4 model's extreme points per feature (GP-07 method); worst sink of the drawn airframe through the hull %.1f mm over %d attitudes, propeller excluded (strike test); features: %s"
                        % (1000 * hull_gap, DIRECTIONS, ", ".join(f["id"] for f in feats))),
        "crash_hull_ids": [f["id"] for f in feats],
        "crash_hull_components": [f["label"] for f in feats],
        "crash_tolerance": {
            "terminal_specific_energy": est(12.5, "J/kg", "EPO foam airframe: five times the shared 2.5 J/kg (about 5 m/s normal impact instead of 2.2 m/s); EPO crush ~80 kJ/m³ (0.16 MPa to ~50 % strain, Xometry EPO sheet S30) absorbs a 3 kg X8's 37 J in ~0.5 L of nose foam; owner drop tests pending"),
            "crash_depth": est(0.12, "m", "a foam belly can bury ~12 cm in turf before structure fails; shared 0.08 m for balsa/glow; estimated"),
            "presentation_durability": est(4.0, "1", "crash presentation's specific-energy divisor for EPO against balsa/ply (CR-08b); estimated"),
        },
        "plausibility": {
            "mass_range": q([2.5, 3.5], "kg", "manual", RETAIL),
            "inertia_reference": der([v / ((3.364 / 1.959) * (2.10 / 1.27) ** 2) for v in (0.335, 0.140, 0.40)], "kg·m2",
                                     S12 + " measured 0.335/0.140/0.40 kg·m² at 3.364 kg, 2.10 m, divided by the loader's UltraStick mass·span² scale so the warning compares this inventory with the measured X8"),
        },
    }
    return raw, pack, pack_bytes, {"mass": mass, "inertia": j, "cg": cg, "station_x": station_x, "coverage": coverage,
                                   "chord_fraction": chord_fraction, "fin": [fin_area, fin_slope, wl_x, wl_z], "hull_gap": hull_gap,
                                   "planform_area": area_plan, "start_speed": start_speed}


PACK_SOURCE = SCRIPT + " pack variant"


def pack_variant(raw, pack, pack_bytes):
    variant = copy.deepcopy(raw)
    battery_item = next(i for i in variant["inventory"] if i["id"] == "battery_main")
    if pack["mass_kg"]["value"] != battery_item["mass"]["value"]:
        raise SystemExit("X8-06: pack mass must equal the battery_main inventory mass")
    variant["description"] = raw["description"].replace("estimated electric drive", "estimated electric drive on the finite 6S 5000 mAh class pack (pack_ecm)")
    variant["capabilities"]["energy"] = "pack_ecm"
    est = lambda value, unit, source: q(value, unit, "estimated", PACK_SOURCE + ": " + source)
    der = lambda value, unit, source: q(value, unit, "derived", PACK_SOURCE + ": " + source)
    variant["propulsion"]["battery"] = {
        "kind": "pack_ecm",
        "pack": {"id": PACK_ID, "sha256": hashlib.sha256(pack_bytes).hexdigest()},
        "mount_inventory_id": "battery_main",
        "initial_soc": est(1.0, "1", "freshly charged pack at rest; the session may override it"),
        "auxiliary_current_a": est(0.6, "A", "autopilot, GPS, telemetry, FPV camera/transmitter and two servos, about 10 W through an assumed 80 % BEC, referred to a 22 V pack; not measured"),
        "cooling_airflow_fraction": est(0.1, "1", "enclosed foam bay under the hatch; ram air past the pack assumed 10 % of airspeed (Turbo Lumber value)"),
        "weak_cell": {
            "capacity_factor": der(1.0, "1", "new balanced pack"),
            "resistance_factor": der(1.0, "1", "new balanced pack"),
            "soc_offset": der(0.0, "1", "balanced charge"),
        },
    }
    variant["propulsion"]["esc"] = {
        "kind": "ideal_motoring", "command_mapping": "identity",
        "low_voltage_cutoff": {
            "mode": "soft", "cell_detection": "auto",
            "detection_max_cell_v": est(4.3, "V", "Betaflight-style 4.30 V/cell auto-detection maximum (BAT-00 F7, fleet value)"),
            "cutoff_per_cell_v": est(3.2, "V", "common 60 A ESC default 3.2 V/cell; installed setting unknown"),
            "soft_limit": est(0.5, "1", "soft cutoff to 50 % output (fleet value)"),
            "soft_ramp_s": est(3.0, "s", "soft cutoff ramp (fleet value)"),
            "debounce_s": est(0.5, "s", "brief punch-out sag does not trip (fleet value)"),
            "recovery": "throttle_reset",
            "reset_throttle_max": der(0.05, "1", "app/input/rc_input.gd ARM_THROTTLE 0.05: the same idle-stick threshold"),
            "voltage_filter_s": est(0.1, "s", "ESC voltage low-pass (fleet value)"),
        },
    }
    return variant


def render(raw):
    # .gitattributes checks aircraft JSON out with CRLF; write those exact bytes so hashes match any checkout.
    return (json.dumps(raw, indent=2, ensure_ascii=False, allow_nan=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def main():
    raw, pack, pack_bytes, summary = build()
    outputs = {OUTPUT: render(raw), PACK_OUTPUT: render(pack_variant(raw, pack, pack_bytes))}
    if "--check" in sys.argv:
        stale = [p for p, data in outputs.items() if not p.exists() or p.read_bytes() != data]
        for p in stale:
            print("stale or missing: %s (run %s)" % (p.relative_to(ROOT).as_posix(), SCRIPT))
        if not stale:
            print("X8-06 physics data current (%d files)" % len(outputs))
        return 1 if stale else 0
    for p, data in outputs.items():
        p.write_bytes(data)
        print("wrote", p.relative_to(ROOT).as_posix())
    print(json.dumps({k: (round(v, 5) if isinstance(v, float) else v) for k, v in summary.items()}, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
