"""Exercise the real shell runner's CI partitions with a disposable fake engine."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class Partitions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-partitions-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        (self.root / "tests").mkdir()
        self.names = [f"test_probe_{i:02}.gd" for i in range(19)]
        for name in self.names:
            (self.root / "tests" / name).touch()
        shutil.copyfile(Path(__file__).parents[1] / "test.sh", self.root / "test.sh")
        scripts = {
            "get-godot.sh": '#!/usr/bin/env bash\nprintf "%s/fake-engine.sh\\n" "$(cd "$(dirname "$0")" && pwd)"\n',
            "fake-engine.sh": '''#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    res://tests/*)
      echo "VISITED ${arg##*/}"
      [[ "${PROBE_FAIL:-}" != "${arg##*/}" ]] || exit 7
      if [[ "${PROBE_ERROR:-}" == "${arg##*/}" ]]; then echo 'ERROR: simulated engine error'; fi
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
        self.assertIn("engine error during", result.stdout)

    def test_p51_envelope_has_a_full_flight_budget(self):
        (self.root / "tests" / "test_p51_envelope.gd").touch()
        timeout = self.root / "timeout"
        timeout.write_text('''#!/usr/bin/env bash
seconds="$1"
shift
for arg in "$@"; do
  case "$arg" in res://tests/*) echo "BUDGET ${arg##*/} $seconds" ;; esac
done
"$@"
''', encoding="utf-8", newline="\n")
        timeout.chmod(0o755)
        result = self.run_partition(0, 1, PATH=str(self.root) + os.pathsep + os.environ["PATH"])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("BUDGET test_p51_envelope.gd 180", result.stdout)
        self.assertIn("BUDGET test_probe_00.gd 60", result.stdout)

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
