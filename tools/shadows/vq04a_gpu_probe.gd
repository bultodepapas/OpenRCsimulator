## Bounded native GPU probe for VQ-04a's 256² silhouette mask.
## Run from the repository root with the pinned Godot 4.7.2 Compatibility build:
## godot --path .tools/vq04a/candidate/app --script C:/DEVELOPMENT/OpenRCsimulator/tools/shadows/vq04a_gpu_probe.gd
extends SceneTree

const Projected := preload("res://render/projected_shadow.gd")
const RESOLUTION := 256
const DATUM_HEIGHT := 0.05
const EDGE_SKIP_PIXELS := 2.5

var failures: Array[String] = []
var model: Node3D
var projected
var child_transform := Transform3D.IDENTITY
var model_points := PackedVector3Array()


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	root.size = Vector2i(720, 720)
	root.msaa_3d = Viewport.MSAA_4X
	var world := Node3D.new()
	root.add_child(world)
	var root_camera := Camera3D.new()
	root_camera.position = Vector3(0.0, 45.0, -30.0)
	root_camera.rotation_degrees.x = -90.0
	world.add_child(root_camera)
	root_camera.current = true

	model = Node3D.new()
	model.name = "ProbeAircraft"
	model.transform = Transform3D(_basis_a(), Vector3(12.0, 7.0, -16.0))
	world.add_child(model)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "AsymmetricTriangles"
	child_transform = Transform3D(Basis.from_euler(Vector3(0.19, -0.31, 0.17)),
		Vector3(4.2, 1.3, -3.6))
	mesh_instance.transform = child_transform
	mesh_instance.mesh = _make_mesh()
	model.add_child(mesh_instance)
	model_points = _make_model_local_points()

	var shape: Dictionary = Projected.collect(model)
	_check(shape.has("mesh") and shape.has("bounds"), "collector returns a merged mesh and bounds")
	_check(int(shape.get("triangles", 0)) == 2, "collector keeps both synthetic triangles")
	if not shape.has("mesh") or not shape.has("bounds"):
		_finish()
		return
	_check(_aabb_close(shape.bounds, _bounds_from_points(model_points)),
		"collector preserves the mesh's off-origin datum")

	projected = Projected.new()
	world.add_child(projected)
	projected.setup(model, shape)
	await process_frame

	var height := 3.25
	var direction_a := Vector3(0.21, 0.91, 0.36).normalized()
	var basis_a := _basis_a()
	model.global_transform = Transform3D(basis_a, Vector3(12.0, 7.0, -16.0))
	projected.refresh(height, direction_a, 0.75, true)
	_check(projected.receiver.visible, "receiver activates")
	_check(projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"initial pose schedules one mask render")
	await _wait_for_draw()
	var image_a: Image = projected.viewport.get_texture().get_image()
	if image_a.is_empty():
		_check(false, "initial mask readback is nonempty")
		_finish()
		return
	_check(_image_has_size(image_a), "initial mask is 256 by 256")
	var reference_a := _reference(basis_a, direction_a, height)
	_check_mask(image_a, reference_a, "pose A")
	_check_border_clear(image_a, "pose A")
	_check_receiver_anchor(basis_a, direction_a, reference_a, "pose A")

	projected.refresh(height, direction_a, 0.75, false)
	_check(not projected.receiver.visible, "hidden state disables the receiver")
	_check(projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"hidden state disables mask updates")
	await _wait_for_draw()
	var hidden_image: Image = projected.viewport.get_texture().get_image()
	_check_images_same(image_a, hidden_image, "hidden state keeps the cached mask")

	projected.refresh(height, direction_a, 0.75, true)
	_check(projected.receiver.visible, "reactivation shows the receiver")
	_check(projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"reactivation schedules a fresh mask render")
	await _wait_for_draw()
	var reactivated_image: Image = projected.viewport.get_texture().get_image()
	_check_images_same(image_a, reactivated_image, "reactivated mask matches pose A")

	var basis_b := Basis.from_euler(Vector3(-0.29, -0.53, 0.46))
	var direction_b := Vector3(-0.48, 0.78, 0.41).normalized()
	model.global_transform = Transform3D(basis_b, Vector3(12.0, 7.0, -16.0))
	projected.refresh(height, direction_b, 0.75, true)
	_check(projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"basis and sun change schedules a new mask render")
	await _wait_for_draw()
	var image_b: Image = projected.viewport.get_texture().get_image()
	if image_b.is_empty():
		_check(false, "changed-pose mask readback is nonempty")
	else:
		var changed := _changed_pixels(image_a, image_b)
		_check(changed > 80, "basis and sun change replaces the cached mask (%d pixels changed)" % changed)
		var reference_b := _reference(basis_b, direction_b, height)
		_check_mask(image_b, reference_b, "pose B")
		_check_border_clear(image_b, "pose B")
		_check_receiver_anchor(basis_b, direction_b, reference_b, "pose B")

	_finish()


func _basis_a() -> Basis:
	return Basis.from_euler(Vector3(0.19, 0.34, -0.27))


func _make_mesh() -> ArrayMesh:
	var a := Vector3(-1.8, 0.4, -1.2)
	var b := Vector3(1.1, 1.1, 1.5)
	var c := Vector3(2.4, 0.2, -0.5)
	# A strictly interior, deliberately smaller triangle tests overlapping coverage.
	var d := a * 0.50 + b * 0.25 + c * 0.25
	var e := a * 0.20 + b * 0.55 + c * 0.25
	var f := a * 0.20 + b * 0.20 + c * 0.60
	var vertices := PackedVector3Array([a, b, c, d, e, f])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_model_local_points() -> PackedVector3Array:
	var arrays := _make_mesh().surface_get_arrays(0)
	var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points := PackedVector3Array()
	for vertex in local_vertices:
		points.append(child_transform * vertex)
	return points


func _reference(basis: Basis, direction: Vector3, height: float) -> Dictionary:
	var box := _bounds_from_points(model_points)
	var projected_corners := PackedVector2Array()
	for corner_index in range(8):
		var corner := Vector3(
			box.end.x if (corner_index & 1) != 0 else box.position.x,
			box.end.y if (corner_index & 2) != 0 else box.position.y,
			box.end.z if (corner_index & 4) != 0 else box.position.z)
		projected_corners.append(_cpu_project(basis * corner, direction))
	var minimum := projected_corners[0]
	var maximum := projected_corners[0]
	for corner in projected_corners:
		minimum.x = minf(minimum.x, corner.x)
		minimum.y = minf(minimum.y, corner.y)
		maximum.x = maxf(maximum.x, corner.x)
		maximum.y = maxf(maximum.y, corner.y)
	var blur := clampf(0.018 + maxf(height, 0.0) * 0.0093, 0.018, 0.45)
	var side := maxf(maximum.x - minimum.x, maximum.y - minimum.y) + 2.0 * (blur + 0.04)
	side = maxf(side, 0.1)
	var center := (minimum + maximum) * 0.5
	var polygons: Array[PackedVector2Array] = []
	for first in range(0, model_points.size(), 3):
		var polygon := PackedVector2Array()
		for index in range(first, first + 3):
			polygon.append(_cpu_project(basis * model_points[index], direction))
		polygons.append(polygon)
	return {center = center, side = side, polygons = polygons}


func _cpu_project(point: Vector3, direction: Vector3) -> Vector2:
	# Independent CPU oracle: intersect the sun ray with the y=0 plane.
	var ray_scale := point.y / maxf(direction.y, 0.05)
	return Vector2(point.x - direction.x * ray_scale, point.z - direction.z * ray_scale)


func _check_mask(image: Image, reference: Dictionary, label: String) -> void:
	var side: float = reference.side
	var center: Vector2 = reference.center
	var polygons: Array[PackedVector2Array] = reference.polygons
	var pixel_world := side / float(RESOLUTION)
	var skipped := 0
	var inside := 0
	var outside := 0
	var mismatches := 0
	var overlap_samples := 0
	var overlap_bad := 0
	var flip_sensitive := 0
	for y in range(0, RESOLUTION, 2):
		for x in range(0, RESOLUTION, 2):
			# Image rows increase with +world Z. Reversing this term must fail the
			# asymmetric specimen's reflected-orientation sensitivity check below.
			var point := Vector2(center.x + (float(x) + 0.5 - RESOLUTION * 0.5) * pixel_world,
				center.y + (float(y) + 0.5 - RESOLUTION * 0.5) * pixel_world)
			var reflected := Vector2(point.x, 2.0 * center.y - point.y)
			if _distance_to_edges(point, polygons) < EDGE_SKIP_PIXELS * pixel_world:
				skipped += 1
				continue
			var memberships := _memberships(point, polygons)
			var expected := memberships > 0
			var alpha := image.get_pixel(x, y).a
			var actual := alpha >= 0.5
			if expected:
				inside += 1
				if alpha < 0.98:
					mismatches += 1
			else:
				outside += 1
				if alpha > 0.02:
					mismatches += 1
			if memberships >= 2:
				overlap_samples += 1
				if alpha < 0.98:
					overlap_bad += 1
			if _distance_to_edges(reflected, polygons) >= EDGE_SKIP_PIXELS * pixel_world:
				var reflected_expected := _memberships(reflected, polygons) > 0
				if expected != reflected_expected and actual == expected:
					flip_sensitive += 1
	_check(inside > 40, "%s has enough interior oracle samples (%d)" % [label, inside])
	_check(outside > 100, "%s has enough exterior oracle samples (%d)" % [label, outside])
	_check(skipped > 0, "%s excludes edge-adjacent samples" % label)
	_check(mismatches == 0, "%s GPU alpha matches CPU triangle rasterization (%d mismatches)" % [label, mismatches])
	_check(overlap_samples > 10 and overlap_bad == 0,
		"%s overlapping triangles stay opaque (%d samples, %d bad)" % [label, overlap_samples, overlap_bad])
	_check(flip_sensitive > 20,
		"%s rejects a vertically flipped +Z mapping (%d distinguishing samples)" % [label, flip_sensitive])


func _memberships(point: Vector2, polygons: Array[PackedVector2Array]) -> int:
	var count := 0
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			count += 1
	return count


func _distance_to_edges(point: Vector2, polygons: Array[PackedVector2Array]) -> float:
	var nearest := INF
	for polygon in polygons:
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var edge := b - a
			var length_squared := edge.length_squared()
			var t := clampf((point - a).dot(edge) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
			nearest = minf(nearest, point.distance_to(a + edge * t))
	return nearest


func _check_border_clear(image: Image, label: String) -> void:
	var nonclear := 0
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			if x >= 2 and x < RESOLUTION - 2 and y >= 2 and y < RESOLUTION - 2:
				continue
			if image.get_pixel(x, y).a > 0.02:
				nonclear += 1
	_check(nonclear == 0, "%s viewport border remains alpha-clear (%d nonclear pixels)" % [label, nonclear])


func _check_receiver_anchor(basis: Basis, direction: Vector3, reference: Dictionary, label: String) -> void:
	var pose_origin := Vector3(12.0, 7.0, -16.0)
	var ground_projection := _cpu_project(pose_origin - Vector3(0.0, DATUM_HEIGHT, 0.0), direction)
	var expected := Vector3(ground_projection.x + reference.center.x, DATUM_HEIGHT,
		ground_projection.y + reference.center.y)
	var actual: Vector3 = projected.receiver.global_transform.origin
	_check(actual.distance_to(expected) < 0.002,
		"%s receiver stays anchored to the aircraft datum (error %.5f m)" % [label, actual.distance_to(expected)])
	var scale: Vector3 = projected.receiver.global_transform.basis.get_scale()
	_check(absf(scale.x - reference.side) < 0.002 and absf(scale.z - reference.side) < 0.002,
		"%s receiver extent matches the orthographic mask frame" % label)


func _bounds_from_points(points: PackedVector3Array) -> AABB:
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


func _aabb_close(actual: AABB, expected: AABB) -> bool:
	return actual.position.distance_to(expected.position) < 0.0001 and actual.size.distance_to(expected.size) < 0.0001


func _image_has_size(image: Image) -> bool:
	return image.get_width() == RESOLUTION and image.get_height() == RESOLUTION


func _changed_pixels(first: Image, second: Image) -> int:
	if not _image_has_size(first) or not _image_has_size(second):
		return 0
	var changed := 0
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			if absf(first.get_pixel(x, y).a - second.get_pixel(x, y).a) > 0.1:
				changed += 1
	return changed


func _check_images_same(first: Image, second: Image, label: String) -> void:
	var changed := _changed_pixels(first, second)
	_check(changed == 0, "%s has identical cached alpha (%d changed pixels)" % [label, changed])


func _wait_for_draw() -> void:
	for frame in range(1):
		await process_frame
		await RenderingServer.frame_post_draw


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	var report := {
		engine = Engine.get_version_info(),
		gpu = RenderingServer.get_video_adapter_name(),
		renderer = RenderingServer.get_current_rendering_method(),
		probe = "VQ-04a synthetic 256² shadow-mask GPU oracle",
		failures = failures,
		passed = failures.is_empty()
	}
	print(JSON.stringify(report, "\t"))
	quit(0 if failures.is_empty() else 1)
