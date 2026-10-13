## Float64 lake terrain and swept point-contact queries.
## All positions use world NED [north, east, down], metres. Renderers negate down for their Y axis.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const SAMPLE_EPSILON_M: float = 0.025
const CONTACT_EPSILON_M: float = 0.0000001
const EDGE_EPSILON_M: float = 0.00000001
const TOI_ITERATIONS: int = 48
const MAX_SWEEP_STEPS: int = 8192
const TAU: float = 6.2831853071795864769
const WAVE_PARAMETER_KEYS: Array[String] = ["amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"]


## Fail-closed wrapper for untrusted dictionaries. Validated callers can use sample_terrain_validated.
static func sample_terrain(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_valid_definition(lake) or not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	return sample_terrain_validated(lake, north, east)


## Returns bounded ground state only inside the bank polygon. `ground_down_m` and both slopes are positive down.
static func sample_terrain_validated(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	var bank: PackedFloat64Array = lake.bank_ne_m
	var inside_bank: bool = _contains(bank, north, east)
	var inside_water: bool = inside_bank and _contains(shoreline, north, east)
	var shore_distance: float = _polygon_boundary_distance(shoreline, north, east)
	var bank_distance: float = _polygon_boundary_distance(bank, north, east)
	var signed_shore_distance: float = shore_distance if inside_water else -shore_distance
	var signed_bank_distance: float = bank_distance if inside_bank else -bank_distance
	var blend_fraction: float = _blend_fraction(lake, north, east)
	var bed_depth: float = _bed_depth_at(lake, north, east)
	var blend_north: float = (_blend_fraction(lake, north + SAMPLE_EPSILON_M, east)
		- _blend_fraction(lake, north - SAMPLE_EPSILON_M, east)) / (2.0 * SAMPLE_EPSILON_M)
	var blend_east: float = (_blend_fraction(lake, north, east + SAMPLE_EPSILON_M)
		- _blend_fraction(lake, north, east - SAMPLE_EPSILON_M)) / (2.0 * SAMPLE_EPSILON_M)
	var depth_north: float = (_bed_depth_at(lake, north + SAMPLE_EPSILON_M, east)
		- _bed_depth_at(lake, north - SAMPLE_EPSILON_M, east)) / (2.0 * SAMPLE_EPSILON_M)
	var depth_east: float = (_bed_depth_at(lake, north, east + SAMPLE_EPSILON_M)
		- _bed_depth_at(lake, north, east - SAMPLE_EPSILON_M)) / (2.0 * SAMPLE_EPSILON_M)
	if not inside_bank:
		return {
			"covered": false,
			"region": "outside",
			"ground_down_m": 0.0,
			"slope_north": 0.0,
			"slope_east": 0.0,
			"blend_fraction": 0.0,
			"blend_slope_north": blend_north,
			"blend_slope_east": blend_east,
			"bed_depth_m": 0.0,
			"bed_depth_slope_north": depth_north,
			"bed_depth_slope_east": depth_east,
			"signed_shore_distance_m": signed_shore_distance,
			"signed_bank_distance_m": signed_bank_distance,
			"water_down_m": float(lake.water_level_down_m),
			"depth_m": 0.0,
		}
	var region: String = "bed" if inside_water else "bank"
	var height_down: float = _terrain_down(lake, north, east)
	var north_slope: float = (_terrain_down(lake, north + SAMPLE_EPSILON_M, east)
		- _terrain_down(lake, north - SAMPLE_EPSILON_M, east)) / (2.0 * SAMPLE_EPSILON_M)
	var east_slope: float = (_terrain_down(lake, north, east + SAMPLE_EPSILON_M)
		- _terrain_down(lake, north, east - SAMPLE_EPSILON_M)) / (2.0 * SAMPLE_EPSILON_M)
	return {
		"covered": true,
		"region": region,
		"ground_down_m": height_down,
		"slope_north": north_slope,
		"slope_east": east_slope,
		"blend_fraction": blend_fraction,
		"blend_slope_north": blend_north,
		"blend_slope_east": blend_east,
		"bed_depth_m": bed_depth,
		"bed_depth_slope_north": depth_north,
		"bed_depth_slope_east": depth_east,
		"signed_shore_distance_m": signed_shore_distance,
		"signed_bank_distance_m": signed_bank_distance,
		"water_down_m": float(lake.water_level_down_m),
		"depth_m": bed_depth,
	}


## Mean water datum shared with the renderer. Waves are an optional deterministic sim-clock displacement.
static func water_mean_down(lake: Dictionary) -> float:
	if not is_valid_definition(lake):
		return NAN
	return float(lake.water_level_down_m)


## Returns NAN for an invalid definition, a point outside the water polygon, or out-of-bound wave settings.
static func water_height_down(lake: Dictionary, north: float, east: float, time_s: float = 0.0,
	waves: Array = []) -> float:
	if not is_valid_definition(lake) or not is_finite(north) or not is_finite(east) or not is_finite(time_s):
		return NAN
	if not _contains(lake.shoreline_ne_m, north, east):
		return NAN
	var normalized: Dictionary = _normalize_waves(lake, waves)
	if not normalized.ok:
		return NAN
	return _water_height_down_validated(lake, north, east, time_s, normalized.components)


## Report the earliest terminal point contact against water or the bounded dry bank.
## Inputs are two PackedFloat64Array NED points [north, east, down], interpolated over the supplied times.
static func sweep_probe(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time_s: float = 0.0, end_time_s: float = 0.0, waves: Array = []) -> Dictionary:
	if not is_valid_definition(lake):
		return _invalid_event("lake: expected validated normalized data")
	if from_ned.size() != 3 or to_ned.size() != 3:
		return _invalid_event("sweep: expected three-component PackedFloat64Array NED points")
	if not _finite3(from_ned) or not _finite3(to_ned) or not is_finite(start_time_s) \
		or not is_finite(end_time_s) or end_time_s < start_time_s:
		return _invalid_event("sweep: points and ordered times must be finite")
	var normalized: Dictionary = _normalize_waves(lake, waves)
	if not normalized.ok:
		return _invalid_event("sweep: wave parameters exceed the lake's validated bounds")
	var north_delta: float = to_ned[0] - from_ned[0]
	var east_delta: float = to_ned[1] - from_ned[1]
	var horizontal_distance: float = M.sqrt_(north_delta * north_delta + east_delta * east_delta)
	if horizontal_distance > 2000.0:
		return _invalid_event("sweep: horizontal segment exceeds the 2000 m bounded query")
	var cuts: Array[float] = [0.0, 1.0]
	_add_polygon_crossings(cuts, lake.bank_ne_m, from_ned[0], from_ned[1], north_delta, east_delta)
	_add_polygon_crossings(cuts, lake.shoreline_ne_m, from_ned[0], from_ned[1], north_delta, east_delta)
	cuts.sort()
	var unique_cuts: Array[float] = []
	for cut: float in cuts:
		if unique_cuts.is_empty() or absf(cut - float(unique_cuts[unique_cuts.size() - 1])) > EDGE_EPSILON_M:
			unique_cuts.append(cut)
	for interval_index: int in range(unique_cuts.size() - 1):
		var interval_start: float = float(unique_cuts[interval_index])
		var interval_end: float = float(unique_cuts[interval_index + 1])
		if interval_end - interval_start <= EDGE_EPSILON_M:
			continue
		var start_north: float = from_ned[0] + north_delta * interval_start
		var start_east: float = from_ned[1] + east_delta * interval_start
		if _contains(lake.bank_ne_m, start_north, start_east):
			var start_material: String = "water" if _contains(lake.shoreline_ne_m, start_north, start_east) else "bank_ground"
			var start_penetration: float = _penetration(lake, from_ned, to_ned, start_time_s,
				end_time_s, interval_start, start_material, normalized.components)
			if start_penetration >= -CONTACT_EPSILON_M:
				return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
					interval_start, start_material, normalized.components, start_penetration)
		var midpoint: float = (interval_start + interval_end) * 0.5
		var midpoint_north: float = from_ned[0] + north_delta * midpoint
		var midpoint_east: float = from_ned[1] + east_delta * midpoint
		if not _contains(lake.bank_ne_m, midpoint_north, midpoint_east):
			var end_north: float = from_ned[0] + north_delta * interval_end
			var end_east: float = from_ned[1] + east_delta * interval_end
			if _contains(lake.bank_ne_m, end_north, end_east):
				var end_material: String = "water" if _contains(lake.shoreline_ne_m, end_north, end_east) else "bank_ground"
				var end_penetration: float = _penetration(lake, from_ned, to_ned, start_time_s,
					end_time_s, interval_end, end_material, normalized.components)
				if end_penetration >= -CONTACT_EPSILON_M:
					return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
						interval_end, end_material, normalized.components, end_penetration)
			continue
		var material: String = "water" if _contains(lake.shoreline_ne_m, midpoint_north, midpoint_east) else "bank_ground"
		var steps: int = _subdivision_count(lake, normalized.components, from_ned, to_ned,
			start_time_s, end_time_s, interval_start, interval_end, material)
		if steps > MAX_SWEEP_STEPS:
			return _invalid_event("sweep: requested wave and path resolution exceeds the bounded query budget")
		var previous_fraction: float = interval_start
		var previous_penetration: float = _penetration(lake, from_ned, to_ned, start_time_s, end_time_s,
			previous_fraction, material, normalized.components)
		if previous_penetration >= -CONTACT_EPSILON_M:
			return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
				previous_fraction, material, normalized.components, previous_penetration)
		for step_index: int in range(1, steps + 1):
			var fraction: float = lerpf(interval_start, interval_end, float(step_index) / float(steps))
			var penetration: float = _penetration(lake, from_ned, to_ned, start_time_s, end_time_s,
				fraction, material, normalized.components)
			if penetration >= -CONTACT_EPSILON_M:
				var contact_fraction: float = _bisect_contact(lake, from_ned, to_ned, start_time_s,
					end_time_s, previous_fraction, fraction, material, normalized.components)
				var event_penetration: float = _penetration(lake, from_ned, to_ned,
					start_time_s, end_time_s, contact_fraction, material, normalized.components)
				return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
					contact_fraction, material, normalized.components, event_penetration)
			previous_fraction = fraction
			previous_penetration = penetration
	return _miss_event()


## Cheap structural guard for normalized data; loaders own exhaustive polygon/profile validation.
static func is_valid_definition(lake: Dictionary) -> bool:
	if lake.get("format") != "openrc-lake v1" or typeof(lake.get("id")) != TYPE_STRING \
		or typeof(lake.get("identity")) != TYPE_STRING or String(lake.identity).is_empty():
		return false
	if typeof(lake.get("water_level_down_m")) != TYPE_FLOAT and typeof(lake.get("water_level_down_m")) != TYPE_INT:
		return false
	if not is_finite(float(lake.water_level_down_m)) or float(lake.water_level_down_m) < 0.05 \
		or float(lake.water_level_down_m) > 2.0 or String(lake.id).is_empty():
		return false
	var shoreline: Variant = lake.get("shoreline_ne_m")
	var bank: Variant = lake.get("bank_ne_m")
	var profile: Variant = lake.get("bed_profile")
	var bounds: Variant = lake.get("wave_bounds")
	var waves: Variant = lake.get("waves")
	if typeof(shoreline) != TYPE_PACKED_FLOAT64_ARRAY or typeof(bank) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(profile) != TYPE_ARRAY or typeof(waves) != TYPE_ARRAY or typeof(bounds) != TYPE_DICTIONARY:
		return false
	if shoreline.size() < 16 or shoreline.size() % 2 != 0 or bank.size() < 16 or bank.size() % 2 != 0 \
		or profile.size() < 2 or profile.size() > 8 or waves.size() > 2:
		return false
	for coordinate: float in shoreline:
		if not is_finite(coordinate):
			return false
	for coordinate: float in bank:
		if not is_finite(coordinate):
			return false
	for row_value: Variant in profile:
		if typeof(row_value) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = row_value
		if not _finite_number(row.get("inset_m")) or not _finite_number(row.get("depth_m")):
			return false
	for index: int in range(1, profile.size()):
		var previous: Dictionary = profile[index - 1]
		var current: Dictionary = profile[index]
		if float(current.inset_m) <= float(previous.inset_m) or float(current.depth_m) <= float(previous.depth_m):
			return false
	var first_profile_point: Dictionary = profile[0]
	if absf(float(first_profile_point.inset_m)) > CONTACT_EPSILON_M \
		or absf(float(first_profile_point.depth_m)) > CONTACT_EPSILON_M:
		return false
	for key: String in ["max_amplitude_m", "min_wavelength_m", "max_wavelength_m", "min_period_s", "max_period_s", "shore_fade_m"]:
		if not _finite_number(bounds.get(key)):
			return false
	if float(bounds.max_amplitude_m) < 0.0 or float(bounds.min_wavelength_m) <= 0.0 \
		or float(bounds.max_wavelength_m) < float(bounds.min_wavelength_m) \
		or float(bounds.min_period_s) <= 0.0 or float(bounds.max_period_s) < float(bounds.min_period_s) \
		or float(bounds.shore_fade_m) <= 0.0:
		return false
	for wave_value: Variant in waves:
		if typeof(wave_value) != TYPE_DICTIONARY:
			return false
		var wave: Dictionary = wave_value
		for key: String in WAVE_PARAMETER_KEYS:
			if not _finite_number(wave.get(key)):
				return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _terrain_down(lake: Dictionary, north: float, east: float) -> float:
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	if _contains(shoreline, north, east):
		return float(lake.water_level_down_m) + _bed_depth_at(lake, north, east)
	return float(lake.water_level_down_m) * _blend_fraction(lake, north, east)


static func _blend_fraction(lake: Dictionary, north: float, east: float) -> float:
	if _contains(lake.shoreline_ne_m, north, east):
		return 1.0
	if not _contains(lake.bank_ne_m, north, east):
		return 0.0
	var shore_distance: float = _polygon_boundary_distance(lake.shoreline_ne_m, north, east)
	var bank_distance: float = _polygon_boundary_distance(lake.bank_ne_m, north, east)
	var span: float = shore_distance + bank_distance
	if span <= 0.0:
		return 1.0
	return _smoothstep(bank_distance / span)


static func _bed_depth_at(lake: Dictionary, north: float, east: float) -> float:
	if not _contains(lake.shoreline_ne_m, north, east):
		return 0.0
	var inset: float = _polygon_boundary_distance(lake.shoreline_ne_m, north, east)
	return _bed_depth(lake.bed_profile, inset)


static func _bed_depth(profile: Array, inset: float) -> float:
	if profile.is_empty():
		return NAN
	for index: int in range(profile.size() - 1):
		var first: Dictionary = profile[index]
		var second: Dictionary = profile[index + 1]
		var first_inset: float = float(first.inset_m)
		var second_inset: float = float(second.inset_m)
		if inset <= second_inset:
			var t: float = clampf((inset - first_inset) / (second_inset - first_inset), 0.0, 1.0)
			return lerpf(float(first.depth_m), float(second.depth_m), _smoothstep(t))
	return float(profile[profile.size() - 1].depth_m)


static func _water_height_down_validated(lake: Dictionary, north: float, east: float, time_s: float,
	waves: Array) -> float:
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	var shore_distance: float = maxf(0.0, _signed_polygon_distance(shoreline, north, east))
	var fade: float = _smoothstep(shore_distance / float(lake.wave_bounds.shore_fade_m))
	var displacement_up: float = 0.0
	for wave: Dictionary in waves:
		var heading: float = float(wave.heading_rad)
		var direction_north: float = M.cos_(heading)
		var direction_east: float = M.sin_(heading)
		var phase: float = TAU * (direction_north * north + direction_east * east) / float(wave.wavelength_m) \
			- TAU * time_s / float(wave.period_s) + float(wave.phase_rad)
		displacement_up += float(wave.amplitude_m) * fade * M.sin_(phase)
	return float(lake.water_level_down_m) - displacement_up


static func _normalize_waves(lake: Dictionary, waves: Array) -> Dictionary:
	var requested: Array = waves
	if requested.is_empty():
		requested = lake.get("waves", [])
	if requested.size() > 2:
		return {"ok": false}
	var bounds: Dictionary = lake.wave_bounds
	var components: Array[Dictionary] = []
	var total_amplitude: float = 0.0
	for component_value: Variant in requested:
		if typeof(component_value) != TYPE_DICTIONARY:
			return {"ok": false}
		var component: Dictionary = component_value
		for key: Variant in component.keys():
			if typeof(key) != TYPE_STRING or not WAVE_PARAMETER_KEYS.has(String(key)):
				return {"ok": false}
		for key: String in WAVE_PARAMETER_KEYS:
			if not component.has(key):
				return {"ok": false}
		var amplitude: float = _wave_number(component, "amplitude_m")
		var wavelength: float = _wave_number(component, "wavelength_m")
		var period: float = _wave_number(component, "period_s")
		var heading: float = _wave_number(component, "heading_rad")
		var phase: float = _wave_number(component, "phase_rad")
		if not is_finite(amplitude) or amplitude < 0.0 \
			or not is_finite(wavelength) or wavelength < float(bounds.min_wavelength_m) \
			or wavelength > float(bounds.max_wavelength_m) or not is_finite(period) \
			or period < float(bounds.min_period_s) or period > float(bounds.max_period_s) \
			or not is_finite(heading) or absf(heading) > TAU * 100.0 \
			or not is_finite(phase) or absf(phase) > 1000000.0:
			return {"ok": false}
		total_amplitude += amplitude
		components.append({
			"amplitude_m": amplitude,
			"wavelength_m": wavelength,
			"period_s": period,
			"heading_rad": heading,
			"phase_rad": phase,
		})
	if total_amplitude > float(bounds.max_amplitude_m) + CONTACT_EPSILON_M:
		return {"ok": false}
	return {"ok": true, "components": components}


static func _wave_number(wave: Dictionary, key: String) -> float:
	var value: Variant = wave.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value)


static func _subdivision_count(lake: Dictionary, waves: Array, from_ned: PackedFloat64Array,
	to_ned: PackedFloat64Array, start_time: float, end_time: float, start_fraction: float,
	end_fraction: float, material: String) -> int:
	var fraction_span: float = end_fraction - start_fraction
	var north_delta: float = (to_ned[0] - from_ned[0]) * fraction_span
	var east_delta: float = (to_ned[1] - from_ned[1]) * fraction_span
	var horizontal: float = M.sqrt_(north_delta * north_delta + east_delta * east_delta)
	var steps: int = maxi(1, ceili(horizontal / 0.25))
	if material == "water" and _total_wave_amplitude(waves) > 0.0:
		var duration: float = (end_time - start_time) * fraction_span
		for wave: Dictionary in waves:
			steps = maxi(steps, ceili(horizontal / (float(wave.wavelength_m) / 8.0)))
			steps = maxi(steps, ceili(duration / (float(wave.period_s) / 8.0)))
	return steps


static func _total_wave_amplitude(waves: Array) -> float:
	var total: float = 0.0
	for wave: Dictionary in waves:
		total += float(wave.amplitude_m)
	return total


static func _penetration(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, fraction: float, material: String, waves: Array) -> float:
	var north: float = lerpf(from_ned[0], to_ned[0], fraction)
	var east: float = lerpf(from_ned[1], to_ned[1], fraction)
	var down: float = lerpf(from_ned[2], to_ned[2], fraction)
	var boundary_down: float = _terrain_down(lake, north, east)
	if material == "water":
		var time_s: float = lerpf(start_time, end_time, fraction)
		boundary_down = _water_height_down_validated(lake, north, east, time_s, waves)
	return down - boundary_down


static func _bisect_contact(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, outside_fraction: float, inside_fraction: float,
	material: String, waves: Array) -> float:
	var low: float = outside_fraction
	var high: float = inside_fraction
	for _iteration: int in range(TOI_ITERATIONS):
		var midpoint: float = (low + high) * 0.5
		var penetration: float = _penetration(lake, from_ned, to_ned, start_time, end_time,
			midpoint, material, waves)
		if penetration >= 0.0:
			high = midpoint
		else:
			low = midpoint
	return high


static func _event_at(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, fraction: float, material: String, waves: Array,
	penetration: float) -> Dictionary:
	return {
		"ok": true,
		"hit": true,
		"fraction": fraction,
		"time_s": lerpf(start_time, end_time, fraction),
		"north_m": lerpf(from_ned[0], to_ned[0], fraction),
		"east_m": lerpf(from_ned[1], to_ned[1], fraction),
		"down_m": lerpf(from_ned[2], to_ned[2], fraction),
		"surface_down_m": _water_height_down_validated(lake,
			lerpf(from_ned[0], to_ned[0], fraction), lerpf(from_ned[1], to_ned[1], fraction),
			lerpf(start_time, end_time, fraction), waves) if material == "water" else _terrain_down(lake,
			lerpf(from_ned[0], to_ned[0], fraction), lerpf(from_ned[1], to_ned[1], fraction)),
		"penetration_m": penetration,
		"material": material,
	}


static func _add_polygon_crossings(cuts: Array[float], polygon: PackedFloat64Array,
	start_north: float, start_east: float, delta_north: float, delta_east: float) -> void:
	if delta_north * delta_north + delta_east * delta_east <= EDGE_EPSILON_M * EDGE_EPSILON_M:
		return
	var count: int = polygon.size() / 2
	for index: int in range(count):
		var next: int = (index + 1) % count
		var edge_north: float = polygon[next * 2] - polygon[index * 2]
		var edge_east: float = polygon[next * 2 + 1] - polygon[index * 2 + 1]
		var offset_north: float = polygon[index * 2] - start_north
		var offset_east: float = polygon[index * 2 + 1] - start_east
		var denominator: float = _cross(delta_north, delta_east, edge_north, edge_east)
		if absf(denominator) <= EDGE_EPSILON_M:
			continue
		var fraction: float = _cross(offset_north, offset_east, edge_north, edge_east) / denominator
		var edge_fraction: float = _cross(offset_north, offset_east, delta_north, delta_east) / denominator
		if fraction > EDGE_EPSILON_M and fraction < 1.0 - EDGE_EPSILON_M \
			and edge_fraction >= -EDGE_EPSILON_M and edge_fraction <= 1.0 + EDGE_EPSILON_M:
			cuts.append(fraction)


static func _contains(polygon: PackedFloat64Array, north: float, east: float) -> bool:
	var inside: bool = false
	var count: int = polygon.size() / 2
	for index: int in range(count):
		var next: int = (index + 1) % count
		var n1: float = polygon[index * 2]
		var e1: float = polygon[index * 2 + 1]
		var n2: float = polygon[next * 2]
		var e2: float = polygon[next * 2 + 1]
		if _point_segment_distance_sq(north, east, n1, e1, n2, e2) <= EDGE_EPSILON_M * EDGE_EPSILON_M:
			return true
		if (n1 > north) != (n2 > north):
			var crossing_east: float = (e2 - e1) * (north - n1) / (n2 - n1) + e1
			if east < crossing_east:
				inside = not inside
	return inside


static func _polygon_boundary_distance(polygon: PackedFloat64Array, north: float, east: float) -> float:
	var minimum_sq: float = INF
	var count: int = polygon.size() / 2
	for index: int in range(count):
		var next: int = (index + 1) % count
		minimum_sq = minf(minimum_sq, _point_segment_distance_sq(north, east,
			polygon[index * 2], polygon[index * 2 + 1], polygon[next * 2], polygon[next * 2 + 1]))
	return M.sqrt_(minimum_sq)


static func _signed_polygon_distance(polygon: PackedFloat64Array, north: float, east: float) -> float:
	var distance: float = _polygon_boundary_distance(polygon, north, east)
	return distance if _contains(polygon, north, east) else -distance


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


static func _smoothstep(t_value: float) -> float:
	var t: float = clampf(t_value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _finite3(value: PackedFloat64Array) -> bool:
	return is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])


static func _invalid_sample() -> Dictionary:
	return {
		"covered": false,
		"region": "invalid",
		"ground_down_m": NAN,
		"slope_north": NAN,
		"slope_east": NAN,
		"blend_fraction": NAN,
		"blend_slope_north": NAN,
		"blend_slope_east": NAN,
		"bed_depth_m": NAN,
		"bed_depth_slope_north": NAN,
		"bed_depth_slope_east": NAN,
		"signed_shore_distance_m": NAN,
		"signed_bank_distance_m": NAN,
		"water_down_m": NAN,
		"depth_m": NAN,
	}


static func _miss_event() -> Dictionary:
	return {"ok": true, "hit": false, "fraction": INF, "time_s": INF, "material": ""}


static func _invalid_event(message: String) -> Dictionary:
	return {"ok": false, "hit": false, "fraction": INF, "time_s": INF, "material": "", "error": message}
