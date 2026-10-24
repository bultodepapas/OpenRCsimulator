## AFC-03/AFC-04: stopped traffic and maneuver continuity through missing observations.
extends SceneTree

const Pilot := preload("res://ai/companions/pilot.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Flight := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const Body := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _checks: int = 0
var _failures: int = 0
var _field: Dictionary
var _snapshot: Dictionary
var _head_on: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)

func _pilot() -> RefCounted:
	var pilot: RefCounted = Pilot.new()
	_check("pilot configures", pilot.configure(0, 2, 20261020, {V = 15.0, throttle = 0.45}, _field))
	return pilot

func _run() -> void:
	var loaded: Dictionary = Field.load_from()
	_check("Club field loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		quit(1)
		return
	_field = loaded.field
	var pilot: RefCounted = _pilot()
	var pose: Dictionary = pilot.initial_pose()
	var heading: float = pose.heading_rad
	var attitude: PackedFloat64Array = Math3D.q_from_euler(heading, 0.0, 0.0)
	var own: PackedFloat64Array = Body.make_state(
		PackedFloat64Array([pose.north, pose.east, -pose.height_m]),
		PackedFloat64Array([15.0, 0.0, 0.0]), attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
	var forward: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([1.0, 0.0, 0.0]))
	var obstacle_position: PackedFloat64Array = own.slice(0, 3)
	obstacle_position[0] += 45.0 * forward[0]
	obstacle_position[1] += 45.0 * forward[1]
	_snapshot = {state = own, airspeed_m_s = 15.0, ground_clearance_m = pose.height_agl_m,
		wind_ned = PackedFloat64Array([0.0, 0.0, 0.0]), trim = {V = 15.0, throttle = 0.45}}
	_head_on = {id = "player", is_player = true, state = Body.make_state(obstacle_position,
		PackedFloat64Array([15.0, 0.0, 0.0]), Math3D.q_from_euler(heading + PI, 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0]))}
	_check_stopped_observation(obstacle_position, heading)
	_check_hold_continuity()
	_check_low_speed_fallback()
	print("companion traffic lifecycle: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_stopped_observation(obstacle_position: PackedFloat64Array, heading: float) -> void:
	var agent: Node = Agent.new()
	agent.slot_id = 1
	agent.session = Flight.new()
	agent.session.input_enabled = false
	agent.session.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	agent.add_child(agent.session)
	# Nonzero last bank/rates and a windy observer must not move a frozen visual.
	agent.session.sim.state = Body.make_state(obstacle_position, PackedFloat64Array([15.0, 0.0, 0.0]),
		Math3D.q_from_euler(heading, 0.0, deg_to_rad(20.0)), PackedFloat64Array([0.2, 0.1, 0.3]))
	var original: PackedByteArray = agent.session.sim.state.to_byte_array()
	var active: Dictionary = agent.observation()
	_check("active observation retains exact physical state", active.state.to_byte_array() == original)
	for reason: String in ["fault", "crash"]:
		agent.failure = "injected fault" if reason == "fault" else ""
		agent.session.crash = {reason = "injected crash"} if reason == "crash" else {}
		var observation: Dictionary = agent.observation()
		var pilot: RefCounted = _pilot()
		pilot._planning_wind = PackedFloat64Array([1.2, -0.5, 0.1])
		var threats: Array[Dictionary] = pilot._prepare_threats([observation], PackedFloat64Array([15.0, 0.0, 0.0]))
		_check(reason + " remains a visible traffic obstacle", threats.size() == 1)
		var stationary: bool = threats.size() == 1
		if stationary:
			var positions: PackedFloat64Array = threats[0].positions
			for index in range(0, positions.size(), 3):
				for axis in 3:
					stationary = stationary and positions[index + axis] == obstacle_position[axis]
		_check(reason + " forecast stays at rendered position for entire horizon", stationary)
		var packet: Dictionary = pilot.command(_snapshot, 0, [observation])
		_check(reason + " ahead activates avoidance", packet.ok and packet.avoidance_active)
		_check(reason + " observation preserves simulation state", agent.session.sim.state.to_byte_array() == original)
		_check(reason + " does not resume the stopped session", not agent.prepare(observation, 0, [observation]))
	agent.free()

func _check_hold_continuity() -> void:
	for missing: Array in [[], [{}], [{id = "companion-0", slot = 0, state = _snapshot.state}]]:
		var pilot: RefCounted = _pilot()
		var initial: Dictionary = pilot.command(_snapshot, 0, [_head_on])
		_check("conflict acquires maneuver", initial.ok and initial.avoidance_active and pilot.snapshot_state().has_held_maneuver)
		var gap: Dictionary = pilot.command(_snapshot, 4, missing)
		_check("brief unusable traffic preserves held control", gap.avoidance_active and gap.roll == initial.roll)
		var returned: Dictionary = pilot.command(_snapshot, 8, [_head_on])
		_check("returning threat does not switch bank", returned.roll == initial.roll)
		# Start a late clear interval: minimum hold alone must not release at tick 480.
		pilot.command(_snapshot, 400, missing)
		var before_release: Dictionary = pilot.command(_snapshot, 636, missing)
		_check("held turn survives until full clear dwell", before_release.avoidance_active and before_release.roll == initial.roll)
		var released: Dictionary = pilot.command(_snapshot, 640, missing)
		var nominal: Dictionary = _pilot().command(_snapshot, 640)
		_check("clear dwell releases to nominal controls", not released.avoidance_active and not pilot.snapshot_state().has_held_maneuver
			and released.roll == nominal.roll and released.pitch == nominal.pitch)

func _check_low_speed_fallback() -> void:
	var pilot: RefCounted = _pilot()
	pilot.command(_snapshot, 0, [_head_on])
	var slow: Dictionary = _snapshot.duplicate(true)
	slow.state[Body.VEL] = 2.0
	slow.airspeed_m_s = 2.0
	var packet: Dictionary = pilot.command(slow, 4)
	var nominal: Dictionary = _pilot().command(slow, 4)
	_check("missing traffic retains low-speed fallback", packet.ok and not packet.avoidance_active and packet.roll == nominal.roll)
	_check("low-speed fallback does not falsely release latch", pilot.snapshot_state().has_held_maneuver)
