extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const Oracle := preload("res://tests/fixtures/scenery_collision_reference.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const ORACLE_SHA256 := "fe4aac96ea43249bc2616c6c3658303e4ce26e10bf85e40b9a4f3f6c864c5e68"

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_reference_is_frozen()
	_test_deterministic_differential_sweeps()
	print("landscape collision oracle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_reference_is_frozen() -> void:
	var source := FileAccess.get_file_as_string("res://tests/fixtures/scenery_collision_reference.gd")
	# Git may use CRLF on Windows; pin code content in the baseline's LF form.
	source = source.replace("\r\n", "\n")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(source.to_utf8_buffer())
	_check("oracle retains baseline detector marker", source.begins_with("## LU-05: deterministic continuous contact"))
	_check("oracle matches committed baseline SHA-256", hash.finish().hex_encode() == ORACLE_SHA256)
	_check("oracle has independent full contacts implementation", source.contains("static func contacts(")
		and source.contains("static func _candidate_indices("))


func _test_deterministic_differential_sweeps() -> void:
	var tree_points: Array = []
	for row: int in 9:
		for column: int in 9:
			var north := -48.0 + float(row) * 12.0 + float((row * 7 + column * 3) % 5) * 0.17
			var east := -48.0 + float(column) * 12.0 - float((column * 11 + row) % 7) * 0.13
			tree_points.append([north, east, 0.0])
	var placements: Array = []
	for index: int in 24:
		var north := -48.0 + float(index % 6) * 19.0 + float(index % 3) * 0.11
		var east := -42.0 + float(index / 6) * 22.0 - float(index % 4) * 0.09
		placements.append({north = north, east = east, heading = float((index * 37) % 360),
			prefab = "car_sedan" if index % 2 == 0 else "shed"})
	var fleet: Array = []
	for index: int in 4:
		var ids := ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]
		fleet.append({north = -50.0 + float(index) * 32.0, east = 62.0, heading = float(index * 67), aircraft = ids[index]})
	var fixtures: Array = []
	for index: int in 16:
		fixtures.append({id = "lamp-%02d" % index, type = "flood",
			north = -54.0 + float(index % 4) * 35.0, east = -36.0 + float(index / 4) * 24.0, height = 5.0 + float(index % 5)})
	var world_result: Dictionary = CollisionWorld.build(
		{pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = [
			{id = "oracle-grid", type = "treeline", positions = tree_points}]},
		{groups = [
			{id = "mixed-structures", type = "instances", placements = placements},
			{id = "parked", type = "fleet", placements = fleet}]},
		{fixtures = fixtures})
	_check("differential fixture world builds", world_result.ok)
	if not world_result.ok:
		return
	var world: Dictionary = world_result.world
	var loaded: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT)
	_check("reference aircraft hull loads", loaded.ok)
	if not loaded.ok:
		return
	var model: Dictionary = loaded.model
	var hull: PackedFloat64Array = model.crash_hull
	var mass := float(model.mass_kg)
	var inertia: PackedFloat64Array = model.inertia
	var cases_with_hits := 0
	var total_contacts := 0
	for index: int in 160:
		var start_n := float((index * 37) % 141 - 70) + float((index * 7) % 19 - 9) * 0.13
		var start_e := float((index * 23) % 141 - 70) + float((index * 11) % 17 - 8) * 0.19
		var start_d := -float((index * 13) % 14) * 0.65 - 0.1
		var move_n := float((index * 29) % 81 - 40) * 1.1
		var move_e := float((index * 41) % 77 - 38) * 0.9
		var move_d := float((index * 17) % 25 - 12) * 0.32
		if index % 16 == 0:
			# Exercise high-speed sweeps, large nlerp rotations and 32 m cell crossings.
			move_n = 105.0 - float(index % 4) * 9.0
			move_e = -61.0 + float(index % 3) * 8.0
		var yaw0 := float((index * 29) % 360) * PI / 180.0
		var pitch0 := float((index * 13) % 80 - 40) * PI / 180.0
		var roll0 := float((index * 17) % 80 - 40) * PI / 180.0
		var yaw_delta := PI if index % 16 == 0 else float((index * 43) % 150 - 75) * PI / 180.0
		var pitch_delta := float((index * 31) % 80 - 40) * PI / 180.0
		var roll_delta := float((index * 19) % 80 - 40) * PI / 180.0
		var attitude0 := M.q_from_euler(yaw0, pitch0, roll0)
		var attitude1 := M.q_from_euler(yaw0 + yaw_delta, pitch0 + pitch_delta, roll0 + roll_delta)
		var speed := 18.0 + float((index * 7) % 91)
		var previous := _state(start_n, start_e, start_d, speed, float(index % 11) - 5.0,
			float(index % 7) - 3.0, attitude0, float(index % 9) * 1.1, float(index % 5) * -0.7, float(index % 4) * 0.9)
		var current := _state(start_n + move_n, start_e + move_e, start_d + move_d, speed,
			float(index % 11) - 5.0, float(index % 7) - 3.0, attitude1,
			float(index % 9) * 1.1, float(index % 5) * -0.7, float(index % 4) * 0.9)
		var reference_hits: Array = Oracle.contacts(previous, current, hull, world, index, mass, inertia)
		var candidate_hits: Array = Collision.contacts(previous, current, hull, world, index, mass, inertia)
		var equal := _events_equal(reference_hits, candidate_hits)
		_check_case("contacts equal frozen oracle", index, equal,
			"reference=%d candidate=%d" % [reference_hits.size(), candidate_hits.size()])
		if reference_hits.size() > 0:
			cases_with_hits += 1
			total_contacts += reference_hits.size()
		var reference_first: Variant = reference_hits[0] if not reference_hits.is_empty() else null
		var candidate_first: Variant = Collision.first_hit(previous, current, hull, world, index, mass, inertia)
		_check_case("first hit equals frozen oracle first contact", index,
			_events_equal([reference_first] if reference_first != null else [],
				[candidate_first] if candidate_first != null else []),
			"reference=%s candidate=%s" % [_event_id(reference_first), _event_id(candidate_first)])
	_check("differential includes actual contacts", cases_with_hits >= 20 and total_contacts >= cases_with_hits)
	print("oracle_differential sweeps=160; cases_with_hits=", cases_with_hits, "; contacts=", total_contacts,
		"; proxies=", world.proxies.size(), "; bins=", world.bins.size())


func _events_equal(reference: Array, candidate: Array) -> bool:
	if reference.size() != candidate.size():
		return false
	for index: int in reference.size():
		if not _event_equal(reference[index], candidate[index]):
			return false
	return true


func _event_equal(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == b
	var scalar_fields: Array[String] = [
		"trigger", "tick", "point_index", "component_name", "has_kinematics", "speed_mps", "down_speed_mps",
		"has_compression", "compression_m", "travel_limit_m", "obstacle_id", "obstacle_kind", "obstacle_part",
		"response_class", "response_status", "restitution", "dissipated_energy_j", "time_fraction",
		"normal_speed_mps", "effective_mass_kg", "impact_energy_j", "terminal"]
	for field: String in scalar_fields:
		if a.get(field) != b.get(field):
			return false
	var packed_fields: Array[String] = ["detected_state", "body_point", "point_ned", "velocity_ned", "normal_ned"]
	for field: String in packed_fields:
		if not _packed_equal(a.get(field), b.get(field)):
			return false
	if not _packed_equal(a.contact_state(), b.contact_state()):
		return false
	var cross_a: Variant = a.get("crossing")
	var cross_b: Variant = b.get("crossing")
	if cross_a == null or cross_b == null:
		return cross_a == cross_b
	for field: String in ["available", "reason", "method", "fraction", "point_index"]:
		if cross_a.get(field) != cross_b.get(field):
			return false
	for field: String in ["position_ned", "attitude", "point_ned"]:
		if not _packed_equal(cross_a.get(field), cross_b.get(field)):
			return false
	return true


func _packed_equal(a: Variant, b: Variant) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if a[index] != b[index]:
			return false
	return true


func _event_id(event: Variant) -> String:
	return "null" if event == null else "%s:%s" % [str(event.obstacle_id), str(event.point_index)]


func _state(north: float, east: float, down: float, vn: float, ve: float, vd: float,
		attitude: PackedFloat64Array, p: float, q: float, r: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([vn, ve, vd]), attitude,
		PackedFloat64Array([p, q, r]))


func _check_case(label: String, index: int, condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL case=", index, " ", label, " ", detail)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)
