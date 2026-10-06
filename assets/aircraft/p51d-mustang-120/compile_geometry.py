#!/usr/bin/env python3
"""Compile the P-51D visual record (geometry.json) into a dependency-free Godot constant.

No physics data is generated. --check detects a stale runtime copy and validates the record's structure.
"""
import argparse
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / "app/aircraft/p51d_geometry.gd"


def finite(*values):
    return all(isinstance(v, (int, float)) and math.isfinite(v) for v in values)


def increasing(rows, column=0):
    return all(a[column] < b[column] for a, b in zip(rows, rows[1:]))


def validate(d):
    assert d["units"] == "m" and d["axes"] == {"nose": "-Z", "right": "+X", "up": "+Y"}
    w = d["wing"]
    assert w["le_z_root"] == 0.0, "datum: z = 0 at the root leading edge"
    assert 0 < w["tip_chord"] < w["root_chord"] < 1.0
    assert 0 < w["flap_inner"] < w["flap_outer"] <= w["aileron_inner"] < w["aileron_outer"] <= w["span"] / 2
    assert 0.1 < w["aileron_chord_fraction"] < 0.4 and 0.1 < w["flap_chord_fraction"] < 0.4
    assert 0 < w["hinge_gap"] < 0.01 and 0 < w["tip_thickness_ratio"] <= w["root_thickness_ratio"] < 0.25
    assert 0 <= w["camber_ratio"] < 0.05 and 0 <= w["dihedral_deg"] < 10
    section = w["section"]
    assert section[0] == [0.0, 0.0] and section[-1][0] == 1.0 and increasing(section)
    assert all(finite(*p) and 0 <= p[1] <= 0.5 for p in section)
    stations = d["fuselage_stations"]
    assert increasing(stations), "stations must run nose to tail"
    for z, half_width, top, bottom, top_exp, bottom_exp in stations:
        assert finite(z, half_width, top, bottom) and half_width > 0 and top > bottom
        assert 1.5 <= top_exp <= 4 and 1.5 <= bottom_exp <= 4
    s = d["spinner"]
    assert s["tip_z"] < s["back_z"] <= stations[0][0] and s["radius"] > 0
    assert stations[0][0] < d["firewall_z"] < d["cowl_rear_z"]
    scoop = d["scoop_stations"]
    assert increasing(scoop) and all(row[1] > 0 for row in scoop)
    canopy = d["canopy"]["top"]
    assert increasing(canopy) and 0 < d["canopy"]["halfwidth_fraction"] <= 1 and canopy[0][0] < d["canopy"]["frame_z"] < canopy[-1][0]
    t = d["tail"]
    assert t["stab_root_le_z"] < t["stab_tip_le_z"] and 0 < t["stab_tip_chord"] < t["stab_root_chord"]
    assert 0.4 < t["elevator_hinge_fraction"] < 0.9 and t["stab_half_span"] > 0
    assert t["dorsal_start_z"] < t["fin_root_le_z"] < t["fin_top_le_z"] < t["rudder_hinge_z"] < t["rudder_te_bottom"][0]
    assert t["fin_top_le_z"] + t["fin_top_chord"] > t["rudder_hinge_z"], "the rudder must reach the fin top"
    assert t["fin_top_y"] > t["stab_y"] and 0 < t["stab_thickness"] < 0.05 and 0 < t["fin_thickness"] < 0.05
    g = d["gear"]
    assert g["main_axle"][1] < w["chord_plane_y"] and g["track"] > 0 and g["main_wheel_diameter"] > g["tail_wheel_diameter"] > 0
    pr = d["propeller"]
    assert 0.3 < pr["diameter"] < 1.2 and 0.1 < pr["pitch"] < 0.6 and pr["blades"] in (2, 3, 4) and 0 < pr["hub_radius"] < s["radius"]
    for key in ("chord_fraction_of_radius", "thickness_fraction_of_chord"):
        rows = pr["blade"][key]
        assert increasing(rows) and rows[-1][0] == 1.0 and all(0 < row[1] < 0.5 for row in rows), key
    pl = d["pilot"]
    assert pl["chin"][1] < pl["nose_front"][1] < pl["cap_brim_front"][1] < pl["cap_top"][1] and pl["nose_front"][0] < pl["head_back"][0]
    assert pl["shoulder_front"][0] < pl["shoulder_back"][0] and 0 < pl["head_half_width"] < pl["shoulder_half_width"]
    for key, record in d["evidence"].items():
        assert record["kind"] in {"manual", "measured", "borrowed", "estimated", "derived"}, key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.loads((HERE / "geometry.json").read_text())
    validate(data)
    output = "# Generated from assets/aircraft/p51d-mustang-120/geometry.json; edit source.json and run build_geometry.py.\n"
    output += "# Visual geometry only. Every group has provenance in DATA.evidence.\nextends RefCounted\n\nconst DATA := "
    output += json.dumps(data, ensure_ascii=False, indent="\t") + "\n"
    if args.check:
        assert TARGET.read_text() == output, "Stale model data: run compile_geometry.py"
        print("P-51D visual geometry source/runtime: identical")
    else:
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == "__main__":
    main()
