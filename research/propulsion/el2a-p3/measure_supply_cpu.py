#!/usr/bin/env python3
"""Linux-only paired child-process CPU diagnostic; not a whole-session/real-time benchmark."""
import argparse
import hashlib
import json
import platform
import re
import resource
import statistics
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-app", type=Path, required=True)
    parser.add_argument("--candidate-app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    script = Path(__file__).with_name("bench_supply.gd").resolve()
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    report = {"format": "openrc-el2a-p3-supply-cpu-v1", "ok": False, "runs": [],
              "platform": platform.platform(), "engine_sha256": sha(args.godot),
              "driver_sha256": sha(script), "runner_sha256": sha(Path(__file__)),
              "scope": "Child user+system CPU includes startup/compilation and 300000 calls. "
                       "Concurrent host tests remain active; wall time is diagnostic only. "
                       "Not full-tick or real-time acceptance; cache/frequency interference remains possible.",
              "sources": {}}
    try:
        for label, app in (("baseline", args.baseline_app), ("candidate", args.candidate_app)):
            report["sources"][label] = {name: sha(app / "physics" / name)
                                         for name in ("electric_motor.gd", "electric_supply.gd")}
        for index, label in enumerate(("baseline", "candidate", "candidate", "baseline") * 2):
            app = args.baseline_app if label == "baseline" else args.candidate_app
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            process = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(app.resolve()),
                                      "--script", str(script)], capture_output=True, text=True, timeout=120)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            output = process.stdout + process.stderr
            (args.out / f"{index:02d}-{label}.log").write_text(output, encoding="utf-8")
            if process.returncode != 0 or re.search(r"^(?:SCRIPT |SHADER )?ERROR:", output, re.M):
                raise ValueError(f"{label}: failed engine run")
            rows = [json.loads(line) for line in output.splitlines() if line.startswith('{"')]
            if len(rows) != 1 or rows[0]["iterations"] != 300000 or rows[0]["fixture_count"] != 120:
                raise ValueError(f"{label}: incomplete diagnostic")
            row = rows[0]
            row.update({"snapshot": label, "order": index,
                        "child_cpu_s": after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime})
            report["runs"].append(row)
        for key in ("fixture_bytes_sha256", "checksum_bytes_sha256"):
            if len({row[key] for row in report["runs"]}) != 1:
                raise ValueError(f"changed {key}")
        medians = {label: statistics.median(row["child_cpu_s"] for row in report["runs"]
                                           if row["snapshot"] == label) for label in ("baseline", "candidate")}
        report["median_child_cpu_s"] = medians
        report["cpu_reduction_percent"] = 100.0 * (1.0 - medians["candidate"] / medians["baseline"])
        report["ok"] = True
    finally:
        (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("ok", "median_child_cpu_s", "cpu_reduction_percent")}))


if __name__ == "__main__":
    main()
