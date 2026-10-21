## AFC-00-R3: paired complete-callback timing and bitwise trace fingerprints.
## Both branches run through the unchanged production manager, agent, session and
## Simulation methods. The candidate controller is injected only after fixture setup.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const ProductionPilot := preload("res://ai/companions/pilot.gd")
const CandidatePilot := preload("res://../research/ai-companions/performance/reachable_clear_candidate.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const WARMUP_TICKS := 240
const MEASURED_TICKS := 2400
const TOTAL_TICKS := WARMUP_TICKS + MEASURED_TICKS
const COUNTS := [0, 1, 2, 3]
const EXPECTED_PRODUCTION_SHA256 := "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
const EXPECTED_CANDIDATE_SHA256 := "3842cbdba80c7bef5041844132a811bfd27c1cb68de759ce06f39bb97ca1f024"
const EXPECTED_BASE_SHA256 := "1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c"

class TimedAgent extends Node:
	var target: Node
	var reporter: Object
	var session: Node:
		get:
			return target.session
	var failure: String:
		get:
			return target.failure
		set(value):
			target.failure = value

	func observation() -> Dictionary:
		reporter.record_observation_call()
		var started := Time.get_ticks_usec()
		var result: Dictionary = target.observation()
		reporter.record_bucket("ai_observation_usec", Time.get_ticks_usec() - started)
		return result

	func needs_command(tick: int) -> bool:
		return target.needs_command(tick)

	func prepare(snapshot: Dictionary, tick: int, traffic: Array) -> bool:
		var started := Time.get_ticks_usec()
		var result: bool = target.prepare(snapshot, tick, traffic)
		reporter.record_bucket("ai_plan_prepare_usec", Time.get_ticks_usec() - started)
		return result

	func advance() -> bool:
		var started := Time.get_ticks_usec()
		var result: bool = target.advance()
		reporter.record_bucket("ai_stepping_usec", Time.get_ticks_usec() - started)
		return result


var _fleet: Node
var _manager_before_usec := 0
var _manager_after_usec := 0
var _counting_measurement := false
var _observation_calls_measured := 0
var _active_buckets: Dictionary = {}


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--parse-only"):
		print("AFC CALLBACK TIMING PROBE PARSED")
		quit(0)
		return
	if not arguments.has("--measure"):
		printerr("Refusing to run timed cases without explicit --measure.")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		printerr("Supply --out=<new JSON file>.")
		quit(2)
		return

	var source_before := _source_hashes()
	var pilot_sha: String = str(source_before.get("app/ai/companions/pilot.gd", ""))
	var base_sha: String = str(source_before.get("app/ai/companions/circuit_controller.gd", ""))
	var candidate_sha: String = str(source_before.get("research/ai-companions/performance/reachable_clear_candidate.gd", ""))
	if pilot_sha != EXPECTED_PRODUCTION_SHA256 or base_sha != EXPECTED_BASE_SHA256 \
			or candidate_sha != EXPECTED_CANDIDATE_SHA256:
		printerr("Pinned controller source identity mismatch.")
		quit(1)
		return
	var physics_hz := int(Engine.physics_ticks_per_second)
	if physics_hz != 240:
		printerr("Expected the unchanged 240 Hz physics frequency, found %d." % physics_hz)
		quit(1)
		return
	var field_result: Dictionary = FieldLoader.load_from()
	var collision: Dictionary = CollisionSetup.build(field_result.field) if field_result.ok else {}
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.ok or not collision.get("ok", false) or not lake.ok:
		printerr("Field/collision/lake fixture failed.")
		quit(1)
		return

	var rows: Array = []
	var complete := true
	for count_value: int in COUNTS:
		var branch_order: Array[String] = ["production", "candidate"] if count_value % 2 == 0 else ["candidate", "production"]
		var branches: Dictionary = {}
		for branch: String in branch_order:
			branches[branch] = _run_case(count_value, field_result.field, collision.world, lake.lake,
				branch == "candidate")
		var row := _compare_pair(count_value, branch_order, branches)
		rows.append(row)
		complete = complete and bool(row.get("complete", false))
	var source_after := _source_hashes()
	var source_unchanged: bool = var_to_bytes(source_before) == var_to_bytes(source_after)
	complete = complete and source_unchanged
	var report := {
		format = "openrc-afc-reachable-clear-callback-timing v1",
		complete = complete,
		engine = Engine.get_version_info().string,
		processor = OS.get_processor_name(),
		physics_hz = physics_hz,
		warmup_ticks = WARMUP_TICKS,
		measured_ticks = MEASURED_TICKS,
		cases = rows,
		count_order = COUNTS,
		variant_order_by_count = {"even_count_production_then_candidate": true,
			"odd_count_candidate_then_production": true},
		source_identity = {
			"production_controller_sha256": pilot_sha,
			"candidate_controller_sha256": candidate_sha,
			"production_base_sha256": base_sha,
			"manager_profile_controller_sha256": EXPECTED_PRODUCTION_SHA256,
			"source_sha256_before": source_before,
			"source_sha256_after": source_after,
			"all_pinned_source_bytes_unchanged": source_unchanged,
		},
		fixture = {
			"aircraft_id": Catalog.DEFAULT_ID,
			"field": "default Club field",
			"collision_inventory": "CollisionSetup.build(field), unchanged production scenery data",
			"lake": "LakeLoader.DEFAULT_PATH",
			"seed": 20261020,
			"weather": "production default calm configuration",
			"physics_frequency_is_read_only": true,
			"renders_audio_realtime_pacing": false,
		},
		percentile_method = "nearest rank: sorted[ceil(sample_count * p) - 1]",
		scope = "Paired headless software timing of complete player/session callbacks and exclusive production manager/agent buckets. Production and candidate controllers use detached fixtures; accepted profile identity remains production.",
		measurement_overhead = "The probe reports outer profiler envelope and wrapper shim beside complete callback samples. Timed agent proxies and wrapped manager callbacks add diagnostic timer reads inside callback time; these are not subtracted or corrected. No per-score-call counter is enabled during timing.",
		note = "Local shared-host diagnostic only; not target-hardware qualification, rendered-frame pacing, a 60 fps result, or physical validation. Matching per-tick state and command fingerprints are required for a complete comparison."
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	print("AFC CALLBACK TIMING PROFILE COMPLETE")
	quit(0 if complete else 1)


func _run_case(count: int, field: Dictionary, collision_world: Dictionary, lake: Dictionary,
		candidate_override: bool) -> Dictionary:
	_observation_calls_measured = 0
	var case_field: Dictionary = field.duplicate(true)
	var case_collision_world: Dictionary = collision_world.duplicate(true)
	var case_lake: Dictionary = lake.duplicate(true)
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(case_field) or not player.set_collision_world(case_collision_world) or not player.set_lake_context(case_lake):
		player.free()
		return {count = count, complete = false, failure = "Player environment setup failed."}
	player.reset()

	_fleet = Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = count > 0
	config.count = count
	config.seed = 20261020
	var prepared: Dictionary = _fleet.configure(player, case_field, "club_field", config, false, false)
	if not prepared.ok:
		_fleet.free()
		player.free()
		return {count = count, complete = false, failure = str(prepared.errors)}

	var original_agents: Array[Node] = []
	var timed_agents: Array[Node] = []
	for raw_agent: Node in _fleet.agents:
		original_agents.append(raw_agent)
		var initial_pose: Dictionary = raw_agent.pilot.initial_pose()
		var replacement: RefCounted = CandidatePilot.new() if candidate_override else ProductionPilot.new()
		if not replacement.configure(raw_agent.slot_id, count, config.seed,
				raw_agent._accepted_trim, case_field):
			_fleet.free()
			player.free()
			return {count = count, complete = false, failure = "Detached controller configure refused: " + str(replacement.configure_error)}
		if var_to_bytes(initial_pose) != var_to_bytes(replacement.initial_pose()):
			_fleet.free()
			player.free()
			return {count = count, complete = false, failure = "Controller replacement changed the configured launch pose."}
		raw_agent.pilot = replacement
		var proxy := TimedAgent.new()
		proxy.target = raw_agent
		proxy.reporter = self
		proxy.name = raw_agent.name
		timed_agents.append(proxy)
	_fleet.agents = timed_agents

	var before_callable := Callable(_fleet, "_before_step")
	var after_callable := Callable(_fleet, "_after_step")
	var wrapped_before := Callable(self, "_profile_before_step")
	var wrapped_after := Callable(self, "_profile_after_step")
	if player.sim.before_step.is_connected(before_callable):
		player.sim.before_step.disconnect(before_callable)
	if player.sim.stepped.is_connected(after_callable):
		player.sim.stepped.disconnect(after_callable)
	player.sim.before_step.connect(wrapped_before)
	player.sim.stepped.connect(wrapped_after)

	var bucket_names := ["complete_callback_usec", "player_session_guard_usec", "player_solver_usec",
		"ai_observation_usec", "ai_plan_prepare_usec", "ai_stepping_usec", "manager_overhead_usec",
		"manager_before_usec", "manager_after_usec"]
	var samples: Dictionary = {}
	for bucket_name: String in bucket_names:
		samples[bucket_name] = []
	var envelope_samples: Array[int] = []
	var shim_samples: Array[int] = []
	var hashes := _new_hashes(count)
	var failure := ""
	var finished_total := 0
	var finished_measured := 0
	for tick in TOTAL_TICKS:
		_counting_measurement = tick >= WARMUP_TICKS
		_active_buckets = {}
		_manager_before_usec = 0
		_manager_after_usec = 0
		var complete_started := Time.get_ticks_usec()
		var session_started := Time.get_ticks_usec()
		player._physics_process(player.sim.dt())
		var session_usec := Time.get_ticks_usec() - session_started
		var sim_started := Time.get_ticks_usec()
		player.sim._physics_process(player.sim.dt())
		var sim_callback_usec := Time.get_ticks_usec() - sim_started
		var complete_callback_usec := session_usec + sim_callback_usec
		var profiler_envelope_usec := Time.get_ticks_usec() - complete_started
		var profiler_shim_usec := profiler_envelope_usec - complete_callback_usec

		if player.sim.tick != tick + 1 or not player.sim.fault_reason.is_empty() or not player.crash.is_empty():
			failure = "Player stopped at tick %d: %s %s" % [tick, player.sim.fault_reason, str(player.crash)]
			break
		for agent: Node in original_agents:
			if agent.session.sim.tick != tick + 1 or not agent.failure.is_empty() or not agent.session.sim.fault_reason.is_empty() or not agent.session.crash.is_empty():
				failure = "%s stopped at tick %d: %s %s" % [agent.name, tick, agent.failure, str(agent.session.crash)]
				break
		if not failure.is_empty():
			break

		if tick >= WARMUP_TICKS:
			var observation_usec := int(_active_buckets.get("ai_observation_usec", 0))
			var planning_usec := int(_active_buckets.get("ai_plan_prepare_usec", 0))
			var stepping_usec := int(_active_buckets.get("ai_stepping_usec", 0))
			var player_solver_usec := sim_callback_usec - _manager_before_usec - _manager_after_usec
			var manager_overhead_usec := _manager_before_usec + _manager_after_usec - observation_usec - planning_usec - stepping_usec
			if player_solver_usec < 0 or manager_overhead_usec < 0:
				failure = "Exclusive callback attribution became negative at tick %d." % tick
				break
			var complete_parts := session_usec + player_solver_usec + observation_usec + planning_usec + stepping_usec + manager_overhead_usec
			if complete_parts != complete_callback_usec:
				failure = "Exclusive buckets do not sum to complete callback time at tick %d: %d != %d." % [tick, complete_parts, complete_callback_usec]
				break
			_append_sample(samples, "complete_callback_usec", complete_callback_usec)
			envelope_samples.append(profiler_envelope_usec)
			shim_samples.append(profiler_shim_usec)
			_append_sample(samples, "player_session_guard_usec", session_usec)
			_append_sample(samples, "player_solver_usec", player_solver_usec)
			_append_sample(samples, "ai_observation_usec", observation_usec)
			_append_sample(samples, "ai_plan_prepare_usec", planning_usec)
			_append_sample(samples, "ai_stepping_usec", stepping_usec)
			_append_sample(samples, "manager_overhead_usec", manager_overhead_usec)
			_append_sample(samples, "manager_before_usec", _manager_before_usec)
			_append_sample(samples, "manager_after_usec", _manager_after_usec)
			_add_trace_tick(hashes, tick - WARMUP_TICKS, player, original_agents)
			finished_measured += 1
		finished_total += 1

	if player.sim.before_step.is_connected(wrapped_before):
		player.sim.before_step.disconnect(wrapped_before)
	if player.sim.stepped.is_connected(wrapped_after):
		player.sim.stepped.disconnect(wrapped_after)
	_counting_measurement = false
	_fleet.agents = original_agents
	var manager_accepted_ticks := int(_fleet.accepted_ticks)
	var manager_observation_batches := int(_fleet.observation_batches)
	var profile_identity: Dictionary = _fleet.status().get("profile_identity", {})
	var profile_identity_matches: bool = count == 0 or str(profile_identity.get("controller_sha256", "")) == EXPECTED_PRODUCTION_SHA256
	for proxy: Node in timed_agents:
		proxy.free()
	_fleet.free()
	player.free()

	var distributions: Dictionary = {}
	for bucket_name: String in bucket_names:
		distributions[bucket_name.trim_suffix("_usec")] = _summarize(samples[bucket_name])
	var measurement: Dictionary = {
		profiler_envelope = _summarize(envelope_samples),
		wrapper_shim = _summarize(shim_samples)
	}
	var hash_report: Dictionary = {}
	for actor_id: String in hashes.keys():
		var actor_hashes: Dictionary = hashes[actor_id]
		hash_report[actor_id] = {
			state_sha256 = actor_hashes.state.finish().hex_encode(),
			command_sha256 = actor_hashes.commands.finish().hex_encode()
		}
	return {
		count = count,
		variant = "candidate" if candidate_override else "production",
		complete = failure.is_empty() and finished_total == TOTAL_TICKS and finished_measured == MEASURED_TICKS,
		failure = failure,
		warmup_ticks = WARMUP_TICKS,
		measured_ticks = finished_measured,
		finished_total_ticks = finished_total,
		manager_accepted_ticks = manager_accepted_ticks,
		manager_observation_batches = manager_observation_batches,
		observation_calls_measured = _observation_calls_measured,
		profile_identity = profile_identity,
		profile_identity_matches_pinned_production = profile_identity_matches,
		controller_override_sha256 = EXPECTED_CANDIDATE_SHA256 if candidate_override else EXPECTED_PRODUCTION_SHA256,
		detached_controller_launch_poses_match = true,
		seed = 20261020,
		weather = "production default calm configuration",
		callback_buckets = distributions,
		measurement_envelope = measurement,
		trace_fingerprints = hash_report
	}


func _compare_pair(count: int, branch_order: Array[String], branches: Dictionary) -> Dictionary:
	var production: Dictionary = branches.get("production", {})
	var candidate: Dictionary = branches.get("candidate", {})
	var production_hashes: Dictionary = production.get("trace_fingerprints", {})
	var candidate_hashes: Dictionary = candidate.get("trace_fingerprints", {})
	var actor_comparisons: Dictionary = {}
	var all_hashes_match: bool = production_hashes.size() == candidate_hashes.size()
	for actor_id: String in production_hashes:
		var before: Dictionary = production_hashes[actor_id]
		var after: Dictionary = candidate_hashes.get(actor_id, {})
		var state_match: bool = before.get("state_sha256", "") == after.get("state_sha256", "")
		var command_match: bool = before.get("command_sha256", "") == after.get("command_sha256", "")
		actor_comparisons[actor_id] = {
			state_match = state_match,
			command_match = command_match,
			production_state_sha256 = before.get("state_sha256", ""),
			candidate_state_sha256 = after.get("state_sha256", ""),
			production_command_sha256 = before.get("command_sha256", ""),
			candidate_command_sha256 = after.get("command_sha256", ""),
		}
		all_hashes_match = all_hashes_match and state_match and command_match
	var profile_identity_equal: bool = var_to_bytes(production.get("profile_identity", {})) == var_to_bytes(candidate.get("profile_identity", {}))
	var bucket_comparisons: Dictionary = {}
	var production_buckets: Dictionary = production.get("callback_buckets", {})
	var candidate_buckets: Dictionary = candidate.get("callback_buckets", {})
	for bucket_name: String in production_buckets:
		var production_distribution: Dictionary = production_buckets[bucket_name]
		var candidate_distribution: Dictionary = candidate_buckets.get(bucket_name, {})
		bucket_comparisons[bucket_name] = _compare_distributions(production_distribution, candidate_distribution)
	var measurement_comparisons: Dictionary = {}
	var production_measurement: Dictionary = production.get("measurement_envelope", {})
	var candidate_measurement: Dictionary = candidate.get("measurement_envelope", {})
	for measurement_name: String in production_measurement:
		measurement_comparisons[measurement_name] = _compare_distributions(
			production_measurement[measurement_name], candidate_measurement.get(measurement_name, {}))
	var complete: bool = bool(production.get("complete", false)) and bool(candidate.get("complete", false)) \
			and bool(production.get("profile_identity_matches_pinned_production", false)) \
			and bool(candidate.get("profile_identity_matches_pinned_production", false)) \
			and profile_identity_equal and all_hashes_match
	return {
		count = count,
		branch_order = branch_order,
		complete = complete,
		production = production,
		candidate = candidate,
		profile_identity_equal = profile_identity_equal,
		actor_fingerprint_comparisons = actor_comparisons,
		all_actor_state_and_command_fingerprints_match = all_hashes_match,
		callback_bucket_comparisons = bucket_comparisons,
		measurement_envelope_comparisons = measurement_comparisons,
	}


func _compare_distributions(production: Dictionary, candidate: Dictionary) -> Dictionary:
	var deltas: Dictionary = {}
	for statistic: String in ["mean_usec", "p50_usec", "p95_usec", "p99_usec"]:
		deltas[statistic] = float(candidate.get(statistic, 0.0)) - float(production.get(statistic, 0.0))
	return {
		production = production,
		candidate = candidate,
		delta_candidate_minus_production_usec = deltas,
	}


func record_bucket(bucket_name: String, usec: int) -> void:
	_active_buckets[bucket_name] = int(_active_buckets.get(bucket_name, 0)) + usec


func record_observation_call() -> void:
	if _counting_measurement:
		_observation_calls_measured += 1


func _profile_before_step(tick: int) -> void:
	var started := Time.get_ticks_usec()
	_fleet._before_step(tick)
	_manager_before_usec = Time.get_ticks_usec() - started


func _profile_after_step(tick: int, sim_time: float, state: PackedFloat64Array,
		loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var started := Time.get_ticks_usec()
	_fleet._after_step(tick, sim_time, state, loads, inputs, aux)
	_manager_after_usec = Time.get_ticks_usec() - started


func _append_sample(samples: Dictionary, key: String, value: int) -> void:
	var target: Array = samples[key]
	target.append(value)


func _summarize(values: Array) -> Dictionary:
	if values.is_empty():
		return {samples = 0, mean_usec = 0.0, p50_usec = 0, p95_usec = 0, p99_usec = 0, max_usec = 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value: int in sorted:
		sum += float(value)
	var p50_index := mini(sorted.size() - 1, ceili(float(sorted.size()) * 0.50) - 1)
	var p95_index := mini(sorted.size() - 1, ceili(float(sorted.size()) * 0.95) - 1)
	var p99_index := mini(sorted.size() - 1, ceili(float(sorted.size()) * 0.99) - 1)
	return {samples = sorted.size(), mean_usec = sum / float(sorted.size()),
		p50_usec = sorted[p50_index], p95_usec = sorted[p95_index],
		p99_usec = sorted[p99_index], max_usec = sorted[-1]}


func _new_hashes(count: int) -> Dictionary:
	var result: Dictionary = {}
	var actor_ids: Array[String] = ["player"]
	for slot in count:
		actor_ids.append("companion-%d" % (slot + 1))
	for actor_id: String in actor_ids:
		var state_hash := HashingContext.new()
		var command_hash := HashingContext.new()
		state_hash.start(HashingContext.HASH_SHA256)
		command_hash.start(HashingContext.HASH_SHA256)
		state_hash.update(("state:" + actor_id + "\n").to_utf8_buffer())
		command_hash.update(("command:" + actor_id + "\n").to_utf8_buffer())
		result[actor_id] = {state = state_hash, commands = command_hash}
	return result


func _add_trace_tick(hashes: Dictionary, measured_tick: int, player: Node, agents: Array[Node]) -> void:
	_update_trace(hashes.player, measured_tick, player.sim.state, player.sim.previous,
		player.sim.aux, player.sim.continuous, player.sim.modes, player.sim.last_loads,
		player.sim.inputs, PackedFloat64Array())
	for agent: Node in agents:
		var command: Dictionary = agent._last_command
		var packet := PackedFloat64Array([
			float(command.get("roll", 0.0)), float(command.get("pitch", 0.0)),
			float(command.get("yaw", 0.0)), float(command.get("throttle", 0.0))])
		var actor_id := "companion-%d" % (int(agent.slot_id) + 1)
		_update_trace(hashes[actor_id], measured_tick, agent.session.sim.state,
			agent.session.sim.previous, agent.session.sim.aux, agent.session.sim.continuous,
			agent.session.sim.modes, agent.session.sim.last_loads, agent.session.sim.inputs, packet)


func _update_trace(actor_hashes: Dictionary, measured_tick: int, state: PackedFloat64Array,
		previous: PackedFloat64Array, aux: PackedFloat64Array, continuous: PackedFloat64Array,
		modes: PackedInt64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array,
		command_packet: PackedFloat64Array) -> void:
	var tick_bytes := PackedInt64Array([measured_tick]).to_byte_array()
	var state_hash: HashingContext = actor_hashes.state
	_hash_bytes(state_hash, tick_bytes)
	_hash_bytes(state_hash, state.to_byte_array())
	_hash_bytes(state_hash, previous.to_byte_array())
	_hash_bytes(state_hash, aux.to_byte_array())
	_hash_bytes(state_hash, continuous.to_byte_array())
	_hash_bytes(state_hash, modes.to_byte_array())
	_hash_bytes(state_hash, loads.to_byte_array())
	var command_hash: HashingContext = actor_hashes.commands
	_hash_bytes(command_hash, tick_bytes)
	_hash_bytes(command_hash, inputs.to_byte_array())
	_hash_bytes(command_hash, command_packet.to_byte_array())


func _hash_bytes(context: HashingContext, value: PackedByteArray) -> void:
	if not value.is_empty():
		context.update(value)


func _source_hashes() -> Dictionary:
	var paths := {
		"app/project.godot": "res://project.godot",
		"app/sim/simulation.gd": "res://sim/simulation.gd",
		"app/sim/flight_session.gd": "res://sim/flight_session.gd",
		"app/sim/aircraft_contact_events.gd": "res://sim/aircraft_contact_events.gd",
		"app/sim/scenery_collision.gd": "res://sim/scenery_collision.gd",
		"app/sim/scenery_damage.gd": "res://sim/scenery_damage.gd",
		"app/sim/lake_collision.gd": "res://sim/lake_collision.gd",
		"app/physics/rigid_body.gd": "res://physics/rigid_body.gd",
		"app/physics/math3d.gd": "res://physics/math3d.gd",
		"app/physics/dynamics.gd": "res://physics/dynamics.gd",
		"app/physics/integrator.gd": "res://physics/integrator.gd",
		"app/physics/aircraft_data.gd": "res://physics/aircraft_data.gd",
		"app/physics/aircraft_modules.gd": "res://physics/aircraft_modules.gd",
		"app/physics/aircraft_contract.gd": "res://physics/aircraft_contract.gd",
		"app/physics/aircraft_contact_contract.gd": "res://physics/aircraft_contact_contract.gd",
		"app/physics/ground_surfaces.gd": "res://physics/ground_surfaces.gd",
		"app/physics/hull_contact.gd": "res://physics/hull_contact.gd",
		"app/physics/lake_surface.gd": "res://physics/lake_surface.gd",
		"app/physics/cruise_trim.gd": "res://physics/cruise_trim.gd",
		"app/data/field_loader.gd": "res://data/field_loader.gd",
		"app/data/lake_loader.gd": "res://data/lake_loader.gd",
		"app/app_state/aircraft_catalog.gd": "res://app_state/aircraft_catalog.gd",
		"app/ai/companions/config.gd": "res://ai/companions/config.gd",
		"app/ai/companions/manager.gd": "res://ai/companions/manager.gd",
		"app/ai/companions/agent.gd": "res://ai/companions/agent.gd",
		"app/ai/companions/pilot.gd": "res://ai/companions/pilot.gd",
		"app/ai/companions/circuit_controller.gd": "res://ai/companions/circuit_controller.gd",
		"app/ai/companions/profile_loader.gd": "res://ai/companions/profile_loader.gd",
		"app/scenery/collision_setup.gd": "res://scenery/collision_setup.gd",
		"app/scenery/collision_world.gd": "res://scenery/collision_world.gd",
		"app/sim/environment.gd": "res://sim/environment.gd",
		"app/aircraft/model_registry.gd": "res://aircraft/model_registry.gd",
		"app/aircraft/ugly_stik_model.gd": "res://aircraft/ugly_stik_model.gd",
		"app/data/aircraft/jensen_ugly_stik_60.json": "res://data/aircraft/jensen_ugly_stik_60.json",
		"app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json": "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
		"app/data/ai/companions/fields/club-default.json": "res://data/ai/companions/fields/club-default.json",
		"app/data/fields/default.json": "res://data/fields/default.json",
		"app/data/fields/lake.json": "res://data/fields/lake.json",
		"app/data/fields/mountains.json": "res://data/fields/mountains.json",
		"research/ai-companions/performance/reachable_clear_candidate.gd": "res://../research/ai-companions/performance/reachable_clear_candidate.gd",
		"research/ai-companions/performance/callback_timing_probe.gd": "res://../research/ai-companions/performance/callback_timing_probe.gd"
	}
	var hashes: Dictionary = {}
	for label: String in paths:
		var path: String = paths[label]
		hashes[label] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return hashes
