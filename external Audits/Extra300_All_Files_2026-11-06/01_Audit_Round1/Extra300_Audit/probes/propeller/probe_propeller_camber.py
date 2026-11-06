#!/usr/bin/env python3
"""Reproduce Extra's omitted propeller camber using its actual generator block.

No repository source is modified. This is an internal-consistency probe, not a
new propeller calibration. Outputs candidate tables only for isolated evaluation.
"""
import argparse
import difflib
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    args.out.mkdir(parents=True, exist_ok=False)
    paths = {
        "generator": "research/extra-300/ex05/derive_physics.py",
        "mirror": "research/glow-engines/calibration_report.py",
        "installation": "app/data/glow/extra_61fx_2t.json",
        "aircraft": "app/data/aircraft/gp_extra_300s_60.json",
        "runtime_propeller": "app/physics/glow/propeller.gd",
        "runtime_crossflow": "app/physics/propulsion.gd",
    }
    generator = (repo / paths["generator"]).read_text()
    spec = importlib.util.spec_from_file_location("openrc_calibration_report", repo / paths["mirror"])
    mirror = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mirror)
    p = {k: v["value"] for k, v in json.loads((repo / paths["installation"]).read_text())["propeller"].items()}
    raw = json.loads((repo / paths["aircraft"]).read_text())
    start = generator.index('section = {"lift_slope_per_rad"')
    end = generator.index("# Tail pieces:", start)
    block = generator[start:end]
    needle = '"blades": gp["blades"]}'
    assert block.count(needle) == 1, "Generator boundary changed; review before reuse"
    replacement = '"blades": gp["blades"], "zero_lift_angle_rad": gp.get("zero_lift_angle_rad", 0.0)}'
    fixed_block = block.replace(needle, replacement, 1)

    def run_block(text):
        scope = {
            "gp": p, "math": math, "RHO": 1.225,
            "INSTALLATION": paths["installation"],
            "note": lambda _section, _name, value, _how: value,
            "annular_prop_performance": mirror.annular_prop_performance,
        }
        exec(compile(text, str(repo / paths["generator"]), "exec"), scope)
        return scope

    baseline = run_block(block)
    candidate = run_block(fixed_block)
    stock_prop = raw["propulsion"]["propeller"]
    assert baseline["nf_rows"] == stock_prop["normal_force"]["value"]
    assert baseline["pm_rows"] == stock_prop["pfactor_moment"]["value"]
    assert len(baseline["nf_rows"]) == len(baseline["pm_rows"]) == 22
    zero_block = fixed_block.replace('gp.get("zero_lift_angle_rad", 0.0)', "0.0")
    zero_control = run_block(zero_block)
    assert zero_control["nf_rows"] == baseline["nf_rows"]
    assert zero_control["pm_rows"] == baseline["pm_rows"]
    rows = []
    for i, (advance, cn_old) in enumerate(baseline["nf_rows"]):
        cn_new = candidate["nf_rows"][i][1]
        cm_old = baseline["pm_rows"][i][1]
        cm_new = candidate["pm_rows"][i][1]
        u = advance * 200.0 * p["diameter_m"]
        ctor = 1.225 * 200.0**2 * p["diameter_m"]**4
        thrusts = [mirror.annular_prop_performance(12000.0, u, p["diameter_m"], p["pitch_m"], p["chord_m"], 1.225, s)["thrust_n"] for s in [baseline["section"], candidate["section"]]]
        dct = (thrusts[1] - thrusts[0]) / ctor
        # Independent cancellation of sigma and section-average lift terms.
        dcn = 3.0 * advance * advance * dct / (2.0 * math.pi**2)
        dcm = advance * dct / (2.0 * math.pi)
        if cm_old > 0.0 and cm_new > 0.0:
            assert abs((cm_new - cm_old) - dcm) <= 1.000000001e-6
        assert abs((cn_new - cn_old) - dcn) <= 1.000000001e-6
        rows.append({"J": advance, "axial_mps_at_12000rpm": u,
                     "thrust_symmetric_n": thrusts[0], "thrust_installed_n": thrusts[1],
                     "Cn_stock": cn_old, "Cn_consistent": cn_new,
                     "Cm_stock": cm_old, "Cm_consistent": cm_new,
                     "Cn_analytic_delta_unrounded": dcn, "Cm_analytic_delta_unclamped": dcm,
                     "Cn_stock_shortfall_percent": (100.0 * (1.0 - cn_old/cn_new) if cn_new else None),
                     "Cm_stock_shortfall_percent": (100.0 * (1.0 - cm_old/cm_new) if cm_new else None)})
    out = {"source_revision": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
           "source_sha256": {path: hashlib.sha256((repo/path).read_bytes()).hexdigest() for path in paths.values()},
           "zero_lift_angle_rad": p["zero_lift_angle_rad"],
           "zero_lift_angle_deg": math.degrees(p["zero_lift_angle_rad"]),
           "stock_rows_reproduced_exactly": 44, "zero_camber_control_exact": True,
           "rows": rows, "normal_force": candidate["nf_rows"], "pfactor_moment": candidate["pm_rows"],
           "scope": "Declared-method consistency only; existing crossflow law and calibration assumptions retained."}
    (args.out/"camber_tables.json").write_text(json.dumps(out, indent=2) + "\n")
    fixed_generator = generator[:start] + fixed_block + generator[end:]
    patch = "".join(difflib.unified_diff(generator.splitlines(keepends=True), fixed_generator.splitlines(keepends=True), fromfile="a/"+paths["generator"], tofile="b/"+paths["generator"]))
    (args.out/"generator_camber_candidate.patch").write_text(patch)
    print(json.dumps({"ok": True, "stock_rows_exact": 44, "zero_camber_control_exact": True,
                      "selected_rows": [row for row in rows if row["J"] in [0.3, 0.5, 0.7, 0.8]]}, indent=2))


if __name__ == "__main__":
    main()
