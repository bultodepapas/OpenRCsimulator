## AFC-00-R1: complete callback timing and bitwise trace fingerprints.
## Production manager, agent, session and Simulation methods run unchanged. The probe
## wraps manager signal callbacks and delegates agent methods through timed proxies.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const WARMUP_TICKS := 240
const MEASURED_TICKS := 2400
const TOTAL_TICKS := WARMUP_TICKS + MEASURED_TICKS
const COUNTS := [0, 1, 2, 3]

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
		var row: Dictionary = _run_case(count_value, field_result.field, collision.world, lake.lake)
		rows.append(row)
		complete = complete and bool(row.get("complete", false))
	var report := {
		format = "openrc-companions-performance v1",
		complete = complete,
		engine = Engine.get_version_info().string,
		processor = OS.get_processor_name(),
		physics_hz = 240,
		warmup_ticks = WARMUP_TICKS,
		measured_ticks = MEASURED_TICKS,
		cases = rows,
		source_sha256 = _source_hashes(),
		scope = "Headless player + production manager/agents/sessions with the Club collision inventory and lake context. Rendering, audio and real-time pacing are excluded. Callback buckets are exclusive and sum to complete player/session callback time. Per-case state and command hashes cover every measured accepted tick.",
		note = "Local shared-host software timing, not target-hardware qualification, rendered-frame pacing, 60 fps evidence, or physical validation. Timed agent proxies and callback wrappers add small measurement overhead; production method bodies and call ordering are unchanged."
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	print("AFC PERFORMANCE PROFILE COMPLETE")
	quit(0 if complete else 1)


func _run_case(count: int, field: Dictionary, collision_world: Dictionary, lake: Dictionary) -> Dictionary:
	_observation_calls_measured = 0
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(field) or not player.set_collision_world(collision_world) or not player.set_lake_context(lake):
		player.free()
		return {count = count, complete = false, failure = "Player environment setup failed."}
	player.reset()

	_fleet = Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = count > 0
	config.count = count
	config.seed = 20261020
	var prepared: Dictionary = _fleet.configure(player, field, "club_field", config, false, false)
	if not prepared.ok:
		_fleet.free()
		player.free()
		return {count = count, complete = false, failure = str(prepared.errors)}

	var original_agents: Array[Node] = []
	var timed_agents: Array[Node] = []
	for raw_agent: Node in _fleet.agents:
		original_agents.append(raw_agent)
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
		complete = failure.is_empty() and finished_total == TOTAL_TICKS and finished_measured == MEASURED_TICKS,
		failure = failure,
		warmup_ticks = WARMUP_TICKS,
		measured_ticks = finished_measured,
		finished_total_ticks = finished_total,
		manager_accepted_ticks = manager_accepted_ticks,
		manager_observation_batches = manager_observation_batches,
		observation_calls_measured = _observation_calls_measured,
		profile_identity = profile_identity,
		seed = 20261020,
		weather = "production default calm configuration",
		callback_buckets = distributions,
		measurement_envelope = measurement,
		trace_fingerprints = hash_report
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
		return {samples = 0, mean_usec = 0.0, p50_usec = 0, p95_usec = 0, max_usec = 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value: int in sorted:
		sum += float(value)
	var p50_index := mini(sorted.size() - 1, ceili(float(sorted.size()) * 0.50) - 1)
	var p95_index := mini(sorted.size() - 1, ceili(float(sorted.size()) * 0.95) - 1)
	return {samples = sorted.size(), mean_usec = sum / float(sorted.size()),
		p50_usec = sorted[p50_index], p95_usec = sorted[p95_index], max_usec = sorted[-1]}


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
		"app/ai/companions/config.gd": "res://ai/companions/config.gd",
		"app/ai/companions/manager.gd": "res://ai/companions/manager.gd",
		"app/ai/companions/agent.gd": "res://ai/companions/agent.gd",
		"app/ai/companions/pilot.gd": "res://ai/companions/pilot.gd",
		"app/ai/companions/profile_loader.gd": "res://ai/companions/profile_loader.gd",
		"app/scenery/collision_setup.gd": "res://scenery/collision_setup.gd",
		"app/scenery/collision_world.gd": "res://scenery/collision_world.gd",
		"app/sim/environment.gd": "res://sim/environment.gd",
		"app/data/aircraft/jensen_ugly_stik_60.json": "res://data/aircraft/jensen_ugly_stik_60.json",
		"app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json": "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
		"app/data/ai/companions/fields/club-default.json": "res://data/ai/companions/fields/club-default.json",
		"app/data/fields/default.json": "res://data/fields/default.json",
		"app/data/fields/lake.json": "res://data/fields/lake.json"
	}
	var hashes: Dictionary = {}
	for label: String in paths:
		var path: String = paths[label]
		hashes[label] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return hashes
