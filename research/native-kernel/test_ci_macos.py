#!/usr/bin/env python3
"""Portable checks for Mac CI orchestration; they do not run Godot or a compiler."""
import importlib.util
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ci = load("test_ci_macos_driver", "ci_macos.py")


class MacCiTest(unittest.TestCase):
    def test_current_installer_roster_drives_every_oracle(self):
        builder = load("test_ci_macos_builder", "build_macos.py")
        commands = ci.oracle_commands(builder)
        self.assertEqual({row[0] for row in commands}, set(builder.verification_roster()))
        self.assertEqual(len(commands), 18)  # 17 positive gates and the mutation control.
        by_key = {key: (script, options) for key, script, options in commands}
        self.assertEqual(by_key["base_oracle"], ("oracle.gd", ["--states", "12000", "--variant-states", "1500"]))
        self.assertEqual(by_key["negative_control"][0], "stage_oracle.gd")
        self.assertIn("--mutant", by_key["negative_control"][1])
        self.assertNotIn("helicopter", by_key)
        self.assertNotIn("helicopter_stage", by_key)

    def test_incomplete_or_inconsistent_roster_fails_closed(self):
        scripts = {"stage": "stage.gd", "helicopter": "heli.gd", "helicopter_stage": "heli_stage.gd"}
        args = {key: "--states 1000" for key in scripts}
        builder = SimpleNamespace(nk=SimpleNamespace(ORACLE_SCRIPTS=scripts, ORACLE_ARGUMENTS=args),
                                  verification_roster=lambda: {"base_oracle": "x", "stage": "y"})
        self.assertEqual(len(ci.oracle_commands(builder)), 2)
        builder.verification_roster = lambda: {"base_oracle": "x"}
        with self.assertRaises(ValueError):
            ci.oracle_commands(builder)
        builder.verification_roster = lambda: {"base_oracle": "x", "stage": "y"}
        del args["stage"]
        with self.assertRaises(ValueError):
            ci.oracle_commands(builder)

    def test_guard_marker_needs_complete_unambiguous_control_count(self):
        self.assertEqual(ci.guard_check_count("MACOS_DOMAIN_GUARD verdict=pass checks=72\n"), 72)
        self.assertEqual(ci.guard_check_count("MACOS_DOMAIN_GUARD verdict=pass checks=80\n"), 80)
        for log in ("", "MACOS_DOMAIN_GUARD verdict=pass checks=71\n",
                    "MACOS_DOMAIN_GUARD verdict=fail checks=72\n",
                    "MACOS_DOMAIN_GUARD verdict=pass checks=72\nMACOS_DOMAIN_GUARD verdict=pass checks=72\n"):
            with self.subTest(log=log), self.assertRaises(ValueError):
                ci.guard_check_count(log)

    def test_failed_subprocess_is_not_silently_retried_or_accepted(self):
        failed = subprocess.CompletedProcess(["example"], 7)
        with mock.patch.object(ci.subprocess, "run", return_value=failed) as invoke, \
                mock.patch.object(Path, "open", mock.mock_open()), \
                mock.patch.object(Path, "read_text", return_value="retained diagnostic\n"):
            with self.assertRaises(subprocess.CalledProcessError):
                ci.run(["example"], "gate", Path("logs"), {})
        self.assertEqual(invoke.call_count, 1)


if __name__ == "__main__":
    unittest.main()
