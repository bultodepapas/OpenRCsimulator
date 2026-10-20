"""Exercise the standalone lifecycle probe against disposable Godot projects.

The fixture tests use real Godot only when OPENRC_TEST_GODOT points to its direct
executable. They copy the production probe unchanged and provide a tiny fake app
that follows the same screen and session surface used by the probe.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

try:
    from .run_checked import run_checked
    from .lifecycle_check import analyze_report
except ImportError:  # direct unittest discovery from tools/godot
    from run_checked import run_checked
    from lifecycle_check import analyze_report


PROBE_SCRIPT = Path(__file__).with_name("lifecycle_probe.gd").resolve()
FIXTURE_CONFIG = {
    "scenario": "both",
    "cycles": 2,
    "warmup_cycles": 1,
    "settle_frames": 3,
    "dwell_seconds": 0,
}


@unittest.skipUnless(os.environ.get("OPENRC_TEST_GODOT"),
                     "set OPENRC_TEST_GODOT to run disposable real-Godot lifecycle fixtures")
class LifecycleProbeFixtureTests(unittest.TestCase):
    """Check clean routes, retained nodes, failed transitions, and output guards."""

    def setUp(self):
        if not PROBE_SCRIPT.is_file():
            self.fail(f"lifecycle probe is missing: {PROBE_SCRIPT}")
        self.temp = tempfile.TemporaryDirectory(prefix="openrc lifecycle fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "fixture project"
        self.project.mkdir()
        self.reports = self.root / "runner reports"
        self.godot = str(Path(os.environ["OPENRC_TEST_GODOT"]).expanduser().resolve())
        self._write_project()

    def _write_project(self):
        (self.project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="OpenRC lifecycle fixture"\n',
            encoding="utf-8",
        )
        app_state = self.project / "app_state"
        app_state.mkdir()
        (app_state / "preferences.gd").write_text(
            '''extends RefCounted

const DEFAULTS := {
    "check_updates": true,
    "first_flight_hint_seen": false,
    "language": "en",
}

static func save_to(path: String, prefs: Dictionary) -> Error:
    var cfg := ConfigFile.new()
    for key in prefs:
        cfg.set_value("preferences", str(key), prefs[key])
    return cfg.save(path)
''',
            encoding="utf-8",
        )
        (self.project / "fake_screens.gd").write_text(
            '''extends RefCounted

var top_id := ""
var workshop: Node

func is_top(screen_id: String) -> bool:
    return top_id == screen_id

func get_screen(screen_id: String) -> Node:
    return workshop if screen_id == "workshop" else null
''',
            encoding="utf-8",
        )
        (self.project / "fake_session.gd").write_text(
            '''extends Node

var sim: Node

func _ready() -> void:
    sim = Node.new()
    sim.name = "FakeSimulation"
    add_child(sim)
''',
            encoding="utf-8",
        )
        (self.project / "fake_flight.gd").write_text(
            '''extends Node

const FakeSessionScript := preload("res://fake_session.gd")

var startup_error := ""
var session: Node

func _ready() -> void:
    session = FakeSessionScript.new()
    session.name = "FakeSession"
    add_child(session)
''',
            encoding="utf-8",
        )
        (self.project / "fake_workshop.gd").write_text(
            '''extends Node

var variants_root := ""
var recovery_enabled := true

func _ready() -> void:
    var isolated := variants_root.begins_with("user://lifecycle_probe_") and not recovery_enabled
    print("FIXTURE_WORKSHOP_ISOLATED=true" if isolated else "FIXTURE_WORKSHOP_ISOLATED=false")
''',
            encoding="utf-8",
        )
        (self.project / "app_root.gd").write_text(
            '''extends Node

const FakeScreensScript := preload("res://fake_screens.gd")
const FakeFlightScript := preload("res://fake_flight.gd")
const FakeWorkshopScript := preload("res://fake_workshop.gd")

var user_args := PackedStringArray()
var preferences_path := ""
var update_check_url := ""
var home: Node
var home_scene: Node
var flight: Node
var pause_menu: Node
var screens

var _fixture_mode := ""
var _end_flight_calls := 0
var _detached_workshops: Array[Node] = []

func _ready() -> void:
    _fixture_mode = OS.get_environment("OPENRC_FIXTURE_MODE")
    screens = FakeScreensScript.new()
    _make_home()

func _make_home() -> void:
    home_scene = Node.new()
    home_scene.name = "FakeHomeScene"
    add_child(home_scene)
    home = Node.new()
    home.name = "FakeHomeUI"
    add_child(home)
    screens.top_id = "home"

func _retire(node: Node) -> void:
    if is_instance_valid(node):
        node.queue_free()

func start_flight() -> void:
    _retire(home)
    _retire(home_scene)
    home = null
    home_scene = null
    flight = FakeFlightScript.new()
    flight.name = "FakeFlight"
    add_child(flight)
    screens.top_id = "flight"

func open_pause() -> void:
    pause_menu = Node.new()
    pause_menu.name = "FakePauseMenu"
    add_child(pause_menu)
    screens.top_id = "pause"

func end_flight() -> void:
    _retire(pause_menu)
    pause_menu = null
    _retire(flight)
    flight = null
    _end_flight_calls += 1
    if _fixture_mode == "fail_home_after_warmup" and _end_flight_calls == 2:
        screens.top_id = "flight"
        return
    _make_home()

func open_workshop() -> void:
    screens.workshop = FakeWorkshopScript.new()
    screens.workshop.name = "FakeWorkshop"
    add_child(screens.workshop)
    screens.top_id = "workshop"

func close_workshop() -> void:
    var workshop: Node = screens.workshop
    if is_instance_valid(workshop):
        if _fixture_mode == "leak_workshop":
            remove_child(workshop)
            _detached_workshops.append(workshop)
        else:
            workshop.queue_free()
    screens.workshop = null
    screens.top_id = "home"

func _exit_tree() -> void:
    # The leak case stays alive long enough for the probe to observe it, then
    # releases it during fixture teardown to avoid a process-exit ObjectDB leak.
    for workshop in _detached_workshops:
        if is_instance_valid(workshop):
            workshop.free()
    _detached_workshops.clear()
''',
            encoding="utf-8",
        )
        (self.project / "app_root.tscn").write_text(
            '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://app_root.gd" id="1"]

[node name="FakeAppRoot" type="Node"]
script = ExtResource("1")
''',
            encoding="utf-8",
        )
        # Test the real diagnostic with no test-only edits or instrumentation.
        shutil.copyfile(PROBE_SCRIPT, self.project / "lifecycle_probe.gd")

    def command(self, output_dir: Path, *, overrides: tuple[str, ...] = ()) -> list[str]:
        config = FIXTURE_CONFIG
        options = [
            f"--out-dir={output_dir.resolve()}",
            f"--scenario={config['scenario']}",
            f"--cycles={config['cycles']}",
            f"--warmup-cycles={config['warmup_cycles']}",
            f"--settle-frames={config['settle_frames']}",
            f"--dwell-seconds={config['dwell_seconds']}",
        ]
        options.extend(overrides)
        return [
            self.godot, "--headless", "--path", str(self.project),
            "--audio-driver", "Dummy", "--max-fps", "60",
            "--script", str(self.project / "lifecycle_probe.gd"), "--", *options,
        ]

    def run_probe(self, name: str, *, mode: str = "clean", output_dir: Path | None = None,
                  overrides: tuple[str, ...] = (), required: list[str] | None = None) -> dict:
        target = output_dir or (self.root / f"probe {name}")
        with mock.patch.dict(os.environ, {"OPENRC_FIXTURE_MODE": mode}):
            return run_checked(
                self.command(target, overrides=overrides), self.reports,
                timeout=60, label=f"fixture-{name}", required=required,
            )

    @staticmethod
    def read_probe_report(output_dir: Path) -> dict:
        return json.loads((output_dir / "lifecycle.json").read_text(encoding="utf-8"))

    def test_clean_home_flight_home_and_workshop_routes(self):
        output_dir = self.root / "probe clean"
        result = self.run_probe(
            "clean", output_dir=output_dir,
            required=["FIXTURE_WORKSHOP_ISOLATED=true", "lifecycle capture complete"],
        )
        report = self.read_probe_report(output_dir)
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["process_exit"], 0)
        self.assertTrue(report["complete"], report)
        self.assertEqual(len(report["samples"]), 3)
        self.assertEqual(report["total_retired_alive"], 0)
        self.assertTrue(report["cleanup"]["complete"])
        self.assertTrue(all(not sample["retired_objects_alive"] for sample in report["samples"]))
        self.assertTrue((output_dir / "settings.cfg").is_file())
        self.assertTrue((self.project / "lifecycle_probe.gd").read_bytes() == PROBE_SCRIPT.read_bytes())

    def test_detached_workshop_node_is_reported_while_app_remains_alive(self):
        output_dir = self.root / "probe leaked workshop"
        with mock.patch.dict(FIXTURE_CONFIG, {"cycles": 5}):
            result = self.run_probe(
                "leaked-workshop", mode="leak_workshop", output_dir=output_dir,
                required=["FIXTURE_WORKSHOP_ISOLATED=true"],
            )
        report = self.read_probe_report(output_dir)
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["reason"], "process_exit")
        self.assertEqual(result["process_exit"], 1)
        self.assertTrue(report["complete"], report)
        self.assertGreater(report["total_retired_alive"], 0)
        self.assertTrue(any(sample["retired_objects_alive"] for sample in report["samples"][1:]))
        self.assertTrue(report["cleanup"]["complete"])
        self.assertEqual(report["cleanup"]["retired_objects_alive"], [])
        self.assertGreater(report["samples"][-1]["orphan_node_count"],
                           report["samples"][-1]["node_count"])
        analysis = analyze_report(report, result["capture_id"], report["config"])
        self.assertTrue(analysis["complete"], analysis)
        self.assertFalse(analysis["ok"])
        self.assertTrue(any(item.startswith("orphan_growth:") for item in analysis["findings"]))
        self.assertTrue(any(item.startswith("retired_objects_alive:") for item in analysis["findings"]))

    def test_failed_home_transition_keeps_an_incomplete_prefix(self):
        output_dir = self.root / "probe failed Home"
        result = self.run_probe(
            "failed-home", mode="fail_home_after_warmup", output_dir=output_dir,
        )
        report = self.read_probe_report(output_dir)
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["reason"], "process_exit")
        self.assertEqual(result["process_exit"], 1)
        self.assertFalse(report["complete"], report)
        self.assertIn("End flight did not return to Home", report["failure"])
        self.assertEqual(len(report["samples"]), 1, "retain the settled Home baseline as the incomplete prefix")
        self.assertTrue(report["cleanup"]["complete"])

    def test_invalid_options_do_not_create_an_output_artifact(self):
        output_dir = self.root / "probe invalid options"
        result = self.run_probe(
            "invalid-options", output_dir=output_dir,
            overrides=("--cycles=1",),
        )
        self.assertEqual(result["reason"], "process_exit", result)
        self.assertEqual(result["process_exit"], 2)
        self.assertFalse(output_dir.exists())

    def test_existing_output_directory_is_never_overwritten(self):
        output_dir = self.root / "probe existing output"
        output_dir.mkdir()
        sentinel = output_dir / "preserve.txt"
        sentinel.write_text("existing fixture evidence\n", encoding="utf-8")
        result = self.run_probe("existing-output", output_dir=output_dir)
        self.assertEqual(result["reason"], "process_exit", result)
        self.assertEqual(result["process_exit"], 2)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "existing fixture evidence\n")
        self.assertFalse((output_dir / "lifecycle.json").exists())


@unittest.skipUnless(os.environ.get("OPENRC_TEST_GODOT")
                     and os.environ.get("OPENRC_TEST_LIFECYCLE_NATIVE"),
                     "set OPENRC_TEST_GODOT and OPENRC_TEST_LIFECYCLE_NATIVE for the production smoke")
class NativeLifecycleProbeSmokeTests(unittest.TestCase):
    """Optional slow smoke of both production routes with isolated probe output."""

    def test_production_home_flight_home_and_workshop_routes(self):
        if not PROBE_SCRIPT.is_file():
            self.fail(f"lifecycle probe is missing: {PROBE_SCRIPT}")
        project = Path(__file__).resolve().parents[2] / "app"
        with tempfile.TemporaryDirectory(prefix="openrc native lifecycle ") as directory:
            root = Path(directory)
            output_dir = root / "probe output"
            command = [
                str(Path(os.environ["OPENRC_TEST_GODOT"]).expanduser().resolve()),
                "--headless", "--path", str(project), "--audio-driver", "Dummy",
                "--max-fps", "60", "--script", str(PROBE_SCRIPT), "--",
                f"--out-dir={output_dir}", "--scenario=both", "--cycles=2",
                "--warmup-cycles=1", "--settle-frames=3", "--dwell-seconds=0",
            ]
            result = run_checked(
                command, root / "runner reports", timeout=300, label="native-lifecycle-smoke",
                required=["lifecycle capture complete"],
            )
            report = json.loads((output_dir / "lifecycle.json").read_text(encoding="utf-8"))
            self.assertTrue(result["ok"], result)
            self.assertTrue(report["complete"], report)
            self.assertEqual(report["total_retired_alive"], 0, report)
            self.assertEqual(len(report["samples"]), 3)
            self.assertTrue(report["cleanup"]["complete"])
            self.assertTrue((output_dir / "settings.cfg").is_file())


if __name__ == "__main__":
    unittest.main()
