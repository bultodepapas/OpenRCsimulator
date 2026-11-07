extends SceneTree

const Broker := preload("res://ui/home_preview_geometry.gd")
const Lights := preload("res://render/world/aircraft_lights.gd")
const Projected := preload("res://render/projected_shadow.gd")
const DEADLINE_MS := 10000

var checks := 0
var failures := 0


class CallbackTarget extends Node:
	var events: Array

	func _init(sink: Array) -> void:
		events = sink

	func receive(layout: Dictionary) -> void:
		events.append({layout = layout, main = Thread.is_main_thread()})


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var captured := _test_snapshot_and_layout()
	_test_invalid_span()
	_test_shadow_bounds()
	if not captured.is_empty():
		await _test_broker(captured)
	print("home preview geometry: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _mesh(primitive: int, vertices: PackedVector3Array, indices := PackedInt32Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(primitive, arrays)
	return result


func _model() -> Dictionary:
	var model := Node3D.new()
	model.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(30.0, 8.0, -20.0))
	var hinge := Node3D.new()
	hinge.transform = Transform3D(Basis(Vector3.RIGHT, 0.21), Vector3(0.0, 0.4, 0.2))
	model.add_child(hinge)
	var verts := PackedVector3Array([
		Vector3(-2.0, -0.3, -0.5), Vector3(2.0, -0.3, -0.5), Vector3(0.0, -0.3, 0.7),
		Vector3(-2.0, 0.3, -0.5), Vector3(2.0, 0.3, -0.5), Vector3(0.0, 0.3, 0.7),
		Vector3(0.0, 0.0, 1.1),
	])
	var indices := PackedInt32Array([0, 2, 1, 3, 4, 5])
	var lines := PackedVector3Array([Vector3(-0.6, 0.0, -0.2), Vector3(0.6, 0.0, -0.2)])
	var wing_mesh := _mesh(Mesh.PRIMITIVE_TRIANGLES, verts, indices)
	var line_arrays := []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = lines
	wing_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	var wing := MeshInstance3D.new()
	wing.name = "Wing"
	wing.transform = Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 0.75)), Vector3(0.0, 0.1, -0.1))
	wing.mesh = wing_mesh
	hinge.add_child(wing)
	var wing_transform := hinge.transform * wing.transform
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0.0, 0.1, -1.0)
	model.add_child(propeller)
	var prop_verts := PackedVector3Array([Vector3(-0.3, 0.0, 0.0), Vector3(0.3, 0.0, 0.0), Vector3(0.0, 0.4, 0.0)])
	var prop := MeshInstance3D.new()
	prop.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, prop_verts)
	propeller.add_child(prop)
	var hidden := Node3D.new()
	hidden.visible = false
	hidden.position = Vector3(0.0, 0.8, 0.5)
	model.add_child(hidden)
	var hidden_verts := PackedVector3Array([Vector3(-0.4, 0.0, 0.0), Vector3(0.4, 0.0, 0.0), Vector3(0.0, 0.0, 0.5)])
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, hidden_verts)
	hidden.add_child(hidden_mesh)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.6, 0.7)
	cube.mesh = box
	cube.position = Vector3(0.0, -0.1, 0.4)
	model.add_child(cube)
	var cube_arrays := box.surface_get_arrays(0)
	var cube_indices := PackedInt32Array()
	if cube_arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		cube_indices = cube_arrays[Mesh.ARRAY_INDEX]
	var empty := MeshInstance3D.new()
	model.add_child(empty)
	return {model = model, wing = wing, meshes = [wing, prop, hidden_mesh, cube], transforms = [wing_transform, propeller.transform, hidden.transform, cube.transform],
		surfaces = [
			{vertices = verts, indices = indices, transform = wing_transform, faces = true},
			{vertices = lines, indices = PackedInt32Array(), transform = wing_transform, faces = false},
			{vertices = prop_verts, indices = PackedInt32Array(), transform = propeller.transform, faces = true},
			{vertices = hidden_verts, indices = PackedInt32Array(), transform = hidden.transform, faces = true},
			{vertices = cube_arrays[Mesh.ARRAY_VERTEX], indices = cube_indices, transform = cube.transform, faces = true},
		]}


func _manual_arrays(surfaces: Array) -> Dictionary:
	var points := PackedVector3Array()
	var triangles := PackedVector3Array()
	for surface: Dictionary in surfaces:
		var transformed := PackedVector3Array()
		for vertex: Vector3 in surface.vertices:
			transformed.append((surface.transform as Transform3D) * vertex)
		points.append_array(transformed)
		if surface.faces:
			var indices: PackedInt32Array = surface.indices
			if indices.is_empty():
				triangles.append_array(transformed)
			else:
				for index: int in indices:
					triangles.append(transformed[index])
	return {points = points, triangles = triangles}


func _snapshot_arrays(snapshot: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	var triangles := PackedVector3Array()
	for surface: Dictionary in snapshot.surfaces:
		var transformed := PackedVector3Array()
		for vertex: Vector3 in surface.vertices:
			transformed.append((surface.transform as Transform3D) * vertex)
		if surface.points:
			points.append_array(transformed)
		if surface.faces:
			if surface.indices.is_empty():
				triangles.append_array(transformed)
			else:
				for index: int in surface.indices:
					triangles.append(transformed[index])
	return {points = points, triangles = triangles}


func _near_points(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


## Independent copy of the pre-refactor layout composition, over the synthetic expected streams.
func _baseline_layout(geometry: Dictionary, bounds: AABB, needs_landing: bool) -> Dictionary:
	var points: PackedVector3Array = geometry.points
	var half := Lights.span_half(points)
	if points.is_empty() or not bounds.is_finite() or not is_finite(half) or half <= 0.00001:
		return {valid = false, bounds = bounds}
	var tris: PackedVector3Array = geometry.triangles
	var skins := Lights.wing_skin_lines(tris, half)
	var left := Lights.tip(points, half, -1.0)
	var right := Lights.tip(points, half, 1.0)
	var landing := Vector3.ZERO
	if needs_landing:
		var piece := Lights.wing_piece(tris, -Lights.LANDING_SPAN * half)
		landing = Vector3(0.0, (left.centre.y + right.centre.y) / 2.0, minf(left.leading_z, right.leading_z)) \
			if piece.is_empty() else Vector3(-Lights.LANDING_SPAN * half, float(piece[2]) - 0.003, float(piece[0]) + 0.01)
	return {bounds = bounds, skins = skins, left = left, right = right, belly = Lights.belly_line(tris, bounds), landing = landing}


func _test_snapshot_and_layout() -> Dictionary:
	var fixture := _model()
	var model: Node3D = fixture.model
	var expected := _manual_arrays(fixture.surfaces)
	var synchronous: Dictionary = Lights._geometry_arrays(model)
	_check("synchronous points include transformed indexed, line, propeller, hidden and primitive vertices",
		_near_points(synchronous.points, expected.points))
	_check("synchronous triangles expand indices and omit line primitives",
		_near_points(synchronous.triangles, expected.triangles))
	var all := AABB()
	for i in fixture.meshes.size():
		var transformed: AABB = (fixture.transforms[i] as Transform3D) * (fixture.meshes[i] as MeshInstance3D).get_aabb()
		all = transformed if i == 0 else all.merge(transformed)
	_check("root-local bounds include hidden and propeller meshes", (Lights.bounds(model).all as AABB).is_equal_approx(all))
	var baseline: Dictionary = Lights.prepare_layout(model)
	_check("pure layout agrees with pre-refactor composition", baseline == _baseline_layout(synchronous, all, true))
	var snapshot := Broker.Snapshot.new(model)
	var advances := 0
	while not snapshot.advance(0) and advances < 100:
		advances += 1
	_check("budgeted snapshot completes across multiple advances", snapshot.complete and not snapshot.failed and advances >= 4)
	if snapshot.failed or not snapshot.complete:
		model.free()
		return {}
	_check("snapshot retains each surface independently", snapshot.data.surfaces.size() == fixture.surfaces.size())
	var copied := _snapshot_arrays(snapshot.data)
	_check("snapshot reproduces original ordered points", _near_points(copied.points, expected.points))
	_check("snapshot reproduces original ordered triangle stream", _near_points(copied.triangles, expected.triangles))
	_check("snapshot preserves initial bounds and landing requirement", (snapshot.data.bounds as AABB).is_equal_approx(all) and snapshot.data.needs_landing)
	model.set_meta("light_anchors", {landing = {}})
	var authored := Broker.Snapshot.new(model)
	while not authored.advance(0):
		pass
	var authored_baseline: Dictionary = Lights.prepare_layout(model)
	_check("authored landing suppresses computed fallback", not authored.data.needs_landing and authored_baseline.landing == Vector3.ZERO
		and Broker.compute(authored.data).layout == authored_baseline)
	(fixture.wing as MeshInstance3D).transform = Transform3D(Basis.IDENTITY, Vector3(900.0, 800.0, 700.0))
	((fixture.wing as MeshInstance3D).mesh as ArrayMesh).clear_surfaces()
	(fixture.wing as MeshInstance3D).mesh = null
	model.free()
	var result: Dictionary = Broker.compute(snapshot.data)
	_check("detached snapshot survives model mutation and destruction", result.layout == baseline)
	_check("worker layout also matches independent baseline", result.layout == _baseline_layout(synchronous, all, true))
	_check("worker reports nonnegative elapsed work", int(result.worker_usec) >= 0)
	return {snapshot = snapshot.data, layout = baseline}


func _test_invalid_span() -> void:
	var model := Node3D.new()
	var node := MeshInstance3D.new()
	node.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES,
		PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)]))
	model.add_child(node)
	var snapshot := Broker.Snapshot.new(model)
	while not snapshot.advance(0):
		pass
	model.free()
	_check("zero-span captured model is invalid", not bool(Broker.compute(snapshot.data).layout.get("valid", true)))
	var empty := Node3D.new()
	var empty_snapshot := Broker.Snapshot.new(empty)
	empty_snapshot.advance(0)
	empty.free()
	_check("empty captured model is invalid", not bool(Broker.compute(empty_snapshot.data).layout.get("valid", true)))


func _old_bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		box = box.expand(points[i])
	return box


func _check_shadow_oracle(label: String, shape: Dictionary) -> void:
	_check(label + " produces a shadow", not shape.is_empty())
	if shape.is_empty():
		return
	var stream: PackedVector3Array = shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var actual: AABB = shape.bounds
	var expected := _old_bounds(stream) if not stream.is_empty() else AABB()
	var matched := not stream.is_empty() and actual.is_equal_approx(expected)
	for axis in 3:
		if expected.size[axis] <= 0.00001:
			matched = matched and actual.position[axis] == expected.position[axis] and actual.size[axis] == expected.size[axis]
	_check(label + " uses the original scalar expanded bounds", matched)
	if not matched and not stream.is_empty():
		printerr("  actual=%s expected=%s" % [actual, expected])
	_check(label + " preserves triangle count", int(shape.triangles) == stream.size() / 3)


func _test_shadow_bounds() -> void:
	var model := Node3D.new()
	model.position = Vector3(100.0, 40.0, 30.0)
	var hinge := Node3D.new()
	hinge.transform = Transform3D(Basis(Vector3.UP, 0.37), Vector3(2.0, 0.5, -1.0))
	model.add_child(hinge)
	var vertices := PackedVector3Array([
		Vector3(-1.0, -1.0, 0.0), Vector3(1.0, -1.0, 0.0), Vector3(0.0, -1.0, 1.0),
		Vector3(-1.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.0), Vector3(0.0, 1.0, 1.0),
	])
	var order := PackedInt32Array([0, 2, 1, 3, 5, 4])
	var wing := MeshInstance3D.new()
	wing.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, vertices, order)
	hinge.add_child(wing)
	var hidden := Node3D.new()
	hidden.visible = false
	hidden.position.x = 1000.0
	model.add_child(hidden)
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, vertices, order)
	hidden.add_child(hidden_mesh)
	var prop := Node3D.new()
	prop.name = "propeller"
	prop.position.x = -1000.0
	model.add_child(prop)
	var prop_mesh := MeshInstance3D.new()
	prop_mesh.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, vertices, order)
	prop.add_child(prop_mesh)
	var full: Dictionary = Projected.collect(model)
	_check_shadow_oracle("indexed transformed shadow", full)
	var expected := PackedVector3Array()
	for index: int in order:
		expected.append(hinge.transform * vertices[index])
	_check("shadow excludes hidden and propeller branches and expands indices",
		not full.is_empty() and _near_points(full.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], expected))
	var clipped: Dictionary = Projected.collect(model, 0.0)
	_check_shadow_oracle("height-cut shadow", clipped)
	_check("cutoff retains only the upper indexed triangle", not clipped.is_empty() and int(clipped.triangles) == 1
		and _near_points(clipped.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], expected.slice(3, 6)))
	_check("cutoff can reject the complete model", Projected.collect(model, INF).is_empty())
	model.free()
	var empty := Node3D.new()
	_check("empty model has no projected shadow", Projected.collect(empty).is_empty())
	empty.free()
	for primitive: PrimitiveMesh in [BoxMesh.new(), SphereMesh.new()]:
		var root_mesh := MeshInstance3D.new()
		root_mesh.mesh = primitive
		_check_shadow_oracle("root primitive " + primitive.get_class(), Projected.collect(root_mesh))
		root_mesh.free()
	var narrow_triangles := [
		PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(1.000001, 1.0, 0.0), Vector3(1.0, 0.0, 1.0)]),
		PackedVector3Array([Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.000001, 0.0), Vector3(0.0, 1.0, 1.0)]),
		PackedVector3Array([Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 1.000001), Vector3(0.0, 1.0, 1.0)]),
	]
	for i in narrow_triangles.size():
		var narrow := MeshInstance3D.new()
		narrow.mesh = _mesh(Mesh.PRIMITIVE_TRIANGLES, narrow_triangles[i])
		_check_shadow_oracle("thin axis %d" % i, Projected.collect(narrow))
		narrow.free()


func _await_idle(broker: Node) -> bool:
	var until := Time.get_ticks_msec() + DEADLINE_MS
	while broker.busy() and Time.get_ticks_msec() < until:
		await process_frame
	return not broker.busy()


func _test_broker(captured: Dictionary) -> void:
	var broker := Broker.new()
	root.add_child(broker)
	var events: Array = []
	var target := CallbackTarget.new(events)
	root.add_child(target)
	_check("empty job is refused", not broker.request({}, Callable(target, "receive")))
	_check("first job accepted", broker.request(captured.snapshot, Callable(target, "receive")))
	_check("broker stays busy and refuses a second job", broker.busy() and not broker.request(captured.snapshot, Callable(target, "receive")))
	var idle: bool = await _await_idle(broker)
	_check("first job finishes", idle)
	_check("completion callback runs exactly once on main with expected layout", events.size() == 1
		and events[0].main and events[0].layout == captured.layout and broker.completed_jobs == 1)
	_check("cancelled job accepted", broker.request(captured.snapshot, Callable(target, "receive")))
	broker.cancel_for(target)
	idle = await _await_idle(broker)
	_check("cancelled job drains without a stale callback", idle and events.size() == 1 and broker.completed_jobs == 2)
	var freed_events: Array = []
	var doomed := CallbackTarget.new(freed_events)
	root.add_child(doomed)
	_check("owner-lifetime job accepted", broker.request(captured.snapshot, Callable(doomed, "receive")))
	doomed.free()
	idle = await _await_idle(broker)
	_check("freed owner receives no callback", idle and freed_events.is_empty() and broker.completed_jobs == 3)
	target.free()
	broker.free()
	var cleanup := Broker.new()
	root.add_child(cleanup)
	var after_free: Array = []
	var cleanup_target := CallbackTarget.new(after_free)
	root.add_child(cleanup_target)
	_check("cleanup job accepted", cleanup.request(captured.snapshot, Callable(cleanup_target, "receive")))
	cleanup.set_process(false)
	var thread: Thread = cleanup._thread
	_check("cleanup uses an owned worker", thread != null)
	if thread != null:
		var until := Time.get_ticks_msec() + DEADLINE_MS
		while thread.is_alive() and Time.get_ticks_msec() < until:
			await process_frame
		_check("worker terminates before cleanup deadline", not thread.is_alive())
		var started := Time.get_ticks_msec()
		cleanup.free()
		var elapsed := Time.get_ticks_msec() - started
		_check("free joins a finished worker within the deadline", not thread.is_started() and elapsed < DEADLINE_MS)
		_check("free clears pending callback", after_free.is_empty())
	else:
		cleanup.free()
	cleanup_target.free()
