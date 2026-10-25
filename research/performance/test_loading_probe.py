"""Exercise loading-probe teardown with real mixer playback and an intentional retained reference.

python research/performance/test_loading_probe.py --godot <pinned-engine>
Fixtures stay outside app/ and cannot modify user settings.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "research/performance/loading_probe.gd"

FIXTURE = '''extends "{probe}"
var _held: AudioStreamPlayback

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	_settings_path = args[1] + ".settings.cfg"
	var settings := FileAccess.open(_settings_path, FileAccess.WRITE)
	settings.store_string("owned by test")
	settings.close()
	_app = Node3D.new()
	root.add_child(_app)
	var player := AudioStreamPlayer3D.new()
	var stream: AudioStreamMP3 = load("res://assets/audio/water/randommind-vistula-short.mp3").duplicate()
	stream.loop = true
	player.stream = stream
	_app.add_child(player)
	player.play()
	await physics_frame
	await process_frame
	if not player.has_stream_playback():
		_fail("fixture has no playback")
		return
	var node_ref: WeakRef = weakref(_app)
	if mode == "failure":
		_fail("intentional failure after settings and audio creation")
		return
	if mode == "retained":
		_held = player.get_stream_playback()
	var shutdown := await _cleanup()
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify({{shutdown = shutdown, app_freed = node_ref.get_ref() == null}}))
	output.close()
	_held = null
	await create_timer(0.2).timeout
	if mode == "retained":
		_fail("intentional retained playback timeout")
		return
	quit(0)
'''

HANDOFF_FIXTURE = '''extends "{probe}"

class MockApp extends Node:
	var flight: Node
	var _loading_active := false

class MockHome extends Node:
	var fly_button: Button

class MockSession extends Node:
	var flyable := true

	func is_flyable() -> bool:
		return flyable

class MockFlight extends Node:
	var startup_error := ""
	var session: Node


func _run() -> void:
	var passed := await _deferred_success()
	if passed:
		passed = await _staged_success()
	if passed:
		passed = await _rejected_launch()
	if passed:
		passed = await _cancelled_launch()
	if passed:
		passed = await _bounded_timeout()
	if passed:
		passed = await _startup_error()
	if passed:
		passed = await _unflyable_session()
	if passed:
		print("PASS all Home Fly handoff regressions")
	quit(0 if passed else 1)


func _route() -> Array:
	var app := MockApp.new()
	var home := MockHome.new()
	home.fly_button = Button.new()
	home.fly_button.disabled = true # Models Home after it has accepted Fly.
	home.add_child(home.fly_button)
	app.add_child(home)
	root.add_child(app)
	return [app, home]


func _flight(startup_error := "", flyable := true) -> MockFlight:
	var flight := MockFlight.new()
	flight.startup_error = startup_error
	var session := MockSession.new()
	session.flyable = flyable
	flight.session = session
	flight.add_child(session)
	return flight


func _check_case(condition: bool, label: String, detail := "") -> bool:
	if condition:
		print("PASS Home Fly handoff: ", label)
		return true
	push_error("Home Fly handoff regression failed: %s %s" % [label, detail])
	return false


func _discard_app(app: Node) -> void:
	if is_instance_valid(app):
		if app.get_parent() != null:
			app.get_parent().remove_child(app)
		app.free()


func _deferred_success() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	var flight := _flight()
	app.add_child(flight)
	app.set_deferred("flight", flight)
	if not app.flight == null:
		push_error("Home Fly handoff success fixture was not deferred")
		await _discard_app(app)
		return false
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var ok: bool = result.get("ok", false) and result.get("flight") == flight and int(result.get("ready_usec", 0)) > 0
	var checked := _check_case(ok, "deferred success", str(result))
	await _discard_app(app)
	return checked


func _rejected_launch() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	home.fly_button.set_deferred("disabled", false) # Home.reject_start restores a retryable button.
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var ok: bool = not result.get("ok", true) and str(result.get("error", "")).begins_with("Home Fly rejected:")
	var checked := _check_case(ok, "rejected launch", str(result))
	await _discard_app(app)
	return checked


func _staged_success() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	app._loading_active = true
	var flight := MockFlight.new() # The candidate exists before its session is ready.
	app.add_child(flight)
	app.flight = flight
	app.remove_child(home)
	_finish_staged_fixture(app, flight)
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var checked := _check_case(result.get("ok", false) and not app._loading_active,
		"staged success with detached Home and incomplete candidate", str(result))
	home.free()
	await _discard_app(app)
	return checked


func _finish_staged_fixture(app: MockApp, flight: MockFlight) -> void:
	await process_frame
	await process_frame
	flight.session = MockSession.new()
	flight.add_child(flight.session)
	app._loading_active = false


func _cancelled_launch() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	root.call_deferred("remove_child", app)
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var ok: bool = not result.get("ok", true) and str(result.get("error", "")).begins_with("Home Fly cancelled:")
	var checked := _check_case(ok, "cancelled route", str(result))
	await _discard_app(app)
	return checked


func _bounded_timeout() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	var max_frames := 2
	var start_frame := Engine.get_process_frames()
	var result: Dictionary = await _wait_for_flight(app, home, max_frames)
	var ok: bool = not result.get("ok", true) and str(result.get("error", "")) == \
		"Home Fly handoff exceeded %d process frames" % max_frames
	ok = ok and Engine.get_process_frames() - start_frame == max_frames
	var checked := _check_case(ok, "bounded pending timeout", str(result))
	await _discard_app(app)
	return checked


func _startup_error() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	var flight := _flight("controlled startup error")
	app.add_child(flight)
	flight.session = null # Startup error must be reported before session validation.
	app.flight = flight
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var ok: bool = not result.get("ok", true) and str(result.get("error", "")) == \
		"Home Fly startup error: controlled startup error"
	var checked := _check_case(ok, "startup_error", str(result))
	await _discard_app(app)
	return checked


func _unflyable_session() -> bool:
	var route := _route()
	var app: MockApp = route[0]
	var home: MockHome = route[1]
	app.flight = _flight("", false)
	app.add_child(app.flight)
	var result: Dictionary = await _wait_for_flight(app, home, 4)
	var ok: bool = not result.get("ok", true) and str(result.get("error", "")) == "Flight session is not flyable"
	var checked := _check_case(ok, "unflyable session", str(result))
	await _discard_app(app)
	return checked
'''


PREPARATION_FIXTURE = '''extends "{probe}"

class PreparingApp extends Node:
	var home_flight_preparation := {{drained = false}}

	func shutdown_home_flight_preparation() -> void:
		for index in 3:
			await get_tree().process_frame
		home_flight_preparation.drained = true


func _run() -> void:
	_app = PreparingApp.new()
	root.add_child(_app)
	var app_ref: WeakRef = weakref(_app)
	var before := Engine.get_process_frames()
	var shutdown := await _cleanup()
	if not shutdown.preparation_drained or app_ref.get_ref() != null \\
			or Engine.get_process_frames() - before < 3:
		push_error("probe freed AppRoot before preparation drained")
		quit(1)
		return
	print("PASS probe waits for preparation before freeing AppRoot")
	quit(0)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    engine = str(args.godot.resolve())
    with tempfile.TemporaryDirectory(prefix="openrc-loading-probe-") as directory:
        folder = Path(directory)
        script = folder / "fixture.gd"
        script.write_text(FIXTURE.format(probe=PROBE.as_posix()), encoding="utf-8")
        for mode in ("success", "failure", "retained"):
            output = folder / (mode + ".json")
            command = [engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy",
                       "--verbose", "--script", str(script), "--", mode, str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
            log = result.stdout + result.stderr
            assert result.returncode == (0 if mode == "success" else 1), log
            assert not Path(str(output) + ".settings.cfg").exists(), log
            assert "instances were leaked" not in log, log
            if mode == "failure":
                assert "intentional failure after settings and audio creation" in log, log
                assert '"audio_released":true' in log and '"settings_removed":true' in log, log
                assert not output.exists(), "Failure must not emit a successful timing report"
                assert log.count("ERROR:") == 1, log
            else:
                if mode == "success":
                    assert not re.search(r"(?m)^(?:SCRIPT )?ERROR:", log), log
                else:
                    assert "intentional retained playback timeout" in log and log.count("ERROR:") == 1, log
                report = json.loads(output.read_text())
                state = report["shutdown"]
                assert report["app_freed"] and state["settings_removed"], report
                assert state["tracked_playbacks"] == 1, report
                assert state["audio_released"] == (mode == "success"), report
                assert state["remaining_playbacks"] == (0 if mode == "success" else 1), report
                if mode == "retained":
                    assert 1_000_000 <= state["elapsed_usec"] < 2_000_000, report
            print("PASS", mode, flush=True)
        # A rejected invocation must never remove an existing output or settings file.
        output = folder / "existing.json"
        settings = Path(str(output) + ".settings.cfg")
        output.write_bytes(b"existing report")
        settings.write_bytes(b"existing settings")
        rejected = subprocess.run([engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver",
                                   "Dummy", "--script", str(PROBE), "--", "--output=" + str(output)],
                                  capture_output=True, timeout=15)
        assert rejected.returncode == 1
        assert output.read_bytes() == b"existing report" and settings.read_bytes() == b"existing settings"
        print("PASS existing files preserved")

        handoff_script = folder / "handoff_fixture.gd"
        handoff_script.write_text(HANDOFF_FIXTURE.format(probe=PROBE.as_posix()), encoding="utf-8")
        handoff = subprocess.run([engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver",
                                  "Dummy", "--verbose", "--script", str(handoff_script)],
                                 capture_output=True, text=True, timeout=15)
        handoff_log = handoff.stdout + handoff.stderr
        assert handoff.returncode == 0, handoff_log
        assert "PASS all Home Fly handoff regressions" in handoff_log, handoff_log
        for case in ("deferred success", "rejected launch", "cancelled route", "bounded pending timeout",
                     "startup_error", "unflyable session"):
            assert "PASS Home Fly handoff: " + case in handoff_log, handoff_log
        assert not re.search(r"(?m)^(?:SCRIPT )?ERROR:", handoff_log), handoff_log
        assert "instances were leaked" not in handoff_log, handoff_log
        print("PASS Home Fly handoff states", flush=True)

        preparation_script = folder / "preparation_fixture.gd"
        preparation_script.write_text(PREPARATION_FIXTURE.format(probe=PROBE.as_posix()), encoding="utf-8")
        preparation = subprocess.run([engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver",
                                      "Dummy", "--verbose", "--script", str(preparation_script)],
                                     capture_output=True, text=True, timeout=15)
        preparation_log = preparation.stdout + preparation.stderr
        assert preparation.returncode == 0, preparation_log
        assert "PASS probe waits for preparation before freeing AppRoot" in preparation_log, preparation_log
        assert not re.search(r"(?m)^(?:SCRIPT )?ERROR:", preparation_log), preparation_log
        assert "instances were leaked" not in preparation_log, preparation_log
        print("PASS preparation drain before teardown", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
