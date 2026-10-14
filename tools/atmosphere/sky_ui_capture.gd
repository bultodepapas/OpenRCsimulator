## FW-78: actual Home/conditions UI at 720p. Use a caller-owned output folder.
extends SceneTree
const Preferences := preload("res://app_state/preferences.gd")
var out := ""
var locale := "es"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--locale="):
			locale = arg.trim_prefix("--locale=")
	_run.call_deferred()

func _run() -> void:
	if out.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.render_loop_enabled = false
	root.size = Vector2i(1280, 720)
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.language = locale
	prefs.time_of_day = "day"
	prefs.check_updates = false
	var path := "user://fw78-capture-%d.cfg" % OS.get_process_id()
	Preferences.save_to(path, prefs)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = path
	root.add_child(app)
	await _settle()
	_save("home")
	app.open_weather()
	app.weather_dialog.tab_bar.current_tab = 4
	await _settle()
	_save("sky-gallery")
	app.weather_dialog.sky_controls.select_preset("electrical_storm")
	await _settle()
	app.weather_dialog.tab_scroll.scroll_vertical = 10000
	await _settle()
	_save("storm-controls")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.remove_child(app)
	app.free()
	quit()

func _settle() -> void:
	for frame: int in 12:
		await process_frame
		RenderingServer.force_draw(false)

func _save(label: String) -> void:
	var error := root.get_texture().get_image().save_png(out.path_join(locale + "-" + label + ".png"))
	if error != OK:
		push_error("Could not save UI evidence: " + error_string(error))
