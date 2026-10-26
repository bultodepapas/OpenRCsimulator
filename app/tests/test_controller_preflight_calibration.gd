extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Profile := preload("res://input/controller_profile.gd")
const Radio := preload("res://input/rc_input.gd")
const PREFS := "user://test_controller_preflight_calibration.cfg"
var failures: int = 0
var checks: int = 0
var ui: RefCounted
var app: Node
var setup: Node
var raw: PackedFloat64Array = PackedFloat64Array()
var devices: Array = []
var selection_at_start: int = -1

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_cleanup()
	ui = UiDriver.new(self)
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	devices = [{"id": 15, "name": "Synthetic limited radio", "guid": "issue5-radio", "kind": "radio", "known": false, "serial_number": "issue5"}]
	app.controllers.enumerate_devices = func() -> Array: return devices
	app.controllers.refresh()
	app.open_controls()
	await ui.settle()
	setup = app.screens.top()
	check("Home offers calibration for a connected radio without a flight", app.flight == null and setup.calibrate_button.visible and not setup.calibrate_button.disabled)
	if not setup.calibrate_button.visible:
		await _finish()
		return
	var original: Dictionary = setup.current_profile()
	original.presentation.glyph_family = "generic"
	original.throttle_rate = 1.7
	original.roll["expo"] = 0.35
	original.roll["deadzone"] = 0.1
	original.aux = {"smoke": {"type": "button", "button": 20, "mode": "level"}, "flaps": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false}}
	check("custom radio fixture uses valid V2 data", Profile.validate(original).ok)
	setup._set_draft_profile(original)
	setup.profile_name_edit.text = "My limited radio"
	var selection_before: int = app.controllers.registry.selected_device_id("flight")
	await _open_wizard()
	await ui.tap(KEY_ESCAPE)
	check("Escape cancels without altering the draft or its edited name", app.screens.is_top("controls") and setup.current_profile() == original and setup.profile_name_edit.text == "My limited radio")
	await _open_wizard()
	app.screens.top().request_close()
	check("Close cancels without saving", app.screens.is_top("controls") and app.controllers.store.load_all().profiles.is_empty())
	for notification_code: int in [Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		await _open_wizard()
		app.screens.top().notification(notification_code)
		check("focus loss cancels calibration", app.screens.is_top("controls") and setup.current_profile() == original)
	await _open_wizard()
	devices.clear()
	app.controllers.refresh()
	check("disconnect cancels and disables calibration", app.screens.is_top("controls") and not setup.calibrate_button.visible and setup.current_profile() == original)
	devices.append({"id": 15, "name": "Synthetic limited radio", "guid": "issue5-radio", "kind": "radio", "known": false, "serial_number": "issue5"})
	app.controllers.refresh()
	await _open_wizard()
	devices[0].guid = "replacement-radio"
	app.controllers.refresh()
	check("reused connection ID with another identity cancels", app.screens.is_top("controls") and setup.current_profile() == original)
	for invalid: Variant in [NAN, INF, 1.1, "invalid"]:
		await _open_wizard()
		var bad: Node = app.screens.top()
		bad.read_axis = func(_id: int, _axis: int) -> Variant: return invalid
		bad.advance()
		check("invalid raw samples never become calibration", app.screens.is_top("controls") and setup.current_profile() == original)
	await _open_wizard()
	app.screens.top()._process(5.1)
	check("application suspension cancels", app.screens.is_top("controls") and setup.current_profile() == original)
	await _open_wizard()
	await ui.tap(KEY_ENTER) # rest
	await ui.tap(KEY_ENTER) # throttle without a sweep
	check("missing sweep reports an error without changing draft", app.screens.is_top("radio_calibration") and app.screens.top()._error_label.visible and setup.current_profile() == original)
	app.screens.top().request_close()

	for inverted: bool in [false, true]:
		await _open_wizard(inverted)
		await _complete_wizard(inverted)
		var calibrated: Dictionary = setup.current_profile()
		check("completed calibration returns to Controls without a flight", app.screens.is_top("controls") and app.flight == null)
		check("limited travel records endpoints and inversion", calibrated.throttle.axis == 4 and is_equal_approx(calibrated.throttle.min, -0.6) and is_equal_approx(calibrated.throttle.max, 0.6) and calibrated.throttle.invert == inverted)
		check("calibration preserves identity, settings, safe AUX and unsaved name", calibrated.profile_id == original.profile_id and calibrated.actions == original.actions and calibrated.presentation == original.presentation and calibrated.throttle_rate == 1.7 and calibrated.aux == {"smoke": original.aux.smoke} and setup.profile_name_edit.text == "My limited radio")
		check("calibration preserves per-channel shaping settings", calibrated.roll.expo == 0.35 and calibrated.roll.deadzone == 0.1)
		if not inverted:
			check("AUX consumed by a new flight axis is reported", "flaps" in setup.status_label.text)
		check("wizard completion never persists a profile", app.controllers.store.load_all().profiles.is_empty())
		_check_arming(calibrated, inverted)
	var complete: Dictionary = setup.current_profile()
	var commit: Callable = setup.save_and_apply
	setup.save_and_apply = func(_candidate: Dictionary, _flight_id: int, _ui_id: int) -> Dictionary: return {"ok": false, "error": "test storage failure"}
	check("failed Save keeps calibrated draft and durable storage unchanged", not setup._save_profile(false) and setup.current_profile() == complete and app.controllers.store.load_all().profiles.is_empty() and app.screens.is_top("controls"))
	setup.save_and_apply = commit
	var stale_generation: int = app.controllers.registry.connection_generation(15)
	app.controllers.registry.disconnect_device(15)
	app.controllers.refresh()
	check("completed ranges cannot be saved to a new connection generation", not setup._save_profile(false) and app.controllers.store.load_all().profiles.is_empty())
	check("stale wizard completion cannot replace another connection's draft", not setup.apply_calibration_draft(complete, 15, stale_generation) and setup.current_profile() == complete)
	var prior_context: String = setup._draft_context_key
	setup._duplicate_profile()
	check("duplicating cannot bypass the calibration connection check", not setup._save_profile(false) and app.controllers.store.load_all().profiles.is_empty())
	setup._set_draft_profile(complete, prior_context)
	setup.profile_name_edit.text = "My limited radio"
	await _open_wizard()
	await _complete_wizard()
	var saved_ok: bool = setup._save_profile(false)
	check("normal Save commits calibrated settings", saved_ok)
	if not saved_ok:
		printerr("Save rejected: ", setup.status_label.text)
		await _finish()
		return
	var saved: Dictionary = app.controllers.store.load_all().profiles[0]
	check("saved identity and calibration match the edited draft", saved.name == "My limited radio" and saved.profile_id == original.profile_id and saved.throttle.min == -0.6 and saved.throttle.max == 0.6)
	app.screens.pop()
	app.open_controls()
	await ui.settle()
	setup = app.screens.top()
	check("reopening Controls reloads saved ranges", setup.current_profile().throttle == saved.throttle)
	var other: Dictionary = Profile.defaults("gamepad")
	setup.load_selected_profile(other)
	check("gamepads cannot enter radio calibration", not setup.calibrate_button.visible)
	devices.append({"id": 18, "name": "Unknown USB joystick", "guid": "unknown-issue5", "known": false})
	app.controllers.refresh()
	for index: int in setup.flight_device_picker.item_count:
		if setup.flight_device_picker.get_item_id(index) == 18:
			setup._on_flight_device_selected(index)
	check("unknown joystick needs an explicit radio profile", setup.current_profile().kind == "joystick" and not setup.calibrate_button.visible)
	setup._on_profile_kind_selected(1)
	check("unknown joystick can calibrate after choosing Radio without Save", setup.current_profile().kind == "radio" and setup.calibrate_button.visible)
	var selected_before_unknown: int = app.controllers.registry.selected_device_id("flight")
	setup.calibration_requested.emit()
	check("unsaved radio selection opens wizard without changing active device", app.screens.is_top("radio_calibration") and app.controllers.registry.selected_device_id("flight") == selected_before_unknown)
	app.screens.top().request_close()
	check("calibration did not start an activity", app.flight == null and selection_before == 15)
	await _finish()


func _open_wizard(inverted: bool = false) -> void:
	selection_at_start = app.controllers.registry.selected_device_id("flight")
	raw.resize(10)
	raw.fill(0.0)
	raw[4] = 0.6 if inverted else -0.6
	raw[6] = 0.05
	setup.calibrate_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Calibrate opens its own screen above Controls", app.screens.is_top("radio_calibration"))
	if not app.screens.is_top("radio_calibration"):
		return
	app.screens.top().read_axis = func(id: int, axis: int) -> float: return raw[axis] if id == 15 else NAN
	await ui.settle()


func _sweep(axis: int, values: Array) -> void:
	for value: float in values:
		raw[axis] = value
		await ui.settle()
	await ui.tap(KEY_ENTER)


func _complete_wizard(inverted: bool = false) -> void:
	await ui.tap(KEY_ENTER)
	await _sweep(4, [-0.6, 0.6] if inverted else [0.6, -0.6])
	await _sweep(6, [0.65, -0.55, 0.05])
	await _sweep(1, [-0.7, 0.7, 0.0])
	await _sweep(0, [0.8, -0.8, 0.0])
	check("finished wizard still requires explicit Use calibration", app.screens.is_top("radio_calibration"))
	await ui.tap(KEY_ENTER)
	check("using calibration does not commit device selection", app.controllers.registry.selected_device_id("flight") == selection_at_start)


func _check_arming(calibrated: Dictionary, inverted: bool) -> void:
	var idle: float = 0.6 if inverted else -0.6
	var high: float = -idle
	var uncalibrated: Dictionary = calibrated.duplicate(true)
	uncalibrated.throttle.min = -1.0
	uncalibrated.throttle.max = 1.0
	uncalibrated.throttle.center = 0.0
	var radio: RefCounted = Radio.new()
	radio.connect_device(15, {"name": "Synthetic radio"}, uncalibrated)
	radio.on_motion(15, 4, idle)
	var reader: Callable = func(_id: int, axis: int) -> float: return idle if axis == 4 else 0.0
	radio.poll(reader, 1.0 / 240.0)
	check("uncalibrated limited travel is 20 percent and cannot arm", is_equal_approx(radio.throttle_position(), 0.2) and not radio.armed)
	radio.use_profile(calibrated, "calibrated")
	radio.poll(reader, 1.0 / 240.0)
	check("calibration cannot reuse old low-throttle evidence", not radio.armed)
	radio.on_motion(15, 4, idle)
	radio.poll(reader, 1.0 / 240.0)
	check("fresh calibrated idle arms at zero throttle", radio.armed and is_equal_approx(radio.throttle_position(), 0.0))
	check("calibrated high endpoint gives full throttle", is_equal_approx(Radio.normalize_throttle(high, calibrated.throttle), 1.0))


func _finish() -> void:
	await ui.close_app(app)
	_cleanup()
	print("Preflight calibration: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _cleanup() -> void:
	for suffix: String in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
