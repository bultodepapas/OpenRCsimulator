extends SceneTree
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
var _checks := 0
var _failed := 0

func _check(name: String, yes: bool) -> void:
	_checks += 1
	if not yes:
		_failed += 1
		printerr("FAIL ", name)

func _initialize() -> void:
	var old_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 10
	_accepted_path()
	_rejections()
	_detachment_and_filter()
	Engine.physics_ticks_per_second = old_rate
	print("Integration receipts: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)

func _model() -> RefCounted:
	var model := Model.new()
	model.state_layout_identity = "integration-receipt-oscillator-v1"
	model.aux_size = 0
	model.modes_size = 1
	model.continuous_size = 0
	model.loads = func(body, _time):
		return PackedFloat64Array([0, 0, -maxf(0, 1000 * body[RB.POS + 2]), 0, 0, 0])
	model.step_policy = _policy
	model.endpoint_transition = func(_previous, candidate, context):
		var receipt: Dictionary = context.get("integration_receipt", {})
		candidate.events = []
		if receipt.get("peak_load_n", 0.0) > 20.0 and candidate.modes[0] == 0:
			candidate.modes[0] = 1
			candidate.events = [{type = "observed_overload", time_s = receipt.peak_time_s, event_id = "observed:first",
				peak_load_n = receipt.peak_load_n, endpoint_load_n = maxf(0, 1000 * candidate.body[RB.POS + 2])}]
		return candidate
	return model

## Only the chosen 16 accepted substeps supply the local receipt. This is a
## bounded evidence transport fixture, NOT capacity localization/fracture code.
func _policy(initial: PackedFloat64Array, t: float, dt: float, f: Callable, first: PackedFloat64Array) -> Dictionary:
	var state := initial.duplicate()
	var peak := 0.0
	var peak_time := t
	var peak_state := state.duplicate()
	for substep in 16:
		state = RK.rk4_step_at(state, t + substep * dt / 16.0, dt / 16.0, f, first if substep == 0 else PackedFloat64Array())
		var force := maxf(0, 1000 * state[RB.POS + 2])
		if force > peak:
			peak = force
			peak_time = t + (substep + 1) * dt / 16.0
			peak_state = state.duplicate()
	return {state = state, events = [], integration_receipt = {format = "accepted-path-fixture-v1", accepted_substeps = 16,
		peak_load_n = peak, peak_time_s = peak_time, peak_body = peak_state}}

func _simulation(model: RefCounted) -> Node:
	var sim := Sim.new()
	sim.gravity = 0
	sim.aux = PackedFloat64Array()
	sim.modes = PackedInt64Array([0])
	_check("model installs", sim.set_model(model))
	_check("reset accepted", sim.reset(RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 1), M.q_identity(), M.v3(0, 0, 0))))
	return sim

func _accepted_path() -> void:
	var sim := _simulation(_model())
	var publication := [0]
	sim.events_located.connect(func(_tick, _events): publication[0] += 1)
	sim.step()
	_check("accepted path reaches endpoint", sim.tick == 1 and sim.fault_reason.is_empty())
	_check("endpoint is already unloaded", sim.state[RB.POS + 2] < 0)
	_check("opaque receipt carries missed overload", sim.modes[0] == 1 and sim.last_events.size() == 1
		and sim.last_events[0].peak_load_n > 31.0 and sim.last_events[0].endpoint_load_n == 0)
	_check("only semantic event is published", publication[0] == 1 and sim.last_events[0].type == "observed_overload")
	var checkpoint: Dictionary = sim.checkpoint()
	_check("receipt is not a second durable state block", not checkpoint.has("integration_receipt"))
	for _tick in 3: sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("checkpoint restores", sim.restore_checkpoint(checkpoint))
	for _tick in 3: sim.step()
	_check("restored accepted continuation is exact without persisted receipt", expected == var_to_bytes(sim.checkpoint()) and publication[0] == 1)
	sim.free()

func _rejections() -> void:
	for kind: String in ["nan", "object", "oversize", "deep", "wrong_type", "mutate_context", "projection", "missing_owner"]:
		var model := _model()
		if kind == "missing_owner": model.endpoint_transition = Callable()
		var sim := _simulation(model)
		var initial_body: PackedFloat64Array = sim.state.duplicate()
		var published := [0]
		sim.events_located.connect(func(_tick, _events): published[0] += 1)
		var valid: Callable = model.step_policy
		model.step_policy = func(s, t, dt, f, k1):
			var result: Dictionary = valid.call(s, t, dt, f, k1)
			match kind:
				"nan": result.integration_receipt.peak_load_n = NAN
				"object": result.integration_receipt.unknown = sim
				"oversize": result.integration_receipt.text = "x".repeat(1025)
				"deep":
					var value := {}
					for _depth in 10: value = {nested = value}
					result.integration_receipt.deep = value
				"wrong_type": result.integration_receipt = []
			return result
		if kind == "mutate_context":
			model.endpoint_transition = func(_previous, candidate, context):
				context.integration_receipt.peak_body[0] += 1
				candidate.events = []
				return candidate
		if kind == "projection": model.block_aux = func(_state, _aux): return PackedFloat64Array([NAN])
		# Projection runs only for a continuous model. A refusing final validator
		# exercises the same atomic no-publication guarantee in this body-only fixture.
		if kind == "projection": model.state_validator = func(_frame, context): return context.tick == 0
		sim.step()
		_check("invalid/rejected receipt rolls back whole tick: " + kind, sim.tick == 0 and sim.state == initial_body
			and sim.modes[0] == 0 and not sim.fault_reason.is_empty() and published[0] == 0)
		sim.free()

func _detachment_and_filter() -> void:
	var model := _model()
	var owner_payload := {values = PackedFloat64Array([1, 2, 3])}
	model.step_policy = func(s, t, dt, f, k1):
		return {state = RK.rk4_step_at(s, t, dt, f, k1), integration_receipt = owner_payload}
	var received := [false]
	model.post_tick = func(_previous, candidate, _next):
		candidate[0] += 0.1
		return candidate
	model.endpoint_transition = func(_previous, candidate, context):
		received[0] = context.body_filtered and context.integration_receipt.values == PackedFloat64Array([1, 2, 3])
		# The model must decide whether this receipt is valid after its body filter.
		# This fixture observes the flag and makes no physical damage claim.
		owner_payload.values[0] = 99
		candidate.events = []
		return candidate
	var sim := _simulation(model)
	sim.step()
	_check("receipt detaches from policy owner and exposes filtered trajectory", sim.tick == 1 and received[0] and sim.fault_reason.is_empty())
	sim.free()
