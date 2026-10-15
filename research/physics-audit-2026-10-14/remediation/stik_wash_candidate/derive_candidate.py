#!/usr/bin/env python3
"""Build an experimental Stik wash aircraft from the existing E0b2/E0b3b sources.

This generator writes only this candidate directory. It never edits the catalog
aircraft, source geometry, runtime, or E0b3b test fixture.
"""
import argparse
import copy
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
E0B3B_GENERATOR = ROOT / "research/propwash/e0b3b/derive_profile.py"
E0B2_GENERATOR = ROOT / "research/propwash/e0b2/derive_geometry.py"
E0B2_VISUAL_GEOMETRY = ROOT / "assets/aircraft/ugly-stik-60/geometry.json"
E0B2_RUNTIME_GEOMETRY = ROOT / "app/aircraft/ugly_stik_geometry.gd"
E0B2_GEOMETRY = ROOT / "docs/research/propwash/E0b2/geometry.json"
E0B3B_REPORT = ROOT / "docs/research/propwash/E0b3b/geometry.json"
BASELINE = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
E0B2_REPORT = ROOT / "docs/research/propwash/E0b2/geometry.json"
OUTPUT = Path(__file__).resolve().parent / "aircraft_v2.json"
GENERATOR = "research/physics-audit-2026-10-14/remediation/stik_wash_candidate/derive_candidate.py"
COEFFICIENT_SOURCE = (
    "app/tests/test_wash_profile.gd::combined_raw; copied exactly as an estimated "
    "experimental test configuration, not measured or calibrated"
)


def quantity(value, unit, source=COEFFICIENT_SOURCE, kind="estimated"):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def equivalent_source_value(expected, actual, tolerance=2e-12):
    if isinstance(expected, dict):
        return isinstance(actual, dict) and expected.keys() == actual.keys() and all(
            equivalent_source_value(expected[key], actual[key], tolerance) for key in expected
        )
    if isinstance(expected, list):
        return isinstance(actual, list) and len(expected) == len(actual) and all(
            equivalent_source_value(left, right, tolerance) for left, right in zip(expected, actual)
        )
    if isinstance(expected, (int, float)) and not isinstance(expected, bool):
        return isinstance(actual, (int, float)) and not isinstance(actual, bool) and math.isclose(
            float(expected), float(actual), rel_tol=0.0, abs_tol=tolerance
        )
    return expected == actual


def build():
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    e0b2 = json.loads(E0B2_GEOMETRY.read_text(encoding="utf-8"))
    e0b3b = json.loads(E0B3B_REPORT.read_text(encoding="utf-8"))
    visual = json.loads(E0B2_VISUAL_GEOMETRY.read_text(encoding="utf-8"))
    compiled_text = E0B2_RUNTIME_GEOMETRY.read_text(encoding="utf-8").split("const DATA := ", 1)[1]
    if json.loads(compiled_text) != visual:
        raise ValueError("E0b2 visual geometry differs from its compiled runtime geometry")
    e0b2_spec = importlib.util.spec_from_file_location("e0b2_generator", E0B2_GENERATOR)
    e0b2_module = importlib.util.module_from_spec(e0b2_spec)
    e0b2_spec.loader.exec_module(e0b2_module)
    _offset, regenerated_e0b2 = e0b2_module.derive(visual, baseline)
    if not equivalent_source_value(regenerated_e0b2, json.loads(E0B2_REPORT.read_text(encoding="utf-8"))):
        raise ValueError("E0b2 geometry handoff differs semantically from its source generator")
    if e0b3b.get("source_geometry") != "docs/research/propwash/E0b2/geometry.json":
        raise ValueError("E0b3b report does not identify the E0b2 geometry source")
    if e0b3b.get("source_geometry_id") != e0b2.get("source_geometry_id"):
        raise ValueError("E0b3b profile and E0b2 geometry source IDs differ")
    hub = e0b2["hub_le"]
    cg = baseline["balance"]["plan_cg"]["value"]
    expected_offset = [hub["value"][axis] - cg[axis] for axis in range(3)]
    recorded_offset = baseline["propulsion"]["propeller"]["thrust_line_offset"]["value"]
    if any(abs(expected_offset[axis] - recorded_offset[axis]) > 1e-12 for axis in range(3)):
        raise ValueError("E0b2 hub no longer matches the baseline aircraft thrust-line offset")
    e0b2_areas = {piece["name"]: piece["area"]["value"] for piece in e0b2["pieces"]}
    for piece in e0b3b["pieces"]:
        source_name = piece["name"]
        if source_name not in e0b2_areas or abs(piece["area"]["value"] - e0b2_areas[source_name]) > 2e-12:
            raise ValueError(f"E0b3b projected area differs from E0b2 source: {source_name}")

    candidate = copy.deepcopy(baseline)
    candidate["description"] = (
        str(baseline.get("description", ""))
        + " Experimental, stateless E0b3b tail-wash candidate; not catalog-enabled or physically calibrated."
    ).strip()

    hub_source = hub["source"] + "; reused without changing the baseline thrust-point quantity"
    pieces = []
    for source_piece in e0b3b["pieces"]:
        pieces.append({
            "surface": source_piece["surface"],
            "root": source_piece["root_le"],
            "span_dir": source_piece["span_dir_le"],
            "span": source_piece["span"],
            "area": source_piece["area"],
            "profile": source_piece["profile"],
        })

    candidate["propulsion"]["propeller"]["thrust_angles"] = quantity([0.0, 0.0], "deg")
    candidate["propulsion"]["propeller"]["slipstream"] = {
        "hub": quantity(hub["value"], hub["unit"], hub_source, hub["kind"]),
        "pieces": pieces,
        "wash_factor": quantity([1.0, 1.4], "1"),
        "swirl_factor": quantity(0.0, "1"),
        "vertical_drift": quantity(0.543, "1"),
        "edge_fraction": quantity(0.15, "1"),
        "reverse_fade": quantity([0.1, 0.2], "1"),
    }
    return candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify inputs and candidate are current")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(E0B3B_GENERATOR), "--check"], cwd=ROOT, check=True)
    output = json.dumps(build(), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output:
            raise SystemExit("Stik wash candidate is stale; run this generator without --check")
        print("R06 Slice A: candidate matches E0b2/E0b3b sources and estimated test coefficients")
        return
    OUTPUT.write_text(output, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
