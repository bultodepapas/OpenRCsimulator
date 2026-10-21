## AFC-00-R5: paired, non-timed observation and command parity through real short fleet flights.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const ProductionPilot := preload("res://ai/companions/pilot.gd")
const Air := preload("res://physics/air_data.gd")
const CandidateAirdata := preload("res://../research/ai-companions/performance/observation_airdata_candidate.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const FLIGHT_TICKS := 1200
const COUNTS := [1, 3]
const APP_SOURCES := {
	"app/project.godot": "res://project.godot",
	"app/ai/companions/agent.gd": "res://ai/companions/agent.gd",
	"app/ai/companions/manager.gd": "res://ai/companions/manager.gd",
	"app/ai/companions/pilot.gd": "res://ai/companions/pilot.gd",
	"app/physics/air_data.gd": "res://physics/air_data.gd",
	"app/physics/math3d.gd": "res://physics/math3d.gd",
	"app/physics/rigid_body.gd": "res://physics/rigid_body.gd",
	"app/physics/wind_config.gd": "res://physics/wind_config.gd",
	"app/physics/wind_field.gd": "res://physics/wind_field.gd",
	"app/sim/flight_session.gd": "res://sim/flight_session.gd",
	"app/sim/simulation.gd": "res://sim/simulation.gd",
	"app/data/field_loader.gd": "res://data/field_loader.gd",
	"app/data/lake_loader.gd": "res://data/lake_loader.gd",
	"app/scenery/collision_setup.gd": "res://scenery/collision_setup.gd",
	"app/app_state/aircraft_catalog.gd": "res://app_state/aircraft_catalog.gd",
}

class PilotCommandRecorder extends RefCounted:
	var target: Variant
	var reporter: Object
	var slot_id := -1

	func command(snapshot: Dictionary, tick: int, traffic: Array) -> Dictionary:
		var result: Dictionary = target.command(snapshot, tick, traffic)
		reporter.record_pilot_return(slot_id, tick, traffic, result)
		return result


class ObservationAgentProxy extends Node:
	var target: Node
	var candidate_observation := false
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
		var value: Dictionary
		if candidate_observation:
			var state: PackedFloat64Array = target.session.sim.state.duplicate()
			var wind: PackedFloat64Array = target.session.wind_at(target.session.sim.time())
			value = {
				id = "companion-%d" % target.slot_id,
				slot = target.slot_id,
				state = state,
				airspeed_m_s = CandidateAirdata.airspeed_m_s(state, wind),
				wind_ned = wind,
				ground_clearance_m = -state[2] - float(target.session.environment.ground(state[0], state[1])[0]),
				trim = target._accepted_trim.duplicate(),
				turbulence_rms_m_s = target._weather_rms.duplicate(),
				is_player = false,
			}
		else:
			value = target.observation()
		reporter.record_observation(target.slot_id, target.session, value)
		return value

	func needs_command(tick: int) -> bool:
		return target.needs_command(tick)

	func prepare(snapshot: Dictionary, tick: int, traffic: Array) -> bool:
		return target.prepare(snapshot, tick, traffic)

	func advance() -> bool:
		return target.advance()


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--parse-only"):
		print("AFC OBSERVATION FLIGHT PROBE PARSED")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	var output := ""
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var smoke: bool = arguments.has("--smoke")
	var ticks: int = 8 if smoke else FLIGHT_TICKS
	var case_counts: Array = [1] if smoke else COUNTS
	for argument: String in arguments:
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		printerr("Supply --out=<new JSON file>.")
		quit(2)
		return
	var source_before: Dictionary = _source_hashes()
	if int(Engine.physics_ticks_per_second) != 240:
		printerr("Expected the unchanged 240 Hz physics frequency.")
		quit(1)
		return
	var field_result: Dictionary = FieldLoader.load_from()
	var collision: Dictionary = CollisionSetup.build(field_result.field) if field_result.ok else {}
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.ok or not collision.get("ok", false) or not lake.ok:
		printerr("Field/collision/lake fixture setup failed.")
		quit(1)
		return
	var started_utc: String = Time.get_datetime_string_from_system(true)
	var rows: Array[Dictionary] = []
	var complete := true
	for count_value: int in case_counts:
		var branches: Dictionary = {}
		for branch: String in ["baseline", "candidate"]:
			print("[observation-flight] start count=%d branch=%s mode=%s ticks=%d" % [
				count_value, branch, "smoke" if smoke else "full", ticks])
			branches[branch] = _run_case(count_value, field_result.field, collision.world, lake.lake,
				branch == "candidate", ticks)
			var result: Dictionary = branches[branch]
			print("[observation-flight] finished count=%d branch=%s complete=%s ticks=%d/%d" % [
				count_value, branch, str(result.get("complete", false)),
				int(result.get("completed_ticks", 0)), ticks])
		var pair: Dictionary = _compare_pair(count_value, branches, not smoke)
		rows.append(pair)
		complete = complete and bool(pair.get("complete", false))
	var source_after: Dictionary = _source_hashes()
	var sources_unchanged: bool = var_to_bytes(source_before) == var_to_bytes(source_after)
	complete = complete and sources_unchanged
	var report := {
		format = "openrc-afc-observation-airdata-flight-parity v1",
		complete = complete,
		status = "pass" if complete else "fail",
		started_utc = started_utc,
		finished_utc = Time.get_datetime_string_from_system(true),
		engine = Engine.get_version_info().string,
		processor = OS.get_processor_name(),
		physics_hz = int(Engine.physics_ticks_per_second),
		run_mode = "smoke" if smoke else "paired_flight",
		ticks_per_branch = ticks,
		counts = case_counts,
		weather = WindConfig.GENTLE_PRACTICE,
		cases = rows,
		source_identity = {
			"sha256_before": source_before,
			"sha256_after": source_after,
			"all_pinned_source_bytes_unchanged": sources_unchanged,
		},
		fixture = {
			"aircraft_id": Catalog.DEFAULT_ID,
			"field": "default Club field",
			"collision_inventory": "CollisionSetup.build(field), unchanged production scenery data",
			"lake": LakeLoader.DEFAULT_PATH,
			"seed": 20261020,
			"weather": "WindConfig.GENTLE_PRACTICE; companion configuration accepts its stated gust and turbulence limits",
			"pilot": "unchanged production pilot; only the Agent.observation calculation is branched outside app/",
			"input_tape": "same deterministic player session per fresh branch; player input_enabled=false; each player and companion tick input/state is fingerprinted",
		},
		scope = "Bounded deterministic software parity proof for the observation output and resulting production pilot commands. No timing, speedup, rendered-frame, broad flight qualification, or physical-validation claim.",
		method = "The baseline uses production Agent.observation(). The candidate proxy reconstructs the same dictionary fields, samples wind once, and uses the external scalar airspeed helper. Both pass snapshots into the unchanged Agent.prepare() and production pilot. Full pilot command dictionaries, observation bytes, applied packets, tick states, and simulation input arrays are SHA-256 fingerprinted per decision/tick. Candidate observations are also checked against both Air.compute(state, sampled wind, density) and the production session.air_data(state) scalar.",
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	print("AFC OBSERVATION FLIGHT PARITY COMPLETE")
	quit(0 if complete else 1)


func _run_case(count: int, field: Dictionary, collision_world: Dictionary, lake: Dictionary,
		candidate_branch: bool, ticks: int) -> Dictionary:
	var case_field: Dictionary = field.duplicate(true)
	var case_collision: Dictionary = collision_world.duplicate(true)
	var case_lake: Dictionary = lake.duplicate(true)
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(case_field) or not player.set_collision_world(case_collision) \
			or not player.set_lake_context(case_lake) or not player.setup_weather(WindConfig.GENTLE_PRACTICE):
		player.free()
		return {complete = false, failure = "Player environment or weather setup failed.", completed_ticks = 0}
	player.reset()

	var fleet := Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = count
	config.seed = 20261020
	var prepared: Dictionary = fleet.configure(player, case_field, "club_field", config, false, false)
	if not prepared.get("ok", false):
		fleet.free()
		player.free()
		return {complete = false, failure = "Manager configuration refused: %s" % str(prepared.get("errors", [])), completed_ticks = 0}

	var original_agents: Array[Node] = []
	var proxies: Array[Node] = []
	for raw_agent: Node in fleet.agents:
		original_agents.append(raw_agent)
		var command_recorder := PilotCommandRecorder.new()
		command_recorder.target = raw_agent.pilot
		command_recorder.reporter = self
		command_recorder.slot_id = int(raw_agent.slot_id)
		raw_agent.pilot = command_recorder
		var proxy := ObservationAgentProxy.new()
		proxy.target = raw_agent
		proxy.candidate_observation = candidate_branch
		proxy.reporter = self
		proxy.name = raw_agent.name
		proxies.append(proxy)
	fleet.agents = proxies

	var trace := {
		"branch": "candidate" if candidate_branch else "baseline",
		"count": count,
		"complete": false,
		"completed_ticks": 0,
		"failure": "",
		"player_tick_fingerprints": [],
		"agent_tick_fingerprints": {},
		"observation_fingerprints": {},
		"pilot_return_fingerprints": {},
		"wind_fingerprints": {},
		"airdata_comparison_count": 0,
		"airdata_bitwise_match_count": 0,
		"repeated_wind_match_count": 0,
		"max_sampled_abs_wind_m_s": 0.0,
		"observations_at_or_after_gust_delay": 0,
	}
	for raw_agent: Node in original_agents:
		var slot_key: String = str(raw_agent.slot_id)
		trace.agent_tick_fingerprints[slot_key] = []
		trace.observation_fingerprints[slot_key] = []
		trace.pilot_return_fingerprints[slot_key] = []
		trace.wind_fingerprints[slot_key] = []
	_active_trace = trace
	for _tick in ticks:
		player._physics_process(player.sim.dt())
		player.sim._physics_process(player.sim.dt())
		for raw_agent: Node in original_agents:
			record_agent_tick(raw_agent.slot_id, raw_agent.session, raw_agent._last_command)
		trace.player_tick_fingerprints.append(_fingerprint({
			"state": player.sim.state, "previous": player.sim.previous, "inputs": player.sim.inputs,
			"aux": player.sim.aux, "continuous": player.sim.continuous, "modes": player.sim.modes,
			"crash": player.crash, "fault": player.sim.fault_reason,
		}))
		trace.completed_ticks += 1
		if player.sim.tick != trace.completed_ticks or not player.sim.fault_reason.is_empty() or not player.crash.is_empty():
			trace.failure = "Player stopped at %d: %s %s" % [trace.completed_ticks, player.sim.fault_reason, str(player.crash)]
			break
		for raw_agent: Node in original_agents:
			if raw_agent.session.sim.tick != trace.completed_ticks or not raw_agent.failure.is_empty() \
					or not raw_agent.session.sim.fault_reason.is_empty() or not raw_agent.session.crash.is_empty():
				trace.failure = "%s stopped at %d: %s %s" % [raw_agent.name, trace.completed_ticks,
					raw_agent.failure, str(raw_agent.session.crash)]
				break
		if not trace.failure.is_empty():
			break
	trace.complete = trace.failure.is_empty() and trace.completed_ticks == ticks
	trace.weather_observation_summary = _weather_summary(trace)
	fleet.agents = original_agents
	for proxy: Node in proxies:
		proxy.free()
	fleet.free()
	player.free()
	return trace


func record_observation(slot: int, session: Node, observation: Dictionary) -> void:
	var slot_key: String = str(slot)
	var wind: PackedFloat64Array = observation.wind_ned
	var state: PackedFloat64Array = observation.state
	var time_s: float = session.sim.time()
	var air_from_session: float = float(session.air_data(state).V)
	var air_from_sample: float = float(Air.compute(state, wind, session.air_density(state)).V)
	var air_candidate: float = float(observation.airspeed_m_s)
	var speed_equal: bool = _float_bits(air_candidate) == _float_bits(air_from_session) \
		and _float_bits(air_candidate) == _float_bits(air_from_sample)
	var second_wind: PackedFloat64Array = session.wind_at(time_s)
	var wind_equal: bool = var_to_bytes(wind) == var_to_bytes(second_wind)
	var observation_hash: String = _fingerprint(observation)
	var wind_hash: String = _fingerprint(wind)
	var air_hashes: Array = _active_trace.observation_fingerprints[slot_key]
	air_hashes.append(observation_hash)
	_active_trace.observation_fingerprints[slot_key] = air_hashes
	var winds: Array = _active_trace.wind_fingerprints[slot_key]
	winds.append(wind_hash)
	_active_trace.wind_fingerprints[slot_key] = winds
	_active_trace.airdata_comparison_count += 1
	if speed_equal:
		_active_trace.airdata_bitwise_match_count += 1
	if wind_equal:
		_active_trace.repeated_wind_match_count += 1
	if time_s >= float(WindConfig.GENTLE_PRACTICE.gust_delay_s):
		_active_trace.observations_at_or_after_gust_delay += 1
	for component: float in wind:
		_active_trace.max_sampled_abs_wind_m_s = maxf(_active_trace.max_sampled_abs_wind_m_s, absf(component))


func record_pilot_return(slot: int, tick: int, traffic: Array, result: Dictionary) -> void:
	var slot_key: String = str(slot)
	var commands: Array = _active_trace.pilot_return_fingerprints[slot_key]
	commands.append({"tick": tick, "fingerprint": _fingerprint({"traffic": traffic, "command": result})})
	_active_trace.pilot_return_fingerprints[slot_key] = commands


func record_agent_tick(slot: int, session: Node, command: Dictionary) -> void:
	var slot_key: String = str(slot)
	var ticks: Array = _active_trace.agent_tick_fingerprints[slot_key]
	ticks.append(_fingerprint({
		"state": session.sim.state, "previous": session.sim.previous, "inputs": session.sim.inputs,
		"aux": session.sim.aux, "continuous": session.sim.continuous, "modes": session.sim.modes,
		"command": command, "crash": session.crash, "fault": session.sim.fault_reason,
	}))
	_active_trace.agent_tick_fingerprints[slot_key] = ticks


var _active_trace: Dictionary = {}


func _compare_pair(count: int, branches: Dictionary, require_gust: bool) -> Dictionary:
	var baseline: Dictionary = branches.get("baseline", {})
	var candidate: Dictionary = branches.get("candidate", {})
	var equality: Dictionary = {
		"player_tick_fingerprints_equal": _same(baseline.get("player_tick_fingerprints", []), candidate.get("player_tick_fingerprints", [])),
		"agent_tick_fingerprints_equal": _same(baseline.get("agent_tick_fingerprints", {}), candidate.get("agent_tick_fingerprints", {})),
		"observation_fingerprints_equal": _same(baseline.get("observation_fingerprints", {}), candidate.get("observation_fingerprints", {})),
		"pilot_return_fingerprints_equal": _same(baseline.get("pilot_return_fingerprints", {}), candidate.get("pilot_return_fingerprints", {})),
		"wind_fingerprints_equal": _same(baseline.get("wind_fingerprints", {}), candidate.get("wind_fingerprints", {})),
	}
	var complete: bool = bool(baseline.get("complete", false)) and bool(candidate.get("complete", false))
	for key: String in equality.keys():
		complete = complete and bool(equality[key])
	complete = complete and int(baseline.get("airdata_comparison_count", -1)) == int(baseline.get("airdata_bitwise_match_count", -2))
	complete = complete and int(candidate.get("airdata_comparison_count", -1)) == int(candidate.get("airdata_bitwise_match_count", -2))
	complete = complete and int(baseline.get("repeated_wind_match_count", -1)) == int(baseline.get("airdata_comparison_count", -2))
	complete = complete and int(candidate.get("repeated_wind_match_count", -1)) == int(candidate.get("airdata_comparison_count", -2))
	if require_gust:
		complete = complete and int(candidate.get("observations_at_or_after_gust_delay", 0)) > 0
	return {
		"count": count,
		"complete": complete,
		"baseline": baseline,
		"candidate": candidate,
		"equality": equality,
		"input_tape_equal": bool(equality.player_tick_fingerprints_equal),
		"gust_delay_coverage_required": require_gust,
		"limitation": "Exact paired behavior for this short deterministic weathered fixture only; not a broad companion flight qualification.",
	}


func _weather_summary(trace: Dictionary) -> Dictionary:
	var sample_count := 0
	var unique_wind_fingerprints := {}
	for key: Variant in trace.wind_fingerprints.keys():
		for fingerprint: String in trace.wind_fingerprints[key]:
			sample_count += 1
			unique_wind_fingerprints[fingerprint] = true
	return {
		"observation_samples": sample_count,
		"unique_wind_sample_fingerprints": unique_wind_fingerprints.size(),
		"max_sampled_abs_component_m_s": trace.max_sampled_abs_wind_m_s,
		"observations_at_or_after_gust_delay": trace.observations_at_or_after_gust_delay,
		"gust_delay_s": float(WindConfig.GENTLE_PRACTICE.gust_delay_s),
		"interpretation": "The fixture runs through the configured gust delay with committed deterministic turbulence. This is varied-input coverage, not weather or flight qualification.",
	}


func _source_hashes() -> Dictionary:
	var result := {}
	for label: String in APP_SOURCES.keys():
		var absolute: String = ProjectSettings.globalize_path(str(APP_SOURCES[label]))
		result[label] = FileAccess.get_sha256(absolute)
	var external_path: String = ProjectSettings.globalize_path("res://../research/ai-companions/performance/observation_airdata_candidate.gd")
	result["research/ai-companions/performance/observation_airdata_candidate.gd"] = FileAccess.get_sha256(external_path)
	var probe_path: String = ProjectSettings.globalize_path("res://../research/ai-companions/performance/observation_flight_probe.gd")
	result["research/ai-companions/performance/observation_flight_probe.gd"] = FileAccess.get_sha256(probe_path)
	return result


func _fingerprint(value: Variant) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(var_to_bytes(value))
	return hasher.finish().hex_encode()


func _float_bits(value: float) -> PackedByteArray:
	return var_to_bytes(PackedFloat64Array([value]))


func _same(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)
