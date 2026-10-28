#!/usr/bin/env python3
"""Run the NK-3 oracle headless against the reference GDScript in app/ and print the evidence tables.

Build first with build.py (and build.py --mutant for the negative control). The oracle runs in the pinned Godot
editor through tools/godot/run_checked.py with `--path app`, loads the extension from tmp/native-kernel/ at run
time and writes its JSON there. `--mutant` runs the deliberately mutated library, which must FAIL the oracle.
"""

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TOOL_ROOT = ROOT / "tmp/native-kernel"
GODOT = ROOT / ".tools/Godot_v4.8-beta1_linux.x86_64"
HARNESS_OPTIONS = {
    "oracle.gd": set(), "stage_oracle.gd": set(),
    "trajectory.gd": {"ticks", "pairs", "warmup", "samples", "timing-cases", "skip-timing", "only", "repeats"},
    "fleet.gd": {"warmup", "samples"},
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_run_matches(report: dict, mutant: bool) -> bool:
    """An expected oracle failure is not permission to ignore engine errors or incomplete capture."""
    return (report.get("complete") is True and report.get("counts", {}).get("error") == 0
            and report.get("missing_required_text") == []
            and report.get("process_exit") == (1 if mutant else 0)
            and report.get("reason") == ("process_exit" if mutant else "passed")
            and (mutant or report.get("ok") is True))


def selected_binary(descriptor: Path) -> Path:
    config = configparser.ConfigParser(interpolation=None)
    config.read(descriptor)
    name = config["libraries"]["linux.x86_64"].strip('"')
    return ((ROOT / "app" / name.removeprefix("res://")) if name.startswith("res://")
            else descriptor.parent / name).resolve()


def validate_options(script: str, options: list[str]) -> None:
    seen = set()
    for option in options:
        name, separator, value = option.partition("=")
        if not separator or not value or name not in HARNESS_OPTIONS[script] or name in seen:
            raise ValueError(f"invalid or repeated option for {script}: {option}")
        seen.add(name)


def render(results: dict) -> str:
    lines = ["| Component | Compared | Identical | Finite ulp (max) | ±0 | NaN bits | Class | Shape |",
             "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |"]
    for name, c in sorted(results["components"].items()):
        lines.append(f"| {name} | {c['count']} | {c['identical']} | {c['finite_ulp']} ({c['max_ulp']}) | "
                     f"{c['zero_sign']} | {c['nan_bits']} | {c['class_mismatch']} | {c['shape']} |")
    lines += ["", "| Component call | Reference µs | Native via binding µs | Native kernel µs | × binding | × kernel |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for name, t in results["timing"].items():
        if "reference_us" not in t:
            continue
        kernel = t["native_kernel_us"]
        kernel_text = "—" if kernel is None else f"{kernel:.3f}"
        speed = "—" if kernel is None else f"{t['speedup_kernel']:.0f}"
        lines.append(f"| {name} | {t['reference_us']:.2f} | {t['native_binding_us']:.3f} | {kernel_text} | "
                     f"{t['speedup_binding']:.0f} | {speed} |")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--states", type=int, default=12000)
    parser.add_argument("--variant-states", type=int, default=1500)
    parser.add_argument("--timing-rounds", type=int, default=15)
    parser.add_argument("--seed", type=int, default=20261027)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--mutant", action="store_true", help="run the negative-control library; expect failure")
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--app-library", action="store_true",
                        help="use the installed res://native/kernel library (build.py --install-app) instead of tmp/")
    parser.add_argument("--render", type=Path, help="only render tables from an existing results JSON")
    parser.add_argument("--script", default="oracle.gd", choices=("oracle.gd", "stage_oracle.gd", "trajectory.gd", "fleet.gd"),
                        help="harness to run (all extend oracle.gd and print the same verdict line)")
    parser.add_argument("--option", action="append", default=[], metavar="NAME=VALUE",
                        help="extra harness option, passed as --NAME=VALUE (repeatable)")
    args = parser.parse_args()
    try:
        validate_options(args.script, args.option)
    except ValueError as error:
        parser.error(str(error))
    if args.render:
        print(render(json.loads(args.render.read_text(encoding="utf-8"))))
        return 0
    variant = "_mutant" if args.mutant else ""
    descriptor = TOOL_ROOT / f"openrc_native_kernel{variant}.gdextension"
    if args.app_library:
        if args.mutant:
            parser.error("--app-library never holds the mutant")
        if not (ROOT / "app/native/kernel/openrc_native_kernel.gdextension").is_file():
            raise SystemExit("No app install; run build.py --install-app first.")
        descriptor = "res://native/kernel/openrc_native_kernel.gdextension"
    elif not descriptor.is_file():
        raise SystemExit(f"Missing {descriptor}; run build.py{' --mutant' if args.mutant else ''} first.")
    descriptor_file = ROOT / "app/native/kernel/openrc_native_kernel.gdextension" if args.app_library else descriptor
    binary = selected_binary(descriptor_file)
    receipt_path = (ROOT / "app/native/kernel/build-receipt.json") if args.app_library \
        else TOOL_ROOT / f"build-receipt{variant}.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if args.app_library:
        receipt = receipt["platforms"]["linux"]
    binary_before = sha256(binary)
    engine_before = sha256(args.godot)
    if binary_before != receipt["binary_sha256"]:
        raise SystemExit("The descriptor's binary differs from its build receipt; rebuild/reinstall first.")
    harness_paths = [HERE / name for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "trajectory.gd",
                                              "fleet.gd", "run.py")]
    harness_paths += [ROOT / "app/sim/native_stage.gd", ROOT / "tools/godot/run_checked.py"]
    harness_sources = {str(path.relative_to(ROOT)): sha256(path) for path in harness_paths}
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    stem = {"oracle.gd": "results", "stage_oracle.gd": "stage", "trajectory.gd": "trajectory",
            "fleet.gd": "fleet"}[args.script]
    output = TOOL_ROOT / f"{stem}{variant}-{stamp}.json"
    marker = "NK3_ORACLE verdict=fail" if args.mutant else "NK3_ORACLE verdict=pass"
    checks = TOOL_ROOT / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    check_directory = Path(tempfile.mkdtemp(prefix=f"{stem}{variant}-", dir=checks))
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(check_directory),
               "--label", f"nk3-{stem}{variant}", "--timeout", str(args.timeout), "--require-text", marker, "--",
               str(args.godot), "--headless", "--path", str(ROOT / "app"), "--script", str(HERE / args.script), "--",
               f"--extension={descriptor}", f"--output={output}", f"--seed={args.seed}", f"--states={args.states}",
               f"--variant-states={args.variant_states}", f"--timing-rounds={args.timing_rounds}",
               *[f"--{option}" for option in args.option]]
    completed = subprocess.run(command, cwd=ROOT)
    if not output.is_file():
        raise SystemExit(f"Oracle wrote no results ({completed.returncode}); see {TOOL_ROOT / 'checks'}.")
    results = json.loads(output.read_text(encoding="utf-8"))
    reports = list(check_directory.glob("*/report.json"))
    checked = json.loads(reports[0].read_text()) if len(reports) == 1 else {}
    results["build_receipt"] = receipt
    results["binary_sha256_before"] = binary_before
    results["binary_sha256_after"] = sha256(binary)
    results["engine_sha256_before"] = engine_before
    results["engine_sha256_after"] = sha256(args.godot)
    results["harness_sources"] = harness_sources
    results["sources_after"] = {name: sha256(ROOT / "app" / name.removeprefix("res://"))
                                for name in results["sources"]}
    results["checked_run"] = checked
    unchanged = (results["binary_sha256_after"] == binary_before and results["engine_sha256_after"] == engine_before
                 and results["sources_after"] == results["sources"]
                 and all(sha256(ROOT / name) == digest for name, digest in harness_sources.items()))
    run_ok = checked_run_matches(checked, args.mutant) and completed.returncode == (1 if args.mutant else 0)
    results["run_valid"] = unchanged and run_ok
    output.write_text(json.dumps(results, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(render(results))
    print(f"\nverdict={results['verdict']} compared={results['total']['compared']} "
          f"identical={results['total']['identical']} results={output.relative_to(ROOT)}")
    expected = "fail" if args.mutant else "pass"
    if not results["run_valid"]:
        print("Run rejected: incomplete/erroring Godot process or sources/binary changed during the run.", file=sys.stderr)
    detected_difference = not args.mutant or results["total"]["mismatched"] > 0
    return 0 if results["verdict"] == expected and results["run_valid"] and detected_difference else 1


if __name__ == "__main__":
    raise SystemExit(main())
