extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const RHO_REFERENCE := 1.225
const ORACLE_TOL := 3.0e-9
const CASES: Array[Dictionary] = [
	{"label": "55AX 12x7", "path": "res://data/aircraft/stik_glow_55ax_2t.json", "family": "glow_2t", "k": 0.06},
	{"label": "55AX 13x6", "path": "res://data/aircraft/stik_glow_55ax_2t_apc_13x6.json", "family": "glow_2t", "k": 0.06},
	{"label": "FS64V 14x6", "path": "res://data/aircraft/stik_glow_fs64v_4t.json", "family": "glow_4t", "k": 0.075},
	{"label": "FS64V 13x6", "path": "res://data/aircraft/stik_glow_fs64v_4t_apc_13x6.json", "family": "glow_4t", "k": 0.075},
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	for item: Dictionary in CASES:
		_test_installation(item)
	_test_legacy_four_stroke_rejection()
	_test_nonpowered_domains()
	_test_overflow_rejection()
	print("glow propeller momentum: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_installation(item: Dictionary) -> void:
	var loaded: Dictionary = AircraftData.load_file(str(item.path))
	_check("%s aircraft loads" % item.label, loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var model: Dictionary = loaded.model
	var install: Dictionary = model.propulsion.glow
	var prop: Dictionary = install.propeller
	_check("%s retains explicit family" % item.label, install.profile.family == item.family)
	_check("%s uses the audited section-loss coefficient" % item.label,
		absf(float(prop.induced_drag) - float(item.k)) <= 1.0e-12,
		"K=%s" % prop.induced_drag)
	var rpm_cap: float = minf(float(model.propulsion.max_rpm),
		minf(float(install.profile.operation.max_rpm), float(prop.max_rpm)))
	_check("%s RPM envelope is nonempty" % item.label, is_finite(rpm_cap) and rpm_cap > 0.0)
	if rpm_cap <= 0.0:
		return
	var zero_u: float = _first_zero_u(prop, rpm_cap, RHO_REFERENCE)
	_check("%s has finite positive-thrust forward range" % item.label,
		is_finite(zero_u) and zero_u > 0.0, "V/(omega R) zero=%s" % zero_u)
	if not is_finite(zero_u) or zero_u <= 0.0:
		return
	var radius: float = float(prop.diameter_m) * 0.5
	var omega: float = rpm_cap * TAU / 60.0
	var static_oracle: Dictionary = _oracle(prop, rpm_cap, 0.0, RHO_REFERENCE)
	var disk_area: float = PI * float(prop.diameter_m) * float(prop.diameter_m) / 4.0
	var static_shortcut: float = pow(float(static_oracle.thrust_n), 1.5) / sqrt(2.0 * RHO_REFERENCE * disk_area)
	_check("%s static bound reduces to T^1.5/sqrt(2 rho A)" % item.label,
		float(static_oracle.thrust_n) > 0.0 and _near(float(static_oracle.ideal_power_w), static_shortcut))
	var matched_oracle: bool = true
	var accepted_forward: bool = true
	var passive: bool = true
	var min_ratio: float = INF
	var sample_count: int = 0
	for rpm_fraction: float in [0.25, 0.5, 0.75, 1.0]:
		var rpm: float = rpm_cap * rpm_fraction
		var sample_omega: float = rpm * TAU / 60.0
		for rho: float in [0.8, 1.225, 1.4]:
			for flow_fraction: float in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.97, 0.99, 0.999]:
				var u: float = zero_u * flow_fraction
				var axial_speed: float = u * sample_omega * radius
				var expected: Dictionary = _oracle(prop, rpm, axial_speed, rho)
				var actual: Dictionary = Blade.evaluate(rpm, axial_speed, rho, prop)
				sample_count += 1
				if not actual.get("ok", false):
					accepted_forward = false
					matched_oracle = false
					continue
				matched_oracle = matched_oracle and _near(float(actual.thrust_n), float(expected.thrust_n))
				matched_oracle = matched_oracle and _near(float(actual.torque_nm), float(expected.torque_nm))
				matched_oracle = matched_oracle and _near(float(actual.shaft_power_w), float(expected.shaft_power_w))
				matched_oracle = matched_oracle and _near(float(actual.thrust_power_w), float(expected.thrust_power_w))
				matched_oracle = matched_oracle and _near(float(actual.dissipation_w), float(expected.dissipation_w))
				passive = passive and _passivity(actual)
				if float(expected.thrust_n) > 0.0:
					var ratio: float = float(expected.shaft_power_w) / float(expected.ideal_power_w)
					min_ratio = minf(min_ratio, ratio)
					accepted_forward = accepted_forward and ratio >= 1.05 - 1.0e-9
	_check("%s matches independent 12-annulus oracle (%d points)" % [item.label, sample_count], matched_oracle)
	_check("%s preserves nonnegative section dissipation/passivity" % item.label, passive)
	_check("%s accepts all forward samples meeting the independent bound" % item.label, accepted_forward)
	_check("%s sampled forward-flow margin >= 1.05" % item.label, min_ratio >= 1.05,
		"minimum Pshaft/Pideal=%0.6f" % min_ratio)
	var beyond: float = zero_u * 1.01 * omega * radius
	var beyond_oracle: Dictionary = _oracle(prop, rpm_cap, beyond, RHO_REFERENCE)
	var beyond_result: Dictionary = Blade.evaluate(rpm_cap, beyond, RHO_REFERENCE, prop)
	_check("%s does not apply forward-thrust bound past zero thrust" % item.label,
		float(beyond_oracle.thrust_n) <= 0.0 and beyond_result.get("ok", false),
		"T=%s N" % beyond_oracle.thrust_n)


func _test_legacy_four_stroke_rejection() -> void:
	for path: String in ["res://data/aircraft/stik_glow_fs64v_4t.json",
			"res://data/aircraft/stik_glow_fs64v_4t_apc_13x6.json"]:
		var loaded: Dictionary = AircraftData.load_file(path)
		if not loaded.get("ok", false):
			_check("prior-K fixture loads for rejection test", false, str(loaded.get("errors", [])))
			continue
		var model: Dictionary = loaded.model
		var install: Dictionary = model.propulsion.glow
		var old_prop: Dictionary = install.propeller.duplicate(true)
		old_prop.induced_drag = 0.06
		var rpm: float = minf(float(model.propulsion.max_rpm),
			minf(float(install.profile.operation.max_rpm), float(old_prop.max_rpm)))
		var old_point: Dictionary = Blade.evaluate(rpm, 0.0, RHO_REFERENCE, old_prop)
		_check("previous FS64V K=0.06 static point is refused",
			not old_point.get("ok", false)
			and old_point.get("message", "") == "Forward thrust requires more power than the shaft supplies",
			str(old_point.get("message", "")))


func _test_nonpowered_domains() -> void:
	for item: Dictionary in CASES:
		var loaded: Dictionary = AircraftData.load_file(str(item.path))
		if not loaded.get("ok", false):
			continue
		var prop: Dictionary = loaded.model.propulsion.glow.propeller
		var rest: Dictionary = Blade.evaluate(0.0, 0.0, RHO_REFERENCE, prop)
		_check("%s rest remains a finite zero-power state" % item.label,
			rest.get("ok", false) and float(rest.shaft_power_w) == 0.0
			and float(rest.thrust_power_w) == 0.0 and float(rest.dissipation_w) == 0.0)
		var stopped_flow: Dictionary = Blade.evaluate(0.0, 30.0, RHO_REFERENCE, prop)
		_check("%s stopped propeller in forward flow remains valid" % item.label,
			stopped_flow.get("ok", false) and _passivity(stopped_flow))
		var windmill: Dictionary = Blade.evaluate(600.0, 30.0, RHO_REFERENCE, prop)
		_check("%s forward-flow windmilling remains valid and extracts shaft power" % item.label,
			windmill.get("ok", false) and float(windmill.thrust_n) < 0.0
			and float(windmill.shaft_power_w) < 0.0 and _passivity(windmill))
		var reverse: Dictionary = Blade.evaluate(6000.0, -12.0, RHO_REFERENCE, prop)
		_check("%s reverse inflow remains outside the forward bound" % item.label,
			reverse.get("ok", false) and _passivity(reverse))


func _test_overflow_rejection() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_fs64v_4t.json")
	if not loaded.get("ok", false):
		_check("overflow fixture loads", false, str(loaded.get("errors", [])))
		return
	var prop: Dictionary = loaded.model.propulsion.glow.propeller
	var result: Dictionary = Blade.evaluate(1.0e308, 0.0, RHO_REFERENCE, prop)
	_check("finite inputs that overflow angular speed are rejected", not result.get("ok", false))


func _oracle(prop: Dictionary, rpm: float, axial_speed: float, rho: float) -> Dictionary:
	var radius: float = float(prop.diameter_m) * 0.5
	var omega: float = rpm * TAU / 60.0
	var dr: float = radius * 0.8 / 12.0
	var thrust: float = 0.0
	var torque: float = 0.0
	var dissipation: float = 0.0
	for section: int in 12:
		var r: float = radius * 0.2 + (float(section) + 0.5) * dr
		var tangential: float = omega * r
		var speed_sq: float = tangential * tangential + axial_speed * axial_speed
		if speed_sq == 0.0:
			continue
		var speed: float = sqrt(speed_sq)
		var inflow_angle: float = atan2(axial_speed, tangential)
		var pitch_angle: float = atan2(float(prop.pitch_m), TAU * r)
		var angle_of_attack: float = pitch_angle - inflow_angle
		var lift_coefficient: float = clampf(float(prop.lift_slope) * sin(2.0 * angle_of_attack) / 2.0,
			-1.25, 1.25)
		var drag_coefficient: float = float(prop.cd0) + float(prop.induced_drag) * lift_coefficient * lift_coefficient \
			+ 1.2 * sin(angle_of_attack) * sin(angle_of_attack)
		var pressure_area: float = 0.5 * rho * speed_sq * float(prop.chord_m) * dr * float(prop.blades)
		var lift: float = pressure_area * lift_coefficient
		var drag: float = pressure_area * drag_coefficient
		thrust += (lift * tangential - drag * axial_speed) / speed
		torque += (lift * axial_speed + drag * tangential) * r / speed
		dissipation += drag * speed
	var shaft_power: float = torque * omega
	var thrust_power: float = thrust * axial_speed
	var ideal_power: float = 0.0
	if thrust > 0.0 and axial_speed >= 0.0:
		var disk_area: float = PI * float(prop.diameter_m) * float(prop.diameter_m) / 4.0
		ideal_power = 0.5 * thrust * (axial_speed + sqrt(axial_speed * axial_speed + 2.0 * thrust / (rho * disk_area)))
	return {thrust_n = thrust, torque_nm = torque, shaft_power_w = shaft_power,
		thrust_power_w = thrust_power, dissipation_w = dissipation, ideal_power_w = ideal_power}


func _first_zero_u(prop: Dictionary, rpm: float, rho: float) -> float:
	var lo: float = 0.0
	var hi: float = 0.25
	for _bracket: int in 20:
		if float(_oracle_u(prop, rpm, hi, rho).thrust_n) <= 0.0:
			break
		hi *= 2.0
	if float(_oracle_u(prop, rpm, hi, rho).thrust_n) > 0.0:
		return NAN
	for _iteration: int in 64:
		var mid: float = 0.5 * (lo + hi)
		if float(_oracle_u(prop, rpm, mid, rho).thrust_n) > 0.0:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


func _oracle_u(prop: Dictionary, rpm: float, u: float, rho: float) -> Dictionary:
	var omega: float = rpm * TAU / 60.0
	var axial_speed: float = u * omega * float(prop.diameter_m) * 0.5
	return _oracle(prop, rpm, axial_speed, rho)


func _passivity(result: Dictionary) -> bool:
	var shaft_minus_thrust: float = float(result.shaft_power_w) - float(result.thrust_power_w)
	return float(result.dissipation_w) >= 0.0 and _near(shaft_minus_thrust, float(result.dissipation_w))


func _near(actual: float, expected: float) -> bool:
	return is_finite(actual) and is_finite(expected) \
		and absf(actual - expected) <= ORACLE_TOL * maxf(1.0, maxf(absf(actual), absf(expected)))


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s%s" % ["ok   " if condition else "FAIL ", label,
		"  " + detail if not detail.is_empty() else ""])
	if not condition:
		_failures += 1
