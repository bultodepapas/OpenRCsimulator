extends RefCounted
const M = preload("res://physics/math3d.gd")

static func _surface_error(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return ("Road callback must return a Dictionary")
	var surface: Dictionary = raw
	if not surface.has("height_m") or not surface.has("normal_ned") or not surface.has("mu") or not surface.has("rolling"):
		return ("Road callback omitted height, normal, friction, or rolling resistance")
	var normal_variant: Variant = surface["normal_ned"]
	if typeof(normal_variant) != TYPE_PACKED_FLOAT64_ARRAY:
		return ("Road normal must be a PackedFloat64Array")
	var normal: PackedFloat64Array = normal_variant
	if normal.size() != 3 or not is_finite(normal[0]) or not is_finite(normal[1]) or not is_finite(normal[2]):
		return ("Road normal must contain three finite NED values")
	var normal_length := M.sqrt_(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if absf(normal_length - 1.0) > 1.0e-5:
		return ("Road normal must be unit length")
	var height := float(surface["height_m"])
	var mu := float(surface["mu"])
	var rolling := float(surface["rolling"])
	if not is_finite(height) or not is_finite(mu) or not is_finite(rolling) or mu < 0.0 or rolling < 0.0:
		return ("Road height/friction/rolling values must be finite and nonnegative where applicable")
	return ""

static func _sample_road_batch(road: Callable, coordinates_xy: PackedFloat64Array) -> Dictionary:
	if not road.is_valid() or coordinates_xy.size() % 2 != 0 or not _finite_array(coordinates_xy):
		return {"ok": false, "error": "Native road batch request is malformed", "samples": PackedFloat64Array()}
	var samples := PackedFloat64Array()
	samples.resize(coordinates_xy.size() * 3)
	var output_index := 0
	for index in range(0, coordinates_xy.size(), 2):
		var north := coordinates_xy[index]
		var east := coordinates_xy[index + 1]
		if not road.is_valid() or not is_finite(north) or not is_finite(east):
			return {"ok": false, "error": "Invalid road sample request", "samples": PackedFloat64Array()}
		var raw: Variant = road.call(north, east)
		var error := _surface_error(raw)
		if not error.is_empty():
			return {"ok": false, "error": error, "samples": PackedFloat64Array()}
		var surface: Dictionary = raw
		var normal: PackedFloat64Array = surface["normal_ned"]
		samples[output_index] = float(surface["height_m"])
		samples[output_index + 1] = normal[0]
		samples[output_index + 2] = normal[1]
		samples[output_index + 3] = normal[2]
		samples[output_index + 4] = float(surface["mu"])
		samples[output_index + 5] = float(surface["rolling"])
		output_index += 6
	return {"ok": true, "error": "", "samples": samples}

static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true
