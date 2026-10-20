# AV-19/20: explicit turbine integration, independent impulse/governor oracles and real-session lifecycle.
# Synthetic force/lag fixtures keep prescribed mass to isolate the governor oracle.
# Production finite stores/cutoff are verified by test_liquid_fuel_session.gd.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Turbine := preload("res://physics/turbine.gd")
const Trace := preload("res://sim/trace.gd")
const Recorder := preload("res://sim/recorder.gd")
const M := preload("res://physics/math3d.gd")
const DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const ID := "sebart-avanti-s-a200-p100rx"

var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func _flight() -> Node:
	var f: Node = Flight.new()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	var fixture: Dictionary = AD.validate_and_derive(raw)
	# File loading resolves the independent wheel-profile asset. Keep that resolved
	# binding in this prescribed governor fixture, rather than downgrading contact.
	var file_data: Dictionary = AD.load_file(DATA)
	fixture.model.wheel_profile = file_data.model.wheel_profile.duplicate(true)
	var bytes: PackedByteArray = JSON.stringify(raw, "", true, true).to_utf8_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	fixture.input_identity = {format = AD.FORMAT, sha256 = hash.finish().hex_encode()}
	f.setup("synthetic://prescribed-turbine-governor", ID, fixture)
	f.input_enabled = false
	return f


func _bits(sim: Node) -> PackedByteArray:
	return var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs,
		sim.last_loads, sim.tick, sim.mass, sim.inertia])


func _advance(f: Node, count: int) -> void:
	for _at: int in count:
		f.sim.step()


func _trace_ok(trace: RefCounted, rows: int) -> bool:
	if trace.row_count() != rows or not trace.is_continuous() or trace.to_csv().is_empty():
		return false
	for row: int in rows:
		for column: String in trace.columns():
			if not is_finite(trace.value(row, column)):
				return false
	return true


func _schema() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_check("authored aircraft explicitly selects RK4", raw.propulsion.engine.spool_integrator == "rk4")
	var absent: Dictionary = raw.duplicate(true)
	absent.propulsion.engine.erase("spool_integrator")
	absent.propulsion.erase("fuel_consumption")
	absent.capabilities.energy = "prescribed_fuel"
	var historical: Dictionary = AD.validate_and_derive(absent)
	_check("absent integration preserves historical sampled branch", historical.ok
		and not historical.model.propulsion.has("spool_integrator") and not Turbine.is_continuous(historical.model.propulsion))
	for invalid: Variant in ["RK4", "rk45", true, 0, null, {}]:
		var candidate: Dictionary = raw.duplicate(true)
		candidate.propulsion.engine.spool_integrator = invalid
		_check("unsupported integration is refused: " + str(invalid), not AD.validate_and_derive(candidate).ok)
	var wrong_branch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	wrong_branch.propulsion.engine.spool_integrator = "rk4"
	_check("turbine selection rejected on a combustion propeller", not AD.validate_and_derive(wrong_branch).ok)
	var f: Node = _flight()
	_check("continuous aircraft prepares and has one evolving RPM", f.is_flyable() and f.turbine_is_continuous()
		and f.sim.continuous.size() == 1 + f.wheel_count() and f.sim.continuous[0] == f.sim.aux[0])
	var bad: Dictionary = f.aircraft.duplicate(true)
	bad.model.propulsion.accel_limit = PackedFloat64Array([44000.0, 1.0, 44000.0001, 1000000.0])
	var before: PackedByteArray = _bits(f.sim)
	_check("stiff schedule refused before accepted flight changes", not f._apply(bad) and _bits(f.sim) == before)
	var prop: Dictionary = f.aircraft.model.propulsion.duplicate(true)
	prop.governor_tau = 0.02
	_check("minimum authored governor supports 240 Hz envelope", Turbine.step_supported(prop, 1.0 / 240.0))
	_check("coarse governor step refused", not Turbine.step_supported(prop, 0.02))
	f.free()


func _stage() -> void:
	var f: Node = _flight()
	var prop: Dictionary = f.aircraft.model.propulsion
	prop.static_thrust = PackedFloat64Array([0.0, 0.0, prop.max_rpm, 100.0])
	prop.mass_flow = PackedFloat64Array([0.0, 0.1, prop.max_rpm, 0.1])
	prop.installed_factor = 1.0
	prop.ram_flow = 0.0
	prop.ram_jet = PackedFloat64Array([0.0, 0.0, prop.max_rpm, 0.0])
	var before: PackedByteArray = _bits(f.sim)
	var stage: PackedFloat64Array = f.sim.continuous.duplicate()
	stage[0] = 70000.0
	var low: Dictionary = f._turbine_evaluate(f.sim.state, stage, f.sim.time())
	stage[0] = 140000.0
	var high: Dictionary = f._turbine_evaluate(f.sim.state, stage, f.sim.time())
	_check("stage force uses stage RPM rather than sampled mirror", not low.is_empty() and not high.is_empty()
		and absf(high.loads[0] - low.loads[0] - 100.0 * 70000.0 / float(prop.max_rpm)) < 1e-10)
	var expected_h: float = float(prop.rotor_inertia) * float(prop.rotor_sense) * 140000.0 * TAU / 60.0
	_check("stage gyro uses stage RPM", absf(high.rotor_momentum[0] - expected_h) < 1e-12)
	_check("stage observation cannot advance committed state", _bits(f.sim) == before)
	stage[0] = -1.0
	var below: bool = f._turbine_evaluate(f.sim.state, stage, 0.0).is_empty()
	stage[0] = prop.max_rpm + 1.0
	_check("malformed or out-of-domain state rejected", f._turbine_evaluate(f.sim.state, PackedFloat64Array(), 0.0).is_empty()
		and below and f._turbine_evaluate(f.sim.state, stage, 0.0).is_empty())
	var observed: Dictionary = f.turbine_state()
	_check("endpoint telemetry exposes flow without changing prescribed mass", observed.ok
		and observed.rpm == f.sim.continuous[0] and observed.fuel_flow_kg_s > 0.0
		and observed.fuel_mass_policy == "prescribed_fuel" and _bits(f.sim) == before)
	f.free()


## Pure closed-loop governor from the actual session, with a synthetic linear RPM force and no aero/gravity.
## Its analytic impulse and displacement independently expose the endpoint-held force defect.
func _analytic(hz: int) -> PackedFloat64Array:
	Engine.physics_ticks_per_second = hz
	var f: Node = _flight()
	var prop: Dictionary = f.aircraft.model.propulsion
	prop.throttle_map = PackedFloat64Array([0.0, prop.idle_rpm, 1.0, prop.max_rpm])
	prop.accel_limit = PackedFloat64Array([0.0, 1000000.0, prop.max_rpm, 1000000.0])
	prop.decel_limit = prop.accel_limit.duplicate()
	prop.governor_tau = 0.4
	var n0: float = 90000.0
	var target: float = 91000.0
	var duration: float = 1.0
	var force_per_rpm: float = 0.001
	f.sim.inputs[3] = (target - float(prop.idle_rpm)) / (float(prop.max_rpm) - float(prop.idle_rpm))
	f.sim.aux[0] = n0
	f.sim.continuous[0] = n0
	f.sim.gravity = 0.0
	var native: Callable = f.sim.model.stage
	f.sim.model.stage = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = native.call(s, c, t)
		if result.is_empty():
			return result
		result.loads = PackedFloat64Array([force_per_rpm * c[0], 0.0, 0.0, 0.0, 0.0, 0.0])
		result.rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])
		return result
	var initial := PackedFloat64Array([0.0, 0.0, -1000.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_check("analytic fixture resets at %d Hz" % hz, f.sim.reset(initial))
	_advance(f, hz)
	var decay: float = M.exp_(-duration / 0.4)
	var n_exact: float = target + (n0 - target) * decay
	var v_exact: float = force_per_rpm / f.sim.mass * (target * duration + (n0 - target) * 0.4 * (1.0 - decay))
	var x_exact: float = force_per_rpm / f.sim.mass * (target * duration * duration / 2.0
		+ (n0 - target) * 0.4 * (duration - 0.4 * (1.0 - decay)))
	var errors := PackedFloat64Array([absf(f.sim.continuous[0] - n_exact), absf(f.sim.state[3] - v_exact), absf(f.sim.state[0] - x_exact)])
	_check("governor/impulse/displacement analytic agreement at %d Hz" % hz,
		f.sim.fault_reason.is_empty() and errors[0] < 5e-6 and errors[1] < 5e-10 and errors[2] < 5e-10, str(errors))
	_check("k1 load uses old RPM while aux mirrors accepted endpoint at %d Hz" % hz,
		f.sim.last_loads[0] < force_per_rpm * f.sim.aux[0] and f.sim.aux[0] == f.sim.continuous[0])
	f.free()
	return errors


func _lifecycle() -> void:
	var f: Node = _flight()
	f.sim.inputs[3] = 0.5
	_advance(f, 37)
	var saved: Dictionary = f.checkpoint()
	_check("turbine checkpoint identifies continuous law", saved.get("format") == "openrc-flight-checkpoint v8"
		and saved.get("turbine_law") == Turbine.CONTINUOUS_LAW)
	_advance(f, 40)
	var expected: PackedByteArray = _bits(f.sim)
	_check("checkpoint restore succeeds", f.restore_checkpoint(saved))
	_advance(f, 40)
	_check("full body/RPM/aux/modes continuation exactly repeats", _bits(f.sim) == expected)
	var invalid: Dictionary = saved.duplicate(true)
	invalid.simulation.continuous[0] += 1.0
	_check("inconsistent endpoint mirror refused transactionally", not f.restore_checkpoint(invalid) and _bits(f.sim) == expected)
	invalid = saved.duplicate(true)
	invalid.format = "openrc-flight-checkpoint v1"
	_check("historical sampled snapshot cannot masquerade as continuous", not f.restore_checkpoint(invalid))
	invalid = saved.duplicate(true)
	invalid.turbine_law = "unidentified"
	_check("wrong model-law snapshot refused", not f.restore_checkpoint(invalid))
	invalid = saved.duplicate(true)
	invalid.simulation.modes[0] = 0
	_check("unsupported hot off-state snapshot refused", not f.restore_checkpoint(invalid))
	f.sim.set_paused(false)
	f.hold("test")
	var held: PackedByteArray = _bits(f.sim)
	f._physics_process(1.0)
	_check("session hold freezes all turbine state", _bits(f.sim) == held)
	f.release("test")
	f.reset()
	var before: PackedByteArray = _bits(f.sim)
	var native: Callable = f.sim.model.stage
	var fault_at: float = f.sim.time() + f.sim.dt() / 2.0
	f.sim.model.stage = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = native.call(s, c, t)
		if t >= fault_at:
			result.derivative[0] = NAN
		return result
	f.sim.step()
	_check("failed RK stage rolls back complete turbine/body transaction", not f.sim.fault_reason.is_empty() and _bits(f.sim) == before)
	f.sim.model.stage = native
	f.reset()
	_check("explicit reset clears fault and rebuilds settled RPM", f.sim.fault_reason.is_empty()
		and f.sim.continuous[0] == f.start.rpm and f.sim.aux[0] == f.start.rpm)
	var running_bits: PackedByteArray = _bits(f.sim)
	f.engine_running = false
	f.sim.step()
	_check("unsupported hot mode switch refuses an instantaneous RPM cut", not f.sim.fault_reason.is_empty()
		and _bits(f.sim) == running_bits)
	f.reset()
	var recorder: RefCounted = Recorder.new(f.sim)
	recorder.start(f.trace_meta())
	_advance(f, 12)
	recorder.detach()
	_check("trace retains 13 fresh complete finite rows", _trace_ok(recorder.trace, 13))
	var malformed: Dictionary = f.trace_meta()
	malformed.recording_start_continuous = "[true]"
	var trace: RefCounted = Trace.new()
	trace.meta = malformed
	trace.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs, f.sim.aux)
	_check("writer refuses invalid turbine metadata", trace.to_csv().is_empty())
	var bad_header: Dictionary = f.trace_meta()
	bad_header.recording_start_aux = JSON.stringify([f.sim.aux[0], null, 0.0, 0.0])
	var bad_servo: RefCounted = Trace.new()
	bad_servo.meta = bad_header
	bad_servo.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs, f.sim.aux)
	_check("calm writer refuses null servo in turbine header", bad_servo.to_csv().is_empty())
	var bad_row: RefCounted = Trace.new()
	bad_row.meta = f.trace_meta()
	var bad_aux: PackedFloat64Array = f.sim.aux.duplicate()
	bad_aux[1] = NAN
	bad_row.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs, bad_aux)
	_check("calm writer refuses nonfinite servo row", bad_row.to_csv().is_empty())
	var frozen: RefCounted = Trace.new()
	frozen.meta = f.trace_meta()
	frozen.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs, f.sim.aux)
	var frozen_csv: String = frozen.to_csv()
	frozen.meta.turbine_integrator = "sampled"
	_check("physical turbine metadata freezes at first sample", not frozen_csv.is_empty() and frozen.to_csv() == frozen_csv)
	frozen.record(f.sim.tick + 2, (f.sim.tick + 2) * f.sim.dt(), f.sim.state, f.sim.last_loads, f.sim.inputs, f.sim.aux)
	_check("calm turbine writer refuses a missing tick", frozen.to_csv().is_empty())
	f.free()


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	_schema()
	_stage()
	var coarse: PackedFloat64Array = _analytic(120)
	var standard: PackedFloat64Array = _analytic(240)
	var fine: PackedFloat64Array = _analytic(480)
	_check("smooth RPM refinement exhibits fourth-order error reduction", coarse[0] / standard[0] > 12.0 and standard[0] / fine[0] > 8.0,
		str([coarse[0], standard[0], fine[0]]))
	Engine.physics_ticks_per_second = original_hz
	_lifecycle()
	_check("all planned checks executed", checks == 45)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
