extends SceneTree

const ControlActuators := preload("res://physics/control_actuators.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const Commands := preload("res://input/commands.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL control actuators: %s %s" % [label, detail])


func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


func _same_bits(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if _bits(a[index]) != _bits(b[index]):
			return false
	return true


func _same_surface_bits(a: Dictionary, b: Dictionary) -> bool:
	for name: String in ["aileron_right", "aileron_left", "elevator", "rudder"]:
		if not a.has(name) or not b.has(name) or _bits(a[name]) != _bits(b[name]):
			return false
	return true


func _aero_loads(positions: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var state := RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var surfaces: Dictionary = ControlSurfaces.independent_deflections_deg(positions, model.controls.throw_deg)
	if surfaces.is_empty():
		return PackedFloat64Array()
	var deflections := Aero.deflections_from_surfaces(surfaces)
	return Aero.loads(state, air, deflections, model, Air.RHO_SEA_LEVEL)


func _test_scalar_kernel_parity() -> void:
	var negative_zero: float = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	_check("signed-zero fixture is negative zero", _bits(negative_zero) != _bits(0.0))
	# Pre-kernel float64 samples pin rounding and signed-zero behavior without
	# recomputing the expected result with the implementation's own formula.
	var samples: Array = [
		[0.0, 1.0, 2.0, 0.25, "000000000000e03f"],
		[-0.5, 0.5, 1.25, 0.2, "000000000000d0bf"],
		[0.8, -1.0, 4.0, 0.25, "989999999999c9bf"],
		[negative_zero, 0.0, 1.0, 0.0, "0000000000000000"],
		[negative_zero, 0.25, 0.0, 0.1, "0000000000000000"],
	]
	for sample: Array in samples:
		var expected: String = sample[4]
		var actual: float = ControlActuators.rate_limit(sample[0], sample[1], sample[2], sample[3])
		_check("scalar law keeps old bytes %s" % str(sample), _bits(actual) == expected,
			"new=%s old=%s" % [_bits(actual), expected])
		_check("scalar kernel matches Commands compatibility path %s" % str(sample),
			_bits(actual) == _bits(Commands.rate_limit(sample[0], sample[1], sample[2], sample[3])))


func _test_batch_rate_step() -> void:
	var actual := PackedFloat64Array([0.0, -0.5, 0.8])
	var demand := PackedFloat64Array([1.0, 0.5, -1.0])
	var rates := PackedFloat64Array([2.0, 1.0, 4.0])
	var before := actual.duplicate()
	var candidate := ControlActuators.step_normalized(actual, demand, rates, 0.25)
	_check("batch computes analytic rate-limited positions", candidate.size() == 3
		and candidate[0] == 0.5 and candidate[1] == -0.25 and absf(candidate[2] + 0.2) < 1e-15, str(candidate))
	var no_overshoot := candidate.size() == demand.size()
	for index in candidate.size():
		no_overshoot = no_overshoot and candidate[index] >= minf(actual[index], demand[index]) \
			and candidate[index] <= maxf(actual[index], demand[index])
	_check("batch never overshoots any demand", no_overshoot)
	_check("batch leaves caller state unchanged", _same_bits(actual, before), str(actual))
	var expected := PackedFloat64Array()
	expected.resize(actual.size())
	for index in actual.size():
		expected[index] = ControlActuators.rate_limit(actual[index], demand[index], rates[index], 0.25)
	_check("batch matches the scalar kernel per channel", _same_bits(candidate, expected))

	var jam_actual := PackedFloat64Array([0.25, -0.25, 0.0, 0.5])
	var jam_demand := PackedFloat64Array([-0.75, 0.75, 0.75, -1.0])
	var jam_rates := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var jam_factors := PackedFloat64Array([0.0, 1.0, 1.0, 0.0])
	var jammed := ControlActuators.step_normalized(jam_actual, jam_demand, jam_rates, 0.5, jam_factors)
	_check("zero factors hold jammed positions while peers move", jammed.size() == 4
		and _bits(jammed[0]) == _bits(jam_actual[0]) and jammed[1] == 0.25
		and jammed[2] == 0.5 and _bits(jammed[3]) == _bits(jam_actual[3]), str(jammed))
	var zero_dt := ControlActuators.step_normalized(jam_actual, jam_demand, jam_rates, 0.0)
	_check("zero timestep returns current positions", _same_bits(zero_dt, jam_actual))
	var no_factors := ControlActuators.step_normalized(actual, demand, rates, 0.25)
	var unity_factors := ControlActuators.step_normalized(actual, demand, rates, 0.25,
		PackedFloat64Array([1.0, 1.0, 1.0]))
	_check("omitted and unit factors agree", _same_bits(no_factors, unity_factors))

	var split_actual := PackedFloat64Array([0.0, -0.5, 0.25, 0.5])
	var split_demand := PackedFloat64Array([0.5, 0.5, -0.25, -0.5])
	var split_rates := PackedFloat64Array([1.0, 2.0, 0.5, 4.0])
	var one_step := ControlActuators.step_normalized(split_actual, split_demand, split_rates, 0.1)
	var half_step := ControlActuators.step_normalized(split_actual, split_demand, split_rates, 0.05)
	var two_steps := ControlActuators.step_normalized(half_step, split_demand, split_rates, 0.05)
	var converged := one_step.size() == two_steps.size()
	for index in one_step.size():
		converged = converged and absf(one_step[index] - two_steps[index]) < 1e-12
	_check("constant-target step converges under timestep split", converged,
		"one=%s split=%s" % [str(one_step), str(two_steps)])


func _test_batch_validation() -> void:
	var valid_actual := PackedFloat64Array([0.0, -0.5])
	var valid_demand := PackedFloat64Array([0.5, 0.5])
	var valid_rates := PackedFloat64Array([1.0, 1.0])
	var original := valid_actual.duplicate()
	var rejected := ControlActuators.step_normalized(PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), 0.1)
	_check("rejects empty batches atomically", rejected.is_empty())
	_check("rejects unequal batch lengths", ControlActuators.step_normalized(valid_actual,
		PackedFloat64Array([0.5]), valid_rates, 0.1).is_empty())
	_check("rejects out-of-range actual position", ControlActuators.step_normalized(
		PackedFloat64Array([1.01]), PackedFloat64Array([0.0]), PackedFloat64Array([1.0]), 0.1).is_empty())
	_check("rejects out-of-range demand", ControlActuators.step_normalized(
		PackedFloat64Array([0.0]), PackedFloat64Array([-1.01]), PackedFloat64Array([1.0]), 0.1).is_empty())
	_check("rejects zero and negative nominal rates", ControlActuators.step_normalized(
		PackedFloat64Array([0.0, 0.0]), PackedFloat64Array([0.5, 0.5]), PackedFloat64Array([1.0, 0.0]), 0.1).is_empty()
		and ControlActuators.step_normalized(PackedFloat64Array([0.0]), PackedFloat64Array([0.5]), PackedFloat64Array([-1.0]), 0.1).is_empty())
	_check("rejects nonfinite positions and rates", ControlActuators.step_normalized(
		PackedFloat64Array([NAN]), PackedFloat64Array([0.0]), PackedFloat64Array([1.0]), 0.1).is_empty()
		and ControlActuators.step_normalized(PackedFloat64Array([0.0]), PackedFloat64Array([0.5]), PackedFloat64Array([INF]), 0.1).is_empty())
	_check("rejects invalid timestep", ControlActuators.step_normalized(valid_actual, valid_demand, valid_rates, -0.1).is_empty()
		and ControlActuators.step_normalized(valid_actual, valid_demand, valid_rates, NAN).is_empty()
		and ControlActuators.step_normalized(valid_actual, valid_demand, valid_rates, INF).is_empty())
	_check("rejects overflowing rate times timestep", ControlActuators.step_normalized(
		PackedFloat64Array([0.0]), PackedFloat64Array([1.0]), PackedFloat64Array([1e308]), 2.0).is_empty())
	_check("rejects malformed or out-of-range factors", ControlActuators.step_normalized(
		valid_actual, valid_demand, valid_rates, 0.1, PackedFloat64Array([1.0])).is_empty()
		and ControlActuators.step_normalized(PackedFloat64Array([0.0]), PackedFloat64Array([0.5]),
			PackedFloat64Array([1.0]), 0.1, PackedFloat64Array([1.01])).is_empty()
		and ControlActuators.step_normalized(PackedFloat64Array([0.0]), PackedFloat64Array([0.5]),
			PackedFloat64Array([1.0]), 0.1, PackedFloat64Array([NAN])).is_empty())
	var invalid_last := ControlActuators.step_normalized(PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.5, 1.01]), PackedFloat64Array([1.0, 1.0]), 0.1)
	_check("late invalid channel rejects whole candidate", invalid_last.is_empty())
	_check("failed candidates never mutate caller positions", _same_bits(valid_actual, original), str(valid_actual))


func _test_independent_surface_conversion() -> void:
	var throws := {"aileron": 30.0, "aileron_down": 10.0, "elevator": 20.0, "rudder": 40.0}
	var positions := PackedFloat64Array([0.5, -0.25, 0.3, -0.4])
	var surfaces: Dictionary = ControlSurfaces.independent_deflections_deg(positions, throws)
	_check("independent throws preserve each sign and differential", surfaces.size() == 4
		and surfaces.aileron_right == 15.0 and surfaces.aileron_left == -2.5
		and surfaces.elevator == 6.0 and surfaces.rudder == -16.0, str(surfaces))

	for roll: float in [-1.0, -0.37, -0.0, 0.0, 0.41, 1.0]:
		var commands := {"roll": roll, "pitch": 0.25, "yaw": -0.3}
		var logical: Dictionary = ControlSurfaces.surface_deflections_deg(commands, throws)
		var independent: Dictionary = ControlSurfaces.independent_deflections_deg(
			PackedFloat64Array([roll, -roll, commands.pitch, commands.yaw]), throws)
		_check("logical pair maps bit-identically to independent positions %s" % _bits(roll),
			_same_surface_bits(logical, independent), str(independent))
	_check("rejects wrong surface-position count", ControlSurfaces.independent_deflections_deg(
		PackedFloat64Array([0.0, 0.0, 0.0]), throws).is_empty())
	_check("rejects nonfinite or out-of-range surface positions", ControlSurfaces.independent_deflections_deg(
		PackedFloat64Array([1.01, 0.0, 0.0, 0.0]), throws).is_empty()
		and ControlSurfaces.independent_deflections_deg(PackedFloat64Array([NAN, 0.0, 0.0, 0.0]), throws).is_empty()
		and ControlSurfaces.independent_deflections_deg(PackedFloat64Array([INF, 0.0, 0.0, 0.0]), throws).is_empty())

	# Isolated topology fixture only: no current aircraft is declared to have these independent drives.
	var actual := PackedFloat64Array([0.25, -0.25, 0.0, 0.0])
	var demand := PackedFloat64Array([-0.75, 0.75, 0.0, 0.0])
	var candidate := ControlActuators.step_normalized(actual, demand,
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0]), 0.5, PackedFloat64Array([0.0, 1.0, 1.0, 1.0]))
	var before := ControlSurfaces.independent_deflections_deg(actual, throws)
	var after := ControlSurfaces.independent_deflections_deg(candidate, throws)
	_check("one-sided jam holds only that physical angle", candidate.size() == 4
		and _bits(before.aileron_right) == _bits(after.aileron_right)
		and before.aileron_left != after.aileron_left,
		"before=%s after=%s" % [str(before), str(after)])


func _test_aero_consumes_asymmetric_fixture() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_check("real aerodynamic model loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var model: Dictionary = loaded.model
	var neutral := _aero_loads(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), model)
	var right_only := _aero_loads(PackedFloat64Array([0.5, 0.0, 0.0, 0.0]), model)
	var left_only := _aero_loads(PackedFloat64Array([0.0, 0.5, 0.0, 0.0]), model)
	_check("neutral independent surface fixture returns finite six-axis loads", neutral.size() == 6)
	var finite := neutral.size() == 6
	for value: float in neutral:
		finite = finite and is_finite(value)
	_check("neutral loads are finite", finite, str(neutral))
	_check("independent right and left ailerons reach aero with opposite roll effects",
		right_only.size() == 6 and left_only.size() == 6
		and right_only[3] * left_only[3] < 0.0,
		"right Mx=%s left Mx=%s" % [right_only[3] if right_only.size() == 6 else NAN,
			left_only[3] if left_only.size() == 6 else NAN])


func _test_visual_surface_pose() -> void:
	# Presentation fixture only: visual hinges consume four supplied poses, not actuator metadata.
	var airplane: Dictionary = AirplaneBuilder.build("jensen-das-ugly-stik-60")
	var root: Variant = airplane.get("root")
	_check("real render model builds for asymmetric fixture", root is Node, str(airplane.keys()))
	if not root is Node:
		return
	var model: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var positions := PackedFloat64Array([0.5, 0.0, 0.0, 0.0])
	var surfaces: Dictionary = ControlSurfaces.independent_deflections_deg(positions, model.controls.throw_deg)
	AirplaneBuilder.apply_surfaces(airplane, ControlSurfaces.hinge_rotations_from_surfaces(surfaces))
	var hinges: Dictionary = airplane.get("hinges", {})
	var visible := hinges.has("aileron_right") and hinges.has("aileron_left")
	if visible:
		var right: Node3D = hinges.aileron_right
		var left: Node3D = hinges.aileron_left
		_check("visual right aileron receives its independent pose",
			absf(right.rotation.x + deg_to_rad(surfaces.aileron_right)) < 1e-6, str(right.rotation.x))
		_check("visual left aileron remains at its independent neutral pose",
			absf(left.rotation.x + deg_to_rad(surfaces.aileron_left)) < 1e-6, str(left.rotation.x))
	else:
		_check("real model exposes both conventional aileron hinges", false, str(hinges.keys()))
	root.free()


func _initialize() -> void:
	_test_scalar_kernel_parity()
	_test_batch_rate_step()
	_test_batch_validation()
	_test_independent_surface_conversion()
	_test_aero_consumes_asymmetric_fixture()
	_test_visual_surface_pose()
	print("Control actuator kernel and isolated surface fixtures: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
