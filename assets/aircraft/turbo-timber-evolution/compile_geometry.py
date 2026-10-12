#!/usr/bin/env python3
"""TT-03: compile geometry.json into the dependency-free Godot constant app/aircraft/timber_geometry.gd.

The builder (timber_model.gd) reads node names, pivots, axes, rest transforms, ranges and the app sign mapping from
DATA.articulations; verify_timber.gd compares the imported scene with DATA. Run --check to detect a stale copy.
"""
import argparse
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / "app/aircraft/timber_geometry.gd"
ARTICULATION_NODES = ["aileron_left_hinge", "aileron_right_hinge", "flap_left_hinge", "flap_right_hinge", "elevator_hinge",
                      "rudder_hinge", "tailwheel_steer", "tailwheel_axle", "propeller_spin", "gear_left_suspension",
                      "gear_right_suspension", "wheel_left_axle", "wheel_right_axle"]


def as_godot_json(value):
    """Godot's JSON parser reads every number as float; keep the generated constant identical to a parsed file."""
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        assert math.isfinite(value), value
        return float(value)
    if isinstance(value, list):
        return [as_godot_json(v) for v in value]
    return {k: as_godot_json(v) for k, v in value.items()}


def validate(d):
    assert d["schema"] == "openrc-timber-geometry v1" and d["units"] == "m"
    assert d["axes"] == {"nose": "-Z", "right": "+X", "up": "+Y"}
    assert d["catalog_id"] == "eflite-turbo-timber-evolution"
    assert d["datum"]["position"] == [0.0, 0.0, 0.0]
    arts = d["articulations"]
    assert sorted(arts) == sorted(ARTICULATION_NODES), sorted(arts)
    for name, a in arts.items():
        assert a["node"] == name and a["parent"] and a["mesh_node"], name
        assert abs(math.sqrt(sum(x * x for x in a["axis"])) - 1.0) < 1e-5, name
        assert a["range_deg"] is None or a["range_deg"][0] < a["range_deg"][1], name
        if a["app_key"]:
            assert a["app_sign"] in (-1.0, 1.0), name
    assert d["thrust"]["node"] == "thrust_frame" and d["thrust"]["spin_node"] == "propeller_spin"
    assert d["scene"]["counts"]["mesh_instances"] == 15 and d["scene"]["counts"]["surfaces"] == 36
    assert d["scene"]["counts"]["animation_players"] == 0 and d["scene"]["counts"]["cameras"] == 0 and d["scene"]["counts"]["lights"] == 0
    assert 1.5 < d["dimensions"]["span"]["value"] < 1.6 and 0.2 < d["wing"]["chord"]["value"] < 0.23
    for key in ("aileron", "elevator", "rudder"):
        assert 0.0 < d["controls"][key]["high_deg"]["value"] < 60.0, key
    for key, record in d["evidence"].items():
        assert record.get("kind") and record.get("source"), key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.loads((HERE / "geometry.json").read_text(encoding="utf-8"))
    validate(data)
    output = "# Generated, do not edit. Source: assets/aircraft/turbo-timber-evolution/geometry.json (revision %s).\n" % data["revision"]
    output += "# Regenerate with: python3 assets/aircraft/turbo-timber-evolution/compile_geometry.py\n"
    output += "# Visual preview geometry of the author's r1 export (see DATA.evidence); not flyable.\n"
    output += "extends RefCounted\n\nconst DATA := "
    output += json.dumps(as_godot_json(data), ensure_ascii=False, indent="\t") + "\n"
    if args.check:
        assert TARGET.exists() and TARGET.read_text(encoding="utf-8") == output, "Stale Timber geometry constant: run compile_geometry.py"
        print("Timber geometry source/runtime: identical")
    else:
        TARGET.write_text(output, encoding="utf-8")
        print(TARGET.relative_to(ROOT))


if __name__ == "__main__":
    main()
