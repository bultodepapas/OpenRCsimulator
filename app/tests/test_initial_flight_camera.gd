## First-current-camera and staged completion are valid before the first Main process frame.
extends SceneTree

const PilotCamera := preload("res://render/pilot_camera.gd")
const Frames := preload("res://render/frames.gd")
const FlightSession := preload("res://sim/flight_session.gd")

class TrackedFlight extends "res://main.gd":
	var render_calls := 0
	var process_calls := 0
	var prime_tick := -1
	var prime_state_unchanged := false
	func _user_args() -> Dictionary:
		return {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	func _process(delta: float) -> void:
		process_calls += 1
		super._process(delta)
	func _render_pose(pose: Dictionary, controls: Dictionary, prop_angle: float) -> void:
		render_calls += 1
		prime_tick = session.sim.tick
		var before: PackedByteArray = var_to_bytes(session.checkpoint())
		super._render_pose(pose, controls, prop_angle)
		prime_state_unchanged = before == var_to_bytes(session.checkpoint())

var _checks := 0
var _failures := 0
var _flight: TrackedFlight
var _input_reads := 0
var _instrument_eye := Vector3.INF

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("ok ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)

func _eye(pilot: Dictionary) -> Vector3:
	return Frames.ned_to_render([pilot.north, pilot.east, float(pilot.down) - float(pilot.eye_height)])

func _raw() -> Dictionary:
	_input_reads += 1
	return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}

func _checkpoint(stage: String) -> bool:
	if stage == "Preparing instruments":
		_instrument_eye = _flight._camera.position
	if stage == "Preparing effects":
		_flight.session.read_raw = _raw
	await process_frame
	return true

func _camera_before_process() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var observed := {}
	parent.child_entered_tree.connect(func(node: Node) -> void:
		if node is Camera3D:
			observed.position = node.position)
	var pilot := {north = 13.0, east = -8.0, down = 2.0, eye_height = 1.9}
	var camera := PilotCamera.create(parent, pilot)
	_check("camera enters the tree already at the configured pilot eye", observed.get("position", Vector3.INF).is_equal_approx(_eye(pilot)))
	_check("camera becomes current at the pilot eye before any process frame", camera.current and camera.position.is_equal_approx(_eye(pilot)))
	parent.free()

func _staged_start(choice: String) -> void:
	_flight = TrackedFlight.new()
	_flight.interactive_start = true
	_flight.external_controller_selection = true
	_flight.accident_reports_enabled = false
	_flight.startup_checkpoint = _checkpoint
	_flight.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE
	_flight.start_choice = choice
	_input_reads = 0
	_instrument_eye = Vector3.INF
	var finished := {}
	_flight.startup_finished.connect(func() -> void:
		finished.merge({tick = _flight.session.sim.tick, pose = _flight._last_render_pose.duplicate(),
			camera_position = _flight._camera.position, renders = _flight.render_calls}))
	root.add_child(_flight)
	for _frame in 2400:
		if _flight.startup_complete:
			break
		await process_frame
	var session: Node = _flight.session
	var valid: bool = session != null and session.is_flyable() and _flight.startup_error.is_empty()
	_check(choice + ": staged startup completes with a valid held session", valid and _flight.startup_complete and session.holds.has("loading"))
	if valid:
		var eye := _eye(_flight.field.pilot)
		var expected: Dictionary = _flight._pose_of(session.sim.state)
		var actual: Dictionary = _flight._last_render_pose
		_check(choice + ": instruments checkpoint already has the pilot eye", _instrument_eye.is_equal_approx(eye))
		_check(choice + ": completion signal observes the first validated tick-zero pose", finished.get("tick", -1) == 0
			and finished.get("renders", 0) == 1 and not finished.get("pose", {}).is_empty()
			and actual.get("pos", Vector3.INF).is_equal_approx(expected.pos)
			and actual.get("basis", Basis.IDENTITY).is_equal_approx(expected.basis))
		_check(choice + ": priming neither processes nor polls input nor changes session state", _flight.process_calls == 0
			and _input_reads == 0 and _flight.prime_tick == 0 and session.sim.tick == 0 and session.sim.time() == 0.0
			and _flight._camera_dt == 0.0 and _flight.prime_state_unchanged)
		var forward: Vector3 = -_flight._camera.global_basis.z
		var target: Vector3 = (expected.pos - _flight._camera.global_position).normalized()
		_check(choice + ": first camera is at the pilot eye looking at the aircraft", _flight._camera.position.is_equal_approx(eye)
			and forward.dot(target) > 0.9999)
	_flight.free()
	_flight = null
	await process_frame

func _run() -> void:
	_camera_before_process()
	await _staged_start(FlightSession.START_RUNWAY)
	await _staged_start(FlightSession.START_AIRBORNE)
	var direct := TrackedFlight.new()
	root.add_child(direct)
	_check("direct technical startup retains deferred render priming", direct.startup_complete and direct.render_calls == 0 and direct._last_render_pose.is_empty())
	direct.free()
	await process_frame
	print("Initial flight camera: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
