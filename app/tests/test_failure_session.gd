extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureRuntime := preload("res://failures/runtime.gd")
const RB := preload("res://physics/rigid_body.gd")
const VisualCheckpoint := preload("res://app_state/visual_checkpoint.gd")
const VisualTimeline := preload("res://environment/visual_timeline.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_all_airplane_configs()
	_test_tick_zero_configuration()
	_test_activation_checkpoint_and_rollback()
	print("Failure session integration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _config(probability: int = 100, include_catastrophic: bool = false, notify: bool = true) -> Dictionary:
	return {
		"probability_percent": probability,
		"include_catastrophic": include_catastrophic,
		"notify": notify,
	}


func _new_flight(id: String) -> Node:
	var entry: Dictionary = Catalog.entry(id)
	var flight: Node = Flight.new()
	flight.setup(str(entry.get("data", "")), id)
	flight.input_enabled = false
	return flight


func _test_all_airplane_configs() -> void:
	var ids: PackedStringArray = Catalog.airplane_flyable_ids()
	_check("catalog retains at least the original seven airplane configs", ids.size() >= 7, ids)
	for id: String in ids:
		var baseline: Node = _new_flight(id)
		var configured: Node = _new_flight(id)
		_check(id + " creates a valid baseline physics flight", baseline.is_flyable())
		_check(id + " creates a valid configured physics flight", configured.is_flyable())
		var before: PackedByteArray = var_to_bytes(configured.sim.checkpoint())
		_check(id + " accepts disabled failure settings at tick zero", configured.setup_failures(FailureConfig.defaults(), 0), configured.failure_error)
		var status: Dictionary = configured.failure_status()
		_check(id + " disabled status stays inactive", not bool(status.get("active", true)) and not bool(status.get("enabled", true)), status)
		_check(id + " disabled settings leave physical checkpoint unchanged", var_to_bytes(configured.sim.checkpoint()) == before)
		for tick in 12:
			var sampled_inputs := PackedFloat64Array([0.1, -0.05, 0.02, 0.55])
			baseline.sim.inputs = sampled_inputs.duplicate()
			configured.sim.inputs = sampled_inputs.duplicate()
			baseline.sim.step()
			configured.sim.step()
		_check(id + " zero probability matches baseline physics for twelve ticks", var_to_bytes(configured.checkpoint()) == var_to_bytes(baseline.checkpoint()))
		baseline.free()
		configured.free()


func _test_tick_zero_configuration() -> void:
	var flight: Node = _new_flight("jensen-das-ugly-stik-60")
	var settings := _config()
	_check("failure plan configures at tick zero", flight.setup_failures(settings, 1751), flight.failure_error)
	var plan: Dictionary = flight._failures.plan()
	_check("session resolves the requested roll jam", str(plan.get("id", "")) == "roll_jam", plan)
	var simulation_before: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
	var runtime_before: Dictionary = flight._failures.snapshot()
	var malformed := settings.duplicate(true)
	malformed.erase("notify")
	_check("malformed settings are refused", not flight.setup_failures(malformed, 1751))
	_check("bad settings leave the selected plan intact", flight._failures.plan() == plan and flight._failures.snapshot() == runtime_before)
	_check("bad settings leave physics intact", var_to_bytes(flight.sim.checkpoint()) == simulation_before)
	_check("out-of-range seed is refused", not flight.setup_failures(settings, -1))
	_check("bad seed leaves the selected plan intact", flight._failures.plan() == plan and flight._failures.snapshot() == runtime_before)
	flight.sim.step()
	_check("manual tick advances the unparented session", flight.sim.tick == 1 and flight.sim.fault_reason.is_empty())
	var after_tick: Dictionary = flight._failures.snapshot()
	_check("failure configuration is refused after flight starts", not flight.setup_failures(settings, 7))
	_check("late configuration leaves failure episode intact", flight._failures.plan() == plan and flight._failures.snapshot() == after_tick)
	flight.free()


func _test_activation_checkpoint_and_rollback() -> void:
	var source: Node = _new_flight("jensen-das-ugly-stik-60")
	var initial: PackedFloat64Array = source.sim.state.duplicate()
	initial[RB.POS + 2] = -1000.0
	_check("test flight moves to a verified airborne altitude", source.sim.reset(initial) and source._failure_airborne())
	_check("roll-jam episode configures", source.setup_failures(_config(), 1751), source.failure_error)
	var plan: Dictionary = source._failures.plan()
	var onset: int = int(plan.onset_airborne_ticks)
	_check("roll-jam seed has a 20 second onset", str(plan.id) == "roll_jam" and int(plan.onset_airborne_seconds) == 20)
	_check("session onset matches its fixed timestep", onset == int(ceili(20.0 / source.sim.dt())), {"onset": onset, "dt": source.sim.dt()})
	var source_events: Array[int] = [0]
	var source_notice: Callable = func() -> void:
		source_events[0] += 1
		_check("onset observer can save a complete accepted checkpoint", not source.checkpoint().is_empty())
	source.failure_changed.connect(source_notice)
	while int(source._failures.snapshot().airborne_ticks) < onset - 1 and source.sim.tick < onset:
		var previous_tick: int = source.sim.tick
		source.sim.step()
		if source.sim.tick == previous_tick:
			break
	_check("pre-onset session reaches exactly one tick before activation", source.sim.tick == onset - 1 and int(source._failures.snapshot().airborne_ticks) == onset - 1)
	var pre_onset_checkpoint: Dictionary = source.checkpoint()
	_check("pre-onset v10 checkpoint captures the inactive plan", pre_onset_checkpoint.get("format", "") == "openrc-flight-checkpoint v10" and not bool(pre_onset_checkpoint.get("failure_state", {}).get("active", true)))

	var rollback_session: Node = _new_flight("jensen-das-ugly-stik-60")
	var rollback_events: Array[int] = [0]
	var rollback_notice: Callable = func() -> void: rollback_events[0] += 1
	rollback_session.failure_changed.connect(rollback_notice)
	_check("pre-onset state restores into an isolated session", rollback_session.restore_checkpoint(pre_onset_checkpoint))
	var onset_before: PackedByteArray = _rollback_bytes(rollback_session.sim)
	var failure_before_onset: Dictionary = rollback_session._failures.snapshot()
	var tick_before_onset: int = rollback_session.sim.tick
	var original_post_step: Callable = rollback_session.sim.post_step
	rollback_session.sim.post_step = func(previous: PackedFloat64Array, candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
		if original_post_step.is_valid():
			original_post_step.call(previous, candidate, tick)
		return PackedFloat64Array([NAN])
	rollback_session.sim.step()
	_check("rejected onset candidate faults without advancing the clock", rollback_session.sim.tick == tick_before_onset and not rollback_session.sim.fault_reason.is_empty())
	_check("rejected onset candidate restores all simulation state", _rollback_bytes(rollback_session.sim) == onset_before)
	_check("rejected onset candidate rolls back its staged failure", rollback_session._failures.snapshot() == failure_before_onset and not bool(rollback_session.failure_status().get("active", true)))
	_check("rejected onset candidate emits no failure notification", rollback_events[0] == 0)
	rollback_session.sim.post_step = original_post_step
	_check("valid pre-onset checkpoint explicitly recovers the rejected session", rollback_session.restore_checkpoint(pre_onset_checkpoint))
	rollback_session.sim.step()
	source.sim.step()
	var active_status: Dictionary = source.failure_status()
	var recovered_status: Dictionary = rollback_session.failure_status()
	_check("failure activates on the first accepted onset tick", bool(active_status.get("active", false)) and int(active_status.get("activation_tick", -1)) == onset, active_status)
	_check("recovered candidate commits and announces exactly once", bool(recovered_status.get("active", false)) and rollback_events[0] == 1)
	_check("healthy source and recovered session commit identical onset state", var_to_bytes(source.checkpoint()) == var_to_bytes(rollback_session.checkpoint()))
	_check("accepted activation emits one session change", source_events[0] == 1, source_events)
	var jam_state: Dictionary = source._failures.snapshot()
	_check("committed session snapshot identifies the roll jam", jam_state.get("active", false) and jam_state.get("event_id", "") == "roll_jam", jam_state)
	var jam_position: float = float(jam_state.jam_positions[0])
	var opposite_roll := -0.8 if jam_position > -0.75 else 0.8
	source.sim.inputs[0] = opposite_roll
	rollback_session.sim.inputs[0] = opposite_roll
	source.sim.step()
	rollback_session.sim.step()
	_check("pilot command remains recorded through the jam", source.sim.inputs[0] == opposite_roll)
	_check("jam holds the captured aileron servo position", source.sim.aux[Flight.AUX_SERVO] == jam_position, {"captured": jam_position, "actual": source.sim.aux[Flight.AUX_SERVO]})
	_check("no duplicate session change follows onset", source_events[0] == 1)
	_check("recovered session stays physically synchronized after the jam", var_to_bytes(source.checkpoint()) == var_to_bytes(rollback_session.checkpoint()))

	var checkpoint: Dictionary = source.checkpoint()
	_check("active failures use the v10 flight checkpoint", checkpoint.get("format", "") == "openrc-flight-checkpoint v10")
	_check("checkpoint contains the committed failure state", checkpoint.get("failure_state", {}) == source._failures.snapshot())
	var timeline: Dictionary = VisualTimeline.create(LightingConfig.defaults(), 0)
	var visual: Dictionary = VisualCheckpoint.make(checkpoint, timeline.timeline, "failure-test-field")
	_check("visual envelope accepts active v10 checkpoint", visual.ok)
	var visual_read: Dictionary = VisualCheckpoint.read(visual.checkpoint, "failure-test-field") if visual.ok else {}
	_check("visual envelope retains exact failure physics", visual_read.get("ok", false) and var_to_bytes(visual_read.get("physics", {})) == var_to_bytes(checkpoint))
	var malformed_visual: Dictionary = checkpoint.duplicate(true)
	malformed_visual.failure_physics_format = "openrc-flight-checkpoint v10"
	_check("recursive failure format is refused by visual envelope", not VisualCheckpoint.make(malformed_visual, timeline.timeline, "failure-test-field").ok)
	malformed_visual = checkpoint.duplicate(true)
	malformed_visual.failure_state.activation_tick = checkpoint.simulation.tick + 1
	_check("visual envelope rejects a future incident", not VisualCheckpoint.make(malformed_visual, timeline.timeline, "failure-test-field").ok)
	var replay: Node = _new_flight("jensen-das-ugly-stik-60")
	var healthy_checkpoint: Dictionary = replay.checkpoint()
	var replay_events: Array[int] = [0]
	var replay_notice: Callable = func() -> void: replay_events[0] += 1
	replay.failure_changed.connect(replay_notice)
	var encoded: PackedByteArray = var_to_bytes(checkpoint)
	_check("fresh session restores active failure checkpoint", replay.restore_checkpoint(bytes_to_var(encoded)))
	_check("restored status and snapshot match source", replay.failure_status() == source.failure_status() and replay._failures.snapshot() == source._failures.snapshot())
	_check("restored checkpoint round-trips exactly", var_to_bytes(replay.checkpoint()) == encoded)
	_check("restoring a recorded event does not replay its onset notice", replay_events[0] == 0)
	var corrupted: Dictionary = checkpoint.duplicate(true)
	corrupted.failure_state.tick = int(corrupted.failure_state.tick) - 1
	var replay_before_rejection: PackedByteArray = var_to_bytes(replay.checkpoint())
	_check("mismatched failure tick is rejected atomically", not replay.restore_checkpoint(corrupted) and var_to_bytes(replay.checkpoint()) == replay_before_rejection)

	for index in 8:
		source.sim.step()
		replay.sim.step()
	_check("restored failure flight continues deterministically", var_to_bytes(source.checkpoint()) == var_to_bytes(replay.checkpoint()))
	var rollback_before: PackedByteArray = _rollback_bytes(replay.sim)
	var failure_before: Dictionary = replay._failures.snapshot()
	var tick_before_fault: int = replay.sim.tick
	var replay_post_step: Callable = replay.sim.post_step
	replay.sim.post_step = func(previous: PackedFloat64Array, candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
		if replay_post_step.is_valid():
			replay_post_step.call(previous, candidate, tick)
		return PackedFloat64Array([NAN])
	replay.sim.step()
	_check("rejected physics candidate faults without committing", replay.sim.tick == tick_before_fault and not replay.sim.fault_reason.is_empty())
	_check("physics rollback restores every committed simulation field", _rollback_bytes(replay.sim) == rollback_before)
	_check("physics rollback clears staged failure changes only", replay._failures.snapshot() == failure_before)
	_check("rejected candidate does not notify the session", replay_events[0] == 0)
	replay.sim.post_step = replay_post_step
	_check("ordinary checkpoint restores over an active failure", replay.restore_checkpoint(healthy_checkpoint))
	_check("ordinary checkpoint clears failure state and its v10 wrapper", not replay.failure_status().get("active", true) and replay.checkpoint().get("format") == healthy_checkpoint.format)
	replay.free()
	rollback_session.free()
	source.free()


func _rollback_bytes(sim: Object) -> PackedByteArray:
	var committed: Array = []
	for field: String in [
		"state", "previous", "continuous", "aux", "inputs", "modes", "last_loads",
		"tick", "stop_at_tick", "mass", "gravity", "inertia", "_inertia_inv", "_inertia_cache",
		"_last_valid_state", "_last_valid_previous", "_last_valid_continuous", "_last_valid_aux",
		"_last_valid_inputs", "_last_valid_modes", "_last_valid_loads", "_last_valid_tick",
		"_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia",
	]:
		committed.append(sim.get(field))
	return var_to_bytes(committed)
