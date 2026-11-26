extends SceneTree
## NK-6a: the native kernel integrates a legacy joint tick (Simulation._native_integrator) exactly as the GDScript
## reference transaction does. Two identical native-stage sessions fly the same inputs, one through the kernel's
## integrate_tick and one with sim.native_tick_enabled = false; after every tick their tick, state, previous state,
## continuous state, aux, modes, loads, located events, fault, pause and crash must be byte-identical, with the same
## number of stage evaluations:
## - takeoffs, landings, throttle cuts, a slowing rotor (the fixed-bus rotor-stop event), gusty, turbulent and spatial
##   weather, retractable gear cycles and fuel exhaustion (the liquid fuel event) across the eligible fleet;
## - single ticks of a bare Simulation restored from a session checkpoint, with injected malformed rotor momentum,
##   substep counts, post-step filters, auxiliary projections, event transitions and event types, an overflowing state
##   and a vanishing mass: each must end like the reference, with its refusal reason and restored state;
## - refusals: the reference keeps ticks the kernel does not own (step policies, a reference stage, the hook off).
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Weather := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")

## Each injected malformed callback or state, and the reference's refusal for it ("" = an accepted tick).
const FAULTS := {
	accepted = "",
	spy = "",
	rotor_nan = "step rejected: rotor momentum is nonfinite or malformed",
	rotor_size = "step rejected: rotor momentum is nonfinite or malformed",
	rotor_null = "step rejected: rotor momentum is nonfinite or malformed",
	substeps_zero = "step rejected: substep count is not an integer within 1..16",
	substeps_many = "step rejected: substep count is not an integer within 1..16",
	substeps_float = "step rejected: substep count is not an integer within 1..16",
	substeps_four = "",
	filter_empty = "step rejected: post-step contact filter returned a malformed body state",
	filter_degenerate = "step rejected: post-step contact filter returned a malformed body state",
	aux_nan = "step rejected: continuous auxiliary projection is nonfinite or malformed",
	aux_size = "step rejected: continuous auxiliary projection is nonfinite or malformed",
	velocity_huge = "step rejected: joint stage evaluation is nonfinite or malformed",
	mass_tiny = "step rejected: RK stage derivative is nonfinite or malformed",
	event = "",
	event_substeps = "",
	transition_bad = "step rejected: the event locator could not bound the tick",
	transition_resized = "step rejected: the event locator could not bound the tick",
	event_type_empty = "step rejected: step policy returned malformed events",
	spy_event = "",
}
const EVENT_FAULTS := ["event", "event_substeps", "transition_bad", "transition_resized", "event_type_empty", "spy_event"]
const SimulationScript := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary
var _lake: Dictionary
var _fleet: PackedStringArray = []
var _start_for := {}
var _events_seen := {}
var _reasons_seen := {}
var _silent_events := {}
var _subdivided := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var start: String = Flight.START_RUNWAY
		var probe := _session(id, start, "calm")
		if probe == null:
			start = Flight.START_AIRBORNE
			probe = _session(id, start, "calm")
		if probe == null:
			print("NK6A_SKIP %s: no flyable fixed-wing session" % id)
			continue
		if probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK6A_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		elif probe.sim._native_integrator() == null:
			print("NK6A_REFERENCE %s: the kernel does not own this tick (policy=%s)" % [id, probe.sim.model.step_policy.is_valid()])
			_reference_kept(probe, id)
		else:
			_fleet.append(id)
			_start_for[id] = start
		probe.free()
	if _fleet.is_empty():
		print("NK6A_TICK_DRIVER_SKIP no native fixed-wing session the kernel integrates")
		print("native tick driver: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	print("NK6A_FLEET ", _fleet)
	for id: String in _fleet:
		if _start_for[id] == Flight.START_RUNWAY:
			_pair(id, "calm", "takeoff")
		_pair(id, "calm", "landing")
		_pair(id, "calm", "cut")
		_pair(id, "calm", "gear_cycle")
		_pair(id, "calm", "fuel")
		_pair(id, "calm", "stop")
	for id: String in ["f4u-corsair-250", "turbo-lumber-evolution", "jensen-das-ugly-stik-60"]:
		if id in _fleet and _start_for[id] == Flight.START_RUNWAY:
			for weather: String in ["gusty", "turbulent", "spatial"]:
				_pair(id, weather, "takeoff")
	for id: String in _fleet:
		for fault: String in FAULTS:
			_fault_case(id, fault)
	_check("the fleet located a rotor-stop event", _events_seen.has("rotor_stop"), str(_events_seen))
	_check("the fleet located a fuel-exhaustion event", _events_seen.has("fuel_exhausted"), str(_events_seen))
	_check("some flight ticks were subdivided", _subdivided > 0, str(_subdivided))
	for reason: String in FAULTS.values():
		_check("the fleet met the refusal \"%s\"" % reason, _reasons_seen.has(reason), str(_reasons_seen.keys()))
	_hook_off()
	print("native tick driver: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _weather_config(weather: String) -> Variant:
	match weather:
		"gusty": return Weather.preset("gusty")
		"turbulent": return Weather.preset("turbulent")
		"spatial": return Weather.spatial_defaults()
	return null


func _session(id: String, start: String, weather: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(str(Catalog.entry(id).data), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	var config: Variant = _weather_config(weather)
	if config != null and not s.setup_weather(config):
		print("NK6A weather %s refused for %s: %s" % [weather, id, s.weather_error])
		s.free()
		return null
	s.reset()
	if not s.is_flyable():
		s.free()
		return null
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _snapshot(s: Node) -> PackedByteArray:
	var sim: Node = s.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.last_loads,
		sim.last_events, sim.fault_reason, sim.paused, sim.inputs, _plain(s.crash)])


## Objects by their script properties (a crash record holds a fresh impact object per session), Callables by name.
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


func _kernel(s: Node) -> Object:
	return s._native_stage._native if s._native_stage != null else null


func _controls(scenario: String, tick: int) -> Dictionary:
	match scenario:
		"takeoff":
			return {roll = 0.0, pitch = 0.25 if tick > 480 else 0.0, yaw = 0.05, throttle = 1.0}
		"cut":
			return {roll = 0.02, pitch = 0.05, yaw = 0.0, throttle = 0.8 if tick < 360 else 0.0}
		"landing":
			return {roll = 0.0, pitch = -0.05, yaw = 0.02, throttle = 0.0}
		"fuel":
			return {roll = 0.0, pitch = 0.1, yaw = 0.0, throttle = 1.0}
		"stop":
			return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	return {roll = 0.05, pitch = 0.04, yaw = 0.0, throttle = 0.6}


## Builds the two sessions of a pair, applies the scenario's start edits to both and returns [driven, reference].
func _sessions(id: String, weather: String, scenario: String) -> Array:
	var start: String = Flight.START_AIRBORNE if scenario in ["gear_cycle", "landing"] else _start_for[id]
	var pair: Array = []
	for driven in [true, false]:
		var s := _session(id, start, weather)
		if s == null:
			for other: Node in pair:
				other.free()
			return []
		s.sim.native_tick_enabled = driven
		pair.append(s)
	for s: Node in pair:
		if scenario == "landing":
			var body: PackedFloat64Array = s.sim.state.duplicate()
			body[RB.POS + 2] = minf(body[RB.POS + 2], -3.0)
			body[RB.VEL] = 15.0
			body[RB.VEL + 2] = 2.0
			s.sim.reset(body)
		var holder: Dictionary = {tick = 0}
		s.set_meta(&"nk6a_holder", holder)
		s.read_raw = func() -> Dictionary: return _controls(scenario, holder.tick)
	return pair


func _event_index(s: Node, type: String) -> int:
	for event: Dictionary in s.sim.model.events:
		if str(event.get("type", "")) == type:
			return int(event.index) - RB.SIZE
	return -1


## Sets one continuous value and the auxiliary projection that must agree with it.
func _set_continuous(s: Node, index: int, value: float) -> void:
	s.sim.continuous[index] = value
	if s.sim.model.block_aux.is_valid():
		s.sim.aux = s.sim.model.block_aux.call(s.sim.continuous.duplicate(), s.sim.aux.duplicate())


func _pair(id: String, weather: String, scenario: String) -> void:
	var pair := _sessions(id, weather, scenario)
	if pair.is_empty():
		return
	var label := "%s %s %s" % [id, weather, scenario]
	if scenario == "gear_cycle" and not pair[0].gear_is_retractable():
		_free(pair)
		return
	if scenario in ["fuel", "stop"]:
		var type := "fuel_exhausted" if scenario == "fuel" else "rotor_stop"
		var index := _event_index(pair[0], type)
		if index < 0:
			_free(pair)
			return
		for s: Node in pair:
			_set_continuous(s, index, 0.0004 if scenario == "fuel" else 300.0) # a few seconds of fuel; a slow rotor
	var ticks: int = {takeoff = 1440, landing = 960, cut = 1440, gear_cycle = 2100, fuel = 2400, stop = 2400}.get(scenario, 960)
	var stats := _fly(pair, ticks, scenario, label)
	if scenario == "fuel":
		_check(label + ": the fuel ran out through the located event", stats.events.has("fuel_exhausted"), str(stats))
	_free(pair)


func _fly(pair: Array, ticks: int, scenario: String, label: String) -> Dictionary:
	var driven: Node = pair[0]
	var reference: Node = pair[1]
	var before_driven: Dictionary = _kernel(driven).tick_stats()
	var before_reference: Dictionary = _kernel(reference).tick_stats()
	var stage_before: Array = [_stage_calls(driven), _stage_calls(reference)]
	var stats := {ticks = 0, mismatched = 0, events = {}}
	var first := ""
	for tick in ticks:
		for s: Node in pair:
			s.get_meta(&"nk6a_holder").tick = tick
			if scenario == "gear_cycle" and tick in [10, 1050]:
				s.set_gear_down(tick == 1050)
		_tick(driven)
		_tick(reference)
		stats.ticks += 1
		if _snapshot(driven) != _snapshot(reference):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: driven %s %s / reference %s %s " % [driven.sim.tick, str(driven.sim.state),
					driven.sim.fault_reason, str(reference.sim.state), reference.sim.fault_reason]
		for event: Dictionary in driven.sim.last_events:
			stats.events[str(event.type)] = int(stats.events.get(str(event.type), 0)) + 1
			_events_seen[str(event.type)] = true
		if not driven.sim.fault_reason.is_empty() or not driven.crash.is_empty() \
				or not reference.sim.fault_reason.is_empty() or not reference.crash.is_empty():
			break
	var after_driven: Dictionary = _kernel(driven).tick_stats()
	var after_reference: Dictionary = _kernel(reference).tick_stats()
	stats.kernel_ticks = int(after_driven.calls) - int(before_driven.calls)
	stats.kernel_answers = int(after_driven.answers) - int(before_driven.answers)
	stats.reference_kernel_ticks = int(after_reference.calls) - int(before_reference.calls)
	stats.stage_calls = [_stage_calls(driven) - stage_before[0], _stage_calls(reference) - stage_before[1]]
	stats.fault = driven.sim.fault_reason
	stats.extra_stages = stats.stage_calls[0] - 4 * stats.ticks # substeps and event trials
	if stats.extra_stages > 0:
		_subdivided += 1
	_check(label + ": every tick is byte-identical to the reference", stats.mismatched == 0, first + str(stats))
	_check(label + ": the kernel integrated the driven ticks", stats.kernel_ticks >= stats.ticks - 1 and stats.kernel_ticks > 0,
		str(stats))
	_check(label + ": the reference session never asked the kernel", stats.reference_kernel_ticks == 0, str(stats))
	_check(label + ": both evaluated the same stages", stats.stage_calls[0] == stats.stage_calls[1], str(stats))
	print("NK6A_FLIGHT %s %s" % [label, str(stats)])
	return stats


func _stage_calls(s: Node) -> int:
	return int(s._native_stage.stage_stats().get("stage_calls", 0))


## One tick of a bare Simulation restored from a native session's checkpoint, with one model callback or state value
## replaced. Each side borrows its own identical session's guarded pre-step, which installs the kernel's tick context.
func _fault_case(id: String, fault: String) -> void:
	var label := "%s case %s" % [id, fault]
	if fault in EVENT_FAULTS and _silent_events.has(id):
		return
	var results: Array = []
	for driven in [true, false]:
		var s := _session(id, _start_for[id], "calm")
		if s == null:
			_check(label + ": the session starts", false)
			return
		var event_case: bool = fault in EVENT_FAULTS
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 if event_case else 0.7}
		for i in 120:
			_tick(s)
		var model: RefCounted = s.sim.model
		if event_case:
			if model.events.size() != 1:
				s.free()
				return
			_set_continuous(s, int(model.events[0].index) - RB.SIZE, 1e-9) # the boundary falls inside the next tick
		var checkpoint: Dictionary = s.sim.checkpoint()
		var b: Node = SimulationScript.new()
		var m: RefCounted = VehicleModel.new()
		for property: Dictionary in model.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				m.set(property.name, model.get(property.name))
		m.events = model.events.duplicate()
		m.pre_tick = func(a: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
			return s._kernel_pre_step(a, inputs, dt)
		b.mass = s.sim.mass
		b.inertia = s.sim.inertia.duplicate()
		b.gravity = s.sim.gravity
		b.continuous = checkpoint.get("continuous", PackedFloat64Array()).duplicate()
		b.aux = checkpoint.get("aux", PackedFloat64Array()).duplicate()
		b.modes = checkpoint.get("modes", PackedInt64Array()).duplicate()
		if checkpoint.is_empty() or not b.set_model(m) or not b.restore_checkpoint(checkpoint):
			_check(label + ": the bare kernel restores the session's checkpoint", false)
			b.free()
			s.free()
			return
		_inject(b, m, fault)
		b.native_tick_enabled = driven
		var kernel: Object = _kernel(s)
		var before: Dictionary = kernel.tick_stats()
		var stages := _stage_calls(s)
		b.step()
		var after: Dictionary = kernel.tick_stats()
		results.append({snapshot = var_to_bytes([b.tick, b.state, b.previous, b.continuous, b.aux, b.modes,
			b.last_loads, b.last_events, b.fault_reason, b.paused]), fault = b.fault_reason, events = b.last_events.duplicate(),
			calls = int(after.calls) - int(before.calls), answers = int(after.answers) - int(before.answers),
			faults = int(after.faults) - int(before.faults), stages = _stage_calls(s) - stages, tick = b.tick,
			calls_log = b.get_meta(&"nk6a_log", []).duplicate()})
		b.free()
		s.free()
	var expected: String = FAULTS[fault]
	var native: Dictionary = results[0]
	var reference: Dictionary = results[1]
	var detail := "%s / %s" % [str(native).left(600), str(reference).left(600)]
	_check(label + ": the tick is byte-identical to the reference", native.snapshot == reference.snapshot, detail)
	_check(label + ": both evaluated the same stages", native.stages == reference.stages, detail)
	_check(label + ": the kernel integrated it and the reference did not", native.calls == 1 and reference.calls == 0, detail)
	_reasons_seen[native.fault] = true
	if fault == "event" and native.events.is_empty() and reference.events.is_empty():
		_silent_events[id] = true # e.g. a windmilling airborne rotor never reaches its boundary in this tick
		print("NK6A_CASE_SKIP %s: the declared event does not fire from this start" % id)
		return
	if fault == "mass_tiny" and native.fault.is_empty():
		return # the stage publishes this airframe's body derivative: the rigid-body law is not evaluated
	_check(label + ": the reference reason", native.fault == expected and reference.fault == expected, detail)
	if expected.is_empty():
		_check(label + ": the kernel answered", native.answers == 1 and native.tick == reference.tick, detail)
	else:
		_check(label + ": the kernel refused like the reference", native.faults == 1, detail)
	if fault in ["spy", "spy_event"]:
		var names: Array = native.calls_log.map(func(entry: Array) -> String: return entry[0])
		var difference := ""
		for i in mini(native.calls_log.size(), reference.calls_log.size()):
			if native.calls_log[i] != reference.calls_log[i]:
				difference = "%s: %s / %s" % [native.calls_log[i][0], str(bytes_to_var(native.calls_log[i][1])).left(1500),
					str(bytes_to_var(reference.calls_log[i][1])).left(1500)]
				break
		_check(label + ": every callback was called in the same order with the same arguments and results",
			not native.calls_log.is_empty() and var_to_bytes(native.calls_log) == var_to_bytes(reference.calls_log),
			"%s / %s %s" % [str(names), str(reference.calls_log.map(func(entry: Array) -> String: return entry[0])), difference])
		if fault == "spy_event":
			_check(label + ": the event transition ran in both", names.has("transition"), str(names))
	if fault in ["event", "event_substeps", "spy_event"]:
		_check(label + ": the event was located", not native.events.is_empty(), detail)
		for event: Dictionary in native.events:
			_events_seen[str(event.type)] = true


func _inject(b: Node, m: RefCounted, fault: String) -> void:
	match fault:
		"spy", "spy_event":
			_spy(b, m)
		"rotor_nan":
			m.rotor_momentum = func(_aux: PackedFloat64Array) -> Variant: return PackedFloat64Array([NAN, 0.0, 0.0])
		"rotor_size":
			m.rotor_momentum = func(_aux: PackedFloat64Array) -> Variant: return PackedFloat64Array([0.0, 0.0])
		"rotor_null":
			m.rotor_momentum = func(_aux: PackedFloat64Array) -> Variant: return null
		"substeps_zero", "substeps_many", "substeps_float", "substeps_four", "event_substeps":
			var count: Variant = {substeps_zero = 0, substeps_many = 17, substeps_float = 1.0, substeps_four = 4,
				event_substeps = 3}[fault]
			if m.substeps_joint.is_valid():
				m.substeps_joint = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float, _j: Dictionary) -> Variant:
					return count
			else:
				m.substeps = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> Variant: return count
		"filter_empty", "filter_degenerate":
			var degenerate: bool = fault == "filter_degenerate"
			var filtered := func(candidate: PackedFloat64Array) -> PackedFloat64Array:
				if not degenerate:
					return PackedFloat64Array()
				var body := candidate.duplicate()
				for i in 4:
					body[RB.ATT + i] = 0.0
				return body
			if m.post_tick_joint.is_valid():
				m.post_tick_joint = func(_p: PackedFloat64Array, c: PackedFloat64Array, _n: int, _pv: PackedFloat64Array,
						_cv: PackedFloat64Array) -> PackedFloat64Array:
					return filtered.call(c)
			else:
				m.post_tick = func(_p: PackedFloat64Array, c: PackedFloat64Array, _n: int) -> PackedFloat64Array:
					return filtered.call(c)
		"aux_nan":
			m.block_aux = func(_c: PackedFloat64Array, _a: PackedFloat64Array) -> Variant: return PackedFloat64Array([NAN])
		"aux_size":
			m.block_aux = func(_c: PackedFloat64Array, a: PackedFloat64Array) -> Variant:
				var out := a.duplicate()
				out.append(0.0)
				return out
		"velocity_huge":
			b.state[RB.VEL] = 1e200
		"mass_tiny":
			b.mass = 1e-300 * 1e-10 # a subnormal positive mass (the literal would parse as zero): 1 / mass overflows
		"transition_bad", "transition_resized", "event_type_empty":
			var original: Dictionary = m.events[0]
			var transition: Callable = original.transition
			if fault == "transition_bad":
				transition = func(values: PackedFloat64Array, _index: int) -> PackedFloat64Array: return values.duplicate()
			elif fault == "transition_resized":
				transition = func(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
					var out: PackedFloat64Array = original.transition.call(values, index)
					out.append(0.0)
					return out
			var declared: Array[Dictionary] = [{type = "" if fault == "event_type_empty" else str(original.type),
				index = int(original.index), transition = transition}]
			m.events = declared


## Wraps every model callback the tick calls so the log records its name, arguments and result in call order.
func _spy(b: Node, m: RefCounted) -> void:
	var log: Array = []
	b.set_meta(&"nk6a_log", log)
	var spy := func(name: String, callback: Callable, arguments: Array) -> Variant:
		log.append([name, var_to_bytes(_plain(arguments))])
		var result: Variant = callback.callv(arguments)
		log.append([name + " result", var_to_bytes(_plain(result))])
		return result
	var rotor: Callable = m.rotor_momentum
	m.rotor_momentum = func(a: PackedFloat64Array) -> Variant: return spy.call("rotor", rotor, [a])
	if m.substeps_joint.is_valid():
		var substeps_joint: Callable = m.substeps_joint
		m.substeps_joint = func(body: PackedFloat64Array, c: PackedFloat64Array, t: float, joint: Dictionary) -> Variant:
			return spy.call("substeps_joint", substeps_joint, [body, c, t, joint])
	elif m.substeps.is_valid():
		var substeps: Callable = m.substeps
		m.substeps = func(body: PackedFloat64Array, c: PackedFloat64Array, t: float) -> Variant:
			return spy.call("substeps", substeps, [body, c, t])
	if m.post_tick_joint.is_valid():
		var post_joint: Callable = m.post_tick_joint
		m.post_tick_joint = func(p: PackedFloat64Array, c: PackedFloat64Array, n: int, pv: PackedFloat64Array,
				cv: PackedFloat64Array) -> Variant:
			return spy.call("post_tick_joint", post_joint, [p, c, n, pv, cv])
	elif m.post_tick.is_valid():
		var post: Callable = m.post_tick
		m.post_tick = func(p: PackedFloat64Array, c: PackedFloat64Array, n: int) -> Variant:
			return spy.call("post_tick", post, [p, c, n])
	if m.block_aux.is_valid():
		var block_aux: Callable = m.block_aux
		m.block_aux = func(c: PackedFloat64Array, a: PackedFloat64Array) -> Variant: return spy.call("block_aux", block_aux, [c, a])
	if not m.events.is_empty():
		var original: Dictionary = m.events[0]
		var transition: Callable = original.transition
		var declared: Array[Dictionary] = [{type = str(original.type), index = int(original.index),
			transition = func(values: PackedFloat64Array, index: int) -> Variant:
				return spy.call("transition", transition, [values, index])}]
		m.events = declared


## A model the kernel does not integrate keeps every tick in the reference transaction.
func _reference_kept(probe: Node, id: String) -> void:
	var kernel: Object = _kernel(probe)
	if kernel == null:
		return
	var before: Dictionary = kernel.tick_stats()
	for i in 120:
		_tick(probe)
	_check(id + ": a model the kernel does not own never reaches it", int(kernel.tick_stats().calls) == int(before.calls),
		str(kernel.tick_stats()))


func _hook_off() -> void:
	var id: String = _fleet[0]
	var s := _session(id, _start_for[id], "calm")
	s.sim.native_tick_enabled = false
	_check(id + ": the hook off leaves no integrator", s.sim._native_integrator() == null)
	s.sim.native_tick_enabled = true
	_check(id + ": the hook on names the stage's kernel", s.sim._native_integrator() == _kernel(s))
	var reference_stage: Callable = s._native_stage._reference_stage
	var native_stage: Callable = s.sim.model.stage
	s.sim.model.stage = reference_stage
	_check(id + ": a reference stage leaves no integrator", s.sim._native_integrator() == null)
	s.sim.model.stage = native_stage
	s.free()


func _free(pair: Array) -> void:
	for s: Node in pair:
		s.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
