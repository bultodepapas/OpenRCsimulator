"""Lease calculation and its source-bound assumptions, with no worker launch."""
import ast
import copy
import math
from pathlib import Path
import unittest

from tools.godtest import admission, catalog
from tools.testqueue import presets


ROOT = Path(__file__).resolve().parents[2]


def function(path, name):
    module = ast.parse((ROOT / path).read_text(encoding="utf-8"))
    return next(node for node in ast.walk(module)
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name)


def calls(node, name):
    return [item for item in ast.walk(node) if isinstance(item, ast.Call)
            and (isinstance(item.func, ast.Name) and item.func.id == name
                 or isinstance(item.func, ast.Attribute) and item.func.attr == name)]


def keyword_literal(call, key):
    return next(ast.literal_eval(item.value) for item in call.keywords if item.arg == key)


def keyword_default(node, name):
    return ast.literal_eval(node.args.kw_defaults[[arg.arg for arg in node.args.kwonlyargs].index(name)])


class AdmissionBudgetTests(unittest.TestCase):
    def test_nine_case_tour_includes_every_repeat_and_overhead(self):
        cases = catalog.performance_tour() * 3
        self.assertEqual(len(cases), 9)
        self.assertEqual(admission.execution_budget(cases), 14924)
        self.assertGreater(admission.execution_budget(cases), sum(case["timeout_s"] for case in cases))
        self.assertEqual(admission.execution_budget(cases[:3]), 5630)

    def test_fractional_timeouts_round_up_and_short_launch_retry_is_counted(self):
        case = catalog.scenario("smoke", {"timeout_s": 123.25, "phase_timeout_s": 100})
        expected = (admission.ADAPTER_HISTORY_ALLOWANCE_S + admission.ADAPTER_IMPORT_ALLOWANCE_S
                    + 123.25 * 2 + admission.CASE_DEADLINE_GRACE_S + admission.CASE_LAUNCH_POLL_ALLOWANCE_S
                    + admission.CASE_IDENTITY_ALLOWANCE_S + admission.CASE_SHUTDOWN_ALLOWANCE_S
                    + admission.CASE_MONITOR_ALLOWANCE_S + admission.CASE_FILES_AND_REDUCTION_ALLOWANCE_S)
        self.assertEqual(admission.execution_budget([case]), math.ceil(expected))

    def test_queue_limit_boundary_rejects_without_truncating(self):
        # Every case remains a fully valid manifest, and the sum hits the
        # authority's limit exactly; increasing one timeout crosses it.
        cases = [catalog.scenario("smoke", {"timeout_s": timeout})
                 for timeout in (3474, 3474, 3474, 3475, 3475)]
        self.assertEqual(admission.execution_budget(cases), admission.QUEUE_EXECUTION_LIMIT_S)
        presets.validate("godtest", {"argv": ["performance-tour"], "timeout": admission.QUEUE_EXECUTION_LIMIT_S})
        with self.assertRaises(ValueError):
            presets.validate("godtest", {"argv": ["performance-tour"], "timeout": admission.QUEUE_EXECUTION_LIMIT_S + 1})
        # Even the smallest representable increase must not disappear when
        # floating-point additions round the total back to 21600.
        cases[-1]["timeout_s"] = math.nextafter(cases[-1]["timeout_s"], math.inf)
        with self.assertRaisesRegex(ValueError, "exceeds the queue limit.*5 expanded cases"):
            admission.execution_budget(cases)
        self.assertEqual(len(cases), 5)

    def test_invalid_or_empty_cases_are_rejected(self):
        case = catalog.scenario("smoke")
        invalid = [None, [], {}, [None], [{}]]
        for timeout in (True, -1, 0, float("nan"), float("inf"), 3601, 10**1000, "900"):
            modified = copy.deepcopy(case)
            modified["timeout_s"] = timeout
            invalid.append([modified])
        modified = copy.deepcopy(case)
        modified["aircraft"] = "unreviewed"
        invalid.append([modified])
        for cases in invalid:
            with self.subTest(cases=str(cases)[:80]), self.assertRaises(ValueError):
                admission.execution_budget(cases)

    def test_adapter_and_import_allowances_cover_current_explicit_timeouts(self):
        history = function("tools/testqueue/adapter.py", "prepare_history")
        history_timeouts = [keyword_literal(call, "timeout") for call in calls(history, "run")]
        self.assertEqual(history_timeouts[:2], [300, 60])
        self.assertGreaterEqual(admission.ADAPTER_HISTORY_ALLOWANCE_S, sum(history_timeouts[:2]))
        adapter = function("tools/testqueue/adapter.py", "main")
        imported = calls(adapter, "run_checked")[0]
        self.assertEqual(keyword_literal(imported, "timeout"), 600)
        stop = function("tools/godot/run_checked.py", "stop_process")
        self.assertEqual(keyword_literal(calls(stop, "run")[0], "timeout"), 10)
        self.assertEqual(keyword_literal(calls(stop, "wait")[0], "timeout"), 10)
        checked = function("tools/godot/run_checked.py", "run_checked")
        join_timeouts = [keyword_literal(call, "timeout") for call in calls(checked, "join")]
        self.assertEqual(join_timeouts, [2, 2])
        self.assertGreaterEqual(admission.ADAPTER_IMPORT_ALLOWANCE_S, 600 + 10 + 10 + max(join_timeouts))

    def test_case_allowances_cover_current_identity_launch_and_cleanup_timeouts(self):
        identity = function("tools/godtest/runner.py", "source_identity")
        git = next(node for node in ast.walk(identity) if isinstance(node, ast.FunctionDef) and node.name == "git")
        self.assertEqual(keyword_literal(calls(git, "check_output")[0], "timeout"), 30)
        self.assertEqual(len(calls(identity, "git")), 3)
        runner = function("tools/godtest/runner.py", "run")
        self.assertEqual(len(calls(runner, "source_identity")), 2)
        self.assertGreaterEqual(admission.CASE_IDENTITY_ALLOWANCE_S, 2 * 3 * 30)
        launcher_min = [call for call in calls(runner, "min")
                        if len(call.args) == 2 and isinstance(call.args[0], ast.Constant)
                        and call.args[0].value == 180]
        self.assertEqual(len(launcher_min), 1)
        self.assertEqual(admission.CASE_LAUNCH_RETRY_MAX_S, launcher_min[0].args[0].value)
        deadline = next(node.value for node in ast.walk(runner) if isinstance(node, ast.Assign)
                        and any(isinstance(target, ast.Name) and target.id == "deadline" for target in node.targets))
        self.assertEqual(deadline.right.value, admission.CASE_DEADLINE_GRACE_S)
        local_launch = function("tools/debug/debugctl.py", "_launch_local")
        self.assertTrue(any(len(call.args) == 1 and isinstance(call.args[0], ast.Constant)
                            and call.args[0].value == 2 for call in calls(local_launch, "range")))
        self.assertEqual(len([call for call in calls(runner, "_call")
                              if call.args and isinstance(call.args[0], ast.Attribute)
                              and call.args[0].attr == "stop"]), 2)
        stop = function("tools/debug/debugctl.py", "stop")
        self.assertEqual(keyword_literal(calls(stop, "result_of")[0], "timeout"), 5.0)
        stop_deadline = next(node.value for node in ast.walk(stop) if isinstance(node, ast.Assign)
                             and any(isinstance(target, ast.Name) and target.id == "deadline" for target in node.targets))
        self.assertEqual(stop_deadline.right.value, 60.0)
        sleeps = [ast.literal_eval(call.args[0]) for call in calls(stop, "sleep")]
        self.assertEqual(sleeps, [0.2, 0.5])
        self.assertGreaterEqual(admission.CASE_SHUTDOWN_ALLOWANCE_S, 2 * (5 + 60 + 0.2) + 0.5)
        gpu = function("tools/godtest/hardware.py", "stop")
        monitor = function("tools/godtest/frame_monitor.py", "stop")
        self.assertEqual(keyword_default(gpu, "join_timeout"), 3.0)
        self.assertEqual(keyword_default(monitor, "join_timeout"), 15.0)
        joins = [call for call in calls(runner, "join") if isinstance(call.func.value, ast.Attribute)
                 and call.func.value.attr == "thread"]
        self.assertEqual([ast.literal_eval(call.args[0]) for call in joins], [3.0])
        self.assertGreaterEqual(admission.CASE_MONITOR_ALLOWANCE_S, 3 + 15 + 3)


if __name__ == "__main__":
    unittest.main()
