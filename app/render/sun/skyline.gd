# SUN-09 (docs/plans/sun.md): the field's skyline as the pilot's eye sees it: for each azimuth bin, the highest elevation
# any static scenery reaches (trees, buildings, the treeline, ridges, terrain). The sun hidden below it neither bleaches
# the eye nor veils it while it is off screen (on screen the depth buffer decides). Built once per eye position from the
# built field's own geometry, incrementally under a fixed per-frame work budget (samples, not wall time, so captures and
# replays complete it on the same frame on any machine) and a flight never hitches; until it is done the callers keep
# SunOptics' constant skyline prior.
# - MultiMesh instances taller than MIN_HEIGHT_M (trees, shrubs, people, cars): the top of each instance's box, over
#   CROWN_SHARE of its horizontal size (a crown is narrower than its rotated box). Gaps between crowns stay open.
# - Meshes (merged scenery cells, ridges, terrain): their triangles' edges, each raising the bins it spans to the lower
#   of its two ends (a wall's top edge covers the wall, never more), at most MAX_SAMPLES_PER_MESH triangles per mesh
#   (stride). Corners alone left gaps across every flat face. Meshes whose top is at or below the eye, terrain sheets
#   and SubViewport subtrees (their own worlds) are skipped.
# Geometry within EXCLUDE_RADIUS_M of the eye (the pilot's own shelter) is ignored. Render axes (y up, −z north).
extends RefCounted

const BINS := 720 # 0.5° of azimuth
const MIN_HEIGHT_M := 1.0
const CROWN_SHARE := 0.35
const MAX_SAMPLES_PER_MESH := 20000
const EXCLUDE_RADIUS_M := 3.0
## Terrain sheets (see _start) are skipped: wider than this, with relief under this share of their size.
const TERRAIN_MIN_SIZE_M := 2000.0
const TERRAIN_RELIEF_SHARE := 0.02
## An edge spanning more azimuth than this (a huge triangle near the eye) only marks its ends.
const MAX_EDGE_SPAN := PI / 6.0
## No scenery in a bin: the elevation reported (stored as float32: compare with is_empty_elevation()).
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


## Processes at most `samples` instances, vertices or triangles; returns true once the skyline is complete.
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
	if is_empty_elevation(top):
		return 1.0
	var el := asin(clampf(dir.normalized().y, -1.0, 1.0))
	var r := maxf(radius, 1e-4)
	return smoothstep(top - r, top + r, el)


## Whether a bin's elevation means "no scenery" (bins are float32, EMPTY is float64).
static func is_empty_elevation(elevation_rad: float) -> bool:
	return elevation_rad <= EMPTY + 1e-6


static func azimuth_bin(dir: Vector3) -> int:
	return posmod(int(floor(fposmod(atan2(dir.x, -dir.z), TAU) / TAU * BINS)), BINS) # clockwise from north (−z)


func _start(node: Node) -> void:
	if node is Viewport:
		return # a SubViewport renders its own world (e.g. projected-shadow silhouettes), not the field the eye sees
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
		# One read of the whole instance buffer: get_instance_transform() reads back from the renderer per call
		# (~0.8 ms each on GLES3). Row-major 3×4 transforms, then the optional colour and custom data.
		var buffer: PackedFloat32Array = mm.buffer
		var width := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		if buffer.size() < count * width:
			return # the headless dummy renderer keeps no instance data
		_job = {kind = "instances", node = node, index = 0, count = count, stride = 1, box = box, buffer = buffer,
			width = width, transform = (node as Node3D).global_transform}
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
		# Terrain sheets kilometres wide with relief under TERRAIN_RELIEF_SHARE of their size are skipped: reading the
		# field's 40 km ground costs a 24 ms frame. Measured on the default field, the skyline drops by at most 1° (at
		# 45–60° and 300° azimuth, where gentle relief near the field rose above the trees): a little more glare there,
		# never less. Distant hills are their own ridge meshes.
		if minf(world_box.size.x, world_box.size.z) > TERRAIN_MIN_SIZE_M \
				and world_box.size.y < TERRAIN_RELIEF_SHARE * minf(world_box.size.x, world_box.size.z):
			return
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var surface_indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var base := vertices.size()
			if surface_indices is PackedInt32Array and not (surface_indices as PackedInt32Array).is_empty():
				for index: int in surface_indices:
					indices.append(base + index)
			else:
				for index in surface_vertices.size():
					indices.append(base + index)
			vertices.append_array(surface_vertices)
		var triangles := indices.size() / 3
		if triangles == 0:
			return
		var azimuths := PackedFloat32Array()
		var elevations := PackedFloat32Array()
		azimuths.resize(vertices.size())
		elevations.resize(vertices.size())
		_job = {kind = "vertices", node = node, index = 0, count = vertices.size(), stride = 1, vertices = vertices,
			indices = indices, triangles = triangles, azimuths = azimuths, elevations = elevations, transform = transform,
			triangle_stride = maxi(1, ceili(float(triangles) / MAX_SAMPLES_PER_MESH))}


## Advances the job by up to `items` samples (instances or triangles); returns how many it used.
func _advance(items: int) -> int:
	var job := _job
	var stride := int(job.stride)
	var start := int(job.index)
	var end := mini(start + items * stride, int(job.count))
	if job.kind == "instances":
		var buffer: PackedFloat32Array = job.buffer
		var width := int(job.width)
		var box: AABB = job.box
		var base: Transform3D = job.transform
		for i in range(start, end):
			var k := i * width
			var instance := Transform3D(Basis(Vector3(buffer[k], buffer[k + 4], buffer[k + 8]),
				Vector3(buffer[k + 1], buffer[k + 5], buffer[k + 9]), Vector3(buffer[k + 2], buffer[k + 6], buffer[k + 10])),
				Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))
			var world: AABB = (base * instance) * box
			var centre := world.get_center()
			_add(Vector3(centre.x, world.end.y, centre.z), CROWN_SHARE * maxf(world.size.x, world.size.z))
	elif job.kind == "vertices":
		# Pass 1: each vertex's azimuth and elevation once (NAN inside the exclusion radius), and its own bin.
		var vertices: PackedVector3Array = job.vertices
		var azimuths: PackedFloat32Array = job.azimuths
		var elevations: PackedFloat32Array = job.elevations
		var base: Transform3D = job.transform
		for i in range(start, end):
			var offset: Vector3 = base * vertices[i] - eye
			var distance := Vector2(offset.x, offset.z).length()
			if distance < EXCLUDE_RADIUS_M or not offset.is_finite():
				elevations[i] = NAN
				continue
			var az := fposmod(atan2(offset.x, -offset.z), TAU)
			var el := atan2(offset.y, distance)
			azimuths[i] = az
			elevations[i] = el
			_raise(az, az, el)
		job.azimuths = azimuths
		job.elevations = elevations
	else:
		# Pass 2: each triangle's edges raise the bins they span to the lower end.
		var indices: PackedInt32Array = job.indices
		var azimuths: PackedFloat32Array = job.azimuths
		var elevations: PackedFloat32Array = job.elevations
		for t in range(start, end, stride):
			var a := indices[3 * t]
			var b := indices[3 * t + 1]
			var c := indices[3 * t + 2]
			_edge(azimuths, elevations, a, b)
			_edge(azimuths, elevations, b, c)
			_edge(azimuths, elevations, c, a)
	job.index = end
	if end >= int(job.count):
		if job.kind == "vertices":
			_job = {kind = "triangles", node = job.node, index = 0, count = job.triangles, stride = job.triangle_stride,
				indices = job.indices, azimuths = job.azimuths, elevations = job.elevations}
		else:
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
	_raise(centre - half, centre + half, el)


## Raises the bins an edge between cached vertices `i` and `j` spans to the lower of its ends' elevations.
func _edge(azimuths: PackedFloat32Array, elevations: PackedFloat32Array, i: int, j: int) -> void:
	var el_i := elevations[i]
	var el_j := elevations[j]
	if is_nan(el_i) or is_nan(el_j):
		return
	var az_i := azimuths[i]
	var span := wrapf(azimuths[j] - az_i, -PI, PI)
	if absf(span) > MAX_EDGE_SPAN or absf(span) < TAU / BINS:
		return # too wide to trust, or inside one bin (the vertex pass covered it)
	var from := az_i if span >= 0.0 else az_i + span
	_raise(from, from + absf(span), minf(el_i, el_j))


## Raises every bin from azimuth `first` to `last` (rad, `last` ≥ `first`, may wrap) to `el`.
func _raise(first: float, last: float, el: float) -> void:
	var a := int(floor(first / TAU * BINS))
	var b := int(floor(last / TAU * BINS))
	for bin in range(a, b + 1):
		var index := posmod(bin, BINS)
		if el > bins[index]:
			bins[index] = el
