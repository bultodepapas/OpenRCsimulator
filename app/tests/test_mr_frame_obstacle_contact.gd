## Independent geometric witnesses for the FPV frame sweep. Distances are metres, axes are north/east/down.
extends SceneTree

const Sweep := preload("res://sim/multirotor/frame_obstacle_contact.gd")
const Prop := preload("res://sim/multirotor/swept_prop_contact.gd")
const Session := preload("res://sim/multirotor/session.gd")
const World := preload("res://scenery/collision_world.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

var checks := 0
var failures := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _pose(n: float, e: float, d := 0.0, yaw := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(n, e, d), M.v3(0, 0, 0), M.q_from_euler(yaw, 0, 0), M.v3(0, 0, 0))


func _query(proxies: Array[Dictionary]) -> Callable:
	return Sweep.query(Session.obstacle_index({proxies = proxies}, 0.30), [])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var zero := M.v3(0, 0, 0)
	var half := M.v3(0.10, 0.08, 0.03)
	var solids: Array[Dictionary] = []
	# Two pencil-thin posts and the nearer slab. A 10 m sweep crosses multiple index cells; neither midpoint nor
	# endpoint overlaps the slab. The front of the box first touches it at n = 4.02 - 0.01 - 0.10 = 3.91 m.
	World._add_capsule(solids, "post", "tree_trunk", "trunk", "hard_terminal", 5.3, 0, 0, 0.04, 1.0)
	World._add_box_at_down(solids, "slab", "equipment", "slab", "hard_terminal", 4.02, 0.07, 0, 0.02, 0.7, 0.02, 0)
	var cast := _query(solids)
	var hit: Dictionary = cast.call(_pose(0, 0), _pose(10, 0), zero, half)
	_check("earliest hit along a multicell sweep", hit.get("obstacle_id") == "slab" and absf(hit.fraction - 0.391) < 1e-6)
	if not hit.is_empty():
		_check("narrow post strikes the side of the front face", absf(hit.point_body[1] - 0.07) < 2.0e-5
			and absf(hit.point_body[0] - 0.10) < 1.0e-8 and hit.normal[0] < -0.99999)
	_check("clear channel beside slab and post", (cast.call(_pose(0, 0.18), _pose(10, 0.18), zero, half) as Dictionary).is_empty())
	solids.reverse()
	_check("changing inventory order keeps the first hit", var_to_bytes(hit) == var_to_bytes(_query(solids).call(
		_pose(0, 0), _pose(10, 0), zero, half)))

	solids.clear()
	World._add_capsule(solids, "tree", "tree_trunk", "trunk", "hard_terminal", 0, 0, 0, 0.04, 1.0)
	cast = _query(solids)
	hit = cast.call(_pose(-1, 0), _pose(1, 0), zero, half)
	_check("trunk impact locates physical surface", hit.get("obstacle_id") == "tree" and absf(hit.fraction - 0.43) < 1e-6)
	if not hit.is_empty():
		_check("centered trunk strike has no spurious roll/pitch lever", absf(hit.point_body[1]) < 1e-8 and absf(hit.point_body[2]) < 1e-8)
	_check("rounded trunk corner clears a box corner outside the radius",
		(cast.call(_pose(0.13, 0.11), _pose(0.13, 0.11), zero, half) as Dictionary).is_empty())
	_check("separating initial touch does not pin the frame", (cast.call(_pose(-0.14, 0), _pose(-1, 0), zero, half) as Dictionary).is_empty())
	_check("flight over the trunk cap is clear", (cast.call(_pose(-1, 0, -1.08), _pose(1, 0, -1.08), zero, half) as Dictionary).is_empty())
	hit = cast.call(_pose(0.088, 0), _pose(0.088, 0), zero, half)
	_check("starting with the shaft inside the frame returns outward depth", not hit.is_empty() and hit.normal[0] > 0.999
		and absf(hit.penetration_m - 0.052) < 1e-8)

	# Pure yaw about a stationary centre. Both endpoints miss the pole, the long front edge traverses it mid-turn.
	solids.clear()
	World._add_capsule(solids, "pole", "fixture", "pole", "hard_terminal", 0.19, 0, 0, 0.006, 0.5)
	cast = _query(solids)
	hit = cast.call(_pose(0, 0, 0, -PI/4.0), _pose(0, 0, 0, PI/4.0), zero, M.v3(0.20, 0.02, 0.02))
	_check("rotation in place hits between two clear poses", hit.get("obstacle_id") == "pole" and hit.fraction > 0.2 and hit.fraction < 0.5)

	solids.clear()
	World._add_box_at_down(solids, "rotated", "fixture", "panel", "hard_terminal", 0, 0, 0, 0.04, 0.5, 0.8, 45.0)
	cast = _query(solids)
	_check("outside a rotated panel despite broad-phase overlap", (cast.call(_pose(0.2, -0.18), _pose(0.2, -0.18), zero, half) as Dictionary).is_empty())
	var diagonal := 1.0 / sqrt(2.0)
	hit = cast.call(_pose(-diagonal, diagonal), _pose(diagonal, -diagonal), zero, half)
	var expected := (1.0 - (half[0] + half[1]) * diagonal - 0.02) / 2.0
	_check("diagonal panel contact agrees with projected half extents", not hit.is_empty() and absf(hit.fraction - expected) < 1e-6)
	# The box already touches a wall while opening, with a small rotation about the wall normal.
	solids.clear()
	World._add_box_at_down(solids, "wall", "fixture", "panel", "hard_terminal", 0, 0, 0, 4.0, 4.0, 0.04, 0)
	var start := _pose(-0.12, 0)
	var finish := RB.make_state(M.v3(-0.126, 0, 0), zero, M.q_from_euler(0, 0, 0.12), zero)
	_check("an opening contact releases during rotation", (_query(solids).call(start, finish, zero, half) as Dictionary).is_empty())
	_branch()
	_prop_sweep()
	_shared_broad_phase()
	_session_prop("graded")
	_session_prop("strict")
	print("FPV swept frame geometry: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _branch() -> void:
	var solids: Array[Dictionary] = []
	World._add_capsule(solids, "branch", "tree_trunk", "branch", "hard_terminal", 0, 0, 0, 0.04, 0.5)
	var branch: Dictionary = solids[0]
	branch.axis_ned = M.v3(0, 1, 0)
	branch.bounds_east_min = -0.54
	branch.bounds_east_max = 0.54
	branch.bounds_down_min = -0.04
	branch.bounds_down_max = 0.04
	var cast := _query(solids)
	var half := M.v3(0.1, 0.08, 0.03)
	var zero := M.v3(0, 0, 0)
	var hit: Dictionary = cast.call(_pose(-1, 0.32), _pose(1, 0.32), zero, half)
	_check("horizontal wood is solid away from the trunk", hit.get("obstacle_id") == "branch" and absf(hit.fraction - 0.43) < 1e-6)
	_check("a path below the branch is clear", (cast.call(_pose(-1, 0, 0.20), _pose(1, 0, 0.20), zero, half) as Dictionary).is_empty())


func _prop_sweep() -> void:
	var solids: Array[Dictionary] = []
	var hub := M.v3(0, 0, 0)
	var radius := 0.065
	var thickness := 0.003
	# Thin foliage-free gate bar, traversed axially at speed. The spinning disc reaches the bar even when the
	# mid-tick location is past it. Passing through the square outside the circular rim is a clean miss.
	World._add_box_at_down(solids, "bar", "fixture", "bar", "frangible_impulse", 0.025, 0.022, -0.04, 0.004, 0.004, 0.004, 0)
	var cast := Prop.query(Session.obstacle_index({proxies = solids}, 0.3), [])
	var hit: Dictionary = cast.call(_pose(0, 0, -0.10), _pose(0, 0, 0.08), hub, radius, thickness)
	var expected := (0.10 - 0.04 - 0.002 - thickness) / 0.18
	_check("axial prop-only crossing locates the thin bar", hit.get("obstacle_id") == "bar" and absf(hit.fraction - expected) < 1e-5)
	_check("a prior frame event clips the rotor search interval", (cast.call(_pose(0, 0, -0.10), _pose(0, 0, 0.08),
		hub, radius, thickness, expected - 0.02) as Dictionary).is_empty())
	_check("empty corners of the prop's enclosing square stay clear", (cast.call(_pose(-0.028, -0.031, -0.10),
		_pose(-0.028, -0.031, 0.08), hub, radius, thickness) as Dictionary).is_empty())
	# A small pole lies inside the radial envelope of a swept prop hub during a yaw, before and after it is clear.
	solids.clear()
	World._add_capsule(solids, "pole", "tree_trunk", "trunk", "hard_terminal", 0.15, 0.0, 0, 0.003, 0.4)
	cast = Prop.query(Session.obstacle_index({proxies = solids}, 0.3), [])
	hit = cast.call(_pose(0, 0, 0, -PI/3.0), _pose(0, 0, 0, PI/3.0), M.v3(0.11, 0, 0), radius, thickness)
	_check("an off-centre spinning prop sweeps an arc around a stationary CG", hit.get("obstacle_id") == "pole"
		and hit.fraction > 0.1 and hit.fraction < 0.5)


## Run identical 240 Hz ticks with and without the shared rejection, including the accepted event payloads.
func _shared_broad_phase() -> void:
	var proxies: Array[Dictionary] = []
	World._add_capsule(proxies, "wood", "tree_trunk", "trunk", "hard_terminal", 2.1, 2, -10, 0.012, 0.4)
	for i in 24:
		World._add_capsule(proxies, "branch-%02d" % i, "tree_trunk", "branch", "hard_terminal",
			2.0 + i / 50.0, 2.0, -7, 0.01, 0.4)
	World._add_box_at_down(proxies, "leaves", "tree_foliage", "crown", "soft_foliage_impulse",
		-2, -2, -10, 2, 2, 2, 0)
	World._add_box_at_down(proxies, "wide", "fixture", "roof", "hard_terminal", 100, 100, -10, 90, 0.04, 90, 0)
	var world := {format = World.FORMAT, cell_size_m = World.CELL_SIZE_M, identity = "shared-broad-phase",
		proxies = proxies, bins = World._build_bins(proxies)}
	var s := Session.new()
	root.add_child(s)
	if not (s.set_collision_world(world) and s.prepare({}, {prepared_data = Fixtures.electric(), crash_model = "graded",
			start = "air", altitude_m = 10.0, north_offset_m = 0.0, heading_deg = 0.0})):
		_check("shared broad phase prepares", false)
		s.free()
		return
	var frames := Session._frame_proxies([{north = 4.06, east = 2.0, down = -10.0, half_z = 0.3,
		half_x = 0.003, half_down = 0.4, heading_deg = 0.0}])
	s._install_obstacle_queries(s.plant, frames, s._body_radius)
	var near: Callable = s.plant.solids_near
	var cast_frame: Callable = s.plant.frame_contact
	var cast_prop: Callable = s.plant.swept_prop_contact
	var leaves: Callable = s.plant.foliage_density
	var count := {frame = 0, prop = 0, leaves = 0}
	s.plant.frame_contact = func(a, b, centre, half) -> Dictionary:
		count.frame += 1
		return cast_frame.call(a, b, centre, half)
	s.plant.swept_prop_contact = func(a, b, hub, radius, thickness, limit) -> Dictionary:
		count.prop += 1
		return cast_prop.call(a, b, hub, radius, thickness, limit)
	s.plant.foliage_density = func(body, attitude) -> PackedFloat64Array:
		count.leaves += 1
		return leaves.call(body, attitude)
	var events: Array = []
	s.sim.events_located.connect(func(_tick: int, found: Array[Dictionary]) -> void: events.append_array(found))
	var mark := s.checkpoint()
	var forward := M.v3(40, 0, 0)
	# [start position, velocity, possibly solid]. All four props spin on each reference tick.
	var cases := {
		"empty cells": [M.v3(10, 10, -10), forward, false],
		"above dense branches": [M.v3(2, 2, -12), forward, false],
		"leaves only": [M.v3(-2, -2, -10), forward, false],
		"trunk": [M.v3(1.90, 2, -10), forward, true],
		"clear beside trunk": [M.v3(1.90, 2.19, -10), forward, true],
		"gate across cell boundary": [M.v3(3.86, 2, -10), forward, true],
		"wide roof": [M.v3(100, 100, -10.14), M.v3(0, 0, 40), true],
	}
	for label: String in cases:
		var row: Array = cases[label]
		mark.kernel.state = RB.make_state(row[0], row[1], M.q_identity(), M.v3(0, 0, 0))
		mark.kernel.previous = mark.kernel.state.duplicate()
		var reference := PackedByteArray()
		for enabled: bool in [false, true]:
			s.plant.solids_near = near if enabled else Callable()
			count.frame = 0
			count.prop = 0
			count.leaves = 0
			events.clear()
			var ok := s.restore_checkpoint(mark) and s.resume() and s.tick_once(FC.neutral_input())
			_check("accepted %s tick (guard=%s)" % [label, enabled], ok)
			var snapshot := var_to_bytes([s.frame(), events])
			if enabled:
				_check("byte-identical state and events for " + label, snapshot == reference)
			else:
				reference = snapshot
			var expected := 1 if not enabled or bool(row[2]) else 0
			_check("frame/prop sweep counts for %s (guard=%s)" % [label, enabled],
				count.frame == expected and count.prop == 4 * expected)
			if label == "leaves only":
				_check("leaf quadrature with clear solids (guard=%s)" % enabled, count.leaves == 3)
	var gate_only := Sweep.near_query({}, Sweep.prepare_gates(frames), 0.2, 0.7)
	_check("gate-only scene admits its bar and rejects distant air", gate_only.call(_pose(3.86, 2, -10), _pose(4.02, 2, -10))
		and not gate_only.call(_pose(-2, -2, -10), _pose(-1.9, -2, -10)))
	var index := Session.obstacle_index({proxies = [proxies[0]]}, 0.1)
	var oversized := Sweep.near_query(index, Sweep.prepare_gates([]), 0.8, 0.1)
	_check("an aircraft larger than the prepared reach retains individual casts", oversized.call(_pose(2, 2), _pose(2.1, 2)))
	_check("long multicell paths retain individual casts", near.call(_pose(-10, 30, -10), _pose(10, 30, -10)))
	s.free()


func _session_prop(mode: String) -> void:
	var session := Session.new()
	root.add_child(session)
	var data := Fixtures.electric()
	var hub: PackedFloat64Array = data.rotors[0].hub_frd
	var solids: Array[Dictionary] = []
	World._add_box_at_down(solids, "twig", "fixture", "bar", "hard_terminal", hub[0], hub[1] + 0.043,
		-9.946, 0.004, 0.004, 0.004, 0)
	var world := {format = World.FORMAT, cell_size_m = World.CELL_SIZE_M, identity = "swept-prop",
		proxies = solids, bins = World._build_bins(solids)}
	var prepared: bool = session.set_collision_world(world) and session.prepare({}, {prepared_data = data, crash_model = mode,
		start = "air", altitude_m = 10.0, north_offset_m = 0.0, heading_deg = 0.0})
	_check("%s scene queries prepare" % mode, prepared)
	if not prepared:
		session.free()
		return
	var frame: Dictionary = session.frame()
	frame.body = RB.make_state(M.v3(0, 0, -10), M.v3(0, 0, 40), M.q_identity(), M.v3(0, 0, 0))
	var neutral := FC.neutral_input()
	var accepted: Array = []
	session.sim.events_located.connect(func(_tick: int, events: Array[Dictionary]) -> void: accepted.append_array(events))
	var tick_ok := Fixtures.reset(session.sim, frame, neutral).is_empty() and session.resume() and session.tick_once(neutral)
	_check("%s dive accepts one tick" % mode, tick_ok)
	_check("%s quad stops at prop-only obstacle before midpoint" % mode, absf(float(session.sim.state[RB.POS + 2]) + 9.951) < 0.002)
	if mode == "graded":
		var health: PackedFloat64Array = session.sim.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4)
		_check("graded crossing breaks only the touched prop", session.crash.is_empty() and health == PackedFloat64Array([0, 1, 1, 1]))
	else:
		var classified := false
		for event: Dictionary in accepted:
			if event.type == "crash":
				classified = event.get("reason") == "Obstacle strike" and event.get("part") == "prop" \
					and event.get("rotor") == 0 and event.get("obstacle_id") == "twig"
		_check("strict scenery event identifies the touched spinning prop", classified and session.crash.get("reason") == "Obstacle strike")
	session.free()
