## Home-only geometry fitting. Mesh/Node snapshots and publication stay on main;
## one owned worker receives only private value arrays and returns compact layout.
extends Node

const Lights := preload("res://render/world/aircraft_lights.gd")
const MAX_SNAPSHOT_BYTES := 96 * 1024 * 1024
const SNAPSHOT_BUDGET_USEC := 3000

class Snapshot:
	extends RefCounted
	var data: Dictionary
	var complete := false
	var failed := false
	var max_chunk_usec := 0
	var _meshes: Array[Node] = []
	var _mesh_index := 0
	var _surface_index := 0
	var _bytes := 0
	var _root: Node3D

	func _init(model: Node3D) -> void:
		_root = model
		data = {bounds = Lights.bounds(model).all,
			needs_landing = not (model.get_meta("light_anchors", {}) as Dictionary).has("landing"), surfaces = []}
		_meshes = model.find_children("*", "MeshInstance3D", true, false)

	## A large engine surface read is indivisible; retain its observed maximum.
	func advance(budget_usec: int = SNAPSHOT_BUDGET_USEC) -> bool:
		var started := Time.get_ticks_usec()
		while _mesh_index < _meshes.size():
			var mi := _meshes[_mesh_index] as MeshInstance3D
			if not is_instance_valid(mi) or mi.mesh == null:
				_mesh_index += 1
				_surface_index = 0
				continue
			if _surface_index >= mi.mesh.get_surface_count():
				_mesh_index += 1
				_surface_index = 0
				continue
			var surface := _surface_index
			_surface_index += 1
			var include_points := mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh
			var include_faces := not (mi.mesh is ArrayMesh and
				(mi.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES)
			if not include_points and not include_faces:
				continue
			var arrays := mi.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			_bytes += vertices.size() * 12 + indices.size() * 4
			if _bytes > MAX_SNAPSHOT_BYTES:
				failed = true
				complete = true
				data.clear()
				break
			var transform := Transform3D.IDENTITY
			var node: Node = mi
			while node != null and node != _root:
				if node is Node3D:
					transform = (node as Node3D).transform * transform
				node = node.get_parent()
			(data.surfaces as Array).append({vertices = vertices.duplicate(), indices = indices.duplicate(),
				transform = transform, points = include_points, faces = include_faces})
			if Time.get_ticks_usec() - started >= budget_usec:
				break
		max_chunk_usec = maxi(max_chunk_usec, Time.get_ticks_usec() - started)
		complete = complete or _mesh_index >= _meshes.size()
		if complete:
			_meshes.clear()
			_root = null
		return complete

var _thread: Thread
var _callback := Callable()
var _fallback: Dictionary = {}
var completed_jobs := 0
var last_worker_usec := 0

func _init() -> void:
	set_process(false)

func busy() -> bool:
	return _thread != null or not _fallback.is_empty()

## No queue of model snapshots: callers wait with only their latest intent.
func request(snapshot: Dictionary, callback: Callable) -> bool:
	if busy() or snapshot.is_empty():
		return false
	_callback = callback
	_thread = Thread.new()
	var error := _thread.start(compute.bind(snapshot))
	if error != OK:
		_thread = null
		# Platforms without threads retain the previous synchronous capability.
		_fallback = snapshot
	set_process(true)
	return true

static func compute(snapshot: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var points := PackedVector3Array()
	var triangles := PackedVector3Array()
	for surface: Dictionary in snapshot.surfaces:
		var vertices: PackedVector3Array = (surface.transform as Transform3D) * (surface.vertices as PackedVector3Array)
		if surface.points:
			points.append_array(vertices)
		if surface.faces:
			var indices: PackedInt32Array = surface.indices
			if indices.is_empty():
				triangles.append_array(vertices)
			else:
				for index: int in indices:
					triangles.append(vertices[index])
	var layout: Dictionary = Lights.layout_from_geometry({points = points, triangles = triangles},
		snapshot.bounds, bool(snapshot.needs_landing))
	return {layout = layout, worker_usec = Time.get_ticks_usec() - started}

func _process(_delta: float) -> void:
	var result: Dictionary
	if _thread != null:
		if _thread.is_alive():
			return
		result = _thread.wait_to_finish()
		_thread = null
	elif not _fallback.is_empty():
		result = compute(_fallback)
		_fallback.clear()
	else:
		set_process(false)
		return
	var callback := _callback
	_callback = Callable()
	completed_jobs += 1
	last_worker_usec = int(result.get("worker_usec", 0))
	set_process(false)
	if callback.is_valid():
		callback.call(result.get("layout", {}))

func cancel_for(owner: Object) -> void:
	if _callback.get_object_id() == owner.get_instance_id():
		_callback = Callable()

func _exit_tree() -> void:
	_callback = Callable()
	_fallback.clear()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
