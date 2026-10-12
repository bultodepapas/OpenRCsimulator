# VQ-04a regression checks: mesh-derived projection, bounds, collection and lifecycle.
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_projected_shadow.gd
extends SceneTree

const Projected := preload("res://render/projected_shadow.gd")
const Shadow := preload("res://render/shadow.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")

const GROUND_DATUM := 0.05
const EPSILON := 0.0001

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near_vec2(a: Vector2, b: Vector2, tolerance: float = EPSILON) -> bool:
	return a.distance_to(b) <= tolerance


func _near_transform(a: Transform3D, b: Transform3D, tolerance: float = EPSILON) -> bool:
	return a.origin.distance_to(b.origin) <= tolerance and a.basis.is_equal_approx(b.basis)


func _ray_to_ground(point: Vector3, direction: Vector3) -> Vector2:
	# Independent ray-plane intersection: point - t * direction, where y reaches 0.
	var t := point.y / direction.y
	var hit := point - direction * t
	return Vector2(hit.x, hit.z)


func _triangle_mesh(points: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _new_mesh(parent: Node3D, name: String, points: PackedVector3Array) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = _triangle_mesh(points)
	parent.add_child(instance)
	return instance


func _make_fixture(name: String, origin: Vector3 = Vector3.ZERO) -> Dictionary:
	var model := Node3D.new()
	model.name = name
	model.position = origin

	# Asymmetric visible surface with distinct offsets at each vertex.
	var visible_frame := Node3D.new()
	visible_frame.name = "VisibleFrame"
	visible_frame.transform = Transform3D(Basis.from_euler(Vector3(0.13, -0.21, 0.31)), Vector3(0.8, 0.4, -1.2))
	model.add_child(visible_frame)
	var points := PackedVector3Array([
		Vector3(-0.6, 0.15, -1.4),
		Vector3(1.9, 0.8, 0.3),
		Vector3(0.25, 1.55, 2.2),
	])
	var visible_mesh := _new_mesh(visible_frame, "VisibleSurface", points)
	visible_mesh.position = Vector3(0.35, -0.2, 0.7)

	# Hidden content beneath a hidden ancestor must not leak into the merged silhouette.
	var hidden_frame := Node3D.new()
	hidden_frame.name = "HiddenFrame"
	hidden_frame.visible = false
	hidden_frame.position = Vector3(14.0, 8.0, -11.0)
	model.add_child(hidden_frame)
	_new_mesh(hidden_frame, "HiddenSurface", PackedVector3Array([
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 1),
	]))

	# Propeller descendants are intentionally excluded to avoid a frozen blade streak.
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(-9.0, 3.0, 12.0)
	model.add_child(propeller)
	var propeller_mount := Node3D.new()
	propeller_mount.name = "Mount"
	propeller.add_child(propeller_mount)
	_new_mesh(propeller_mount, "Blade", PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 6, 0.4), Vector3(0.5, 0, 0),
	]))

	return {
		"model": model,
		"visible_frame": visible_frame,
		"visible_mesh": visible_mesh,
		"visible_points": points,
		"hidden_frame": hidden_frame,
		"propeller": propeller,
	}


func _test_independent_projection_and_datum() -> void:
	var direction := Vector3(0.6, 0.8, -0.3)
	var point := Vector3(2.4, 3.0, -1.5)
	var expected := _ray_to_ground(point, direction)
	_check("light ray hits y=0 at independently calculated x/z",
		_near_vec2(Projected.project(point, direction), expected),
		"got %s expected %s" % [Projected.project(point, direction), expected])

	var fixture := _make_fixture("DatumFixture", Vector3(4.0, 3.5, -6.0))
	var model := fixture.model as Node3D
	model.transform = Transform3D(Basis.from_euler(Vector3(-0.18, 0.37, 0.29)), Vector3(4.0, 3.5, -6.0))
	var shape: Dictionary = Projected.collect(model)
	_check("datum fixture has collected geometry", not shape.is_empty())
	if shape.is_empty():
		model.free()
		return

	var host := Node3D.new()
	root.add_child(host)
	host.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(3, 0, 7))
	host.add_child(model)
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var projected := carrier.get_node_or_null("ProjectedShadow") as Node
	_check("bind creates projected shadow node", projected != null)
	if projected == null:
		host.free()
		return

	var renderer := projected as Node
	renderer.call("refresh", 5.0, Vector3(0.31, 0.91, -0.24).normalized(), 0.6, true)
	var receiver := renderer.get("receiver") as MeshInstance3D
	var mask_material := renderer.get("mask_material") as ShaderMaterial
	var frame_center: Vector2 = mask_material.get_shader_parameter("frame_center")
	var root_at_datum := model.global_transform.origin - Vector3(0.0, GROUND_DATUM, 0.0)
	var direction_for_datum := Vector3(0.31, 0.91, -0.24).normalized()
	var expected_root_shadow := _ray_to_ground(root_at_datum, direction_for_datum)
	var receiver_origin := Vector2(receiver.transform.origin.x, receiver.transform.origin.z)
	_check("receiver origin separates mesh-local offset from model datum",
		_near_vec2(receiver_origin - frame_center, expected_root_shadow),
		"got %s expected %s" % [receiver_origin - frame_center, expected_root_shadow])
	_check("receiver sits on the configured ground datum",
		absf(receiver.transform.origin.y - GROUND_DATUM) <= EPSILON,
		str(receiver.transform.origin.y))
	host.free()


func _test_collection_excludes_hidden_and_propeller() -> void:
	var fixture := _make_fixture("CollectionFixture")
	var model := fixture.model as Node3D
	var shape: Dictionary = Projected.collect(model)
	_check("synthetic collection returns one merged surface",
		not shape.is_empty() and shape.mesh.get_surface_count() == 1)
	_check("hidden and propeller meshes are excluded",
		shape.get("triangles", 0) == 1,
		"collected triangles=%s" % shape.get("triangles", -1))

	if not shape.is_empty():
		var arrays: Array = shape.mesh.surface_get_arrays(0)
		var merged: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var frame: Node3D = fixture.visible_frame
		var mesh: MeshInstance3D = fixture.visible_mesh
		var local_to_model: Transform3D = frame.transform * mesh.transform
		var source_points: PackedVector3Array = fixture.visible_points
		var expected_first := local_to_model * source_points[0]
		_check("merged vertices preserve descendant transforms",
			merged.size() == 3 and merged[0].distance_to(expected_first) <= EPSILON,
			"got %s expected %s" % [merged[0] if not merged.is_empty() else Vector3.INF, expected_first])
		var expected_bounds := AABB(merged[0], Vector3.ZERO)
		for vertex: Vector3 in merged:
			expected_bounds = expected_bounds.expand(vertex)
		_check("bounds contain only the visible asymmetric mesh",
			shape.bounds.position.distance_to(expected_bounds.position) <= EPSILON
				and shape.bounds.size.distance_to(expected_bounds.size) <= EPSILON,
			"got %s expected %s" % [shape.bounds, expected_bounds])
	model.free()


func _test_conservative_framing() -> void:
	var fixture := _make_fixture("FramingFixture")
	var shape: Dictionary = Projected.collect(fixture.model)
	if shape.is_empty():
		_check("framing fixture collected", false)
		fixture.model.free()
		return

	var low_sun := Vector3(0.994, 0.105, -0.02).normalized() # About six degrees above the horizon.
	var cases: Array[Dictionary] = [
		{"name": "bank", "basis": Basis.from_euler(Vector3(0.08, -0.22, deg_to_rad(48.0))), "light": Vector3.UP, "blur": 0.08},
		{"name": "knife edge", "basis": Basis.from_euler(Vector3(-0.12, 0.18, deg_to_rad(89.5))), "light": Vector3.UP, "blur": 0.16},
		{"name": "inverted", "basis": Basis.from_euler(Vector3(0.05, 0.39, PI)), "light": Vector3.UP, "blur": 0.22},
		{"name": "low sun", "basis": Basis.from_euler(Vector3(-0.09, -0.34, deg_to_rad(63.0))), "light": low_sun, "blur": 0.40},
	]

	for pose: Dictionary in cases:
		var bounds: AABB = shape.bounds
		var basis: Basis = pose.basis
		var direction: Vector3 = pose.light
		var blur: float = pose.blur
		var frame: Rect2 = Projected.framing(bounds, basis, direction, blur)
		var required_padding := blur + 0.04
		var smallest_padding := INF
		var right := frame.position.x + frame.size.x
		var bottom := frame.position.y + frame.size.y
		for corner in 8:
			var transformed := basis * bounds.get_endpoint(corner)
			var projected := _ray_to_ground(transformed, direction)
			smallest_padding = minf(smallest_padding, projected.x - frame.position.x)
			smallest_padding = minf(smallest_padding, right - projected.x)
			smallest_padding = minf(smallest_padding, projected.y - frame.position.y)
			smallest_padding = minf(smallest_padding, bottom - projected.y)
		_check("%s frame contains every transformed corner plus blur margin" % pose.name,
			is_finite(smallest_padding) and smallest_padding + EPSILON >= required_padding,
			"padding %.6f, required %.6f, frame %s" % [smallest_padding, required_padding, frame])
	fixture.model.free()


func _hinge_node(value: Variant) -> Node3D:
	if value is Node3D:
		return value as Node3D
	if value is Dictionary:
		return value.get("node") as Node3D
	return null


func _test_neutral_geometry_on_catalog_models() -> void:
	var ids: Array[String] = [
		AirplaneBuilder.STIK_ID,
		AirplaneBuilder.EXTRA_ID,
		AirplaneBuilder.P51_ID,
		AirplaneBuilder.AVANTI_ID,
		AirplaneBuilder.TIMBER_ID,
	]
	for id: String in ids:
		var airplane: Dictionary = AirplaneBuilder.build(id)
		var model := airplane.get("root") as Node3D
		_check("%s builder returned a root" % id, model != null)
		if model == null:
			continue
		root.add_child(model)

		var before: Dictionary = {}
		var hinges: Dictionary = airplane.get("hinges", {})
		for key: String in hinges:
			var hinge := _hinge_node(hinges[key])
			if hinge != null:
				before[key] = hinge.transform
		var neutral := Commands.neutral_commands()
		AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(neutral))
		var stayed_neutral := true
		for key: String in before:
			var hinge := _hinge_node(hinges[key])
			if hinge == null or not _near_transform(before[key], hinge.transform):
				stayed_neutral = false
		_check("%s accepts neutral controls without moving its rest geometry" % id, stayed_neutral)

		var shape: Dictionary = Projected.collect(model)
		var valid_geometry := not shape.is_empty()
		if valid_geometry:
			var box: AABB = shape.bounds
			valid_geometry = shape.mesh.get_surface_count() == 1 \
				and int(shape.triangles) > 0 \
				and is_finite(box.position.x) and is_finite(box.position.y) and is_finite(box.position.z) \
				and box.size.length() > 0.1
		_check("%s produces one finite merged neutral silhouette" % id, valid_geometry,
			"triangles=%s bounds=%s" % [shape.get("triangles", 0), shape.get("bounds", AABB())])
		model.free()


func _test_binding_lifecycle_and_hidden_updates() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var fixture_a := _make_fixture("SourceA", Vector3(1.0, 2.0, 3.0))
	var fixture_b := _make_fixture("SourceB", Vector3(-4.0, 5.0, 2.0))
	var model_a: Node3D = fixture_a.model
	var model_b: Node3D = fixture_b.model
	host.add_child(model_a)
	host.add_child(model_b)
	var carrier := Shadow.create(host)

	Shadow.bind_model(carrier, model_a)
	var first := carrier.get_node_or_null("ProjectedShadow") as Node
	_check("initial bind captures first source",
		first != null and first.get("source") == model_a)
	if first == null:
		host.free()
		return
	var first_viewport := first.get("viewport") as SubViewport
	_check("initial viewport starts disabled until a visible refresh",
		first_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	first.call("refresh", 2.0, Vector3.UP, 0.5, true)
	_check("visible refresh schedules one mask redraw",
		first_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE
			and (first.get("receiver") as MeshInstance3D).visible)

	Shadow.bind_model(carrier, model_b)
	var second := carrier.get_node_or_null("ProjectedShadow") as Node
	_check("swap rebinds to second source and retires old node",
		second != null and second != first and second.get("source") == model_b
			and first.is_queued_for_deletion())
	if second == null:
		host.free()
		return

	Shadow.bind_model(carrier, model_b)
	var rebound := carrier.get_node_or_null("ProjectedShadow") as Node
	_check("rebind replaces rather than duplicates the projected node",
		rebound != null and rebound != second and second.is_queued_for_deletion()
			and carrier.get_children().filter(func(child: Node) -> bool: return child.name == "ProjectedShadow").size() == 1)
	if rebound == null:
		host.free()
		return

	rebound.call("refresh", 3.0, Vector3.UP, 0.5, false)
	var viewport := rebound.get("viewport") as SubViewport
	var receiver := rebound.get("receiver") as MeshInstance3D
	_check("zero visibility hides receiver and disables viewport redraw",
		not receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)

	rebound.call("refresh", 3.0, Vector3.UP, 0.5, true)
	_check("visible again schedules a fresh mask after hidden invalidation",
		receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)

	var empty := Node3D.new()
	host.add_child(empty)
	var fallback := Shadow.create(host)
	Shadow.bind_model(fallback, model_a)
	Shadow.bind_model(fallback, empty)
	_check("empty replacement restores legacy fallback", fallback.mesh is PlaneMesh and fallback.get_node_or_null("ProjectedShadow") == null)

	model_b.free()
	rebound.call("refresh", 3.0, Vector3.UP, 0.5, true)
	_check("freed source hides the receiver and disables the viewport",
		not receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	host.free()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_independent_projection_and_datum()
	_test_collection_excludes_hidden_and_propeller()
	_test_conservative_framing()
	_test_neutral_geometry_on_catalog_models()
	_test_binding_lifecycle_and_hidden_updates()
	print("Projected shadow regression: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

