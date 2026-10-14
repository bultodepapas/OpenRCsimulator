## Real native axis reads, automated button events, actual car garage/drive UI.
## Run with --out=<existing-directory>; does not load or save player preferences.
extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
var scene: Node3D
var output := ""
var selected := -1
var report := {"synthetic_axis_events": false, "synthetic_button_events": true,
	"physical_driving_qualification": false, "checks": {}}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a native renderer and --out=<existing-directory>")
		quit(2)
		return
	_run.call_deferred()

func button(index: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = selected
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(filename))
	report.checks[filename] = error == OK

func _run() -> void:
	TranslationServer.set_locale("es")
	root.size = Vector2i(1280, 720)
	root.title = "OpenRC — comprobación de controles del carro"
	root.grab_focus()
	await create_timer(0.4).timeout
	scene = Activity.new()
	scene.enable_audio = false
	root.add_child(scene)
	if not scene.startup_error.is_empty():
		report.error = scene.startup_error
		await finish()
		return
	await create_timer(0.8).timeout
	selected = scene._controller_device_id
	var info: Dictionary = scene._registry_device_for_id(selected)
	report.device = {"name": info.get("name", ""), "known": info.get("known", false), "kind": info.get("kind", "")}
	report.resting_axes = scene._joy_controls(selected) if selected >= 0 else {}
	report.checks.focused = root.has_focus()
	report.checks.known_gamepad = selected >= 0 and scene._has_flight_gamepad()
	report.checks.neutral_ready = scene._controls_ready(scene._last_controls)
	report.checks.garage_navigation_owned = scene.UiInput.selected_gamepad_id() == selected
	report.controls_hint = scene.dashboard.control_hint.text
	var panel_rect: Rect2 = scene.dashboard.panel.get_global_rect()
	report.checks.device_selector_visible = panel_rect.encloses(scene.dashboard.controller_choice.get_global_rect())
	report.checks.drive_button_visible = panel_rect.encloses(scene.dashboard.resume_button.get_global_rect())
	report.checks.ready_status_visible = panel_rect.encloses(scene.dashboard.input_status.get_global_rect())
	await capture("garage-native-es.png")
	if not report.checks.known_gamepad or not report.checks.neutral_ready:
		report.error = "A recognized gamepad must be connected with controls released."
		await finish()
		return
	await button(JOY_BUTTON_START)
	report.checks.start_drives = not scene.session.paused and not scene.dashboard.menu_visible
	await capture("drive-native-es.png")
	var camera_before: int = scene.camera_rig.mode
	await button(JOY_BUTTON_X)
	report.checks.camera_shortcut = scene.camera_rig.mode != camera_before
	await button(JOY_BUTTON_START)
	report.checks.start_pauses = scene.session.paused and scene.dashboard.menu_visible
	scene.handle_action("reset")
	await create_timer(0.3).timeout
	await button(JOY_BUTTON_START)
	report.checks.reset_then_start_drives = not scene.session.paused
	await button(JOY_BUTTON_Y)
	report.checks.recovery_pauses_and_marks_assisted = scene.session.paused and not scene.session.run_valid
	scene.select_driving_device(-1)
	await create_timer(0.3).timeout
	await capture("garage-keyboard-es.png")
	scene.handle_action("resume")
	report.checks.explicit_keyboard_drives = not scene.session.paused and scene._controller_device_id == -1
	await finish()

func finish() -> void:
	report.engine = Engine.get_version_info().string
	report.renderer = RenderingServer.get_video_adapter_name()
	report.passed = not report.has("error") and report.checks.values().all(func(value: Variant) -> bool: return value == true)
	var file := FileAccess.open(output.path_join("native-controls.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
	print(JSON.stringify(report))
	if is_instance_valid(scene): scene.free()
	await process_frame
	await process_frame
	quit(0 if report.passed else 1)
