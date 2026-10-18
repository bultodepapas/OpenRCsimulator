#!/usr/bin/env python3
"""Check source fidelity and deterministic wind using native gallery artifacts."""
import argparse
import hashlib
import json
from pathlib import Path


def read(folder: Path) -> tuple[dict, dict[str, str]]:
    report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    if not report.get("complete") or report.get("mode") != "gallery":
        raise ValueError("a complete gallery is required")
    hashes = {}
    for capture in report["captures"]:
        name = capture["id"]
        if Path(name).name != name or name in hashes:
            raise ValueError("invalid or duplicate capture ID")
        digest = hashlib.sha256((folder / (name + ".png")).read_bytes()).hexdigest()
        if digest != capture["sha256"]:
            raise ValueError("capture hash mismatch: " + name)
        hashes[name] = digest
    return report, hashes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="wind-off gallery")
    parser.add_argument("--wind", type=Path, required=True, help="tree-wind gallery")
    args = parser.parse_args()
    source, source_hashes = read(args.source)
    wind, wind_hashes = read(args.wind)
    for key in ("godot", "renderer", "adapter", "api", "viewport", "msaa", "vegetation_catalog_sha256", "assets"):
        if source[key] != wind[key]:
            raise ValueError("mismatched fixture identity: " + key)
    ids = [asset["id"] for asset in source["assets"]]
    if not ids:
        raise ValueError("no source assets")
    checks = {
        "native_compatibility": source["renderer"] == "gl_compatibility",
        "explicit_wind_control": source["arguments"].get("wind") == "off" and wind["arguments"].get("wind") == "on",
        "all_calm_sources_pixel_exact": all(source_hashes[id] == wind_hashes[id] for id in ids),
        "wind_off_clock_control_static": len({source_hashes[key] for key in source_hashes if key.startswith("wind_")}) == 1,
        "repeat_pixel_exact": wind_hashes["wind_one"] == wind_hashes["wind_repeat"],
        "clock_wrap_pixel_exact": wind_hashes["wind_start"] == wind_hashes["wind_wrap"],
        "wind_moves": wind_hashes["wind_start"] != wind_hashes["wind_one"],
        "wind_reversal_changes_image": wind_hashes["wind_one"] != wind_hashes["wind_reverse"],
    }
    print(json.dumps({"assets": ids, "checks": checks, "passed": all(checks.values())}, indent=2))
    if not all(checks.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
