#!/usr/bin/env python3
"""Reduce completed native audit field artifacts from extracted directories or original ZIPs.

python3 reduce_hosted_fields.py <artifact-directory-or-zip> [...] --candidate <full-sha> --out <summary.json>
A directory may contain multiple extracted field artifacts. Detail-only fixtures are skipped.
The original plan, inputs, results, four field reports, checked reports and resources.json files
are sufficient for numeric replay. The optional replay ZIP also retains one common full runtime
hash manifest, matched against every shard. No PNG decoding or Godot installation is required.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import re
import tempfile
from pathlib import Path
import statistics
import zipfile


BASE = "71306784a250d634854f0c8bab3a927cc46a61b8"
FIRST_CANDIDATE = "9d4569310ef223fc129472a20e21aada8ea624f0"
ORDER = ["baseline", "candidate", "candidate", "baseline"]
METHODS = {"gl_compatibility": "Compatibility", "forward_plus": "Forward+"}
CASES = ("lake_shore", "lake_overview", "pilot_north", "plain_highway", "plain_field_entry", "postcard_pavilion")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def percentile(values, quantile):
    """Nearest-rank quantile, matching the capture reducer's p95."""
    return sorted(values)[math.ceil(quantile * len(values)) - 1]


def timing(intervals, cpu, gpu):
    positive_cpu = [v for v in cpu if v > 0]
    positive_gpu = [v for v in gpu if v > 0]
    return {
        "wall_intervals": len(intervals),
        "loop_throughput_fps": 1000 * len(intervals) / sum(intervals),
        "median_instantaneous_loop_fps": statistics.median(1000 / v for v in intervals),
        "wall_p50_ms": statistics.median(intervals), "wall_p95_ms": percentile(intervals, 0.95),
        "viewport_cpu_positive_polls": len(positive_cpu),
        "viewport_cpu_positive_poll_p50_ms": statistics.median(positive_cpu) if positive_cpu else None,
        "viewport_gpu_positive_polls": len(positive_gpu),
        "viewport_gpu_positive_poll_p50_ms": statistics.median(positive_gpu) if positive_gpu else None,
    }


@contextmanager
def artifact(source):
    if source.is_dir():
        entries = {file.relative_to(source).as_posix() for file in source.rglob("*.json")}
        yield entries, lambda name: (source / name).read_bytes()
    else:
        with zipfile.ZipFile(source) as archive:
            require(len(archive.namelist()) == len(set(archive.namelist())), "Duplicate ZIP entries")
            yield set(archive.namelist()), archive.read


def read_capture(source, expected_candidate):
    with artifact(source) as (entries, read):
        def document(name):
            return json.loads(read(name))
        result = document("results.json")
        workload = result["workload"]
        if not workload.startswith("field:"):
            return None
        case = workload.removeprefix("field:")
        plan, inputs = document("plan.json"), document("inputs.json")
        require(case in CASES and result["completed"] is True and result["order"] == ORDER, "Incomplete field ABBA")
        require(plan["workload"] == workload and plan["base"] == inputs["base"] == BASE, "Baseline/workload mismatch")
        require(plan["candidate_head"] == inputs["candidate"] == expected_candidate, "Candidate mismatch")
        require(plan["warmup_frames_per_case"] == 60 and plan["first_interval_excluded"] is True, "Warmup mismatch")
        require(inputs["software_renderer"] is True and inputs["hardware_performance_qualified"] is False,
                "Unexpected performance qualification")
        require(plan["env"]["LP_NUM_THREADS"] == "2" and inputs["host"]["machine"], "Missing host or Mesa configuration")
        require(len(inputs["shader_sha256"]) == 10 and inputs["candidate_runtime_inputs"] > 0, "Wrong shader input scope")
        require(len(result["observations"]) == len(plan["blocks"]) == 4, "Missing launch")
        method = None
        common = result["observations"][0]["field"]["conditions"]
        device = result["observations"][0]["field"]["device"]
        launches, by_side = [], {side: [[], [], []] for side in ("baseline", "candidate")}
        for idx, (block, obs, side) in enumerate(zip(plan["blocks"], result["observations"], ORDER, strict=True), 1):
            prefix = f"{idx}-{side}"
            require(block["block"] == prefix and block["variant"] == side and block["field_cases"] == [case],
                    f"Wrong case or order in {prefix}")
            cmd = block["commands"]["field"]
            actual = cmd[cmd.index("--rendering-method") + 1]
            require(actual in METHODS and (method is None or actual == method), "Inconsistent renderer")
            method = actual
            field = obs["field"]
            require(field["conditions"] == common and field["device"] == device, f"Unmatched conditions at {prefix}")
            require(METHODS[method] in device and any(x in device.lower() for x in ("llvmpipe", "lavapipe")),
                    "Unidentified software backend")
            require(all(flag in cmd for flag in ("--resources", "--frames=31", "--motion=off", "--measure_render_time=on",
                                                  "--cases=" + case, "--width=1920", "--height=1080")), "Changed sampling route")
            field_path = prefix + "/field/report.json"
            raw = document(field_path)
            require((raw["width"], raw["height"]) == (1920, 1080) and list(raw["cases"]) == [case], "Wrong raw view")
            row = raw["cases"][case]
            require(row["timing_valid"] is True and row["render_timing_enabled"] is True, "Unmeasured rendering")
            polls = [row[key] for key in ("frame_ms_raw", "viewport_cpu_ms_raw", "viewport_gpu_ms_raw")]
            require(all(len(seq) == 31 and all(type(v) in (int, float) and math.isfinite(v) and v >= 0 for v in seq)
                        for seq in polls) and min(polls[0]) > 0, "Incomplete or invalid raw intervals")
            usable = [seq[1:] for seq in polls]
            for pool, seq in zip(by_side[side], usable, strict=True):
                pool.extend(seq)
            times = timing(*usable)
            captured = field["cases"][case]
            require(math.isclose(captured["throughput_fps"], times["loop_throughput_fps"]) and
                    math.isclose(captured["median_render_loop_fps"], times["median_instantaneous_loop_fps"]),
                    "Recomputed wall rate differs from observation")
            checked = [name for name in entries if name.startswith(prefix + "/checks/field/") and name.endswith("/report.json")]
            require(len(checked) == 1, "Missing or duplicate checked field launch")
            check = document(checked[0])
            resource_path = checked[0].removesuffix("report.json") + "resources.json"
            resource_bytes = read(resource_path)
            resources = json.loads(resource_bytes)
            require(check["ok"] is True and check["complete"] is True and check["process_exit"] == 0 and
                    resources["capture_id"] == check["capture_id"] and sha(resource_bytes) == check["resources"]["sha256"],
                    "Invalid field process/resource provenance")
            summary = resources["summary"]
            peak_rss = summary["peaks"]["rss_bytes"]
            cpu_s = sum(summary["counter_deltas"][key] for key in ("cpu_user_seconds", "cpu_system_seconds"))
            process = field["process_including_startup_and_selected_cases"]
            require(peak_rss == process["sampled_peak_rss_bytes"] and math.isclose(cpu_s, process["sampled_cpu_seconds"])
                    and resources["sample_count"] == process["sample_count"] >= 2
                    and process["coverage"] == resources["required_coverage"], "Process telemetry mismatch")
            launches.append({"block": prefix, "variant": side, **times, "engine_video_memory_bytes": row["video_memory"],
                             "draw_calls": row["draws"], "visible_draws": row["visible_draws"],
                             "shadow_draws": row["shadow_draws"], "primitives": row["primitives"],
                             "sampled_direct_process_peak_rss_bytes": peak_rss, "sampled_direct_process_cpu_s": cpu_s,
                             "direct_process_samples": resources["sample_count"], "process_elapsed_s": check["elapsed_seconds"],
                             "resource_sampler": {key: resources[key] for key in
                                ("measurement_status", "required_coverage", "required_field_counts", "stop_reason",
                                 "error_count", "errors", "errors_truncated", "capped")},
                             "capture_id": check["capture_id"], "field_report_sha256": sha(read(field_path)),
                             "process_resource_sha256": sha(resource_bytes)})
        f = [row["loop_throughput_fps"] for row in launches]
        pair = result["pairs"]["field-" + case]
        return {"renderer": method, "case": case, "device": device, "host": inputs["host"],
                "mesa_worker_thread_limit": int(plan["env"]["LP_NUM_THREADS"]), "base": BASE, "candidate": expected_candidate,
                "runtime_manifest_sha256": inputs["candidate_runtime_manifest_sha256"],
                "inputs_sha256": sha(read("inputs.json")), "results_sha256": sha(read("results.json")),
                "baseline_pixels_repeat_identically": pair["baseline_repeat_rgb_identical"],
                "candidate_pixels_repeat_identically": pair["candidate_repeat_rgb_identical"],
                "launches": launches, "pooled_by_variant": {side: timing(*pool) for side, pool in by_side.items()},
                "paired_throughput_change_pct": [100 * (f[b] / f[a] - 1) for a, b in ((0, 1), (3, 2))]}


def write_replay(output, sources, candidate):
    """Save exactly the numeric inputs used by the reducer and their original bytes."""
    entries = []
    origins = []
    shared_runtime = None
    runtime_name = "runtime-input-sha256.json"
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix="replay-", suffix=".zip", delete=False) as temp:
        staged = Path(temp.name)
    try:
        with zipfile.ZipFile(staged, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            def add(name, data):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            for (renderer, case), source in sorted(sources.items()):
                with artifact(source) as (files, read):
                    if runtime_name in files:
                        runtime = read(runtime_name)
                    elif source.is_dir():
                        # An extracted replay stores one shared copy above <renderer>/field-<case>/.
                        runtime = (source.parent.parent / runtime_name).read_bytes()
                    else:
                        raise ValueError("Missing runtime input hash manifest in original archive")
                    inputs = json.loads(read("inputs.json"))
                    require(sha(runtime) == inputs["candidate_runtime_manifest_sha256"] and
                            len(json.loads(runtime)) == inputs["candidate_runtime_inputs"] == 7858,
                            "Invalid runtime manifest identity or file count")
                    require(shared_runtime is None or runtime == shared_runtime, "Shards used different runtime inputs")
                    shared_runtime = runtime
                    names = {"plan.json", "inputs.json", "results.json"}
                    for i, side in enumerate(ORDER, 1):
                        block = f"{i}-{side}"
                        names.add(block + "/field/report.json")
                        matches = [f for f in files if f.startswith(block + "/checks/field/") and f.endswith("/report.json")]
                        require(len(matches) == 1, "Incomplete checked report in replay")
                        names.update([matches[0], matches[0].removesuffix("report.json") + "resources.json"])
                    for name in sorted(names):
                        data = read(name)
                        member = renderer + "/field-" + case + "/" + name
                        add(member, data)
                        entries.append({"member": member, "sha256": sha(data), "bytes": len(data)})
                receipt = source.parent / (source.name + "-download.json")
                if source.is_dir() and receipt.is_file():
                    origin = json.loads(receipt.read_bytes())
                    require(origin["external_sha256_verified"], "Unverified original artifact archive")
                    origins.append({"renderer": renderer, "case": case, "github_artifact_id": int(origin["artifact_id"]),
                                    "original_zip_sha256": origin["zip_sha256"], "original_zip_bytes": origin["zip_bytes"]})
            require(shared_runtime is not None, "Missing shared runtime provenance")
            add(runtime_name, shared_runtime)
            entries.append({"member": runtime_name, "sha256": sha(shared_runtime), "bytes": len(shared_runtime)})
            record = {"format": "OpenRC exact original field JSON replay v1", "candidate": candidate, "base": BASE,
                      "original_archives": origins, "members": entries}
            manifest = (json.dumps(record, indent=2) + "\n").encode()
            add("MANIFEST.json", manifest)
        with staged.open("rb") as data:
            archive_digest = hashlib.file_digest(data, "sha256").hexdigest()
        staged.replace(output)
        receipt = {"archive": output.name, "zip_bytes": output.stat().st_size, "zip_sha256": archive_digest,
                   "embedded_manifest_sha256": sha(manifest), "candidate": candidate, "base": BASE,
                   "field_shards": len(sources), "raw_json_files": len(entries), "original_archives": origins,
                   "shared_runtime_manifest_sha256": sha(shared_runtime), "runtime_inputs": 7858}
        output.with_name(output.stem + "-manifest.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    finally:
        staged.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path, nargs="+")
    parser.add_argument("--candidate", default=FIRST_CANDIDATE,
                        help="expected full Git SHA for all inputs (default: first reviewed candidate)")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--replay-zip", type=Path, help="write a deterministic minimal raw JSON replay and digest manifest")
    parser.add_argument("--require-all", action="store_true", help="require all six field cases for both renderers")
    args = parser.parse_args()
    if not re.fullmatch("[0-9a-f]{40}", args.candidate):
        parser.error("--candidate must be one full lowercase 40-hex Git commit SHA")
    sources = set()
    for path in args.artifacts:
        if path.is_file():
            sources.add(path.resolve())
        elif path.is_dir():
            sources.update(report.parent.resolve() for report in path.rglob("results.json"))
        else:
            parser.error(f"Missing artifact {path}")
    groups, provenance = {}, {}
    for source in sorted(sources):
        capture = read_capture(source, args.candidate)
        if capture:
            key = capture["renderer"], capture["case"]
            require(key not in groups, f"Duplicate field artifact: {key}")
            groups[key] = capture
            provenance[key] = source
    require(groups, "No completed field artifacts")
    if args.require_all:
        require(set(groups) == {(method, case) for method in METHODS for case in CASES}, "Missing field shards")
    summary = {"format": "OpenRC native software-rendered field performance v1", "candidate": args.candidate,
               "base": BASE, "completed_field_shards": len(groups),
               "scope": {
                   "wall": "1920x1080 post-draw render-loop intervals. First interval excluded on every launch.",
                   "pool": "ABBA on one VM per case/renderer. Each variant pool has 60 intervals from its two launches.",
                   "viewport_cpu": "Positive engine viewport CPU polls. GLES3 measures elapsed host ticks around viewport rendering, including waits. Poll age and uniqueness are unverified.",
                   "viewport_gpu": "Positive backend GPU polls only. Per-frame association, sample age and uniqueness are unverified.",
                   "process": "Direct Godot process sampled at 1 Hz across launch and teardown. Reported CPU seconds sum changes in user and system counters between sampled observations. RSS peak is the highest observed sample. Work and peaks between observations can be missed; each launch retains sampler coverage, stop reason and errors.",
                   "memory": "Engine-reported video allocations and sampled process RSS are different counters on shared system RAM.",
                   "hardware": "Mesa software rasterization. CPU model and core count were not recorded. Host kernel and architecture come from the input receipt. Compare each case within its own renderer/VM ABBA job."},
               "captures": [groups[k] for k in sorted(groups)]}
    if args.replay_zip:
        write_replay(args.replay_zip, provenance, args.candidate)
    data = json.dumps(summary, indent=2, allow_nan=False) + "\n"
    if args.out:
        args.out.write_text(data, encoding="utf-8")
    else:
        print(data, end="")


if __name__ == "__main__":
    main()
