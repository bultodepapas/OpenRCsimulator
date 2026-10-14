# HELI-09: fast-path parity, context immutability and invalid-data guards.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
const M = preload("res://physics/math3d.gd")

const COLLECTIVE: float = 0.09624751257538011
const FLOW_FLOOR: float = 0.1
const FIN_WAKE_FRACTION: float = 0.2

var checks: int = 0
var failures: int = 0
var main_model: Dictionary
var tail_model: Dictionary
var airframe_model: Dictionary
var context: Dictionary


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	main_model = Main.prepare(MainFixture.PARAMS).model
	tail_model = Tail.prepare(TailFixture.PARAMS).model
	airframe_model = Airframe.prepare(AirframeFixture.PARAMS).model
	var prepared: Dictionary = Stage.prepare(main_model, tail_model, airframe_model,
		FLOW_FLOOR, FIN_WAKE_FRACTION, -1.0, 1.0, 0.0)
	check("prepared immutable aero context valid", prepared.ok)
	if not prepared.ok:
		quit(1)
	context = prepared.context
	check("context dictionary is read-only", context.is_read_only())
	check("component contexts are read-only", main_model.is_read_only() and tail_model.is_read_only() and airframe_model.is_read_only())
	_scenarios()
	_randomized_parity()
	_invalid_data()
	print("HELI-09 performance context: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _scenarios() -> void:
	var hover_state := PackedFloat64Array([0.0, 0.0, 1.0])
	var hover_air := M.v3(0.0, 0.0, 0.0)
	var zero_rates := M.v3(0.0, 0.0, 0.0)
	_compare("hover", hover_state, 167.0, hover_air, zero_rates, COLLECTIVE, 0.01, -0.01, 0.1)
	_compare("forward flight", PackedFloat64Array([-0.025, 0.018, 1.2]), 167.0,
		M.v3(18.0, -1.0, 0.5), M.v3(0.02, -0.03, 0.08), 0.105, 0.015, -0.02, 0.11)
	# Descent near the induced velocity with modest crossflow exercises the
	# published vortex-ring interpolation while keeping the same exact equations.
	_compare("vortex-ring descent", PackedFloat64Array([0.02, -0.015, 1.4]), 167.0,
		M.v3(0.7, 0.0, 4.0), M.v3(0.0, 0.0, 0.0), COLLECTIVE, 0.0, 0.0, 0.1)
	# Negative disk thrust and a climb along the positive thrust axis exercise the
	# reflected windmill branch of the same source inflow table.
	_compare("windmill", PackedFloat64Array([-0.01, 0.01, -0.4]), 167.0,
		M.v3(0.0, 0.0, -12.0), M.v3(0.0, 0.0, 0.0), -0.12, 0.0, 0.0, 0.1)
	var wind := M.v3(4.0, -2.0, 1.0)
	var rates := M.v3(0.12, -0.08, 0.15)
	_compare("crosswind and rotation", PackedFloat64Array([0.03, -0.02, 0.8]), 167.0,
		wind, rates, 0.11, -0.025, 0.03, 0.12)
	# The same state queried after other regimes must reproduce every full output.
	_compare("hover after regime changes", hover_state, 167.0, hover_air, zero_rates,
		COLLECTIVE, 0.01, -0.01, 0.1)


func _randomized_parity() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 0x48454c493039
	for index: int in range(128):
		var state := PackedFloat64Array([
		random.randf_range(-0.08, 0.08), random.randf_range(-0.08, 0.08), random.randf_range(0.2, 2.2)])
		var air := M.v3(random.randf_range(-8.0, 8.0), random.randf_range(-4.0, 4.0), random.randf_range(-3.0, 4.0))
		var body_rates := M.v3(random.randf_range(-0.3, 0.3), random.randf_range(-0.3, 0.3), random.randf_range(-0.5, 0.5))
		_compare("seeded sample %d" % index, state, random.randf_range(135.0, 185.0), air, body_rates,
			random.randf_range(0.075, 0.12), random.randf_range(-0.05, 0.05),
			random.randf_range(-0.05, 0.05), random.randf_range(0.07, 0.15))


func _compare(label: String, state: PackedFloat64Array, omega: float, air: PackedFloat64Array,
		rates: PackedFloat64Array, collective: float, cyclic_forward: float,
		cyclic_right: float, tail_collective: float) -> void:
	for diagnostics: bool in [false, true]:
		var reference: Dictionary = Stage.evaluate(main_model, tail_model, airframe_model,
			state, omega, air, rates, collective, cyclic_forward, cyclic_right,
			tail_collective, FLOW_FLOOR, FIN_WAKE_FRACTION, -1.0, 1.0, 0.0, diagnostics)
		var fast: Dictionary = Stage.fast_evaluate(context, state, omega, air, rates,
			collective, cyclic_forward, cyclic_right, tail_collective, diagnostics)
		check("%s %s result valid" % [label, "full" if diagnostics else "compact"], reference.ok and fast.ok)
		check("%s %s exact payload parity" % [label, "full" if diagnostics else "compact"], reference == fast)
		if reference.ok and fast.ok:
			check("%s loads byte parity" % label, reference.loads.to_byte_array() == fast.loads.to_byte_array())
			check("%s derivative byte parity" % label, reference.derivative.to_byte_array() == fast.derivative.to_byte_array())


func _invalid_data() -> void:
	var state := PackedFloat64Array([0.0, 0.0, 1.0])
	var zero := M.v3(0.0, 0.0, 0.0)
	check("mutable stage context refused", not Stage.fast_evaluate(context.duplicate(), state, 167.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	var forged := context.duplicate()
	forged["main_model"] = main_model.duplicate()
	forged.make_read_only()
	check("mutable nested component context refused", not Stage.fast_evaluate(forged, state, 167.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("wrong-size state refused", not Stage.fast_evaluate(context, PackedFloat64Array([0.0]), 167.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("nonfinite state refused", not Stage.fast_evaluate(context, PackedFloat64Array([0.0, NAN, 1.0]), 167.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("nonfinite air flow refused", not Stage.fast_evaluate(context, state, 167.0,
		M.v3(INF, 0.0, 0.0), zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("nonfinite body rate refused", not Stage.fast_evaluate(context, state, 167.0,
		zero, M.v3(0.0, NAN, 0.0), COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("nonfinite command refused", not Stage.fast_evaluate(context, state, 167.0,
		zero, zero, COLLECTIVE, 0.0, NAN, 0.1).ok)
	check("negative shaft speed refused", not Stage.fast_evaluate(context, state, -1.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, 0.1).ok)
	check("tail collective bound remains enforced", not Stage.fast_evaluate(context, state, 167.0,
		zero, zero, COLLECTIVE, 0.0, 0.0, PI).ok)
	check("mutable source model refused at preparation", not Stage.prepare(main_model.duplicate(),
		tail_model, airframe_model, FLOW_FLOOR, FIN_WAKE_FRACTION).ok)
	check("invalid flow floor refused at preparation", not Stage.prepare(main_model, tail_model,
		airframe_model, 0.0, FIN_WAKE_FRACTION).ok)
	check("invalid wake fraction refused at preparation", not Stage.prepare(main_model, tail_model,
		airframe_model, FLOW_FLOOR, 1.1).ok)
