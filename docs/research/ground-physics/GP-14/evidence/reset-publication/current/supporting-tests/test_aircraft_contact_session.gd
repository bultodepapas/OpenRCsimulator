extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const Hull := preload("res://physics/hull_contact.gd")
const World := preload("res://scenery/collision_world.gd")
const LakeLoader := preload("res://data/lake_loader.gd")

var checks := 0
var failures := 0

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_initial_checkpoint()
	_hull_lifecycle()
	_accepted_collision()
	_rejected_collision()
	_rejected_projection()
	_strike_checkpoint()
	_failed_reload()
	_water_transaction()
	print("AS-13 contact session: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _session(soft := false) -> Node:
	var s := Session.new()
	s.input_enabled = false
	s.soft_hull_contacts = soft
	s.setup()
	s.sim.continuous = PackedFloat64Array()
	for field: String in ["step_policy", "stage", "block_loads", "block_derivative",
		"stage_rotor_momentum", "block_aux"]:
		s.sim.model.set(field, Callable())
	s.sim.gravity = 0.0
	s.sim.model.loads = func(_body: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0, 0, 0, 0, 0, 0])
	s.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return aux
	s.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	return s

func _state(down: float, speed: float, sink := 0.0) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([0, 0, down]), PackedFloat64Array([speed, 0, sink]),
		PackedFloat64Array([1, 0, 0, 0]), PackedFloat64Array([0, 0, 0]))

func _initial_checkpoint() -> void:
	for soft: bool in [false, true]:
		var s := Session.new()
		s.soft_hull_contacts = soft
		s.setup()
		check("setup seeds tick zero history: %s" % soft, s.contact_events().tick == 0
			and not s.checkpoint().is_empty())
		s.reset()
		check("session reset keeps checkpoint valid: %s" % soft, not s.checkpoint().is_empty())
		s.free()
	var s := _session(true)
	check("touching reset is accepted", s.sim.reset(_state(0.0, 0.0)))
	check("touching reset seeds identities without events", not s.contact_events().active_hull_ids.is_empty()
		and s.contact_events().events.is_empty() and not s.checkpoint().is_empty())
	s.free()

func _hull_lifecycle() -> void:
	var s := _session(true)
	var lowest := -INF
	for index in range(2, s.aircraft.model.crash_hull.size(), 3):
		lowest = maxf(lowest, s.aircraft.model.crash_hull[index])
	check("clear initial state resets", s.sim.reset(_state(-lowest - 0.001, 4.0, 0.5)))
	check("reset has no events", s.contact_events().events.is_empty())
	s.sim.step()
	var first: Dictionary = s.contact_events()
	check("first accepted contact has a new event", not first.events.is_empty()
		and first.tick == 1 and first.events[0].lifecycle == "new")
	s.sim.step()
	var saved: Dictionary = s.checkpoint()
	check("persistent contact is not a repeated impact", not s.contact_events().events.is_empty()
		and s.contact_events().events[0].lifecycle == "persistent")
	check("contact snapshot is included in a valid checkpoint", not saved.is_empty() and saved.has("contact_state"))
	if saved.is_empty():
		s.free()
		return
	var detached: Dictionary = s.contact_events()
	detached.events.clear()
	detached.active_hull_ids.clear()
	check("public events cannot mutate the journal", not s.contact_events().events.is_empty())
	s.sim.step()
	var replay_bytes := var_to_bytes(s.contact_events())
	check("checkpoint restores history", s.restore_checkpoint(saved)
		and var_to_bytes(s.contact_events()) == var_to_bytes(saved.contact_state))
	s.sim.step()
	check("contact replay is byte exact", var_to_bytes(s.contact_events()) == replay_bytes)
	var before := var_to_bytes(s.sim.checkpoint())
	var before_events := var_to_bytes(s.contact_events())
	for mutation: String in ["tick", "id", "event", "extra", "policy"]:
		var bad: Dictionary = saved.duplicate(true)
		match mutation:
			"tick": bad.contact_state.tick += 1
			"id": bad.contact_state.active_hull_ids.append("not-a-probe")
			"event": bad.contact_state.events[0].tick = -1
			"extra": bad.contact_state.unrecognized = true
			"policy": bad.contact_state.events[0].policy = "unknown-law"
		check("bad history rejected atomically: " + mutation, not s.restore_checkpoint(bad)
			and var_to_bytes(s.sim.checkpoint()) == before and var_to_bytes(s.contact_events()) == before_events)
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("contact_state")
	check("legacy checkpoint seeds contact state without inventing events", s.restore_checkpoint(legacy)
		and s.contact_events().events.is_empty() and not s.contact_events().active_hull_ids.is_empty())
	s.sim.step()
	check("legacy ongoing contact remains persistent", s.contact_events().events[0].lifecycle == "persistent")
	# Reverse the motion after a valid boundary; this fixture has no forces, so exit is deterministic.
	s.sim.state[RB.VEL + 2] = -2.0
	s.sim.step()
	var exited: Dictionary = s.contact_events()
	check("contact exit emits ended events once", not exited.events.is_empty()
		and exited.events[0].lifecycle == "ended" and exited.active_hull_ids.is_empty())
	s.sim.step()
	var ended: Dictionary = s.contact_events()
	check("ended contact is not repeated", ended.active_hull_ids.is_empty() and ended.events.is_empty())
	# Reset a stopped/airborne state; no old contact or propeller history survives.
	s.sim.reset(_state(-30.0, 0.0))
	check("reset clears lifecycle and strike history", s.contact_events().tick == 0
		and s.contact_events().events.is_empty() and s.contact_events().active_hull_ids.is_empty())
	s.free()

func _install_obstacle(s: Node) -> void:
	var built: Dictionary = World.build({pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []},
		{groups = []}, {fixtures = [{id = "contact-test", type = "flood", north = 5.0, east = 0.0, height = 8.0}]})
	check("world fixture installs", built.ok and s.set_collision_world(built.world))
	# Actual catalog hull retained: its forwardmost probe reaches the obstacle during this large sweep.
	check("collision fixture resets", s.sim.reset(_state(-4.0, 2400.0)))

func _accepted_collision() -> void:
	var s := _session()
	_install_obstacle(s)
	var observed := [false]
	s.sim.stepped.connect(func(tick: int, _t: float, _body: PackedFloat64Array, _loads: PackedFloat64Array,
		_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		if tick == 1:
			observed[0] = not s.contact_events().events.is_empty() and not s.crash.is_empty())
	s.sim.step()
	check("terminal impact commits before downstream observers", observed[0])
	check("accepted collision keeps terminal behavior", s.sim.tick == 1 and s.sim.paused and not s.crash.is_empty())
	check("terminal journal contains one scene impact", s.contact_events().events.size() == 1
		and s.contact_events().events[0].source == "scenery" and s.contact_events().events[0].response == "terminal")
	var saved: Dictionary = s.checkpoint()
	check("accepted impact checkpoint is valid", not saved.is_empty())
	if not saved.is_empty():
		var bad: Dictionary = saved.duplicate(true)
		var event: Dictionary = bad.contact_state.events[0]
		event.contact_id = "unknown-obstacle"
		event.event_id = "as13:impact:scenery:%d:new:%d:%s" % [event.tick, event.contact_id.length(), event.contact_id]
		check("foreign obstacle rejected without changing accepted impact", not s.restore_checkpoint(bad)
			and not s.crash.is_empty() and var_to_bytes(s.contact_events()) == var_to_bytes(saved.contact_state))
		check("accepted impact restores exact event record", s.restore_checkpoint(saved)
			and var_to_bytes(s.contact_events()) == var_to_bytes(saved.contact_state))
	s.free()

func _rejected_collision() -> void:
	var s := _session()
	_install_obstacle(s)
	var published := [0]
	s.contact_events_changed.connect(func() -> void: published[0] += 1)
	var before := var_to_bytes(s.contact_events())
	var state: PackedByteArray = s.sim.state.to_byte_array()
	s.sim.model.post_tick = func(previous: PackedFloat64Array, candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
		s._resolve_collision_step(previous, candidate, tick)
		check("candidate crash is still private", s.crash.is_empty() and s.last_scenery_event() == null)
		return PackedFloat64Array([NAN])
	s.sim.step()
	check("rejected tick rolls back the body", s.sim.tick == 0 and not s.sim.fault_reason.is_empty()
		and s.sim.state.to_byte_array() == state)
	check("rejected tick emits no crash, damage or event", s.crash.is_empty() and s.last_scenery_event() == null
		and s.scenery_damage().is_empty() and var_to_bytes(s.contact_events()) == before)
	check("rejected tick discards pending impact", s._pending_crash == null and s._pending_contact_tick == -1)
	check("rejected tick notifies no contact consumer", published[0] == 0)
	s.free()

func _strike_checkpoint() -> void:
	var s := _session(true)
	# The strike detector is independently tested physically; here exercise its real boundary and saved latch.
	var body := _state(-30.0, 0.0)
	var disc: Dictionary = s._prop_disc
	var depth: Dictionary = Hull.prop_disc_depth(body, disc)
	body[RB.POS + 2] += -float(depth.depth) + 0.001
	check("strike state resets", s.sim.reset(body))
	var observed: Array[Dictionary] = []
	s.contact_events_changed.connect(func() -> void: observed.append(s.contact_events()))
	s._check_prop_strike()
	check("strike event stops the engine once", not s.prop_strike.is_empty() and not s.engine_running
		and s.contact_events().events.size() == 1 and s.contact_events().events[0].response == "engine_stop_continue")
	check("between-step strike notifies event consumers", observed.size() == 1 and observed[0].events.size() == 1
		and observed[0].events[0].event_type == "strike")
	var saved: Dictionary = s.checkpoint()
	check("strike checkpoint is valid", not saved.is_empty())
	if not saved.is_empty():
		var exact := var_to_bytes(s.contact_events())
		s._check_prop_strike()
		check("repeated strike check creates no duplicate", var_to_bytes(s.contact_events()) == exact)
		check("latched strike notifies consumers only once", observed.size() == 1)
		s.sim.reset(_state(-30.0, 0.0))
		check("restore preserves the broken propeller latch", s.restore_checkpoint(saved)
			and var_to_bytes(s.contact_events()) == exact and not s.prop_strike.is_empty())
	s.free()

func _rejected_projection() -> void:
	var s := _session()
	s.sim.continuous = PackedFloat64Array([0.0])
	s.sim.model.block_loads = func(_body: PackedFloat64Array, _extra: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0, 0, 0, 0, 0, 0])
	s.sim.model.block_derivative = func(_body: PackedFloat64Array, _extra: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0])
	s.sim.model.block_aux = func(_extra: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
		return aux
	_install_obstacle(s)
	var before := var_to_bytes(s.contact_events())
	var before_body: PackedByteArray = s.sim.state.to_byte_array()
	# Fail after the valid swept collision, at the final projection before commit.
	s.sim.model.block_aux = func(_extra: PackedFloat64Array, _aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	s.sim.step()
	check("projection failure rolls back the valid contact body", s.sim.tick == 0
		and not s.sim.fault_reason.is_empty() and s.sim.state.to_byte_array() == before_body)
	check("projection failure publishes no impact or damage", s.crash.is_empty()
		and s.last_scenery_event() == null and s.scenery_damage().is_empty()
		and var_to_bytes(s.contact_events()) == before and s._pending_contact_tick == -1)
	s.free()

func _failed_reload() -> void:
	var s := Session.new()
	s.soft_hull_contacts = true
	s.setup()
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var depth: Dictionary = Hull.prop_disc_depth(body, s._prop_disc)
	body[RB.POS + 2] += -float(depth.depth) + 0.001
	check("reload fixture resets", s.sim.reset(body))
	s._check_prop_strike()
	var before := var_to_bytes(s.contact_events())
	var before_body: PackedByteArray = s.sim.state.to_byte_array()
	# Fail after preparation commits a valid aircraft, during its new-flight reset.
	s.resetting.connect(func() -> void: s.sim.mass = 0.0, CONNECT_ONE_SHOT)
	var reason: String = s.reload()
	check("failed reload restores previous accepted body", reason.begins_with("reload failed;")
		and s.sim.fault_reason.is_empty() and s.sim.state.to_byte_array() == before_body)
	check("failed reload restores contact and broken-propeller history", var_to_bytes(s.contact_events()) == before
		and not s.prop_strike.is_empty() and not s.checkpoint().is_empty())
	s.free()

func _water_transaction() -> void:
	var loaded: Dictionary = LakeLoader.load_from("res://data/fields/lake.json")
	for reject: bool in [false, true]:
		var s := _session()
		check("water fixture installs", loaded.ok and s.set_lake_context(loaded.lake))
		var body := _state(-1.0, 0.0, 480.0)
		body[RB.POS] = 110.0
		body[RB.POS + 1] = 125.0
		check("water fixture resets", s.sim.reset(body))
		var before := var_to_bytes(s.contact_events())
		if reject:
			s.sim.model.post_tick = func(previous: PackedFloat64Array, candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
				s._resolve_collision_step(previous, candidate, tick)
				check("water stop stays inside transaction", not s.engine_running and s.crash.is_empty()
					and s.last_lake_event() == null)
				return PackedFloat64Array([NAN])
		s.sim.step()
		if reject:
			check("rejected water impact restores engine and publishes nothing", s.sim.tick == 0 and s.engine_running
				and s.crash.is_empty() and s.last_lake_event() == null and var_to_bytes(s.contact_events()) == before)
		else:
			check("accepted water impact stops engine and publishes bound event", s.sim.tick == 1 and not s.engine_running
				and s.contact_events().events.size() == 1 and s.contact_events().events[0].source == "lake")
			var saved: Dictionary = s.checkpoint()
			check("water checkpoint carries validated events", not saved.is_empty())
			if not saved.is_empty():
				var bad: Dictionary = saved.duplicate(true)
				var event: Dictionary = bad.contact_state.events[0]
				event.lake_id = "foreign"
				event.contact_id = "lake:foreign:water"
				event.event_id = "as13:impact:lake:%d:new:%d:%s" % [event.tick, event.contact_id.length(), event.contact_id]
				check("foreign lake event is refused atomically", not s.restore_checkpoint(bad)
					and var_to_bytes(s.contact_events()) == var_to_bytes(saved.contact_state))
				check("water event checkpoint restores exactly", s.restore_checkpoint(saved)
					and var_to_bytes(s.contact_events()) == var_to_bytes(saved.contact_state))
		s.free()
