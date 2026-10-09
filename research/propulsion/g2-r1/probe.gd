# G2-R1: reproduce steady shaft-RPM false success and snapshot supported aircraft.
# Run from the repository root:
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script "$PWD/research/propulsion/g2-r1/probe.gd"
# The two synthetic cases mutate an in-memory copy of the P-51 JSON. They should still pass aircraft-data
# validation; before the G2-R1 repair, steady_rpm returns a boundary or nonfinite result without a root check.
# Fleet hashes cover the steady-RPM grid, the production level/glide trims, and 240 hands-off ticks at each
# aircraft's declared start speed. Packed float64 bytes are hashed in the order written below.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

const P51 := "res://data/aircraft/p51d_mustang_120.json"
const FLEET := [
	["jensen-das-ugly-stik-60", "res://data/aircraft/jensen_ugly_stik_60.json"],
	["gp-extra-300s-60", "res://data/aircraft/gp_extra_300s_60.json"],
	["p51d-mustang-120", P51],
	["sebart-avanti-s-a200-p100rx", "res://data/aircraft/sebart_avanti_s_a200.json"],
]
const THROTTLES := [0.0, 0.25, 0.5, 0.75, 1.0]
const AXIAL_SPEEDS := [0.0, 15.0, 30.0]
const RHO := 1.225
const G := 9.80665
const TICK_COUNT := 240

var _failed := false


func _initialize() -> void:
	_print_root_failure_cases()
	_print_fleet_snapshots()
	quit(1 if _failed else 0)


func _print_root_failure_cases() -> void:
	print("G2-R1 accepted-data boundary probes")
	var source := FileAccess.open(P51, FileAccess.READ)
	if source == null:
		push_error("cannot read P-51 source data")
		_failed = true
		return
	var raw_text := source.get_as_text()
	var root_raw: Dictionary = JSON.parse_string(raw_text)
	root_raw.propulsion.engine.shaft.power_curve.value = [[1000.0, 1000.0], [2000.0, 2000.0]]
	root_raw.propulsion.engine.shaft.friction_torque.value = [0.0, 0.0]
	root_raw.propulsion.propeller.cp_table.value = [[0.0, 0.0001], [0.5, 0.0001]]
	var root_load: Dictionary = AircraftData.validate_and_derive(root_raw)
	if not root_load.ok:
		push_error("no-root counterexample stopped passing aircraft-data validation: %s" % str(root_load.errors))
		_failed = true
		return
	var root_prop: Dictionary = root_load.model.propulsion
	var low_net := _net_torque(1.0, 0.0, root_prop, RHO)
	var high_rpm := float(root_prop.shaft.power_curve[root_prop.shaft.power_curve.size() - 2]) * Propulsion.SHAFT_RPM_CEILING
	var high_net := _net_torque(high_rpm, 0.0, root_prop, RHO)
	var returned_rpm := Propulsion.steady_rpm(1.0, 0.0, root_prop, RHO)
	var returned_net := _net_torque(returned_rpm, 0.0, root_prop, RHO)
	print("no_root accepted=true lo=1.0 lo_net=", low_net, " hi=", high_rpm, " hi_net=", high_net, " returned_rpm=", returned_rpm, " returned_net=", returned_net)

	var overflow_raw: Dictionary = JSON.parse_string(raw_text)
	overflow_raw.propulsion.engine.shaft.power_curve.value = [[1000.0, 1000.0], [1.2e308, 2000.0]]
	var overflow_load: Dictionary = AircraftData.validate_and_derive(overflow_raw)
	if not overflow_load.ok:
		push_error("finite-overflow counterexample stopped passing aircraft-data validation: %s" % str(overflow_load.errors))
		_failed = true
		return
	var overflow_prop: Dictionary = overflow_load.model.propulsion
	var overflow_hi := float(overflow_prop.shaft.power_curve[overflow_prop.shaft.power_curve.size() - 2]) * Propulsion.SHAFT_RPM_CEILING
	var overflow_rpm := Propulsion.steady_rpm(1.0, 0.0, overflow_prop, RHO)
	var overflow_net := _net_torque(overflow_rpm, 0.0, overflow_prop, RHO)
	print("overflow accepted=true hi_finite=", is_finite(overflow_hi), " rpm_finite=", is_finite(overflow_rpm), " hi=", overflow_hi, " returned_rpm=", overflow_rpm, " returned_net=", overflow_net)


func _print_fleet_snapshots() -> void:
	print("fleet snapshots (SHA-256 over packed float64 values)")
	for entry in FLEET:
		var loaded: Dictionary = AircraftData.load_file(entry[1])
		if not loaded.ok:
			push_error("%s data failed to load: %s" % [entry[0], str(loaded.errors)])
			_failed = true
			continue
		var model: Dictionary = loaded.model
		var prop: Dictionary = model.propulsion
		var steady_values := PackedFloat64Array()
		for throttle in THROTTLES:
			for axial_speed in AXIAL_SPEEDS:
				steady_values.append(Propulsion.steady_rpm(throttle, axial_speed, prop, RHO))
		var steady_hash := _sha256(steady_values.to_byte_array())

		var session := FlightSession.new()
		session.setup(entry[1])
		root.add_child(session)
		session.input_enabled = false
		if not session.aircraft.get("ok", false) or not session.start.get("ok", false):
			push_error("%s production start failed: %s" % [entry[0], str(session.start.get("message", "no start"))])
			_failed = true
			session.free()
			continue
		var start_speed := float(session.start.V)
		var level_trim := session.start.duplicate(true)
		var level_hash := _sha256(_trim_bytes(level_trim))
		var glide_trim: Dictionary = session.trim_at(start_speed, "glide")
		if not glide_trim.get("ok", false):
			push_error("%s glide trim failed: %s" % [entry[0], str(glide_trim.get("message", "no trim"))])
			_failed = true
			session.free()
			continue
		var glide_hash := _sha256(_trim_bytes(glide_trim))
		var hold_trace: RefCounted = Maneuvers.fly(session, {
			mode = "level", speed = start_speed, duration = float(TICK_COUNT) / 240.0,
			sticks = func(_t: float, _state: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off(),
		})
		if session.sim.tick != TICK_COUNT or not session.sim.fault_reason.is_empty():
			push_error("%s 240-tick hold did not complete cleanly: tick=%d fault=%s rows=%d" % [entry[0], session.sim.tick, session.sim.fault_reason, hold_trace.row_count()])
			_failed = true
		var endpoint_values := PackedFloat64Array([float(session.sim.tick)])
		endpoint_values.append_array(session.sim.state)
		endpoint_values.append_array(session.sim.aux)
		endpoint_values.append_array(session.sim.last_loads)
		endpoint_values.append_array(session.sim.inputs)
		var endpoint_hash := _sha256(endpoint_values.to_byte_array())
		print(entry[0], " steady_grid=", steady_hash, " level_trim=", level_hash, " glide_trim=", glide_hash, " flight_240=", endpoint_hash, " rpm_end=", session.sim.aux[0])
		session.free()


func _trim_bytes(trim: Dictionary) -> PackedByteArray:
	var values := PackedFloat64Array()
	values.append(1.0 if trim.get("ok", false) else 0.0)
	for key in ["V", "alpha", "beta", "gamma", "throttle", "rpm", "thrust", "elevator", "aileron", "rudder", "pitch_command", "roll_command", "yaw_command", "residual", "iterations"]:
		values.append(float(trim.get(key, NAN)))
	var state: PackedFloat64Array = trim.get("state", PackedFloat64Array())
	values.append_array(state)
	return values.to_byte_array()


func _net_torque(rpm: float, axial_speed: float, prop: Dictionary, rho: float) -> float:
	return Propulsion.engine_torque(rpm, 1.0, prop) - Propulsion.prop_torque(rpm, axial_speed, prop, rho)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
