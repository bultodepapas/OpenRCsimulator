## AFC-00-R5 follow-up: isolated Agent.observation ABBA timing, without in-loop tracing.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const CandidateAgentScript := preload("res://../research/ai-companions/performance/observation_candidate_agent.gd")

const WARMUP_ROUNDS := 2
const MEASURED_ROUNDS := 240
const CALLS_PER_BLOCK := 1024
const PREPARED_TICKS := 1200
const HARD_TIMEOUT_SECONDS := 90
const EXPECTED_AGENT_SHA256 := "c3846b59fc59b40ffb25af2adf95f74077f150591d027d1a2512f70930a26fb8"
const EXPECTED_PILOT_SHA256 := "3842cbdba80c7bef5041844132a811bfd27c1cb68de759ce06f39bb97ca1f024"
const EXPECTED_MANAGER_SHA256 := "68bdacfb4c840cdb9b509c9c767b63bd818dd4699d268c58cfdecbdded086892"
const EXPECTED_BASE_CONTROLLER_SHA256 := "1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c"
const SOURCE_PATHS := {
	"app/project.godot": "res://project.godot",
	"app/ai/companions/agent.gd": "res://ai/companions/agent.gd",
	"app/ai/companions/manager.gd": "res://ai/companions/manager.gd",
	"app/ai/companions/pilot.gd": "res://ai/companions/pilot.gd",
	"app/ai/companions/circuit_controller.gd": "res://ai/companions/circuit_controller.gd",
	"app/ai/companions/profile_loader.gd": "res://ai/companions/profile_loader.gd",
	"app/ai/companions/config.gd": "res://ai/companions/config.gd",
	"app/sim/flight_session.gd": "res://sim/flight_session.gd",
	"app/sim/simulation.gd": "res://sim/simulation.gd",
	"app/physics/air_data.gd": "res://physics/air_data.gd",
	"app/physics/math3d.gd": "res://physics/math3d.gd",
	"app/physics/rigid_body.gd": "res://physics/rigid_body.gd",
	"app/physics/wind_config.gd": "res://physics/wind_config.gd",
	"app/physics/wind_field.gd": "res://physics/wind_field.gd",
	"app/data/field_loader.gd": "res://data/field_loader.gd",
	"app/data/lake_loader.gd": "res://data/lake_loader.gd",
	"app/scenery/collision_setup.gd": "res://scenery/collision_setup.gd",
	"app/app_state/aircraft_catalog.gd": "res://app_state/aircraft_catalog.gd",
	"app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json": "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
	"app/data/ai/companions/fields/club-default.json": "res://data/ai/companions/fields/club-default.json",
	"app/data/aircraft/jensen_ugly_stik_60.json": "res://data/aircraft/jensen_ugly_stik_60.json",
	"app/data/fields/default.json": "res://data/fields/default.json",
	"app/data/fields/lake.json": "res://data/fields/lake.json",
}


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--parse-only"):
		print("AFC OBSERVATION ABBA TIMING PROBE PARSED")
		quit(0)
		return
	if not arguments.has("--measure"):
		printerr("Supply --measure after the external engine window is released.")
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
	var source_before: Dictionary = _source_hashes()
	if str(source_before.get("app/ai/companions/agent.gd", "")) != EXPECTED_AGENT_SHA256 \
			or str(source_before.get("app/ai/companions/pilot.gd", "")) != EXPECTED_PILOT_SHA256 \
			or str(source_before.get("app/ai/companions/manager.gd", "")) != EXPECTED_MANAGER_SHA256 \
			or str(source_before.get("app/ai/companions/circuit_controller.gd", "")) != EXPECTED_BASE_CONTROLLER_SHA256:
		printerr("Pinned production companion source identity mismatch.")
		quit(1)
		return
	if int(Engine.physics_ticks_per_second) != 240:
		printerr("Expected the unchanged 240 Hz physics frequency.")
		quit(1)
		return
	var fixture := _prepare_fixture()
	if not fixture.get("ok", false):
		printerr("Observation fixture failed: " + str(fixture.get("failure", "unknown")))
		quit(1)
		return
	var baseline: Object = fixture.baseline_agent
	var candidate: Object = fixture.candidate_agent
	var baseline_warmup_usec := 0
	var candidate_warmup_usec := 0
	for _round in WARMUP_ROUNDS:
		baseline_warmup_usec += _run_calls(baseline)
		candidate_warmup_usec += _run_calls(candidate)
		candidate_warmup_usec += _run_calls(candidate)
		baseline_warmup_usec += _run_calls(baseline)
	var timing_started_utc: String = Time.get_datetime_string_from_system(true)
	var measurement_started_usec: int = Time.get_ticks_usec()
	var warmup_parity := _parity_check(baseline, candidate, fixture.session)
	if not bool(warmup_parity.equal) or not bool(warmup_parity.state_unchanged):
		fixture.fleet.free()
		fixture.player.free()
		candidate.free()
		printerr("Warmup changed state or candidate snapshot bytes differ.")
		quit(1)
		return

	var samples: Array[Dictionary] = []
	var parity_checks: Array[Dictionary] = []
	var timed_calls_baseline := 0
	var timed_calls_candidate := 0
	var timed_out := false
	var state_before: String = _fingerprint(_session_state(fixture.session))
	for round_index in MEASURED_ROUNDS:
		# ABBA blocks counter order drift. Timer reads and report appends are outside the call loops.
		var elapsed_a1: int = _time_block(baseline)
		samples.append(_sample(round_index, "A1", "production_agent", elapsed_a1))
		timed_calls_baseline += CALLS_PER_BLOCK
		if _deadline_elapsed(measurement_started_usec):
			timed_out = true
			break
		var elapsed_b1: int = _time_block(candidate)
		samples.append(_sample(round_index, "B1", "candidate_subclass", elapsed_b1))
		timed_calls_candidate += CALLS_PER_BLOCK
		if _deadline_elapsed(measurement_started_usec):
			timed_out = true
			break
		var elapsed_b2: int = _time_block(candidate)
		samples.append(_sample(round_index, "B2", "candidate_subclass", elapsed_b2))
		timed_calls_candidate += CALLS_PER_BLOCK
		if _deadline_elapsed(measurement_started_usec):
			timed_out = true
			break
		var elapsed_a2: int = _time_block(baseline)
		samples.append(_sample(round_index, "A2", "production_agent", elapsed_a2))
		timed_calls_baseline += CALLS_PER_BLOCK
		if _deadline_elapsed(measurement_started_usec):
			timed_out = true
			break
		var parity: Dictionary = _parity_check(baseline, candidate, fixture.session)
		parity.round = round_index
		parity_checks.append(parity)
		if not bool(parity.equal) or not bool(parity.state_unchanged) \
				or str(parity.state_fingerprint) != state_before:
			printerr("Observation output or prepared state changed at ABBA round %d." % round_index)
			fixture.fleet.free()
			fixture.player.free()
			candidate.free()
			quit(1)
			return
		if round_index % 40 == 39:
			print("[observation-abba] finished rounds=%d/%d" % [round_index + 1, MEASURED_ROUNDS])

	var source_after: Dictionary = _source_hashes()
	var sources_unchanged: bool = _same(source_before, source_after)
	var baseline_samples := _variant_samples(samples, "production_agent")
	var candidate_samples := _variant_samples(samples, "candidate_subclass")
	var report := {
		format = "openrc-afc-observation-airdata-abba-timing v1",
		complete = not timed_out and sources_unchanged and timed_calls_baseline == MEASURED_ROUNDS * 2 * CALLS_PER_BLOCK \
			and timed_calls_candidate == MEASURED_ROUNDS * 2 * CALLS_PER_BLOCK \
			and baseline_samples.size() == MEASURED_ROUNDS * 2 \
			and candidate_samples.size() == MEASURED_ROUNDS * 2 \
			and parity_checks.size() == MEASURED_ROUNDS \
			and bool(warmup_parity.equal) and bool(warmup_parity.state_unchanged),
		started_utc = fixture.started_utc,
		timing_started_utc = timing_started_utc,
		finished_utc = Time.get_datetime_string_from_system(true),
		engine = Engine.get_version_info().string,
		processor = OS.get_processor_name(),
		platform = OS.get_name(),
		physics_hz = int(Engine.physics_ticks_per_second),
		warmup_rounds = WARMUP_ROUNDS,
		measured_abba_rounds = MEASURED_ROUNDS,
		prepared_ticks = PREPARED_TICKS,
		hard_timeout_seconds = HARD_TIMEOUT_SECONDS,
		timed_out = timed_out,
		block_calls = CALLS_PER_BLOCK,
		measured_calls_baseline = timed_calls_baseline,
		measured_calls_candidate = timed_calls_candidate,
		timer_reads_per_block = 2,
		instrumentation_inside_timed_loop = false,
		branch_order = "production A1, candidate B1, candidate B2, production A2",
		baseline_summary = _summary(baseline_samples),
		candidate_summary = _summary(candidate_samples),
		raw_block_samples = samples,
		parity_checks_outside_timed_blocks = parity_checks,
		prepared_state_fingerprint = state_before,
		prepared_tick = int(fixture.session.sim.tick),
		prepared_time_s = float(fixture.session.sim.time()),
		prepared_after_gust_delay = float(fixture.session.sim.time()) >= float(WindConfig.GENTLE_PRACTICE.gust_delay_s),
		profile_identity = fixture.profile_identity,
		weather = WindConfig.GENTLE_PRACTICE,
		source_identity = {
			"sha256_before": source_before,
			"sha256_after": source_after,
			"all_pinned_source_bytes_unchanged": sources_unchanged,
		},
		fixture = {
			"aircraft_id": Catalog.DEFAULT_ID,
			"field": "default Club field",
			"requested_companions": 1,
			"actual_companions": fixture.fleet.agents.size(),
			"observation_target_is_production_agent": true,
			"candidate_is_agent_subclass_override": true,
			"both_targets_share_same_session": baseline.get("session") == candidate.get("session"),
		"same_state_and_weather_each_block": true,
		"prepared_ticks": PREPARED_TICKS,
		"prepared_after_gust_delay": float(baseline.get("session").sim.time()) >= float(WindConfig.GENTLE_PRACTICE.gust_delay_s),
			"no_player_or_companion_ticks_during_timing": true,
			"renders_audio_realtime_pacing": false,
		},
		scope = "Observation function cost for this prepared state on this Windows host. It is not manager callback, full flight, render-frame, fleet budget, physical, or target-hardware qualification.",
		method = "Baseline calls the unmodified production Agent.observation(). Candidate is a research subclass overriding only that method and sharing the same accepted session, state, and weather. The real player, manager, and companion are advanced for 1,200 ticks (5 seconds at 240 Hz) before measurement, past the gentle-practice 3-second gust delay; then both targets remain frozen. Two ABBA warmup rounds are excluded. Each measured block times 1,024 calls with one start and one end timer read; fingerprinting, sample construction, progress output, and parity calls occur outside timed blocks. Each complete measured round verifies complete snapshot bytes and unchanged session state outside timing. The 90-second limit is checked between blocks.",
		measurement_limit = "Each raw sample and percentile describes a block-averaged microseconds-per-call value, not individual-call latency. The block time includes loop, dynamic call/return dispatch, and the two amortized timer reads, but excludes manager orchestration, physics ticks, rendering, file output, and per-call diagnostic instrumentation. The result is a scoped comparative observation measurement, not an end-to-end speedup claim.",
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		fixture.fleet.free()
		fixture.player.free()
		candidate.free()
		printerr("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	fixture.fleet.free()
	fixture.player.free()
	candidate.free()
	print(JSON.stringify({complete = report.complete, rounds = MEASURED_ROUNDS,
		block_calls = CALLS_PER_BLOCK, raw_samples_per_arm = MEASURED_ROUNDS * 2,
		calls_per_arm = timed_calls_baseline, source_unchanged = sources_unchanged}))
	print("AFC OBSERVATION ABBA TIMING COMPLETE")
	quit(0 if bool(report.complete) else 1)


func _prepare_fixture() -> Dictionary:
	var field_result: Dictionary = FieldLoader.load_from()
	var collision: Dictionary = CollisionSetup.build(field_result.field) if field_result.ok else {}
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.ok or not collision.get("ok", false) or not lake.ok:
		return {ok = false, failure = "field, collision, or lake fixture load failed"}
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(field_result.field) or not player.set_collision_world(collision.world) \
			or not player.set_lake_context(lake.lake) or not player.setup_weather(WindConfig.GENTLE_PRACTICE):
		player.free()
		return {ok = false, failure = "player fixture or weather setup failed"}
	player.reset()
	var fleet := Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = 1
	config.seed = 20261020
	var prepared: Dictionary = fleet.configure(player, field_result.field, "club_field", config, false, false)
	if not prepared.get("ok", false) or fleet.agents.size() != 1:
		fleet.free()
		player.free()
		return {ok = false, failure = "manager refused count-1 profile: %s" % str(prepared.get("errors", []))}
	var baseline: Node = fleet.agents[0]
	for tick in PREPARED_TICKS:
		player._physics_process(player.sim.dt())
		player.sim._physics_process(player.sim.dt())
		if player.sim.tick != tick + 1 or not player.sim.fault_reason.is_empty() or not player.crash.is_empty():
			var player_failure: String = "%s %s" % [player.sim.fault_reason, str(player.crash)]
			fleet.free()
			player.free()
			return {ok = false, failure = "player failed during prepared tick %d: %s" % [tick + 1, player_failure]}
		if baseline.session.sim.tick != tick + 1 or not baseline.failure.is_empty() \
				or not baseline.session.sim.fault_reason.is_empty() or not baseline.session.crash.is_empty():
			var companion_failure: String = "%s %s %s" % [baseline.failure,
				baseline.session.sim.fault_reason, str(baseline.session.crash)]
			fleet.free()
			player.free()
			return {ok = false, failure = "companion failed during prepared tick %d: %s" % [tick + 1, companion_failure]}
	if int(player.sim.tick) != PREPARED_TICKS or int(baseline.session.sim.tick) != PREPARED_TICKS \
			or int(fleet.accepted_ticks) != PREPARED_TICKS:
		fleet.free()
		player.free()
		return {ok = false, failure = "prepared fixture did not complete exactly %d manager/player/companion ticks" % PREPARED_TICKS}
	var candidate: Object = CandidateAgentScript.new()
	candidate.set("session", baseline.session)
	candidate.set("slot_id", baseline.slot_id)
	candidate.set("_accepted_trim", baseline._accepted_trim.duplicate(true))
	candidate.set("_weather_rms", baseline._weather_rms.duplicate())
	var profile_identity: Dictionary = fleet.status().get("profile_identity", {}).duplicate(true)
	return {
		ok = true,
		started_utc = Time.get_datetime_string_from_system(true),
		player = player,
		fleet = fleet,
		baseline_agent = baseline,
		candidate_agent = candidate,
		session = baseline.session,
		profile_identity = profile_identity,
	}


func _run_calls(agent: Object) -> int:
	var started: int = Time.get_ticks_usec()
	for _call_index in CALLS_PER_BLOCK:
		var observation: Dictionary = agent.call("observation")
	return Time.get_ticks_usec() - started


func _time_block(agent: Object) -> int:
	return _run_calls(agent)


func _sample(round_index: int, position: String, variant: String, elapsed_usec: int) -> Dictionary:
	return {
		round = round_index,
		position = position,
		variant = variant,
		elapsed_usec = elapsed_usec,
		calls = CALLS_PER_BLOCK,
		block_mean_usec_per_call = float(elapsed_usec) / float(CALLS_PER_BLOCK),
	}


func _parity_check(baseline: Object, candidate: Object, session: Node) -> Dictionary:
	var before_state: String = _fingerprint(_session_state(session))
	var production_snapshot: Dictionary = baseline.call("observation")
	var candidate_snapshot: Dictionary = candidate.call("observation")
	var after_state: String = _fingerprint(_session_state(session))
	return {
		equal = var_to_bytes(production_snapshot) == var_to_bytes(candidate_snapshot),
		state_unchanged = before_state == after_state,
		state_fingerprint = after_state,
	}


func _session_state(session: Node) -> Dictionary:
	return {
		"tick": session.sim.tick,
		"time": session.sim.time(),
		"state": session.sim.state,
		"previous": session.sim.previous,
		"inputs": session.sim.inputs,
		"aux": session.sim.aux,
		"continuous": session.sim.continuous,
		"modes": session.sim.modes,
		"failure": session.sim.fault_reason,
		"crash": session.crash,
	}


func _source_hashes() -> Dictionary:
	var result := {}
	for label: String in SOURCE_PATHS.keys():
		result[label] = FileAccess.get_sha256(ProjectSettings.globalize_path(str(SOURCE_PATHS[label])))
	for relative: String in [
		"../research/ai-companions/performance/observation_airdata_candidate.gd",
		"../research/ai-companions/performance/observation_candidate_agent.gd",
		"../research/ai-companions/performance/observation_abba_timing_probe.gd",
	]:
		var absolute: String = ProjectSettings.globalize_path("res://" + relative)
		result["research/ai-companions/performance/" + relative.get_file()] = FileAccess.get_sha256(absolute)
	return result


func _fingerprint(value: Variant) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(var_to_bytes(value))
	return hasher.finish().hex_encode()


func _variant_samples(samples: Array[Dictionary], variant: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sample: Dictionary in samples:
		if str(sample.variant) == variant:
			result.append(sample)
	return result


func _summary(samples: Array[Dictionary]) -> Dictionary:
	var values: Array[float] = []
	var sum := 0.0
	for sample: Dictionary in samples:
		var value: float = float(sample.block_mean_usec_per_call)
		values.append(value)
		sum += value
	values.sort()
	return {
		"block_count": values.size(),
		"mean_of_block_means_usec_per_call": sum / float(values.size()) if not values.is_empty() else 0.0,
		"p50_block_mean_usec_per_call": _nearest_rank(values, 0.50),
		"p95_block_mean_usec_per_call": _nearest_rank(values, 0.95),
		"p99_block_mean_usec_per_call": _nearest_rank(values, 0.99),
		"min_block_mean_usec_per_call": values[0] if not values.is_empty() else 0.0,
		"max_block_mean_usec_per_call": values[values.size() - 1] if not values.is_empty() else 0.0,
		"percentile_method": "nearest rank over block means: sorted[ceil(n*p)-1]",
	}


func _nearest_rank(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(int(ceil(float(values.size()) * percentile)) - 1, 0, values.size() - 1)
	return values[index]


func _deadline_elapsed(started_usec: int) -> bool:
	return Time.get_ticks_usec() - started_usec >= HARD_TIMEOUT_SECONDS * 1000000


func _same(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)
