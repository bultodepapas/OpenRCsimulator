## Offline fixed-roster checkpoint staging. Never called by Main or production runtime.
extends RefCounted

const RECORD_FORMAT := "openrc-offline-fixed-roster-checkpoint v2"
const SCOPE := "offline_fixed_roster_clean_world_same_build"
const COMPANION_COUNT := 2
const MAX_FUTURE_TICKS := 240 * 60
const MAX_SOURCE_FILES := 4096
const MAX_CONTROLLER_STATE_NODES := 4096
const MAX_CONTROLLER_STATE_DEPTH := 32
const MAX_CONTROLLER_STATE_BYTES := 8 * 1024 * 1024
const MAX_CONTROLLER_STRING_BYTES := 2048
const MAX_CHECKPOINT_PAYLOAD_BYTES := 16 * 1024 * 1024
const MAX_LIMITATIONS := 32
const MAX_LIMITATION_BYTES := 512
const SOURCE_CODE_DIRS := [
	"res://physics", "res://sim", "res://failures", "res://input", "res://ai/companions",
	"res://app_state", "res://data", "res://scenery", "res://render",
]
const SOURCE_DATA_DIRS := ["res://data"]
const SOURCE_ROOT_FILES := ["res://project.godot"]
const SOURCE_EXTRA_FILES := [
	"res://../research/ai-companions/checkpoints/test_fleet_checkpoint.gd",
	"res://../research/ai-companions/checkpoints/fleet_checkpoint_candidate.gd",
	"res://../research/ai-companions/checkpoints/controller_probe.gd",
	"res://../research/ai-companions/checkpoints/controller_probe_partial.gd",
	"res://../research/ai-companions/checkpoints/controller_probe_mutate_then_refuse.gd",
	"res://../research/ai-companions/checkpoints/fleet_decision_replay.gd",
	"res://../research/ai-companions/avoidance/reachable_pilot_r2.gd",
]
const FIXED_GENERATION := 0 # Proof-local initial generation; current Manager has no generation counter.
const BASE_PILOT_SOURCE_SHA256 := "1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c"
const PILOT_KEYS := [
	"configure_error", "_configured", "_slot", "_count", "_seed", "_phase_rad", "_direction",
	"_target_speed_mps", "_trim_throttle", "_field_ground_up_m", "_target_height_agl_m",
	"_runway_north_m", "_runway_east_m", "_runway_length_m", "_runway_width_m",
	"_pilot_north_m", "_pilot_east_m", "_center_north_m", "_center_east_m", "_radius_m", "_target_height_m",
]
const MANAGER_KEYS := ["accepted_ticks", "observation_batches", "snapshot_tick", "removed", "damage_dirty"]
const CONTROL_KEYS := [
	"commands", "raw", "trims", "rate_profile", "input_enabled", "external_driver_enabled", "holds",
	"crash_auto_restart", "pause_reason", "gear_requested_down", "gear_request_inhibited",
	"wheel_brake_demand", "flap_requested",
]


## Build a detached research record only at a clean, accepted fixed-roster common-tick boundary.
static func create_record(fixture: Dictionary, field: Dictionary, world: Dictionary,
		source_hashes: Dictionary, future_player_tape: Array, limitations: Array) -> Dictionary:
	if not fixture.has_all(["player", "manager"]):
		return {ok = false, reason = "fixture is incomplete"}
	if future_player_tape.is_empty() or future_player_tape.size() > MAX_FUTURE_TICKS:
		return {ok = false, reason = "future accepted-input tape is outside the bounded duration"}
	if not _source_manifest_is_current(source_hashes):
		return {ok = false, reason = "source/data manifest is incomplete, malformed or stale"}
	if not _limitations_valid(limitations):
		return {ok = false, reason = "research limitations are outside the bounded schema"}
	var player: Node = fixture.player
	var manager: Node = fixture.manager
	var tick: int = player.sim.tick
	if manager._player != player or not _aligned(fixture, tick):
		return {ok = false, reason = "player, manager and roster are not at one accepted common tick"}
	var environment_context: Dictionary = _environment_context(fixture)
	if environment_context.is_empty() or environment_context.player.collision_world_identity != str(world.get("identity", "")):
		return {ok = false, reason = "real session environment does not match the supplied field world"}
	var reason: String = _session_boundary_refusal(player, false)
	if not reason.is_empty():
		return {ok = false, reason = "player: " + reason}
	if manager._damage_dirty or not player.scenery_damage().is_empty():
		return {ok = false, reason = "shared-world publication/damage is outside this proof"}
	var player_checkpoint: Dictionary = player.checkpoint()
	if player_checkpoint.is_empty() or player_checkpoint.simulation.tick != tick:
		return {ok = false, reason = "player FlightSession checkpoint refused"}
	var roster: Array = []
	for index in manager.agents.size():
		var agent: Node = manager.agents[index]
		reason = _session_boundary_refusal(agent.session, true)
		if not reason.is_empty():
			return {ok = false, reason = "companion-%d: %s" % [index, reason]}
		var session_checkpoint: Dictionary = agent.session.checkpoint()
		if session_checkpoint.is_empty() or session_checkpoint.simulation.tick != tick:
			return {ok = false, reason = "companion-%d FlightSession checkpoint refused" % index}
		var controller: Dictionary = capture_controller_state(agent, source_hashes)
		if not controller.get("ok", false):
			return {ok = false, reason = "companion-%d: %s" % [index, controller.get("reason", "controller state refused")]}
		roster.append({
			"stable_id": "companion-%d" % index,
			"slot_id": agent.slot_id,
			"generation": FIXED_GENERATION,
			"local_tick": agent.session.sim.tick,
			"session_checkpoint": session_checkpoint,
			"controls": _session_controls(agent.session),
			"agent_state": _agent_state(agent, controller.state),
		})
	if future_player_tape.size() < 1:
		return {ok = false, reason = "future accepted-input tape is empty"}
	for packet: Variant in future_player_tape:
		if not packet is Dictionary or not packet_valid(packet):
			return {ok = false, reason = "future accepted-input tape contains a malformed packet"}
	var status: Dictionary = manager.status()
	var field_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://data/fields/default.json")
	var record := {
		"format": RECORD_FORMAT,
		"scope": SCOPE,
		"engine": Engine.get_version_info(),
		"physics_hz": Engine.physics_ticks_per_second,
		"dt": player.sim.dt(),
		"capture_tick": tick,
		"global_time_s": float(tick) * player.sim.dt(),
		"field_id": str(field.get("id", "")),
		"field_sha256": _hash_bytes(field_bytes),
		"world_identity": str(world.get("identity", "")),
		"config": manager.config.duplicate(true),
		"profile_identity": status.get("profile_identity", {}).duplicate(true),
		"airspace_report": status.get("airspace_report", {}).duplicate(true),
		"environment_context": environment_context,
		"source_hashes": source_hashes.duplicate(true),
		"manager_state": {
			"accepted_ticks": manager.accepted_ticks,
			"observation_batches": manager.observation_batches,
			"snapshot_tick": manager._snapshot_tick,
			"removed": manager._removed,
			"damage_dirty": manager._damage_dirty,
		},
		"player": {
			"stable_id": "player",
			"local_tick": tick,
			"session_checkpoint": player_checkpoint,
			"controls": _session_controls(player),
		},
		"roster": roster,
		"future_player_tape": future_player_tape.duplicate(true),
		"limitations": limitations.duplicate(true),
	}
	if not exact_keys(record, [
		"format", "scope", "engine", "physics_hz", "dt", "capture_tick", "global_time_s", "field_id",
		"field_sha256", "world_identity", "config", "profile_identity", "airspace_report",
		"environment_context", "source_hashes",
		"manager_state", "player", "roster", "future_player_tape", "limitations",
	]):
		return {ok = false, reason = "draft checkpoint schema keys are not exact"}
	if var_to_bytes(record).size() > MAX_CHECKPOINT_PAYLOAD_BYTES:
		return {ok = false, reason = "checkpoint exceeds the bounded lossless carrier payload"}
	return {ok = true, record = record}


## Validate the entire envelope against a newly configured detached fixture before restoring anything into it.
static func validate_record(record: Dictionary, fixture: Dictionary, field: Dictionary, world: Dictionary,
		source_hashes: Dictionary, future_tick_count: int) -> Dictionary:
	if not exact_keys(record, [
		"format", "scope", "engine", "physics_hz", "dt", "capture_tick", "global_time_s", "field_id",
		"field_sha256", "world_identity", "config", "profile_identity", "airspace_report",
		"environment_context", "source_hashes",
		"manager_state", "player", "roster", "future_player_tape", "limitations",
	]) or record.get("format") != RECORD_FORMAT or record.get("scope") != SCOPE:
		return {ok = false, reason = "checkpoint schema or scope is unsupported"}
	var fresh_refusal: String = _fresh_fixture_refusal(fixture)
	if not fresh_refusal.is_empty():
		return {ok = false, reason = fresh_refusal}
	if future_tick_count < 1 or future_tick_count > MAX_FUTURE_TICKS \
			or record.get("engine") != Engine.get_version_info() \
			or typeof(record.get("physics_hz")) != TYPE_INT or record.physics_hz != Engine.physics_ticks_per_second \
			or typeof(record.get("capture_tick")) != TYPE_INT or record.capture_tick < 0 \
			or typeof(record.get("dt")) != TYPE_FLOAT or record.dt != fixture.player.sim.dt() \
			or typeof(record.get("global_time_s")) != TYPE_FLOAT \
			or record.global_time_s != float(record.capture_tick) * record.dt:
		return {ok = false, reason = "engine, clock or timestep identity mismatch"}
	var raw_field_sha: String = FileAccess.get_sha256("res://data/fields/default.json")
	if record.get("field_id") != str(field.get("id", "")) or record.get("field_sha256") != raw_field_sha \
			or record.get("world_identity") != str(world.get("identity", "")):
		return {ok = false, reason = "field or collision-world identity mismatch"}
	if typeof(record.get("source_hashes")) != TYPE_DICTIONARY or record.source_hashes != source_hashes:
		return {ok = false, reason = "runtime source/data identity mismatch"}
	if not _source_manifest_is_current(source_hashes):
		return {ok = false, reason = "runtime source/data manifest does not match current files"}
	var manager: Node = fixture.manager
	var status: Dictionary = manager.status()
	if record.get("config") != manager.config or record.get("profile_identity") != status.profile_identity \
			or record.get("airspace_report") != status.airspace_report:
		return {ok = false, reason = "resolved configuration, profile or airspace identity mismatch"}
	var current_environment: Dictionary = _environment_context(fixture)
	if current_environment.is_empty() or var_to_bytes(record.get("environment_context")) != var_to_bytes(current_environment):
		return {ok = false, reason = "player/companion weather, lake, surfaces or collision world differ"}
	if typeof(record.get("manager_state")) != TYPE_DICTIONARY or not exact_keys(record.manager_state, MANAGER_KEYS):
		return {ok = false, reason = "manager clock schema is malformed"}
	var manager_state: Dictionary = record.manager_state
	var expected_batches: int = (record.capture_tick + 3) / 4
	if typeof(manager_state.accepted_ticks) != TYPE_INT or manager_state.accepted_ticks != record.capture_tick \
			or typeof(manager_state.observation_batches) != TYPE_INT or manager_state.observation_batches != expected_batches \
			or typeof(manager_state.snapshot_tick) != TYPE_INT or manager_state.snapshot_tick != -1 \
			or typeof(manager_state.removed) != TYPE_BOOL or manager_state.removed \
			or typeof(manager_state.damage_dirty) != TYPE_BOOL or manager_state.damage_dirty:
		return {ok = false, reason = "manager counters include an unsupported event or malformed clock"}
	if manager.agents.size() != COMPANION_COUNT or typeof(record.get("roster")) != TYPE_ARRAY \
			or record.roster.size() != COMPANION_COUNT or typeof(record.get("player")) != TYPE_DICTIONARY:
		return {ok = false, reason = "fixed roster shape is not supported"}
	if not _session_record_valid(record.player, "player", record.capture_tick, fixture.player):
		return {ok = false, reason = "player checkpoint record or tick is malformed"}
	for index in COMPANION_COUNT:
		var saved: Variant = record.roster[index]
		if not saved is Dictionary or not exact_keys(saved,
			["stable_id", "slot_id", "generation", "local_tick", "session_checkpoint", "controls", "agent_state"]):
			return {ok = false, reason = "companion roster schema is malformed"}
		if saved.stable_id != "companion-%d" % index or typeof(saved.slot_id) != TYPE_INT \
				or saved.slot_id != index or typeof(saved.generation) != TYPE_INT or saved.generation != FIXED_GENERATION \
				or typeof(saved.local_tick) != TYPE_INT or saved.local_tick != record.capture_tick \
				or not saved.get("session_checkpoint") is Dictionary or not saved.get("controls") is Dictionary \
				or not saved.get("agent_state") is Dictionary:
			return {ok = false, reason = "companion identity/generation/local tick is malformed"}
		if not _session_record_valid(saved, saved.stable_id, record.capture_tick, manager.agents[index].session):
			return {ok = false, reason = "companion checkpoint or controls are malformed"}
		if not _agent_state_valid(manager.agents[index], saved.agent_state, record.source_hashes):
			return {ok = false, reason = "companion controller state is malformed or from an unknown controller"}
	if typeof(record.get("future_player_tape")) != TYPE_ARRAY \
			or record.future_player_tape.size() != future_tick_count \
			or record.future_player_tape.size() > MAX_FUTURE_TICKS:
		return {ok = false, reason = "future accepted-input tape has the wrong length"}
	for packet: Variant in record.future_player_tape:
		if not packet is Dictionary or not packet_valid(packet):
			return {ok = false, reason = "future accepted-input tape contains an invalid packet"}
	if typeof(record.get("limitations")) != TYPE_ARRAY or record.limitations.is_empty():
		return {ok = false, reason = "research limitations are missing"}
	for limitation: Variant in record.limitations:
		if typeof(limitation) != TYPE_STRING or limitation.is_empty():
			return {ok = false, reason = "research limitation entry is malformed"}
	return {ok = true}


## This mutates only a newly built offline candidate. A failed restore requires discarding that detached fixture.
static func restore_disposable_candidate(fixture: Dictionary, record: Dictionary, field: Dictionary,
		world: Dictionary, source_hashes: Dictionary, future_tick_count: int) -> Dictionary:
	var preflight: Dictionary = validate_record(record, fixture, field, world, source_hashes, future_tick_count)
	if not preflight.get("ok", false):
		return preflight
	var player: Node = fixture.player
	var manager: Node = fixture.manager
	# Restore controller locals first. A controller-specific refusal must happen before any
	# physical session or manager clock has changed. restore_state refusals are rolled back below.
	var original_controller_states: Array[Dictionary] = []
	for agent: Node in manager.agents:
		var captured: Dictionary = capture_controller_state(agent, source_hashes)
		if not captured.get("ok", false):
			return {ok = false, reason = "fresh companion controller cannot be staged"}
		original_controller_states.append(captured.state)
	var initial_sessions: Array[Dictionary] = [_session_backup(player)]
	for agent: Node in manager.agents:
		initial_sessions.append(_session_backup(agent.session))
	var initial_manager := {
		"accepted_ticks": manager.accepted_ticks,
		"observation_batches": manager.observation_batches,
		"snapshot_tick": manager._snapshot_tick,
		"snapshot": manager._snapshot.duplicate(true),
		"removed": manager._removed,
		"damage_dirty": manager._damage_dirty,
	}
	var restored_controllers := 0
	for index in manager.agents.size():
		var controller_result: Dictionary = _restore_controller_state(
			manager.agents[index], record.roster[index].agent_state.controller_state)
		if not controller_result.get("ok", false):
			var rollback_ok: bool = bool(controller_result.get("rollback_ok", false))
			for rollback_index in range(restored_controllers - 1, -1, -1):
				var rollback: Dictionary = _restore_controller_state(manager.agents[rollback_index],
					original_controller_states[rollback_index])
				rollback_ok = rollback_ok and bool(rollback.get("ok", false))
			return {ok = false, reason = "companion controller restore refused before session mutation; discard candidate",
				controller_rollback_ok = rollback_ok}
		restored_controllers += 1
	var player_record: Dictionary = record.player
	if not player.restore_checkpoint(player_record.session_checkpoint):
		return _rollback_candidate_restore(fixture, initial_sessions, original_controller_states,
			restored_controllers, initial_manager, "fresh player FlightSession refused its checkpoint")
	if not player.sim.paused or player.input_enabled \
			or player.pause_reason != "checkpoint restored (recorded inputs)":
		return _rollback_candidate_restore(fixture, initial_sessions, original_controller_states,
			restored_controllers, initial_manager, "FlightSession restore did not enter paused recorded-input mode")
	_restore_session_controls(player, player_record.controls)
	for index in manager.agents.size():
		var agent: Node = manager.agents[index]
		var saved: Dictionary = record.roster[index]
		if not agent.session.restore_checkpoint(saved.session_checkpoint):
			return _rollback_candidate_restore(fixture, initial_sessions, original_controller_states,
				restored_controllers, initial_manager, "fresh companion-%d refused its checkpoint" % index)
		if not agent.session.sim.paused or agent.session.input_enabled \
				or agent.session.pause_reason != "checkpoint restored (recorded inputs)":
			return _rollback_candidate_restore(fixture, initial_sessions, original_controller_states,
				restored_controllers, initial_manager, "companion-%d did not enter paused recorded-input mode" % index)
		_restore_session_controls(agent.session, saved.controls)
	# All potentially refusing physical restores have succeeded. Apply the plain agent/manager
	# dictionaries only after that boundary so a later session refusal cannot leave half a roster.
	for index in manager.agents.size():
		var agent: Node = manager.agents[index]
		var saved: Dictionary = record.roster[index]
		var local_state: Dictionary = saved.agent_state
		agent.failure = local_state.failure
		agent._last_command = local_state.last_command.duplicate(true)
		agent._accepted_trim = local_state.accepted_trim.duplicate(true)
		agent._weather_rms = local_state.weather_rms.duplicate()
	manager.accepted_ticks = record.manager_state.accepted_ticks
	manager.observation_batches = record.manager_state.observation_batches
	manager._snapshot_tick = record.manager_state.snapshot_tick
	manager._snapshot.clear()
	manager._removed = record.manager_state.removed
	manager._damage_dirty = record.manager_state.damage_dirty
	return {ok = true}


static func _session_backup(session: Node) -> Dictionary:
	return {
		"checkpoint": session.checkpoint(),
		"controls": _session_controls(session),
		"paused": session.sim.paused,
		"pause_reason": session.pause_reason,
	}


static func _rollback_candidate_restore(fixture: Dictionary, session_backups: Array[Dictionary],
		controller_backups: Array[Dictionary], restored_controllers: int,
		manager_backup: Dictionary, reason: String) -> Dictionary:
	var rollback_ok := true
	var sessions: Array[Node] = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	for index in range(sessions.size() - 1, -1, -1):
		var session: Node = sessions[index]
		var backup: Dictionary = session_backups[index]
		var restored: bool = session.restore_checkpoint(backup.checkpoint)
		if restored:
			_restore_session_controls(session, backup.controls)
			session.sim.set_paused(backup.paused)
			session.pause_reason = backup.pause_reason
		rollback_ok = rollback_ok and restored
	for index in range(restored_controllers - 1, -1, -1):
		var controller: Dictionary = _restore_controller_state(fixture.manager.agents[index], controller_backups[index])
		rollback_ok = rollback_ok and bool(controller.get("ok", false))
	fixture.manager.accepted_ticks = manager_backup.accepted_ticks
	fixture.manager.observation_batches = manager_backup.observation_batches
	fixture.manager._snapshot_tick = manager_backup.snapshot_tick
	fixture.manager._snapshot = manager_backup.snapshot.duplicate(true)
	fixture.manager._removed = manager_backup.removed
	fixture.manager._damage_dirty = manager_backup.damage_dirty
	return {ok = false, reason = reason + "; discarded staged candidate", rollback_ok = rollback_ok}


static func controller_state(agent: Node, source_hashes: Dictionary) -> Dictionary:
	return capture_controller_state(agent, source_hashes).get("state", {})


static func capture_controller_state(agent: Node, source_hashes: Dictionary) -> Dictionary:
	var pilot: Object = agent.pilot
	var script: Script = pilot.get_script()
	var script_path: String = str(script.resource_path) if script != null else ""
	var source_hash: String = str(source_hashes.get(script_path, ""))
	if not _source_file_matches(script_path, source_hash):
		return {ok = false, reason = "controller source hash is missing or stale"}
	var has_capture: bool = pilot.has_method("snapshot_state")
	var has_restore: bool = pilot.has_method("restore_state")
	if has_capture or has_restore:
		if not has_capture or not has_restore:
			return {ok = false, reason = "controller must provide both snapshot_state and restore_state"}
		var method_state: Variant = pilot.call("snapshot_state")
		if not method_state is Dictionary or not _serializable_controller_state(method_state):
			return {ok = false, reason = "controller snapshot_state must return a bounded Variant-only Dictionary"}
		return {ok = true, state = {
			"format": "controller-method-state v1", "script_path": script_path,
			"source_sha256": source_hash, "state": method_state.duplicate(true),
		}}
	if script_path != "res://ai/companions/pilot.gd" or source_hash != BASE_PILOT_SOURCE_SHA256:
		return {ok = false, reason = "mutable controller has no explicit checkpoint methods"}
	var fields: Dictionary = _base_pilot_state(pilot)
	if not exact_keys(fields, PILOT_KEYS):
		return {ok = false, reason = "base pilot field schema changed; add checkpoint methods"}
	return {ok = true, state = {
		"format": "base-pilot-fields v1", "script_path": script_path,
		"source_sha256": source_hash, "state": fields,
	}}


static func _agent_state_valid(agent: Node, value: Dictionary, source_hashes: Dictionary) -> bool:
	if not exact_keys(value, ["failure", "last_command", "accepted_trim", "weather_rms", "controller_state"]):
		return false
	if typeof(value.failure) != TYPE_STRING or not value.failure.is_empty() \
			or not value.last_command is Dictionary or not packet_valid(value.last_command) \
			or not value.accepted_trim is Dictionary or not _accepted_trim_valid(value.accepted_trim, agent) \
			or not value.weather_rms is PackedFloat64Array or value.weather_rms.size() != 3:
		return false
	for component: float in value.weather_rms:
		if not is_finite(component) or component < 0.0:
			return false
	var controller: Variant = value.controller_state
	if not controller is Dictionary or not exact_keys(controller, ["format", "script_path", "source_sha256", "state"]):
		return false
	var pilot: Object = agent.pilot
	var script: Script = pilot.get_script()
	var script_path: String = str(script.resource_path) if script != null else ""
	var actual_hash: String = str(source_hashes.get(script_path, ""))
	if controller.script_path != script_path or controller.source_sha256 != actual_hash \
			or not _source_file_matches(script_path, actual_hash) or not controller.state is Dictionary \
			or not _serializable_controller_state(controller.state):
		return false
	if controller.format == "base-pilot-fields v1":
		if script_path != "res://ai/companions/pilot.gd" or actual_hash != BASE_PILOT_SOURCE_SHA256 \
				or not exact_keys(controller.state, PILOT_KEYS):
			return false
		for key: String in PILOT_KEYS:
			if typeof(controller.state[key]) != typeof(pilot.get(key)):
				return false
		if var_to_bytes(controller.state) != var_to_bytes(_base_pilot_state(pilot)):
			return false # The current base pilot's locals are configuration-only and must match fresh setup.
		return true
	if controller.format == "controller-method-state v1":
		return pilot.has_method("snapshot_state") and pilot.has_method("restore_state")
	return false


static func _restore_controller_state(agent: Node, controller: Dictionary) -> Dictionary:
	if controller.format == "controller-method-state v1":
		if not agent.pilot.has_method("snapshot_state") or not agent.pilot.has_method("restore_state"):
			return {ok = false, rollback_ok = true}
		var before: Variant = agent.pilot.call("snapshot_state")
		if not before is Dictionary or not _serializable_controller_state(before):
			return {ok = false, rollback_ok = false}
		var result: Variant = agent.pilot.call("restore_state", controller.state.duplicate(true))
		if result is Dictionary and typeof(result.get("ok")) == TYPE_BOOL and result.ok:
			return {ok = true, rollback_ok = true}
		# Third-party/controller candidates may mutate before refusing. Restore their exact
		# pre-call snapshot before returning; the disposable fixture is still discarded on error.
		var rollback: Variant = agent.pilot.call("restore_state", before.duplicate(true))
		var rollback_ok: bool = rollback is Dictionary and typeof(rollback.get("ok")) == TYPE_BOOL and rollback.ok
		return {ok = false, rollback_ok = rollback_ok}
	if controller.format != "base-pilot-fields v1" or not exact_keys(controller.state, PILOT_KEYS):
		return {ok = false, rollback_ok = true}
	for key: String in PILOT_KEYS:
		agent.pilot.set(key, controller.state[key])
	return {ok = var_to_bytes(_base_pilot_state(agent.pilot)) == var_to_bytes(controller.state), rollback_ok = true}


static func _base_pilot_state(pilot: Object) -> Dictionary:
	var state: Dictionary = {}
	for key: String in PILOT_KEYS:
		state[key] = pilot.get(key)
	return state


static func _fresh_fixture_refusal(fixture: Dictionary) -> String:
	if not fixture.has_all(["player", "manager"]) or not fixture.player is Node or not fixture.manager is Node:
		return "restore target must contain a player and manager Node"
	var player: Node = fixture.player
	var manager: Node = fixture.manager
	if player.is_inside_tree() or manager.is_inside_tree() or player.get_parent() != null or manager.get_parent() != null:
		return "restore target must be detached from every scene tree"
	if manager._player != player or player.sim == null or player.sim.tick != 0 or player.sim.paused \
			or player.external_driver_enabled or player.input_enabled:
		return "restore target player/manager ownership or fresh tick-zero state is invalid"
	if manager.accepted_ticks != 0 or manager.observation_batches != 0 or manager._snapshot_tick != -1 \
			or manager._removed or not manager._snapshot.is_empty() or manager.agents.size() != COMPANION_COUNT:
		return "restore target manager is not a fresh fixed-roster instance"
	for index in COMPANION_COUNT:
		var agent: Node = manager.agents[index]
		if agent.get_parent() != manager or agent.is_inside_tree() or agent.slot_id != index \
				or agent.session == null or agent.session.get_parent() != agent or agent.session.is_inside_tree() \
				or agent.session.sim == null or agent.session.sim.tick != 0 or agent.session.sim.paused \
				or not agent.session.external_driver_enabled or agent.session.input_enabled \
				or not agent.failure.is_empty() or not agent._last_command.is_empty() \
				or not _session_boundary_refusal(agent.session, true).is_empty():
			return "restore target companion-%d is not fresh, detached, and externally driven" % index
	if not _session_boundary_refusal(player, false).is_empty():
		return "restore target player is not a healthy fresh session"
	return ""


static func _environment_context(fixture: Dictionary) -> Dictionary:
	if not fixture.has_all(["player", "manager"]) or not fixture.player is Node or not fixture.manager is Node:
		return {}
	var player_context: Dictionary = _session_environment(fixture.player)
	if player_context.is_empty():
		return {}
	var companion_contexts: Array = []
	if fixture.manager.agents.size() != COMPANION_COUNT:
		return {}
	for index in COMPANION_COUNT:
		var agent: Node = fixture.manager.agents[index]
		var context: Dictionary = _session_environment(agent.session)
		if context.is_empty():
			return {}
		companion_contexts.append({"stable_id": "companion-%d" % index, "context": context})
	return {"player": player_context, "companions": companion_contexts}


static func _session_environment(session: Node) -> Dictionary:
	if session == null or not session.has_method("weather_configuration") \
			or not session.has_method("lake_context") or not session.has_method("collision_world") \
			or session.environment == null or not session.environment.surfaces is PackedFloat64Array:
		return {}
	var weather: Variant = session.weather_configuration()
	var lake: Variant = session.lake_context()
	var world: Variant = session.collision_world()
	if not weather is Dictionary or not lake is Dictionary or not world is Dictionary:
		return {}
	return {
		"weather": weather.duplicate(true),
		"lake_identity": str(lake.get("identity", "")),
		"surface_table_sha256": _hash_bytes(session.environment.surfaces.to_byte_array()),
		"collision_world_identity": str(world.get("identity", "")),
	}


static func _source_manifest_is_current(source_hashes: Dictionary) -> bool:
	if source_hashes.is_empty() or source_hashes.size() > MAX_SOURCE_FILES:
		return false
	var expected_paths: Array[String] = []
	for directory: String in SOURCE_CODE_DIRS:
		_collect_source_files(directory, ".gd", expected_paths)
	for directory: String in SOURCE_DATA_DIRS:
		_collect_source_files(directory, ".json", expected_paths)
	for path: String in SOURCE_ROOT_FILES + SOURCE_EXTRA_FILES:
		expected_paths.append(path)
	expected_paths.sort()
	if expected_paths.size() != source_hashes.size() or expected_paths.size() > MAX_SOURCE_FILES:
		return false
	for path: String in expected_paths:
		if not source_hashes.has(path):
			return false
		var expected_hash: Variant = source_hashes[path]
		if typeof(expected_hash) != TYPE_STRING or not _source_file_matches(path, expected_hash):
			return false
	return true


static func _collect_source_files(directory: String, extension: String, paths: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(extension):
			paths.append(directory.path_join(file_name))
	for child: String in DirAccess.get_directories_at(directory):
		_collect_source_files(directory.path_join(child), extension, paths)


static func _source_file_matches(path: String, expected_hash: String) -> bool:
	if not path.begins_with("res://") or expected_hash.length() != 64 or not FileAccess.file_exists(path):
		return false
	for at in expected_hash.length():
		if expected_hash[at] not in "0123456789abcdef":
			return false
	return FileAccess.get_sha256(path) == expected_hash


static func _serializable_controller_state(value: Dictionary) -> bool:
	var budget: Array[int] = [MAX_CONTROLLER_STATE_NODES, MAX_CONTROLLER_STATE_BYTES]
	if not _serializable_variant(value, 0, budget):
		return false
	return var_to_bytes(value).size() <= MAX_CONTROLLER_STATE_BYTES


static func _serializable_variant(value: Variant, depth: int, budget: Array[int]) -> bool:
	if depth > MAX_CONTROLLER_STATE_DEPTH or budget.size() != 2 or budget[0] <= 0 or budget[1] < 0:
		return false
	budget[0] -= 1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			budget[1] -= 16
			return true
		TYPE_FLOAT:
			budget[1] -= 16
			return is_finite(float(value))
		TYPE_STRING:
			if str(value).length() > MAX_CONTROLLER_STRING_BYTES:
				return false
			var string_bytes: int = str(value).to_utf8_buffer().size()
			budget[1] -= string_bytes + 16
			return string_bytes <= MAX_CONTROLLER_STRING_BYTES and budget[1] >= 0
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.size() > MAX_CONTROLLER_STATE_NODES:
				return false
			var element_bytes: int = 1 if typeof(value) == TYPE_PACKED_BYTE_ARRAY else (4 if typeof(value) == TYPE_PACKED_INT32_ARRAY else 8)
			if typeof(value) == TYPE_PACKED_STRING_ARRAY:
				element_bytes = 16
				for item: String in value:
					if item.length() > MAX_CONTROLLER_STRING_BYTES:
						return false
					budget[1] -= item.to_utf8_buffer().size()
			budget[1] -= value.size() * element_bytes + 16
			return budget[1] >= 0
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if value.size() > MAX_CONTROLLER_STATE_NODES:
				return false
			for component: float in value:
				if not is_finite(component):
					return false
			budget[1] -= value.size() * (4 if typeof(value) == TYPE_PACKED_FLOAT32_ARRAY else 8) + 16
			return budget[1] >= 0
		TYPE_ARRAY:
			if value.size() > MAX_CONTROLLER_STATE_NODES:
				return false
			budget[1] -= value.size() * 8 + 16
			for child: Variant in value:
				if not _serializable_variant(child, depth + 1, budget):
					return false
			return budget[1] >= 0
		TYPE_DICTIONARY:
			if value.size() > MAX_CONTROLLER_STATE_NODES:
				return false
			budget[1] -= value.size() * 16 + 16
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or str(key).length() > MAX_CONTROLLER_STRING_BYTES:
					return false
				var key_bytes: int = str(key).to_utf8_buffer().size()
				budget[1] -= key_bytes
				if budget[1] < 0 or not _serializable_variant(value[key], depth + 1, budget):
					return false
			return budget[1] >= 0
	return false


static func _session_boundary_refusal(session: Node, is_agent: bool) -> String:
	if session.sim == null or session.sim.paused:
		return "session is paused or missing"
	if not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or not session.prop_strike.is_empty():
		return "session has a fault, crash or prop strike"
	if not session.holds.is_empty() or not session._flight_ready():
		return "session has a hold or is not flight-ready"
	if session._external_packet_ready or not session._external_pending_packet.is_empty():
		return "session has a staged external packet"
	if session._pending_crash != null or not session._pending_crash_state.is_empty():
		return "session has a pending crash decision"
	if not session.scenery_damage().is_empty() or not session._pending_scenery_damage.is_empty() \
			or session._pending_scenery_tick != -1 or session._last_scenery_event != null or session._last_lake_event != null:
		return "shared world/contact aftermath is outside this proof"
	if is_agent != session.external_driver_enabled:
		return "driver mode does not match fixed roster"
	return ""


static func _aligned(fixture: Dictionary, expected_tick: int) -> bool:
	var player: Node = fixture.player
	var manager: Node = fixture.manager
	if player.sim.tick != expected_tick or manager.accepted_ticks != expected_tick \
			or manager._snapshot_tick != -1 or manager._removed or manager.agents.size() != COMPANION_COUNT:
		return false
	for index in manager.agents.size():
		var agent: Node = manager.agents[index]
		if agent.slot_id != index or agent.session.sim.tick != expected_tick or not agent.failure.is_empty() \
				or not agent.session.crash.is_empty() or not agent.session._flight_ready():
			return false
	return true


static func _session_controls(session: Node) -> Dictionary:
	return {
		"commands": session.commands.duplicate(true),
		"raw": session.raw.duplicate(true),
		"trims": session.trims.duplicate(true),
		"rate_profile": session.rate_profile,
		"input_enabled": session.input_enabled,
		"external_driver_enabled": session.external_driver_enabled,
		"holds": session.holds.duplicate(true),
		"crash_auto_restart": session.crash_auto_restart,
		"pause_reason": session.pause_reason,
		"gear_requested_down": session._gear_requested_down,
		"gear_request_inhibited": session._gear_request_inhibited,
		"wheel_brake_demand": session._wheel_brake_demand,
		"flap_requested": session._flap_requested,
	}


static func _agent_state(agent: Node, controller_state: Dictionary) -> Dictionary:
	return {
		"failure": agent.failure,
		"last_command": agent._last_command.duplicate(true),
		"accepted_trim": agent._accepted_trim.duplicate(true),
		"weather_rms": agent._weather_rms.duplicate(),
		"controller_state": controller_state.duplicate(true),
	}


static func _session_record_valid(saved: Dictionary, expected_id: String, tick: int, session: Node) -> bool:
	if not saved.has_all(["stable_id", "local_tick", "session_checkpoint", "controls"]) \
			or (expected_id == "player" and not exact_keys(saved, ["stable_id", "local_tick", "session_checkpoint", "controls"])) \
			or saved.get("stable_id") != expected_id or typeof(saved.get("local_tick")) != TYPE_INT \
			or saved.local_tick != tick or not saved.get("session_checkpoint") is Dictionary \
			or not saved.get("controls") is Dictionary:
		return false
	var checkpoint: Dictionary = saved.session_checkpoint
	if typeof(checkpoint.get("format")) != TYPE_STRING or typeof(checkpoint.get("configuration")) != TYPE_STRING \
			or checkpoint.configuration.length() != 64 or not checkpoint.get("simulation") is Dictionary \
			or typeof(checkpoint.simulation.get("tick")) != TYPE_INT or checkpoint.simulation.tick != tick:
		return false
	var controls: Dictionary = saved.controls
	if not exact_keys(controls, CONTROL_KEYS):
		return false
	return _control_dictionary_valid(controls.commands) and _control_dictionary_valid(controls.raw) \
			and _trim_dictionary_valid(controls.trims, session.trims) \
			and typeof(controls.rate_profile) == TYPE_STRING and controls.rate_profile in ["full", "normal"] \
			and typeof(controls.input_enabled) == TYPE_BOOL and not controls.input_enabled \
			and typeof(controls.external_driver_enabled) == TYPE_BOOL \
			and controls.external_driver_enabled == (expected_id != "player") \
			and controls.holds is Dictionary and controls.holds.is_empty() \
			and typeof(controls.crash_auto_restart) == TYPE_BOOL \
			and typeof(controls.pause_reason) == TYPE_STRING and controls.pause_reason.is_empty() \
			and typeof(controls.gear_requested_down) == TYPE_BOOL \
			and typeof(controls.gear_request_inhibited) == TYPE_BOOL \
			and typeof(controls.wheel_brake_demand) in [TYPE_FLOAT, TYPE_INT] \
			and is_finite(float(controls.wheel_brake_demand)) and float(controls.wheel_brake_demand) >= 0.0 \
			and float(controls.wheel_brake_demand) <= 1.0 \
			and typeof(controls.flap_requested) in [TYPE_FLOAT, TYPE_INT] \
			and is_finite(float(controls.flap_requested)) and float(controls.flap_requested) >= 0.0 \
			and float(controls.flap_requested) <= 1.0


static func _control_dictionary_valid(values: Variant) -> bool:
	if not values is Dictionary or not exact_keys(values, ["roll", "pitch", "yaw", "throttle"]):
		return false
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(values[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[key])):
			return false
	return float(values.roll) >= -1.0 and float(values.roll) <= 1.0 \
			and float(values.pitch) >= -1.0 and float(values.pitch) <= 1.0 \
			and float(values.yaw) >= -1.0 and float(values.yaw) <= 1.0 \
			and float(values.throttle) >= 0.0 and float(values.throttle) <= 1.0


static func _trim_dictionary_valid(values: Variant, expected: Dictionary) -> bool:
	if not values is Dictionary or not exact_keys(values, ["roll", "pitch", "yaw"]) \
			or var_to_bytes(values) != var_to_bytes(expected):
		return false
	for key: String in ["roll", "pitch", "yaw"]:
		if typeof(values[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[key])) \
				or float(values[key]) < -1.0 or float(values[key]) > 1.0:
			return false
	return true


static func _accepted_trim_valid(values: Dictionary, agent: Node) -> bool:
	if not exact_keys(values, ["roll", "pitch", "yaw", "throttle", "speed_m_s"]) \
			or var_to_bytes(values) != var_to_bytes(agent._accepted_trim):
		return false
	for key: String in ["roll", "pitch", "yaw", "throttle", "speed_m_s"]:
		if typeof(values[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[key])):
			return false
	return float(values.roll) >= -1.0 and float(values.roll) <= 1.0 \
			and float(values.pitch) >= -1.0 and float(values.pitch) <= 1.0 \
			and float(values.yaw) >= -1.0 and float(values.yaw) <= 1.0 \
			and float(values.throttle) >= 0.0 and float(values.throttle) <= 1.0 \
			and float(values.speed_m_s) >= 10.0 and float(values.speed_m_s) <= 25.0


static func _restore_session_controls(session: Node, controls: Dictionary) -> void:
	session.commands = controls.commands.duplicate(true)
	session.raw = controls.raw.duplicate(true)
	session.trims = controls.trims.duplicate(true)
	session.rate_profile = str(controls.rate_profile)
	session.input_enabled = false
	session.external_driver_enabled = bool(controls.external_driver_enabled)
	session.holds = controls.holds.duplicate(true)
	session.crash_auto_restart = bool(controls.crash_auto_restart)
	session._gear_requested_down = bool(controls.gear_requested_down)
	session._gear_request_inhibited = bool(controls.gear_request_inhibited)
	session._wheel_brake_demand = float(controls.wheel_brake_demand)
	session._flap_requested = float(controls.flap_requested)
	# Restore intentionally enters paused recorded-input mode; caller unpauses only offline after checks.
	session.pause_reason = ""


static func packet_valid(packet: Variant) -> bool:
	if not packet is Dictionary or not exact_keys(packet, ["roll", "pitch", "yaw", "throttle"]):
		return false
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(packet[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(packet[key])):
			return false
	return float(packet.roll) >= -1.0 and float(packet.roll) <= 1.0 \
			and float(packet.pitch) >= -1.0 and float(packet.pitch) <= 1.0 \
			and float(packet.yaw) >= -1.0 and float(packet.yaw) <= 1.0 \
			and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0


static func exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _hash_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _limitations_valid(limitations: Array) -> bool:
	if limitations.is_empty() or limitations.size() > MAX_LIMITATIONS:
		return false
	for limitation: Variant in limitations:
		if typeof(limitation) != TYPE_STRING or limitation.is_empty() \
				or limitation.to_utf8_buffer().size() > MAX_LIMITATION_BYTES:
			return false
	return true
