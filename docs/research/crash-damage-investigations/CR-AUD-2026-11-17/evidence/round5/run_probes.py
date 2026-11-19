#!/usr/bin/env python3
"""Reproduce selected current-main checks in the exact component fixture.

Known desired-behavior failures retain their nonzero checked exits. Passing
observation probes can characterize a defect. See the verification document.
The inconclusive stock-slope attempt is opt-in and excluded from final totals.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import runpy
import subprocess
import sys

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
ENGINE_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
NEW_PROBES = {
    "slope-severity": ("probe_slope_severity.gd", "SLOPE_SEVERITY_PROBE:"),
    "quad-severity": ("probe_quad_severity.gd", "QUAD_SEVERITY_DRAFT_COMPLETE"),
    "person-attribution": ("probe_person_attribution.gd", "helicopter person attribution:"),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--source-repo", type=Path)
    parser.add_argument("--project", type=Path, help="The isolated fixture's app directory.")
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()
    jobs = {}
    for directory in [EVIDENCE] + [EVIDENCE / f"round{i}" for i in (2, 3, 4)]:
        for name, spec in runpy.run_path(str(directory / "run_probes.py"))["PROBES"].items():
            jobs[name] = (directory / "probes" / spec[0], spec[1])
    jobs.update({name: (HERE / "probes" / spec[0], spec[1]) for name, spec in NEW_PROBES.items()})
    controls = {"test_crash_severity": "0 failed", "test_parked_aircraft_collision": "0 failures",
                "test_heli_crash_visual": "0 failed"}
    all_names = list(jobs) + list(controls)
    if args.list:
        print("\n".join(all_names))
        print("stock-slope-producer (inconclusive historical attempt; opt-in only)")
        return 0
    if any(value is None for value in (args.source_repo, args.project, args.engine, args.out)):
        parser.error("Provide --source-repo, --project, --engine and a fresh --out.")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive and finite.")
    source, project, engine, out = (value.resolve() for value in
                                    (args.source_repo, args.project, args.engine, args.out))
    jobs.update({name: (project / "tests" / f"{name}.gd", marker) for name, marker in controls.items()})
    jobs["stock-slope-producer"] = (HERE / "attempts" / "probe_stock_slope_producer.gd", "STOCK_SLOPE_PRODUCER_PROBE:")
    names = args.names or all_names
    if len(names) != len(set(names)) or set(names) - set(jobs):
        parser.error("Select unique known names; use --list.")
    if out.exists():
        parser.error("--out already exists; existing evidence is never overwritten.")
    manifest = json.loads((HERE / "source-manifest.json").read_text())
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if commit != manifest["source_commit"]:
        parser.error("This historical reproduction requires the recorded source revision.")
    if (project / "project.godot").read_text() != manifest["project_text"]:
        parser.error("Project settings differ from the isolated audit fixture.")
    for row in manifest["files"]:
        if row["path"].endswith(".import"):
            continue  # The editor regenerates import descriptors/cache.
        path = project.parent / row["path"]
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            parser.error(f"Fixture content differs or is missing: {row['path']}")
    with engine.open("rb") as stream:
        if hashlib.file_digest(stream, "sha512").hexdigest() != ENGINE_SHA512:
            parser.error("Pinned engine SHA-512 differs.")
    sys.path.insert(0, str(source))
    from tools.godot.run_checked import run_checked
    out.mkdir(parents=True)
    summary = {"format": "openrc-collision-round5-reproduction-v1", "source_commit": commit,
               "engine_sha512": ENGINE_SHA512, "project": str(project), "runs": []}
    os.chdir(source)
    for name in names:
        script, marker = jobs[name]
        job_out = out / name
        for variable, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            os.environ[variable] = str(job_out / "profile" / suffix)
        command = [str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy", "--script", str(script)]
        if name in ("crash-pause-log", "airship-collision-recording"):
            command += ["--", "--out=" + str(job_out / "recording")]
        result = run_checked(command, job_out, timeout=args.timeout, required=[marker], label=name)
        summary["runs"].append({"name": name, "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                                **{key: result.get(key) for key in ("ok", "reason", "process_exit", "complete", "counts", "report", "log")}})
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{name}: {result['reason']}; process exit {result.get('process_exit')}", flush=True)
    return 0 if all(row["ok"] for row in summary["runs"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
