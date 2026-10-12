extends SceneTree

const MeshKit = preload("res://scenery/mesh_kit.gd")
const GroundFeatures = preload("res://scenery/ground_features.gd")
const Prefabs = preload("res://scenery/prefabs.gd")

var failures := 0


func _initialize() -> void:
	_test_apron()
	_test_service_details()
	print("LU08 scenery ground checks passed" if failures == 0 else "%d LU08 scenery ground checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_apron() -> void:
	var apron := PackedVector2Array([
		Vector2(-33.5, -24.0), Vector2(-33.5, 5.5), Vector2(-35.0, 7.0), Vector2(-44.5, 7.0),
		Vector2(-45.5, 5.5), Vector2(-45.5, -34.5), Vector2(-44.0, -36.0), Vector2(-35.0, -36.0), Vector2(-33.5, -34.0),
	])
	var first := MeshKit.new()
	var repeated := MeshKit.new()
	GroundFeatures.patch(first, apron, "gravel", "temperate", 913)
	GroundFeatures.patch(repeated, apron, "gravel", "temperate", 913)
	_check("car apron remains within the ground triangle budget", first.triangle_count() <= 4000)
	_check("apron triangles remain within clipped tile bounds", _max_triangle_edge(first) <= 2.0)
	_check("sparse aggregate uses sub-metre clipped cells", _small_triangle_count(first) >= 20)
	_check("apron fill is deterministic", first.verts == repeated.verts and first.cols == repeated.cols)
	_check("apron uses only the established shoulder and surface lifts", _has_only_lifts(first, [GroundFeatures.LIFT_WORN, GroundFeatures.LIFT_SURFACE]))
	_check("apron gains fine color variation", _unique_colors(first.cols) >= 6)
	_check("rough edge remains inside the shoulder envelope", _within_apron_envelope(first, apron, 1.1))
	_check("outer shoulder feathers back into field grass", _field_edge_resolves_to_grass(first, apron))


func _test_service_details() -> void:
	var charger := MeshKit.new()
	var fuel_can := MeshKit.new()
	Prefabs._battery_charger(charger, Vector3.ZERO, 913)
	Prefabs._fuel_jug(fuel_can, Vector3.ZERO, 917)
	_check("battery charger stays below the prop budget", charger.triangle_count() > 0 and charger.triangle_count() <= 200)
	_check("fuel can stays below the prop budget", fuel_can.triangle_count() > 0 and fuel_can.triangle_count() <= 200)
	var shelter := MeshKit.new()
	var motion := Prefabs.build("pit_shelter", shelter, 3021, "temperate")
	_check("pit shelter adds no animated parts", motion.is_empty())
	_check("service details remain within the existing shelter bounds", _within_prefab_bounds(shelter, Prefabs.CATALOG["pit_shelter"].size))
	_check("service detail mesh arrays are complete", shelter.verts.size() % 3 == 0 and shelter.norms.size() == shelter.verts.size() and shelter.cols.size() == shelter.verts.size())


func _has_only_lifts(kit: MeshKit, lifts: Array[float]) -> bool:
	for p: Vector3 in kit.verts:
		var found := false
		for lift: float in lifts:
			if absf(p.y - lift) < 0.000001:
				found = true
				break
		if not found:
			return false
	return true


func _unique_colors(colors: PackedColorArray) -> int:
	var unique := {}
	for c: Color in colors:
		unique[c.to_rgba32()] = true
	return unique.size()


func _max_triangle_edge(kit: MeshKit) -> float:
	var longest := 0.0
	for i in range(0, kit.verts.size(), 3):
		longest = maxf(longest, kit.verts[i].distance_to(kit.verts[i + 1]))
		longest = maxf(longest, kit.verts[i + 1].distance_to(kit.verts[i + 2]))
		longest = maxf(longest, kit.verts[i + 2].distance_to(kit.verts[i]))
	return longest


func _small_triangle_count(kit: MeshKit) -> int:
	var count := 0
	for i in range(0, kit.verts.size(), 3):
		var longest := maxf(kit.verts[i].distance_to(kit.verts[i + 1]), maxf(kit.verts[i + 1].distance_to(kit.verts[i + 2]), kit.verts[i + 2].distance_to(kit.verts[i])))
		if longest < 0.7:
			count += 1
	return count


func _within_apron_envelope(kit: MeshKit, poly: PackedVector2Array, shoulder: float) -> bool:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p: Vector2 in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	for v: Vector3 in kit.verts:
		if v.x < min_x - shoulder or v.x > max_x + shoulder or v.z < min_z - shoulder or v.z > max_z + shoulder:
			return false
	return true


func _field_edge_resolves_to_grass(kit: MeshKit, poly: PackedVector2Array) -> bool:
	var samples := 0
	var resolved := 0
	for i in kit.verts.size():
		var p := kit.verts[i]
		var point := Vector2(p.x, p.z)
		if absf(p.y - GroundFeatures.LIFT_WORN) > 0.000001 or Geometry2D.is_point_in_polygon(point, poly) or GroundFeatures._edge_distance(point, poly) < 0.75:
			continue
		samples += 1
		if _color_distance(kit.cols[i], GroundFeatures.PATCH_FIELD_GRASS_COLOR) <= 0.16:
			resolved += 1
	return samples >= 30 and resolved * 2 >= samples


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _within_prefab_bounds(kit: MeshKit, expected: Vector3) -> bool:
	if kit.verts.is_empty():
		return false
	var min_v := kit.verts[0]
	var max_v := kit.verts[0]
	for v: Vector3 in kit.verts:
		min_v = min_v.min(v)
		max_v = max_v.max(v)
	var size := max_v - min_v
	return absf(size.x - expected.x) <= expected.x * 0.1 and absf(size.y - expected.y) <= expected.y * 0.1 and absf(size.z - expected.z) <= expected.z * 0.1


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
