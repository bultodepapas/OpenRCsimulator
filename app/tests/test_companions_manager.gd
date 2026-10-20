extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Math := preload("res://physics/math3d.gd")

const COMPANION_COUNT := 3
const COMPANION_SEED := 20261020
const PLAYER_PARITY_TICKS := 240
const SESSION_PARITY_TICKS := 10000

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _same_f64(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return left.to_byte_array() == right.to_byte_array()


func _finite_f64(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _driver_state_matches(left: FlightSession, right: FlightSession) -> bool:
	return left.sim.tick == right.sim.tick and left.sim.time() == right.sim.time() \
		and _same_f64(left.sim.state, right.sim.state) \
		and _same_f64(left.sim.previous, right.sim.previous) \
		and _same_f64(left.sim.aux, right.sim.aux) \
		and _same_f64(left.sim.inputs, right.sim.inputs) \
		and _same_f64(left.sim.continuous, right.sim.continuous) \
		and left.sim.modes.to_byte_array() == right.sim.modes.to_byte_array() \
		and _same_f64(left.sim.last_loads, right.sim.last_loads)


func _new_parity_session(external: bool) -> FlightSession:
	var session: FlightSession = FlightSession.new()
	session.input_enabled = false
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("%s parity session starts flyable" % ("external" if external else "manual"),
		session.is_flyable())
	if external:
		_check("external parity driver configures while detached", session.configure_external_driver())
	return session


func _run_session_parity_gate() -> void:
	var manual: FlightSession = _new_parity_session(false)
	var external: FlightSession = _new_parity_session(true)
	var packet := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = float(manual.start.throttle)}
	var parity := true
	var all_manual_ticks_accepted := true
	var all_external_ticks_accepted := true
	var mismatch_tick := -1
	for tick in SESSION_PARITY_TICKS:
		manual.commands = {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle}
		manual.raw = manual.commands.duplicate()
		manual.sim.inputs = manual._inputs()
		var manual_before: int = manual.sim.tick
		if manual._session_after_input():
			manual.sim.step()
		else:
			all_manual_ticks_accepted = false
		all_manual_ticks_accepted = all_manual_ticks_accepted and manual.sim.tick == manual_before + 1
		var staged: Dictionary = external.prepare_external_tick(packet)
		var external_accepted: bool = staged.get("ok", false) and external.step_external_tick()
		all_external_ticks_accepted = all_external_ticks_accepted and external_accepted
		if not parity and mismatch_tick >= 0:
			continue
		if not _driver_state_matches(manual, external):
			parity = false
			mismatch_tick = tick + 1
	_check("manual and external drivers accept 10,000 trim-relative ticks",
		all_manual_ticks_accepted and all_external_ticks_accepted \
			and manual.sim.tick == SESSION_PARITY_TICKS and external.sim.tick == SESSION_PARITY_TICKS,
		"manual=%d external=%d" % [manual.sim.tick, external.sim.tick])
	_check("manual/external state, aux, inputs, continuous, modes, and loads are byte-identical each tick",
		parity, "first mismatch at tick %d" % mismatch_tick)
	manual.free()
	external.free()


func _new_player(field: Dictionary, world: Dictionary) -> FlightSession:
	var player: FlightSession = FlightSession.new()
	player.input_enabled = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("Club field player starts flyable", player.is_flyable())
	_check("Club field surfaces install before reset", player.set_field(field), player.surface_error)
	player.reset()
	_check("player collision world installs", player.set_collision_world(world))
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	root.add_child(player)
	# Session._ready configures the ordinary live callback path; these test players
	# remain manually driven so the tape is the sole source of player ticks.
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	return player


func _requested_config() -> Dictionary:
	var requested: Dictionary = Config.defaults()
	requested.enabled = true
	requested.count = COMPANION_COUNT
	requested.seed = COMPANION_SEED
	return requested


func _same_agent_refs(left: Array[Node], right: Array[Node]) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _damage_event(proxy: Dictionary, tick: int) -> SceneryCollision.Event:
	var profile: String = str(proxy.get("damage_profile", "none"))
	var event: SceneryCollision.Event = SceneryCollision.Event.new()
	event.obstacle_id = str(proxy.get("id", ""))
	event.damage_id = str(proxy.get("damage_id", ""))
	event.damage_profile = profile
	event.tick = tick
	event.impact_energy_j = SceneryDamage.threshold_j(profile) * 1.1
	event.point_ned = PackedFloat64Array([
		float(proxy.get("north", 0.0)), float(proxy.get("east", 0.0)), float(proxy.get("down", 0.0))])
	event.normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])
	event.velocity_ned = PackedFloat64Array([0.0, 0.0, 1.0])
	return event


func _control_for_tick(tick: int) -> Dictionary:
	var segment: int = (tick / 30) % 4
	var rolls: Array[float] = [-0.06, 0.0, 0.06, 0.0]
	var pitches: Array[float] = [0.0, 0.025, 0.0, -0.025]
	return {roll = rolls[segment], pitch = pitches[segment], yaw = 0.0, throttle = 0.56}


func _prepare_player_tick(player: FlightSession, packet: Dictionary) -> bool:
	player.commands = {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle}
	player.raw = player.commands.duplicate()
	player.sim.inputs = player._inputs()
	return player._session_after_input()


func _run_manager_gate(field: Dictionary, world: Dictionary, damage_proxy: Dictionary) -> void:
	var player: FlightSession = _new_player(field, world)
	var manual_player: FlightSession = _new_player(field, world)
	var second_player: FlightSession = _new_player(field, world)
	var initial_player_state: PackedFloat64Array = player.sim.state.duplicate()
	var initial_player_aux: PackedFloat64Array = player.sim.aux.duplicate()
	var initial_player_inputs: PackedFloat64Array = player.sim.inputs.duplicate()
	var manager: Node = Manager.new()
	var configured: Dictionary = manager.configure(player, field, "club_field", _requested_config(), false, false)
	_check("three-aircraft Club field fleet configures before tree entry",
		configured.get("ok", false) and manager.agents.size() == COMPANION_COUNT, str(configured))
	_check("fleet construction leaves the player snapshot untouched",
		_same_f64(player.sim.state, initial_player_state) and _same_f64(player.sim.aux, initial_player_aux)
			and _same_f64(player.sim.inputs, initial_player_inputs))
	var original_agents: Array[Node] = manager.agents.duplicate()
	var profile_identity: Dictionary = manager.status().profile_identity
	_check("manager records the accepted aircraft, controller, solver and field profile identities",
		profile_identity.get("aircraft_id") == Config.AIRCRAFT_ID
		and str(profile_identity.get("controller_sha256", "")).length() == 64
		and str(profile_identity.get("solver_sha256", "")).length() == 64
		and str(profile_identity.get("solver_qualification_sha256", "")).length() == 64
		and str(profile_identity.get("field_profile_sha256", "")).length() == 64)
	profile_identity.clear()
	_check("profile diagnostic identity is detached", not manager.status().profile_identity.is_empty())
	var airspace_report: Dictionary = manager.status().airspace_report
	_check("launch records clearance against the actual world and companion model",
		airspace_report.get("scope") == "nominal_circuit_corridor" \
		and airspace_report.get("collision_world_identity") == world.identity \
		and airspace_report.get("proxy_count") == world.proxies.size() \
		and str(airspace_report.get("geometry_sha256", "")).length() == 64 \
		and airspace_report.get("count") == COMPANION_COUNT)
	airspace_report.clear()
	_check("airspace diagnostics are detached", not manager.status().airspace_report.is_empty())
	var original_airspace: Dictionary = manager.status().airspace_report
	# Keep the supplied identity unchanged: admission must inspect the actual shapes.
	var blocked_world: Dictionary = world.duplicate(true)
	var blocker := {id = "afc-route-blocker", kind = "fixture", part = "box", shape = "box",
		response_class = "hard_terminal", north = 279.0, east = 0.0, down = -35.0,
		radius = 0.0, half_length = 0.0, half_x = 1.0, half_down = 1.0, half_z = 1.0,
		sin_heading = 0.0, cos_heading = 1.0,
		bounds_north_min = 278.0, bounds_north_max = 280.0, bounds_east_min = -1.0, bounds_east_max = 1.0,
		bounds_down_min = -36.0, bounds_down_max = -34.0}
	blocked_world.proxies.append(blocker)
	_check("obstructed session world installs at tick zero", player.set_collision_world(blocked_world))
	var blocked: Dictionary = manager.configure(player, field, "club_field", _requested_config(), false, false)
	_check("route obstruction refuses admission before replacing the live roster",
		not blocked.get("ok", true) and str(blocked.get("errors", [])).contains("afc-route-blocker") \
		and _same_agent_refs(manager.agents, original_agents) and manager.status().airspace_report == original_airspace \
		and player.sim.tick == 0 and manager.accepted_ticks == 0)
	var disabled_manager := Manager.new()
	var off_admission: Dictionary = disabled_manager.configure(player, field, "club_field", Config.defaults(), false, false)
	_check("disabled companions bypass the airspace gate", off_admission.ok and disabled_manager.status().airspace_report.is_empty())
	disabled_manager.remove_now()
	disabled_manager.free()
	_check("original session collision world restores", player.set_collision_world(world))
	_check("manager agents begin at tick zero", manager.agents.all(func(agent: Node) -> bool: return agent.session.sim.tick == 0))

	var deterministic_manager: Node = Manager.new()
	var deterministic_result: Dictionary = deterministic_manager.configure(second_player, field, "club_field",
		_requested_config(), false, false)
	var deterministic: bool = deterministic_result.get("ok", false) and deterministic_manager.agents.size() == COMPANION_COUNT
	if deterministic:
		for slot in COMPANION_COUNT:
			var first_state: PackedFloat64Array = manager.agents[slot].session.sim.state
			var repeat_state: PackedFloat64Array = deterministic_manager.agents[slot].session.sim.state
			deterministic = deterministic and _same_f64(first_state, repeat_state)
	_check("same seed reproduces identical initial companion states", deterministic, str(deterministic_result))
	var independent: bool = manager.agents.size() == COMPANION_COUNT
	for slot in manager.agents.size():
		var agent: Node = manager.agents[slot]
		var state: PackedFloat64Array = agent.session.sim.state
		independent = independent and _finite_f64(state) and _finite_f64(agent.session.sim.aux)
		independent = independent and agent.session != manager.agents[(slot + 1) % manager.agents.size()].session
		for other_slot in range(slot + 1, manager.agents.size()):
			var other_state: PackedFloat64Array = manager.agents[other_slot].session.sim.state
			var separation: float = Math.norm(Math.v3(state[0] - other_state[0],
				state[1] - other_state[1], state[2] - other_state[2]))
			independent = independent and separation > 1.0
	_check("companions have independent finite launch states", independent)

	var bad_count: Dictionary = _requested_config()
	bad_count.count = COMPANION_COUNT + 1
	var count_refusal: Dictionary = manager.configure(player, field, "club_field", bad_count, false, false)
	_check("invalid count refusal preserves the live fleet atomically",
		not count_refusal.get("ok", true) and _same_agent_refs(manager.agents, original_agents)
			and manager.get_child_count() == COMPANION_COUNT, str(count_refusal))
	var bad_field: Dictionary = field.duplicate(true)
	bad_field.surfaces[0].center_north += 1.0
	var geometry_refusal: Dictionary = manager.configure(player, bad_field, "club_field", _requested_config(), false, false)
	_check("same-id modified field is refused without replacing the live fleet",
		not geometry_refusal.get("ok", true) and _same_agent_refs(manager.agents, original_agents), str(geometry_refusal))
	bad_field.id = "unsupported_field"
	var field_refusal: Dictionary = manager.configure(player, bad_field, "club_field", _requested_config(), false, false)
	var landscape_refusal: Dictionary = manager.configure(player, field, "backyard", _requested_config(), false, false)
	_check("unsupported field and landscape refusals preserve the live fleet",
		not field_refusal.get("ok", true) and not landscape_refusal.get("ok", true)
			and _same_agent_refs(manager.agents, original_agents), str(field_refusal) + " " + str(landscape_refusal))
	var bad_weather: Dictionary = WindConfig.defaults()
	bad_weather.speed_mps = 2.0
	var weather_installed: bool = player.setup_weather(bad_weather)
	var weather_refusal: Dictionary = manager.configure(player, field, "club_field", _requested_config(), false, false)
	var weather_restored: bool = player.setup_weather(WindConfig.defaults())
	player.reset()
	_check("unsupported weather refusal preserves the live fleet atomically",
		weather_installed and not weather_refusal.get("ok", true) and weather_restored
			and _same_agent_refs(manager.agents, original_agents), str(weather_refusal))

	var disabled: Dictionary = Config.defaults()
	disabled.count = 0
	var off_path_manager: Node = Manager.new()
	var off_path_result: Dictionary = off_path_manager.configure(manual_player, field, "backyard", disabled, false, false)
	_check("disabled companions stay off-path and create no agents",
		off_path_result.get("ok", false) and off_path_manager.agents.is_empty(), str(off_path_result))

	root.add_child(manager)
	root.add_child(deterministic_manager)
	root.add_child(off_path_manager)
	_check("configured managers enter the SceneTree before lifecycle checks",
		manager.is_inside_tree() and deterministic_manager.is_inside_tree() and off_path_manager.is_inside_tree())
	_check("player and simulation callbacks stay disabled after tree entry",
		not player.is_physics_processing() and not player.sim.is_physics_processing()
		and not manual_player.is_physics_processing() and not manual_player.sim.is_physics_processing())
	var callbacks_disabled := true
	for agent: Node in manager.agents:
		callbacks_disabled = callbacks_disabled and not agent.session.is_physics_processing() \
			and not agent.session.sim.is_physics_processing() and not agent.session.is_processing_input() \
			and not Input.joy_connection_changed.is_connected(agent.session._on_joy_connection_changed)
	_check("external companion sessions disable automatic callbacks and joystick subscriptions", callbacks_disabled)
	_check("manager, agent, and simulation ticks start aligned at zero",
		manager.accepted_ticks == 0 and player.sim.tick == 0)

	var event: SceneryCollision.Event = _damage_event(damage_proxy, 1)
	player._stage_scenery_damage(event)
	_check("normal player session stages the valid damage event",
		player._pending_scenery_tick == 1 and not player._pending_scenery_damage.is_empty(),
		"profile=%s id=%s energy=%.3f pending=%s" % [event.damage_profile, event.damage_id,
		event.impact_energy_j, str(player._pending_scenery_damage)])
	var shared_damage := {event.damage_id: {
		profile = event.damage_profile,
		state = SceneryDamage.impact_state(event.damage_profile, event.impact_energy_j),
		tick = 1,
		energy_j = event.impact_energy_j,
		point_ned = event.point_ned.duplicate(),
		normal_ned = event.normal_ned.duplicate(),
		velocity_ned = event.velocity_ned.duplicate(),
		obstacle_id = event.obstacle_id,
	}}
	# Model a world-authorized player commit at the tick boundary; the real collision
	# callback owns commit timing, while this fixture provides its validated snapshot.
	player._scenery_damage = shared_damage.duplicate(true)
	player.scenery_damage_changed.emit()
	var paired_bytes_equal := true
	var ticks_exactly_once := true
	var player_damage_imported := true
	for tick in PLAYER_PARITY_TICKS:
		var packet: Dictionary = _control_for_tick(tick)
		var player_ready: bool = _prepare_player_tick(player, packet)
		var manual_ready: bool = _prepare_player_tick(manual_player, packet)
		if player_ready:
			player.sim.step()
		if manual_ready:
			manual_player.sim.step()
		var expected_tick: int = tick + 1
		ticks_exactly_once = ticks_exactly_once and player_ready and manual_ready \
			and player.sim.tick == expected_tick and manual_player.sim.tick == expected_tick \
			and manager.accepted_ticks == expected_tick
		for agent: Node in manager.agents:
			ticks_exactly_once = ticks_exactly_once and agent.session.sim.tick == expected_tick
		paired_bytes_equal = paired_bytes_equal and _same_f64(player.sim.state, manual_player.sim.state) \
			and _same_f64(player.sim.aux, manual_player.sim.aux) \
			and _same_f64(player.sim.inputs, manual_player.sim.inputs)
		if tick == 0:
			player_damage_imported = not player.scenery_damage().is_empty()
			for agent: Node in manager.agents:
				player_damage_imported = player_damage_imported and agent.session.scenery_damage() == player.scenery_damage()
	_check("player before_step/stepped callbacks advance each companion exactly once", ticks_exactly_once,
		"player=%d manager=%d" % [player.sim.tick, manager.accepted_ticks])
	_check("fleet observations are sampled only on the 60 Hz planning cadence",
		manager.observation_batches == PLAYER_PARITY_TICKS / 4, str(manager.observation_batches))
	_check("three-agent fleet leaves player state, aux, and input bytes unchanged over 240 ticks",
		paired_bytes_equal, "with=%d without=%d" % [player.sim.tick, manual_player.sim.tick])
	_check("player-authored scenery damage imports after the shared tick", player_damage_imported,
		str(player.scenery_damage()))
	var companion_damage_guard := true
	for agent: Node in manager.agents:
		var prior_damage: Dictionary = agent.session.scenery_damage()
		var companion_event: SceneryCollision.Event = _damage_event(damage_proxy, 2)
		agent.session._stage_scenery_damage(companion_event)
		companion_damage_guard = companion_damage_guard and (
			agent.session.scenery_damage() == prior_damage
			and agent.session._pending_scenery_damage.is_empty())
	_check("companions cannot author shared scenery damage", companion_damage_guard)
	_check("off-path manager does not tick or create agents", off_path_manager.agents.is_empty()
		and off_path_manager.accepted_ticks == 0)

	var post_tick_refusal: Dictionary = manager.configure(player, field, "club_field", _requested_config(), false, false)
	_check("nonzero player tick refuses reconfiguration without replacing the fleet",
		not post_tick_refusal.get("ok", true) and _same_agent_refs(manager.agents, original_agents), str(post_tick_refusal))
	var tick_before_pause: int = player.sim.tick
	var accepted_before_pause: int = manager.accepted_ticks
	var agent_ticks_before_pause: Array[int] = []
	for agent: Node in manager.agents:
		agent_ticks_before_pause.append(agent.session.sim.tick)
	player.sim.set_paused(true)
	player._physics_process(1.0 / 240.0)
	player.sim._physics_process(1.0 / 240.0)
	var paused_stable: bool = player.sim.tick == tick_before_pause and manager.accepted_ticks == accepted_before_pause
	for index in manager.agents.size():
		paused_stable = paused_stable and manager.agents[index].session.sim.tick == agent_ticks_before_pause[index]
	_check("paused player callbacks do not advance companions", paused_stable)
	player.sim.set_paused(false)
	player.sim._fail_safe("companions manager test fault")
	var fault_tick: int = player.sim.tick
	var fault_accepted: int = manager.accepted_ticks
	player.sim.step()
	player.sim._physics_process(1.0 / 240.0)
	var fault_stable: bool = player.sim.tick == fault_tick and manager.accepted_ticks == fault_accepted
	for index in manager.agents.size():
		fault_stable = fault_stable and manager.agents[index].session.sim.tick == agent_ticks_before_pause[index]
	_check("faulted player callbacks do not advance companions", fault_stable)

	var manager_connections_removed := true
	var before_step_callback := Callable(manager, "_before_step")
	var after_step_callback := Callable(manager, "_after_step")
	var damage_callback := Callable(manager, "_scenery_changed")
	manager.remove_now()
	_check("remove_now clears every companion and child immediately",
		manager.status().removed and manager.agents.is_empty() and manager.get_child_count() == 0)
	var off_path_tick: int = manual_player.sim.tick
	var off_path_ready: bool = _prepare_player_tick(manual_player, _control_for_tick(0))
	if off_path_ready:
		manual_player.sim.step()
	_check("off-path no-agent callback remains inert after a player tick",
		off_path_manager.accepted_ticks == 0 and manual_player.sim.tick == off_path_tick + 1)
	off_path_manager.remove_now()
	root.remove_child(manager)
	var before_connected: bool = player.sim.before_step.is_connected(before_step_callback)
	var stepped_connected: bool = player.sim.stepped.is_connected(after_step_callback)
	var damage_connected: bool = player.scenery_damage_changed.is_connected(damage_callback)
	manager_connections_removed = not before_connected and not stepped_connected and not damage_connected
	manager.free()
	root.remove_child(deterministic_manager)
	deterministic_manager.remove_now()
	deterministic_manager.free()
	root.remove_child(off_path_manager)
	off_path_manager.free()
	_check("manager tree removal disconnects player observers", manager_connections_removed,
		"before=%s stepped=%s damage=%s" % [before_connected, stepped_connected, damage_connected])
	for session: FlightSession in [player, manual_player, second_player]:
		if session.is_inside_tree():
			root.remove_child(session)
		session.free()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_session_parity_gate()
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default Club field loads", loaded_field.get("ok", false), str(loaded_field.get("errors", [])))
	if not loaded_field.get("ok", false):
		print("companions manager: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var field: Dictionary = loaded_field.field
	var loaded_scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("default Club field scenery loads", loaded_scenery.get("ok", false), str(loaded_scenery.get("errors", [])))
	if not loaded_scenery.get("ok", false):
		print("companions manager: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var built_world: Dictionary = CollisionWorld.build(field, loaded_scenery.scenery)
	_check("Club field collision world builds", built_world.get("ok", false), str(built_world.get("errors", [])))
	if not built_world.get("ok", false):
		print("companions manager: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var damage_proxy: Dictionary = {}
	for proxy: Dictionary in built_world.world.get("proxies", []):
		var profile: String = str(proxy.get("damage_profile", "none"))
		if SceneryDamage.profile_is_valid(profile) and profile != "none" and not str(proxy.get("damage_id", "")).is_empty():
			damage_proxy = proxy
			break
	_check("Club field has a damageable proxy for coordinator-import coverage", not damage_proxy.is_empty())
	if damage_proxy.is_empty():
		print("companions manager: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	_run_manager_gate(field, built_world.world, damage_proxy)
	print("companions manager: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
