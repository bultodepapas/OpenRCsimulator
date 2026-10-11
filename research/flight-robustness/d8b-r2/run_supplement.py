"""Reproduce D8b-R2 static research and independently decompose wing roll feedback."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs/research/flight-robustness/D8b-R2"


def hashes():
    files = [p for p in ROOT.joinpath("app").rglob("*")
             if p.is_file() and ".godot" not in p.parts
             and p.suffix in {".gd", ".json", ".godot"}]
    files += [Path(__file__), Path(__file__).with_name("supplement.gd")]
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(files)}


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x*x*(3-2*x)


def wing_moment(data, alpha, p, freeze_weights=False):
    """Direct force/moment reduction of wing strips; no tail, gyro, or integration.

    Frozen weights remove only d(stall blend)/dp for causal attribution at p=0.
    This intentionally nonphysical counterfactual must never become a flight law.
    """
    env, aero, ref = data["envelope"], data["aero"], data["reference"]
    ys, matrix = env["station_ys"], env["induced_map"]
    n = len(ys)
    area = ref["S"]/n
    az = -(ref["arp_le"][2] - data["cg"][2])
    vx, vz = 25*math.cos(alpha), 25*math.sin(alpha)
    angles = [math.atan2(vz+p*y, vx) for y in ys]
    total = 0.0
    for i, y in enumerate(ys):
        f0, f1, f2 = vx, -p*az, vz+p*y
        angle = angles[i]
        stall_angle = alpha if freeze_weights else angle
        weight = smooth((stall_angle-env["a1"])/(env["a2"]-env["a1"]))
        base = env["strip_cl0"][i] + env["strip_slope"]*sum(matrix[i*n+k]*angles[k] for k in range(n))
        cl = (1-weight)*base + weight*0.5*env["CD90"]*math.sin(2*angle)
        cd = aero["CD0"] + (1-weight)*aero["k_induced"]*(cl-aero["CL_minD"])**2 + weight*env["CD90"]*math.sin(angle)**2
        speed, plane = math.sqrt(f0*f0+f1*f1+f2*f2), math.hypot(f0,f2)
        drag_scale = -0.5*1.225*speed*area*cd
        fy = drag_scale*f1
        fz = drag_scale*f2 - 0.5*1.225*plane*area*cl*f0
        total += y*fz-az*fy
    return total


def finite(value):
    if isinstance(value, float):
        assert math.isfinite(value)
    elif isinstance(value, dict):
        for v in value.values(): finite(v)
    elif isinstance(value, list):
        for v in value: finite(v)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    godot = args.godot.resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    before = hashes()
    output = OUT / "supplement.json"
    if output.exists(): output.unlink()  # Only the explicitly named generated result.
    run = subprocess.run([str(godot), "--headless", "--path", str(ROOT/"app"), "--script",
                          str(Path(__file__).with_name("supplement.gd"))], cwd=ROOT,
                         text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=60)
    log = run.stdout + run.stderr
    (OUT/"supplement.log").write_text(log, encoding="utf-8")
    assert run.returncode == 0 and not re.search(r"(?m)^(?:SCRIPT |SHADER )?ERROR:", log)
    data = json.loads(output.read_text(encoding="utf-8"))
    finite(data)
    assert len(data["width_sensitivity"]) == 5 and all(r["accepted"] for r in data["width_sensitivity"])
    assert len(data["spatial_refinement"]) == 4 and len(data["difference_step"]) == 5
    assert data["positive_control_derivative_error"] < 1e-7
    baseline = json.loads((OUT/"results.json").read_text(encoding="utf-8"))[-1]
    decomposition = []
    dp = 1e-5
    for degrees in [11.0,13.0,14.0,15.5,18.0]:
        a = math.radians(degrees)
        wing = (wing_moment(data,a,dp)-wing_moment(data,a,-dp))/(2*dp)
        frozen = (wing_moment(data,a,dp,True)-wing_moment(data,a,-dp,True))/(2*dp)
        total = next(row["roll_nm_per_radps"] for row in baseline["rows"] if row["alpha_deg"] == degrees)
        native_wing = next(row["derivative"] for row in data["native_wing_derivative"] if row["alpha_deg"] == degrees)
        assert abs(wing-native_wing) < 1e-7, "Independent wing reduction disagrees with Godot"
        decomposition.append({"alpha_deg": degrees, "production_total_derivative": total,
                              "wing_derivative": wing, "frozen_weight_wing_derivative": frozen,
                              "native_wing_comparison_error": abs(wing-native_wing),
                              "blend_weight_contribution": wing-frozen,
                              "total_minus_wing": total-wing})
    # The original finite-difference sweep is an independent saved runtime control.
    assert abs(data["difference_step"][3]["derivative"] - baseline["rows"][15]["roll_nm_per_radps"]) < 1e-7
    assert hashes() == before, "Concurrent source changes invalidate the comparison"
    finite(decomposition)
    (OUT/"decomposition.json").write_text(json.dumps(decomposition,indent=2)+"\n",encoding="utf-8")
    manifest = {"format": "openrc-pullup-research-supplement v1", "date": "2026-10-11",
                "base_commit": subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),
                "engine_version": subprocess.check_output([str(godot),"--version"],text=True).strip(),
                "source_sha256": before,
                "output_sha256": {name:hashlib.sha256((OUT/name).read_bytes()).hexdigest()
                                  for name in ["results.json","supplement.json","decomposition.json"]},
                "checks": "5 accepted widths, 4 meshes, 5 epsilons, positive control, finite results, no engine errors, unchanged sources"}
    (OUT/"supplement-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(decomposition,indent=2))
    print("Supplement complete; production source unchanged.")


if __name__ == "__main__": main()
