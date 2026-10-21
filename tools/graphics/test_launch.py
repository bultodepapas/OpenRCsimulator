"""Portable, GPU-free tests for the experimental graphics launcher."""

from __future__ import annotations

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

try:
    from . import launch
except ImportError:  # Also support `python tools/graphics/test_launch.py`.
    import launch  # type: ignore[no-redef]


class GraphicsLauncherTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.engine = self.root / "godot stub"
        self.engine.write_text("stub", encoding="utf-8")
        self.engine.chmod(0o755)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_high_engine_launch_passes_renderer_resolution_and_user_args(self) -> None:
        completed = SimpleNamespace(returncode=23)
        with mock.patch.object(launch.subprocess, "run", return_value=completed) as run:
            status = launch.main(
                [
                    "--godot",
                    str(self.engine),
                    "--profile",
                    "high",
                    "--resolution",
                    "1920x1080",
                    "--verbose",
                    "--",
                    "--landscape=green_paradise",
                ]
            )

        self.assertEqual(status, 23)
        command = run.call_args.args[0]
        self.assertEqual(command[0], str(self.engine.resolve()))
        self.assertEqual(command[1:5], ["--path", str(launch.APP_DIR.resolve()), "--rendering-method", "forward_plus"])
        self.assertIn(["--resolution", "1920x1080"], [command[i : i + 2] for i in range(len(command) - 1)])
        self.assertLess(command.index("--verbose"), command.index("--"))
        self.assertEqual(command[-2:], ["--", "--landscape=green_paradise"])
        self.assertEqual(run.call_args.kwargs["env"][launch.PROFILE_ENV], "high")
        self.assertNotIn("--rendering-driver", command)

    def test_standard_removes_inherited_high_profile_and_passes_exit_code(self) -> None:
        with mock.patch.dict(os.environ, {launch.PROFILE_ENV: "high"}), mock.patch.object(
            launch.subprocess, "run", return_value=SimpleNamespace(returncode=5)
        ) as run:
            status = launch.main(["--godot", str(self.engine), "--profile", "standard"])

        self.assertEqual(status, 5)
        self.assertNotIn(launch.PROFILE_ENV, run.call_args.kwargs["env"])
        self.assertEqual(
            run.call_args.args[0][1:5],
            ["--path", str(launch.APP_DIR.resolve()), "--rendering-method", "gl_compatibility"],
        )

    def test_packaged_executable_omits_project_path(self) -> None:
        with mock.patch.object(launch.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
            status = launch.main(["--executable", str(self.engine), "--profile", "high"])

        self.assertEqual(status, 0)
        command = run.call_args.args[0]
        self.assertEqual(command, [str(self.engine.resolve()), "--rendering-method", "forward_plus"])
        self.assertNotIn("--path", command)

    def test_mutually_exclusive_targets_fail_before_launch(self) -> None:
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                launch.main(["--godot", str(self.engine), "--executable", str(self.engine)])
        self.assertEqual(error.exception.code, 2)
        run.assert_not_called()

    def test_conflicting_renderer_driver_path_and_profile_args_are_rejected(self) -> None:
        conflicting = (
            ["--rendering-method=forward_plus"],
            ["--rendering-driver", "vulkan"],
            ["--path=other"],
            ["--", "--profile=standard"],
        )
        for forwarded in conflicting:
            with self.subTest(forwarded=forwarded), mock.patch.object(launch.subprocess, "run") as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    launch.main(["--godot", str(self.engine), *forwarded])
                self.assertEqual(error.exception.code, 2)
                run.assert_not_called()

    def test_dry_run_is_json_and_reports_environment_removal(self) -> None:
        with mock.patch.dict(os.environ, {launch.PROFILE_ENV: "high"}):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = launch.main(
                    ["--godot", str(self.engine), "--dry-run", "--profile", "standard", "--", "--seed=7"]
                )

        self.assertEqual(status, 0)
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["env_override"], {launch.PROFILE_ENV: None})
        self.assertEqual(plan["argv"][-2:], ["--", "--seed=7"])
        self.assertIn("--rendering-method", plan["argv"])

    def test_godot_discovery_prefers_explicit_path_then_env_then_pinned_path(self) -> None:
        local_engine = self.root / ".tools" / launch.PINNED_WINDOWS_GODOT
        local_engine.parent.mkdir()
        local_engine.write_text("pinned", encoding="utf-8")
        local_engine.chmod(0o755)
        cwd = self.root / "cwd"
        cwd.mkdir()

        explicit = launch._discover_godot(
            str(self.engine),
            environ={"GODOT": str(local_engine)},
            repo_root=self.root,
            cwd=cwd,
            require_exists=True,
        )
        from_env = launch._discover_godot(
            None,
            environ={"GODOT": str(self.engine)},
            repo_root=self.root,
            cwd=cwd,
            require_exists=True,
        )
        with mock.patch.object(launch.sys, "platform", "win32"):
            pinned = launch._discover_godot(
                None,
                environ={},
                repo_root=self.root,
                cwd=cwd,
                require_exists=True,
            )
        self.assertEqual(explicit, str(self.engine.resolve()))
        self.assertEqual(from_env, str(self.engine.resolve()))
        self.assertEqual(pinned, str(local_engine.resolve()))

    def test_non_windows_ignores_pinned_windows_binary(self) -> None:
        local_engine = self.root / ".tools" / launch.PINNED_WINDOWS_GODOT
        local_engine.parent.mkdir()
        local_engine.write_text("Windows executable", encoding="utf-8")
        with mock.patch.object(launch.sys, "platform", "linux"), mock.patch.object(
            launch.shutil, "which", return_value=str(self.engine)
        ):
            found = launch._discover_godot(
                None, environ={}, repo_root=self.root, cwd=self.root, require_exists=True
            )
        self.assertEqual(found, str(self.engine.resolve()))

    def test_resolution_validation_and_duplicate_profile_rejection(self) -> None:
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(["--godot", str(self.engine), "--resolution", "0x1080"])
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(["--godot", str(self.engine), "--profile", "high", "--profile", "standard"])
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
