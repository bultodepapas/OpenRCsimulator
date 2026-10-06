#!/usr/bin/env python3
"""P51-01: scale the full-size P-51D record (source.json) to the kit and write geometry.json.

Model axes: +X right, +Y up, -Z nose; z = 0 at the wing leading edge on the centreline, y = 0 on the thrust line
(spinner axis). Every full-size length is multiplied by kit.span / full_size.span; angles and fractions pass through.
The kit's own values (propeller, engine, mass, throws) are copied, not scaled.

    python3 assets/aircraft/p51d-mustang-120/build_geometry.py          # writes geometry.json
    python3 assets/aircraft/p51d-mustang-120/build_geometry.py --check  # fails if geometry.json is stale
"""
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source.json"
TARGET = HERE / "geometry.json"
IN = 0.0254


def r(x, nd=4):
    return round(x, nd)


def main():
    src = json.loads(SOURCE.read_text())
    fs = src["full_size"]
    kit = src["kit"]
    k = kit["span"] / fs["span"]
    L = lambda v: r(v * k)  # scaled length
    semi_fs = fs["span"] / 2
    cr, ct = fs["root_chord_centreline"], fs["tip_chord"]
    lam = ct / cr
    le_tip_fs = math.tan(math.radians(fs["quarter_chord_sweep_deg"])) * semi_fs + 0.25 * (cr - ct)
    mac_fs = 2 / 3 * cr * (1 + lam + lam * lam) / (1 + lam)
    y_mac_fs = semi_fs / 3 * (1 + 2 * lam) / (1 + lam)
    mac_le_fs = le_tip_fs * y_mac_fs / semi_fs
    trap_fs = fs["span"] * (cr + ct) / 2
    t = fs["tail"]
    g = fs["gear"]
    # Scoop: the top of every scoop ring is the fuselage bottom at that station; only [z, half width, bottom].
    scoop = [[L(z), L(w), L(b)] for z, w, b in fs["scoop_stations"]]
    out = {
        "id": "p51d-mustang-120-v1",
        "kit": kit["name"],
        "units": "m",
        "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "datum": "Symmetry plane; z = 0 at the wing leading edge on the centreline; y = 0 on the thrust line (spinner axis). Physics CG is set in the data file.",
        "scale": {"full_size_span": fs["span"], "model_span": kit["span"], "factor": r(k, 6), "nominal": f"1/{1 / k:.2f}"},
        "engine_class": kit["engine"],
        "wing": {
            "span": r(kit["span"]),
            "root_chord": L(cr),
            "tip_chord": L(ct),
            "le_z_root": 0.0,
            "le_z_tip": L(le_tip_fs),
            "chord_plane_y": L(fs["chord_plane_y_root"]),
            "dihedral_deg": fs["dihedral_deg"],
            "incidence_deg": fs["incidence_deg"],
            "washout_deg": fs["washout_deg"],
            "root_thickness_ratio": fs["root_thickness_ratio"],
            "tip_thickness_ratio": fs["tip_thickness_ratio"],
            "camber_ratio": fs["camber_ratio"],
            "aileron_inner": L(fs["aileron"]["inner"]),
            "aileron_outer": L(fs["aileron"]["outer"]),
            "aileron_chord_fraction": fs["aileron"]["chord_fraction"],
            "flap_inner": L(fs["flap"]["inner"]),
            "flap_outer": L(fs["flap"]["outer"]),
            "flap_chord_fraction": fs["flap"]["chord_fraction"],
            "hinge_gap": 0.003,
            "section": src["section"]["half_thickness_normalised"],
            "reference": {
                "trapezoid_area": r(trap_fs * k * k),
                "s_over_b": r(trap_fs * k * k / kit["span"]),
                "mac": L(mac_fs),
                "mac_le_z": L(mac_le_fs),
                "mac_span_station": L(y_mac_fs),
                "cg_fraction_of_mac": kit["cg_fraction_of_mac"],
            },
        },
        "fuselage_stations": [[L(z), L(w), L(top), L(bot), te, be] for z, w, top, bot, te, be in fs["fuselage_stations"]],
        "scoop_stations": scoop,
        "carb_intake": {"z0": L(fs["carb_intake"]["z0"]), "z1": L(fs["carb_intake"]["z1"]), "half_width": L(fs["carb_intake"]["half_width"]), "height": L(fs["carb_intake"]["height"])},
        "spinner": {"tip_z": L(fs["spinner"]["tip_z"]), "back_z": L(fs["spinner"]["back_z"]), "radius": L(fs["spinner"]["radius"])},
        "firewall_z": L(fs["firewall_z"]),
        "cowl_rear_z": L(fs["cowl_rear_z"]),
        "canopy": {"top": [[L(z), L(y)] for z, y in fs["canopy"]["top"]], "frame_z": L(fs["canopy"]["frame_z"]), "halfwidth_fraction": fs["canopy"]["halfwidth_fraction"]},
        "tail": {
            "stab_y": L(t["stab_y"]),
            "stab_root_le_z": L(t["stab_root_le_z"]),
            "stab_tip_le_z": L(t["stab_tip_le_z"]),
            "stab_half_span": L(t["stab_half_span"]),
            "stab_root_chord": L(t["stab_root_chord"]),
            "stab_tip_chord": L(t["stab_tip_chord"]),
            "elevator_hinge_fraction": t["elevator_hinge_fraction"],
            "stab_thickness": L(t["stab_thickness_ratio"] * (t["stab_root_chord"] + t["stab_tip_chord"]) / 2),
            "stab_incidence_deg": t["stab_incidence_deg"],
            "fin_root_le_z": L(t["fin_root_le_z"]),
            "dorsal_start_z": L(t["dorsal_start_z"]),
            "fin_top_y": L(t["fin_top_y"]),
            "fin_top_le_z": L(t["fin_top_le_z"]),
            "fin_top_chord": L(t["fin_top_chord"]),
            "rudder_hinge_z": L(t["rudder_hinge_z"]),
            "rudder_te_bottom": [L(t["rudder_te_bottom"][0]), L(t["rudder_te_bottom"][1])],
            "fin_thickness": L(t["fin_thickness_ratio"] * t["fin_top_chord"] * 1.6),
            "hinge_gap": 0.003,
            # V01 (measured outlines, scaled): tail upper/lower contours [z, y] and stab planform [x, z]
            "upper_outline": [[L(z), L(y)] for z, y in t["upper_outline"]],
            "lower_outline": [[L(z), L(y)] for z, y in t["lower_outline"]],
            "stab_planform": {"le": [[L(x), L(z)] for x, z in t["stab_planform"]["le"]], "te": [[L(x), L(z)] for x, z in t["stab_planform"]["te"]]},
            "elevator_horn": t["elevator_horn"],
            "stab_tip_round": L(t["stab_tip_round"]),
        },
        "gear": {
            "main_axle": [L(g["main_axle"][0]), L(g["main_axle"][1])],
            "main_wheel_diameter": L(g["main_wheel_diameter"]),
            "main_wheel_width": L(g["main_wheel_width"]),
            "track": L(g["track"]),
            "strut_radius": L(g["strut_radius"]),
            "tail_axle": [L(g["tail_axle"][0]), L(g["tail_axle"][1])],
            "tail_wheel_diameter": L(g["tail_wheel_diameter"]),
        },
        "propeller": {
            "diameter": r(kit["propeller"]["diameter_in"] * IN),
            "pitch": r(kit["propeller"]["pitch_in"] * IN),
            "blades": kit["propeller"]["blades"],
            "z": L(fs["spinner"]["back_z"] - 0.20),
            "hub_radius": L(fs["spinner"]["radius"] * 0.5),
            "scale_diameter": L(fs["propeller_diameter"]),
            "blade": {
                "chord_fraction_of_radius": [[0.2, 0.14], [0.35, 0.17], [0.55, 0.18], [0.75, 0.17], [0.9, 0.13], [1.0, 0.04]],
                "thickness_fraction_of_chord": [[0.2, 0.18], [0.5, 0.1], [1.0, 0.06]],
            },
        },
        "pilot": {key: ([L(v[0]), L(v[1])] if isinstance(v, list) else L(v)) for key, v in fs["pilot"].items()},
        "evidence": dict(src["evidence"], **{
            "scaling": {"kind": "derived", "source": "assets/aircraft/p51d-mustang-120/build_geometry.py: every full-size length x kit.span / full_size.span", "method": f"factor {k:.5f} (1/{1 / k:.2f})"},
            "propeller": {"kind": "estimated", "source": "kit propeller size (not the scaled 11 ft 2 in Hamilton Standard, recorded as scale_diameter); paddle-blade planform by eye; pitch for the twist only", "limits": "visual stand-in"},
        }),
    }
    text = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != text:
            sys.exit("stale geometry.json: run build_geometry.py")
        print("geometry.json is up to date with source.json")
    else:
        TARGET.write_text(text)
        print(f"wrote {TARGET.relative_to(HERE.parents[2])} (scale 1/{1 / k:.2f}, span {kit['span']} m, MAC {mac_fs * k:.4f} m)")


if __name__ == "__main__":
    main()
