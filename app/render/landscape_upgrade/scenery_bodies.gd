## LU-05 secondary wreck contacts. Float64 flight detection remains authoritative; these disposable bodies
## exist only around the crash, on the crash presentation's isolated layer, and are removed on reset.
extends RefCounted
const Frames := preload("res://render/frames.gd")
const WreckScene := preload("res://render/crash/wreck.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const RANGE_M := 65.0
const MAX_BODIES := 160

## `broken` (optional, CR-22e): scenery damage records; their broken proxies are skipped exactly as
## FlightSession.collision_world(true) removes them, so a caller can pass the installed world itself
## instead of a deep copy of every proxy.
static func build_near(world: Dictionary, point_ned: PackedFloat64Array, broken: Dictionary = {}) -> Node3D:
	return build_near_staged(world, point_ned, broken, MAX_BODIES)


## CR-22e: the same selection and order as build_near, but only the `first` nearest bodies are created
## now; continue_build() adds the farther ones on later frames. Creating up to 160 physics bodies cost
## about 13 ms in one frame, while debris needs several frames to reach anything but the nearest.
static func build_near_staged(world: Dictionary, point_ned: PackedFloat64Array, broken: Dictionary,
		first: int) -> Node3D:
	var root := Node3D.new()
	root.name = "SceneryWreckContacts"
	root.set_meta("bodies", 0)
	if point_ned.size() != 3:
		return root
	root.set_meta("pending", _plan_near(world, point_ned, broken))
	root.set_meta("omitted", _last_omitted)
	continue_build(root, first)
	return root


## Adds up to `count` more planned bodies, nearest first. Returns true once every planned body exists.
static func continue_build(root: Node3D, count: int) -> bool:
	if not is_instance_valid(root) or not root.has_meta("pending"):
		return true
	var pending: Array = root.get_meta("pending")
	var built: int = root.get_meta("bodies", 0)
	var stop := mini(pending.size(), built + maxi(0, count))
	for index in range(built, stop):
		root.add_child(_body(pending[index], index))
	root.set_meta("bodies", stop)
	if stop < pending.size():
		return false
	root.remove_meta("pending")
	return true


## CR-22e: per installed world, the largest filter margin and the vertical bounds of every proxy.
## Computed once (flight setup calls prepare()); only the latest world is kept.
static var _extents_cache: Dictionary = {}
static var _last_omitted := 0


static func prepare(world: Dictionary) -> Dictionary:
	var identity := str(world.get("identity", ""))
	if identity.is_empty() or world.get("bins", {}).is_empty():
		return {}
	if _extents_cache.has(identity):
		return _extents_cache[identity]
	var extents := {margin = 0.0, down_min = INF, down_max = -INF}
	for proxy: Dictionary in world.get("proxies", []):
		extents.margin = maxf(extents.margin, _margin(proxy))
		extents.down_min = minf(extents.down_min, float(proxy.bounds_down_min))
		extents.down_max = maxf(extents.down_max, float(proxy.bounds_down_max))
	_extents_cache = {identity: extents}
	return extents


static func _margin(proxy: Dictionary) -> float:
	return maxf(float(proxy.get("radius", 0.0)), maxf(float(proxy.get("half_x", 0.0)), float(proxy.get("half_z", 0.0))))


## Proxy indices to test. Every proxy is binned in each 32 m cell its bounds touch and its centre lies in
## its bounds, so cells within RANGE_M + the largest margin (all heights) contain every proxy the range
## filter can accept: the same candidates as a full scan, without visiting ~6,000 proxies.
static func _nearby_indices(world: Dictionary, point_ned: PackedFloat64Array) -> Array:
	var extents := prepare(world)
	if extents.is_empty() or not is_finite(float(extents.down_min)):
		return range(world.get("proxies", []).size())
	var reach: float = RANGE_M + float(extents.margin)
	return CollisionWorld._candidate_indices(world, point_ned[0] - reach, point_ned[0] + reach,
		point_ned[1] - reach, point_ned[1] + reach, float(extents.down_min), float(extents.down_max))


## The bounded secondary-contact selection, nearest first.
static func _plan_near(world: Dictionary, point_ned: PackedFloat64Array, broken: Dictionary) -> Array:
	var proxies: Array = world.get("proxies", [])
	var candidates: Array = [] # [distance², id, proxy index]: a native lexicographic sort, same order as before.
	for index: int in _nearby_indices(world, point_ned):
		var proxy: Dictionary = proxies[index]
		# Leaves do not become solid walls when an aircraft breaks up.
		if str(proxy.get("response_class", "")) == "soft_foliage_impulse":
			continue
		if not broken.is_empty() and SceneryDamage.id_is_broken(broken, str(proxy.get("damage_id", ""))):
			continue
		var margin := _margin(proxy)
		if absf(float(proxy.north) - point_ned[0]) > RANGE_M + margin or absf(float(proxy.east) - point_ned[1]) > RANGE_M + margin:
			continue
		candidates.append([_distance_squared(proxy, point_ned), str(proxy.id), index])
	# Spend the bounded secondary-contact budget near the actual impact, rather than in inventory-ID order.
	# The local fence bays add proxies; they must not evict the car/trunk/lamp that the wreck just struck.
	# Nearest first, ties by ID (CR-22e: native sort; a GDScript comparator cost ~10 ms here).
	candidates.sort()
	# The bound is by design. CR-22e: a console warning here cost 6–28 ms inside the crash frame,
	# so the omitted count is reported through the root's "omitted" meta (director stats) instead.
	_last_omitted = maxi(0, candidates.size() - MAX_BODIES)
	var plan: Array = []
	for rank in mini(candidates.size(), MAX_BODIES):
		plan.append(proxies[candidates[rank][2]])
	return plan


static func _body(proxy: Dictionary, index: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Obstacle%d" % index
	body.collision_layer = WreckScene.DEBRIS_LAYER
	body.collision_mask = 0
	body.position = Frames.ned_to_render([proxy.north, proxy.east, proxy.down])
	body.rotation.y = -atan2(float(proxy.get("sin_heading", 0.0)), float(proxy.get("cos_heading", 1.0)))
	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = 0.04
	body.physics_material_override = material
	var shape := CollisionShape3D.new()
	if proxy.shape == "capsule":
		var capsule := CapsuleShape3D.new()
		capsule.radius = maxf(0.01, float(proxy.radius))
		capsule.height = 2.0 * (float(proxy.half_length) + capsule.radius)
		shape.shape = capsule
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(float(proxy.half_x) * 2.0, float(proxy.half_down) * 2.0, float(proxy.half_z) * 2.0)
		shape.shape = box
	body.add_child(shape)
	body.set_meta("obstacle_id", proxy.id)
	return body


static func _distance_squared(proxy: Dictionary, point: PackedFloat64Array) -> float:
	var north := maxf(0.0, maxf(float(proxy.bounds_north_min) - point[0], point[0] - float(proxy.bounds_north_max)))
	var east := maxf(0.0, maxf(float(proxy.bounds_east_min) - point[1], point[1] - float(proxy.bounds_east_max)))
	var down := maxf(0.0, maxf(float(proxy.bounds_down_min) - point[2], point[2] - float(proxy.bounds_down_max)))
	return north * north + east * east + down * down
