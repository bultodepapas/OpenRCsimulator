"""Exercise the real shell runner's CI partitions with a disposable fake engine."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


class Partitions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-partitions-")
        self.root = Path(self.temp.name) / "app"
        self.root.mkdir()
        self.addCleanup(self.temp.cleanup)
        (self.root / "tests").mkdir()
        self.names = [f"test_probe_{i:02}.gd" for i in range(19)]
        for name in self.names:
            (self.root / "tests" / name).touch()
        (self.root / "test.sh").write_text((Path(__file__).parents[1] / "test.sh").read_text(),
                                           encoding="utf-8", newline="\n")
        runner = self.root.parent / "tools" / "godot"
        runner.mkdir(parents=True)
        shutil.copyfile(Path(__file__).parents[2] / "tools/godot/run_checked.py", runner / "run_checked.py")
        scripts = {
            "get-godot.sh": '#!/usr/bin/env bash\nprintf "%s/fake-engine.sh\\n" "$(cd "$(dirname "$0")" && pwd)"\n',
            "fake-engine.sh": '''#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --import)
      if [[ "${PROBE_IMPORT_ERROR:-}" == "1" ]]; then echo 'SCRIPT ERROR: import failed'; fi
      ;;
    res://tests/*)
      echo "VISITED ${arg##*/}"
      [[ "${PROBE_FAIL:-}" != "${arg##*/}" ]] || exit 7
      if [[ "${PROBE_ERROR:-}" == "${arg##*/}" ]]; then printf '\\033[31m  %s: simulated engine error\\033[0m\\n' "${PROBE_KIND:-ERROR}"; fi
      ;;
  esac
done
exit 0
''',
        }
        for name, content in scripts.items():
            p = self.root / name
            p.write_text(content, encoding="utf-8", newline="\n")
            p.chmod(0o755)

    def run_partition(self, shard=0, count=8, **overrides):
        env = os.environ.copy()
        env.update(OPENRC_TEST_PART="units", OPENRC_UNIT_SHARD=str(shard), OPENRC_UNIT_SHARDS=str(count))
        env["OPENRC_CHECK_OUT"] = str(self.root.parent / "tmp/godot-checks")
        env.update(overrides)
        bash = os.environ.get("OPENRC_TEST_BASH", "bash")
        return subprocess.run([bash, "test.sh"], cwd=self.root, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)

    def test_every_script_runs_exactly_once_across_all_partitions(self):
        visited = []
        for shard in range(8):
            result = self.run_partition(shard)
            self.assertEqual(result.returncode, 0, result.stdout)
            visited.extend(line.removeprefix("VISITED ") for line in result.stdout.splitlines()
                           if line.startswith("VISITED "))
        self.assertCountEqual(visited, self.names)

    def test_test_failure_is_fatal(self):
        result = self.run_partition(0, 1, PROBE_FAIL=self.names[0])
        self.assertEqual(result.returncode, 7, result.stdout)

    def test_engine_error_is_fatal_even_with_zero_exit(self):
        result = self.run_partition(0, 1, PROBE_ERROR=self.names[0])
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("engine_error", result.stdout)

    def test_shader_error_is_fatal_even_with_zero_exit(self):
        result = self.run_partition(0, 1, PROBE_ERROR=self.names[0], PROBE_KIND="SHADER ERROR")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("engine_error", result.stdout)

    def test_import_error_prevents_any_tests_from_running(self):
        result = self.run_partition(0, 1, PROBE_IMPORT_ERROR="1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("import failed", result.stdout)
        self.assertNotIn("VISITED", result.stdout)
        reports = list((self.root.parent / "tmp/godot-checks").glob("*/report.json"))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        self.assertEqual(report["timeout_seconds"], 600)
        self.assertEqual(report["reason"], "engine_error")

    def test_ci_import_precedes_schema_and_publishes_failures(self):
        repository = Path(__file__).resolve().parents[2]
        workflow = (repository / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        start = workflow.index("      - name: Import resources before schema probes\n")
        end = workflow.index("      - name: Aircraft v2 contract and explicit v1 loader compatibility", start)
        step = workflow[start:end]
        self.assertIn("        id: resource_import\n", step)
        self.assertIn("        if: matrix.part == 'integration'\n", step)
        script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        env = os.environ.copy()
        env["PROBE_IMPORT_ERROR"] = "1"
        bash = os.environ.get("OPENRC_TEST_BASH", "bash")
        result = subprocess.run([bash, "-c", script], cwd=self.root.parent, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        self.assertEqual(result.returncode, 1, result.stdout)
        reports = list((self.root.parent / "tmp/godot-checks").glob("*/report.json"))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        self.assertEqual(report["timeout_seconds"], 600)
        self.assertEqual(report["reason"], "engine_error")
        self.assertIn("import failed", (reports[0].parent / "engine.log").read_text())
        condition = "if: always() && (steps.resource_import.outcome != 'skipped' || steps.app_check.outcome != 'skipped')"
        self.assertEqual(workflow.count(condition), 2)

    def test_measured_slow_gates_have_bounded_ci_budgets(self):
        slow_gates = {
            "test_workshop_starts.gd",
            "test_p51_ground.gd",
            "test_prop_strike.gd",
            "test_p51_handling.gd",
            "test_rcv_handling.gd",
        }
        for name in slow_gates | {"test_p51_envelope.gd", "test_trim_throttle.gd", "test_half_power_start.gd", "test_ui_home_layout.gd", "test_ui_modal_responsive.gd"}:
            (self.root / "tests" / name).touch()
        result = self.run_partition(0, 1)
        self.assertEqual(result.returncode, 0, result.stdout)
        budgets = {}
        for path in (self.root.parent / "tmp/godot-checks").glob("*/report.json"):
            report = json.loads(path.read_text())
            for arg in report["command"]:
                if arg.startswith("res://tests/"):
                    budgets[arg.rsplit("/", 1)[-1]] = report["timeout_seconds"]
        for name in slow_gates:
            with self.subTest(test=name):
                self.assertEqual(budgets[name], 120)
        self.assertEqual(budgets["test_p51_envelope.gd"], 180)
        # The merged trim regression includes both airborne holds and controlled runway takeoffs.
        self.assertEqual(budgets["test_trim_throttle.gd"], 300)
        self.assertEqual(budgets["test_half_power_start.gd"], 600)
        self.assertEqual(budgets["test_ui_home_layout.gd"], 180)
        self.assertEqual(budgets["test_ui_modal_responsive.gd"], 600)
        self.assertEqual(budgets["test_probe_00.gd"], 60)

    def test_expected_cli_failures_are_uploaded_outside_positive_summary(self):
        repository = Path(__file__).resolve().parents[2]
        script = (repository / "app" / "test.sh").read_text(encoding="utf-8")
        workflow = (repository / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertIn('EXPECTED_CHECK_OUT="${OPENRC_EXPECTED_CHECK_OUT:-$HERE/../tmp/godot-checks-expected}"', script)
        self.assertIn("summarize.py tmp/godot-checks --junit tmp/godot-checks/results.xml", workflow)
        self.assertIn("path: tmp/godot-checks/", workflow)
        self.assertIn("name: godot-expected-diagnostics-${{ matrix.part }}-${{ matrix.shard }}", workflow)
        self.assertIn("tmp/godot-checks-expected/", workflow)

    def test_invalid_and_empty_partitions_are_rejected(self):
        for shard, count in [(8, 8), (-1, 8), (0, 0), (0, "08"), (0, 129), (19, 20)]:
            with self.subTest(shard=shard, count=count):
                result = self.run_partition(shard, count)
                self.assertEqual(result.returncode, 2, result.stdout)
        for part in ["unknown", "all", "integration"]:
            result = self.run_partition(0, 8, OPENRC_TEST_PART=part)
            self.assertEqual(result.returncode, 2, result.stdout)


if __name__ == "__main__":
    unittest.main()
