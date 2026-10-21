## AFC-04-R2: avoidance must not ask the circuit pilot to descend into its recovery band.
extends SceneTree

const Field := preload("res://data/field_loader.gd")
const Body := preload("res://physics/rigid_body.gd")
const Math := preload("res://physics/math3d.gd")
var _pilot_script: Script = preload("res://ai/companions/pilot.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pilot="):
			_pilot_script = load(argument.trim_prefix("--pilot="))
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var field: Dictionary = Field.load_from()
	_check("Club fixture loads", field.get("ok", false))
	if not field.get("ok", false) or _pilot_script == null:
		quit(1)
		return
	for slot in 3:
		var pilot: RefCounted = _pilot_script.new()
		_check("height-band pilot configures", pilot.configure(slot, 3, 20261020,
			{V = 15.0, throttle = 0.3}, field.field))
		var pose: Dictionary = pilot.initial_pose()
		var height: float = float(pose.height_m)
		var snapshot := _snapshot(pose, height, height)
		var clear: Dictionary = pilot.command(snapshot, 0, [])
		var threat: Dictionary = _traffic(snapshot, 0.0)
		var response: Dictionary = pilot.command(snapshot, 0, [threat])
		_check("avoidance target stays at least 35 m above local terrain",
			response.ok and response.target_height_m >= height - float(snapshot.ground_clearance_m) + 35.0)
		_check("reachable horizontal avoidance retains the nominal circuit altitude",
			response.target_height_m == clear.target_height_m)
		_check("lateral avoidance remains active when vertical descent is constrained",
			response.avoidance_active and response.roll != clear.roll)
		var before := var_to_bytes([snapshot, threat])
		pilot.command(snapshot, 0, [threat])
		_check("clearance policy does not mutate observations", before == var_to_bytes([snapshot, threat]))
		if slot != 0:
			continue
		# Raised terrain is deliberately synthetic; altitude and AGL are different quantities.
		var raised := _snapshot(pose, 135.0, 35.0)
		var raised_response: Dictionary = pilot.command(raised, 0, [_traffic(raised, 0.0)])
		_check("avoidance floor uses observed local terrain, not field datum",
			raised_response.ok and raised_response.target_height_m >= 135.0)
		for clearance: float in [30.01, 29.99]:
			var boundary := _snapshot(pose, clearance, clearance)
			var recovery: Dictionary = pilot.command(boundary, 0, [_traffic(boundary, 0.0)])
			_check("neither side of recovery threshold requests further descent",
				recovery.ok and recovery.target_height_m > clearance and recovery.pitch > 0.0)
		var overhead: Dictionary = pilot.command(snapshot, 0, [_traffic(snapshot, -6.0)])
		_check("overhead traffic retains nominal altitude when descent would cross the floor",
			overhead.ok and overhead.target_height_m == height and not overhead.recovering_clearance)
	print("companion clearance: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _snapshot(pose: Dictionary, height: float, clearance: float) -> Dictionary:
	return {state = Body.make_state(PackedFloat64Array([pose.north, pose.east, -height]),
		PackedFloat64Array([15.0, 0.0, 0.0]), Math.q_from_euler(float(pose.heading_rad), 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0])), ground_clearance_m = clearance,
		airspeed_m_s = 15.0, trim = {V = 15.0, throttle = 0.3}, wind_ned = PackedFloat64Array([0.0, 0.0, 0.0])}


func _traffic(snapshot: Dictionary, down_delta: float) -> Dictionary:
	var state: PackedFloat64Array = snapshot.state.duplicate()
	# Twenty metres to the right of each seeded aircraft, with matched velocity.
	var heading: float = Math.q_to_euler(state.slice(6, 10))[0]
	state[0] -= 20.0 * sin(heading)
	state[1] += 20.0 * cos(heading)
	state[2] += down_delta
	return {id = "player", is_player = true, state = state}
