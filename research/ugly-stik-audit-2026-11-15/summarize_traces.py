#!/usr/bin/env python3
"""Retain CSV identities and unmodified rows supporting the dated audit's interpretations."""

import argparse
import csv
import hashlib
import json
from pathlib import Path


def csv_rows(path):
    return list(csv.DictReader(line for line in path.read_text().splitlines() if not line.startswith("#")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dynamic", type=Path, required=True)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    campaigns = {"dynamic": args.dynamic, "electric-pack": args.pack}
    result = {
        "scope": "Selected unmodified CSV rows, not full trajectories; decimals remain strings as recorded.",
        "sampling": "Default flight-card CSV cadence, 20 Hz; events detected at 240 Hz can fall between retained rows.",
        "csv_manifest": [],
        "observations": [],
    }
    for campaign, root in campaigns.items():
        for path in sorted(root.rglob("*.csv")):
            data = path.read_bytes()
            result["csv_manifest"].append({
                "path": f"{campaign}/{path.relative_to(root)}",
                "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                "rows": len(csv_rows(path)),
            })

        for directory in sorted(p.parent for p in root.glob("*/profile.json")):
            profile = json.loads((directory / "profile.json").read_text())
            for case in profile["results"]["power_step"]["table"]:
                event = case.get("inverted_at_s")
                if event is None:
                    continue
                path = directory / ("power_step_" + case["case"] + ".csv")
                rows = csv_rows(path)
                index = min(range(len(rows)), key=lambda i: abs(float(rows[i]["t_s"]) - event))
                result["observations"].append({
                    "purpose": "Orientation-criterion crossing with active lateral controller; not sustained inverted flight.",
                    "path": f"{campaign}/{path.relative_to(root)}",
                    "profile_event_s": event, "closest_data_row_zero_based": index,
                    "rows": rows[max(0, index - 1):index + 2],
                })

            if directory.name == "stik-electric-6s":
                path = directory / "vmax.csv"
                rows = csv_rows(path)
                index = min(range(len(rows)), key=lambda i: abs(float(rows[i]["t_s"]) - 2.0))
                result["observations"].append({
                    "purpose": "Ideal/finite-pack source-voltage comparison at 2 seconds.",
                    "path": f"{campaign}/{path.relative_to(root)}",
                    "closest_data_row_zero_based": index, "rows": [rows[index]],
                })
            if directory.name == "stik-glow-61fx-2t":
                path = directory / "vmax.csv"
                result["observations"].append({
                    "purpose": "Modeled level-speed endpoint and RPM; component-limit exceedance is not physical test evidence.",
                    "path": f"{campaign}/{path.relative_to(root)}",
                    "profile_metrics": profile["results"]["vmax"]["metrics"],
                    "rows": csv_rows(path)[-3:],
                })
            if directory.name == "gp-extra-300s-60":
                path = directory / "hands_off.csv"
                result["observations"].append({
                    "purpose": "Disturbed-model response endpoint; not a measured real-aircraft stability result.",
                    "path": f"{campaign}/{path.relative_to(root)}",
                    "profile_metrics": profile["results"]["hands_off"]["metrics"],
                    "rows": csv_rows(path)[-3:],
                })
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Retained {len(result['csv_manifest'])} CSV identities and {len(result['observations'])} observations.")


if __name__ == "__main__":
    main()
