## AFC-04: terrain recovery must not manufacture or prolong a traffic conflict.
extends SceneTree

const Pilot := preload("res://ai/companions/pilot.gd")
const Field := preload("res://data/field_loader.gd")
const Body := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")

var _field: Dictionary
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)

func _pilot() -> RefCounted:
	var pilot: RefCounted = Pilot.new()
	_check("pilot configures", pilot.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, _field))
	return pilot

func _snapshot(pilot: RefCounted, clearance: float) -> Dictionary:
	var pose: Dictionary = pilot.initial_pose()
	# Raised terrain separates absolute altitude from local clearance. Offset the
	# aircraft from its circuit so losing nominal route correction is observable.
	return {state = Body.make_state(PackedFloat64Array([pose.north + 20.0, pose.east, -35.0]),
		PackedFloat64Array([15.0, 0.0, 0.0]), Math3D.q_from_euler(pose.heading_rad, 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0])), ground_clearance_m = clearance,
		airspeed_m_s = 15.0, wind_ned = PackedFloat64Array([0.0, 0.0, 0.0]),
		trim = {V = 15.0, throttle = 0.45}}

func _traffic(snapshot: Dictionary, distance: float, player: bool) -> Dictionary:
	var state: PackedFloat64Array = snapshot.state.duplicate()
	state[0] += distance
	return {id = "player" if player else "companion-1", is_player = player, state = state}

func _controls(packet: Dictionary) -> Array:
	return [packet.roll, packet.pitch, packet.yaw, packet.throttle, packet.target_height_m]

func _run() -> void:
	var loaded: Dictionary = Field.load_from()
	_check("Club field loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		quit(1)
		return
	_field = loaded.field
	for clearance: float in [35.0, 29.0, 24.0, 10.0]:
		for player: bool in [false, true]:
			var pilot: RefCounted = _pilot()
			var snapshot: Dictionary = _snapshot(pilot, clearance)
			var far: Dictionary = _traffic(snapshot, 1000.0, player)
			var before := var_to_bytes([snapshot, far])
			var nominal: Dictionary = _pilot().command(snapshot, 0)
			var actual: Dictionary = pilot.command(snapshot, 0, [far])
			_check("distant traffic cannot activate avoidance at %.0f m" % clearance,
				actual.ok and not actual.avoidance_active and not pilot.snapshot_state().has_held_maneuver)
			_check("distant traffic preserves route and recovery controls", _controls(actual) == _controls(nominal))
			_check("terrain recovery remains independent", actual.recovering_clearance == (clearance < 30.0)
				and (clearance >= 30.0 or actual.throttle == 1.0))
			_check("observations are unchanged", before == var_to_bytes([snapshot, far]))
	_check_release()
	print("companion terrain traffic: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_release() -> void:
	var pilot: RefCounted = _pilot()
	var snapshot: Dictionary = _snapshot(pilot, 24.0)
	var near: Dictionary = _traffic(snapshot, 10.0, true)
	var far: Dictionary = _traffic(snapshot, 1000.0, true)
	var conflict: Dictionary = pilot.command(snapshot, 0, [near])
	_check("real conflict still acquires maneuver during terrain recovery", conflict.ok
		and conflict.avoidance_active and pilot.snapshot_state().has_held_maneuver)
	_check("real conflict retains recovery power and climb", conflict.recovering_clearance
		and conflict.throttle == 1.0 and conflict.pitch > 0.0 and conflict.target_height_m >= 45.0)
	_check("traffic bank remains bounded", absf(pilot.snapshot_state().held_bank_rad) <= deg_to_rad(25.0))
	# Clear starts late; minimum hold alone cannot release the traffic response.
	var clearing: Dictionary = pilot.command(snapshot, 400, [far])
	_check("clear traffic starts dwell without dropping held turn", clearing.avoidance_active)
	var before: Dictionary = pilot.command(snapshot, 636, [far])
	_check("terrain-independent release preserves full clear dwell", before.avoidance_active)
	var released: Dictionary = pilot.command(snapshot, 640, [far])
	var nominal: Dictionary = _pilot().command(snapshot, 640)
	_check("clear traffic releases despite unmet terrain reserve", not released.avoidance_active
		and not pilot.snapshot_state().has_held_maneuver)
	_check("release preserves ongoing terrain recovery", released.recovering_clearance
		and _controls(released) == _controls(nominal))
	# A returning conflict must restart clear dwell, even below the terrain reserve.
	pilot.command(snapshot, 644, [near])
	pilot.command(snapshot, 1044, [far])
	pilot.command(snapshot, 1048, [near])
	pilot.command(snapshot, 1052, [far])
	_check("returning threat restarts clear dwell", pilot.command(snapshot, 1288, [far]).avoidance_active)
	_check("restarted clear dwell eventually releases", not pilot.command(snapshot, 1292, [far]).avoidance_active)
