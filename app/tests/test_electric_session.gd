# EL1d/e: real electric loader/trim/session, mode, telemetry, replay and rollback.
extends SceneTree
const Flight: Script = preload("res://sim/flight_session.gd")
const Recorder: Script = preload("res://sim/recorder.gd")
const Trace: Script = preload("res://sim/trace.gd")
const Weather: Script = preload("res://physics/wind_config.gd")
const M: Script = preload("res://physics/math3d.gd")
const RB: Script = preload("res://physics/rigid_body.gd")
const Dynamics: Script = preload("res://physics/dynamics.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")
const PATHS: Array[String] = ["res://data/aircraft/synthetic_stik_electric_4s.json", "res://data/aircraft/synthetic_stik_electric_6s.json"]
const BATTERY_PATH: String = "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
var checks: int = 0
var failures: int = 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
func flight(path: String) -> Node:
	var value: Node = Flight.new()
	value.setup(path)
	value.input_enabled = false
	return value
func advance(value: Node, count: int) -> bool:
	var initial: int = value.sim.tick
	for i: int in count:
		value.sim.step()
		if not value.sim.fault_reason.is_empty():
			print("flight fault: ", value.sim.fault_reason)
			return false
	return value.sim.tick == initial + count


func check_rest_coupling(path: String) -> void:
	var a: Node = flight(path)
	a.engine_running = false
	a.sim.inputs[3] = 0.0
	var prop: Dictionary = a.aircraft.model.propulsion
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var inverse: PackedFloat64Array = RB.inertia_inverse(a.sim.inertia)
	var jr: float = prop.rotor_inertia
	var friction: float = 60.0 / (TAU * prop.motor.kv_rpm_per_volt) * prop.motor.no_load_current_a
	var carrier: float = 1.0 - jr * M.dot(axis, RB.inertia_mul(inverse, axis))
	for rates: PackedFloat64Array in [PackedFloat64Array([0.0, 4.0, 4.0]), PackedFloat64Array([0.0, 10.0, 10.0]), PackedFloat64Array([0.0, -10.0, 10.0])]:
		var state: PackedFloat64Array = a.sim.state.duplicate()
		for i: int in 3:
			state[3 + i] = 0.0
			state[10 + i] = rates[i]
		var lag: int = a.downwash_index()
		# Shared external aerodynamics are inputs to this independent angular-momentum equation.
		# The expected acceleration never calls the production rotor-coupling solver.
		var external: PackedFloat64Array = Dynamics.loads(state, a.aircraft.model, a._deflections(a.sim.aux),
			0.0, a.air_density(), a.wind_at(0.0), a.sim.aux[lag] if lag >= 0 else NAN)
		var alpha_free: PackedFloat64Array = RB.inertia_mul(inverse,
			M.sub(external.slice(3, 6), M.cross(rates, RB.inertia_mul(a.sim.inertia, rates))))
		var required: float = jr * M.dot(axis, alpha_free)
		var continuous := PackedFloat64Array()
		continuous.resize(1 + a.wheel_count())
		var response: Dictionary = a._coupled_response(state, continuous, 0.0)
		if absf(required) <= friction:
			check("static bearing holds body-driven relative rest", response.ok and response.spin_acceleration == 0.0)
		elif required < -friction:
			var expected: float = (-friction / jr - M.dot(axis, alpha_free)) / carrier
			check("body-driven forward breakaway retains bearing loss", response.ok and expected > 0.0 and absf(response.spin_acceleration - expected) < 1e-10)
		else:
			check("body-driven reverse breakaway is refused", not response.ok)
	a.free()


func _arrays_close(got: PackedFloat64Array, want: PackedFloat64Array, tolerance: float) -> bool:
	if got.size() != want.size():
		return false
	for i: int in got.size():
		if not is_finite(got[i]) or not is_finite(want[i]) or absf(got[i] - want[i]) > tolerance:
			return false
	return true


func _array_distance(got: PackedFloat64Array, want: PackedFloat64Array) -> float:
	if got.size() != want.size():
		return INF
	var squared: float = 0.0
	for i: int in got.size():
		squared += (got[i] - want[i]) * (got[i] - want[i])
	return sqrt(squared)


## Independent rigid-point velocity: propulsion offsets are [aft, right, up] while state rates are FRD.
func _hub_air_velocity_hand(state: PackedFloat64Array, datum_air: PackedFloat64Array,
		offset: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = -offset[0]
	var y: float = offset[1]
	var z: float = -offset[2]
	var p: float = state[RB.RATE]
	var q: float = state[RB.RATE + 1]
	var r: float = state[RB.RATE + 2]
	return PackedFloat64Array([datum_air[0] + q * z - r * y,
		datum_air[1] + r * x - p * z, datum_air[2] + p * y - q * x])


func check_hub_inflow(path: String, label: String) -> void:
	var a: Node = flight(path)
	check(label + " session is flyable", a.is_flyable())
	if not a.is_flyable():
		a.free()
		return
	a.engine_running = true
	a.sim.inputs[3] = 0.72
	var prop: Dictionary = a.aircraft.model.propulsion
	# Give this regression a supported, off-axis installation so q/r produce a sizeable axial hub-flow delta.
	# The published demo uses a centreline shaft; this remains a test-only in-memory model mutation.
	prop.offset = PackedFloat64Array([-0.414176, 0.08, 0.11])
	var rpm: float = a.sim.continuous[0]
	var values: PackedFloat64Array = a.sim.continuous.duplicate()
	var state: PackedFloat64Array = a.sim.state.duplicate()
	state[RB.POS + 2] = -20.0 # keep the local probe clear of ground contacts
	state[RB.RATE] = 1.5
	state[RB.RATE + 1] = 6.0
	state[RB.RATE + 2] = 4.0
	var rho: float = a.air_density(state)
	var wind: PackedFloat64Array = a.wind_at(0.0)
	var air: Dictionary = a.air_data(state, 0.0)
	var hub_air: PackedFloat64Array = _hub_air_velocity_hand(state, air.v_air, prop.offset)
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	check(label + " rate and offset change prop axial inflow",
		absf(M.dot(hub_air, axis) - M.dot(air.v_air, axis)) > 0.5)

	# Zero-rate positive control: the hub and datum velocities coincide, and the legacy result remains valid.
	var zero_rate_state: PackedFloat64Array = state.duplicate()
	for i: int in 3:
		zero_rate_state[RB.RATE + i] = 0.0
	var zero_air: Dictionary = a.air_data(zero_rate_state, 0.0)
	var zero_expected: PackedFloat64Array = Propulsion.loads(zero_air.v_air, rpm, prop, rho)
	var zero_dynamics: Dictionary = Dynamics.evaluate(zero_rate_state, a.aircraft.model,
		a._deflections(a.sim.aux), rpm, rho, wind, a.sim.gravity)
	check(label + " zero-rate propulsion loads match the datum-flow control",
		_arrays_close(zero_dynamics.propulsion_loads, zero_expected, 1e-10))

	# The explicit propeller loads in Dynamics must use the hand-computed local hub flow at nonzero p/q/r.
	var expected_loads: PackedFloat64Array = Propulsion.loads(hub_air, rpm, prop, rho)
	var dynamics: Dictionary = Dynamics.evaluate(state, a.aircraft.model, a._deflections(a.sim.aux),
		rpm, rho, wind, a.sim.gravity)
	print(label, " hub-flow load norm error = ", _array_distance(dynamics.propulsion_loads, expected_loads),
		"; expected = ", expected_loads, "; actual = ", dynamics.propulsion_loads)
	check(label + " Dynamics propeller loads use local hub velocity",
		_arrays_close(dynamics.propulsion_loads, expected_loads, 1e-10))

	# Exercise the real session coupling and close angular momentum without calling RotorCoupling for the oracle.
	var response: Dictionary = a._coupled_response(state, values, 0.0)
	check(label + " coupled session stage evaluates", response.get("ok", false))
	if response.get("ok", false):
		var motor_torque: float
		if a.battery_is_dynamic():
			motor_torque = float(response.battery.shaft_torque_nm)
		else:
			var source: Dictionary = Propulsion.electric_source_state(rpm, a.propulsion_throttle(), prop,
				a.propulsion_power_enabled())
			motor_torque = float(source.shaft_torque_nm)
		var propeller_torque: float = Propulsion.prop_torque(rpm, M.dot(hub_air, axis), prop, rho)
		var body_derivative: PackedFloat64Array = RB.derivative(state, a.sim.mass, a.sim.inertia,
			RB.inertia_inverse(a.sim.inertia), response.loads.slice(0, 3), response.loads.slice(3, 6),
			a.sim.gravity, Dynamics.rotor_momentum(a.aircraft.model, rpm))
		var body_alpha: PackedFloat64Array = body_derivative.slice(RB.RATE, RB.RATE + 3)
		var shaft_absolute_acceleration: float = float(prop.rotor_inertia) * \
			(float(response.spin_acceleration) + M.dot(axis, body_alpha))
		var shaft_torque_difference: float = motor_torque - propeller_torque
		print(label, " hub-flow angular-momentum residual = ",
			shaft_absolute_acceleration - shaft_torque_difference, " Nm")
		check(label + " angular-momentum balance uses hub propeller torque",
			absf(shaft_absolute_acceleration - shaft_torque_difference) < 1e-8)
	a.free()


func _initialize() -> void:
	check_hub_inflow(PATHS[0], "fixed-voltage")
	check_hub_inflow(BATTERY_PATH, "dynamic-battery")
	for path: String in PATHS:
		check_rest_coupling(path)
		var a: Node = flight(path)
		check("electric auto-selects the coupled solver", a.is_flyable() and a.shaft_is_coupled())
		if not a.is_flyable():
			a.free()
			continue
		var start_rpm: float = a.sim.aux[0]
		var stiff: Dictionary = a.aircraft.duplicate(true)
		stiff.model.propulsion.rotor_inertia = 1e-8
		var stiff_before: PackedByteArray = var_to_bytes(a.checkpoint())
		var rejected: Dictionary = a._prepare_aircraft(stiff)
		check("stiff electric source refused before launch transactionally", not rejected.ok and "too stiff" in rejected.message and var_to_bytes(a.checkpoint()) == stiff_before)
		var record: RefCounted = Recorder.new(a.sim, a.electrical_state)
		record.start(a.trace_meta())
		check("five-second real trimmed electric flight advances", advance(a, 1200))
		check("trimmed RPM remains at equilibrium", absf(a.sim.aux[0] - start_rpm) < 0.01)
		check("trace includes each tick including initial", record.trace.row_count() == 1201)
		check("electric trace explicitly versioned", record.trace.to_csv().begins_with("# format: openrc-trace v7\n"))
		check("electric trace current is a finite measured plane", record.trace.value(1200, "drive_bus_current_a") > 0.0)
		var before_pause: PackedByteArray = var_to_bytes(a.checkpoint())
		a.hold("electric test")
		a.sim._physics_process(a.sim.dt())
		check("pause freezes full physics state", var_to_bytes(a.checkpoint()) == before_pause)
		a.engine_running = false
		var prior_rpm: float = a.sim.aux[0]
		check("source off preserves mechanical spin", a.sim.aux[0] == prior_rpm and a.electrical_state().battery_current_a == 0.0)
		check("coast tick advances", advance(a, 1))
		check("source-off trace uses endpoint mode", record.trace.value(1201, "drive_enabled") == 0.0 and record.trace.value(1201, "drive_bus_current_a") == 0.0)
		var saved: Dictionary = bytes_to_var(var_to_bytes(a.checkpoint()))
		check("electric checkpoint version and law explicit", saved.get("format") == "openrc-flight-checkpoint v5" and saved.get("electric_law") == Flight.ELECTRIC_LAW)
		var b: Node = flight(path)
		check("fresh session restores native electric checkpoint", b.restore_checkpoint(saved))
		check("source-off mode survives restore", not b.engine_running)
		check("both continuations advance", advance(a, 120) and advance(b, 120))
		check("fresh continuation is byte-identical", var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
		var independent: PackedByteArray = var_to_bytes(b.checkpoint())
		check("first session advances alone", advance(a, 1))
		check("second session state is independent", var_to_bytes(b.checkpoint()) == independent)
		var wrong: Dictionary = saved.duplicate(true)
		wrong.electric_law = "other-law"
		check("wrong electrical law refused transactionally", not b.restore_checkpoint(wrong) and var_to_bytes(b.checkpoint()) == independent)
		wrong = saved.duplicate(true)
		wrong.simulation.continuous[0] = -1.0
		wrong.simulation.aux[0] = -1.0
		check("negative saved RPM refused transactionally", not b.restore_checkpoint(wrong) and var_to_bytes(b.checkpoint()) == independent)
		var missing_sampler: RefCounted = Trace.new()
		missing_sampler.meta = a.trace_meta()
		missing_sampler.record(a.sim.tick, a.sim.time(), a.sim.state, a.sim.last_loads, a.sim.inputs, a.sim.aux)
		check("electrical trace refuses missing sampler", missing_sampler.to_csv() == "")
		for defect: String in ["identity", "sample_time", "nonfinite", "sample_mode"]:
			var bad_trace: RefCounted = Trace.new()
			bad_trace.meta = a.trace_meta()
			var point: Dictionary = a.electrical_state()
			match defect:
				"identity": bad_trace.meta.propulsion_model = "propeller-shaft-coupled-rk4-v1"
				"sample_time": point.time_s += a.sim.dt()
				"nonfinite": point.motor_current_a = NAN
				"sample_mode": point.enabled = 1
			bad_trace.electrical_sample = func() -> Dictionary: return point
			bad_trace.record(a.sim.tick, a.sim.time(), a.sim.state, a.sim.last_loads, a.sim.inputs, a.sim.aux)
			check("electric trace refuses " + defect, bad_trace.to_csv() == "" and bad_trace.row_count() == 0)
		var stopped: Node = flight(path)
		stopped.engine_running = false
		for at: int in range(3, 6):
			stopped.sim.state[at] = 0.0
		for at: int in range(10, 13):
			stopped.sim.state[at] = 0.0
		stopped.sim.continuous[0] = 0.5
		stopped.sim.aux[0] = 0.5
		var crossing: Dictionary = bytes_to_var(var_to_bytes(stopped.checkpoint()))
		var crossing_copy: Node = flight(path)
		check("restore immediately before physical stop", crossing_copy.restore_checkpoint(crossing))
		check("low-speed coast reaches exact rest within one tick", advance(stopped, 1) and stopped.sim.continuous[0] == 0.0)
		check("stop replay is exact", advance(crossing_copy, 1) and var_to_bytes(stopped.checkpoint()) == var_to_bytes(crossing_copy.checkpoint()))
		check("source disabled holds at relative rest", advance(stopped, 3) and stopped.sim.aux[0] == 0.0)
		stopped.engine_running = true
		stopped.sim.inputs[3] = 0.7
		check("enabled duty restarts actual session from rest", advance(stopped, 2) and stopped.sim.aux[0] > 0.0)
		stopped.reset()
		check("reset restores prescribed powered trim", stopped.sim.tick == 0 and stopped.engine_running and absf(stopped.sim.aux[0] - start_rpm) < 0.01)
		stopped.free()
		crossing_copy.free()
		var original_r: float = a.aircraft.model.propulsion.motor.resistance_ohm
		var tick: int = a.sim.tick
		var prior: PackedFloat64Array = a.sim.state.duplicate()
		var prior_continuous: PackedFloat64Array = a.sim.continuous.duplicate()
		a.aircraft.model.propulsion.motor.resistance_ohm = -1.0
		a.sim.step()
		check("source fault rolls back body and shaft", not a.sim.fault_reason.is_empty() and a.sim.tick == tick and a.sim.state == prior and a.sim.continuous == prior_continuous)
		a.aircraft.model.propulsion.motor.resistance_ohm = original_r
		record.detach()
		a.free()
		b.free()
	# Version 7 composes electrical samples with the existing atmosphere and seeded-weather layout.
	for preset: String in ["turbulent", "hot-high"]:
		var a: Node = Flight.new()
		check("electric environment accepted", a.setup_weather(Weather.preset(preset)))
		a.setup(PATHS[0])
		a.input_enabled = false
		check("electric environment trim flyable", a.is_flyable())
		var recorder: RefCounted = Recorder.new(a.sim, a.electrical_state)
		recorder.start(a.trace_meta())
		check("weather electric flight advances", advance(a, 120))
		check("weather electric v7 records every endpoint", recorder.trace.row_count() == 121 and recorder.trace.to_csv().begins_with("# format: openrc-trace v7\n"))
		var b: Node = flight(PATHS[0])
		check("fresh electric session restores changed weather", b.restore_checkpoint(bytes_to_var(var_to_bytes(a.checkpoint()))))
		check("electric weather replay includes RNG and atmosphere", advance(a, 120) and advance(b, 120) and var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
		var other: Node = flight(PATHS[1])
		var before: PackedByteArray = var_to_bytes(other.checkpoint())
		check("different electric configuration refuses checkpoint transactionally", not other.restore_checkpoint(a.checkpoint()) and var_to_bytes(other.checkpoint()) == before)
		recorder.detach()
		a.free()
		b.free()
		other.free()
	var split: Node = Flight.new()
	check("explicit legacy choice accepted before load", split.setup_shaft_integrator("split"))
	split.setup(PATHS[0])
	check("explicit split electric combination refused", not split.is_flyable())
	split.free()
	print("EL1d electric session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
