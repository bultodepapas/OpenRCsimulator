extends SceneTree

const Collision := preload("res://sim/scenery_collision.gd")
const World := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")

var cases: Array[Dictionary] = []
var failures := 0


func _initialize() -> void:
	var proxies: Array[Dictionary] = []
	World._add_capsule(proxies, "capsule", "tree_trunk", "trunk", "hard_terminal", 0, 0, 0, 1, 2)
	var world := {format = World.FORMAT, cell_size_m = World.CELL_SIZE_M, proxies = proxies,
		bins = World._build_bins(proxies)}
	_case(world, "hidden positive cap", 0.81, 1.39, 0.80, 1.41, 1, 0.7006265212)
	_case(world, "hidden negative cap", 0.81, -1.39, 0.80, -1.41, 1, 0.7006265212)
	_case(world, "interior at cylinder middle", 0.81, -0.01, 0.80, 0.01, 0)
	_case(world, "true external side entry", 1.01, -0.01, 0.99, 0.01, 1, 0.5)
	_case(world, "true external tip entry", 0.0, 3.01, 0.0, 2.99, 1, 0.5)
	_case(world, "wholly outside and approaching", 1.03, 1.39, 1.02, 1.41, 0)
	print("CAPSULE_SEAM ", JSON.stringify({cases = cases, failures = failures}))
	quit(0 if failures == 0 else 1)


func _case(world: Dictionary, label: String, r0: float, z0: float, r1: float, z1: float,
		expected_count: int, expected_fraction: float = -1.0) -> void:
	var velocity := PackedFloat64Array([(r1 - r0) * 240.0, 0.0, (z1 - z0) * 240.0])
	var q := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var start := RB.make_state(PackedFloat64Array([r0, 0.0, z0]), velocity, q, zero)
	var finish := RB.make_state(PackedFloat64Array([r1, 0.0, z1]), velocity, q, zero)
	var hits := Collision.contacts(start, finish, zero, world, 1, 1.0,
		PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))
	var record := {label = label, contacts = hits.size(), start_gap_m = _gap(r0, z0),
		finish_gap_m = _gap(r1, z1)}
	if hits.size() != expected_count:
		failures += 1
	if not hits.is_empty():
		var hit := hits[0]
		var gap := _gap(hit.point_ned[0], hit.point_ned[2])
		record["event_fraction"] = hit.time_fraction
		record["event_gap_m"] = gap
		record["normal_speed_mps"] = hit.normal_speed_mps
		record["terminal"] = hit.terminal
		if absf(hit.time_fraction - expected_fraction) > 1.0e-6 or not hit.terminal:
			failures += 1
		if label.begins_with("hidden") and (gap > -0.19 or absf(hit.normal_speed_mps - 2.4) > 1.0e-9):
			failures += 1
	cases.append(record)


func _gap(radial: float, axial: float) -> float:
	# Exact signed distance from a unit-radius capsule with axial interval [-2, 2].
	var past_end := maxf(absf(axial) - 2.0, 0.0)
	return sqrt(radial * radial + past_end * past_end) - 1.0
