#!/usr/bin/env python3
"""Sequential, identified R11 session-cost measurements; use immutable app copies."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--ticks", type=int, default=480)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--preparations", type=int, default=3)
    args = parser.parse_args()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    harness = Path(__file__).with_name("measure_cost.gd").resolve()
    shutil.copyfile(harness, output / harness.name)
    shutil.copyfile(Path(__file__), output / Path(__file__).name)
    engine_sha256 = hashlib.sha256(args.godot.read_bytes()).hexdigest()
    started = datetime.now(timezone.utc).isoformat()
    results = []
    reports = []
    for version, project, weather in (
        ("before", args.before, "reference"),
        ("after", args.after, "reference"),
        ("after", args.after, "column"),
    ):
        for aircraft, filename in (
            ("stik", "jensen_ugly_stik_60.json"),
            ("jet", "sebart_avanti_s_a200.json"),
        ):
            name = f"{version}-{aircraft}-{weather}"
            report_path = output / f"{name}.json"
            command = [str(args.godot.resolve()), "--headless", "--path", str(project.resolve()),
                       "--audio-driver", "Dummy", "--script", str(harness), "--",
                       f"--out={report_path}", f"--aircraft=res://data/aircraft/{filename}",
                       f"--weather={weather}", f"--ticks={args.ticks}",
                       f"--samples={args.samples}", f"--preparations={args.preparations}"]
            print(f"Starting {name}", flush=True)
            t0 = time.monotonic()
            process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (output / f"{name}.log").write_bytes(process.stdout)
            report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
            reports.append(report)
            engine_errors = bool(re.search(rb"(?:SCRIPT ERROR|ERROR):", process.stdout))
            complete = bool(report.get("ok") and report.get("source_unchanged")
                            and len(report.get("regimes", {})) == 4
                            and all(r.get("ok") and r.get("completed_ticks") == args.ticks * args.samples
                                    for r in report.get("regimes", {}).values()))
            result = dict(name=name, command=command, exit_code=process.returncode,
                          wall_seconds=time.monotonic() - t0, engine_errors=engine_errors,
                          complete=complete, ok=process.returncode == 0 and not engine_errors and complete)
            results.append(result)
            print(json.dumps(result), flush=True)
            if not result["ok"]:
                break
        if not results[-1]["ok"]:
            break
    identities_match = (len(reports) == 6
                        and reports[0].get("aircraft_file_sha256") == reports[2].get("aircraft_file_sha256") == reports[4].get("aircraft_file_sha256")
                        and reports[1].get("aircraft_file_sha256") == reports[3].get("aircraft_file_sha256") == reports[5].get("aircraft_file_sha256")
                        and reports[0].get("source_sha256") == reports[1].get("source_sha256")
                        and len({r.get("source_sha256") for r in reports[2:]}) == 1
                        and len({r.get("field_sha256") for r in reports}) == 1)
    summary = dict(format="openrc-audit-cost-batch-v1", started_utc=started,
                   finished_utc=datetime.now(timezone.utc).isoformat(),
                   harness_sha256=hashlib.sha256(harness.read_bytes()).hexdigest(),
                   runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   godot_sha256=engine_sha256,
                   results=results, consistent_identities=identities_match,
                   ok=len(results) == 6 and all(r["ok"] for r in results) and identities_match)
    (output / "verification.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
