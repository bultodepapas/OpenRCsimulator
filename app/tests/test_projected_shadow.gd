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


## SA-19/SA-05: tagged propeller blades are live parts (spinner excluded); natively non-casting meshes stay out.
func _test_rotor_blades_and_native_casting() -> void:
	var fixture := _make_fixture("RotorFixture")
	var model := fixture.model as Node3D
	var propeller := fixture.propeller as Node3D
	var spinner := _new_mesh(propeller, "Spinner", PackedVector3Array([
		Vector3(-0.3, -0.3, 0), Vector3(0.3, -0.3, 0), Vector3(0, 0.3, 0.6)]))
	# A round hub at 0.4 of the tip radius: its bounding-box corner reaches 0.53 R, its real vertices 0.4 R.
	var hub := _new_mesh(propeller, "Hub", PackedVector3Array([
		Vector3(2.4, 0, 0.1), Vector3(-1.2, 2.078, 0.1), Vector3(-1.2, -2.078, 0.1)]))
	var cone := _new_mesh(model, "LightCone", PackedVector3Array([
		Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 9)]))
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blade := propeller.get_node("Mount/Blade") as MeshInstance3D
	_check("an untagged propeller still stays out", Projected.collect(model).get("triangles", 0) == 1)
	Projected.tag_articulation({propeller = propeller})
	_check("tag_rotor tags the blade, not the short spinner or a round hub (real vertex radii, not box corners)",
		bool(blade.get_meta(Projected.ARTICULATED_META, false))
		and not bool(spinner.get_meta(Projected.ARTICULATED_META, false))
		and not bool(hub.get_meta(Projected.ARTICULATED_META, false)))
	blade.visible = false # blurred when the shadow binds: still a part, shown live once the blur shows it again
	var shape: Dictionary = Projected.collect(model)
	var parts: Array = shape.get("parts", [])
	# Two triangles: the visible surface and the blade; the spinner and the non-casting cone are out.
	_check("SA-19/SA-05: the blade enters only as its own live part; spinner and non-casting cone stay out",
		shape.get("triangles", 0) == 2 and parts.size() == 1 and model.get_node(parts[0].path) == blade,
		"triangles=%s parts=%d" % [shape.get("triangles", -1), parts.size()])
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check("SA-05: a shadows-only mesh casts", Projected.collect(model).get("triangles", 0) == 3)
	model.free()


## SA-05: per-surface native caster semantics, as measured on Forward+ and Compatibility (2026-11-18).
func _test_surface_casting_semantics() -> void:
	var model := Node3D.new()
	var mesh := ArrayMesh.new()
	var opaque_points := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	var glass_points := PackedVector3Array([Vector3(5, 1, 5), Vector3(6, 1, 5), Vector3(5, 1, 6)])
	for points: PackedVector3Array in [opaque_points, glass_points]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	model.add_child(instance)
	var opaque := StandardMaterial3D.new()
	opaque.albedo_color.a = 0.4 # alpha below one with transparency disabled still casts
	instance.set_surface_override_material(0, opaque)
	var cases := {}
	var blend := StandardMaterial3D.new()
	blend.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blend.albedo_color.a = 0.45
	cases["blend"] = [blend, false]
	var prepass := blend.duplicate() as StandardMaterial3D
	prepass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	cases["depth pre-pass"] = [prepass, true]
	var scissor := StandardMaterial3D.new()
	scissor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	scissor.albedo_color.a = 0.0
	cases["scissor at alpha 0"] = [scissor, false]
	var hashed := StandardMaterial3D.new()
	hashed.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	hashed.albedo_color.a = 0.8
	cases["hash at alpha 0.8"] = [hashed, true]
	var shader_cases := {
		"void fragment() { ALBEDO = vec3(1.0); ALPHA = 1.0; }": false,
		"void fragment() { ALBEDO = vec3(1.0); }": true,
		"render_mode depth_prepass_alpha;\nvoid fragment() { ALPHA = 0.5; }": true,
		"void fragment() {\n\t// ALPHA = 0.5;\n\tALBEDO = vec3(1.0);\n}": true,
		"void fragment() {\n\t/* a block\n\t * ALPHA = 0.0; */\n\tALBEDO = vec3(1.0);\n}": true,
		"void fragment() { float a = 1.0 / 2.0; ALPHA *= a; }": false,
		"void fragment() { if (ALPHA == 1.0) { ALBEDO = vec3(1.0); } }": true,
		"render_mode blend_add;\nvoid fragment() { ALBEDO = vec3(1.0); }": false,
	}
	for code: String in shader_cases:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = Shader.new()
		shader_material.shader.code = "shader_type spatial;\n" + code
		cases["shader: " + code.replace("\n", " ")] = [shader_material, shader_cases[code]]
	for label: String in cases:
		instance.set_surface_override_material(1, cases[label][0])
		var expected: bool = cases[label][1]
		var shape := Projected.collect(model)
		_check("SA-05: %s %s" % [label, "casts" if expected else "casts nothing"],
			Projected.surface_casts(instance, 1) == expected and int(shape.get("triangles", 0)) == (2 if expected else 1),
			"triangles=%s" % shape.get("triangles", -1))
	instance.set_surface_override_material(1, blend)
	var faces := Projected.casting_faces(instance)
	_check("SA-05: a blended surface's faces are dropped in get_faces() order", faces == opaque_points)
	instance.set_surface_override_material(0, blend)
	_check("SA-05: a fully blended mesh is not an aircraft caster", Projected.mesh_entries(model).is_empty()
		and not Projected.mesh_entries(model, false).is_empty())
	model.free()


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
		"sebart-avanti-s-a200-p100rx",
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


## Audit SA-07 counterexample: 0.2° of pitch on a 6 m model at a 12° sun moves its end ~49 mm on the ground,
## which the old 0.25° angular rule reused. The bounded rule must redraw it and still reuse a sub-tolerance change.
func _test_error_bounded_reuse() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	host.add_child(model)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.4, 6.0)
	var projected := Projected.new()
	host.add_child(projected)
	projected.setup(model, {mesh = mesh, bounds = mesh.get_aabb(), triangles = 12}, 256, Viewport.MSAA_DISABLED)
	var sun := Vector3(0.0, sin(deg_to_rad(12.0)), cos(deg_to_rad(12.0)))
	projected.refresh(0.0, sun, 0.5, true)
	var drawn_basis := model.global_basis
	var tolerance: float = projected.reuse_tolerance(0.018, (projected._last_signature[2] as Rect2).size.x)
	model.rotation.x = deg_to_rad(0.2)
	var end_shift := _ray_to_ground(model.global_basis * Vector3(0, 0, 3), sun).distance_to(
		_ray_to_ground(drawn_basis * Vector3(0, 0, 3), sun))
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projected.refresh(0.0, sun, 0.5, true)
	_check("SA-07: a 0.2° change that moves the 6 m model's end %.1f mm redraws at a 12° sun" % (end_shift * 1000.0),
		end_shift > 0.045 and end_shift > tolerance
		and projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "tolerance %.4f" % tolerance)
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	model.rotation.x = deg_to_rad(0.2 + 0.02)
	projected.refresh(0.0, sun, 0.5, true)
	_check("SA-07: a sub-tolerance 0.02° change reuses the mask",
		projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_check("SA-07: the blur arm is capped at REUSE_MAX_M for a fine mask",
		projected.reuse_tolerance(0.45, 1.0) == Projected.REUSE_MAX_M)
	_check("SA-07: a coarse mask never redraws for less than one texel",
		is_equal_approx(projected.reuse_tolerance(0.018, 40.0), 40.0 / 256.0))
	host.free()


## SA-11: a releasing (field) projector holds no full render target while hidden and redraws when shown again.
func _test_release_when_hidden() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	host.add_child(model)
	var mesh := BoxMesh.new()
	var projected := Projected.new()
	projected.release_when_hidden = true
	host.add_child(projected)
	projected.setup(model, {mesh = mesh, bounds = mesh.get_aabb(), triangles = 12}, 512, Viewport.MSAA_DISABLED)
	_check("SA-11: a releasing projector starts without a full target", projected.viewport.size == Projected.RELEASED_SIZE)
	projected.refresh(0.0, Vector3.UP, 0.4, true)
	var drawn := projected.redraw_count
	_check("SA-11: showing allocates the full target and draws", projected.viewport.size == Vector2i(512, 512)
		and drawn == 1 and projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	projected.refresh(0.0, Vector3.UP, 0.4, false)
	_check("SA-11: hiding releases the target", projected.viewport.size == Projected.RELEASED_SIZE)
	projected.refresh(0.0, Vector3.UP, 0.4, true)
	_check("SA-11: showing again reallocates and redraws the same pose", projected.viewport.size == Vector2i(512, 512)
		and projected.redraw_count == drawn + 1)
	var kept := Projected.new()
	host.add_child(kept)
	kept.setup(model, {mesh = mesh, bounds = mesh.get_aabb(), triangles = 12}, 256, Viewport.MSAA_DISABLED)
	kept.refresh(0.0, Vector3.UP, 0.4, false)
	_check("SA-11: the aircraft cue keeps its target while hidden", kept.viewport.size == Vector2i(256, 256))
	host.free()


## SA-03: control surfaces and tagged mechanisms follow their live hinge in the projected mask.
func _test_articulated_parts() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	model.name = "airplane"
	host.add_child(model)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.0, 0.2, 2.0)
	body.mesh = body_mesh
	model.add_child(body)
	var hinge := Node3D.new()
	hinge.name = "elevator_hinge"
	hinge.position = Vector3(0, 0, 1)
	model.add_child(hinge)
	var surface := MeshInstance3D.new()
	var surface_mesh := BoxMesh.new()
	surface_mesh.size = Vector3(1.0, 0.02, 0.4)
	surface.mesh = surface_mesh
	surface.position = Vector3(0, 0, 0.2)
	hinge.add_child(surface)
	var canopy_mount := Node3D.new()
	canopy_mount.name = "canopy"
	canopy_mount.set_meta(Projected.ARTICULATED_META, true)
	model.add_child(canopy_mount)
	var canopy := MeshInstance3D.new()
	canopy.mesh = BoxMesh.new()
	canopy.position = Vector3(0, 0.5, -0.5)
	canopy_mount.add_child(canopy)
	var shape := Projected.collect(model)
	var parts: Array = shape.get("parts", [])
	var expected := body_mesh.get_aabb().merge(Transform3D(Basis(), Vector3(0, 0, 1.2)) * surface_mesh.get_aabb()) \
		.merge(Transform3D(Basis(), Vector3(0, 0.5, -0.5)) * (canopy.mesh as BoxMesh).get_aabb())
	_check("SA-03: hinged and tagged meshes become parts; whole-model bounds and triangles are unchanged",
		parts.size() == 2 and int(shape.triangles) == 36 and (shape.bounds as AABB).is_equal_approx(expected)
		and shape.mesh != null and shape.mesh.get_faces().size() == 36, str(shape.bounds))
	_check("SA-03: a cropped (scenery) collection never articulates", not Projected.collect(model, -1.0).has("parts"))
	var projected := Projected.new()
	host.add_child(projected)
	projected.setup(model, shape, 64, Viewport.MSAA_DISABLED)
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	var redraws := projected.redraw_count
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	_check("SA-03: an unchanged pose reuses the mask", projected.redraw_count == redraws
		and projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	hinge.rotation.x = deg_to_rad(35.0)
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	var elevator: Dictionary = {}
	for part: Dictionary in projected._parts:
		if part.node == hinge:
			elevator = part
	_check("SA-03: a 35° hinge deflection redraws the mask with the live hinge transform",
		projected.redraw_count == redraws + 1 and not elevator.is_empty()
		and (elevator.material as ShaderMaterial).get_shader_parameter("part_basis") == hinge.transform.basis
		and (elevator.material as ShaderMaterial).get_shader_parameter("part_origin") == hinge.transform.origin)
	_check("SA-03: parts share the projection uniforms", (elevator.material as ShaderMaterial).get_shader_parameter(
		"frame_size") == projected.mask_material.get_shader_parameter("frame_size"))
	canopy_mount.position = Vector3(0, 0, -0.4)
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	_check("SA-03: a tagged mechanism slide redraws and widens the framing", projected.redraw_count == redraws + 2
		and (projected._last_signature[2] as Rect2).size.y >= 2.0 + 0.4)
	surface.visible = false
	hinge.visible = false
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	_check("SA-03: a hidden part stops casting", projected.redraw_count == redraws + 3
		and not (elevator.proxy as MeshInstance3D).visible)
	hinge.visible = true
	model.remove_child(hinge)
	hinge.free()
	projected.refresh(0.0, Vector3.UP, 0.5, true)
	_check("SA-03: a freed part stays out of the mask", not (elevator.proxy as MeshInstance3D).visible)
	host.free()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_independent_projection_and_datum()
	_test_collection_excludes_hidden_and_propeller()
	_test_rotor_blades_and_native_casting()
	_test_surface_casting_semantics()
	_test_conservative_framing()
	_test_framing_reuse_inputs()
	_test_error_bounded_reuse()
	_test_articulated_parts()
	_test_release_when_hidden()
	_test_neutral_geometry_on_catalog_models()
	_test_binding_lifecycle_and_hidden_updates()
	print("Projected shadow regression: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)



func _test_framing_reuse_inputs() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	host.add_child(model)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3, 0.6, 2)
	var projected := Projected.new()
	host.add_child(projected)
	projected.setup(model, {mesh = mesh, bounds = mesh.get_aabb(), triangles = 12}, 32, Viewport.MSAA_DISABLED)
	var direction := Vector3(0.3, 1, -0.2)
	var height := 3.0
	projected.refresh(height, direction, 0.5, true)
	var first_transform: Transform3D = projected.receiver.transform
	var signature := var_to_bytes(projected._last_signature)
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	model.position = Vector3(4, 3, -2)
	projected.refresh(height, direction, 0.7, true)
	_check("translation and opacity still update without redrawing unchanged framing",
		projected.receiver.transform != first_transform and signature == var_to_bytes(projected._last_signature)
		and projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and projected.receiver.material_override.get_shader_parameter("opacity") == 0.7)
	for change: String in ["basis", "direction", "height", "bounds"]:
		if change == "basis": model.rotation = Vector3(0.2, 0.3, -0.1)
		elif change == "direction": direction = Vector3(-0.5, 0.01, 0.4)
		elif change == "height": height = 12.0
		else: projected.bounds.size.x += 0.125
		projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		projected.refresh(height, direction, 0.5, true)
		var blur := clampf(0.018 + maxf(height, 0.0) * 0.0093, 0.018, 0.45)
		var expected := Projected.framing(projected.bounds, model.global_basis, direction, blur)
		_check("framing invalidates changed " + change,
			projected.mask_material.get_shader_parameter("frame_center") == expected.get_center()
			and projected.mask_material.get_shader_parameter("frame_size") == expected.size.x
			and projected.receiver.material_override.get_shader_parameter("blur_uv") == blur / expected.size.x
			and projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	projected.refresh(100, direction, 0.5, true)
	var capped_signature := var_to_bytes(projected._last_signature)
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projected.refresh(200, direction, 0.5, true)
	_check("height changes above the blur cap retain the same mask framing",
		var_to_bytes(projected._last_signature) == capped_signature
		and projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	# PT1h-R12/SA-07: in flight the attitude changes every frame. Changes the blurred shadow cannot show reuse the
	# drawn mask; the corner shift is measured from the last drawn mask, so small steps cannot accumulate past it.
	height = 3.0
	direction = Vector3(0.3, 1, -0.2) # above the projector's 0.05 grazing clamp, so the ray oracle is exact
	model.rotation = Vector3.ZERO
	projected.refresh(height, direction, 0.5, true)
	var drawn := var_to_bytes(projected._last_signature)
	var tolerance: float = projected.reuse_tolerance(clampf(0.018 + height * 0.0093, 0.018, 0.45),
		(projected._last_signature[2] as Rect2).size.x)
	var redraws: Array[bool] = []
	var predicted: Array[bool] = []
	for step in 40:
		projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var drawn_basis: Basis = projected._last_signature[0]
		var drawn_direction: Vector3 = projected._last_signature[1]
		model.rotate_object_local(Vector3.FORWARD, deg_to_rad(0.5)) # the 32² fixture mask has a ~0.11 m texel
		model.position.x += 0.5
		# Independent corner-shift oracle: ray/plane projections of all eight corners, before and after.
		var worst := 0.0
		for i in 8:
			var corner := projected.bounds.get_endpoint(i)
			var now := model.global_basis * corner
			var then := drawn_basis * corner
			worst = maxf(worst, _ray_to_ground(now, direction).distance_to(_ray_to_ground(then, drawn_direction)))
		predicted.append(worst > tolerance)
		projected.refresh(height, direction, 0.5, true)
		redraws.append(projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	_check("0.5° steps reuse the mask exactly until the corner shift passes the tolerance, then redraw",
		redraws == predicted and redraws.has(true) and not redraws[0] and var_to_bytes(projected._last_signature) != drawn,
		"%s predicted %s tolerance %.4f" % [str(redraws), str(predicted), tolerance])
	var moved_transform: Transform3D = projected.receiver.transform
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	model.position.x += 1.0
	projected.refresh(height + 0.1, direction, 0.5, true) # +0.93 mm of blur
	_check("a reused mask still follows the aircraft and its blur",
		projected.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and projected.receiver.transform.origin.x > moved_transform.origin.x
		and is_equal_approx(projected.receiver.material_override.get_shader_parameter("blur_uv"),
			clampf(0.018 + (height + 0.1) * 0.0093, 0.018, 0.45) / projected._last_signature[2].size.x))
	projected.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	model.scale = Vector3(1.01, 1.01, 1.01)
	projected.refresh(height + 0.1, direction, 0.5, true)
	_check("a scale change is never reused", projected.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	host.free()
