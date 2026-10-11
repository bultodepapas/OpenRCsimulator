#!/usr/bin/env python3
"""Require exact same-engine EL2a-E1 maneuver traces after a performance change."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

DURATIONS = {"takeoff": 8, "stall": 20, "landing": 46}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    # Python equality conflates false/0 and true/1; evidence types must also agree.
    return json.dumps(value, sort_keys=True, allow_nan=False, separators=(",", ":"))


def compare(baseline: Path, candidate: Path) -> dict:
    reports = [json.loads((directory / "report.json").read_text(encoding="utf-8"))
               for directory in (baseline, candidate)]
    expected = {f"{pack}_{maneuver}_{hz}": duration * hz + 1
                for pack in ("4s", "6s") for maneuver, duration in DURATIONS.items()
                for hz in (240, 480)}
    for report in reports:
        require(report["format"] == "openrc-el2a-e1-envelope-v1" and report["ok"] is True,
                "independent maneuver verification did not pass")
        names = [case["name"] for case in report["cases"]]
        require(len(names) == len(expected) and set(names) == set(expected), "incomplete/duplicate cases")
        require(type(report["checked_rows"]) is int and report["checked_rows"] == sum(expected.values()),
                "incomplete row total")
        require(len(report["refinement"]) == 22, "incomplete refinement")
    for key in ("godot_version", "godot_sha256", "driver_sha256", "verifier_sha256", "refinement"):
        require(canonical(reports[0][key]) == canonical(reports[1][key]), f"changed {key}")
    result = {"format": "openrc-el2a-p3-envelope-parity-v1", "ok": False,
              "baseline_report_sha256": digest((baseline / "report.json").read_bytes()),
              "candidate_report_sha256": digest((candidate / "report.json").read_bytes()),
              "cases": {}, "checked_rows": sum(expected.values())}
    indexes = [{case["name"]: case for case in report["cases"]} for report in reports]
    for name, row_count in sorted(expected.items()):
        payloads, summaries = [], []
        for directory, index in zip((baseline, candidate), indexes):
            case = copy.deepcopy(index[name])
            require(case["flight"]["passed"] is True and case["flight"]["completed"] is True,
                    f"{name}: incomplete flight")
            require(case["flight"]["trace"]["row_count"] == row_count
                    and case["electrical"]["rows"] == row_count, f"{name}: wrong row count")
            raw = (directory / "cases" / f"{name}.csv").read_bytes()
            require(digest(raw) == case["electrical"]["trace_sha256"], f"{name}: corrupted trace")
            lines = raw.splitlines(keepends=True)
            require(sum(line.startswith(b"# created_utc:") for line in lines) == 1,
                    f"{name}: expected one creation timestamp")
            require(sum(bool(line.strip()) and not line.startswith(b"#") for line in lines) == row_count + 1,
                    f"{name}: incomplete CSV")
            payloads.append(b"".join(line for line in lines if not line.startswith(b"# created_utc:")))
            # Only artifact location and wall-clock-dependent raw hash differ; compare all metrics.
            del case["flight"]["trace"]["path"]
            del case["electrical"]["trace_sha256"]
            summaries.append(case)
        require(payloads[0] == payloads[1], f"{name}: telemetry/metadata differs")
        require(canonical(summaries[0]) == canonical(summaries[1]), f"{name}: maneuver/electrical metrics differ")
        result["cases"][name] = {"rows": row_count, "trace_sha256_excluding_created_utc": digest(payloads[0])}
    result["ok"] = True
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.baseline, args.candidate)
    with args.out.open("x", encoding="utf-8") as output:
        json.dump(report, output, indent=2)
        output.write("\n")
    print(f"PASS: {len(report['cases'])} byte-identical maneuver traces; {report['checked_rows']} rows")
