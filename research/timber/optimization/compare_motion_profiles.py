#!/usr/bin/env python3
"""Compare separate-run TT-21 exploratory profiles and their render/state snapshots.

Timing differences from this tool are host-drift-confounded. Use motion_paired_profile.gd
for order-alternating same-process timing when evaluating an optimization.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def without_resource_ids(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: without_resource_ids(item)
            for key, item in value.items()
            if key != "resource_id"
        }
    if isinstance(value, list):
        return [without_resource_ids(item) for item in value]
    return value


def profiles_by_case(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(row["case"]): row for row in rows}


def parity_checks(before: dict[str, Any], after: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    checks.append(
        {
            "check": "baseline runtime source matches frozen source",
            "passed": before.get("runtime_sha256") == before.get("frozen_baseline_sha256"),
            "before": before.get("runtime_sha256"),
            "frozen": before.get("frozen_baseline_sha256"),
        }
    )
    checks.append(
        {
            "check": "candidate references the same frozen source",
            "passed": after.get("frozen_baseline_sha256") == before.get("frozen_baseline_sha256"),
            "before_frozen": before.get("frozen_baseline_sha256"),
            "after_frozen": after.get("frozen_baseline_sha256"),
        }
    )
    for key in ("input_states", "fixture_session_inputs_restored"):
        checks.append(
            {
                "check": f"{key} unchanged",
                "passed": before.get(key) == after.get(key),
            }
        )
    before_snapshots = before.get("mesh_snapshots", [])
    after_snapshots = after.get("mesh_snapshots", [])
    checks.append(
        {
            "check": "snapshot pose count unchanged",
            "passed": len(before_snapshots) == len(after_snapshots),
            "before_count": len(before_snapshots),
            "after_count": len(after_snapshots),
        }
    )
    checks.append(
        {
            "check": "exact state, leg, geometry, material, and AABB parity",
            "passed": without_resource_ids(before_snapshots)
            == without_resource_ids(after_snapshots),
            "before_poses": [row.get("pose") for row in before_snapshots],
            "after_poses": [row.get("pose") for row in after_snapshots],
        }
    )
    checks.append(
        {
            "check": "zero harness failures",
            "passed": not before.get("failures") and not after.get("failures"),
            "before_failures": before.get("failures", []),
            "after_failures": after.get("failures", []),
        }
    )
    return checks


def compare_profile_sections(
    key: str, before: dict[str, Any], after: dict[str, Any]
) -> list[dict[str, Any]]:
    before_rows = before.get(key, [])
    after_rows = after.get(key, [])
    after_by_case = profiles_by_case(after_rows)
    rows: list[dict[str, Any]] = []
    for old in before_rows:
        name = str(old.get("case", ""))
        new = after_by_case.get(name)
        if new is None:
            continue
        old_median = float(old["median_us_per_call"])
        new_median = float(new["median_us_per_call"])
        old_mean = float(old["mean_us_per_call"])
        new_mean = float(new["mean_us_per_call"])
        rows.append(
            {
                "case": name,
                "operation_count": int(old.get("operation_count", 0)),
                "before_median_us_per_call": old_median,
                "after_median_us_per_call": new_median,
                "median_change_percent": (
                    (new_median - old_median) / old_median * 100.0
                    if old_median
                    else 0.0
                ),
                "before_mean_us_per_call": old_mean,
                "after_mean_us_per_call": new_mean,
                "mean_change_percent": (
                    (new_mean - old_mean) / old_mean * 100.0 if old_mean else 0.0
                ),
                "before_p95_us_per_call": float(old["p95_us_per_call"]),
                "after_p95_us_per_call": float(new["p95_us_per_call"]),
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    before = load(args.before)
    after = load(args.after)
    checks = parity_checks(before, after)
    profiles = {
        "process_profiles": compare_profile_sections(
            "process_profiles", before, after
        ),
        "contact_dust_profiles": compare_profile_sections(
            "contact_dust_profiles", before, after
        ),
        "cable_and_coil_update_profile": {
            "case": before.get("cable_and_coil_update_profile", {})
            .get("profile", {})
            .get("case"),
            "before": before.get("cable_and_coil_update_profile", {}).get(
                "profile", {}
            ),
            "after": after.get("cable_and_coil_update_profile", {}).get(
                "profile", {}
            ),
        },
        "reset_response_profile": {
            "before": before.get("reset_response_profile", {}),
            "after": after.get("reset_response_profile", {}),
        },
        "wreck_response_profile": {
            "before": before.get("wreck_response_profile", {}),
            "after": after.get("wreck_response_profile", {}),
        },
    }
    report = {
        "schema": "tt21-timber-motion-separate-run-exploratory-v1",
        "profiling_mode": "separate-process exploratory CPU profiles; not an FPS measurement",
        "timing_status": "confounded; before and after came from separate runs and do not establish optimization acceptance",
        "timing_warning": "Host scheduling, load, frequency, and process setup can shift medians. Use the same-process alternating paired harness for performance claims.",
        "before_report": str(args.before),
        "after_report": str(args.after),
        "before_runtime_sha256": before.get("runtime_sha256"),
        "after_runtime_sha256": after.get("runtime_sha256"),
        "frozen_baseline_sha256": before.get("frozen_baseline_sha256"),
        "parity_checks": checks,
        "profile_deltas": profiles,
    }
    payload = json.dumps(report, indent=2) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0 if all(check["passed"] for check in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
