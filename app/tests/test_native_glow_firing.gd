extends SceneTree
## NK-6b: the glow step policy's endpoint sample. GlowFlight.step and _count_segment read only `ok` and
## `firing_fraction` of point(); inside a guarded tick the session's native glow stage answers that fraction from the
## same point evaluation (FlightSession.native_glow_firing). Checks, for every native glow aircraft:
## - random endpoints inside a guarded tick (bodies, rpm, temperature, crank phase, fuel, times): every finite answer
##   equals point().firing_fraction bit for bit, and the stage refuses only where point() fails or gives no finite
##   fraction;
## - takeoffs, idle cuts, fuel exhaustion through the resource events (transitions and counted segments) and gusty and
##   turbulent flights fly byte-identical with and without the answer, ticks and glow telemetry alike;
## - refusals: outside the guarded tick, the hook off, a pending weather reset, a derived session class.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Weather := preload("res://physics/wind_config.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 400

class DerivedSession extends "res://sim/flight_session.gd":
	pass

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _fleet: PackedStringArray = []
var _start_for := {}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 61622
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var start: String = Flight.START_RUNWAY
		var probe := _session(id, start, "calm")
		if probe == null:
			start = Flight.START_AIRBORNE
			probe = _session(id, start, "calm")
		if probe == null:
			continue
		if probe.glow_is_active() and probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE \
				and probe._native_stage._glow_firing_bound:
			_fleet.append(id)
			_start_for[id] = start
		elif probe.glow_is_active():
			print("NK6B_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		probe.free()
	if _fleet.is_empty():
		print("NK6B_GLOW_FIRING_SKIP no native glow session")
		print("native glow firing: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	print("NK6B_FLEET ", _fleet)
	for id: String in _fleet:
		_direct(id)
		_pair(id, "calm", "takeoff")
		_pair(id, "calm", "airborne")
		_pair(id, "calm", "cut")
		_pair(id, "calm", "fuel")
	for weather: String in ["gusty", "turbulent"]:
		_pair(_fleet[0], weather, "takeoff")
	_refusals(_fleet[0])
	print("native glow firing: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _weather_config(weather: String) -> Variant:
	match weather:
		"gusty": return Weather.preset("gusty")
		"turbulent": return Weather.preset("turbulent")
	return null


func _session(id: String, start: String, weather: String, derived := false) -> Node:
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
	var config: Variant = _weather_config(weather)
	if config != null and not s.setup_weather(config):
		s.free()
		return null
	s.reset()
	if not s.is_flyable():
		s.free()
		return null
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start() # the starter action the application offers; deterministic for both sides of a pair
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## Enter the guarded tick as Simulation.step does: the session's pre-step installs the native context and the
## sampled aux becomes sim.aux before the step policy runs. Returns the aux to restore.
func _enter_tick(s: Node) -> PackedFloat64Array:
	var restore: PackedFloat64Array = s.sim.aux.duplicate()
	var next: PackedFloat64Array = s._kernel_pre_step(s.sim.aux.duplicate(), s.sim.inputs.duplicate(), s.sim.dt())
	if next.size() == restore.size():
		s.sim.aux = next
	return restore


func _direct(id: String) -> void:
	var s := _session(id, _start_for[id], "calm")
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.1, yaw = 0.0, throttle = 1.0}
	var stats := {compared = 0, mismatched = 0, refused = 0, wrong_refusal = 0, firing = 0}
	var first := ""
	for round in 4:
		for i in 240:
			_tick(s)
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
		var restore := _enter_tick(s)
		var origin: PackedFloat64Array = s.sim._packed_state(s.sim.state)
		for i in SAMPLES / 4:
			var combined := _random_endpoint(origin)
			var body: PackedFloat64Array = combined.slice(0, RB.SIZE)
			var values: PackedFloat64Array = combined.slice(RB.SIZE)
			var at: float = s.sim.time() + _rng.randf_range(0.0, s.sim.dt())
			var native: float = s.native_glow_firing(body, values, at)
			var point: Dictionary = GlowFlight.point(s, body, values, at)
			var reference: float = float(point.get("firing_fraction", NAN)) if point.get("ok", false) else NAN
			if not is_finite(native):
				stats.refused += 1
				if is_finite(reference):
					stats.wrong_refusal += 1
					if first.is_empty():
						first = "refused a finite reference %s at %s " % [reference, str(values)]
				continue
			stats.compared += 1
			if native > 0.0:
				stats.firing += 1
			if var_to_bytes(native) != var_to_bytes(reference):
				stats.mismatched += 1
				if first.is_empty():
					first = "%s / %s " % [native, reference]
		s.sim.aux = restore
	_check(id + ": every answer equals point().firing_fraction bit for bit", stats.mismatched == 0, first + str(stats))
	# A refusal is always exact (point() runs); it costs only time. Record how often a finite fraction was refused.
	_check(id + ": the stage answered firing endpoints", stats.compared > SAMPLES / 2 and stats.firing > 0, str(stats))
	print("NK6B_DIRECT %s %s" % [id, str(stats)])
	s.free()


func _random_endpoint(origin: PackedFloat64Array) -> PackedFloat64Array:
	var out := origin.duplicate()
	for k in 3:
		out[RB.POS + k] += _rng.randf_range(-2.0, 2.0)
		out[RB.VEL + k] += _rng.randf_range(-4.0, 4.0)
		out[RB.RATE + k] += _rng.randf_range(-1.0, 1.0)
	var q := Quaternion(out[RB.ATT + 1], out[RB.ATT + 2], out[RB.ATT + 3], out[RB.ATT]) \
		* Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.3, 0.3))
	q = q.normalized()
	out[RB.ATT] = q.w
	out[RB.ATT + 1] = q.x
	out[RB.ATT + 2] = q.y
	out[RB.ATT + 3] = q.z
	var g := RB.SIZE
	out[g] = maxf(0.0, out[g] * _rng.randf_range(0.3, 1.6)) # rpm
	out[g + 2] += _rng.randf_range(-40.0, 40.0) # head temperature K
	out[g + 6] += _rng.randf_range(0.0, 3.0) # crank revolutions
	out[g + 1] *= _rng.randf_range(0.5, 1.0) # fuel kg
	return out


func _pair(id: String, weather: String, scenario: String) -> void:
	var pair: Array = []
	for native in [true, false]:
		var s := _session(id, Flight.START_AIRBORNE if scenario == "airborne" else _start_for[id], weather)
		if s == null:
			for other: Node in pair:
				other.free()
			return
		s.native_glow_firing_enabled = native
		var holder := {tick = 0}
		s.set_meta(&"nk6b_holder", holder)
		s.read_raw = func() -> Dictionary:
			var throttle: float = 0.0 if scenario == "cut" and holder.tick > 600 else 1.0
			return {roll = 0.0, pitch = 0.15 if holder.tick > 480 else 0.0, yaw = 0.03, throttle = throttle}
		pair.append(s)
	if scenario == "fuel":
		var install: Dictionary = pair[0].aircraft.model.propulsion.glow
		for s: Node in pair:
			var values: PackedFloat64Array = s.sim.continuous
			values[1] = values[GlowFlight.LINE_FUEL_INDEX] + float(install.unusable_fuel_kg) + 0.0002
			s.sim.continuous = values
	var label := "%s %s %s" % [id, weather, scenario]
	var stats := {ticks = 0, mismatched = 0, answers = 0, events = {}, firing_ticks = 0}
	var first := ""
	var ticks: int = {takeoff = 1440, airborne = 1440, cut = 2400, fuel = 2400}[scenario]
	for tick in ticks:
		for s: Node in pair:
			s.get_meta(&"nk6b_holder").tick = tick
		var before: int = pair[0].native_glow_firing_answers
		_tick(pair[0])
		_tick(pair[1])
		stats.ticks += 1
		stats.answers += pair[0].native_glow_firing_answers - before
		for event: Dictionary in pair[0].sim.last_events:
			stats.events[str(event.type)] = true
		if pair[0].sim.continuous[0] > 0.0 and pair[0].sim.continuous[7] == 1.0:
			stats.firing_ticks += 1
		if _snapshot(pair[0]) != _snapshot(pair[1]):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s " % [pair[0].sim.tick, str(pair[0].sim.continuous), str(pair[1].sim.continuous)]
		if not pair[0].crash.is_empty() or not pair[0].sim.fault_reason.is_empty() \
				or not pair[1].crash.is_empty() or not pair[1].sim.fault_reason.is_empty():
			break
	_check(label + ": every tick and the glow telemetry are byte-identical", stats.mismatched == 0 \
		and var_to_bytes(_plain(pair[0].glow_state())) == var_to_bytes(_plain(pair[1].glow_state())), first + str(stats))
	_check(label + ": the native stage answered the policy's endpoints", stats.answers >= stats.ticks * 0.9, str(stats))
	_check(label + ": the reference session never asked", pair[1].native_glow_firing_answers == 0, str(stats))
	# Fuel exhaustion stops the engine part way; every other scenario keeps it running for most of the flight.
	_check(label + ": the engine ran", stats.firing_ticks > (0 if scenario == "fuel" else stats.ticks / 4), str(stats))
	if scenario == "fuel":
		_check(label + ": the fuel ran out through the resource events", stats.events.has("glow_stopped") \
			or stats.events.has("fuel_exhausted") or stats.events.has("fuel_tank_unusable"), str(stats))
	print("NK6B_FLIGHT %s %s" % [label, str(stats)])
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
	var s := _session(id, _start_for[id], "calm")
	for i in 60:
		_tick(s)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var values: PackedFloat64Array = s.sim.continuous.duplicate()
	_check(id + ": outside the guarded tick the session refuses", not is_finite(s.native_glow_firing(body, values, s.sim.time())))
	var restore := _enter_tick(s)
	_check(id + ": inside the guarded tick the session answers", is_finite(s.native_glow_firing(body, values, s.sim.time())))
	s.native_glow_firing_enabled = false
	_check(id + ": the hook off refuses", not is_finite(s.native_glow_firing(body, values, s.sim.time())))
	s.native_glow_firing_enabled = true
	s._weather_pending_reset = true
	_check(id + ": a pending weather reset refuses", not is_finite(s.native_glow_firing(body, values, s.sim.time())))
	s._weather_pending_reset = false
	s.sim.aux = restore
	s.free()
	var derived := _session(id, _start_for[id], "calm", true)
	if derived != null:
		for i in 10:
			_tick(derived)
		_enter_tick(derived)
		_check(id + ": a derived session class refuses", derived.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE \
			or not is_finite(derived.native_glow_firing(derived.sim.state, derived.sim.continuous, derived.sim.time())))
		derived.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
