# G2a/G2b experimental shaft integration contract: stage-local RPM, locked-body coupling,
# exact checkpoint identity, and unchanged split/no-shaft paths.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Prop := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Wind := preload("res://physics/wind_config.gd")
const WashFixture := preload("res://tests/test_wash_profile.gd")
const Trace := preload("res://sim/trace.gd")

const P51_ID := "p51d-mustang-120"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1


func _new_flight(mode: String = "split", path: String = P51_PATH, weather: Dictionary = {}) -> Node:
	var flight: Node = Flight.new()
	if not weather.is_empty():
		if not flight.setup_weather(weather):
			flight.free()
			return null
	if mode != "split" and not flight.setup_shaft_integrator(mode):
		flight.free()
		return null
	flight.setup(path)
	flight.input_enabled = false
	return flight


func _coupled_fixture(transport: bool = false, weather: Dictionary = {}) -> Node:
	var flight: Node = _new_flight("coupled-rk4", P51_PATH, weather)
	if flight == null or not flight.is_flyable():
		return flight
	if transport:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
		var wash_raw: Dictionary = WashFixture.combined_raw().propulsion.propeller.slipstream
		wash_raw.transport_speed_floor = WashFixture.quantity(1.0, "m/s")
		raw.propulsion.propeller.thrust_angles = WashFixture.quantity([0.0, 0.0], "deg")
		raw.propulsion.propeller.slipstream = wash_raw
		var checked: Dictionary = AD.validate_and_derive(raw)
		_check("P-51 test-only transported wash fixture validates", checked.ok, str(checked.errors))
		if not checked.ok or not flight._apply(checked):
			flight.free()
			return null
		flight.reset()
	return flight


func _advance(flight: Node, count: int, throttle: float = 0.68) -> void:
	for i: int in count:
		flight.sim.inputs[0] = 0.08 if i % 30 < 15 else -0.04
		flight.sim.inputs[1] = -0.03
		flight.sim.inputs[2] = 0.02
		flight.sim.inputs[3] = throttle
		flight.sim.step()


func _dynamic_bits(sim: Node) -> PackedByteArray:
	var dynamic: Dictionary = {
		"state": sim.state,
		"previous": sim.previous,
		"continuous": sim.continuous,
		"aux": sim.aux,
		"inputs": sim.inputs,
		"modes": sim.modes,
		"last_loads": sim.last_loads,
		"tick": sim.tick,
		"stop_at_tick": sim.stop_at_tick,
		"mass": sim.mass,
		"inertia": sim.inertia,
		"gravity": sim.gravity,
		"fixed_dt": sim._fixed_dt,
	}
	return var_to_bytes(dynamic)


func _torque_closure(flight: Node, label: String) -> void:
	var prop: Dictionary = flight.aircraft.model.propulsion
	var sim: Node = flight.sim
	var state: PackedFloat64Array = sim.state.duplicate()
	var continuous: PackedFloat64Array = sim.continuous.duplicate()
	var rpm: float = continuous[-1]
	var time_s: float = sim.time()
	var loads: PackedFloat64Array = flight._coupled_loads(state, continuous, time_s)
	var h: PackedFloat64Array = flight._coupled_rotor(state, continuous, time_s)
	var derivative: PackedFloat64Array = RB.derivative(state, sim.mass, sim.inertia,
		RB.inertia_inverse(sim.inertia), M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), sim.gravity, h)
	var shaft: PackedFloat64Array = flight._coupled_derivative(state, continuous, time_s)
	var air: Dictionary = flight.air_data(state, time_s)
	var axis: PackedFloat64Array = Prop.axis(prop)
	var axial_speed: float = M.dot(air.v_air, axis)
	var engine: float
	if flight.engine_running:
		engine = Prop.engine_torque(rpm, sim.inputs[3], prop, flight.engine_charge_ratio())
	else:
		var friction: PackedFloat64Array = prop.shaft.friction
		engine = -float(friction[0]) - float(friction[1]) * rpm / 1000.0
	var prop_torque: float = Prop.prop_torque(rpm, axial_speed, prop, flight.air_density())
	var applied_shaft_torque: float = engine - prop_torque
	var body_alpha: PackedFloat64Array = derivative.slice(RB.RATE, RB.RATE + 3)
	var lhs: float = float(prop.rotor_inertia) * (shaft[-1] * TAU / 60.0 + M.dot(axis, body_alpha))
	var error: float = absf(lhs - applied_shaft_torque)
	_check(label, is_finite(lhs) and is_finite(applied_shaft_torque) and error < 2e-7 * maxf(1.0, absf(applied_shaft_torque)),
		"I*(Omega_dot + axis·body_alpha)=Q_engine-Q_prop; residual " + String.num_scientific(error) + " N·m")


func _mode_and_legacy_paths() -> void:
	var default_p51: Node = _new_flight()
	var explicit_split: Node = Flight.new()
	_check("split remains the default integrator", default_p51.shaft_integrator() == "split")
	_check("P-51 accepts explicit split mode", explicit_split.setup_shaft_integrator("split"))
	explicit_split.setup(P51_PATH)
	explicit_split.input_enabled = false
	_advance(default_p51, 80)
	_advance(explicit_split, 80)
	_check("default P-51 and explicit split trajectories stay byte-identical",
		var_to_bytes(default_p51.sim.checkpoint()) == var_to_bytes(explicit_split.sim.checkpoint()))
	var stik: Node = _new_flight("split", STIK_PATH)
	var stik_before: PackedByteArray = _dynamic_bits(stik.sim)
	_check("no-shaft Stik refuses coupled-rk4", not stik.setup_shaft_integrator("coupled-rk4")
		and stik.shaft_integrator() == "split" and _dynamic_bits(stik.sim) == stik_before)
	var stik_reference: Node = _new_flight("split", STIK_PATH)
	_advance(stik, 35)
	_advance(stik_reference, 35)
	_check("rejected mode leaves no-shaft flight trajectory unchanged",
		var_to_bytes(stik.sim.checkpoint()) == var_to_bytes(stik_reference.sim.checkpoint()))
	for flight: Node in [default_p51, explicit_split, stik, stik_reference]:
		flight.free()


func _coupling_physics() -> void:
	var flight: Node = _coupled_fixture()
	_check("P-51 coupled mode starts with one continuous RPM state", flight != null and flight.is_flyable()
		and flight.shaft_is_coupled() and flight.sim.continuous.size() == 1
		and flight.sim.continuous[-1] == flight.sim.aux[0])
	if flight == null:
		return
	var prop: Dictionary = flight.aircraft.model.propulsion
	var rpm: float = maxf(float(prop.idle_rpm) + 25.0, 1000.0)
	flight.sim.continuous[0] = rpm
	flight.sim.aux[0] = rpm
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	_check("high-throttle punch starts the relative rotor accelerating",
		flight._shaft_rate(flight.sim.state, rpm, 0.0) > 0.0)
	var z: PackedFloat64Array = flight.sim.continuous.duplicate()
	var body: PackedFloat64Array = flight.sim.state.duplicate()
	var at_time: float = flight.sim.time()
	var coupled_loads: PackedFloat64Array = flight._coupled_loads(body, z, at_time)
	var prefix: PackedFloat64Array = z.slice(0, z.size() - 1)
	var lag: int = flight.downwash_index()
	var downwash: float = flight.sim.aux[lag] if lag >= 0 and lag < flight.sim.aux.size() else NAN
	var external: PackedFloat64Array = Dynamics.loads(body, flight.aircraft.model, flight._deflections(flight.sim.aux),
		rpm, flight.air_density(), flight.wind_at(at_time), downwash, prefix)
	var ground: PackedFloat64Array = Ground.loads(body, flight.aircraft.model.landing_gear,
		flight.sim.aux[Flight.AUX_SERVO + 2], flight.ground_surfaces,
		flight.sim.aux.slice(Flight.AUX_ANCHORS, Flight.AUX_ANCHORS + flight.anchor_count() * Ground.ANCHOR_STRIDE))
	for i: int in ground.size():
		external[i] += ground[i]
	var response: PackedFloat64Array = flight._coupled_derivative(body, z, at_time)
	var axis: PackedFloat64Array = Prop.axis(prop)
	var relative_spin_accel: float = response[-1] * TAU / 60.0
	var added_moment: PackedFloat64Array = M.sub(coupled_loads.slice(3, 6), external.slice(3, 6))
	var expected_reaction: PackedFloat64Array = M.scale(axis, -float(prop.rotor_inertia) * relative_spin_accel)
	var reaction_error: float = 0.0
	for i: int in 3:
		reaction_error = maxf(reaction_error, absf(added_moment[i] - expected_reaction[i]))
	_check("first-punch relative-spin reaction is added once over external loads",
		relative_spin_accel > 0.0 and M.dot(axis, added_moment) < 0.0
		and reaction_error < 2e-7, "reaction residual " + String.num_scientific(reaction_error) + " N·m")
	_torque_closure(flight, "running torque, body coupling and friction close algebraically")
	flight.engine_running = false
	_torque_closure(flight, "engine-off closure includes mechanical friction once")
	flight.free()


func _stage_local_integration() -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check("stage-local fixture starts", false)
		return
	var prop: Dictionary = flight.aircraft.model.propulsion
	var start_rpm: float = float(prop.idle_rpm) + 40.0
	flight.sim.continuous[-1] = start_rpm
	flight.sim.aux[0] = start_rpm
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	_check("stage-local fixture resets cleanly", flight.sim.reset(flight.sim.state))
	var stages: Array = []
	var legacy_calls := { loads = 0, derivative = 0, rotor = 0 }
	var real_evaluate: Callable = flight.sim.continuous_evaluate
	var real_loads: Callable = flight.sim.continuous_loads
	var real_derivative: Callable = flight.sim.continuous_derivative
	var real_rotor: Callable = flight.sim.continuous_rotor_momentum
	flight.sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		stages.append({rpm = z[-1], time = t, z = z.duplicate(), loads = result.get("loads", null)})
		return result
	flight.sim.continuous_loads = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.loads += 1
		return real_loads.call(s, z, t)
	flight.sim.continuous_derivative = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.derivative += 1
		return real_derivative.call(s, z, t)
	flight.sim.continuous_rotor_momentum = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.rotor += 1
		return real_rotor.call(s, z, t)
	flight.sim.step()
	flight.sim.continuous_evaluate = real_evaluate
	flight.sim.continuous_loads = real_loads
	flight.sim.continuous_derivative = real_derivative
	flight.sim.continuous_rotor_momentum = real_rotor
	var dt: float = flight.sim.dt()
	var times_ok: bool = stages.size() == 4
	if times_ok:
		var expected: Array[float] = [0.0, dt * 0.5, dt * 0.5, dt]
		for i: int in 4:
			times_ok = times_ok and absf(float(stages[i].time) - expected[i]) < 1e-14
	var rpms: Array[float] = []
	for stage: Dictionary in stages:
		rpms.append(float(stage.rpm))
	var loads_ok: bool = stages.size() == 4
	for stage: Dictionary in stages:
		var stage_loads: Variant = stage.loads
		loads_ok = loads_ok and typeof(stage_loads) == TYPE_PACKED_FLOAT64_ARRAY and stage_loads.size() == 6
	if stages.size() == 4:
		loads_ok = loads_ok and flight.sim.last_loads == stages[0].loads
	_check("coupled RK4 performs four joint evaluations with stage loads at k1–k4 times and RPM", times_ok
		and loads_ok and rpms.size() == 4 and rpms.max() > rpms.min() + 1e-8
		and legacy_calls.loads == 0 and legacy_calls.derivative == 0 and legacy_calls.rotor == 0,
		"stage rpm %s; times %s; legacy calls %s" % [str(rpms),
		str(stages.map(func(stage: Dictionary) -> float: return float(stage.time))), str(legacy_calls)])
	_check("endpoint projection mirrors continuous RPM into sampled telemetry",
		flight.sim.continuous[-1] > start_rpm and flight.sim.aux[0] == flight.sim.continuous[-1])
	flight.free()


func _joint_callback_falls_back_to_legacy() -> void:
	var fallback: Node = _coupled_fixture()
	var reference: Node = _coupled_fixture()
	if fallback == null or reference == null or not fallback.is_flyable() or not reference.is_flyable():
		_check("legacy callback fallback fixtures start", false)
		return
	var calls := { loads = 0, derivative = 0, rotor = 0 }
	var original_loads: Callable = fallback.sim.continuous_loads
	var original_derivative: Callable = fallback.sim.continuous_derivative
	var original_rotor: Callable = fallback.sim.continuous_rotor_momentum
	fallback.sim.continuous_evaluate = Callable()
	fallback.sim.continuous_loads = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.loads += 1
		return original_loads.call(s, z, t)
	fallback.sim.continuous_derivative = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.derivative += 1
		return original_derivative.call(s, z, t)
	fallback.sim.continuous_rotor_momentum = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.rotor += 1
		return original_rotor.call(s, z, t)
	fallback.sim.step()
	reference.sim.step()
	_check("unset joint callback uses each legacy stage callback four times without fault",
		fallback.sim.tick == 1 and fallback.sim.fault_reason.is_empty()
		and calls.loads == 4 and calls.derivative == 4 and calls.rotor == 4,
		str(calls))
	var fallback_checkpoint: Dictionary = fallback.sim.checkpoint()
	var reference_checkpoint: Dictionary = reference.sim.checkpoint()
	_check("legacy callback fallback remains bit-identical to joint evaluation",
		var_to_bytes(fallback_checkpoint) == var_to_bytes(reference_checkpoint))
	fallback.free()
	reference.free()


func _wind_time_purity() -> void:
	var weather: Dictionary = Wind.defaults()
	weather.speed_mps = 3.0
	weather.from_deg = 180.0
	weather.gust_mps = 4.0
	weather.gust_duration_s = 1.5
	weather.gust_period_s = 4.0
	weather.gust_delay_s = 0.3
	var flight: Node = _coupled_fixture(false, weather)
	if flight == null or not flight.is_flyable():
		_check("wind purity fixture starts", false)
		return
	var before: PackedByteArray = _dynamic_bits(flight.sim)
	var rpm: float = flight.sim.continuous[-1]
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	var during: float = flight._shaft_rate(state, rpm, 1.05)
	var repeat: float = flight._shaft_rate(state, rpm, 1.05)
	var after_gust: float = flight._shaft_rate(state, rpm, 2.0)
	_check("stage shaft rate uses explicit wind time and remains pure",
		is_finite(during) and during == repeat and is_finite(after_gust) and absf(during - after_gust) > 1e-8
		and before == _dynamic_bits(flight.sim))
	flight.free()


func _transported_wash_and_replay() -> void:
	var flight: Node = _coupled_fixture(true)
	if flight == null or not flight.is_flyable():
		_check("coupled transported-wash fixture starts", false)
		return
	var pieces: int = flight.aircraft.model.propulsion.slipstream.pieces.size()
	var initial: PackedFloat64Array = flight.sim.continuous.duplicate()
	_check("transported wash precedes RPM in the continuous layout",
		initial.size() == pieces + 1 and initial[-1] == flight.sim.aux[0]
		and initial.slice(0, pieces) == flight._settled_wash(flight.sim.state, flight.sim.aux))
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	var stages: Array[PackedFloat64Array] = []
	var real_evaluate: Callable = flight.sim.continuous_evaluate
	flight.sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		stages.append(z.duplicate())
		return result
	flight.sim.step()
	flight.sim.continuous_evaluate = real_evaluate
	var wash_changed: bool = false
	var rpm_changed: bool = false
	if stages.size() == 4:
		for i: int in range(1, 4):
			wash_changed = wash_changed or stages[i].slice(0, pieces) != stages[0].slice(0, pieces)
			rpm_changed = rpm_changed or stages[i][-1] != stages[0][-1]
	_check("RK stages transport wash and solve RPM together", wash_changed and rpm_changed
		and flight.sim.continuous[-1] == flight.sim.aux[0])
	var metadata: Dictionary = flight.trace_meta()
	_check("coupled traces retain schema and identify the shaft integrator",
		metadata.metadata_schema == "openrc-flight-meta v2"
		and metadata.propulsion_model == "propeller-shaft-coupled-rk4-v1"
		and metadata.shaft_integrator == "coupled-rk4"
		and metadata.rotor_coupling == "relative-spin-locked-inertia-reaction-v1"
		and metadata.continuous_layout == "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled")
	var boundary: Dictionary = flight.checkpoint()
	_check("coupled checkpoint records a distinct v4 integrator identity",
		boundary.format == "openrc-flight-checkpoint v4"
		and boundary.get("shaft_integrator", "") == "coupled-rk4"
		and boundary.simulation.continuous.size() == pieces + 1)
	if boundary.is_empty():
		flight.free()
		return
	var captured: Dictionary = bytes_to_var(var_to_bytes(boundary))
	_advance(flight, 40, 0.74)
	var expected: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
	_check("coupled transported-wash checkpoint restores exactly", flight.restore_checkpoint(captured))
	_advance(flight, 40, 0.74)
	_check("coupled transported-wash replay is bit-exact", expected == var_to_bytes(flight.sim.checkpoint()))
	var before_bad_restore: PackedByteArray = _dynamic_bits(flight.sim)
	var bad_cases: Array[Dictionary] = []
	var bad_mirror: Dictionary = captured.duplicate(true)
	bad_mirror.simulation.aux[0] += 1.0
	bad_cases.append(bad_mirror)
	var bad_layout: Dictionary = captured.duplicate(true)
	bad_layout.simulation.continuous = bad_layout.simulation.continuous.slice(0, pieces)
	bad_cases.append(bad_layout)
	var bad_rpm: Dictionary = captured.duplicate(true)
	bad_rpm.simulation.continuous[-1] = -1.0
	bad_rpm.simulation.aux[0] = -1.0
	bad_cases.append(bad_rpm)
	var names: Array[String] = ["RPM mirror", "continuous layout", "negative RPM"]
	for i: int in bad_cases.size():
		_check("bad checkpoint " + names[i] + " is rejected atomically",
			not flight.restore_checkpoint(bad_cases[i]) and before_bad_restore == _dynamic_bits(flight.sim))
	var split: Node = _new_flight()
	var split_before: PackedByteArray = _dynamic_bits(split.sim)
	_check("split session refuses coupled checkpoint without mutation",
		not split.restore_checkpoint(captured) and split_before == _dynamic_bits(split.sim))
	split.free()
	flight.free()


func _fault_rollback(kind: String) -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check(kind + " rollback fixture starts", false)
		return
	var sim: Node = flight.sim
	var before: PackedByteArray = _dynamic_bits(sim)
	var stepped := [0]
	sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: stepped[0] += 1)
	var real_evaluate: Callable = sim.continuous_evaluate
	match kind:
		"stage":
			var calls := [0]
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				calls[0] += 1
				var result: Dictionary = real_evaluate.call(s, z, t)
				if calls[0] == 2:
					var bad_loads: PackedFloat64Array = result.loads.duplicate()
					bad_loads[0] = NAN
					result.loads = bad_loads
				return result
		"gyro":
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.rotor_momentum = PackedFloat64Array([NAN, 0, 0])
				return result
		"derivative":
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat64Array([NAN])
				return result
		"missing_field":
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.erase("derivative")
				return result
		"wrong_float32":
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat32Array([0.0])
				return result
		"wrong_width":
			sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat64Array([0.0, 0.0])
				return result
		"wrong_type":
			sim.continuous_evaluate = func(_s: PackedFloat64Array, _z: PackedFloat64Array, _t: float):
				return "invalid joint payload"
		"projection":
			sim.continuous_aux = func(_z: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
				var invalid: PackedFloat64Array = sampled.duplicate()
				invalid[0] = NAN
				return invalid
	sim.step()
	_check(kind + " failure rolls every committed dynamic field back and emits no tick",
		not sim.fault_reason.is_empty() and sim.paused and stepped[0] == 0 and before == _dynamic_bits(sim), sim.fault_reason)
	flight.free()


func _reset_joint_payload_rollback() -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check("malformed joint reset fixture starts", false)
		return
	var sim: Node = flight.sim
	var before: PackedByteArray = _dynamic_bits(sim)
	var stepped := [0]
	sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: stepped[0] += 1)
	var real_evaluate: Callable = sim.continuous_evaluate
	sim.continuous_evaluate = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		result.derivative = PackedFloat32Array([0.0])
		return result
	var reset_ok: bool = sim.reset(sim.state)
	_check("malformed float32 joint payload rejects reset atomically and emits no tick",
		not reset_ok and sim.paused and not sim.fault_reason.is_empty() and stepped[0] == 0
		and before == _dynamic_bits(sim), sim.fault_reason)
	flight.free()


func _trace_integrity() -> void:
	var flight: Node = _coupled_fixture()
	var trace: Trace = Trace.new()
	trace.meta = flight.trace_meta()
	trace.record(0, 0.0, flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux)
	trace.meta.shaft_integrator = "split"
	flight.sim.step()
	trace.record(1, flight.sim.time(), flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux)
	_check("coupled recording freezes its integration identity", trace.row_count() == 2 \
		and trace.to_csv().contains("# shaft_integrator: coupled-rk4\n"))
	var malformed: Trace = Trace.new()
	malformed.meta = flight.trace_meta()
	malformed.meta.recording_start_continuous = "[123.0]"
	malformed.record(flight.sim.tick, flight.sim.time(), flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux)
	_check("trace refuses a false initial continuous RPM mirror", malformed.to_csv().is_empty())
	flight.free()
	var wash: Node = _coupled_fixture(true)
	wash.sim.continuous[0] = -0.25 # a transported induced-velocity deficit is signed; RPM stays positive
	var signed_trace: Trace = Trace.new()
	signed_trace.meta = wash.trace_meta()
	signed_trace.record(wash.sim.tick, wash.sim.time(), wash.sim.state, wash.sim.last_loads, wash.sim.inputs, wash.sim.aux)
	_check("coupled trace accepts finite negative wash increments with positive RPM", not signed_trace.to_csv().is_empty())
	wash.free()


func _pending_restore() -> void:
	var source: Node = _coupled_fixture()
	var saved: Dictionary = source.checkpoint()
	var destination: Node = _coupled_fixture()
	var switched: bool = destination.setup_shaft_integrator("split") and destination.setup_shaft_integrator("coupled-rk4")
	_check("compatible restore completes a tick-zero mode draft", switched and destination.restore_checkpoint(saved))
	destination.sim.step()
	_check("restored mode draft advances without a pending-reset fault", destination.sim.tick == 1 and destination.sim.fault_reason.is_empty())
	source.free()
	destination.free()


func _initialize() -> void:
	var p51_data: Dictionary = AD.load_file(P51_PATH)
	_check("coupled target is the positive-inertia P-51 shaft model", p51_data.ok
		and p51_data.model.id == P51_ID and Prop.has_shaft(p51_data.model.propulsion)
		and p51_data.model.propulsion.rotor_inertia > 0.0)
	_mode_and_legacy_paths()
	_coupling_physics()
	_stage_local_integration()
	_joint_callback_falls_back_to_legacy()
	_wind_time_purity()
	_transported_wash_and_replay()
	_fault_rollback("stage")
	_fault_rollback("gyro")
	_fault_rollback("derivative")
	_fault_rollback("missing_field")
	_fault_rollback("wrong_float32")
	_fault_rollback("wrong_width")
	_fault_rollback("wrong_type")
	_fault_rollback("projection")
	_reset_joint_payload_rollback()
	_trace_integrity()
	_pending_restore()
	print("G2 coupled shaft: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
