"""Portable fixtures: profile isolation and requested renderer are hard gates."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

import catalog
from godtest import parser, plan
from runner import audio_output, check_frozen, rendering_options
from tools.godtest.isolation import prepare_macos_launch


class PlatformTests(unittest.TestCase):
    def test_platform_renderer_defaults_and_explicit_apis(self):
        manifest = catalog.scenario("runway-menus")
        self.assertEqual(rendering_options(manifest, "darwin"), {"rendering_method": "mobile", "rendering_driver": "metal"})
        for host in ("linux", "win32"):
            self.assertEqual(rendering_options(manifest, host), {"rendering_method": "forward_plus", "rendering_driver": "vulkan"})
        with self.assertRaisesRegex(ValueError, "Metal"):
            rendering_options(dict(manifest, rendering_driver="metal"), "linux")
        with self.assertRaisesRegex(ValueError, "Compatibility"):
            rendering_options(dict(manifest, rendering_method="gl_compatibility", rendering_driver="vulkan"), "win32")

    def test_linux_without_playback_device_uses_paced_dummy_audio(self):
        with tempfile.TemporaryDirectory() as raw:
            sound = Path(raw)
            self.assertEqual(audio_output("linux", sound / "absent")["driver"], "dummy")
            (sound / "controlC0").touch()
            (sound / "pcmC0D0c").touch()  # capture only
            self.assertEqual(audio_output("linux", sound)["driver"], "dummy")
            (sound / "pcmC0D0p").touch()
            self.assertEqual(audio_output("linux", sound)["driver"], "platform_default")
        for host in ("win32", "darwin"):
            self.assertEqual(audio_output(host, Path("/nonexistent"))["driver"], "platform_default")

    def test_graphics_profile_option_is_validated_and_kept_for_every_tour_case(self):
        cases = plan(parser().parse_args(["performance-tour", "--repeats", "1", "--graphics", "automatic", "--dry-run"]))
        self.assertEqual({case["graphics"] for case in cases}, {"automatic"})
        self.assertNotIn("graphics", catalog.scenario("runway-menus"))
        with self.assertRaisesRegex(ValueError, "graphics"):
            catalog.scenario("runway-menus", {"graphics": "minimal"})
        with self.assertRaises(SystemExit):
            parser().parse_args(["performance-tour", "--graphics", "minimal"])

    def test_three_aircraft_roster_cannot_be_reduced(self):
        cases = plan(parser().parse_args(["performance-tour", "--repeats", "2", "--dry-run"]))
        self.assertEqual([item["aircraft"] for item in cases], list(catalog.TOUR_AIRCRAFT) * 2)
        for case in cases:
            self.assertEqual(case["phases"], catalog.TOUR_PHASES)
            self.assertTrue(case["watch_frames"] and case["require_native"] and case["monitor_hardware"])
        for options in ({"monitor_hardware": False}, {"aircraft": catalog.STIK}, {"start": "runway"}):
            with self.assertRaises(ValueError):
                catalog.performance_tour(options)

    def test_fixed_render_scale_reaches_every_tour_case_and_rejects_invalid_values(self):
        args = parser().parse_args(["performance-tour", "--render-scale", "75", "--graphics", "automatic", "--dry-run"])
        self.assertEqual({case["render_scale"] for case in plan(args)}, {75})
        self.assertNotIn("render_scale", catalog.scenario("runway-menus"))
        for value in (True, 75.0, 74, "75"):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "render_scale"):
                catalog.scenario("runway-menus", {"render_scale": value})

    def test_native_panel_requires_borderless_and_product_vsync_values(self):
        with self.assertRaisesRegex(ValueError, "borderless"):
            catalog.scenario("runway-menus", {"resolution": [3024, 1964]})
        self.assertEqual(catalog.scenario("runway-menus", {"resolution": [3024, 1964], "window_mode": "borderless"})["resolution"], [3024, 1964])
        for value in ("adaptive", "mailbox", [], True):
            with self.assertRaises(ValueError):
                catalog.scenario("runway-menus", {"vsync_mode": value})

    def _snapshot(self, root, extra=""):
        source = root / "source"
        (source / "app/.godot/imported").mkdir(parents=True)
        files = {"app/project.godot": '[application]\nconfig/name="OpenRC Simulator"\n' + extra + '\n[rendering]\nrendering_method="mobile"\n',
                 "app/main.gd": "# immutable runtime fixture\n"}
        imports = {"app/.godot/imported/a.ctex": "immutable cache"}
        for name, data in {**files, **imports}.items():
            (source / name).write_text(data, encoding="utf-8")
        digest = lambda name: hashlib.sha256((source / name).read_bytes()).hexdigest()
        return {"format": "openrc-godtest-source-v1", "root": str(source),
                "files": {name: digest(name) for name in files}, "imports": {name: digest(name) for name in imports},
                "source_digest": "canonical", "project_mutated": False}

    def test_mac_isolation_changes_only_launch_name_and_preserves_shared_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = self._snapshot(root)
            run = root / "run"
            run.mkdir()
            launched = prepare_macos_launch(snapshot, run, user_home=root / "home")
            self.assertEqual(check_frozen(snapshot), [])
            self.assertEqual(check_frozen(launched), [])
            changed = [name for name in snapshot["files"] if snapshot["files"][name] != launched["files"][name]]
            self.assertEqual(changed, ["app/project.godot"])
            self.assertEqual(snapshot["imports"], launched["imports"])
            receipt = launched["profile_isolation"]
            self.assertTrue(Path(receipt["user_dir"]).is_dir())
            self.assertIn("OpenRC-GodTest-", receipt["project_name"])
            self.assertFalse(receipt["player_profile_touched"])
            canonical = (Path(snapshot["root"]) / "app/project.godot").read_text()
            actual = (Path(launched["root"]) / "app/project.godot").read_text()
            self.assertEqual(actual.replace(receipt["project_name"], "OpenRC Simulator"), canonical)

    def test_mac_refuses_name_overrides_and_custom_player_paths(self):
        for extra in ('config/name.macos="OpenRC Simulator"\n', 'config/use_custom_user_dir=true\n',
                      'config/project_settings_override="user://override.cfg"\n'):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                snapshot = self._snapshot(root, extra)
                run = root / "run"
                run.mkdir()
                with self.assertRaises(ValueError):
                    prepare_macos_launch(snapshot, run, user_home=root / "home")
                self.assertFalse((run / "mac-source").exists())
                self.assertEqual(check_frozen(snapshot), [])

    def test_user_manifest_cannot_choose_the_macos_profile(self):
        with self.assertRaisesRegex(ValueError, "unknown manifest"):
            catalog.scenario("runway-menus", {"isolated_user_dir": "/Users/player/Library/Application Support/Godot/app_userdata/OpenRC Simulator"})


if __name__ == "__main__":
    unittest.main()
