# CR-22a: production crash presentation leaves the flight state authoritative and cleans up per fleet.
# Run: godot --headless --path . --script res://tests/test_crash_integration.gd
extends SceneTree

const MainScene = preload("res://main.tscn")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for aircraft_id: String in Catalog.ids():
		await _test_aircraft(aircraft_id)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _test_aircraft(aircraft_id: String) -> void:
	var base_bus_count: int = AudioServer.bus_count
	var base_root_children: int = root.get_child_count()
	var enabled: Variant = _make_main(aircraft_id, true, "CrashEnabled")
	var disabled: Variant = _make_main(aircraft_id, false, "CrashDisabled")
	var enabled_session: Variant = enabled.get("session")
	var disabled_session: Variant = disabled.get("session")
	if enabled_session == null or disabled_session == null:
		_check("%s: both production sessions initialize" % aircraft_id, false)
		enabled.queue_free()
		disabled.queue_free()
		await process_frame
		await process_frame
		return
	enabled_session.input_enabled = false
	disabled_session.input_enabled = false
	_check("%s: effects-on production path disables legacy auto-restart" % aircraft_id,
		enabled.get("_crash_director") != null and not enabled_session.crash_auto_restart)
	_check("%s: effects-off production path keeps legacy auto-restart" % aircraft_id,
		disabled.get("_crash_director") == null and disabled_session.crash_auto_restart)

	var first_tick: int = enabled_session.sim.tick
	var frame_guard := 0
	while (enabled_session.sim.tick < first_tick + 100 or disabled_session.sim.tick < first_tick + 100) and frame_guard < 500:
		await physics_frame
		frame_guard += 1
	var enabled_checkpoint: Dictionary = enabled_session.sim.checkpoint()
	var disabled_checkpoint: Dictionary = disabled_session.sim.checkpoint()
	_check("%s: both healthy flights reach the same 100-tick checkpoint" % aircraft_id,
		enabled_session.sim.tick == first_tick + 100 and disabled_session.sim.tick == first_tick + 100)
	_check("%s: healthy flight checkpoint is valid" % aircraft_id,
		not enabled_checkpoint.is_empty() and not disabled_checkpoint.is_empty())
	_check("%s: healthy physics is identical with crash effects on or off through 100 ticks" % aircraft_id,
		enabled_checkpoint == disabled_checkpoint)

	disabled.queue_free()
	await process_frame
	await process_frame
	var director: Variant = enabled.get("_crash_director")
	var session: Variant = enabled.get("session")
	if director == null or session == null:
		_check("%s: production crash director exists" % aircraft_id, false)
		enabled.queue_free()
		await process_frame
		await process_frame
		_check("%s: cleanup restores root nodes and audio buses" % aircraft_id,
			root.get_child_count() == base_root_children and AudioServer.bus_count == base_bus_count)
		return

	session.input_enabled = false
	session.set_physics_process(false)
	var airplane: Dictionary = enabled.get("_airplane")
	var source_root: Node3D = airplane.get("root") as Node3D
	var source_propeller: Node3D = airplane.get("propeller") as Node3D
	var source_root_id: int = source_root.get_instance_id() if source_root != null else 0
	var source_propeller_id: int = source_propeller.get_instance_id() if source_propeller != null else 0
	var source_signature: PackedStringArray = _subtree_signature(source_root) if source_root != null else PackedStringArray()
	var hinge_ids: Dictionary = _hinge_ids(airplane)
	var pool_ids: PackedInt64Array = _instance_ids(director.wreck._bodies)
	var twin_id: int = director.wreck._twin.get_instance_id()

	var impact_state: PackedFloat64Array = _place_hull_contact(session)
	_check("%s: generated state intersects this aircraft's own crash hull" % aircraft_id,
		session.touches_ground(impact_state))
	session.sim.state = impact_state.duplicate()
	session.sim.previous = impact_state.duplicate()
	session.sim.set_paused(false)
	var before_crash: Dictionary = session.sim.checkpoint()
	session._physics_process(session.sim.dt())
	var after_crash: Dictionary = session.sim.checkpoint()
	_check("%s: production detects a typed hull-contact crash" % aircraft_id,
		not session.crash.is_empty() and session.crash.impact.trigger == "hull_contact")
	_check("%s: crash detection preserves the complete simulation checkpoint" % aircraft_id,
		not before_crash.is_empty() and before_crash == after_crash)
	director.update(session.sim.dt())
	_check("%s: crash director and disposable wreck presentation become active" % aircraft_id,
		director.active and director.effects._active and director.wreck.stats().started
			and int(director.wreck.stats().active_body_count) > 0)
	_check("%s: source aircraft is hidden while its disposable wreck is active" % aircraft_id,
		not source_root.visible)
	var audio: Variant = director.audio
	var renders_audio := AudioServer.get_driver_name() != "Dummy"
	if renders_audio:
		_check("%s: crash produces at least one audio one-shot" % aircraft_id,
			audio.active_voice_count() > 0)
	else:
		print("skip %s: Dummy has no playback; native integration covers audio" % aircraft_id)

	# Allow the presentation bodies to advance before pausing, then compare their full visible state.
	for _frame in 3:
		await physics_frame
	_check("%s: source-airplane shadow stays hidden during the wreck" % aircraft_id,
		not enabled.get("_shadow").visible)
	var body_snapshot: Array[Dictionary] = _visible_body_snapshot(director.wreck._bodies)
	var emitter_states: Array[bool] = []
	for emitter: CPUParticles3D in director.effects.emitters:
		emitter_states.append(emitter.emitting)
	session.hold("crash-integration")
	director.update(session.sim.dt())
	for _frame in 3:
		await physics_frame
	_check("%s: user hold freezes every visible wreck body" % aircraft_id,
		director.wreck.stats().paused == true and _visible_bodies_unchanged(body_snapshot))
	_check("%s: user hold pauses all particle emitters" % aircraft_id,
		director.effects._paused == true and _emitters_held(director.effects.emitters, emitter_states))
	if renders_audio:
		_check("%s: user hold mutes crash audio" % aircraft_id,
			_audio_is_held(audio))

	var impact_snapshot: RefCounted = session.crash.impact
	var held_ticks: int = int(session.crash.ticks_left)
	var held_simulation: Dictionary = session.sim.checkpoint()
	session.release("crash-integration")
	for _tick in 361:
		session._physics_process(session.sim.dt())
	_check("%s: presentation crash never auto-restarts after 361 physics callbacks" % aircraft_id,
		not session.crash.is_empty() and session.sim.tick == impact_snapshot.tick
			and session.crash.impact == impact_snapshot and session.crash.ticks_left == held_ticks
			and session.sim.checkpoint() == held_simulation and director.active)

	session.reset()
	director.update(session.sim.dt())
	var effects_after_reset: Dictionary = director.effects.stats()
	var wreck_after_reset: Dictionary = director.wreck.stats()
	_check("%s: explicit reset clears report, wreck bodies, marks, particles and fire" % aircraft_id,
		not director.active and director.report.is_empty() and not wreck_after_reset.started
			and int(wreck_after_reset.active_body_count) == 0 and int(effects_after_reset.splinters) == 0
			and int(effects_after_reset.marks) == 0 and float(effects_after_reset.fire) == 0.0
			and _effects_are_clear(director.effects) and _wreck_is_clear(director.wreck))
	_check("%s: explicit reset stops and clears crash audio" % aircraft_id,
		audio.active_voice_count() == 0 and not audio._fire_voice.playing)
	_check("%s: original airplane, propeller and every hinge remain intact after reset" % aircraft_id,
		source_root != null and is_instance_valid(source_root) and source_root.visible
			and source_root.get_parent() == enabled and source_root.get_instance_id() == source_root_id
			and _subtree_signature(source_root) == source_signature
			and source_propeller != null and is_instance_valid(source_propeller)
			and source_propeller.get_instance_id() == source_propeller_id and _hinges_match(airplane, hinge_ids))

	var second_state: PackedFloat64Array = _place_hull_contact(session)
	session.sim.state = second_state.duplicate()
	session.sim.previous = second_state.duplicate()
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	director.update(session.sim.dt())
	_check("%s: a second hull crash reuses the prepared wreck body and mesh pools" % aircraft_id,
		director.active and session.crash.impact.trigger == "hull_contact"
			and _instance_ids(director.wreck._bodies) == pool_ids
			and director.wreck._twin.get_instance_id() == twin_id)

	enabled.queue_free()
	await process_frame
	await process_frame
	_check("%s: cleanup leaves no production scene orphan or audio bus" % aircraft_id,
		root.get_child_count() == base_root_children and AudioServer.bus_count == base_bus_count)


func _make_main(aircraft_id: String, effects_enabled: bool, node_name: String) -> Variant:
	var scene: Variant = MainScene.instantiate()
	scene.name = node_name
	scene.set("aircraft_id", aircraft_id)
	scene.set("crash_effects_enabled", effects_enabled)
	root.add_child(scene)
	return scene


func _place_hull_contact(session: Variant) -> PackedFloat64Array:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var attitude: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest_down := -INF
	for index in range(0, hull.size(), 3):
		var point: PackedFloat64Array = PackedFloat64Array([hull[index], hull[index + 1], hull[index + 2]])
		var world_point: PackedFloat64Array = M.q_rotate(attitude, point)
		deepest_down = maxf(deepest_down, world_point[2])
	state[RB.POS + 2] = -deepest_down + 0.001
	return state


func _visible_body_snapshot(bodies: Array) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for body: RigidBody3D in bodies:
		if body.visible:
			snapshot.append({body = body, transform = body.global_transform,
				linear = body.linear_velocity, angular = body.angular_velocity})
	return snapshot


func _visible_bodies_unchanged(snapshot: Array[Dictionary]) -> bool:
	if snapshot.is_empty():
		return false
	for record: Dictionary in snapshot:
		var body: RigidBody3D = record.body as RigidBody3D
		if body == null or not is_instance_valid(body) or not body.freeze \
			or body.global_transform != record.transform or body.linear_velocity != record.linear \
			or body.angular_velocity != record.angular:
			return false
	return true


func _emitters_held(emitters: Array, initial_states: Array[bool]) -> bool:
	if emitters.size() != initial_states.size() or emitters.is_empty():
		return false
	for index in emitters.size():
		var emitter: CPUParticles3D = emitters[index]
		if emitter.speed_scale != 0.0 or emitter.emitting != initial_states[index]:
			return false
	return true


func _audio_is_held(audio: Variant) -> bool:
	if audio.get("_user_paused") != true:
		return false
	var has_impact_voice := false
	for index in audio._voices.size():
		var voice: AudioStreamPlayer3D = audio._voices[index]
		if float(audio._voice_gain[index]) > 0.0:
			has_impact_voice = true
			if voice.volume_db > -79.0:
				return false
	return has_impact_voice


func _effects_are_clear(effects: Variant) -> bool:
	for emitter: CPUParticles3D in effects.emitters:
		if emitter.emitting or emitter.visible or emitter.speed_scale != 1.0:
			return false
	for mark: MeshInstance3D in effects.marks:
		if mark.visible:
			return false
	return effects.fragments.multimesh.visible_instance_count == 0 and not effects.light.visible


func _wreck_is_clear(wreck: Variant) -> bool:
	for body: RigidBody3D in wreck._bodies:
		if body.visible or not body.freeze or body.collision_layer != 0 or body.collision_mask != 0 \
			or body.linear_velocity != Vector3.ZERO or body.angular_velocity != Vector3.ZERO:
			return false
	return not wreck._twin.visible


func _hinge_ids(airplane: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	for hinge_name: String in airplane.get("hinges", {}).keys():
		var hinge: Node = _hinge_node(airplane.hinges[hinge_name])
		if hinge != null:
			ids[hinge_name] = hinge.get_instance_id()
	return ids


func _hinges_match(airplane: Dictionary, expected: Dictionary) -> bool:
	var hinges: Dictionary = airplane.get("hinges", {})
	if hinges.size() != expected.size() or hinges.is_empty():
		return false
	for hinge_name: String in expected:
		var hinge: Node = _hinge_node(hinges.get(hinge_name))
		if hinge == null or not is_instance_valid(hinge) or hinge.get_instance_id() != int(expected[hinge_name]):
			return false
	return true


func _hinge_node(value: Variant) -> Node:
	if value is Node:
		return value
	if value is Dictionary:
		return value.get("node") as Node
	return null


func _subtree_signature(node: Node) -> PackedStringArray:
	var signature := PackedStringArray()
	_append_subtree_signature(node, signature)
	return signature


func _append_subtree_signature(node: Node, signature: PackedStringArray) -> void:
	if node == null or not is_instance_valid(node):
		return
	signature.append("%d:%s:%s" % [node.get_instance_id(), node.name, node.get_class()])
	for child: Node in node.get_children():
		_append_subtree_signature(child, signature)


func _instance_ids(nodes: Array) -> PackedInt64Array:
	var ids := PackedInt64Array()
	for node: Node in nodes:
		ids.append(node.get_instance_id())
	return ids
