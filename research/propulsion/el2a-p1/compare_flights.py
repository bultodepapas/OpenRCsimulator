#!/usr/bin/env python3
"""Compare EL2a's completed flight/ledger/refinement evidence before and after EL2a-P1."""
import argparse
import hashlib
import json
from pathlib import Path


def compare(baseline: Path, candidate: Path) -> dict:
    result = {"format": "openrc-el2a-p1-flight-parity-v1", "flights": {}, "ok": False}
    for name, count in (("flight", 8), ("refinement", 10)):
        old = json.loads((baseline / f"{name}.json").read_text())
        new = json.loads((candidate / f"{name}.json").read_text())
        if old != new or len(old["cases"]) != count or not all(c["ok"] for c in old["cases"].values()):
            raise ValueError(f"{name}: incomplete or differing complete-state results")
        result[name + "_identical"] = True
    # Require the independent electrical ledger/refinement checker to have completed too.
    for directory in (baseline, candidate):
        verified = json.loads((directory / "verified.json").read_text())
        if len(verified["flights"]) != 8 or verified["negative_controls"] != 48:
            raise ValueError("independent flight verification did not complete")
    for pack in ("4s", "6s"):
        for maneuver in ("level", "turn", "climb", "chop"):
            name = f"{pack}_battery-{maneuver}"
            normalized = []
            for directory in (baseline, candidate):
                lines = (directory / f"{name}.csv").read_bytes().splitlines(keepends=True)
                timestamps = [line for line in lines if line.startswith(b"# created_utc:")]
                if len(timestamps) != 1:
                    raise ValueError(f"{name}: expected exactly one wall-clock creation header")
                # Creation time is not simulation state. No numeric column or other metadata is excluded.
                payload = b"".join(line for line in lines if not line.startswith(b"# created_utc:"))
                if len([line for line in lines if line.strip() and not line.startswith(b"#")]) != 7202:
                    raise ValueError(f"{name}: expected column header and 7201 samples")
                normalized.append(payload)
            if normalized[0] != normalized[1]:
                raise ValueError(f"{name}: telemetry or metadata changed")
            result["flights"][name] = {"rows": 7201, "trace_sha256_excluding_created_utc":
                                      hashlib.sha256(normalized[0]).hexdigest()}
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
    print("8 complete 30-second traces, checkpoints and 10 refinement endpoints are identical")
