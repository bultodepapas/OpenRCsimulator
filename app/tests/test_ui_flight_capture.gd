# VQ-01b: the Home Fly transition leaves one flight world, then the capture tick policy is exact.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_flight_capture.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS: String = "user://test_ui_flight_capture_settings.cfg"
const CAPTURE_TICKS: int = 360

var _failures: int = 0
var _ui: RefCounted


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run()


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate()
	preferences.first_flight_hint_seen = true
	_check("test preferences save", Preferences.save_to(PREFS, preferences) == OK)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", PREFS)
	root.add_child(app)
	await _ui.settle()
	var home: Control = app.get("home")
	_check("interactive app starts on Home", home != null and app.get("flight") == null)
	if home == null:
		app.queue_free()
		quit(1)
		return
	_check("Home Fly is the focused real button", home.get("fly_button").has_focus())
	home.get("fly_button").pressed.emit()
	await _ui.settle()
	var flight: Node = app.get("flight")
	_check("Home Fly creates the flight", flight != null)
	_check("Home and HomeScene leave the viewport", _count_named_nodes(root, "Home") == 0 and _count_named_nodes(root, "HomeScene") == 0)
	_check("exactly one Camera3D remains under the viewport", _count_nodes(root.get_viewport(), "Camera3D") == 1, str(_count_nodes(root.get_viewport(), "Camera3D")))
	_check("exactly one WorldEnvironment remains under the viewport", _count_nodes(root.get_viewport(), "WorldEnvironment") == 1, str(_count_nodes(root.get_viewport(), "WorldEnvironment")))
	if flight == null:
		app.queue_free()
		quit(1)
		return
	_check("flight camera is active", root.get_viewport().get_camera_3d() == flight.get("_camera"))
	var session: Node = flight.get("session")
	var sim: Node = session.get("sim")
	flight.set_process(false)
	session.set("input_enabled", false)
	session.call("reset")
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	for tick_index in range(CAPTURE_TICKS):
		sim.step()
	_check("fixed capture state is exactly 360 simulation ticks", int(sim.get("tick")) == CAPTURE_TICKS, str(sim.get("tick")))
	_check("fixed capture state is exactly 1.5 simulation seconds", is_equal_approx(float(sim.call("time")), 1.5), str(sim.call("time")))
	await _ui.settle()
	_check("disabled simulation stays frozen without showing the pause state", int(sim.get("tick")) == CAPTURE_TICKS and not bool(sim.get("paused")))
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all UI flight capture checks passed" if _failures == 0 else "%d UI flight capture checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _count_nodes(parent: Node, type_name: String) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child.is_class(type_name):
			count += 1
		count += _count_nodes(child, type_name)
	return count


func _count_named_nodes(parent: Node, target_name: String) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child.name == target_name:
			count += 1
		count += _count_named_nodes(child, target_name)
	return count
