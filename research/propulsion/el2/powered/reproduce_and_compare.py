#!/usr/bin/env python3
"""Create isolated EL2a control/instrumented app copies and compare exact checkpoints."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPRO: Path
DEFAULT_APP = ROOT.parents[3] / "app"
PATCH_FILE = ROOT / "instrument-flight-session.patch"
PROBE = ROOT / "powered_parity_probe.gd"
IGNORED = {".godot", "captures"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], *, cwd: Path | None = None, log_path: Path | None = None) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False, timeout=300)
    output = result.stdout
    if log_path is not None:
        log_path.write_text(output)
    if result.returncode:
        raise RuntimeError(f"command exited {result.returncode}: {' '.join(command)}\n{output[-8000:]}")
    if re.search(r"(?m)^(?:SCRIPT |SHADER )?ERROR:", output):
        raise RuntimeError(f"engine error: {' '.join(command)}\n{output[-8000:]}")
    return output


def ignored(directory: str, names: list[str]) -> set[str]:
    return set(names) & IGNORED


def file_hashes(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if any(part in IGNORED for part in relative.parts):
            continue
        result[relative.as_posix()] = sha256(path.read_bytes())
    return result


def compare_mode_outputs() -> dict:
    control_dir = REPRO / "control"
    measured_dir = REPRO / "instrumented"
    control = json.loads((control_dir / "results.json").read_text())
    measured = json.loads((measured_dir / "results.json").read_text())
    if control["mode"] != "control" or control["instrumented"]:
        raise AssertionError("control run metadata is wrong")
    if measured["mode"] != "instrumented" or not measured["instrumented"]:
        raise AssertionError("instrumented run metadata is wrong")
    if control["failures"] or measured["failures"]:
        raise AssertionError(f"probe failures: {control['failures']} {measured['failures']}")
    if len(control["rows"]) != 8 or len(measured["rows"]) != 8:
        raise AssertionError("expected eight cases in each run")

    crows = {(r["pack"], r["hz"]): r for r in control["rows"]}
    irows = {(r["pack"], r["hz"]): r for r in measured["rows"]}
    if crows.keys() != irows.keys():
        raise AssertionError("control/instrumented case sets differ")
    results = []
    for key in sorted(crows):
        c, i = crows[key], irows[key]
        if not c["ok"] or not i["ok"]:
            raise AssertionError(f"case {key} failed an accepted-state invariant")
        if c["event_tick"] != i["event_tick"]:
            raise AssertionError(f"case {key} exhausted on a different tick")
        for field in ("event_start_charge_c", "configured_initial_charge_c", "end_time_s", "steps"):
            if c[field] != i[field]:
                raise AssertionError(f"case {key} differs in {field}")

        seed_c = (control_dir / c["seed_checkpoint_file"]).read_bytes()
        seed_i = (measured_dir / i["seed_checkpoint_file"]).read_bytes()
        if seed_c != seed_i:
            raise AssertionError(f"case {key} did not start from identical checkpoint bytes")
        endpoint_c = (control_dir / c["checkpoint_file"]).read_bytes()
        endpoint_i = (measured_dir / i["checkpoint_file"]).read_bytes()
        if endpoint_c != endpoint_i:
            first_difference = next((n for n, (a, b) in enumerate(zip(endpoint_c, endpoint_i)) if a != b),
                                     min(len(endpoint_c), len(endpoint_i)))
            raise AssertionError(f"case {key} endpoint checkpoint bytes differ at byte {first_difference}; lengths {len(endpoint_c)}/{len(endpoint_i)}")
        events = i["events"]
        if len(events) != 1 or events[0]["type"] != "battery_exhausted":
            raise AssertionError(f"instrumented case {key} lacks a unique exhaustion event")
        results.append({
            "pack": key[0], "hz": key[1], "event_tick": i["event_tick"],
            "seed_checkpoint_bytes": len(seed_c), "seed_checkpoint_sha256": sha256(seed_c),
            "endpoint_checkpoint_bytes": len(endpoint_c), "endpoint_checkpoint_sha256": sha256(endpoint_c),
            "checkpoint_bytes_identical": True,
            "event": events[0],
            "event_step_usec": i["event_step_usec"],
            "event_tick_wall_usec_instrumented": i["event_tick_wall_usec"],
            "event_tick_wall_usec_control": c["event_tick_wall_usec"],
        })

    control_tree = file_hashes(REPRO / "control" / "app")
    instrumented_tree = file_hashes(REPRO / "instrumented" / "app")
    if control_tree.keys() != instrumented_tree.keys():
        raise AssertionError("isolated app copies have different non-cache file sets")
    changed = sorted(path for path in control_tree if control_tree[path] != instrumented_tree[path])
    if changed != ["sim/flight_session.gd"]:
        raise AssertionError(f"instrumentation changed unexpected copied app paths: {changed}")
    return {
        "format": "el2-powered-session-parity-v1",
        "control_app": str(REPRO / "control" / "app"),
        "instrumented_app": str(REPRO / "instrumented" / "app"),
        "probe": str(PROBE),
        "instrumentation_patch": str(PATCH_FILE),
        "changed_app_paths": changed,
        "cases_compared": len(results),
        "all_seed_checkpoints_identical": True,
        "all_endpoint_checkpoint_bytes_identical": True,
        "rows": results,
    }


def main() -> int:
    global REPRO
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, help="empty output directory; default: a new temporary directory")
    args = parser.parse_args()
    source = args.source_app.resolve()
    godot = args.godot.resolve()
    if not source.is_dir() or not (source / "project.godot").is_file():
        raise FileNotFoundError(f"not a Godot project: {source}")
    if not godot.is_file():
        raise FileNotFoundError(f"pinned Godot binary is missing: {godot}")
    if not PATCH_FILE.is_file() or not PROBE.is_file():
        raise FileNotFoundError("instrumentation patch or GDScript probe is missing")

    version = run([str(godot), "--version"]).strip()
    if version != "4.7.2.stable.official.ed1daf0bf":
        raise RuntimeError(f"unexpected Godot version: {version}")
    REPRO = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="openrc-el2-powered-"))
    if REPRO.is_relative_to(source):
        raise ValueError("output must be outside the source app to avoid recursive copying")
    if REPRO.exists() and any(REPRO.iterdir()):
        raise FileExistsError(f"output directory must be empty: {REPRO}")
    REPRO.mkdir(parents=True, exist_ok=True)
    copies = {mode: REPRO / mode / "app" for mode in ("control", "instrumented")}
    for mode, destination in copies.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, destination, ignore=ignored)
        import_log = REPRO / mode / "import.log"
        run([str(godot), "--headless", "--editor", "--path", str(destination), "--import", "--quit"], log_path=import_log)

    patch_run = subprocess.run(["patch", "-p1", "--batch", "--forward", "-i", str(PATCH_FILE)],
                               cwd=copies["instrumented"], text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, check=False, timeout=30)
    (REPRO / "instrumentation-patch.log").write_text(patch_run.stdout)
    if patch_run.returncode:
        raise RuntimeError(f"could not apply instrumentation patch:\n{patch_run.stdout}")

    for mode, app in copies.items():
        command = [str(godot), "--headless", "--path", str(app), "--script", str(PROBE), "--", str(REPRO)]
        if mode == "instrumented":
            command.append("--instrumented")
        run(command, log_path=REPRO / mode / "probe.log")

    version_info = {
        "source_app": str(source), "godot_binary": str(godot), "godot_version": version,
        "excluded_from_copies": sorted(IGNORED),
        "instrumentation_patch_sha256": sha256(PATCH_FILE.read_bytes()),
        "probe_sha256": sha256(PROBE.read_bytes()),
        "runner_sha256": sha256(Path(__file__).read_bytes()),
        "verifier_sha256": sha256((ROOT / "verify_powered_exhaustion.py").read_bytes()),
        "source_sha256": {str(path.relative_to(source)): sha256(path.read_bytes())
                          for folder in ("sim", "physics", "data/aircraft")
                          for path in (source / folder).iterdir() if path.suffix in (".gd", ".json")},
    }
    (REPRO / "source.json").write_text(json.dumps(version_info, indent=2) + "\n")
    parity = compare_mode_outputs()
    (REPRO / "parity.json").write_text(json.dumps(parity, indent=2) + "\n")
    run([sys.executable, str(ROOT / "verify_powered_exhaustion.py"),
         "--results", str(REPRO / "instrumented" / "results.json"),
         "--output", str(REPRO / "verified.json")], log_path=REPRO / "verification.log")
    print(f"PASS: {parity['cases_compared']} control/instrumented cases; all seed checkpoint bytes and all complete endpoint checkpoint bytes are identical.")
    print(f"Only changed copied app file: {', '.join(parity['changed_app_paths'])}")
    print("pack  Hz  endpoint bytes  SHA-256  event tick  instrumented BatteryStep ms  control tick ms  instrumented tick ms")
    for row in parity["rows"]:
        print(f"{row['pack']:>2} {row['hz']:4d} {row['endpoint_checkpoint_bytes']:14d} "
              f"{row['endpoint_checkpoint_sha256']} {row['event_tick']:11d} "
              f"{row['event_step_usec']/1000:26.3f} {row['event_tick_wall_usec_control']/1000:15.3f} "
              f"{row['event_tick_wall_usec_instrumented']/1000:21.3f}")
    print(f"Evidence: {REPRO}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise
