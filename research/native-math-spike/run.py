#!/usr/bin/env python3
"""Run the NK-1 math identity spike headless and print the results table.

Copies app/physics/math3d.gd into the standalone project (git-ignored), runs spike.gd in the
pinned Godot editor through tools/godot/run_checked.py, keeps the JSON under tmp/native-math-spike/.
Build the extension first with build.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROJECT = HERE / "project"
TOOL_ROOT = ROOT / "tmp/native-math-spike"
LIBRARY = TOOL_ROOT / "lib/libopenrc_math_spike.so"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fmt_ns(entry) -> str:
    return "—" if not entry else f"{entry['median_ns']:.1f}"


def fmt_cmp(entry) -> str:
    if not entry:
        return "—"
    text = f"{entry['identical']}/{entry['count']}"
    extra = []
    if entry["finite_diff"]:
        extra.append(f"{entry['finite_diff']} finite, max {entry['max_ulp']} ulp")
    if entry["class_mismatch"]:
        extra.append(f"{entry['class_mismatch']} NaN/inf class")
    if entry["zero_sign_only"]:
        extra.append(f"{entry['zero_sign_only']} ±0")
    if entry["nan_payload_only"]:
        extra.append(f"{entry['nan_payload_only']} NaN bits")
    return text + (f" ({'; '.join(extra)})" if extra else "")


def table(results: dict) -> str:
    lines = [
        "| Function | Inputs (random + edge) | GDScript = `std::` | GDScript = `UtilityFunctions` | GDScript = `math3d` | "
        "ns GD direct | ns GD `math3d` | ns `std::` | ns Utility |",
        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |",
    ]
    for row in results["rows"]:
        lines.append(
            f"| {row['fn']} | {row['random_count']} + {row['edge_count']} | {fmt_cmp(row['std'])} | "
            f"{fmt_cmp(row['utility'])} | {fmt_cmp(row.get('math3d'))} | {fmt_ns(row['ns_gd_direct'])} | "
            f"{fmt_ns(row.get('ns_gd_math3d'))} | {fmt_ns(row['ns_std'])} | {fmt_ns(row['ns_utility'])} |"
        )
    lines += ["", "| Compiler-rewrite probe (`std::`) | GDScript reference | Identical |", "| --- | --- | --- |"]
    references = {
        "sincos_sin": "sin(x)", "sincos_cos": "cos(x)", "pow_lit_2": "pow(x, 2.0)", "pow_lit_0.5": "pow(x, 0.5)",
        "pow_lit_3.5": "pow(x, 3.5)", "pow_lit_1/1.4": "pow(x, 1.0 / 1.4)",
    }
    for row in results["variants"]:
        lines.append(f"| {row['variant']} | `{references.get(row['variant'], '?')}` | {fmt_cmp(row)} |")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=1_000_000, help="random inputs per function")
    parser.add_argument("--batches", type=int, default=5, help="timed batches after one warmup pass")
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--render", type=Path, help="only render the table from an existing results JSON")
    args = parser.parse_args()
    if args.render:
        print(table(json.loads(args.render.read_text(encoding="utf-8"))))
        return 0
    if not LIBRARY.is_file():
        raise SystemExit(f"Missing {LIBRARY}; run research/native-math-spike/build.py first.")
    if subprocess.run(["pgrep", "-f", r"^\S*Godot_v"], capture_output=True).returncode == 0:
        print("warning: another Godot process is running; timings share the CPU", file=sys.stderr)
    math3d = ROOT / "app/physics/math3d.gd"
    (PROJECT / "physics").mkdir(exist_ok=True)
    shutil.copy2(math3d, PROJECT / "physics/math3d.gd")
    godot = subprocess.run([str(ROOT / "app/get-godot.sh")], check=True, text=True, capture_output=True).stdout.strip()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = TOOL_ROOT / f"results-{stamp}.json"
    command = [
        sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--timeout", str(args.timeout),
        "--out-dir", str(TOOL_ROOT / "checks"), "--label", "nk1-math-spike",
        "--require-text", "OPENRC_MATH_SPIKE_OK", "--",
        godot, "--headless", "--path", str(PROJECT), "--script", "res://spike.gd", "--",
        f"--out={out}", f"--count={args.count}", f"--batches={args.batches}",
    ]
    status = subprocess.run(command).returncode
    if status != 0 or not out.is_file():
        raise SystemExit(f"Spike run failed (exit {status}).")
    results = json.loads(out.read_text(encoding="utf-8"))
    receipt_path = TOOL_ROOT / "build-receipt.json"
    results["identity"] = {
        "godot_binary_sha256": sha256_file(Path(godot)),
        "library_sha256": sha256_file(LIBRARY),
        "build_receipt": json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.is_file() else None,
        "math3d_sha256": sha256_file(math3d),
        "spike_gd_sha256": sha256_file(PROJECT / "spike.gd"),
    }
    out.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(out, TOOL_ROOT / "results-latest.json")
    print(json.dumps({"build_info": results["build_info"], "identity": results["identity"]}, indent=2))
    print(table(results))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
