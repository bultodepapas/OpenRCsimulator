#!/usr/bin/env python3
"""Stage a verified RCV Linux extension into a disposable frozen-app copy."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--diagnostic-root", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    candidate = args.candidate.resolve(strict=True)
    diagnostic = args.diagnostic_root.resolve(strict=True)
    evidence = args.evidence.resolve(strict=True)
    copied_app = diagnostic / "app"
    native_dir = copied_app / "native/ground_vehicle"
    if not copied_app.is_dir() or not (copied_app / "project.godot").is_file():
        raise SystemExit(f"Diagnostic app copy is incomplete: {copied_app}")
    if not native_dir.resolve().is_relative_to(diagnostic):
        raise SystemExit(f"Refusing to stage outside diagnostic root: {native_dir}")
    if (candidate / "app/native").exists():
        raise SystemExit("Frozen candidate unexpectedly has app/native; do not overlay this diagnostic.")

    report_path = evidence / "verification.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("exit_code") != 0 or not report.get("smoke_passed") or not report.get("parity_passed"):
        raise SystemExit("Native verifier did not report build, load smoke, and parity success.")
    binary = evidence / "libopenrc_ground_vehicle.so"
    record = report.get("isolated_build_receipt")
    if not isinstance(record, dict) or sha256(binary) != report.get("library_sha256"):
        raise SystemExit("Native binary does not match the verified report.")
    if record.get("binary_sha256") != report.get("library_sha256"):
        raise SystemExit("Native binary does not match the isolated build receipt.")

    native_dir.mkdir(parents=True, exist_ok=True)
    staged_binary = native_dir / "libopenrc_ground_vehicle.so"
    shutil.copy2(binary, staged_binary)
    descriptor = (
        '[configuration]\n'
        'entry_symbol = "openrc_ground_vehicle_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        'reloadable = false\n\n'
        '[libraries]\n'
        'windows = "res://native/ground_vehicle/openrc_ground_vehicle.dll"\n'
        'linux = "res://native/ground_vehicle/libopenrc_ground_vehicle.so"\n'
    )
    descriptor_path = native_dir / "openrc_ground_vehicle.gdextension"
    descriptor_path.write_text(descriptor, encoding="utf-8")
    receipt = {
        "format": "openrc-ground-vehicle-native-receipt",
        "backend": "native",
        "backend_version": record["backend_version"],
        "abi_version": record["abi_version"],
        "solver_version": record["solver_version"],
        "platforms": {"linux": record},
    }
    receipt_path = native_dir / "build-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    manifest_path = evidence.parent.parent / "linux-rate-guard-candidate-before.json"
    paths = {
        "app/test.sh": "dae260326426be613b065b0ae00f040842c310fab217979b537a274b3b36b7d6",
        "app/tests/test_rcv_powertrain.gd": "6f7aa16278b83e9f6146d29f980279d5542de5281763ffe1f7f952209e72bfe3",
        "app/physics/ground_vehicle/vehicle_dynamics.gd": "957b3398d114ae57c71c455c1f1054f9b4646a793712d6e9f719aeef5d6a1a22",
    }
    current_hashes = {rel: sha256(candidate / rel) for rel in paths}
    if current_hashes != paths:
        raise SystemExit(f"Frozen source files differ from captured identities: {current_hashes}")

    stage = {
        "format": "openrc-rcv-native-powertrain-diagnostic-stage-v1",
        "pwd": str(Path.cwd().resolve()),
        "candidate_root": str(candidate),
        "candidate_manifest": str(manifest_path),
        "candidate_manifest_sha256": sha256(manifest_path),
        "diagnostic_root": str(diagnostic),
        "evidence_root": str(evidence),
        "native_verification_json_sha256": sha256(report_path),
        "native_snapshot_input_sha256": report["snapshot_input_sha256"],
        "native_library_sha256": sha256(staged_binary),
        "native_receipt_sha256": sha256(receipt_path),
        "native_receipt": record,
        "candidate_source_sha256": current_hashes,
        "staged_files": [
            str(staged_binary),
            str(descriptor_path),
            str(receipt_path),
        ],
        "note": "Only the disposable diagnostic app copy receives generated native files; frozen candidate remains unchanged.",
    }
    stage_path = evidence / "stage-receipt.json"
    stage_path.write_text(json.dumps(stage, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(stage, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
