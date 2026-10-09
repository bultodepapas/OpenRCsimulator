# E5a: source-to-contact geometry, static taildragger equilibrium, steering signs and bare-contact refinement.
# Run: godot --headless --path app --script "$PWD/research/ground-contact/e5a/checks.gd" -- --out=/tmp/e5a-checks.json
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SimScript := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const G := 9.80665
const GEOMETRY_TOLERANCE := 2e-6
const DATA_FILES: Array[Dictionary] = [
	{
		id = "p51d-mustang-120",
		data = "res://data/aircraft/p51d_mustang_120.json",
		geometry = "assets/aircraft/p51d-mustang-120/geometry.json",
	},
	{
		id = "gp-extra-300s-60",
		data = "res://data/aircraft/gp_extra_300s_60.json",
		geometry = "assets/aircraft/extra-300s-60/geometry.json",
	},
]

var _count: int = 0
var _failures: int = 0
var _report: Dictionary = {}


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _read_json(path: String) -> Dictionary:
	var file_text: String = FileAccess.get_file_as_string(path)
	if file_text.is_empty():
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file_text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


func _repo_path(relative_path: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../" + relative_path).simplify_path()


func _le(model_z: float, model_y: float, model_x: float, le0: float) -> PackedFloat64Array:
	return PackedFloat64Array([model_z - le0, model_x, model_y])


func _max_difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var difference: float = 0.0
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]):
			return INF
		difference = maxf(difference, absf(a[i] - b[i]))
	return difference


func _geometry_contacts(geometry: Dictionary) -> Array[PackedFloat64Array]:
	var wing: Dictionary = geometry.get("wing", {})
	var gear: Dictionary = geometry.get("gear", {})
	var le0: float = float(wing.get("le_z_root", NAN))
	var main_axle: Array = gear.get("main_axle", [])
	var tail_axle: Array = gear.get("tail_axle", [])
	var main_radius: float = float(gear.get("main_wheel_diameter", NAN)) / 2.0
	var tail_radius: float = float(gear.get("tail_wheel_diameter", NAN)) / 2.0
	var track: float = float(gear.get("track", NAN))
	var points: Array[PackedFloat64Array] = []
	if main_axle.size() != 2 or tail_axle.size() != 2 or not is_finite(le0) or not is_finite(track):
		return points
	points.append(_le(float(main_axle[0]), float(main_axle[1]) - main_radius, -track / 2.0, le0))
	points.append(_le(float(main_axle[0]), float(main_axle[1]) - main_radius, track / 2.0, le0))
	points.append(_le(float(tail_axle[0]), float(tail_axle[1]) - tail_radius, 0.0, le0))
	return points


func _geometry_checks(case: Dictionary, geometry: Dictionary, raw: Dictionary, model: Dictionary) -> Dictionary:
	var case_id: String = str(case.id)
	var expected: Array[PackedFloat64Array] = _geometry_contacts(geometry)
	var raw_gear: Dictionary = raw.get("landing_gear", {})
	var raw_contacts: Array = raw_gear.get("contacts", [])
	var loaded_gear: Dictionary = model.get("landing_gear", {})
	var loaded_contacts: Array = loaded_gear.get("contacts", [])
	var cg: PackedFloat64Array = model.get("cg_inventory_le", PackedFloat64Array())
	var geometry_ok: bool = expected.size() == 3 and raw_contacts.size() == 3 and loaded_contacts.size() == 3 and cg.size() == 3
	var raw_max_error: float = 0.0
	var loaded_max_error: float = 0.0
	var names: Array[String] = ["main_left", "main_right", "tail"]
	if geometry_ok:
		for i in 3:
			var raw_contact: Dictionary = raw_contacts[i]
			var raw_position: Dictionary = raw_contact.get("position", {})
			var raw_values: Array = raw_position.get("value", [])
			var loaded_contact: Dictionary = loaded_contacts[i]
			var loaded_position: PackedFloat64Array = loaded_contact.get("position", PackedFloat64Array())
			geometry_ok = geometry_ok and str(raw_contact.get("name", "")) == names[i] and str(loaded_contact.get("name", "")) == names[i]
			if raw_values.size() != 3 or loaded_position.size() != 3:
				geometry_ok = false
				continue
			var raw_point := PackedFloat64Array([float(raw_values[0]), float(raw_values[1]), float(raw_values[2])])
			raw_max_error = maxf(raw_max_error, _max_difference(raw_point, expected[i]))
			var expected_body := PackedFloat64Array([
				-(raw_point[0] - cg[0]), raw_point[1] - cg[1], -(raw_point[2] - cg[2]),
			])
			loaded_max_error = maxf(loaded_max_error, _max_difference(loaded_position, expected_body))
		var hull_node: Dictionary = raw.get("crash_hull", {})
		var hull_points: Array = hull_node.get("value", [])
		for wheel_point in expected:
			for hull_variant in hull_points:
				var hull_array: Array = hull_variant
				if hull_array.size() == 3:
					var hull_point := PackedFloat64Array([float(hull_array[0]), float(hull_array[1]), float(hull_array[2])])
					if _max_difference(hull_point, wheel_point) <= GEOMETRY_TOLERANCE:
						geometry_ok = false
	var source_ok: bool = geometry_ok and raw_max_error <= GEOMETRY_TOLERANCE
	var loaded_ok: bool = geometry_ok and loaded_max_error <= GEOMETRY_TOLERANCE
	_check("%s: generator wheel bottoms match geometry and remain outside crash hull" % case_id,
		source_ok,
		"max source error %s m" % String.num_scientific(raw_max_error))
	_check("%s: loader transforms LE [aft,right,up] contacts into CG [forward,right,down]" % case_id,
		loaded_ok,
		"max loaded error %s m" % String.num_scientific(loaded_max_error))
	return { ok = source_ok and loaded_ok, source_ok = source_ok, loaded_ok = loaded_ok,
		source_error_m = raw_max_error, loaded_error_m = loaded_max_error,
		positions_le = [Array(expected[0]), Array(expected[1]), Array(expected[2])] if expected.size() == 3 else [] }


func _three_point_pitch(gear: Dictionary) -> float:
	var main: PackedFloat64Array = gear.contacts[0].position
	var tail: PackedFloat64Array = gear.contacts[2].position
	return atan2(main[2] - tail[2], main[0] - tail[0])


func _zero_loads() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _sim_for(model: Dictionary, gear: Dictionary, steer: float = 0.0) -> Node:
	var simulation: Node = SimScript.new()
	simulation.mass = float(model.mass_kg)
	simulation.inertia = model.inertia.duplicate()
	simulation.loads = func(state: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		var loads: PackedFloat64Array = Ground.loads(state, gear, steer)
		return _zero_loads() if loads.is_empty() else loads
	return simulation


func _ground_start(gear: Dictionary) -> PackedFloat64Array:
	var pitch: float = _three_point_pitch(gear)
	var attitude: PackedFloat64Array = M.q_from_euler(0.0, pitch, 0.0)
	var deepest: float = -INF
	for contact in gear.contacts:
		var offset: PackedFloat64Array = M.q_rotate(attitude, contact.position)
		deepest = maxf(deepest, offset[2])
	return RB.make_state(M.v3(0.0, 0.0, -deepest), M.v3(0.0, 0.0, 0.0), attitude, M.v3(0.0, 0.0, 0.0))


func _settle(model: Dictionary, gear: Dictionary, seconds: float = 8.0) -> Dictionary:
	Engine.physics_ticks_per_second = 240
	var simulation: Node = _sim_for(model, gear)
	var initial: PackedFloat64Array = _ground_start(gear)
	var reset_ok: bool = simulation.reset(initial)
	for _tick in range(roundi(seconds * 240.0)):
		simulation.step()
	var final_state: PackedFloat64Array = simulation.state.duplicate()
	var fault: String = str(simulation.fault_reason)
	var fault_free: bool = fault.is_empty()
	simulation.free()
	return { ok = reset_ok and fault_free, state = final_state, fault = fault }


func _static_checks(case_id: String, model: Dictionary, gear: Dictionary, settled: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = settled.state
	var loads: PackedFloat64Array = Ground.loads(state, gear)
	var euler: PackedFloat64Array = M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))
	var world_force: PackedFloat64Array = M.q_rotate(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]),
		M.v3(loads[0], loads[1], loads[2])) if loads.size() == 6 else M.v3(0.0, 0.0, 0.0)
	var weight: float = float(model.mass_kg) * G
	var normal_error: float = absf(-world_force[2] - weight) / weight
	var moment_size: float = sqrt(loads[3] ** 2 + loads[4] ** 2 + loads[5] ** 2) if loads.size() == 6 else INF
	var compression: PackedFloat64Array = Ground.compressions(state, gear)
	var actual_normal: PackedFloat64Array = PackedFloat64Array()
	var actual_total: float = 0.0
	for i in gear.contacts.size():
		var force: float = float(gear.contacts[i].stiffness) * compression[i]
		actual_normal.append(force)
		actual_total += force
	var actual_tail_share: float = actual_normal[2] / actual_total if actual_total > 0.0 else NAN
	var q: PackedFloat64Array = M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var main_left_world: PackedFloat64Array = M.q_rotate(q, gear.contacts[0].position)
	var main_right_world: PackedFloat64Array = M.q_rotate(q, gear.contacts[1].position)
	var tail_world: PackedFloat64Array = M.q_rotate(q, gear.contacts[2].position)
	var main_arm: float = (main_left_world[0] + main_right_world[0]) / 2.0
	var tail_arm: float = tail_world[0]
	var wheelbase: float = absf(main_arm - tail_arm)
	var oracle_tail_share: float = main_arm / (main_arm - tail_arm) if wheelbase > 1e-9 else NAN
	var geometric_pitch: float = _three_point_pitch(gear)
	var pitch_error_deg: float = absf(rad_to_deg(euler[1] - geometric_pitch))
	var every_wheel_loaded: bool = compression.size() == 3 and compression[0] > 0.0 and compression[1] > 0.0 and compression[2] > 0.0
	var share_error: float = absf(actual_tail_share - oracle_tail_share) if is_finite(actual_tail_share) and is_finite(oracle_tail_share) else INF
	var shares_match: bool = share_error < 1e-5
	var moment_ratio: float = moment_size / (weight * wheelbase) if wheelbase > 1e-9 else INF
	var moment_balanced: bool = is_finite(moment_ratio) and moment_ratio < 1e-5
	var pitch_tolerance_deg: float = 0.001 if case_id == "gp-extra-300s-60" else 2.0
	var pitch_matches: bool = pitch_error_deg < pitch_tolerance_deg
	var extra_compression_spread: float = maxf(compression[0], maxf(compression[1], compression[2])) \
		- minf(compression[0], minf(compression[1], compression[2])) if compression.size() == 3 else INF
	var extra_compressions_match: bool = case_id != "gp-extra-300s-60" or extra_compression_spread < 2e-6
	var equilibrium_ok: bool = settled.ok and every_wheel_loaded and not Ground.collapsed(state, gear) \
		and loads.size() == 6 and normal_error < 1e-4 and moment_balanced and shares_match \
		and pitch_matches and extra_compressions_match
	_check("%s: bare gear settles on all three wheels" % case_id,
		settled.ok and every_wheel_loaded and not Ground.collapsed(state, gear),
		"pitch %.3f°, compressions %s, fault '%s'" % [rad_to_deg(euler[1]), str(compression), str(settled.fault)])
	_check("%s: static contacts balance weight and hand-computed moment shares" % case_id,
		loads.size() == 6 and normal_error < 1e-4 and moment_balanced and shares_match,
		"ΣN error %s, |M| %s N·m (%s of W·wheelbase), tail share %s vs oracle %s (Δ %s)" % [
			String.num_scientific(normal_error), String.num(moment_size, 4), String.num(moment_ratio, 6),
			String.num(actual_tail_share, 8), String.num(oracle_tail_share, 8), String.num_scientific(share_error)])
	var pitch_detail: String = "wheel-bottom geometry %s°, settled %s° (Δ %s°, limit %s°)" % [
		String.num(rad_to_deg(geometric_pitch), 3), String.num(rad_to_deg(euler[1]), 3),
		String.num(pitch_error_deg, 5), String.num(pitch_tolerance_deg, 3)]
	if case_id == "p51d-mustang-120":
		pitch_detail += "; established P-51 spring split uses raw x moment arms, so a small compliant pitch offset is expected"
	_check("%s: compliant rest attitude matches wheel-bottom three-point geometry" % case_id,
		pitch_matches,
		pitch_detail)
	if case_id == "gp-extra-300s-60":
		_check("%s: projected-arm spring split gives equal main and tail compression" % case_id,
			extra_compressions_match,
			"compression spread %s m (limit 2e-6 m)" % String.num_scientific(extra_compression_spread))
	return { ok = equilibrium_ok, settled_ok = settled.ok, every_wheel_loaded = every_wheel_loaded,
		normal_force_ok = loads.size() == 6 and normal_error < 1e-4,
		moment_balance_ok = moment_balanced, moment_share_ok = shares_match, pitch_ok = pitch_matches,
		extra_compressions_ok = extra_compressions_match,
		pitch_deg = rad_to_deg(euler[1]), geometric_pitch_deg = rad_to_deg(geometric_pitch), pitch_error_deg = pitch_error_deg,
		pitch_tolerance_deg = pitch_tolerance_deg, compressions_m = Array(compression),
		extra_compression_spread_m = extra_compression_spread,
		normal_force_error_fraction = normal_error, moment_norm_nm = moment_size, moment_ratio = moment_ratio,
		actual_tail_share = actual_tail_share, oracle_tail_share = oracle_tail_share, tail_share_error = share_error }


func _taxi_state(rest: PackedFloat64Array, forward_speed: float, sideslip: float) -> PackedFloat64Array:
	var state: PackedFloat64Array = rest.duplicate()
	var euler: PackedFloat64Array = M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))
	state[RB.VEL] = forward_speed * cos(euler[1])
	state[RB.VEL + 1] = sideslip
	state[RB.VEL + 2] = forward_speed * sin(euler[1])
	for axis in 3:
		state[RB.RATE + axis] = 0.0
	return state


func _sign_checks(case_id: String, state: PackedFloat64Array, gear: Dictionary) -> Dictionary:
	var taxi: PackedFloat64Array = _taxi_state(state, 2.0, 0.0)
	var right: PackedFloat64Array = Ground.loads(taxi, gear, 1.0)
	var left: PackedFloat64Array = Ground.loads(taxi, gear, -1.0)
	var tail_angle_deg: float = rad_to_deg(float(gear.contacts[2].max_steering))
	var steer_signs: bool = tail_angle_deg < 0.0 and right.size() == 6 and left.size() == 6 \
		and right[1] < 0.0 and right[5] > 0.0 and left[1] > 0.0 and left[5] < 0.0
	_check("%s: +right command steers linked tailwheel left and yaws nose right; reverse command mirrors" % case_id,
		steer_signs,
		"tail coefficient %.1f°, +cmd Fy %.3f N Mz %.3f N·m; −cmd Fy %.3f N Mz %.3f N·m" % [tail_angle_deg, right[1], right[5], left[1], left[5]])
	var sideslip: PackedFloat64Array = _taxi_state(state, 2.0, 0.1)
	var main_only: Dictionary = gear.duplicate(true)
	main_only.contacts = [gear.contacts[0], gear.contacts[1]]
	var tail_only: Dictionary = gear.duplicate(true)
	tail_only.contacts = [gear.contacts[2]]
	var main_loads: PackedFloat64Array = Ground.loads(sideslip, main_only)
	var tail_loads: PackedFloat64Array = Ground.loads(sideslip, tail_only)
	var pivot_signs: bool = main_loads.size() == 6 and tail_loads.size() == 6 \
		and main_loads[1] < 0.0 and main_loads[5] < 0.0 and tail_loads[1] < 0.0 and tail_loads[5] > 0.0
	_check("%s: rightward slip gives main-ahead yaw divergence, aft-tail restoring moment" % case_id,
		pivot_signs,
		"main only Fy %.3f N Mz %.3f N·m; tail only Fy %.3f N Mz %.3f N·m" % [main_loads[1], main_loads[5], tail_loads[1], tail_loads[5]])
	return { ok = steer_signs and pivot_signs, tail_steering_deg = tail_angle_deg,
		right_command_loads = Array(right), left_command_loads = Array(left),
		main_only_sideslip_loads = Array(main_loads), tail_only_sideslip_loads = Array(tail_loads) }


func _taxi(model: Dictionary, gear: Dictionary, rest: PackedFloat64Array, hz: int, steer: float) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var simulation: Node = _sim_for(model, gear, steer)
	var state: PackedFloat64Array = _taxi_state(rest, 1.0, 0.0)
	var reset_ok: bool = simulation.reset(state)
	for _tick in range(2 * hz):
		simulation.step()
	var result: Dictionary = { ok = reset_ok and str(simulation.fault_reason).is_empty(),
		state = simulation.state.duplicate(), fault = str(simulation.fault_reason) }
	simulation.free()
	return result


func _refinement_checks(case_id: String, model: Dictionary, gear: Dictionary, rest: PackedFloat64Array) -> Dictionary:
	var saved_hz: int = Engine.physics_ticks_per_second
	var positive_240: Dictionary = _taxi(model, gear, rest, 240, 0.5)
	var positive_480: Dictionary = _taxi(model, gear, rest, 480, 0.5)
	var negative_240: Dictionary = _taxi(model, gear, rest, 240, -0.5)
	var negative_480: Dictionary = _taxi(model, gear, rest, 480, -0.5)
	Engine.physics_ticks_per_second = saved_hz
	var positive_state: PackedFloat64Array = positive_240.state
	var positive_fine: PackedFloat64Array = positive_480.state
	var negative_state: PackedFloat64Array = negative_240.state
	var negative_fine: PackedFloat64Array = negative_480.state
	var max_position_error: float = 0.0
	var max_velocity_error: float = 0.0
	var max_attitude_error: float = 0.0
	var max_rate_error: float = 0.0
	for i in 3:
		max_position_error = maxf(max_position_error, absf(positive_state[RB.POS + i] - positive_fine[RB.POS + i]))
		max_position_error = maxf(max_position_error, absf(negative_state[RB.POS + i] - negative_fine[RB.POS + i]))
		max_velocity_error = maxf(max_velocity_error, absf(positive_state[RB.VEL + i] - positive_fine[RB.VEL + i]))
		max_velocity_error = maxf(max_velocity_error, absf(negative_state[RB.VEL + i] - negative_fine[RB.VEL + i]))
		max_rate_error = maxf(max_rate_error, absf(positive_state[RB.RATE + i] - positive_fine[RB.RATE + i]))
		max_rate_error = maxf(max_rate_error, absf(negative_state[RB.RATE + i] - negative_fine[RB.RATE + i]))
	for i in 4:
		max_attitude_error = maxf(max_attitude_error, absf(positive_state[RB.ATT + i] - positive_fine[RB.ATT + i]))
		max_attitude_error = maxf(max_attitude_error, absf(negative_state[RB.ATT + i] - negative_fine[RB.ATT + i]))
	var positive_euler: PackedFloat64Array = M.q_to_euler(M.quat(positive_state[RB.ATT], positive_state[RB.ATT + 1], positive_state[RB.ATT + 2], positive_state[RB.ATT + 3]))
	var negative_euler: PackedFloat64Array = M.q_to_euler(M.quat(negative_state[RB.ATT], negative_state[RB.ATT + 1], negative_state[RB.ATT + 2], negative_state[RB.ATT + 3]))
	var signs_ok: bool = positive_240.ok and positive_480.ok and negative_240.ok and negative_480.ok \
		and positive_euler[0] > 0.01 and negative_euler[0] < -0.01
	var refinement_ok: bool = max_position_error < 0.001 and max_velocity_error < 0.01 \
		and max_attitude_error < 0.001 and max_rate_error < 0.001
	_check("%s: opposite rudder commands turn opposite ways in the two-second bare taxi" % case_id,
		signs_ok,
		"+cmd yaw %.3f°, −cmd yaw %.3f°; faults '%s' / '%s'" % [rad_to_deg(positive_euler[0]), rad_to_deg(negative_euler[0]), positive_240.fault, negative_240.fault])
	_check("%s: 240/480 Hz bare taxi refinement within 1 mm, 1 cm/s and 0.001 attitude/rate" % case_id,
		positive_240.ok and positive_480.ok and negative_240.ok and negative_480.ok and refinement_ok,
		"Δpos %s m, Δvel %s m/s, Δq %s, Δrate %s rad/s" % [String.num_scientific(max_position_error),
			String.num_scientific(max_velocity_error), String.num_scientific(max_attitude_error), String.num_scientific(max_rate_error)])
	return { ok = signs_ok and refinement_ok, delta_position_m = max_position_error, delta_velocity_m_s = max_velocity_error,
		delta_quaternion = max_attitude_error, delta_rate_rad_s = max_rate_error,
		positive_yaw_deg = rad_to_deg(positive_euler[0]), negative_yaw_deg = rad_to_deg(negative_euler[0]) }


func _case(case: Dictionary) -> void:
	var case_id: String = str(case.id)
	var geometry_path: String = _repo_path(str(case.geometry))
	var geometry: Dictionary = _read_json(geometry_path)
	var raw_path: String = str(case.data)
	var raw: Dictionary = _read_json(raw_path)
	var loaded: Dictionary = AircraftData.load_file(raw_path)
	_check("%s: raw and loaded aircraft data are available" % case_id,
		not geometry.is_empty() and not raw.is_empty() and bool(loaded.get("ok", false)),
		str(loaded.get("errors", [])))
	if geometry.is_empty() or raw.is_empty() or not bool(loaded.get("ok", false)):
		_report[case_id] = { ok = false, error = str(loaded.get("errors", [])) }
		return
	var model: Dictionary = loaded.model
	var gear: Dictionary = model.landing_gear
	var geometry_result: Dictionary = _geometry_checks(case, geometry, raw, model)
	var settled: Dictionary = _settle(model, gear)
	var static_result: Dictionary = _static_checks(case_id, model, gear, settled)
	var sign_result: Dictionary = _sign_checks(case_id, settled.state, gear)
	var refinement_result: Dictionary = _refinement_checks(case_id, model, gear, settled.state)
	_report[case_id] = { ok = geometry_result.ok and static_result.ok and sign_result.ok and refinement_result.ok,
		geometry = geometry_result, equilibrium = static_result, signs = sign_result, refinement = refinement_result }


func _write_report() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--out="):
			continue
		var path: String = argument.trim_prefix("--out=")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		_check("report opened", file != null, path)
		if file != null:
			file.store_string(JSON.stringify({ format = "openrc-e5a-checks v1", checks = _count, failures = _failures,
				results = _report }, "\t") + "\n")
		return


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	for case in DATA_FILES:
		_case(case)
	Engine.physics_ticks_per_second = original_hz
	_write_report()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
