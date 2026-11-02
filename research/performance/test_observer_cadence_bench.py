"""Offline scheduling and append-output contracts for the cadence benchmark."""
from collections import Counter
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import observer_cadence_bench as bench


class CadenceBenchmarkTests(unittest.TestCase):
    def run_fixture(self, directory, pairs, cadences, extra=()):
        destination = Path(directory) / "runs.jsonl"
        previous = {"existing": "keep"}
        destination.write_text(json.dumps(previous) + "\n", encoding="utf-8")
        captured = io.StringIO()

        def fake_run(app, cadence, label, scenario, warm, sample, fps, scale):
            return {"label": label, "app_dir": app, "cadence": cadence, "scenario": scenario,
                    "settings": [warm, sample, fps, scale]}

        with mock.patch.object(bench, "run", side_effect=fake_run), \
                mock.patch.object(bench.time, "sleep") as sleep, redirect_stdout(captured):
            bench.main(["base-app", "candidate-app", str(destination), "airborne", str(pairs), cadences, *extra])
        rows = [json.loads(line) for line in destination.read_text(encoding="utf-8").splitlines()]
        stdout_rows = [json.loads(line) for line in captured.getvalue().splitlines()]
        self.assertEqual(rows[0], previous)
        self.assertEqual(rows[1:], stdout_rows)
        return rows[1:], sleep

    def test_two_roles_alternate_every_pair_and_append_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, sleep = self.run_fixture(directory, 6, "1", ("3", "8", "30", "0.5", "0"))
        self.assertEqual(len(rows), 12)
        for pair in range(6):
            group = rows[2 * pair:2 * pair + 2]
            expected = ["base", "cadence1"] if pair % 2 == 0 else ["cadence1", "base"]
            self.assertEqual([row["label"] for row in group], expected)
            self.assertTrue(all(row["pair"] == pair + 1 for row in group))
            self.assertTrue(all(row["settings"] == ["3", "8", "30", "0.5"] for row in group))
        self.assertEqual([row["cadence"] for row in rows[:2]], [None, 1])
        self.assertEqual([row["app_dir"] for row in rows[:2]], ["base-app", "candidate-app"])
        self.assertEqual(sleep.call_count, 12)
        sleep.assert_called_with(0.0)

    def test_three_to_five_roles_balance_positions_and_pairwise_precedence(self):
        for count in (3, 4, 5):
            cadences = ",".join(str(value) for value in range(1, count))
            with self.subTest(roles=count), tempfile.TemporaryDirectory() as directory:
                rows, sleep = self.run_fixture(directory, 2 * count, cadences)
                labels = ["base"] + [f"cadence{value}" for value in range(1, count)]
                positions = {label: Counter() for label in labels}
                precedence = Counter()
                for pair in range(2 * count):
                    group = rows[count * pair:count * (pair + 1)]
                    order = [row["label"] for row in group]
                    self.assertCountEqual(order, labels)
                    self.assertTrue(all(row["pair"] == pair + 1 for row in group))
                    for position, label in enumerate(order):
                        positions[label][position] += 1
                        for later in order[position + 1:]:
                            precedence[label, later] += 1
                for label in labels:
                    self.assertEqual(positions[label], Counter({position: 2 for position in range(count)}))
                    for other in labels:
                        if label != other:
                            self.assertEqual(precedence[label, other], count)
                self.assertEqual(sleep.call_count, count * count * 2)
                sleep.assert_called_with(20.0)
                self.assertTrue(all(row["settings"] == ["10", "40", "60", "0.5"] for row in rows))

    def test_baseline_clears_cadence_and_candidate_uses_requested_cadence(self):
        output = SimpleNamespace(returncode=0, stdout='noise\n{"cpu_ms_per_sim_s": 42}\n', stderr="")
        with mock.patch.dict(os.environ, {"OPENRC_PRESENTATION_CADENCE": "4",
                                         "OPENRC_DETACH_PRESENTATION": "1"}, clear=True), \
                mock.patch.object(bench.subprocess, "run", return_value=output) as subprocess_run:
            self.assertEqual(bench.run("base", None, "base", "airborne", "10", "40", "60", "0.5"),
                             {"cpu_ms_per_sim_s": 42})
            base_env = subprocess_run.call_args.kwargs["env"]
            self.assertNotIn("OPENRC_PRESENTATION_CADENCE", base_env)
            self.assertNotIn("OPENRC_DETACH_PRESENTATION", base_env)
            self.assertEqual(base_env["OPENRC_APP_DIR"], "base")

            bench.run("candidate", 1, "cadence1", "airborne", "10", "40", "60", "0.5")
            candidate_env = subprocess_run.call_args.kwargs["env"]
            self.assertEqual(candidate_env["OPENRC_PRESENTATION_CADENCE"], "1")
            self.assertNotIn("OPENRC_DETACH_PRESENTATION", candidate_env)
            self.assertEqual(candidate_env["OPENRC_APP_DIR"], "candidate")

    def test_failed_child_is_preserved_as_an_error_result(self):
        output = SimpleNamespace(returncode=1, stdout="", stderr="counter unavailable")
        with mock.patch.object(bench.subprocess, "run", return_value=output):
            result = bench.run("candidate", 1, "cadence1", "runway", "10", "40", "60", "0.5")
        self.assertEqual(result["label"], "cadence1")
        self.assertEqual(result["scenario"], "runway")
        self.assertIn("counter unavailable", result["error"])


if __name__ == "__main__":
    unittest.main()
