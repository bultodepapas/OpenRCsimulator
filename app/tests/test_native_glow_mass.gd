extends SceneTree
## NK-6e: inside a guarded tick the native glow stage answers GlowFlight.valid(values) and
## GlowFlight.mass_context(session, values).ok for the contact mass sampler and the auxiliary projection
## (FlightSession._native_glow_mass_check). For every native glow aircraft:
## - perturbed stores at every bound valid() and mass_context() check (counts, flags, reason codes, accumulator, phase,
##   temperature, mixture, rpm, fuel against capacity and reserve, line liquid, source modes, NaN): every answer equals
##   the reference, both ways;
## - takeoffs, landings (the hull terminal check asks the lazy contact sample on the ground) and fuel exhaustion fly
##   byte-identical with and without the answer;
## - refusals: outside the guarded tick, the hook off, a derived session class.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 3000

class DerivedSession extends "res://sim/flight_session.gd":
	pass

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _fleet: PackedStringArray = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 62626
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var probe := _session(id, Flight.START_RUNWAY)
		if probe == null:
			continue
		if probe.glow_is_active() and probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE \
				and probe._native_stage._glow_mass_bound:
			_fleet.append(id)
		elif probe.glow_is_active():
			print("NK6E_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		probe.free()
	if _fleet.is_empty():
		print("NK6E_GLOW_MASS_SKIP no native glow session")
		print("native glow mass: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	print("NK6E_FLEET ", _fleet)
	for id: String in _fleet:
		_direct(id)
		_pair(id, "takeoff")
		_pair(id, "landing")
		_pair(id, "fuel")
	_refusals(_fleet[0])
	print("native glow mass: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start: String, derived := false) -> Node:
	var s: Node = DerivedSession.new() if derived else Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	if not s.is_flyable():
		s.free()
		return null
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## Enter the guarded tick as Simulation.step does (the session's pre-step installs the native context).
func _enter_tick(s: Node) -> void:
	s._kernel_pre_step(s.sim.aux.duplicate(), s.sim.inputs.duplicate(), s.sim.dt())


func _direct(id: String) -> void:
	var s := _session(id, Flight.START_RUNWAY)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.1, yaw = 0.0, throttle = 1.0}
	for i in 240:
		_tick(s)
	_enter_tick(s)
	var install: Dictionary = s.aircraft.model.propulsion.glow
	var origin: PackedFloat64Array = s.sim.continuous.duplicate()
	var stats := {valid_true = 0, valid_false = 0, mass_true = 0, mass_false = 0, mismatched = 0, refused = 0}
	var first := ""
	for i in SAMPLES:
		var values := _perturb(origin, install)
		var native_valid: int = s._native_glow_mass_check(values, false)
		var native_mass: int = s._native_glow_mass_check(values, true)
		var reference_valid: bool = GlowFlight.valid(values, install)
		var reference_mass: bool = bool(GlowFlight.mass_context(s, values).get("ok", false))
		if native_valid < 0 or native_mass < 0:
			stats.refused += 1
			continue
		stats["valid_true" if reference_valid else "valid_false"] += 1
		stats["mass_true" if reference_mass else "mass_false"] += 1
		if (native_valid == 1) != reference_valid or (native_mass == 1) != reference_mass:
			stats.mismatched += 1
			if first.is_empty():
				first = "native %d/%d reference %s/%s at %s " % [native_valid, native_mass, reference_valid, reference_mass, str(values)]
	_check(id + ": every answer equals GlowFlight.valid and mass_context().ok", stats.mismatched == 0, first + str(stats))
	_check(id + ": the stage answered inside the guarded tick", stats.refused == 0, str(stats))
	_check(id + ": both outcomes occurred for both checks", stats.valid_true > 100 and stats.valid_false > 100
		and stats.mass_true > 100 and stats.mass_false > 100, str(stats))
	print("NK6E_DIRECT %s %s" % [id, str(stats)])
	s.free()


## One store with a few slots pushed onto, just inside or just past the bounds valid() and mass_context() check.
func _perturb(origin: PackedFloat64Array, install: Dictionary) -> PackedFloat64Array:
	var v := origin.duplicate()
	var line: Dictionary = install.get("feed_line", {})
	var capacity: float = float(install.capacity_fuel_kg)
	var unusable: float = float(install.unusable_fuel_kg)
	var tiny := 1.0e-9
	for k in _rng.randi_range(1, 3):
		match _rng.randi_range(0, 17):
			0: v[0] = [0.0, -tiny, float(install.profile.operation.max_rpm), float(install.profile.operation.max_rpm) + 1.0,
				origin[0] * _rng.randf_range(0.0, 1.5)][_rng.randi_range(0, 4)]
			1: v[1] = [0.0, -tiny, capacity, capacity + tiny, unusable, unusable + tiny, unusable - tiny,
				float(install.total_capacity_kg) + tiny, origin[1] * _rng.randf()][_rng.randi_range(0, 8)]
			2: v[2] = [0.0, -1.0, 300.0, origin[2]][_rng.randi_range(0, 3)]
			3: v[3] = [-tiny, 0.0, 1.0, 1.0 + tiny, _rng.randf()][_rng.randi_range(0, 4)]
			4: v[4] = [-tiny, 0.0, 1.0, 1.0 + tiny, _rng.randf()][_rng.randi_range(0, 4)]
			5: v[5] = [-tiny, 0.0, origin[5]][_rng.randi_range(0, 2)]
			6: v[6] = [-tiny, 0.0, 0.99, 1.0, 2.0, 1.999999, origin[6]][_rng.randi_range(0, 6)]
			7: v[7] = [0.0, 1.0, 0.5, 2.0][_rng.randi_range(0, 3)]
			8: v[8] = [0.0, 3.0, 4.0, 6.0, 7.0, 1.5, -1.0][_rng.randi_range(0, 6)]
			9: v[9] = [0.0, 10.0, -1.0, 2.5, origin[9]][_rng.randi_range(0, 4)]
			10: v[10] = [0.0, 5.0, 11.0, -1.0, 0.5, origin[10]][_rng.randi_range(0, 5)]
			11: v[11] = [0.0, 0.5, 1.0, -tiny, 0.999999][_rng.randi_range(0, 4)]
			12: v[12] = [0.0, -tiny, 2.8, 2.8 + tiny, 1.15][_rng.randi_range(0, 4)]
			13: v[GlowFlight.LINE_FUEL_INDEX] = [0.0, -tiny, 1.0e-16, float(line.get("capacity_kg", 0.0)),
				float(line.get("capacity_kg", 0.0)) + tiny][_rng.randi_range(0, 4)]
			14: v[GlowFlight.SOURCE_MODE_INDEX] = [0.0, 1.0, 2.0, 3.0, 1.5, -1.0][_rng.randi_range(0, 5)]
			15: v[_rng.randi_range(0, v.size() - 1)] = NAN
			16: v[1] = v[GlowFlight.LINE_FUEL_INDEX] + unusable + [-tiny, 0.0, tiny, 0.0002][_rng.randi_range(0, 3)]
			17: pass
	return v


func _pair(id: String, scenario: String) -> void:
	var pair: Array = []
	for native in [true, false]:
		var s := _session(id, Flight.START_AIRBORNE if scenario == "landing" else Flight.START_RUNWAY)
		if s == null:
			for other: Node in pair:
				other.free()
			return
		s.native_glow_mass_enabled = native
		if scenario == "landing":
			var body: PackedFloat64Array = s.sim.state.duplicate()
			body[RB.POS + 2] = minf(body[RB.POS + 2], -3.0)
			body[RB.VEL] = 15.0
			body[RB.VEL + 2] = 2.0
			s.sim.reset(body)
		elif scenario == "fuel":
			var install: Dictionary = s.aircraft.model.propulsion.glow
			var values: PackedFloat64Array = s.sim.continuous
			values[1] = values[GlowFlight.LINE_FUEL_INDEX] + float(install.unusable_fuel_kg) + 0.0002
			s.sim.continuous = values
		var throttle := 0.0 if scenario == "landing" else 1.0
		s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = -0.05 if scenario == "landing" else 0.1, yaw = 0.0,
			throttle = throttle}
		pair.append(s)
	var kernel: Object = pair[0]._native_stage._native
	var before: int = int(kernel.tick_stats().get("glow_mass_calls", 0))
	var label := "%s %s" % [id, scenario]
	var stats := {ticks = 0, mismatched = 0}
	var first := ""
	for tick in {takeoff = 1440, landing = 960, fuel = 2400}[scenario]:
		_tick(pair[0])
		_tick(pair[1])
		stats.ticks += 1
		if _snapshot(pair[0]) != _snapshot(pair[1]):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s " % [pair[0].sim.tick, pair[0].sim.fault_reason, pair[1].sim.fault_reason]
		if not pair[0].crash.is_empty() or not pair[0].sim.fault_reason.is_empty() \
				or not pair[1].crash.is_empty() or not pair[1].sim.fault_reason.is_empty():
			break
	stats.native_checks = int(kernel.tick_stats().get("glow_mass_calls", 0)) - before
	_check(label + ": every tick is byte-identical with and without the native checks", stats.mismatched == 0, first + str(stats))
	_check(label + ": the native stage answered the checks", stats.native_checks >= stats.ticks, str(stats))
	print("NK6E_FLIGHT %s %s" % [label, str(stats)])
	for s: Node in pair:
		s.free()


func _snapshot(s: Node) -> PackedByteArray:
	var sim: Node = s.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.last_loads,
		_plain(sim.last_events), sim.fault_reason, sim.paused, _plain(s.crash)])


func _plain(value: Variant) -> Variant:
	if value is Object:
		return _plain(inst_to_dict(value)) if value.get_script() != null else value.get_class()
	if value is Callable:
		return str(value.get_method())
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _plain(value[key])
		return out
	if value is Array:
		return value.map(_plain)
	return value


func _refusals(id: String) -> void:
	var s := _session(id, Flight.START_RUNWAY)
	for i in 20:
		_tick(s)
	var values: PackedFloat64Array = s.sim.continuous.duplicate()
	_check(id + ": outside the guarded tick the session refuses", s._native_glow_mass_check(values, true) < 0)
	_enter_tick(s)
	_check(id + ": inside the guarded tick it answers", s._native_glow_mass_check(values, true) == 1)
	s.native_glow_mass_enabled = false
	_check(id + ": the hook off refuses", s._native_glow_mass_check(values, true) < 0)
	s.free()
	var derived := _session(id, Flight.START_RUNWAY, true)
	if derived != null:
		_enter_tick(derived)
		_check(id + ": a derived session class refuses", derived._native_glow_mass_check(derived.sim.continuous, true) < 0)
		derived.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
