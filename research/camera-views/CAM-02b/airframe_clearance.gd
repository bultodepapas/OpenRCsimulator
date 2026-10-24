# CAM-02b probe: nearest airframe triangle to the camera in the closest chase, close-up and orbit poses, every
# flyable catalog airplane, against the rig's near plane. Run from the repository root:
#   godot --headless --path app --audio-driver Dummy --script "$PWD/research/camera-views/CAM-02b/airframe_clearance.gd"
extends SceneTree
const Catalog := preload("res://app_state/aircraft_catalog.gd")
class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

func _initialize() -> void:
	_run.call_deferred()

func _meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)

static func _seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	return Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p)

static func _tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-18:
		return minf(_seg(p, a, b), _seg(p, b, c))
	n = n.normalized()
	var proj := p - n * n.dot(p - a)
	if Geometry3D.ray_intersects_triangle(proj + n, -n, a, b, c) != null:
		return absf(n.dot(p - a))
	return minf(minf(_seg(p, a, b), _seg(p, b, c)), _seg(p, c, a))

func _nearest(meshes: Array, eye: Vector3) -> float:
	var best := INF
	for m: MeshInstance3D in meshes:
		var xf := m.global_transform
		if (xf * m.mesh.get_aabb()).grow(0.0).has_point(eye) == false:
			var q := eye.clamp((xf * m.mesh.get_aabb()).position, (xf * m.mesh.get_aabb()).end)
			if q.distance_to(eye) > best:
				continue
		var f := m.mesh.get_faces()
		for i in range(0, f.size(), 3):
			best = minf(best, _tri(eye, xf * f[i], xf * f[i + 1], xf * f[i + 2]))
	return best

func _run() -> void:
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var flight: TestFlight = TestFlight.new()
		flight.aircraft_id = entry.id
		flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
		root.add_child(flight)
		await process_frame
		flight.session.sim.set_paused(true)
		var rig: RefCounted = flight._rig
		var meshes: Array = []
		_meshes(flight._airplane.root, meshes)
		var worst := {}
		for view: String in ["chase", "closeup", "orbit"]:
			rig.set_view(view)
			if view == "chase":
				rig.chase.zoom = rig.CHASE_ZOOM_MIN
			var poses := 1 if view != "orbit" else 12
			var best := INF
			var near := 0.0
			for k in poses:
				if view == "orbit":
					rig.orbit.distance = rig.orbit.MIN_SPANS * rig._span
					rig.orbit.azimuth_deg = -180.0 + 30.0 * k
					rig.orbit.elevation_deg = [-20.0, 0.0, 45.0][k % 3]
				flight._process(1.0 / 60.0)
				var d := _nearest(meshes, flight._camera.global_position)
				if d < best:
					best = d
					near = flight._camera.near
			worst[view] = "%.2f m (near %.2f)" % [best, near]
		print("AIRFRAME %-28s span %.2f  %s" % [entry.id, rig._span, str(worst)])
		flight.free()
		await process_frame
	quit(0)
