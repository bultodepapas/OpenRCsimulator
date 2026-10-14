extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const GroundStart := preload("res://physics/rotorcraft/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundContact := preload("res://physics/ground_contact.gd")
const Skids := preload("res://physics/rotorcraft/skid_contact.gd")

const TICK := 1.0 / 240.0
const BRISTLE_STIFFNESS_PROXY_N_M := 10000.0

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	var aircraft: Dictionary = RotorcraftData.load_file("res://data/aircraft/xcell_60_research.json")
	_check("pad and aircraft inputs load", bool(loaded_field.get("ok", false)) and bool(aircraft.get("ok", false)))
	if not bool(loaded_field.get("ok", false)) or not bool(aircraft.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = loaded_field.field
	var start: Dictionary = GroundStart.resolve(field, aircraft)
	_check("flat pad resolves before friction tests", bool(start.get("ok", false)), str(start.get("reason", "")))
	if not bool(start.get("ok", false)):
		quit(1)
		return
	var table: Dictionary = GroundSurfaces.load_table()
	var built: Dictionary = GroundSurfaces.build(table.table, field)
	var surfaces: PackedFloat64Array = built.rects
	var skids: Dictionary = aircraft.skids
	var points: PackedFloat64Array = skids.points_body_frd_m
	var state: PackedFloat64Array = start.state.duplicate()
	_set_yaw_zero(state)
	var zero := PackedFloat64Array()
	zero.resize(8)
	var rest: Dictionary = Skids.evaluate(state, skids, surfaces, true, zero)
	_check("zero bristles hold the balanced rest without tangential creep",
		bool(rest.get("ok", false)) and rest.bristle_derivative.size() == 8
		and rest.contact_count == 4 and absf(rest.loads[0]) < 1.0e-8
		and absf(rest.loads[1]) < 1.0e-8 and absf(rest.loads[5]) < 1.0e-8
		and _max_abs(rest.bristle_derivative) == 0.0,
		str(rest.get("loads", PackedFloat64Array())))
	_check("legacy airborne calls preserve old result shape",
		not Skids.evaluate(state, skids, surfaces).has("bristle_derivative"))

	var light_preload := PackedFloat64Array()
	light_preload.resize(8)
	for index: int in 4:
		light_preload[index * 2] = 0.00005
		light_preload[index * 2 + 1] = -0.000025
	var static_result: Dictionary = Skids.evaluate(state, skids, surfaces, true, light_preload)
	_check("sub-limit stored strain supports static horizontal load with no creep",
		static_result.contact_count == 4 and _max_abs(static_result.bristle_derivative) == 0.0
		and absf(static_result.bristle_force_world_n[0] + 0.5) < 1.0e-9
		and absf(static_result.bristle_force_world_n[1] - 0.25) < 1.0e-9,
		str(static_result.bristle_force_world_n))

	var pad_surface: int = GroundContact.surface_at(surfaces, state[0], state[1])
	var friction_mu: float = float(skids.friction) * surfaces[pad_surface + 4]
	var expected_yaw_limit: float = 0.0
	var max_yaw_bristles := PackedFloat64Array()
	max_yaw_bristles.resize(8)
	for index: int in 4:
		var north_arm: float = points[index * 3]
		var east_arm: float = points[index * 3 + 1]
		var radius: float = sqrt(north_arm * north_arm + east_arm * east_arm)
		var capacity: float = friction_mu * static_result.normal_forces_n[index]
		expected_yaw_limit += capacity * radius
		var force_north: float = -east_arm / radius * capacity
		var force_east: float = north_arm / radius * capacity
		max_yaw_bristles[index * 2] = -force_north / BRISTLE_STIFFNESS_PROXY_N_M
		max_yaw_bristles[index * 2 + 1] = -force_east / BRISTLE_STIFFNESS_PROXY_N_M
	var yaw_bound: Dictionary = Skids.evaluate(state, skids, surfaces, true, max_yaw_bristles)
	_check("static yaw torque matches the four skid friction-circle bound without retuning",
		absf(absf(yaw_bound.loads[5]) - expected_yaw_limit) < 1.0e-7
		and absf(expected_yaw_limit - 3.6533) < 0.002,
		"actual=%s expected=%s" % [str(yaw_bound.loads[5]), str(expected_yaw_limit)])
	_check("every skid tangent force stays within mu times its normal load",
		_forces_within_caps(yaw_bound.bristle_force_world_n, yaw_bound.normal_forces_n, friction_mu))

	var moving: PackedFloat64Array = state.duplicate()
	moving[3] = 0.1
	var moving_bristles := PackedFloat64Array()
	moving_bristles.resize(8)
	for index: int in 4:
		moving_bristles[index * 2] = 0.0002
		moving_bristles[index * 2 + 1] = -0.0001
	var moving_result: Dictionary = Skids.evaluate(moving, skids, surfaces, true, moving_bristles)
	_check("Dahl force and elastic-energy rates are passive for four skid contacts",
		_is_passive(moving_bristles, moving_result, 0.1),
		"power+stored-energy rate=%s W" % str(_power_plus_energy(moving_bristles, moving_result, 0.1)))
	_check("high slip remains finite with bounded relaxation", _all_finite(moving_result.bristle_derivative))

	var altered_surface: PackedFloat64Array = surfaces.duplicate()
	altered_surface[pad_surface + 5] = 5.0
	var unqualified: PackedFloat64Array = state.duplicate()
	unqualified[2] += 0.02
	var decay_input := PackedFloat64Array()
	decay_input.resize(8)
	for index: int in 8:
		decay_input[index] = 0.0001 * float(index + 1)
	var legacy_contact: Dictionary = Skids.evaluate(unqualified, skids, altered_surface, true, decay_input)
	_check("non-rotorpad contact uses legacy friction and dissipates bristle memory",
		legacy_contact.contact_count == 4 and _all_finite(legacy_contact.bristle_derivative)
		and _max_abs(legacy_contact.bristle_force_world_n) == 0.0
		and _is_decay(legacy_contact.bristle_derivative, decay_input),
		str(legacy_contact.bristle_derivative))

	var airborne: PackedFloat64Array = state.duplicate()
	airborne[2] = -5.0
	var released: Dictionary = Skids.evaluate(airborne, skids, surfaces, true, decay_input)
	_check("loss of normal contact gives no adhesive force and finite memory decay",
		_max_abs(released.loads) == 0.0 and _max_abs(released.bristle_force_world_n) == 0.0
		and _is_decay(released.bristle_derivative, decay_input),
		str(released.bristle_derivative))
	_check("malformed seven-value contact memory fails closed",
		not bool(Skids.evaluate(state, skids, surfaces, false, PackedFloat64Array([0, 0, 0, 0, 0, 0, 0])).get("ok", false)))

	var high_slip: PackedFloat64Array = moving.duplicate()
	high_slip[3] = 1.0
	var initial_high := PackedFloat64Array()
	initial_high.resize(8)
	for index: int in 4:
		initial_high[index * 2] = 0.0002
	var high_result: Dictionary = Skids.evaluate(high_slip, skids, surfaces, true, initial_high)
	_check("one metre per second slip has finite derivative and bounded contact force",
		_all_finite(high_result.bristle_derivative)
		and _forces_within_caps(high_result.bristle_force_world_n, high_result.normal_forces_n, friction_mu),
		str(high_result.bristle_derivative))
	var z240: PackedFloat64Array = _integrate_bristles(initial_high, high_slip, skids, surfaces, TICK, 24)
	var z480: PackedFloat64Array = _integrate_bristles(initial_high, high_slip, skids, surfaces, TICK / 2.0, 48)
	var z960: PackedFloat64Array = _integrate_bristles(initial_high, high_slip, skids, surfaces, TICK / 4.0, 96)
	var high_error_240: float = _distance(z240, z960)
	var high_error_480: float = _distance(z480, z960)
	_check("high-slip bristle RK4 solution converges at 240/480/960 Hz",
		high_error_480 < high_error_240 and high_error_480 < 1.0e-8,
		"errors=%s,%s" % [str(high_error_240), str(high_error_480)])

	var decay240: PackedFloat64Array = _integrate_bristles(decay_input, airborne, skids, surfaces, TICK, 240)
	var decay480: PackedFloat64Array = _integrate_bristles(decay_input, airborne, skids, surfaces, TICK / 2.0, 480)
	var decay960: PackedFloat64Array = _integrate_bristles(decay_input, airborne, skids, surfaces, TICK / 4.0, 960)
	var decay_error_240: float = _distance(decay240, decay960)
	var decay_error_480: float = _distance(decay480, decay960)
	_check("unloaded 0.2 s memory decay converges at 240/480/960 Hz",
		decay_error_480 < decay_error_240 and decay_error_480 < 1.0e-8,
		"errors=%s,%s" % [str(decay_error_240), str(decay_error_480)])

	print("estimated static yaw capacity N·m=", expected_yaw_limit)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _set_yaw_zero(state: PackedFloat64Array) -> void:
	state[6] = 1.0
	state[7] = 0.0
	state[8] = 0.0
	state[9] = 0.0


func _forces_within_caps(forces: PackedFloat64Array, normal: PackedFloat64Array, mu: float) -> bool:
	if forces.size() != 8 or normal.size() != 4:
		return false
	for index: int in 4:
		var magnitude: float = sqrt(forces[index * 2] * forces[index * 2]
			+ forces[index * 2 + 1] * forces[index * 2 + 1])
		if not is_finite(magnitude) or magnitude > mu * normal[index] + 1.0e-8:
			return false
	return true


func _power_plus_energy(bristles: PackedFloat64Array, result: Dictionary, north_speed: float) -> float:
	var total: float = 0.0
	var derivative: PackedFloat64Array = result.bristle_derivative
	var forces: PackedFloat64Array = result.bristle_force_world_n
	for index: int in 4:
		total += forces[index * 2] * north_speed + forces[index * 2 + 1] * 0.0
		total += BRISTLE_STIFFNESS_PROXY_N_M * (bristles[index * 2] * derivative[index * 2]
			+ bristles[index * 2 + 1] * derivative[index * 2 + 1])
	return total


func _is_passive(bristles: PackedFloat64Array, result: Dictionary, north_speed: float) -> bool:
	return bool(result.get("ok", false)) and _power_plus_energy(bristles, result, north_speed) <= 1.0e-8


func _is_decay(derivative: PackedFloat64Array, bristles: PackedFloat64Array) -> bool:
	if derivative.size() != 8 or bristles.size() != 8:
		return false
	for index: int in 8:
		if absf(derivative[index] + bristles[index] / 0.2) > 1.0e-12:
			return false
	return true


func _integrate_bristles(initial: PackedFloat64Array, state: PackedFloat64Array, skids: Dictionary,
		surfaces: PackedFloat64Array, dt: float, steps: int) -> PackedFloat64Array:
	var z: PackedFloat64Array = initial.duplicate()
	for _step: int in steps:
		var k1: PackedFloat64Array = _derivative(state, skids, surfaces, z)
		var k2: PackedFloat64Array = _derivative(state, skids, surfaces, _offset(z, k1, dt * 0.5))
		var k3: PackedFloat64Array = _derivative(state, skids, surfaces, _offset(z, k2, dt * 0.5))
		var k4: PackedFloat64Array = _derivative(state, skids, surfaces, _offset(z, k3, dt))
		for index: int in 8:
			z[index] += dt / 6.0 * (k1[index] + 2.0 * k2[index] + 2.0 * k3[index] + k4[index])
	return z


func _derivative(state: PackedFloat64Array, skids: Dictionary, surfaces: PackedFloat64Array,
		bristles: PackedFloat64Array) -> PackedFloat64Array:
	var result: Dictionary = Skids.evaluate(state, skids, surfaces, false, bristles)
	return result.get("bristle_derivative", PackedFloat64Array())


func _offset(value: PackedFloat64Array, derivative: PackedFloat64Array, scale: float) -> PackedFloat64Array:
	var output: PackedFloat64Array = value.duplicate()
	for index: int in output.size():
		output[index] += scale * derivative[index]
	return output


func _distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var squared: float = 0.0
	for index: int in min(a.size(), b.size()):
		var delta: float = a[index] - b[index]
		squared += delta * delta
	return sqrt(squared)


func _max_abs(values: PackedFloat64Array) -> float:
	var maximum: float = 0.0
	for value: float in values:
		maximum = maxf(maximum, absf(value))
	return maximum


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
