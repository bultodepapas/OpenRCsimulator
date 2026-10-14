## DT-11a: conservative exclusion culling before testing the fixed grass rows.
extends SceneTree

const Grass = preload("res://scenery/imported_near_grass.gd")
const NearGrass = preload("res://render/near_grass.gd")
const Mask = preload("res://render/landscape_upgrade/scenery_grass_mask.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var rows := Grass._placement_rows()
	var inside := not rows.is_empty()
	for row: Array in rows:
		inside = inside and absf(float(row[0]) * 0.001) <= NearGrass.RADIUS_M \
			and absf(float(row[1]) * 0.001) <= NearGrass.RADIUS_M
	_check("every validated row fits the culling radius", inside)
	_test_edges()
	_test_predicate_parity()
	print("grass mask bounds: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_edges() -> void:
	for axis: String in ["north", "east"]:
		for sign_value: float in [-1.0, 1.0]:
			var bound := axis + ("_min" if sign_value > 0.0 else "_max")
			var record := {north_min = -100.0, north_max = 100.0, east_min = -100.0, east_max = 100.0}
			record[bound] = sign_value * (NearGrass.RADIUS_M + Mask.CLEARANCE_M)
			_check("expanded boundary stays inclusive: " + bound, Grass._nearby_exclusions(0.0, 0.0, [record]).size() == 1)
			record[bound] += sign_value * 0.000001
			_check("strictly separated boundary is removed: " + bound, Grass._nearby_exclusions(0.0, 0.0, [record]).is_empty())
	var polygon := PackedVector2Array([Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)])
	var near_record := Mask._record("near", "test", polygon)
	_check("moving the pilot reevaluates the mask list", Grass._nearby_exclusions(0, 0, [near_record]).size() == 1 \
		and Grass._nearby_exclusions(100, 100, [near_record]).is_empty())
	_check("absent bounds and non-dictionaries cannot exclude finite points", Grass._nearby_exclusions(0, 0, [null, 1, "x", {}, {points = polygon}]).is_empty())
	for bound: String in ["north_min", "north_max", "east_min", "east_max"]:
		var record := near_record.duplicate(true)
		record[bound] = NAN
		_check("indeterminate bound remains for the point predicate: " + bound, Grass._nearby_exclusions(0, 0, [record]).size() == 1)
	_check("indeterminate pilot coordinates do not create a false gap", Grass._nearby_exclusions(NAN, NAN, [near_record]).size() == 1)
	var broad := near_record.duplicate(true)
	broad.points = PackedVector2Array([Vector2(200, 200), Vector2(200, 201), Vector2(201, 201)])
	_check("overlapping bounds leave polygon decisions to the original predicate", Grass._nearby_exclusions(0, 0, [broad]).size() == 1)


func _test_predicate_parity() -> void:
	# Concave, repeated-vertex, far, malformed and exact-clearance masks. Compare
	# the unmodified polygon predicate at boundaries and throughout the whole square.
	var masks: Array = [
		Mask._record("concave", "test", PackedVector2Array([Vector2(-5,-5), Vector2(-5,5), Vector2(0,1), Vector2(5,5), Vector2(5,-5)])),
		Mask._record("edge", "test", PackedVector2Array([Vector2(30.4,-2), Vector2(30.4,2), Vector2(32,2), Vector2(32,-2)])),
		Mask._record("far", "test", PackedVector2Array([Vector2(90,90), Vector2(90,91), Vector2(91,91)])),
		Mask._record("degenerate", "test", PackedVector2Array([Vector2(10,10), Vector2(10,10), Vector2(11,10)])),
		{}, null, "invalid", {north_min = -1, north_max = 1, east_min = -1, east_max = 1, points = "invalid"},
	]
	var before := var_to_bytes(masks)
	for pilot: Vector2 in [Vector2.ZERO, Vector2(12.25,-8.5), Vector2(100,100), Vector2(-40000,40000)]:
		var filtered := Grass._nearby_exclusions(float(pilot.x), float(pilot.y), masks)
		var same := true
		for n in range(-30, 31):
			for e in range(-30, 31):
				var north := float(pilot.x) + float(n)
				var east := float(pilot.y) + float(e)
				same = same and Mask.excludes(north, east, masks) == Mask.excludes(north, east, filtered)
		_check("full 61-by-61 square agrees at pilot " + str(pilot), same)
	_check("input masks are unchanged", before == var_to_bytes(masks))
	var edge_result := Grass._nearby_exclusions(0, 0, masks)
	var edge_ok := true
	for north: float in [29.999999, 30.0, -30.0]:
		for east: float in [-2.4, -2.0, 0.0, 2.0, 2.4]:
			edge_ok = edge_ok and Mask.excludes(north, east, masks) == Mask.excludes(north, east, edge_result)
	_check("clearance and sampling edge decisions agree", edge_ok)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)
