# E0b3b numerical comparison: one weighted-area centroid load vs dense spanwise local loads.
# Standalone headless experiment, not an application test or an aircraft calibration.
extends SceneTree

const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const S = preload("res://physics/slipstream.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Prop = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

const RHO: float = 1.225
const DOWNWASH_CL: float = 0.3
const DEFAULT_SAMPLES_PER_INTERVAL: int = 64
const MIN_SAMPLES_PER_INTERVAL: int = 8
const MAX_SAMPLES_PER_INTERVAL: int = 1024
var samples_per_interval: int = DEFAULT_SAMPLES_PER_INTERVAL


func _initialize() -> void:
	if not parse_sample_count():
		quit(2)
		return
	print("E0b3b centroid comparison: %d midpoint samples per profile interval" % samples_per_interval)
	print("Reference integrates the same edge occupancy, local rates, local swirl, area scale, load arms and reverse fade.")
	print("Chordwise x remains fixed at the runtime aerodynamic reference; horizontal load z stays on the existing CP plane.")
	print("No error threshold is applied. Centroid evaluation is an approximation to local nonlinear loads.")
	var finite: bool = true
	for swirl_factor: float in [0.0, 0.4]:
		var raw: Dictionary = Fixture.combined_raw()
		raw.propulsion.propeller.slipstream.swirl_factor.value = swirl_factor
		var loaded: Dictionary = AD.validate_and_derive(raw)
		if not loaded.ok:
			print("ERROR fixture validation: ", loaded.errors)
			quit(1)
			return
		for scenario: Dictionary in scenarios():
			finite = compare_case(loaded.model, scenario, swirl_factor) and finite
	print("all centroid and dense load components finite: ", finite)
	print("Interpret the differences as the measured centroid approximation error for these six synthetic cases; they do not validate the Stik or its wake model.")
	quit(0 if finite else 1)


func parse_sample_count() -> bool:
	var seen: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--samples-per-interval="):
			continue
		if seen:
			push_error("Use --samples-per-interval once")
			return false
		seen = true
		var token: String = argument.trim_prefix("--samples-per-interval=")
		if not token.is_valid_int():
			push_error("--samples-per-interval must be an integer")
			return false
		var requested: int = token.to_int()
		if requested < MIN_SAMPLES_PER_INTERVAL or requested > MAX_SAMPLES_PER_INTERVAL:
			push_error("--samples-per-interval must be in [%d, %d]" % [MIN_SAMPLES_PER_INTERVAL, MAX_SAMPLES_PER_INTERVAL])
			return false
		samples_per_interval = requested
	return true


func scenarios() -> Array[Dictionary]:
	return [
		{name = "static_controls", speed = 0.0, alpha_deg = 0.0, rates = [0.0, 0.0, 0.0], elevator = 0.1, rudder = -0.1},
		{name = "forward_15mps_alpha3", speed = 15.0, alpha_deg = 3.0, rates = [0.3, -0.2, 0.4], elevator = 0.0, rudder = 0.0},
		{name = "stall_alpha15", speed = 15.0, alpha_deg = 15.0, rates = [0.0, 0.0, 0.0], elevator = 0.2, rudder = 0.0},
	]


func compare_case(model: Dictionary, scenario: Dictionary, swirl_factor: float) -> bool:
	var angle: float = deg_to_rad(float(scenario.alpha_deg))
	var state := PackedFloat64Array([
		0.0, 0.0, -100.0,
		float(scenario.speed) * cos(angle), 0.0, float(scenario.speed) * sin(angle),
		1.0, 0.0, 0.0, 0.0,
		float(scenario.rates[0]), float(scenario.rates[1]), float(scenario.rates[2]),
	])
	var controls: Dictionary = {
		elevator = float(scenario.elevator),
		rudder = float(scenario.rudder),
		aileron_left = 0.0,
		aileron_right = 0.0,
	}
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var rpm: float = model.propulsion.max_rpm
	var actual: PackedFloat64Array = S.loads(state, air, controls, model, rpm, RHO, DOWNWASH_CL)
	var prop: Dictionary = model.propulsion
	var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, rpm, prop, RHO)
	var wake: Dictionary = S.wake(air.v_air, tq[0], tq[1], prop, RHO)
	var fade: float = S.reverse_weight(air.v_air, rpm, prop)
	var dense := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for piece: Dictionary in prop.slipstream.pieces:
		var contribution: PackedFloat64Array = dense_piece(state, air, controls, model, piece, wake)
		for axis in 6:
			dense[axis] += contribution[axis]
	for axis in 6:
		dense[axis] *= fade
	var error := PackedFloat64Array()
	var finite: bool = true
	for axis in 6:
		var delta: float = actual[axis] - dense[axis]
		error.append(delta)
		finite = finite and is_finite(actual[axis]) and is_finite(dense[axis]) and is_finite(delta)
	var force_error: float = vector_norm(error, 0)
	var moment_error: float = vector_norm(error, 3)
	var force_reference: float = vector_norm(dense, 0)
	var moment_reference: float = vector_norm(dense, 3)
	var result: Dictionary = {
		"scenario": scenario.name,
		"swirl_factor": swirl_factor,
		"reverse_fade": fade,
		"samples_per_profile_interval": samples_per_interval,
		"centroid_load_Fx_Fy_Fz_Mx_My_Mz": actual,
		"dense_load_Fx_Fy_Fz_Mx_My_Mz": dense,
		"signed_error_Fx_Fy_Fz_Mx_My_Mz": error,
		"absolute_force_error_norm_N": force_error,
		"dense_force_norm_N": force_reference,
		"normalized_force_error": force_error / force_reference if force_reference > 1e-12 else null,
		"absolute_moment_error_norm_Nm": moment_error,
		"dense_moment_norm_Nm": moment_reference,
		"normalized_moment_error": moment_error / moment_reference if moment_reference > 1e-12 else null,
		"finite": finite,
	}
	print(JSON.stringify(result))
	return finite


func dense_piece(state: PackedFloat64Array, air: Dictionary, controls: Dictionary, model: Dictionary,
		piece: Dictionary, wake: Dictionary) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var axis: PackedFloat64Array = Prop.axis(prop)
	var root: PackedFloat64Array = piece.root
	var direction: PackedFloat64Array = piece.span_dir
	var hub: PackedFloat64Array = slipstream.hub
	# Match the production root-based wake centre and drift, holding chordwise x at the reference root.
	var axis_le_0: float = -axis[0]
	var axis_le_1: float = axis[1]
	var axis_le_2: float = -axis[2]
	var distance: float = root[0] - hub[0]
	var shaft_scale: float = distance / axis_le_0
	var centre_0: float = hub[0] + axis_le_0 * shaft_scale
	var centre_1: float = hub[1] + axis_le_1 * shaft_scale
	var centre_2: float = hub[2] + axis_le_2 * shaft_scale
	var velocity: PackedFloat64Array = air.v_air
	if air.V > 1e-6 and wake.vs > 1e-6:
		var lean: float = minf(air.V / (wake.u + wake.w), 1.0) * distance / air.V
		centre_1 -= velocity[1] * lean
		centre_2 += velocity[2] * lean * float(slipstream.vertical_drift)
	var relative_0: float = root[0] - centre_0
	var relative_1: float = root[1] - centre_1
	var relative_2: float = root[2] - centre_2
	var along: float = relative_0 * direction[0] + relative_1 * direction[1] + relative_2 * direction[2]
	var perp_0: float = relative_0 - direction[0] * along
	var perp_1: float = relative_1 - direction[1] * along
	var perp_2: float = relative_2 - direction[2] * along
	var d2: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
	var inner2: float = wake.rs * wake.rs * pow(1.0 - float(slipstream.edge_fraction), 2)
	var outer2: float = wake.rs * wake.rs * pow(1.0 + float(slipstream.edge_fraction), 2)
	var profile: PackedFloat64Array = piece.profile
	var profile_area: float = 0.0
	for i in range(0, profile.size(), 4):
		profile_area += 0.5 * (profile[i + 2] + profile[i + 3]) * (profile[i + 1] - profile[i])
	var area_scale: float = float(piece.area) / profile_area
	var result := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in range(0, profile.size(), 4):
		var start: float = profile[i]
		var end: float = profile[i + 1]
		var h: float = (end - start) / float(samples_per_interval)
		var slope: float = (profile[i + 3] - profile[i + 2]) / (end - start)
		for sample in samples_per_interval:
			var eta: float = start + (float(sample) + 0.5) * h
			var radial: float = eta + along
			var t: float = clampf((d2 + radial * radial - inner2) / (outer2 - inner2), 0.0, 1.0)
			var occupancy: float = 1.0 - t * t * (3.0 - 2.0 * t)
			var chord: float = profile[i + 2] + slope * (eta - start)
			var sample_area: float = area_scale * h * chord * occupancy
			if sample_area <= 0.0:
				continue
			var point_0: float = root[0] + direction[0] * eta
			var point_1: float = root[1] + direction[1] * eta
			var point_2: float = root[2] + direction[2] * eta
			var shift := PackedFloat64Array([
				0.0,
				point_1 - float(model.surfaces[piece.surface].position[1]),
				0.0 if piece.surface == "horizontal" else -(point_2 - float(model.surfaces[piece.surface].position[2])),
			])
			var radial_body_0: float = -(point_0 - centre_0)
			var radial_body_1: float = point_1 - centre_1
			var radial_body_2: float = -(point_2 - centre_2)
			var axial: float = radial_body_0 * axis[0] + radial_body_1 * axis[1] + radial_body_2 * axis[2]
			radial_body_0 -= axis[0] * axial
			radial_body_1 -= axis[1] * axial
			radial_body_2 -= axis[2] * axial
			var radius: float = maxf(M.sqrt_(radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1 + radial_body_2 * radial_body_2), wake.core)
			var swirl_scale: float = wake.swirl / (radius * radius)
			var swirl := PackedFloat64Array([
				(axis[1] * radial_body_2 - axis[2] * radial_body_1) * swirl_scale,
				(axis[2] * radial_body_0 - axis[0] * radial_body_2) * swirl_scale,
				(axis[0] * radial_body_1 - axis[1] * radial_body_0) * swirl_scale,
			])
			var extra: PackedFloat64Array = M.sub(M.scale(axis, wake.dv), swirl)
			var increment: PackedFloat64Array = Aero.tail_surface_increment(
				velocity, state.slice(RB.RATE, RB.RATE + 3), controls, model,
				piece.surface, sample_area, shift, extra, RHO, 0.3)
			for component in 6:
				result[component] += increment[component]
	return result


func vector_norm(values: PackedFloat64Array, start: int) -> float:
	return M.sqrt_(values[start] * values[start] + values[start + 1] * values[start + 1] + values[start + 2] * values[start + 2])
