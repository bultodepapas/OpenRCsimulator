## Loads and validates renderer-neutral, bounded lake terrain in local NED coordinates.
## Polygon coordinates in source JSON are north/east offsets in metres from `origin`.
extends RefCounted

const DEFAULT_PATH: String = "res://data/fields/lake.json"
const FORMAT: String = "openrc-lake v1"
const ROOT_ALLOWED_KEYS: Array[String] = [
	"format", "id", "origin", "water_level_down_m", "shoreline_offsets_ne_m",
	"bank_offsets_ne_m", "bed_profile", "waves", "source",
]
const ORIGIN_KEYS: Array[String] = ["north_m", "east_m"]
const WAVE_KEYS: Array[String] = [
	"max_amplitude_m", "min_wavelength_m", "max_wavelength_m",
	"min_period_s", "max_period_s", "shore_fade_m", "components",
]
const COMPONENT_KEYS: Array[String] = [
	"amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad",
]
const PROFILE_KEYS: Array[String] = ["inset_m", "depth_m"]
const MAX_VERTICES: int = 64
const MAX_OFFSET_M: float = 1000.0
const GEOMETRY_EPSILON_M: float = 0.000001
const AREA_EPSILON_M2: float = 0.001
const TAU: float = 6.2831853071795864769


## Result shape: {ok: bool, errors: PackedStringArray, lake: Dictionary, data: Dictionary}.
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("%s: cannot open lake file (error %d)" % [path, FileAccess.get_open_error()])
	var source_text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(source_text)
	if parse_result != OK:
		return _failure("%s: JSON error at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
	return validate(parser.data)


## Validate untrusted source and return absolute N/E polygons plus a canonical content identity.
static func validate(raw: Variant) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("lake: expected an object")
	var root: Dictionary = raw
	_check_keys(errors, "lake", root, ROOT_ALLOWED_KEYS, ROOT_ALLOWED_KEYS)
	if typeof(root.get("format")) != TYPE_STRING or root.get("format") != FORMAT:
		errors.append("format: expected '%s'" % FORMAT)
	var lake_id: String = _read_id(errors, root.get("id"))
	var origin: Dictionary = _object(errors, "origin", root.get("origin"))
	_check_keys(errors, "origin", origin, ORIGIN_KEYS, ORIGIN_KEYS)
	var origin_north: float = _read_number(errors, "origin.north_m", origin.get("north_m"), -1000000.0, 1000000.0)
	var origin_east: float = _read_number(errors, "origin.east_m", origin.get("east_m"), -1000000.0, 1000000.0)
	var water_down: float = _read_number(errors, "water_level_down_m", root.get("water_level_down_m"), 0.05, 2.0)
	var shoreline: PackedFloat64Array = _polygon(errors, "shoreline_offsets_ne_m", root.get("shoreline_offsets_ne_m"), origin_north, origin_east)
	var bank: PackedFloat64Array = _polygon(errors, "bank_offsets_ne_m", root.get("bank_offsets_ne_m"), origin_north, origin_east)
	if not shoreline.is_empty() and not bank.is_empty():
		_validate_containment(errors, shoreline, bank, origin_north, origin_east)
	var profile: Array[Dictionary] = _profile(errors, root.get("bed_profile"))
	var wave_bounds: Dictionary = _wave_bounds(errors, root.get("waves"))
	var waves: Array[Dictionary] = []
	if typeof(wave_bounds.get("components")) == TYPE_ARRAY:
		for wave_value: Variant in wave_bounds.components:
			if typeof(wave_value) == TYPE_DICTIONARY:
				waves.append(wave_value)
	wave_bounds.erase("components")
	var source: String = _read_source(errors, root.get("source"))
	if profile.size() >= 2 and not wave_bounds.is_empty():
		if float(wave_bounds.max_amplitude_m) > float(profile[1].depth_m):
			errors.append("waves.max_amplitude_m: must not exceed the first submerged bed depth")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "lake": {}, "data": {}}
	var lake: Dictionary = {
		"format": FORMAT,
		"id": lake_id,
		"origin_north_m": origin_north,
		"origin_east_m": origin_east,
		"water_level_down_m": water_down,
		"shoreline_ne_m": shoreline,
		"bank_ne_m": bank,
		"bed_profile": profile,
		"wave_bounds": wave_bounds,
		"waves": waves,
		"source": source,
	}
	lake["identity"] = identity(lake)
	return {"ok": true, "errors": errors, "lake": lake, "data": lake}


## SHA-256 over sorted normalized fields. Identity does not depend on source key order or formatting.
static func identity(lake: Dictionary) -> String:
	var canonical: Dictionary = lake.duplicate(true)
	canonical.erase("identity")
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(JSON.stringify(canonical, "", true, true).to_utf8_buffer())
	return context.finish().hex_encode()


static func _profile(errors: PackedStringArray, value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("bed_profile: expected an array")
		return result
	var rows: Array = value
	if rows.size() < 2 or rows.size() > 8:
		errors.append("bed_profile: expected 2 to 8 profile points")
	for index: int in range(rows.size()):
		var path: String = "bed_profile[%d]" % index
		var row: Dictionary = _object(errors, path, rows[index])
		_check_keys(errors, path, row, PROFILE_KEYS, PROFILE_KEYS)
		var inset: float = _read_number(errors, path + ".inset_m", row.get("inset_m"), 0.0, 200.0)
		var depth: float = _read_number(errors, path + ".depth_m", row.get("depth_m"), 0.0, 20.0)
		result.append({"inset_m": inset, "depth_m": depth})
	if result.size() >= 2:
		if absf(float(result[0].inset_m)) > GEOMETRY_EPSILON_M or absf(float(result[0].depth_m)) > GEOMETRY_EPSILON_M:
			errors.append("bed_profile[0]: must start at shoreline inset 0 and depth 0")
		for index: int in range(1, result.size()):
			if float(result[index].inset_m) <= float(result[index - 1].inset_m):
				errors.append("bed_profile[%d].inset_m: must strictly increase" % index)
			if float(result[index].depth_m) <= float(result[index - 1].depth_m):
				errors.append("bed_profile[%d].depth_m: must strictly increase" % index)
	return result


static func _wave_bounds(errors: PackedStringArray, value: Variant) -> Dictionary:
	var bounds: Dictionary = _object(errors, "waves", value)
	_check_keys(errors, "waves", bounds, WAVE_KEYS, WAVE_KEYS)
	var amplitude: float = _read_number(errors, "waves.max_amplitude_m", bounds.get("max_amplitude_m"), 0.0, 0.35)
	var min_wavelength: float = _read_number(errors, "waves.min_wavelength_m", bounds.get("min_wavelength_m"), 2.0, 50.0)
	var max_wavelength: float = _read_number(errors, "waves.max_wavelength_m", bounds.get("max_wavelength_m"), 2.0, 100.0)
	var min_period: float = _read_number(errors, "waves.min_period_s", bounds.get("min_period_s"), 0.25, 30.0)
	var max_period: float = _read_number(errors, "waves.max_period_s", bounds.get("max_period_s"), 0.25, 60.0)
	var shore_fade: float = _read_number(errors, "waves.shore_fade_m", bounds.get("shore_fade_m"), 0.25, 50.0)
	var components: Array[Dictionary] = _wave_components(errors, bounds.get("components"), amplitude,
		min_wavelength, max_wavelength, min_period, max_period)
	if max_wavelength < min_wavelength:
		errors.append("waves.max_wavelength_m: must be at least min_wavelength_m")
	if max_period < min_period:
		errors.append("waves.max_period_s: must be at least min_period_s")
	return {
		"max_amplitude_m": amplitude,
		"min_wavelength_m": min_wavelength,
		"max_wavelength_m": max_wavelength,
		"min_period_s": min_period,
		"max_period_s": max_period,
		"shore_fade_m": shore_fade,
		"components": components,
	}


static func _wave_components(errors: PackedStringArray, value: Variant, max_amplitude: float,
	min_wavelength: float, max_wavelength: float, min_period: float, max_period: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("waves.components: expected an array of up to two wave components")
		return result
	var rows: Array = value
	if rows.size() > 2:
		errors.append("waves.components: at most two analytic waves are allowed")
	var total_amplitude: float = 0.0
	for index: int in range(rows.size()):
		var path: String = "waves.components[%d]" % index
		var row: Dictionary = _object(errors, path, rows[index])
		_check_keys(errors, path, row, COMPONENT_KEYS, COMPONENT_KEYS)
		var amplitude: float = _read_number(errors, path + ".amplitude_m", row.get("amplitude_m"), 0.0, max_amplitude)
		var wavelength: float = _read_number(errors, path + ".wavelength_m", row.get("wavelength_m"), min_wavelength, max_wavelength)
		var period: float = _read_number(errors, path + ".period_s", row.get("period_s"), min_period, max_period)
		var heading: float = _read_number(errors, path + ".heading_rad", row.get("heading_rad"), -TAU * 100.0, TAU * 100.0)
		var phase: float = _read_number(errors, path + ".phase_rad", row.get("phase_rad"), -1000000.0, 1000000.0)
		total_amplitude += amplitude
		result.append({
			"amplitude_m": amplitude,
			"wavelength_m": wavelength,
			"period_s": period,
			"heading_rad": heading,
			"phase_rad": phase,
		})
	if total_amplitude > max_amplitude + GEOMETRY_EPSILON_M:
		errors.append("waves.components: summed amplitude may not exceed max_amplitude_m")
	return result


static func _polygon(errors: PackedStringArray, path: String, value: Variant,
	origin_north: float, origin_east: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if typeof(value) != TYPE_ARRAY:
		errors.append(path + ": expected an array of [north, east] offset pairs")
		return result
	var points: Array = value
	if points.size() < 8 or points.size() > MAX_VERTICES:
		errors.append("%s: expected 8 to %d vertices" % [path, MAX_VERTICES])
		return result
	for index: int in range(points.size()):
		if typeof(points[index]) != TYPE_ARRAY:
			errors.append("%s[%d]: expected [north_offset_m, east_offset_m]" % [path, index])
			return PackedFloat64Array()
		var pair: Array = points[index]
		if pair.size() != 2:
			errors.append("%s[%d]: expected exactly two coordinates" % [path, index])
			return PackedFloat64Array()
		var north_offset: float = _read_number(errors, "%s[%d][0]" % [path, index], pair[0], -MAX_OFFSET_M, MAX_OFFSET_M)
		var east_offset: float = _read_number(errors, "%s[%d][1]" % [path, index], pair[1], -MAX_OFFSET_M, MAX_OFFSET_M)
		result.append(origin_north + north_offset)
		result.append(origin_east + east_offset)
	if result.size() >= 16:
		_validate_simple_polygon(errors, path, result)
		var bounds: PackedFloat64Array = _polygon_bounds(result)
		if bounds[1] - bounds[0] < 10.0 or bounds[3] - bounds[2] < 10.0:
			errors.append(path + ": bounds must span at least 10 m north and east")
		if bounds[1] - bounds[0] > 1000.0 or bounds[3] - bounds[2] > 1000.0:
			errors.append(path + ": bounds may not exceed 1000 m north or east")
	return result


static func _validate_simple_polygon(errors: PackedStringArray, path: String, polygon: PackedFloat64Array) -> void:
	var count: int = polygon.size() / 2
	var twice_area: float = 0.0
	for index: int in range(count):
		var next: int = (index + 1) % count
		var north: float = polygon[index * 2]
		var east: float = polygon[index * 2 + 1]
		var next_north: float = polygon[next * 2]
		var next_east: float = polygon[next * 2 + 1]
		if _distance_sq(north, east, next_north, next_east) <= GEOMETRY_EPSILON_M * GEOMETRY_EPSILON_M:
			errors.append("%s[%d]: duplicate adjacent vertices are not allowed" % [path, index])
		twice_area += east * next_north - next_east * north
	if _distance_sq(polygon[0], polygon[1], polygon[polygon.size() - 2], polygon[polygon.size() - 1]) <= GEOMETRY_EPSILON_M * GEOMETRY_EPSILON_M:
		errors.append(path + ": omit a duplicate closing vertex")
	if absf(twice_area) * 0.5 < AREA_EPSILON_M2:
		errors.append(path + ": polygon area must be nonzero")
	for first: int in range(count):
		var first_next: int = (first + 1) % count
		for second: int in range(first + 1, count):
			var second_next: int = (second + 1) % count
			if first == second or first_next == second or second_next == first:
				continue
			if _segments_intersect(
				polygon[first * 2], polygon[first * 2 + 1], polygon[first_next * 2], polygon[first_next * 2 + 1],
				polygon[second * 2], polygon[second * 2 + 1], polygon[second_next * 2], polygon[second_next * 2 + 1]
			):
				errors.append("%s: polygon edges %d and %d intersect" % [path, first, second])
				return


static func _validate_containment(errors: PackedStringArray, shoreline: PackedFloat64Array,
	bank: PackedFloat64Array, origin_north: float, origin_east: float) -> void:
	if not _point_inside(shoreline, origin_north, origin_east):
		errors.append("origin: must lie inside the shoreline polygon")
	for index: int in range(shoreline.size() / 2):
		if not _point_inside(bank, shoreline[index * 2], shoreline[index * 2 + 1], false):
			errors.append("bank_offsets_ne_m: must strictly enclose every shoreline vertex")
			return
	var shore_count: int = shoreline.size() / 2
	var bank_count: int = bank.size() / 2
	for first: int in range(shore_count):
		var first_next: int = (first + 1) % shore_count
		for second: int in range(bank_count):
			var second_next: int = (second + 1) % bank_count
			if _segments_intersect(
				shoreline[first * 2], shoreline[first * 2 + 1], shoreline[first_next * 2], shoreline[first_next * 2 + 1],
				bank[second * 2], bank[second * 2 + 1], bank[second_next * 2], bank[second_next * 2 + 1]
			):
				errors.append("bank_offsets_ne_m: bank boundary may not intersect shoreline")
				return


static func _polygon_bounds(polygon: PackedFloat64Array) -> PackedFloat64Array:
	var north_min: float = INF
	var north_max: float = -INF
	var east_min: float = INF
	var east_max: float = -INF
	for index: int in range(0, polygon.size(), 2):
		north_min = minf(north_min, polygon[index])
		north_max = maxf(north_max, polygon[index])
		east_min = minf(east_min, polygon[index + 1])
		east_max = maxf(east_max, polygon[index + 1])
	return PackedFloat64Array([north_min, north_max, east_min, east_max])


static func _point_inside(polygon: PackedFloat64Array, north: float, east: float, include_boundary: bool = true) -> bool:
	var inside: bool = false
	var count: int = polygon.size() / 2
	for index: int in range(count):
		var next: int = (index + 1) % count
		var n1: float = polygon[index * 2]
		var e1: float = polygon[index * 2 + 1]
		var n2: float = polygon[next * 2]
		var e2: float = polygon[next * 2 + 1]
		if include_boundary and _point_segment_distance_sq(north, east, n1, e1, n2, e2) <= GEOMETRY_EPSILON_M * GEOMETRY_EPSILON_M:
			return true
		if (n1 > north) != (n2 > north):
			var crossing_east: float = (e2 - e1) * (north - n1) / (n2 - n1) + e1
			if east < crossing_east:
				inside = not inside
	return inside


static func _segments_intersect(an: float, ae: float, bn: float, be: float,
	cn: float, ce: float, dn: float, de: float) -> bool:
	var o1: float = _cross(bn - an, be - ae, cn - an, ce - ae)
	var o2: float = _cross(bn - an, be - ae, dn - an, de - ae)
	var o3: float = _cross(dn - cn, de - ce, an - cn, ae - ce)
	var o4: float = _cross(dn - cn, de - ce, bn - cn, be - ce)
	if ((o1 > GEOMETRY_EPSILON_M and o2 < -GEOMETRY_EPSILON_M) or (o1 < -GEOMETRY_EPSILON_M and o2 > GEOMETRY_EPSILON_M)) \
		and ((o3 > GEOMETRY_EPSILON_M and o4 < -GEOMETRY_EPSILON_M) or (o3 < -GEOMETRY_EPSILON_M and o4 > GEOMETRY_EPSILON_M)):
		return true
	return absf(o1) <= GEOMETRY_EPSILON_M and _on_segment(an, ae, bn, be, cn, ce) \
		or absf(o2) <= GEOMETRY_EPSILON_M and _on_segment(an, ae, bn, be, dn, de) \
		or absf(o3) <= GEOMETRY_EPSILON_M and _on_segment(cn, ce, dn, de, an, ae) \
		or absf(o4) <= GEOMETRY_EPSILON_M and _on_segment(cn, ce, dn, de, bn, be)


static func _on_segment(an: float, ae: float, bn: float, be: float, pn: float, pe: float) -> bool:
	return pn >= minf(an, bn) - GEOMETRY_EPSILON_M and pn <= maxf(an, bn) + GEOMETRY_EPSILON_M \
		and pe >= minf(ae, be) - GEOMETRY_EPSILON_M and pe <= maxf(ae, be) + GEOMETRY_EPSILON_M


static func _point_segment_distance_sq(north: float, east: float,
	an: float, ae: float, bn: float, be: float) -> float:
	var dn: float = bn - an
	var de: float = be - ae
	var length_sq: float = dn * dn + de * de
	if length_sq <= 0.0:
		return _distance_sq(north, east, an, ae)
	var t: float = clampf(((north - an) * dn + (east - ae) * de) / length_sq, 0.0, 1.0)
	return _distance_sq(north, east, an + t * dn, ae + t * de)


static func _distance_sq(n1: float, e1: float, n2: float, e2: float) -> float:
	var dn: float = n1 - n2
	var de: float = e1 - e2
	return dn * dn + de * de


static func _cross(a_n: float, a_e: float, b_n: float, b_e: float) -> float:
	return a_n * b_e - a_e * b_n


static func _read_id(errors: PackedStringArray, value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		errors.append("id: expected a string")
		return ""
	var result: String = value
	if result.is_empty() or result != result.strip_edges() or result.validate_node_name() != result:
		errors.append("id: expected a non-empty Godot node name without surrounding whitespace")
	return result


static func _read_source(errors: PackedStringArray, value: Variant) -> String:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty() or String(value).length() > 256:
		errors.append("source: expected a non-empty note of at most 256 characters")
		return ""
	return String(value).strip_edges()


static func _read_number(errors: PackedStringArray, path: String, value: Variant,
	minimum: float, maximum: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		errors.append(path + ": expected a number")
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		errors.append(path + ": expected a finite number")
		return 0.0
	if number < minimum or number > maximum:
		errors.append("%s: expected a value in [%s, %s]" % [path, minimum, maximum])
	return number


static func _object(errors: PackedStringArray, path: String, value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	errors.append(path + ": expected an object")
	return {}


static func _check_keys(errors: PackedStringArray, path: String, value: Dictionary,
	allowed: Array[String], required: Array[String]) -> void:
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(String(key)):
			errors.append("%s: unknown key '%s'" % [path, key])
	for key: String in required:
		if not value.has(key):
			errors.append("%s: missing required key '%s'" % [path, key])


static func _failure(message: String) -> Dictionary:
	var errors := PackedStringArray([message])
	return {"ok": false, "errors": errors, "lake": {}, "data": {}}
