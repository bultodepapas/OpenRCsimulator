#!/usr/bin/env python3
"""Reproduce the third audit against its pinned Git snapshot in disposable projects.

Passing observations describe the baseline, including known failures. They do
not establish repaired behavior, GPU timing, a native backend or a full game run.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def digest(path: Path, algorithm: str = "sha256") -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True,
                        help="A new output directory; existing directories are refused")
    args = parser.parse_args()
    engine, out = args.godot.resolve(), args.out.resolve()
    manifest = json.loads((HERE / "fixture_sources.json").read_text())
    commit = manifest["source_commit"]
    if not engine.is_file() or digest(engine, "sha512") != manifest["engine_sha512"]:
        raise RuntimeError("Engine differs from the pinned official Linux x86_64 binary")
    for name, expected in manifest["assets"].items():
        if digest(HERE / name) != expected:
            raise RuntimeError(f"Fixture asset differs: {name}")
    subprocess.run(["git", "cat-file", "-e", commit + "^{commit}"], cwd=REPO, check=True)
    out.mkdir(parents=True, exist_ok=False)
    sources: dict[str, bytes] = {}
    for name, expected in manifest["files"].items():
        data = subprocess.check_output(["git", "show", commit + ":" + name], cwd=REPO)
        if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise RuntimeError(f"Pinned Git source differs: {name}")
        sources[name] = data
    # Keep the checked runner in its repository so its queue/admission imports
    # retain their supported location. Do not bypass those imports in a copy.
    runner = REPO / "tools/godot/run_checked.py"
    if runner.read_bytes() != sources["tools/godot/run_checked.py"]:
        raise RuntimeError("Checked runner differs from the pinned source")
    environments: dict[str, dict[str, str]] = {}
    for group, specification in manifest["groups"].items():
        fixture = out / group
        fixture.mkdir()
        for name in specification["files"]:
            target = fixture / Path(name).relative_to("app")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(sources[name])
        for name in specification["patches"]:
            patch = manifest["patches"][name]
            target = fixture / Path(patch["path"]).relative_to("app")
            lines = target.read_text().splitlines(keepends=True)
            for edit in reversed(patch["edits"]):
                start = edit["start_line"]
                end = start + len(edit["old_lines"])
                if lines[start:end] != edit["old_lines"]:
                    raise RuntimeError(f"Fixture patch precondition differs: {name}")
                lines[start:end] = edit["new_lines"]
            target.write_bytes("".join(lines).encode())
            if digest(target) != patch["output_sha256"]:
                raise RuntimeError(f"Fixture patch output differs: {name}")
        for target_name, asset in specification["assets"].items():
            target = fixture / target_name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(HERE / asset, target)
        environment = os.environ.copy()
        for variable, leaf in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_CACHE_HOME", "cache")):
            environment[variable] = str(out / "xdg" / group / leaf)
        environments[group] = environment
    # Source scanners may enumerate these roots. Their identity is explicitly a
    # fixture identity, not the complete shipped application or a native package.
    for name in ("physics", "sim", "failures"):
        (out / "simulation" / name).mkdir(exist_ok=True)
    runs: list[dict] = []

    def checked(group: str, label: str, script: str = "", marker: str = "") -> None:
        command = [sys.executable, str(runner), "--label", label, "--out-dir", str(out / "runs"),
                   "--timeout", "60"]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(out / group)]
        command += ["--script", "res://" + script] if script else ["--editor", "--import"]
        process = subprocess.run(command, cwd=REPO, env=environments[group],
                                 capture_output=True, text=True, check=False)
        candidates = list((out / "runs").glob(label + "-*/report.json"))
        if len(candidates) != 1:
            raise RuntimeError(f"Ambiguous/missing checked receipt: {label}\n{process.stdout[-2000:]}\n{process.stderr[-2000:]}")
        receipt_path = candidates[0]
        receipt = json.loads(receipt_path.read_text())
        log = receipt_path.parent / "engine.log"
        if digest(log) != receipt["log_sha256"]:
            raise RuntimeError(f"Checked log hash differs: {label}")
        runs.append({"label": label, "group": group,
                     "report": str(receipt_path.relative_to(out)),
                     "log": str(log.relative_to(out)), "receipt": receipt})
        print(f"{label}: {receipt['reason']}; diagnostics={receipt['counts']}", flush=True)
        if process.returncode or not receipt.get("ok"):
            raise RuntimeError(f"Checked launch failed: {receipt_path}\n{process.stdout[-6000:]}\n{process.stderr[-2000:]}")

    checked("simulation", "r3-resource", "tests/test_resource_event_step.gd", "90 checks, 0 failed")
    checked("simulation", "r3-collision-order", "tests/test_collision_tie_order.gd", "17 checks, 0 failed")
    checked("simulation", "r3-collision-anchor", "collision_anchor_probe.gd", "COLLISION_ANCHOR_COMPLETE failures=0")
    checked("simulation", "r3-event-bound", "root_bound_probe.gd", "ROOT_BOUND_COMPLETE failures=0")
    checked("simulation", "r3-airship-restore", "restore_probe.gd", "RESTORE_PROBE_COMPLETE failures=0")
    checked("render", "r3-render-import")
    checked("render", "r3-lighting-off", "probe.gd", "lighting disabled probe: 1 check, 0 failed")
    checked("render", "r3-calibration-mixed", "calibration_probe.gd", "mixed workload probe: 1 check, 0 failed")
    checked("render", "r3-calibration-high", "calibration_high_probe.gd", "high workload probe: 1 check, 0 failed")
    checked("render", "r3-auto-control", "tests/test_auto_calibration.gd", "94 checks, 0 failed")
    checked("render", "r3-cloud-control", "tests/test_cloud_shadow_reorder.gd", "16 checks, 0 failed")
    checked("loading", "r3-loading", "loading_probe.gd", "PROBE_COMPLETE failures=0")
    checked("identity", "r3-identity", "probe.gd", "IDENTITY_PROBE_COMPLETE expected_observation=true")
    for name, expected in manifest["assets"].items():
        if digest(HERE / name) != expected:
            raise RuntimeError(f"Fixture asset changed during collection: {name}")
    if digest(engine, "sha512") != manifest["engine_sha512"]:
        raise RuntimeError("Engine changed during collection")
    result = {"format": "openrc-performance-audit-round3-results-v1",
              "collected_utc": datetime.now(timezone.utc).isoformat(),
              "source_commit": commit, "engine_sha512": manifest["engine_sha512"],
              "fixture_manifest_sha256": digest(HERE / "fixture_sources.json"),
              "runner_sha256": digest(Path(__file__)), "runs": runs,
              "limits": "Headless source fixtures. No GPU/FPS/native/release/full-game or latency qualification."}
    (out / "audit_results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Complete: {len(runs)} checked launches; {out / 'audit_results.json'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
