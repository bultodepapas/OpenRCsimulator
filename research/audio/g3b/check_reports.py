"""Reject incomplete/invalid mixer artifacts; distinguish native latency from Dummy stability."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path


def finite(value):
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, list):
        return all(finite(v) for v in value)
    return not isinstance(value, float) or math.isfinite(value)


def valid(data):
    response = data["rpm_step"]["response"]
    return (finite(data) and data["status"] == "ok" and not data["failure"]
            and data["audio_driver_requested"] == data["audio_driver_runtime"]
            and data["capture_peak_linear"] > .01 and data["capture_rms_linear"] > .01
            and data["capture_discarded_frames"] == 0 and data["steady_seconds"] >= 10.0
            and data["captured_frames"] / data["mix_rate_hz"] > 10.0
            and data["rpm_step"]["request_to_end_seconds"] >= 2.0
            and response["ok"] and response["post_step_400_to_100_power_ratio_max"] > 3.0
            and response["pre_step_400_to_100_power_ratio_max"] < 3.0
            and response["response_ms"] >= 0)


def native_acceptance(data):
    return (valid(data) and data["audio_driver_runtime"] != "Dummy"
            and data["steady_skips_delta"] == 0 and data["steady_queue_max_frames"] <= 1103
            and data["rpm_step"]["response"]["end_to_end_ms"] <= 70.0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, nargs=3, required=True)
    parser.add_argument("--dummy", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    native = [json.loads(p.read_text(encoding="utf-8")) for p in args.native]
    dummy = json.loads(args.dummy.read_text(encoding="utf-8"))
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    assert {d["fps_requested"] for d in native} == {30, 60, 144}, "missing native FPS case"
    assert all(native_acceptance(d) for d in native), "native acceptance failed"
    assert valid(dummy) and dummy["audio_driver_runtime"] == "Dummy" and dummy["steady_skips_delta"] == 0, "Dummy stability failed"
    assert valid(baseline) and not native_acceptance(baseline), "delayed baseline was not rejected"
    # Reader controls: a zero signal, truncated run and nonfinite report cannot qualify.
    for key, value in [("capture_peak_linear", 0.0), ("steady_seconds", .1), ("capture_rms_linear", float("nan"))]:
        mutated = dict(native[0], **{key: value})
        assert not native_acceptance(mutated), f"reader accepted {key} defect"
    print("Three native FPS cases, Dummy fallback, delayed baseline and three reader controls verified")


if __name__ == "__main__":
    main()
