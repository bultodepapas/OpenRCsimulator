## Test-only installed hardware owner; synthetic support data is unchanged.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/tmp/gp12-capacity-production/test_traction_capacity.gd"
var pending_receipt: Dictionary = {}
const FALLBACK_VERSION := "bounded-eight-KKT-probe-unresolved-descent-certified-fallback-v2"


func _initialize() -> void:
	selected_law = DraftStep.INTEGRATED_CAPACITY_LAW
	_fixture()
	_prepare_composition()
	_prepare_quality()
	lift_ratio = 0.0
	lift_start = 100.0
	brake_start = 100.0
	_bind()
	var held_identity := (
		"sourcefree-P51-experiment:"
		+ (
			JSON
			. stringify(
				{
					source = _source(),
					properties = live,
					normal = prepared.normal.identity,
					traction = traction.identity,
					provider = provider.identity
				},
				"",
				true,
				true
			)
			. sha256_text()
		)
	)
	capacity_context = DraftTraction.prepare_capacity(
		traction, prepared.normal, provider, motion, held_identity
	)
	check("full owner capacity context binds", capacity_context.ok, str(capacity_context))
	if not capacity_context.ok:
		quit(1)
		return
	var speed := .25
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--speed="):
			speed = argument.trim_prefix("--speed=").to_float()
	_run_full(speed)
	print("Shared capacity full tape: ", checks, " checks, ", failed, " failed")
	quit(1 if failed else 0)


func _mechanical(sim: Node) -> float:
	var state := _combined(sim)
	var point := _snapshot(state, sim.time())
	var velocity_cm := M.add(
		sim.state.slice(RB.VEL, RB.VEL + 3), M.cross(sim.state.slice(RB.RATE), live.cg_body_m)
	)
	return (
		.5 * live.mass_kg * M.dot(velocity_cm, velocity_cm)
		+ Rotor._stage_energy(point.rotor_stage, point.rotor_stage.velocity)
		+ point.potential_j
	)


func _capacity_sim(initial: PackedFloat64Array) -> Node:
	var sim := _new_sim(initial)
	sim.model.state_layout_identity = (
		"full-capacity-owner:"
		+ (
			JSON
			. stringify(
				[
					selected_law,
					Capacity.LAW,
					capacity_context.identity,
					binding.identity,
					FALLBACK_VERSION
				]
			)
			. sha256_text()
		)
	)
	sim.model.step_policy = func(state, at, h, derivative, first):
		return DraftStep.advance(
			state,
			at,
			h,
			derivative,
			first,
			_capacity_sample,
			_capacity_certificate,
			_options(),
			_gate,
			_policy
		)
	var accepted: Callable = sim.model.endpoint_transition
	sim.model.endpoint_transition = func(previous, candidate, context):
		pending_receipt = context.integration_receipt.duplicate(true)
		return accepted.call(previous, candidate, context)
	check(
		"source/operator/fallback identity reset before use", sim.reset(initial.slice(0, RB.SIZE))
	)
	return sim


func _run_full(speed: float) -> void:
	var initial := _initial(-.28, 3.0, speed, 0.0)
	var sim := _capacity_sim(initial)
	var started := Time.get_ticks_msec()
	var initial_energy := _mechanical(sim)
	var frames: Array = []
	var receipts: Array = []
	var checkpoints: Array = [{tick = sim.tick, checkpoint = sim.checkpoint()}]
	var batches: Array = []
	var phase := ["primary"]
	sim.events_located.connect(
		func(tick, events):
			batches.append({phase = phase[0], tick = tick, events = events.duplicate(true)})
	)
	var maximum_compression := 0.0
	var rebounded := false
	var replay_checkpoint: Dictionary = {}
	for i in 180:
		pending_receipt.clear()
		var before: int = sim.tick
		sim.step()
		if sim.tick != before + 1:
			break
		var point := _snapshot(_combined(sim), sim.time())
		for contact: Dictionary in point.physical.ground.contacts:
			if contact.geometry_evaluated:
				maximum_compression = maxf(maximum_compression, -contact.gap_m)
		rebounded = rebounded or (sim.modes[1] == 1 and sim.state[RB.VEL + 2] < -.1)
		frames.append(
			{
				tick = sim.tick,
				time_s = sim.time(),
				state = sim.state.duplicate(),
				continuous = sim.continuous.duplicate(),
				aux = sim.aux.duplicate(),
				modes = sim.modes.duplicate(),
				inputs = sim.inputs.duplicate()
			}
		)
		receipts.append(pending_receipt.duplicate(true))
		if sim.tick % 30 == 0:
			checkpoints.append({tick = sim.tick, checkpoint = sim.checkpoint()})
			print("SHARED_CAPACITY_PROGRESS speed=", speed, " tick=", sim.tick)
		if sim.tick == 178:
			replay_checkpoint = sim.checkpoint()
	var final_checkpoint: Dictionary = sim.checkpoint()
	var final_state := _combined(sim)
	var balance: float = _mechanical(sim) + sim.aux[0] + sim.aux[1] - sim.aux[2] - initial_energy
	check(
		"whole original tape accepts180 ticks",
		sim.tick == 180 and sim.fault_reason.is_empty(),
		sim.fault_reason
	)
	check(
		"every accepted tick retains full receipt/frame",
		receipts.size() == sim.tick and frames.size() == sim.tick
	)
	check("original complete-tape mechanical balance", absf(balance) < 2e-4, str(balance))
	check("original drop rebounds naturally", rebounded)
	var types: Array = []
	for batch: Dictionary in batches:
		for event: Dictionary in batch.events:
			types.append(event.type)
	check(
		"physical touchdown and last-contact unload observed",
		types.has("composition_touchdown") and types.has("composition_last_contact_unloaded")
	)
	var replay_receipts: Array = []
	var replay_equal := false
	if sim.tick == 180:
		var expected := var_to_bytes(final_checkpoint)
		phase[0] = "checkpoint-replay"
		check(
			"real owner restores source-pinned checkpoint178",
			sim.restore_checkpoint(replay_checkpoint)
		)
		for i in 2:
			pending_receipt.clear()
			sim.step()
			replay_receipts.append(pending_receipt.duplicate(true))
		replay_equal = (
			expected == var_to_bytes(sim.checkpoint())
			and var_to_bytes(receipts.slice(178)) == var_to_bytes(replay_receipts)
		)
		check(
			"real owner checkpoint state and complete receipts continue byte exactly", replay_equal
		)
	var result := {
		speed_mps = speed,
		accepted_ticks = frames.size(),
		target_ticks = 180,
		initial_state = initial,
		final_state = final_state,
		initial_energy_j = initial_energy,
		mechanical_balance_j = balance,
		maximum_compression_m = maximum_compression,
		rebounded = rebounded,
		fault = sim.fault_reason,
		dt = sim.dt(),
		quality = quality,
		options = _options(),
		source = _source(),
		capacity_binding = capacity_context.identity,
		layout_identity = sim.model.state_layout_identity,
		frames = frames,
		integration_receipts = receipts,
		checkpoints = checkpoints,
		event_batches = batches,
		final_checkpoint = final_checkpoint,
		replay_checkpoint178 = replay_checkpoint,
		replay_receipts = replay_receipts,
		replay_byte_equal = replay_equal,
		elapsed_ms = Time.get_ticks_msec() - started
	}
	var stem := "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/full-" + str(speed)
	var bytes := var_to_bytes(result)
	check("retained tape is bounded below64MiB", bytes.size() < 64 * 1024 * 1024)
	var file := FileAccess.open(stem + ".bin", FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	file = FileAccess.open(stem + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t", true, true))
	file.close()
	print(
		"SHARED_CAPACITY_FINAL speed=",
		speed,
		" accepted=",
		frames.size(),
		" balance_j=",
		balance,
		" replay_equal=",
		replay_equal,
		" retained_bytes=",
		bytes.size()
	)
	sim.free()
