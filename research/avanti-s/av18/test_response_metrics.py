"""Analytic oracles for the bounded AV-18 response reducer."""

from __future__ import annotations

import csv
import io
import json
import math
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import response_metrics as metrics


SCRIPT = Path(__file__).with_name("response_metrics.py")


def linear_step_trial(
    *,
    direction: str = "up",
    command_edge_s: float = 1.0,
    ramp_start_s: float = 1.5,
    ramp_duration_s: float = 4.0,
    dwell_required_s: float = 0.1,
) -> metrics.Trial:
    f0, f1 = (2.0, 100.0) if direction == "up" else (100.0, 2.0)
    times = [i / 4 for i in range(27)]  # 0 to 6.5 s at 4 Hz, including a settled tail.
    samples = []
    for time_s in times:
        progress = min(1.0, max(0.0, (time_s - ramp_start_s) / ramp_duration_s))
        samples.append(metrics.Sample(time_s, f0 + progress * (f1 - f0)))
    return metrics.Trial(
        trial_id=f"{direction}-linear",
        command_edge_time_s=command_edge_s,
        command_before=0.0,
        command_after=1.0,
        f0_n=f0,
        f1_n=f1,
        rated_thrust_n=100.0,
        samples=tuple(samples),
        dwell_required_s=dwell_required_s,
    )


class ResponseMetricsTests(unittest.TestCase):
    def test_linear_step_separates_edge_latency_transition_and_rated_levels(self):
        trial = linear_step_trial()
        result = metrics.analyze_trial(trial)

        self.assertEqual(result["direction"], "up")
        progress = result["progress_crossings"]
        self.assertAlmostEqual(progress["10"]["crossing_time_s"], 1.9)
        self.assertAlmostEqual(progress["50"]["crossing_time_s"], 3.5)
        self.assertAlmostEqual(progress["90"]["crossing_time_s"], 5.1)
        self.assertAlmostEqual(progress["95"]["crossing_time_s"], 5.3)
        summary = result["summary"]
        self.assertAlmostEqual(summary["response_latency_to_10_progress_s"], 0.9)
        self.assertAlmostEqual(summary["command_to_95_progress_s"], 4.3)
        self.assertAlmostEqual(summary["transition_duration_10_to_95_progress_s"], 3.4)

        # Absolute rated-thrust crossings differ from F0-to-F1 progress levels.
        rated_5 = result["rated_thrust_crossings"]["5"]
        self.assertAlmostEqual(rated_5["level_n"], 5.0)
        self.assertAlmostEqual(rated_5["crossing_time_s"], 1.5 + 3.0 / 24.5)
        self.assertNotAlmostEqual(rated_5["crossing_time_s"], progress["10"]["crossing_time_s"])
        self.assertAlmostEqual(summary["transition_duration_5_to_95_percent_rated_s"], 3.673469387755102)
        self.assertEqual(summary["rated_5_to_95_order"], "5_to_95")

    def test_down_step_uses_response_progress_and_reverses_rated_order(self):
        trial = linear_step_trial(
            direction="down", ramp_start_s=1.25, ramp_duration_s=2.0
        )
        result = metrics.analyze_trial(trial)
        self.assertEqual(result["direction"], "down")
        progress = result["progress_crossings"]
        self.assertLess(progress["10"]["crossing_time_s"], progress["95"]["crossing_time_s"])
        self.assertAlmostEqual(result["summary"]["transition_duration_10_to_95_progress_s"], 1.7)
        self.assertEqual(result["summary"]["rated_5_to_95_order"], "95_to_5")
        self.assertGreater(
            result["rated_thrust_crossings"]["5"]["crossing_time_s"],
            result["rated_thrust_crossings"]["95"]["crossing_time_s"],
        )

    def test_exponential_response_matches_closed_form_on_irregular_samples(self):
        onset_s = 1.3
        tau_s = 1.5
        f0, f1 = 2.0, 100.0
        times = {0.0, 1.0, onset_s}
        steps = (0.07, 0.11, 0.09, 0.13)
        current = 0.0
        step_index = 0
        while current < 7.0:
            current += steps[step_index % len(steps)]
            times.add(min(current, 7.0))
            step_index += 1
        samples = tuple(
            metrics.Sample(
                time_s,
                f0 if time_s <= onset_s else f1 - (f1 - f0) * math.exp(-(time_s - onset_s) / tau_s),
            )
            for time_s in sorted(times)
        )
        trial = metrics.Trial(
            trial_id="exponential-oracle",
            command_edge_time_s=1.0,
            command_before=0.0,
            command_after=1.0,
            f0_n=f0,
            f1_n=f1,
            rated_thrust_n=100.0,
            samples=samples,
            dwell_required_s=0.1,
        )
        result = metrics.analyze_trial(trial)
        for percent in metrics.PROGRESS_LEVELS:
            expected = onset_s - tau_s * math.log1p(-percent / 100.0)
            self.assertAlmostEqual(
                result["progress_crossings"][str(percent)]["crossing_time_s"],
                expected,
                delta=0.01,
            )
        expected_duration = tau_s * math.log(18.0)
        self.assertAlmostEqual(
            result["summary"]["transition_duration_10_to_95_progress_s"],
            expected_duration,
            delta=0.02,
        )

    def test_reversal_reports_first_crossing_count_and_crossing_dwell(self):
        samples = tuple(
            metrics.Sample(t, y)
            for t, y in (
                (0.0, 0.0),
                (0.05, 0.0),
                (0.1, 0.0),
                (0.3, 20.0),
                (0.5, 0.0),
                (0.7, 40.0),
                (0.9, 100.0),
                (1.1, 100.0),
                (1.5, 100.0),
            )
        )
        trial = metrics.Trial(
            trial_id="overshoot-and-recovery",
            command_edge_time_s=0.1,
            command_before=0.0,
            command_after=1.0,
            f0_n=0.0,
            f1_n=100.0,
            rated_thrust_n=100.0,
            samples=samples,
            dwell_required_s=0.3,
        )
        first_ten = metrics.analyze_trial(trial)["progress_crossings"]["10"]
        self.assertAlmostEqual(first_ten["crossing_time_s"], 0.2)
        self.assertAlmostEqual(first_ten["crossing_dwell_s"], 0.2)
        self.assertFalse(first_ten["dwell_qualified"])
        self.assertEqual(first_ten["directional_crossing_count"], 2)
        self.assertEqual(first_ten["reverse_crossing_count"], 1)
        self.assertEqual(first_ten["sample_support_s"], [0.1, 0.3])

    def test_crossing_uncertainty_propagates_input_errors_and_edge_error(self):
        uncertain_times = {0.75, 1.75, 3.0}
        samples = tuple(
            metrics.Sample(
                time_s,
                thrust_n,
                time_uncertainty_s=0.0 if time_s in uncertain_times else None,
                thrust_uncertainty_n=1.0 if time_s in uncertain_times else None,
            )
            for time_s, thrust_n in (
                (0.0, 0.0),
                (0.25, 0.0),
                (0.5, 0.0),
                (0.75, 40.0),
                (1.75, 60.0),
                (2.0, 70.0),
                (3.0, 100.0),
                (4.0, 100.0),
            )
        )
        trial = metrics.Trial(
            trial_id="uncertainty-oracle",
            command_edge_time_s=0.5,
            command_before=0.0,
            command_after=1.0,
            f0_n=0.0,
            f1_n=100.0,
            rated_thrust_n=100.0,
            command_edge_uncertainty_s=0.02,
            f0_uncertainty_n=1.0,
            f1_uncertainty_n=1.0,
            rated_thrust_uncertainty_n=1.0,
            samples=samples,
            dwell_required_s=0.1,
        )
        result = metrics.analyze_trial(trial)
        crossing = result["progress_crossings"]["50"]
        self.assertAlmostEqual(crossing["crossing_time_s"], 1.25)
        self.assertAlmostEqual(crossing["crossing_time_standard_uncertainty_s"], 0.05)
        self.assertAlmostEqual(crossing["after_command_standard_uncertainty_s"], math.sqrt(0.0029))
        self.assertEqual(crossing["sample_support_s"], [0.75, 1.75])
        self.assertAlmostEqual(crossing["sample_support_width_s"], 1.0)

    def test_rejects_nonfinite_nonmonotone_and_insufficient_samples(self):
        base = linear_step_trial()
        with self.assertRaisesRegex(metrics.InputError, "strictly increasing"):
            metrics.analyze_trial(replace(base, samples=(base.samples[0], base.samples[0], *base.samples[2:])))

        bad_sample = replace(base.samples[3], thrust_n=float("nan"))
        with self.assertRaisesRegex(metrics.InputError, "must be finite"):
            metrics.analyze_trial(replace(base, samples=(*base.samples[:3], bad_sample, *base.samples[4:])))

        short = replace(
            base,
            samples=(base.samples[0], base.samples[1], base.samples[4], base.samples[-1]),
        )
        with self.assertRaisesRegex(metrics.InputError, "insufficient samples"):
            metrics.analyze_trial(short)

        with self.assertRaisesRegex(metrics.InputError, "sample gap .* exceeds"):
            metrics.analyze_trial(replace(base, max_sample_gap_s=0.24))

    def test_rejects_trace_missing_a_required_progress_crossing(self):
        base = linear_step_trial()
        samples = tuple(
            replace(sample, thrust_n=sample.thrust_n if sample.time_s < 3.5 else 50.0)
            for sample in base.samples
        )
        with self.assertRaisesRegex(metrics.InputError, "does not cross normalized progress level"):
            metrics.analyze_trial(replace(base, samples=samples))

    def test_rejects_capture_that_ends_before_requested_dwell_window(self):
        with self.assertRaisesRegex(metrics.InputError, "capture ends before the 3 s dwell window"):
            metrics.analyze_trial(replace(linear_step_trial(), dwell_required_s=3.0))

    def test_json_rejects_duplicate_keys_and_nonfinite_literals(self):
        with self.assertRaisesRegex(metrics.InputError, "duplicate key"):
            metrics.load_json_document(io.StringIO('{"schema":"x","schema":"y"}'))
        with self.assertRaisesRegex(metrics.InputError, "non-finite"):
            metrics.load_json_document(io.StringIO('{"schema":"x","value":NaN}'))

    def test_csv_cli_writes_one_row_per_crossing_with_timing_support(self):
        trial = linear_step_trial()
        with tempfile.TemporaryDirectory() as directory:
            csv_path = Path(directory) / "capture.csv"
            output_path = Path(directory) / "metrics.csv"
            with csv_path.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(("time_s", "thrust_n"))
                writer.writerows((sample.time_s, sample.thrust_n) for sample in trial.samples)
            completed = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(SCRIPT),
                    str(csv_path),
                    "--edge-time-s",
                    str(trial.command_edge_time_s),
                    "--command-before",
                    str(trial.command_before),
                    "--command-after",
                    str(trial.command_after),
                    "--f0-n",
                    str(trial.f0_n),
                    "--f1-n",
                    str(trial.f1_n),
                    "--rated-thrust-n",
                    str(trial.rated_thrust_n),
                    "--dwell-required-s",
                    str(trial.dwell_required_s),
                    "--output-format",
                    "csv",
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            with output_path.open("r", encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 8)
            progress_ten = next(
                row for row in rows if row["metric_family"] == "progress" and row["threshold_pct"] == "10"
            )
            self.assertAlmostEqual(float(progress_ten["after_command_s"]), 0.9)
            self.assertAlmostEqual(float(progress_ten["sample_support_width_s"]), 0.25)
            self.assertAlmostEqual(float(progress_ten["transition_duration_10_to_95_progress_s"]), 3.4)

    def test_json_cli_reads_batch_schema_and_preserves_source_label(self):
        trial = linear_step_trial()
        document = {
            "schema": metrics.INPUT_SCHEMA,
            "source": "synthetic analytic fixture",
            "rated_thrust_n": trial.rated_thrust_n,
            "dwell_required_s": trial.dwell_required_s,
            "trials": [
                {
                    "id": trial.trial_id,
                    "command_edge_time_s": trial.command_edge_time_s,
                    "command_before": trial.command_before,
                    "command_after": trial.command_after,
                    "f0_n": trial.f0_n,
                    "f1_n": trial.f1_n,
                    "samples": [
                        {"time_s": sample.time_s, "thrust_n": sample.thrust_n}
                        for sample in trial.samples
                    ],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "trace.json"
            output_path = Path(directory) / "metrics.json"
            input_path.write_text(json.dumps(document), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, "-B", str(SCRIPT), str(input_path), "--output", str(output_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(report["schema"], metrics.OUTPUT_SCHEMA)
        self.assertEqual(report["source"], "synthetic analytic fixture")
        self.assertEqual(report["trials"][0]["id"], trial.trial_id)
        self.assertAlmostEqual(
            report["trials"][0]["summary"]["response_latency_to_10_progress_s"], 0.9
        )


if __name__ == "__main__":
    unittest.main()
