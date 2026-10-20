## Bounded tree-owned lifecycle and active-flight soak. Long runs are opt-in via --seconds=1200.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")

const PHYSICS_HZ := 240
const DEFAULT_CYCLES := 50
const DEFAULT_VISUAL_CYCLES := 10
const DEFAULT_TICKS := 2400
const MAX_SOAK_SECONDS := 1200.0
const SEED_BASE := 20261020
const SOURCE_PATHS := [
	"app/ai/companions/config.gd",
	"app/ai/companions/profile_loader.gd",
	"app/ai/companions/manager.gd",
	"app/ai/companions/agent.gd",
	"app/ai/companions/pilot.gd",
	"app/app_state/aircraft_catalog.gd",
	"app/sim/flight_session.gd",
	"app/sim/simulation.gd",
	"app/scenery/collision_setup.gd",
	"app/data/lake_loader.gd",
	"app/render/engine_audio.gd",
	"app/render/engine_sound.gd",
	"app/render/airplane.gd",
	"app/render/frames.gd",
	"app/tests/test_companions_lifecycle.gd",
	"app/data/ai/companions/fields/club-default.json",
	"app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
	"app/data/aircraft/jensen_ugly_stik_60.json",
	"app/data/fields/default.json",
	"app/data/fields/lake.json",
	"app/project.godot",
	"research/ai-companions/lifecycle_probe.gd",
]

var _options: Dictionary = {}
var _failures: Array[String] = []
var _samples: Array[Dictionary] = []
var _agent_ids: Array[int] = []
var _session_ids: Array[int] = []
var _player: Flight
var _field: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if not parsed.get("ok", false):
		printerr("Invalid lifecycle probe options: ", str(parsed.get("error", "unknown error")))
		quit(2)
		return
	_options = parsed.options
	var repo_root: String = ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var output_dir: String = _output_directory(repo_root, str(_options.out_dir))
	if DirAccess.dir_exists_absolute(output_dir) or FileAccess.file_exists(output_dir):
		printerr("Output path already exists; select a new --out-dir: ", output_dir)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("Cannot create new output directory: ", output_dir)
		quit(1)
		return

	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.get("ok", false) or not lake_result.get("ok", false):
		_fail("Club field or lake fixture failed: field=%s lake=%s" % [
			str(field_result.get("errors", [])), str(lake_result.get("errors", []))])
	else:
		_field = field_result.field
		var collision: Dictionary = CollisionSetup.build(_field)
		if not collision.get("ok", false):
			_fail("Club collision fixture failed: " + str(collision.get("errors", [])))
		else:
			_player = _make_player(_field, collision.world, lake_result.lake)
			root.add_child(_player)
			_player.set_physics_process(false)
			_player.set_process(false)
			_player.sim.set_physics_process(false)
			await _warm_visual_lifecycle()
			var baseline_nodes: int = _monitor(Performance.OBJECT_NODE_COUNT)
			await _run_lifecycle_cycles(baseline_nodes)
			if _failures.is_empty():
				_run_active_soak(baseline_nodes)
			_teardown_player()

	var report := _build_report(repo_root, output_dir)
	var report_path: String = output_dir.path_join("report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write lifecycle report: ", report_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	print("COMPANION LIFECYCLE PROBE COMPLETE")
	quit(0 if report.complete else 1)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {cycles = DEFAULT_CYCLES, visual_cycles = DEFAULT_VISUAL_CYCLES,
		ticks = DEFAULT_TICKS, count = 1, seed = SEED_BASE, out_dir = "", ticks_set = false, seconds_set = false}
	for argument: String in arguments:
		if argument.begins_with("--cycles="):
			var value: String = argument.trim_prefix("--cycles=")
			if not value.is_valid_int(): return {ok = false, error = "--cycles requires an integer"}
			options.cycles = value.to_int()
		elif argument.begins_with("--visual-cycles="):
			var value: String = argument.trim_prefix("--visual-cycles=")
			if not value.is_valid_int(): return {ok = false, error = "--visual-cycles requires an integer"}
			options.visual_cycles = value.to_int()
		elif argument.begins_with("--ticks="):
			var value: String = argument.trim_prefix("--ticks=")
			if not value.is_valid_int(): return {ok = false, error = "--ticks requires an integer"}
			options.ticks = value.to_int()
			options.ticks_set = true
		elif argument.begins_with("--seconds="):
			var value: String = argument.trim_prefix("--seconds=")
			if not value.is_valid_float(): return {ok = false, error = "--seconds requires a finite number"}
			var seconds: float = value.to_float()
			if not is_finite(seconds) or seconds < 0.0 or seconds > MAX_SOAK_SECONDS:
				return {ok = false, error = "--seconds must be between 0 and %.0f" % MAX_SOAK_SECONDS}
			options.ticks = ceili(seconds * PHYSICS_HZ)
			options.seconds_set = true
		elif argument.begins_with("--count="):
			var value: String = argument.trim_prefix("--count=")
			if not value.is_valid_int(): return {ok = false, error = "--count requires an integer"}
			options.count = value.to_int()
		elif argument.begins_with("--seed="):
			var value: String = argument.trim_prefix("--seed=")
			if not value.is_valid_int(): return {ok = false, error = "--seed requires an integer"}
			options.seed = value.to_int()
		elif argument.begins_with("--out-dir="):
			options.out_dir = argument.trim_prefix("--out-dir=")
		else:
			return {ok = false, error = "unknown argument %s" % argument}
	if options.ticks_set and options.seconds_set:
		return {ok = false, error = "use either --ticks or --seconds, not both"}
	if options.cycles < 1 or options.cycles > 5000:
		return {ok = false, error = "--cycles must be between 1 and 5000"}
	if options.visual_cycles < 0 or options.visual_cycles > options.cycles:
		return {ok = false, error = "--visual-cycles must be between 0 and --cycles"}
	if options.count < 1 or options.count > 3:
		return {ok = false, error = "--count must be between 1 and 3"}
	if options.seed < 0 or options.seed > 4294967295:
		return {ok = false, error = "--seed must be an unsigned 32-bit integer"}
	if options.ticks < 0 or options.ticks > int(MAX_SOAK_SECONDS * PHYSICS_HZ):
		return {ok = false, error = "--ticks must be between 0 and 288000 (20 simulated minutes)"}
	return {ok = true, options = options}


func _output_directory(repo_root: String, requested: String) -> String:
	if not requested.is_empty():
		return requested.simplify_path() if requested.is_absolute_path() else repo_root.path_join(requested).simplify_path()
	var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	return repo_root.path_join("docs/research/ai-companions/AFC-03-R1/runs/%s-%d" % [stamp, Time.get_ticks_usec()]).simplify_path()


func _make_player(field: Dictionary, world: Dictionary, lake: Dictionary) -> Flight:
	var player: Flight = Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.is_flyable() or not player.set_field(field) or not player.set_collision_world(world) \
			or not player.set_lake_context(lake):
		_fail("Player FlightSession setup failed.")
	player.reset()
	return player


func _enabled_config(count: int, seed_value: int) -> Dictionary:
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = count
	config.seed = seed_value
	return config


func _connection_count(signal_value: Signal, callback: Callable) -> int:
	var count := 0
	for connection: Dictionary in signal_value.get_connections():
		if connection.get("callable") == callback:
			count += 1
	return count


func _observer_counts(manager: Node) -> Array[int]:
	return [
		_connection_count(_player.sim.before_step, Callable(manager, "_before_step")),
		_connection_count(_player.sim.stepped, Callable(manager, "_after_step")),
		_connection_count(_player.scenery_damage_changed, Callable(manager, "_scenery_changed")),
	]


func _observers_connected_once(manager: Node) -> bool:
	return _observer_counts(manager).all(func(value: int) -> bool: return value == 1)


func _observers_disconnected(manager: Node) -> bool:
	return _observer_counts(manager).all(func(value: int) -> bool: return value == 0)


func _warm_visual_lifecycle() -> void:
	# Visual assets/audio can initialize engine singletons on first use. Warm once before
	# measuring repeated cycles so one-time engine setup is not reported as a lifecycle leak.
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(_player, _field, "club_field",
		_enabled_config(1, int(_options.seed) + 900000), true, true)
	if not configured.get("ok", false):
		_fail("Visual warmup refused: " + str(configured))
		manager.free()
		return
	root.add_child(manager)
	if manager.agents.size() != 1 or not _observers_connected_once(manager):
		_fail("Visual warmup did not create one tree-owned companion and observer set")
		manager.remove_now()
		root.remove_child(manager)
		manager.free()
		return
	var agent: Node = manager.agents[0]
	var session: Node = agent.session
	var engine: AudioStreamPlayer3D = agent.get("_engine") as AudioStreamPlayer3D
	var manager_ref: WeakRef = weakref(manager)
	var agent_ref: WeakRef = weakref(agent)
	var session_ref: WeakRef = weakref(session)
	var engine_ref: WeakRef = weakref(engine) if engine != null else null
	manager.remove_now()
	if not _observers_disconnected(manager):
		_fail("Visual warmup Remove left player observers connected")
	root.remove_child(manager)
	manager.free()
	await create_timer(0.2).timeout
	await process_frame
	await process_frame
	if manager_ref.get_ref() != null or agent_ref.get_ref() != null \
			or session_ref.get_ref() != null or (engine_ref != null and engine_ref.get_ref() != null):
		_fail("Visual warmup retained a manager, companion, session or engine node")
	_samples.append({stage = "visual_warmup", nodes = _monitor(Performance.OBJECT_NODE_COUNT),
		objects = _monitor(Performance.OBJECT_COUNT), resources = _monitor(Performance.OBJECT_RESOURCE_COUNT),
		counted = false})


func _run_lifecycle_cycles(baseline_nodes: int) -> void:
	var completed := 0
	var cycle_resource_min := 2147483647
	var cycle_resource_max := 0
	var cycle_object_min := 2147483647
	var cycle_object_max := 0
	for index in int(_options.cycles):
		var visual: bool = index >= int(_options.cycles) - int(_options.visual_cycles)
		var manager: Node = Manager.new()
		var prepared: Dictionary = manager.configure(_player, _field, "club_field",
			_enabled_config(1, int(_options.seed) + index), visual, visual)
		if not prepared.get("ok", false):
			_fail("Cycle %d enable refused: %s" % [index, str(prepared)])
			manager.free()
			break
		root.add_child(manager)
		if manager.agents.size() != 1 or not manager.agents[0].is_inside_tree() or not _observers_connected_once(manager):
			_fail("Cycle %d did not create one tree-owned session and observer set" % index)
			manager.remove_now()
			root.remove_child(manager)
			manager.free()
			break
		var old_agent: Node = manager.agents[0]
		var old_session: Node = old_agent.session
		var old_agent_ref: WeakRef = weakref(old_agent)
		var old_session_ref: WeakRef = weakref(old_session)
		_agent_ids.append(old_agent.get_instance_id())
		_session_ids.append(old_session.get_instance_id())
		var changed: Dictionary = manager.configure(_player, _field, "club_field",
			_enabled_config(1, int(_options.seed) + int(_options.cycles) + index), visual, visual)
		if not changed.get("ok", false) or manager.agents.size() != 1 \
				or old_agent_ref.get_ref() != null or old_session_ref.get_ref() != null \
				or not _observers_connected_once(manager):
			_fail("Cycle %d reconfiguration left an old session or duplicated callbacks" % index)
			manager.remove_now()
			root.remove_child(manager)
			manager.free()
			break
		if visual:
			var engine: AudioStreamPlayer3D = manager.agents[0].get("_engine") as AudioStreamPlayer3D
			if engine == null or not engine.is_playing() or not (manager.agents[0].view.root is Node3D):
				_fail("Visual cycle %d failed to create the model or engine voice" % index)
		var current_agent: Node = manager.agents[0]
		var current_session: Node = current_agent.session
		var current_agent_ref: WeakRef = weakref(current_agent)
		var current_session_ref: WeakRef = weakref(current_session)
		var manager_ref: WeakRef = weakref(manager)
		manager.remove_now()
		if not _observers_disconnected(manager):
			_fail("Cycle %d Remove left player observers connected: %s" % [index, str(_observer_counts(manager))])
		root.remove_child(manager)
		manager.free()
		if current_agent_ref.get_ref() != null or current_session_ref.get_ref() != null or manager_ref.get_ref() != null:
			_fail("Cycle %d left a manager, companion or FlightSession object alive" % index)
		if visual:
			await create_timer(0.2).timeout
		completed += 1
		var live_nodes: int = _monitor(Performance.OBJECT_NODE_COUNT)
		if live_nodes != baseline_nodes:
			_fail("Cycle %d left %d live nodes above baseline %d" % [index, live_nodes, baseline_nodes])
		var resources: int = _monitor(Performance.OBJECT_RESOURCE_COUNT)
		var objects: int = _monitor(Performance.OBJECT_COUNT)
		if index >= 2:
			cycle_resource_min = mini(cycle_resource_min, resources)
			cycle_resource_max = maxi(cycle_resource_max, resources)
			cycle_object_min = mini(cycle_object_min, objects)
			cycle_object_max = maxi(cycle_object_max, objects)
		if index % 10 == 9 or index == int(_options.cycles) - 1:
			_samples.append({stage = "lifecycle", cycle = index + 1, nodes = live_nodes,
				objects = objects, resources = resources, visual = visual})
	if completed != int(_options.cycles):
		_fail("Lifecycle completed %d of %d cycles" % [completed, int(_options.cycles)])
	if cycle_resource_min != 2147483647 and cycle_resource_max > cycle_resource_min + 2:
		_fail("Lifecycle resources grew after warmup: %d to %d" % [cycle_resource_min, cycle_resource_max])
	if cycle_object_min != 2147483647 and cycle_object_max > cycle_object_min + 4:
		_fail("Lifecycle object count grew after warmup: %d to %d" % [cycle_object_min, cycle_object_max])
	if int(_options.cycles) > 0:
		_samples.append({stage = "lifecycle_summary", cycles = completed, nodes = _monitor(Performance.OBJECT_NODE_COUNT),
			objects_min = cycle_object_min if cycle_object_min != 2147483647 else _monitor(Performance.OBJECT_COUNT),
			objects_max = cycle_object_max, resources_min = cycle_resource_min if cycle_resource_min != 2147483647 else _monitor(Performance.OBJECT_RESOURCE_COUNT),
			resources_max = cycle_resource_max})


func _run_active_soak(baseline_nodes: int) -> void:
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(_player, _field, "club_field",
		_enabled_config(int(_options.count), int(_options.seed) + 100000), false, false)
	if not configured.get("ok", false):
		_fail("Active soak fleet refused: " + str(configured))
		manager.free()
		return
	root.add_child(manager)
	if not _observers_connected_once(manager) or manager.agents.size() != int(_options.count):
		_fail("Active soak manager did not install one observer set and the requested roster")
	var active_node_count: int = _monitor(Performance.OBJECT_NODE_COUNT)
	if active_node_count <= baseline_nodes:
		_fail("Active manager did not add its bounded companion node graph")
	var start_object_count: int = _monitor(Performance.OBJECT_COUNT)
	var start_resource_count: int = _monitor(Performance.OBJECT_RESOURCE_COUNT)
	var completed := 0
	var failure := ""
	var packet := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = float(_player.start.throttle)}
	if int(_options.ticks) > 0:
		for tick in int(_options.ticks):
			_player.commands = packet.duplicate()
			_player.raw = packet.duplicate()
			_player.sim.inputs = _player._inputs()
			_player._physics_process(_player.sim.dt())
			_player.sim._physics_process(_player.sim.dt())
			if _player.sim.tick != tick + 1 or not _player.sim.fault_reason.is_empty() or not _player.crash.is_empty():
				failure = "Player stopped at tick %d: %s" % [tick, _player.sim.fault_reason]
				break
			for agent: Node in manager.agents:
				if agent.session.sim.tick != tick + 1 or not agent.failure.is_empty() \
						or not agent.session.sim.fault_reason.is_empty() or not agent.session.crash.is_empty():
					failure = "%s stopped at tick %d: %s %s" % [agent.name, tick, agent.failure, str(agent.session.crash)]
					break
			if not failure.is_empty():
				break
			completed += 1
			if completed % PHYSICS_HZ == 0 or completed == int(_options.ticks):
				var sample := {stage = "flight", tick = completed, player_tick = _player.sim.tick,
					manager_ticks = manager.accepted_ticks, nodes = _monitor(Performance.OBJECT_NODE_COUNT),
					objects = _monitor(Performance.OBJECT_COUNT), resources = _monitor(Performance.OBJECT_RESOURCE_COUNT)}
				_samples.append(sample)
				if int(sample.nodes) != active_node_count:
					failure = "Live node count changed at tick %d: %s" % [completed, str(sample)]
					break
	if not failure.is_empty():
		_fail(failure)
	if completed != int(_options.ticks):
		_fail("Active flight accepted %d of %d requested ticks" % [completed, int(_options.ticks)])
	if manager.accepted_ticks != completed or _player.sim.tick != completed:
		_fail("Player/manager tick counts diverged: player=%d manager=%d expected=%d" % [
			_player.sim.tick, manager.accepted_ticks, completed])
	var end_object_count: int = _monitor(Performance.OBJECT_COUNT)
	var end_resource_count: int = _monitor(Performance.OBJECT_RESOURCE_COUNT)
	if end_object_count > start_object_count + 4 or end_resource_count > start_resource_count + 2:
		_fail("Active flight object/resource count drifted: objects=%d/%d resources=%d/%d" % [
			start_object_count, end_object_count, start_resource_count, end_resource_count])
	var agent_refs: Array[WeakRef] = []
	for agent: Node in manager.agents:
		agent_refs.append(weakref(agent))
	manager.remove_now()
	if not _observers_disconnected(manager):
		_fail("Active soak Remove left observers connected: " + str(_observer_counts(manager)))
	root.remove_child(manager)
	manager.free()
	if not agent_refs.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null):
		_fail("Active soak retained an agent after Remove/free")
	_samples.append({stage = "active_soak_end", requested_ticks = int(_options.ticks), ticks = completed,
		start_objects = start_object_count, end_objects = end_object_count,
		start_resources = start_resource_count, end_resources = end_resource_count,
		failure = failure})


func _monitor(metric: int) -> int:
	return int(Performance.get_monitor(metric))


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("FAIL ", message)


func _teardown_player() -> void:
	if _player == null:
		return
	var player_ref: WeakRef = weakref(_player)
	if _player.is_inside_tree():
		root.remove_child(_player)
	_player.free()
	_player = null
	if player_ref.get_ref() != null:
		_fail("Player FlightSession survived its tree teardown")


func _hash_file(repo_root: String, relative_path: String) -> Dictionary:
	var absolute_path: String = repo_root.path_join(relative_path)
	if not FileAccess.file_exists(absolute_path):
		return {path = relative_path, bytes = 0, sha256 = "", error = "missing"}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute_path)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return {path = relative_path, bytes = bytes.size(), sha256 = "", error = "hash failed"}
	return {path = relative_path, bytes = bytes.size(), sha256 = context.finish().hex_encode()}


func _build_report(repo_root: String, output_dir: String) -> Dictionary:
	var sources: Array[Dictionary] = []
	var source_receipt_complete := true
	for relative_path: String in SOURCE_PATHS:
		var source: Dictionary = _hash_file(repo_root, relative_path)
		sources.append(source)
		source_receipt_complete = source_receipt_complete and str(source.get("sha256", "")).length() == 64
	var completed_ticks := -1
	for sample: Dictionary in _samples:
		if sample.get("stage", "") == "active_soak_end":
			completed_ticks = int(sample.get("ticks", 0))
			break
	var requested_ticks: int = int(_options.ticks)
	var requested_seconds: float = float(requested_ticks) / PHYSICS_HZ
	var completion_text: String = "no active-flight result was recorded"
	if completed_ticks >= 0:
		completion_text = "completed %d ticks (%.3f simulated seconds)" % [
			completed_ticks, float(completed_ticks) / PHYSICS_HZ]
	var duration_summary := "Requested %d ticks (%.3f simulated seconds); %s." % [
		requested_ticks, requested_seconds, completion_text]
	var twenty_minute_ticks: int = int(MAX_SOAK_SECONDS * PHYSICS_HZ)
	if requested_ticks == twenty_minute_ticks:
		if completed_ticks == requested_ticks:
			duration_summary += " The requested 20-minute simulated duration was reached; overall lifecycle and fault criteria are reported separately."
		else:
			duration_summary += " The 20-minute simulated-duration target was requested but not completed."
	else:
		duration_summary += " The 20-minute simulated-duration target was not requested."
	var complete: bool = _failures.is_empty() and source_receipt_complete and int(_samples.filter(func(row: Dictionary) -> bool:
		return row.get("stage", "") == "active_soak_end").size()) == 1
	return {
		format = "openrc-companions-lifecycle v1",
		complete = complete,
		failures = _failures,
		engine = Engine.get_version_info().string,
		platform = OS.get_name(),
		processor = OS.get_processor_name(),
		physics_hz = PHYSICS_HZ,
		requested_cycles = int(_options.cycles),
		visual_audio_cycles = int(_options.visual_cycles),
		requested_ticks = int(_options.ticks),
		requested_seconds = float(_options.ticks) / PHYSICS_HZ,
		companion_count = int(_options.count),
		seed = int(_options.seed),
		cycle_agent_ids = _agent_ids,
		cycle_session_ids = _session_ids,
		measurements = _samples,
		source_hash_receipt = {algorithm = "sha256", complete = source_receipt_complete, files = sources},
		output_directory = output_dir,
		scope = "Tree-owned manager, agent, FlightSession and (for the bounded visual subset) engine voice lifecycle; fixed-step active-flight soak. This is software lifecycle evidence, not physical validation, wall-clock performance, or a 50-cycle fully rendered/audio run.",
		long_soak = duration_summary,
	}
