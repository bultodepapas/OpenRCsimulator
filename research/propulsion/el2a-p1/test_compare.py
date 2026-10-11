#!/usr/bin/env python3
"""Pure contract tests for the EL2a-P1 report comparator."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compare  # noqa: E402


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def benchmark_report(batches: int = 2, timing_scale: float = 1.0) -> dict:
    rows = []
    for case_id, family in compare.EXPECTED_CASE_FAMILIES.items():
        for mode in ("powered", "coast"):
            key = f"{case_id}:{mode}".encode()
            seed = b"seed:" + key
            endpoint = b"endpoint:" + key
            samples = [100.0 * timing_scale + i for i in range(batches)]
            batch_rows = [{
                "index": i,
                "completed_ticks": 120,
                "elapsed_us": int(samples[i] * 120),
                "us_per_tick": samples[i],
                "checkpoint_bytes": len(endpoint),
                "checkpoint_native_hex": endpoint.hex(),
                "checkpoint_sha256": sha(endpoint),
            } for i in range(batches)]
            rows.append({
                "ok": True, "type": family, "id": case_id, "family": family,
                "mode": mode, "engine_running": mode == "powered",
                "warmup_ticks": 240, "ticks_per_batch": 120, "batch_count": batches,
                "completed_batch_count": batches,
                "seed_checkpoint_bytes": len(seed), "seed_checkpoint_native_hex": seed.hex(),
                "seed_checkpoint_sha256": sha(seed),
                "median_us_per_tick": (samples[(batches - 1) // 2] + samples[batches // 2]) / 2,
                "p95_us_per_tick": samples[-1], "batch_checkpoint_bytes_identical": True,
                "batches": batch_rows,
                "trajectory_fingerprint": {
                    "ok": True, "ticks": 120, "includes_initial_checkpoint": True,
                    "sha256": sha(b"trajectory:" + key),
                    "endpoint_checkpoint_sha256": sha(endpoint),
                },
            })
    return {
        "format": "openrc-el2a-p1-performance-bench-v1",
        "type": "whole_session_physics_tick_cost",
        "machine": {"os": "test", "architecture": "test", "processor": "test",
                    "logical_cpu_count": 1, "godot": {"major": 4}},
        "tick_hz": 240, "warmup_ticks": 240, "ticks_per_batch": 120,
        "batch_count": batches, "case_count": len(rows), "success_count": len(rows),
        "failure_count": 0, "successful_batch_count": len(rows) * batches, "cases": rows,
    }


def event_report(output: Path, mutate_endpoint: bool = False) -> dict:
    control = output / "control"
    control.mkdir(parents=True)
    rows = []
    for pack, hz in sorted(compare.EVENT_KEYS):
        seed = f"seed:{pack}:{hz}".encode()
        endpoint = f"checkpoint:{pack}:{hz}".encode()
        if mutate_endpoint and pack == "4s" and hz == 240:
            endpoint += b":changed"
        seed_name = f"seed_{pack}_{hz}.bin"
        end_name = f"checkpoint_{pack}_{hz}.bin"
        (control / seed_name).write_bytes(seed)
        (control / end_name).write_bytes(endpoint)
        rows.append({"pack": pack, "hz": hz, "ok": True, "all_finite": True,
                     "steps": round(0.05 * hz), "end_time_s": 0.05, "event_tick": hz,
                     "event_tick_wall_usec": 2500 + hz, "events": [],
                     "event_start_charge_c": 0.2 if pack == "4s" else 0.12,
                     "configured_initial_charge_c": 100.0,
                     "seed_checkpoint_file": seed_name, "seed_checkpoint_byte_count": len(seed),
                     "checkpoint_file": end_name, "checkpoint_byte_count": len(endpoint)})
    return {"format": "el2-powered-parity-v1", "mode": "control", "instrumented": False,
            "rates_hz": [120, 240, 480, 960], "end_time_s": 0.05, "failures": [], "rows": rows}


class ComparatorTests(unittest.TestCase):
    def test_valid_reports_keep_raw_samples_and_summarize_ratio(self) -> None:
        baseline, candidate = benchmark_report(), benchmark_report(timing_scale=1.2)
        result = compare.compare_benchmark_reports([baseline], [candidate], batches=2)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["case_count"], 12)
        self.assertTrue(result["all_batch_endpoint_bytes_identical"])
        self.assertAlmostEqual(result["cases"][0]["candidate_over_baseline_median_ratio"], 120.5 / 100.5)

    def test_missing_benchmark_case_is_rejected(self) -> None:
        report = benchmark_report()
        report["cases"].pop()
        with self.assertRaisesRegex(compare.CompareError, "12 benchmark cases"):
            compare.validate_benchmark_report(report, batches=2)

    def test_checkpoint_mutation_across_snapshots_fails_exact_comparison(self) -> None:
        baseline, candidate = benchmark_report(), benchmark_report()
        row = next(item for item in candidate["cases"] if item["id"] == "synthetic_stik_electric_4s"
                   and item["mode"] == "powered")
        changed = b"mutated endpoint checkpoint"
        for batch in row["batches"]:
            batch["checkpoint_native_hex"] = changed.hex()
            batch["checkpoint_bytes"] = len(changed)
            batch["checkpoint_sha256"] = sha(changed)
        row["trajectory_fingerprint"]["sha256"] = sha(b"mutated trajectory")
        row["trajectory_fingerprint"]["endpoint_checkpoint_sha256"] = sha(changed)
        result = compare.compare_benchmark_reports([baseline], [candidate], batches=2)
        self.assertEqual(result["status"], "failed")
        changed_row = next(item for item in result["cases"] if item["id"] == row["id"] and item["mode"] == "powered")
        self.assertFalse(changed_row["all_batch_endpoint_bytes_identical"])
        self.assertFalse(changed_row["trajectory_fingerprints_identical"])

    def test_corrupted_json_is_rejected_and_left_intact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "corrupt.json"
            path.write_text('{"format":', encoding="utf-8")
            with self.assertRaisesRegex(compare.CompareError, "valid JSON"):
                compare.read_json(path)
            self.assertEqual(path.read_text(encoding="utf-8"), '{"format":')

    def test_non_finite_metadata_number_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "non-finite.json"
            path.write_text('{"machine":{"logical_cpu_count":NaN}}', encoding="utf-8")
            with self.assertRaisesRegex(compare.CompareError, "non-finite JSON number"):
                compare.read_json(path)

    def test_version_output_must_be_one_exact_pinned_line(self) -> None:
        version = "4.7.2.stable.official.ed1daf0bf"
        self.assertEqual(compare.validate_godot_version_output(version + "\n"), version)
        for invalid in (version + "\nextra\n", "Godot Engine " + version, "4.7.2.dev.custom"):
            with self.subTest(output=invalid), self.assertRaisesRegex(compare.CompareError, "pinned 4.7.2"):
                compare.validate_godot_version_output(invalid)

    def test_command_return_code_exception_is_explicit_and_xdg_isolated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = "import os,sys; print(os.environ['XDG_CONFIG_HOME']); sys.exit(1)"
            command = [sys.executable, "-c", script]
            with self.assertRaisesRegex(compare.CompareError, "command exited 1"):
                compare.run_command(command, 10, root / "strict.log", xdg_root=root / "xdg-strict")
            output = compare.run_command(command, 10, root / "allowed.log", allowed_returncodes=(0, 1),
                                         xdg_root=root / "xdg-allowed")
            self.assertEqual(output.strip(), str(root / "xdg-allowed" / "config_home"))
            self.assertTrue((root / "xdg-allowed" / "data_home").is_dir())

    def test_event_checkpoint_file_mutation_fails_exact_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_dir, candidate_dir = root / "baseline-events", root / "candidate-events"
            baseline_dir.mkdir()
            candidate_dir.mkdir()
            baseline = event_report(baseline_dir)
            candidate = event_report(candidate_dir, mutate_endpoint=True)
            result = compare.compare_event_reports(baseline, candidate, baseline_dir, candidate_dir)
            self.assertEqual(result["status"], "failed")
            changed = next(row for row in result["rows"] if row["pack"] == "4s" and row["hz"] == 240)
            self.assertFalse(changed["endpoint_checkpoint_bytes_identical"])


if __name__ == "__main__":
    unittest.main()
