# Run: godot --headless --path . --script res://tests/test_companions_session.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const RB := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const STIK_ID := "jensen-das-ugly-stik-60"

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


func _new_aircraft_session(external: bool, aircraft_id: String) -> Session:
	var entry: Dictionary = Catalog.entry(aircraft_id)
	var session: Session = Session.new()
	session.input_enabled = false
	session.setup(str(entry.get("data", "")), aircraft_id)
	_check("%s %s session starts flyable" % [aircraft_id, "external" if external else "manual"],
		session.is_flyable())
	if external:
		_check("%s external driver configures while detached" % aircraft_id, session.configure_external_driver())
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


func _manual_tick(session: Session, packet: Dictionary) -> bool:
	session.commands = {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle}
	session.raw = session.commands.duplicate()
	session.sim.inputs = session._inputs()
	var previous_tick: int = session.sim.tick
	if not session._session_after_input() or session.sim.paused or not session.sim.fault_reason.is_empty():
		return false
	session.sim.step()
	return session.sim.tick == previous_tick + 1 and session.sim.fault_reason.is_empty()


func _run_avanti_external_actuator_parity() -> void:
	var manual: Session = _new_aircraft_session(false, AVANTI_ID)
	var external: Session = _new_aircraft_session(true, AVANTI_ID)
	var equipment_ready: bool = manual.gear_is_retractable() and external.gear_is_retractable() \
		and manual.flaps_available() and external.flaps_available() \
		and manual.sim.inputs.size() == 7 and external.sim.inputs.size() == 7
	_check("Avanti parity fixture exposes retractable gear, brakes, flaps, and seven inputs", equipment_ready)
	if not equipment_ready:
		manual.free()
		external.free()
		return
	manual.input_enabled = true
	var requests_ok: bool = manual.set_gear_down(true) and manual.set_wheel_brake(0.5) \
		and manual.set_flaps(1.0)
	manual.input_enabled = false
	_check("manual Avanti accepts matching gear, brake, and flap requests", requests_ok)
	var packet := {roll = 0.02, pitch = -0.01, yaw = 0.0, throttle = float(manual.start.throttle)}
	var external_packet: Dictionary = packet.duplicate(true)
	external_packet.gear_down = true
	external_packet.brake = 0.5
	external_packet.flaps = 1.0
	var staged: Dictionary = external.prepare_external_tick(external_packet)
	var manual_first: bool = _manual_tick(manual, packet)
	var external_first: bool = staged.get("ok", false) and external.step_external_tick()
	_check("manual and external Avanti actuator ticks are both accepted", manual_first and external_first,
		"stage=%s manual_tick=%s external_tick=%s" % [str(staged), str(manual_first), str(external_first)])
	_check("first Avanti external actuator tick matches every session boundary array",
		_same_tick(manual, external))
	var first_gear_extension: float = float(external.gear_state().extension)
	var first_flap_fraction: float = float(external.flap_state().actual)
	_check("external gear and flap AUX advance from their requested targets",
		first_gear_extension > 0.0 and first_gear_extension < 1.0 \
		and external.gear_state().target_down and first_flap_fraction > 0.0 and first_flap_fraction < 1.0,
		"gear=%.9f target_down=%s flap=%.9f" % [first_gear_extension,
		str(external.gear_state().target_down), first_flap_fraction])
	var next_packet := {roll = -0.03, pitch = 0.04, yaw = 0.01, throttle = float(manual.start.throttle)}
	var second_stage: Dictionary = external.prepare_external_tick(next_packet)
	var manual_second: bool = _manual_tick(manual, next_packet)
	var external_second: bool = second_stage.get("ok", false) and external.step_external_tick()
	_check("four-field external packet preserves omitted actuator demands", manual_second and external_second
		and external.sim.inputs.size() == 7 and external.sim.inputs[4] == 1.0
		and external.sim.inputs[5] == 0.5 and external.sim.inputs[6] == 1.0,
		"stage=%s inputs=%s" % [str(second_stage), str(external.sim.inputs)])
	_check("omitted gear, brake, and flap fields remain byte-identical to manual controls",
		_same_tick(manual, external) and external.gear_state().extension > first_gear_extension
		and external.flap_state().actual > first_flap_fraction)
	manual.free()
	external.free()


func _run_external_actuator_packet_atomicity() -> void:
	var external_avanti: Session = _new_aircraft_session(true, AVANTI_ID)
	var valid_avanti := {roll = 0.01, pitch = 0.02, yaw = -0.03, throttle = 0.55,
		gear_down = true, brake = 0.25, flaps = 0.75}
	var valid_stage: Dictionary = external_avanti.prepare_external_tick(valid_avanti)
	var pending_before_bad: Dictionary = external_avanti._external_pending_packet.duplicate(true)
	var commands_before_bad: Dictionary = external_avanti.commands.duplicate(true)
	var inputs_before_bad: PackedFloat64Array = external_avanti.sim.inputs.duplicate()
	var bad_avanti: Dictionary = valid_avanti.duplicate(true)
	bad_avanti.roll = -0.8
	bad_avanti.flaps = 1.01
	var invalid_result: Dictionary = external_avanti.prepare_external_tick(bad_avanti)
	_check("out-of-range optional actuator rejects without replacing a valid pending packet",
		valid_stage.get("ok", false) and not invalid_result.get("ok", true)
		and external_avanti._external_packet_ready
		and external_avanti._external_pending_packet == pending_before_bad
		and external_avanti.commands == commands_before_bad
		and _same_array(external_avanti.sim.inputs, inputs_before_bad), str(invalid_result))
	_check("the preserved Avanti actuator packet still executes exactly as staged",
		external_avanti.step_external_tick() and external_avanti.sim.tick == 1
		and external_avanti.sim.inputs.size() == 7 and external_avanti.sim.inputs[4] == 1.0
		and external_avanti.sim.inputs[5] == 0.25 and external_avanti.sim.inputs[6] == 0.75,
		str(external_avanti.sim.inputs))

	var external_stik: Session = _new_aircraft_session(true, STIK_ID)
	var valid_stik: Dictionary = _packet()
	var stik_stage: Dictionary = external_stik.prepare_external_tick(valid_stik)
	var stik_pending: Dictionary = external_stik._external_pending_packet.duplicate(true)
	var stik_commands: Dictionary = external_stik.commands.duplicate(true)
	var stik_inputs: PackedFloat64Array = external_stik.sim.inputs.duplicate()
	var unsupported := valid_stik.duplicate(true)
	unsupported.gear_down = true
	unsupported.brake = 0.5
	unsupported.flaps = 0.5
	var unsupported_result: Dictionary = external_stik.prepare_external_tick(unsupported)
	_check("Stik fixture has no retractable gear or flaps", not external_stik.gear_is_retractable()
		and not external_stik.flaps_available())
	_check("unsupported equipment rejects atomically without replacing the valid pending packet",
		stik_stage.get("ok", false) and not unsupported_result.get("ok", true)
		and external_stik._external_packet_ready and external_stik._external_pending_packet == stik_pending
		and external_stik.commands == stik_commands and _same_array(external_stik.sim.inputs, stik_inputs),
		str(unsupported_result))
	_check("the valid Stik controls still advance after unsupported equipment is rejected",
		external_stik.step_external_tick() and external_stik.sim.tick == 1,
		str(external_stik.sim.inputs))
	external_avanti.free()
	external_stik.free()


func _run_external_runway_first_tick() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default field loads for the Stik runway parity fixture", loaded_field.get("ok", false),
		str(loaded_field.get("errors", [])))
	if not loaded_field.get("ok", false):
		return
	var field: Dictionary = loaded_field.field
	var entry: Dictionary = Catalog.entry(STIK_ID)
	var manual: Session = Session.new()
	manual.start_choice = Session.START_RUNWAY
	manual.input_enabled = false
	manual.setup(str(entry.get("data", "")), STIK_ID)
	var external: Session = Session.new()
	external.start_choice = Session.START_RUNWAY
	external.input_enabled = false
	external.setup(str(entry.get("data", "")), STIK_ID)
	var manual_field_ok: bool = manual.set_field(field)
	var external_field_ok: bool = external.set_field(field)
	manual.reset()
	external.reset()
	var external_configured: bool = external.configure_external_driver()
	_check("manual and external sessions build matching explicit Stik runway starts",
		manual_field_ok and external_field_ok and external_configured
		and manual.start_error.is_empty() and external.start_error.is_empty()
		and manual.trace_meta().launch_choice == "runway" and external.trace_meta().launch_choice == "runway"
		and manual.sim.tick == 0 and external.sim.tick == 0
		and _same_array(manual.sim.state, external.sim.state)
		and _same_array(manual.sim.aux, external.sim.aux)
		and _same_array(manual.sim.inputs, external.sim.inputs),
		"manual=%s external=%s config=%s" % [manual.start_error, external.start_error, str(external_configured)])
	var packet := {roll = 0.0, pitch = 0.02, yaw = 0.0, throttle = 0.56}
	var staged: Dictionary = external.prepare_external_tick(packet)
	var manual_accepted: bool = _manual_tick(manual, packet)
	var external_accepted: bool = staged.get("ok", false) and external.step_external_tick()
	_check("manual and external Stik runway sessions both accept the first tick",
		manual_accepted and external_accepted and manual.sim.tick == 1 and external.sim.tick == 1,
		"stage=%s manual_tick=%s external_tick=%s" % [str(staged), str(manual_accepted), str(external_accepted)])
	_check("external runway-start first tick matches manual state and session arrays",
		_same_tick(manual, external))
	manual.free()
	external.free()


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
	_run_avanti_external_actuator_parity()
	_run_external_actuator_packet_atomicity()
	_run_external_runway_first_tick()
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
	var baseline_euler: PackedFloat64Array = Math3D.q_to_euler(spawned.start.state.slice(RB.ATT, RB.ATT + 4))
	var baseline_heading := 1.1
	var baseline_attitude: PackedFloat64Array = Math3D.q_from_euler(baseline_heading,
		baseline_euler[1], baseline_euler[2])
	var trim_state: PackedFloat64Array = spawned.start.state.duplicate()
	for axis: int in 4:
		trim_state[RB.ATT + axis] = baseline_attitude[axis]
	spawned.start.state = trim_state
	var heading_rad := -0.35
	var terrain: PackedFloat64Array = spawned.environment.terrain(north, east)
	_check("external airborne spawn accepts a finite local NED pose",
		spawned.external_spawn_airborne(north, east, height_m, heading_rad))
	var spawn_state: PackedFloat64Array = spawned.sim.state.duplicate()
	var spawn_euler: PackedFloat64Array = Math3D.q_to_euler(spawn_state.slice(RB.ATT, RB.ATT + 4))
	var nose_ned: PackedFloat64Array = Math3D.q_rotate(spawn_state.slice(RB.ATT, RB.ATT + 4),
		PackedFloat64Array([1.0, 0.0, 0.0]))
	var ground_velocity_ned: PackedFloat64Array = Math3D.q_rotate(spawn_state.slice(RB.ATT, RB.ATT + 4),
		spawn_state.slice(RB.VEL, RB.VEL + 3))
	var velocity_heading := atan2(ground_velocity_ned[1], ground_velocity_ned[0])
	_check("spawn sets local position and height above sampled terrain",
		spawned.sim.tick == 0 and absf(spawn_state[RB.POS] - north) < 1e-12 \
			and absf(spawn_state[RB.POS + 1] - east) < 1e-12 \
			and absf(spawn_state[RB.POS + 2] + terrain[0] + height_m) < 1e-10)
	_check("external spawn heading replaces a nonzero trim heading and preserves trim pitch/roll",
		absf(wrapf(spawn_euler[0] - heading_rad, -PI, PI)) < 1e-12 \
			and absf(spawn_euler[1] - baseline_euler[1]) < 1e-12 \
			and absf(spawn_euler[2] - baseline_euler[2]) < 1e-12)
	_check("spawned ground velocity follows the absolute nose heading",
		absf(wrapf(velocity_heading - heading_rad, -PI, PI)) < 0.02 \
			and absf(wrapf(atan2(nose_ned[1], nose_ned[0]) - heading_rad, -PI, PI)) < 1e-12)
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
