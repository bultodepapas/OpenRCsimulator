## CR-AUD-14: the shared scenery collision world as ground-vehicle wall boxes. The car dynamics (GDScript and native)
## collide hull probes with axis-aligned boxes only (VehicleDynamics._validated_walls, at most
## MAX_WALL_CONTACT_BOXES per road sample), so each admitted obstacle is converted once, when the course is built:
## - a box whose own bounding box overreaches its true footprint by at most OVERREACH_M keeps that one box;
## - any other box (rotated) is replaced by a SHELL_M thick shell along its perimeter, cut into segments whose boxes
##   overreach by at most OVERREACH_M (MAX_EDGE_SEGMENTS per edge; a capped edge is counted in `inflated`). A car
##   meets the shell; the hollow interior is never reached at the supported speeds;
## - a vertical capsule (tree trunk, pole, person) becomes its bounding column (corner overreach 0.41 × radius).
## Declared policy, not a fidelity claim: soft foliage stays drivable, obstacles whose bottom is more than
## CAR_REACH_UP_M above the local ground are out of reach, and an obstacle that mostly duplicates one course wall is
## skipped. Scenery damage is not tracked for cars: the world is the immutable installed inventory.
extends RefCounted

const POLICY_VERSION := 2
const OVERREACH_M := 0.3
const SHELL_M := 0.2
const MAX_EDGE_SEGMENTS := 96
const MIN_SEGMENT_M := 0.05
const CAR_REACH_UP_M := 2.0
const DUPLICATE_OVERLAP := 0.5
const BIN_SIZE_M := 8.0
## Same reach as Track.nearby_walls: the largest hub/hull distance is < 0.6 m, 1.0 m also covers RK stage motion.
const QUERY_MARGIN_M := 1.0
const DRIVABLE_RESPONSES := ["soft_foliage_impulse"]
const WALL_MU := {"hard_terminal": 0.6, "frangible_impulse": 0.5, "light_airframe_impulse": 0.4}
const WALL_MU_DEFAULT := 0.5
const BIN_KEY_OFFSET := 1 << 19
const BIN_KEY_STRIDE := 1 << 20


## {walls, bins, summary, sha256}. `course_walls` (the course's own wall boxes) are never duplicated; `ground_up`
## (north, east) -> local ground height (m, up) decides reach; `ground_key` identifies that ground for the cache.
## Deterministic: proxies in world order, segments in order, ids "scenery:<proxy id>" or "scenery:<proxy id>#<n>",
## `order` = position in that sequence. The latest conversion is cached; callers must treat it as read-only.
static func build(world: Dictionary, course_walls: Array, ground_up: Callable = Callable(), ground_key := "") -> Dictionary:
	var identity := str(world.get("identity", ""))
	var key := "%d|%s|%s|%s" % [POLICY_VERSION, identity, ground_key, JSON.stringify(course_walls, "", true, true)]
	if not identity.is_empty() and key == _cache_key:
		return _cache_value
	var built := _build_uncached(world, course_walls, ground_up)
	built.sha256 = JSON.stringify(built.walls, "", true, true).sha256_text()
	if not identity.is_empty():
		_cache_key = key
		_cache_value = built
	return built


static var _cache_key := ""
static var _cache_value := {}


static func _build_uncached(world: Dictionary, course_walls: Array, ground_up: Callable) -> Dictionary:
	var walls: Array = []
	var summary := {admitted = 0, drivable = 0, out_of_reach = 0, duplicate = 0, unsupported = 0, shelled = 0,
		inflated = 0, world_identity = str(world.get("identity", ""))}
	var proxies_value: Variant = world.get("proxies", [])
	if typeof(proxies_value) != TYPE_ARRAY:
		return {walls = walls, bins = {}, summary = summary}
	for proxy: Dictionary in proxies_value:
		var response := str(proxy.get("response_class", ""))
		if response in DRIVABLE_RESPONSES:
			summary.drivable += 1
			continue
		var boxes: Array = _proxy_boxes(proxy, summary)
		if boxes.is_empty():
			summary.unsupported += 1
			continue
		var ground := 0.0
		if ground_up.is_valid():
			var sampled: Variant = ground_up.call(float(proxy.north), float(proxy.east))
			if typeof(sampled) == TYPE_FLOAT and is_finite(sampled):
				ground = sampled
		var bottom := INF
		for box: Dictionary in boxes:
			bottom = minf(bottom, float(box.bottom_up_m))
		if bottom - ground > CAR_REACH_UP_M:
			summary.out_of_reach += 1
			continue
		if _duplicates_course_wall(boxes, course_walls):
			summary.duplicate += 1
			continue
		summary.admitted += 1
		var mu: float = float(WALL_MU.get(response, WALL_MU_DEFAULT))
		for index in boxes.size():
			var wall: Dictionary = boxes[index]
			wall.id = "scenery:%s" % str(proxy.get("id", "")) if boxes.size() == 1 \
				else "scenery:%s#%d" % [str(proxy.get("id", "")), index]
			wall.mu = mu
			wall.order = walls.size()
			walls.append(wall)
	summary.walls = walls.size()
	return {walls = walls, bins = _bins(walls), summary = summary}


## Scenery walls near (north, east), nearest first (ties by `order`), at most `limit`; `omitted` counts the rest.
static func nearby(walls: Array, bins: Dictionary, north: float, east: float, limit: int) -> Dictionary:
	var found: Array = []
	var key := _bin_key(floori(north / BIN_SIZE_M), floori(east / BIN_SIZE_M))
	for index: int in bins.get(key, PackedInt32Array()):
		var wall: Dictionary = walls[index]
		var dn := maxf(maxf(float(wall.north_min_m) - north, north - float(wall.north_max_m)), 0.0)
		var de := maxf(maxf(float(wall.east_min_m) - east, east - float(wall.east_max_m)), 0.0)
		if dn <= QUERY_MARGIN_M and de <= QUERY_MARGIN_M:
			found.append([dn * dn + de * de, index])
	if found.is_empty():
		return {walls = [], omitted = 0}
	if found.size() == 1 and limit >= 1:
		return {walls = [walls[found[0][1]]], omitted = 0}
	# Bins hold indices in ascending order, so equal distances keep the conversion order.
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for entry: Array in found.slice(0, maxi(limit, 0)):
		out.append(walls[entry[1]])
	return {walls = out, omitted = maxi(found.size() - maxi(limit, 0), 0)}


static func _proxy_boxes(proxy: Dictionary, summary: Dictionary) -> Array:
	var north := float(proxy.get("north", NAN))
	var east := float(proxy.get("east", NAN))
	var down := float(proxy.get("down", NAN))
	if not (is_finite(north) and is_finite(east) and is_finite(down)):
		return []
	var shape := str(proxy.get("shape", ""))
	if shape == "capsule":
		var radius := float(proxy.get("radius", NAN))
		var half_length := float(proxy.get("half_length", NAN))
		if not (radius > 0.0 and half_length >= 0.0):
			return []
		return [_box(north - radius, north + radius, east - radius, east + radius,
			-(down + half_length + radius), -(down - half_length - radius))]
	if shape != "box":
		return []
	var half_x := float(proxy.get("half_x", NAN))
	var half_z := float(proxy.get("half_z", NAN))
	var half_down := float(proxy.get("half_down", NAN))
	var sh := float(proxy.get("sin_heading", NAN))
	var ch := float(proxy.get("cos_heading", NAN))
	if not (half_x > 0.0 and half_z > 0.0 and half_down > 0.0 and is_finite(sh) and is_finite(ch)):
		return []
	var bottom := -(down + half_down)
	var top := -(down - half_down)
	# Local axes as in the shared signed distance: x = (-sin, cos), z = (cos, sin) in (north, east).
	var x_axis := PackedFloat64Array([-sh, ch])
	var z_axis := PackedFloat64Array([ch, sh])
	var tilt := minf(absf(sh), absf(ch))
	# A rectangle's bounding box overreaches it by at most (both full sides) × tilt at its corners.
	if 2.0 * (half_x + half_z) * tilt <= OVERREACH_M:
		return [_footprint_box(north, east, x_axis, half_x, z_axis, half_z, bottom, top)]
	summary.shelled += 1
	var boxes: Array = []
	var inflated := false
	# Four edges: along each local axis, at both ends of the other one.
	for edge: Array in [[x_axis, half_x, z_axis, half_z], [z_axis, half_z, x_axis, half_x]]:
		var along: PackedFloat64Array = edge[0]
		var half_along: float = edge[1]
		var across: PackedFloat64Array = edge[2]
		var half_across: float = edge[3]
		var shell := minf(SHELL_M, half_across)
		var segment := maxf(OVERREACH_M / tilt - shell, MIN_SEGMENT_M)
		var wanted := int(ceilf(2.0 * half_along / segment))
		var count := clampi(wanted, 1, MAX_EDGE_SEGMENTS)
		inflated = inflated or wanted > MAX_EDGE_SEGMENTS
		for side: float in [-1.0, 1.0]:
			var offset := side * (half_across - 0.5 * shell)
			for index in count:
				var position := -half_along + (2.0 * float(index) + 1.0) * half_along / float(count)
				boxes.append(_footprint_box(north + across[0] * offset + along[0] * position,
					east + across[1] * offset + along[1] * position, along, half_along / float(count),
					across, 0.5 * shell, bottom, top))
	if inflated:
		summary.inflated += 1
	return boxes


static func _footprint_box(north: float, east: float, a: PackedFloat64Array, half_a: float, b: PackedFloat64Array,
		half_b: float, bottom: float, top: float) -> Dictionary:
	var reach_north := absf(a[0]) * half_a + absf(b[0]) * half_b
	var reach_east := absf(a[1]) * half_a + absf(b[1]) * half_b
	return _box(north - reach_north, north + reach_north, east - reach_east, east + reach_east, bottom, top)


static func _box(n0: float, n1: float, e0: float, e1: float, bottom: float, top: float) -> Dictionary:
	return {north_min_m = n0, north_max_m = n1, east_min_m = e0, east_max_m = e1, bottom_up_m = bottom, top_up_m = top}


## True when most of an obstacle's volume lies inside a single course wall (the same object authored twice).
static func _duplicates_course_wall(boxes: Array, course_walls: Array) -> bool:
	var volume := 0.0
	for box: Dictionary in boxes:
		volume += _volume(box)
	if not (volume > 0.0):
		return false
	for wall: Dictionary in course_walls:
		var shared := 0.0
		for box: Dictionary in boxes:
			shared += _overlap_volume(box, wall)
		if shared >= DUPLICATE_OVERLAP * volume:
			return true
	return false


static func _volume(box: Dictionary) -> float:
	return (float(box.north_max_m) - float(box.north_min_m)) * (float(box.east_max_m) - float(box.east_min_m)) \
		* (float(box.top_up_m) - float(box.bottom_up_m))


static func _overlap_volume(a: Dictionary, b: Dictionary) -> float:
	var result := 1.0
	for pair in [["north_min_m", "north_max_m"], ["east_min_m", "east_max_m"], ["bottom_up_m", "top_up_m"]]:
		var low := maxf(float(a[pair[0]]), float(b[pair[0]]))
		var high := minf(float(a[pair[1]]), float(b[pair[1]]))
		if high <= low:
			return 0.0
		result *= high - low
	return result


static func _bins(walls: Array) -> Dictionary:
	var bins := {}
	for index in walls.size():
		var wall: Dictionary = walls[index]
		for i in range(floori((float(wall.north_min_m) - QUERY_MARGIN_M) / BIN_SIZE_M),
				floori((float(wall.north_max_m) + QUERY_MARGIN_M) / BIN_SIZE_M) + 1):
			for j in range(floori((float(wall.east_min_m) - QUERY_MARGIN_M) / BIN_SIZE_M),
					floori((float(wall.east_max_m) + QUERY_MARGIN_M) / BIN_SIZE_M) + 1):
				var key := _bin_key(i, j)
				var list: PackedInt32Array = bins.get(key, PackedInt32Array())
				list.append(index)
				bins[key] = list
	return bins


## Integer bin key (2^20 cells per axis is far beyond any field).
static func _bin_key(i: int, j: int) -> int:
	return (i + BIN_KEY_OFFSET) * BIN_KEY_STRIDE + (j + BIN_KEY_OFFSET)
