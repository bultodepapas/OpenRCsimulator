"""Exercise phase routing and the shared generator contract in disposable trees."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("partition_fixtures", ROOT / "app/tests/test_ci_partitions.py")
partition_fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(partition_fixtures)
ROSTER_SPEC = importlib.util.spec_from_file_location("phase_roster", ROOT / "tools/ci/phase_roster.py")
phase_roster = importlib.util.module_from_spec(ROSTER_SPEC)
ROSTER_SPEC.loader.exec_module(phase_roster)

GENERATORS = [
    "assets/aircraft/ugly-stik-60/compile_geometry.py",
    "assets/aircraft/extra-300s-60/compile_geometry.py",
    "assets/aircraft/extra-300s-60/compile_appearance.py",
    "assets/aircraft/avanti-s-a200/compile_geometry.py",
    "assets/aircraft/p51d-mustang-120/build_geometry.py",
    "assets/aircraft/p51d-mustang-120/compile_geometry.py",
    "research/extra-300/ex14/ground_effect_vlm.py",
    "research/extra-300/ex05/derive_physics.py",
    "research/p51/p51-05/derive_physics.py",
    "research/timber/tt01/manifest.py",
    "assets/aircraft/turbo-lumber-evolution/build_geometry.py",
    "assets/aircraft/turbo-lumber-evolution/compile_geometry.py",
    "research/timber/tt07/derive_physics.py",
    "research/skywalker-x8/X8-00/manifest.py",
    "research/skywalker-x8/X8-02/install_assets.py",
    "research/skywalker-x8/X8-02/compile_model.py",
    "research/skywalker-x8/X8-06/derive_physics.py",
]


class PhaseRouting(unittest.TestCase):
    def setUp(self):
        self.fixture = partition_fixtures.Partitions("runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.app = self.fixture.root
        script = (self.app / "test.sh").read_text(encoding="utf-8")
        # Keep the real selection, parse, unit, import, receipt and pipe logic;
        # replace only the expensive integration blocks in this disposable copy.
        start = script.index('echo "== CI and local generated source checks"')
        end = script.index("fi # offline generators and references", start)
        script = script[:start] + 'echo SOURCE_PHASE\n[[ "${FAIL_SOURCE:-}" != 1 ]]\n' + script[end:]
        start = script.index('echo "== H7:')
        script = script[:start] + 'echo RUNTIME_PHASE\n[[ "${FAIL_RUNTIME:-}" != 1 ]]\n'
        (self.app / "test.sh").write_text(script, encoding="utf-8", newline="\n")
        (self.app / "simulation").mkdir()
        (self.app / "simulation/non_unit.gd").write_text("# parse me\n", encoding="utf-8")
        (self.app / "simulation/non unit á.gd").write_text("# parse me too\n", encoding="utf-8")

    def run_part(self, part, **extra):
        output = self.app.parent / "outputs" / part
        return self.fixture.run_partition(0, 1, OPENRC_TEST_PART=part,
                                          OPENRC_CHECK_OUT=str(output), **extra)

    def test_selectors_and_backwards_compatible_unions(self):
        expected = {
            "integration-source": (True, False, False, False),
            "integration-parse": (False, True, False, False),
            "integration-runtime": (False, False, False, True),
            "integration": (True, True, False, True),
            "units": (False, False, True, False),
            "all": (True, True, True, True),
        }
        for part, wanted in expected.items():
            with self.subTest(part=part):
                result = self.run_part(part)
                self.assertEqual(result.returncode, 0, result.stdout)
                path = self.app.parent / "outputs" / part
                parse_receipts = list(path.glob("roster-parse-*.json"))
                unit_receipts = list(path.glob("roster-units-0-of-1-*.json"))
                actual = ("SOURCE_PHASE" in result.stdout, bool(parse_receipts),
                          bool(unit_receipts), "RUNTIME_PHASE" in result.stdout)
                self.assertEqual(actual, wanted, result.stdout)
                if actual[1]:
                    receipt = json.loads(parse_receipts[0].read_text())
                    self.assertIn("simulation/non_unit.gd", receipt["completed"])
                    self.assertIn("simulation/non unit á.gd", receipt["completed"])
                    self.assertEqual(receipt["expected"], receipt["completed"])

    def test_phase_failures_and_no_false_success_receipts(self):
        for part, failure in (("integration-source", {"FAIL_SOURCE": "1"}),
                              ("integration-runtime", {"FAIL_RUNTIME": "1"}),
                              ("integration-parse", {"PROBE_FAIL": self.fixture.names[0]}),
                              ("units", {"PROBE_FAIL": self.fixture.names[0]})):
            with self.subTest(part=part):
                result = self.run_part(part, **failure)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(list((self.app.parent / "outputs" / part).glob("roster-*.json")))

    def test_roster_change_during_execution_cannot_create_receipt(self):
        result = self.run_part("units", PROBE_ADD=str(self.app / "tests/test_added.gd"))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("roster, completed scripts, commit or source bytes changed", result.stdout)
        self.assertFalse(list((self.app.parent / "outputs/units").glob("roster-*.json")))

    def test_unset_selector_remains_the_complete_local_default(self):
        env = os.environ.copy()
        for name in ("OPENRC_TEST_PART", "OPENRC_UNIT_SHARDS", "OPENRC_UNIT_SHARD"):
            env.pop(name, None)
        output = self.app.parent / "outputs/default"
        env["OPENRC_CHECK_OUT"] = str(output)
        result = subprocess.run([os.environ.get("OPENRC_TEST_BASH", "bash"), "test.sh"], cwd=self.app,
                                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("SOURCE_PHASE", result.stdout)
        self.assertIn("RUNTIME_PHASE", result.stdout)
        self.assertEqual(len(list(output.glob("roster-parse-*.json"))), 1)
        self.assertEqual(len(list(output.glob("roster-units-0-of-1-*.json"))), 1)

    def test_ci_verifier_rejects_missing_duplicate_changed_and_partial(self):
        root = self.app.parent
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        subprocess.run(["git", "-C", str(root), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "commit", "-q", "--allow-empty", "-m", "fixture"], check=True)
        reports = root / "reports"
        parse = self.fixture.run_partition(0, 1, OPENRC_TEST_PART="integration-parse",
                                           OPENRC_CHECK_OUT=str(reports / "parse"))
        self.assertEqual(parse.returncode, 0, parse.stdout)
        for shard in range(8):
            result = self.fixture.run_partition(shard, 8, OPENRC_CHECK_OUT=str(reports / str(shard)))
            self.assertEqual(result.returncode, 0, result.stdout)
        phase_roster.validate_ci(self.app, reports)
        receipt = next((reports / "0").glob("roster-units-0-of-8-*.json"))
        original = receipt.read_text()
        receipt.unlink()
        with self.assertRaises(ValueError): phase_roster.validate_ci(self.app, reports)
        receipt.write_text(original)
        duplicate = reports / "duplicate"
        duplicate.mkdir()
        shutil.copyfile(receipt, duplicate / receipt.name)
        with self.assertRaises(ValueError): phase_roster.validate_ci(self.app, reports)
        (duplicate / receipt.name).unlink()
        data = json.loads(original)
        data["completed"].pop()
        receipt.write_text(json.dumps(data))
        with self.assertRaises(ValueError): phase_roster.validate_ci(self.app, reports)
        receipt.write_text(original)
        (self.app / "tests" / self.fixture.names[0]).write_text("# changed\n")
        with self.assertRaises(ValueError): phase_roster.validate_ci(self.app, reports)
        (self.app / "tests" / self.fixture.names[0]).write_text("")
        (self.app / "tests/test_new.gd").touch()
        with self.assertRaises(ValueError): phase_roster.validate_ci(self.app, reports)


class GeneratorContract(unittest.TestCase):
    def test_shared_roster_replaces_only_the_duplicate_app_calls(self):
        app = (ROOT / "app/test.sh").read_text(encoding="utf-8")
        shared = (ROOT / "tools/ci/check-sources.sh").read_text(encoding="utf-8")
        self.assertEqual(app.count('bash "$HERE/../tools/ci/check-sources.sh"'), 1)
        for generator in GENERATORS:
            with self.subTest(generator=generator):
                self.assertEqual(shared.count("python3 " + generator + " --check"), 1)
                self.assertNotIn(generator, app)

    def test_every_original_ci_generator_runs_once_and_failure_stops(self):
        with tempfile.TemporaryDirectory(prefix="openrc-generators-") as temporary:
            root = Path(temporary)
            (root / "tools/ci").mkdir(parents=True)
            shutil.copyfile(ROOT / "tools/ci/check-sources.sh", root / "tools/ci/check-sources.sh")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "python3"
            fake.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$GEN_LOG"\n'
                            '[[ "$1" != "${GEN_FAIL:-}" ]]\n', encoding="utf-8")
            fake.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(fake_bin) + os.pathsep + env["PATH"], GEN_LOG=str(root / "calls"))
            bash = os.environ.get("OPENRC_TEST_BASH", "bash")
            for index in range(-1, len(GENERATORS)):
                (root / "calls").unlink(missing_ok=True)
                env["GEN_FAIL"] = GENERATORS[index] if index >= 0 else ""
                result = subprocess.run([bash, str(root / "tools/ci/check-sources.sh")], env=env,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode == 0, index == -1, result.stdout + result.stderr)
                calls = (root / "calls").read_text().splitlines()
                stop = len(GENERATORS) if index == -1 else index + 1
                self.assertEqual(calls, [name + " --check" for name in GENERATORS[:stop]])


if __name__ == "__main__":
    unittest.main()
