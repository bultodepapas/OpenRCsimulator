## AFC-02 black-box checks for bounded fleet capture and per-session replay.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")

const TEST_SEED := 20261020
const PARITY_TICKS := 260

var _checks := 0
var _failures := 0
var _temp_root := ""
var _out_path := ""
var _measurements: Array = []
var _field: Dictionary = {}
var _world: Dictionary = {}


func _initialize() -> void:
	# AFC-02-R3: a logic suite; tests/test_companions_profiles.gd alone gates the pinned solver identity.
	preload("res://ai/companions/profile_loader.gd").accept_current_solver_for_tests()
	_temp_root = ProjectSettings.globalize_path("res://../tmp/afc02-companions-record-%d" % Time.get_ticks_usec())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out_path = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_temp_root)
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _run() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("Club field loads", loaded_field.get("ok", false), str(loaded_field.get("errors", [])))
	if not loaded_field.get("ok", false):
		_finish()
		return
	_field = loaded_field.field
	var loaded_scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, _field)
	_check("Club field scenery loads", loaded_scenery.get("ok", false), str(loaded_scenery.get("errors", [])))
	if not loaded_scenery.get("ok", false):
		_finish()
		return
	var built: Dictionary = CollisionWorld.build(_field, loaded_scenery.scenery)
	_check("Club field collision world builds", built.get("ok", false), str(built.get("errors", [])))
	if not built.get("ok", false):
		_finish()
		return
	_world = built.world
	_run_start_refusals()
	_run_four_stream_capture()
	_run_recorded_parity_and_replay()
	_run_remove_and_reset_finalization()
	_run_refused_reconfigure_preserves_capture()
	_run_reconfigure_finalization()
	await _run_world_mutation_incomplete()
	_run_writer_failure()
	_run_crash_incomplete()
	await _run_deferred_fault()
	_run_tree_exit_finalization()
	_run_detached_manager_free()
	_finish()


func _requested_config() -> Dictionary:
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = 1
	config.seed = TEST_SEED
	return config


func _new_fixture(companion_count: int = 1, enter_manager_tree: bool = true) -> Dictionary:
	var player: FlightSession = FlightSession.new()
	player.input_enabled = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("player starts flyable", player.is_flyable())
	_check("Club field installs", player.set_field(_field), player.surface_error)
	player.reset()
	_check("collision world installs", player.set_collision_world(_world))
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	root.add_child(player)
	var manager: Node = Manager.new()
	var config: Dictionary = _requested_config()
	config.count = companion_count
	var configured: Dictionary = manager.configure(player, _field, "club_field", config, false, false)
	_check("one-aircraft fleet configures at tick zero", configured.get("ok", false), str(configured))
	if enter_manager_tree:
		root.add_child(manager)
	return {player = player, manager = manager}


func _dispose_fixture(fixture: Dictionary) -> void:
	var manager: Node = fixture.get("manager")
	var player: Node = fixture.get("player")
	if is_instance_valid(manager):
		if manager.has_method("stop_recording"):
			manager.stop_recording("test cleanup")
		if manager.has_method("remove_now"):
			manager.remove_now()
		if manager.is_inside_tree():
			root.remove_child(manager)
		manager.free()
	if is_instance_valid(player):
		if player.is_inside_tree():
			root.remove_child(player)
		player.free()


func _step(player: FlightSession, tick: int) -> bool:
	var segment: int = (tick / 30) % 4
	var rolls: Array[float] = [-0.06, 0.0, 0.06, 0.0]
	var pitches: Array[float] = [0.0, 0.025, 0.0, -0.025]
	player.commands = {roll = rolls[segment], pitch = pitches[segment], yaw = 0.0, throttle = 0.56}
	player.raw = player.commands.duplicate()
	player.sim.inputs = player._inputs()
	if not player._session_after_input():
		return false
	player.sim.step()
	return player.sim.tick > tick


func _same_f64(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return left.to_byte_array() == right.to_byte_array()


func _session_bytes(session: FlightSession) -> PackedByteArray:
	return var_to_bytes([session.sim.tick, session.sim.state, session.sim.previous, session.sim.aux,
		session.sim.inputs, session.sim.continuous, session.sim.modes, session.sim.last_loads])


func _manager_matches(left: Node, right: Node) -> bool:
	if left.agents.size() != right.agents.size():
		return false
	for index in left.agents.size():
		if _session_bytes(left.agents[index].session) != _session_bytes(right.agents[index].session):
			return false
	return true


func _recording(manager: Node) -> Dictionary:
	var state: Dictionary = manager.status().get("recording", {})
	return state


func _run_start_refusals() -> void:
	var fixture := _new_fixture()
	var manager: Node = fixture.manager
	for bad_limit in [0, 28801]:
		var path: String = _temp_root.path_join("invalid-limit-%d" % bad_limit)
		var result: Dictionary = manager.start_recording(path, bad_limit)
		_check("invalid max_ticks %d is refused" % bad_limit, not result.get("ok", true), str(result))
		_check("invalid max_ticks allocates no capture directory", not DirAccess.dir_exists_absolute(path))
	_check("recording is explicit opt-in", not _recording(manager).get("active", true))
	var occupied: String = _temp_root.path_join("occupied")
	DirAccess.make_dir_absolute(occupied)
	var sentinel := FileAccess.open(occupied.path_join("keep.txt"), FileAccess.WRITE)
	sentinel.store_string("preserve")
	sentinel.close()
	var preserved := FileAccess.get_file_as_bytes(occupied.path_join("keep.txt"))
	var existing: Dictionary = manager.start_recording(occupied)
	_check("pre-existing directory is refused", not existing.get("ok", true), str(existing))
	_check("pre-existing bytes remain unchanged", FileAccess.get_file_as_bytes(occupied.path_join("keep.txt")) == preserved)
	_check("refusals leave capture inactive", not _recording(manager).get("active", true))
	# A nonzero player tick cannot create a capture; reset and reconfigure restore the fixture.
	_check("one refusal fixture tick accepted", _step(fixture.player, 0))
	var nonzero_path: String = _temp_root.path_join("nonzero-start")
	var nonzero: Dictionary = manager.start_recording(nonzero_path)
	_check("nonzero start tick is refused", not nonzero.get("ok", true), str(nonzero))
	_check("nonzero start creates no capture", not DirAccess.dir_exists_absolute(nonzero_path))
	fixture.player.reset()
	var rebuilt: Dictionary = manager.configure(fixture.player, _field, "club_field", _requested_config(), false, false)
	_check("fleet can be rebuilt after refused nonzero start", rebuilt.get("ok", false), str(rebuilt))
	# The inclusive lower bound is a valid one-tick capture and stops on its accepted end tick.
	var one_tick_path: String = _temp_root.path_join("minimum-limit")
	var minimum: Dictionary = manager.start_recording(one_tick_path, 1)
	_check("max_ticks=1 is accepted", minimum.get("ok", false), str(minimum))
	_check("minimum-limit tick accepted", _step(fixture.player, 0))
	_check("max_ticks=1 closes on tick one", not _recording(manager).get("active", true)
		and _recording(manager).get("complete", false) and _recording(manager).get("last_tick", -1) == 1,
		str(_recording(manager)))
	_check("minimum-limit capture has initial and final rows", _inspect_stream(one_tick_path.path_join("player.orfl"), 2, 1))
	_dispose_fixture(fixture)


func _run_four_stream_capture() -> void:
	var fixture := _new_fixture(3)
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("four-stream-cap")
	var started: Dictionary = manager.start_recording(directory, 10)
	_check("three companions fit the fixed four-stream capture cap", started.get("ok", false), str(started))
	var manifest: Dictionary = _read_json(directory.path_join("manifest.json"))
	_check("four-stream manifest fixes roster and stream limit", manifest.get("roster", []).size() == 4
		and manifest.get("max_streams", -1) == 4)
	var aligned := true
	for tick in 3:
		aligned = _step(player, tick) and aligned
		aligned = aligned and fixture.manager.status().ticks == tick + 1
		for agent: Node in manager.agents:
			aligned = aligned and agent.session.sim.tick == player.sim.tick
	_check("all three companions share each accepted player tick", aligned)
	var stopped: Dictionary = manager.stop_recording("four-stream clock check")
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("all four streams close at one common tick", stopped.get("complete", false)
		and _summary_has_common_extent(summary, 3, 4)
		and _summary_hashes_match(summary, directory, 3, 4, 4), str(summary))
	var files := ["player.orfl", "companion-0.orfl", "companion-1.orfl", "companion-2.orfl"]
	var logs_valid := true
	for file_name: String in files:
		logs_valid = FileAccess.file_exists(directory.path_join(file_name)) and logs_valid
		logs_valid = _inspect_stream(directory.path_join(file_name), 4, 3) and logs_valid
	_check("four-stream capture preserves existing per-session ORFL files", logs_valid)
	_dispose_fixture(fixture)


func _run_recorded_parity_and_replay() -> void:
	var recorded := _new_fixture()
	var baseline := _new_fixture()
	var manager: Node = recorded.manager
	var player: FlightSession = recorded.player
	var directory: String = _temp_root.path_join("parity-capture")
	_check("fleet configuration does not allocate a recorder", manager._record == null)
	var started: Dictionary = manager.start_recording(directory)
	_check("capture starts only after explicit request", started.get("ok", false), str(started))
	_check("capture status is active", _recording(manager).get("active", false), str(_recording(manager)))
	_check("default capture duration uses the 28,800-tick bound", _recording(manager).get("max_ticks", -1) == 28800)
	var manifest_path: String = directory.path_join("manifest.json")
	_check("manifest exists at capture start", FileAccess.file_exists(manifest_path))
	var manifest_bytes := FileAccess.get_file_as_bytes(manifest_path)
	var manifest: Dictionary = _read_json(manifest_path)
	_check("manifest format and initial incomplete state", manifest.get("format") == "openrc-companion-capture v1"
		and manifest.get("complete") == false, str(manifest))
	_check("manifest starts at global tick zero and declares 240 Hz", _manifest_has_global_clock(manifest), str(manifest))
	_check("manifest records each stream's companion profile identity", _manifest_has_profiles(manifest), str(manifest))
	_check("manifest source hashes match the selected source files", _manifest_source_hashes_match(manifest), str(manifest.get("source_sha256", {})))
	_check("manifest declares fixed stream, file, and row limits",
		manifest.get("max_streams", -1) == 4 and manifest.get("max_bytes_per_stream", -1) == Log.MAX_BYTES
			and manifest.get("max_buffer_rows_per_stream", -1) == Log.CHUNK_TICKS, str(manifest))
	_check("manifest labels replay scope without fleet restore or decisions", _manifest_limits_replay(manifest), str(manifest))
	var attached_status: Dictionary = manager.status()
	var attached_recording: Dictionary = attached_status.recording
	attached_recording.active = false
	attached_recording.last_tick = -987
	_check("recording status is detached", _recording(manager).get("active", false)
		and _recording(manager).get("last_tick", -1) == 0)
	var parity := true
	var pause_stable := true
	var tick_acceptance := true
	for tick in PARITY_TICKS:
		var accepted_recorded: bool = _step(player, tick)
		var accepted_baseline: bool = _step(baseline.player, tick)
		tick_acceptance = tick_acceptance and accepted_recorded and accepted_baseline
		parity = parity and _session_bytes(player) == _session_bytes(baseline.player)
		parity = parity and _manager_matches(recorded.manager, baseline.manager)
		if tick == 79:
			var captured_tick: int = int(_recording(manager).get("last_tick", -1))
			var recorded_before := _session_bytes(player)
			var companion_before := _session_bytes(manager.agents[0].session)
			player.sim.set_paused(true)
			baseline.player.sim.set_paused(true)
			player.sim._physics_process(1.0 / 240.0)
			baseline.player.sim._physics_process(1.0 / 240.0)
			pause_stable = player.sim.tick == 80 and baseline.player.sim.tick == 80 \
				and _session_bytes(player) == recorded_before \
				and _session_bytes(manager.agents[0].session) == companion_before \
				and int(_recording(manager).get("last_tick", -1)) == captured_tick
			player.sim.set_paused(false)
			baseline.player.sim.set_paused(false)
	_check("260 accepted ticks match the unrecorded player and one-agent fleet byte-for-byte", tick_acceptance and parity)
	_check("pause does not advance fleet or capture tick", pause_stable, str(_recording(manager)))
	var stopped: Dictionary = manager.stop_recording("AFC-02 parity capture complete")
	_check("explicit stop completes all streams", stopped.get("complete", false), str(stopped))
	var final_status: Dictionary = _recording(manager)
	_check("capture ends at common tick 260 with 261 rows", not final_status.get("active", true)
		and final_status.get("complete", false) and final_status.get("last_tick", -1) == 260
		and _summary_has_common_extent(final_status.get("summary", {}), 260, 261), str(final_status))
	_check("manifest remains immutable and incomplete after capture", FileAccess.get_file_as_bytes(manifest_path) == manifest_bytes)
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("summary certifies only the contiguous common 260-tick capture", summary.get("complete", false)
		and _summary_has_common_extent(summary, 260, 261), str(summary))
	_check("per-stream hashes and byte sizes match closed logs", _summary_hashes_match(summary, directory), str(summary))
	var detached_summary: Dictionary = manager.status().recording.summary
	detached_summary.streams.clear()
	_check("retained final status summary is detached", _recording(manager).get("summary", {}).get("streams", []).size() == 2)
	var expected_files := ["player.orfl", "companion-0.orfl"]
	var replay_checks := true
	for file_name: String in expected_files:
		var log_path: String = directory.path_join(file_name)
		if not FileAccess.file_exists(log_path) or not _inspect_stream(log_path, 261, 260) or not _bounded_stream(log_path):
			replay_checks = false
			continue
		replay_checks = _replay_stream(log_path) and replay_checks
	_check("one player and one companion stream close at the common tick", replay_checks)
	var preserved := _capture_file_hashes(directory)
	_step(player, PARITY_TICKS)
	_check("stopped recorder callbacks do not append another physics row", _capture_file_hashes(directory) == preserved)
	# Reset to tick zero and reconfigure before checking collision behavior with a fresh capture attempt.
	player.reset()
	var rebuilt: Dictionary = manager.configure(player, _field, "club_field", _requested_config(), false, false)
	_check("fleet rebuilds for no-overwrite check", rebuilt.get("ok", false), str(rebuilt))
	var overwrite: Dictionary = manager.start_recording(directory)
	_check("existing capture directory cannot be overwritten", not overwrite.get("ok", true), str(overwrite))
	_check("all existing capture bytes remain unchanged", _capture_file_hashes(directory) == preserved)
	_check("no callbacks append after stop", _capture_file_hashes(directory) == preserved
		and not _recording(manager).get("active", true))
	_measurements.append({test = "AFC-02 parity", ticks = PARITY_TICKS, files = expected_files,
		player_sha256 = FileAccess.get_sha256(directory.path_join("player.orfl")),
		companion_sha256 = FileAccess.get_sha256(directory.path_join("companion-0.orfl")),
		rows = 261, complete = true})
	_dispose_fixture(recorded)
	_dispose_fixture(baseline)


func _run_remove_and_reset_finalization() -> void:
	var fixture := _new_fixture()
	var manager: Node = fixture.manager
	var player: FlightSession = fixture.player
	var remove_dir: String = _temp_root.path_join("remove-finalizes")
	var started: Dictionary = manager.start_recording(remove_dir)
	_check("remove capture starts", started.get("ok", false), str(started))
	for tick in 3:
		_check("remove fixture tick %d accepted" % (tick + 1), _step(player, tick))
	var remove_tick: int = player.sim.tick
	manager.remove_now()
	_check("remove_now closes a complete common capture before clearing agents",
		manager.agents.is_empty() and not _recording(manager).get("active", true)
			and _recording(manager).get("complete", false) and _recording(manager).get("last_tick", -1) == remove_tick,
		str(_recording(manager)))
	_check("remove summary includes the last accepted tick", _summary_has_common_extent(_read_json(remove_dir.path_join("summary.json")), remove_tick, remove_tick + 1))
	var remove_hashes := _capture_file_hashes(remove_dir)
	_step(player, remove_tick)
	_check("remove leaves no capture callback attached", _capture_file_hashes(remove_dir) == remove_hashes)
	player.reset()
	var rebuilt: Dictionary = manager.configure(player, _field, "club_field", _requested_config(), false, false)
	_check("fleet rebuilds after remove", rebuilt.get("ok", false), str(rebuilt))

	var reset_dir: String = _temp_root.path_join("reset-finalizes")
	started = manager.start_recording(reset_dir)
	_check("reset capture starts", started.get("ok", false), str(started))
	for tick in 4:
		_check("reset fixture tick %d accepted" % (tick + 1), _step(player, tick))
	var reset_tick: int = player.sim.tick
	player.reset()
	_check("session reset closes previous capture before time returns to zero",
		player.sim.tick == 0 and not _recording(manager).get("active", true)
			and _recording(manager).get("complete", false) and _recording(manager).get("last_tick", -1) == reset_tick,
		str(_recording(manager)))
	_check("reset summary preserves only old-flight rows", _summary_has_common_extent(_read_json(reset_dir.path_join("summary.json")), reset_tick, reset_tick + 1))
	_dispose_fixture(fixture)


func _run_reconfigure_finalization() -> void:
	var fixture := _new_fixture()
	var directory: String = _temp_root.path_join("reconfigure-finalizes")
	var started: Dictionary = fixture.manager.start_recording(directory)
	_check("reconfiguration capture starts", started.get("ok", false), str(started))
	var configured: Dictionary = fixture.manager.configure(fixture.player, _field, "club_field", _requested_config(), false, false)
	_check("manager reconfiguration closes old capture after valid candidate setup",
		configured.get("ok", false) and not _recording(fixture.manager).get("active", true)
			and _recording(fixture.manager).get("complete", false) and _recording(fixture.manager).get("last_tick", -1) == 0,
		str(configured) + " " + str(_recording(fixture.manager)))
	_check("reconfiguration summary keeps the initial row", _summary_has_common_extent(_read_json(directory.path_join("summary.json")), 0, 1))
	_dispose_fixture(fixture)


func _run_refused_reconfigure_preserves_capture() -> void:
	var fixture := _new_fixture()
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("refused-reconfigure-preserves")
	var started: Dictionary = manager.start_recording(directory)
	_check("refused-reconfigure capture starts", started.get("ok", false), str(started))
	_check("refused-reconfigure first tick accepted", _step(player, 0))
	var bad_field: Dictionary = _field.duplicate(true)
	bad_field.surfaces[0].center_north += 1.0
	var refused: Dictionary = manager.configure(player, bad_field, "club_field", _requested_config(), false, false)
	_check("refused manager reconfiguration preserves the active capture and roster",
		not refused.get("ok", true) and _recording(manager).get("active", false)
			and manager.agents.size() == 1 and manager.status().ticks == 1, str(refused))
	_check("capture continues after rejected reconfiguration", _step(player, 1))
	var stopped: Dictionary = manager.stop_recording("refused configure remained observational")
	_check("preserved capture can still finish completely", stopped.get("complete", false)
		and _summary_has_common_extent(_read_json(directory.path_join("summary.json")), 2, 3), str(stopped))
	_dispose_fixture(fixture)


func _run_world_mutation_incomplete() -> void:
	var fixture := _new_fixture()
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("world-mutation-incomplete")
	var started: Dictionary = manager.start_recording(directory)
	_check("world-mutation capture starts", started.get("ok", false), str(started))
	for tick in 3:
		_check("world-mutation tick %d accepted" % (tick + 1), _step(player, tick))
	var changed := false
	for proxy: Dictionary in _world.get("proxies", []):
		var profile: String = str(proxy.get("damage_profile", "none"))
		var damage_id: String = str(proxy.get("damage_id", ""))
		if not SceneryDamage.profile_is_valid(profile) or profile == "none" or damage_id.is_empty():
			continue
		var energy: float = SceneryDamage.threshold_j(profile) * 1.1
		player._scenery_damage = {damage_id: {profile = profile,
			state = SceneryDamage.impact_state(profile, energy), tick = player.sim.tick,
			energy_j = energy, point_ned = PackedFloat64Array([proxy.get("north", 0.0),
				proxy.get("east", 0.0), proxy.get("down", 0.0)]),
			normal_ned = PackedFloat64Array([0.0, 0.0, -1.0]),
			velocity_ned = PackedFloat64Array([0.0, 0.0, 1.0]), obstacle_id = str(proxy.get("id", ""))}}
		player.scenery_damage_changed.emit()
		changed = true
		break
	_check("a valid shared scenery-state mutation is observed", changed)
	await process_frame
	var status: Dictionary = _recording(manager)
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("world mutation closes the capture as incomplete", not status.get("active", true)
		and not status.get("complete", true) and not str(status.get("error", "")).is_empty()
		and summary.get("complete") == false, str(status) + " " + str(summary))
	_dispose_fixture(fixture)


func _run_writer_failure() -> void:
	var fixture := _new_fixture()
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("writer-failure-incomplete")
	var started: Dictionary = manager.start_recording(directory)
	_check("writer-failure capture starts", started.get("ok", false), str(started))
	for tick in 4:
		_check("writer-failure tick %d accepted" % (tick + 1), _step(player, tick))
	var recorder: RefCounted = manager._record
	_check("fleet writer has player and companion log streams", recorder._logs.size() == 2)
	if recorder._logs.size() == 2:
		recorder._logs[1]._failed("injected test writer failure", ERR_FILE_CANT_WRITE)
	_step(player, 4)
	var status: Dictionary = _recording(manager)
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("writer failure closes all streams and refuses fleet completion",
		not status.get("active", true) and not status.get("complete", true)
			and not str(status.get("error", "")).is_empty() and summary.get("complete") == false,
		str(status) + " " + str(summary))
	var hashes := _capture_file_hashes(directory)
	_step(player, 5)
	_check("writer-failure cleanup leaves no callbacks changing capture bytes", _capture_file_hashes(directory) == hashes)
	_dispose_fixture(fixture)


func _run_deferred_fault() -> void:
	var fixture := _new_fixture()
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("deferred-fault-incomplete")
	var started: Dictionary = manager.start_recording(directory)
	_check("fault capture starts", started.get("ok", false), str(started))
	var stepped_ticks: Array[int] = []
	var observer := func(tick: int, _time: float, _state: PackedFloat64Array,
			_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		stepped_ticks.append(tick)
	fixture.player.sim.stepped.connect(observer)
	fixture.player.sim._fail_safe("injected no-step fault")
	fixture.player.sim.step()
	_check("faulted player step emits no stepped signal", fixture.player.sim.tick == 0 and stepped_ticks.is_empty())
	await process_frame
	var status: Dictionary = _recording(manager)
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("fault without an accepted step defers closure and marks incomplete",
		not status.get("active", true) and not status.get("complete", true)
			and status.get("last_tick", -1) == 0 and summary.get("complete") == false,
		str(status) + " " + str(summary))
	if fixture.player.sim.stepped.is_connected(observer):
		fixture.player.sim.stepped.disconnect(observer)
	_dispose_fixture(fixture)


func _run_crash_incomplete() -> void:
	var fixture := _new_fixture()
	var player: FlightSession = fixture.player
	var manager: Node = fixture.manager
	# Model the session reporting a crash at the accepted common tick boundary.
	var crash_injector := func(_tick: int, _time: float, _state: PackedFloat64Array,
			_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		player.crash = {why = "injected crash boundary"}
		player.sim.set_paused(true)
	player.sim.stepped.connect(crash_injector)
	var directory: String = _temp_root.path_join("crash-incomplete")
	var started: Dictionary = manager.start_recording(directory)
	_check("crash capture starts", started.get("ok", false), str(started))
	_check("tick containing crash report is accepted", _step(player, 0))
	var status: Dictionary = _recording(manager)
	var summary: Dictionary = _read_json(directory.path_join("summary.json"))
	_check("crash at the accepted boundary closes incomplete", not status.get("active", true)
		and not status.get("complete", true) and status.get("last_tick", -1) == 1
		and summary.get("complete") == false, str(status) + " " + str(summary))
	if player.sim.stepped.is_connected(crash_injector):
		player.sim.stepped.disconnect(crash_injector)
	_dispose_fixture(fixture)


func _run_tree_exit_finalization() -> void:
	var fixture := _new_fixture()
	var manager: Node = fixture.manager
	var directory: String = _temp_root.path_join("tree-exit-finalizes")
	var started: Dictionary = manager.start_recording(directory)
	_check("tree-exit capture starts", started.get("ok", false), str(started))
	for tick in 2:
		_check("tree-exit fixture tick %d accepted" % (tick + 1), _step(fixture.player, tick))
	var final_tick: int = fixture.player.sim.tick
	root.remove_child(manager)
	var status: Dictionary = _recording(manager)
	_check("manager tree exit closes a complete capture before freeing children",
		not status.get("active", true) and status.get("complete", false)
			and status.get("last_tick", -1) == final_tick, str(status))
	_check("tree-exit summary contains final common tick", _summary_has_common_extent(_read_json(directory.path_join("summary.json")), final_tick, final_tick + 1))
	_dispose_fixture(fixture)


func _run_detached_manager_free() -> void:
	var fixture := _new_fixture(1, false)
	var manager: Node = fixture.manager
	var player: FlightSession = fixture.player
	var directory: String = _temp_root.path_join("detached-manager-free")
	var started: Dictionary = manager.start_recording(directory)
	_check("detached manager capture starts", started.get("ok", false), str(started))
	for tick in 2:
		_check("detached-manager tick %d accepted" % (tick + 1), _step(player, tick))
	var record: RefCounted = manager._record
	manager.free()
	var status: Dictionary = record.status()
	_check("freeing a detached manager finalizes before its agents are freed",
		not status.get("active", true) and status.get("complete", false)
			and status.get("last_tick", -1) == 2, str(status))
	_check("detached-manager summary has both complete sessions",
		_summary_has_common_extent(_read_json(directory.path_join("summary.json")), 2, 3))
	var hashes := _capture_file_hashes(directory)
	_step(player, 2)
	_check("detached free disconnects all capture and manager callbacks", _capture_file_hashes(directory) == hashes)
	if player.is_inside_tree():
		root.remove_child(player)
	player.free()


func _inspect_stream(path: String, expected_rows: int, final_tick: int) -> bool:
	var checked: Dictionary = Reader.inspect(path)
	return checked.get("ok", false) and checked.get("complete", false) \
		and checked.get("rows", -1) == expected_rows and checked.get("first_tick", -1) == 0 \
		and checked.get("footer", {}).get("final_tick", -1) == final_tick


func _bounded_stream(path: String) -> bool:
	var checked: Dictionary = Reader.inspect(path)
	return checked.get("ok", false) and int(checked.footer.get("peak_buffer_rows", -1)) <= Log.CHUNK_TICKS \
		and FileAccess.get_file_as_bytes(path).size() <= Log.MAX_BYTES


func _replay_stream(path: String) -> bool:
	var checked: Dictionary = Reader.inspect(path)
	if not checked.get("ok", false) or not checked.get("complete", false):
		return false
	var prepared: Dictionary = Reader.prepare_replay(checked.header)
	if not prepared.get("ok", false):
		return false
	var flight: FlightSession = prepared.flight
	var observer := Log.new(flight)
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null:
		flight.free()
		return false
	stream.seek(8)
	var header_packet: Dictionary = Log.read_packet(stream)
	var first := true
	var replayed := 0
	var divergence := ""
	while header_packet.get("ok", false) and stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.get("ok", false):
			divergence = str(packet.get("error", "packet read failed"))
			break
		var value: Dictionary = packet.value
		if value.get("kind") == "footer":
			break
		for row: Dictionary in value.get("rows", []):
			if first:
				first = false
				continue
			for key: String in row.intervention:
				flight.sim.set(key, row.intervention[key].duplicate())
			flight.sim.inputs = row.inputs.duplicate()
			flight.sim.step()
			var difference: String = Reader.disagreement(row, observer._sample({}))
			if not difference.is_empty():
				divergence = difference
				break
			replayed += 1
		if not divergence.is_empty():
			break
	stream.close()
	flight.free()
	if not divergence.is_empty():
		printerr("replay divergence: ", divergence)
	return divergence.is_empty() and replayed == 260


func _manifest_has_global_clock(manifest: Dictionary) -> bool:
	return manifest.get("global_tick_origin", -1) == 0 and manifest.get("physics_hz", -1) == 240


func _manifest_has_profiles(manifest: Dictionary) -> bool:
	var roster: Variant = manifest.get("roster", [])
	var admission: Dictionary = manifest.get("admission", {})
	var profile: Dictionary = admission.get("profile_identity", {})
	if not roster is Array or roster.size() != 2 or profile.is_empty():
		return false
	for key in ["controller_sha256", "solver_sha256", "field_profile_sha256"]:
		if str(profile.get(key, "")).length() != 64:
			return false
	for index in roster.size():
		var stream: Dictionary = roster[index]
		if stream.get("id") != ("player" if index == 0 else "companion-0") \
				or stream.get("generation") != 0 or stream.get("local_tick_origin") != 0 \
				or not stream.get("aircraft_identity") is Dictionary:
			return false
	return true


func _manifest_limits_replay(manifest: Dictionary) -> bool:
	var scope: Dictionary = manifest.get("replay_scope", {})
	return scope.get("fleet_restore", true) == false and scope.get("decision_replay", true) == false \
		and scope.get("shared_world_replay", true) == false


func _manifest_source_hashes_match(manifest: Dictionary) -> bool:
	var source_hashes: Variant = manifest.get("source_sha256", {})
	if not source_hashes is Dictionary or source_hashes.is_empty():
		return false
	for resource_path: String in source_hashes:
		var expected: String = str(source_hashes[resource_path])
		if expected.length() != 64 or not FileAccess.file_exists(resource_path) \
				or FileAccess.get_sha256(resource_path) != expected:
			return false
	return true


func _summary_has_common_extent(summary: Dictionary, final_tick: int, rows: int) -> bool:
	if not summary.get("complete", false) or summary.get("final_tick", -1) != final_tick:
		return false
	var streams: Variant = summary.get("streams", [])
	if not streams is Array or streams.size() < 2:
		return false
	for stream: Dictionary in streams:
		if not stream.get("complete", false) or stream.get("final_tick", -1) != final_tick \
				or stream.get("rows", -1) != rows:
			return false
	return true


func _summary_hashes_match(summary: Dictionary, directory: String, final_tick: int = 260,
		rows: int = 261, stream_count: int = 2) -> bool:
	var streams: Variant = summary.get("streams", [])
	if not streams is Array or streams.size() != stream_count:
		return false
	for stream: Dictionary in streams:
		var file_name: String = str(stream.get("log", ""))
		var path: String = directory.path_join(file_name)
		if not FileAccess.file_exists(path):
			return false
		var bytes := FileAccess.get_file_as_bytes(path)
		if not stream.get("complete", false) or stream.get("final_tick", -1) != final_tick \
				or stream.get("rows", -1) != rows or stream.get("bytes", -1) != bytes.size() \
				or stream.get("sha256", "") != FileAccess.get_sha256(path):
			return false
	return true


func _capture_file_hashes(directory: String) -> Dictionary:
	var result := {}
	for file_name in ["manifest.json", "summary.json", "player.orfl", "companion-0.orfl"]:
		var path: String = directory.path_join(file_name)
		if FileAccess.file_exists(path):
			result[file_name] = FileAccess.get_sha256(path)
	return result


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _finish() -> void:
	if not _out_path.is_empty():
		_write_report()
	var result := {format = "openrc-companion-record-test v1", checks = _checks,
		failures = _failures, capture_root = _temp_root, measurements = _measurements}
	print(JSON.stringify(result, "\t", true, true))
	print("companions record: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _write_report() -> void:
	_checks += 1
	var absolute_path: String = ProjectSettings.globalize_path(_out_path)
	var error_detail := ""
	var report_ok := true
	if FileAccess.file_exists(absolute_path):
		report_ok = false
		error_detail = "--out path already exists: " + absolute_path
	else:
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
		if directory_error != OK:
			report_ok = false
			error_detail = "cannot create --out parent directory: %s (%s)" % [absolute_path.get_base_dir(), error_string(directory_error)]
	if report_ok:
		var file := FileAccess.open(absolute_path, FileAccess.WRITE)
		if file == null:
			report_ok = false
			error_detail = "cannot open --out path: %s (%s)" % [absolute_path, error_string(FileAccess.get_open_error())]
		else:
			var payload := {format = "openrc-companion-record-test v1", checks = _checks,
				failures = _failures, capture_root = _temp_root, measurements = _measurements}
			file.store_string(JSON.stringify(payload, "\t", true, true))
			file.flush()
			var write_error: Error = file.get_error()
			file.close()
			if write_error != OK:
				report_ok = false
				error_detail = "cannot write/flush --out path: %s (%s)" % [absolute_path, error_string(write_error)]
			else:
				var verify := FileAccess.open(absolute_path, FileAccess.READ)
				if verify == null:
					report_ok = false
					error_detail = "cannot verify --out path: %s (%s)" % [absolute_path, error_string(FileAccess.get_open_error())]
				else:
					var decoded: Variant = JSON.parse_string(verify.get_as_text())
					verify.close()
					if not decoded is Dictionary or decoded.get("checks", -1) != _checks:
						report_ok = false
						error_detail = "--out report did not round-trip: " + absolute_path
	if not report_ok:
		_fail("evidence report write: " + error_detail)


func _fail(message: String) -> void:
	_failures += 1
	printerr("FAIL ", message)


