# DR-16a (SF): the opt-in framed sampled protocol of sim/vehicle_model.gd on the shared kernel.
# A deliberately generic toy model (one shaft, a PI sampled controller, one arm mode) exercises the transaction
# ledger TX-01…TX-10 of the FPV backlog: pure sampling of the accepted frame, the same held sample in every stage,
# full rollback of a refused tick, detached full-frame reset, restore without hidden caches and the legacy dispatch
# left exactly as it was. The guard is a finite contract on kernel/model state, not a sandbox for arbitrary code.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")

const LAYOUT := "test-framed-toy-v1"
const TAU := 0.05
const GAIN := 0.002 # N per (rad/s): shaft speed to body force

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _body() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -2.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


## Toy framed model. aux = [integral, command, samples_seen]; modes = [armed]; continuous = [shaft speed].
## `spy` is test-side bookkeeping (call counts, injected faults); it is not simulation state.
func _toy(spy: Dictionary) -> VehicleModel:
	var vehicle := VehicleModel.new()
	vehicle.callback_protocol = VehicleModel.PROTOCOL_FRAMED_SAMPLED
	vehicle.state_layout_identity = LAYOUT
	vehicle.input_size = 2 # [target speed, arm switch]
	vehicle.aux_size = 3
	vehicle.modes_size = 1
	vehicle.continuous_size = 1
	vehicle.identity = {vehicle = "toy", law = LAYOUT}
	vehicle.sample_tick = func(frame: Dictionary, input: PackedFloat64Array, clock: Dictionary) -> Variant:
		spy.samples = int(spy.get("samples", 0)) + 1
		spy.last_clock = clock.duplicate()
		if spy.get("sample_mutates_frame", false):
			frame.aux[0] = 99.0
		if spy.get("sample_mutates_input", false):
			input[0] = 99.0
		if spy.get("sample_malformed", false):
			return {aux = PackedFloat64Array([NAN, 0.0, 0.0]), modes = frame.modes}
		var armed: int = 1 if input[1] > 0.5 else 0
		var error: float = input[0] - frame.continuous[0]
		var integral: float = frame.aux[0] + clock.dt * 4.0 * error if armed == 1 else 0.0
		var command: float = (input[0] + integral) if armed == 1 else 0.0
		return {aux = PackedFloat64Array([integral, command, frame.aux[2] + 1.0]), modes = PackedInt64Array([armed])}
	vehicle.stage_sampled = func(_b: PackedFloat64Array, extra: PackedFloat64Array, stage_t: float, context: Dictionary) -> Variant:
		spy.stages = int(spy.get("stages", 0)) + 1
		var seen: Array = spy.get("contexts", [])
		seen.append(var_to_bytes(context))
		spy.contexts = seen
		var times: Array = spy.get("stage_times", [])
		times.append(stage_t)
		spy.stage_times = times
		if int(spy.get("fail_stage", -1)) == int(spy.stages):
			return {loads = PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = PackedFloat64Array([0.0]),
				rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
		if spy.get("stage_mutates_context", false):
			context.aux[1] = 1234.0
		if spy.has("reenter"):
			spy.reenter.call()
		var command: float = context.aux[1] if context.modes[0] == 1 else 0.0
		return {loads = PackedFloat64Array([0.0, 0.0, -GAIN * extra[0], 0.0, 0.0, 0.0]),
			derivative = PackedFloat64Array([(command - extra[0]) / TAU]),
			rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	# The legacy default fields stay installed; a framed model must never reach them.
	vehicle.pre_tick = func(aux: PackedFloat64Array, _i: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		spy.legacy_calls = int(spy.get("legacy_calls", 0)) + 1
		return aux
	vehicle.loads = func(_b: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		spy.legacy_calls = int(spy.get("legacy_calls", 0)) + 1
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	vehicle.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		spy.legacy_calls = int(spy.get("legacy_calls", 0)) + 1
		return PackedFloat64Array()
	vehicle.state_validator = func(frame: Dictionary, _context: Dictionary) -> bool:
		return frame.modes[0] in [0, 1] and frame.continuous[0] > -1.0e-6
	return vehicle


func _frame(speed := 0.0) -> Dictionary:
	return {body = _body(), continuous = PackedFloat64Array([speed]), aux = PackedFloat64Array([0.0, 0.0, 0.0]),
		modes = PackedInt64Array([0])}


## A kernel with the toy installed and a full-frame reset committed. Returns {sim, spy, ok}.
func _flying(spy: Dictionary = {}) -> Dictionary:
	var sim: Node = Sim.new()
	root.add_child(sim)
	var installed: bool = sim.set_model(_toy(spy))
	sim.mass = 0.5
	var prepared: Dictionary = sim.prepare_reset_frame(_frame(), PackedFloat64Array([100.0, 1.0]))
	var committed: bool = prepared.ok and sim.commit_prepared_reset_frame(prepared)
	spy.erase("contexts")
	spy.erase("stage_times")
	spy.stages = 0
	spy.samples = 0
	return {sim = sim, spy = spy, ok = installed and committed, message = str(prepared.get("message", ""))}


func _signature(sim: Node) -> PackedByteArray:
	return var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs, sim.last_loads,
		sim.tick, sim.last_events])


func _run() -> void:
	_contract()
	_sampling()
	_rollback()
	_guards()
	_held_sample()
	_frame_reset()
	_restore()
	_observers()
	_legacy()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _contract() -> void:
	var spy := {}
	var good := _toy(spy)
	_check("a framed sampled model validates", VehicleModel.validate(good).ok, str(VehicleModel.validate(good).message))
	_check("TX-05 a framed model is a joint-stage model", good.uses_joint_stage())
	var unknown := _toy(spy)
	unknown.callback_protocol = "framed-sampled-v2"
	_check("an unknown callback protocol is refused", not VehicleModel.validate(unknown).ok)
	var no_layout := _toy(spy)
	no_layout.state_layout_identity = ""
	_check("the framed protocol requires a state layout identity", not VehicleModel.validate(no_layout).ok)
	var no_block := _toy(spy)
	no_block.continuous_size = 0
	_check("the framed protocol requires a nonempty continuous block", not VehicleModel.validate(no_block).ok)
	var no_sample := _toy(spy)
	no_sample.sample_tick = Callable()
	_check("the framed protocol requires sample_tick", not VehicleModel.validate(no_sample).ok)
	var both := _toy(spy)
	both.stage = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> Dictionary: return {}
	_check("TX-05 a framed model cannot also select the legacy joint stage", not VehicleModel.validate(both).ok)
	var split := _toy(spy)
	split.block_loads = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> PackedFloat64Array: return PackedFloat64Array()
	_check("TX-05 a framed model cannot also select the legacy split route", not VehicleModel.validate(split).ok)
	var legacy := VehicleModel.new()
	legacy.sample_tick = good.sample_tick
	_check("a legacy model cannot carry sampled callbacks", not VehicleModel.validate(legacy).ok)
	var sim: Node = Sim.new()
	root.add_child(sim)
	_check("the kernel refuses to install a malformed protocol combination", not sim.set_model(both) and sim.set_model(good))
	sim.free()


func _sampling() -> void:
	var spy := {}
	var vehicle := _toy(spy)
	var frame := _frame(40.0)
	var input := PackedFloat64Array([100.0, 1.0])
	var clock := {tick = 7, time_s = 7.0 / 240.0, dt = 1.0 / 240.0}
	var before: PackedByteArray = var_to_bytes([frame, input, clock])
	var first: Variant = vehicle.sample_tick.call(frame, input, clock)
	var second: Variant = vehicle.sample_tick.call(frame, input, clock)
	_check("TX-01 sampling the same accepted frame twice gives identical candidate bytes",
		var_to_bytes(first) == var_to_bytes(second) and var_to_bytes([frame, input, clock]) == before)
	var h: Dictionary = _flying()
	var sim: Node = h.sim
	_check("a framed model resets through the full-frame path", h.ok, h.message)
	for _i in 10:
		sim.step()
	_check("TX-01 one accepted sample per tick, four stage evaluations per plain RK4 tick",
		int(h.spy.samples) == 10 and int(h.spy.stages) == 40 and sim.tick == 10 and sim.fault_reason.is_empty(),
		"samples %d stages %d" % [int(h.spy.samples), int(h.spy.stages)])
	_check("the sample saw the accepted clock of its tick", int(h.spy.last_clock.tick) == 9
		and is_equal_approx(float(h.spy.last_clock.time_s), 9.0 / 240.0) and float(h.spy.last_clock.dt) == 1.0 / 240.0)
	_check("the sampled command drives the shaft and the mode is committed", sim.continuous[0] > 10.0
		and sim.modes[0] == 1 and sim.aux[2] == 10.0, "speed %.3f" % sim.continuous[0])
	_check("TX-05 the legacy default callbacks are never called for a framed model", int(h.spy.get("legacy_calls", 0)) == 0)
	sim.free()


func _rollback() -> void:
	# TX-02: a malformed k1, k2 or k4 after a new command and integrator update restores the whole accepted frame.
	for bad_stage: int in [1, 2, 4]:
		var h: Dictionary = _flying()
		var sim: Node = h.sim
		for _i in 5:
			sim.step()
		var accepted: PackedByteArray = _signature(sim)
		var emitted := {stepped = 0, events = 0, faults = 0}
		sim.stepped.connect(func(_tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array,
				_i: PackedFloat64Array, _a: PackedFloat64Array) -> void: emitted.stepped += 1)
		sim.faulted.connect(func(_reason: String) -> void: emitted.faults += 1)
		sim.inputs = PackedFloat64Array([250.0, 0.0]) # a new command and a disarm the failed tick must not consume
		h.spy.stages = 0
		h.spy.fail_stage = bad_stage
		sim.step()
		# The kernel also restores the accepted input snapshot; the session owns the unconsumed command tape.
		_check("TX-02 a malformed stage %d restores body, shaft, controller memory, mode, inputs and clock" % bad_stage,
			_signature(sim) == accepted and not sim.fault_reason.is_empty() and sim.paused
			and emitted.stepped == 0 and emitted.faults == 1 and sim.inputs[0] == 100.0 and sim.modes[0] == 1, sim.fault_reason)
		sim.free()
	var m: Dictionary = _flying()
	for _i in 3:
		m.sim.step()
	var kept: PackedByteArray = _signature(m.sim)
	m.spy.sample_malformed = true
	m.sim.step()
	_check("TX-02 a malformed sample is refused before any stage runs", _signature(m.sim) == kept
		and not m.sim.fault_reason.is_empty() and int(m.spy.stages) == 12, m.sim.fault_reason)
	m.sim.free()


func _guards() -> void:
	var a: Dictionary = _flying()
	for _i in 3:
		a.sim.step()
	var kept: PackedByteArray = _signature(a.sim)
	a.spy.stage_mutates_context = true
	a.sim.step()
	_check("TX-03 a stage that mutates its sampled context is refused and the frame restored",
		_signature(a.sim) == kept and not a.sim.fault_reason.is_empty(), a.sim.fault_reason)
	a.sim.free()
	var b: Dictionary = _flying()
	b.sim.step()
	kept = _signature(b.sim)
	b.spy.sample_mutates_frame = true
	b.sim.step()
	_check("TX-03 a sample that mutates its accepted frame is refused", _signature(b.sim) == kept
		and not b.sim.fault_reason.is_empty(), b.sim.fault_reason)
	b.sim.free()
	var c: Dictionary = _flying()
	c.sim.step()
	kept = _signature(c.sim)
	c.spy.sample_mutates_input = true
	c.sim.step()
	_check("TX-03 a sample that mutates its input snapshot is refused", _signature(c.sim) == kept
		and not c.sim.fault_reason.is_empty(), c.sim.fault_reason)
	c.sim.free()
	var d: Dictionary = _flying()
	d.sim.step()
	kept = _signature(d.sim)
	var target: Node = d.sim
	d.spy.reenter = func() -> void: target.step()
	d.sim.step()
	_check("TX-03 a stage that reenters the kernel is refused without a nested tick", _signature(d.sim) == kept
		and not d.sim.fault_reason.is_empty() and d.sim.tick == 1, d.sim.fault_reason)
	d.sim.free()
	var e: Dictionary = _flying()
	e.sim.step()
	kept = _signature(e.sim)
	var owner: Node = e.sim
	e.spy.reenter = func() -> void:
		owner.aux = PackedFloat64Array([5.0, 5.0, 5.0])
		owner.modes = PackedInt64Array([0])
	e.spy.contexts = []
	e.sim.step()
	# One guard spans the whole integration: a live write is refused, and meanwhile every stage still read the
	# same detached sample.
	_check("TX-03 a stage writing live sampled state is refused and never committed", _signature(e.sim) == kept
		and not e.sim.fault_reason.is_empty() and e.spy.contexts.size() >= 4 and e.spy.contexts[0] == e.spy.contexts[3],
		e.sim.fault_reason)
	e.sim.free()
	var f: Dictionary = _flying()
	f.sim.step()
	kept = _signature(f.sim)
	var tampered_owner: Node = f.sim
	var original_sampler: Callable = f.sim.model.sample_tick
	f.spy.reenter = func() -> void:
		tampered_owner.mass = 7.0
		tampered_owner.model.identity = {tampered = true}
		tampered_owner.model.sample_tick = func(_a: Dictionary, _b: PackedFloat64Array, _c: Dictionary) -> Variant: return null
	f.sim.step()
	_check("TX-03 a stage that edits mass, model identity or a callback is refused and the registered state restored",
		_signature(f.sim) == kept and not f.sim.fault_reason.is_empty() and f.sim.mass == 0.5
		and not f.sim.model.identity.has("tampered") and f.sim.model.sample_tick == original_sampler, f.sim.fault_reason)
	f.sim.free()
	var g: Dictionary = _flying()
	var kept_frames: Array = []
	var inner_sampler: Callable = g.sim.model.sample_tick
	g.sim.model.sample_tick = func(frame: Dictionary, input: PackedFloat64Array, clock: Dictionary) -> Variant:
		kept_frames.append(frame)
		return inner_sampler.call(frame, input, clock)
	g.sim.model.endpoint_transition = func(previous: Dictionary, candidate: Dictionary, _context: Dictionary) -> Dictionary:
		g.spy.previous_seen = previous.aux[2]
		return {body = candidate.body, continuous = candidate.continuous, aux = candidate.aux, modes = candidate.modes, events = []}
	g.spy.reenter = func() -> void:
		if not kept_frames.is_empty():
			kept_frames[kept_frames.size() - 1].aux[2] = 1000.0
	g.sim.step()
	g.sim.step()
	_check("TX-03 a sampler that keeps its frame cannot reach the previous frame the endpoint transition sees",
		g.sim.fault_reason.is_empty() and float(g.spy.previous_seen) == 1.0, "%s %s" % [str(g.spy.get("previous_seen")), g.sim.fault_reason])
	g.sim.free()


func _held_sample() -> void:
	var h: Dictionary = _flying()
	var sim: Node = h.sim
	sim.model.substeps = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> int: return 4
	h.spy.contexts = []
	h.spy.stages = 0
	h.spy.samples = 0
	sim.step()
	var same := true
	for bytes: Variant in h.spy.contexts:
		same = same and bytes == h.spy.contexts[0]
	_check("TX-04 four plant substeps reuse one held sample and never resample the controller",
		sim.fault_reason.is_empty() and int(h.spy.samples) == 1 and int(h.spy.stages) == 16 and same,
		"samples %d stages %d %s" % [int(h.spy.samples), int(h.spy.stages), sim.fault_reason])
	sim.free()
	var p: Dictionary = _flying()
	var policy_sim: Node = p.sim
	policy_sim.model.step_policy = func(combined: PackedFloat64Array, t: float, dt: float, f: Callable, k1: PackedFloat64Array) -> Variant:
		# Trial stages a bracketing policy would abandon, then the accepted step.
		f.call(combined, t + 0.25 * dt)
		f.call(combined, t + 0.75 * dt)
		return RK.rk4_step_at(combined, t, dt, f, k1)
	p.spy.contexts = []
	p.spy.stages = 0
	p.spy.samples = 0
	policy_sim.step()
	same = true
	for bytes: Variant in p.spy.contexts:
		same = same and bytes == p.spy.contexts[0]
	_check("TX-04/05 step-policy trial stages dispatch the sampled stage with the same held sample",
		policy_sim.fault_reason.is_empty() and int(p.spy.samples) == 1 and int(p.spy.stages) == 6 and same,
		"samples %d stages %d %s" % [int(p.spy.samples), int(p.spy.stages), policy_sim.fault_reason])
	_check("TX-05 no legacy callback ran on the substep or policy routes", int(h.spy.get("legacy_calls", 0)) == 0
		and int(p.spy.get("legacy_calls", 0)) == 0)
	policy_sim.free()


func _frame_reset() -> void:
	var h: Dictionary = _flying()
	var sim: Node = h.sim
	for _i in 20:
		sim.step()
	var flying: PackedByteArray = _signature(sim)
	var emitted := {stepped = 0}
	sim.stepped.connect(func(_tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array,
			_i: PackedFloat64Array, _a: PackedFloat64Array) -> void: emitted.stepped += 1)
	var bad := _frame(30.0)
	bad.aux = PackedFloat64Array([0.0, NAN, 0.0])
	var refused: Dictionary = sim.prepare_reset_frame(bad, PackedFloat64Array([50.0, 0.0]))
	var wrong_size := _frame(30.0)
	wrong_size.modes = PackedInt64Array([0, 0])
	var refused_size: Dictionary = sim.prepare_reset_frame(wrong_size, PackedFloat64Array([50.0, 0.0]))
	var invalid_domain := _frame(30.0)
	invalid_domain.modes = PackedInt64Array([7])
	var refused_domain: Dictionary = sim.prepare_reset_frame(invalid_domain, PackedFloat64Array([50.0, 0.0]))
	var refused_input: Dictionary = sim.prepare_reset_frame(_frame(30.0), PackedFloat64Array([50.0]))
	_check("TX-06 malformed reset candidates are refused and the running flight is untouched",
		not refused.ok and not refused_size.ok and not refused_domain.ok and not refused_input.ok
		and _signature(sim) == flying and emitted.stepped == 0 and sim.fault_reason.is_empty())
	h.spy.stages = 0
	h.spy.contexts = []
	var candidate := _frame(30.0)
	candidate.aux = PackedFloat64Array([0.0, 77.0, 0.0])
	candidate.modes = PackedInt64Array([1])
	var prepared: Dictionary = sim.prepare_reset_frame(candidate, PackedFloat64Array([50.0, 1.0]))
	var expected_context: PackedByteArray = var_to_bytes({aux = candidate.aux, modes = candidate.modes, sample_tick = 0, sample_time_s = 0.0})
	_check("TX-06 preparation evaluates the candidate frame's own sampled context and changes nothing",
		prepared.ok and _signature(sim) == flying and int(h.spy.stages) == 1 and h.spy.contexts[0] == expected_context
		and absf(prepared.loads[2] + GAIN * 30.0) < 1e-15 and emitted.stepped == 0, str(prepared.get("message", "")))
	candidate.aux[1] = 5.0 # the caller's arrays stay the caller's
	var other: Dictionary = _flying()
	_check("TX-07 a prepared candidate is refused on another owner", not other.sim.commit_prepared_reset_frame(prepared)
		and other.sim.tick == 0)
	other.sim.free()
	var tampered: Dictionary = prepared.duplicate(true)
	tampered.frame.aux[1] = 1.0
	_check("TX-07 a tampered candidate is refused", not sim.commit_prepared_reset_frame(tampered) and _signature(sim) == flying)
	_check("TX-07 the legacy commit refuses a full-frame candidate", not sim.commit_prepared_reset(prepared) and _signature(sim) == flying)
	_check("TX-06 the accepted candidate publishes every array together at tick zero",
		sim.commit_prepared_reset_frame(prepared) and sim.tick == 0 and sim.continuous[0] == 30.0 and sim.aux[1] == 77.0
		and sim.modes[0] == 1 and sim.inputs[0] == 50.0 and emitted.stepped == 1 and sim.state == sim.previous)
	sim.step()
	var stale: Dictionary = sim.prepare_reset_frame(_frame(10.0), PackedFloat64Array([0.0, 0.0]))
	sim.step()
	var after_step: PackedByteArray = _signature(sim)
	_check("TX-07 a candidate prepared before the owner advanced is refused", stale.ok
		and not sim.commit_prepared_reset_frame(stale) and _signature(sim) == after_step)
	sim.free()
	var fresh: Node = Sim.new()
	root.add_child(fresh)
	fresh.set_model(_toy({}))
	var first: Dictionary = fresh.prepare_reset_frame(_frame(), PackedFloat64Array([0.0, 0.0]))
	_check("a fresh owner with no previous layout prepares and commits a full frame", first.ok and fresh.commit_prepared_reset_frame(first))
	fresh.free()
	var legacy_reset: Node = Sim.new()
	root.add_child(legacy_reset)
	legacy_reset.set_model(_toy({}))
	legacy_reset.inputs = PackedFloat64Array([0.0, 0.0])
	legacy_reset.aux = PackedFloat64Array([0.0, 0.0, 0.0])
	legacy_reset.modes = PackedInt64Array([0])
	legacy_reset.continuous = PackedFloat64Array([12.0])
	_check("TX-05 the historical reset route also dispatches the sampled stage", legacy_reset.reset(_body())
		and absf(legacy_reset.last_loads[2] + GAIN * 12.0) < 1e-15)
	legacy_reset.free()


func _restore() -> void:
	var a: Dictionary = _flying()
	for _i in 30:
		a.sim.step()
	var snapshot: Dictionary = a.sim.checkpoint()
	_check("a framed checkpoint pins its protocol and layout", not snapshot.is_empty()
		and snapshot.get("callback_protocol") == VehicleModel.PROTOCOL_FRAMED_SAMPLED and snapshot.get("state_layout_identity") == LAYOUT)
	# Later commands, integrator history and a disarm the restore must not inherit.
	a.sim.inputs = PackedFloat64Array([400.0, 1.0])
	for _i in 40:
		a.sim.step()
	a.sim.inputs = PackedFloat64Array([400.0, 0.0])
	for _i in 5:
		a.sim.step()
	var b: Dictionary = _flying()
	_check("TX-08 the checkpoint restores into the used owner and into another owner reset to the same layout",
		a.sim.restore_checkpoint(snapshot) and b.sim.restore_checkpoint(snapshot))
	a.sim.set_paused(false)
	b.sim.set_paused(false)
	var equal := true
	for tick in 60:
		var command := PackedFloat64Array([120.0 + float(tick), 1.0])
		a.sim.inputs = command
		b.sim.inputs = command.duplicate()
		a.sim.step()
		b.sim.step()
		equal = equal and _signature(a.sim) == _signature(b.sim)
	_check("TX-08 after restore the next commands, loads and state equal a fresh control from that checkpoint",
		equal and a.sim.fault_reason.is_empty() and a.sim.tick == 90)
	var legacy_key: Dictionary = snapshot.duplicate(true)
	legacy_key.erase("callback_protocol")
	var wrong_protocol: Dictionary = snapshot.duplicate(true)
	wrong_protocol.callback_protocol = "legacy"
	var wrong_type: Dictionary = snapshot.duplicate(true)
	wrong_type.callback_protocol = 5
	var resized: Dictionary = snapshot.duplicate(true)
	resized.aux = PackedFloat64Array([0.0, 0.0])
	_check("a framed checkpoint without, or with another, protocol pin, or with a resized block, is refused",
		not a.sim.can_restore_checkpoint(legacy_key) and not a.sim.can_restore_checkpoint(wrong_protocol)
		and not a.sim.can_restore_checkpoint(wrong_type) and not a.sim.can_restore_checkpoint(resized))
	var declared := _toy({})
	declared.events = [{type = "stop", index = 18, transition = func(state: PackedFloat64Array, _index: int) -> PackedFloat64Array: return state}]
	var declared_sim: Node = Sim.new()
	root.add_child(declared_sim)
	declared_sim.set_model(declared)
	_check("a full-frame reset refuses a declared event outside the continuous block",
		not declared_sim.prepare_reset_frame(_frame(), PackedFloat64Array([0.0, 0.0])).ok)
	declared_sim.free()
	a.sim.free()
	b.sim.free()


func _observers() -> void:
	var h: Dictionary = _flying()
	var sim: Node = h.sim
	var seen := {ok = true, count = 0}
	sim.stepped.connect(func(tick: int, _t: float, state: PackedFloat64Array, _l: PackedFloat64Array,
			_i: PackedFloat64Array, aux: PackedFloat64Array) -> void:
		var inside: Dictionary = sim.checkpoint()
		seen.count += 1
		var same_tick: bool = not inside.is_empty() and int(inside.tick) == tick and inside.aux == aux
		seen.ok = seen.ok and same_tick and inside.state == state and inside.aux[2] == float(tick))
	for _i in 12:
		sim.step()
	_check("TX-10 a checkpoint taken inside the stepped signal belongs to the same accepted tick", seen.ok and seen.count == 12)
	var prepared: Dictionary = sim.prepare_reset_frame(_frame(20.0), PackedFloat64Array([0.0, 0.0]))
	var committed: bool = sim.commit_prepared_reset_frame(prepared, func() -> void: sim.aux = PackedFloat64Array([9.0, 9.0, 9.0]))
	_check("TX-09 an observer fault after an accepted reset is a committed observer fault, not a rollback",
		committed and sim.tick == 0 and sim.continuous[0] == 20.0 and sim.aux[0] == 0.0
		and not sim.reset_observer_fault.is_empty() and sim.paused, sim.reset_observer_fault)
	sim.free()


func _legacy() -> void:
	var calls := {pre_tick = 0, stage = 0}
	var vehicle := VehicleModel.new()
	vehicle.input_size = 1
	vehicle.aux_size = 1
	vehicle.modes_size = 0
	vehicle.continuous_size = 1
	vehicle.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		calls.pre_tick += 1
		return PackedFloat64Array([inputs[0]])
	vehicle.stage = func(_b: PackedFloat64Array, extra: PackedFloat64Array, _t: float) -> Dictionary:
		calls.stage += 1
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = PackedFloat64Array([-extra[0]]),
			rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	var sim: Node = Sim.new()
	root.add_child(sim)
	sim.set_model(vehicle)
	sim.inputs = PackedFloat64Array([0.5])
	sim.aux = PackedFloat64Array([0.0])
	sim.continuous = PackedFloat64Array([3.0])
	var reset_ok: bool = sim.reset(_body())
	calls.stage = 0
	for _i in 5:
		sim.step()
	_check("legacy dispatch is unchanged: one pre_tick and four joint stages per tick", reset_ok and calls.pre_tick == 5
		and calls.stage == 20 and sim.fault_reason.is_empty() and sim.aux[0] == 0.5)
	var snapshot: Dictionary = sim.checkpoint()
	_check("a legacy checkpoint keeps the v1 format and carries no protocol key", snapshot.get("format") == Sim.CHECKPOINT_FORMAT
		and not snapshot.has("callback_protocol") and not snapshot.has("state_layout_identity"))
	var forged: Dictionary = snapshot.duplicate(true)
	forged.callback_protocol = VehicleModel.PROTOCOL_FRAMED_SAMPLED
	_check("a legacy owner refuses a checkpoint carrying a protocol key", not sim.can_restore_checkpoint(forged)
		and sim.can_restore_checkpoint(snapshot))
	_check("a legacy model has no full-frame reset", not sim.prepare_reset_frame({body = _body(), continuous = PackedFloat64Array([3.0]),
		aux = PackedFloat64Array([0.0]), modes = PackedInt64Array()}, PackedFloat64Array([0.5])).ok)
	sim.free()
