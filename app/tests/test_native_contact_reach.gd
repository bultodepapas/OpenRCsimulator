extends SceneTree
## NK-5d: the native contact reach may only prove the absence of contact. Over random tick pairs near trees, fences,
## the lake and open air, every claimed scenery proof must match an empty SceneryCollision sweep and every claimed
## lake proof a null LakeCollision sweep; hits must still occur among unproven pairs. Paired sessions with and
## without the shortcut must then fly identically through cruise, a tree strike and a lake ditching.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 4000
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _world: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 5432
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var built: Dictionary = CollisionSetup.build(_field)
	_check("collision world builds", built.get("ok", false))
	_world = built.world
	for id: String in ["f4u-corsair-250", "p51d-mustang-120", "jensen-das-ugly-stik-60"]:
		var probe := _session(id, true)
		if probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK5D_CONTACT_REACH_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
			probe.free()
			continue
		_soundness(probe, id)
		probe.free()
		_equivalence(id, "cruise")
		_equivalence(id, "tree")
		_equivalence(id, "lake")
	print("native contact reach: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, enabled: bool) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.native_contact_reach_enabled = enabled
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(str(Catalog.entry(id).data), id)
	s.set_field(_field)
	s.set_collision_world(_world)
	s.set_lake_context(_lake)
	s.reset()
	return s


func _soundness(s: Node, id: String) -> void:
	var hull: PackedFloat64Array = s.aircraft.model.crash_hull
	var unit := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var proxies: Array = s._collision_world.proxies
	var shore: PackedFloat64Array = _lake.shoreline_ne_m
	var lake_n := 0.0
	var lake_e := 0.0
	for i: int in range(0, shore.size(), 2):
		lake_n += shore[i]
		lake_e += shore[i + 1]
	lake_n /= float(shore.size() / 2)
	lake_e /= float(shore.size() / 2)
	var stats := {scenery_proved = 0, scenery_hits = 0, lake_proved = 0, lake_hits = 0, unsound = 0}
	for i: int in SAMPLES:
		var base := PackedFloat64Array([0.0, 0.0, 0.0])
		match i % 4:
			0, 1:
				var proxy: Dictionary = proxies[_rng.randi_range(0, proxies.size() - 1)]
				base[0] = lerpf(float(proxy.bounds_north_min), float(proxy.bounds_north_max), _rng.randf()) + _rng.randf_range(-12.0, 12.0)
				base[1] = lerpf(float(proxy.bounds_east_min), float(proxy.bounds_east_max), _rng.randf()) + _rng.randf_range(-12.0, 12.0)
				base[2] = _rng.randf_range(float(proxy.bounds_down_min) - 12.0, float(proxy.bounds_down_max) + 2.0)
			2:
				base[0] = lake_n + _rng.randf_range(-40.0, 40.0)
				base[1] = lake_e + _rng.randf_range(-40.0, 40.0)
				base[2] = -_rng.randf_range(-0.5, 12.0)
			3:
				base[0] = _rng.randf_range(-300.0, 300.0)
				base[1] = _rng.randf_range(-300.0, 300.0)
				base[2] = -_rng.randf_range(2.0, 90.0)
		var previous := _state(base)
		var candidate := _advance(previous, 0.05 if i % 10 else 1.5, 0.02 if i % 7 else 0.4)
		var reach: int = s._native_contact_reach(previous, candidate)
		var tick: int = 1 + i
		var hits: Array = SceneryCollision.contacts(previous, candidate, hull, s._collision_world, tick, 1.0, unit, {})
		var water: Variant = LakeCollision.first_hit(s._lake, previous, candidate, hull, s.current_landing_gear(), tick,
			s.sim.dt(), 1.0, unit, true, s._prop_disc, s._hull_contact)
		if reach & Flight.REACH_SCENERY_CLEAR:
			stats.scenery_proved += 1
			if not hits.is_empty(): stats.unsound += 1
		elif not hits.is_empty():
			stats.scenery_hits += 1
		if reach & Flight.REACH_LAKE_CLEAR:
			stats.lake_proved += 1
			if water != null: stats.unsound += 1
		elif water != null:
			stats.lake_hits += 1
	_check(id + " every scenery and lake proof matches an empty sweep", stats.unsound == 0, str(stats))
	_check(id + " proofs and real hits both occur", stats.scenery_proved > SAMPLES / 4 and stats.lake_proved > SAMPLES / 4
		and stats.scenery_hits > 0 and stats.lake_hits > 0, str(stats))
	print("NK5D_CONTACT_REACH %s %s" % [id, str(stats)])


func _state(position: PackedFloat64Array) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(RB.SIZE)
	for axis: int in 3:
		s[RB.POS + axis] = position[axis]
		s[RB.VEL + axis] = _rng.randf_range(-25.0, 25.0)
		s[RB.RATE + axis] = _rng.randf_range(-3.0, 3.0)
	var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-PI, PI)).normalized()
	s[RB.ATT] = q.w
	s[RB.ATT + 1] = q.x
	s[RB.ATT + 2] = q.y
	s[RB.ATT + 3] = q.z
	return _unit(s)


func _advance(previous: PackedFloat64Array, max_move: float, max_turn: float) -> PackedFloat64Array:
	var s := previous.duplicate()
	for axis: int in 3:
		s[RB.POS + axis] += _rng.randf_range(-max_move, max_move)
	for axis: int in 4:
		s[RB.ATT + axis] += _rng.randf_range(-max_turn, max_turn) * 0.5
	return _unit(s)


## Normalize the attitude in float64 so SceneryCollision's 1e-9 quaternion check accepts it.
func _unit(s: PackedFloat64Array) -> PackedFloat64Array:
	var norm := sqrt(s[RB.ATT] * s[RB.ATT] + s[RB.ATT + 1] * s[RB.ATT + 1] + s[RB.ATT + 2] * s[RB.ATT + 2] + s[RB.ATT + 3] * s[RB.ATT + 3])
	for axis: int in 4:
		s[RB.ATT + axis] /= norm
	return s


## Fly the same scripted start with and without the shortcut and require identical ticks and outcomes.
func _equivalence(id: String, scenario: String) -> void:
	var sessions: Array[Node] = [_session(id, true), _session(id, false)]
	for s: Node in sessions:
		var body: PackedFloat64Array = s.sim.state.duplicate()
		match scenario:
			"tree":
				# Level, heading north at 20 m/s, 25 m short of the tallest obstacle's middle height.
				var tree: Dictionary = _tallest(s._collision_world.proxies)
				body[RB.POS] = float(tree.bounds_north_min) - 25.0
				body[RB.POS + 1] = (float(tree.bounds_east_min) + float(tree.bounds_east_max)) * 0.5
				body[RB.POS + 2] = (float(tree.bounds_down_min) + float(tree.bounds_down_max)) * 0.5
				_level(body, 20.0, 0.0)
			"lake":
				# Level over the middle of the water, 0.95 m above it, sinking at 2 m/s.
				var shore: PackedFloat64Array = _lake.shoreline_ne_m
				body[RB.POS] = _centroid(shore, 0)
				body[RB.POS + 1] = _centroid(shore, 1)
				body[RB.POS + 2] = float(_lake.water_level_down_m) - 0.95
				_level(body, 15.0, 2.0)
		if scenario != "cruise":
			s.sim.reset(body)
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.6}
	var identical := true
	var detail := ""
	var ticks := 0
	for tick: int in 480:
		for s: Node in sessions:
			var dt: float = s.sim.dt()
			s._physics_process(dt)
			s.sim._physics_process(dt)
		ticks += 1
		var a: Node = sessions[0]
		var b: Node = sessions[1]
		if var_to_bytes([a.sim.tick, a.sim.state, a.sim.continuous, a.sim.aux, a.sim.fault_reason, a.crash.keys(),
				a._contact_events.size()]) != var_to_bytes([b.sim.tick, b.sim.state, b.sim.continuous, b.sim.aux,
				b.sim.fault_reason, b.crash.keys(), b._contact_events.size()]):
			identical = false
			detail = "tick %d: %s / %s" % [tick, str(a.sim.state.slice(0, 3)), str(b.sim.state.slice(0, 3))]
			break
		if not a.crash.is_empty() or not a.sim.fault_reason.is_empty():
			break
	var outcome: String = "crash" if not sessions[0].crash.is_empty() else ("fault" if not sessions[0].sim.fault_reason.is_empty() else "flying")
	_check("%s %s flies identically with and without the contact reach (%d ticks, %s)" % [id, scenario, ticks, outcome],
		identical, detail)
	if identical and not sessions[0].crash.is_empty():
		_check("%s %s crash records match" % [id, scenario], var_to_bytes(sessions[0].crash.get("state", null))
			== var_to_bytes(sessions[1].crash.get("state", null)))
	print("NK5D_EQUIVALENCE %s %s ticks=%d outcome=%s" % [id, scenario, ticks, outcome])
	for s: Node in sessions:
		s.free()


func _tallest(proxies: Array) -> Dictionary:
	var best: Dictionary = proxies[0]
	for proxy: Dictionary in proxies:
		if float(proxy.bounds_down_max) - float(proxy.bounds_down_min) > float(best.bounds_down_max) - float(best.bounds_down_min):
			best = proxy
	return best


## Level attitude heading north, body velocity (forward, 0, sink), no rotation.
func _level(body: PackedFloat64Array, forward: float, sink: float) -> void:
	body[RB.ATT] = 1.0
	body[RB.ATT + 1] = 0.0
	body[RB.ATT + 2] = 0.0
	body[RB.ATT + 3] = 0.0
	body[RB.VEL] = forward
	body[RB.VEL + 1] = 0.0
	body[RB.VEL + 2] = sink
	for axis: int in 3:
		body[RB.RATE + axis] = 0.0


func _centroid(points: PackedFloat64Array, offset: int) -> float:
	var sum := 0.0
	for i: int in range(offset, points.size(), 2):
		sum += points[i]
	return sum / float(points.size() / 2)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
