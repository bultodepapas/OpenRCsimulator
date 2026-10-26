## GP-16 prerequisite: generic fixed-layout accepted endpoint transactions.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const RK := preload("res://physics/integrator.gd")
var checks := 0
var failures := 0

class RejectCommit:
	extends "res://sim/simulation.gd"
	func commit_prepared_reset(_candidate: Dictionary, _before_sample: Callable = Callable()) -> bool:
		return false

class MalformedContract:
	extends RefCounted
	var input_size := 4
	var aux_size := 0
	var modes_size := 0
	var continuous_size := 0
	var identity := {}
	var state_layout_identity := "duck-typed-v1"
	var endpoint_transition: Variant = Callable()
	var state_validator: Variant = Callable()
	func uses_joint_stage() -> bool: return false
	func placeholder() -> void: pass
	func _get(_property: StringName) -> Variant:
		return Callable(self, "placeholder")

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_contract()
	_commit_and_replay()
	_bad_frames()
	_live_mutations()
	_events()
	_validator_and_reset()
	_projection_and_filter()
	_body_only_and_validator_step()
	_reentry()
	_clock_identity_and_owner()
	print("Endpoint transitions: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _body() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(1.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))

func _new_sim() -> Node:
	var sim := Sim.new()
	var model := Model.new()
	model.state_layout_identity = "generic-endpoint-fixture-v1"
	model.aux_size = 2
	model.modes_size = 2
	model.continuous_size = 1
	model.stage = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> Dictionary:
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			derivative = PackedFloat64Array([2.0]), rotor_momentum = M.v3(0.0, 0.0, 0.0)}
	model.block_aux = func(extra: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
		var out := sampled.duplicate()
		out[0] = extra[0]
		return out
	model.state_validator = func(frame: Dictionary, context: Dictionary) -> bool:
		return frame.continuous[0] >= 0.0 and frame.aux[0] == frame.continuous[0] \
			and frame.modes[0] in [0, 1] and (frame.modes[1] == -1 if frame.modes[0] == 0 \
			else frame.modes[1] >= 1 and frame.modes[1] <= context.tick)
	sim.aux = PackedFloat64Array([0.0, 7.0])
	sim.continuous = PackedFloat64Array([0.0])
	sim.modes = PackedInt64Array([0, -1])
	sim.gravity = 0.0
	check("fixture installs", sim.set_model(model))
	check("fixture resets", sim.reset(_body()))
	return sim

func _raw(sim: Node) -> PackedByteArray:
	var values: Array = []
	for field: String in ["state", "previous", "continuous", "aux", "modes", "inputs", "last_loads", "last_events",
		"tick", "mass", "inertia", "gravity", "stop_at_tick", "_fixed_dt", "_state_layout_identity",
		"_last_valid_state", "_last_valid_previous", "_last_valid_continuous", "_last_valid_aux", "_last_valid_modes",
		"_last_valid_inputs", "_last_valid_loads", "_last_valid_tick", "_last_valid_mass", "_last_valid_inertia"]:
		values.append(sim.get(field))
	return var_to_bytes(values)

func _result(candidate: Dictionary, events: Array = []) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	result.events = events
	return result

func _contract() -> void:
	var model := Model.new()
	check("legacy model contract unchanged", Model.validate(model).ok)
	model.endpoint_transition = func(_p: Dictionary, c: Dictionary, _t: Dictionary) -> Dictionary: return _result(c)
	check("callback without identity rejected", not Model.validate(model).ok)
	model.state_layout_identity = "fixture-v1"
	check("opt-in requires declared sizes", not Model.validate(model).ok)
	model.aux_size = 0
	model.continuous_size = 0
	model.modes_size = 0
	check("fully declared body-only endpoint model accepted", Model.validate(model).ok)
	model.state_layout_identity = " padded "
	check("identity whitespace rejected", not Model.validate(model).ok)
	for property: String in ["endpoint_transition", "state_validator"]:
		var malformed := MalformedContract.new()
		malformed.set(property, "not callable")
		var rejected_shape: Dictionary = Model.validate(malformed)
		check("malformed duck-typed callback is rejected without invoking it: " + property,
			not rejected_shape.ok and str(rejected_shape.message).contains(property))
	var legacy := Sim.new()
	check("legacy reset", legacy.reset(_body()))
	var snapshot: Dictionary = legacy.checkpoint()
	check("legacy checkpoint remains v1 without new key", snapshot.format == Sim.CHECKPOINT_FORMAT \
		and not snapshot.has("state_layout_identity"))
	legacy.free()
	var rejected := RejectCommit.new()
	check("reset propagates rejected commit", not rejected.reset(_body()) and rejected.tick == 0 and rejected.state.is_empty())
	rejected.free()

func _commit_and_replay() -> void:
	var sim := _new_sim()
	var retained := {}
	var observed: Array = []
	sim.events_located.connect(func(_tick: int, events: Array[Dictionary]) -> void:
		observed.append({modes = sim.modes.duplicate(), work = sim.continuous.duplicate(), events = events.duplicate(true)}))
	sim.model.endpoint_transition = func(previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
		var out := _result(candidate)
		if previous.modes[0] == 0:
			out.modes[0] = 1
			out.modes[1] = context.tick
			out.continuous[0] += 3.0
			out.aux[1] = 9.0
			out.body[RB.VEL] += 0.125
			out.events = [{type = "component_transition", time_s = context.time_s, event_id = "fixture:first"}]
		retained.value = out
		return out
	sim.step()
	check("all state channels commit at one endpoint", sim.tick == 1 and sim.modes == PackedInt64Array([1, 1]) \
		and absf(sim.continuous[0] - 3.0 - 2.0 * sim.dt()) < 1e-14 and sim.aux[1] == 9.0 \
		and sim.state[RB.VEL] == 1.125)
	check("final continuous projection precedes validation", sim.aux[0] == sim.continuous[0] and sim.fault_reason.is_empty())
	check("events observe already committed state", observed.size() == 1 and observed[0].modes == sim.modes \
		and observed[0].work == sim.continuous)
	var committed := _raw(sim)
	retained.value.body[0] = 999.0
	retained.value.continuous[0] = 999.0
	retained.value.aux[0] = 999.0
	retained.value.modes[0] = 999
	retained.value.events[0].type = "tampered"
	check("returned frame/event aliases are detached", committed == _raw(sim))
	var snapshot: Dictionary = sim.checkpoint()
	check("direct kernel checkpoint contains opt-in identity and modes", snapshot.get("format") == Sim.ENDPOINT_CHECKPOINT_FORMAT \
		and snapshot.state_layout_identity == sim.model.state_layout_identity and snapshot.modes == sim.modes)
	for _i in 4: sim.step()
	var expected := _raw(sim)
	check("persistent mode does not reemit first transition", observed.size() == 1)
	check("direct checkpoint restore succeeds", sim.restore_checkpoint(snapshot))
	check("restore clears diagnostic events without emitting transition", sim.last_events.is_empty() and observed.size() == 1)
	for _i in 4: sim.step()
	check("restored continuation is byte-identical", expected == _raw(sim))
	var before := _raw(sim)
	var old_identity: String = sim.model.state_layout_identity
	sim.model.state_layout_identity = "other-semantics"
	check("changed live identity cannot relabel a checkpoint", sim.checkpoint().is_empty())
	sim.step()
	check("changed identity faults without moving accepted state", not sim.fault_reason.is_empty() and before == _raw(sim))
	sim.model.state_layout_identity = old_identity
	sim.free()

func _bad_frames() -> void:
	for kind: String in ["body_nan", "body_size", "quaternion", "continuous_nan", "continuous_size", "aux_nan", "aux_size",
		"modes_type", "modes_size", "mode_domain", "extra_key", "missing_key", "previous_mutation", "context_mutation"]:
		var sim := _new_sim()
		var signals := [0, 0]
		sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): signals[0] += 1)
		sim.events_located.connect(func(_a, _b): signals[1] += 1)
		var before := _raw(sim)
		sim.model.endpoint_transition = func(previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
			var out := _result(candidate, [{type = "never", time_s = context.time_s}])
			match kind:
				"body_nan": out.body[0] = NAN
				"body_size": out.body.resize(12)
				"quaternion":
					for at in range(RB.ATT, RB.ATT + 4): out.body[at] = 0.0
				"continuous_nan": out.continuous[0] = NAN
				"continuous_size": out.continuous.resize(2)
				"aux_nan": out.aux[1] = INF
				"aux_size": out.aux.resize(3)
				"modes_type": out.modes = PackedFloat64Array([0.0, 0.0])
				"modes_size": out.modes.resize(3)
				"mode_domain": out.modes[0] = 8
				"extra_key": out.inputs = PackedFloat64Array()
				"missing_key": out.erase("aux")
				"previous_mutation": previous.aux[1] = 99.0
				"context_mutation": context.dt = 99.0
			return out
		sim.step()
		check("invalid frame rejects entire transaction: " + kind, not sim.fault_reason.is_empty() and before == _raw(sim))
		check("rejected frame publishes no tick or event: " + kind, signals == [0, 0])
		sim.free()

func _live_mutations() -> void:
	for kind: String in ["inputs", "mass", "inertia", "gravity", "state", "aux", "continuous", "modes", "clock", "history", "model", "events"]:
		var sim := _new_sim()
		var before := _raw(sim)
		sim.model.endpoint_transition = func(_previous: Dictionary, candidate: Dictionary, _context: Dictionary) -> Dictionary:
			match kind:
				"inputs": sim.inputs[0] = 0.8
				"mass": sim.mass = 123.0
				"inertia": sim.inertia[0] = 123.0
				"gravity": sim.gravity = 123.0
				"state": sim.state[0] = 123.0
				"aux": sim.aux[0] = 123.0
				"continuous": sim.continuous[0] = 123.0
				"modes": sim.modes[0] = 123
				"clock": sim.tick = 123
				"history": sim._last_valid_state[0] = 123.0
				"model": sim.model.identity.mutated = true
				"events": sim.last_events.append({type = "phantom", time_s = 0.0})
			return _result(candidate)
		sim.step()
		check("live mutation is reverted before rollback: " + kind, before == _raw(sim) and not sim.fault_reason.is_empty() \
			and not sim.model.identity.has("mutated"))
		sim.free()

func _events() -> void:
	for kind: String in ["valid", "without_ids", "duplicate", "policy_duplicate", "empty_id", "numeric_id", "long_id",
		"past", "future", "nan_time", "empty_type", "nan_payload", "object_payload", "too_many", "wrong_array", "payload_budget"]:
		var sim := _new_sim()
		var before := _raw(sim)
		if kind in ["valid", "policy_duplicate"]:
			sim.model.step_policy = func(combined, time_s, dt_tick, derivative, first):
				return {state = RK.rk4_step_at(combined, time_s, dt_tick, derivative, first),
					events = [{type = "located", time_s = time_s + dt_tick, event_id = "located:first"}]}
		sim.model.endpoint_transition = func(_previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
			var event := {type = "endpoint", time_s = context.time_s, event_id = "endpoint:first"}
			var events: Variant = [event]
			match kind:
				"without_ids":
					event.erase("event_id")
					events.append(event.duplicate())
				"duplicate": events.append(event.duplicate())
				"policy_duplicate": event.event_id = "located:first"
				"empty_id": event.event_id = ""
				"numeric_id": event.event_id = 1
				"long_id": event.event_id = "x".repeat(257)
				"past": event.time_s = context.time_s - 2.0 * context.dt
				"future": event.time_s = context.time_s + context.dt
				"nan_time": event.time_s = NAN
				"empty_type": event.type = ""
				"nan_payload": event.work_j = NAN
				"object_payload": event.object = sim
				"too_many":
					event.erase("event_id")
					events.resize(Sim.MAX_ENDPOINT_EVENTS + 1)
				"wrong_array": events = {}
				"payload_budget":
					var nested: Array = []
					for _index in 32: nested.append(range(256))
					event.payload = nested
			var out := _result(candidate)
			out.events = events
			return out
		sim.step()
		if kind == "valid":
			check("located and endpoint events retain order", sim.fault_reason.is_empty() and sim.last_events.size() == 2 \
				and sim.last_events[0].type == "located" and sim.last_events[1].type == "endpoint")
		elif kind == "without_ids":
			check("events without IDs preserve duplicate legacy semantics", sim.fault_reason.is_empty() and sim.last_events.size() == 2)
		else:
			check("malformed event batch rejects atomically: " + kind, not sim.fault_reason.is_empty() and before == _raw(sim))
		sim.free()

func _validator_and_reset() -> void:
	var sim := _new_sim()
	var snapshot: Dictionary = sim.checkpoint()
	sim.step()
	sim.step()
	check("restore fixture has a later live clock than its snapshot", sim.tick > snapshot.tick)
	for kind: String in ["format", "identity", "missing_identity", "extra", "mode", "work", "projection", "future_transition"]:
		var bad := snapshot.duplicate(true)
		match kind:
			"format": bad.format = Sim.CHECKPOINT_FORMAT
			"identity": bad.state_layout_identity = "other"
			"missing_identity": bad.erase("state_layout_identity")
			"extra": bad.extra = false
			"mode": bad.modes[0] = 4
			"work": bad.continuous[0] = -1.0
			"projection": bad.aux[0] = 9.0
			"future_transition":
				bad.modes[0] = 1
				bad.modes[1] = bad.tick + 1
		var before := _raw(sim)
		check("strict v2 restore rejects without mutation: " + kind, not sim.restore_checkpoint(bad) and before == _raw(sim) \
			and sim.fault_reason.is_empty())
	var legacy := Sim.new()
	check("legacy reader refuses opt-in v2 checkpoint", not legacy.can_restore_checkpoint(snapshot))
	legacy.free()
	var prepared: Dictionary = sim.prepare_reset(_body())
	var before := _raw(sim)
	prepared.state[RB.VEL] += 2.0
	check("tampered prepared reset is rejected without publication", not sim.commit_prepared_reset(prepared) and before == _raw(sim))
	prepared = sim.prepare_reset(_body())
	sim.mass = 2.0
	before = _raw(sim)
	check("changed reset context is refused and preserved", not sim.commit_prepared_reset(prepared) and before == _raw(sim))
	sim.mass = 1.0
	for kind: String in ["return_type", "frame_mutation", "context_mutation", "mass_mutation", "input_mutation"]:
		sim.model.state_validator = func(frame: Dictionary, context: Dictionary) -> Variant:
			match kind:
				"return_type": return 1
				"frame_mutation": frame.modes[0] = 1
				"context_mutation": context.tick += 1
				"mass_mutation": sim.mass = 9.0
				"input_mutation": sim.inputs[0] = 0.9
			return true
		before = _raw(sim)
		check("reset validator rejection is atomic: " + kind, not sim.prepare_reset(_body()).ok and before == _raw(sim))
		check("restore validator rejection is atomic: " + kind, not sim.restore_checkpoint(snapshot) and before == _raw(sim))
	sim.free()

func _projection_and_filter() -> void:
	var sim := _new_sim()
	var filtered := [false]
	sim.model.post_tick = func(_p, candidate, _tick):
		candidate[0] += 0.5
		return candidate
	sim.model.endpoint_transition = func(_p, candidate, context):
		filtered[0] = context.body_filtered
		return _result(candidate)
	sim.step()
	check("endpoint context discloses body filtering", sim.fault_reason.is_empty() and filtered[0])
	sim.free()
	for kind: String in ["projection_nan", "projection_mass", "projection_nonidempotent", "filter_mass", "validator_final"]:
		sim = _new_sim()
		var before := _raw(sim)
		var published := [0, 0]
		sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): published[0] += 1)
		sim.events_located.connect(func(_a, _b): published[1] += 1)
		if kind.begins_with("projection"):
			sim.model.block_aux = func(_extra, sampled):
				if kind == "projection_mass": sim.mass = 42.0
				elif kind == "projection_nonidempotent":
					sampled[0] = _extra[0]
					sampled[1] += 1.0
				else: sampled[0] = NAN
				return sampled
		elif kind == "filter_mass":
			sim.model.post_tick = func(_p, candidate, _tick):
				sim.mass = 42.0
				return candidate
		else:
			sim.model.endpoint_transition = func(_p, candidate, _context):
				candidate.modes[0] = 7
				return _result(candidate)
		sim.step()
		check("later endpoint failure rolls every channel back: " + kind, not sim.fault_reason.is_empty() and before == _raw(sim))
		check("later endpoint failure emits no observers: " + kind, published == [0, 0])
		sim.free()

func _body_only_and_validator_step() -> void:
	var body_only := Sim.new()
	var model := Model.new()
	model.state_layout_identity = "body-only-endpoint-v1"
	model.aux_size = 0
	model.continuous_size = 0
	model.modes_size = 0
	model.endpoint_transition = func(_previous, candidate, context):
		candidate.body[RB.VEL] = 2.0
		return _result(candidate, [{type = "body_only", time_s = context.time_s}])
	body_only.aux = PackedFloat64Array()
	check("body-only endpoint setup", body_only.set_model(model) and body_only.reset(_body()))
	body_only.step()
	check("body-only transition commits without inventing continuous state", body_only.tick == 1 and body_only.state[RB.VEL] == 2.0 \
		and body_only.continuous.is_empty() and body_only.last_events.size() == 1)
	body_only.free()
	for kind: String in ["mass", "inputs", "frame", "context", "return_type"]:
		var sim := _new_sim()
		var before := _raw(sim)
		sim.model.state_validator = func(frame: Dictionary, context: Dictionary) -> Variant:
			match kind:
				"mass": sim.mass = 12.0
				"inputs": sim.inputs[0] = 0.6
				"frame": frame.modes[0] = 1
				"context": context.dt = 5.0
				"return_type": return 1
			return true
		sim.step()
		check("step validator rejects mutation/type without state loss: " + kind, not sim.fault_reason.is_empty() and before == _raw(sim))
		sim.free()

func _reentry() -> void:
	for kind: String in ["step", "reset", "prepare", "commit", "restore", "pause", "checkpoint", "model"]:
		var sim := _new_sim()
		var snapshot: Dictionary = sim.checkpoint()
		var prepared: Dictionary = sim.prepare_reset(_body())
		var published := [0, 0]
		sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): published[0] += 1)
		sim.events_located.connect(func(_a, _b): published[1] += 1)
		var before := _raw(sim)
		sim.model.endpoint_transition = func(_p, candidate, _context):
			match kind:
				"step": sim.step()
				"reset": sim.reset(_body())
				"prepare": sim.prepare_reset(_body())
				"commit": sim.commit_prepared_reset(prepared)
				"restore": sim.restore_checkpoint(snapshot)
				"pause": sim.set_paused(true)
				"checkpoint": sim.checkpoint()
				"model": sim.set_model(Model.new())
			return _result(candidate)
		sim.step()
		check("endpoint kernel reentry is refused atomically: " + kind, before == _raw(sim) and not sim.fault_reason.is_empty())
		check("reentry cannot publish a nested tick/event: " + kind, published == [0, 0])
		sim.free()

func _clock_identity_and_owner() -> void:
	var sim := _new_sim()
	var seen: Array = []
	sim.model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
		seen.append(context.duplicate(true))
		return context.size() == 3 and typeof(context.tick) == TYPE_INT and typeof(context.dt) == TYPE_FLOAT \
			and context.tick >= 0 and context.dt > 0.0 and context.time_s == context.tick * context.dt
	check("reset validation receives reset clock", sim.reset(_body()) and seen.size() >= 2 and seen[0].tick == 0)
	var saved: Dictionary = sim.checkpoint()
	seen.clear()
	sim.step()
	check("step validates both current and candidate clocks", seen.size() == 2 and seen[0].tick == 0 and seen[1].tick == 1)
	sim.step()
	seen.clear()
	check("restore validates saved clock rather than live clock", sim.restore_checkpoint(saved) and seen.size() == 1 and seen[0].tick == 0)
	sim.free()
	sim = _new_sim()
	var before := _raw(sim)
	sim.model.endpoint_transition = Callable()
	sim.model.state_validator = Callable()
	sim.model.state_layout_identity = ""
	sim.step()
	check("cleared identity cannot downgrade a pinned step", not sim.fault_reason.is_empty() and before == _raw(sim))
	sim.free()
	var first := _new_sim()
	var second := _new_sim()
	check("two owners can deliberately share a model", second.set_model(first.model))
	var prepared: Dictionary = first.prepare_reset(_body())
	before = _raw(second)
	var resets := [0]
	second.stepped.connect(func(_a, _b, _c, _d, _e, _f): resets[0] += 1)
	check("another owner's prepared reset is refused", not second.commit_prepared_reset(prepared) \
		and before == _raw(second) and resets[0] == 0)
	check("preparing owner still accepts its own reset", first.commit_prepared_reset(prepared))
	first.free()
	second.free()
