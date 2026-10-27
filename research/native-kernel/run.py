#!/usr/bin/env python3
"""Run the NK-3 oracle headless against the reference GDScript in app/ and print the evidence tables.

Build first with build.py (and build.py --mutant for the negative control). The oracle runs in the pinned Godot
editor through tools/godot/run_checked.py with `--path app`, loads the extension from tmp/native-kernel/ at run
time and writes its JSON there. `--mutant` runs the deliberately mutated library, which must FAIL the oracle.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TOOL_ROOT = ROOT / "tmp/native-kernel"
GODOT = ROOT / ".tools/Godot_v4.8-beta1_linux.x86_64"


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
    parser.add_argument("--render", type=Path, help="only render tables from an existing results JSON")
    args = parser.parse_args()
    if args.render:
        print(render(json.loads(args.render.read_text(encoding="utf-8"))))
        return 0
    variant = "_mutant" if args.mutant else ""
    descriptor = TOOL_ROOT / f"openrc_native_kernel{variant}.gdextension"
    if not descriptor.is_file():
        raise SystemExit(f"Missing {descriptor}; run build.py{' --mutant' if args.mutant else ''} first.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = TOOL_ROOT / f"results{variant}-{stamp}.json"
    marker = "NK3_ORACLE verdict=fail" if args.mutant else "NK3_ORACLE verdict=pass"
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(TOOL_ROOT / "checks"),
               "--label", f"nk3-oracle{variant}", "--timeout", str(args.timeout), "--require-text", marker, "--",
               str(args.godot), "--headless", "--path", str(ROOT / "app"), "--script", str(HERE / "oracle.gd"), "--",
               f"--extension={descriptor}", f"--output={output}", f"--seed={args.seed}", f"--states={args.states}",
               f"--variant-states={args.variant_states}", f"--timing-rounds={args.timing_rounds}"]
    completed = subprocess.run(command, cwd=ROOT)
    if not output.is_file():
        raise SystemExit(f"Oracle wrote no results ({completed.returncode}); see {TOOL_ROOT / 'checks'}.")
    results = json.loads(output.read_text(encoding="utf-8"))
    receipt_path = TOOL_ROOT / f"build-receipt{variant}.json"
    results["build_receipt"] = json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.is_file() else None
    output.write_text(json.dumps(results, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(render(results))
    print(f"\nverdict={results['verdict']} compared={results['total']['compared']} "
          f"identical={results['total']['identical']} results={output.relative_to(ROOT)}")
    expected = "fail" if args.mutant else "pass"
    # run_checked's own non-zero exit is expected for the mutant (the oracle exits 1 on a failed verdict).
    return 0 if results["verdict"] == expected and (args.mutant or completed.returncode == 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
