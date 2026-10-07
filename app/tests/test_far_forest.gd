# L7: bounded far patches, preserved near identities and Compatibility packing.
# Run: godot --headless --path app --script res://tests/test_far_forest.gd
extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const Trees := preload("res://render/treeline.gd")

const NEAR_COUNT: int = 480
const FAR_COUNT: int = 1200
const NEAR_LIMIT_M: float = 600.0
const FAR_MIN_M: float = 600.0
const FAR_MAX_M: float = 1500.0
const TREE_CROWN_RADIUS_M: float = 15.0
const GAPS: Array[Vector2] = [Vector2(30.0, 8.0), Vector2(210.0, 10.0)]
const LEGACY_IDENTITY_SAMPLES: Array = [
	[-560.0, -37.25, 1, 24.212121212121, 1.412160785603],
	[-308.5, -1.0, 0, 18.048875855327, 1.816553155079],
	[-94.75, -561.5, 2, 17.629521016618, 4.180479239956],
	[262.75, -141.5, 1, 24.161290322581, 5.237442174828],
	[560.25, -70.0, 2, 13.181818181818, 1.917339586266],
]

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = Loader.load_from()
	_check("generated near/far field validates", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = loaded.field
	var object_data: Dictionary = field.objects[0]
	var positions: Array = object_data.positions
	var near_count: int = 0
	var far_count: int = 0
	var far_by_sector: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var all_far_in_range: bool = true
	var all_far_pack_exact: bool = true
	var all_crowns_clear_gaps: bool = true
	var all_trees_clear_corridor: bool = true
	for point: Array in positions:
		var north: float = float(point[0])
		var east: float = float(point[1])
		var radius: float = sqrt(north * north + east * east)
		var packed: Color = Trees.packed_position(north, east)
		var unpacked: Vector2 = Trees.unpacked_position(packed)
		all_far_pack_exact = all_far_pack_exact and unpacked.x == north and unpacked.y == east
		all_crowns_clear_gaps = all_crowns_clear_gaps and _crown_clears_gaps(north, east, radius)
		all_trees_clear_corridor = all_trees_clear_corridor and _tree_clears_corridor(north, field)
		if radius <= NEAR_LIMIT_M:
			near_count += 1
		else:
			far_count += 1
			all_far_in_range = all_far_in_range and radius >= FAR_MIN_M and radius <= FAR_MAX_M
			far_by_sector[Trees.sector(north, east)] += 1
	_check("L6b keeps exactly 480 near identities", near_count == NEAR_COUNT, str(near_count))
	_check("L7 adds exactly 1,200 far trees", far_count == FAR_COUNT, str(far_count))
	_check("far centers stay within the 600–1,500 m ring", all_far_in_range)
	_check("every packed N/E position round-trips exactly", all_far_pack_exact)
	_check("every complete crown keeps both deliberate gaps clear", all_crowns_clear_gaps)
	_check("all near and far centers keep the runway/mown corridor clear", all_trees_clear_corridor)
	_check("all eight sectors receive far forest", far_by_sector.min() > 0, str(far_by_sector))
	_test_near_identity_samples()
	_test_extended_pack_endpoints()
	print("L7 far forest: %d checks, %d failed; %d near, %d far; sector counts %s" % [
		_checks, _failures, near_count, far_count, far_by_sector,
	])
	quit(1 if _failures > 0 else 0)


func _crown_clears_gaps(north: float, east: float, radius: float) -> bool:
	if radius <= 0.0:
		return false
	var angle: float = fposmod(rad_to_deg(atan2(east, north)), 360.0)
	var margin: float = rad_to_deg(asin(TREE_CROWN_RADIUS_M / radius))
	for gap: Vector2 in GAPS:
		var delta: float = absf(fposmod(angle - gap.x + 180.0, 360.0) - 180.0)
		if delta <= gap.y + margin:
			return false
	return true


func _tree_clears_corridor(north: float, field: Dictionary) -> bool:
	for surface: Dictionary in field.surfaces:
		if surface.type != "runway" and surface.type != "mown":
			continue
		var clearance: float = float(surface.width_north_south) * 0.5 + 35.0 + TREE_CROWN_RADIUS_M
		if absf(north + float(field.pilot.north) - float(surface.center_north)) <= clearance:
			return false
	return true


func _test_near_identity_samples() -> void:
	var matches: bool = true
	for sample: Array in LEGACY_IDENTITY_SAMPLES:
		var identity: Dictionary = Trees.identity(float(sample[0]), float(sample[1]))
		matches = matches and int(identity.species) == int(sample[2])
		matches = matches and absf(float(identity.height) - float(sample[3])) <= 1e-10
		matches = matches and absf(float(identity.yaw) - float(sample[4])) <= 1e-10
	_check("frozen L6b sample identities survive the larger packing range", matches)


func _test_extended_pack_endpoints() -> void:
	var endpoints: Array[Vector2] = [
		Vector2(-1500.0, 0.0),
		Vector2(0.0, -1500.0),
		Vector2(1500.0, 0.0),
		Vector2(0.0, 1500.0),
	]
	var matches: bool = true
	for point: Vector2 in endpoints:
		var packed: Color = Trees.packed_position(point.x, point.y)
		var decoded: Vector2 = Trees.unpacked_position(packed)
		matches = matches and decoded == point
	_check("expanded south/east/west/north limits retain exact coordinates", matches)
