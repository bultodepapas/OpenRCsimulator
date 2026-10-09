#!/usr/bin/env python3
"""D1-R5: exact load pairs, isolated solver faults, and a residual-check negative control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RESIDUAL = "\tif not is_finite(solved) or absf(solved - target) > 1e-10 * maxf(1.0, absf(target)):\n\t\treturn false\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True, help="pre-D1-R5 aircraft_data.gd snapshot")
    parser.add_argument("--loader", type=Path, default=ROOT / "app/physics/aircraft_data.gd")
    parser.add_argument("--output", type=Path, required=True, help="new evidence directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    godot = subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip()
    source = args.loader.read_text()
    before = args.baseline.read_bytes()
    records = []

    def run(name, script, env=None, expected=0):
        result = subprocess.run([godot, "--headless", "--path", str(ROOT / "app"), "--script", str(script)],
                                env=os.environ | (env or {}), text=True, capture_output=True, timeout=60)
        log = result.stdout + result.stderr
        (args.output / (name + ".log")).write_text(log)
        assert result.returncode == expected, (name, result.returncode, log)
        assert "ERROR:" not in log, (name, log)
        if name == "missing_residual":
            assert log.count("refused=false") == 4, log
        records.append({"name": name, "exit": result.returncode})

    with tempfile.TemporaryDirectory(prefix="openrc-d1-r5-faults-") as temp:
        temp = Path(temp)
        baseline = temp / "before.gd"
        baseline.write_bytes(before)
        candidate = temp / "candidate.gd"
        candidate.write_text(source)
        run("pairs", ROOT / "research/aircraft-data/data2b/compare.gd", {
            "OPENRC_DATA2B_BEFORE": str(baseline), "OPENRC_DATA2B_AFTER": str(candidate)})
        marker = "\tvar wsum := _row_mean(e_map, n)"
        assert source.count(marker) == 1
        for fault, expr in {"nan": "NAN", "infinity": "INF", "finite_wrong_map": "0.0"}.items():
            mutant = temp / (fault + ".gd")
            injection = "\te_map.fill(%s)\n" % expr
            mutant.write_text(source.replace(marker, injection + marker))
            run(fault, ROOT / "research/aircraft-data/d1-r5/fault_probe.gd", {"OPENRC_INDUCED_LOADER": str(mutant)})
        # Removing only residual acceptance must let a finite wrong map escape to the loader.
        assert source.count(RESIDUAL) == 1
        mutant = temp / "missing_residual.gd"
        mutant.write_text(source.replace(RESIDUAL, "").replace(marker, "\te_map.fill(1.0)\n" + marker))
        run("missing_residual", ROOT / "research/aircraft-data/d1-r5/fault_probe.gd",
            {"OPENRC_INDUCED_LOADER": str(mutant)}, expected=1)
    assert args.loader.read_text() == source, "loader changed during verification"
    report = {"baseline_sha256": hashlib.sha256(before).hexdigest(),
              "loader_sha256": hashlib.sha256(source.encode()).hexdigest(),
              "exact_fleet_load_pairs": 96, "solver_fault_refusals": 12,
              "negative_control": "missing residual accepts four wrong maps", "runs": records}
    (args.output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
