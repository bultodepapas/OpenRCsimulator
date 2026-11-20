extends SceneTree
## Internal mesh/lifecycle checks, not rendered fit, flight or performance qualification.

const Selection := preload("res://workshop/attachment_selection.gd")
const Preview := preload("res://render/attachments/stik_wheel_preview.gd")
const Airplane := preload("res://render/airplane.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ROLES := ["left", "right", "nose"]
const NAMES := ["gear_left", "gear_right", "nosewheel"]

var _checks := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first := Airplane.build(Selection.PILOT_ID)
	var other := Airplane.build(Selection.PILOT_ID)
	_check("two manifest-bound Stik models build", not first.is_empty() and not other.is_empty())
	if first.is_empty() or other.is_empty():
		for built: Dictionary in [first, other]:
			if built.get("root") is Node: built.root.free()
		_finish()
		return
	var source_meshes := _meshes(first)
	var source_arrays: Array = []
	var source_overrides: Array = []
	for node: MeshInstance3D in _nodes(first):
		source_arrays.append(node.mesh.surface_get_arrays(0))
		source_overrides.append(_overrides(node))
	var before := _tree_snapshot(first.root)
	var selected := Selection.original()
	selected.selections.wheels = Selection.TWIN_GROOVE_ID
	var staged := Preview.stage(first, selected, 1.0)
	_check("study stages as preview-only", staged.ok and staged.get("availability") == "preview_only", str(staged.get("errors")))
	if not staged.ok:
		first.root.free()
		other.root.free()
		_finish()
		return
	var handle: Variant = staged.preview
	_check("staging leaves every mesh and node untouched", _meshes(first) == source_meshes and _tree_snapshot(first.root) == before)
	var applied: Dictionary = handle.apply()
	_check("all three replacements publish together", applied.ok and applied.get("geometry_changed", false))
	_check("node identities, parents, transforms and metadata are unchanged", _tree_snapshot(first.root) == before)
	var replacement_meshes := _meshes(first)
	_check("second apply is an idempotent no-op", handle.apply().ok and not handle.apply().geometry_changed
		and _meshes(first) == replacement_meshes)
	_test_geometry(first, other, source_meshes, source_arrays, source_overrides)
	_test_motion(first, other)
	_test_material_isolation(first, other, source_meshes)
	var new_paint := StandardMaterial3D.new()
	new_paint.albedo_color = Color("a0b0c0")
	_nodes(first)[0].set_surface_override_material(2, new_paint)
	_check("restore returns the exact original Mesh resources", handle.restore().ok and _meshes(first) == source_meshes)
	_check("Parts restore preserves a later paint edit", _nodes(first)[0].get_surface_override_material(2) == new_paint)
	_check("second restore is an idempotent no-op", handle.restore().ok and not handle.restore().geometry_changed)
	for cycle in 8:
		var on: Dictionary = handle.apply()
		var same_resources := _meshes(first) == replacement_meshes
		var off: Dictionary = handle.restore()
		_check("repeat apply/restore reuses the bounded meshes: %d" % cycle, on.ok and off.ok
			and same_resources and _meshes(first) == source_meshes)
	var original := Preview.stage(first, Selection.original(), 1.0)
	_check("explicit Original stages a no-op", original.ok and original.preview.apply().ok
		and not original.preview.apply().geometry_changed and _meshes(first) == source_meshes)
	_test_atomic_failures(first, selected, source_meshes)
	_check("the other model retains its original wheel surfaces", _meshes(other) != replacement_meshes
		and _nodes(other)[0].mesh.surface_get_arrays(0) == source_arrays[0])
	first.root.free()
	_check("a freed model refuses further application", not handle.apply().ok)
	other.root.free()
	_finish()


func _test_geometry(first: Dictionary, other: Dictionary, sources: Array, arrays: Array, overrides: Array) -> void:
	var loaded := AircraftData.load_file(str(Catalog.entry(Selection.PILOT_ID).data))
	_check("independent physics contact profile loads", loaded.ok, str(loaded.get("errors")))
	var radii: Dictionary = {}
	if loaded.ok:
		for contact: Dictionary in loaded.model.landing_gear.contacts:
			radii[str(contact.name).trim_prefix("main_")] = float(contact.wheel_radius)
	for index in ROLES.size():
		var node: MeshInstance3D = _nodes(first)[index]
		var mesh := node.mesh as ArrayMesh
		var original: ArrayMesh = sources[index]
		_check(ROLES[index] + " retains four material surfaces", mesh.get_surface_count() == 4)
		_check(ROLES[index] + " retains node paint overrides", _overrides(node) == overrides[index])
		for surface in 4:
			_check("%s surface %d keeps its material role" % [ROLES[index], surface],
				mesh.surface_get_material(surface).resource_name == original.surface_get_material(surface).resource_name)
			_check("%s surface %d owns a distinct material" % [ROLES[index], surface],
				mesh.surface_get_material(surface) != original.surface_get_material(surface)
				and mesh.surface_get_material(surface) != _nodes(other)[index].mesh.surface_get_material(surface))
			if surface > 0:
				_check("%s surface %d hardware buffers and decoded bytes are unchanged" % [ROLES[index], surface],
					_surface_payload(mesh, surface) == _surface_payload(original, surface)
					and var_to_bytes(mesh.surface_get_arrays(surface)) == var_to_bytes(original.surface_get_arrays(surface)))
		var measured := _measure(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		var reference := _measure(arrays[index][Mesh.ARRAY_VERTEX])
		_check(ROLES[index] + " actual tire envelope matches stock", measured.bounds.is_equal_approx(reference.bounds)
			and absf(measured.radius - reference.radius) < 1e-7)
		_check(ROLES[index] + " actual lowest vertex matches the physical radius", radii.has(ROLES[index])
			and absf(measured.bounds.position.y + float(radii.get(ROLES[index], 0.0))) < 1e-7)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(ROLES[index] + " adds only 480 tire triangles", vertices.size() - (arrays[index][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 480 * 3)
		_check(ROLES[index] + " has finite, nondegenerate outward triangles", _valid_tire(mesh))
		_check(ROLES[index] + " has the two measured grooves and full-radius center support",
			_grooves_and_crown(mesh, reference.radius, reference.bounds.size.x))
		_check(ROLES[index] + " leaves the source resource untouched", original.surface_get_arrays(0) == arrays[index])
		print("MEASURE %s radius_m=%.9f width_m=%.9f bottom_m=%.9f tire_triangles=%d" % [
			ROLES[index], measured.radius, measured.bounds.size.x, measured.bounds.position.y, vertices.size() / 3])


func _test_motion(first: Dictionary, other: Dictionary) -> void:
	var poses := [
		{"steer": 0.0, "spin": 0.0, "compression": Vector3.ZERO, "attitude": Vector3.ZERO},
		{"steer": deg_to_rad(30.0), "spin": 0.7, "compression": Vector3(0.0, 0.018, 0.0), "attitude": Vector3.ZERO},
		{"steer": deg_to_rad(-30.0), "spin": 2.2, "compression": Vector3(0.005, 0.04, -0.008), "attitude": Vector3(0.17, 0.0, -0.23)},
	]
	var rest: Dictionary = {}
	for role: String in ROLES:
		rest[role] = first.gear[role].position
	for index in poses.size():
		var pose: Dictionary = poses[index]
		for airplane: Dictionary in [first, other]:
			airplane.root.rotation = pose.attitude
			Airplane.apply_gear(airplane, {"left": pose.spin, "right": pose.spin, "nose": pose.spin}, pose.steer)
			for role: String in ROLES:
				airplane.gear[role].position = rest[role] + pose.compression
			airplane.root.find_child("gear_flex", false, false).update()
		for wheel in ROLES.size():
			var a := _nodes(first)[wheel]
			var b := _nodes(other)[wheel]
			_check("pose %d %s preserves the transformed tire envelope" % [index, ROLES[wheel]],
				_world_bounds(a, first.root).is_equal_approx(_world_bounds(b, other.root)))
			_check("pose %d %s preserves pivot motion/section" % [index, ROLES[wheel]],
				first.gear[ROLES[wheel]].transform == other.gear[ROLES[wheel]].transform
				and first.gear[ROLES[wheel]].get_meta("crash_section") == "wheel")
	for airplane: Dictionary in [first, other]:
		airplane.root.rotation = Vector3.ZERO
		Airplane.apply_gear(airplane, {"left": 0.0, "right": 0.0, "nose": 0.0}, 0.0)
		for role: String in ROLES:
			airplane.gear[role].position = rest[role]
		airplane.root.find_child("gear_flex", false, false).update()


func _test_material_isolation(first: Dictionary, other: Dictionary, sources: Array) -> void:
	var changed := _nodes(first)[0].mesh.surface_get_material(0) as StandardMaterial3D
	var source := (sources[0] as Mesh).surface_get_material(0) as StandardMaterial3D
	var separate := _nodes(other)[0].mesh.surface_get_material(0) as StandardMaterial3D
	var source_color := source.albedo_color
	var separate_color := separate.albedo_color
	changed.albedo_color = Color.MAGENTA
	_check("editing a replacement material leaves source and second model unchanged", source.albedo_color == source_color
		and separate.albedo_color == separate_color)
	var active := _nodes(first)[0].get_active_material(0) as StandardMaterial3D
	var other_active := _nodes(other)[0].get_active_material(0) as StandardMaterial3D
	var active_color := active.albedo_color
	var other_color := other_active.albedo_color
	active.albedo_color = Color.CYAN
	_check("the active vehicle-paint override is isolated across models", active != other_active
		and other_active.albedo_color == other_color)
	active.albedo_color = active_color


func _test_atomic_failures(airplane: Dictionary, selected: Dictionary, sources: Array) -> void:
	var nodes := _nodes(airplane)
	var nose_parent := nodes[2].get_parent()
	nose_parent.remove_child(nodes[2])
	_check("missing last wheel refuses staging without changing the first two", not Preview.stage(airplane, selected, 1.0).ok
		and nodes[0].mesh == sources[0] and nodes[1].mesh == sources[1])
	nose_parent.add_child(nodes[2])
	var staged := Preview.stage(airplane, selected, 1.0)
	_check("a complete model can be staged again", staged.ok)
	if staged.ok:
		nodes[2].mesh = sources[2].duplicate()
		_check("intervening mesh replacement refuses the whole commit", not staged.preview.apply().ok
			and nodes[0].mesh == sources[0] and nodes[1].mesh == sources[1])
		nodes[2].mesh = sources[2]
	var changed_paint := Preview.stage(airplane, selected, 1.0)
	if changed_paint.ok:
		var old := nodes[2].get_surface_override_material(0)
		nodes[2].set_surface_override_material(0, StandardMaterial3D.new())
		_check("intervening paint change refuses without discarding it", not changed_paint.preview.apply().ok and _meshes(airplane) == sources)
		nodes[2].set_surface_override_material(0, old)
	nodes[2].mesh = BoxMesh.new()
	_check("changed mesh topology refuses before publication", not Preview.stage(airplane, selected, 1.0).ok
		and nodes[0].mesh == sources[0] and nodes[1].mesh == sources[1])
	nodes[2].mesh = sources[2]
	var invalid := selected.duplicate(true)
	invalid.availability = "cosmetic_flight"
	_check("payload cannot supply flight availability", not Preview.stage(airplane, invalid, 1.0).ok and _meshes(airplane) == sources)
	_check("unqualified scale refuses before staging", not Preview.stage(airplane, selected, 2.0).ok)
	_check("missing scale refuses before staging", not Preview.stage(airplane, selected).ok)
	airplane.root.scale = Vector3.ONE * 2.0
	_check("a misleading scale argument cannot disguise an already scaled root", not Preview.stage(airplane, selected, 1.0).ok)
	airplane.root.scale = Vector3.ONE
	airplane.gear.nose.scale = Vector3.ONE * 2.0
	_check("a scaled wheel frame refuses staging", not Preview.stage(airplane, selected, 1.0).ok)
	airplane.gear.nose.scale = Vector3.ONE
	var scale_change := Preview.stage(airplane, selected, 1.0)
	_check("scale-change fixture stages", scale_change.ok)
	if scale_change.ok:
		airplane.root.scale = Vector3.ONE * 2.0
		_check("root scale changed after staging refuses apply", not scale_change.preview.apply().ok and _meshes(airplane) == sources)
		airplane.root.scale = Vector3.ONE
		airplane.gear.nose.scale = Vector3.ONE * 2.0
		_check("wheel scale changed after staging refuses apply", not scale_change.preview.apply().ok and _meshes(airplane) == sources)
		airplane.gear.nose.scale = Vector3.ONE
		_check("corrected scale permits the staged study", scale_change.preview.apply().ok)
		airplane.root.scale = Vector3.ONE * 2.0
		_check("restore remains available after a detached scale edit", scale_change.preview.restore().ok and _meshes(airplane) == sources)
		airplane.root.scale = Vector3.ONE
	var wrong := airplane.duplicate()
	wrong.aircraft_id = "stik-electric-6s"
	_check("shared geometry does not grant another configuration support", not Preview.stage(wrong, selected, 1.0).ok)
	root.add_child(airplane.root)
	_check("a model in a live scene refuses staging", not Preview.stage(airplane, selected, 1.0).ok)
	if staged.ok:
		_check("an already staged handle cannot mutate a live scene", not staged.preview.apply().ok)
	root.remove_child(airplane.root)
	var attached_after_apply := Preview.stage(airplane, selected, 1.0)
	_check("attach/restore fixture stages", attached_after_apply.ok)
	if attached_after_apply.ok:
		_check("detached fixture applies", attached_after_apply.preview.apply().ok)
		var active_meshes := _meshes(airplane)
		root.add_child(airplane.root)
		_check("restore refuses to mutate a live scene", not attached_after_apply.preview.restore().ok and _meshes(airplane) == active_meshes)
		root.remove_child(airplane.root)
		_check("detaching permits exact Original recovery", attached_after_apply.preview.restore().ok and _meshes(airplane) == sources)
	_check("all failed operations retain the stock meshes", _meshes(airplane) == sources)


func _nodes(airplane: Dictionary) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for index in ROLES.size():
		result.append(airplane.gear[ROLES[index]].get_node(NodePath(NAMES[index])) as MeshInstance3D)
	return result


func _meshes(airplane: Dictionary) -> Array:
	var result: Array = []
	for node: MeshInstance3D in _nodes(airplane):
		result.append(node.mesh)
	return result


func _overrides(node: MeshInstance3D) -> Array:
	var result: Array = []
	for surface in 4:
		result.append(node.get_surface_override_material(surface))
	return result


func _surface_payload(mesh: ArrayMesh, surface: int) -> Dictionary:
	var stored: Dictionary = mesh.get("_surfaces")[surface].duplicate()
	stored.erase("material") # Material resources are deliberately instance-local.
	return stored


func _tree_snapshot(node: Node) -> Array:
	var metadata: Dictionary = {}
	for key: StringName in node.get_meta_list():
		metadata[key] = node.get_meta(key)
	var result: Array = [node.get_instance_id(), node.name, node.get_parent(), metadata,
		node.transform if node is Node3D else null]
	for child: Node in node.get_children():
		result.append(_tree_snapshot(child))
	return result


func _measure(vertices: PackedVector3Array) -> Dictionary:
	var bounds := AABB(vertices[0], Vector3.ZERO)
	var radius := 0.0
	for vertex: Vector3 in vertices:
		bounds = bounds.expand(vertex)
		radius = maxf(radius, Vector2(vertex.y, vertex.z).length())
	return {"bounds": bounds, "radius": radius}


func _world_bounds(node: MeshInstance3D, top: Node3D) -> AABB:
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		if parent == top: break
		parent = parent.get_parent()
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds := AABB(transform * vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		bounds = bounds.expand(transform * vertex)
	return bounds


func _valid_tire(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.size() != normals.size(): return false
	for index in range(0, vertices.size(), 3):
		for offset in 3:
			if not vertices[index + offset].is_finite() or not normals[index + offset].is_finite(): return false
		var clockwise := (vertices[index + 2] - vertices[index]).cross(vertices[index + 1] - vertices[index])
		if clockwise.length_squared() < 1e-20 or clockwise.dot(normals[index] + normals[index + 1] + normals[index + 2]) <= 0.0:
			return false
	return true


## Independent dimensions, sampled from the actual triangle buffer, rather than
## reading the generator's profile or using the physics radius as a mesh estimate.
func _grooves_and_crown(mesh: ArrayMesh, radius: float, width: float) -> bool:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for side: float in [-1.0, 1.0]:
		var center := side * width * 0.07
		for sample: Vector2 in [Vector2(center - 0.0005, radius), Vector2(center, radius - 0.0004),
			Vector2(center + 0.0005, radius)]:
			var found := false
			for vertex: Vector3 in vertices:
				if absf(vertex.x - sample.x) < 1e-7:
					if absf(Vector2(vertex.y, vertex.z).length() - sample.y) > 1e-7:
						return false
					found = true
			if not found: return false
	# A tire triangle edge must still cross x=0 at the original lowest point.
	for index in range(0, vertices.size(), 3):
		for edge in 3:
			var a := vertices[index + edge]
			var b := vertices[index + (edge + 1) % 3]
			if a.x * b.x >= 0.0: continue
			var point := a.lerp(b, -a.x / (b.x - a.x))
			if absf(point.y + radius) < 1e-7 and absf(point.z) < 1e-7:
				return true
	return false


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok: _failed += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not ok else ""))


func _finish() -> void:
	print("Stik wheel preview: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
