# TOD-06 rendered UI proof and pointer smoke check. Run from the repository with a display (for example, xvfb-run).
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")

const PREFS_PATH: String = "user://tod06_rendered_ui_settings.cfg"
const EVIDENCE_RELATIVE: String = "docs/research/time-of-day-investigations/TOD-06"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(800, 600)
	DisplayServer.window_set_size(Vector2i(800, 600))
	TranslationServer.set_locale("en")
	var lighting: Dictionary = TimeOfDay.defaults()
	lighting["mode"] = "astronomical"
	lighting["date"] = "2026-03-20"
	lighting["local_seconds"] = 21600
	lighting["location_name"] = "Reference field (synthetic)"
	var checked: Dictionary = TimeOfDay.validate(lighting)
	if not checked.get("ok", false):
		_fail("capture lighting fixture is invalid: %s" % str(checked.errors))
		return
	var prefs: Dictionary = Preferences.load_from(PREFS_PATH)
	prefs["lighting_config"] = checked.config
	if Preferences.save_to(PREFS_PATH, prefs) != OK:
		_fail("could not prepare a rendered settings fixture")
		return

	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS_PATH
	root.add_child(app)
	await _frames(3)
	if app.home == null:
		_fail("Home did not open for the rendered UI proof")
		app.queue_free()
		return
	await _click(app.home.weather_button)
	if app.weather_dialog == null:
		_fail("mouse click on Home's Weather button did not open the dialog")
		app.queue_free()
		return

	var dialog: CanvasLayer = app.weather_dialog
	dialog.tab_container.current_tab = 3
	await _frames(3)
	var summary: Label = dialog.time_of_day_controls.find_child("TimeOfDaySummary", true, false) as Label
	if summary == null or not summary.text.contains("Reference field (synthetic)"):
		_fail("time-of-day summary is not visible outside Advanced: %s" % (summary.text if summary != null else "missing"))
		app.queue_free()
		return
	await _capture("time-of-day-en-800x600.png")

	app.set_language("es")
	await _frames(3)
	await _capture("time-of-day-es-800x600.png")

	await _click(dialog.cancel_button)
	if app.weather_dialog != null:
		_fail("mouse click on Cancel did not close the dialog")
	else:
		print("mouse pointer path passed: Home → Weather → Cancel")
	if not _failed:
		print("rendered English and Spanish 800×600 captures saved under docs/research/time-of-day-investigations/TOD-06")
	app.queue_free()
	await _frames(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	quit(1 if _failed else 0)


func _capture(file_name: String) -> void:
	await _frames(2)
	var app_path: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var output_dir: String = app_path.get_base_dir().path_join(EVIDENCE_RELATIVE)
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		_fail("could not create screenshot folder (error %d)" % make_dir_error)
		return
	var image: Image = root.get_texture().get_image()
	if image.get_size() != Vector2i(800, 600):
		_fail("expected an 800×600 viewport, got %s" % str(image.get_size()))
		return
	var path: String = output_dir.path_join(file_name)
	var save_error: Error = image.save_png(path)
	if save_error != OK:
		_fail("could not save %s (error %d)" % [path, save_error])
		return
	print("saved %s" % path)


func _click(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await _frames(2)
	event.pressed = false
	root.push_input(event)
	await _frames(2)


func _frames(count: int) -> void:
	for _index: int in count:
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	printerr("FAIL: %s" % message)
	quit(1)
