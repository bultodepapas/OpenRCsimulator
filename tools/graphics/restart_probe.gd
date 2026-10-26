## Native three-process smoke: real Home restart handler, High child, Standard grandchild.
## Test-only --script/log arguments are appended after validating the production argument list.
extends SceneTree

const Profile := preload("res://render/high_graphics_profile.gd")
const Preferences := preload("res://app_state/preferences.gd")
var stage := 0
var output := ""

func _initialize() -> void:
	stage = int(OS.get_environment("OPENRC_GRAPHICS_PROBE_STAGE"))
	output = OS.get_environment("OPENRC_GRAPHICS_PROBE_OUT")
	if stage == 0:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--out="):
				output = arg.trim_prefix("--out=")
		if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
			printerr("restart probe requires --out=<new absolute directory>")
			quit(2)
			return
		DirAccess.make_dir_recursive_absolute(output)
		OS.set_environment("OPENRC_GRAPHICS_PROBE_OUT", output)
	_run.call_deferred()

func _run() -> void:
	if stage not in [0, 1, 2] or output.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1920, 1080)
	var prefs_path := output.path_join("isolated.cfg")
	if stage == 0:
		var prefs := Preferences.DEFAULTS.duplicate(true)
		prefs.first_flight_hint_seen = true
		prefs.check_updates = false
		Preferences.save_to(prefs_path, prefs)
	var before := FileAccess.get_file_as_string(prefs_path)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs_path
	root.add_child(app)
	await _settle()
	app.open_settings()
	await _settle()
	var settings: CanvasLayer = app.screens.get_screen("settings")
	settings._show_category(3)
	await _settle()
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("stage-%d.png" % stage))
	var expected_renderer := "forward_plus" if stage == 1 else "gl_compatibility"
	var ok: bool = RenderingServer.get_current_rendering_method() == expected_renderer \
		and Profile.active() == (stage == 1) and app.has_home and app.home != null \
		and not settings._graphics_restart_button.disabled \
		and FileAccess.get_file_as_string(prefs_path) == before
	var report := {"stage": stage, "pid": OS.get_process_id(), "ok": ok,
		"graphics": Profile.describe(), "home": app.home != null,
		"executable": OS.get_executable_path(), "editor_binary": OS.has_feature("editor"),
		"viewport": [root.size.x, root.size.y],
		"contact_shadows_setting": ProjectSettings.get_setting(Profile.CONTACT_SHADOW_SETTING, false),
		"multi_bounce_occlusion_configured": ProjectSettings.get_setting("rendering/lights_and_shadows/multi_bounce_occlusion/enabled", false),
		"preferences_unchanged": FileAccess.get_file_as_string(prefs_path) == before}
	if ok and stage < 2:
		# Follow the actual menu signal through preview rollback and the Home-only gate.
		# Emit synchronously so the restart receipt can be written before the tree exits.
		settings._graphics_restart_button.pressed.emit()
		var args := OS.get_restart_on_exit_arguments()
		report["production_restart_arguments"] = args.duplicate()
		ok = OS.is_restart_on_exit_set() and args == Profile.restart_arguments(
			"high" if stage == 0 else "standard", OS.has_feature("editor"), ProjectSettings.globalize_path("res://"))
		report.ok = ok
		if ok:
			OS.set_environment("OPENRC_GRAPHICS_PROBE_STAGE", str(stage + 1))
			args.append_array(["--script", get_script().resource_path, "--log-file", output.path_join("stage-%d.log" % (stage + 1))])
			OS.set_restart_on_exit(true, args)
		else:
			OS.set_restart_on_exit(false)
			quit(1)
	else:
		app.free()
		await process_frame
		OS.set_restart_on_exit(false)
		quit(0 if ok else 1)
	FileAccess.open(output.path_join("stage-%d.json" % stage), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))


func _settle() -> void:
	# Exercise the source application without depending on a UI test helper.
	await process_frame
	await process_frame
