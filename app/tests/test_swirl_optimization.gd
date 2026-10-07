# E0b6p: deterministic numerical equivalence against the frozen pre-optimization quadrature.
# Geometry fixtures are schema-validated, synthetic perturbations of the E0b3b test profile, not aircraft calibration.
extends SceneTree

const Fixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const AirData = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const SwirlLoads = preload("res://physics/swirl_loads.gd")
const FrozenReference = preload("res://tests/swirl_e0b6_reference.gd")
const M = preload("res://physics/math3d.gd")

const CASE_COUNT: int = 200
const MODEL_COUNT: int = 16
const ABSOLUTE_TOLERANCE: float = 1.0e-10
const RELATIVE_TOLERANCE: float = 1.0e-10
const SEED: int = 2601007

var checks: int = 0
var failures: int = 0
var worst_absolute_error: float = 0.0
var worst_tolerance_ratio: float = 0.0
var worst_detail: String = "none"
var core_crossing_cases: int = 0
var inner_edge_crossing_cases: int = 0
var outer_edge_crossing_cases: int = 0
var full_fade_cases: int = 0
var partial_reverse_fade_cases: int = 0
var reverse_cutoff_cases: int = 0
var default_cl_cases: int = 0
var held_cl_cases: int = 0
var downwash_tail_law_cases: int = 0
var classic_tail_law_cases: int = 0


func _initialize() -> void:
	print("E0b6p optimized swirl equivalence: %d deterministic cases, seed %d" % [CASE_COUNT, SEED])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var models: Array[Dictionary] = _build_valid_models(rng)
	if models.size() != MODEL_COUNT:
		print("FAIL could not build all validated smooth fixtures")
		quit(1)
		return

	for case_index in CASE_COUNT:
		var model_index: int = case_index % MODEL_COUNT
		var model: Dictionary = models[model_index]
		var prop: Dictionary = model.propulsion
		var rho: float = rng.randf_range(0.72, 1.42)
		var rpm: float = rng.randf_range(prop.idle_rpm, prop.max_rpm)
		var velocity: PackedFloat64Array = _case_velocity(case_index, model, rpm, rng)
		if case_index % 53 == 52:
			rpm = 0.0 # The helper's exact early return also stays covered.
		var rates: PackedFloat64Array = PackedFloat64Array([
			rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8),
		])
		var state: PackedFloat64Array = PackedFloat64Array([
			0.0, 0.0, -100.0,
			velocity[0], velocity[1], velocity[2],
			1.0, 0.0, 0.0, 0.0,
			rates[0], rates[1], rates[2],
		])
		var controls: Dictionary = {
			elevator = rng.randf_range(-0.55, 0.55),
			rudder = rng.randf_range(-0.55, 0.55),
			aileron_left = rng.randf_range(-0.4, 0.4),
			aileron_right = rng.randf_range(-0.4, 0.4),
		}
		var air: Dictionary = AirData.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
		var thrust_torque: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, prop, rho)
		var wake: Dictionary = Slipstream.wake(air.v_air, thrust_torque[0], thrust_torque[1], prop, rho)
		var fade: float = Slipstream.reverse_weight(air.v_air, rpm, prop)
		var downwash_cl: float = NAN if case_index % 2 == 0 else rng.randf_range(-1.1, 1.1)
		if is_nan(downwash_cl):
			default_cl_cases += 1
		else:
			held_cl_cases += 1
		if model.surfaces.horizontal.has("free_slope"):
			downwash_tail_law_cases += 1
		else:
			classic_tail_law_cases += 1

		var expected: PackedFloat64Array = FrozenReference.correction(
			state, air, controls, model, wake, fade, rho, downwash_cl)
		var actual: PackedFloat64Array = SwirlLoads.correction(
			state, air, controls, model, wake, fade, rho, downwash_cl)
		_compare_case(case_index, model_index, expected, actual)

		if fade >= 1.0:
			full_fade_cases += 1
		elif fade > 0.0:
			partial_reverse_fade_cases += 1
		else:
			reverse_cutoff_cases += 1
		if fade > 0.0 and float(wake.swirl) != 0.0:
			var crossings: Dictionary = _crossings(model, air.v_air, air.V, wake)
			if crossings.core:
				core_crossing_cases += 1
			if crossings.inner:
				inner_edge_crossing_cases += 1
			if crossings.outer:
				outer_edge_crossing_cases += 1

	_check("200 cases include default and held downwash CL", default_cl_cases == 100 and held_cl_cases == 100,
		"default=%d held=%d" % [default_cl_cases, held_cl_cases])
	_check("200 cases include both horizontal tail-law modes",
		downwash_tail_law_cases == 150 and classic_tail_law_cases == 50,
		"free_slope/downwash=%d classic/no-free_slope=%d" % [downwash_tail_law_cases, classic_tail_law_cases])
	_check("active smooth geometry crosses the regularized vortex core",
		core_crossing_cases > 0, "%d cases" % core_crossing_cases)
	_check("active smooth geometry crosses the inner occupancy edge",
		inner_edge_crossing_cases > 0, "%d cases" % inner_edge_crossing_cases)
	_check("active smooth geometry crosses the outer occupancy edge",
		outer_edge_crossing_cases > 0, "%d cases" % outer_edge_crossing_cases)
	_check("forward and reverse fade regimes are all sampled",
		full_fade_cases > 0 and partial_reverse_fade_cases > 0 and reverse_cutoff_cases > 0,
		"full=%d partial=%d cutoff=%d" % [full_fade_cases, partial_reverse_fade_cases, reverse_cutoff_cases])
	_check("optimized helper matches frozen helper within abs+relative 1e-10",
		failures == 0, "%d mismatches; worst %s" % [failures, worst_detail])
	print("E0b6p equivalence worst absolute error=%s, worst error/tolerance=%s (%s)" % [
		String.num_scientific(worst_absolute_error), String.num_scientific(worst_tolerance_ratio), worst_detail])
	print("E0b6p equivalence coverage: core=%d inner=%d outer=%d reverse(full/partial/cutoff)=%d/%d/%d CL(default/held)=%d/%d tail_law(downwash/classic)=%d/%d" % [
		core_crossing_cases, inner_edge_crossing_cases, outer_edge_crossing_cases,
		full_fade_cases, partial_reverse_fade_cases, reverse_cutoff_cases, default_cl_cases, held_cl_cases,
		downwash_tail_law_cases, classic_tail_law_cases])
	print("E0b6p optimized swirl equivalence: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _build_valid_models(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var models: Array[Dictionary] = []
	for model_index in MODEL_COUNT:
		var raw: Dictionary = Fixture.combined_raw()
		var propeller: Dictionary = raw.propulsion.propeller
		var smooth: Dictionary = propeller.slipstream
		var neutral_crossing_geometry: bool = model_index % 4 == 0
		if model_index % 4 == 1:
			raw.aero.surfaces.horizontal.erase("downwash_gradient")
		smooth.edge_fraction.value = rng.randf_range(0.035, 0.44)
		smooth.swirl_factor.value = rng.randf_range(0.18, 0.95)
		smooth.vertical_drift.value = rng.randf_range(0.05, 0.95)
		smooth.hub.value[0] = rng.randf_range(-0.39, -0.20)
		smooth.hub.value[1] = 0.0 if neutral_crossing_geometry else rng.randf_range(-0.018, 0.018)
		smooth.hub.value[2] = 0.0 if neutral_crossing_geometry else rng.randf_range(-0.018, 0.018)
		propeller.diameter.value = rng.randf_range(0.22, 0.48)
		for piece: Dictionary in smooth.pieces:
			var span_scale: float = rng.randf_range(0.86, 1.14)
			var chord_scale: float = rng.randf_range(0.88, 1.12)
			piece.span.value *= span_scale
			piece.area.value *= span_scale * chord_scale
			piece.root.value[0] += rng.randf_range(-0.025, 0.08)
			if neutral_crossing_geometry:
				piece.root.value[1] = 0.0
				if piece.surface == "horizontal":
					piece.root.value[2] = -0.04064
				else:
					piece.root.value[2] = -0.02667
			else:
				piece.root.value[1] += rng.randf_range(-0.025, 0.025)
				piece.root.value[2] += rng.randf_range(-0.025, 0.025)
			for row: Array in piece.profile.value:
				row[0] *= span_scale
				row[1] *= span_scale
				row[2] *= chord_scale
				row[3] *= chord_scale
		var loaded: Dictionary = AircraftData.validate_and_derive(raw)
		if not loaded.get("ok", false):
			_check("randomized smooth fixture %d validates" % model_index, false, str(loaded.get("errors", [])))
			return []
		models.append(loaded.model)
	return models


func _case_velocity(case_index: int, model: Dictionary, rpm: float, rng: RandomNumberGenerator) -> PackedFloat64Array:
	var slot: int = case_index % MODEL_COUNT
	if slot in [0, 4, 8, 12]:
		# With centered geometry these cross the core and both smooth occupancy edges along a tail span.
		return PackedFloat64Array([rng.randf_range(3.0, 20.0), 0.0, 0.0])
	var velocity: PackedFloat64Array = PackedFloat64Array([
		rng.randf_range(-9.0, 28.0), rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0),
	])
	if slot in [1, 2, 3]:
		var prop: Dictionary = model.propulsion
		var vi0: float = rpm / 60.0 * prop.diameter * M.sqrt_(2.0 * prop.ct[1] / PI)
		var bounds: PackedFloat64Array = prop.slipstream.reverse_fade
		if slot == 1:
			velocity[0] = -0.5 * bounds[0] * vi0
		elif slot == 2:
			velocity[0] = -0.5 * (bounds[0] + bounds[1]) * vi0
		else:
			velocity[0] = -1.15 * bounds[1] * vi0
	return velocity


func _compare_case(case_index: int, model_index: int,
		expected: PackedFloat64Array, actual: PackedFloat64Array) -> void:
	var finite: bool = expected.size() == 6 and actual.size() == 6
	var case_worst_absolute: float = 0.0
	var case_worst_ratio: float = 0.0
	var case_worst_detail: String = ""
	for component in 6:
		if not is_finite(expected[component]) or not is_finite(actual[component]):
			finite = false
			case_worst_detail = "case=%d model=%d component=%d nonfinite expected=%s actual=%s" % [
				case_index, model_index, component, str(expected[component]), str(actual[component])]
			continue
		var error: float = absf(actual[component] - expected[component])
		var tolerance: float = ABSOLUTE_TOLERANCE + RELATIVE_TOLERANCE * absf(expected[component])
		var ratio: float = error / tolerance
		if error > case_worst_absolute:
			case_worst_absolute = error
			case_worst_detail = "case=%d model=%d component=%d reference=%s actual=%s abs_error=%s tolerance=%s" % [
				case_index, model_index, component,
				String.num_scientific(expected[component]), String.num_scientific(actual[component]),
				String.num_scientific(error), String.num_scientific(tolerance)]
		if ratio > case_worst_ratio:
			case_worst_ratio = ratio
	if case_worst_absolute > worst_absolute_error:
		worst_absolute_error = case_worst_absolute
		worst_detail = case_worst_detail
	worst_tolerance_ratio = maxf(worst_tolerance_ratio, case_worst_ratio)
	if not finite or case_worst_ratio > 1.0:
		_check("case %d equivalence" % case_index, false,
			case_worst_detail if not case_worst_detail.is_empty() else "nonfinite correction")


func _crossings(model: Dictionary, velocity: PackedFloat64Array, speed: float, wake: Dictionary) -> Dictionary:
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var hub: PackedFloat64Array = slipstream.hub
	var core_crossed: bool = false
	var inner_crossed: bool = false
	var outer_crossed: bool = false
	for piece: Dictionary in slipstream.pieces:
		var piece_root: PackedFloat64Array = piece.root
		var direction: PackedFloat64Array = piece.span_dir
		var axis_le_0: float = -axis[0]
		var axis_le_1: float = axis[1]
		var axis_le_2: float = -axis[2]
		var distance: float = piece_root[0] - hub[0]
		var shaft_scale: float = distance / axis_le_0
		var centre_0: float = hub[0] + axis_le_0 * shaft_scale
		var centre_1: float = hub[1] + axis_le_1 * shaft_scale
		var centre_2: float = hub[2] + axis_le_2 * shaft_scale
		if speed > 1e-6 and float(wake.vs) > 1e-6:
			var lean: float = minf(speed / (float(wake.u) + float(wake.w)), 1.0) * distance / speed
			centre_1 -= velocity[1] * lean
			centre_2 += velocity[2] * lean * float(slipstream.vertical_drift)
		var rel_0: float = piece_root[0] - centre_0
		var rel_1: float = piece_root[1] - centre_1
		var rel_2: float = piece_root[2] - centre_2
		var along: float = rel_0 * direction[0] + rel_1 * direction[1] + rel_2 * direction[2]
		var perp_0: float = rel_0 - direction[0] * along
		var perp_1: float = rel_1 - direction[1] * along
		var perp_2: float = rel_2 - direction[2] * along
		var perpendicular_squared: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
		var inner_radius: float = float(wake.rs) * (1.0 - float(slipstream.edge_fraction))
		var outer_radius: float = float(wake.rs) * (1.0 + float(slipstream.edge_fraction))
		var profile: PackedFloat64Array = piece.profile
		core_crossed = core_crossed or _profile_crosses_radius(profile, along, perpendicular_squared, float(wake.core))
		inner_crossed = inner_crossed or _profile_crosses_radius(profile, along, perpendicular_squared, inner_radius)
		outer_crossed = outer_crossed or _profile_crosses_radius(profile, along, perpendicular_squared, outer_radius)
	return {core = core_crossed, inner = inner_crossed, outer = outer_crossed}


func _profile_crosses_radius(profile: PackedFloat64Array, along: float, perpendicular_squared: float,
		radius: float) -> bool:
	for interval in range(0, profile.size(), 4):
		var start: float = profile[interval]
		var end: float = profile[interval + 1]
		var at_start: float = M.sqrt_(perpendicular_squared + (start + along) * (start + along))
		var at_end: float = M.sqrt_(perpendicular_squared + (end + along) * (end + along))
		var maximum: float = maxf(at_start, at_end)
		var minimum: float = M.sqrt_(perpendicular_squared) if -along >= start and -along <= end else minf(at_start, at_end)
		if radius >= minimum and radius <= maximum:
			return true
	return false


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])
