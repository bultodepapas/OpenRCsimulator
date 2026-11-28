extends SceneTree
## NK-6n: the native kernel's steady-tick answer for GlowFlight.finish (nk_glow_finish.hpp). For every native glow
## aircraft:
## - random start and end stores around real ticks, through every check finish makes (rpm envelope, fuel floor and
##   rise, temperature, transport, servo and air bounds, phase direction, running flag, stop reason, counters,
##   accumulator, overheat, stall, fuel exhaustion, opportunity counts): wherever the kernel answers, finish returns the
##   same state bytes and no events;
## - fixed boundary stores: fractional, negative-fraction and 2^53 counters, signed-zero start values, finite wheel
##   values past the glow store, and a start stop reason the end store does not carry;
## - takeoffs, airborne flights, throttle cuts and fuel exhaustion fly byte-identical with the answer on and off.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 3000

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
	_rng.seed = 7113
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var start: String = Flight.START_RUNWAY
		var probe := _session(id, start)
		if probe == null:
			start = Flight.START_AIRBORNE
			probe = _session(id, start)
		if probe == null:
			continue
		if probe.glow_is_active() and probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE \
				and probe._native_stage._native.has_method("glow_steady_finish_component"):
			_fleet.append(id)
			_start_for[id] = start
		probe.free()
	if _fleet.is_empty():
		print("NK6N_SKIP no native glow session with the steady finish")
		print("native glow finish: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	print("NK6N_FLEET ", _fleet)
	for id: String in _fleet:
		_direct(id)
		for scenario: String in ["takeoff", "airborne", "cut", "fuel"]:
			_pair(id, scenario)
	print("native glow finish: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start: String) -> Node:
	var s: Node = Flight.new()
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


## Enter the guarded tick as Simulation.step does (test_native_glow_firing): the pre-step installs the native context.
func _enter_tick(s: Node) -> PackedFloat64Array:
	var restore: PackedFloat64Array = s.sim.aux.duplicate()
	var next: PackedFloat64Array = s._kernel_pre_step(s.sim.aux.duplicate(), s.sim.inputs.duplicate(), s.sim.dt())
	if next.size() == restore.size():
		s.sim.aux = next
	return restore


func _direct(id: String) -> void:
	var s := _session(id, _start_for[id])
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.1, yaw = 0.0, throttle = 1.0}
	var stats := {answered = 0, mismatched = 0, refused = 0, refused_plain = 0, reference_failed = 0, boundary = 0,
		boundary_answered = 0}
	var first := ""
	for round in 4:
		for i in 240:
			_tick(s)
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
		var restore := _enter_tick(s)
		var terms: PackedFloat64Array = s._native_glow_finish_terms()
		_check(id + ": the plan carries the steady terms inside the guarded tick", terms.size() == 9, str(terms))
		if terms.size() != 9:
			s.sim.aux = restore
			continue
		var hot: float = terms[4]
		var stall: float = terms[3]
		var max_rpm: float = terms[2]
		var origin: PackedFloat64Array = s.sim._packed_state(s.sim.state)
		var t: float = s.sim.time()
		for i in SAMPLES / 4:
			var dt: float = s.sim.dt() if i % 17 != 0 else 0.0
			var start := _random_start(origin)
			var end := _random_end(start, hot, stall, max_rpm)
			var detail := _compare(s, start, end, t, dt, terms, stats)
			if first.is_empty() and not detail.is_empty():
				first = detail
		# Fixed boundary stores around a plausible steady pair.
		for store: Array in _boundary_pairs(origin, terms):
			var before_answered: int = stats.answered
			var detail := _compare(s, store[0], store[1], t, s.sim.dt(), terms, stats)
			if first.is_empty() and not detail.is_empty():
				first = "boundary %s: %s" % [store[2], detail]
			stats.boundary += 1
			if stats.answered > before_answered:
				stats.boundary_answered += 1
		s.sim.aux = restore
	_check(id + ": every steady answer equals GlowFlight.finish byte for byte", stats.mismatched == 0, first + str(stats))
	_check(id + ": the kernel answers every steady end and refuses the rest", stats.answered > SAMPLES / 3 \
		and stats.refused > SAMPLES / 10 and stats.refused_plain == 0, str(stats))
	_check(id + ": the kernel answers the steady boundary stores", stats.boundary_answered >= stats.boundary / 2,
		str(stats))
	print("NK6N_DIRECT %s %s" % [id, str(stats)])
	s.free()


## Compares GlowFlight.finish with the kernel's steady answer for one pair, with the firing fraction finish reads.
## Returns a description of the first difference, or "".
func _compare(s: Node, start: PackedFloat64Array, end: PackedFloat64Array, t: float, dt: float,
		terms: PackedFloat64Array, stats: Dictionary) -> String:
	var empty: Array[Dictionary] = []
	var at: float = t + dt
	var body: PackedFloat64Array = end.slice(0, RB.SIZE)
	var values: PackedFloat64Array = end.slice(RB.SIZE)
	var firing: float = s.native_glow_firing(body, values, at)
	if not is_finite(firing):
		var point: Dictionary = GlowFlight.point(s, body, values, at)
		firing = float(point.get("firing_fraction", NAN)) if point.get("ok", false) else NAN
	var reference: Variant = GlowFlight.finish(start, t, dt, s, {ok = true, state = end, events = []}, empty)
	var plain: bool = reference is Dictionary and (reference.events as Array).is_empty()
	if not plain:
		stats.reference_failed += 1
	var native: PackedFloat64Array = s._native_stage._native.glow_steady_finish_component(start, end, dt, terms,
		firing) if is_finite(firing) else PackedFloat64Array()
	if native.is_empty():
		stats.refused += 1
		if plain:
			stats.refused_plain += 1
		return ""
	stats.answered += 1
	if not plain or var_to_bytes(reference.state) != var_to_bytes(native):
		stats.mismatched += 1
		return "native %s reference %s " % [str(native.slice(RB.SIZE, RB.SIZE + 12)),
			str(reference.state.slice(RB.SIZE, RB.SIZE + 12) if plain else reference)]
	return ""


## Plausible steady pairs with one fixed boundary each: [start, end, label].
func _boundary_pairs(origin: PackedFloat64Array, terms: PackedFloat64Array) -> Array:
	var g := RB.SIZE
	var base := origin.duplicate()
	base[g + 6] = 0.4
	base[g + 7] = 1.0
	base[g + 8] = 0.0
	base[g + 9] = 12.0
	base[g + 10] = 9.0
	base[g + 11] = 0.3
	var next := base.duplicate()
	next[g] = 0.5 * (terms[3] + terms[2])
	next[g + 1] = maxf(0.0, base[g + 1] - 1.0e-6)
	next[g + 3] = 0.5
	next[g + 4] = 0.5
	next[g + 6] = base[g + 6] + 0.7
	var pairs: Array = [[base, next, "plain"]]
	var cases := {
		fractional_counters = {g + 9: 12.7, g + 10: 9.2},
		negative_fraction_fires = {g + 10: -0.5},
		counters_2_53 = {g + 9: 9007199254740992.0, g + 10: 9007199254740990.0},
		negative_zero_phase = {g + 6: -0.0},
		negative_zero_fuel_stopped = {g + 1: -0.0, g + 7: 0.0},
		stopped_with_reason = {g + 7: 0.0, g + 8: 2.0},
		running_with_reason = {g + 8: 3.0},
	}
	for label: String in cases:
		var a := base.duplicate()
		for index: int in cases[label]:
			a[index] = cases[label][index]
		var b := next.duplicate()
		b[g + 6] = a[g + 6] + 0.7
		b[g + 1] = maxf(0.0, a[g + 1] - 1.0e-6) if a[g + 1] > 0.0 else a[g + 1]
		pairs.append([a, b, label])
	# The end store's own stop reason and running flag are not the accepted ones.
	var other_reason := next.duplicate()
	other_reason[g + 8] = 5.0
	pairs.append([base, other_reason, "end_reason_differs"])
	# Finite values past the glow store (wheel states) travel through unchanged.
	if base.size() > g + 19:
		var wheels := next.duplicate()
		for k in range(g + 19, wheels.size()):
			wheels[k] = _rng.randf_range(-3.0, 3.0)
		pairs.append([base, wheels, "wheel_values"])
	return pairs


## A start store around a real one: mostly accepted, sometimes stopped, out of fuel or with odd counters.
func _random_start(origin: PackedFloat64Array) -> PackedFloat64Array:
	var out := origin.duplicate()
	var g := RB.SIZE
	out[g + 6] = _rng.randf_range(0.0, 2.0) # crank revolutions within the cycle
	out[g + 11] = [0.0, 0.5, 0.999999999999, _rng.randf()][_rng.randi_range(0, 3)] # firing accumulator
	if _rng.randf() < 0.1:
		out[g + 7] = 0.0 # stopped
	if _rng.randf() < 0.05:
		out[g + 1] = 0.0 # no fuel
	if _rng.randf() < 0.05:
		out[g + 10] = out[g + 9] + 1.0 # more fires than opportunities
	if _rng.randf() < 0.05:
		out[g + 8] = float(_rng.randi_range(0, 6)) # another recorded stop reason (accepted stores are always well formed)
	return out


## An end store after one tick: a plausible steady end, then at most one value at or across a check finish makes.
func _random_end(start: PackedFloat64Array, hot: float, stall: float, max_rpm: float) -> PackedFloat64Array:
	var out := start.duplicate()
	var g := RB.SIZE
	for k in 3:
		out[RB.POS + k] += _rng.randf_range(-0.1, 0.1)
		out[RB.VEL + k] += _rng.randf_range(-0.5, 0.5)
	out[g] = _rng.randf_range(stall + 1.0, max_rpm)
	out[g + 1] = maxf(0.0, start[g + 1] - _rng.randf_range(0.0, 1.0e-5))
	out[g + 2] = clampf(start[g + 2] + _rng.randf_range(-1.0, 1.0), 1.0, hot - 1.0)
	out[g + 3] = _rng.randf()
	out[g + 4] = _rng.randf()
	out[g + 5] = maxf(0.0, start[g + 5] + _rng.randf_range(-1.0e-6, 1.0e-6))
	out[g + 6] = start[g + 6] + (_rng.randf_range(0.0, 0.3) if _rng.randf() < 0.8 else _rng.randf_range(0.0, 4.0))
	match _rng.randi_range(0, 13):
		3: out[g] = [stall, stall + 1.0e-9, max_rpm, max_rpm * 1.01, 0.0][_rng.randi_range(0, 4)]
		4: out[g + 1] = [start[g + 1], start[g + 1] + 1.0e-15, start[g + 1] + 1.0e-13, 0.0, -1.0e-9][_rng.randi_range(0, 4)]
		5: out[g + 2] = [hot, hot - 1.0e-9, -1.0, 1.0e-300][_rng.randi_range(0, 3)]
		6: out[g + 3] = [0.0, 1.0, -1.0e-13, 1.0 + 1.0e-13, -1.0e-11, 1.0 + 1.0e-11][_rng.randi_range(0, 5)]
		7: out[g + 4] = [0.0, 1.0, -1.0e-13, 1.0 + 1.0e-13, -1.0e-11, 1.0 + 1.0e-11][_rng.randi_range(0, 5)]
		8: out[g + 5] = [0.0, -0.0, -1.0e-9][_rng.randi_range(0, 2)]
		9: out[g + 6] = [start[g + 6], start[g + 6] - 1.0e-13, start[g + 6] - 1.0e-11, 2.0, 1.0, 4.0 - 1.0e-13][_rng.randi_range(0, 5)]
		10: out[g + 7] = [0.5, 1.0 - out[g + 7]][_rng.randi_range(0, 1)]
		11: out[g + 11] = [1.0, -1.0e-12, 0.999999999999, 0.0][_rng.randi_range(0, 3)]
		12: out[g + 8] = [0.5, 7.0, -1.0, 3.0][_rng.randi_range(0, 3)]
		13:
			out[g + 9] = start[g + 9] + float(_rng.randi_range(0, 3))
			out[g + 10] = out[g + 9] + float(_rng.randi_range(-1, 1))
	return out


func _pair(id: String, scenario: String) -> void:
	var pair: Array = []
	for native in [true, false]:
		var s := _session(id, Flight.START_AIRBORNE if scenario == "airborne" else _start_for[id])
		if s == null:
			for other: Node in pair:
				other.free()
			return
		s.native_glow_finish_enabled = native
		var holder := {tick = 0}
		s.set_meta(&"nk6n_holder", holder)
		s.read_raw = func() -> Dictionary:
			var throttle: float = 0.0 if scenario == "cut" and holder.tick > 600 else (0.35 + 0.65 * float(holder.tick % 480 < 300))
			return {roll = 0.0, pitch = 0.15 if holder.tick > 480 else 0.0, yaw = 0.03, throttle = throttle}
		pair.append(s)
	if scenario == "fuel":
		var install: Dictionary = pair[0].aircraft.model.propulsion.glow
		for s: Node in pair:
			var values: PackedFloat64Array = s.sim.continuous
			values[1] = values[GlowFlight.LINE_FUEL_INDEX] + float(install.unusable_fuel_kg) + 0.0002
			s.sim.continuous = values
	var native_kernel: Object = pair[0]._native_stage._native
	var reference_kernel: Object = pair[1]._native_stage._native
	var answers_before: int = native_kernel.glow_finish_answers()
	var reference_before: int = reference_kernel.glow_finish_answers()
	var label := "%s %s" % [id, scenario]
	var stats := {ticks = 0, mismatched = 0, events = {}}
	var first := ""
	var ticks: int = {takeoff = 1440, airborne = 1440, cut = 2400, fuel = 2400}[scenario]
	for tick in ticks:
		for s: Node in pair:
			s.get_meta(&"nk6n_holder").tick = tick
		_tick(pair[0])
		_tick(pair[1])
		stats.ticks += 1
		for event: Dictionary in pair[0].sim.last_events:
			stats.events[str(event.type)] = true
		if _snapshot(pair[0]) != _snapshot(pair[1]):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s " % [pair[0].sim.tick, str(pair[0].sim.continuous), str(pair[1].sim.continuous)]
		if not pair[0].crash.is_empty() or not pair[0].sim.fault_reason.is_empty() \
				or not pair[1].crash.is_empty() or not pair[1].sim.fault_reason.is_empty():
			break
	stats.answers = native_kernel.glow_finish_answers() - answers_before
	stats.reference_answers = reference_kernel.glow_finish_answers() - reference_before
	_check(label + ": every tick is byte-identical with the steady answer on and off", stats.mismatched == 0 \
		and var_to_bytes(_plain(pair[0].glow_state())) == var_to_bytes(_plain(pair[1].glow_state())), first + str(stats))
	_check(label + ": the kernel answered steady ticks", stats.answers > stats.ticks / 3, str(stats))
	_check(label + ": the hook off never answers", stats.reference_answers == 0, str(stats))
	print("NK6N_FLIGHT %s %s" % [label, str(stats)])
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
		var out := []
		for item: Variant in value:
			out.append(_plain(item))
		return out
	return value


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
