extends SceneTree
const Session = preload("res://sim/helicopter_flight_session.gd")
const Wind = preload("res://physics/wind_config.gd")
const Recorder = preload("res://sim/rotorcraft_recorder.gd")
const ControllerProfile = preload("res://input/controller_profile.gd")
const Math3D = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label, (" — " + detail) if not detail.is_empty() else "")
func make_session(external: bool = false) -> Node:
	var session = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.external_controller_selection = external
	root.add_child(session)
	check("session setup", session.setup())
	check("session hover reset", session.reset())
	return session
func run_steps(session: Node, count: int) -> bool:
	for tick: int in count:
		session.sim.step()
		if not session.is_flyable():
			return false
	return true
func _run() -> void:
	var session: Node = make_session()
	var initial_checkpoint: Dictionary = session.checkpoint()
	var initial_bytes: PackedByteArray = var_to_bytes(initial_checkpoint)
	var initial_surfaces: PackedFloat64Array = session.ground_surfaces.duplicate()
	var initial_start: PackedFloat64Array = session._start.duplicate()
	check("checkpoint v3 records field, start and power identity", initial_checkpoint.get("format", "") == "openrc-helicopter-checkpoint v3" and initial_checkpoint.ground_surfaces.to_byte_array() == initial_surfaces.to_byte_array() and initial_checkpoint.start_position.to_byte_array() == initial_start.to_byte_array() and initial_checkpoint.has("power") and initial_checkpoint.has("shaft_phase"))

	var failed_setup_weather: Dictionary = session.weather_configuration()
	session.aircraft_path = "res://data/aircraft/__heli_state_audit_missing__.json"
	check("missing model load is refused", not session.setup_weather(Wind.preset("steady")))
	check("failed weather setup is atomic", session.weather_configuration() == failed_setup_weather and var_to_bytes(session.checkpoint()) == initial_bytes)
	session.aircraft_path = "res://data/aircraft/xcell_60_research.json"

	check("incomplete field is rejected without partial surface commit", not session.set_field({}) and session.ground_surfaces.to_byte_array() == initial_surfaces.to_byte_array() and session._start.to_byte_array() == initial_start.to_byte_array())
	var field: Dictionary = {"pilot": {"north": 0.0, "east": 0.0}, "surfaces": []}
	check("valid field commits", session.set_field(field))
	check("field change invalidates the old hover until reset", not session.is_flyable() and session.sim.paused and session.checkpoint().is_empty())
	check("reset builds a field-bound hover", session.reset())

	var saved: Dictionary = session.checkpoint()
	var unchanged: PackedByteArray = var_to_bytes(saved)
	var bad: Dictionary = saved.duplicate(true)
	bad.ground_surfaces[4] = 0.8 # friction-only foreign field; hover trim is unchanged
	check("foreign field with the same trim is rejected atomically", bad.trim == saved.trim and not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.start_position[0] += 1.0
	check("foreign authored start position is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.format = "openrc-helicopter-checkpoint v1"
	bad.erase("ground_surfaces")
	bad.erase("start_position")
	var old_result: Dictionary = session.restore_checkpoint(bad)
	check("v1 checkpoint refusal explains missing field identity", not old_result.ok and str(old_result.errors).contains("v1") and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.simulation.dt *= 2.0
	check("checkpoint timestep mismatch is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.simulation.aux[0] += 1.0
	check("checkpoint rotor RPM projection mismatch is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.simulation.continuous[0] = -1.0
	bad.simulation.aux[0] = -60.0 / (2.0 * PI)
	check("negative main-rotor speed is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.simulation.continuous = PackedFloat64Array([167.0])
	check("wrong continuous-state length is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.commands.throttle = 1.1
	check("out-of-range collective is rejected atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)
	bad = saved.duplicate(true)
	bad.weather.speed_mps = 2.0
	check("checkpoint weather identity is enforced atomically", not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint()) == unchanged)

	var accepted_mass: float = session.sim.mass
	bad = saved.duplicate(true)
	session.sim.mass = accepted_mass + 1.0
	bad.simulation.mass = session.sim.mass
	var mismatched_simulation: PackedByteArray = var_to_bytes(session.sim.checkpoint())
	check("session checkpoint refuses mass that disagrees with aircraft", session.checkpoint().is_empty())
	check("restore rejects a self-consistent but foreign simulation mass", not session.restore_checkpoint(bad).ok and var_to_bytes(session.sim.checkpoint()) == mismatched_simulation)
	session.sim.mass = accepted_mass
	var accepted_gravity: float = session.sim.gravity
	bad = saved.duplicate(true)
	session.sim.gravity = accepted_gravity + 0.5
	bad.simulation.gravity = session.sim.gravity
	mismatched_simulation = var_to_bytes(session.sim.checkpoint())
	check("restore rejects a self-consistent but foreign simulation gravity", not session.restore_checkpoint(bad).ok and var_to_bytes(session.sim.checkpoint()) == mismatched_simulation)
	session.sim.gravity = accepted_gravity
	var accepted_inertia: PackedFloat64Array = session.sim.inertia.duplicate()
	var foreign_inertia: PackedFloat64Array = accepted_inertia.duplicate()
	foreign_inertia[0] *= 1.01
	bad = saved.duplicate(true)
	session.sim.inertia = foreign_inertia
	bad.simulation.inertia = foreign_inertia.duplicate()
	mismatched_simulation = var_to_bytes(session.sim.checkpoint())
	check("restore rejects a self-consistent but foreign inertia", not session.restore_checkpoint(bad).ok and var_to_bytes(session.sim.checkpoint()) == mismatched_simulation)
	session.sim.inertia = accepted_inertia

	session.hold("modal")
	var held_restore: Dictionary = session.restore_checkpoint(saved)
	check("checkpoint restore retains modal hold and remains paused", held_restore.ok and session.sim.paused and session.holds.has("modal") and not session.can_resume())
	session.release("modal")
	check("release does not auto-resume restored simulation", session.sim.paused)
	check("short control tail advances", run_steps(session, 8))
	var endpoint: PackedFloat64Array = session.sim.state.duplicate()
	var continuous_endpoint: PackedFloat64Array = session.sim.continuous.duplicate()
	var reset_signal_tick: Array = [-1]
	session.resetting.connect(func() -> void: reset_signal_tick[0] = session.sim.tick, CONNECT_ONE_SHOT)
	check("v3 checkpoint restores", session.restore_checkpoint(saved).ok)
	check("reset observers see the committed restored tick", reset_signal_tick[0] == saved.simulation.tick)
	check("replayed control tail advances", run_steps(session, 8))
	check("body and rotor state replay byte-identically", endpoint.to_byte_array() == session.sim.state.to_byte_array() and continuous_endpoint.to_byte_array() == session.sim.continuous.to_byte_array())

	var live_surfaces: PackedFloat64Array = session.ground_surfaces.duplicate()
	var live_start: PackedFloat64Array = session._start.duplicate()
	var moved_field: Dictionary = {"pilot": {"north": 1.0, "east": 0.0}, "surfaces": []}
	check("live field change is refused after tick advancement", not session.set_field(moved_field) and session.ground_surfaces.to_byte_array() == live_surfaces.to_byte_array() and session._start.to_byte_array() == live_start.to_byte_array())
	var live_weather: Dictionary = session.weather_configuration()
	check("live weather change is refused after tick advancement", not session.setup_weather(Wind.preset("steady")) and session.weather_configuration() == live_weather)
	session.set_start_altitude(4.0)
	check("live start altitude edit is refused", session._start[2] == live_start[2])
	session.reset()
	check("tick-zero weather change requires re-trim", session.setup_weather(Wind.preset("steady")) and session.sim.paused and not session.is_flyable() and session.reset())
	session.set_start_altitude(4.0)
	check("tick-zero start altitude edit invalidates hover", not session.is_flyable() and session.sim.paused and session.reset() and session.checkpoint().start_position[2] == -4.0)
	var valid_rotor_state: PackedFloat64Array = session.sim.continuous.duplicate()
	var valid_rotor_aux: PackedFloat64Array = session.sim.aux.duplicate()
	session.sim.continuous[0] = -1.0
	session.sim.aux[0] = -60.0 / (2.0 * PI)
	check("checkpoint producer refuses finite but invalid rotor state", session.checkpoint().is_empty())
	session.sim.continuous = valid_rotor_state
	session.sim.aux = valid_rotor_aux
	var valid_commands: Dictionary = session.commands.duplicate(true)
	session.commands.throttle = 1.1
	check("checkpoint producer refuses out-of-range saved commands", session.checkpoint().is_empty())
	session.commands = valid_commands
	session.sim.state[2] = -0.15
	var tilted: PackedFloat64Array = Math3D.q_from_euler(0.0, 0.0, 0.6)
	for index: int in 4: session.sim.state[6 + index] = tilted[index]
	session.sim.step()
	check("ground-strike checkpoint cannot erase the crash hold", not session.crash.is_empty() and session.sim.paused and session.checkpoint().is_empty())
	check("reset restores checkpointable hover after crash", session.reset() and session.crash.is_empty() and not session.checkpoint().is_empty())

	var recorder: RefCounted = Recorder.new(session.sim)
	recorder.start(session.trace_meta())
	recorder._record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads, session.sim.inputs, session.sim.aux)
	var rejected_path: String = "user://heli-state-audit-rejected.csv"
	if FileAccess.file_exists(rejected_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(rejected_path))
	check("recorder latches a duplicate tick failure", not recorder.recording and recorder.trace.row_count() == 1 and str(recorder.note).contains("malformed telemetry"))
	check("stop cannot report or write a partial failed trace", recorder.stop(rejected_path) == ERR_INVALID_DATA and not FileAccess.file_exists(rejected_path) and str(recorder.note).contains("rejected"))
	recorder.detach()
	var good_recorder: RefCounted = Recorder.new(session.sim)
	good_recorder.start(session.trace_meta())
	check("valid recorder sample is retained", good_recorder.trace.row_count() == 1)
	check("valid fixed ticks continue to record", run_steps(session, 2) and good_recorder.trace.row_count() == 3)
	var good_path: String = "user://heli-state-audit-valid.csv"
	check("valid trace still saves", good_recorder.stop(good_path) == OK and FileAccess.file_exists(good_path))
	if FileAccess.file_exists(good_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(good_path))
	good_recorder.detach()

	var controller: Node = make_session(true)
	var invalid_profile: Dictionary = {"throttle_mode": "stick_rate"}
	check("malformed controller profile is rejected before connect", not controller.apply_controller_selection(991, {"name": "audit joystick", "known": false}, invalid_profile) and controller._controller_lost and not controller.radio.connected and controller.sim.paused)
	var valid_profile: Dictionary = ControllerProfile.defaults("gamepad", "mode2")
	check("validated stick-rate profile connects", controller.apply_controller_selection(992, {"name": "audit gamepad", "known": true}, valid_profile) and controller.radio.profile_error.is_empty() and not controller._controller_lost)

	print("HELI state audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
