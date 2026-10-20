# Run: godot --headless --path . --script res://tests/test_companions_session.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _new_session(external: bool) -> Session:
	var session: Session = Session.new()
	session.input_enabled = false
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data)
	_check("%s session starts flyable" % ("external" if external else "manual"), session.is_flyable())
	if external:
		_check("external driver configures after setup while detached", session.configure_external_driver())
	return session


func _packet() -> Dictionary:
	return {roll = 0.17, pitch = -0.08, yaw = 0.11, throttle = 0.62}


func _string_packet() -> Dictionary:
	return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.5}


func _same_array(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return left.to_byte_array() == right.to_byte_array()


func _same_tick(left: Session, right: Session) -> bool:
	return left.sim.tick == right.sim.tick and left.sim.time() == right.sim.time() \
		and _same_array(left.sim.state, right.sim.state) and _same_array(left.sim.previous, right.sim.previous) \
		and _same_array(left.sim.aux, right.sim.aux) and _same_array(left.sim.inputs, right.sim.inputs) \
		and _same_array(left.sim.last_loads, right.sim.last_loads) and left.commands == right.commands


func _send_tick(session: Session, packet: Dictionary = {}) -> bool:
	var staged: Dictionary = session.prepare_external_tick(packet if not packet.is_empty() else _packet())
	return staged.get("ok", false) and session.step_external_tick()


func _damage_world() -> Dictionary:
	return {
		format = CollisionWorld.FORMAT,
		identity = "companions-session-test",
		cell_size_m = CollisionWorld.CELL_SIZE_M,
		proxies = [{id = "post", damage_id = "post", damage_profile = "wood"}],
		bins = {},
	}


func _damage_snapshot() -> Dictionary:
	return {"post": {
		profile = "wood",
		state = SceneryDamage.impact_state("wood", 25.0),
		tick = 1,
		energy_j = 25.0,
		point_ned = PackedFloat64Array([1.0, 2.0, 3.0]),
		normal_ned = PackedFloat64Array([0.0, 1.0, 0.0]),
		velocity_ned = PackedFloat64Array([4.0, 5.0, 6.0]),
		obstacle_id = "post",
	}}


func _initialize() -> void:
	var manual: Session = _new_session(false)
	var external: Session = _new_session(true)
	var packet := _packet()
	var original_commands: Dictionary = external.commands.duplicate(true)
	var original_inputs: PackedFloat64Array = external.sim.inputs.duplicate()
	_check("manual and external sessions begin from the same trimmed snapshot",
		_same_array(manual.sim.state, external.sim.state) and _same_array(manual.sim.aux, external.sim.aux))
	var staged: Dictionary = external.prepare_external_tick(packet)
	_check("valid trim-relative controls stage", staged.get("ok", false), str(staged))
	var pending_before_bad_packet: Dictionary = external._external_pending_packet.duplicate(true)
	var invalid_packet := packet.duplicate(true)
	invalid_packet.roll = 1.01
	var rejected: Dictionary = external.prepare_external_tick(invalid_packet)
	_check("out-of-range packet rejects atomically while preserving the staged packet",
		not rejected.get("ok", true) and external._external_packet_ready \
			and external._external_pending_packet == pending_before_bad_packet \
			and external.commands == original_commands and _same_array(external.sim.inputs, original_inputs), str(rejected))
	manual.commands = {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle}
	manual.raw = manual.commands.duplicate()
	manual.sim.inputs = manual._inputs()
	var manual_guard_ok: bool = manual._session_after_input()
	if manual_guard_ok:
		manual.sim.step()
	_check("ordinary session guard admits the manual tick", manual_guard_ok)
	_check("external packet tick matches the existing manual session tick",
		external.step_external_tick() and _same_tick(manual, external))
	_check("a consumed packet cannot step twice", not external.step_external_tick() and external.sim.tick == 1)
	var string_key_stage: Dictionary = external.prepare_external_tick(_string_packet())
	_check("JSON string-key packets also stage", string_key_stage.get("ok", false), str(string_key_stage))
	external._discard_external_packet()
	root.add_child(external)
	_check("external session and simulation automatic physics are disabled",
		not external.is_physics_processing() and not external.sim.is_physics_processing()
		and not external.is_processing_input())
	await physics_frame
	await physics_frame
	_check("tree physics callbacks do not advance an external flight", external.sim.tick == 1)

	var spawned: Session = _new_session(true)
	var north := 12.0
	var east := -8.0
	var height_m := 45.0
	var heading_rad := 0.35
	var terrain: PackedFloat64Array = spawned.environment.terrain(north, east)
	_check("external airborne spawn accepts a finite local NED pose",
		spawned.external_spawn_airborne(north, east, height_m, heading_rad))
	var spawn_state: PackedFloat64Array = spawned.sim.state.duplicate()
	_check("spawn sets local position and height above sampled terrain",
		spawned.sim.tick == 0 and absf(spawn_state[RB.POS] - north) < 1e-12 \
			and absf(spawn_state[RB.POS + 1] - east) < 1e-12 \
			and absf(spawn_state[RB.POS + 2] + terrain[0] + height_m) < 1e-10)
	_check("spawn rejects nonfinite poses without changing the reset state",
		not spawned.external_spawn_airborne(INF, east, height_m, heading_rad)
		and _same_array(spawn_state, spawned.sim.state))
	root.add_child(spawned)
	_check("external spawn is closed after tree entry", not spawned.external_spawn_airborne(north, east, height_m, heading_rad))
	_check("spawned flight accepts one external tick", _send_tick(spawned) and spawned.sim.tick == 1)
	spawned.reset()
	_check("external reset returns to the complete spawn pose at tick zero",
		spawned.sim.tick == 0 and _same_array(spawned.sim.state, spawn_state) and spawned.is_flyable())

	var held: Session = _new_session(true)
	held.hold("companion-test")
	var held_stage: Dictionary = held.prepare_external_tick(_packet())
	_check("held external session consumes without stepping", held_stage.ok
		and not held.step_external_tick() and held.sim.tick == 0 and not held._external_packet_ready)
	held.release("companion-test")
	held.resume()
	_check("explicit resume allows a fresh staged packet", _send_tick(held) and held.sim.tick == 1)
	held.reset()
	_check("external reset clears tick and restores trimmed controls", held.sim.tick == 0
		and held.commands.throttle == held.start.throttle and held.is_flyable())

	var faulted: Session = _new_session(true)
	faulted.sim._fail_safe("companion test fault")
	var fault_stage: Dictionary = faulted.prepare_external_tick(_packet())
	_check("faulted external session consumes but refuses a packet", fault_stage.ok
		and not faulted.step_external_tick() and faulted.sim.tick == 0 and not faulted._external_packet_ready)
	faulted.reset()
	_check("reset recovers a faulted external session", faulted.sim.fault_reason.is_empty()
		and faulted.sim.tick == 0 and faulted.is_flyable())

	var crashed: Session = _new_session(true)
	crashed.crash = {ticks_left = 2, why = "companion session test"}
	crashed.sim.set_paused(true)
	var first_crash_stage: Dictionary = crashed.prepare_external_tick(_packet())
	var first_crash_step: bool = crashed.step_external_tick()
	var second_crash_stage: Dictionary = crashed.prepare_external_tick(_packet())
	var second_crash_step: bool = crashed.step_external_tick()
	_check("crash packets advance the existing hold countdown without kernel ticks",
		first_crash_stage.ok and second_crash_stage.ok and not first_crash_step and not second_crash_step
		and crashed.sim.tick == 0 and crashed.crash.is_empty() and not crashed.sim.paused)

	var damage_owner: Session = _new_session(true)
	_check("external session installs coordinator scenery", damage_owner.set_collision_world(_damage_world()))
	var imported: Dictionary = _damage_snapshot()
	var damage_signal_count := [0]
	damage_owner.scenery_damage_changed.connect(func() -> void: damage_signal_count[0] += 1)
	_check("external damage snapshot imports and emits once",
		damage_owner.import_external_scenery_damage(imported, 1)
		and damage_owner.scenery_damage() == imported and damage_signal_count[0] == 1)
	var staged_event: SceneryCollision.Event = SceneryCollision.Event.new()
	staged_event.damage_id = "other"
	staged_event.damage_profile = "wood"
	staged_event.tick = 1
	staged_event.impact_energy_j = 25.0
	damage_owner._stage_scenery_damage(staged_event)
	_check("external sessions leave shared damage authoring to the coordinator",
		not damage_owner.scenery_damage().has("other"))
	var changed_source: Dictionary = imported.post.duplicate(true)
	changed_source.point_ned[0] = 99.0
	imported.post = changed_source
	_check("external damage import is deep-copied", damage_owner.scenery_damage().post.point_ned[0] == 1.0)
	var committed_before_bad_import: Dictionary = damage_owner.scenery_damage()
	var malformed_damage: Dictionary = _damage_snapshot()
	malformed_damage.post.obstacle_id = "missing-proxy"
	_check("invalid external damage leaves the prior snapshot unchanged",
		not damage_owner.import_external_scenery_damage(malformed_damage, 1)
		and damage_owner.scenery_damage() == committed_before_bad_import and damage_signal_count[0] == 1)
	_check("ordinary sessions cannot import coordinator damage",
		not manual.import_external_scenery_damage(_damage_snapshot(), 1))

	for session: Session in [manual, external, spawned, held, faulted, crashed, damage_owner]:
		if session.is_inside_tree():
			root.remove_child(session)
		session.free()
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
