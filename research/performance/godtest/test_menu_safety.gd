extends SceneTree
## Exercise the benchmark's resumed-flight guard without changing aircraft or starting a scene.

const DisplayPreferences := preload("res://app_state/display_preferences.gd")


class ProbeDriver extends "res://debug/godtest_driver.gd":
	var ended_status := ""
	var ended_reason := ""
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _fail(message: String) -> void:
		failure = message
		running = false
	func _end(status: String = "complete", message: String = "") -> void:
		ended_status = status
		ended_reason = message


class FakePilot extends RefCounted:
	var failed := false
	func read_raw() -> Dictionary: return {}
	func observe() -> Dictionary: return {failed = failed, reason = "injected pilot failure"}


class FakeRadio extends RefCounted:
	var connected := false


class FakeSim extends RefCounted:
	var tick := 1
	var paused := false
	var fault_reason := ""


class FakeScreenStack extends RefCounted:
	var current: Node
	func top() -> Node: return current


class FakeFlight extends Node:
	var session: Node


class FakeApp extends Node:
	var flight: Node
	var pause_menu: Node
	var screens := FakeScreenStack.new()


class FakeSession extends Node:
	var sim := FakeSim.new()
	var radio := FakeRadio.new()
	var crash := {}
	var holds := {}
	var read_raw: Callable
	var physics_enabled := true
	var external_driver_enabled := false
	var mode := "success"
	var updates := 0
	var pilot: FakePilot
	var app: FakeApp
	func _process(_delta: float) -> void:
		updates += 1
		if mode != "stalled" and mode != "never_resumed": sim.tick += 1
		if updates != 4: return
		match mode:
			"pilot_failure": pilot.failed = true
			"crash": crash = {kind = "injected"}
			"fault": sim.fault_reason = "injected fault"
			"session_replaced": app.flight.session = null
			"screen_remains": app.screens.current = app
			"paused_again": sim.paused = true
			"tick_regressed": sim.tick = 0


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _case("success", true)
	for mode: String in ["pilot_failure", "crash", "fault", "session_replaced", "screen_remains", "paused_again", "tick_regressed", "stalled", "never_resumed"]:
		await _case(mode, false)
	await _test_end_home_refusal()
	_test_button_visibility()
	_test_profile()
	print("GOD_MENU_SAFETY_TESTS: ", failures, " failed")
	quit(0 if failures == 0 else 1)


func _case(mode: String, expected: bool) -> void:
	var pilot := FakePilot.new()
	var session := FakeSession.new()
	var flight := FakeFlight.new()
	var app := FakeApp.new()
	var driver := ProbeDriver.new()
	session.mode = mode
	session.pilot = pilot
	session.app = app
	session.read_raw = pilot.read_raw
	flight.session = session
	app.flight = flight
	driver.app = app
	driver.bound_session = session
	driver.pilot = pilot
	driver.running = true
	root.add_child(session)
	root.add_child(driver)
	var pause_tick := 1 if mode == "never_resumed" else 0
	var result: bool = await driver._observe_resumed_flight(pause_tick, 0.04, "test_resume")
	_check(result == expected, mode + " must " + ("pass" if expected else "fail"))
	if expected:
		_check(int(driver.phase.get("resume_observed_ticks", 0)) > 0, "successful resume records continued tick progress")
	else:
		_check(driver.ended_status == "failed", mode + " records a failed phase")
	driver.free()
	session.free()
	flight.free()
	app.free()


func _test_end_home_refusal() -> void:
	var pilot := FakePilot.new()
	var session := FakeSession.new()
	var flight := FakeFlight.new()
	var app := FakeApp.new()
	var driver := ProbeDriver.new()
	session.read_raw = pilot.read_raw
	app.flight = flight # The original session was replaced before Home was requested.
	driver.app = app
	driver.bound_session = session
	driver.pilot = pilot
	driver.running = true
	var result: bool = await driver._end_home()
	_check(not result and not driver.failure.is_empty(), "return to Home refuses a replaced session")
	driver.free()
	session.free()
	flight.free()
	app.free()


func _test_button_visibility() -> void:
	var driver := ProbeDriver.new()
	var button := Button.new()
	root.add_child(button)
	_check(driver._usable_menu_button(button), "visible enabled menu button is usable")
	button.hide()
	_check(not driver._usable_menu_button(button), "hidden menu button cannot be activated by its signal")
	button.show()
	button.disabled = true
	_check(not driver._usable_menu_button(button), "disabled menu button cannot be activated by its signal")
	button.free()
	driver.free()


func _test_profile() -> void:
	var owned := OS.get_environment("OPENRC_GODTEST_TEST_PROFILE").replace("\\", "/").simplify_path()
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if owned.is_empty() or not owned.is_absolute_path() or not user_dir.begins_with(owned.trim_suffix("/") + "/"):
		_check(false, "test requires an explicitly isolated user data directory")
		return
	var driver := ProbeDriver.new()
	driver.config = {window_mode = "borderless", resolution = [1920, 1080], scene_detail = "medium", camera = "pilot", max_fps = 0, vsync_mode = "disabled"}
	driver._prepare_profile()
	_check(driver.failure.is_empty(), "fresh owned profile prepared")
	var display_path := "user://settings.cfg.display"
	_check(FileAccess.file_exists(display_path), "display saved at the production preferences path")
	var display := DisplayPreferences.new(display_path)
	_check(display.config.window_mode == "borderless" and display.config.window_resolution == "auto", "borderless display uses the product's native panel resolution")
	_check(display.config.max_fps == 0 and display.config.vsync_mode == "disabled", "product loader receives requested pacing settings")
	driver._prepare_profile()
	_check(not driver.failure.is_empty(), "existing owned profile cannot be overwritten")
	driver.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
