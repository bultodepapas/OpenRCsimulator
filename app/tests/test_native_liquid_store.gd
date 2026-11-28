extends SceneTree
## NK-6t: the native liquid stage's LiquidFlight.valid answer equals the reference on valid and broken stores (NaN,
## negative, beyond usable capacity, latch values, an empty store with the latch set, wrong sizes); inside the guarded
## tick the lazily built contact sampler answers exactly as LiquidFlight.contact_sampler does; and two native P-51
## sessions, one building the sampler through the reference, keep identical checkpoints from an airborne start, power
## off and nose down, into ground contact. Skips (passes) without the verified library.

const Session := preload("res://sim/flight_session.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const TICKS := 2400

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _session(native_store: bool) -> Node:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.native_liquid_store_enabled = native_store
	session.setup_stage_backend("native")
	session.setup("res://data/aircraft/p51d_mustang_120.json", "p51d-mustang-120")
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	return session


func _run() -> void:
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stage_liquid_store_valid"):
		print("NK6T_SKIP no native library with the liquid store check")
		quit(0)
		return
	var sessions: Array = [_session(true), _session(false)]
	var native: Node = sessions[0]
	var reference: Node = sessions[1]
	var both_native: bool = native.stage_backend_identity().get("backend", "") == "native" 		and reference.stage_backend_identity().get("backend", "") == "native" and native._native_stage != null
	_check("both sessions fly on the native liquid stage", both_native)
	if not both_native:
		print("native liquid store: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	# 1. The native validity equals LiquidFlight.valid.
	var rng := RandomNumberGenerator.new()
	rng.seed = 6116
	var index: int = native._liquid_index()
	var base: PackedFloat64Array = native.sim.continuous
	var limit: float = float(native.aircraft.model.propulsion.liquid_fuel.capacity_kg) \
		- float(native.aircraft.model.propulsion.liquid_fuel.unusable_kg)
	var mismatched := 0
	var invalid := 0
	for i: int in 6000:
		var values: PackedFloat64Array = base.duplicate()
		values[index] = [0.0, -0.0, limit, limit + 1e-9, -1e-12, rng.randf_range(0.0, limit), rng.randf_range(-1.0, limit + 1.0)][i % 7]
		values[index + 1] = [0.0, 1.0, -0.0, 0.5, 1.0, 0.0][i % 6]
		if i % 13 == 0:
			values[rng.randi_range(0, values.size() - 1)] = [NAN, INF, -INF][i % 3]
		if i % 17 == 0:
			values.resize(values.size() + [1, -1][i % 2])
		var expected: int = 1 if LiquidFlight.valid(native, values) else 0
		invalid += 1 - expected
		if native._native_stage.liquid_store_valid(values, index) != expected:
			mismatched += 1
	_check("native store validity equals LiquidFlight.valid (%d invalid of 6000)" % invalid, mismatched == 0 and invalid > 1000,
		str(mismatched))
	# 2. Inside the guarded tick, the lazy sampler answers as the reference sampler.
	for session: Node in sessions:
		session.sim.step()
	var before: PackedFloat64Array = native.sim.continuous.duplicate()
	var after: PackedFloat64Array = before.duplicate()
	after[index] = maxf(0.0, before[index] - 0.01)
	native._native_endpoint_tick = native.sim.tick + 1 # as the guarded pre-step leaves it
	var lazy: Callable = native._contact_mass_sampler(before, after)
	var direct: Callable = LiquidFlight.contact_sampler(native, before, after)
	var sample_mismatch := 0
	for i: int in 200:
		var fraction: float = [0.0, 1.0, -0.1, 1.5, NAN][i % 5] if i < 5 else rng.randf()
		if var_to_bytes(lazy.call(fraction)) != var_to_bytes(direct.call(fraction)):
			sample_mismatch += 1
	native._native_endpoint_tick = -1
	_check("the lazy sampler answers as LiquidFlight.contact_sampler", lazy.is_valid() and sample_mismatch == 0,
		str(sample_mismatch))
	# 3. Lockstep flight into the ground: power off, nose down.
	for session: Node in sessions:
		session.sim.inputs[3] = 0.0
		session.sim.inputs[1] = -0.35
	var diverged := -1
	var lowest := INF
	for tick: int in TICKS:
		for session: Node in sessions:
			session.sim.step()
		lowest = minf(lowest, -native.sim.state[2])
		if var_to_bytes(native.checkpoint()) != var_to_bytes(reference.checkpoint()):
			diverged = tick
			break
	_check("native and reference samplers keep identical checkpoints into ground contact (lowest %.2f m)" % lowest,
		diverged < 0 and lowest < 1.0, "diverged at tick %d" % diverged)
	print("native liquid store: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
