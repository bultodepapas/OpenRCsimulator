#!/usr/bin/env python3
"""Failure-oriented regressions for the NK-3 development wrapper; no native build required."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import devtools as dev
import test_verification as verification


def oracle_evidence(kind, seed=20261027):
    # A sparse checkout may not contain app/; the verification policy does not consume these fixture hashes.
    with patch.object(verification.builder, "sha256_file", return_value="f" * 64):
        result = verification.evidence(kind)
    result["seed"] = seed
    return result


class DevelopmentToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def database(self, mode="ubsan"):
        flags = [*dev.FP_FLAGS, "-std=c++17", "-fexceptions", "-fno-omit-frame-pointer"]
        flags += dev.sanitizer_flags(mode)
        for header in ("godot_cpp/core/defs.hpp", "godot_cpp/classes/ref_counted.hpp"):
            path = self.work / "include" / header
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        flags += [f"-I{self.work / 'include'}", f"-I{dev.HERE / 'src'}"]
        return [{"directory": str(self.work), "file": str(source),
                 "command": "g++ " + " ".join(flags) + " -c " + str(source)}
                for source in (dev.HERE / "src").glob("*.cpp")]

    def validate(self, rows, mode="ubsan"):
        path = self.work / "compile_commands.json"
        path.write_text(json.dumps(rows))
        return dev.validate_compdb(path, mode)

    def test_db_requires_actual_native_translation_units(self):
        self.assertTrue(self.validate(self.database()))
        with self.assertRaisesRegex(ValueError, "misses"):
            self.validate([])
        with self.assertRaisesRegex(ValueError, "misses"):
            self.validate([{ "file": "unrelated.cpp", "directory": str(self.work), "command": "g++"}])

    def test_db_rejects_lost_instrumentation_or_fp_policy(self):
        for flag in [*dev.FP_FLAGS, *dev.sanitizer_flags("ubsan"), "-std=c++17", "-fno-omit-frame-pointer"]:
            with self.subTest(flag=flag):
                rows = self.database()
                rows[0]["command"] = rows[0]["command"].replace(flag, "")
                with self.assertRaisesRegex(ValueError, "required flags"):
                    self.validate(rows)

    def test_profile_database_does_not_require_sanitizers(self):
        self.assertTrue(self.validate(self.database("profile"), "profile"))

    def test_database_needs_generated_headers_and_strict_flags(self):
        rows = self.database()
        (self.work / "include/godot_cpp/classes/ref_counted.hpp").unlink()
        with self.assertRaisesRegex(ValueError, "cannot resolve"):
            self.validate(rows)
        rows = self.database()
        rows[0]["command"] += " -ffast-math"
        with self.assertRaisesRegex(ValueError, "unsafe floating-point"):
            self.validate(rows)

    def test_database_rejects_effective_flag_overrides(self):
        for flag in ("-fno-sanitize=undefined", "-fno-sanitize=all", "-fsanitize-recover=undefined",
                     "-fno-exceptions", "-fomit-frame-pointer", "-std=c++20", "-ffp-contract=on",
                     "-fassociative-math"):
            with self.subTest(flag=flag):
                rows = self.database()
                rows[0]["command"] += " " + flag
                with self.assertRaises(ValueError):
                    self.validate(rows)
        rows = self.database()
        rows[0]["command"] += " -fno-exceptions -fexceptions"
        self.assertTrue(self.validate(rows))

    def test_profile_database_rejects_sanitizer_instrumentation(self):
        rows = self.database("profile")
        rows[0]["command"] += " -fsanitize=address"
        with self.assertRaisesRegex(ValueError, "profile compilation"):
            self.validate(rows, "profile")

    def test_sanitizer_stderr_does_not_look_like_godot_errors(self):
        for diagnostic in ["==123==ERROR: AddressSanitizer: heap-buffer-overflow",
                           "test.cpp:9:8: runtime error: signed integer overflow",
                           "SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior"]:
            path = self.work / "engine.log"
            path.write_text(diagnostic)
            self.assertEqual(dev.sanitizer_lines(path), [diagnostic])
        path.write_text("Godot Engine\nNK3_ORACLE verdict=pass\n")
        self.assertEqual(dev.sanitizer_lines(path), [])

    def test_recovering_sanitizer_error_overrides_zero_exit(self):
        report = dev.checked(["python3", "-c", "print('x.cpp:2: runtime error: bad operation')"],
                             self.work, "recovering", 10)
        self.assertEqual(report["process_exit"], 0)
        self.assertFalse(report["ok"])
        self.assertTrue(report["sanitizer_diagnostics"])
        saved = json.loads(Path(report["diagnostic_report"]).read_text())
        self.assertFalse(saved["ok"])

    def test_literal_only_oracle_cannot_pass(self):
        oracle = {"verdict": "pass", "failures": [], "format": "openrc-nk3-stage-oracle v1",
                  "components": {"literals": {"count": 30, "identical": 30}},
                  "total": {"compared": 30, "identical": 30, "mismatched": 0}, "coverage": {}}
        checked = {"ok": True, "complete": True, "reason": "passed", "process_exit": 0,
                   "counts": {"error": 0}}
        self.assertTrue(dev.coverage_error(oracle, checked, "stage_oracle.gd", 12000))

    def test_private_userdata_environment(self):
        values = dev.private_environment(self.work)
        self.assertIn(f"XDG_DATA_HOME={self.work / 'xdg-data'}", values)

    def test_private_environment_removes_inherited_loader_overrides(self):
        inherited = {**os.environ, "LD_PRELOAD": "/nonexistent/nk3.so",
                     "LD_LIBRARY_PATH": "/nonexistent/nk3", "LD_AUDIT": "/nonexistent/audit.so"}
        command = [*dev.private_environment(self.work), *dev.sanitizer_environment("ubsan"),
                   sys.executable, "-c", "import json,os; print(json.dumps(dict(os.environ)))"]
        result = subprocess.run(command, env=inherited, check=True, capture_output=True, text=True)
        actual = json.loads(result.stdout)
        for name in ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT"):
            self.assertNotIn(name, actual)
        for kind in ("DATA", "CONFIG", "CACHE"):
            self.assertEqual(actual[f"XDG_{kind}_HOME"], str(self.work / ("xdg-" + kind.lower())))

    def test_positive_control_requires_the_marker_and_control_origin(self):
        report = {"complete": True, "process_exit": 1, "reason": "process_exit"}
        source, library = self.work / "positive-control.cpp", self.work / "positive-control.so"
        marker = "NK3_CONTROL_BEGIN ubsan\n"
        intended = f"{source}:7: runtime error: signed integer overflow\n"
        self.assertTrue(dev.control_detected(report, marker + intended, "ubsan", "signed integer overflow", source, library))
        for log in (intended, marker + "other.cpp:7: runtime error: signed integer overflow\n",
                    intended + marker, marker + f"{source}: other failure\n"):
            with self.subTest(log=log):
                self.assertFalse(dev.control_detected(report, log, "ubsan", "signed integer overflow", source, library))
        for altered in ({**report, "complete": False}, {**report, "process_exit": 0}, {**report, "reason": "timeout"}):
            self.assertFalse(dev.control_detected(altered, marker + intended, "ubsan", "signed integer overflow", source, library))
        asan = "NK3_CONTROL_BEGIN asan\n" + f"{library}: heap-buffer-overflow\n"
        self.assertTrue(dev.control_detected(report, asan, "asan", "heap-buffer-overflow", source, library))
        self.assertFalse(dev.control_detected(report, asan.replace(library.name, "unrelated.so"),
                                              "asan", "heap-buffer-overflow", source, library))

    def test_private_app_paths_reject_overlap_and_symlink_aliases(self):
        app = self.work / "app"
        app.mkdir()
        (app / "project.godot").write_text("config_version=5\n")
        alias = self.work / "alias"
        alias.symlink_to(app, target_is_directory=True)
        dev.validate_paths(app, self.work / "output")
        for source, output in ((app, app), (app, app / "output"), (app, self.work),
                               (alias, app / "output"), (app, alias / "output")):
            with self.subTest(source=source, output=output), self.assertRaisesRegex(ValueError, "must not overlap"):
                dev.validate_paths(source, output)
        with self.assertRaisesRegex(ValueError, "project.godot"):
            dev.validate_paths(self.work / "missing", self.work / "output")

    def test_snapshot_rejects_directory_symlink_cycles_before_copying(self):
        app, out = self.work / "app", self.work / "output"
        (app / "assets").mkdir(parents=True)
        out.mkdir()
        (app / "project.godot").write_text("config_version=5\n")
        (app / "assets/loop").symlink_to(app, target_is_directory=True)
        with patch.object(dev.shutil, "copytree") as copy, \
             patch.object(dev.shutil, "disk_usage", return_value=SimpleNamespace(free=5 * 1024**3)):
            with self.assertRaisesRegex(ValueError, "symlink"):
                dev.snapshot(app, out, self.work / "godot")
            copy.assert_not_called()

    def test_snapshot_keeps_nested_native_sources_and_hashes_the_copy(self):
        app, out = self.work / "app", self.work / "output"
        out.mkdir()
        for name, contents in (("project.godot", "config_version=5\n"),
                               ("sim/native/weather_adapter.gd", "# native weather source\n"),
                               ("sim/native/nested/helper.gd", "# nested source\n"),
                               ("native/kernel/libopenrc_native_kernel.so", "installed binary"),
                               ("captures/frame.png", "old capture"),
                               (".godot/extension_list.cfg", "installed extension"),
                               (".godot/imported/resource", "cached import")):
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        with patch.object(dev.shutil, "disk_usage", return_value=SimpleNamespace(free=5 * 1024**3)):
            before = dev.app_hashes(app)
            copied = dev.snapshot(app, out, self.work / "godot")
        self.assertEqual(before, dev.app_hashes(copied))
        self.assertIn("sim/native/weather_adapter.gd", before)
        self.assertIn("sim/native/nested/helper.gd", before)
        self.assertFalse((copied / "native").exists())
        self.assertFalse((copied / "captures").exists())
        self.assertFalse((copied / ".godot/extension_list.cfg").exists())
        self.assertTrue((copied / ".godot/imported/resource").is_file())
        (copied / "sim/native/weather_adapter.gd").write_text("# changed during check\n")
        self.assertNotEqual(before, dev.app_hashes(copied))

    def test_nested_native_directory_symlink_is_rejected(self):
        app, out = self.work / "app", self.work / "output"
        (app / "sim").mkdir(parents=True)
        out.mkdir()
        (app / "project.godot").write_text("config_version=5\n")
        (app / "sim/native").symlink_to(app, target_is_directory=True)
        with patch.object(dev.shutil, "copytree") as copy:
            with self.assertRaisesRegex(ValueError, "symlink"):
                dev.snapshot(app, out, self.work / "godot")
            copy.assert_not_called()
        with self.assertRaisesRegex(ValueError, "symlink"):
            dev.app_hashes(app)
        # The installed root is excluded, so even an alias there is never followed.
        (app / "sim/native").unlink()
        (app / "sim/native").mkdir()
        (app / "sim/native/helper.gd").write_text("# retained source\n")
        (app / "native").symlink_to(app, target_is_directory=True)
        with patch.object(dev.shutil, "disk_usage", return_value=SimpleNamespace(free=5 * 1024**3)):
            copied = dev.snapshot(app, out, self.work / "godot")
        self.assertTrue((copied / "sim/native/helper.gd").is_file())
        self.assertFalse((copied / "native").exists())
        self.assertEqual(dev.app_hashes(app), dev.app_hashes(copied))

    def test_json_object_reader_rejects_nonobjects_and_bad_json(self):
        path = self.work / "input.json"
        path.write_text('{"ok": true}')
        self.assertEqual(dev.read_object(path), {"ok": True})
        for text in ("[]", "null", '"text"', "42", "{"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                path.write_text(text)
                dev.read_object(path)

    def test_source_identity_changes_when_a_verifier_helper_changes(self):
        root = self.work / "repo"
        kernel = root / "research/native-kernel"
        for name in ("research/native-kernel/src/sample.cpp", "research/native-kernel/toolchain-lock.json",
                     "research/native-kernel/devtools.py", "research/native-kernel/build.py",
                     "research/native-slipstream/build.py", "tools/godot/run_checked.py"):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original")
        with patch.object(dev, "ROOT", root), patch.object(dev, "HERE", kernel):
            baseline = dev.source_hashes()
            for name in ("research/native-kernel/build.py", "tools/godot/run_checked.py"):
                with self.subTest(name=name):
                    path = root / name
                    path.write_text("changed")
                    self.assertNotEqual(dev.source_hashes(), baseline)
                    path.write_text("original")

    def test_coverage_checks_requested_counts_and_seed(self):
        stage, trajectory = oracle_evidence("stage_oracle"), oracle_evidence("trajectory")
        report = stage["checked_run"]
        self.assertEqual(dev.coverage_error(stage, report, "stage_oracle.gd", 12000, 960, stage["seed"]), "")
        self.assertEqual(dev.coverage_error(trajectory, report, "trajectory.gd", 12000, 960, trajectory["seed"]), "")
        self.assertIn("stage coverage", dev.coverage_error(stage, report, "stage_oracle.gd", 10000, 960, stage["seed"]))
        self.assertIn("trajectory length", dev.coverage_error(trajectory, report, "trajectory.gd", 12000, 14400, trajectory["seed"]))
        for script, oracle in (("stage_oracle.gd", stage), ("trajectory.gd", trajectory)):
            self.assertIn("seed", dev.coverage_error(oracle, report, script, 12000, 960, oracle["seed"] + 1))

    def test_missing_marker_is_not_a_pass(self):
        report = dev.checked(["python3", "-c", "pass"], self.work, "empty", 10, ["NK3_ORACLE verdict=pass"])
        self.assertFalse(report["ok"])

    def test_outputs_cannot_overwrite_or_escape_tmp(self):
        with patch.object(dev, "ROOT", self.work):
            made = dev.fresh(self.work / "tmp/new")
            self.assertTrue(made.is_dir())
            with self.assertRaises(FileExistsError):
                dev.fresh(made)
            for path in [self.work / "app", self.work / "tmp", self.work / "tmp/../app"]:
                with self.assertRaisesRegex(ValueError, "new directory"):
                    dev.fresh(path)


class DevelopmentCheckWorkflowTests(unittest.TestCase):
    """Exercise orchestration with a small real snapshot and verifier, replacing only external work."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="nk3-development-check-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.kernel = self.root / "research/native-kernel"
        (self.kernel / "src").mkdir(parents=True)
        for origin, target in ((dev.HERE / "build.py", self.kernel / "build.py"),
                               (dev.ROOT / "research/native-slipstream/build.py",
                                self.root / "research/native-slipstream/build.py")):
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, target)
        for name, contents in (("devtools.py", "fixture driver"), ("toolchain-lock.json", "{}"),
                               ("src/nk_kernel.cpp", "fixture translation unit"), ("src/nk_math.hpp", "// math"),
                               ("stage_oracle.gd", "# stage harness"), ("trajectory.gd", "# trajectory harness")):
            (self.kernel / name).write_text(contents)
        runner = self.root / "tools/godot/run_checked.py"
        runner.parent.mkdir(parents=True)
        runner.write_text("# fixture runner")
        include = self.root / "include"
        for name in ("godot_cpp/core/defs.hpp", "godot_cpp/classes/ref_counted.hpp"):
            path = include / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture header")
        self.app = self.root / "app"
        self.app.mkdir()
        (self.app / "project.godot").write_text("config_version=5\n")
        (self.app / "model.gd").write_text("# fixture application")
        (self.app / "sim/native").mkdir(parents=True)
        (self.app / "sim/native/helper.gd").write_text("# fixture native helper")
        self.engine = self.root / "godot"
        self.engine.write_bytes(b"fixture engine")
        self.build = self.root / "tmp/build"
        (self.build / "lib").mkdir(parents=True)
        library = self.build / "lib/libopenrc_native_kernel.so"
        library.write_bytes(b"fixture binary")
        descriptor = self.build / "openrc_native_kernel.gdextension"
        descriptor.write_text("fixture descriptor")
        database = self.build / "compile_commands.json"
        flags = [*dev.FP_FLAGS, "-std=c++17", "-fexceptions", "-fno-omit-frame-pointer",
                 *dev.sanitizer_flags("ubsan"), f"-I{self.kernel / 'src'}", f"-I{include}"]
        database.write_text(json.dumps([{"directory": str(self.root), "file": str(self.kernel / "src/nk_kernel.cpp"),
                                         "arguments": ["g++", "-c", *flags]}]))
        for name, value in (("ROOT", self.root), ("HERE", self.kernel)):
            patched = patch.object(dev, name, value)
            patched.start()
            self.addCleanup(patched.stop)
        receipt = {"format": dev.FORMAT, "installable": False, "mode": "ubsan",
                   "source_hashes": dev.source_hashes(), "binary_sha256": dev.digest(library),
                   "descriptor_sha256": dev.digest(descriptor), "compile_database_sha256": dev.digest(database)}
        (self.build / "development-build.json").write_text(json.dumps(receipt))
        self.args = SimpleNamespace(build=self.build, out=self.root / "tmp/check", app=self.app, godot=self.engine,
                                    script="all", states=12000, ticks=960, seed=20261027, timeout=10)

    def run_check(self, behavior=None):
        behavior = behavior or {}
        commands = []

        def fake_checked(command, _out, label, _timeout, _required=None):
            commands.append((label, command))
            output = Path(next(arg.partition("=")[2] for arg in command if arg.startswith("--output=")))
            result = behavior.get(label, "pass")
            if result == "invalid":
                output.write_text("[]")
            elif result == "malformed":
                output.write_text("{")
            elif result != "missing":
                output.write_text(json.dumps(oracle_evidence("stage_oracle" if label == "stage_oracle" else "trajectory")))
            if result == "change_snapshot":
                (self.args.out / "app/model.gd").write_text("# changed during oracle")
            elif result == "change_native_source":
                (self.args.out / "app/sim/native/helper.gd").write_text("# changed during oracle")
            return {"ok": result != "failure", "complete": True,
                    "reason": "process_exit" if result == "failure" else "passed",
                    "process_exit": 1 if result == "failure" else 0, "counts": {"error": 0},
                    "missing_required_text": []}

        with patch.object(dev, "controls", return_value={"ubsan": {"detected": True}}) as controls, \
             patch.object(dev, "snapshot", wraps=dev.snapshot) as snapshot, \
             patch.object(dev, "import_snapshot") as imported, \
             patch.object(dev, "checked", side_effect=fake_checked), \
             patch.object(dev.shutil, "disk_usage", return_value=SimpleNamespace(free=5 * 1024**3)), \
             contextlib.redirect_stdout(io.StringIO()):
            result = dev.check(self.args)
        summary = json.loads((self.args.out / "summary.json").read_text())
        return result, summary, commands, controls, snapshot, imported

    def test_all_checks_both_oracles_from_one_snapshot(self):
        result, summary, commands, controls, snapshot, imported = self.run_check()
        self.assertEqual(result, 0)
        self.assertTrue(summary["ok"])
        self.assertEqual(summary["requested_scripts"], ["stage_oracle.gd", "trajectory.gd"])
        self.assertEqual(set(summary["runs"]), set(summary["requested_scripts"]))
        self.assertEqual([label for label, _ in commands], ["stage_oracle", "trajectory"])
        controls.assert_called_once()
        snapshot.assert_called_once()
        imported.assert_called_once()
        for _, command in commands:
            self.assertIn(str(self.args.out / "app"), command)
            self.assertIn(f"--states={self.args.states}", command)
            self.assertIn(f"--seed={self.args.seed}", command)
        self.assertIn(f"--ticks={self.args.ticks}", commands[1][1])

    def test_all_cannot_pass_when_the_second_oracle_fails(self):
        result, summary, commands, _, snapshot, imported = self.run_check({"trajectory": "failure"})
        self.assertEqual(result, 1)
        self.assertFalse(summary["ok"])
        self.assertTrue(summary["runs"]["stage_oracle.gd"]["ok"])
        self.assertFalse(summary["runs"]["trajectory.gd"]["ok"])
        self.assertEqual(len(commands), 2)
        snapshot.assert_called_once()
        imported.assert_called_once()

        self.args.out = self.root / "tmp/longer-request"
        self.args.ticks = 14400
        result, summary, commands, _, _, _ = self.run_check()
        self.assertEqual(result, 1)
        self.assertFalse(summary["ok"])
        self.assertTrue(summary["runs"]["stage_oracle.gd"]["ok"])
        self.assertIn("trajectory length", summary["runs"]["trajectory.gd"]["coverage_error"])
        self.assertEqual(len(commands), 2)

        self.args.out = self.root / "tmp/changed-snapshot"
        self.args.ticks = 960
        result, summary, commands, _, _, _ = self.run_check({"trajectory": "change_snapshot"})
        self.assertEqual(result, 1)
        self.assertFalse(summary["runs"]["trajectory.gd"]["unchanged"])
        self.assertFalse(summary["ok"])
        self.assertEqual(len(commands), 2)

    def test_changed_native_helper_during_oracle_invalidates_the_snapshot(self):
        result, summary, commands, _, _, _ = self.run_check({"trajectory": "change_native_source"})
        self.assertEqual(result, 1)
        self.assertIn("sim/native/helper.gd", summary["source_snapshot"])
        self.assertFalse(summary["runs"]["trajectory.gd"]["unchanged"])
        self.assertFalse(summary["ok"])
        self.assertEqual(len(commands), 2)

    def test_all_stops_after_the_first_failure(self):
        result, summary, commands, _, _, _ = self.run_check({"stage_oracle": "failure"})
        self.assertEqual(result, 1)
        self.assertFalse(summary["ok"])
        self.assertEqual([label for label, _ in commands], ["stage_oracle"])
        self.assertEqual(list(summary["runs"]), ["stage_oracle.gd"])
        self.assertEqual(summary["requested_scripts"], ["stage_oracle.gd", "trajectory.gd"])

        self.args.out = self.root / "tmp/different-seed"
        self.args.seed += 1
        result, summary, commands, _, _, _ = self.run_check()
        self.assertEqual(result, 1)
        self.assertIn("seed", summary["runs"]["stage_oracle.gd"]["coverage_error"])
        self.assertEqual([label for label, _ in commands], ["stage_oracle"])

    def test_invalid_or_missing_oracle_json_retains_a_failed_summary(self):
        for label, failure in (("stage_oracle", "invalid"), ("trajectory", "malformed"), ("stage_oracle", "missing")):
            with self.subTest(label=label, failure=failure):
                self.args.out = self.root / "tmp" / f"{label}-{failure}"
                result, summary, commands, _, _, _ = self.run_check({label: failure})
                self.assertEqual(result, 1)
                self.assertFalse(summary["ok"])
                self.assertIn("oracle output unavailable or invalid", summary["runs"][label + ".gd"]["coverage_error"])
                self.assertEqual(commands[-1][0], label)


if __name__ == "__main__":
    unittest.main()
