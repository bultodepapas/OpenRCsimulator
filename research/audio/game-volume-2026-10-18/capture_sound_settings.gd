extends SceneTree
# AUD-12b: opens the real app, Settings > Sound (focus on Game volume) and saves a PNG. Under Xvfb, from the repo root:
#   godot --path app --rendering-driver opengl3 --resolution 1280x720 --script /abs/research/audio/game-volume-2026-10-18/capture_sound_settings.gd -- --out=<png> --lang=en|es
const Preferences := preload("res://app_state/preferences.gd")
const PREFS := "user://capture_sound_settings.cfg"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else ""
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.language = str(args.get("lang", "en"))
	Preferences.save_to(PREFS, prefs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".display"))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	for i in 30: await process_frame
	app.open_settings(app.home.settings_button)
	for i in 10: await process_frame
	var settings = app.screens.get_screen("settings")
	settings._show_category(2)
	settings._master_slider.grab_focus()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(str(args.out))
	print("saved ", args.out, " ", image.get_size())
	quit()
