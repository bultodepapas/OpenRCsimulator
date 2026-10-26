## GP-16/17 pure experimental capacity/energy contract and generic kernel composition.
## Synthetic thresholds/loads are software fixtures, not calibrated aircraft structure.
extends SceneTree
const Damage := preload("res://physics/gear_damage.gd")
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_profiles()
	_thresholds_and_energy()
	_grouping()
	_state_rejection()
	_input_rejection()
	_kernel_composition()
	print("Gear damage core: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _component(id: String, supports: Array, limit: Variant = 10.0) -> Dictionary:
	var result := {component_id = id, support_ids = supports, source = "Synthetic attached support fixture; no hardware calibration"}
	if limit != null:
		result.normal_failure_force = {value = limit, unit = "N", kind = "estimated", source = "Explicit synthetic fixture capacity, not an RC measurement"}
	return result

func _raw(components: Array) -> Dictionary:
	return {format = Damage.FORMAT, law = Damage.LAW, source = "GP-16/17 synthetic software fixture", components = components}

func _profile(components: Array = [], supports: Array = ["a"]) -> Dictionary:
	var prepared := Damage.prepare(_raw([_component("leg", ["a"])] if components.is_empty() else components), supports)
	check("profile fixture prepares", prepared.ok)
	return prepared.get("profile", {})

func _clock(tick: int = 1, dt_value: float = 0.1) -> Dictionary:
	return {tick = tick, time_s = tick * dt_value, dt = dt_value}

func _apply(profile: Dictionary, state: Dictionary, loads: PackedFloat64Array = PackedFloat64Array([11.0]),
		before: PackedFloat64Array = PackedFloat64Array([4.0]), after: PackedFloat64Array = PackedFloat64Array([1.0]), tick: int = 1) -> Dictionary:
	return Damage.transition(profile, state.modes, state.losses, loads, before, after, _clock(tick), "fixture-generation")

func _profiles() -> void:
	var baseline := _raw([_component("leg", ["a"])])
	for kind: String in ["format", "law", "source", "extra", "empty_id", "long_id", "duplicate_component", "double_support",
		"missing_support", "unknown_support", "duplicate_support", "zero_force", "negative_force", "nan_force", "bool_force",
		"unit", "kind", "quantity_source", "quantity_extra", "null_force"]:
		var raw := baseline.duplicate(true)
		match kind:
			"format": raw.format = "future"
			"law": raw.law = "unqualified"
			"source": raw.source = ""
			"extra": raw.extra = true
			"empty_id": raw.components[0].component_id = ""
			"long_id": raw.components[0].component_id = "x".repeat(Damage.MAX_ID_LENGTH + 1)
			"duplicate_component": raw.components.append(_component("leg", ["a"]))
			"double_support": raw.components.append(_component("other", ["a"]))
			"missing_support": raw.components.clear()
			"unknown_support": raw.components[0].support_ids = ["other"]
			"duplicate_support": raw.components[0].support_ids = ["a", "a"]
			"zero_force": raw.components[0].normal_failure_force.value = 0.0
			"negative_force": raw.components[0].normal_failure_force.value = -1.0
			"nan_force": raw.components[0].normal_failure_force.value = NAN
			"bool_force": raw.components[0].normal_failure_force.value = true
			"unit": raw.components[0].normal_failure_force.unit = "kg"
			"kind": raw.components[0].normal_failure_force.kind = "fictional"
			"quantity_source": raw.components[0].normal_failure_force.source = ""
			"quantity_extra": raw.components[0].normal_failure_force.extra = false
			"null_force": raw.components[0].normal_failure_force = null
		var bytes := var_to_bytes(raw)
		check("invalid profile rejected without mutation: " + kind, not Damage.prepare(raw, ["a"]).ok and bytes == var_to_bytes(raw))
	check("duplicate installed IDs rejected", not Damage.prepare(baseline, ["a", "a"]).ok)
	check("unbound installed ID rejected", not Damage.prepare(baseline, ["a", "b"]).ok)
	var many: Array = []
	for index in Damage.MAX_COMPONENTS + 1: many.append(_component("c%d" % index, ["s%d" % index]))
	check("component count bound enforced", not Damage.prepare(_raw(many), ["a"]).ok)
	var empty := Damage.prepare(_raw([]), PackedStringArray())
	check("no installed support creates no invented component", empty.ok and Damage.initial_state(empty.profile).modes.is_empty())
	var profile := _profile()
	var prepared_bytes := var_to_bytes(profile)
	var initial := Damage.initial_state(profile)
	initial.modes[0] = 9
	check("initial state arrays do not alias prepared profile", prepared_bytes == var_to_bytes(profile))
	var corrupted := profile.duplicate(true)
	corrupted.components[0].normal_failure_force.value = 999.0
	check("changed prepared profile must be re-prepared", not Damage.initial_state(corrupted).ok)
	corrupted = profile.duplicate(true)
	corrupted.support_to_component[0] = 99
	check("tampered support mapping rejected", not Damage.initial_state(corrupted).ok)

func _thresholds_and_energy() -> void:
	var profile := _profile()
	var initial := Damage.initial_state(profile)
	var initial_bytes := var_to_bytes(initial)
	for load_value: float in [0.0, 9.9, 10.0]:
		var unfailed := _apply(profile, initial, PackedFloat64Array([load_value]), PackedFloat64Array([1.0]), PackedFloat64Array([100.0]))
		check("below/at capacity keeps healthy and ignores unused after potential", unfailed.ok and unfailed.modes[0] == Damage.HEALTHY \
			and unfailed.losses[0] == 0.0 and unfailed.events.is_empty())
	var failed := _apply(profile, initial)
	check("capacity breach creates attached nonterminal failure", failed.ok and failed.modes == PackedInt64Array([Damage.FAILED_ATTACHED, 1]) \
		and failed.events.size() == 1 and not failed.events[0].terminal)
	check("transition closes the potential-loss ledger exactly", failed.losses[0] == 3.0 and failed.events[0].transition_loss_j == 3.0 \
		and failed.events[0].potential_before_j - failed.events[0].potential_after_j == failed.losses[0])
	check("loss receipt identifies elastic/stop/anchor provenance", failed.events[0].loss_provenance.contains("anchor") \
		and failed.events[0].qualification == Damage.QUALIFICATION)
	check("input state remains detached and untouched", var_to_bytes(initial) == initial_bytes)
	var repeated := _apply(profile, failed, PackedFloat64Array([999.0]), PackedFloat64Array([0.0]), PackedFloat64Array([100.0]))
	check("same-tick persistent scrape has no repeated event or energy charge", repeated.ok and repeated.events.is_empty() and repeated.losses == failed.losses)
	for tick in range(2, 102):
		repeated = _apply(profile, repeated, PackedFloat64Array([999.0]), PackedFloat64Array([0.0]), PackedFloat64Array([100.0]), tick)
	check("100 later scrape ticks retain one first tick/loss", repeated.ok and repeated.modes[1] == 1 \
		and repeated.events.is_empty() and repeated.losses[0] == 3.0)
	var retry := _apply(profile, initial)
	check("rollback retry yields deterministic bytes", var_to_bytes(retry) == var_to_bytes(failed))
	var event_id: String = failed.events[0].event_id
	failed.events[0].support_ids[0] = "tampered"
	failed.modes[0] = 99
	failed.losses[0] = 999.0
	check("returned fields cannot mutate profile or later results", profile.components[0].support_ids[0] == "a" \
		and _apply(profile, initial).events[0].event_id == event_id and initial.modes[0] == 0)
	var other_generation := Damage.transition(profile, initial.modes, initial.losses, PackedFloat64Array([11.0]),
		PackedFloat64Array([4.0]), PackedFloat64Array([1.0]), _clock(), "another-generation")
	check("new generation namespaces the same component transition", other_generation.ok and other_generation.events[0].event_id != event_id)
	var zero_release := _apply(profile, initial, PackedFloat64Array([11.0]), PackedFloat64Array([4.0]), PackedFloat64Array([4.0]))
	check("zero potential release permits failure without invented energy", zero_release.ok and zero_release.losses[0] == 0.0 \
		and Damage.validate_state(profile, zero_release.modes, zero_release.losses, 1))
	var unknown := _profile([_component("leg", ["a"], null)])
	var unknown_result := _apply(unknown, Damage.initial_state(unknown), PackedFloat64Array([1e100]))
	check("absent strength stays healthy and inspection-required", unknown_result.ok and unknown_result.modes[0] == Damage.HEALTHY \
		and unknown_result.events.is_empty() and unknown_result.assessments[0] == "inspection_required_unknown_strength")
	var strong := _profile([_component("leg", ["a"], 20.0)])
	check("stronger configured component survives the same load", _apply(strong, Damage.initial_state(strong)).modes[0] == Damage.HEALTHY)
	var weight_profile := _profile([_component("leg", ["a"], 15.0)])
	var light := _apply(weight_profile, Damage.initial_state(weight_profile), PackedFloat64Array([1.0 * 9.80665]))
	var heavy := _apply(weight_profile, Damage.initial_state(weight_profile), PackedFloat64Array([2.0 * 9.80665]))
	check("mass affects the producer's load, not a hidden mass switch", light.modes[0] == Damage.HEALTHY and heavy.modes[0] == Damage.FAILED_ATTACHED)
	var pair := _profile([_component("a_leg", ["a"]), _component("b_leg", ["b"])], ["a", "b"])
	var pair_initial := Damage.initial_state(pair)
	var pair_bytes := var_to_bytes(pair_initial)
	var simultaneous := _apply(pair, pair_initial, PackedFloat64Array([11.0, 11.0]), PackedFloat64Array([4.0, 8.0]), PackedFloat64Array([1.0, 2.0]))
	check("simultaneous components emit unique canonical events and separate losses", simultaneous.ok and simultaneous.losses == PackedFloat64Array([3.0, 6.0]) \
		and simultaneous.events[0].component_id == "a_leg" and simultaneous.events[1].component_id == "b_leg" \
		and simultaneous.events[0].event_id != simultaneous.events[1].event_id)
	var gain := _apply(pair, pair_initial, PackedFloat64Array([11.0, 11.0]), PackedFloat64Array([4.0, 1.0]), PackedFloat64Array([0.0, 2.0]))
	check("second component energy gain rejects the entire batch", not gain.ok and gain.events.is_empty() and pair_bytes == var_to_bytes(pair_initial))
	var overflow := _apply(pair, pair_initial, PackedFloat64Array([11.0, 11.0]), PackedFloat64Array([1e308, 1e308]), PackedFloat64Array([0.0, 0.0]))
	check("finite rows with overflowing total ledger reject atomically", not overflow.ok and overflow.events.is_empty() \
		and pair_bytes == var_to_bytes(pair_initial))

func _grouping() -> void:
	var single := _profile()
	var split := _profile([_component("leg", ["a1", "a2"])], ["a1", "a2"])
	var loads := Damage.sum_aligned_normal_loads(split, PackedFloat64Array([5.0, 6.0]), true)
	check("qualified aligned supports sum once per component", loads.ok and loads.loads_n == PackedFloat64Array([11.0]))
	check("unqualified axes cannot use scalar summation", not Damage.sum_aligned_normal_loads(split, PackedFloat64Array([5.0, 6.0]), false).ok)
	check("negative support normal is rejected, not absolutized", not Damage.sum_aligned_normal_loads(split, PackedFloat64Array([-5.0, 6.0]), true).ok)
	check("support load aggregate overflow rejected", not Damage.sum_aligned_normal_loads(split, PackedFloat64Array([1e308, 1e308]), true).ok)
	var a := _apply(single, Damage.initial_state(single))
	var b := _apply(split, Damage.initial_state(split), loads.loads_n)
	check("probe split preserves mode/loss and physical component event ID", a.modes == b.modes and a.losses == b.losses \
		and a.events[0].event_id == b.events[0].event_id and a.events.size() == b.events.size())
	var components := [_component("z_leg", ["b"]), _component("a_leg", ["a"])]
	var first := _profile(components, ["b", "a"])
	components.reverse()
	var second := _profile(components, ["b", "a"])
	check("author component order cannot move state slots", first.identity == second.identity and first.components[0].component_id == "a_leg")
	var mapped := Damage.sum_aligned_normal_loads(first, PackedFloat64Array([4.0, 7.0]), true)
	check("native support order maps to sorted component slots", mapped.ok and mapped.loads_n == PackedFloat64Array([7.0, 4.0]))

func _state_rejection() -> void:
	var profile := _profile()
	for kind: String in ["mode_type", "mode_size", "mode_code", "healthy_tick", "healthy_loss", "failed_tick", "future_tick", "negative_loss", "nan_loss", "loss_type"]:
		var state := Damage.initial_state(profile)
		match kind:
			"mode_type": state.modes = PackedFloat64Array([0.0, -1.0])
			"mode_size": state.modes.resize(1)
			"mode_code": state.modes[0] = 8
			"healthy_tick": state.modes[1] = 0
			"healthy_loss": state.losses[0] = 1.0
			"failed_tick": state.modes[0] = Damage.FAILED_ATTACHED
			"future_tick": state.modes = PackedInt64Array([Damage.FAILED_ATTACHED, 2])
			"negative_loss": state.losses[0] = -1.0
			"nan_loss": state.losses[0] = NAN
			"loss_type": state.losses = [0.0]
		check("malformed component checkpoint rejected: " + kind, not Damage.validate_state(profile, state.modes, state.losses, 1))
	var unknown := _profile([_component("leg", ["a"], null)])
	check("unknown strength cannot restore as physically failed", not Damage.validate_state(unknown, PackedInt64Array([1, 1]), PackedFloat64Array([0.0]), 1))

func _input_rejection() -> void:
	var profile := _profile()
	var state := Damage.initial_state(profile)
	for tick: int in [1, 2, 17, 999999, 1000000000]:
		var step_dt := 1.0 / 240.0
		var context := {tick = tick, time_s = (tick - 1) * step_dt + step_dt, dt = step_dt}
		var context_bytes := var_to_bytes(context)
		var loads := PackedFloat64Array([11.0])
		var before := PackedFloat64Array([4.0])
		var after := PackedFloat64Array([1.0])
		var input_bytes := var_to_bytes([profile, state, loads, before, after])
		var accepted := Damage.transition(profile, state.modes, state.losses, loads, before, after, context, "clock-fixture")
		check("kernel endpoint clock arithmetic accepted without mutating any input", accepted.ok and accepted.modes[1] == tick \
			and var_to_bytes(context) == context_bytes and var_to_bytes([profile, state, loads, before, after]) == input_bytes)
	for kind: String in ["load_size", "load_negative", "load_nan", "before_size", "before_negative", "after_nan", "after_increase",
		"generation_empty", "generation_long", "generation_type", "time", "dt_zero", "tick_zero", "tick_float", "time_type", "clock_extra"]:
		var loads: Variant = PackedFloat64Array([11.0])
		var before: Variant = PackedFloat64Array([4.0])
		var after: Variant = PackedFloat64Array([1.0])
		var context := _clock()
		var generation: Variant = "fixture-generation"
		match kind:
			"load_size": loads = PackedFloat64Array()
			"load_negative": loads[0] = -1.0
			"load_nan": loads[0] = NAN
			"before_size": before = PackedFloat64Array()
			"before_negative": before[0] = -1.0
			"after_nan": after[0] = NAN
			"after_increase": after[0] = 5.0
			"generation_empty": generation = ""
			"generation_long": generation = "x".repeat(Damage.MAX_ID_LENGTH + 1)
			"generation_type": generation = 1
			"time": context.time_s += context.dt
			"dt_zero": context.dt = 0.0
			"tick_zero": context.tick = 0
			"tick_float": context.tick = 1.0
			"time_type": context.time_s = 0
			"clock_extra": context.extra = false
		var bytes := var_to_bytes(state)
		var bad := Damage.transition(profile, state.modes, state.losses, loads, before, after, context, generation)
		check("invalid transition input rejected atomically: " + kind, not bad.ok and bad.events.is_empty() and bytes == var_to_bytes(state))

func _body() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(2.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))

## This is a generic endpoint adapter fixture, not a new contact solver or a flight validation.
func _simulation(profile: Dictionary) -> Node:
	var initial := Damage.initial_state(profile)
	var model := Model.new()
	model.state_layout_identity = Damage.LAW + ":" + str(profile.identity)
	model.aux_size = 0
	model.modes_size = initial.modes.size()
	model.continuous_size = initial.losses.size()
	model.state_validator = func(frame: Dictionary, context: Dictionary) -> bool:
		return Damage.validate_state(profile, frame.modes, frame.continuous, context.tick)
	model.stage = func(_body_value, extra: PackedFloat64Array, _time_value):
		var derivative := PackedFloat64Array()
		derivative.resize(extra.size())
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, 0.0)}
	model.endpoint_transition = func(_previous, candidate, context):
		var applied := Damage.transition(profile, candidate.modes, candidate.continuous, PackedFloat64Array([11.0]),
			PackedFloat64Array([4.0]), PackedFloat64Array([1.0]),
			{tick = context.tick, time_s = context.time_s, dt = context.dt}, "kernel-fixture-generation")
		if not applied.ok: return {}
		candidate.modes = applied.modes
		candidate.continuous = applied.losses
		candidate.events = applied.events
		return candidate
	var sim := Sim.new()
	sim.aux = PackedFloat64Array()
	sim.modes = initial.modes.duplicate()
	sim.continuous = initial.losses.duplicate()
	sim.gravity = 0.0
	check("kernel profile model installs", sim.set_model(model))
	check("kernel profile reset is valid", sim.reset(_body()))
	return sim

func _kernel_composition() -> void:
	var profile := _profile()
	var sim := _simulation(profile)
	var published := [0]
	sim.events_located.connect(func(_tick, _events): published[0] += 1)
	sim.step()
	check("kernel atomically commits damage mode and exact loss", sim.tick == 1 and sim.modes == PackedInt64Array([1, 1]) \
		and sim.continuous == PackedFloat64Array([3.0]) and sim.last_events.size() == 1)
	check("failure preserves body velocity and finite continued motion", sim.state[RB.VEL] == 2.0 and sim.state[RB.POS] > 0.0 and sim.fault_reason.is_empty())
	var saved: Dictionary = sim.checkpoint()
	for _tick in 12: sim.step()
	check("repeated accepted motion cannot re-charge loss or emit damage", sim.tick == 13 and sim.continuous[0] == 3.0 and published[0] == 1)
	var expected: PackedByteArray = var_to_bytes(sim.checkpoint())
	var invalid := saved.duplicate(true)
	invalid.modes[1] = saved.tick + 1
	check("direct kernel restore rejects future damage tick against saved clock", not sim.restore_checkpoint(invalid) \
		and expected == var_to_bytes(sim.checkpoint()))
	check("direct kernel restores failed component and loss ledger", sim.restore_checkpoint(saved) and sim.last_events.is_empty() and published[0] == 1)
	for _tick in 12: sim.step()
	check("checkpoint continuation is byte-identical", expected == var_to_bytes(sim.checkpoint()) and published[0] == 1)
	var before: PackedByteArray = var_to_bytes(sim.checkpoint())
	check("reset cannot silently carry a future failed tick into tick zero", not sim.prepare_reset(_body()).ok and before == var_to_bytes(sim.checkpoint()))
	var initial := Damage.initial_state(profile)
	sim.modes = initial.modes.duplicate()
	sim.continuous = initial.losses.duplicate()
	check("explicit new-flight initialization clears damage transactionally", sim.reset(_body()) and sim.modes == initial.modes \
		and sim.continuous == initial.losses and sim.last_events.is_empty() and published[0] == 1)
	sim.free()
	sim = _simulation(profile)
	before = var_to_bytes(sim.checkpoint())
	var phantom := [0]
	sim.events_located.connect(func(_a, _b): phantom[0] += 1)
	sim.model.block_aux = func(_extra, _sampled): return PackedFloat64Array([NAN])
	sim.step()
	check("later projection rejection rolls back candidate damage/body/loss", sim.tick == 0 and sim.modes == PackedInt64Array([0, -1]) \
		and sim.continuous == PackedFloat64Array([0.0]) and sim.state == _body() and not sim.fault_reason.is_empty())
	check("rejected damage transition emits no phantom event", phantom[0] == 0 and sim.last_events.is_empty())
	sim.free()
