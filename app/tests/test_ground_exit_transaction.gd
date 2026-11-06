## UI-31-R2: the root and real ground participant share one departure decision.
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Dashboard := preload("res://vehicles/ground/ground_dashboard.gd")

class ExportSession extends "res://sim/ground_vehicle/session.gd":
	var export_attempts := 0
	var stop_calls := 0
	var allow_export := false
	func stop_recording() -> bool:
		stop_calls += 1
		return super.stop_recording()
	func export_recording(_name: String) -> Dictionary:
		export_attempts += 1
		if not allow_export: return {ok = false, error = "injected export failure"}
		_recording_exported = true
		return {ok = true, csv_path = "memory://recording.csv", metadata_path = "memory://recording.json"}

class GroundFixture extends "res://vehicles/ground/ground_scene.gd":
	func _ready() -> void:
		session = ExportSession.new()
		if not session.prepare_default(): startup_error = "ground fixture did not prepare"
		add_child(session)
		dashboard = Dashboard.new()
		add_child(dashboard)
		dashboard.action_requested.connect(handle_action)
		open_garage()
		set_process(false)
		set_physics_process(false)
	func _accept_controller_button(device: int) -> bool:
		return device == 42
	func _registry_selected_device_id(_role: String) -> int:
		return 42

class ProbeApp extends "res://app_root.gd":
	var quit_requests := 0
	func _request_app_quit() -> void:
		quit_requests += 1

var checks := 0
var failures := 0
var ui: RefCounted

func check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _app(with_home: bool) -> ProbeApp:
	var app := ProbeApp.new()
	app.preferences_path = "user://ground_exit_%d_%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	app.user_args = PackedStringArray() if with_home else PackedStringArray(["--vehicle=mt8-bisonte"])
	app.ground_vehicle_factory = func() -> Node3D: return GroundFixture.new()
	root.add_child(app)
	await ui.settle()
	if with_home:
		app.start_ground_vehicle("mt8-bisonte")
		await ui.settle()
	return app

func _dialog(app: ProbeApp) -> ConfirmationDialog:
	for frame in 12:
		if is_instance_valid(app._trace_recovery_dialog): return app._trace_recovery_dialog
		await process_frame
	return null

func _quit(app: ProbeApp) -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while app.quit_requests == 0 and Time.get_ticks_msec() < deadline:
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _notify_main_window(node: Node) -> void:
	# Match Window::_propagate_window_notification in pinned Godot cafc17a19:
	# nested Windows are independent OS/embedded event surfaces, not notification recipients.
	node.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for child: Node in node.get_children():
		if not child is Window: _notify_main_window(child)

func _close(app: ProbeApp) -> void:
	var path := app.preferences_path
	await ui.close_app(app)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	ui = UiDriver.new(self)
	var initial_auto_accept := auto_accept_quit
	var app := await _app(true)
	var ground: Node = app.ground_vehicle
	check("root sets managed ownership before the real ground scene enters", ground != null and ground.departure_managed and not ground._owns_auto_quit and not auto_accept_quit)
	if ground == null:
		await _close(app)
		quit(1)
		return
	var session: Node = ground.session
	ground.dashboard.set_menu(false)
	session.release_pause_hold("garage")
	session.tick_once({throttle = 0.0, steering = 0.0, brake = 0.0, reverse = false, armed = true})
	session.resume()
	check("departure begins driving with no focused menu control", not session.paused and root.gui_get_focus_owner() == null)
	check("active recording starts", session.start_recording())
	var retained: PackedByteArray = session._record_samples.to_byte_array()
	# Deliver the notification to both real handlers, not just AppRoot.notification().
	_notify_main_window(app)
	_notify_main_window(app)
	app.quit_app() # enter the deferred request synchronously, then exercise its first modal gap
	_key(KEY_F9)
	ground.dashboard.record_button.pressed.emit()
	check("record shortcuts and queued button actions cannot replace pending data", session.recording_generation == 1 and session._record_samples.to_byte_array() == retained)
	var dialog := await _dialog(app)
	check("combined WM close is vetoed by one failed export", dialog != null and app.quit_requests == 0 and session.stop_calls == 1 and session.export_attempts == 1 and session.has_unexported_recording())
	check("the garage input surface is blocked throughout the request", ground.dashboard.record_button.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE and ground.dashboard.resume_button.get_focus_mode_with_override() == Control.FOCUS_NONE)
	_notify_main_window(app)
	await ui.settle()
	check("repeated close reuses the decision and retained data", app._trace_recovery_dialog == dialog and session.export_attempts == 1 and session._record_samples.to_byte_array() == retained)
	var pad := InputEventJoypadButton.new()
	pad.device = 42
	pad.button_index = JOY_BUTTON_START
	pad.pressed = true
	ground._unhandled_input(pad)
	check("a pad press during the guard is remembered without acting", ground._shortcut_buttons.has("42:6") and ground.dashboard.menu_visible and session.paused)
	pad.pressed = false
	ground._unhandled_input(pad)
	check("a pad release during the guard clears its edge", ground._shortcut_buttons.is_empty())
	pad.pressed = true
	ground._unhandled_input(pad)
	# Model releases/presses swallowed by the native exclusive Window using the existing reader seam.
	ground._shortcut_buttons["42:2"] = true
	var held_buttons := {JOY_BUTTON_START: true, JOY_BUTTON_Y: true}
	ground.joy_button_reader = func(device: int, button: JoyButton) -> bool:
		return device == 42 and held_buttons.get(button, false)
	if dialog != null: dialog.confirmed.emit()
	await ui.settle()
	check("Stay reconciles buttons even when modal input swallowed their events", not ground._shortcut_buttons.has("42:2") and ground._shortcut_buttons.has("42:3"))
	ground._unhandled_input(pad)
	check("Stay preserves garage pause and a still-held pad cannot resume", not app._exit_request_active and session.paused and ground.dashboard.menu_visible and "garage" in session.pause_holds() and "exit_guard" not in session.pause_holds())
	check("Stay restores the original input surface and retains unsaved samples", ground.is_processing_unhandled_input() and ground.dashboard.record_button.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE and session._record_samples.to_byte_array() == retained)
	check("Stay from driving gives the garage a usable Resume focus", ground.dashboard.resume_button.has_focus())
	pad.pressed = false
	ground._unhandled_input(pad)
	check("releasing after Stay rearms the pad shortcut", not ground._shortcut_buttons.has("42:6"))
	session.allow_export = true
	ground.handle_action("record")
	check("manual save resolves the failed generation", not session.has_unexported_recording() and session.export_attempts == 2)
	ground.handle_action("home")
	await ui.settle()
	check("manual save then Home completes without another save or quit", app.ground_vehicle == null and app.home != null and app.quit_requests == 0 and not auto_accept_quit)
	await _close(app)

	app = await _app(false)
	ground = app.ground_vehicle
	session = ground.session
	check("stopped recording fixture starts and retains data", session.start_recording() and session.stop_recording())
	app.quit_app()
	dialog = await _dialog(app)
	check("already-stopped recording also vetoes departure", dialog != null and session.export_attempts == 1 and app.quit_requests == 0)
	session.allow_export = true
	if dialog != null: dialog.custom_action.emit("retry")
	await _quit(app)
	check("explicit Retry saves and reaches final quit once", app.quit_requests == 1 and session.export_attempts == 2 and not session.has_unexported_recording())
	await _close(app)

	app = await _app(false)
	ground = app.ground_vehicle
	session = ground.session
	check("discard fixture starts", session.start_recording())
	app.quit_app()
	dialog = await _dialog(app)
	if dialog != null: dialog.custom_action.emit("discard")
	await _quit(app)
	check("explicit Discard clears only this recording and commits once", app.quit_requests == 1 and session.export_attempts == 1 and not session.has_unexported_recording() and session._record_samples.is_empty())
	await _close(app)
	check("host automatic-close policy is restored after disposal", auto_accept_quit == initial_auto_accept)
	print("Ground exit transaction: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
