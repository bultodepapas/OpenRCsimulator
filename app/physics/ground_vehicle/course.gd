## Deterministic analytic practice course shared by the vehicle kernel and renderer.
## World positions use north/east metres; surface height is positive Up; normals
## use NED and point outward/up. No engine vectors are used in this data path.
extends RefCounted

const Math3D := preload("res://physics/math3d.gd")
const FORMAT := "openrc-ground-course"
const VERSION := 1
const DEFAULT_PATH := "res://data/ground_vehicle/practice.json"
const TOP_KEYS := ["format", "version", "id", "name", "description", "bounds", "surfaces", "regions", "features", "spawns", "checkpoints"]
const BOUNDS_KEYS := ["north_min_m", "north_max_m", "east_min_m", "east_max_m"]
const SURFACE_KEYS := ["id", "name", "mu", "rolling", "color_srgb", "roughness"]
const REGION_KEYS := ["id", "surface_id", "north_min_m", "north_max_m", "east_min_m", "east_max_m", "priority"]
const FEATURE_BASE_KEYS := ["id", "type", "surface_id", "center_north_m", "center_east_m", "width_m", "shoulder_width_m", "height_m"]
const PROFILE_KEYS := ["approach_length_m", "top_length_m", "departure_length_m"]
const WEDGE_KEYS := ["length_m"]
const BUMP_KEYS := ["bump_length_m", "bump_spacing_m", "bump_count"]
const SPAWN_KEYS := ["id", "north_m", "east_m", "heading_rad", "vehicle_up_m"]
const CHECKPOINT_KEYS := ["id", "north_m", "east_m", "radius_m"]


static func load_default() -> Dictionary:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(PackedStringArray(["Cannot read ground course: %s (error %d)" % [path, FileAccess.get_open_error()]]))
	var source: String = file.get_as_text()
	file.close()
	var parsed := parse_text(source)
	if bool(parsed.get("ok", false)):
		var identity: Dictionary = parsed.identity.duplicate(true)
		identity.sha256 = FileAccess.get_sha256(path)
		parsed.identity = identity
	return parsed


static func parse_text(source: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _result(PackedStringArray([
			"Invalid ground course JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		]))
	var parsed := validate(parser.data)
	if bool(parsed.get("ok", false)):
		var identity: Dictionary = parsed.identity.duplicate(true)
		identity.sha256 = _sha256_bytes(source.to_utf8_buffer())
		parsed.identity = identity
	return parsed


## Atomic validation. Unknown fields and malformed quantities reject the whole course.
static func validate(data: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return _result(PackedStringArray(["Ground course data must be an object"]))
	_exact_keys(data, TOP_KEYS, "course", errors)
	if data.get("format") != FORMAT:
		errors.append("Unsupported ground course format")
	if not _number(data.get("version")) or float(data.get("version", -1.0)) != float(VERSION):
		errors.append("Unsupported ground course version")
	if not _text(data.get("id")) or not _text(data.get("name")) or not _text(data.get("description")):
		errors.append("Course id, name, and description must be nonempty text")
	var bounds := _parse_bounds(data.get("bounds"), errors)
	var surfaces := _parse_surfaces(data.get("surfaces"), errors)
	var surface_by_id: Dictionary = {}
	for surface in surfaces:
		surface_by_id[surface.id] = surface
	var regions := _parse_regions(data.get("regions"), surface_by_id, bounds, errors)
	var features := _parse_features(data.get("features"), surface_by_id, bounds, errors)
	var spawns := _parse_spawns(data.get("spawns"), bounds, errors)
	var checkpoints := _parse_checkpoints(data.get("checkpoints"), bounds, errors)
	if not errors.is_empty():
		return _result(errors)
	var course := {
		"id": str(data.id),
		"name": str(data.name),
		"description": str(data.description),
		"north_min_m": bounds.north_min_m,
		"north_max_m": bounds.north_max_m,
		"east_min_m": bounds.east_min_m,
		"east_max_m": bounds.east_max_m,
		"fallback_surface_id": "asphalt",
		"surfaces": surfaces,
		"surface_by_id": surface_by_id,
		"regions": regions,
		"features": features,
		"spawns": spawns,
		"checkpoints": checkpoints,
	}
	if not surface_by_id.has("asphalt"):
		errors.append("Course must define asphalt as the flat fallback surface")
		return _result(errors)
	var identity := {
		"format": FORMAT,
		"version": str(VERSION),
		"id": str(data.id),
		"sha256": _sha256_text(JSON.stringify(data, "", true, true)),
	}
	return _result(errors, course, identity)


## Returns a deterministic road sample. Height is positive Up; `normal_ned` is
## a unit outward/up normal in NED. Outside bounds the field is flat asphalt.
static func sample(course: Dictionary, north_m: float, east_m: float) -> Dictionary:
	var fallback_surface_id := str(course.get("fallback_surface_id", "asphalt"))
	var surface_by_id: Dictionary = course.get("surface_by_id", {})
	var fallback_surface: Dictionary = surface_by_id.get(fallback_surface_id, {"mu": 0.8, "rolling": 0.03})
	var flat := {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": float(fallback_surface.get("mu", 0.8)),
		"rolling": float(fallback_surface.get("rolling", 0.03)),
		"surface_id": fallback_surface_id,
		"in_bounds": false,
		"feature_id": "",
		"feature_ids": [],
	}
	if not is_finite(north_m) or not is_finite(east_m):
		return flat
	var in_bounds: bool = (
		north_m >= float(course.get("north_min_m", 0.0))
		and north_m <= float(course.get("north_max_m", 0.0))
		and east_m >= float(course.get("east_min_m", 0.0))
		and east_m <= float(course.get("east_max_m", 0.0))
	)
	var surface_id := fallback_surface_id
	var region_priority := -2147483648
	for region: Dictionary in course.get("regions", []):
		if (
			north_m >= float(region.north_min_m)
			and north_m <= float(region.north_max_m)
			and east_m >= float(region.east_min_m)
			and east_m <= float(region.east_max_m)
			and int(region.priority) > region_priority
		):
			surface_id = str(region.surface_id)
			region_priority = int(region.priority)
	var height := 0.0
	var dheight_dn := 0.0
	var dheight_de := 0.0
	var feature_id := ""
	var feature_height := -1.0
	var feature_ids: Array[String] = []
	for feature: Dictionary in course.get("features", []):
		var lateral := _lateral_profile(feature, east_m)
		if lateral.factor <= 0.0:
			continue
		var profile: PackedFloat64Array = _feature_profile(feature, north_m)
		if profile[0] <= 0.0:
			continue
		var contribution: float = profile[0] * lateral.factor
		height += contribution
		dheight_dn += profile[1] * lateral.factor
		dheight_de += profile[0] * lateral.derivative
		feature_ids.append(str(feature.id))
		if contribution > feature_height:
			feature_height = contribution
			feature_id = str(feature.id)
			surface_id = str(feature.surface_id)
	var normal := PackedFloat64Array([-dheight_dn, -dheight_de, -1.0])
	var magnitude: float = sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if magnitude > 0.0:
		normal[0] /= magnitude
		normal[1] /= magnitude
		normal[2] /= magnitude
	var surface: Dictionary = surface_by_id.get(surface_id, fallback_surface)
	return {
		"height_m": height,
		"normal_ned": normal,
		"mu": float(surface.get("mu", 0.8)),
		"rolling": float(surface.get("rolling", 0.03)),
		"surface_id": surface_id,
		"in_bounds": in_bounds,
		"feature_id": feature_id,
		"feature_ids": feature_ids,
	}


static func _parse_bounds(raw: Variant, errors: PackedStringArray) -> Dictionary:
	if not raw is Dictionary:
		errors.append("course.bounds must be an object")
		return {}
	_exact_keys(raw, BOUNDS_KEYS, "bounds", errors)
	var result := {}
	for key in BOUNDS_KEYS:
		result[key] = _quantity(raw.get(key), "m", "bounds." + key, errors)
	if result.get("north_max_m", 0.0) <= result.get("north_min_m", 0.0):
		errors.append("course north bounds must be increasing")
	if result.get("east_max_m", 0.0) <= result.get("east_min_m", 0.0):
		errors.append("course east bounds must be increasing")
	return result


static func _parse_surfaces(raw: Variant, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array or raw.is_empty():
		errors.append("course.surfaces must be a nonempty array")
		return result
	var seen: Dictionary = {}
	for index in raw.size():
		var item: Variant = raw[index]
		var path := "surfaces[%d]" % index
		if not item is Dictionary:
			errors.append("%s must be an object" % path)
			continue
		_exact_keys(item, SURFACE_KEYS, path, errors)
		var id: String = str(item.get("id", ""))
		if not _text(item.get("id")) or not _text(item.get("name")):
			errors.append("%s id and name must be nonempty text" % path)
		if seen.has(id):
			errors.append("%s duplicates surface id %s" % [path, id])
		seen[id] = true
		var mu: float = _quantity(item.get("mu"), "1", path + ".mu", errors)
		var rolling: float = _quantity(item.get("rolling"), "1", path + ".rolling", errors)
		if mu <= 0.0 or mu > 3.0:
			errors.append("%s.mu must be in (0, 3]" % path)
		if rolling < 0.0 or rolling > 1.0:
			errors.append("%s.rolling must be in [0, 1]" % path)
		var color: Variant = item.get("color_srgb")
		if not _finite_array(color, 3):
			errors.append("%s.color_srgb must contain three finite channels" % path)
			color = [0.0, 0.0, 0.0]
		else:
			for channel in color:
				if float(channel) < 0.0 or float(channel) > 1.0:
					errors.append("%s.color_srgb channels must be in [0, 1]" % path)
		var roughness: Variant = item.get("roughness")
		if not _number(roughness) or float(roughness) < 0.0 or float(roughness) > 1.0:
			errors.append("%s.roughness must be in [0, 1]" % path)
		result.append({
			"id": id,
			"name": str(item.get("name", "")),
			"mu": mu,
			"rolling": rolling,
			"color_srgb": PackedFloat64Array(color),
			"roughness": float(roughness) if _number(roughness) else 0.0,
		})
	return result


static func _parse_regions(raw: Variant, surfaces: Dictionary, bounds: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		errors.append("course.regions must be an array")
		return result
	var seen: Dictionary = {}
	for index in raw.size():
		var item: Variant = raw[index]
		var path := "regions[%d]" % index
		if not item is Dictionary:
			errors.append("%s must be an object" % path)
			continue
		_exact_keys(item, REGION_KEYS, path, errors)
		var id: String = str(item.get("id", ""))
		var surface_id: String = str(item.get("surface_id", ""))
		if not _text(item.get("id")) or seen.has(id):
			errors.append("%s requires a unique nonempty id" % path)
		seen[id] = true
		if not surfaces.has(surface_id):
			errors.append("%s references unknown surface '%s'" % [path, surface_id])
		var north_min: float = _quantity(item.get("north_min_m"), "m", path + ".north_min_m", errors)
		var north_max: float = _quantity(item.get("north_max_m"), "m", path + ".north_max_m", errors)
		var east_min: float = _quantity(item.get("east_min_m"), "m", path + ".east_min_m", errors)
		var east_max: float = _quantity(item.get("east_max_m"), "m", path + ".east_max_m", errors)
		var priority: Variant = item.get("priority")
		if not _integer_number(priority) or int(priority) < 0:
			errors.append("%s.priority must be a nonnegative integer" % path)
		if north_min >= north_max or east_min >= east_max:
			errors.append("%s rectangle bounds must be increasing" % path)
		_check_inside_bounds(north_min, north_max, east_min, east_max, bounds, path, errors)
		result.append({
			"id": id,
			"surface_id": surface_id,
			"north_min_m": north_min,
			"north_max_m": north_max,
			"east_min_m": east_min,
			"east_max_m": east_max,
			"priority": int(priority) if _integer_number(priority) else 0,
		})
	return result


static func _parse_features(raw: Variant, surfaces: Dictionary, bounds: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		errors.append("course.features must be an array")
		return result
	var seen: Dictionary = {}
	for index in raw.size():
		var item: Variant = raw[index]
		var path := "features[%d]" % index
		if not item is Dictionary:
			errors.append("%s must be an object" % path)
			continue
		var type: String = str(item.get("type", ""))
		var keys := FEATURE_BASE_KEYS.duplicate()
		if type in ["tabletop", "slope"]:
			keys.append_array(PROFILE_KEYS)
		elif type == "wedge":
			keys.append_array(WEDGE_KEYS)
		elif type == "bump_lane":
			keys.append_array(BUMP_KEYS)
		else:
			errors.append("%s.type is unsupported" % path)
		_exact_keys(item, keys, path, errors)
		var id: String = str(item.get("id", ""))
		var surface_id: String = str(item.get("surface_id", ""))
		if not _text(item.get("id")) or seen.has(id):
			errors.append("%s requires a unique nonempty id" % path)
		seen[id] = true
		if not surfaces.has(surface_id):
			errors.append("%s references unknown surface '%s'" % [path, surface_id])
		var feature := {
			"id": id,
			"type": type,
			"surface_id": surface_id,
			"center_north_m": _quantity(item.get("center_north_m"), "m", path + ".center_north_m", errors),
			"center_east_m": _quantity(item.get("center_east_m"), "m", path + ".center_east_m", errors),
			"width_m": _quantity(item.get("width_m"), "m", path + ".width_m", errors),
			"shoulder_width_m": _quantity(item.get("shoulder_width_m"), "m", path + ".shoulder_width_m", errors),
			"height_m": _quantity(item.get("height_m"), "m", path + ".height_m", errors),
		}
		if type in ["tabletop", "slope"]:
			feature["approach_length_m"] = _quantity(item.get("approach_length_m"), "m", path + ".approach_length_m", errors)
			feature["top_length_m"] = _quantity(item.get("top_length_m"), "m", path + ".top_length_m", errors)
			feature["departure_length_m"] = _quantity(item.get("departure_length_m"), "m", path + ".departure_length_m", errors)
		elif type == "wedge":
			feature["length_m"] = _quantity(item.get("length_m"), "m", path + ".length_m", errors)
		elif type == "bump_lane":
			feature["bump_length_m"] = _quantity(item.get("bump_length_m"), "m", path + ".bump_length_m", errors)
			feature["bump_spacing_m"] = _quantity(item.get("bump_spacing_m"), "m", path + ".bump_spacing_m", errors)
			var count: Variant = item.get("bump_count")
			if not _integer_number(count) or int(count) < 1 or int(count) > 12:
				errors.append("%s.bump_count must be an integer in [1, 12]" % path)
			feature["bump_count"] = int(count) if _integer_number(count) else 0
		_validate_feature(feature, bounds, path, errors)
		result.append(feature)
	return result


static func _parse_spawns(raw: Variant, bounds: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array or raw.is_empty():
		errors.append("course.spawns must be a nonempty array")
		return result
	var seen: Dictionary = {}
	for index in raw.size():
		var item: Variant = raw[index]
		var path := "spawns[%d]" % index
		if not item is Dictionary:
			errors.append("%s must be an object" % path)
			continue
		_exact_keys(item, SPAWN_KEYS, path, errors)
		var id: String = str(item.get("id", ""))
		if not _text(item.get("id")) or seen.has(id):
			errors.append("%s requires a unique nonempty id" % path)
		seen[id] = true
		var north: float = _quantity(item.get("north_m"), "m", path + ".north_m", errors)
		var east: float = _quantity(item.get("east_m"), "m", path + ".east_m", errors)
		var heading: float = _quantity(item.get("heading_rad"), "rad", path + ".heading_rad", errors)
		var up: float = _quantity(item.get("vehicle_up_m"), "m", path + ".vehicle_up_m", errors)
		if up <= 0.0:
			errors.append("%s.vehicle_up_m must be positive CG altitude above ground" % path)
		_check_point_inside_bounds(north, east, bounds, path, errors)
		result.append({"id": id, "north_m": north, "east_m": east, "heading_rad": heading, "vehicle_up_m": up})
	return result


static func _parse_checkpoints(raw: Variant, bounds: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		errors.append("course.checkpoints must be an array")
		return result
	var seen: Dictionary = {}
	for index in raw.size():
		var item: Variant = raw[index]
		var path := "checkpoints[%d]" % index
		if not item is Dictionary:
			errors.append("%s must be an object" % path)
			continue
		_exact_keys(item, CHECKPOINT_KEYS, path, errors)
		var id: String = str(item.get("id", ""))
		if not _text(item.get("id")) or seen.has(id):
			errors.append("%s requires a unique nonempty id" % path)
		seen[id] = true
		var north: float = _quantity(item.get("north_m"), "m", path + ".north_m", errors)
		var east: float = _quantity(item.get("east_m"), "m", path + ".east_m", errors)
		var radius: float = _quantity(item.get("radius_m"), "m", path + ".radius_m", errors)
		if radius <= 0.0:
			errors.append("%s.radius_m must be positive" % path)
		_check_point_inside_bounds(north, east, bounds, path, errors)
		result.append({"id": id, "north_m": north, "east_m": east, "radius_m": radius})
	return result


static func _validate_feature(feature: Dictionary, bounds: Dictionary, path: String, errors: PackedStringArray) -> void:
	if feature.width_m <= 0.0 or feature.shoulder_width_m < 0.0 or feature.height_m <= 0.0:
		errors.append("%s width/height must be positive and shoulder width nonnegative" % path)
	var total_length := 0.0
	if feature.type in ["tabletop", "slope"]:
		if feature.approach_length_m <= 0.0 or feature.top_length_m < 0.0 or feature.departure_length_m <= 0.0:
			errors.append("%s ramp lengths must be positive and top length nonnegative" % path)
		total_length = feature.approach_length_m + feature.top_length_m + feature.departure_length_m
	elif feature.type == "wedge":
		if feature.length_m <= 0.0:
			errors.append("%s.length_m must be positive" % path)
		total_length = feature.length_m
	elif feature.type == "bump_lane":
		if feature.bump_length_m <= 0.0 or feature.bump_spacing_m < feature.bump_length_m:
			errors.append("%s bump length must be positive and spacing must avoid overlap" % path)
		total_length = maxf(feature.bump_length_m, feature.bump_spacing_m * maxf(0.0, float(feature.bump_count - 1)) + feature.bump_length_m)
	var north_min: float = feature.center_north_m - total_length * 0.5
	var north_max: float = feature.center_north_m + total_length * 0.5
	var east_min: float = feature.center_east_m - feature.width_m * 0.5 - feature.shoulder_width_m
	var east_max: float = feature.center_east_m + feature.width_m * 0.5 + feature.shoulder_width_m
	_check_inside_bounds(north_min, north_max, east_min, east_max, bounds, path, errors)


static func _feature_profile(feature: Dictionary, north_m: float) -> PackedFloat64Array:
	var center: float = float(feature.center_north_m)
	if feature.type in ["tabletop", "slope"]:
		var rise: float = float(feature.approach_length_m)
		var top: float = float(feature.top_length_m)
		var fall: float = float(feature.departure_length_m)
		var start: float = center - (rise + top + fall) * 0.5
		if north_m < start or north_m > start + rise + top + fall:
			return PackedFloat64Array([0.0, 0.0])
		if north_m < start + rise:
			var t: float = (north_m - start) / rise
			return PackedFloat64Array([feature.height_m * _smooth01(t), feature.height_m * _smooth01_derivative(t) / rise])
		if north_m <= start + rise + top:
			return PackedFloat64Array([feature.height_m, 0.0])
		var t_down: float = (north_m - start - rise - top) / fall
		return PackedFloat64Array([feature.height_m * (1.0 - _smooth01(t_down)), -feature.height_m * _smooth01_derivative(t_down) / fall])
	if feature.type == "wedge":
		var length: float = float(feature.length_m)
		var start_wedge: float = center - length * 0.5
		var t_wedge: float = (north_m - start_wedge) / length
		if t_wedge <= 0.0 or t_wedge >= 1.0:
			return PackedFloat64Array([0.0, 0.0])
		var phase: float = PI * t_wedge
		var sine: float = Math3D.sin_(phase)
		return PackedFloat64Array([feature.height_m * sine * sine, feature.height_m * PI * Math3D.sin_(2.0 * phase) / length])
	if feature.type == "bump_lane":
		var count: int = int(feature.bump_count)
		for bump_index in count:
			var bump_center: float = center + (float(bump_index) - float(count - 1) * 0.5) * float(feature.bump_spacing_m)
			var t_bump: float = (north_m - (bump_center - float(feature.bump_length_m) * 0.5)) / float(feature.bump_length_m)
			if t_bump > 0.0 and t_bump < 1.0:
				var phase_bump: float = PI * t_bump
				var sine_bump: float = Math3D.sin_(phase_bump)
				return PackedFloat64Array([feature.height_m * sine_bump * sine_bump, feature.height_m * PI * Math3D.sin_(2.0 * phase_bump) / float(feature.bump_length_m)])
	return PackedFloat64Array([0.0, 0.0])


static func _lateral_profile(feature: Dictionary, east_m: float) -> Dictionary:
	var delta: float = east_m - float(feature.center_east_m)
	var distance: float = absf(delta)
	var half_width: float = float(feature.width_m) * 0.5
	var shoulder: float = float(feature.shoulder_width_m)
	if distance <= half_width:
		return {"factor": 1.0, "derivative": 0.0}
	if shoulder <= 0.0 or distance >= half_width + shoulder:
		return {"factor": 0.0, "derivative": 0.0}
	var t: float = (half_width + shoulder - distance) / shoulder
	var factor: float = _smooth01(t)
	var derivative_distance: float = -_smooth01_derivative(t) / shoulder
	return {"factor": factor, "derivative": derivative_distance * (1.0 if delta > 0.0 else -1.0)}


static func _smooth01(t: float) -> float:
	var clipped: float = clampf(t, 0.0, 1.0)
	return clipped * clipped * (3.0 - 2.0 * clipped)


static func _smooth01_derivative(t: float) -> float:
	var clipped: float = clampf(t, 0.0, 1.0)
	return 6.0 * clipped * (1.0 - clipped)


static func _quantity(raw: Variant, unit: String, path: String, errors: PackedStringArray) -> float:
	if not raw is Dictionary:
		errors.append("%s must be a quantity object" % path)
		return 0.0
	_exact_keys(raw, ["value", "unit", "kind", "source"], path, errors)
	if raw.get("unit") != unit:
		errors.append("%s requires unit %s" % [path, unit])
	if raw.get("kind") != "estimated":
		errors.append("%s must be marked estimated for this synthetic course" % path)
	if not _text(raw.get("source")):
		errors.append("%s requires nonempty provenance" % path)
	if not _number(raw.get("value")):
		errors.append("%s.value must be a finite number, not a boolean" % path)
		return 0.0
	return float(raw.value)


static func _check_inside_bounds(north_min: float, north_max: float, east_min: float, east_max: float, bounds: Dictionary, path: String, errors: PackedStringArray) -> void:
	if north_min < bounds.get("north_min_m", 0.0) or north_max > bounds.get("north_max_m", 0.0) or east_min < bounds.get("east_min_m", 0.0) or east_max > bounds.get("east_max_m", 0.0):
		errors.append("%s extends outside course bounds" % path)


static func _check_point_inside_bounds(north: float, east: float, bounds: Dictionary, path: String, errors: PackedStringArray) -> void:
	if north < bounds.get("north_min_m", 0.0) or north > bounds.get("north_max_m", 0.0) or east < bounds.get("east_min_m", 0.0) or east > bounds.get("east_max_m", 0.0):
		errors.append("%s point lies outside course bounds" % path)


static func _finite_array(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item in value:
		if not _number(item):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _integer_number(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _exact_keys(data: Dictionary, allowed: Array, path: String, errors: PackedStringArray) -> void:
	for key in allowed:
		if not data.has(key):
			errors.append("%s.%s is required" % [path, key])
	for key in data:
		if not key is String or not key in allowed:
			errors.append("Unknown field %s.%s" % [path, key])


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _sha256_text(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


static func _result(errors: PackedStringArray, course: Dictionary = {}, identity: Dictionary = {}) -> Dictionary:
	var okay := errors.is_empty()
	return {
		"ok": okay,
		"errors": errors,
		"course": course if okay else {},
		"identity": identity if okay else {},
	}
