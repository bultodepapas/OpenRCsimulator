## NR: native-renderer capture of the actual Home -> briefing -> flight path, with isolated preferences.
## --out=<fresh-directory> --lang=en|es --seed=<uint32> --width=1280 --height=720
extends SceneTree

const Preferences = preload("res://app_state/preferences.gd")
const AppRoot = preload("res://app_root.gd")

var _out: String
var _prefix: String
var _preferences_path: String
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			options[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	_out = str(options.get("out", ""))
	if _out.is_empty() or DirAccess.dir_exists_absolute(_out):
		printerr("Capture needs --out with a fresh directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var language: String = str(options.get("lang", "en"))
	var seed_value: int = int(options.get("seed", "4"))
	var size_value := Vector2i(int(options.get("width", "1280")), int(options.get("height", "720")))
	root.size = size_value
	_prefix = "%s-%d" % [language, size_value.y]
	_preferences_path = "user://nr_capture_%d.cfg" % OS.get_process_id()
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.language = language
	preferences.check_updates = false
	preferences.first_flight_hint_seen = true
	preferences.time_of_day = "day"
	Preferences.save_to(_preferences_path, preferences)
	var app := AppRoot.new()
	app.preferences_path = _preferences_path
	app.user_args = PackedStringArray()
	app.random_seed_source = func() -> int: return seed_value
	root.add_child(app)
	await _capture("home")
	app.open_natural_random()
	await _capture("briefing")
	var briefing: CanvasLayer = app.natural_random_screen
	if briefing.fly_button.disabled:
		printerr("Random preparation refused: ", briefing.error_label.text)
		app.free()
		_finish(1)
		return
	briefing.details_button.pressed.emit()
	await _capture("details")
	briefing.fly_button.pressed.emit()
	if app.flight == null:
		printerr("Random launch failed")
		app.free()
		_finish(1)
		return
	var flight: Node = app.flight
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.session.sim.set_paused(true)
	flight.session.reset()
	flight.session.sim.set_paused(true)
	var file := FileAccess.open(_out.path_join("scenario.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(flight.flight_scenario, "  ", true, true) + "\n")
	file.close()
	await _capture("flight")
	app.open_pause()
	await _capture("pause")
	app.free()
	_finish(_failures)

func _capture(label: String) -> void:
	for _frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var captured: Image = root.get_texture().get_image()
	var path: String = _out.path_join("%s-%s.png" % [_prefix, label])
	if captured == null or captured.is_empty() or captured.save_png(path) != OK:
		printerr("Capture failed: ", path)
		_failures += 1
	else:
		print("captured ", path)

func _finish(code: int) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_preferences_path))
	quit(0 if code == 0 else 1)
