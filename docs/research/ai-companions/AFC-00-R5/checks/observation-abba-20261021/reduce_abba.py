"""Offline integrity reducer for the single AFC observation ABBA run."""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys


def nearest_rank(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    index = max(0, min(len(values) - 1, math.ceil(len(values) * percentile) - 1))
    return values[index]


def summary(values: list[float]) -> dict:
    ordered = sorted(values)
    return {
        "block_count": len(ordered),
        "mean_of_block_means_usec_per_call": sum(ordered) / len(ordered) if ordered else 0.0,
        "p50_block_mean_usec_per_call": nearest_rank(ordered, 0.50),
        "p95_block_mean_usec_per_call": nearest_rank(ordered, 0.95),
        "p99_block_mean_usec_per_call": nearest_rank(ordered, 0.99),
        "min_block_mean_usec_per_call": ordered[0] if ordered else 0.0,
        "max_block_mean_usec_per_call": ordered[-1] if ordered else 0.0,
        "percentile_method": "nearest rank: sorted[ceil(n*p)-1]",
    }


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: reduce_abba.py <raw-probe-report.json> <verification.json>")
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    report = json.loads(source.read_text(encoding="utf-8"))
    expected_rounds = int(report["measured_abba_rounds"])
    expected_calls = int(report["block_calls"])
    samples = report["raw_block_samples"]
    assert report["complete"] and not report["timed_out"]
    assert report["prepared_tick"] == report["prepared_ticks"] == 1200
    assert report["prepared_time_s"] == 5.0 and report["prepared_after_gust_delay"]
    assert report["measured_calls_baseline"] == report["measured_calls_candidate"] == expected_rounds * 2 * expected_calls
    assert report["source_identity"]["all_pinned_source_bytes_unchanged"]
    assert report["source_identity"]["sha256_before"] == report["source_identity"]["sha256_after"]
    assert len(samples) == expected_rounds * 4

    by_round: dict[int, dict[str, dict]] = {}
    baseline: list[float] = []
    candidate: list[float] = []
    for sample in samples:
        round_index = int(sample["round"])
        position = str(sample["position"])
        variant = str(sample["variant"])
        assert 0 <= round_index < expected_rounds
        assert sample["calls"] == expected_calls
        assert sample["elapsed_usec"] >= 0
        value = float(sample["elapsed_usec"]) / expected_calls
        assert sample["block_mean_usec_per_call"] == value
        expected_variant = "production_agent" if position in {"A1", "A2"} else "candidate_subclass"
        assert variant == expected_variant
        round_samples = by_round.setdefault(round_index, {})
        assert position not in round_samples
        round_samples[position] = sample
        (baseline if variant == "production_agent" else candidate).append(value)

    expected_positions = {"A1", "B1", "B2", "A2"}
    assert len(baseline) == len(candidate) == expected_rounds * 2
    assert all(set(row) == expected_positions for row in by_round.values())
    parity = report["parity_checks_outside_timed_blocks"]
    assert len(parity) == expected_rounds
    assert [row["round"] for row in parity] == list(range(expected_rounds))
    assert all(row["equal"] and row["state_unchanged"] for row in parity)
    assert len({row["state_fingerprint"] for row in parity}) == 1

    ratios = []
    for round_index in range(expected_rounds):
        row = by_round[round_index]
        baseline_mean = (row["A1"]["elapsed_usec"] + row["A2"]["elapsed_usec"]) / (2 * expected_calls)
        candidate_mean = (row["B1"]["elapsed_usec"] + row["B2"]["elapsed_usec"]) / (2 * expected_calls)
        ratio = candidate_mean / baseline_mean if baseline_mean else 0.0
        ratios.append({
            "round": round_index,
            "baseline_abba_paired_block_mean_usec_per_call": baseline_mean,
            "candidate_abba_paired_block_mean_usec_per_call": candidate_mean,
            "candidate_over_baseline_ratio": ratio,
        })

    ratio_values = sorted(row["candidate_over_baseline_ratio"] for row in ratios)
    ratio_summary = {
        "paired_round_count": len(ratios),
        "mean_candidate_over_baseline_ratio": sum(ratio_values) / len(ratio_values),
        "p05_candidate_over_baseline_ratio": nearest_rank(ratio_values, 0.05),
        "p50_candidate_over_baseline_ratio": nearest_rank(ratio_values, 0.50),
        "p95_candidate_over_baseline_ratio": nearest_rank(ratio_values, 0.95),
        "min_candidate_over_baseline_ratio": ratio_values[0],
        "max_candidate_over_baseline_ratio": ratio_values[-1],
        "percentile_method": "nearest rank across round-paired ABBA block means",
        "definition": "((B1 elapsed + B2 elapsed) / 2) / ((A1 elapsed + A2 elapsed) / 2); equal call counts cancel",
    }
    result = {
        "format": "openrc-afc-observation-abba-offline-verification v1",
        "complete": True,
        "raw_sample_count": len(samples),
        "raw_samples_per_arm": {"production_agent": len(baseline), "candidate_subclass": len(candidate)},
        "measured_calls_per_arm": {"production_agent": report["measured_calls_baseline"], "candidate_subclass": report["measured_calls_candidate"]},
        "snapshot_checks": {"rounds": len(parity), "all_byte_equal": True, "all_state_unchanged": True,
                            "unique_state_fingerprints": 1, "warmup_parity_passed": report["complete"]},
        "source_checks": {"all_source_bytes_unchanged": True, "source_identity_count": len(report["source_identity"]["sha256_before"])},
        "block_mean_summary": {"production_agent": summary(baseline), "candidate_subclass": summary(candidate)},
        "paired_round_ratio_summary": ratio_summary,
        "paired_round_ratios": ratios,
        "interpretation_limit": "This is one observation-method microbenchmark on one prepared state and host. Ratios describe paired blocks, not a causal whole-flight or render-frame speedup.",
    }
    destination.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"complete": result["complete"], "samples": len(samples),
                      "samples_per_arm": result["raw_samples_per_arm"],
                      "paired_rounds": len(ratios), "ratio_summary": ratio_summary}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
