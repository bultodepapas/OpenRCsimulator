extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Loader := preload("res://data/lake_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const Session := preload("res://sim/flight_session.gd")

var _count: int = 0
var _failures: int = 0

func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from("res://data/fields/lake.json")
	_check("normalized lake loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var lake: Dictionary = loaded.lake
	_test_context_and_callback(lake)
	_test_water_entry_without_scenery(lake)
	_test_checkpoint_identity(lake)
	_test_earliest_event(lake)
	_test_outside_parity(lake)
	print("%d lake session checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

func _test_context_and_callback(lake: Dictionary) -> void:
	var session: Session = _new_session()
	_check("empty context leaves post-step callback unset", not session.sim.model.post_tick.is_valid())
	_check("lake context accepts normalized geometry and attaches callback", session.set_lake_context(lake)
		and session.sim.model.post_tick.is_valid())
	_check("lake-only callback survives empty scenery-world installation",
		session.set_collision_world({}) and session.sim.model.post_tick.is_valid())
	var detached: Dictionary = session.lake_context()
	detached["id"] = "mutated"
	_check("lake getter returns detached geometry", str(session.lake_context().get("id", "")) == str(lake.id))
	var stale: Dictionary = lake.duplicate(true)
	stale["identity"] = "0".repeat(64)
	_check("stale normalized identity is rejected", not session.set_lake_context(stale)
		and str(session.lake_context().get("identity", "")) == str(lake.identity))
	_check("empty context disables callback at tick zero", session.set_lake_context({})
		and session.lake_context().is_empty() and not session.sim.model.post_tick.is_valid())

func _test_water_entry_without_scenery(lake: Dictionary) -> void:
	var session: Session = _new_session(lake)
	_check("lake sweep is installed without scenery proxies", session.collision_world().is_empty()
		and session.sim.model.post_tick.is_valid())
	_set_direct_state(session, [110.0, 125.0, -1.0], [0.0, 0.0, 480.0])
	session.sim.step()
	var event: LakeCollision.WaterEvent = session.last_lake_event()
	_check("high-speed sim.step enters water through the session callback", session.sim.tick == 1
		and event != null and event.trigger == "water" and event.obstacle_kind == "water"
		and event.damage_profile == "none" and not session.crash.is_empty(), str(event))
	_check("water crash stops the engine", not session.engine_running)
	_check("water impact is retained and pauses at the swept contact", session.sim.paused
		and session.crash.get("impact") == event and event.point_ned[2] > 0.0)
	var accepted_identity: String = str(session.lake_context().get("identity", ""))
	session.reset()
	_check("reset keeps lake identity and clears event/crash state", str(session.lake_context().get("identity", "")) == accepted_identity
		and session.last_lake_event() == null and session.crash.is_empty())

func _test_checkpoint_identity(lake: Dictionary) -> void:
	var session: Session = _new_session(lake)
	var checkpoint: Dictionary = session.checkpoint()
	_check("lake checkpoint records format, identity, and trace header", checkpoint.get("format", "") == "openrc-flight-checkpoint v7"
		and checkpoint.get("lake_identity", "") == lake.identity and session.trace_meta().get("lake_identity", "") == lake.identity)
	var other: Dictionary = lake.duplicate(true)
	other["id"] = str(lake.id) + "_other"
	other["identity"] = Loader.identity(other)
	_check("identity mismatch cannot restore another basin", session.set_lake_context(other)
		and not session.restore_checkpoint(checkpoint))
	_check("matching basin checkpoint restores paused and retains context", session.set_lake_context(lake)
		and session.restore_checkpoint(checkpoint) and session.sim.paused
		and str(session.lake_context().get("identity", "")) == str(lake.identity))

func _test_earliest_event(lake: Dictionary) -> void:
	var bank_session: Session = _new_collision_session(lake)
	var late_proxy: Dictionary = _proxy("late-bank-scenery", 110.0, 174.5, 0.5, 0.15, 0.1, 0.15)
	_check("later scenery proxy installs", bank_session.set_collision_world(_world(late_proxy)))
	var bank_previous := _state([110.0, 177.0, 0.5], [0.0, -100.0, 0.0])
	var bank_candidate := _state([110.0, 174.0, 0.5], [0.0, -100.0, 0.0])
	_accept_sweep(bank_session, bank_previous, bank_candidate)
	_check("earlier bank TOI wins over later scenery", bank_session.last_lake_event() != null
		and bank_session.last_lake_event().trigger == "lake_bank" and bank_session.last_scenery_event() == null
		and str(bank_session.crash.get("impact").trigger) == "lake_bank")
	var scenery_session: Session = _new_collision_session(lake)
	var early_proxy: Dictionary = _proxy("early-water-scenery", 110.0, 125.0, -0.4, 0.2, 0.05, 0.2)
	_check("earlier water-path scenery proxy installs", scenery_session.set_collision_world(_world(early_proxy)))
	var water_previous := _state([110.0, 125.0, -1.0], [0.0, 0.0, 480.0])
	var water_candidate := _state([110.0, 125.0, 1.0], [0.0, 0.0, 480.0])
	_accept_sweep(scenery_session, water_previous, water_candidate)
	_check("earlier scenery TOI wins over later water entry", scenery_session.last_scenery_event() != null
		and scenery_session.last_lake_event() == null and str(scenery_session.crash.get("impact").trigger) == "scenery")

## Supply the controlled geometric sweep through the actual simulation acceptance boundary.
func _accept_sweep(session: Session, previous: PackedFloat64Array, candidate: PackedFloat64Array) -> void:
	# These fixtures replace the aircraft's geometry; disable propulsion callbacks tied to its original gear.
	session.sim.continuous = PackedFloat64Array()
	for field: String in ["step_policy", "stage", "block_loads", "block_derivative",
		"stage_rotor_momentum", "block_aux"]:
		session.sim.model.set(field, Callable())
	_set_direct_state(session, Array(previous.slice(RB.POS, RB.POS + 3)), Array(previous.slice(RB.VEL, RB.VEL + 3)))
	session.sim.model.post_tick = func(_previous: PackedFloat64Array, _candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
		var filtered: PackedFloat64Array = session._resolve_collision_step(previous, candidate, tick)
		_check("unaccepted sweep keeps impact private", session.crash.is_empty()
			and session.last_lake_event() == null and session.last_scenery_event() == null)
		return filtered
	session.sim.step()
	_check("controlled sweep commits", session.sim.tick == 1 and session.sim.fault_reason.is_empty())

func _test_outside_parity(lake: Dictionary) -> void:
	var dry: Session = _new_session()
	var bounded: Session = _new_session(lake)
	var initial := _state([0.0, 0.0, -100.0], [15.0, 0.0, 0.0])
	_check("dry and lake sessions accept identical airborne reset", dry.sim.reset(initial) and bounded.sim.reset(initial))
	dry.sim.set_paused(false)
	bounded.sim.set_paused(false)
	dry.sim.step()
	bounded.sim.step()
	var a: Dictionary = dry.sim.checkpoint()
	var b: Dictionary = bounded.sim.checkpoint()
	var same: bool = true
	for key: String in ["tick", "state", "previous", "aux", "inputs", "modes", "continuous", "last_loads"]:
		if a.get(key) != b.get(key):
			same = false
	_check("airborne tick outside lake bank is bit-identical", same)
	var on_dry_ground := _state([0.0, 0.0, 0.05], [0.0, 0.0, 0.0])
	_check("dry-ground hull semantics remain unchanged outside lake", dry.touches_ground(on_dry_ground)
		and bounded.touches_ground(on_dry_ground))
	_check("outside-bank gear compression remains bit-identical",
		_same_packed(dry.gear_compressions(on_dry_ground), bounded.gear_compressions(on_dry_ground)))

func _new_session(lake: Dictionary = {}) -> Session:
	var session: Session = Session.new()
	session.physics_enabled = false
	session.crash_auto_restart = false
	root.add_child(session)
	session.setup()
	if not lake.is_empty():
		_check("session receives normalized lake", session.set_lake_context(lake))
	return session

func _new_collision_session(lake: Dictionary) -> Session:
	var session: Session = _new_session()
	session.aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	session.aircraft.model.landing_gear = {}
	session._prop_disc = {}
	_check("collision fixture installs lake after its point probes", session.set_lake_context(lake))
	return session

func _set_direct_state(session: Session, position: Array, velocity: Array) -> void:
	session.sim.gravity = 0.0
	session.sim.model.loads = func(_state_value: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return aux.duplicate()
	var initial: PackedFloat64Array = _state(position, velocity)
	_check("direct session state resets", session.sim.reset(initial), str(session.sim.fault_reason))
	session.sim.set_paused(false)

func _state(position: Array, velocity: Array) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array(position), PackedFloat64Array(velocity),
		M.q_from_euler(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))

func _proxy(id: String, north: float, east: float, down: float, half_n: float,
		half_down: float, half_e: float) -> Dictionary:
	return {"id": id, "kind": "test_obstacle", "part": "body", "shape": "box",
		"response_class": "hard_terminal", "damage_id": "", "damage_profile": "none",
		"north": north, "east": east, "down": down, "half_x": half_n, "half_down": half_down,
		"half_z": half_e, "sin_heading": 0.0, "cos_heading": 1.0,
		"bounds_north_min": north - half_n, "bounds_north_max": north + half_n,
		"bounds_east_min": east - half_e, "bounds_east_max": east + half_e,
		"bounds_down_min": down - half_down, "bounds_down_max": down + half_down}

func _world(proxy: Dictionary) -> Dictionary:
	var bins: Dictionary = {}
	var cell_size: float = CollisionWorld.CELL_SIZE_M
	var min_n: int = floori(float(proxy.bounds_north_min) / cell_size)
	var max_n: int = floori(float(proxy.bounds_north_max) / cell_size)
	var min_e: int = floori(float(proxy.bounds_east_min) / cell_size)
	var max_e: int = floori(float(proxy.bounds_east_max) / cell_size)
	var min_d: int = floori(float(proxy.bounds_down_min) / cell_size)
	var max_d: int = floori(float(proxy.bounds_down_max) / cell_size)
	for north_cell: int in range(min_n, max_n + 1):
		for east_cell: int in range(min_e, max_e + 1):
			for down_cell: int in range(min_d, max_d + 1):
				bins["%d,%d,%d" % [north_cell, east_cell, down_cell]] = PackedInt64Array([0])
	return {"format": CollisionWorld.FORMAT, "identity": str(proxy.id),
		"cell_size_m": cell_size, "proxies": [proxy], "bins": bins}

func _same_packed(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if a[index] != b[index]:
			return false
	return true

func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1
