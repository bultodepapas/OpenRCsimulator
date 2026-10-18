#!/usr/bin/env python3
"""Verify native grass material controls; reuse the stdlib quality PNG reducer."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import quality_compare as quality


def compare(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != "openrc-grass-material-capture v1":
        raise quality.EvidenceError("unsupported material capture format")
    manifest["_manifest_dir"] = str(path.resolve().parent)
    records = {}
    for capture in manifest["captures"]:
        if capture["id"] in records:
            raise quality.EvidenceError("duplicate capture ID")
        records[capture["id"]] = dict(capture, image=capture["file"], image_sha256=capture["sha256"])
    if len(records) != 36:
        raise quality.EvidenceError("expected exactly 36 material captures")
    hash_cache = {}
    results = {}
    passed = True
    comparisons = {
        "source_parity": ("source-calm", "candidate-calm", "exact"),
        "calm_clock": ("candidate-calm", "candidate-calm-t1", "exact"),
        "repeat": ("candidate-wind-t0", "candidate-wind-repeat", "exact"),
        "clock_wrap": ("candidate-wind-t0", "candidate-wind-wrap", "exact"),
        "wind_motion": ("candidate-wind-t0", "candidate-wind-t1", "different"),
        "wind_reversal": ("candidate-wind-t0", "candidate-wind-reverse", "different"),
        "near_wrap_sample": ("candidate-wind-t0", "candidate-wind-prewrap", "informational"),
    }
    for lighting in ("front", "back", "shadow", "local"):
        results[lighting] = {}
        for name, (first, second, expectation) in comparisons.items():
            metrics = quality.compare_image_records(
                manifest, records[f"{lighting}-{first}"], manifest, records[f"{lighting}-{second}"], hash_cache
            )
            exact = metrics["exact_pixels_match"]
            valid = expectation == "informational" or exact == (expectation == "exact")
            passed = passed and valid
            results[lighting][name] = dict(metrics, expectation=expectation, passed=valid)
    return {
        "format": "openrc-grass-material-comparison v1",
        "source_manifest": str(path),
        "manifest_sha256": quality.hashlib.sha256(path.read_bytes()).hexdigest(),
        "adapter_sha256": manifest["adapter_sha256"],
        "results": results,
        "passed": passed,
        "scope": "Pixel controls for the recorded native fixture; motion differences alone do not prove world direction, root anchoring or physical realism.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = compare(args.manifest)
        quality.write_report(args.out, report)
        print(json.dumps({"report": str(args.out), "passed": report["passed"]}))
        return 0 if report["passed"] else 1
    except (quality.EvidenceError, OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, f"material_compare: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
