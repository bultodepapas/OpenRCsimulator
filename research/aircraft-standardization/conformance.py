#!/usr/bin/env python3
"""Run aircraft authoring conformance and optional exact flight/package comparisons."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:|^FAIL\b", re.MULTILINE)


def fingerprint() -> dict[str, str]:
    paths = [*Path(APP / "physics").rglob("*.gd"), *Path(APP / "sim").glob("*.gd"),
             *Path(APP / "input").glob("*.gd"), *Path(APP / "data/aircraft").glob("*.json"),
             *Path(APP / "data/glow").glob("*.json")]
    return {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Pinned Godot executable")
    parser.add_argument("--out", required=True, type=Path, help="Evidence directory (existing files are overwritten)")
    parser.add_argument("--baseline", type=Path, help="Previously captured fleet.json, same platform/tool build")
    parser.add_argument("--contact-baseline", type=Path, help="Previously captured contacts.json, same physical sources/platform")
    parser.add_argument("--parse-all", action="store_true", help="Also parse every current app GDScript")
    parser.add_argument("--package", action="store_true", help="Export the current Windows preset PCK and inspect its aircraft")
    parser.add_argument("--models-only", action="store_true", help="Model/package conformance without the focused physics suites")
    args = parser.parse_args()
    godot = args.godot.resolve()
    if not godot.is_file():
        parser.error("--godot does not name a file")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, OPENRC_TEST_GODOT=str(godot))
    commands: list[dict] = []

    def run(name: str, argv: list[str], timeout: int = 180) -> bool:
        start = time.monotonic()
        try:
            process = subprocess.run(argv, cwd=ROOT, env=environment, capture_output=True,
                                     text=True, encoding="utf-8", errors="replace", timeout=timeout)
            log = process.stdout + process.stderr
            code = process.returncode
        except subprocess.TimeoutExpired as exc:
            def decode(value):
                return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")
            log = decode(exc.stdout) + decode(exc.stderr) + "\nTIMEOUT\n"
            code = 124
        path = out / (name + ".log")
        path.write_text(log, encoding="utf-8", newline="\n")
        ok = code == 0 and not ERROR.search(log)
        commands.append({"name": name, "argv": argv, "exit_code": code, "ok": bool(ok),
                         "seconds": time.monotonic() - start,
                         "log": path.name, "log_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        if not name.startswith("parse-") or not ok:
            print(f"{'PASS' if ok else 'FAIL'} {name}", flush=True)
        return bool(ok)

    def engine(*arguments: str) -> list[str]:
        return [str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy", *arguments]

    ok = run("import", engine("--import"), 300)
    python_checks = [
        ("schema", "research/aircraft-standardization/build_schema.py", ["--check"]),
        ("parameters", "research/aircraft-standardization/parameter_register.py", ["--check"]),
        ("migration", "research/aircraft-standardization/migrate.py", ["--check-known"]),
        ("modules-python", "research/aircraft-standardization/test_modules.py", []),
        ("models-current", "research/aircraft-standardization/build_models.py", ["--check"]),
        ("models-python", "research/aircraft-standardization/test_models.py", []),
        ("descriptors-current", "research/aircraft-editor/build_descriptors.py", ["--check"]),
        ("descriptor-checkout", "research/aircraft-editor/test_descriptor_checkout.py", []),
    ]
    for name, path, arguments in python_checks:
        ok = run(name, [sys.executable, str(ROOT / path), *arguments]) and ok
    if args.parse_all:
        scripts = sorted(p for p in APP.rglob("*.gd") if ".godot" not in p.parts)
        def parse(script: Path):
            name = "parse-" + "-".join(script.relative_to(APP).parts).replace(".gd", "")
            return run(name, engine("--check-only", "--script", "res://" + script.relative_to(APP).as_posix()))
        with ThreadPoolExecutor(max_workers=3) as executor:
            parsed = all(list(executor.map(parse, scripts)))
            ok = parsed and ok
        print(f"{'PASS' if parsed else 'FAIL'} parsed {len(scripts)} scripts", flush=True)
    model_tests = ["aircraft_package_proofs", "aircraft_modules", "aircraft_model_manifest", "aircraft_render_contract", "workshop_descriptor"]
    physics_tests = ["control_surfaces", "aircraft_contact_contract", "aircraft_contact_events", "aircraft_contact_session",
                     "landscape_collision_session", "scenery_damage_session", "lake_session", "crash_snapshot",
                     "aircraft_propulsion_runtime", "aircraft_contract",
                     "aircraft_data", "controls", "servo", "checkpoint", "checkpoint_integrity", "session_guards",
                     "contact_policy", "soft_contacts", "soft_contact_feedback", "prop_strike", "prop_strike_feedback",
                     "electric_session", "electric_battery_session", "electric_event_localization",
                     "glow_session", "glow_lifecycle", "glow_trace", "shaft_coupled", "turbine_continuous", "wheel_session",
                     "workshop_compiler", "workshop_trial", "workshop_store", "workshop_integration", "aircraft_catalog"]
    for test in model_tests + ([] if args.models_only else physics_tests):
        ok = run(test, engine("--script", "res://tests/test_" + test + ".gd"), 600) and ok
    preflight = ROOT / "research/aircraft-standardization/preflight.gd"
    ok = run("preflight", engine("--script", str(preflight), "--", str(out / "preflight.json")), 600) and ok
    comparison = None
    contact_comparison = None
    if not args.models_only:
        before = fingerprint()
        probe = ROOT / "research/aircraft-standardization/fleet_probe.gd"
        flight_ok = run("fleet", engine("--script", str(probe), "--", str(out / "fleet.json")))
        drift = before != fingerprint()
        comparison = {"source_drift_during_probe": drift, "source_sha256": before}
        ok = flight_ok and not drift and ok
        if args.baseline and flight_ok:
            baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
            candidate = json.loads((out / "fleet.json").read_text(encoding="utf-8"))
            comparison["exact_baseline_match"] = baseline == candidate
            comparison["baseline_sha256"] = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
            ok = baseline == candidate and ok
            print("PASS exact flight baseline" if baseline == candidate else "FAIL exact flight baseline", flush=True)
        before_contacts = fingerprint()
        contacts_ok = run("contacts", engine("--script", str(ROOT / "research/aircraft-standardization/contact_probe.gd"),
                                             "--", str(out / "contacts.json")))
        contact_drift = before_contacts != fingerprint()
        contact_comparison = {"source_drift_during_probe": contact_drift, "source_sha256": before_contacts}
        ok = contacts_ok and not contact_drift and ok
        if args.contact_baseline and contacts_ok:
            baseline = json.loads(args.contact_baseline.read_text(encoding="utf-8"))
            candidate = json.loads((out / "contacts.json").read_text(encoding="utf-8"))
            contact_comparison["exact_baseline_match"] = baseline == candidate
            contact_comparison["baseline_sha256"] = hashlib.sha256(args.contact_baseline.read_bytes()).hexdigest()
            ok = baseline == candidate and ok
            print("PASS exact contact baseline" if baseline == candidate else "FAIL exact contact baseline", flush=True)
    if args.package:
        pack = out / "aircraft-contract.pck"
        package_ok = run("export-pack", engine("--export-pack", "Windows", str(pack)), 600)
        ok = package_ok and ok
        if package_ok:
            # Do not use --path app: the pack must supply every runtime dependency.
            ok = run("package-preflight", [str(godot), "--headless", "--audio-driver", "Dummy",
                      "--main-pack", str(pack), "--script", str(preflight), "--", str(out / "package-preflight.json")], 600) and ok
    report = {"format": "openrc-aircraft-verification v1", "ok": bool(ok),
              "commands": sorted(commands, key=lambda row: row["name"]), "flight_comparison": comparison,
              "contact_comparison": contact_comparison}
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
