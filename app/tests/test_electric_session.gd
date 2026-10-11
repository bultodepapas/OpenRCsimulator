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


func _initialize() -> void:
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
