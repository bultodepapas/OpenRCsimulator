extends SceneTree

const Gear := preload("res://physics/retractable_gear.gd")
const Math := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var state := PackedFloat64Array()
	state.resize(RB.SIZE)
	state[RB.ATT] = 1.0
	state[RB.RATE] = 0.7
	state[RB.RATE + 1] = -0.4
	state[RB.RATE + 2] = 0.9
	var air := PackedFloat64Array([4.0, -1.5, 0.8])
	var extension := 0.7
	var density := 1.225
	var gear := {"retraction": {
		"drag_center": PackedFloat64Array([0.8, -0.4, 0.3]),
		"drag_area": 0.05,
	}}
	var gradient := PackedFloat64Array([
		0.25, -0.5, 0.0,
		0.0, 0.5, 0.0,
		0.5, 0.0, 1.0,
	])
	var delta := _linear_gradient_delta(gradient, gear.retraction.drag_center)

	var actual: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density, delta)
	var expected := _analytic_loads(state, air, delta, gear, extension, density)
	_check("linear-gradient gear sample adds local wind then one body-rate term", _near_array(actual, expected, 2e-14))
	if actual.size() == 6:
		var total_flow := PackedFloat64Array([4.64, -1.19, 1.54])
		var force_dot_flow: float = actual[0] * total_flow[0] + actual[1] * total_flow[1] + actual[2] * total_flow[2]
		var speed: float = sqrt(total_flow[0] * total_flow[0] + total_flow[1] * total_flow[1] + total_flow[2] * total_flow[2])
		var expected_work: float = -0.5 * density * gear.retraction.drag_area * extension * speed * speed * speed
		_check("spatial gear drag opposes local flow", force_dot_flow < 0.0 and _near(force_dot_flow, expected_work, 2e-14))
	else:
		_check("spatial gear drag opposes local flow", false)

	var legacy: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density)
	var explicit_empty: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density, PackedFloat64Array())
	var zero_delta: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density,
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var old_formula := _legacy_loads(state, air, gear, extension, density)
	_check("empty spatial delta preserves legacy bytes", legacy.to_byte_array() == explicit_empty.to_byte_array()
		and legacy.to_byte_array() == old_formula.to_byte_array())
	_check("explicit zero spatial delta preserves legacy bytes", legacy.to_byte_array() == zero_delta.to_byte_array())

	var stowed: PackedFloat64Array = Gear.drag_loads(state, air, gear, 0.0, density, delta)
	_check("stowed gear remains exactly zero drag", stowed.is_empty())

	var bad_shape: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density,
		PackedFloat64Array([0.1, 0.2]))
	var bad_value: PackedFloat64Array = Gear.drag_loads(state, air, gear, extension, density,
		PackedFloat64Array([0.1, NAN, 0.3]))
	var overflow: PackedFloat64Array = Gear.drag_loads(state, PackedFloat64Array([1.0e308, 0.0, 0.0]), gear,
		extension, density, PackedFloat64Array([1.0e308, 0.0, 0.0]))
	_check("malformed local delta refuses with a NaN load", bad_shape.size() == 1 and is_nan(bad_shape[0]))
	_check("nonfinite local delta refuses with a NaN load", bad_value.size() == 1 and is_nan(bad_value[0]))
	_check("overflow while adding local delta refuses with a NaN load", overflow.size() == 1 and is_nan(overflow[0]))

	print("spatial gear drag: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _analytic_loads(state: PackedFloat64Array, air: PackedFloat64Array, delta: PackedFloat64Array,
		gear: Dictionary, extension: float, density: float) -> PackedFloat64Array:
	var arm: PackedFloat64Array = gear.retraction.drag_center
	var flow := PackedFloat64Array([
		air[0] + delta[0] + state[RB.RATE + 1] * arm[2] - state[RB.RATE + 2] * arm[1],
		air[1] + delta[1] + state[RB.RATE + 2] * arm[0] - state[RB.RATE] * arm[2],
		air[2] + delta[2] + state[RB.RATE] * arm[1] - state[RB.RATE + 1] * arm[0],
	])
	var speed := sqrt(flow[0] * flow[0] + flow[1] * flow[1] + flow[2] * flow[2])
	var scale: float = -0.5 * density * gear.retraction.drag_area * extension * speed
	var force := PackedFloat64Array([scale * flow[0], scale * flow[1], scale * flow[2]])
	return PackedFloat64Array([
		force[0], force[1], force[2],
		arm[1] * force[2] - arm[2] * force[1],
		arm[2] * force[0] - arm[0] * force[2],
		arm[0] * force[1] - arm[1] * force[0],
	])


func _linear_gradient_delta(gradient: PackedFloat64Array, point: PackedFloat64Array) -> PackedFloat64Array:
	var delta := PackedFloat64Array()
	for row in 3:
		delta.append(gradient[row * 3] * point[0] + gradient[row * 3 + 1] * point[1]
			+ gradient[row * 3 + 2] * point[2])
	return delta


func _legacy_loads(state: PackedFloat64Array, air: PackedFloat64Array, gear: Dictionary,
		extension: float, density: float) -> PackedFloat64Array:
	var arm: PackedFloat64Array = gear.retraction.drag_center
	var rates := PackedFloat64Array([state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2]])
	var velocity: PackedFloat64Array = Math.add(air, Math.cross(rates, arm))
	var speed: float = Math.norm(velocity)
	var force: PackedFloat64Array = Math.scale(velocity, -0.5 * density * gear.retraction.drag_area * extension * speed)
	var moment: PackedFloat64Array = Math.cross(arm, force)
	force.append_array(moment)
	return force


func _near_array(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if not _near(actual[index], expected[index], tolerance):
			return false
	return true


func _near(actual: float, expected: float, tolerance: float) -> bool:
	return is_finite(actual) and is_finite(expected) \
		and absf(actual - expected) <= tolerance * maxf(1.0, maxf(absf(actual), absf(expected)))
