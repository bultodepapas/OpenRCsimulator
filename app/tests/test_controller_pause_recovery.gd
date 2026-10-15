extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://controller_pause_recovery_test.cfg"
const DT := 1.0 / 240.0
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func ticks(reader: RcInput, count: int, values: Dictionary = {}, held := false) -> void:
	for _i in count:
		reader.poll(func(_id: int, axis: int) -> float: return float(values.get(axis, 0.0)), DT,
			func(_id: int, button: int) -> bool: return held and button == JOY_BUTTON_A, false)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reader := RcInput.new()
	reader.connect_device(15, {"known": true, "name": "Test mapped pad"}, Profile.defaults())
	ticks(reader, 60)
	check("unconfirmed polled zero still cannot arm", not reader.armed)
	reader.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	ticks(reader, 1, {1: 0.03084})
	check("confirmed resting pad is ready on the first poll", reader.armed)
	check("resting pad arms without motion events despite normal stick drift", reader.armed and reader.throttle_position() == 0.0)
	reader.require_neutral(false)
	ticks(reader, 60, {1: -0.5})
	check("held stick does not block Continue or advance paused throttle", reader.armed and reader.throttle_position() == 0.0)
	ticks(reader, 60, {}, true)
	check("held menu button does not block flight readiness", reader.armed)
	ticks(reader, 48)
	check("released controls recover without another motion event", reader.armed)
	reader.require_neutral(true, true)
	reader.confirmed_gamepad_connection = func(_id: int) -> bool: return false
	ticks(reader, 60)
	check("focus/disconnection verifier refusal keeps fresh gate closed", not reader.armed and not reader.has_axis_sample(0))
	reader.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	ticks(reader, 48)
	check("confirmed focus return can recover from resting samples", reader.armed)
	reader.require_neutral(false)
	ticks(reader, 1, {3: NAN})
	ticks(reader, 60)
	check("nonfinite input cannot be cleared by confirmed polling alone", not reader.armed and not reader.input_error.is_empty())
	reader.use_profile(Profile.defaults("gamepad", "trigger_absolute"), "test")
	ticks(reader, 60, {5: 0.7})
	check("absolute trigger is ready with its actual staged value", reader.armed and is_equal_approx(reader.throttle_position(), 0.7))
	ticks(reader, 48)
	check("released absolute trigger arms from confirmed polling", reader.armed)
	var extended := Profile.defaults()
	extended.roll.axis = 9
	reader.use_profile(extended, "test")
	ticks(reader, 60)
	check("nonstandard mapped axis still requires a real event", not reader.armed and not reader.has_axis_sample(9))
	reader.connect_device(15, {"name": "EdgeTX Radio"}, Profile.defaults("radio", "radio_custom"))
	ticks(reader, 60, {2: -1.0})
	check("radio throttle evidence cannot use the mapped-gamepad shortcut", not reader.armed)
	reader.disconnect_device()
	ticks(reader, 60)
	check("disconnected reader cannot arm", not reader.armed)
	reader.connect_device(15, {"known": true, "name": "Test mapped pad"}, Profile.defaults())
	reader.poll(func(_id: int, axis: int) -> float: return 0.5 if axis == 2 else 0.0, DT,
		func(_id: int, _button: int) -> bool: return false, true)
	check("direct active flight accepts a live pad without moving every axis", reader.armed and reader.sticks().roll > 0.0)

	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	var ui := UiDriver.new(self)
	await ui.settle()
	app.controllers.enumerate_devices = func() -> Array:
		return [{"id": 15, "name": "Synthetic Xbox", "known": true, "guid": "pause-test-pad"}]
	app.controllers.refresh()
	app.start_flight()
	var session: Node = app.flight.session
	session.read_axis = func(_id: int, axis: int) -> float: return 0.03084 if axis == 1 else 0.0
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	await create_timer(0.35).timeout
	check("automatic controller launch is ready at rest but never auto-resumes", session.radio.armed and session.sim.paused and app.pause_menu != null)
	check("pause reports ready instead of asking for more motion", app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Continue works without any synthetic axis events", app.pause_menu == null and not session.sim.paused)
	app.open_pause()
	session.read_axis = func(_id: int, axis: int) -> float: return 0.5 if axis == 2 else 0.0
	await create_timer(0.35).timeout
	check("moving a stick in Pause does not revoke Continue", session.radio.armed and session.sim.paused)
	app.pause_menu.restart_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Restart resets and visibly acknowledges the restart", app.pause_menu != null and session.sim.paused and app.pause_menu.note_label.text == tr("Flight restarted. Select Continue when the controls are ready."))
	await create_timer(0.35).timeout
	check("restarted stationary pad rearms without another stick movement", session.radio.armed and session.sim.paused)
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Continue after Restart resumes the new flight", app.pause_menu == null and not session.sim.paused)
	session.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return false
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await ui.settle()
	await create_timer(0.3).timeout
	check("focus loss still requires verified recovery and stays paused", app.pause_menu != null and session.sim.paused and not session.radio.armed)
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	await create_timer(0.3).timeout
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("verified neutral focus recovery can Continue without moving sticks", app.pause_menu == null and not session.sim.paused)
	app.free()
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	print("Controller pause recovery: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
