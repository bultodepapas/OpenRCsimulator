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
	var fake_axes := {1: 0.03084}
	session.read_axis = func(_id: int, axis: int) -> float: return float(fake_axes.get(axis, 0.0))
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	await create_timer(0.35).timeout
	check("automatic controller launch is ready at rest but never auto-resumes", session.radio.armed and session.sim.paused and app.pause_menu != null)
	check("controller recovery test starts on the selected runway", session.start_choice == "runway" and session.trace_meta().launch_choice == "runway")
	check("pause reports ready instead of asking for more motion", app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Continue works without any synthetic axis events", app.pause_menu == null and not session.sim.paused)
	for cycle in 3:
		if session.glow_is_active() and not session.glow_state().get("running", false):
			await ui.tap(KEY_F7)
			await create_timer(0.35).timeout
		var idle_rpm := float(session.sim.aux[0])
		check("cycle %d has an available engine before throttle input" % (cycle + 1), session.engine_running)
		var tick_before_throttle: int = session.sim.tick
		fake_axes[1] = -1.0 # Mode 2 throttle is a rate control with inverted stick travel.
		await create_timer(0.45).timeout
		check("cycle %d responds to throttle and advances simulation" % (cycle + 1),
			session.radio.throttle_position() > 0.05 and session.sim.tick > tick_before_throttle)
		check("cycle %d throttle raises actual engine RPM" % (cycle + 1), float(session.sim.aux[0]) > idle_rpm)
		fake_axes[1] = 0.03084 # centered gamepad drift remains inside the configured dead zone.
		await ui.tap(KEY_R)
		check("real R requests a shell restart and leaves the controller ready to Continue",
			app.pause_menu != null and session.sim.paused
			and session.start_choice == "runway"
			and app.pause_menu.note_label.text == tr("Flight restarted. Select Continue when the controls are ready.")
			and is_equal_approx(session._pending_controller_start, 0.0))
		var frozen_state: PackedByteArray = _simulation_snapshot(session)
		var frozen_tick: int = session.sim.tick
		await create_timer(0.15).timeout
		check("cycle %d pause holds the exact simulation state" % (cycle + 1),
			session.sim.paused and session.sim.tick == frozen_tick and _simulation_snapshot(session) == frozen_state)
		await create_timer(0.35).timeout
		check("cycle %d is ready without stick movement" % (cycle + 1),
			session.radio.armed and app.pause_menu.continue_button.is_visible_in_tree()
			and app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
		app.pause_menu.continue_button.grab_focus()
		await ui.tap(KEY_ENTER)
		var tick_after_continue: int = session.sim.tick
		await create_timer(0.1).timeout
		check("cycle %d Continue resumes simulation ticks" % (cycle + 1),
			app.pause_menu == null and not session.sim.paused and session.sim.tick > tick_after_continue)
		check("cycle %d runway Continue starts at zero throttle" % (cycle + 1),
			is_equal_approx(session.radio.throttle_position(), 0.0)
			and is_equal_approx(session.commands.throttle, 0.0)
			and is_equal_approx(session.sim.inputs[3], 0.0))

	# The menu Restart action is independently exercised through keyboard focus and Enter. Raw roll
	# input is deliberately held: its presence must not revoke readiness or hide the recovery menu.
	fake_axes[2] = 0.75
	await ui.tap(KEY_ESCAPE)
	await create_timer(0.15).timeout
	check("normal Pause opens with live roll input and keeps readiness", app.pause_menu != null
		and session.sim.paused and session.radio.armed and session.radio.sticks().roll > 0.5
		and app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
	await ui.tap(KEY_DOWN)
	check("focused menu navigation selects Restart", ui.focus_name() == "Restart")
	await ui.tap(KEY_ENTER)
	check("focused Restart plus Enter preserves Pause while restarting", app.pause_menu != null
		and session.sim.paused and session.start_choice == "runway"
		and is_equal_approx(session._pending_controller_start, 0.0)
		and app.pause_menu.note_label.text == tr("Flight restarted. Select Continue when the controls are ready."))
	check("held roll does not revoke Continue readiness after menu Restart",
		session.radio.armed and app.pause_menu.continue_button.is_visible_in_tree()
		and app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
	fake_axes[2] = 0.0
	await create_timer(0.15).timeout
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("focused menu Restart can Continue and resume simulation", app.pause_menu == null and not session.sim.paused)

	# A rejected selected-runway reset must leave the visible menu and its error note in place.
	app.open_pause()
	await ui.settle()
	var previous_surface_error: String = session.surface_error
	session.surface_error = "synthetic runway reset rejection"
	app.restart_flight()
	check("rejected runway reset keeps Pause open and explains the failure",
		app.pause_menu != null and session.sim.paused
		and app.pause_menu.note_label.text.contains("Could not restart flight")
		and app.pause_menu.note_label.text.contains("synthetic runway reset rejection")
		and not app.pause_menu.note_label.text.contains("Flight restarted"))
	session.surface_error = previous_surface_error
	app.restart_flight()
	check("retry after restoring runway data succeeds and resets pending throttle",
		app.pause_menu != null and session.sim.paused and session.start_error.is_empty()
		and session.start_choice == "runway" and is_equal_approx(session._pending_controller_start, 0.0)
		and app.pause_menu.note_label.text == tr("Flight restarted. Select Continue when the controls are ready."))
	await create_timer(0.35).timeout
	check("runway retry becomes ready to Continue", session.radio.armed
		and app.pause_menu.status_text(session) == tr("Controls ready. Select Continue to fly."))
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Continue after a rejected reset resumes the valid runway flight", app.pause_menu == null and not session.sim.paused)

	# The accident report uses the same shell restart path as keyboard and menu actions.
	var report: Node = app.flight.get("_accident_report") as Node
	if report != null and report.has_signal("restart_requested"):
		report.restart_requested.emit()
		check("accident-report restart enters the controller-ready Pause shell",
			app.pause_menu != null and session.sim.paused and session.start_choice == "runway"
			and is_equal_approx(session._pending_controller_start, 0.0))
		await create_timer(0.35).timeout
		app.pause_menu.continue_button.grab_focus()
		await ui.tap(KEY_ENTER)
		check("accident-report restart can Continue through the shell", app.pause_menu == null and not session.sim.paused)
	else:
		check("flight exposes the accident-report restart signal", false)
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

	# A selected controller that disconnects requires explicit controller recovery before Continue.
	session.controller_disconnected()
	app.open_pause()
	await ui.settle()
	app.restart_flight()
	check("restart after controller loss keeps the recovery menu visible",
		app.pause_menu != null and session.sim.paused and session._controller_lost)
	app.continue_flight()
	check("Continue explains and refuses a lost controller while Pause stays open",
		app.pause_menu != null and session.sim.paused and app.pause_menu.note_label.text.contains("Controller unavailable"))
	check("explicit keyboard selection clears controller loss", app.controllers.select_devices(-1, 15)
		and not session._controller_lost and not session.radio.connected)
	app.continue_flight()
	var keyboard_resume_tick: int = session.sim.tick
	await create_timer(0.1).timeout
	check("keyboard recovery Continues and resumes the restarted flight",
		app.pause_menu == null and not session.sim.paused and session.sim.tick > keyboard_resume_tick)
	await ui.close_app(app)
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	print("Controller pause recovery: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _simulation_snapshot(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.inputs, sim.aux, sim.continuous, sim.modes])
