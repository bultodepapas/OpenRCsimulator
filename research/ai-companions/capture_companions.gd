## Native rendered evidence, using isolated preferences and production scene/model paths.
extends SceneTree
const UiDriver := preload("res://tests/ui_driver.gd")
const Frames := preload("res://render/frames.gd")
const PREFS := "user://afc_capture_isolated.cfg"
var ui: RefCounted
var app: Node
var output := ""
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _capture(file_name: String) -> void:
	await create_timer(0.25).timeout # Let the shared screen entrance fade finish.
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path := output.path_join(file_name)
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failed = true
		printerr("Capture failed: ", path)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a native renderer and --out=<new directory>.")
		quit(2)
		return
	output = ProjectSettings.globalize_path(output)
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("Capture output must be a new directory.")
		quit(2)
		return
	TranslationServer.set_locale("en")
	root.size = Vector2i(1280, 720)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	ui = UiDriver.new(self)
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	app.controllers.enumerate_devices = func() -> Array[Dictionary]: return []
	app.controllers.refresh()
	app.preferences.latency_marker = false
	app.preferences.first_flight_hint_seen = true
	app.open_companions_settings(app.home.companions_button)
	await ui.settle()
	await _capture("home-dialog.png")
	app.companions_dialog.enabled_check.button_pressed = true
	app.companions_dialog.count_picker.select(2)
	app.companions_dialog.seed_edit.text = "20261020"
	app.companions_dialog._on_apply()
	await ui.settle()
	app.start_flight()
	if app.flight == null or not app.flight.startup_error.is_empty():
		printerr("Production flight did not start.")
		await ui.close_app(app)
		quit(1)
		return
	await create_timer(1.0).timeout
	for companion: Node in app.flight.companions.agents:
		if companion.session.sim.tick < 1 or not companion.failure.is_empty():
			failed = true
			printerr("Companion did not advance: ", companion.failure)
	app.open_pause()
	await ui.settle()
	app.open_companions_settings(app.pause_menu.companions_button)
	await ui.settle()
	await _capture("pause-dialog.png")
	app.close_companions()
	app._close_pause()
	var flight: Node = app.flight
	flight.session.hold("evidence")
	flight.set_process(false)
	flight.set_overlays_visible(false)
	await ui.settle()
	await _capture("pilot-view.png")
	# Inspection camera only: the aircraft pose, controls and source model remain untouched.
	var agent: Node = flight.companions.agents[0]
	var state: PackedFloat64Array = agent.session.sim.state
	var center: Vector3 = Frames.ned_to_render([state[0], state[1], state[2]])
	flight._camera.global_position = center + Vector3(2.5, 1.5, 3.5)
	flight._camera.look_at(center)
	flight._camera.fov = 45.0
	await _capture("companion-closeup.png")
	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("COMPANION CAPTURES COMPLETE")
	quit(1 if failed else 0)
