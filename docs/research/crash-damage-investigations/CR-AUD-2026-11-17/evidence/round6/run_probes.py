#!/usr/bin/env python3
"""Run the dated nonfatal-contact audit in its exact-source component fixture.

Characterization passes describe the existing policy, not physical correctness.
The geometry probe intentionally retains a desired-behavior failure. Existing
controls and new probes are reported separately; no engine-error run qualifies.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ENGINE_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
PROBES = {
    "geometry": ("probe_nonfatal_geometry.gd", "SUMMARY component checks="),
    "geometry-outside": ("probe_nonfatal_geometry_outside.gd", "SUMMARY outside-CG component checks="),
    "water-prop": ("probe_nonfatal_water_prop.gd", "NONFATAL CHARACTERIZATION checks="),
    "remainder": ("probe_nonfatal_remainder.gd", "SUMMARY accepted-step characterization checks="),
}
CONTROLS = {
    "test_soft_contacts": "0 failed",
    "test_hull_friction_observation": "Hull scrape metrics:",
    "test_hull_scrape_audio": "Hull scrape audio complete",
    "test_prop_strike": "0 failed",
    "test_lake_collision": "all lake collision checks passed",
    "test_collision_tie_order": "collision tie order:",
    "test_airframe_contacts": "0 failed",
}
OPTIONAL_CONTROLS = {
    # This invokes Main and requires resources beyond the component fixture.
    # Retained failed attempts are excluded from the qualifying audit totals.
    "test_hull_scrape_session": "Hull scrape Session complete",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--source-repo", type=Path)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()
    all_names = list(PROBES) + list(CONTROLS)
    if args.list:
        print("\n".join(all_names))
        print("test_hull_scrape_session (opt-in full-Main resource check; excluded attempts retained)")
        return 0
    if any(value is None for value in (args.source_repo, args.project, args.engine, args.out)):
        parser.error("Provide --source-repo, --project, --engine and a fresh --out.")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive and finite.")
    source, project, engine, out = (value.resolve() for value in
                                    (args.source_repo, args.project, args.engine, args.out))
    jobs = {name: (HERE / "probes" / filename, marker) for name, (filename, marker) in PROBES.items()}
    jobs.update({name: (project / "tests" / f"{name}.gd", marker) for name, marker in CONTROLS.items()})
    jobs.update({name: (project / "tests" / f"{name}.gd", marker) for name, marker in OPTIONAL_CONTROLS.items()})
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
            continue  # Editor import descriptors/cache are generated separately.
        path = project.parent / row["path"]
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            parser.error(f"Fixture content differs or is missing: {row['path']}")
    with engine.open("rb") as stream:
        if hashlib.file_digest(stream, "sha512").hexdigest() != ENGINE_SHA512:
            parser.error("Pinned engine SHA-512 differs.")
    for name in names:
        if not jobs[name][0].is_file():
            parser.error(f"Missing script: {jobs[name][0]}")
    sys.path.insert(0, str(source))
    from tools.godot.run_checked import run_checked
    out.mkdir(parents=True)
    summary = {"format": "openrc-nonfatal-contact-round6-reproduction-v1", "source_commit": commit,
               "engine_sha512": ENGINE_SHA512, "project": str(project), "runs": []}
    os.chdir(source)
    for name in names:
        script, marker = jobs[name]
        job_out = out / name
        for variable, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            os.environ[variable] = str(job_out / "profile" / suffix)
        command = [str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy", "--script", str(script)]
        result = run_checked(command, job_out, timeout=args.timeout, required=[marker], warnings_as_errors=True, label=name)
        summary["runs"].append({"name": name, "kind": "existing-control" if name in CONTROLS or name in OPTIONAL_CONTROLS else "audit-probe",
                                "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                                **{key: result.get(key) for key in ("ok", "reason", "process_exit", "complete", "counts", "report", "log")}})
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{name}: {result['reason']}; process exit {result.get('process_exit')}", flush=True)
    return 0 if all(row["ok"] for row in summary["runs"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
