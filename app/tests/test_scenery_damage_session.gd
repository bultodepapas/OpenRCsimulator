# Run: godot --headless --path . --script res://tests/test_scenery_damage_session.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const Session := preload("res://sim/flight_session.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _proxy(id: String, damage_id: String, profile: String, response_class: String = "hard_terminal") -> Dictionary:
	return {
		"id": id,
		"kind": "fence" if profile == "wire" else "test_obstacle",
		"part": "rail" if profile == "wire" else "body",
		"shape": "box",
		"response_class": response_class,
		"damage_id": damage_id,
		"damage_profile": profile,
		"north": 0.2,
		"east": 0.0,
		"down": -10.0,
		"half_x": 1.0,
		"half_down": 5.0,
		"half_z": 0.1,
		"sin_heading": 0.0,
		"cos_heading": 1.0,
		"bounds_north_min": 0.1,
		"bounds_north_max": 0.3,
		"bounds_east_min": -1.0,
		"bounds_east_max": 1.0,
		"bounds_down_min": -15.0,
		"bounds_down_max": -5.0,
	}


func _world(proxies: Array[Dictionary], identity: String = "scenery-damage-test") -> Dictionary:
	var indices := PackedInt64Array()
	for index: int in proxies.size():
		indices.append(index)
	return {
		"format": CollisionWorld.FORMAT,
		"identity": identity,
		"cell_size_m": CollisionWorld.CELL_SIZE_M,
		"proxies": proxies,
		"bins": {"0,0,-1": indices},
	}


func _move_proxy_north(proxy: Dictionary, north: float) -> Dictionary:
	var moved: Dictionary = proxy.duplicate(true)
	var delta: float = north - float(moved.north)
	moved.north = north
	moved.bounds_north_min = float(moved.bounds_north_min) + delta
	moved.bounds_north_max = float(moved.bounds_north_max) + delta
	return moved


func _new_session(world: Dictionary) -> Session:
	var session: Session = Session.new()
	session.physics_enabled = false
	root.add_child(session)
	_check("test collision world installs", session.set_collision_world(world))
	session.setup()
	return session


func _prepare_direct_step(session: Session, project_continuous: bool = false) -> PackedFloat64Array:
	session.aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	session.sim.gravity = 0.0
	session.sim.loads = func(_state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if project_continuous:
		session.sim.continuous = PackedFloat64Array([0.0])
		session.sim.continuous_evaluate = Callable()
		session.sim.continuous_step = Callable()
		session.sim.continuous_rotor_momentum = Callable()
		session.sim.continuous_loads = func(_state: PackedFloat64Array, _extra: PackedFloat64Array,
				_time_s: float) -> PackedFloat64Array:
			return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		session.sim.continuous_derivative = func(_state: PackedFloat64Array, _extra: PackedFloat64Array,
				_time_s: float) -> PackedFloat64Array:
			return PackedFloat64Array([0.0])
		session.sim.continuous_aux = func(_extra: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
			return sampled
	var initial := PackedFloat64Array()
	initial.resize(RB.SIZE)
	initial[RB.POS + 2] = -10.0
	initial[RB.VEL] = 100.0
	initial[RB.ATT] = 1.0
	var reset_ok: bool = session.sim.reset(initial)
	_check("test state reset succeeds", reset_ok, str(session.sim.fault_reason))
	if project_continuous:
		# Reset accepts the projection; this fails only after post_step stages a scenery hit.
		session.sim.continuous_aux = func(_extra: PackedFloat64Array, _sampled: PackedFloat64Array) -> PackedFloat64Array:
			return PackedFloat64Array()
	session.sim.set_paused(false)
	return initial


func _run_damage_hit(profile: String, identity: String) -> Dictionary:
	var id := "obstacle:" + profile
	var proxies: Array[Dictionary] = [_proxy(id, "damage:" + profile, profile)]
	if profile == "wood":
		proxies.append(_proxy(id + ":rail", "damage:" + profile, profile))
		proxies.append(_move_proxy_north(_proxy("tree:shade-tree:fixture:trunk", "tree:shade-tree:fixture", "wood_mark"), 20.0))
		proxies.append(_move_proxy_north(_proxy("tree:shade-tree:fixture:crown", "tree:shade-tree:fixture", "foliage_mark"), 20.0))
		proxies.append(_move_proxy_north(_proxy("person:fixture", "person:fixture", "none"), 20.0))
	var world := _world(proxies, identity)
	var session := _new_session(world)
	var signal_count := [0]
	session.scenery_damage_changed.connect(func() -> void: signal_count[0] += 1)
	var initial := _prepare_direct_step(session)
	session.sim.step()
	var result := {
		"session": session,
		"world": world,
		"initial": initial,
		"damage_id": "damage:" + profile,
		"obstacle_id": id,
		"damage_signal_count": signal_count,
	}
	return result


func _same_simulation(a: Session, b: Session) -> bool:
	var a_snapshot: Dictionary = a.sim.checkpoint()
	var b_snapshot: Dictionary = b.sim.checkpoint()
	for key: String in ["tick", "state", "previous", "aux", "inputs", "modes", "continuous", "last_loads"]:
		if a_snapshot.get(key) != b_snapshot.get(key):
			return false
	return true


func _initialize() -> void:
	for profile: String in ["wood", "wire", "foam", "straw", "foliage", "metal", "masonry", "wood_mark", "foliage_mark"]:
		var expected := "broken" if SceneryDamage.profile_is_destructible(profile) else "marked"
		var threshold := SceneryDamage.threshold_j(profile)
		_check("%s reaches its provisional energy threshold" % profile,
			SceneryDamage.impact_state(profile, threshold) == expected)
	_check("non-damageable profile stays unchanged", SceneryDamage.impact_state("none", 1000.0).is_empty())

	var shared_proxies: Array[Dictionary] = [
		_proxy("shared:post", "shared", "wood"),
		_proxy("shared:rail", "shared", "wood"),
	]
	var shared_world := _world(shared_proxies)
	var start := PackedFloat64Array()
	start.resize(RB.SIZE)
	start[RB.POS + 2] = -10.0
	start[RB.ATT] = 1.0
	var finish := start.duplicate()
	finish[RB.POS] = 0.5
	finish[RB.VEL] = 100.0
	var unfiltered := SceneryCollision.contacts(start, finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		shared_world, 1, 2.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))
	_check("optional damage argument preserves legacy contacts", unfiltered.size() == 2, "contacts=%d" % unfiltered.size())
	var already_broken := {"shared": {"state": "broken"}}
	var filtered := SceneryCollision.contacts(start, finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		shared_world, 1, 2.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]), already_broken)
	_check("broken damage id filters every shared proxy", filtered.is_empty())

	var wood := _run_damage_hit("wood", "wood-world")
	var wood_session: Session = wood.session
	var wood_damage: Dictionary = wood_session.scenery_damage()
	_check("direct sim.step commits threshold wood damage", wood_session.sim.tick == 1 and wood_damage.has(wood.damage_id))
	_check("accepted damage emits the no-argument change signal once", wood.damage_signal_count[0] == 1)
	if wood_damage.has(wood.damage_id):
		var wood_record: Dictionary = wood_damage[wood.damage_id]
		_check("wood record includes impact state, energy, tick and NED vectors",
			wood_record.state == "broken" and wood_record.tick == 1 and float(wood_record.energy_j) >= 20.0 \
				and wood_record.point_ned is PackedFloat64Array and wood_record.normal_ned is PackedFloat64Array \
				and wood_record.velocity_ned is PackedFloat64Array and wood_record.obstacle_id == wood.obstacle_id)
	var detached_damage: Dictionary = wood_session.scenery_damage()
	detached_damage.erase(wood.damage_id)
	_check("public damage state is detached from session storage", wood_session.scenery_damage().has(wood.damage_id))
	var intact_view: Dictionary = wood_session.collision_world()
	var active_view: Dictionary = wood_session.collision_world(true)
	var remaining_ids := {}
	for proxy: Dictionary in active_view.proxies:
		remaining_ids[str(proxy.damage_id)] = true
	_check("active-only world omits broken shared proxies but retains unrelated proxies",
		intact_view.proxies.size() == 5 and active_view.proxies.size() == 3 \
			and not remaining_ids.has(wood.damage_id) and remaining_ids.has("tree:shade-tree:fixture") \
			and remaining_ids.has("person:fixture") and not active_view.bins.is_empty())
	_check("same-identity world installation does not heal damage",
		wood_session.set_collision_world(wood.world) and wood_session.scenery_damage().has(wood.damage_id))
	var damaged_hits := SceneryCollision.contacts(start, finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		wood.world, 2, wood_session.sim.mass, wood_session.sim.inertia, wood_session.scenery_damage())
	_check("session damage removes all matching proxies from later sweeps", damaged_hits.is_empty())

	var fence := _run_damage_hit("wire", "fence-world")
	var fence_session: Session = fence.session
	_check("fence hit remains hard-terminal while wire damage breaks",
		fence_session.sim.tick == 1 and not fence_session.crash.is_empty() \
			and fence_session.scenery_damage().get(fence.damage_id, {}).get("state", "") == "broken")

	for profile: String in ["metal", "masonry", "wood_mark", "foliage_mark"]:
		var marked := _run_damage_hit(profile, profile + "-world")
		var marked_session: Session = marked.session
		var record: Dictionary = marked_session.scenery_damage().get(marked.damage_id, {})
		var remaining: Dictionary = marked_session.collision_world(true)
		var repeat_hit: SceneryCollision.Event = SceneryCollision.first_hit(start, finish,
			PackedFloat64Array([0.0, 0.0, 0.0]), marked.world, 2, marked_session.sim.mass,
			marked_session.sim.inertia, marked_session.scenery_damage())
		_check("%s impact marks but retains collision" % profile,
			record.get("state", "") == "marked" and remaining.proxies.size() == 1 and repeat_hit != null)

	var saved_damage: Dictionary = wood_session.scenery_damage()
	var checkpoint: Dictionary = wood_session.checkpoint()
	_check("v7 checkpoint carries nonempty scenery damage",
		checkpoint.get("format", "") == "openrc-flight-checkpoint v7" and checkpoint.get("scenery_damage", {}).has(wood.damage_id))
	var restored: Session = _new_session(wood.world)
	_prepare_direct_step(restored)
	var restore_signal_count := [0]
	restored.scenery_damage_changed.connect(func() -> void: restore_signal_count[0] += 1)
	_check("checkpoint restores scenery damage", restored.restore_checkpoint(checkpoint)
		and restored.scenery_damage() == saved_damage and restore_signal_count[0] == 1)
	var old_v7: Dictionary = checkpoint.duplicate(true)
	old_v7.erase("scenery_damage")
	var restored_without_damage: Session = _new_session(wood.world)
	_prepare_direct_step(restored_without_damage)
	_check("older v7 checkpoint without optional damage restores empty state",
		restored_without_damage.restore_checkpoint(old_v7) and restored_without_damage.scenery_damage().is_empty())
	var before_bad_restore: Dictionary = restored.checkpoint()
	var malformed: Dictionary = checkpoint.duplicate(true)
	malformed.scenery_damage[wood.damage_id].obstacle_id = "missing-proxy"
	_check("checkpoint rejects a damage record for an absent proxy", not restored.restore_checkpoint(malformed))
	_check("malformed restore leaves simulation and damage atomic",
		restored.checkpoint().simulation == before_bad_restore.simulation \
			and restored.scenery_damage() == before_bad_restore.scenery_damage)
	var malformed_vector: Dictionary = checkpoint.duplicate(true)
	malformed_vector.scenery_damage[wood.damage_id].point_ned = PackedFloat64Array([INF, 0.0, 0.0])
	_check("checkpoint rejects nonfinite damage vectors", not restored.restore_checkpoint(malformed_vector))
	wood_session.sim.set_paused(false)
	restored.sim.set_paused(false)
	wood_session.sim.step()
	restored.sim.step()
	_check("restored damaged flight continues exactly", _same_simulation(wood_session, restored)
		and wood_session.scenery_damage() == restored.scenery_damage())

	var projection_world := _world([_proxy("projection:wood", "projection", "wood")], "projection-world")
	var projection_session := _new_session(projection_world)
	_prepare_direct_step(projection_session, true)
	projection_session.sim.step()
	_check("failed continuous projection discards staged damage",
		projection_session.sim.tick == 0 and not projection_session.sim.fault_reason.is_empty() \
			and projection_session.scenery_damage().is_empty())

	wood_session.reset()
	_check("session reset clears committed scenery damage", wood_session.scenery_damage().is_empty())
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
