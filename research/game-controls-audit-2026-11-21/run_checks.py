#!/usr/bin/env python3
"""Replay the bounded Linux/headless controls audit through OpenRC's checked runner.

Uses unchanged production scripts. Each process has isolated user data. No test
result qualifies physical controllers, a rendered flight, or another platform.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
from datetime import datetime, timezone

ENGINE = "4.8.beta2.official.cafc17a19"
ENGINE_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
BASELINE = "57abea025f62b20233ca281d58d2acbee4ab8b8e"
SUITES = {
    "test_rc_input.gd": "44 checks, 0 failed",
    "test_rc_calibration.gd": "49 checks, 0 failed",
    "test_controller_profile.gd": "Controller profile:",
    "test_controller_profile_hardening.gd": "Controller profile hardening:",
    "test_controller_store.gd": "Controller profile store:",
    "test_controller_audit_concurrency.gd": "Controller audit concurrency:",
    "test_controller_registry.gd": "Controller registry:",
    "test_controller_auto_defaults.gd": "Controller automatic defaults:",
    "test_controller_external_audit.gd": "External controller audit:",
    "test_controller_audit_shell.gd": "controller audit shell:",
    "test_controller_audit_vehicle_quad.gd": "vehicle quad audit:",
    "test_controller_audit_vehicle_airship.gd": "vehicle airship audit:",
    "test_controls_setup_p0.gd": "all controls setup P0 checks passed",
    "test_controls_assign.gd": "Controls assign:",
    "test_controls_workspace.gd": "Controls workspace:",
    "test_setup_assistant_wiring.gd": "setup assistant wiring:",
    "test_calibration_view.gd": "calibration view:",
    "test_controller_pause_recovery.gd": "Controller pause recovery:",
    "test_controller_recovery_focus.gd": "controller recovery focus:",
    "test_controller_routing_audit.gd": "controller routing audit:",
    "test_mr_controller_authority.gd": "controller authority:",
    "test_controller_menu.gd": "Controller menu:",
    "test_controller_conditioning.gd": "Controller conditioning:",
    "test_controller_calibration_session.gd": "Controller calibration session:",
    "test_controller_actions.gd": "all controller action checks passed",
    "test_controller_ground.gd": "Ground controller integration:",
    "test_controller_car.gd": "Car controller audit:",
}


def digest(path: Path, algorithm: str = "sha256") -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def generated_uids(root: Path) -> dict:
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "-z", "--", "app"]
    ).decode().split("\0")
    paths = [name for name in paths if name]
    if any(not name.endswith(".uid") for name in paths):
        raise ValueError("Unexpected untracked app files; review before running.")
    return {name: digest(root / name) for name in paths}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--out", type=Path, required=True, help="new output directory")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--jobs", type=int, choices=(1,), default=1,
                        help="serial only in this checkout; concurrent suites need separate frozen checkouts")
    parser.add_argument("--script", action="append", choices=tuple(SUITES))
    parser.add_argument("--skip-import", action="store_true", help="only after a successful import of this tree")
    args = parser.parse_args()
    root, out = args.repo.resolve(), args.out.resolve()
    if platform.system() != "Linux":
        parser.error("This retained runner qualifies Linux only; use the repository's native test route elsewhere.")
    engine = args.godot.resolve() if args.godot else Path(subprocess.check_output(["bash", str(root / "app/get-godot.sh")], cwd=root, text=True).strip())
    if digest(engine, "sha512") != ENGINE_SHA512 or subprocess.check_output([str(engine), "--version"], text=True).strip() != ENGINE:
        parser.error("Engine identity differs from the audited official Linux executable.")
    if git(root, "status", "--porcelain", "--untracked-files=no", "--", "app"):
        parser.error("Tracked production files have changes; use a stable reviewed tree.")
    try:
        prepared_uids = generated_uids(root)
    except ValueError as error:
        parser.error(str(error))
    out.mkdir(parents=True, exist_ok=False)
    selected = args.script or list(SUITES)
    identity = {
        "schema": "openrc-controls-audit-run-v1", "baseline": BASELINE,
        "head": git(root, "rev-parse", "HEAD"), "app_tree": git(root, "rev-parse", "HEAD:app"),
        "engine": ENGINE, "engine_sha512": digest(engine, "sha512"),
        "platform": platform.platform(), "started_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "Linux headless, Dummy audio, synthetic input, unchanged production scripts",
        "generated_untracked_uids": prepared_uids,
        "scheduling": "serial suites in one stable checkout",
        "suite_sha256": {s: digest(root / "app/tests" / s) for s in selected},
    }
    (out / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")

    def run(label: str, arguments: list[str], marker: str = "", timeout: int = 90) -> dict:
        location = out / label
        location.mkdir()
        env = os.environ.copy()
        for name, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            env[name] = str(location / "user" / folder)
        command = [sys.executable, str(root / "tools/godot/run_checked.py"), "--label", label,
                   "--out-dir", str(location / "checked"), "--timeout", str(timeout)]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--path", str(root / "app"), "--audio-driver", "Dummy", *arguments]
        with (location / "console.txt").open("w") as output:
            completed = subprocess.run(command, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
        reports = list((location / "checked").glob("*/report.json"))
        if len(reports) != 1:
            return {"script": label, "ok": False, "reason": "missing_or_ambiguous_checked_receipt", "returncode": completed.returncode}
        report_path = reports[0]
        report = json.loads(report_path.read_text())
        log_path = report_path.parent / "engine.log"
        log = log_path.read_text(errors="replace")
        summaries = [line for line in log.splitlines() if re.search(r"checks.*(?:failed|failures|passed)|all .* checks passed", line)]
        result = {"script": label, "ok": bool(report.get("ok")) and completed.returncode == 0,
                  "reason": report.get("reason"), "returncode": completed.returncode,
                  "complete": report.get("complete"), "counts": report.get("counts"),
                  "elapsed_seconds": report.get("elapsed_seconds"), "completion": summaries[-4:],
                  "report": str(report_path.relative_to(out)), "report_sha256": digest(report_path),
                  "log": str(log_path.relative_to(out)), "log_sha256": digest(log_path),
                  "diagnostics": report.get("diagnostics", [])}
        print(json.dumps({k: result[k] for k in ("script", "ok", "reason", "counts", "completion")}), flush=True)
        return result

    results = []
    if not args.skip_import:
        imported = run("import", ["--import"], timeout=180)
        results.append(imported)
        if not imported["ok"]:
            (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            return 1
        if git(root, "status", "--porcelain", "--untracked-files=no", "--", "app"):
            (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print("Import generated tracked metadata changes. Review them, restore only owned changes, then repeat the checked import until cache and committed mappings agree.", file=sys.stderr)
            return 1
        prepared_uids = generated_uids(root)
        identity["generated_untracked_uids"] = prepared_uids
        (out / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    results += [run(name, ["--script", "res://tests/" + name], SUITES[name]) for name in selected]
    unchanged = not git(root, "status", "--porcelain", "--untracked-files=no", "--", "app")
    try:
        uids_stable = generated_uids(root) == prepared_uids
    except ValueError:
        uids_stable = False
    (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    summary = {"passed": sum(bool(r["ok"]) for r in results), "failed": sum(not r["ok"] for r in results),
               "production_unchanged": unchanged, "generated_uids_stable": uids_stable,
               "results": "results.json"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary), flush=True)
    return 0 if unchanged and uids_stable and all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
