# SUN-09 (docs/plans/sun.md): the field's skyline as the pilot's eye sees it: for each azimuth bin, the highest elevation
# any static scenery reaches (trees, buildings, the treeline, ridges, terrain). The sun hidden below it neither bleaches
# the eye nor veils it while it is off screen (on screen the depth buffer decides). Built once per eye position from the
# built field's own geometry, incrementally under a fixed per-frame work budget (samples, not wall time, so captures and
# replays complete it on the same frame on any machine) and a flight never hitches; until it is done the callers keep
# SunOptics' constant skyline prior.
# - MultiMesh instances taller than MIN_HEIGHT_M (trees, shrubs, people, cars): the top of each instance's box, over
#   CROWN_SHARE of its horizontal size (a crown is narrower than its rotated box).
# - Meshes: their vertices (merged scenery cells, ridges, terrain), at most MAX_SAMPLES_PER_MESH per mesh (stride).
# Geometry within EXCLUDE_RADIUS_M of the eye (the pilot's own shelter) is ignored. Render axes (y up, −z north).
extends RefCounted

const BINS := 720 # 0.5° of azimuth
const MIN_HEIGHT_M := 1.0
const CROWN_SHARE := 0.35
const MAX_SAMPLES_PER_MESH := 20000
const EXCLUDE_RADIUS_M := 3.0
## No scenery in a bin: the elevation reported.
const EMPTY := -PI / 2.0

var eye := Vector3.ZERO
var bins := PackedFloat32Array()
var done := false
var _stack: Array[Node] = []
var _job: Dictionary = {} # the node in progress: {kind, node, index, count, stride, ...}


func _init(field: Node, eye_position: Vector3) -> void:
	eye = eye_position
	bins.resize(BINS)
	bins.fill(EMPTY)
	if field != null:
		_stack.append(field)
	done = _stack.is_empty()


## Processes at most `samples` points (instances or vertices); returns true once the skyline is complete.
func step(samples: int) -> bool:
	var left := maxi(samples, 1)
	while not done and left > 0:
		if _job.is_empty():
			if _stack.is_empty():
				done = true
				break
			_start(_stack.pop_back())
		else:
			left -= _advance(mini(left, 256))
	return done


## Builds to completion (tests, captures).
func finish() -> void:
	while not step(1 << 20):
		pass


## The skyline's elevation (rad) toward `dir`'s azimuth.
func elevation(dir: Vector3) -> float:
	return bins[azimuth_bin(dir)]


## Fraction of a disc of angular `radius` (rad) toward `dir` that clears the skyline (a smooth edge over its diameter).
func visibility(dir: Vector3, radius: float) -> float:
	var top := elevation(dir)
	if top <= EMPTY:
		return 1.0
	var el := asin(clampf(dir.normalized().y, -1.0, 1.0))
	var r := maxf(radius, 1e-4)
	return smoothstep(top - r, top + r, el)


static func azimuth_bin(dir: Vector3) -> int:
	var az := fposmod(atan2(dir.x, -dir.z), TAU) # clockwise from north (render −z), east = +x
	return mini(int(az / TAU * BINS), BINS - 1)


func _start(node: Node) -> void:
	for child in node.get_children():
		_stack.append(child)
	if node is CanvasItem or node is CanvasLayer:
		return
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return
	if node is MultiMeshInstance3D:
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
			return
		var box := mm.mesh.get_aabb()
		if box.size.y < MIN_HEIGHT_M:
			return
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		_job = {kind = "instances", node = node, index = 0, count = count, box = box,
			transform = (node as Node3D).global_transform}
	elif node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			return
		var transform := (node as Node3D).global_transform
		# Nothing at or below the eye can rise above the horizon (the callers keep the geometric horizon): the flat
		# ground and lake are skipped without reading their vertices.
		var world_box: AABB = transform * mesh.get_aabb()
		if world_box.end.y <= eye.y:
			return
		var vertices := PackedVector3Array()
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			vertices.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
		if vertices.is_empty():
			return
		_job = {kind = "vertices", node = node, index = 0, count = vertices.size(), vertices = vertices,
			stride = maxi(1, ceili(float(vertices.size()) / MAX_SAMPLES_PER_MESH)), transform = transform}


## Advances the job by up to `items` samples; returns how many it used.
func _advance(items: int) -> int:
	var job := _job
	var stride := int(job.stride) if job.kind == "vertices" else 1
	var start := int(job.index)
	var end := mini(start + items * stride, int(job.count))
	if job.kind == "instances":
		var mm: MultiMesh = (job.node as MultiMeshInstance3D).multimesh
		var box: AABB = job.box
		var base: Transform3D = job.transform
		for i in range(start, end):
			var world: AABB = (base * mm.get_instance_transform(i)) * box
			var centre := world.get_center()
			_add(Vector3(centre.x, world.end.y, centre.z), CROWN_SHARE * maxf(world.size.x, world.size.z))
	else:
		var vertices: PackedVector3Array = job.vertices
		var base: Transform3D = job.transform
		for i in range(start, end, stride):
			_add(base * vertices[i], 0.0)
	job.index = end
	if end >= int(job.count):
		_job = {}
	return maxi(ceili(float(end - start) / stride), 1)


## Raises the bins a point (with a horizontal half-width in metres) covers to its elevation.
func _add(point: Vector3, half_width: float) -> void:
	var offset := point - eye
	var distance := Vector2(offset.x, offset.z).length()
	if distance < EXCLUDE_RADIUS_M or not offset.is_finite():
		return
	var el := atan2(offset.y, distance)
	var centre := fposmod(atan2(offset.x, -offset.z), TAU)
	var half := atan2(half_width, distance) if half_width > 0.0 else 0.0
	var first := int(floor((centre - half) / TAU * BINS))
	var last := int(floor((centre + half) / TAU * BINS))
	for b in range(first, last + 1):
		var index := posmod(b, BINS)
		if el > bins[index]:
			bins[index] = el
