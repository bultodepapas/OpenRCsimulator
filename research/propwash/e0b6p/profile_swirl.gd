# E0b6p profile: direct correction, zero-swirl axial load, and quadrature work counts.
# Synthetic combined wash-profile fixture only; timings are machine-local, not Gate P acceptance.
extends SceneTree

const Fixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const AirData = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const SwirlLoads = preload("res://physics/swirl_loads.gd")
const Reference = preload("res://tests/swirl_e0b6_reference.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

const RHO: float = 1.225
const DOWNWASH_CL: float = 0.3
const REPETITIONS: int = 16
const WARMUP: int = 3
const ROOT_TOLERANCE: float = 1.0e-14
const QUADRATURE_NODES: Array[float] = [
	-0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640,
]
const QUADRATURE_WEIGHTS: Array[float] = [
	0.2369268850561891, 0.4786286704993665, 0.5688888888888889,
	0.4786286704993665, 0.2369268850561891,
]

func _initialize() -> void:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var validated: Dictionary = AircraftData.validate_and_derive(raw)
	if not bool(validated.get("ok", false)):
		push_error("E0b6p profiling fixture rejected: %s" % str(validated.get("errors", [])))
		quit(1)
		return
	var active_model: Dictionary = validated.model
	var axial_model: Dictionary = active_model.duplicate(true)
	axial_model.propulsion.slipstream.swirl_factor = 0.0
	var rows: Array[Dictionary] = []
	for scenario: Dictionary in _scenarios():
		rows.append(_profile_case(active_model, axial_model, scenario))
		var row: Dictionary = rows.back()
		print("E0b6p %s correction=%.1f us axial_load=%.1f us intervals=%d nodes=%d active=%d tail_calls=%d" % [
			str(row.regime), float(row.correction_us), float(row.axial_slipstream_us), int(row.intervals),
			int(row.nodes), int(row.active_nodes), int(row.tail_load_calls),
		])
	var output_path: String = "/tmp/e0b6p-profile.json"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		output_path = args[0]
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("Unable to write E0b6p profile: %s" % output_path)
		quit(1)
		return
	output.store_string(JSON.stringify({
		"format": "openrc-e0b6p-profile v1",
		"cpu": OS.get_processor_name(),
		"godot": Engine.get_version_info().string,
		"repetitions": REPETITIONS,
		"warmup": WARMUP,
		"rows": rows,
	}, "\t", true, true) + "\n")
	quit()


func _scenarios() -> Array[Dictionary]:
	return [
		{"regime": "forward", "speed": 15.0, "alpha": deg_to_rad(3.0), "rates": [0.3, -0.2, 0.4], "elevator": 0.0, "rudder": 0.0},
		{"regime": "stall", "speed": 15.0, "alpha": deg_to_rad(15.0), "rates": [0.0, 0.0, 0.0], "elevator": 0.2, "rudder": 0.0},
		{"regime": "static", "speed": 0.0, "alpha": 0.0, "rates": [0.0, 0.0, 0.0], "elevator": 0.1, "rudder": -0.1},
		{"regime": "spin", "speed": 15.0, "alpha": deg_to_rad(15.0), "rates": [0.5, -0.3, 1.5], "elevator": 0.0, "rudder": 0.0},
		{"regime": "reverse_fade", "speed": -0.15, "alpha": 0.0, "rates": [0.1, 0.2, -0.1], "elevator": -0.1, "rudder": 0.1},
	]


func _profile_case(active_model: Dictionary, axial_model: Dictionary, scenario: Dictionary) -> Dictionary:
	var speed: float = float(scenario.speed)
	if scenario.regime == "reverse_fade":
		var propeller: Dictionary = active_model.propulsion
		speed *= propeller.max_rpm / 60.0 * propeller.diameter * M.sqrt_(2.0 * propeller.ct[1] / PI)
	var state: PackedFloat64Array = PackedFloat64Array([
		0.0, 0.0, -100.0,
		speed * cos(float(scenario.alpha)), 0.0,
		speed * sin(float(scenario.alpha)),
		1.0, 0.0, 0.0, 0.0,
		float(scenario.rates[0]), float(scenario.rates[1]), float(scenario.rates[2]),
	])
	var controls: Dictionary = {
		"elevator": float(scenario.elevator), "rudder": float(scenario.rudder),
		"aileron_left": 0.0, "aileron_right": 0.0,
	}
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var prop: Dictionary = active_model.propulsion
	var rpm: float = float(prop.max_rpm)
	var torque: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, prop, RHO)
	var wake: Dictionary = Slipstream.wake(air.v_air, torque[0], torque[1], prop, RHO)
	var fade: float = Slipstream.reverse_weight(air.v_air, rpm, prop)
	var counts: Dictionary = _work_counts(air.v_air, active_model, wake)
	var reference_times: Array[float] = []
	var correction_times: Array[float] = []
	var axial_times: Array[float] = []
	for sample: int in WARMUP + REPETITIONS:
		# Alternate order within the same process, fixture and wall-time window.
		for slot: int in 2:
			var reference_first: bool = (sample + slot) % 2 == 0
			var begin: int = Time.get_ticks_usec()
			if reference_first:
				Reference.correction(state, air, controls, active_model, wake, fade, RHO, DOWNWASH_CL)
			else:
				SwirlLoads.correction(state, air, controls, active_model, wake, fade, RHO, DOWNWASH_CL)
			if sample >= WARMUP:
				var elapsed: float = float(Time.get_ticks_usec() - begin)
				if reference_first:
					reference_times.append(elapsed)
				else:
					correction_times.append(elapsed)
		var begin: int = Time.get_ticks_usec()
		Slipstream.loads(state, air, controls, axial_model, rpm, RHO, DOWNWASH_CL)
		if sample >= WARMUP:
			axial_times.append(float(Time.get_ticks_usec() - begin))
	reference_times.sort()
	correction_times.sort()
	axial_times.sort()
	return {
		"regime": scenario.regime, "speed_mps": speed, "reverse_weight": fade,
		"reference_us": 0.5*(reference_times[7]+reference_times[8]),
		"correction_us": 0.5*(correction_times[7]+correction_times[8]),
		"axial_slipstream_us": 0.5*(axial_times[7]+axial_times[8]),
		"reference_samples_us": reference_times, "correction_samples_us": correction_times,
		"axial_samples_us": axial_times,
		"intervals": counts.intervals, "nodes": counts.nodes,
		"active_nodes": counts.active_nodes, "tail_load_calls": counts.tail_load_calls,
	}



func _work_counts(velocity: PackedFloat64Array, model: Dictionary, wake: Dictionary) -> Dictionary:
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var hub: PackedFloat64Array = slipstream.hub
	var speed: float = M.sqrt_(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2])
	var intervals: int = 0
	var nodes: int = 0
	var active_nodes: int = 0
	for piece: Dictionary in slipstream.pieces:
		var root: PackedFloat64Array = piece.root
		var direction: PackedFloat64Array = piece.span_dir
		var axis_le_0: float = -axis[0]
		var axis_le_1: float = axis[1]
		var axis_le_2: float = -axis[2]
		var distance: float = root[0] - hub[0]
		var shaft_scale: float = distance / axis_le_0
		var centre_0: float = hub[0] + axis_le_0 * shaft_scale
		var centre_1: float = hub[1] + axis_le_1 * shaft_scale
		var centre_2: float = hub[2] + axis_le_2 * shaft_scale
		if speed > 1.0e-6 and float(wake.vs) > 1.0e-6:
			var lean: float = minf(speed / (float(wake.u) + float(wake.w)), 1.0) * distance / speed
			centre_1 -= velocity[1] * lean
			centre_2 += velocity[2] * lean * float(slipstream.vertical_drift)
		var relative_0: float = root[0] - centre_0
		var relative_1: float = root[1] - centre_1
		var relative_2: float = root[2] - centre_2
		var along: float = relative_0 * direction[0] + relative_1 * direction[1] + relative_2 * direction[2]
		var perpendicular_0: float = relative_0 - direction[0] * along
		var perpendicular_1: float = relative_1 - direction[1] * along
		var perpendicular_2: float = relative_2 - direction[2] * along
		var perpendicular_squared: float = perpendicular_0 * perpendicular_0 + perpendicular_1 * perpendicular_1 + perpendicular_2 * perpendicular_2
		var inner_radius: float = float(wake.rs) * (1.0 - float(slipstream.edge_fraction))
		var outer_radius: float = float(wake.rs) * (1.0 + float(slipstream.edge_fraction))
		var core_roots: Array[float] = _circle_intersections(along, perpendicular_squared, float(wake.core) * float(wake.core))
		var inner_roots: Array[float] = _circle_intersections(along, perpendicular_squared, inner_radius * inner_radius)
		var outer_roots: Array[float] = _circle_intersections(along, perpendicular_squared, outer_radius * outer_radius)
		var profile: PackedFloat64Array = piece.profile
		var profile_area: float = 0.0
		for profile_index in range(0, profile.size(), 4):
			profile_area += 0.5 * (profile[profile_index + 2] + profile[profile_index + 3]) * (profile[profile_index + 1] - profile[profile_index])
		if profile_area <= 0.0:
			continue
		var area_scale: float = float(piece.area) / profile_area
		for profile_index in range(0, profile.size(), 4):
			var profile_start: float = profile[profile_index]
			var profile_end: float = profile[profile_index + 1]
			var chord_start: float = profile[profile_index + 2]
			var chord_end: float = profile[profile_index + 3]
			var splits: Array[float] = [profile_start, profile_end]
			_add_roots(splits, inner_roots, profile_start, profile_end)
			_add_roots(splits, outer_roots, profile_start, profile_end)
			_add_roots(splits, core_roots, profile_start, profile_end)
			splits.sort()
			for segment: int in range(splits.size() - 1):
				var low: float = splits[segment]
				var high: float = splits[segment + 1]
				if high - low <= ROOT_TOLERANCE:
					continue
				intervals += 1
				nodes += QUADRATURE_NODES.size()
				var middle: float = 0.5 * (low + high)
				var half: float = 0.5 * (high - low)
				var chord_slope: float = (chord_end - chord_start) / (profile_end - profile_start)
				for node: int in QUADRATURE_NODES.size():
					var eta: float = middle + half * QUADRATURE_NODES[node]
					var occupancy: float = _occupancy(eta, along, perpendicular_squared, inner_radius * inner_radius, outer_radius * outer_radius)
					var chord: float = chord_start + chord_slope * (eta - profile_start)
					var sample_area: float = area_scale * half * QUADRATURE_WEIGHTS[node] * chord * occupancy
					if sample_area > 0.0:
						active_nodes += 1
	return {"intervals": intervals, "nodes": nodes, "active_nodes": active_nodes, "tail_load_calls": 2 * active_nodes}


func _occupancy(eta: float, along: float, perpendicular_squared: float, inner_squared: float, outer_squared: float) -> float:
	var radial: float = eta + along
	var radius_squared: float = perpendicular_squared + radial * radial
	if radius_squared <= inner_squared:
		return 1.0
	if radius_squared >= outer_squared:
		return 0.0
	var t: float = clampf((radius_squared - inner_squared) / (outer_squared - inner_squared), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


func _circle_intersections(along: float, perpendicular_squared: float, radius_squared: float) -> Array[float]:
	var roots: Array[float] = []
	var radial_squared: float = radius_squared - perpendicular_squared
	if radial_squared < 0.0:
		return roots
	var half: float = M.sqrt_(radial_squared)
	roots.append(-along - half)
	if half > ROOT_TOLERANCE:
		roots.append(-along + half)
	return roots


func _add_roots(splits: Array[float], roots: Array[float], start: float, finish: float) -> void:
	for root: float in roots:
		if root > start and root < finish:
			splits.append(root)
