extends SceneTree
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Fixture = preload("res://tests/test_heli_flight.gd")
const M = preload("res://physics/math3d.gd")
var _checks := 0
var _failures := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var parameters: Dictionary = Fixture.electronics_parameters()
	# Exercise ordinary author arrays as well as packed float64 curve sources.
	parameters.curves_by_mode.normal.pitch = [-0.2, 0.1, 0.45, 0.7, 1.0]
	var prepared: Dictionary = Electronics.prepare(parameters)
	_check("fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var model: Dictionary = prepared.model
	_check("ordinary curve arrays are deeply frozen", model.curves_by_mode.normal.pitch.is_read_only())
	parameters.curves_by_mode.normal.pitch[0] = 0.8
	_check("source authoring arrays cannot change accepted curves", model.curves_by_mode.normal.pitch[0] == -0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18641
	for index: int in range(512):
		var state: PackedFloat64Array = Fixture.state_at_hover()
		var q := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.3, 1.3), rng.randf_range(-2.7, 2.7))
		for axis: int in range(4): state[6 + axis] = q[axis]
		for axis: int in range(3): state[10 + axis] = rng.randf_range(-4.0, 4.0)
		state[17] = rng.randf_range(-10, 10)
		state[18] = rng.randf_range(-0.3, 0.3)
		var sticks := PackedFloat64Array([rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)])
		if index < 5: sticks[3] = -1.0 + index * 0.5
		var mode := "normal" if index % 2 == 0 else "idle_up"
		var trim := {"roll_reference_rad":0.04, "pitch_reference_rad":-0.03, "cyclic_forward_bias_rad":0.012, "cyclic_right_bias_rad":-0.009, "tail_collective_bias_rad":0.01}
		var safe: Dictionary = Electronics.evaluate(model, state, sticks, mode, index % 3 == 0, trim)
		var fast: Dictionary = Electronics.fast_evaluate(model, state, sticks, mode, index % 3 == 0, trim)
		_check("complete safe/prepared payload parity %d" % index, safe.ok and fast.ok and safe == fast)
		if safe.ok and fast.ok:
			_check("servo/controller byte identity %d" % index,
				safe.swash_servo_targets.to_byte_array() == fast.swash_servo_targets.to_byte_array()
				and safe.controller_derivative.to_byte_array() == fast.controller_derivative.to_byte_array())
	var state: PackedFloat64Array = Fixture.state_at_hover()
	var sticks := PackedFloat64Array([0,0,0,0])
	_check("missing mode rejected", not Electronics.fast_evaluate(model, state, sticks, "missing", true).ok)
	_check("malformed state rejected", not Electronics.fast_evaluate(model, PackedFloat64Array([0]), sticks, "normal", true).ok)
	sticks[2] = NAN
	_check("nonfinite stick rejected", not Electronics.fast_evaluate(model, state, sticks, "normal", true).ok)
	sticks[2] = 0.0
	state[12] = INF
	_check("nonfinite body rate rejected", not Electronics.fast_evaluate(model, state, sticks, "normal", true).ok)
	state[12] = 0.0
	_check("unknown trim rejected", not Electronics.fast_evaluate(model, state, sticks, "normal", true, {"invented":1}).ok)
	var bad_parameters: Dictionary = Fixture.electronics_parameters()
	bad_parameters.linkage = []
	_check("wrong authoring container rejects without script error", not Electronics.prepare(bad_parameters).ok)
	var forged: Dictionary = model.duplicate(true)
	forged.curves_by_mode = {"normal":{"pitch":[0.0],"throttle":[0.0]}}
	forged.make_read_only()
	_check("mutable/short prepared curves reject without script error", not Electronics.fast_evaluate(forged, state, sticks, "normal", true).ok)
	print("HELI-09 prepared electronics: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
