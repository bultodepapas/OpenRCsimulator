#!/usr/bin/env python3
"""Record the refresh's independent acceptance controls, without launching an engine.

These witnesses challenge proposed gates and reproduce selected source equations.
They are not repaired-behavior, installed-package, physical, or performance tests.
"""

import argparse
import hashlib
import importlib.metadata
import json
import platform
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
AUDIT = Path(__file__).resolve().parent
PROBES = AUDIT / "probes"
CASES = ("drone", "propulsion", "electric", "mechanics", "mathematics", "verifier")


def identity(path):
    return {"path": path.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def command(args):
    completed = subprocess.run(list(map(str, args)), cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return {"command": list(map(str, args)), "returncode": completed.returncode,
            "stdout": completed.stdout, "stderr": completed.stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--case", choices=CASES, action="append")
    args = parser.parse_args()
    output = args.out.resolve()
    if output.exists():
        parser.error("--out must name a new receipt; historical evidence is immutable")

    versions = {}
    for package in ("numpy", "scipy"):
        try:
            versions[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            versions[package] = None
    record = {
        "schema": "openrc-physics-audit-refresh-oracles-v1",
        "scope": "Independent equations/manufactured geometry plus the electric native-header component; no engine launch, admitted package, hardware measurement or performance claim.",
        "git_head": command(["git", "rev-parse", "HEAD"])["stdout"].strip(),
        "platform": platform.platform(), "python": sys.version,
        "packages": versions, "compiler": command(["g++", "--version"]),
        "runner": identity(Path(__file__).resolve()), "cases": [],
    }
    for name in args.case or CASES:
        suffix = ".cpp" if name == "mathematics" else ".py"
        probe = PROBES / (name + "_acceptance_oracles" + suffix)
        inputs = [probe]
        if name in ("drone", "electric"):
            inputs.append(ROOT / "app/data/multirotors/openrc-fpv5-x1.json")
        if name == "propulsion":
            inputs.extend(ROOT / ("app/data/aircraft/" + model + ".json") for model in
                          ("p51d_mustang_120", "f4u_corsair_250", "sebart_avanti_s_a200"))
        if name == "electric":
            inputs.extend(PROBES / ("electric_probe" + ext) for ext in (".py", ".cpp"))
            inputs.append(ROOT / "app/data/aircraft/battery/moonrunner_x99_6s_pack.json")
            aircraft = json.loads((ROOT / "app/data/aircraft/battery/moonrunner_x99_6s_pack.json").read_text())
            pack_ref = aircraft["propulsion"]["battery"]["pack"]
            pack_path = ROOT / "app/data/batteries/packs" / (pack_ref["id"] + ".json")
            cell_ref = json.loads(pack_path.read_text())["cell_template"]
            inputs.extend((pack_path, ROOT / "app/data/batteries/cells" / (cell_ref["id"] + ".json")))
            inputs.extend(sorted((ROOT / "research/native-kernel/src").glob("*.hpp")))
        row = {"name": name, "inputs": [identity(path) for path in inputs]}
        if name == "mathematics":
            with tempfile.TemporaryDirectory(prefix="openrc-refresh-") as stage:
                binary = Path(stage) / "math-oracle"
                row["build"] = command(["g++", "-std=c++17", "-O2", "-Wall",
                                        "-Wextra", "-Werror", "-fno-fast-math",
                                        "-ffp-contract=off", probe, "-o", binary])
                row["run"] = command([binary]) if row["build"]["returncode"] == 0 else None
        else:
            argv = [sys.executable, probe]
            if name in ("drone", "propulsion", "electric"):
                argv.append(ROOT)
            row["run"] = command(argv)
        row["ok"] = row["run"] is not None and row["run"]["returncode"] == 0
        record["cases"].append(row)
        print(f"{name}: {'observed' if row['ok'] else 'FAILED'}", flush=True)
    record["ok"] = all(row["ok"] for row in record["cases"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
    return 0 if record["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
