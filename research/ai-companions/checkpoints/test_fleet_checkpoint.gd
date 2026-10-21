## Offline, fixed-roster continuation proof. This is research-only; it does not add a runtime restore path.
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
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
const Candidate := preload("res://../research/ai-companions/checkpoints/fleet_checkpoint_candidate.gd")
const FleetReplay := preload("res://../research/ai-companions/checkpoints/fleet_decision_replay.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FlightLogReader := preload("res://tools/flight_log_cli.gd")
const ProbeController := preload("res://../research/ai-companions/checkpoints/controller_probe.gd")
const PartialProbeController := preload("res://../research/ai-companions/checkpoints/controller_probe_partial.gd")
const RefusalProbeController := preload("res://../research/ai-companions/checkpoints/controller_probe_mutate_then_refuse.gd")
const ReachablePilotR2 := preload("res://../research/ai-companions/avoidance/reachable_pilot_r2.gd")

const EVIDENCE_ROOT := "D:/OpenRCsimulator-AFC-work/evidence/checkpoints"
const CAPTURE_TICK := 137
const CONTINUATION_TICKS := 240
const COMPANION_COUNT := 2
const COMPANION_SEED := 20261020
const TEST_SOURCE_PATH := "res://../research/ai-companions/checkpoints/test_fleet_checkpoint.gd"
const CANDIDATE_SOURCE_PATH := "res://../research/ai-companions/checkpoints/fleet_checkpoint_candidate.gd"
const PROBE_SOURCE_PATH := "res://../research/ai-companions/checkpoints/controller_probe.gd"
const PARTIAL_PROBE_SOURCE_PATH := "res://../research/ai-companions/checkpoints/controller_probe_partial.gd"
const REFUSAL_PROBE_SOURCE_PATH := "res://../research/ai-companions/checkpoints/controller_probe_mutate_then_refuse.gd"
const FLEET_REPLAY_SOURCE_PATH := "res://../research/ai-companions/checkpoints/fleet_decision_replay.gd"
const REACHABLE_PILOT_SOURCE_PATH := "res://../research/ai-companions/avoidance/reachable_pilot_r2.gd"
const SOURCE_CODE_DIRS := [
	"res://physics", "res://sim", "res://failures", "res://input", "res://ai/companions",
	"res://app_state", "res://data", "res://scenery", "res://render",
]
const DATA_DIRS := ["res://data"]
const ROOT_SOURCE_FILES := ["res://project.godot"]
const LIMITATIONS := [
	"Research proof only; no Main/live-session restore or product checkpoint feature.",
	"Fixed two-agent Club/Stik roster, seed 20261020, reference calm atmosphere, one source/build identity.",
	"Clean shared world only: scenery damage, inter-aircraft contact, incidents, runway/activity reservations and world transitions are refused or absent; per-session contact history stays inside FlightSession checkpoints.",
	"No hot admission, retirement, generation changes, settings changes, weather changes or configuration migration.",
	"The proof-local generation value is zero because current Manager exposes no generation counter.",
	"FlightSession restore switches to recorded-input mode and stays paused; this harness explicitly unpauses only detached offline candidates.",
	"This is a same-process decision-continuation comparison, not a fleet journal or cross-platform replay claim.",
]

var _checks := 0
var _failures := 0
var _field: Dictionary = {}
var _world: Dictionary = {}
var _lake: Dictionary = {}
var _lights: Dictionary = {}
var _checkpoint_path := ""
var _report_path := ""
var _source_hashes: Dictionary = {}
var _report: Dictionary = {}
var _decision_replay_comparison: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _run() -> void:
	var engine_info: Dictionary = Engine.get_version_info()
	_check("native engine is the qualified 4.7.2 build", engine_info.get("major", -1) == 4
		and engine_info.get("minor", -1) == 7 and engine_info.get("patch", -1) == 2, str(engine_info))
	_check("fixed simulation rate is 240 Hz", Engine.physics_ticks_per_second == 240,
		str(Engine.physics_ticks_per_second))
	var field_result: Dictionary = FieldLoader.load_from()
	_check("Club field loads", field_result.get("ok", false), str(field_result.get("errors", [])))
	if not field_result.get("ok", false):
		_finish()
		return
	_field = field_result.field
	var lake_result: Dictionary = LakeLoader.load_from()
	_check("real default lake context loads", lake_result.get("ok", false), str(lake_result.get("errors", [])))
	if not lake_result.get("ok", false):
		_finish()
		return
	_lake = lake_result.lake
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, _field)
	_check("Club scenery loads", scenery_result.get("ok", false), str(scenery_result.get("errors", [])))
	if not scenery_result.get("ok", false):
		_finish()
		return
	var lights_result: Dictionary = FieldLights.load_from()
	_check("real default field lights load", lights_result.get("ok", false), str(lights_result.get("errors", [])))
	if not lights_result.get("ok", false):
		_finish()
		return
	_lights = lights_result.lights
	var world_result: Dictionary = CollisionWorld.build(_field, scenery_result.scenery, _lights)
	_check("full Club scenery and lights collision world builds", world_result.get("ok", false), str(world_result.get("errors", [])))
	if not world_result.get("ok", false):
		_finish()
		return
	_world = world_result.world
	_check("production world contains its immutable static inventory", not _world.identity.is_empty()
		and not _world.proxies.is_empty(), "proxies=%d" % _world.get("proxies", []).size())
	var source_result: Dictionary = _source_manifest()
	_check("runtime input manifest is complete", source_result.get("ok", false), str(source_result.get("error", "")))
	if not source_result.get("ok", false):
		_finish()
		return
	_source_hashes = source_result.hashes

	var baseline: Dictionary = _new_fixture("baseline")
	if not baseline.get("ok", false):
		_finish()
		return
	var baseline_player: FlightSession = baseline.player
	for tick in CAPTURE_TICK:
		if not _step_player(baseline_player, _control_for_tick(tick)):
			_check("baseline reaches capture tick", false, "player stopped at %d" % baseline_player.sim.tick)
			_dispose_fixture(baseline)
			_finish()
			return
	_check("capture lands between four-tick pilot updates", CAPTURE_TICK % 4 != 0)
	_check("baseline has an aligned healthy common tick", _aligned_fixture(baseline, CAPTURE_TICK),
		"player=%d accepted=%d" % [baseline_player.sim.tick, baseline.manager.accepted_ticks])
	var record_result: Dictionary = _draft_record(baseline)
	_check("clean fixed-roster boundary is capturable", record_result.get("ok", false),
		str(record_result.get("reason", "")))
	if not record_result.get("ok", false):
		_dispose_fixture(baseline)
		_finish()
		return
	var record: Dictionary = record_result.record
	var encoded: String = CheckpointJson.encode(record)
	_check("lossless native checkpoint carrier encodes", not encoded.is_empty(),
		"encoded bytes=%d" % encoded.to_utf8_buffer().size())
	var decoded: Dictionary = CheckpointJson.decode(encoded)
	_check("carrier decode preserves the complete Variant tree byte-for-byte",
		decoded.get("ok", false) and var_to_bytes(decoded.snapshot) == var_to_bytes(record))
	_checkpoint_path = _write_checkpoint(encoded)
	_check("checkpoint is written and read back from the requested evidence volume",
		not _checkpoint_path.is_empty(), _checkpoint_path)
	if _checkpoint_path.is_empty():
		_dispose_fixture(baseline)
		_finish()
		return
	var transported_text: String = FileAccess.get_file_as_string(_checkpoint_path)
	var transported: Dictionary = CheckpointJson.decode(transported_text)
	_check("actual file transport preserves float64 and signed native Variants",
		transported.get("ok", false) and var_to_bytes(transported.snapshot) == var_to_bytes(record),
		"transport bytes=%d" % transported_text.to_utf8_buffer().size())
	if not transported.get("ok", false) or var_to_bytes(transported.snapshot) != var_to_bytes(record):
		_dispose_fixture(baseline)
		_finish()
		return

	var expected_capture: Dictionary = FleetReplay.start_capture(baseline, record,
		_evidence_directory("decision-expected"))
	_check("ORFL writers can start together at the nonzero common tick",
		expected_capture.get("ok", false), str(expected_capture.get("reason", "")))
	var baseline_frames: Dictionary = _continue_and_capture(baseline, record.future_player_tape)
	_check("uninterrupted baseline advances the complete fixed-roster continuation",
		baseline_frames.get("ok", false), str(baseline_frames.get("reason", "")))
	var expected_capture_result: Dictionary = {"ok": false}
	if expected_capture.get("ok", false):
		expected_capture_result = FleetReplay.finish_capture(expected_capture, record)
	_check("baseline ORFL streams close with a complete source-bound replay manifest",
		expected_capture_result.get("ok", false), str(expected_capture_result.get("reason", "")))
	var decision_manifest: Dictionary = expected_capture_result.get("manifest", {})
	var expected_paths: Dictionary = expected_capture_result.get("paths", {})
	if expected_capture_result.get("ok", false):
		var manifest_text: String = FileAccess.get_file_as_string(expected_capture_result.manifest_path)
		var manifest_decoded: Dictionary = CheckpointJson.decode(manifest_text)
		_check("decision manifest file transport is lossless through the native JSON carrier",
			manifest_decoded.get("ok", false)
			and var_to_bytes(manifest_decoded.get("snapshot", {})) == var_to_bytes(decision_manifest),
			"manifest bytes=%d" % manifest_text.to_utf8_buffer().size())
		if manifest_decoded.get("ok", false):
			decision_manifest = manifest_decoded.snapshot
		var initial_binding := FleetReplay.validate_manifest(decision_manifest, record, expected_paths)
		_check("baseline ORFL bytes still match the manifest before candidate replay",
			initial_binding.get("ok", false), str(initial_binding.get("reason", "")))
	var restored: Dictionary = _new_fixture("restored-candidate")
	if not restored.get("ok", false):
		_dispose_fixture(baseline)
		_finish()
		return
	var fresh_source_result: Dictionary = _source_manifest()
	_check("source identities remain frozen during proof", fresh_source_result.get("ok", false)
		and fresh_source_result.get("hashes", {}) == _source_hashes)
	var restore_result: Dictionary = Candidate.restore_disposable_candidate(restored, record, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	_check("fresh fixed-roster candidate restores before any publication",
		restore_result.get("ok", false), str(restore_result.get("reason", "")))
	if not restore_result.get("ok", false):
		_dispose_fixture(restored)
		_dispose_fixture(baseline)
		_finish()
		return
	var paused_tick: int = restored.player.sim.tick
	var paused_agents: Array[int] = []
	for agent: Node in restored.manager.agents:
		paused_agents.append(agent.session.sim.tick)
	var pause_capture: Dictionary = _draft_record(restored)
	_check("restored candidate refuses snapshot while every restored simulation is paused",
		not pause_capture.get("ok", true) and not str(pause_capture.get("reason", "")).is_empty(),
		str(pause_capture.get("reason", "")))
	var player_pause_refusal: bool = not _prepare_player_tick(restored.player, _control_for_tick(CAPTURE_TICK))
	var agent_pause_refusal := true
	for agent: Node in restored.manager.agents:
		var staged: Dictionary = agent.session.prepare_external_tick(agent._last_command)
		var accepted: bool = staged.get("ok", false) and agent.session.step_external_tick()
		agent_pause_refusal = agent_pause_refusal and staged.get("ok", false) and not accepted
	_check("player and external-agent tick paths refuse advancement while restored-paused",
		player_pause_refusal and agent_pause_refusal and restored.player.sim.tick == paused_tick,
		"player refused=%s agents=%s" % [player_pause_refusal, agent_pause_refusal])
	for index in restored.manager.agents.size():
		agent_pause_refusal = agent_pause_refusal and restored.manager.agents[index].session.sim.tick == paused_agents[index]
	_check("pause refusals leave every common tick unchanged", agent_pause_refusal)
	var unpaused: bool = _unpause_offline(restored)
	_check("caller explicitly unpauses the disposable offline candidate", unpaused)
	var restored_frames: Dictionary = _continue_and_capture(restored, transported.snapshot.future_player_tape)
	_check("restored candidate advances the same continuation", restored_frames.get("ok", false),
		str(restored_frames.get("reason", "")))
	var physical_equal: bool = _frames_equal(baseline_frames.get("physical", []), restored_frames.get("physical", []))
	var commands_equal: bool = _frames_equal(baseline_frames.get("commands", []), restored_frames.get("commands", []))
	_check("player and companion physical state bytes match at every continued tick",
		physical_equal, _first_frame_difference(baseline_frames.get("physical", []), restored_frames.get("physical", [])))
	_check("player input, held commands, trims, pilot locals and manager decisions match byte-for-byte",
		commands_equal, _first_frame_difference(baseline_frames.get("commands", []), restored_frames.get("commands", [])))
	_check("source manifest remains unchanged through both branches",
		_source_manifest().get("hashes", {}) == _source_hashes)
	if expected_capture_result.get("ok", false):
		_run_decision_replay(record, expected_paths, decision_manifest, baseline_frames)
		_run_decision_negative_cases(record, expected_paths, decision_manifest)
	_run_refusal_cases()
	_run_invalid_restore_case()
	_run_invalid_fleet_record_case(record)
	_report = {
		"format": "openrc-offline-fixed-roster-continuation-report v1",
		"status": "pass" if _failures == 0 else "fail",
		"checks": _checks,
		"failures": _failures,
		"engine": engine_info,
		"physics_hz": Engine.physics_ticks_per_second,
		"capture_tick": CAPTURE_TICK,
		"capture_tick_mod_4": CAPTURE_TICK % 4,
		"continuation_ticks": CONTINUATION_TICKS,
		"physical_frames_compared": CONTINUATION_TICKS if physical_equal else 0,
		"command_frames_compared": CONTINUATION_TICKS if commands_equal else 0,
		"checkpoint_path": _checkpoint_path,
		"world_identity": str(_world.get("identity", "")),
		"environment_context": record.environment_context.duplicate(true),
		"source_hashes": _source_hashes.duplicate(true),
		"profile_identity": record.profile_identity.duplicate(true),
		"solver_identity_attribution": {
			"raw_source_sha256": str(record.profile_identity.get("solver_sha256", "")),
			"normalized_profile_qualification_sha256": str(record.profile_identity.get("solver_qualification_sha256", "")),
		},
		"decision_replay_comparison": _decision_replay_comparison.duplicate(true),
		"execution_context": {
			"project_root": ProjectSettings.globalize_path("res://").simplify_path(),
			"checkpoint_source_root": ProjectSettings.globalize_path("res://../research/ai-companions/checkpoints").simplify_path(),
			"controller_path": str(record.profile_identity.get("controller_path", "")),
			"controller_sha256": str(record.profile_identity.get("controller_sha256", "")),
			"reachable_pilot_source_path": REACHABLE_PILOT_SOURCE_PATH,
			"reachable_pilot_source_sha256": _source_hashes.get(REACHABLE_PILOT_SOURCE_PATH, ""),
		},
		"limitations": record.limitations.duplicate(true),
	}
	_dispose_fixture(restored)
	_dispose_fixture(baseline)
	_finish()


func _requested_config() -> Dictionary:
	var requested: Dictionary = Config.defaults()
	requested.enabled = true
	requested.count = COMPANION_COUNT
	requested.seed = COMPANION_SEED
	return requested


func _new_player(field: Dictionary, world: Dictionary) -> FlightSession:
	var player: FlightSession = FlightSession.new()
	player.input_enabled = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(field) or not player.set_lake_context(_lake) \
			or not player.setup_weather(WeatherSettings.defaults()):
		player.free()
		return null
	player.reset()
	if not player.set_collision_world(world):
		player.free()
		return null
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	return player


func _new_fixture(label: String) -> Dictionary:
	var player: FlightSession = _new_player(_field, _world)
	if player == null:
		return {ok = false, reason = label + ": player session setup failed"}
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(player, _field, "club_field", _requested_config(), false, false)
	if not configured.get("ok", false) or manager.agents.size() != COMPANION_COUNT:
		manager.free()
		player.free()
		return {ok = false, reason = label + ": manager configure refused " + str(configured)}
	manager.set_process(false)
	return {ok = true, player = player, manager = manager}


func _dispose_fixture(fixture: Dictionary) -> void:
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


func _control_for_tick(tick: int) -> Dictionary:
	var segment: int = (tick / 30) % 4
	var rolls: Array[float] = [-0.06, 0.0, 0.06, 0.0]
	var pitches: Array[float] = [0.0, 0.025, 0.0, -0.025]
	return {"roll": rolls[segment], "pitch": pitches[segment], "yaw": 0.0, "throttle": 0.56}


func _prepare_player_tick(player: FlightSession, packet: Dictionary) -> bool:
	player.commands = {"roll": packet.roll, "pitch": packet.pitch, "yaw": packet.yaw, "throttle": packet.throttle}
	player.raw = player.commands.duplicate(true)
	player.sim.inputs = player._inputs()
	return player._session_after_input()


func _step_player(player: FlightSession, packet: Dictionary) -> bool:
	var prior_tick: int = player.sim.tick
	if not _prepare_player_tick(player, packet):
		return false
	player.sim.step()
	return player.sim.tick == prior_tick + 1 and player.sim.fault_reason.is_empty()


func _aligned_fixture(fixture: Dictionary, expected_tick: int) -> bool:
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	if player.sim.tick != expected_tick or manager.accepted_ticks != expected_tick or manager._snapshot_tick != -1 \
			or manager._removed or manager.agents.size() != COMPANION_COUNT:
		return false
	for index in manager.agents.size():
		var agent: Node = manager.agents[index]
		if agent.slot_id != index or agent.session.sim.tick != expected_tick or not agent.failure.is_empty() \
				or not agent.session.crash.is_empty() or not agent.session._flight_ready():
			return false
	return true


func _draft_record(fixture: Dictionary) -> Dictionary:
	var tape: Array = []
	for offset in CONTINUATION_TICKS:
		tape.append(_control_for_tick(fixture.player.sim.tick + offset))
	return Candidate.create_record(fixture, _field, _world, _source_hashes, tape, LIMITATIONS)


func _write_checkpoint(text: String) -> String:
	var error_code: Error = DirAccess.make_dir_recursive_absolute(EVIDENCE_ROOT)
	if error_code != OK:
		return ""
	var absolute_path: String = EVIDENCE_ROOT.path_join("fixed-roster-%d.json" % Time.get_ticks_usec())
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return absolute_path if write_error == OK and FileAccess.file_exists(absolute_path) else ""


func _unpause_offline(fixture: Dictionary) -> bool:
	var player: FlightSession = fixture.player
	if not player.sim.paused or player.input_enabled or not player.holds.is_empty():
		return false
	player.pause_reason = ""
	player.sim.set_paused(false)
	for agent: Node in fixture.manager.agents:
		if not agent.session.sim.paused or agent.session.input_enabled or not agent.session.holds.is_empty():
			return false
		agent.session.pause_reason = ""
		agent.session.sim.set_paused(false)
	return not player.sim.paused and fixture.manager.agents.all(func(agent: Node) -> bool: return not agent.session.sim.paused)


func _continue_and_capture(fixture: Dictionary, tape: Array) -> Dictionary:
	if tape.size() != CONTINUATION_TICKS or fixture.player.sim.tick != CAPTURE_TICK:
		return {ok = false, reason = "continuation input tape or starting clock mismatch"}
	var physical: Array[PackedByteArray] = []
	var commands: Array[PackedByteArray] = []
	for index in tape.size():
		var packet: Variant = tape[index]
		if not packet is Dictionary or not _packet_valid(packet):
			return {ok = false, reason = "continuation packet %d is malformed" % index}
		var tick: int = fixture.player.sim.tick
		if not _step_player(fixture.player, packet):
			return {ok = false, reason = "player refused continuation tick %d" % tick}
		if not _aligned_fixture(fixture, tick + 1):
			return {ok = false, reason = "fleet diverged from common tick %d" % (tick + 1)}
		for agent: Node in fixture.manager.agents:
			if not agent.failure.is_empty() or not agent.session.crash.is_empty() or not agent.session.sim.fault_reason.is_empty():
				return {ok = false, reason = "companion fault/crash at tick %d: %s" % [tick + 1, agent.failure]}
		physical.append(var_to_bytes(_physical_frame(fixture)))
		commands.append(var_to_bytes(_command_frame(fixture)))
	return {ok = true, physical = physical, commands = commands}


func _run_decision_replay(record: Dictionary, expected_paths: Dictionary, manifest: Dictionary,
		baseline_frames: Dictionary) -> void:
	var fixture: Dictionary = _new_fixture("ORFL-decision-replay")
	if not fixture.get("ok", false):
		_check("ORFL decision replay fixture configures", false, str(fixture.get("reason", "")))
		return
	var replayed: Dictionary = FleetReplay.restore_and_replay(fixture, expected_paths, manifest, record,
		_field, _world, _source_hashes, _evidence_directory("decision-restored"))
	_check("nonzero-tick ORFL input replay restores a detached fleet and lets Manager recompute decisions",
		replayed.get("ok", false), str(replayed.get("reason", "")))
	_decision_replay_comparison = replayed.get("comparison", {}).duplicate(true)
	if replayed.get("ok", false):
		var comparison: Dictionary = replayed.get("comparison", {})
		_check("all three fleet streams compare every ORFL row and retained event",
			comparison.get("ok", false) and comparison.get("streams", 0) == COMPANION_COUNT + 1
			and comparison.get("rows_compared", 0) == (COMPANION_COUNT + 1) * (CONTINUATION_TICKS + 1)
			and comparison.get("events_compared", false), str(comparison))
		var physical_equal := _frames_equal(baseline_frames.get("physical", []), replayed.get("physical", []))
		var commands_equal := _frames_equal(baseline_frames.get("commands", []), replayed.get("commands", []))
		_check("ORFL-driven fleet physical frames match the independent command-tape continuation",
			physical_equal, _first_frame_difference(baseline_frames.get("physical", []), replayed.get("physical", [])))
		_check("ORFL-driven fleet commands and controller decisions match byte-for-byte",
			commands_equal, _first_frame_difference(baseline_frames.get("commands", []), replayed.get("commands", [])))
		var manifest_text: String = FileAccess.get_file_as_string(replayed.capture.manifest_path)
		var carrier: Dictionary = CheckpointJson.decode(manifest_text)
		_check("candidate replay manifest also survives actual lossless carrier transport",
			carrier.get("ok", false) and var_to_bytes(carrier.get("snapshot", {}))
			== var_to_bytes(replayed.capture.manifest), "manifest bytes=%d" % manifest_text.to_utf8_buffer().size())
	_dispose_fixture(fixture)


func _run_decision_negative_cases(record: Dictionary, expected_paths: Dictionary,
		manifest: Dictionary) -> void:
	var control_directory: String = _evidence_directory("decision-tampered-control")
	var control_copy: String = control_directory.path_join("player.orfl")
	var control_rewrite: Dictionary = _rewrite_orfl(expected_paths.player, control_copy, "control")
	var control_info: Dictionary = FlightLogReader.inspect(control_copy, false) if control_rewrite.get("ok", false) else {"ok": false}
	_check("tampered-control fixture remains a complete, internally checksummed ORFL",
		control_info.get("ok", false) and control_info.get("complete", false), str(control_info.get("error", "")))
	if control_info.get("ok", false):
		var changed_controls: Dictionary = expected_paths.duplicate(true)
		changed_controls.player = control_copy
		var file_binding: Dictionary = FleetReplay.validate_manifest(manifest, record, changed_controls)
		var semantic_binding: Dictionary = FleetReplay.create_manifest(record, changed_controls)
		_check("replay refuses tampered controls before restore by digest and checkpoint-tape binding",
			not file_binding.get("ok", true) and not semantic_binding.get("ok", true),
			str({"manifest": file_binding.get("reason", ""), "tape": semantic_binding.get("reason", "")}))

	var event_directory: String = _evidence_directory("decision-tampered-event")
	var event_copy: String = event_directory.path_join("companion-1.orfl")
	var event_rewrite: Dictionary = _rewrite_orfl(expected_paths["companion-1"], event_copy, "event")
	var event_info: Dictionary = FlightLogReader.inspect(event_copy, false) if event_rewrite.get("ok", false) else {"ok": false}
	_check("tampered-event fixture preserves valid ORFL packet and chain checks",
		event_rewrite.get("changed", false) and event_info.get("ok", false) and event_info.get("complete", false),
		str(event_info.get("error", "")))
	if event_info.get("ok", false):
		var changed_events: Dictionary = expected_paths.duplicate(true)
		changed_events["companion-1"] = event_copy
		var event_binding: Dictionary = FleetReplay.validate_manifest(manifest, record, changed_events)
		_check("replay refuses a semantically changed ORFL event before restoring a candidate",
			not event_binding.get("ok", true), str(event_binding.get("reason", "")))

	var metadata_directory: String = _evidence_directory("decision-tampered-metadata")
	var metadata_copy: String = metadata_directory.path_join("companion-0.orfl")
	var metadata_rewrite: Dictionary = _rewrite_orfl(expected_paths["companion-0"], metadata_copy, "metadata")
	var metadata_info: Dictionary = FlightLogReader.inspect(metadata_copy, false) if metadata_rewrite.get("ok", false) else {"ok": false}
	_check("meaningful-metadata tamper remains a complete, internally checksummed ORFL",
		metadata_rewrite.get("changed", false) and metadata_info.get("ok", false)
		and metadata_info.get("complete", false), str(metadata_info.get("error", "")))
	if metadata_info.get("ok", false):
		var changed_metadata: Dictionary = expected_paths.duplicate(true)
		changed_metadata["companion-0"] = metadata_copy
		var metadata_comparison: Dictionary = FleetReplay.compare_stream_sets(expected_paths,
			changed_metadata, manifest, record)
		_check("replay comparison refuses a neighboring meaningful metadata field outside the provenance allowlist",
			not metadata_comparison.get("ok", true)
			and str(metadata_comparison.get("reason", "")).contains("header.metadata.configuration"),
			str(metadata_comparison.get("reason", "")))

	var source_fixture: Dictionary = _new_fixture("tampered-source-preflight")
	if not source_fixture.get("ok", false):
		_check("tampered-source fixture configures", false, str(source_fixture.get("reason", "")))
		return
	var changed_record: Dictionary = record.duplicate(true)
	var bad_hash := "0".repeat(64)
	if bad_hash == _source_hashes[FLEET_REPLAY_SOURCE_PATH]:
		bad_hash = "1".repeat(64)
	changed_record.source_hashes[FLEET_REPLAY_SOURCE_PATH] = bad_hash
	var changed_manifest: Dictionary = manifest.duplicate(true)
	changed_manifest.source_hashes = changed_record.source_hashes.duplicate(true)
	changed_manifest.record_sha256 = _hash_bytes(var_to_bytes(changed_record))
	var before := var_to_bytes([source_fixture.player.checkpoint(), source_fixture.manager.accepted_ticks,
		source_fixture.manager.observation_batches,
		source_fixture.manager.agents.map(func(agent: Node) -> Dictionary: return agent.session.checkpoint())])
	var source_result: Dictionary = FleetReplay.restore_and_replay(source_fixture, expected_paths,
		changed_manifest, changed_record, _field, _world, _source_hashes,
		_evidence_directory("decision-tampered-source"))
	var after := var_to_bytes([source_fixture.player.checkpoint(), source_fixture.manager.accepted_ticks,
		source_fixture.manager.observation_batches,
		source_fixture.manager.agents.map(func(agent: Node) -> Dictionary: return agent.session.checkpoint())])
	_check("tampered source identity is refused before any session or manager mutation",
		not source_result.get("ok", true) and before == after
		and str(source_result.get("reason", "")).contains("source/data identity"), str(source_result.get("reason", "")))
	_dispose_fixture(source_fixture)


func _evidence_directory(label: String) -> String:
	return EVIDENCE_ROOT.path_join("%s-%d" % [label, Time.get_ticks_usec()])


func _rewrite_orfl(source_path: String, destination: String, mutation: String) -> Dictionary:
	if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		return {ok = false, changed = false, reason = "tamper destination already exists"}
	var input: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if input == null or input.get_length() > FleetReplay.MAX_STREAM_BYTES \
			or input.get_buffer(8).get_string_from_ascii() != FlightLog.MAGIC:
		return {ok = false, changed = false, reason = "source ORFL is missing or oversized"}
	var packets: Array[Dictionary] = []
	var changed := false
	while input.get_position() < input.get_length():
		var packet: Dictionary = FlightLog.read_packet(input)
		if not packet.get("ok", false):
			input.close()
			return {ok = false, changed = false, reason = str(packet.get("error", "packet refused"))}
		var value: Dictionary = packet.value
		if mutation == "control" and value.get("kind") == "block":
			for row_index in value.rows.size():
				var row: Dictionary = value.rows[row_index]
				if row.tick == CAPTURE_TICK + 1:
					var raw: PackedFloat64Array = row.raw.duplicate()
					raw[0] = clampf(raw[0] + 0.01, -1.0, 1.0)
					row.raw = raw
					value.rows[row_index] = row
					changed = true
		if mutation == "event" and value.get("kind") == "block":
			for event_index in value.events.size():
				var event: Dictionary = value.events[event_index]
				if event.kind == "stop":
					event.detail = "tampered stop event"
					value.events[event_index] = event
					changed = true
		if mutation == "metadata" and value.get("kind") == "header":
			var metadata: Dictionary = value.get("metadata", {}).duplicate(true)
			metadata.configuration = "tampered meaningful configuration"
			value.metadata = metadata
			changed = true
		packets.append(value)
	input.close()
	if not changed or packets.size() < 3 or packets.back().get("kind") != "footer":
		return {ok = false, changed = changed, reason = "requested ORFL field was not present"}
	var parent_error: Error = DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if parent_error != OK:
		return {ok = false, changed = false, reason = "tamper evidence directory could not be created"}
	var output: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return {ok = false, changed = false, reason = "tamper fixture could not be written"}
	output.store_buffer(FlightLog.MAGIC.to_ascii_buffer())
	var chain := PackedByteArray()
	for index in packets.size():
		var value: Dictionary = packets[index]
		var footer: bool = index == packets.size() - 1
		if footer:
			value.chain_sha256 = chain.hex_encode()
		var payload: PackedByteArray = var_to_bytes(value)
		var digest: PackedByteArray = FlightLog.sha256(payload)
		output.store_32(payload.size())
		output.store_buffer(digest)
		output.store_buffer(payload)
		if index == 0:
			chain = FlightLog.sha256(digest)
		elif not footer:
			chain = FlightLog.sha256(chain + digest)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	return {ok = write_error == OK and FileAccess.file_exists(destination), changed = changed,
		reason = "" if write_error == OK else "tamper fixture write failed"}


func _physical_frame(fixture: Dictionary) -> Array:
	var sessions: Array[FlightSession] = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	var frame: Array = []
	for session: FlightSession in sessions:
		frame.append([
			session.sim.tick,
			session.sim.state,
			session.sim.previous,
			session.sim.aux,
			session.sim.inputs,
			session.sim.continuous,
			session.sim.modes,
			session.sim.last_loads,
			session.contact_events(),
			session.scenery_damage(),
		])
	return frame


func _command_frame(fixture: Dictionary) -> Array:
	var frame: Array = []
	frame.append([
		fixture.player.commands,
		fixture.player.raw,
		fixture.player.trims,
		fixture.player.sim.inputs,
		fixture.player._gear_requested_down,
		fixture.player._wheel_brake_demand,
		fixture.player._flap_requested,
	])
	for agent: Node in fixture.manager.agents:
		frame.append([
			agent.slot_id,
			agent.failure,
			agent._last_command,
			agent._accepted_trim,
			agent._weather_rms,
			agent.session.commands,
			agent.session.raw,
			agent.session.trims,
			agent.session.sim.inputs,
			Candidate.controller_state(agent, _source_hashes),
		])
	frame.append([fixture.manager.accepted_ticks, fixture.manager.observation_batches,
		fixture.manager._snapshot_tick, fixture.manager._damage_dirty])
	return frame


func _frames_equal(left: Array, right: Array) -> bool:
	if left.size() != CONTINUATION_TICKS or right.size() != CONTINUATION_TICKS:
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _first_frame_difference(left: Array, right: Array) -> String:
	for index in mini(left.size(), right.size()):
		if left[index] != right[index]:
			return "first mismatch at continuation frame %d" % index
	return "frame counts %d/%d" % [left.size(), right.size()]


func _packet_valid(packet: Dictionary) -> bool:
	if not _exact_keys(packet, ["roll", "pitch", "yaw", "throttle"]):
		return false
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(packet[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(packet[key])):
			return false
	return float(packet.roll) >= -1.0 and float(packet.roll) <= 1.0 \
			and float(packet.pitch) >= -1.0 and float(packet.pitch) <= 1.0 \
			and float(packet.yaw) >= -1.0 and float(packet.yaw) <= 1.0 \
			and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0


func _run_refusal_cases() -> void:
	var paused_fixture: Dictionary = _new_fixture("pause-refusal")
	if paused_fixture.get("ok", false):
		_check("pause-refusal fixture accepts one tick", _step_player(paused_fixture.player, _control_for_tick(0)))
		paused_fixture.player.sim.set_paused(true)
		var paused_result: Dictionary = _draft_record(paused_fixture)
		_check("checkpoint creation refuses a paused player", not paused_result.get("ok", true),
			str(paused_result.get("reason", "")))
		_dispose_fixture(paused_fixture)
	else:
		_check("pause-refusal fixture configures", false, str(paused_fixture.get("reason", "")))

	var reset_fixture: Dictionary = _new_fixture("reset-refusal")
	if reset_fixture.get("ok", false):
		_check("reset-refusal fixture accepts one common tick", _step_player(reset_fixture.player, _control_for_tick(0)))
		var agent_tick_before: int = reset_fixture.manager.agents[0].session.sim.tick
		reset_fixture.player.reset()
		var reset_result: Dictionary = _draft_record(reset_fixture)
		_check("checkpoint creation refuses reset-induced player/agent clock mismatch",
			not reset_result.get("ok", true) and reset_fixture.player.sim.tick == 0
			and agent_tick_before == 1 and reset_fixture.manager.agents[0].session.sim.tick == agent_tick_before,
			str(reset_result.get("reason", "")))
		_dispose_fixture(reset_fixture)
	else:
		_check("reset-refusal fixture configures", false, str(reset_fixture.get("reason", "")))

	var world_fixture: Dictionary = _new_fixture("world-refusal")
	if world_fixture.get("ok", false):
		_check("world-refusal fixture accepts one common tick", _step_player(world_fixture.player, _control_for_tick(0)))
		world_fixture.manager._damage_dirty = true
		var world_result: Dictionary = _draft_record(world_fixture)
		_check("checkpoint creation refuses a pending shared-world publication",
			not world_result.get("ok", true) and str(world_result.get("reason", "")).contains("world"),
			str(world_result.get("reason", "")))
		_dispose_fixture(world_fixture)
	else:
		_check("world-refusal fixture configures", false, str(world_fixture.get("reason", "")))


func _run_invalid_restore_case() -> void:
	var session: FlightSession = _new_player(_field, _world)
	if session == null:
		_check("invalid restore transaction fixture configures", false)
		return
	var before: Dictionary = session.checkpoint()
	var before_bytes: PackedByteArray = var_to_bytes([before, session.commands, session.raw, session.trims,
		session.input_enabled, session.external_driver_enabled, session.sim.paused])
	var malformed: Dictionary = before.duplicate(true)
	malformed.simulation.state[0] = NAN
	var accepted: bool = session.restore_checkpoint(malformed)
	var after: Dictionary = session.checkpoint()
	var after_bytes: PackedByteArray = var_to_bytes([after, session.commands, session.raw, session.trims,
		session.input_enabled, session.external_driver_enabled, session.sim.paused])
	_check("nonfinite nested physics state is refused transactionally",
		not accepted and before_bytes == after_bytes, "restore=%s" % accepted)
	session.free()


func _run_invalid_fleet_record_case(record: Dictionary) -> void:
	var source_before: PackedByteArray = var_to_bytes(record)
	var malformed: Dictionary = record.duplicate(true)
	malformed.roster[0].local_tick = record.capture_tick - 1
	var fixture: Dictionary = _new_fixture("invalid-fleet-candidate")
	if not fixture.get("ok", false):
		_check("invalid fleet candidate fixture configures", false, str(fixture.get("reason", "")))
		return
	var rejected: Dictionary = Candidate.validate_record(malformed, fixture, _field, _world, _source_hashes,
		CONTINUATION_TICKS)
	_check("wrong local clock is rejected before a candidate is published",
		not rejected.get("ok", true) and var_to_bytes(record) == source_before
		and fixture.player.sim.tick == 0 and fixture.manager.agents.all(func(agent: Node) -> bool: return agent.session.sim.tick == 0),
		str(rejected.get("reason", "")))
	var unknown_controller: Dictionary = record.duplicate(true)
	unknown_controller.roster[0].agent_state.controller_state.script_path = \
		"res://ai/companions/unregistered_mutable_controller.gd"
	var controller_rejected: Dictionary = Candidate.validate_record(unknown_controller, fixture, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	_check("unknown mutable controller state is refused without an explicit serializer",
		not controller_rejected.get("ok", true) and fixture.player.sim.tick == 0
		and fixture.manager.agents[0].session.sim.tick == 0, str(controller_rejected.get("reason", "")))
	var out_of_range_control: Dictionary = record.duplicate(true)
	out_of_range_control.roster[0].controls.commands.throttle = 10.0
	var control_rejected: Dictionary = Candidate.validate_record(out_of_range_control, fixture, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	_check("non-normalized restored command ranges are refused",
		not control_rejected.get("ok", true) and fixture.player.sim.tick == 0, str(control_rejected.get("reason", "")))
	var altered_trim: Dictionary = record.duplicate(true)
	altered_trim.roster[0].agent_state.accepted_trim.speed_m_s = 99.0
	var trim_rejected: Dictionary = Candidate.validate_record(altered_trim, fixture, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	_check("agent accepted trim must match the fresh configured aircraft", not trim_rejected.get("ok", true),
		str(trim_rejected.get("reason", "")))
	var forged_manifest: Dictionary = _source_hashes.duplicate(true)
	forged_manifest[CANDIDATE_SOURCE_PATH] = "0".repeat(64)
	var forged_record: Dictionary = record.duplicate(true)
	forged_record.source_hashes = forged_manifest.duplicate(true)
	var hash_rejected: Dictionary = Candidate.validate_record(forged_record, fixture, _field, _world,
		forged_manifest, CONTINUATION_TICKS)
	_check("manifest entries must match current on-disk source bytes", not hash_rejected.get("ok", true),
		str(hash_rejected.get("reason", "")))
	var incomplete_manifest: Dictionary = _source_hashes.duplicate(true)
	incomplete_manifest.erase("res://physics/rigid_body.gd")
	var incomplete_record: Dictionary = record.duplicate(true)
	incomplete_record.source_hashes = incomplete_manifest.duplicate(true)
	var incomplete_rejected: Dictionary = Candidate.validate_record(incomplete_record, fixture, _field, _world,
		incomplete_manifest, CONTINUATION_TICKS)
	_check("manifest must include every in-scope runtime dependency", not incomplete_rejected.get("ok", true),
		str(incomplete_rejected.get("reason", "")))
	_run_controller_protocol_case(fixture.manager.agents[0])
	_check("incomplete snapshot/restore method pair is refused",
		_run_partial_controller_refusal(fixture.manager.agents[0]))
	_run_reachable_controller_protocol_case(fixture.manager.agents[1])
	_check("controller snapshot rejects oversized strings before native serialization",
		not Candidate._serializable_controller_state({"oversized": "x".repeat(2049)}))
	_run_mutate_then_refuse_restore_case(record)
	var oversized_tape: Array = []
	oversized_tape.resize(14401)
	var oversized: Dictionary = Candidate.create_record(fixture, _field, _world, _source_hashes,
		oversized_tape, LIMITATIONS)
	_check("future tape duration is rejected before scanning oversized input",
		not oversized.get("ok", true) and str(oversized.get("reason", "")).contains("bounded"),
		str(oversized.get("reason", "")))
	var advanced: bool = _step_player(fixture.player, _control_for_tick(0))
	_check("candidate fixture accepts preflight tick for stale-target regression", advanced)
	var before_restore: PackedByteArray = var_to_bytes([fixture.player.checkpoint(), fixture.manager.accepted_ticks,
		fixture.manager.observation_batches, fixture.manager.agents.map(func(agent: Node) -> Dictionary:
			return agent.session.checkpoint())])
	var stale_restore: Dictionary = Candidate.restore_disposable_candidate(fixture, record, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	var after_restore: PackedByteArray = var_to_bytes([fixture.player.checkpoint(), fixture.manager.accepted_ticks,
		fixture.manager.observation_batches, fixture.manager.agents.map(func(agent: Node) -> Dictionary:
			return agent.session.checkpoint())])
	_check("restore refuses an already-used target before changing any session",
		not stale_restore.get("ok", true) and before_restore == after_restore
		and fixture.player.sim.tick == 1 and fixture.manager.agents.all(func(agent: Node) -> bool: return agent.session.sim.tick == 1),
		str(stale_restore.get("reason", "")))
	_dispose_fixture(fixture)
	var in_tree_fixture: Dictionary = _new_fixture("in-tree-target-refusal")
	if in_tree_fixture.get("ok", false):
		get_root().add_child(in_tree_fixture.manager)
		var in_tree_result: Dictionary = Candidate.validate_record(record, in_tree_fixture, _field, _world,
			_source_hashes, CONTINUATION_TICKS)
		_check("scene-tree target is refused before checkpoint mutation",
			not in_tree_result.get("ok", true) and in_tree_fixture.player.sim.tick == 0
			and in_tree_fixture.manager.agents.all(func(agent: Node) -> bool: return agent.session.sim.tick == 0),
			str(in_tree_result.get("reason", "")))
		get_root().remove_child(in_tree_fixture.manager)
		_dispose_fixture(in_tree_fixture)
	else:
		_check("in-tree target refusal fixture configures", false, str(in_tree_fixture.get("reason", "")))


func _run_controller_protocol_case(agent: Node) -> void:
	var original: RefCounted = agent.pilot
	var probe := ProbeController.new()
	probe.continuation_token = 41
	agent.pilot = probe
	var captured: Dictionary = Candidate.capture_controller_state(agent, _source_hashes)
	_check("snapshot_state captures a source-bound controller snapshot",
		captured.get("ok", false) and captured.get("state", {}).get("format", "") == "controller-method-state v1"
		and captured.get("state", {}).get("state", {}).get("continuation_token", -1) == 41,
		str(captured.get("reason", "")))
	probe.continuation_token = 0
	var restored: Dictionary = {"ok": false}
	if captured.get("ok", false):
		restored = Candidate._restore_controller_state(agent, captured.state)
	_check("restore_state Dictionary{ok:true} restores controller locals",
		restored.get("ok", false) and probe.continuation_token == 41)
	var invalid: Dictionary = captured.state.duplicate(true)
	invalid.state.continuation_token = -1
	probe.continuation_token = 9
	var invalid_restore: Dictionary = Candidate._restore_controller_state(agent, invalid)
	_check("atomic controller refusal preserves its prior locals",
		not invalid_restore.get("ok", true) and invalid_restore.get("rollback_ok", false)
		and probe.continuation_token == 9)
	agent.pilot = original


func _run_reachable_controller_protocol_case(agent: Node) -> void:
	var original: RefCounted = agent.pilot
	var pilot: RefCounted = ReachablePilotR2.new()
	var configured: bool = pilot.configure(agent.slot_id, COMPANION_COUNT, COMPANION_SEED,
		agent._accepted_trim.duplicate(true), _field)
	var seed_state := {
		"version": "reachable-pilot-state-v1", "planning_tick": 136,
		"has_held_maneuver": false, "held_bank_rad": 0.0,
		"hold_until_tick": -1, "clear_since_tick": -1,
	}
	var seeded: Dictionary = pilot.restore_state(seed_state) if configured else {"ok": false}
	agent.pilot = pilot
	var old_command: Dictionary = agent._last_command.duplicate(true)
	if agent._last_command.is_empty():
		agent._last_command = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.5}
	var captured: Dictionary = Candidate.capture_controller_state(agent, _source_hashes)
	var saved_agent_state: Dictionary = Candidate._agent_state(agent, captured.get("state", {}))
	var valid: bool = configured and seeded.get("ok", false) and captured.get("ok", false) \
			and Candidate._agent_state_valid(agent, saved_agent_state, _source_hashes)
	_check("reachable_pilot_r2 method snapshot is source-bound and valid in the reusable protocol", valid,
		str({"configured": configured, "seeded": seeded, "captured": captured,
			"valid": valid, "script_path": pilot.get_script().resource_path,
			"manifest_has": _source_hashes.has(REACHABLE_PILOT_SOURCE_PATH)}))
	if valid:
		pilot._planning_tick = 220
		var restored: Dictionary = Candidate._restore_controller_state(agent, captured.state)
		_check("reachable_pilot_r2 restore_state Dictionary contract round-trips locals",
			restored.get("ok", false) and var_to_bytes(pilot.snapshot_state()) == var_to_bytes(seed_state))
		var malformed: Dictionary = captured.state.duplicate(true)
		malformed.state.planning_tick = 136.0
		var before: PackedByteArray = var_to_bytes(pilot.snapshot_state())
		var refused: Dictionary = Candidate._restore_controller_state(agent, malformed)
		_check("reachable pilot rejects malformed snapshot without changing its locals",
			not refused.get("ok", true) and refused.get("rollback_ok", false)
			and before == var_to_bytes(pilot.snapshot_state()))
	agent.pilot = original
	agent._last_command = old_command


func _run_mutate_then_refuse_restore_case(record: Dictionary) -> void:
	var fixture: Dictionary = _new_fixture("controller-refusal-transaction")
	if not fixture.get("ok", false):
		_check("controller refusal transaction fixture configures", false, str(fixture.get("reason", "")))
		return
	var probe := RefusalProbeController.new()
	probe.continuation_token = 5
	fixture.manager.agents[0].pilot = probe
	var malformed: Dictionary = record.duplicate(true)
	malformed.roster[0].agent_state.controller_state = {
		"format": "controller-method-state v1",
		"script_path": REFUSAL_PROBE_SOURCE_PATH,
		"source_sha256": _source_hashes[REFUSAL_PROBE_SOURCE_PATH],
		"state": {"continuation_token": 13},
	}
	var before: PackedByteArray = var_to_bytes([
		fixture.player.checkpoint(), fixture.manager.accepted_ticks, fixture.manager.observation_batches,
		fixture.manager.agents.map(func(agent: Node) -> Dictionary: return agent.session.checkpoint()),
	])
	var result: Dictionary = Candidate.restore_disposable_candidate(fixture, malformed, _field, _world,
		_source_hashes, CONTINUATION_TICKS)
	var after: PackedByteArray = var_to_bytes([
		fixture.player.checkpoint(), fixture.manager.accepted_ticks, fixture.manager.observation_batches,
		fixture.manager.agents.map(func(agent: Node) -> Dictionary: return agent.session.checkpoint()),
	])
	_check("mutating controller refusal is rolled back before any session checkpoint mutation",
		not result.get("ok", true) and result.get("controller_rollback_ok", false)
		and probe.continuation_token == 5 and before == after,
		str({"reason": result.get("reason", ""), "manifest_current": Candidate._source_manifest_is_current(_source_hashes),
			"manifest_entries": _source_hashes.size(), "token": probe.continuation_token,
			"session_bytes_match": before == after}))
	_dispose_fixture(fixture)


func _run_partial_controller_refusal(agent: Node) -> bool:
	var original: RefCounted = agent.pilot
	agent.pilot = PartialProbeController.new()
	var result: Dictionary = Candidate.capture_controller_state(agent, _source_hashes)
	agent.pilot = original
	return not result.get("ok", true)


func _source_manifest() -> Dictionary:
	var paths: Array[String] = []
	for directory: String in SOURCE_CODE_DIRS:
		_collect_files(directory, ".gd", paths)
	for directory: String in DATA_DIRS:
		_collect_files(directory, ".json", paths)
	for path: String in ROOT_SOURCE_FILES:
		paths.append(path)
	paths.append(TEST_SOURCE_PATH)
	paths.append(CANDIDATE_SOURCE_PATH)
	paths.append(PROBE_SOURCE_PATH)
	paths.append(PARTIAL_PROBE_SOURCE_PATH)
	paths.append(REFUSAL_PROBE_SOURCE_PATH)
	paths.append(REACHABLE_PILOT_SOURCE_PATH)
	paths.append(FLEET_REPLAY_SOURCE_PATH)
	paths.sort()
	var hashes: Dictionary = {}
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


func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


func _finish() -> void:
	if _report.is_empty():
		_report = {"format": "openrc-offline-fixed-roster-continuation-report v1",
			"status": "fail", "checks": _checks, "failures": _failures,
			"checkpoint_path": _checkpoint_path, "source_hashes": _source_hashes}
	else:
		_report.checks = _checks
		_report.failures = _failures
		_report.status = "pass" if _failures == 0 else "fail"
	_report_path = _write_report(_report)
	if _report_path.is_empty():
		_failures += 1
		printerr("FAIL compact human-readable report write to evidence volume")
	var final_text := "PASS" if _failures == 0 else "FAIL"
	print("%s offline fleet checkpoint continuation checks=%d failures=%d capture_tick=%d continuation_ticks=%d checkpoint=%s report=%s" % [
		final_text, _checks, _failures, CAPTURE_TICK, CONTINUATION_TICKS, _checkpoint_path, _report_path])
	quit(1 if _failures > 0 else 0)


func _write_report(value: Dictionary) -> String:
	var error_code: Error = DirAccess.make_dir_recursive_absolute(EVIDENCE_ROOT)
	if error_code != OK:
		return ""
	var path: String = EVIDENCE_ROOT.path_join("report-%d.json" % Time.get_ticks_usec())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return path if parsed is Dictionary and parsed.get("format") == value.format else ""
