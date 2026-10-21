## Actual FlightSession/Manager differential for the reachable-clear score fast path.
## Research-only: the candidate is injected into detached fixtures, never Main/profile.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FlightLogReader := preload("res://tools/flight_log_cli.gd")

const PILOT_PATH := "res://ai/companions/pilot.gd"
const BASE_PATH := "res://ai/companions/circuit_controller.gd"
const CANDIDATE_PATH := "res://../research/ai-companions/performance/reachable_clear_candidate.gd"
const TEST_PATH := "res://../research/ai-companions/performance/flight_clear_equivalence.gd"
const EXPECTED_PILOT_SHA256 := "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
const EXPECTED_BASE_SHA256 := "1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c"
const TICKS := 480
const AGENT_COUNT := 2
const AGENT_SEED := 20261020
const PLAYER_THROTTLE := 0.56
const SOURCE_CODE_DIRS := [
	"res://physics", "res://sim", "res://failures", "res://input", "res://ai/companions",
	"res://app_state", "res://data", "res://scenery", "res://render",
]
const SOURCE_DATA_DIRS := ["res://data"]
const SOURCE_ROOT_FILES := ["res://project.godot"]

class CountedProductionPilot extends "res://ai/companions/pilot.gd":
	var score_evaluations := 0
	func _score_bank(state: PackedFloat64Array, velocity: PackedFloat64Array, speed: float,
			bank: float, nominal: float, candidate: float, clearance: float,
			threats: Array[Dictionary], trace: bool = false) -> Dictionary:
		score_evaluations += 1
		return super._score_bank(state, velocity, speed, bank, nominal, candidate, clearance, threats, trace)

class CountedCandidatePilot extends "res://../research/ai-companions/performance/reachable_clear_candidate.gd":
	var score_evaluations := 0
	func _score_bank(state: PackedFloat64Array, velocity: PackedFloat64Array, speed: float,
			bank: float, nominal: float, candidate: float, clearance: float,
			threats: Array[Dictionary], trace: bool = false) -> Dictionary:
		score_evaluations += 1
		return super._score_bank(state, velocity, speed, bank, nominal, candidate, clearance, threats, trace)

var _checks := 0
var _failures := 0
var _output_directory := ""
var _report: Dictionary = {}
var _input_tape: Array[Dictionary] = []
var _baseline_saved_scores := 0
var _clear_decisions := 0
var _plan_decisions := 0
var _first_difference_tick := -1


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			_output_directory = argument.trim_prefix("--evidence=")
	if _output_directory.is_empty() or DirAccess.dir_exists_absolute(_output_directory) \
			or FileAccess.file_exists(_output_directory):
		printerr("Require --evidence=<new absolute directory>")
		quit(2)
		return
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(_output_directory)
	if mkdir_error != OK:
		printerr("Cannot create evidence directory: ", mkdir_error)
		quit(2)
		return
	for branch: String in ["baseline", "candidate"]:
		var branch_error: Error = DirAccess.make_dir_absolute(_output_directory.path_join(branch))
		if branch_error != OK:
			_check("new branch evidence directory", false, branch + ": " + str(branch_error))
			_finish()
			return

	_check("native engine is Godot 4.7.2", _engine_is_qualified(), str(Engine.get_version_info()))
	_check("fixed simulation clock is 240 Hz", Engine.physics_ticks_per_second == 240,
		str(Engine.physics_ticks_per_second))
	var pilot_sha: String = FileAccess.get_sha256(PILOT_PATH)
	var base_sha: String = FileAccess.get_sha256(BASE_PATH)
	var candidate_sha: String = FileAccess.get_sha256(CANDIDATE_PATH)
	_check("production pilot remains the pinned 363942b4 controller", pilot_sha == EXPECTED_PILOT_SHA256, pilot_sha)
	_check("required circuit base remains pinned", base_sha == EXPECTED_BASE_SHA256, base_sha)
	_check("candidate and baseline scripts are readable", candidate_sha.length() == 64, candidate_sha)
	if _failures > 0:
		_finish()
		return

	var sources_before: Dictionary = _source_manifest()
	_check("scoped source/data identity is complete before run", sources_before.get("ok", false), str(sources_before.get("error", "")))
	if not sources_before.get("ok", false):
		_finish()
		return
	var baseline_result: Dictionary = _new_fixture(false)
	_check("production baseline FlightSession and Manager configure", baseline_result.get("ok", false), str(baseline_result.get("reason", "")))
	if not baseline_result.get("ok", false):
		_finish()
		return
	var candidate_result: Dictionary = _new_fixture(true)
	_check("candidate FlightSession and Manager configure", candidate_result.get("ok", false), str(candidate_result.get("reason", "")))
	if not candidate_result.get("ok", false):
		_dispose_fixture(baseline_result)
		_finish()
		return
	var baseline: Dictionary = baseline_result.fixture
	var candidate: Dictionary = candidate_result.fixture
	var profile_base: Dictionary = baseline.manager.status().get("profile_identity", {})
	var profile_candidate: Dictionary = candidate.manager.status().get("profile_identity", {})
	_check("both fixtures keep the accepted production profile identity",
		var_to_bytes(profile_base) == var_to_bytes(profile_candidate)
		and profile_base.get("controller_sha256", "") == EXPECTED_PILOT_SHA256,
		str({"baseline": profile_base, "candidate": profile_candidate}))
	_check("both branches use the same full scenery collision world",
		baseline.world.identity == candidate.world.identity,
		str({"baseline": baseline.world.identity, "candidate": candidate.world.identity}))
	_check("candidate is marked as an explicit research override, not an accepted profile",
		candidate.candidate_override and candidate.candidate_sha256 == candidate_sha,
		str({"override": candidate.candidate_override, "sha256": candidate.candidate_sha256}))
	if _failures > 0:
		_dispose_fixture(baseline)
		_dispose_fixture(candidate)
		_finish()
		return

	var initial_equal: bool = var_to_bytes(_physical_frame(baseline)) == var_to_bytes(_physical_frame(candidate)) \
		and var_to_bytes(_command_frame(baseline)) == var_to_bytes(_command_frame(candidate))
	_check("both branches start from byte-identical real session/roster state", initial_equal)
	if not initial_equal:
		_dispose_fixture(baseline)
		_dispose_fixture(candidate)
		_finish()
		return

	var baseline_logs: Dictionary = _start_logs(baseline, "baseline")
	_check("all baseline ORFL writers start at common tick zero", baseline_logs.get("ok", false), str(baseline_logs.get("reason", "")))
	var candidate_logs: Dictionary = _start_logs(candidate, "candidate")
	_check("all candidate ORFL writers start at common tick zero", candidate_logs.get("ok", false), str(candidate_logs.get("reason", "")))
	if not baseline_logs.get("ok", false) or not candidate_logs.get("ok", false):
		_stop_logs(baseline_logs, "failed startup")
		_stop_logs(candidate_logs, "failed startup")
		_dispose_fixture(baseline)
		_dispose_fixture(candidate)
		_finish()
		return

	var matched_ticks := 0
	var stream_fault := ""
	for tick in TICKS:
		var input: Dictionary = _control_for_tick(tick)
		_input_tape.append(input.duplicate(true))
		var old_base_counts: Array[int] = _score_counts(baseline)
		var old_candidate_counts: Array[int] = _score_counts(candidate)
		var base_stepped: bool = _step_player(baseline.player, input)
		var candidate_stepped: bool = _step_player(candidate.player, input)
		if not base_stepped or not candidate_stepped:
			stream_fault = "player refused input tick %d (baseline=%s candidate=%s)" % [tick, base_stepped, candidate_stepped]
			break
		if not _fixture_healthy(baseline, tick + 1) or not _fixture_healthy(candidate, tick + 1):
			stream_fault = "fleet did not accept the common tick %d" % (tick + 1)
			break
		var base_counts: Array[int] = _score_counts(baseline)
		var candidate_counts: Array[int] = _score_counts(candidate)
		for index in base_counts.size():
			var base_delta: int = base_counts[index] - old_base_counts[index]
			var candidate_delta: int = candidate_counts[index] - old_candidate_counts[index]
			var saved: int = base_delta - candidate_delta
			if saved == 11:
				_clear_decisions += 1
				_baseline_saved_scores += saved
			elif saved != 0:
				stream_fault = "unexpected score-call difference %d at tick %d slot %d" % [saved, tick, index]
				break
			if base_delta > 0:
				_plan_decisions += 1
		if not stream_fault.is_empty():
			break
		var base_frame := {"physical": _physical_frame(baseline), "commands": _command_frame(baseline)}
		var candidate_frame := {"physical": _physical_frame(candidate), "commands": _command_frame(candidate)}
		if var_to_bytes(base_frame) != var_to_bytes(candidate_frame):
			_first_difference_tick = tick + 1
			stream_fault = "branch frame diverged at accepted tick %d" % (tick + 1)
			break
		matched_ticks += 1
	
	var baseline_stop: Dictionary = _stop_logs(baseline_logs, "flight equivalence baseline complete")
	var candidate_stop: Dictionary = _stop_logs(candidate_logs, "flight equivalence candidate complete")
	_check("both physical branches completed without a frame/control divergence", stream_fault.is_empty(), stream_fault)
	_check("both branches captured all accepted ticks", matched_ticks == TICKS, "%d/%d" % [matched_ticks, TICKS])
	_check("real companion callback reached the clear fast path", _clear_decisions > 0,
		"clear decisions=%d planning decisions=%d score calls skipped=%d" % [_clear_decisions, _plan_decisions, _baseline_saved_scores])
	_check("each clear decision skips exactly eleven pure bank scores", _baseline_saved_scores == _clear_decisions * 11,
		"saved=%d clear=%d" % [_baseline_saved_scores, _clear_decisions])
	_check("all baseline ORFL writers stopped cleanly", baseline_stop.get("ok", false), str(baseline_stop.get("reason", "")))
	_check("all candidate ORFL writers stopped cleanly", candidate_stop.get("ok", false), str(candidate_stop.get("reason", "")))

	var baseline_streams: Dictionary = _inspect_logs(baseline_logs)
	var candidate_streams: Dictionary = _inspect_logs(candidate_logs)
	_check("all six ORFL streams are complete and have matching session clocks",
		baseline_streams.get("ok", false) and candidate_streams.get("ok", false)
		and baseline_streams.get("rows", 0) == TICKS + 1 and candidate_streams.get("rows", 0) == TICKS + 1,
		str({"baseline": baseline_streams, "candidate": candidate_streams}))
	_check("baseline/candidate physics logs pin one identical solver source",
		baseline_streams.get("solver_sha256", "") == candidate_streams.get("solver_sha256", "")
		and not baseline_streams.get("solver_sha256", "").is_empty(),
		str({"baseline": baseline_streams.get("solver_sha256", ""), "candidate": candidate_streams.get("solver_sha256", "")}))

	var sources_after: Dictionary = _source_manifest()
	_check("no source/data identity changed during the run",
		sources_after.get("ok", false) and var_to_bytes(sources_before.get("hashes", {}))
		== var_to_bytes(sources_after.get("hashes", {})), str(sources_after.get("error", "")))
	var tape_path: String = _output_directory.path_join("flight-input-tape.json")
	var tape_file: FileAccess = FileAccess.open(tape_path, FileAccess.WRITE)
	if tape_file != null:
		tape_file.store_string(JSON.stringify(_input_tape, "\t"))
		tape_file.flush()
		tape_file.close()
	_check("exact common player input tape is retained", FileAccess.file_exists(tape_path), tape_path)

	_report = {
		"format": "openrc-clear-fast-path-flight-equivalence v1",
		"proof_status": "pass" if _failures == 0 else "fail",
		"checks": _checks,
		"failures": _failures,
		"engine": Engine.get_version_info().string,
		"physics_hz": Engine.physics_ticks_per_second,
		"accepted_ticks": matched_ticks,
		"capture_start_tick": 0,
		"capture_final_tick": matched_ticks,
		"agents": AGENT_COUNT,
		"agent_seed": AGENT_SEED,
		"player_input_tape_sha256": _hash_bytes(var_to_bytes(_input_tape)),
		"player_input_tape_file": tape_path,
		"input_tape_contract": "The same fixed 240-Hz roll/pitch/yaw/throttle packet is applied to the two real FlightSession player fixtures at each integer tick. Manager controls each real companion from its own session observations on the same common-tick schedule.",
		"baseline_controller": {"path": PILOT_PATH, "sha256": pilot_sha},
		"required_base_dependency": {"path": BASE_PATH, "sha256": base_sha},
		"candidate_controller": {"path": CANDIDATE_PATH, "sha256": candidate_sha,
			"status": "research override injected into a detached Manager fixture; not accepted profile/runtime"},
		"profile_identity": profile_base,
		"source_hashes": sources_before.hashes,
		"world_identity": baseline.world.identity,
		"candidate_world_identity": candidate.world.identity,
		"score_work": {"planning_decisions": _plan_decisions,
			"clear_decisions_with_no_held_plan": _clear_decisions,
			"bank_score_evaluations_skipped": _baseline_saved_scores,
			"expected_skipped_per_clear_decision": 11,
			"elapsed_or_cpu_timing_collected": false},
		"byte_exact_branch_comparison": {"matched_ticks": matched_ticks,
			"compared": ["player/companion state, previous state, inputs, aux, continuous, modes, loads, contact events, scenery damage",
				"player commands/raw controls/trims", "agent command packets and session controls",
				"controller snapshot state, held-maneuver latch, tick/wind/clearance, decision diagnostics",
				"manager accepted ticks, observation batches, snapshot clock, damage flag"],
			"first_difference_tick": _first_difference_tick},
		"orfl": {"baseline": baseline_streams, "candidate": candidate_streams,
			"baseline_player": baseline_logs.paths.get("player", ""),
			"candidate_player": candidate_logs.paths.get("player", "")},
		"limits": [
			"Research-only software equivalence, not physical-flight validation or a performance timing result.",
			"Two-agent Club/Stik roster, calm defaults, one fixed scripted player tape and one source/build/world identity.",
			"Candidate controller is explicitly injected into detached test fixtures while manager profile identity remains pinned to the production controller; this does not prove accepted-profile deployment.",
			"Only the clear, unheld early-return path is optimized; held maneuvers, negative-score conflicts, no-traffic, malformed traffic and non-finite-score fallback paths retain production evaluation flow."
		]
	}
	_dispose_fixture(baseline)
	_dispose_fixture(candidate)
	_finish()


func _new_fixture(candidate_override: bool) -> Dictionary:
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false):
		return {ok = false, reason = "Club field load refused: " + str(field_result.get("errors", []))}
	var lake_result: Dictionary = LakeLoader.load_from()
	if not lake_result.get("ok", false):
		return {ok = false, reason = "default lake load refused: " + str(lake_result.get("errors", []))}
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	if not scenery_result.get("ok", false):
		return {ok = false, reason = "Club scenery load refused: " + str(scenery_result.get("errors", []))}
	var lights_result: Dictionary = FieldLights.load_from()
	if not lights_result.get("ok", false):
		return {ok = false, reason = "field-lights load refused: " + str(lights_result.get("errors", []))}
	var world_result: Dictionary = CollisionWorld.build(field_result.field, scenery_result.scenery, lights_result.lights)
	if not world_result.get("ok", false):
		return {ok = false, reason = "full scenery collision-world build refused: " + str(world_result.get("errors", []))}
	var player: FlightSession = FlightSession.new()
	player.input_enabled = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(field_result.field) or not player.set_lake_context(lake_result.lake) \
			or not player.setup_weather(WeatherSettings.defaults()):
		player.free()
		return {ok = false, reason = "player FlightSession field/lake/weather setup refused"}
	player.reset()
	if not player.set_collision_world(world_result.world):
		player.free()
		return {ok = false, reason = "player FlightSession collision-world setup refused"}
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	var manager: Node = Manager.new()
	var request: Dictionary = Config.defaults()
	request.enabled = true
	request.count = AGENT_COUNT
	request.seed = AGENT_SEED
	var configured: Dictionary = manager.configure(player, field_result.field, "club_field", request, false, false)
	if not configured.get("ok", false) or manager.agents.size() != AGENT_COUNT:
		manager.free()
		player.free()
		return {ok = false, reason = "manager configure refused: " + str(configured)}
	manager.set_process(false)
	var controllers: Array = []
	for agent: Node in manager.agents:
		var preexisting_pose: Dictionary = agent.pilot.initial_pose()
		var replacement: Variant = CountedCandidatePilot.new() if candidate_override else CountedProductionPilot.new()
		if not replacement.configure(agent.slot_id, AGENT_COUNT, AGENT_SEED, agent._accepted_trim, field_result.field):
			manager.remove_now()
			manager.free()
			player.free()
			return {ok = false, reason = "instrumented %s controller configure refused: %s" % ["candidate" if candidate_override else "baseline", replacement.configure_error]}
		if var_to_bytes(replacement.initial_pose()) != var_to_bytes(preexisting_pose):
			manager.remove_now()
			manager.free()
			player.free()
			return {ok = false, reason = "controller replacement changed the already-created launch pose"}
		agent.pilot = replacement
		controllers.append(replacement)
	return {ok = true, fixture = {player = player, manager = manager, field = field_result.field,
		world = world_result.world, controllers = controllers, candidate_override = candidate_override,
		candidate_sha256 = FileAccess.get_sha256(CANDIDATE_PATH) if candidate_override else ""}}


func _start_logs(fixture: Dictionary, branch: String) -> Dictionary:
	var sessions: Array = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	var writers: Array = []
	var paths := {}
	for index in sessions.size():
		var id: String = "player" if index == 0 else "companion-%d" % (index - 1)
		var path: String = _output_directory.path_join(branch).path_join(id + ".orfl")
		var writer: Variant = FlightLog.new(sessions[index])
		var started: Error = writer.start(path)
		if started != OK:
			for prior: Variant in writers:
				prior.stop("capture startup failed")
			return {ok = false, reason = "%s log failed to start (%d): %s" % [id, started, writer.failure]}
		writers.append(writer)
		paths[id] = path
	return {ok = true, writers = writers, paths = paths, branch = branch}


func _stop_logs(capture: Dictionary, reason: String) -> Dictionary:
	if not capture.get("ok", false):
		return {ok = false, reason = "capture handle was not started"}
	var failures: Array[String] = []
	for writer: Variant in capture.writers:
		var stopped: Error = writer.stop(reason)
		if stopped != OK or not writer.failure.is_empty():
			failures.append("%s (%d): %s" % [writer.path, stopped, writer.failure])
	return {ok = failures.is_empty(), reason = "; ".join(failures)}


func _inspect_logs(capture: Dictionary) -> Dictionary:
	if not capture.get("ok", false):
		return {ok = false, reason = "capture handle not started"}
	var entries: Array[Dictionary] = []
	var common_solver := ""
	var row_count := TICKS + 1
	for id: String in ["player", "companion-0", "companion-1"]:
		var path: String = capture.paths[id]
		var inspected: Dictionary = FlightLogReader.inspect(path, false)
		if not inspected.get("ok", false) or not inspected.get("complete", false):
			return {ok = false, reason = "%s ORFL incomplete: %s" % [id, inspected.get("error", "invalid report")]}
		var actual_rows: int = int(inspected.get("rows", -1))
		var footer: Dictionary = inspected.get("footer", {})
		var final_tick: int = int(footer.get("final_tick", -1))
		if actual_rows != row_count or final_tick != TICKS:
			return {ok = false, reason = "%s ORFL clock/count mismatch rows=%d final=%d" % [id, actual_rows, final_tick]}
		var header: Dictionary = capture.writers[entries.size()].header
		var solver: String = str(header.get("solver_sha256", ""))
		if solver.is_empty() or (not common_solver.is_empty() and solver != common_solver):
			return {ok = false, reason = "%s ORFL solver identity differs" % id}
		common_solver = solver
		entries.append({"id": id, "path": path, "bytes": FileAccess.get_file_as_bytes(path).size(),
			"sha256": FileAccess.get_sha256(path), "rows": actual_rows, "final_tick": final_tick,
			"solver_sha256": solver})
	return {ok = true, rows = row_count, final_tick = TICKS, solver_sha256 = common_solver, streams = entries}


func _step_player(player: FlightSession, packet: Dictionary) -> bool:
	player.commands = packet.duplicate(true)
	player.raw = packet.duplicate(true)
	player.sim.inputs = player._inputs()
	if not player._session_after_input():
		return false
	var prior_tick: int = player.sim.tick
	player.sim.step()
	return player.sim.tick == prior_tick + 1 and player.sim.fault_reason.is_empty()


func _control_for_tick(tick: int) -> Dictionary:
	var segment: int = int(tick / 60) % 4
	var rolls: Array[float] = [0.0, -0.035, 0.0, 0.035]
	var pitches: Array[float] = [0.0, 0.015, 0.0, -0.015]
	return {"roll": rolls[segment], "pitch": pitches[segment], "yaw": 0.0, "throttle": PLAYER_THROTTLE}


func _fixture_healthy(fixture: Dictionary, tick: int) -> bool:
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	if player.sim.tick != tick or manager.accepted_ticks != tick or manager._snapshot_tick != -1 \
			or manager._removed or manager.agents.size() != AGENT_COUNT or not player.crash.is_empty() \
			or not player.sim.fault_reason.is_empty():
		return false
	for index in AGENT_COUNT:
		var agent: Node = manager.agents[index]
		if agent.session.sim.tick != tick or not agent.failure.is_empty() or not agent.session.crash.is_empty() \
				or not agent.session.sim.fault_reason.is_empty():
			return false
	return true


func _score_counts(fixture: Dictionary) -> Array[int]:
	var counts: Array[int] = []
	for controller: Variant in fixture.controllers:
		counts.append(int(controller.score_evaluations))
	return counts


func _physical_frame(fixture: Dictionary) -> Array:
	var sessions: Array = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	var frame: Array = []
	for session: FlightSession in sessions:
		frame.append([
			session.sim.tick, session.sim.state, session.sim.previous, session.sim.aux,
			session.sim.inputs, session.sim.continuous, session.sim.modes, session.sim.last_loads,
			session.contact_events(), session.scenery_damage(),
		])
	return frame


func _command_frame(fixture: Dictionary) -> Array:
	var frame: Array = [[fixture.player.commands, fixture.player.raw, fixture.player.trims,
		fixture.player.sim.inputs, fixture.player._gear_requested_down,
		fixture.player._wheel_brake_demand, fixture.player._flap_requested]]
	for index in AGENT_COUNT:
		var agent: Node = fixture.manager.agents[index]
		var controller: Variant = fixture.controllers[index]
		frame.append([
			agent.slot_id, agent.failure, agent._last_command, agent._accepted_trim,
			agent._weather_rms, agent.session.commands, agent.session.raw, agent.session.trims,
			agent.session.sim.inputs, controller.snapshot_state(), _controller_locals(controller),
		])
	frame.append([fixture.manager.accepted_ticks, fixture.manager.observation_batches,
		fixture.manager._snapshot_tick, fixture.manager._damage_dirty])
	return frame


func _controller_locals(controller: Variant) -> Dictionary:
	var result := {}
	for key: String in ["_planning_tick", "_planning_clearance_m", "_has_held_maneuver",
			"_held_bank_rad", "_hold_until_tick", "_clear_since_tick", "_last_decision",
			"_override_roll_demand", "_selected_bank_target_rad", "_planning_wind",
			"_plan_diagnostic_count"]:
		result[key] = controller.get(key)
	return result


func _start_frame(fixture: Dictionary) -> Array:
	return [_physical_frame(fixture), _command_frame(fixture)]


func _dispose_fixture(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var manager: Node = fixture.get("manager")
	var player: FlightSession = fixture.get("player")
	if is_instance_valid(manager):
		if manager.has_method("remove_now"):
			manager.remove_now()
		if manager.get_parent() != null:
			manager.get_parent().remove_child(manager)
		manager.free()
	if is_instance_valid(player):
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
		player.free()


func _source_manifest() -> Dictionary:
	var paths: Array[String] = []
	for directory: String in SOURCE_CODE_DIRS:
		_collect_files(directory, ".gd", paths)
	for directory: String in SOURCE_DATA_DIRS:
		_collect_files(directory, ".json", paths)
	for path: String in SOURCE_ROOT_FILES:
		paths.append(path)
	paths.append(CANDIDATE_PATH)
	paths.append(TEST_PATH)
	paths.sort()
	var hashes := {}
	for path: String in paths:
		if hashes.has(path) or not FileAccess.file_exists(path):
			return {ok = false, error = "missing or duplicate source/data path " + path}
		var digest: String = FileAccess.get_sha256(path)
		if digest.length() != 64:
			return {ok = false, error = "cannot hash source/data path " + path}
		hashes[path] = digest
	return {ok = true, hashes = hashes}


func _collect_files(directory: String, extension: String, paths: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(extension):
			paths.append(directory.path_join(file_name))
	for child: String in DirAccess.get_directories_at(directory):
		_collect_files(directory.path_join(child), extension, paths)


func _hash_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _engine_is_qualified() -> bool:
	var version: Dictionary = Engine.get_version_info()
	return version.get("major", -1) == 4 and version.get("minor", -1) == 7 and version.get("patch", -1) == 2


func _finish() -> void:
	if _report.is_empty():
		_report = {"format": "openrc-clear-fast-path-flight-equivalence v1", "proof_status": "fail",
			"checks": _checks, "failures": _failures, "scope": "preflight or fixture setup failed"}
	else:
		_report.checks = _checks
		_report.failures = _failures
		_report.proof_status = "pass" if _failures == 0 else "fail"
	var path: String = _output_directory.path_join("flight-equivalence.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write flight-equivalence report: ", path)
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("Flight-equivalence report write failed: ", write_error)
		quit(1)
		return
	print("clear fast-path flight equivalence: %d checks, %d failed, %d/%d ticks, %d clear decisions, %d score calls skipped" % [
		_checks, _failures, int(_report.get("accepted_ticks", 0)), TICKS,
		_clear_decisions, _baseline_saved_scores])
	quit(1 if _failures > 0 else 0)
