"""The command must preflight and budget the whole plan before submission."""
from __future__ import annotations

from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import json
import unittest
from unittest import mock

import godtest
from tools.godtest.admission import execution_budget
from tools.testqueue import common, integration


class ManagedAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.object(common, "enabled", return_value=True))
        self.stack.enter_context(mock.patch.object(common, "inherited", return_value=False))
        self.submit = self.stack.enter_context(mock.patch.object(integration, "run", return_value=0))
        self.engine = self.stack.enter_context(mock.patch.object(godtest, "run"))
        self.stderr = io.StringIO()
        self.stdout = io.StringIO()
        self.stack.enter_context(redirect_stderr(self.stderr))
        self.stack.enter_context(redirect_stdout(self.stdout))

    def test_three_repeat_roster_gets_full_execution_budget(self):
        argv = ["performance-tour", "--repeats", "3"]
        cases = godtest.plan(godtest.parser().parse_args(argv))
        self.assertEqual(len(cases), 9)
        self.assertEqual(godtest.main(argv), 0)
        expected = execution_budget(cases)
        self.assertGreater(expected, 3600)
        self.assertLessEqual(expected, 21600)
        self.submit.assert_called_once_with("godtest", argv, godtest.ROOT, timeout=expected)
        self.engine.assert_not_called()

    def test_oversized_roster_is_rejected_before_submission_or_launch(self):
        self.assertEqual(godtest.main(["performance-tour", "--repeats", "20"]), 2)
        self.assertIn("exceeds the queue limit", self.stderr.getvalue())
        self.submit.assert_not_called()
        self.engine.assert_not_called()

    def test_worker_owned_flags_are_rejected_before_reading_any_plan(self):
        for option in ("--godot", "--out", "--snapshot", "--manifest"):
            with self.subTest(option=option), mock.patch.object(godtest, "plan") as plan:
                self.assertEqual(godtest.main(["performance-tour", option, "missing-path"]), 2)
                plan.assert_not_called()
        self.submit.assert_not_called()
        self.engine.assert_not_called()

    def test_abbreviated_worker_inputs_cannot_bypass_direct_managed_submission(self):
        from tools.testqueue.presets import validate
        for option in ("--go", "--ou", "--snap", "--man"):
            with self.subTest(option=option), mock.patch.object(godtest, "plan") as plan:
                argv = ["run", "smoke", option + "=/tmp/worker-external-input"]
                # A queue request may reach the adapter with unknown raw argv;
                # the worker command must reject it before planning or IO.
                validate("godtest", {"argv": argv})
                with self.assertRaises(SystemExit) as error:
                    godtest.main(argv)
                self.assertEqual(error.exception.code, 2)
                plan.assert_not_called()
        self.submit.assert_not_called()
        self.engine.assert_not_called()

    def test_dry_run_shows_budget_without_submitting_or_claiming_a_wall_bound(self):
        self.assertEqual(godtest.main(["performance-tour", "--repeats", "3", "--dry-run"]), 0)
        result = json.loads(self.stdout.getvalue())
        self.assertEqual(result["case_count"], 9)
        self.assertEqual(result["managed_admission"]["status"], "fits_queue_limit")
        self.assertGreater(result["managed_admission"]["execution_budget_seconds"], 3600)
        self.assertNotIn("max_wall_seconds", result)
        self.assertIn("not measured duration or a completion guarantee", result["note"])
        self.submit.assert_not_called()
        self.engine.assert_not_called()

    def test_oversized_dry_run_keeps_every_case_and_reports_rejection(self):
        self.assertEqual(godtest.main(["performance-tour", "--repeats", "20", "--dry-run"]), 0)
        result = json.loads(self.stdout.getvalue())
        self.assertEqual((result["case_count"], len(result["cases"])), (60, 60))
        self.assertEqual(result["managed_admission"]["status"], "rejected")
        self.assertIsNone(result["managed_admission"]["execution_budget_seconds"])
        self.submit.assert_not_called()


if __name__ == "__main__":
    unittest.main()
