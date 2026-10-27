"""Merge one capture of the frozen pre-packed-mode candidate into the sample-byte fixture.

Usage: python merge_os_capture.py <app/tests/fixtures/spatial_wind_mode_grid_before.json> <capture.json>

`wind_bytes_hex` stays the original Windows capture. A capture from another OS adds
`wind_bytes_hex_by_os[<os>]` only to samples whose bytes differ; a Windows capture must
match every sample. The capture must come from the reconstructed pre-packed sources.
"""
import json
import sys

FORMAT = "openrc-spatial-mode-grid-before-opt v2"
BASE_OS = "Windows"
PREOPT_SOURCES = {
    "physics/wind_spatial_field.gd": "c9e213aa6b063c43948854cabbd354209437cbb2e5ce167ab9615e481ea99e86",
    "physics/wind_spatial_config.gd": "75486c40764a625fc89836fb8362b420dc82d9c1929cd2588200bd08a869188f",
    "physics/wind_thermal_field.gd": "7952776560fbd6e3cb4379d47ee7d77da97720605b7b64f0c9a838114fa54d66",
    "tests/test_spatial_wind_field.gd": "e6041a5e04a7c18e0e41e73e79f40be2b6f0c0dc97522162dc77589b2703fa3d",
}


def main(fixture_path: str, capture_path: str) -> int:
    with open(fixture_path, encoding="utf-8") as handle:
        fixture = json.load(handle)
    with open(capture_path, encoding="utf-8") as handle:
        capture = json.load(handle)
    if capture.get("format") != "openrc-spatial-mode-grid-capture v1":
        sys.exit("unknown capture format")
    if capture.get("source_sha256") != PREOPT_SOURCES:
        sys.exit("capture did not run on the reconstructed pre-packed sources: %s" % capture.get("source_sha256"))
    os_name = capture["os"]
    captured = {case["id"]: case for case in capture["fixtures"]}
    if sorted(captured) != sorted(case["id"] for case in fixture["fixtures"]):
        sys.exit("capture case ids differ from the fixture")
    differing = 0
    for case in fixture["fixtures"]:
        other = captured[case["id"]]
        if (other["spatial_hash"], other["thermal_hash"]) != (case["spatial_hash"], case["thermal_hash"]):
            sys.exit("config identity differs for " + case["id"])
        if len(other["samples"]) != len(case["samples"]):
            sys.exit("sample count differs for " + case["id"])
        for sample, got in zip(case["samples"], other["samples"]):
            if (sample["position_ned_m"], sample["time_s"]) != (got["position_ned_m"], got["time_s"]):
                sys.exit("sample grid differs for " + case["id"])
            if not got["wind_bytes_hex"]:
                sys.exit("capture sample failed for " + case["id"])
            by_os = sample.pop("wind_bytes_hex_by_os", {})
            by_os.pop(os_name, None)
            if got["wind_bytes_hex"] != sample["wind_bytes_hex"]:
                if os_name == BASE_OS:
                    sys.exit("Windows capture no longer reproduces the original bytes for " + case["id"])
                by_os[os_name] = got["wind_bytes_hex"]
                differing += 1
            if by_os:
                sample["wind_bytes_hex_by_os"] = by_os
    fixture["format"] = FORMAT
    fixture.setdefault("os_captures", {})[os_name] = {
        "capture_tool": "docs/research/wind-implementation/M5-W05d-R1/fixture-capture/",
        "engine": capture["engine"],
        "samples_differing_from_wind_bytes_hex": differing,
        "source_sha256": capture["source_sha256"],
    }
    with open(fixture_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(fixture, indent="\t", sort_keys=True, ensure_ascii=False) + "\n")
    print("%s: %d samples differ from wind_bytes_hex" % (os_name, differing))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
