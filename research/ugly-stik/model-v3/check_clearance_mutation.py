#!/usr/bin/env python3
"""Prove the integrated mesh-clearance gate rejects a broken tail hinge gap.

The generated geometry is mutated only inside a disposable copy of app/.
The shared application tree and source geometry JSON are never edited.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
GODOT_PATH = ROOT / ".tools/Godot_v4.7.2-stable_linux.x86_64"
GENERATED_GEOMETRY = Path("aircraft/ugly_stik_geometry.gd")
MUTATION_RUNNER = Path("research/ugly-stik/model-v3/verify_clearance.gd")
DEFAULT_OUTPUT = ROOT / "research/ugly-stik/model-v3/clearance-mutation-hinge-gap.json"
BEFORE = '"hinge_gap": 0.004'
AFTER = '"hinge_gap": 0.0'


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if not GODOT_PATH.is_file():
        raise SystemExit(f"Pinned Godot binary not found: {GODOT_PATH}")

    baseline_geometry = ROOT / "assets/aircraft/ugly-stik-60/geometry.json"
    baseline_generated = ROOT / "app" / GENERATED_GEOMETRY
    baseline_checker = ROOT / "app/aircraft/model_clearance.gd"
    baseline_builder = ROOT / "app/aircraft/ugly_stik_model.gd"
    baseline_geometry_hash = sha256(baseline_geometry.read_bytes())
    baseline_generated_bytes = baseline_generated.read_bytes()
    baseline_generated_hash = sha256(baseline_generated_bytes)
    generated_text = baseline_generated_bytes.decode("utf-8")
    if generated_text.count(BEFORE) != 1:
        raise SystemExit(f"Expected exactly one tail hinge gap {BEFORE!r}")
    mutated_generated = generated_text.replace(BEFORE, AFTER).encode("utf-8")

    with tempfile.TemporaryDirectory(prefix="stik-v3-hinge-gap-mutation-") as scratch_name:
        scratch = Path(scratch_name)
        app_copy = scratch / "app"
        shutil.copytree(ROOT / "app", app_copy)
        (app_copy / GENERATED_GEOMETRY).write_bytes(mutated_generated)
        runner_destination = scratch / MUTATION_RUNNER
        runner_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / MUTATION_RUNNER, runner_destination)

        scratch_report_path = scratch / "clearance-mutation.json"
        clearance = subprocess.run(
            [str(GODOT_PATH), "--headless", "--path", str(app_copy), "--script",
             "../research/ugly-stik/model-v3/verify_clearance.gd", "--",
             f"--output={scratch_report_path}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        print(clearance.stdout, end="")
        if clearance.returncode == 0 or not scratch_report_path.is_file():
            raise SystemExit("Detailed checker did not reject the zero-gap mutation")
        report = json.loads(scratch_report_path.read_text())
        if report.get("ok") or not report.get("failures"):
            raise SystemExit("Mutation report did not contain clearance failures")

        contract = subprocess.run(
            [str(GODOT_PATH), "--headless", "--path", str(app_copy), "--script",
             "res://aircraft/verify_model.gd"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        print(contract.stdout, end="")
        if contract.returncode == 0 or "moving surfaces retain geometric clearance" not in contract.stdout:
            raise SystemExit("Integrated model contract did not reject the mutation")
        checks_match = re.search(r"(\d+) checks, (\d+) failed", contract.stdout)

        # The source JSON stayed unchanged in the scratch copy; the runner
        # cannot resolve that repo-relative source from /tmp, so record its
        # original digest explicitly with the generated-file mutation.
        report["geometry_source_sha256"] = baseline_geometry_hash
        report["mutation"] = {
            "field": "tail.hinge_gap",
            "baseline_m": 0.004,
            "mutated_m": 0.0,
            "baseline_geometry_source_sha256": baseline_geometry_hash,
            "baseline_generated_geometry_sha256": baseline_generated_hash,
            "mutated_generated_geometry_sha256": sha256(mutated_generated),
            "method": "changed generated geometry only in a disposable temporary app copy",
            "detailed_checker_exit_code": clearance.returncode,
            "integrated_contract_exit_code": contract.returncode,
            "integrated_contract_checks": int(checks_match.group(1)) if checks_match else None,
            "integrated_contract_failed_checks": int(checks_match.group(2)) if checks_match else None,
            "result": "detected by moving-surface clearance regression",
            "shared_app_modified": False,
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"saved mutation evidence: {args.output}")


if __name__ == "__main__":
    run()
