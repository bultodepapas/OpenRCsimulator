"""Summarize the disposable HELI skid surface-lookup ABBA experiment."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROJECT = ROOT / "tmp" / "heli-ground-contact-candidate-20261014" / "project"
RAW: Path | None = None
OUT = ROOT / "docs" / "research" / "helicopter" / "HELI-20" / "optimization" / "run-2"
CASES = ["stoppedground", "12ssoftspool", "governedground", "legacyairbornehover"]
EXPECTED_TICKS = {
    "stoppedground": 1200,
    "12ssoftspool": 2880,
    "governedground": 1200,
    "legacyairbornehover": 1200,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nearest_rank(values: list[int], percentile: float) -> int:
    ordered = sorted(values)
    rank = max(1, math.ceil(len(ordered) * percentile))
    return ordered[min(len(ordered), rank) - 1]


def summarize(values: list[int]) -> dict[str, int]:
    return {
        "raw_ticks": len(values),
        "accepted_ticks": len(values),
        "p50_usec": nearest_rank(values, 0.50),
        "p95_usec": nearest_rank(values, 0.95),
        "p99_usec": nearest_rank(values, 0.99),
        "max_usec": max(values),
        "min_usec": min(values),
    }


def source_paths() -> list[Path]:
    relative = [
        Path("project.godot"),
        Path("data/field_loader.gd"),
        Path("data/fields/default.json"),
        Path("data/ground/surface_friction.json"),
        Path("data/aircraft/xcell_60_research.json"),
        Path("physics/rotorcraft/skid_contact_candidate.gd"),
        Path("physics/rotorcraft/skid_contact.gd"),
        Path("sim/helicopter_flight_session_candidate.gd"),
        Path("sim/helicopter_flight_session.gd"),
        Path("research/helicopter/ground_start/contact_abba.gd"),
    ]
    for dirname in ("physics", "sim", "input"):
        relative.extend(
            path.relative_to(PROJECT)
            for path in (PROJECT / dirname).rglob("*.gd")
            if ".godot" not in path.parts
        )
    return sorted({PROJECT / path for path in relative if (PROJECT / path).is_file()})


def git_head() -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main() -> None:
    global PROJECT, RAW, OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=PROJECT,
                        help="disposable project copy used by the probe")
    parser.add_argument("--raw", type=Path, default=None,
                        help="raw JSON emitted by contact_abba.gd; defaults inside --project")
    parser.add_argument("--out", type=Path, default=OUT,
                        help="directory for summary and per-tick samples")
    args = parser.parse_args()
    PROJECT = args.project.resolve()
    RAW = args.raw.resolve() if args.raw is not None else PROJECT / "ground_contact_abba_raw.json"
    OUT = args.out.resolve()
    if not PROJECT.is_dir() or not RAW.is_file():
        parser.error("--project and --raw must identify an existing disposable run")
    OUT.mkdir(parents=True, exist_ok=True)
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    segments = raw.get("segments", [])
    if not raw.get("complete"):
        raise RuntimeError(f"The Godot probe is incomplete: {raw.get('error', '')}")
    if len(segments) != 16:
        raise RuntimeError(f"Expected 16 measured segments, got {len(segments)}")

    by_pair: dict[tuple[str, int], dict[str, dict]] = {}
    samples: list[dict] = []
    pooled: dict[tuple[str, str], list[int]] = {}
    pair_summaries: list[dict] = []
    for segment in segments:
        case = str(segment["case"])
        pair = int(segment["pair"])
        variant = str(segment["variant"])
        timings = [int(value) for value in segment["elapsed_usec"]]
        if case not in EXPECTED_TICKS or len(timings) != EXPECTED_TICKS[case]:
            raise RuntimeError(f"Unexpected tick count in {case} pair {pair} variant {variant}")
        if int(segment["accepted_ticks"]) != len(timings):
            raise RuntimeError(f"Accepted tick count disagrees in {case} pair {pair} variant {variant}")
        by_pair.setdefault((case, pair), {})[variant] = segment
        pooled.setdefault((case, variant), []).extend(timings)
        pair_summaries.append({
            "case": case,
            "pair": pair,
            "variant": variant,
            "order": segment["order"],
            "start_tick": segment["start_tick"],
            "end_tick": segment["end_tick"],
            "final_power_phase": segment["final_power_phase"],
            **summarize(timings),
        })
        for index, elapsed in enumerate(timings):
            samples.append({
                "case": case,
                "pair": pair,
                "order": "".join(segment["order"]),
                "variant": variant,
                "sample_index": index,
                "tick": int(segment["start_tick"]) + index + 1,
                "elapsed_usec": elapsed,
                "accepted": True,
            })

    parity: list[dict] = []
    for case in CASES:
        for pair in (1, 2):
            variants = by_pair.get((case, pair), {})
            if set(variants) != {"A", "B"}:
                raise RuntimeError(f"Missing A/B pair for {case} #{pair}")
            a = variants["A"]["signature_sha256"]
            b = variants["B"]["signature_sha256"]
            exact = {key: a[key] == b[key] for key in ("state", "aux", "continuous", "phase")}
            if not all(exact.values()):
                raise RuntimeError(f"A/B byte-stream hashes differ: {case} #{pair}: {exact}")
            expected_order = ["A", "B"] if pair == 1 else ["B", "A"]
            if variants["A"]["order"] != expected_order or variants["B"]["order"] != expected_order:
                raise RuntimeError(f"Unexpected order for {case} #{pair}")
            parity.append({"case": case, "pair": pair, "order": expected_order,
                           "state_aux_continuous_phase_byte_parity": exact})

    scenarios = []
    for case in CASES:
        a = summarize(pooled[(case, "A")])
        b = summarize(pooled[(case, "B")])
        scenarios.append({
            "case": case,
            "pairs": 2,
            "ticks_per_segment": EXPECTED_TICKS[case],
            "baseline_A": a,
            "candidate_B": b,
            "candidate_delta_usec": {
                "p50": b["p50_usec"] - a["p50_usec"],
                "p95": b["p95_usec"] - a["p95_usec"],
            },
        })

    source_hashes = {
        path.relative_to(PROJECT).as_posix(): sha256(path)
        for path in source_paths()
    }
    source_fingerprint = hashlib.sha256(
        json.dumps(source_hashes, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    production_comparison = {}
    for relative in (
        "project.godot",
        "physics/rotorcraft/skid_contact.gd",
        "sim/helicopter_flight_session.gd",
        "sim/simulation.gd",
        "physics/rotorcraft/simulation_step_adapter.gd",
        "physics/ground_contact.gd",
        "physics/ground_terrain.gd",
        "physics/ground_surfaces.gd",
    ):
        source = PROJECT / relative
        live = ROOT / "app" / relative
        if source.is_file() and live.is_file():
            clone_hash = sha256(source)
            live_hash = sha256(live)
            production_comparison[relative] = {
                "disposable_baseline_sha256": clone_hash,
                "live_app_sha256_after_run": live_hash,
                "matches": clone_hash == live_hash,
            }

    raw_copy = OUT / "samples_raw_godot.json"
    raw_copy.write_bytes(RAW.read_bytes())
    (OUT / "samples.json").write_text(json.dumps(samples, indent=2) + "\n", encoding="utf-8")
    with (OUT / "samples.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(samples[0]))
        writer.writeheader()
        writer.writerows(samples)
    report = {
        "format": "heli-ground-contact-abba-performance-v1",
        "run_date": "2026-10-14",
        "summarized_utc": datetime.now(timezone.utc).isoformat(),
        "complete": True,
        "timed_operation": "session.sim.step() per accepted fixed tick",
        "tick_rate_hz": raw["tick_rate_hz"],
        "tick_duration_s": raw["tick_duration_s"],
        "percentile_method": "nearest rank: ceil(p*n), one-indexed",
        "source_fingerprint_sha256": source_fingerprint,
        "source_sha256": source_hashes,
        "production_vs_disposable_baseline_after_run": production_comparison,
        "environment": {
            "godot_version": "4.7.2.stable.official.ed1daf0bf",
            "os": platform.platform(),
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "logical_cpu_count": os.cpu_count(),
            "git_head_at_summary": git_head(),
        },
        "host_load_note": raw["host_load_note"],
        "accepted_tick_observer": raw["accepted_tick_observer"],
        "control_trace_recording": raw["control_trace_recording"],
        "comparison_design": raw["order_design"],
        "sample_streams": {
            "raw_godot": raw_copy.name,
            "flat_samples_json": "samples.json",
            "flat_samples_csv": "samples.csv",
            "raw_tick_count": len(samples),
        },
        "byte_parity": parity,
        "pair_summaries": pair_summaries,
        "scenarios": scenarios,
        "qualification": {
            "h15_qualification": False,
            "note": "Concurrent development timing only. It does not qualify flight performance or establish a reliable speedup under controlled host load.",
        },
    }
    (OUT / "performance.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# HELI ground-contact temporary A/B experiment",
        "",
        "Candidate: reuse one `GroundContact.surface_at` result within a single skid RK-stage evaluation.",
        "The copied Session and Skids sources were measured in a disposable project; production files were not edited.",
        "",
        "Godot 4.7.2; 240 Hz; AB then BA, two pairs per scenario. Each timing surrounds the full `session.sim.step()` call.",
        "State, aux, 14/6 continuous values, and shaft phase were byte-compared at every accepted tick; all paired hashes match.",
        raw["host_load_note"],
        "",
        "| Regime | A ticks | A p50 / p95 (µs) | B ticks | B p50 / p95 (µs) | Δ p50 / p95 (µs) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for row in scenarios:
        a = row["baseline_A"]
        b = row["candidate_B"]
        delta = row["candidate_delta_usec"]
        lines.append(
            f"| {row['case']} | {a['raw_ticks']} | {a['p50_usec']} / {a['p95_usec']} | "
            f"{b['raw_ticks']} | {b['p50_usec']} / {b['p95_usec']} | "
            f"{delta['p50']:+d} / {delta['p95']:+d} |"
        )
    lines += [
        "",
        f"Source fingerprint: `{source_fingerprint}`.",
        "See `performance.json` for per-file SHA-256, exact parity evidence, pair summaries, and disposable-versus-live source comparison.",
        "",
        "This development run is not H15 qualification and is not evidence of a physical-model improvement.",
    ]
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(OUT),
        "source_fingerprint_sha256": source_fingerprint,
        "scenarios": [{
            "case": row["case"],
            "A_ticks": row["baseline_A"]["raw_ticks"],
            "A_p50_p95_usec": [row["baseline_A"]["p50_usec"], row["baseline_A"]["p95_usec"]],
            "B_ticks": row["candidate_B"]["raw_ticks"],
            "B_p50_p95_usec": [row["candidate_B"]["p50_usec"], row["candidate_B"]["p95_usec"]],
            "delta_p50_p95_usec": [row["candidate_delta_usec"]["p50"], row["candidate_delta_usec"]["p95"]],
        } for row in scenarios],
        "parity_pairs": len(parity),
        "production_source_matches": production_comparison,
    }, indent=2))


if __name__ == "__main__":
    main()
