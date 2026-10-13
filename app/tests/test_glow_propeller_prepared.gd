extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const M := preload("res://physics/math3d.gd")
const RHO := 1.225
const CASES: Array[Dictionary] = [
	{"label": "55AX 12x7", "path": "res://data/aircraft/stik_glow_55ax_2t.json"},
	{"label": "55AX 13x6", "path": "res://data/aircraft/stik_glow_55ax_2t_apc_13x6.json"},
	{"label": "FS64V 14x6", "path": "res://data/aircraft/stik_glow_fs64v_4t.json"},
	{"label": "FS64V 13x6", "path": "res://data/aircraft/stik_glow_fs64v_4t_apc_13x6.json"},
]
const OUTPUT_KEYS: Array[String] = [
	"thrust_n", "torque_nm", "shaft_power_w", "thrust_power_w", "dissipation_w",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	for item: Dictionary in CASES:
		_test_installation(item)
	_test_bad_prepare_inputs()
	_test_query_guards_and_overflow()
	_test_untyped_evaluator_rejection()
	print("glow propeller prepared: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_installation(item: Dictionary) -> void:
	var loaded: Dictionary = AircraftData.load_file(str(item.path))
	_check("%s installation loads" % item.label, loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var prop: Dictionary = loaded.model.propulsion.glow.propeller
	var baseline: Dictionary = prop.duplicate(true)
	var prepared_result: Dictionary = Blade.prepare_evaluator(prop)
	_check("%s preparation succeeds" % item.label, prepared_result.get("ok", false),
		str(prepared_result.get("message", "")))
	if not prepared_result.get("ok", false):
		return
	var evaluator: Variant = prepared_result.evaluator
	_check("%s evaluator is typed" % item.label, evaluator is Blade.PreparedEvaluator)

	var rpm_max: float = minf(float(loaded.model.propulsion.max_rpm),
		minf(float(loaded.model.propulsion.glow.profile.operation.max_rpm), float(prop.max_rpm)))
	var rpm_samples: Array[float] = [0.0, rpm_max * 0.125, rpm_max * 0.5, rpm_max]
	var inflow_samples: Array[float] = [-30.0, -7.0, 0.0, 3.0, 15.0, 40.0]
	var density_samples: Array[float] = [0.8, RHO, 1.4]
	var parity: bool = true
	var sample_count: int = 0
	for rpm: float in rpm_samples:
		for axial_speed: float in inflow_samples:
			for rho: float in density_samples:
				var old_result: Dictionary = _frozen_prepared_baseline(rpm, axial_speed, rho, baseline)
				var public_result: Dictionary = Blade.evaluate(rpm, axial_speed, rho, baseline)
				var prepared: Dictionary = Blade.evaluate_prepared(evaluator, rpm, axial_speed, rho)
				sample_count += 1
				parity = parity and _exact_result_equal(old_result, public_result)
				parity = parity and _exact_result_equal(old_result, prepared)
	_check("%s public/prepared results match the frozen pre-optimization evaluator exactly (%d samples)" % [item.label, sample_count], parity)

	# The evaluator must not retain a mutable reference to authoring data.
	var detached_input: Dictionary = baseline.duplicate(true)
	var detached_result: Dictionary = Blade.prepare_evaluator(detached_input)
	var detached_evaluator: Variant = detached_result.get("evaluator")
	var rpm: float = rpm_max * 0.5
	var before_mutation: Dictionary = Blade.evaluate_prepared(detached_evaluator, rpm, 0.0, RHO)
	detached_input.diameter_m = float(detached_input.diameter_m) * 0.7
	detached_input.pitch_m = float(detached_input.pitch_m) * 1.4
	detached_input.chord_m = float(detached_input.chord_m) * 1.3
	detached_input.lift_slope = float(detached_input.lift_slope) * 0.8
	detached_input.cd0 = float(detached_input.cd0) * 1.1
	detached_input.induced_drag = float(detached_input.induced_drag) * 1.2
	detached_input.blades = float(detached_input.blades) + 1.0
	var after_mutation: Dictionary = Blade.evaluate_prepared(detached_evaluator, rpm, 0.0, RHO)
	_check("%s evaluator is detached from later installation mutation" % item.label,
		_exact_result_equal(before_mutation, after_mutation))


func _test_bad_prepare_inputs() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_55ax_2t.json")
	if not loaded.get("ok", false):
		_check("bad-parameter fixture loads", false, str(loaded.get("errors", [])))
		return
	var original: Dictionary = loaded.model.propulsion.glow.propeller
	var malformed: Array[Dictionary] = []
	var missing: Dictionary = original.duplicate(true)
	missing.erase("chord_m")
	malformed.append(missing)
	var zero: Dictionary = original.duplicate(true)
	zero.cd0 = 0.0
	malformed.append(zero)
	var infinity: Dictionary = original.duplicate(true)
	infinity.lift_slope = INF
	malformed.append(infinity)
	var wrong_type: Dictionary = original.duplicate(true)
	wrong_type.blades = "four"
	malformed.append(wrong_type)
	for index: int in range(malformed.size()):
		var parameters: Dictionary = malformed[index]
		var prepared: Dictionary = Blade.prepare_evaluator(parameters)
		var public_result: Dictionary = Blade.evaluate(4000.0, 0.0, RHO, parameters)
		_check("malformed parameter set %d cannot prepare" % index, not prepared.get("ok", false))
		_check("malformed parameter set %d remains rejected by public path" % index,
			not public_result.get("ok", false) and not public_result.has("message"))


func _test_query_guards_and_overflow() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_fs64v_4t.json")
	if not loaded.get("ok", false):
		_check("query-guard fixture loads", false, str(loaded.get("errors", [])))
		return
	var prop: Dictionary = loaded.model.propulsion.glow.propeller
	var evaluator: Variant = Blade.prepare_evaluator(prop).evaluator
	var invalid_queries: Array[Array] = [
		[-1.0, 0.0, RHO], [INF, 0.0, RHO], [4000.0, NAN, RHO], [4000.0, 0.0, 0.0],
		[4000.0, 0.0, INF],
	]
	for index: int in range(invalid_queries.size()):
		var args: Array = invalid_queries[index]
		var public_result: Dictionary = Blade.evaluate(float(args[0]), float(args[1]), float(args[2]), prop)
		var prepared: Dictionary = Blade.evaluate_prepared(evaluator,
			float(args[0]), float(args[1]), float(args[2]))
		_check("invalid dynamic query %d rejected on both routes" % index,
			_exact_result_equal({ok = false}, public_result)
			and _exact_result_equal(public_result, prepared))
	for rpm: float in [1.0e200, 1.0e308]:
		var old_result: Dictionary = _frozen_prepared_baseline(rpm, 0.0, RHO, prop)
		var public_result: Dictionary = Blade.evaluate(rpm, 0.0, RHO, prop)
		var prepared: Dictionary = Blade.evaluate_prepared(evaluator, rpm, 0.0, RHO)
		_check("finite angular/section overflow %s preserves refusal" % rpm,
			_exact_result_equal(old_result, public_result)
			and _exact_result_equal(old_result, prepared)
			and not public_result.get("ok", false))
	var force_overflow_old: Dictionary = _frozen_prepared_baseline(4000.0, 0.0, 1.0e308, prop)
	var force_overflow_public: Dictionary = Blade.evaluate(4000.0, 0.0, 1.0e308, prop)
	var force_overflow_prepared: Dictionary = Blade.evaluate_prepared(evaluator, 4000.0, 0.0, 1.0e308)
	_check("finite force overflow preserves refusal and reason",
		_exact_result_equal(force_overflow_old, force_overflow_public)
		and _exact_result_equal(force_overflow_old, force_overflow_prepared)
		and force_overflow_public.get("message", "") == "Propeller section force overflowed")


func _test_untyped_evaluator_rejection() -> void:
	var result: Dictionary = Blade.evaluate_prepared({}, 1000.0, 0.0, RHO)
	_check("arbitrary dictionary cannot bypass public validation",
		not result.get("ok", false)
		and result.get("message", "") == "A prepared propeller evaluator is required")
	var forged: Variant = Blade.PreparedEvaluator.new({})
	var forged_result: Dictionary = Blade.evaluate_prepared(forged, 1000.0, 0.0, RHO)
	_check("direct construction from malformed parameters cannot bypass validation",
		not forged_result.get("ok", false)
		and forged_result.get("message", "") == "A prepared propeller evaluator is required")


## Frozen copy of the pre-optimization public evaluator. Keep annulus expression
## order intact so this protects the optimized path against shared-core drift.
func _frozen_prepared_baseline(rpm: float, axial_speed: float, rho: float,
		p: Dictionary) -> Dictionary:
	if not is_finite(rpm) or rpm < 0.0 or not is_finite(axial_speed) or not is_finite(rho) or rho <= 0.0:
		return {ok = false}
	for key in ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]:
		if typeof(p.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p[key])) or p[key] <= 0.0:
			return {ok = false}
	var diameter_m: float = float(p.diameter_m)
	var pitch_m: float = float(p.pitch_m)
	var chord_m: float = float(p.chord_m)
	var lift_slope: float = float(p.lift_slope)
	var cd0: float = float(p.cd0)
	var induced_drag: float = float(p.induced_drag)
	var blades: float = float(p.blades)
	var radius: float = 0.5 * diameter_m
	var omega: float = rpm * TAU / 60.0
	if not is_finite(omega):
		return {ok = false, message = "Propeller angular speed overflowed"}
	var thrust: float = 0.0
	var torque: float = 0.0
	var dissipation: float = 0.0
	var dr: float = radius * 0.8 / 12.0
	for i in 12:
		var r: float = radius * 0.2 + (i + 0.5) * dr
		var tangential: float = omega * r
		var speed_sq: float = tangential * tangential + axial_speed * axial_speed
		if not is_finite(speed_sq) or speed_sq < 0.0:
			return {ok = false, message = "Propeller section speed overflowed"}
		if speed_sq == 0.0:
			continue
		var speed: float = M.sqrt_(speed_sq)
		if not is_finite(speed) or speed <= 0.0:
			return {ok = false, message = "Propeller section speed is invalid"}
		var phi: float = M.atan2_(axial_speed, tangential)
		var beta: float = M.atan2_(pitch_m, TAU * r)
		var alpha: float = beta - phi
		var cl: float = lift_slope * M.sin_(2.0 * alpha) / 2.0
		cl = clampf(cl, -1.25, 1.25)
		var cd: float = cd0 + induced_drag * cl * cl + 1.2 * M.pow_(M.sin_(alpha), 2.0)
		var area_pressure: float = 0.5 * rho * speed_sq * chord_m * dr * blades
		var lift: float = area_pressure * cl
		var drag: float = area_pressure * cd
		if not is_finite(area_pressure) or not is_finite(lift) or not is_finite(drag):
			return {ok = false, message = "Propeller section force overflowed"}
		thrust += (lift * tangential - drag * axial_speed) / speed
		torque += (lift * axial_speed + drag * tangential) * r / speed
		dissipation += drag * speed
	var shaft_power: float = torque * omega
	var thrust_power: float = thrust * axial_speed
	if not is_finite(thrust) or not is_finite(torque) or not is_finite(dissipation) \
			or not is_finite(shaft_power) or not is_finite(thrust_power):
		return {ok = false, message = "Propeller force or power overflowed"}
	if thrust > 0.0 and axial_speed >= 0.0:
		var disk_area: float = PI * diameter_m * diameter_m / 4.0
		var disk_mass_term: float = rho * disk_area
		if not is_finite(disk_area) or disk_area <= 0.0 or not is_finite(disk_mass_term) or disk_mass_term <= 0.0:
			return {ok = false, message = "Propeller actuator-disk area overflowed"}
		var ideal_speed_sq: float = axial_speed * axial_speed + 2.0 * thrust / disk_mass_term
		if not is_finite(ideal_speed_sq) or ideal_speed_sq <= 0.0:
			return {ok = false, message = "Propeller ideal induced speed overflowed"}
		var ideal_power: float = 0.5 * thrust * (axial_speed + M.sqrt_(ideal_speed_sq))
		if not is_finite(ideal_power) or ideal_power <= 0.0:
			return {ok = false, message = "Propeller ideal actuator-disk power overflowed"}
		var power_scale: float = maxf(absf(shaft_power), ideal_power)
		if shaft_power < ideal_power - 1.0e-10 * power_scale:
			return {ok = false, message = "Forward thrust requires more power than the shaft supplies"}
	return {ok = true, thrust_n = thrust, torque_nm = torque,
		shaft_power_w = shaft_power, thrust_power_w = thrust_power,
		dissipation_w = dissipation}


func _exact_result_equal(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.get("ok", false) != actual.get("ok", false):
		return false
	if not expected.get("ok", false):
		return expected.get("message", "") == actual.get("message", "")
	for key: String in OUTPUT_KEYS:
		if not actual.has(key) or float(expected[key]) != float(actual[key]):
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s%s" % ["ok   " if condition else "FAIL ", label,
		"  " + detail if not detail.is_empty() else ""])
	if not condition:
		_failures += 1
