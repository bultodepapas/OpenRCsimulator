#!/usr/bin/env python3
"""Late-mount the three -08 exported packs from empty project paths."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile


ROOT = Path("/home/bulto/openrc-r11-package-20261015-08")
GODOT = Path("/home/bulto/openrc-r11-b09-r05b-20261015-07/.tools/Godot_v4.7.2-stable_linux.x86_64")
PROBE = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/research/aircraft-standardization/rotorcraft_package_smoke.gd")
OUT = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/export-resource-probes/package-mount-01")
TIMEOUT_SECONDS = 60


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run_one(label: str, pack: Path, expected_exit: int, empty_root: Path) -> dict[str, object]:
    empty_root.mkdir(parents=True, exist_ok=False)
    log = OUT / f"{label}.log"
    command = [
        "timeout", str(TIMEOUT_SECONDS), str(GODOT), "--headless", "--path", str(empty_root),
        "--audio-driver", "Dummy", "--script", str(PROBE), "--", str(pack),
    ]
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    log.write_text(completed.stdout, encoding="utf-8", newline="\n")
    timeout_code = completed.returncode == 124
    checks = re.search(r"Rotorcraft package smoke: (\d+) checks, (\d+) failures", completed.stdout)
    record = {
        "label": label,
        "command": command,
        "empty_project_path": str(empty_root),
        "empty_project_path_was_empty_before_run": True,
        "pack_path": str(pack),
        "pack_sha256": sha256_file(pack) if pack.is_file() else None,
        "exit_code": completed.returncode,
        "expected_exit_code": expected_exit,
        "timed_out": timeout_code,
        "checks": int(checks.group(1)) if checks else None,
        "failures": int(checks.group(2)) if checks else None,
        "pack_mount_refusal": "Could not mount rotorcraft pack" in completed.stdout,
        "script_or_engine_error_markers": [
            line for line in completed.stdout.splitlines()
            if re.search(r"^(SCRIPT |SHADER )?ERROR:", line)
        ],
        "log": str(log),
        "log_sha256": sha256_file(log),
    }
    print(json.dumps(record, sort_keys=True), flush=True)
    return record


def main() -> None:
    if OUT.exists():
        raise SystemExit(f"refusing to overwrite existing probe evidence: {OUT}")
    if sha256_file(PROBE) != "929aa191632812c9083f909771c99d125c0d9c05b1ab59c8acf72076a49d3cae":
        raise SystemExit("live rotorcraft package probe changed after source-before receipt; stop and recapture")
    if subprocess.run([str(GODOT), "--version"], capture_output=True, text=True, check=True).stdout.strip() != "4.7.2.stable.official.ed1daf0bf":
        raise SystemExit("pinned Godot version mismatch")
    OUT.mkdir(parents=True, exist_ok=False)
    empty_base = Path("/tmp/openrc-r11-pack-mount-20261015-01")
    if empty_base.exists():
        raise SystemExit(f"refusing to reuse preexisting path: {empty_base}")
    empty_base.mkdir(parents=True)
    mac_zip = ROOT / "dist/macos/OpenRC Simulator.zip"
    mac_dir = OUT / "macos-extracted"
    mac_dir.mkdir()
    with zipfile.ZipFile(mac_zip) as archive:
        packs = [name for name in archive.namelist() if name.endswith(".pck")]
        if len(packs) != 1:
            raise RuntimeError(f"expected exactly one macOS PCK, got {packs!r}")
        mac_pack = mac_dir / "OpenRC Simulator.pck"
        mac_pack.write_bytes(archive.read(packs[0]))
    expected = [
        ("linux-exe", ROOT / "dist/linux/openrc-simulator.x86_64", 0),
        ("windows-exe", ROOT / "dist/windows/OpenRC Simulator.exe", 0),
        ("macos-pck", mac_pack, 0),
    ]
    records = []
    for label, pack, expected_exit in expected:
        records.append(run_one(label, pack, expected_exit, empty_base / f"{label}-empty"))
    missing = empty_base / "missing-pack.pck"
    records.append(run_one("missing-pack-negative", missing, 1, empty_base / "missing-pack-empty"))
    payload = {
        "format": "openrc-r11-exported-pack-late-mount-probe-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "scope": "Resource-only test from fresh empty project roots; no source tree path is used as --path and GDExtensions are not executed.",
        "candidate_root": str(ROOT),
        "candidate_head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip(),
        "godot_path": str(GODOT),
        "godot_sha256": sha256_file(GODOT),
        "godot_version": "4.7.2.stable.official.ed1daf0bf",
        "probe_source": str(PROBE),
        "probe_source_sha256": sha256_file(PROBE),
        "macos_zip_sha256": sha256_file(mac_zip),
        "macos_pack_member": packs[0],
        "macos_extracted_pack_sha256": sha256_file(mac_pack),
        "timeout_seconds_each": TIMEOUT_SECONDS,
        "runs": records,
        "all_expected_outcomes": all(r["exit_code"] == r["expected_exit_code"] and not r["timed_out"] for r in records),
    }
    (OUT / "results.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not payload["all_expected_outcomes"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
