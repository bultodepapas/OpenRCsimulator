"""Offline scheduling and append-output contracts for both cadence benchmarks."""
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

import observer_cadence_ab as ab
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


class CadenceWindowTests(unittest.TestCase):
    def run_fixture(self, directory, modes, rounds, extra=(), scenario="airborne", use_sys_argv=False):
        destination = Path(directory) / "window runs.jsonl"
        previous = {"existing": "keep"}
        destination.write_text(json.dumps(previous) + "\n", encoding="utf-8")
        captured = io.StringIO()
        sample = {"main_ms_per_sim_s": 42.25, "realtime": 0.5,
                  "frames_per_sim_s": 120.0, "height_m": 100.0}

        def fake_ctl(port, *args):
            return json.dumps({"port": 12345, "pid": 1234}) if args[0] == "launch" else "ok"

        args = [str(destination), scenario, ",".join(str(mode) for mode in modes), str(rounds), *extra]
        with mock.patch.object(ab, "ctl", side_effect=fake_ctl) as ctl, \
                mock.patch.object(ab, "set_mode", side_effect=lambda port, mode: [str(mode)] * 5), \
                mock.patch.object(ab, "sample", side_effect=lambda *args: dict(sample)) as take_sample, \
                mock.patch.object(ab.time, "sleep") as sleep, \
                mock.patch.dict(os.environ, {"OPENRC_APP_DIR": "frozen app"}, clear=True), \
                mock.patch.object(ab.sys, "argv", ["observer_cadence_ab.py", *args]), \
                redirect_stdout(captured):
            ab.main() if use_sys_argv else ab.main(args)
        rows = [json.loads(line) for line in destination.read_text(encoding="utf-8").splitlines()]
        stdout_rows = [json.loads(line) for line in captured.getvalue().splitlines()]
        self.assertEqual(rows[0], previous)
        self.assertEqual(rows[1:], stdout_rows)
        self.assertEqual(take_sample.call_count, rounds * len(modes))
        ctl.assert_any_call(0, "launch", "--headless", "--app", "frozen app")
        self.assertEqual(ctl.call_args, mock.call(12345, "stop"))
        return rows[1:], ctl, take_sample, sleep

    def test_two_modes_alternate_with_odd_round_count_and_preserve_window_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, ctl, take_sample, sleep = self.run_fixture(
                directory, [4, 0], 5, ("3", "1", "30", "0.25"), scenario="runway", use_sys_argv=True)
        self.assertEqual(len(rows), 10)
        for round_index in range(5):
            group = rows[2 * round_index:2 * round_index + 2]
            expected = [4, 0] if round_index % 2 == 0 else [0, 4]
            self.assertEqual([row["mode"] for row in group], expected)
            for row in group:
                self.assertEqual(row, {"main_ms_per_sim_s": 42.25, "realtime": 0.5,
                                      "frames_per_sim_s": 120.0, "height_m": 100.0,
                                      "scenario": "runway", "round": round_index + 1,
                                      "mode": row["mode"], "max_fps": 30, "time_scale": 0.25,
                                      "app_dir": "frozen app", "gates": [str(row["mode"])] * 5})
        take_sample.assert_called_with(12345, 1234, 3.0)
        ctl.assert_any_call(12345, "fly", "start=runway")
        ctl.assert_any_call(12345, "eval", "expr=Engine.set_max_fps(30)")
        ctl.assert_any_call(12345, "eval", "expr=Engine.set_time_scale(0.25)")
        self.assertEqual(sleep.call_args_list, [mock.call(10)] + [mock.call(1.0)] * 10)

    def test_one_to_four_modes_balance_positions_and_precedence_over_complete_cycle(self):
        for count in (1, 2, 3, 4):
            with self.subTest(modes=count), tempfile.TemporaryDirectory() as directory:
                rows, _, take_sample, _ = self.run_fixture(directory, list(range(count)), 2 * count)
                positions = {mode: Counter() for mode in range(count)}
                precedence = Counter()
                for round_index in range(2 * count):
                    group = rows[count * round_index:count * (round_index + 1)]
                    order = [row["mode"] for row in group]
                    self.assertCountEqual(order, range(count))
                    self.assertTrue(all(row["round"] == round_index + 1 for row in group))
                    for position, mode in enumerate(order):
                        positions[mode][position] += 1
                        for later in order[position + 1:]:
                            precedence[mode, later] += 1
                for mode in range(count):
                    self.assertEqual(positions[mode], Counter({position: 2 for position in range(count)}))
                    for other in range(count):
                        if mode != other:
                            self.assertEqual(precedence[mode, other], count)
                take_sample.assert_called_with(12345, 1234, 8.0)

    def test_partial_cycles_sample_every_mode_once_per_round(self):
        for rounds in (1, 3):
            with self.subTest(rounds=rounds), tempfile.TemporaryDirectory() as directory:
                rows, _, _, _ = self.run_fixture(directory, [3, 0, 2], rounds)
                for round_index in range(rounds):
                    self.assertCountEqual([row["mode"] for row in rows[3 * round_index:3 * round_index + 3]],
                                          [3, 0, 2])

    def test_failed_window_stops_the_owned_session(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(ab, "ctl", return_value='{"port": 12345, "pid": 1234}') as ctl, \
                mock.patch.object(ab, "set_mode", return_value=[]), \
                mock.patch.object(ab, "sample", side_effect=RuntimeError("invalid window")), \
                mock.patch.object(ab.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "invalid window"):
                ab.main([str(Path(directory) / "runs.jsonl"), "airborne", "0,1"])
        self.assertEqual(ctl.call_args, mock.call(12345, "stop"))


if __name__ == "__main__":
    unittest.main()
