extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Snapshot := preload("res://physics/impact_snapshot.gd")

var failures := 0
var checks := 0
var mass := 2.0
var inertia := PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])


func _initialize() -> void:
	_run()
	print("landscape collision: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run() -> void:
	_test_world_inventory_and_identity()
	_test_thin_lamp_continuous_sweep()
	_test_tree_response_types()
	_test_severity_and_energy_response()
	_test_open_shelter_void_and_parts()
	_test_building_vehicle_and_fleet_boxes()
	_test_rotation_sweep_and_tie_break()
	_test_rotational_chord_padding()


func _test_world_inventory_and_identity() -> void:
	var tree_points: Array = []
	for index: int in 1680:
		tree_points.append([float(index), 500.0, 0.0])
	var field := _field_with_trees(tree_points)
	var scenery := _inventory_scenery()
	var lights := _inventory_lights()
	var first: Dictionary = CollisionWorld.build(field, scenery, lights)
	_check("normalized inventory builds", first.ok)
	if not first.ok:
		return
	var world: Dictionary = first.world
	var tree_parts := 0
	var fleet_placements := {}
	var lamp_count := 0
	var shelter_parts := 0
	var cradle_parts := 0
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) in ["tree_trunk", "tree_foliage"]:
			tree_parts += 1
		if str(proxy.kind) == "parked_aircraft":
			fleet_placements[str(proxy.damage_id)] = true
		if str(proxy.kind) == "lamp":
			lamp_count += 1
		if str(proxy.id).begins_with("building:shelter"):
			shelter_parts += 1
		if str(proxy.kind) == "aircraft_support":
			cradle_parts += 1
	_check("all 1,680 source trees make trunk/crown proxies", tree_parts == 3360)
	_check("each parked aircraft placement has collision proxies", fleet_placements.size() == 4)
	_check("flood and stake fixtures receive proxies", lamp_count >= 3)
	_check("open shelter has 18 posts plus roof", shelter_parts == 19)
	_check("Avanti display cradle has explicit support boxes", cradle_parts == 6)
	var nearby: Array[Dictionary] = CollisionWorld.nearby(world, 100.0, 0.0, -1.0, 50.0)
	_check("nearby query uses local broadphase", not nearby.is_empty() and nearby.size() < world.proxies.size())
	var changed_scenery := _inventory_scenery()
	changed_scenery.groups[0].placements[0].north += 0.25
	var changed: Dictionary = CollisionWorld.build(field, changed_scenery, lights)
	_check("collision inventory identity changes with object geometry", changed.ok and changed.world.identity != world.identity)
	_check("proxy IDs are in stable order", _proxy_ids_sorted(world.proxies))


func _test_thin_lamp_continuous_sweep() -> void:
	var world := _world([], [], [{id = "thin", type = "flood", north = 5.0, east = 0.0, height = 8.0}])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var previous := _state(0.0, 0.0, -4.0, 2400.0, 0.0, 0.0)
	var current := _state(10.0, 0.0, -4.0, 2400.0, 0.0, 0.0)
	var hits: Array[Collision.Event] = Collision.contacts(previous, current, hull, world, 1, mass, inertia)
	_check("thin pole hit despite both endpoints being clear", hits.size() == 1)
	if hits.is_empty():
		return
	var hit: Collision.Event = hits[0]
	var snapshot: Snapshot.Snapshot = hit
	_check("scenery event remains compatible with crash snapshot", snapshot.trigger == "scenery")
	_check("thin-pole time of impact is inside the tick", hit.time_fraction > 0.48 and hit.time_fraction < 0.50)
	_check("contact normal and effective-mass energy are finite", hit.normal_ned.size() == 3 and is_finite(hit.impact_energy_j) and hit.impact_energy_j > 0.0)
	_check("contact-state pose is at the interpolated hit", absf(hit.contact_state()[RB.POS] - 4.93) < 0.02)
	_check("high-normal-speed lamp response is object-specific", hit.response_class == "frangible_impulse" and hit.terminal)
	var miss_start := _state(0.0, 1.0, -4.0, 2400.0, 0.0, 0.0)
	var miss_end := _state(10.0, 1.0, -4.0, 2400.0, 0.0, 0.0)
	_check("nearby path that clears the pole stays clear", Collision.contacts(miss_start, miss_end, hull, world, 1, mass, inertia).is_empty())


func _test_tree_response_types() -> void:
	var canopy_world := _world([[5.0, 0.0, 0.0]], [], [])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var crown_half_extent := 0.0
	for proxy: Dictionary in canopy_world.proxies:
		if str(proxy.part) == "crown":
			crown_half_extent = maxf(float(proxy.half_x), float(proxy.half_z))
	var sweep_half_length := sqrt(2.0) * crown_half_extent + 1.0
	var canopy_start := _state(5.0 - sweep_half_length, 0.0, -6.0, 8.0, 0.0, 0.0)
	var canopy_end := _state(5.0 + sweep_half_length, 0.0, -6.0, 8.0, 0.0, 0.0)
	var canopy_hits: Array[Collision.Event] = Collision.contacts(canopy_start, canopy_end, hull, canopy_world, 2, mass, inertia)
	_check("tree crown is a low-severity entering response", not canopy_hits.is_empty() and not canopy_hits[0].terminal
		and canopy_hits[0].response_class == "soft_foliage_impulse")
	if not canopy_hits.is_empty():
		var foliage_response := Collision.apply_response(canopy_hits[0].contact_state(), canopy_hits[0], mass, inertia)
		_check("foliage response applies a bounded dissipative impulse", foliage_response.ok
			and foliage_response.restitution == Collision.FOLIAGE_RESTITUTION
			and foliage_response.dissipated_energy_j > 0.0
			and foliage_response.kinetic_after_j <= foliage_response.kinetic_before_j)
	var trunk_start := _state(0.0, 0.0, -1.0, 100.0, 0.0, 0.0)
	var trunk_end := _state(10.0, 0.0, -1.0, 100.0, 0.0, 0.0)
	var trunk_hits: Array[Collision.Event] = Collision.contacts(trunk_start, trunk_end, hull, canopy_world, 3, mass, inertia)
	_check("tree trunk uses terminal hard response", not trunk_hits.is_empty() and trunk_hits[0].terminal
		and trunk_hits[0].obstacle_kind == "tree_trunk")
	if not trunk_hits.is_empty():
		_check("trunk incident energy is a finite severity estimate", is_finite(trunk_hits[0].impact_energy_j) and trunk_hits[0].impact_energy_j > 0.0)


func _test_severity_and_energy_response() -> void:
	var lamp_world := _world([], [], [{id = "severity-lamp", type = "flood", north = 5.0, east = 0.0, height = 8.0}])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var low_start := _state(0.0, 0.0, -4.0, 8.0, 0.0, 0.0)
	var low_end := _state(10.0, 0.0, -4.0, 8.0, 0.0, 0.0)
	var low_hit := Collision.first_hit(low_start, low_end, hull, lamp_world, 10, mass, inertia)
	_check("low-speed lamp contact survives as a frangible impulse", low_hit != null and not low_hit.terminal
		and low_hit.response_class == "frangible_impulse")
	var high_start := _state(0.0, 0.0, -4.0, 20.0, 0.0, 0.0)
	var high_end := _state(10.0, 0.0, -4.0, 20.0, 0.0, 0.0)
	var high_hit := Collision.first_hit(high_start, high_end, hull, lamp_world, 11, mass, inertia)
	_check("same lamp at higher normal speed becomes terminal", high_hit != null and high_hit.terminal)
	var glancing_start := _state(5.0699999, -5.0, -4.0, 0.0, 2400.0, 0.0)
	var glancing_end := _state(5.0699999, 5.0, -4.0, 0.0, 2400.0, 0.0)
	var glancing_hit := Collision.first_hit(glancing_start, glancing_end, hull, lamp_world, 12, mass, inertia)
	_check("high total speed with low grazing normal speed stays nonterminal", glancing_hit != null
		and glancing_hit.normal_speed_mps < Collision.FRANGIBLE_TERMINAL_NORMAL_SPEED_MPS
		and not glancing_hit.terminal)
	if glancing_hit != null:
		var response := Collision.apply_response(glancing_hit.contact_state(), glancing_hit, mass, inertia)
		_check("grazing impulse removes normal energy without creating kinetic energy", response.ok
			and response.dissipated_energy_j > 0.0 and response.kinetic_after_j <= response.kinetic_before_j)
	var fleet_groups := [{id = "parked", type = "fleet", placements = [
		{north = 5.0, east = 0.0, heading = 0.0, aircraft = "jensen-das-ugly-stik-60"}]}]
	var aircraft_world := _world([], fleet_groups, [])
	var aircraft_proxy: Dictionary = {}
	for proxy: Dictionary in aircraft_world.proxies:
		if proxy.kind == "parked_aircraft":
			aircraft_proxy = proxy
			break
	var gentle_plane: Array[Collision.Event] = []
	if not aircraft_proxy.is_empty():
		var span := float(aircraft_proxy.half_x) + 0.2
		var aircraft_start := _state(float(aircraft_proxy.north), float(aircraft_proxy.east) - span,
			float(aircraft_proxy.down), 0.0, 5.0, 0.0)
		var aircraft_end := _state(float(aircraft_proxy.north), float(aircraft_proxy.east) + span,
			float(aircraft_proxy.down), 0.0, 5.0, 0.0)
		gentle_plane = Collision.contacts(aircraft_start, aircraft_end, hull, aircraft_world, 13, mass, inertia)
	_check("low-speed contact with parked aircraft has a distinct nonterminal response", not gentle_plane.is_empty()
		and gentle_plane[0].response_class == "light_airframe_impulse" and not gentle_plane[0].terminal)


func _test_open_shelter_void_and_parts() -> void:
	var group := {id = "shelter", type = "instances", prefab = "pit_shelter",
		placements = [{north = 5.0, east = 0.0, heading = 0.0, prefab = "pit_shelter"}]}
	var world := _world([], [group], [])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var under_start := _state(5.0, -5.0, -1.0, 0.0, 2400.0, 0.0)
	var under_end := _state(5.0, 5.0, -1.0, 0.0, 2400.0, 0.0)
	_check("open shelter does not collide as a solid air envelope", Collision.contacts(under_start, under_end, hull, world, 4, mass, inertia).is_empty())
	var post_start := _state(2.6, -1.0, -1.0, 0.0, 480.0, 0.0)
	var post_end := _state(2.6, 1.0, -1.0, 0.0, 480.0, 0.0)
	var post_hits: Array[Collision.Event] = Collision.contacts(post_start, post_end, hull, world, 5, mass, inertia)
	_check("open shelter post is independently collidable", not post_hits.is_empty() and post_hits[0].obstacle_part == "shelter_post")
	var roof_start := _state(5.0, 0.0, -1.0, 0.0, 0.0, -720.0)
	var roof_end := _state(5.0, 0.0, -4.0, 0.0, 0.0, -720.0)
	var roof_hits: Array[Collision.Event] = Collision.contacts(roof_start, roof_end, hull, world, 6, mass, inertia)
	_check("open shelter roof is independently collidable", not roof_hits.is_empty() and roof_hits[0].obstacle_part == "shelter_roof")


func _test_building_vehicle_and_fleet_boxes() -> void:
	var groups: Array = [
		{id = "shed", type = "instances", placements = [{north = 5.0, east = 0.0, heading = 0.0, prefab = "shed"}]},
		{id = "car", type = "instances", placements = [{north = 20.0, east = 0.0, heading = 0.0, prefab = "car_sedan"}]},
	]
	var fleet_ids := ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]
	var fleet_placements: Array = []
	for index: int in fleet_ids.size():
		fleet_placements.append({north = 40.0 + 10.0 * float(index), east = 0.0, heading = 0.0, aircraft = fleet_ids[index]})
	groups.append({id = "fleet", type = "fleet", placements = fleet_placements})
	var world := _world([], groups, [])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var building_hit := _sweep_n(world, 5.0, -1.0, 0.0, hull)
	_check("building box creates terminal contact", not building_hit.is_empty() and building_hit[0].obstacle_kind == "building")
	var vehicle_hit := _sweep_n(world, 20.0, -0.7, 0.0, hull)
	_check("car box creates terminal contact", not vehicle_hit.is_empty() and vehicle_hit[0].obstacle_kind == "vehicle")
	for index: int in fleet_ids.size():
		var placement_id := "fleet:fleet:%02d:%s" % [index, fleet_ids[index]]
		var part: Dictionary = {}
		for proxy: Dictionary in world.proxies:
			if str(proxy.get("damage_id", "")) == placement_id:
				part = proxy
				break
		var hits: Array[Collision.Event] = []
		if not part.is_empty():
			hits = _sweep_n(world, float(part.north), float(part.down), float(part.east), hull)
		_check("parked aircraft %s is collidable" % fleet_ids[index], not hits.is_empty() and hits[0].obstacle_kind == "parked_aircraft")


func _test_rotation_sweep_and_tie_break() -> void:
	var target := 0.7071067811865476
	var rotation_world := _world([], [], [{id = "rotation-pole", type = "flood", north = target, east = target, height = 2.0}])
	var hull := PackedFloat64Array([1.0, 0.0, 0.0])
	var q_start := M.q_identity()
	var q_end := PackedFloat64Array([cos(PI / 4.0), 0.0, 0.0, sin(PI / 4.0)])
	var previous := _state(0.0, 0.0, -1.0, 0.0, 0.0, 0.0, q_start)
	var current := _state(0.0, 0.0, -1.0, 0.0, 0.0, 0.0, q_end)
	previous[RB.RATE + 2] = 0.0
	current[RB.RATE + 2] = PI * 0.5 * 240.0
	var rotating: Array[Collision.Event] = Collision.contacts(previous, current, hull, rotation_world, 7, mass, inertia)
	_check("subdivided attitude sweep catches arc missed by endpoint chord", not rotating.is_empty())
	if not rotating.is_empty():
		_check("rotating sweep reports a sub-tick fraction", rotating[0].time_fraction > 0.0 and rotating[0].time_fraction < 1.0)
	var tied_world := _world([], [], [
		{id = "zeta", type = "flood", north = 5.0, east = 0.0, height = 8.0},
		{id = "alpha", type = "flood", north = 5.0, east = 0.0, height = 8.0},
	])
	var line_start := _state(0.0, 0.0, -4.0, 240.0, 0.0, 0.0)
	var line_end := _state(10.0, 0.0, -4.0, 240.0, 0.0, 0.0)
	var first := Collision.first_hit(line_start, line_end, PackedFloat64Array([0.0, 0.0, 0.0]), tied_world, 8, mass, inertia)
	var repeated := Collision.first_hit(line_start, line_end, PackedFloat64Array([0.0, 0.0, 0.0]), tied_world, 8, mass, inertia)
	_check("simultaneous objects tie-break by stable ID", first != null and first.obstacle_id == "lamp:alpha:pole")
	_check("same input returns bit-stable time of impact", first != null and repeated != null and first.time_fraction == repeated.time_fraction)


func _test_rotational_chord_padding() -> void:
	# A 10 m probe turning through the detector's maximum 2° segment bows 1.523 mm outside its endpoint chord.
	var start := PackedFloat64Array([10.0, 0.0, 0.0])
	var finish := PackedFloat64Array([10.0 * cos(deg_to_rad(2.0)), 10.0 * sin(deg_to_rad(2.0)), 0.0])
	var arc_midpoint := PackedFloat64Array([10.0 * cos(deg_to_rad(1.0)), 10.0 * sin(deg_to_rad(1.0)), 0.0])
	var proxy := {shape = "capsule", north = arc_midpoint[0], east = arc_midpoint[1], down = 0.0,
		radius = 0.0001, half_length = 0.0}
	var sagitta := 10.0 * (1.0 - cos(deg_to_rad(1.0)))
	_check("unexpanded chord misses the curved-path witness", not Collision._segment_proxy(start, finish, proxy, 0.0).hit)
	_check("2-degree sagitta padding conservatively catches the rotational arc", Collision._segment_proxy(start, finish,
		proxy, sagitta + 1.0e-7).hit)
	_test_nlerp_rotation_padding()


func _test_nlerp_rotation_padding() -> void:
	# A 180° nlerp has a central segment about 1.27x the average angular increment.
	# Put a tiny witness on that true arc, where average-angle padding misses the chord.
	var q_start := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var q_finish := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var total_angle := PI
	var subdivisions := ceili(total_angle / Collision.MAX_ROTATION_STEP_RAD)
	var segment_index := subdivisions / 2 - 1
	var fraction0 := float(segment_index) / float(subdivisions)
	var fraction1 := float(segment_index + 1) / float(subdivisions)
	var q0: PackedFloat64Array = Collision._attitude_at(q_start, q_finish, fraction0)
	var q1: PackedFloat64Array = Collision._attitude_at(q_start, q_finish, fraction1)
	var q_mid: PackedFloat64Array = Collision._attitude_at(q_start, q_finish, (fraction0 + fraction1) * 0.5)
	var hull_point := PackedFloat64Array([10.0, 0.0, 0.0])
	var start := M.q_rotate(q0, hull_point)
	var finish := M.q_rotate(q1, hull_point)
	var witness := M.q_rotate(q_mid, hull_point)
	var average_angle := total_angle / float(subdivisions)
	var average_padding := 10.0 * (1.0 - M.cos_(average_angle * 0.5)) + 1.0e-9
	var segment_padding := Collision._rotational_chord_padding(q0, q1, 10.0)
	var actual_angle := 2.0 * M.acos_(absf(q0[0] * q1[0] + q0[1] * q1[1] + q0[2] * q1[2] + q0[3] * q1[3]))
	var proxy := {shape = "capsule", north = witness[0], east = witness[1], down = witness[2],
		radius = 0.0001, half_length = 0.0}
	_check("large-rotation central nlerp step exceeds the average angular step", actual_angle > average_angle * 1.25)
	_check("average-angle padding misses a witness on the large-rotation arc", not Collision._segment_proxy(start,
		finish, proxy, average_padding).hit)
	_check("actual per-segment nlerp padding catches the large-rotation arc", Collision._segment_proxy(start,
		finish, proxy, segment_padding).hit)


func _sweep_n(world: Dictionary, center_north: float, down: float, east: float, hull: PackedFloat64Array) -> Array[Collision.Event]:
	var start := _state(center_north - 5.0, east, down, 1200.0, 0.0, 0.0)
	var finish := _state(center_north + 5.0, east, down, 1200.0, 0.0, 0.0)
	return Collision.contacts(start, finish, hull, world, 9, mass, inertia)


func _world(trees: Array, groups: Array, fixtures: Array) -> Dictionary:
	var built: Dictionary = CollisionWorld.build(_field_with_trees(trees), {groups = groups}, {fixtures = fixtures})
	_check("synthetic world build succeeds", built.ok)
	return built.world


func _field_with_trees(trees: Array) -> Dictionary:
	return {id = "collision-test", pilot = {north = 0.0, east = 0.0, down = 0.0},
		objects = [{id = "test-trees", type = "treeline", positions = trees}]}


func _inventory_scenery() -> Dictionary:
	var placements: Array = []
	var aircraft := ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]
	for index: int in aircraft.size():
		placements.append({north = 400.0 + float(index) * 8.0, east = 0.0, heading = 0.0, aircraft = aircraft[index]})
	return {groups = [
		{id = "shelter", type = "instances", placements = [{north = 100.0, east = 0.0, heading = 0.0, prefab = "pit_shelter"}]},
		{id = "shed", type = "instances", placements = [{north = 200.0, east = 0.0, heading = 0.0, prefab = "shed"}]},
		{id = "car", type = "instances", placements = [{north = 300.0, east = 0.0, heading = 0.0, prefab = "car_sedan"}]},
		{id = "fleet", type = "fleet", placements = placements},
		{id = "avanti-cradle", type = "instances", placements = [
			{north = -17.6, east = 38.5, heading = 345.0, prefab = "avanti_cradle"}]},
	]}


func _inventory_lights() -> Dictionary:
	return {fixtures = [
		{id = "flood", type = "flood", north = 900.0, east = 0.0, height = 8.0},
		{id = "stakes", type = "stake_row", points = [[910.0, 0.0], [920.0, 0.0]], height = 0.35},
	]}


func _state(north: float, east: float, down: float, vn: float, ve: float, vd: float,
		attitude: PackedFloat64Array = PackedFloat64Array([1.0, 0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([vn, ve, vd]),
		attitude, PackedFloat64Array([0.0, 0.0, 0.0]))


func _proxy_ids_sorted(proxies: Array) -> bool:
	for index: int in range(1, proxies.size()):
		if str(proxies[index - 1].id) > str(proxies[index].id):
			return false
	return true


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)
