"""Reproduce this evidence's fixed-clock summary; not a flight qualifier."""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def percentile(values, fraction=0.95):
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


def reduce():
    reports = {}
    result = {}
    for name in ("high-before", "high-after", "standard-before", "standard-after"):
        report = json.loads((ROOT / name / "report.json").read_text())
        high = name.startswith("high")
        assert report["complete"] and report["format"] == "openrc-sky-flow-probe v1"
        assert report["viewport"] == [1920, 1080] and report["msaa"] == 4
        assert report["fixed_clock_hz"] == 60 and report["time_scale"] == 20
        assert report["profile"]["renderer"] == ("forward_plus" if high else "gl_compatibility")
        assert report["profile"]["active"] == ("high_experimental" if high else "standard")
        assert [c["scenario"] for c in report["cases"]] == ["moon", "twilight"]
        reports[name] = report
        result[name] = {}
        for case in report["cases"]:
            assert len(case["samples"]) == 481
            assert case["process_mode"] == (3 if name == "high-after" else 1)
            assert case["radiance_size"] == 3  # Godot enum: 256 pixels
            samples = case["samples"][1:]  # first sample establishes the initial state
            stats = {key + "_max": max(s[key] for s in samples) for key in
                     ("moon_delta_deg", "stars_delta_deg", "zenith_log_delta")}
            stats.update({key + "_p95": percentile([s[key] for s in samples]) for key in
                          ("wall_ms", "render_cpu_ms", "render_gpu_ms")})
            if "paused_samples" in case:
                assert len(case["paused_samples"]) == 120
                stats["paused_gpu_ms_p95"] = percentile([s["render_gpu_ms"] for s in case["paused_samples"][8:]])
            result[name][case["scenario"]] = stats
    control, candidate = reports["standard-before"], reports["standard-after"]
    assert all(r["engine"] == control["engine"] for r in reports.values())
    assert all(r["profile"]["gpu"] == control["profile"]["gpu"] for r in reports.values())
    keys = ("clock_s", "moon_delta_deg", "stars_delta_deg", "zenith_log_delta")
    trace_exact = all(all(a[k] == b[k] for k in keys) for ca, cb in zip(control["cases"], candidate["cases"])
                      for a, b in zip(ca["samples"], cb["samples"]))
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    before_pngs = sorted((ROOT / "standard-before").glob("*.png"))
    assert len(before_pngs) == 12
    png_exact = {p.name: digest(p) == digest(ROOT / "standard-after" / p.name) for p in before_pngs}
    result["standard_parity"] = {"trace_exact": trace_exact, "png_exact": png_exact}
    assert trace_exact and all(png_exact.values())
    return result


if __name__ == "__main__":
    print(json.dumps(reduce(), indent=2))
