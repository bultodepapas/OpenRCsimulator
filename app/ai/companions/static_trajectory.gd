## Conservative clearance of an airborne NED polyline against static field context.
## This checks geometry, not whether a controller can fly the proposed trajectory.
extends RefCounted

const Airspace := preload("res://ai/companions/airspace.gd")
const Contacts := preload("res://physics/aircraft_contact_contract.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Lake := preload("res://physics/lake_surface.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const MAX_POINTS := 129
const MAX_COORDINATE_M := 1000000.0
const TERRAIN_CLEARANCE_M := 20.0
const ROUNDING_PADDING_M := 0.000001

var _configured := false
var _geometry: Array[Dictionary] = []
var _query_world: Dictionary = {}
var _protected: Array[Dictionary] = []
var _ground_upper_m := 0.0
var _aircraft_radius_m := 0.0
var _identity := ""

## Configured once from the real session, and rebuilt after any shared-world change.
## A failed configure invalidates assessments, even if previous storage remains.
func configure(field: Dictionary, world: Dictionary, surfaces: PackedFloat64Array,
		lake: Dictionary, model: Dictionary, allow_empty_world: bool = false) -> Dictionary:
	_configured = false
	if world.is_empty() and not allow_empty_world:
		return _refuse("empty_world_requires_explicit_opt_in")
	var pilot: Variant = field.get("pilot")
	if not pilot is Dictionary:
		return _refuse("invalid_pilot_station")
	for key: String in ["north", "east", "down"]:
		if not _number(pilot.get(key)):
			return _refuse("invalid_pilot_station")
	var inventory: Dictionary = Airspace._inventory(world)
	if not inventory.ok:
		return _refuse("invalid_collision_inventory")
	var contact: Dictionary = Contacts.describe(model, false)
	if not contact.ok:
		return _refuse("invalid_aircraft_geometry")
	var radius := 0.0
	for point: Dictionary in contact.hull_probes + contact.support_points:
		radius = maxf(radius, Airspace._length(point.position))
	var disc: Dictionary = contact.rotor_disc
	if not disc.is_empty():
		radius = maxf(radius, Airspace._length(disc.hub) + float(disc.radius))
	if not is_finite(radius) or radius <= 0.0 or radius > 100.0:
		return _refuse("invalid_aircraft_radius")
	var ground := Terrain.max_height(surfaces)
	if not is_finite(ground):
		return _refuse("invalid_terrain")
	if not lake.is_empty():
		if not Lake.is_valid_definition(lake) or LakeLoader.identity(lake) != lake.get("identity", ""):
			return _refuse("invalid_lake")
		ground = maxf(ground, -float(lake.water_level_down_m) + float(lake.wave_bounds.max_amplitude_m))
	var protected: Array[Dictionary] = [{id = "pilot_station", bounds = PackedFloat64Array([
		float(pilot.north), float(pilot.north), float(pilot.east), float(pilot.east), 0.0, 0.0])}]
	for proxy: Dictionary in inventory.geometry:
		if proxy.kind == "person" or (proxy.kind == "building" and
				(str(proxy.part).begins_with("shelter_") or str(proxy.part).begins_with("pavilion_"))):
			protected.append({id = proxy.id, bounds = proxy.bounds.duplicate()})
	_geometry = inventory.geometry.duplicate(true)
	# Rebuild bins from validated/enclosing bounds; never trust caller-supplied
	# bins, which may be stale or incomplete. Reuse the scenery broad phase.
	var bin_proxies: Array[Dictionary] = []
	for proxy: Dictionary in _geometry:
		var bounds: PackedFloat64Array = proxy.bounds
		bin_proxies.append({bounds_north_min = bounds[0], bounds_north_max = bounds[1],
			bounds_east_min = bounds[2], bounds_east_max = bounds[3],
			bounds_down_min = bounds[4], bounds_down_max = bounds[5]})
	_query_world = {proxies = bin_proxies, bins = CollisionWorld._build_bins(bin_proxies)}
	_protected = protected
	_ground_upper_m = ground
	_aircraft_radius_m = radius
	_identity = Airspace._hash({geometry = _geometry, protected = _protected, ground = ground,
		radius = radius, world_identity = world.get("identity", ""), surfaces = surfaces, lake = lake.get("identity", "")})
	_configured = true
	return {ok = true, identity = _identity, proxies = _geometry.size(), protected = protected.size(),
		aircraft_radius_m = radius, ground_upper_m = ground}

## path_error_m MUST bound physical tracking/prediction and interpolation error
## everywhere between points. Passing zero certifies only the supplied polyline.
## AABB inflation encloses the accepted hull/gear/propeller at every attitude;
## it can reject a safe corner passage. It never shrinks occupied bounds.
func assess(points: PackedFloat64Array, path_error_m: float) -> Dictionary:
	if not _configured:
		return _refuse("context_not_configured")
	if points.size() < 6 or points.size() % 3 != 0 or points.size() / 3 > MAX_POINTS \
			or not is_finite(path_error_m) or path_error_m < 0.0 or path_error_m > 10000.0:
		return _refuse("invalid_path_or_error_bound")
	for value: float in points:
		if not is_finite(value) or absf(value) > MAX_COORDINATE_M:
			return _refuse("invalid_path_coordinate")
	var radius := _aircraft_radius_m + path_error_m + ROUNDING_PADDING_M
	var min_height := INF
	var path_bounds := PackedFloat64Array([INF, -INF, INF, -INF, INF, -INF])
	for offset: int in range(0, points.size(), 3):
		min_height = minf(min_height, -points[offset + 2])
		for axis: int in 3:
			path_bounds[2 * axis] = minf(path_bounds[2 * axis], points[offset + axis])
			path_bounds[2 * axis + 1] = maxf(path_bounds[2 * axis + 1], points[offset + axis])
	var terrain_margin := min_height - radius - _ground_upper_m - TERRAIN_CLEARANCE_M
	if terrain_margin <= 0.0:
		return _blocked("terrain_or_water", "", terrain_margin)
	for zone: Dictionary in _protected:
		var bounds := _expanded(zone.bounds, radius + Airspace.EXCLUSION_MARGIN_M, 2)
		if not _overlap(path_bounds, bounds, 2):
			continue
		for offset: int in range(0, points.size() - 3, 3):
			if _segment_hits_box(points, offset, bounds, 2):
				return _blocked("protected_footprint", str(zone.id), terrain_margin)
	var candidates := 0
	var segment_checks := 0
	var padding := radius + Airspace.OBSTACLE_CLEARANCE_M
	var indices: Array[int] = []
	if _query_world.bins.is_empty():
		# The bounded scenery index returns empty on an oversized inventory.
		# All-proxy fallback preserves coverage rather than silently omitting it.
		for index: int in _geometry.size():
			indices.append(index)
	else:
		indices = CollisionWorld._candidate_indices(_query_world,
			path_bounds[0] - padding, path_bounds[1] + padding,
			path_bounds[2] - padding, path_bounds[3] + padding,
			path_bounds[4] - padding, path_bounds[5] + padding)
	for index: int in indices:
		var proxy: Dictionary = _geometry[index]
		# Avoid allocating expanded arrays for the large majority of remote proxies.
		if not _overlap_padded(path_bounds, proxy.bounds, padding):
			continue
		var bounds := _expanded(proxy.bounds, padding, 3)
		candidates += 1
		for offset: int in range(0, points.size() - 3, 3):
			segment_checks += 1
			if _segment_hits_box(points, offset, bounds, 3):
				return _blocked("static_obstacle", str(proxy.id), terrain_margin)
	return {ok = true, clear = true, identity = _identity, terrain_margin_m = terrain_margin,
		indexed_proxies = indices.size(), candidate_proxies = candidates, segment_checks = segment_checks}

static func _expanded(source: PackedFloat64Array, padding: float, dimensions: int) -> PackedFloat64Array:
	var bounds := source.duplicate()
	for axis: int in dimensions:
		bounds[2 * axis] -= padding
		bounds[2 * axis + 1] += padding
	return bounds

static func _overlap(first: PackedFloat64Array, second: PackedFloat64Array, dimensions: int) -> bool:
	for axis: int in dimensions:
		if first[2 * axis] > second[2 * axis + 1] or second[2 * axis] > first[2 * axis + 1]:
			return false
	return true

static func _overlap_padded(path_bounds: PackedFloat64Array, proxy_bounds: PackedFloat64Array, padding: float) -> bool:
	for axis: int in 3:
		if path_bounds[2 * axis] > proxy_bounds[2 * axis + 1] + padding \
				or proxy_bounds[2 * axis] - padding > path_bounds[2 * axis + 1]:
			return false
	return true

## Slab clipping finds crossings between endpoints, including parallel/tangent cases.
static func _segment_hits_box(points: PackedFloat64Array, offset: int, bounds: PackedFloat64Array, dimensions: int) -> bool:
	var entry := 0.0
	var exit_time := 1.0
	for axis: int in dimensions:
		var start := points[offset + axis]
		var change := points[offset + 3 + axis] - start
		if change == 0.0:
			if start < bounds[2 * axis] or start > bounds[2 * axis + 1]:
				return false
			continue
		var first := (bounds[2 * axis] - start) / change
		var second := (bounds[2 * axis + 1] - start) / change
		entry = maxf(entry, minf(first, second))
		exit_time = minf(exit_time, maxf(first, second))
		if entry > exit_time:
			return false
	return true

func _blocked(reason: String, proxy_id: String, terrain_margin: float) -> Dictionary:
	return {ok = true, clear = false, reason = reason, proxy_id = proxy_id,
		identity = _identity, terrain_margin_m = terrain_margin}

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and absf(float(value)) <= MAX_COORDINATE_M

static func _refuse(reason: String) -> Dictionary:
	return {ok = false, clear = false, reason = reason}
