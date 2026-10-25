# CAM-09: camera clearance against the scenery's collision proxies (scenery/collision_world.gd: oriented boxes for
# buildings, vehicles, the flight-line barrier and tree crowns; vertical capsules for trunks). Presentation only: it
# reads the world the simulation collides with and answers how much of a camera boom is free, using the simulation's
# own exact segment tests (sim/scenery_collision.gd) with the probe radius as padding. Render space in, NED inside.
extends RefCounted

const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")

## Probe sphere radius (m): the corner of a 0.25 m near plane at a 55° vertical, 16:9 view is 0.36 m from the eye.
const PROBE_RADIUS_M := 0.4
## Objects whose largest side is shorter (runway threshold stakes, small parts of parked models) can neither hide the
## aircraft nor fill the view: the camera passes them, as game cameras let small props through.
const MIN_OBSTACLE_M := 0.5


## Share (0..1) of the boom from `from` (the aircraft) to `to` (the wanted eye) that a sphere of `radius` travels
## before touching a proxy at least `min_size` long; 1 when the boom is clear or there is no world.
static func free_fraction(world: Dictionary, from: Vector3, to: Vector3, radius := PROBE_RADIUS_M,
		min_size := MIN_OBSTACLE_M) -> float:
	if world.is_empty() or from.distance_squared_to(to) < 1e-8:
		return 1.0
	var a := PackedFloat64Array([-from.z, from.x, -from.y])
	var b := PackedFloat64Array([-to.z, to.x, -to.y])
	var n_min := minf(a[0], b[0]) - radius
	var n_max := maxf(a[0], b[0]) + radius
	var e_min := minf(a[1], b[1]) - radius
	var e_max := maxf(a[1], b[1]) + radius
	var d_min := minf(a[2], b[2]) - radius
	var d_max := maxf(a[2], b[2]) + radius
	var cell := CollisionWorld.CELL_SIZE_M
	var proxies: Array = world.proxies
	var bins: Dictionary = world.bins
	var best := 1.0
	# The world's own 32 m bins, walked directly: no candidate set or proxy copies per frame (a proxy in two cells
	# is tested twice, which cannot change the minimum). Bounds reject most of the field's fences and people.
	for n_cell in range(floori(n_min / cell), floori(n_max / cell) + 1):
		for e_cell in range(floori(e_min / cell), floori(e_max / cell) + 1):
			for d_cell in range(floori(d_min / cell), floori(d_max / cell) + 1):
				var key := CollisionWorld._cell_key(n_cell, e_cell, d_cell)
				if not bins.has(key):
					continue
				for index: int in bins[key]:
					var proxy: Dictionary = proxies[index]
					if float(proxy.bounds_north_max) < n_min or float(proxy.bounds_north_min) > n_max \
							or float(proxy.bounds_east_max) < e_min or float(proxy.bounds_east_min) > e_max \
							or float(proxy.bounds_down_max) < d_min or float(proxy.bounds_down_min) > d_max:
						continue
					if float(proxy.bounds_north_max) - float(proxy.bounds_north_min) < min_size \
							and float(proxy.bounds_east_max) - float(proxy.bounds_east_min) < min_size \
							and float(proxy.bounds_down_max) - float(proxy.bounds_down_min) < min_size:
						continue
					var hit: Dictionary = SceneryCollision._segment_proxy(a, b, proxy, radius)
					if bool(hit.get("hit", false)):
						best = minf(best, float(hit.fraction))
	return best


## The boom length a view may use this frame: it shortens at once when something comes between the aircraft and the
## camera, and lengthens again only after the way has been clear for DWELL_S, easing out (Cinemachine's minimum
## occlusion time and damping when occluded, UE's spring arm probe). A thin post the camera sweeps past therefore
## costs one quick pull-in, not a pumping boom.
class BoomGuard:
	const CameraMath := preload("res://render/camera/camera_math.gd")
	const DWELL_S := 0.3
	const EASE_OUT_HALF_LIFE := 0.35

	var limit := INF
	var _clear_for := 0.0

	func reset() -> void:
		limit = INF
		_clear_for = 0.0

	## free_length: how far the boom is clear now; wanted: the view's own boom length. Returns the length to use.
	func update(free_length: float, wanted: float, dt: float) -> float:
		if free_length < minf(limit, wanted) - 1e-4:
			limit = free_length
			_clear_for = 0.0
		elif limit < wanted:
			_clear_for += maxf(dt, 0.0)
			if _clear_for >= DWELL_S:
				limit = CameraMath.damp(limit, minf(free_length, wanted), dt, EASE_OUT_HALF_LIFE)
				if limit >= wanted - 0.01: # within a centimetre: the full boom
					limit = INF
		else:
			limit = INF
		return minf(limit, wanted)
