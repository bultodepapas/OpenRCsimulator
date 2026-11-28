#!/usr/bin/env python3
"""Record audit component counterexamples; never qualifies an installed backend."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = "8d4169f8febfd7d78a028eaa817414217a54f24b"
KINDS = {
    "fixed-wing": ("aerospace_probe.py", "actual native header components"),
    "helicopter": ("helicopter_probe.cpp", "actual native header components"),
    "multirotor": ("drone_probe.py", "independent equations and stock data"),
    "combustion-turbine": ("propulsion_probe.py", "actual native header components and independent scalar integration"),
    "electric": ("electric_probe.py", "actual native header components and stock data"),
    "native-engine": ("native_engine_probe.cpp", "actual native header work/allocation counters"),
    "mechanics": ("mechanics_probe.py", "actual ground native header and independent collision geometry"),
    "mathematics": ("mathematics_probe.py", "actual native integration headers and independent airship scalar laws"),
    "flight-controls": ("controls_probe.py", "independent sampled control equations and actual native actuator components"),
}


def stamp():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command):
    p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=180)
    return {"command": [str(x) for x in command], "returncode": p.returncode,
            "stdout": p.stdout, "stderr": p.stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new JSON receipt path")
    parser.add_argument("--case", choices=KINDS, action="append")
    args = parser.parse_args()
    if args.out.exists():
        parser.error("refusing to replace an existing receipt")
    receipt = {
        "schema": "openrc-physics-audit-components-v1", "audited_base": BASE,
        "started_utc": stamp(), "platform": platform.platform(),
        "compiler": run(["c++", "--version"])["stdout"].splitlines()[0],
        "scope": "Component evidence only. GCC 14.2 is not the qualified Linux GCC 13.3 package. No installed native backend or target latency claim.",
        "counterexample_interpretation": "A successful witness can confirm baseline discrepancy; it is not a repaired-behavior pass.",
        "cases": [],
    }
    with tempfile.TemporaryDirectory(prefix="openrc-audit-components-") as work:
        for name in args.case or list(KINDS):
            filename, scope = KINDS[name]
            source = HERE / "probes" / filename
            row = {"name": name, "scope": scope, "source": str(source.relative_to(ROOT)),
                   "source_sha256": sha(source), "steps": []}
            if source.suffix == ".cpp":
                exe = Path(work) / name
                command = ["c++", "-std=c++17", "-O2", "-fno-fast-math", "-ffp-contract=off",
                           "-I", str(ROOT / "research/native-kernel/src"), str(source), "-o", str(exe)]
                row["steps"].append(run(command))
                if row["steps"][-1]["returncode"] == 0:
                    row["steps"].append(run([str(exe)]))
            else:
                adjacent = source.with_suffix(".cpp")
                if adjacent.exists():
                    row["adjacent_cpp_sha256"] = sha(adjacent)
                arguments = ["--repo", str(ROOT)] if name == "mathematics" else [str(ROOT)]
                if name == "flight-controls":
                    arguments.append("--native")
                row["steps"].append(run([sys.executable, str(source), *arguments]))
            row["ok"] = all(s["returncode"] == 0 for s in row["steps"])
            receipt["cases"].append(row)
            print(f"{name}: {'PASS' if row['ok'] else 'FAIL'} ({scope})", flush=True)
    receipt["finished_utc"] = stamp()
    receipt["ok"] = all(row["ok"] for row in receipt["cases"])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
