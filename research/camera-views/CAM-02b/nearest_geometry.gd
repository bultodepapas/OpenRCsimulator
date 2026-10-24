# CAM-02b probe: nearest geometry to the pilot's eye in every landscape (exact triangle distance for meshes and
# multimesh instances whose bounds come within 1.5 m; lights, other worlds and layers the camera cannot see skipped).
# Run from the repository root:
#   godot --headless --path app --audio-driver Dummy --script "$PWD/research/camera-views/CAM-02b/nearest_geometry.gd"
extends SceneTree
const Catalog := preload("res://landscapes/catalog.gd")
class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

func _initialize() -> void:
	_run.call_deferred()

func _collect(node: Node, out: Array) -> void:
	if node is SubViewport:
		return # another world (projected-shadow casters, reflections)
	if (node is MeshInstance3D or node is MultiMeshInstance3D) and (node as VisualInstance3D).is_visible_in_tree():
		out.append(node)
	for child in node.get_children():
		_collect(child, out)

## Smallest distance from p to the triangles of a mesh placed by xf (exact, brute force).
static func _mesh_distance(mesh: Mesh, xf: Transform3D, p: Vector3) -> float:
	if mesh == null:
		return INF
	var faces := mesh.get_faces()
	var best := INF
	for i in range(0, faces.size(), 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		best = minf(best, _point_triangle(p, a, b, c))
	return best

static func _point_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := Plane(a, b, c).normal
	var proj := p - n * n.dot(p - a)
	var inside := Geometry3D.ray_intersects_triangle(proj + n, -n, a, b, c) != null
	if inside:
		return absf(n.dot(p - a))
	return minf(minf(Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p),
		Geometry3D.get_closest_point_to_segment(p, b, c).distance_to(p)), Geometry3D.get_closest_point_to_segment(p, c, a).distance_to(p))

static func _aabb_distance(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return q.distance_to(p)

func _run() -> void:
	for id: String in Catalog.ids():
		var flight: TestFlight = TestFlight.new()
		flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off", "landscape": id}
		root.add_child(flight)
		await process_frame
		flight._process(1.0 / 60.0)
		var eye: Vector3 = flight._camera.global_position
		var nodes: Array = []
		_collect(flight, nodes)
		var rows: Array = []
		var mask: int = flight._camera.cull_mask
		for n: VisualInstance3D in nodes:
			if flight._airplane.root.is_ancestor_of(n) or (n.layers & mask) == 0:
				continue
			var box: AABB = n.get_aabb()
			if box.size == Vector3.ZERO or _aabb_distance(n.global_transform * box, eye) > 1.5:
				continue
			var d := INF
			if n is MeshInstance3D:
				d = _mesh_distance((n as MeshInstance3D).mesh, n.global_transform, eye)
			else:
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				if mm != null:
					for k in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
						var xf: Transform3D = n.global_transform * mm.get_instance_transform(k)
						if _aabb_distance(xf * mm.mesh.get_aabb(), eye) <= 1.5:
							d = minf(d, _mesh_distance(mm.mesh, xf, eye))
			rows.append([d, str(n.get_path()).replace(str(flight.get_path()), ""), n.get_class()])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		print("LANDSCAPE %s eye %s, %d visual instances; nearest:" % [id, eye, rows.size()])
		for r in rows.slice(0, 8):
			print("  %.2f m  %s  %s" % r)
		flight.free()
		await process_frame
	quit(0)
