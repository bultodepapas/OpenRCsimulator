#!/usr/bin/env python3
"""Run the five second-investigation probes sequentially with the checked runner.

The audited baseline fails desired-behavior assertions. Those nonzero exits are
preserved, not converted to passes. Hydrate/import the app before running.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]
ENGINE_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
PROBES = {
    "heli-delayed-frames": ("probe_heli_delayed_frames.gd", "ROUND2_HELI_DELAYED_FRAMES_COMPLETE:"),
    "quad-crash-checkpoint": ("probe_quad_crash_checkpoint.gd", "ROUND2_QUAD_CHECKPOINT_COMPLETE "),
    "contact-order": ("probe_contact_order.gd", "ROUND2_CONTACT_ORDER_COMPLETE "),
    "crash-pause-log": ("probe_crash_pause_log.gd", "ROUND2_CRASH_PAUSE_LOG_COMPLETE "),
    "quad-obstacle-aftermath": ("probe_quad_obstacle_aftermath.gd", "ROUND2_QUAD_OBSTACLE_AFTERMATH_COMPLETE "),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="Selected names; all five by default.")
    parser.add_argument("--list", action="store_true", help="List names without launching the engine.")
    parser.add_argument("--engine", type=Path, default=ROOT / ".tools/Godot_v4.8-beta2_linux.x86_64")
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/collision-audit-round2/reproductions" /
                        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ"))
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()
    if args.list:
        print("\n".join(PROBES))
        return 0
    names = args.names or list(PROBES)
    unknown = sorted(set(names) - set(PROBES))
    if unknown:
        parser.error("Unknown probes: " + ", ".join(unknown))
    if len(names) != len(set(names)):
        parser.error("Choose each probe at most once per fresh output directory.")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive and finite")
    engine = args.engine.resolve()
    if not engine.is_file():
        parser.error("Pinned engine missing; use the repository downloader or --engine with its verified binary.")
    with engine.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha512").hexdigest()
    if digest != ENGINE_SHA512:
        parser.error("Engine SHA-512 does not match the audited pinned Linux x86_64 binary.")
    out = args.out.resolve()
    if out.exists():
        parser.error("--out must be a fresh directory; existing evidence will not be overwritten.")
    out.mkdir(parents=True)
    summary = {"format": "openrc-collision-audit-round2-reproduction-v1", "engine_sha512": digest,
               "note": "Raw checked-runner exits are preserved; known baseline failures are not passes.", "runs": []}
    failed = False
    for name in names:
        filename, marker = PROBES[name]
        probe = HERE / "probes" / filename
        probe_out = out / name
        command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"),
                   "--label", name, "--timeout", str(args.timeout), "--out-dir", str(probe_out / "runs"),
                   "--require-text", marker, "--", str(engine), "--headless", "--path", str(ROOT / "app"),
                   "--audio-driver", "Dummy", "--script", str(probe)]
        if name == "crash-pause-log":
            command.extend(["--", "--out=" + str(probe_out / "recording")])
        environment = os.environ.copy()
        for variable, directory in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache")]:
            environment[variable] = str(probe_out / "profile" / directory)
        result = subprocess.run(command, cwd=ROOT, env=environment, check=False)
        failed = failed or result.returncode != 0
        summary["runs"].append({"name": name, "checked_exit_code": result.returncode,
                                "probe_sha256": hashlib.sha256(probe.read_bytes()).hexdigest(),
                                "command": command})
        (out / "reproduction.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{name}: checked runner exit {result.returncode}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
