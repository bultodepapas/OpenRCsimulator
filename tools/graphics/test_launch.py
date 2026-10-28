"""Portable, GPU-free tests for the experimental graphics launcher."""

from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
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
        self.research = self.root / "snapshot" / "app"
        (self.research / "render").mkdir(parents=True)
        (self.research.parent / "assets").mkdir()
        (self.research / "render" / "high_graphics_profile.gd").write_bytes(
            (launch.APP_DIR / "render" / "high_graphics_profile.gd").read_bytes()
        )
        self.project_file = self.research / "project.godot"
        self.project_name = "OpenRC-Research-" + uuid.uuid4().hex
        self.project_file.write_text(
            f'config_version=5\n[application]\nconfig/name="{self.project_name}"\n'
            '[rendering]\nlights_and_shadows/multi_bounce_occlusion/enabled=false\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def research_args(self, method: str = "forward_plus", driver: str = "metal") -> list[str]:
        return ["--godot", str(self.engine), "--research-project", str(self.research),
                "--research-method", method, "--research-driver", driver]

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

    def test_linux_prefers_pinned_linux_binary_to_path(self) -> None:
        local_engine = self.root / ".tools" / launch.PINNED_LINUX_GODOT
        local_engine.parent.mkdir()
        local_engine.write_text("Linux executable", encoding="utf-8")
        local_engine.chmod(0o755)
        with mock.patch.object(launch.sys, "platform", "linux"), mock.patch.object(
            launch.shutil, "which", return_value=str(self.engine)
        ) as which:
            found = launch._discover_godot(
                None, environ={}, repo_root=self.root, cwd=self.root, require_exists=True
            )
        self.assertEqual(found, str(local_engine.resolve()))
        which.assert_not_called()

    def test_resolution_validation_and_duplicate_profile_rejection(self) -> None:
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(["--godot", str(self.engine), "--resolution", "0x1080"])
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(["--godot", str(self.engine), "--profile", "high", "--profile", "standard"])
        run.assert_not_called()

    def test_research_matrix_uses_isolated_project_and_explicit_common_profile(self) -> None:
        original = self.project_file.read_bytes()
        for method, driver in sorted(launch._RESEARCH_PAIRS):
            with self.subTest(method=method, driver=driver), mock.patch.dict(os.environ, {
                    launch.PROFILE_ENV: "high", launch.RECONSTRUCTION_ENV: "fsr2_quality",
                    launch.METALFX_TRIAL_ENV: "1", "OPENRC_LAKE_REFLECTIONS": "planar"}), \
                    mock.patch.object(launch.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
                status = launch.main(self.research_args(method, driver) + [
                    "--resolution", "1920x1080", "--verbose", "--", "--quick-flight"])
                self.assertEqual(status, 0)
                command = run.call_args.args[0]
                self.assertEqual(command[1:7], ["--path", str(self.research.resolve()),
                                               "--rendering-method", method, "--rendering-driver", driver])
                self.assertLess(command.index("--rendering-driver"), command.index("--"))
                self.assertEqual(command[-2:], ["--", "--quick-flight"])
                env = run.call_args.kwargs["env"]
                self.assertEqual(env[launch.PROFILE_ENV], "standard")
                self.assertEqual(env[launch.RECONSTRUCTION_ENV], "native")
                self.assertNotIn(launch.METALFX_TRIAL_ENV, env)
                self.assertEqual(env["OPENRC_CONTACT_SHADOWS"], "off")
                self.assertEqual(env["OPENRC_LAKE_REFLECTIONS"], "off")
                identity = json.loads(env[launch.RESEARCH_ENV])
                self.assertEqual((identity["requested_method"], identity["requested_driver"],
                                  identity["requested_effects"], identity["requested_reconstruction"]),
                                 (method, driver, "common", "native"))
                self.assertEqual(identity["project_name"], self.project_name)
                self.assertEqual(len(identity["project_sha256"]), 64)
                self.assertEqual(len(identity["profile_sha256"]), 64)
        self.assertEqual(self.project_file.read_bytes(), original)
        self.assertFalse((self.research / "override.cfg").exists())

    def test_metalfx_is_an_explicit_metal_only_direct_flight_trial(self) -> None:
        cases = (("mobile", "metalfx_spatial_85"), ("forward_plus", "metalfx_spatial_quality"),
                 ("forward_plus", "metalfx_temporal_native"), ("forward_plus", "metalfx_temporal_85"),
                 ("forward_plus", "metalfx_temporal_quality"))
        for method, mode in cases:
            with self.subTest(method=method, mode=mode), mock.patch.object(
                    launch.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
                status = launch.main(self.research_args(method, "metal") + [
                    "--research-reconstruction", mode, "--", "--quick-flight"])
                self.assertEqual(status, 0)
                env = run.call_args.kwargs["env"]
                self.assertEqual(env[launch.RECONSTRUCTION_ENV], mode)
                self.assertEqual(env[launch.METALFX_TRIAL_ENV], "1")
                self.assertEqual(json.loads(env[launch.RESEARCH_ENV])["requested_reconstruction"], mode)

        rejected = (
            ("mobile", "metal", "metalfx_temporal_85", ["--", "--quick-flight"]),
            ("forward_plus", "vulkan", "metalfx_spatial_85", ["--", "--quick-flight"]),
            ("gl_compatibility", "opengl3", "metalfx_temporal_native", ["--", "--quick-flight"]),
            ("forward_plus", "metal", "metalfx_spatial_85", []),
            ("forward_plus", "metal", "metalfx_spatial_85", ["--", "--input-report"]),
            ("forward_plus", "metal", "metalfx_spatial_85", ["--", "--vehicle=mt8-bisonte"]),
        )
        for method, driver, mode, suffix in rejected:
            with self.subTest(method=method, driver=driver, mode=mode, suffix=suffix), \
                    mock.patch.object(launch.subprocess, "run") as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    launch.main(self.research_args(method, driver) + ["--research-reconstruction", mode] + suffix)
                run.assert_not_called()

    def test_research_refuses_ambiguous_or_contradictory_options(self) -> None:
        invalid = (
            ["--research-project", str(self.research)],
            self.research_args("mobile", "opengl3"),
            self.research_args("gl_compatibility", "metal"),
            self.research_args() + ["--profile", "standard"],
            self.research_args() + ["--prof", "standard"],
            self.research_args() + ["--research-method", "mobile"],
            self.research_args() + ["--research-meth", "mobile"],
            self.research_args() + ["--research-unknown", "value"],
            self.research_args() + ["--godot", str(self.engine)],
            self.research_args() + ["--main-pack", "other.pck"],
            self.research_args() + ["--display-driver", "headless"],
            self.research_args() + ["--headless"],
            self.research_args() + ["--editor"],
            self.research_args() + ["--", "--research-driver=metal"],
            self.research_args() + ["--resolution", "1920x1080", "--resolution", "1280x720"],
            ["--executable", str(self.engine), "--research-project", str(self.research),
             "--research-method", "mobile", "--research-driver", "metal"],
        )
        for args in invalid:
            with self.subTest(args=args), mock.patch.object(launch.subprocess, "run") as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    launch.main(args)
                run.assert_not_called()

    def test_research_requires_isolated_settings_and_no_overrides(self) -> None:
        original = self.project_file.read_text(encoding="utf-8")
        variants = (
            original.replace(self.project_name, "OpenRC Simulator"),
            original.replace("enabled=false", "enabled=true"),
            original.replace("[rendering]", 'config/use_custom_user_dir=true\n[rendering]'),
            original.replace("[rendering]", 'config/name.macos="OpenRC Simulator"\n[rendering]'),
            original.replace("[rendering]", 'config/project_settings_override="user://override.cfg"\n[rendering]'),
            original.replace("[rendering]", 'config/use_hidden_project_data_directory=false\n[rendering]'),
            original.replace("[rendering]", f'config/name="{self.project_name}"\n[rendering]'),
        )
        for value in variants:
            self.project_file.write_text(value, encoding="utf-8")
            with self.subTest(project=value), mock.patch.object(launch.subprocess, "run") as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    launch.main(self.research_args())
                run.assert_not_called()
        self.project_file.write_text(original, encoding="utf-8")
        (self.research / "override.cfg").write_text("[application]\nconfig/name=\"OpenRC Simulator\"\n")
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(self.research_args())
            run.assert_not_called()

    def test_research_rejects_live_project_and_stale_profile(self) -> None:
        with mock.patch.object(launch.subprocess, "run") as run:
            args = self.research_args()
            args[args.index("--research-project") + 1] = str(launch.APP_DIR)
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(args)
            (self.research / "render" / "high_graphics_profile.gd").write_text("# stale\n")
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(self.research_args())
            run.assert_not_called()

    def test_research_refuses_settings_changed_during_validation(self) -> None:
        real_reader = launch._research_project_settings

        def changed_after_read(project: Path):
            checked = real_reader(project)
            self.project_file.write_text(self.project_file.read_text(encoding="utf-8").replace(
                self.project_name, "OpenRC Simulator"), encoding="utf-8")
            return checked

        with mock.patch.object(launch, "_research_project_settings", side_effect=changed_after_read), \
                mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(self.research_args())
            run.assert_not_called()

    def test_research_rejects_cache_link_outside_snapshot(self) -> None:
        cache = self.research / ".godot"
        try:
            cache.symlink_to(self.root, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"directory symlinks unavailable: {error}")
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(self.research_args())
            run.assert_not_called()

    def test_research_rejects_nested_cache_link(self) -> None:
        cache = self.research / ".godot"
        cache.mkdir()
        try:
            (cache / "imported").symlink_to(self.root, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"directory symlinks unavailable: {error}")
        with mock.patch.object(launch.subprocess, "run") as run:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                launch.main(self.research_args())
            run.assert_not_called()

    def test_research_dry_run_reports_requested_identity_without_launch(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output), mock.patch.object(launch.subprocess, "run") as run:
            self.assertEqual(launch.main(self.research_args("mobile", "metal") + ["--dry-run"]), 0)
        run.assert_not_called()
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["research_project"]["path"], str(self.research.resolve()))
        self.assertEqual(plan["research_project"]["project_name"], self.project_name)
        self.assertEqual(json.loads(plan["env_override"][launch.RESEARCH_ENV])["requested_method"], "mobile")
        self.assertIsNone(plan["env_override"][launch.METALFX_TRIAL_ENV])

    def test_normal_launcher_does_not_inherit_research_identity(self) -> None:
        with mock.patch.dict(os.environ, {launch.RESEARCH_ENV: '{"fake":true}'}), mock.patch.object(
                launch.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
            self.assertEqual(launch.main(["--godot", str(self.engine)]), 0)
        self.assertNotIn(launch.RESEARCH_ENV, run.call_args.kwargs["env"])

    @unittest.skipUnless(os.environ.get("OPENRC_RESEARCH_TEST_GODOT"), "set OPENRC_RESEARCH_TEST_GODOT for the real-engine check")
    def test_research_identity_in_real_headless_engine(self) -> None:
        project = launch._research_project(str(self.research), cwd=self.root)
        override = launch._research_environment("forward_plus", "metal", "native", project)
        env = launch._child_environment(os.environ, override)
        # Isolate the test process's ordinary application-data root as well as its project name.
        if sys.platform == "win32":
            env["APPDATA"] = str(self.root / "appdata")
        elif sys.platform != "darwin":
            env["XDG_DATA_HOME"] = str(self.root / "data")
        command = [sys.executable, str(launch.REPO_ROOT / "tools/godot/run_checked.py"),
                   "--out-dir", str(self.root / "checks"), "--timeout", "90", "--",
                   os.environ["OPENRC_RESEARCH_TEST_GODOT"], "--headless", "--path", str(self.research),
                   "--audio-driver", "Dummy", "--script",
                   str(launch.REPO_ROOT / "tools/graphics/test_research_identity.gd")]
        result = subprocess.run(command, env=env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + "\n" + result.stderr)
        self.assertIn("Research identity verified in headless project", result.stdout)


if __name__ == "__main__":
    unittest.main()
