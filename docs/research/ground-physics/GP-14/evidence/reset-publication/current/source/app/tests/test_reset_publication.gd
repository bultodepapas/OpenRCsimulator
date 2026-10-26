## Accepted reset publication and preservation of actual Session/Log/Fleet consumers.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Fleet := preload("res://ai/companions/fleet_record.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Incident := preload("res://economy/incident.gd")
const LegacySim := preload("res://sim/simulation.gd")
const Statistics := preload("res://statistics/service.gd")
# Captured before production changes with the engine/version and fixture state
# in checks/default-before. A fixed byte sentinel survives this test's promotion.
const DEFAULT_RESET_CHECKPOINT_SHA256 := "f002aed32d5d5281df23dbdb8c0e14615536bbff68fd895c7881fbb919b71d0f"
var checks := 0
var failed := 0
var field: Dictionary
var spot: Dictionary
var output := ""

class RejectingFlight extends "res://sim/flight_session.gd":
	var refuse := false
	func _wheel_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		return {} if refuse else super._wheel_evaluate(s, x, t)

class Agent extends Node:
	var failure := ""
	var slot_id := 1
	var session: Node

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	call_deferred("_run")

func body(north := 0.0) -> PackedFloat64Array:
	return PackedFloat64Array([north, 0.0, -30.0, 10.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

func new_sim(endpoint := true) -> Node:
	var sim := Sim.new()
	if endpoint:
		sim.model.aux_size = sim.aux.size()
		sim.model.continuous_size = 0
		sim.model.modes_size = 0
		sim.model.state_layout_identity = "reset-publication-fixture-v1"
	check("generic initial reset", sim.reset(body()))
	return sim

func new_flight(endpoint := false) -> Node:
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup()
	check("actual field installed", f.set_field(field))
	if endpoint:
		f.sim.model.aux_size = f.sim.aux.size()
		f.sim.model.continuous_size = f.sim.continuous.size()
		f.sim.model.modes_size = f.sim.modes.size()
		f.sim.model.state_layout_identity = "actual-session-reset-publication-v1"
		check("actual endpoint reset", f.sim.reset(f.sim.state.duplicate()))
	return f

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	field = Field.load_from().field
	spot = GroundStart.threshold(field)
	output = ProjectSettings.globalize_path("res://../tmp/reset-publication-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_generic()
	_rejection()
	_prepare_owner_reentry()
	_commit_validation_owner_reentry()
	_session_and_log()
	_session_faults()
	_public_helpers()
	_unavailable_closing_checkpoint()
	_fleet()
	print("Reset publication: %d checks, %d failed; %s" % [checks, failed, output])
	quit(1 if failed else 0)

func _generic() -> void:
	var previous := LegacySim.new()
	var current := new_sim(false)
	check("production default reset sentinel prepares", previous.reset(body(9.0)) and current.reset(body(9.0)))
	check("empty-hook default unchanged from production kernel", var_to_bytes(previous.checkpoint()) == var_to_bytes(current.checkpoint()))
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(current.checkpoint()))
	check("legacy empty-hook frozen byte sentinel", digest.finish().hex_encode() == DEFAULT_RESET_CHECKPOINT_SHA256)
	previous.free()
	current.free()
	for endpoint: bool in [false, true]:
		var plain := new_sim(endpoint)
		var hook := new_sim(endpoint)
		var order := []
		hook.stepped.connect(func(_k, _t, _s, _l, _i, _a): order.append("sample"))
		check("plain reset candidate", plain.commit_prepared_reset(plain.prepare_reset(body(7.0))))
		check("hook commits", hook.commit_prepared_reset(hook.prepare_reset(body(7.0)), func():
			check("physical install precedes hook", hook.state[0] == 7.0 and hook.tick == 0)
			order.append("hook")))
		check("empty/noop hook physical checkpoint bytes identical", var_to_bytes(plain.checkpoint()) == var_to_bytes(hook.checkpoint()))
		check("hook precedes sample exactly once", order == ["hook", "sample"])
		plain.free()
		hook.free()
	var sim := new_sim()
	var prepared: Dictionary = sim.prepare_reset(body(4.0))
	sim.mass = 3.0
	var called := [false]
	check("changed context rejects before hook", not sim.commit_prepared_reset(prepared, func(): called[0] = true) and not called[0] and sim.state[0] == 0.0 and sim.mass == 3.0)
	sim.free()
	var freed := Node.new()
	var freed_callback := Callable(freed, "get_instance_id")
	freed.free()
	var invalid_callbacks := [Callable(self, "missing_reset_hook"), freed_callback, func(_required): pass]
	for callback: Callable in invalid_callbacks:
		sim = new_sim()
		var before := var_to_bytes(sim.checkpoint())
		check("invalid/freed/wrong arity hook refused before commit", not sim.commit_prepared_reset(sim.prepare_reset(body(8.0)), callback)
			and before == var_to_bytes(sim.checkpoint()))
		sim.free()
	for mutation: String in ["mass", "array", "model", "step", "reset", "prepare", "restore", "set_model"]:
		sim = new_sim()
		var target := body(11.0)
		var candidate: Dictionary = sim.prepare_reset(target)
		var original_model: RefCounted = sim.model
		var before: Dictionary = sim.checkpoint()
		var core := sim
		var mutation_callback := func():
			core.set_paused(true) # The final legal pause survives every restore.
			match mutation:
				"mass": core.mass = 0.0
				"array": core.state[0] = 99.0
				"model": core.model.input_size = 8
				"step": core.step()
				"reset": core.reset(body(100.0))
				"prepare": core.prepare_reset(body())
				"restore": core.restore_checkpoint(before)
				"set_model": core.set_model(preload("res://sim/vehicle_model.gd").new())
		check("observer mutation keeps accepted commit " + mutation, sim.commit_prepared_reset(candidate, mutation_callback))
		check("committed protected frame restored/fault paused " + mutation, sim.state.to_byte_array() == target.to_byte_array()
			and sim.mass == 1.0 and sim.model == original_model and sim.model.input_size == 4
			and sim.paused and not sim.fault_reason.is_empty() and not sim.reset_observer_fault.is_empty())
		sim.free()

func _rejection() -> void:
	var f := RejectingFlight.new()
	f.input_enabled = false
	f.setup()
	check("rejecting field", f.set_field(field))
	for i: int in 3: f.sim.step()
	f.engine_running = false
	var writer := Log.new(f)
	check("rejected candidate recorder starts", writer.start(output.path_join("rejected.orfl")) == OK)
	var signals := [0, 0]
	f.resetting.connect(func(): signals[0] += 1)
	f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): signals[1] += 1)
	var before := var_to_bytes([f.checkpoint(), f.commands, f.engine_running])
	var generation: int = f.statistics_generation
	f.refuse = true
	var result: Dictionary = f.try_runway_start(spot.north, spot.east, spot.heading)
	check("rejected candidate no publication/close/generation", not result.ok and signals == [0, 0] and writer.recording and generation == f.statistics_generation)
	check("rejected candidate full owner context restored", before == var_to_bytes([f.checkpoint(), f.commands, f.engine_running]))
	check("closing context absent on rejection", f.reset_closing_context().is_empty())
	writer.stop("rejection test cleanup")
	f.free()

func _session_and_log() -> void:
	var f := new_flight()
	var writer := Log.new(f)
	var incident := Incident.new()
	incident.archive_path = output.path_join("old-incident.json")
	incident.begin("jensen-das-ugly-stik-60", str(f.aircraft.input_identity.sha256))
	# Exercise actual Incident archive/rebegin consumers with an explicitly
	# terminal observer fixture; this does not assert a physical aircraft crash.
	incident.observe(f.contact_events(), f.contact_contract(), true)
	incident.evaluate_pending()
	var old_incident := var_to_bytes(incident.report)
	check("old incident fixture has stored assessment", not incident.report.is_empty())
	var archived := {}
	# Main's hold listener precedes the recorder listener, as in the real shell.
	var closing := {}
	var order := []
	f.resetting.connect(func():
		closing.merge(f.reset_closing_context(), true)
		var detached: Dictionary = f.reset_closing_context()
		detached.checkpoint.clear()
		check("closing context is deep detached", not f.reset_closing_context().checkpoint.is_empty())
		archived.merge(incident.archive(), true)
		incident.begin("jensen-das-ugly-stik-60", str(f.aircraft.input_identity.sha256))
		f.hold("companions-reset")
		order.append("resetting"))
	var path := output.path_join("accepted.orfl")
	check("accepted recorder starts", writer.start(path) == OK)
	for i: int in 6: f.sim.step()
	var old_checkpoint: Dictionary = f.checkpoint()
	var old_tick: int = f.sim.tick
	f.sim.stepped.connect(func(k, _t, _s, _l, _i, _a):
		if k == 0: order.append("sample"))
	var accepted: Dictionary = f.try_runway_start(spot.north, spot.east, spot.heading)
	check("legitimate hold accepts ready reset paused", accepted.ok and accepted.status == "converged" and f.sim.tick == 0 and f.sim.paused and f.sim.fault_reason.is_empty())
	check("ordinary result gains no fault-only fields", not accepted.has("committed") and not accepted.has("ready") and not accepted.has("observer_fault"))
	check("resetting before sample0; closing context scoped", order == ["resetting", "sample"] and f.reset_closing_context().is_empty())
	check("old checkpoint captured before staging", closing.tick == old_tick and closing.checkpoint_available and var_to_bytes(closing.checkpoint) == var_to_bytes(old_checkpoint))
	check("actual old accident archive kept; new ledger empty", old_incident == var_to_bytes(archived)
		and FileAccess.file_exists(incident.archive_path) and incident.report.is_empty() and incident.journal.is_empty())
	var inspected: Dictionary = Reader.inspect(path)
	check("actual log closes complete", not writer.recording and inspected.ok, str(inspected))
	if inspected.ok:
		check("actual footer exact old full checkpoint", var_to_bytes(inspected.footer.checkpoint) == var_to_bytes(old_checkpoint) and inspected.footer.final_tick == old_tick)
		var event_ticks_ok := true
		var saw_pause := false
		for event: Dictionary in inspected.events:
			event_ticks_ok = event_ticks_ok and event.tick == old_tick
			saw_pause = saw_pause or event.kind == "pause"
		check("pause-before-recorder reset uses closing tick", event_ticks_ok and saw_pause)
		_replay(path, inspected)
	check("accepted held session checkpoint valid", not f.checkpoint().is_empty())
	f.free()

func _prepare_owner_reentry() -> void:
	for action: String in ["reset", "runway_wrapper", "field", "hold", "release", "resume"]:
		var f := new_flight(true)
		var preparation := [0]
		f.sim.model.state_validator = func(frame: Dictionary, _context: Dictionary) -> bool:
			# Only the proposed runway pose reaches this branch; reading the old
			# airborne checkpoint remains a valid, non-reentrant observation.
			if frame.body[2] > -1.0:
				preparation[0] += 1
				match action:
					"reset": f.reset()
					"runway_wrapper": f.reset_on_runway(spot.north, spot.east, spot.heading)
					"field": f.set_field(field)
					"hold": f.hold("preparation-must-not-mutate")
					"release": f.release("retained-hold")
					"resume": f.resume()
			return true
		if action == "release": f.hold("retained-hold")
		var writer := Log.new(f)
		check("preparation reentry recorder starts " + action, writer.start(output.path_join("prepare-" + action + ".orfl")) == OK)
		var before := var_to_bytes([f.checkpoint(), f.commands, f.engine_running, f.contact_events(), f.holds])
		var generation: int = f.statistics_generation
		var notifications := [0, 0]
		f.resetting.connect(func(): notifications[0] += 1)
		f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): notifications[1] += 1)
		var result: Dictionary = f.try_runway_start(spot.north, spot.east, spot.heading)
		check("actual validator owner reentry refuses before commit " + action,
			preparation[0] > 0 and not result.ok and str(result.message).contains("reentry"))
		check("preparation owner rollback complete " + action, before == var_to_bytes([f.checkpoint(), f.commands, f.engine_running, f.contact_events(), f.holds]))
		check("preparation reentry no publication/close/generation " + action, writer.recording and notifications == [0, 0]
			and generation == f.statistics_generation and f.sim.fault_reason.is_empty() and f.reset_closing_context().is_empty())
		writer.stop("preparation test cleanup")
		f.free()

func _replay(path: String, inspected: Dictionary) -> void:
	var replay: Dictionary = Reader.prepare_replay(inspected.header)
	check("old recording replay prepares", replay.ok, str(replay))
	if not replay.ok: return
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var observer := Log.new(replay.flight)
	var first := true
	var identical := true
	var count := 0
	while stream.get_position() < stream.get_length():
		var block: Dictionary = Log.read_packet(stream).value
		if block.kind == "footer": break
		for row: Dictionary in block.rows:
			if not first:
				for key in row.intervention: replay.flight.sim.set(key, row.intervention[key].duplicate())
				replay.flight.sim.inputs = row.inputs.duplicate()
				replay.flight.sim.step()
			identical = identical and Reader.disagreement(row, observer._sample({})).is_empty()
			first = false
			count += 1
	check("old recording complete numeric replay", identical and count == inspected.rows and replay.flight.sim.tick == inspected.footer.final_tick)
	stream.close()
	replay.flight.free()

func _commit_validation_owner_reentry() -> void:
	var f := new_flight(true)
	var calls := [0]
	f.sim.model.state_validator = func(frame: Dictionary, _context: Dictionary) -> bool:
		if frame.body[2] > -1.0:
			calls[0] += 1
			if calls[0] == 2: f.reset() # Final commit validation, after prepare passed.
		return true
	var writer := Log.new(f)
	check("commit-only reentry recorder starts", writer.start(output.path_join("commit-validator.orfl")) == OK)
	var before := var_to_bytes([f.checkpoint(), f.commands, f.engine_running, f.contact_events(), f.holds])
	var generation: int = f.statistics_generation
	var notifications := [0, 0]
	f.resetting.connect(func(): notifications[0] += 1)
	f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): notifications[1] += 1)
	var result: Dictionary = f.try_runway_start(spot.north, spot.east, spot.heading)
	check("armed final commit validator refuses owner reentry", calls[0] == 2 and not result.ok)
	check("commit-validation refusal preserves full old owner", before == var_to_bytes([f.checkpoint(), f.commands, f.engine_running, f.contact_events(), f.holds]))
	check("commit-validation refusal publishes/closes nothing", writer.recording and notifications == [0, 0]
		and f.statistics_generation == generation and f.sim.fault_reason.is_empty() and f.reset_closing_context().is_empty())
	writer.stop("commit validator cleanup")
	f.free()

func _session_faults() -> void:
	for action: String in ["mass", "session_reset", "kernel_step", "runway_wrapper"]:
		var f := new_flight(true)
		var statistics := Statistics.new()
		check("in-memory statistics setup", statistics.setup("", false))
		statistics.begin_activity(f, "jensen-das-ugly-stik-60", "Stik reset fixture")
		for i: int in 3: f.sim.step()
		var generation: int = f.statistics_generation
		var events := [0, 0, 0]
		f.start_choice = Flight.START_RUNWAY
		var mutation_callback := func():
			events[0] += 1
			match action:
				"mass": f.sim.mass = 0.0
				"session_reset": f.reset()
				"kernel_step": f.sim.step()
				"runway_wrapper": f.reset_on_runway(spot.north, spot.east, spot.heading)
		f.resetting.connect(mutation_callback)
		f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): events[1] += 1)
		f.statistics_lifecycle.connect(func(_r): events[2] += 1)
		f.reset()
		check("accepted observer fault receipt " + action, f.runway_start_outcome.ok and f.runway_start_outcome.status == "observer_fault"
			and f.runway_start_outcome.committed and not f.runway_start_outcome.ready and not f.start_error.is_empty())
		check("observer fault has one reset/sample/generation " + action, events == [1, 1, 1] and f.sim.tick == 0 and f.statistics_generation == generation + 1)
		check("observer fault retained runway/no fallback " + action, f.sim.mass > 0.0 and f.sim.paused and not f.sim.fault_reason.is_empty()
			and not f.runway_start_outcome.has("fallback") and f._launch_metadata.launch_kind == "runway_threshold")
		check("observer fault context absent after call " + action, f.reset_closing_context().is_empty())
		var q: Dictionary = statistics.query()
		check("no phantom flight or M7 on faulted reset " + action, q.ok and q.started == 0 and q.crashes == 0)
		statistics.close()
		statistics.free()
		f.free()

func _public_helpers() -> void:
	for wrapper: bool in [false, true]:
		for outcome: String in ["accepted", "observer_fault", "rejected"]:
			var f := new_flight(true)
			var before_generation: int = f.statistics_generation
			var lifecycle := [0]
			f.statistics_lifecycle.connect(func(_r): lifecycle[0] += 1)
			if outcome == "observer_fault":
				f.resetting.connect(func(): f.sim.mass = 0.0)
			var north: float = NAN if outcome == "rejected" else spot.north
			var result: Dictionary
			if wrapper:
				result = {ok = f.reset_on_runway(north, spot.east, spot.heading)}
			else:
				result = f.try_runway_start(north, spot.east, spot.heading)
			var commits: int = 0 if outcome == "rejected" and not wrapper else 1
			check("public helper counts physical commit once " + str(wrapper) + "/" + outcome,
				lifecycle[0] == commits and f.statistics_generation == before_generation + commits)
			check("public helper boolean reflects requested runway acceptance " + str(wrapper) + "/" + outcome,
				result.ok == (outcome != "rejected"))
			if outcome == "observer_fault":
				check("public helper never falls back after committed fault " + str(wrapper),
					f.runway_start_outcome.status == "observer_fault" and f.runway_start_outcome.committed
					and not f.runway_start_outcome.ready and not f.runway_start_outcome.has("fallback") and f.sim.paused)
			f.free()

func _unavailable_closing_checkpoint() -> void:
	var f := new_flight()
	f.sim.fault_reason = "software fixture prior fault"
	var closing := {}
	f.resetting.connect(func(): closing.merge(f.reset_closing_context(), true))
	check("reset from prior fault accepts", f.try_runway_start(spot.north, spot.east, spot.heading).ok)
	check("missing old checkpoint explicitly unavailable", not closing.checkpoint_available and closing.checkpoint.is_empty()
		and f.reset_closing_context().is_empty() and not f.checkpoint().is_empty())
	f.free()

func _fleet() -> void:
	var player := new_flight()
	var companion := new_flight()
	var agent := Agent.new()
	agent.session = companion
	var fleet := Fleet.new()
	var agents: Array[Node] = [agent]
	var directory := output.path_join("fleet")
	check("actual bounded fleet capture starts", fleet.start(player, agents, {}, directory, 32).ok)
	for i: int in 4:
		companion.sim.step()
		player.sim.step()
	check("fleet reset accepted", player.try_runway_start(spot.north, spot.east, spot.heading).ok)
	var status: Dictionary = fleet.status()
	check("fleet closes complete at old aligned tick", not status.active and status.complete and status.summary.final_tick == 4, str(status))
	if status.has("summary") and status.summary.has("streams"):
		for s: Dictionary in status.summary.streams:
			check("fleet stream old boundary " + s.id, s.complete and s.session_tick == 4 and Reader.inspect(directory.path_join(s.log)).ok)
	player.free()
	companion.free()
	agent.free()
