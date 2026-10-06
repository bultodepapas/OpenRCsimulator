# EX-04: clearances between each moving surface and the parts around it, on the built and posed Extra model.
# A pair fails when an edge of one closed mesh crosses a triangle of the other, or a vertex lies inside it; the
# reported gap is the smallest vertex-triangle or edge-edge distance. Rendering-side geometry (32-bit floats).
extends RefCounted

const Commands := preload("res://input/commands.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const PROXIMITY_M := 0.03 # only triangles this close to the other part's bounds are compared
const RAY := Vector3(1.0, 0.37139067, 0.69474659) # odd direction: avoids grazing axis-aligned faces
const RAY_LENGTH_M := 5.0

# Pairs [moving mesh, neighbour mesh] per pose family; each neighbour must be a closed mesh.
const AILERON_PAIRS := [
	["aileron_right", "wing_right_ahead_of_aileron"], ["aileron_right", "wing_right_root"], ["aileron_right", "wing_right_tip"],
	["aileron_left", "wing_left_ahead_of_aileron"], ["aileron_left", "wing_left_root"], ["aileron_left", "wing_left_tip"],
]
const TAIL_PAIRS := [
	["rudder", "fin"], ["rudder", "fuselage"], ["rudder", "stab"], ["rudder", "elevator_right"], ["rudder", "elevator_left"],
	["elevator_right", "stab"], ["elevator_right", "fin"], ["elevator_right", "fuselage"],
	["elevator_left", "stab"], ["elevator_left", "fin"], ["elevator_left", "fuselage"],
]


## Poses: every aileron throw, and every elevator x rudder combination at the given maximum throws (degrees).
## `only` (optional) restricts the checked pairs, e.g. to the hinge pairs that a bevel must keep clear.
static func run(airplane: Dictionary, throws_deg: Dictionary, only := []) -> Dictionary:
	var meshes := {}
	_collect(airplane.root, meshes)
	var results := []
	for roll in [-1.0, 0.0, 1.0]:
		results.append(_pose(airplane, meshes, {roll = roll, pitch = 0.0, yaw = 0.0, throttle = 0.0}, throws_deg, _filter(AILERON_PAIRS, only)))
	for pitch in [-1.0, 0.0, 1.0]:
		for yaw in [-1.0, 0.0, 1.0]:
			results.append(_pose(airplane, meshes, {roll = 0.0, pitch = pitch, yaw = yaw, throttle = 0.0}, throws_deg, _filter(TAIL_PAIRS, only)))
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}, throws_deg))
	var failures := []
	var minimum := INF
	for pose in results:
		for pair in pose.pairs:
			minimum = minf(minimum, pair.gap_m)
			if pair.penetrates: failures.append("%s vs %s at %s" % [pair.a, pair.b, pose.command])
	return {ok = failures.is_empty(), failures = failures, minimum_gap_m = minimum, poses = results}


static func _filter(pairs: Array, only: Array) -> Array:
	if only.is_empty(): return pairs
	return pairs.filter(func(pair): return only.has(pair[0] + "/" + pair[1]))


## Largest rudder deflection (deg, 0.5 deg steps from `start`) before it touches either elevator half with the
## elevator neutral: the plan's elevator relief cut, not the hinge, sets this limit.
static func rudder_limit_deg(airplane: Dictionary, start := 30.0, stop := 60.0) -> float:
	var meshes := {}
	_collect(airplane.root, meshes)
	var pairs := [["rudder", "elevator_right"], ["rudder", "elevator_left"]]
	var angle := start
	while angle <= stop:
		var pose := _pose(airplane, meshes, {roll = 0.0, pitch = 0.0, yaw = 1.0, throttle = 0.0}, {aileron = 0.0, elevator = 0.0, rudder = angle}, pairs)
		if pose.pairs.any(func(pair): return pair.penetrates): break
		angle += 0.5
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}))
	return angle - 0.5


static func _pose(airplane: Dictionary, meshes: Dictionary, command: Dictionary, throws_deg: Dictionary, pairs: Array) -> Dictionary:
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(command, throws_deg))
	var cache := {}
	var out := []
	for pair in pairs:
		if not (meshes.has(pair[0]) and meshes.has(pair[1])):
			out.append({a = pair[0], b = pair[1], penetrates = true, gap_m = 0.0, missing = true}) # reported, never skipped
			continue
		for name in pair:
			if not cache.has(name): cache[name] = _triangles(meshes[name], airplane.root)
		var a: Array = cache[pair[0]]
		var b: Array = cache[pair[1]]
		var near_b := _near(b, _bounds(a))
		var near_a := _near(a, _bounds(b))
		var penetrates := _crosses(near_a, near_b) or _crosses(near_b, near_a) or _vertex_inside(a, b) or _vertex_inside(b, a)
		out.append({a = pair[0], b = pair[1], penetrates = penetrates, gap_m = 0.0 if penetrates else _gap(near_a, near_b)})
	return {command = "roll %+.0f pitch %+.0f yaw %+.0f" % [command.roll, command.pitch, command.yaw], pairs = out}


static func _collect(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D: out[String(node.name)] = node
	for child in node.get_children(): _collect(child, out)


static func _triangles(mesh: MeshInstance3D, root: Node3D) -> Array:
	var to_root := root.global_transform.affine_inverse() * mesh.global_transform
	var faces := mesh.mesh.get_faces()
	var out := []
	for i in range(0, faces.size(), 3):
		out.append(PackedVector3Array([to_root * faces[i], to_root * faces[i + 1], to_root * faces[i + 2]]))
	return out


static func _bounds(triangles: Array) -> AABB:
	var box := AABB(triangles[0][0], Vector3.ZERO)
	for t in triangles:
		for p in t: box = box.expand(p)
	return box


static func _near(triangles: Array, box: AABB) -> Array:
	var grown := box.grow(PROXIMITY_M)
	var out := []
	for t in triangles:
		var tb := AABB(t[0], Vector3.ZERO).expand(t[1]).expand(t[2])
		if grown.intersects(tb): out.append(t)
	return out


static func _crosses(edges_from: Array, triangles: Array) -> bool:
	for t in edges_from:
		for k in 3:
			var p: Vector3 = t[k]
			var q: Vector3 = t[(k + 1) % 3]
			for u in triangles:
				if Geometry3D.segment_intersects_triangle(p, q, u[0], u[1], u[2]) != null:
					return true
	return false


# Ray parity from a few vertices of `a` against closed mesh `b` (catches a part buried whole inside another).
static func _vertex_inside(a: Array, b: Array) -> bool:
	var box := _bounds(b)
	var step := maxi(1, a.size() / 8)
	for i in range(0, a.size(), step):
		var p: Vector3 = a[i][0]
		if not box.has_point(p): continue
		var hits := 0
		for u in b:
			if Geometry3D.segment_intersects_triangle(p, p + RAY * RAY_LENGTH_M, u[0], u[1], u[2]) != null: hits += 1
		if hits % 2 == 1: return true
	return false


static func _gap(a: Array, b: Array) -> float:
	if a.is_empty() or b.is_empty(): return PROXIMITY_M
	var best := PROXIMITY_M
	for t in a:
		for u in b:
			for p in t: best = minf(best, _point_triangle_distance(p, u))
			for p in u: best = minf(best, _point_triangle_distance(p, t))
			for k in 3:
				for m in 3:
					var c := Geometry3D.get_closest_points_between_segments(t[k], t[(k + 1) % 3], u[m], u[(m + 1) % 3])
					best = minf(best, c[0].distance_to(c[1]))
	return best


static func _point_triangle_distance(p: Vector3, t: PackedVector3Array) -> float:
	var n := (t[1] - t[0]).cross(t[2] - t[0])
	if n.length_squared() < 1e-18: return INF
	n = n.normalized()
	var projected := p - n * n.dot(p - t[0])
	var inside := true
	for k in 3:
		if (t[(k + 1) % 3] - t[k]).cross(projected - t[k]).dot(n) < 0.0: inside = false
	if inside: return absf(n.dot(p - t[0]))
	var best := INF
	for k in 3:
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, t[k], t[(k + 1) % 3])))
	return best
