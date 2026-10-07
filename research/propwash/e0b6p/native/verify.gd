# Research verification for the whole-load E0b6p native kernel. Run only in a disposable app copy.
extends SceneTree

const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const Oracle = preload("res://physics/slipstream.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Aero = preload("res://physics/aero.gd")
const RB = preload("res://physics/rigid_body.gd")

const SEED: int = 2601007
const RANDOM_CASES: int = 256
const MODEL_COUNT: int = 16
const ABSOLUTE_TOLERANCE: float = 1.0e-10
const RELATIVE_TOLERANCE: float = 1.0e-10

var _checks: int = 0
var _failures: int = 0
var _compared: int = 0
var _exact: int = 0
var _worst_absolute: float = 0.0
var _worst_tolerance_ratio: float = 0.0
var _worst_detail: String = "none"
var _worst_ratio_detail: String = "none"
var _coverage: Dictionary = {
	"random_smooth": 0,
	"transported_zero": 0,
	"transported_nonzero": 0,
	"rpm_stopped": 0,
	"reverse_partial": 0,
	"reverse_cutoff": 0,
	"zero_swirl": 0,
	"instantaneous_downwash": 0,
	"held_downwash": 0,
	"classic_tail": 0,
	"free_slope_tail": 0,
}


func _initialize() -> void:
	Adapter.reset_route_counts()
	_check("native GDExtension is available", Adapter.available())
	if _failures > 0:
		_finish()
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var models: Array[Dictionary] = _build_valid_models(rng)
	_check("all randomized smooth fixture models validate", models.size() == MODEL_COUNT,
		"built %d of %d" % [models.size(), MODEL_COUNT])
	if models.size() != MODEL_COUNT:
		_finish()
		return
	for case_index: int in RANDOM_CASES:
		_compare_random_case(case_index, models[case_index % MODEL_COUNT], rng)
	_compare_boundaries(models[0])
	_check_legacy_fallback()
	_check_malformed_refusal(models[0])
	_check("randomized smooth path reached native loads", int(Adapter.route_counts.native) > 0
		and int(Adapter.route_counts.kernel_calls) > 0,
		str(Adapter.route_counts))
	_check("non-smooth path reached the GDScript fallback", int(Adapter.route_counts.legacy) > 0,
		str(Adapter.route_counts))
	_check("zero and nonzero transported wash cases were exercised",
		int(_coverage.transported_zero) > 0 and int(_coverage.transported_nonzero) > 0, str(_coverage))
	_check("both held and instantaneous downwash and both tail laws were exercised",
		int(_coverage.instantaneous_downwash) > 0 and int(_coverage.held_downwash) > 0
		and int(_coverage.classic_tail) > 0 and int(_coverage.free_slope_tail) > 0, str(_coverage))
	_check("all whole-load comparisons are finite and within abs+rel 1e-10", _worst_tolerance_ratio <= 1.0,
		"compared=%d exact=%d worst_abs=%s worst_ratio=%s (%s)" % [
			_compared, _exact, String.num_scientific(_worst_absolute),
			String.num_scientific(_worst_tolerance_ratio), _worst_ratio_detail])
	_finish()


func _build_valid_models(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var models: Array[Dictionary] = []
	for model_index: int in MODEL_COUNT:
		var raw: Dictionary = Fixture.combined_raw()
		var propeller: Dictionary = raw.propulsion.propeller
		var smooth: Dictionary = propeller.slipstream
		var centred_geometry: bool = model_index % 4 == 0
		if model_index % 4 == 1:
			raw.aero.surfaces.horizontal.erase("downwash_gradient")
		smooth.edge_fraction.value = rng.randf_range(0.035, 0.44)
		smooth.swirl_factor.value = rng.randf_range(0.18, 0.95)
		smooth.vertical_drift.value = rng.randf_range(0.05, 0.95)
		smooth.hub.value[0] = rng.randf_range(-0.39, -0.20)
		smooth.hub.value[1] = 0.0 if centred_geometry else rng.randf_range(-0.018, 0.018)
		smooth.hub.value[2] = 0.0 if centred_geometry else rng.randf_range(-0.018, 0.018)
		propeller.diameter.value = rng.randf_range(0.22, 0.48)
		for piece: Dictionary in smooth.pieces:
			var span_scale: float = rng.randf_range(0.86, 1.14)
			var chord_scale: float = rng.randf_range(0.88, 1.12)
			piece.span.value *= span_scale
			piece.area.value *= span_scale * chord_scale
			piece.root.value[0] += rng.randf_range(-0.025, 0.08)
			if centred_geometry:
				piece.root.value[1] = 0.0
				piece.root.value[2] = -0.04064 if piece.surface == "horizontal" else -0.02667
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
			_check("randomized fixture %d validates" % model_index, false, str(loaded.get("errors", [])))
			return []
		models.append(loaded.model)
	return models


func _compare_random_case(case_index: int, model: Dictionary, rng: RandomNumberGenerator) -> void:
	var prop: Dictionary = model.propulsion
	var rho: float = rng.randf_range(0.72, 1.42)
	var rpm: float = rng.randf_range(prop.idle_rpm, prop.max_rpm)
	var velocity: PackedFloat64Array = _case_velocity(case_index, model, rpm, rng)
	if case_index % 53 == 52:
		rpm = 0.0
	var state: PackedFloat64Array = _state(velocity)
	for axis: int in 3:
		state[RB.RATE + axis] = rng.randf_range(-1.8, 1.8)
	var controls: Dictionary = {
		elevator = rng.randf_range(-0.55, 0.55),
		rudder = rng.randf_range(-0.55, 0.55),
		aileron_left = rng.randf_range(-0.4, 0.4),
		aileron_right = rng.randf_range(-0.4, 0.4),
	}
	var downwash_cl: float = NAN if case_index % 2 == 0 else rng.randf_range(-1.1, 1.1)
	if model.surfaces.horizontal.has("free_slope"):
		if is_nan(downwash_cl):
			_coverage.instantaneous_downwash = int(_coverage.instantaneous_downwash) + 1
		else:
			_coverage.held_downwash = int(_coverage.held_downwash) + 1
		_coverage.free_slope_tail = int(_coverage.free_slope_tail) + 1
	else:
		# Also cover the native no-downwash NAN sentinel on the classic tail law.
		downwash_cl = NAN if case_index % 3 == 1 else downwash_cl
		_coverage.classic_tail = int(_coverage.classic_tail) + 1
	var transported_dv: PackedFloat64Array = PackedFloat64Array()
	var case_model: Dictionary = model
	match case_index % 16:
		2, 6, 10, 14:
			case_model = model.duplicate(true)
			case_model.propulsion.slipstream.swirl_factor = 0.0
			transported_dv.resize(prop.slipstream.pieces.size())
			transported_dv.fill(0.0)
			_coverage.transported_zero = int(_coverage.transported_zero) + 1
		3, 7, 11, 15:
			case_model = model.duplicate(true)
			case_model.propulsion.slipstream.swirl_factor = 0.0
			transported_dv.resize(prop.slipstream.pieces.size())
			for piece_index: int in transported_dv.size():
				transported_dv[piece_index] = rng.randf_range(0.05, 5.0)
			_coverage.transported_nonzero = int(_coverage.transported_nonzero) + 1
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
	_compare_loads("random smooth case %d" % case_index, state, air, controls, case_model, rpm, rho,
		downwash_cl, transported_dv)
	_coverage.random_smooth = int(_coverage.random_smooth) + 1
	if rpm < Propulsion.STOPPED_RPM:
		_coverage.rpm_stopped = int(_coverage.rpm_stopped) + 1


func _case_velocity(case_index: int, model: Dictionary, rpm: float, rng: RandomNumberGenerator) -> PackedFloat64Array:
	var slot: int = case_index % MODEL_COUNT
	if slot in [0, 4, 8, 12]:
		return PackedFloat64Array([rng.randf_range(3.0, 20.0), 0.0, 0.0])
	var velocity: PackedFloat64Array = PackedFloat64Array([
		rng.randf_range(-9.0, 28.0), rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0),
	])
	if slot in [1, 2, 3]:
		var prop: Dictionary = model.propulsion
		var vi0: float = rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
		var bounds: PackedFloat64Array = prop.slipstream.reverse_fade
		if slot == 1:
			velocity[0] = -0.5 * bounds[0] * vi0
		elif slot == 2:
			velocity[0] = -0.5 * (bounds[0] + bounds[1]) * vi0
		else:
			velocity[0] = -1.15 * bounds[1] * vi0
	return velocity


func _compare_boundaries(model_value: Dictionary) -> void:
	var model: Dictionary = model_value.duplicate(true)
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
	var velocities: Array[PackedFloat64Array] = [
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([18.0, 0.0, 0.0]),
		PackedFloat64Array([-0.15 * vi0, 0.0, 0.0]),
		PackedFloat64Array([-0.3 * vi0, 0.0, 0.0]),
	]
	var rpms: Array[float] = [0.0, Propulsion.STOPPED_RPM - 1.0e-10, Propulsion.STOPPED_RPM, prop.max_rpm]
	var deflections: Dictionary = {elevator = 0.12, rudder = -0.08, aileron_left = 0.0, aileron_right = 0.0}
	var label_index: int = 0
	for swirl: float in [0.4, 0.0]:
		slipstream.swirl_factor = swirl
		for rpm: float in rpms:
			for velocity: PackedFloat64Array in velocities:
				var state: PackedFloat64Array = _state(velocity)
				var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
				_compare_loads("edge swirl=%s rpm=%s velocity=%s" % [swirl, rpm, velocity], state, air,
					deflections, model, rpm, 1.225, NAN, PackedFloat64Array())
				if velocity[0] < 0.0 and rpm >= Propulsion.STOPPED_RPM:
					var weight: float = Oracle.reverse_weight(velocity, rpm, prop)
					if weight > 0.0 and weight < 1.0:
						_coverage.reverse_partial = int(_coverage.reverse_partial) + 1
					elif weight == 0.0:
						_coverage.reverse_cutoff = int(_coverage.reverse_cutoff) + 1
				if rpm < Propulsion.STOPPED_RPM:
					_coverage.rpm_stopped = int(_coverage.rpm_stopped) + 1
					if swirl == 0.0:
						var residual: PackedFloat64Array = PackedFloat64Array([0.25, 0.25, 0.25])
						_compare_loads("stopped transported residual %d" % label_index, state, air, deflections,
							model, rpm, 1.225, NAN, residual)
						if velocity[0] >= 0.0:
							var residual_loads: PackedFloat64Array = Adapter.loads(state, air, deflections,
								model, rpm, 1.225, NAN, residual)
							_check("stopped residual has a nonzero load %d" % label_index,
								absf(residual_loads[0]) + absf(residual_loads[1]) + absf(residual_loads[2]) > 0.0)
						label_index += 1
	_check("reverse fade onset, partial fade, and cutoff reached", int(_coverage.reverse_partial) > 0
		and int(_coverage.reverse_cutoff) > 0, str(_coverage))
	_check("stopped RPM cases reached", int(_coverage.rpm_stopped) > 0, str(_coverage))
	# Zero swirl is a separate zero-sensitivity case, including a zero transported increment.
	slipstream.swirl_factor = 0.0
	var state_zero: PackedFloat64Array = _state(PackedFloat64Array([16.0, 0.0, 0.0]))
	var air_zero: Dictionary = Air.compute(state_zero, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	var zeros: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	_compare_loads("zero swirl with transported zero", state_zero, air_zero, deflections, model,
		prop.max_rpm, 1.225, NAN, zeros)
	_coverage.transported_zero = int(_coverage.transported_zero) + 1


func _check_legacy_fallback() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_check("legacy fallback fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var model: Dictionary = loaded.model
	var state: PackedFloat64Array = _state(PackedFloat64Array([12.0, 0.0, 0.0]))
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	var controls: Dictionary = {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}
	var expected: PackedFloat64Array = Oracle.loads(state, air, controls, model, model.propulsion.max_rpm, 1.225)
	var actual: PackedFloat64Array = Adapter.loads(state, air, controls, model, model.propulsion.max_rpm, 1.225)
	_check("non-smooth aircraft output equals the GDScript fallback byte-for-byte",
		actual.to_byte_array() == expected.to_byte_array(), str(actual))


func _check_malformed_refusal(model: Dictionary) -> void:
	var state: PackedFloat64Array = _state(PackedFloat64Array([14.0, 0.0, 0.0]))
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	var prop: Dictionary = model.propulsion
	var tq_full: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, prop.max_rpm, prop, 1.225)
	var tq: PackedFloat64Array = PackedFloat64Array([tq_full[0], tq_full[1]])
	var controls: Dictionary = {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}
	var fade: float = Oracle.reverse_weight(air.v_air, prop.max_rpm, prop)
	var valid_result: Variant = Adapter.backend.call("loads", state, air.v_air, controls, model, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	_check("refusal probes start from a finite accepted native call", valid_result is PackedFloat64Array
		and valid_result.size() == 6 and _all_finite(valid_result))
	var rejected: bool = true
	var malformed_state: PackedFloat64Array = state.duplicate()
	malformed_state[RB.RATE] = NAN
	var result: Variant = Adapter.backend.call("loads", malformed_state, air.v_air, controls, model, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	var malformed_velocity: PackedFloat64Array = PackedFloat64Array([14.0, 0.0])
	result = Adapter.backend.call("loads", state, malformed_velocity, controls, model, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	var malformed_density: float = NAN
	result = Adapter.backend.call("loads", state, air.v_air, controls, model, tq,
		malformed_density, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	var malformed_model: Dictionary = model.duplicate(true)
	malformed_model.propulsion.slipstream.pieces[0].root = PackedFloat64Array([0.0, 0.0])
	result = Adapter.backend.call("loads", state, air.v_air, controls, malformed_model, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	var excessive_edge: Dictionary = model.duplicate(true)
	excessive_edge.propulsion.slipstream.edge_fraction = 0.7
	result = Adapter.backend.call("loads", state, air.v_air, controls, excessive_edge, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	var non_unit_span: Dictionary = model.duplicate(true)
	var first_piece: Dictionary = non_unit_span.propulsion.slipstream.pieces[0]
	var span_direction: PackedFloat64Array = first_piece.span_dir
	span_direction[0] = 0.25
	first_piece.span_dir = span_direction
	non_unit_span.propulsion.slipstream.pieces[0] = first_piece
	result = Adapter.backend.call("loads", state, air.v_air, controls, non_unit_span, tq,
		1.225, fade, 0.3, PackedFloat64Array())
	rejected = rejected and result is PackedFloat64Array and result.is_empty()
	_check("native kernel refuses malformed/non-finite state, velocity, density, and geometry", rejected)
	var adapter_refusal: PackedFloat64Array = Adapter.loads(malformed_state, air, controls, model,
		prop.max_rpm, 1.225)
	_check("adapter maps native refusal to six NaNs for the simulation guard",
		adapter_refusal.size() == 6 and not _all_finite(adapter_refusal), str(adapter_refusal))


func _compare_loads(label: String, state: PackedFloat64Array, air: Dictionary, controls: Dictionary,
		model: Dictionary, rpm: float, rho: float, downwash_cl: float,
		transported_dv: PackedFloat64Array) -> void:
	var expected: PackedFloat64Array = Oracle.loads(state, air, controls, model, rpm, rho,
		downwash_cl, transported_dv)
	var actual: PackedFloat64Array = Adapter.loads(state, air, controls, model, rpm, rho,
		downwash_cl, transported_dv)
	_compared += 1
	var ok: bool = expected.size() == 6 and actual.size() == 6
	var case_worst_absolute: float = 0.0
	var case_ratio: float = 0.0
	var absolute_detail: String = label
	var ratio_detail: String = label
	if not ok:
		_check(label, false, "expected six load components")
		return
	for component: int in 6:
		if not is_finite(expected[component]) or not is_finite(actual[component]):
			ok = false
			ratio_detail = "%s component=%d non-finite expected=%s actual=%s" % [
				label, component, str(expected[component]), str(actual[component])]
			continue
		var error: float = absf(actual[component] - expected[component])
		var tolerance: float = ABSOLUTE_TOLERANCE + RELATIVE_TOLERANCE * absf(expected[component])
		var ratio: float = error / tolerance
		if error > case_worst_absolute:
			case_worst_absolute = error
			absolute_detail = "%s component=%d expected=%s actual=%s abs_error=%s tolerance=%s" % [
				label, component, String.num_scientific(expected[component]),
				String.num_scientific(actual[component]), String.num_scientific(error),
				String.num_scientific(tolerance)]
		if ratio > case_ratio:
			case_ratio = ratio
			ratio_detail = "%s component=%d expected=%s actual=%s tolerance_ratio=%s" % [
				label, component, String.num_scientific(expected[component]),
				String.num_scientific(actual[component]), String.num_scientific(ratio)]
	var is_exact: bool = actual.to_byte_array() == expected.to_byte_array()
	if is_exact:
		_exact += 1
	if case_worst_absolute > _worst_absolute:
		_worst_absolute = case_worst_absolute
		_worst_detail = absolute_detail
	if case_ratio > _worst_tolerance_ratio:
		_worst_tolerance_ratio = case_ratio
		_worst_ratio_detail = ratio_detail
	_check(label, ok and case_ratio <= 1.0, ratio_detail if not ok or case_ratio > 1.0 else "")
	if float(model.propulsion.slipstream.swirl_factor) == 0.0:
		_coverage.zero_swirl = int(_coverage.zero_swirl) + 1


func _state(velocity: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		0.0, 0.0, -100.0, velocity[0], velocity[1], velocity[2],
		1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	])


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	var report: Dictionary = {
		"format": "openrc-e0b6p-native-verification v1",
		"seed": SEED,
		"random_cases": RANDOM_CASES,
		"compared_loads": _compared,
		"exact_loads": _exact,
		"checks": _checks,
		"failures": _failures,
		"absolute_tolerance": ABSOLUTE_TOLERANCE,
		"relative_tolerance": RELATIVE_TOLERANCE,
		"fixture_note": "Random geometry perturbations of a validated research fixture; no production aircraft calibration.",
		"worst_absolute_error": _worst_absolute,
		"worst_tolerance_ratio": _worst_tolerance_ratio,
		"worst_absolute_detail": _worst_detail,
		"worst_ratio_detail": _worst_ratio_detail,
		"coverage": _coverage,
		"native_routes": Adapter.route_counts,
		"godot": Engine.get_version_info().string,
	}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("verify.gd needs an output JSON path")
		_failures += 1
	else:
		var output: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
		if output == null:
			printerr("could not open verification report: ", args[0])
			_failures += 1
		else:
			report["failures"] = _failures
			output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("E0b6p native: %d checks, %d failed; %d full-load comparisons, %d exact; max ratio=%s" % [
		_checks, _failures, _compared, _exact, String.num_scientific(_worst_tolerance_ratio)])
	quit(1 if _failures > 0 else 0)
