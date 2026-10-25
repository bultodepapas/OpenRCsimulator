## M5-W05b-R1: body-datum spatial queries through the actual aircraft stage evaluators.
## Synthetic providers are test fixtures, not accepted weather configurations or per-surface airflow models.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const Config := preload("res://physics/wind_config.gd")

class ProbeField extends "res://physics/wind_field.gd":
	var fixed := false
	var fixed_value := PackedFloat64Array([0.0, 0.0, 0.0])
	var fail_after := INF
	var active := false
	var expected_position := PackedFloat64Array()
	var expected_time := 0.0
	var mismatches := 0
	var calls := 0
	var counts: Array[int] = []
	var positions: Array[PackedFloat64Array] = []
	var times: Array[float] = []

	static func value_at(p: PackedFloat64Array, t: float) -> PackedFloat64Array:
		# Smooth, small, divergence-free linear test field; depends on all coordinates and time.
		return PackedFloat64Array([0.15 + 0.002 * p[1] + 0.03 * t,
			-0.1 + 0.001 * p[2] - 0.02 * t, 0.001 * p[0] + 0.01 * t])

	func sample_world(p: PackedFloat64Array, t: float) -> PackedFloat64Array:
		if active:
			calls += 1
			if p.to_byte_array() != expected_position.to_byte_array() or t != expected_time:
				mismatches += 1
		if t > fail_after:
			return PackedFloat64Array([NAN, NAN, NAN])
		return fixed_value.duplicate() if fixed else value_at(p, t)

	func begin_stage(s: PackedFloat64Array, t: float, record: bool = true) -> void:
		active = true
		calls = 0
		expected_position = s.slice(0, 3)
		expected_time = t
		if record:
			positions.append(expected_position)
			times.append(t)

	func end_stage() -> void:
		counts.append(calls)
		active = false

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok " if passed else "FAIL ") + label)


func _run() -> void:
	var paths: Array[String] = []
	for id: String in Catalog.airplane_flyable_ids():
		paths.append(str(Catalog.entry(id).data))
		if Catalog.has_battery_mode(id, "pack"):
			paths.append(Catalog.data_for(id, "pack"))
	for path: String in paths:
		_flight(path)
	print("M5-W05b-R1 aircraft spatial contract: %d checks, %d failures; %d configurations" % [checks, failures, paths.size()])
	quit(1 if failures else 0)


func _evaluate(session: Node, s: PackedFloat64Array, t: float) -> Dictionary:
	if session.sim.model.stage.is_valid():
		return session.sim.model.stage.call(s, session.sim.continuous, t)
	if not session.sim.continuous.is_empty():
		return {loads = session.sim.model.block_loads.call(s, session.sim.continuous, t),
			derivative = session.sim.model.block_derivative.call(s, session.sim.continuous, t)}
	return {loads = session.sim.model.loads.call(s, t)}


func _instrument(session: Node, field: ProbeField) -> void:
	if session.sim.model.stage.is_valid():
		var original: Callable = session.sim.model.stage
		session.sim.model.stage = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> Dictionary:
			field.begin_stage(s, t)
			var result: Dictionary = original.call(s, c, t)
			field.end_stage()
			return result
	elif not session.sim.continuous.is_empty():
		var loads: Callable = session.sim.model.block_loads
		var derivative: Callable = session.sim.model.block_derivative
		session.sim.model.block_loads = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> PackedFloat64Array:
			field.begin_stage(s, t)
			var result: PackedFloat64Array = loads.call(s, c, t)
			field.end_stage()
			return result
		session.sim.model.block_derivative = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> PackedFloat64Array:
			field.begin_stage(s, t, false)
			var result: PackedFloat64Array = derivative.call(s, c, t)
			field.end_stage()
			return result
	else:
		var loads: Callable = session.sim.model.loads
		session.sim.model.loads = func(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
			field.begin_stage(s, t)
			var result: PackedFloat64Array = loads.call(s, t)
			field.end_stage()
			return result


func _flight(path: String) -> void:
	var session := Flight.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(path)
	root.add_child(session)
	check(path + " prepares", session.is_flyable())
	if not session.is_flyable():
		session.free()
		return
	# Exercise failure rollback with a live OU window/RNG as well as propulsion/wake state.
	check(path + " accepts legacy turbulence", session.setup_weather(Config.preset("turbulent")))
	session.reset()
	session.sim.step()
	var field := ProbeField.new()
	field._apply_config(session.weather_configuration())
	session.environment.weather = field
	var s: PackedFloat64Array = session.sim.state.duplicate()
	s[RB.POS] += 23.0
	s[RB.POS + 1] -= 17.0
	s[RB.POS + 2] -= 5.0
	var t: float = session.sim.time()
	var expected: PackedFloat64Array = ProbeField.value_at(s.slice(0, 3), t)
	var noise: PackedFloat64Array = session._turbulence_noise(t)
	for axis in 3:
		expected[axis] += noise[axis]
	var actual_air: Dictionary = session.air_data(s, t)
	var oracle_air: Dictionary = Air.compute(s, expected, session.air_density(s))
	check(path + " air data uses supplied body position and adds turbulence once",
		var_to_bytes(actual_air) == var_to_bytes(oracle_air))
	check(path + " endpoint observer uses accepted position", session.wind_at(t).to_byte_array()
		== session.environment.wind_world(session.sim.state.slice(0, 3), t).to_byte_array())
	check(path + " malformed state yields invalid wind", is_nan(session.wind_at(t, PackedFloat64Array([1.0]))[0]))
	# At one supplied body position, a linear provider and a constant provider with the same value
	# must give identical complete stage loads/derivatives. This catches indirect propulsion/ground paths.
	var spatial: Dictionary = _evaluate(session, s, t)
	field.fixed = true
	field.fixed_value = ProbeField.value_at(s.slice(0, 3), t)
	var uniform: Dictionary = _evaluate(session, s, t)
	check(path + " spatial and matched uniform body-datum stage agree", var_to_bytes(spatial) == var_to_bytes(uniform))
	field.fixed = false
	var before_observers: PackedByteArray = var_to_bytes(session.sim.checkpoint())
	for query_time: float in [t + 0.1, t, t + 0.05, t]:
		session.air_data(s, query_time)
	check(path + " reordered observer queries leave all kernel state unchanged", before_observers == var_to_bytes(session.sim.checkpoint()))
	_instrument(session, field)
	var start_position: PackedFloat64Array = session.sim.state.slice(0, 3)
	var h: float = session.sim.dt()
	session.sim.step()
	check(path + " real RK step succeeds", session.sim.fault_reason.is_empty())
	check(path + " actual stage times reach provider", field.times == [t, t + h / 2.0, t + h / 2.0, t + h])
	check(path + " every sampled stage uses its own position/time", field.mismatches == 0
		and not field.counts.is_empty() and field.counts.all(func(n: int) -> bool: return n > 0))
	check(path + " midpoint position differs from committed endpoint", field.positions.size() == 4 and field.positions[1] != start_position)
	# Poison the next tick's midpoint. The existing transaction must reject it and restore all state,
	# including the just-advanced OU window and private RNG mode. No successful tick signal is allowed.
	field.fail_after = session.sim.time()
	var before: Dictionary = session.sim.checkpoint()
	var previous: PackedFloat64Array = session.sim.previous.duplicate()
	var loads: PackedFloat64Array = session.sim.last_loads.duplicate()
	var emitted := [0]
	session.sim.stepped.connect(func(_tick, _time, _state, _loads, _inputs, _aux): emitted[0] += 1)
	session.sim.step()
	var restored := true
	for key: String in ["state", "aux", "continuous", "modes", "inputs"]:
		restored = restored and var_to_bytes(session.sim.get(key)) == var_to_bytes(before[key])
	check(path + " bad spatial sample rolls back body/aux/continuous/RNG/inputs", restored
		and session.sim.tick == before.tick and session.sim.previous.to_byte_array() == previous.to_byte_array()
		and session.sim.last_loads.to_byte_array() == loads.to_byte_array())
	check(path + " bad spatial sample pauses without publishing", session.sim.paused
		and not session.sim.fault_reason.is_empty() and emitted[0] == 0)
	session.free()
