extends RefCounted
const M = preload("res://physics/math3d.gd")

static func _sample_surface(road: Callable, north: float, east: float) -> Dictionary:
	if not road.is_valid() or not is_finite(north) or not is_finite(east):
		return _failure("Invalid road sample request")
	var raw: Variant = road.call(north, east)
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("Road callback must return a Dictionary")
	var surface: Dictionary = raw
	if not surface.has("height_m") or not surface.has("normal_ned") or not surface.has("mu") or not surface.has("rolling"):
		return _failure("Road callback omitted height, normal, friction, or rolling resistance")
	var normal_variant: Variant = surface["normal_ned"]
	if typeof(normal_variant) != TYPE_PACKED_FLOAT64_ARRAY:
		return _failure("Road normal must be a PackedFloat64Array")
	var normal: PackedFloat64Array = normal_variant
	if normal.size() != 3 or not _finite_array(normal):
		return _failure("Road normal must contain three finite NED values")
	var normal_length := M.norm(normal)
	if absf(normal_length - 1.0) > 1.0e-5:
		return _failure("Road normal must be unit length")
	var height := float(surface["height_m"])
	var mu := float(surface["mu"])
	var rolling := float(surface["rolling"])
	if not is_finite(height) or not is_finite(mu) or not is_finite(rolling) or mu < 0.0 or rolling < 0.0:
		return _failure("Road height/friction/rolling values must be finite and nonnegative where applicable")
	return {"ok": true, "surface": surface}


static func _sample_road_batch(road: Callable, coordinates_xy: PackedFloat64Array) -> Dictionary:
	if not road.is_valid() or coordinates_xy.size() % 2 != 0 or not _finite_array(coordinates_xy):
		return {"ok": false, "error": "Native road batch request is malformed", "samples": PackedFloat64Array()}
	var samples := PackedFloat64Array()
	for index in range(0, coordinates_xy.size(), 2):
		var sampled := _sample_surface(road, coordinates_xy[index], coordinates_xy[index + 1])
		if not bool(sampled.get("ok", false)):
			return {"ok": false, "error": str(sampled.get("error", "Road callback failed")), "samples": PackedFloat64Array()}
		var surface: Dictionary = sampled["surface"]
		var normal: PackedFloat64Array = surface["normal_ned"]
		samples.append(float(surface["height_m"]))
		samples.append(normal[0])
		samples.append(normal[1])
		samples.append(normal[2])
		samples.append(float(surface["mu"]))
		samples.append(float(surface["rolling"]))
	return {"ok": true, "error": "", "samples": samples}


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
