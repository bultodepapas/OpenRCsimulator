extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const Session := preload("res://sim/flight_session.gd")
const DT := 1.0 / 240.0
const DEVICE_ID := 15
const INFO := {"name": "Synthetic mapped gamepad", "known": true}

var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_held_reader_recovery()
	_test_flight_session_loss()
	_test_unverified_event_reader()
	print("Controller verifier loss: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_held_reader_recovery() -> void:
	var state := {"confirmed": true}
	var reader := RcInput.new()
	reader.connect_device(DEVICE_ID, INFO, Profile.defaults())
	reader.confirmed_gamepad_connection = func(id: int) -> bool: return id == DEVICE_ID and state.confirmed
	var axes := func(_id: int, _axis: int) -> float: return 0.0
	var buttons := func(_id: int, _button: int) -> bool: return false
	reader.poll(axes, DT, buttons, false)
	check("verified sample arms the held gamepad", reader.armed and reader.set_rate_throttle_for_start(0.4))
	state.confirmed = false
	reader.poll(axes, DT, buttons, false)
	check("a refusal while held revokes readiness and retains staged throttle", not reader.armed and reader.input_error.is_empty() and is_equal_approx(reader.throttle_position(), 0.4))
	for axis in [0, 1, 2, 3]:
		reader.on_motion(DEVICE_ID, axis, 0.0)
	for _i in 60:
		reader.poll(axes, DT, buttons, false)
	check("neutral events cannot replace lost verification during a hold", not reader.armed and is_equal_approx(reader.throttle_position(), 0.4))
	state.confirmed = true
	reader.poll(axes, DT, buttons, false)
	check("restored proof can rearm without moving the held throttle", reader.armed and is_equal_approx(reader.throttle_position(), 0.4))


func _test_flight_session_loss() -> void:
	var state := {"confirmed": true, "trigger": 0.0}
	var session := Session.new()
	session.external_controller_selection = true
	session.physics_enabled = false
	session.read_axis = func(_id: int, axis: int) -> float: return float(state.trigger) if axis == JOY_AXIS_TRIGGER_RIGHT else 0.0
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.setup()
	check("verified trigger fixture selects", session.apply_controller_selection(DEVICE_ID, INFO, Profile.defaults("gamepad", "trigger_absolute")))
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == DEVICE_ID and state.confirmed
	session._physics_process(DT)
	check("verified sample arms the paused session", session.radio.armed)
	session.resume()
	state.trigger = 0.75
	session._physics_process(DT)
	check("verified trigger reaches the flight command", not session.sim.paused and is_equal_approx(session.commands.throttle, 0.75))
	state.confirmed = false
	session._physics_process(DT)
	check("lost proof during flight holds the session and clears thrust", session.sim.paused and session._controller_lost and not session.radio.connected and session.commands.throttle == 0.0)
	state.trigger = 0.0
	session._physics_process(DT)
	session.resume()
	check("releasing the trigger while proof is refused cannot resume", session.sim.paused and session._controller_lost and session.commands.throttle == 0.0)
	state.confirmed = true
	session._physics_process(DT)
	check("restored proof alone cannot reconnect or resume the session", session.sim.paused and session._controller_lost and not session.radio.connected)
	check("an explicit selection can restore the same controller", session.apply_controller_selection(DEVICE_ID, INFO, Profile.defaults("gamepad", "trigger_absolute")))
	session._physics_process(DT)
	session.resume()
	check("explicit resume after reselection starts at the released trigger", not session.sim.paused and not session._controller_lost and session.commands.throttle == 0.0)
	session.free()


func _test_unverified_event_reader() -> void:
	var reader := RcInput.new()
	reader.connect_device(DEVICE_ID, {"name": "User-configured stick", "known": false}, Profile.defaults())
	# Service binds the verifier to every device, including a configured raw stick
	# that is intentionally ineligible for the live standard-gamepad shortcut.
	reader.confirmed_gamepad_connection = func(_id: int) -> bool: return false
	for axis in [0, 1, 2, 3]:
		reader.on_motion(DEVICE_ID, axis, 0.0)
	for _i in 60:
		reader.poll(func(_id: int, _axis: int) -> float: return 0.0, DT, func(_id: int, _button: int) -> bool: return false)
	check("a configured raw device can arm on events despite a bound verifier refusal", reader.armed)

	var extended := Profile.defaults()
	extended.roll.axis = 9
	reader.connect_device(DEVICE_ID, INFO, extended)
	reader.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	for _i in 60:
		reader.poll(func(_id: int, _axis: int) -> float: return 0.0, DT, func(_id: int, _button: int) -> bool: return false)
	check("a nonstandard axis still requires real events", not reader.armed)
	for axis in [0, 1, 3, 9]:
		reader.on_motion(DEVICE_ID, axis, 0.0)
	for _i in 60:
		reader.poll(func(_id: int, _axis: int) -> float: return 0.0, DT, func(_id: int, _button: int) -> bool: return false)
	check("a nonstandard mapping can arm on fresh events", reader.armed)
