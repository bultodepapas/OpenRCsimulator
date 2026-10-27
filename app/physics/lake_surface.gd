## Float64 lake terrain and swept point-contact queries.
## All positions use world NED [north, east, down], metres. Renderers negate down for their Y axis.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const SAMPLE_EPSILON_M: float = 0.025
const CONTACT_EPSILON_M: float = 0.0000001
const EDGE_EPSILON_M: float = 0.00000001
const TOI_ITERATIONS: int = 48 # Upper bound; ordinary contacts select only the iterations their path needs.
const LOG_TWO: float = 0.6931471805599453
const MAX_SWEEP_STEPS: int = 8192
const TAU: float = 6.2831853071795864769
const WAVE_PARAMETER_KEYS: Array[String] = ["amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"]


## Fail-closed wrapper for untrusted dictionaries. Validated callers can use sample_terrain_validated.
static func sample_terrain(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_valid_definition(lake) or not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	return sample_terrain_validated(lake, north, east)


## Signed nearest-shore distance in metres; positive is inside the water polygon.
## This geometry-only query is intended for render mesh attributes that do not need terrain state.
static func shore_distance_validated(lake: Dictionary, north: float, east: float) -> float:
	if not is_finite(north) or not is_finite(east) \
			or typeof(lake.get("shoreline_ne_m")) != TYPE_PACKED_FLOAT64_ARRAY:
		return NAN
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	if shoreline.size() < 6 or shoreline.size() % 2 != 0:
		return NAN
	return _signed_polygon_distance(shoreline, north, east)


## Contact-only query for validated definitions. Outside the bank, callers receive only covered=false;
## they must not use this route for distances or finite-difference diagnostics outside coverage.
## Keep a full stencil margin so boundary tolerance and near-bank samples use the original sampler.
static func sample_covered_terrain_validated(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	if _outside_expanded_polygon_aabb(lake.bank_ne_m, north, east, SAMPLE_EPSILON_M):
		return {covered = false}
	return sample_terrain_validated(lake, north, east)


## Returns bounded ground state only inside the bank polygon. `ground_down_m` and both slopes are positive down.
static func sample_terrain_validated(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	# Keep the four finite-difference neighbors, but resolve each point's shoreline/bank distances once.
	# The older nested helpers repeated the same polygon scans for contains, blend, depth and height.
	var center: PackedFloat64Array = _terrain_point_state(lake, north, east)
	var inside_bank: bool = center[1] > 0.5
	var inside_water: bool = center[0] > 0.5
	var signed_shore_distance: float = center[2] if inside_water else -center[2]
	var signed_bank_distance: float = center[3] if inside_bank else -center[3]
	# Distance to a polygon boundary is 1-Lipschitz. Beyond the last bed
	# profile inset plus the stencil radius, all four neighbors stay inside
	# the bank and on the same constant-depth bed. Their finite differences
	# are exactly zero, so avoid four more polygon scans per contact query.
	if inside_water and center[2] > float(lake.bed_profile.back().inset_m) + SAMPLE_EPSILON_M \
			and center[3] > SAMPLE_EPSILON_M:
		return {
			"covered": true,
			"region": "bed",
			"ground_down_m": center[6],
			"slope_north": 0.0,
			"slope_east": 0.0,
			"blend_fraction": center[4],
			"blend_slope_north": 0.0,
			"blend_slope_east": 0.0,
			"bed_depth_m": center[5],
			"bed_depth_slope_north": 0.0,
			"bed_depth_slope_east": 0.0,
			"signed_shore_distance_m": signed_shore_distance,
			"signed_bank_distance_m": signed_bank_distance,
			"water_down_m": float(lake.water_level_down_m),
			"depth_m": center[5],
		}
	if not inside_bank and _outside_expanded_polygon_aabb(lake.bank_ne_m, north, east, SAMPLE_EPSILON_M):
		return {
			"covered": false,
			"region": "outside",
			"ground_down_m": 0.0,
			"slope_north": 0.0,
			"slope_east": 0.0,
			"blend_fraction": 0.0,
			"blend_slope_north": 0.0,
			"blend_slope_east": 0.0,
			"bed_depth_m": 0.0,
			"bed_depth_slope_north": 0.0,
			"bed_depth_slope_east": 0.0,
			"signed_shore_distance_m": signed_shore_distance,
			"signed_bank_distance_m": signed_bank_distance,
			"water_down_m": float(lake.water_level_down_m),
			"depth_m": 0.0,
		}
	var north_plus: PackedFloat64Array = _terrain_point_state(lake, north + SAMPLE_EPSILON_M, east)
	var north_minus: PackedFloat64Array = _terrain_point_state(lake, north - SAMPLE_EPSILON_M, east)
	var east_plus: PackedFloat64Array = _terrain_point_state(lake, north, east + SAMPLE_EPSILON_M)
	var east_minus: PackedFloat64Array = _terrain_point_state(lake, north, east - SAMPLE_EPSILON_M)
	var blend_fraction: float = center[4]
	var bed_depth: float = center[5]
	var blend_north: float = (north_plus[4] - north_minus[4]) / (2.0 * SAMPLE_EPSILON_M)
	var blend_east: float = (east_plus[4] - east_minus[4]) / (2.0 * SAMPLE_EPSILON_M)
	var depth_north: float = (north_plus[5] - north_minus[5]) / (2.0 * SAMPLE_EPSILON_M)
	var depth_east: float = (east_plus[5] - east_minus[5]) / (2.0 * SAMPLE_EPSILON_M)
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
	var height_down: float = center[6]
	var north_slope: float = (north_plus[6] - north_minus[6]) / (2.0 * SAMPLE_EPSILON_M)
	var east_slope: float = (east_plus[6] - east_minus[6]) / (2.0 * SAMPLE_EPSILON_M)
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
	# Bank terrain is between down=0 and the mean water datum. Water can rise by no more
	# than its validated summed amplitude, so this envelope safely rejects an airborne chord
	# before shoreline and bank polygon scans. Equality stays on the full path for grazing.
	var highest_possible_down: float = minf(0.0,
		float(lake.water_level_down_m) - float(lake.wave_bounds.max_amplitude_m))
	if maxf(from_ned[2], to_ned[2]) < highest_possible_down - CONTACT_EPSILON_M:
		return _miss_event()
	var north_delta: float = to_ned[0] - from_ned[0]
	var east_delta: float = to_ned[1] - from_ned[1]
	var horizontal_distance: float = sqrt(north_delta * north_delta + east_delta * east_delta)
	if horizontal_distance > 2000.0:
		return _invalid_event("sweep: horizontal segment exceeds the 2000 m bounded query")
	var shore_fade_override: float = -1.0
	var fade_distance: float = float(lake.wave_bounds.shore_fade_m) + SAMPLE_EPSILON_M
	var shore_start: float = _signed_polygon_distance(lake.shoreline_ne_m, from_ned[0], from_ned[1])
	var shore_end: float = _signed_polygon_distance(lake.shoreline_ne_m, to_ned[0], to_ned[1])
	if shore_start >= horizontal_distance + fade_distance \
		and shore_end >= horizontal_distance + fade_distance:
		# Distance to the shoreline is 1-Lipschitz, so the entire straight path and the contact
		# normal's 2.5 cm finite-difference stencil stay past the wave fade radius.
		shore_fade_override = 1.0
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
				end_time_s, interval_start, start_material, normalized.components, shore_fade_override)
			if start_penetration >= -CONTACT_EPSILON_M:
				return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
					interval_start, start_material, normalized.components, start_penetration, shore_fade_override)
		var midpoint: float = (interval_start + interval_end) * 0.5
		var midpoint_north: float = from_ned[0] + north_delta * midpoint
		var midpoint_east: float = from_ned[1] + east_delta * midpoint
		if not _contains(lake.bank_ne_m, midpoint_north, midpoint_east):
			var end_north: float = from_ned[0] + north_delta * interval_end
			var end_east: float = from_ned[1] + east_delta * interval_end
			if _contains(lake.bank_ne_m, end_north, end_east):
				var end_material: String = "water" if _contains(lake.shoreline_ne_m, end_north, end_east) else "bank_ground"
				var end_penetration: float = _penetration(lake, from_ned, to_ned, start_time_s,
					end_time_s, interval_end, end_material, normalized.components, shore_fade_override)
				if end_penetration >= -CONTACT_EPSILON_M:
					return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
						interval_end, end_material, normalized.components, end_penetration, shore_fade_override)
			continue
		var material: String = "water" if _contains(lake.shoreline_ne_m, midpoint_north, midpoint_east) else "bank_ground"
		var steps: int = _subdivision_count(lake, normalized.components, from_ned, to_ned,
			start_time_s, end_time_s, interval_start, interval_end, material)
		if steps > MAX_SWEEP_STEPS:
			return _invalid_event("sweep: requested wave and path resolution exceeds the bounded query budget")
		var previous_fraction: float = interval_start
		var previous_penetration: float = _penetration(lake, from_ned, to_ned, start_time_s, end_time_s,
			previous_fraction, material, normalized.components, shore_fade_override)
		if previous_penetration >= -CONTACT_EPSILON_M:
			return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
				previous_fraction, material, normalized.components, previous_penetration, shore_fade_override)
		for step_index: int in range(1, steps + 1):
			var fraction: float = lerpf(interval_start, interval_end, float(step_index) / float(steps))
			var penetration: float = _penetration(lake, from_ned, to_ned, start_time_s, end_time_s,
				fraction, material, normalized.components, shore_fade_override)
			if penetration >= -CONTACT_EPSILON_M:
				var contact_fraction: float = _bisect_contact(lake, from_ned, to_ned, start_time_s,
					end_time_s, previous_fraction, fraction, material, normalized.components, shore_fade_override)
				var event_penetration: float = _penetration(lake, from_ned, to_ned,
					start_time_s, end_time_s, contact_fraction, material, normalized.components, shore_fade_override)
				return _event_at(lake, from_ned, to_ned, start_time_s, end_time_s,
					contact_fraction, material, normalized.components, event_penetration, shore_fade_override)
			previous_fraction = fraction
			previous_penetration = penetration
	return _miss_event()


# LU-25-R1: one detached, bounded successful definition. Never trust the identity
# string alone: callers may edit nested fields without changing that label.
static var _definition_cache: Dictionary = {}
static var _definition_cache_mutex := Mutex.new()


## Repeated queries compare the complete value, including Variant types, against
## the last successful guard. Mutation (including nested arrays) takes the original
## validation path. The cached copy is private and never returned to callers.
static func is_valid_definition(lake: Dictionary) -> bool:
	_definition_cache_mutex.lock()
	var cached: Dictionary = _definition_cache
	_definition_cache_mutex.unlock()
	if not cached.is_empty() and lake == cached:
		return true
	if not _definition_is_valid_uncached(lake):
		return false
	# Unusual/large metadata remains accepted by the existing guard, without
	# retaining objects, recursively copying cycles or growing the cache unbounded.
	var budget: Array[int] = [512]
	if _definition_cacheable(lake, 0, budget):
		var detached: Dictionary = lake.duplicate(true)
		_definition_cache_mutex.lock()
		_definition_cache = detached
		_definition_cache_mutex.unlock()
	return true


## Only cache a bounded plain-data tree. This is a retention policy, not validation.
static func _definition_cacheable(value: Variant, depth: int, budget: Array[int]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 4:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return true
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= 1024
		TYPE_PACKED_FLOAT64_ARRAY:
			budget[0] -= value.size()
			return budget[0] >= 0
		TYPE_ARRAY:
			if value.size() > budget[0]: return false
			for item: Variant in value:
				if not _definition_cacheable(item, depth + 1, budget): return false
			return true
		TYPE_DICTIONARY:
			if value.size() * 2 > budget[0]: return false
			for key: Variant in value:
				if not _definition_cacheable(key, depth + 1, budget) \
						or not _definition_cacheable(value[key], depth + 1, budget): return false
			return true
	return false


## Original structural guard; loaders still own exhaustive polygon/profile validation.
static func _definition_is_valid_uncached(lake: Dictionary) -> bool:
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


## Returns [in_water, in_bank, shore_distance, bank_distance, blend, depth, ground_down].
## Packed scalar output avoids temporary dictionaries in this five-point terrain stencil.
static func _terrain_point_state(lake: Dictionary, north: float, east: float) -> PackedFloat64Array:
	var shore_signed: float = _polygon_state(lake.shoreline_ne_m, north, east)
	var bank_signed: float = _polygon_state(lake.bank_ne_m, north, east)
	var shore_distance: float = absf(shore_signed)
	var bank_distance: float = absf(bank_signed)
	var inside_shoreline: bool = shore_signed >= 0.0
	var inside_bank: bool = bank_signed >= 0.0
	var inside_water: bool = inside_bank and inside_shoreline
	var blend: float = 1.0
	if not inside_shoreline:
		if not inside_bank:
			blend = 0.0
		else:
			var span: float = shore_distance + bank_distance
			blend = 1.0 if span <= 0.0 else _smoothstep(bank_distance / span)
	var depth: float = _bed_depth(lake.bed_profile, shore_distance) if inside_shoreline else 0.0
	var ground_down: float = float(lake.water_level_down_m) + depth if inside_shoreline \
		else float(lake.water_level_down_m) * blend
	return PackedFloat64Array([1.0 if inside_water else 0.0, 1.0 if inside_bank else 0.0,
		shore_distance, bank_distance, blend, depth, ground_down])


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
	waves: Array, shore_fade_override: float = -1.0) -> float:
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	var fade: float = shore_fade_override
	if fade < 0.0:
		var shore_distance: float = maxf(0.0, _signed_polygon_distance(shoreline, north, east))
		fade = _smoothstep(shore_distance / float(lake.wave_bounds.shore_fade_m))
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
	var horizontal: float = sqrt(north_delta * north_delta + east_delta * east_delta)
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
	start_time: float, end_time: float, fraction: float, material: String, waves: Array,
	shore_fade_override: float = -1.0) -> float:
	var north: float = lerpf(from_ned[0], to_ned[0], fraction)
	var east: float = lerpf(from_ned[1], to_ned[1], fraction)
	var down: float = lerpf(from_ned[2], to_ned[2], fraction)
	var boundary_down: float
	if material == "water":
		var time_s: float = lerpf(start_time, end_time, fraction)
		boundary_down = _water_height_down_validated(lake, north, east, time_s, waves, shore_fade_override)
	else:
		boundary_down = _terrain_down(lake, north, east)
	return down - boundary_down


static func _bisect_contact(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, outside_fraction: float, inside_fraction: float,
	material: String, waves: Array, shore_fade_override: float = -1.0) -> float:
	var low: float = outside_fraction
	var high: float = inside_fraction
	var iterations: int = _bisection_iterations(lake, from_ned, to_ned, start_time, end_time,
		low, high, material, waves)
	for _iteration: int in range(iterations):
		var midpoint: float = (low + high) * 0.5
		var penetration: float = _penetration(lake, from_ned, to_ned, start_time, end_time,
			midpoint, material, waves, shore_fade_override)
		if penetration >= 0.0:
			high = midpoint
		else:
			low = midpoint
	return high


static func _bisection_iterations(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
		start_time: float, end_time: float, low: float, high: float, material: String, waves: Array) -> int:
	var fraction_span: float = high - low
	var north_span: float = absf(to_ned[0] - from_ned[0]) * fraction_span
	var east_span: float = absf(to_ned[1] - from_ned[1]) * fraction_span
	var horizontal_span: float = sqrt(north_span * north_span + east_span * east_span)
	var residual_span: float = absf(to_ned[2] - from_ned[2]) * fraction_span + 2.0 * horizontal_span
	if material == "water":
		var duration_span: float = absf(end_time - start_time) * fraction_span
		for wave: Dictionary in waves:
			var amplitude: float = float(wave.amplitude_m)
			residual_span += amplitude * TAU * (horizontal_span / float(wave.wavelength_m)
				+ duration_span / float(wave.period_s)) + amplitude * horizontal_span
	if not is_finite(residual_span):
		return TOI_ITERATIONS
	var ratio: float = maxf(1.0, residual_span / CONTACT_EPSILON_M)
	return clampi(ceili(M.log_(ratio) / LOG_TWO), 1, TOI_ITERATIONS)


static func _event_at(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, fraction: float, material: String, waves: Array,
	penetration: float, shore_fade_override: float = -1.0) -> Dictionary:
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
			lerpf(start_time, end_time, fraction), waves, shore_fade_override) if material == "water" else _terrain_down(lake,
			lerpf(from_ned[0], to_ned[0], fraction), lerpf(from_ned[1], to_ned[1], fraction)),
		"shore_fade_override": shore_fade_override,
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
	return sqrt(minimum_sq)


static func _signed_polygon_distance(polygon: PackedFloat64Array, north: float, east: float) -> float:
	return _polygon_state(polygon, north, east)


## Combines point-in-polygon and nearest-boundary distance in one edge walk.
static func _polygon_state(polygon: PackedFloat64Array, north: float, east: float) -> float:
	# LU-25-R3: every terrain stencil point walks both polygons, and a GDScript call per
	# edge cost more than its arithmetic. The edge distance is _point_segment_distance_sq
	# inlined with identical operations; keep the two in step.
	var inside: bool = false
	var on_boundary: bool = false
	var minimum_sq: float = INF
	var count: int = polygon.size() / 2
	for index: int in range(count):
		var next: int = index + 1 if index + 1 < count else 0
		var n1: float = polygon[index * 2]
		var e1: float = polygon[index * 2 + 1]
		var n2: float = polygon[next * 2]
		var e2: float = polygon[next * 2 + 1]
		var dn: float = n2 - n1
		var de: float = e2 - e1
		var length_sq: float = dn * dn + de * de
		var distance_sq: float
		if length_sq <= 0.0:
			distance_sq = (north - n1) * (north - n1) + (east - e1) * (east - e1)
		else:
			var t: float = clampf(((north - n1) * dn + (east - e1) * de) / length_sq, 0.0, 1.0)
			var gap_north: float = north - (n1 + t * dn)
			var gap_east: float = east - (e1 + t * de)
			distance_sq = gap_north * gap_north + gap_east * gap_east
		minimum_sq = minf(minimum_sq, distance_sq)
		if distance_sq <= EDGE_EPSILON_M * EDGE_EPSILON_M:
			on_boundary = true
		if (n1 > north) != (n2 > north):
			var crossing_east: float = (e2 - e1) * (north - n1) / (n2 - n1) + e1
			if east < crossing_east:
				inside = not inside
	var distance: float = sqrt(minimum_sq)
	return distance if on_boundary or inside else -distance


## LU-25-R7: bounds of the last polygon seen, keyed by a detached copy compared by value. Only an equal polygon
## reuses them; a ±0 vertex difference cannot change a comparison against a bound ± margin.
static var _aabb_polygon := PackedFloat64Array()
static var _aabb := PackedFloat64Array([INF, -INF, INF, -INF])
static var _aabb_mutex := Mutex.new()


static func _outside_expanded_polygon_aabb(polygon: PackedFloat64Array, north: float, east: float,
		margin: float) -> bool:
	_aabb_mutex.lock()
	var cached_polygon: PackedFloat64Array = _aabb_polygon
	var bounds: PackedFloat64Array = _aabb
	_aabb_mutex.unlock()
	if polygon != cached_polygon:
		bounds = _polygon_aabb(polygon)
		var detached: PackedFloat64Array = polygon.duplicate()
		_aabb_mutex.lock()
		_aabb_polygon = detached
		_aabb = bounds
		_aabb_mutex.unlock()
	return north < bounds[0] - margin or north > bounds[1] + margin \
		or east < bounds[2] - margin or east > bounds[3] + margin


static func _polygon_aabb(polygon: PackedFloat64Array) -> PackedFloat64Array:
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
