extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Loader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const QuadSession := preload("res://sim/multirotor/session.gd")
const BlimpSession := preload("res://sim/airship/session.gd")
const QuadController := preload("res://physics/multirotor/flight_controller.gd")

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
	_test_audit_bank_ticks(lake)
	_test_sampled_bank_tolerance(lake)
	_test_quad_and_blimp_lake(lake)
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
	_check("lake trace declares the corrected swept contact law", session.trace_meta().get("lake_collision_law", "") == LakeCollision.LAW)
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
func _accept_sweep(session: Session, previous: PackedFloat64Array, candidate: PackedFloat64Array,
		mass_at_fraction: Callable = Callable()) -> void:
	# These fixtures replace the aircraft's geometry; disable propulsion callbacks tied to its original gear.
	session.sim.continuous = PackedFloat64Array()
	for field: String in ["step_policy", "stage", "block_loads", "block_derivative",
		"stage_rotor_momentum", "block_aux"]:
		session.sim.model.set(field, Callable())
	_set_direct_state(session, Array(previous.slice(RB.POS, RB.POS + 3)), Array(previous.slice(RB.VEL, RB.VEL + 3)))
	session.sim.model.post_tick = func(_previous: PackedFloat64Array, _candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
		var filtered: PackedFloat64Array = session._resolve_collision_step(previous, candidate, tick, mass_at_fraction)
		_check("unaccepted sweep keeps impact private", session.crash.is_empty()
			and session.last_lake_event() == null and session.last_scenery_event() == null)
		return filtered
	session.sim.step()
	_check("controlled sweep commits", session.sim.tick == 1 and session.sim.fault_reason.is_empty(), session.sim.fault_reason)

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


## A35 F06/F07 witnesses, using the real aircraft, accepted tick and stopped propeller.
func _test_audit_bank_ticks(lake: Dictionary) -> void:
	var stik: Session = _bank_tick(lake, "res://data/aircraft/jensen_ugly_stik_60.json",
		171.3, M.q_from_euler(-PI / 2.0, 0.0, 0.0), PackedFloat64Array([35.0, 0.0, 4.45]), 0.001)
	_check("F06 shallow Stik bank approach survives the accepted tick", stik.sim.tick == 1
		and stik.sim.fault_reason.is_empty() and stik.crash.is_empty() and stik.last_lake_event() == null,
		str(stik.crash))
	var foam: Session = _bank_tick(lake, "res://data/aircraft/moonrunner_x99.json",
		174.0, M.q_from_euler(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 5.0]), 0.0)
	_check("F07 X99 uses its authored bank impact tolerance in the accepted tick", foam.sim.tick == 1
		and foam.sim.fault_reason.is_empty() and foam.crash.is_empty() and foam.last_lake_event() == null,
		str(foam.crash))


func _test_sampled_bank_tolerance(lake: Dictionary) -> void:
	var session: Session = _new_collision_session(lake)
	session.soft_hull_contacts = true
	session.aircraft.model.crash_tolerance = {terminal_specific_energy = 12.5, crash_depth = 0.12}
	session._hull_contact = HullContact.prepare_geometry(session.aircraft.model.crash_hull, lake,
		session.airframe_surfaces, session.aircraft.model.crash_tolerance)
	var properties := {mass_kg = session.sim.mass, cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia = session.sim.inertia, inverse = RB.inertia_inverse(session.sim.inertia)}
	var sampler := func(_fraction: float) -> Dictionary:
		return properties
	var down: float = LakeSurface.sample_terrain_validated(lake, 110.0, 174.0).ground_down_m
	var previous := _state([110.0, 174.0, down - 0.005], [0.0, 0.0, 3.0])
	var candidate := _state([110.0, 174.0, down + 0.005], [0.0, 0.0, 3.0])
	_accept_sweep(session, previous, candidate, sampler)
	_check("session forwards prepared aircraft tolerance to the sampled bank sweep", session.crash.is_empty()
		and session.last_lake_event() == null)


func _bank_tick(lake: Dictionary, aircraft_path: String, east: float, q: PackedFloat64Array,
		velocity_body: PackedFloat64Array, penetration: float) -> Session:
	var session := Session.new()
	session.physics_enabled = false
	session.soft_hull_contacts = true
	session.crash_auto_restart = false
	root.add_child(session)
	session.setup(aircraft_path)
	_check("audit aircraft accepts lake context", session.aircraft.ok and session.set_lake_context(lake))
	var center_down: float = INF
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	for at: int in range(0, hull.size(), 3):
		var offset: PackedFloat64Array = M.q_rotate(q, hull.slice(at, at + 3))
		var terrain: Dictionary = LakeSurface.sample_terrain_validated(lake, 110.0 + offset[0], east + offset[1])
		center_down = minf(center_down, float(terrain.ground_down_m) - offset[2])
	var velocity_ned: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var center := PackedFloat64Array([110.0, east, center_down + penetration])
	var lead_time: float = session.sim.dt() * (0.5 if penetration > 0.0 else 0.25)
	var initial: PackedFloat64Array = RB.make_state(M.sub(center, M.scale(velocity_ned, lead_time)),
		velocity_body, q, PackedFloat64Array([0.0, 0.0, 0.0]))
	session.engine_running = false
	session.sim.continuous[session._rotor_index()] = 0.0
	session.sim.aux[Session.AUX_RPM] = 0.0
	_check("audit bank state resets", session.sim.reset(initial))
	session.sim.set_paused(false)
	session.sim.step()
	return session

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

## CR-AUD-01: the quad and the blimp compose the field's enabled lake into their terrain, refuse a start over water and
## end the flight at the first water contact with an explicit, observable outcome. Lake disabled stays dry.
func _test_quad_and_blimp_lake(lake: Dictionary) -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field loads for the quad and blimp", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var field: Dictionary = loaded.field
	var interior_n: float = 110.0
	var interior_e: float = 125.0
	var interior: Dictionary = LakeSurface.sample_terrain_validated(lake, interior_n, interior_e)
	_check("interior sample is submerged lake bed", str(interior.get("region", "")) == "bed"
		and absf(float(interior.get("ground_down_m", 0.0)) - 5.45) < 1.0e-9, str(interior))
	var probes: Array[PackedFloat64Array] = [PackedFloat64Array([interior_n, interior_e]),
		PackedFloat64Array([lake.shoreline_ne_m[0], lake.shoreline_ne_m[1]]),
		PackedFloat64Array([lake.bank_ne_m[0], lake.bank_ne_m[1]]), PackedFloat64Array([15.0, 0.0])]
	var kinds: Array[Dictionary] = [
		{name = "quad", script = QuadSession, options = {crash_model = "graded", start = "air", altitude_m = 3.0}},
		{name = "blimp", script = BlimpSession, options = {}}]
	for kind: Dictionary in kinds:
		var label: String = str(kind.name)
		var base: Dictionary = kind.options
		var dry: Node = kind.script.new()
		root.add_child(dry)
		var none_ok: bool = dry.prepare(field, base.duplicate(true))
		var empty: Node = kind.script.new()
		root.add_child(empty)
		var empty_options: Dictionary = base.duplicate(true)
		empty_options["lake"] = {}
		var empty_ok: bool = empty.prepare(field, empty_options)
		var wet: Node = kind.script.new()
		root.add_child(wet)
		var wet_options: Dictionary = base.duplicate(true)
		wet_options["lake"] = lake
		var wet_ok: bool = wet.prepare(field, wet_options)
		_check(label + " prepares dry, with an empty lake and with the lake", none_ok and empty_ok and wet_ok,
			"%s | %s | %s" % [dry.load_error, empty.load_error, wet.load_error])
		if not (none_ok and empty_ok and wet_ok):
			dry.free()
			empty.free()
			wet.free()
			continue
		var dry_ground: PackedFloat64Array = dry.environment.ground(interior_n, interior_e)
		_check(label + " lake disabled stays dry: no provider, no option, byte-identical identity and terrain",
			dry.environment.lake.is_empty() and empty.environment.lake.is_empty() and not dry.options.has("lake")
			and not empty.options.has("lake") and dry.lake_context().is_empty()
			and var_to_bytes(dry.identity()) == var_to_bytes(empty.identity())
			and var_to_bytes(dry_ground) == var_to_bytes(empty.environment.ground(interior_n, interior_e))
			and absf(dry_ground[0]) < 0.05, str(dry_ground))
		var env: RefCounted = wet.environment
		_check(label + " lake enabled composes the bed: interior render height is -5.45 m, not dry ground",
			not env.lake.is_empty() and wet.lake_context().identity == lake.identity
			and absf(env.ground(interior_n, interior_e)[0] + float(interior.ground_down_m)) < 1.0e-9
			and absf(env.ground(interior_n, interior_e)[0] - dry_ground[0]) > 5.0
			and not env.water(interior_n, interior_e).is_empty(), str(env.ground(interior_n, interior_e)))
		var agree: bool = true
		for point: PackedFloat64Array in probes:
			agree = agree and var_to_bytes(env.ground(point[0], point[1])) \
				== var_to_bytes(GroundTerrain.sample_validated(point[0], point[1], env.surfaces, lake))
		_check(label + " interior, shore, bank and outside terrain agree with the lake provider", agree)
		var outside: PackedFloat64Array = probes[3]
		_check(label + " outside the bank the terrain is byte-identical to the dry session",
			var_to_bytes(wet.environment.ground(outside[0], outside[1])) == var_to_bytes(dry.environment.ground(outside[0], outside[1])))
		_check(label + " lake identity enters the session identity", var_to_bytes(wet.identity()) != var_to_bytes(dry.identity())
			and str(wet.identity().environment.lake) == str(lake.identity))
		var contact: PackedFloat64Array = wet.plant.ground.call(interior_n, interior_e) if label == "quad" \
			else wet._ground.call(interior_n, interior_e)
		_check(label + " contact callback sees the lake bed", absf(contact[0] + float(interior.ground_down_m)) < 1.0e-4, str(contact))
		# A stale or malformed lake is refused and the running flight is kept.
		var stale: Dictionary = lake.duplicate(true)
		stale["identity"] = "0".repeat(64)
		var refused_options: Dictionary = base.duplicate(true)
		refused_options["lake"] = stale
		var before: PackedFloat64Array = wet.environment.ground(interior_n, interior_e)
		_check(label + " stale lake identity is refused and keeps the prepared session", not wet.prepare(field, refused_options)
			and wet.prepared and not wet.load_error.is_empty()
			and var_to_bytes(wet.environment.ground(interior_n, interior_e)) == var_to_bytes(before))
		refused_options["lake"] = 3
		_check(label + " a non-dictionary lake option is refused", not wet.prepare(field, refused_options))
		# A start over or beside the water is refused (water contact is terminal).
		var pilot: Dictionary = field.get("pilot", {north = 0.0, east = 0.0})
		var over_water: Dictionary = base.duplicate(true)
		over_water["lake"] = lake
		over_water["north_offset_m"] = interior_n - float(pilot.north)
		over_water["east_offset_m"] = interior_e - float(pilot.east)
		_check(label + " a start over the lake is refused", not wet.prepare(field, over_water) and wet.load_error.contains("lake"),
			wet.load_error)
		over_water.erase("lake")
		_check(label + " the same start without a lake is accepted", wet.prepare(field, over_water))
		var reset_ok: bool = wet.prepare(field, wet_options) and (wet.reset_to_pad() if label == "quad" else wet.reset())
		_check(label + " reset keeps the lake", reset_ok and wet.lake_context().identity == lake.identity)
		_water_entry(label, wet, interior_n, interior_e)
		# Control: lake disabled at the same place has no water outcome.
		_place(dry, interior_n, interior_e, 1.0)
		var control_ok: bool = _resume_and_tick(dry)
		_check(label + " lake disabled gives no water outcome at the same point", control_ok
			and str(dry.crash.get("reason", "")) != "Water contact", str(dry.crash))
		dry.free()
		empty.free()
		wet.free()


## Put the accepted kernel state of a prepared session at (north, east, down).
func _place(session: Node, north: float, east: float, down: float) -> void:
	var state: PackedFloat64Array = session.sim.state
	state[0] = north
	state[1] = east
	state[2] = down
	session.sim.state = state


func _neutral(session: Node) -> PackedFloat64Array:
	return QuadController.neutral_input() if session.has_method("reset_to_pad") else PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


func _resume_and_tick(session: Node) -> bool:
	return session.resume() and session.tick_once(_neutral(session))


func _water_entry(label: String, session: Node, north: float, east: float) -> void:
	var reasons: Array[String] = []
	session.crashed.connect(func(reason: String) -> void: reasons.append(reason))
	_place(session, north, east, -3.0)
	var above_ok: bool = _resume_and_tick(session)
	_check(label + " three metres above the water is no contact", above_ok and session.crash.is_empty() and reasons.is_empty(),
		str(session.crash))
	_place(session, north, east, 1.0)
	var entered: bool = session.tick_once(_neutral(session))
	_check(label + " water entry ends the flight with an explicit water crash", entered
		and str(session.crash.get("reason", "")) == "Water contact" and reasons == ["Water contact"] and session.paused
		and int(session.crash.get("tick", 0)) == int(session.sim.tick), str(session.crash))
	_check(label + " the water crash refuses resume and further ticks", not session.resume()
		and not session.tick_once(_neutral(session)))


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
