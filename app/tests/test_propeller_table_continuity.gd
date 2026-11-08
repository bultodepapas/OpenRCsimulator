extends SceneTree
const P := preload("res://physics/propulsion.gd")
const AD := preload("res://physics/aircraft_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Flight := preload("res://sim/flight_session.gd")

var count := 0
var failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func adjacent(value: float, delta: int) -> float:
	var bytes := PackedFloat64Array([value]).to_byte_array()
	bytes.encode_u64(0, bytes.decode_u64(0) + delta)
	return bytes.decode_double(0)


func table_case(name: String, last: float, floor_value: float) -> void:
	var table := PackedFloat64Array([0.0, 0.2, 1.0, last])
	var left := P.coefficient(table, adjacent(1.0, -1), floor_value)
	var knot := P.coefficient(table, 1.0, floor_value)
	var right := P.coefficient(table, adjacent(1.0, 1), floor_value)
	check(name + " authored final knot", absf(knot - last) < 1e-14)
	check(name + " adjacent below continuous", absf(left - last) < 1e-14, str(left))
	check(name + " adjacent above continuous", absf(right - last) < 1e-14, str(right))
	check(name + " in-table interpolation unchanged", P.coefficient(table, 0.5, floor_value) == lerpf(0.2, last, 0.5))
	check(name + " static extrapolation unchanged", P.coefficient(table, -1.0, floor_value) == 0.2)
	check(name + " continuation bounded by lower of authored endpoint and floor",
		P.coefficient(table, 10.0, floor_value) == minf(last, floor_value))


func engine_off_crossing() -> void:
	var flight := Flight.new()
	flight.setup("res://data/aircraft/f4u_corsair_250.json")
	flight.input_enabled = false
	var prop: Dictionary = flight.aircraft.model.propulsion
	var rpm := 1750.0
	var initial_j := 1.35001
	var axis := P.axis(prop)
	var state := RB.make_state(M.v3(0, 0, -100), M.scale(axis, initial_j * rpm / 60.0 * float(prop.diameter)),
		M.q_identity(), M.v3(0, 0, 0))
	flight.engine_running = false
	flight.sim.inputs[3] = 0.0
	flight.sim.continuous[flight._rotor_index()] = rpm
	flight.sim.aux[Flight.AUX_RPM] = rpm
	check("engine-off fixture resets", flight.sim.reset(state))
	var before_j: float = P.thrust_torque(state.slice(RB.VEL, RB.VEL + 3), rpm, prop, 1.225)[2]
	flight.sim.step()
	var final_rpm: float = flight.sim.continuous[flight._rotor_index()]
	var after_j: float = P.thrust_torque(flight.sim.state.slice(RB.VEL, RB.VEL + 3), final_rpm, prop, 1.225)[2]
	print("Engine-off tick: J %.9f -> %.9f; RPM %.6f -> %.6f; tick %d; fault %s" % [before_j, after_j, rpm, final_rpm, flight.sim.tick, flight.sim.fault_reason])
	check("engine-off accepted tick crosses final knot", flight.sim.tick == 1 and flight.sim.fault_reason.is_empty() and before_j > 1.35 and after_j < 1.35)
	flight.free()


func tilted_changed_domain() -> void:
	# Hand-built vector force and r×F oracle; Ct's final value lies below its floor.
	var axis := M.v3(sqrt(0.99), 0.1, 0.0)
	var prop := {diameter = 0.762, axis = axis, offset = M.v3(0.12, 0.04, -0.03),
		ct = PackedFloat64Array([0.0, 0.2, 1.0, -0.12]), cp = PackedFloat64Array([0.0, 0.08, 1.0, 0.05]),
		normal_force = PackedFloat64Array([0.0, 0.25, 1.0, 0.25]),
		pfactor_moment = PackedFloat64Array([0.0, 0.1, 1.0, 0.1])}
	var n := 1750.0 / 60.0
	var along: float = 1.4 * n * float(prop.diameter)
	var velocity := M.add(M.scale(axis, along), M.v3(-0.1, sqrt(0.99), 0.5))
	var rho := 1.225
	var thrust: float = -0.12 * rho * n*n * pow(prop.diameter, 4)
	var cp := 0.05 + (0.05 - 0.08) * 0.4
	var torque: float = cp * rho * n*n * pow(prop.diameter, 5) / TAU
	var crossflow := M.sub(velocity, M.scale(axis, along))
	var normal := M.scale(crossflow, -0.25 * rho*n*n*pow(prop.diameter, 4) / sqrt(M.dot(velocity, velocity)))
	var pfactor := M.scale(crossflow, -0.1 * rho*n*n*pow(prop.diameter, 5) / sqrt(M.dot(velocity, velocity)))
	var force := M.add(M.scale(axis, thrust), normal)
	var arm := M.v3(-prop.offset[0], prop.offset[1], -prop.offset[2])
	var moment := M.add(M.sub(M.cross(arm, force), M.scale(axis, torque)), pfactor)
	var expected := PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]])
	var actual := P.loads(velocity, 1750.0, prop, rho)
	var close := true
	for i in 6:
		close = close and absf(actual[i] - expected[i]) < 1e-9
	check("tilted changed-domain wrench matches independent vector construction", close, "%s vs %s" % [actual, expected])


func malformed_table_refusals() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/f4u_corsair_250.json"))
	for entry in [
		["one row", [[0.0, 0.1]]],
		["descending knots", [[0.0, 0.1], [0.7, 0.0], [0.6, -0.01]]],
		["duplicate knots", [[0.0, 0.1], [0.7, 0.0], [0.7, -0.01]]],
		["nonfinite value", [[0.0, 0.1], [0.7, NAN]]],
		["nonfinite knot", [[0.0, 0.1], [INF, 0.0]]],
	]:
		var candidate: Dictionary = raw.duplicate(true)
		candidate.propulsion.propeller.ct_table.value = entry[1]
		var result := AD.validate_and_derive(candidate)
		check("invalid Ct " + entry[0] + " refused at admission", not result.ok, str(result.errors))


func _initialize() -> void:
	for value in [-0.05, -0.1, -0.12]:
		table_case("Ct last=" + str(value), value, -0.1)
	for value in [0.05, 0.0, -0.02]:
		table_case("zero-floor table last=" + str(value), value, 0.0)
	var ascending := PackedFloat64Array([0.0, -0.2, 1.0, -0.12])
	check("ascending below-floor continuation retains positive slope", absf(P.coefficient(ascending, 1.05, -0.1) - (-0.116)) < 1e-14)
	var loaded := AD.load_file("res://data/aircraft/f4u_corsair_250.json")
	check("Corsair admitted", loaded.ok, str(loaded.errors))
	if loaded.ok:
		var prop: Dictionary = loaded.model.propulsion
		var j: float = prop.ct[prop.ct.size() - 2]
		var before := P.coefficient(prop.ct, adjacent(j, -1), P.CT_FLOOR)
		var at := P.coefficient(prop.ct, j, P.CT_FLOOR)
		var after := P.coefficient(prop.ct, adjacent(j, 1), P.CT_FLOOR)
		var rpm := 1750.0
		var diameter: float = prop.diameter
		var n := rpm / 60.0
		var force_jump := (after - at) * 1.225 * n * n * pow(diameter, 4)
		print("Corsair endpoint: J=%.12f Ct(before,at,after)=(%.12f,%.12f,%.12f), thrust step=%.9f N" % [j, before, at, after, force_jump])
		check("Corsair final knot has no thrust step", absf(force_jump) < 1e-9)
		var control := j - 0.05
		check("in-table control remains locally continuous", absf(P.coefficient(prop.ct, control+1e-9, P.CT_FLOOR) - P.coefficient(prop.ct, control-1e-9, P.CT_FLOOR)) < 1e-7)
		var stopped := P.thrust_torque(M.v3(30, 1, 2), 0.0, prop, 1.225)
		check("stopped prop remains zero", stopped == PackedFloat64Array([0, 0, 0]))
		engine_off_crossing()
		tilted_changed_domain()
		malformed_table_refusals()
	print("Propeller table continuity: %d checks, %d failed" % [count, failures])
	quit(1 if failures else 0)
