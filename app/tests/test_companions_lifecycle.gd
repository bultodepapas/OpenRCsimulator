extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")

const HEADLESS_CYCLES := 50
const VISUAL_AUDIO_CYCLES := 10
const SEED_BASE := 20261020

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _enabled_config(count: int, seed_value: int) -> Dictionary:
	var requested: Dictionary = Config.defaults()
	requested.enabled = true
	requested.count = count
	requested.seed = seed_value
	return requested


func _new_player(field: Dictionary, world: Dictionary, lake: Dictionary) -> Flight:
	var player: Flight = Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("player starts flyable", player.is_flyable())
	_check("Club field installs", player.set_field(field), player.surface_error)
	_check("collision world installs", player.set_collision_world(world))
	_check("lake context installs", player.set_lake_context(lake))
	player.reset()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.sim.set_physics_process(false)
	return player


func _connection_count(signal_value: Signal, callback: Callable) -> int:
	var count := 0
	for connection: Dictionary in signal_value.get_connections():
		if connection.get("callable") == callback:
			count += 1
	return count


func _manager_connection_counts(player: Flight, manager: Node) -> Array[int]:
	return [
		_connection_count(player.sim.before_step, Callable(manager, "_before_step")),
		_connection_count(player.sim.stepped, Callable(manager, "_after_step")),
		_connection_count(player.scenery_damage_changed, Callable(manager, "_scenery_changed")),
	]


func _signals_match(player: Flight, manager: Node, expected: int) -> bool:
	var counts: Array[int] = _manager_connection_counts(player, manager)
	return counts.all(func(value: int) -> bool: return value == expected)


func _send_player_tick(player: Flight) -> bool:
	player.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = float(player.start.throttle)}
	player.raw = player.commands.duplicate()
	player.sim.inputs = player._inputs()
	if not player._session_after_input():
		return false
	player.sim.step()
	return true


func _cycle_manager(player: Flight, index: int) -> void:
	var manager: Node = Manager.new()
	var initial: Dictionary = manager.configure(player, _field, "club_field", _enabled_config(1, SEED_BASE + index), false, false)
	_check("headless cycle %d enables one companion" % index,
		initial.get("ok", false) and manager.agents.size() == 1, str(initial))
	root.add_child(manager)
	_check("headless cycle %d manager and session enter SceneTree" % index,
		manager.is_inside_tree() and manager.agents[0].is_inside_tree()
			and manager.agents[0].session.is_inside_tree())
	_check("headless cycle %d installs each player observer once" % index, _signals_match(player, manager, 1),
		str(_manager_connection_counts(player, manager)))

	var retired_agent: Node = manager.agents[0]
	var retired_session: Node = retired_agent.session
	var retired_agent_ref: WeakRef = weakref(retired_agent)
	var retired_session_ref: WeakRef = weakref(retired_session)
	var retired_id: int = retired_agent.get_instance_id()
	var reconfigured: Dictionary = manager.configure(player, _field, "club_field",
		_enabled_config(1, SEED_BASE + HEADLESS_CYCLES + index), false, false)
	_check("headless cycle %d reconfigures atomically at tick zero" % index,
		reconfigured.get("ok", false) and manager.agents.size() == 1
			and manager.agents[0].get_instance_id() != retired_id,
		str(reconfigured))
	_check("headless cycle %d releases the replaced agent and session" % index,
		retired_agent_ref.get_ref() == null and retired_session_ref.get_ref() == null)
	_check("headless cycle %d keeps one observer set after reconfigure" % index,
		_signals_match(player, manager, 1), str(_manager_connection_counts(player, manager)))

	var live_agent: Node = manager.agents[0]
	var live_session: Node = live_agent.session
	var manager_ref: WeakRef = weakref(manager)
	var live_agent_ref: WeakRef = weakref(live_agent)
	var live_session_ref: WeakRef = weakref(live_session)
	manager.remove_now()
	_check("headless cycle %d Remove clears sessions while manager stays attached" % index,
		manager.is_inside_tree() and manager.agents.is_empty() and manager.get_child_count() == 0
			and manager.status().removed)
	_check("headless cycle %d Remove disconnects all player observers immediately" % index,
		_signals_match(player, manager, 0), str(_manager_connection_counts(player, manager)))
	_check("headless cycle %d Remove frees the live agent and session" % index,
		live_agent_ref.get_ref() == null and live_session_ref.get_ref() == null)

	# Verify the manager can be reused after Remove, then remove it again before freeing the node.
	if index == 0:
		var reenabled: Dictionary = manager.configure(player, _field, "club_field",
			_enabled_config(1, SEED_BASE + HEADLESS_CYCLES * 2), false, false)
		_check("same manager reconnects once after Remove", reenabled.get("ok", false)
			and manager.agents.size() == 1 and _signals_match(player, manager, 1),
			str(reenabled) + " " + str(_manager_connection_counts(player, manager)))
		manager.remove_now()
		_check("second Remove disconnects the re-enabled manager", _signals_match(player, manager, 0))

	root.remove_child(manager)
	manager.free()
	_check("headless cycle %d frees the manager" % index, manager_ref.get_ref() == null)
	_check("headless cycle %d returns to the player-only tree" % index, root.get_child_count() == 1)


func _visual_audio_cycle(player: Flight, index: int) -> void:
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(player, _field, "club_field",
		_enabled_config(1, SEED_BASE + HEADLESS_CYCLES * 3 + index), true, true)
	_check("visual cycle %d configures" % index, configured.get("ok", false), str(configured))
	root.add_child(manager)
	if manager.agents.is_empty():
		manager.remove_now()
		root.remove_child(manager)
		manager.free()
		return
	var agent: Node = manager.agents[0]
	var session: Node = agent.session
	var view_root: Node3D = agent.view.get("root") as Node3D
	var engine: AudioStreamPlayer3D = agent.get("_engine") as AudioStreamPlayer3D
	var stream_id: int = engine.stream.get_instance_id() if engine != null and engine.stream != null else 0
	var engine_callback := Callable(engine, "_accepted_tick") if engine != null else Callable()
	var manager_ref: WeakRef = weakref(manager)
	var agent_ref: WeakRef = weakref(agent)
	var session_ref: WeakRef = weakref(session)
	var view_ref: WeakRef = weakref(view_root) if view_root != null else null
	var engine_ref: WeakRef = weakref(engine) if engine != null else null
	var stream_ref: WeakRef = weakref(engine.stream) if engine != null and engine.stream != null else null
	var ids := {
		manager = manager.get_instance_id(), agent = agent.get_instance_id(),
		session = session.get_instance_id(), view = view_root.get_instance_id() if view_root != null else 0,
		engine = engine.get_instance_id() if engine != null else 0,
		stream = stream_id,
	}
	_check("visual cycle %d enters with model and engine voice" % index,
		view_root != null and view_root.is_inside_tree() and engine != null and engine.is_inside_tree()
			and engine.stream is AudioStreamGenerator and engine.is_playing(), str(ids))
	if engine != null:
		_check("visual cycle %d owns one read-only audio observer pair" % index,
			_connection_count(session.sim.stepped, engine_callback) == 1
				and _connection_count(session.sim.paused_changed, Callable(engine, "_paused_changed")) == 1)

	manager.remove_now()
	_check("visual cycle %d immediately releases manager callbacks" % index,
		_signals_match(player, manager, 0))
	root.remove_child(manager)
	manager.free()
	# The pinned Godot 4.7 audio server can keep the generator source through its fade tail.
	await create_timer(0.2).timeout
	await process_frame
	await process_frame
	_check("visual cycle %d releases manager, agent, session, view and engine nodes" % index,
		manager_ref.get_ref() == null and agent_ref.get_ref() == null and session_ref.get_ref() == null
			and (view_ref == null or view_ref.get_ref() == null)
			and (engine_ref == null or engine_ref.get_ref() == null), str(ids))
	_check("visual cycle %d releases the generated audio stream" % index,
		stream_ref == null or stream_ref.get_ref() == null, str(ids))
	_check("visual cycle %d leaves no engine voice under the player" % index,
		root.find_children("engine_sound", "", true, false).is_empty())
	_check("visual cycle %d restores the player-only tree" % index, root.get_child_count() == 1)


func _run_isolation_gate(player: Flight) -> void:
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(player, _field, "club_field", _enabled_config(2, SEED_BASE + 700), false, false)
	_check("isolation fleet configures", configured.get("ok", false), str(configured))
	root.add_child(manager)
	_check("first player tick advances player and both agents",
		_send_player_tick(player) and player.sim.tick == 1 and manager.agents.all(
			func(agent: Node) -> bool: return agent.session.sim.tick == 1))

	player.hold("lifecycle-test")
	var held_player_tick: int = player.sim.tick
	var held_agent_ticks: Array[int] = []
	for agent: Node in manager.agents:
		held_agent_ticks.append(agent.session.sim.tick)
	_check("menu hold rejects the next player tick", not _send_player_tick(player))
	var hold_stable: bool = player.sim.tick == held_player_tick
	for index in manager.agents.size():
		hold_stable = hold_stable and manager.agents[index].session.sim.tick == held_agent_ticks[index]
	_check("hold leaves player and companion ticks frozen", hold_stable)
	player.release("lifecycle-test")
	player.resume()

	var faulted_agent: Node = manager.agents[0]
	var survivor: Node = manager.agents[1]
	faulted_agent.session.sim._fail_safe("lifecycle fault isolation")
	var next_player_tick := _send_player_tick(player)
	_check("one companion fault does not stop the player or surviving companion",
		next_player_tick and player.sim.tick == 2 and survivor.session.sim.tick == 2
			and faulted_agent.session.sim.tick == 1 and not faulted_agent.failure.is_empty()
			and manager.status().faulted == 1, str(manager.status()))

	var crashed_agent: Node = survivor
	crashed_agent.session.crash = {ticks_left = 2, why = "lifecycle crash isolation"}
	crashed_agent.session.sim.set_paused(true)
	var faulted_tick: int = faulted_agent.session.sim.tick
	_check("one companion crash does not stop the player or fault status", _send_player_tick(player)
		and player.sim.tick == 3 and faulted_agent.session.sim.tick == faulted_tick
			and manager.status().crashed == 1 and manager.status().faulted == 1,
		str(manager.status()))

	var old_agents: Array[WeakRef] = []
	for agent: Node in manager.agents:
		old_agents.append(weakref(agent))
	player.reset()
	var restarted: Dictionary = manager.configure(player, _field, "club_field",
		_enabled_config(2, SEED_BASE + 701), false, false)
	_check("explicit player restart replaces faulted and crashed agents at tick zero",
		restarted.get("ok", false) and player.sim.tick == 0 and manager.accepted_ticks == 0
			and manager.agents.size() == 2 and manager.status().faulted == 0 and manager.status().crashed == 0,
		str(restarted) + " " + str(manager.status()))
	_check("restart frees both prior agent nodes", old_agents.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null))
	_check("restart retains exactly one callback for each manager observer", _signals_match(player, manager, 1),
		str(_manager_connection_counts(player, manager)))
	_check("post-restart player and companions accept one tick", _send_player_tick(player)
		and player.sim.tick == 1 and manager.agents.all(func(agent: Node) -> bool: return agent.session.sim.tick == 1))

	manager.remove_now()
	_check("isolation Remove detaches callbacks while manager remains in tree", _signals_match(player, manager, 0))
	root.remove_child(manager)
	manager.free()


var _field: Dictionary = {}


func _initialize() -> void:
	# AFC-02-R3: a logic suite; tests/test_companions_profiles.gd alone gates the pinned solver identity.
	preload("res://ai/companions/profile_loader.gd").accept_current_solver_for_tests()
	_run.call_deferred()


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.get("ok", false) or not lake_result.get("ok", false):
		printerr("Lifecycle fixtures failed: field=%s lake=%s" % [str(field_result.get("errors", [])), str(lake_result.get("errors", []))])
		quit(1)
		return
	_field = field_result.field
	var collision: Dictionary = CollisionSetup.build(_field)
	if not collision.get("ok", false):
		printerr("Collision fixture failed: %s" % str(collision.get("errors", [])))
		quit(1)
		return
	var player: Flight = _new_player(_field, collision.world, lake_result.lake)
	var baseline_children: int = root.get_child_count()
	var baseline_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var baseline_resources: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var baseline_objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var post_warmup_resources := -1
	var max_resources := 0
	var post_warmup_objects := -1
	var max_objects := 0
	for index in HEADLESS_CYCLES:
		_cycle_manager(player, index)
		if index == 2:
			await process_frame
			post_warmup_resources = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
			post_warmup_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if index >= 2 and index % 5 == 4:
			await process_frame
			max_resources = maxi(max_resources, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
			max_objects = maxi(max_objects, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_check("50 headless lifecycle cycles restore the baseline child and node counts",
		root.get_child_count() == baseline_children
			and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == baseline_nodes,
		"children=%d/%d nodes=%d/%d" % [root.get_child_count(), baseline_children,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), baseline_nodes])
	_check("headless lifecycle resource count stays bounded after warmup",
		post_warmup_resources >= 0 and max_resources <= post_warmup_resources + 2,
		"baseline=%d warm=%d max=%d" % [baseline_resources, post_warmup_resources, max_resources])
	_check("headless lifecycle object count stays bounded after warmup",
		post_warmup_objects >= 0 and max_objects <= post_warmup_objects + 4,
		"baseline=%d warm=%d max=%d" % [baseline_objects, post_warmup_objects, max_objects])

	for index in VISUAL_AUDIO_CYCLES:
		await _visual_audio_cycle(player, index)
	await process_frame
	var visual_resources: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var visual_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check("10 visual/audio cycles return to the post-headless resource envelope",
		visual_resources <= max_resources + 4,
		"headless_max=%d visual_end=%d" % [max_resources, visual_resources])
	_check("10 visual/audio cycles return to the player-only node count", visual_nodes == baseline_nodes,
		"baseline=%d visual_end=%d" % [baseline_nodes, visual_nodes])

	_run_isolation_gate(player)
	if player.is_inside_tree():
		root.remove_child(player)
	player.free()
	await process_frame
	_check("player teardown leaves no companion or flight nodes", root.get_child_count() == 0
		and root.find_children("Companion*", "", true, false).is_empty()
		and root.find_children("FlightSession", "", true, false).is_empty())
	print("companions lifecycle: %d checks, %d failed; %d headless cycles, %d visual/audio cycles" %
		[_checks, _failures, HEADLESS_CYCLES, VISUAL_AUDIO_CYCLES])
	quit(1 if _failures > 0 else 0)
