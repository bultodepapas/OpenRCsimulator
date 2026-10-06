# L6b: complete transformed geometry bounds, shared resources and stable instance identities.
extends SceneTree
const Loader = preload("res://data/field_loader.gd")
const Field = preload("res://render/field.gd")
const Trees = preload("res://render/treeline.gd")
var failed: int = 0
var checks: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loaded: Dictionary = Loader.load_from()
	check("default validates", loaded.ok)
	if not loaded.ok:
		printerr(loaded.errors)
		quit(1)
		return
	var field: Node3D = Field.build(loaded.field)
	var second: Node3D = Field.build(loaded.field)
	var trees: Node3D = field.get_node("treeline")
	var other: Node3D = second.get_node("treeline")
	check("eight azimuth sectors", trees.get_child_count() == 8)
	var count: int = 0
	var species_count: Array[int] = [0, 0, 0]
	var mesh: ArrayMesh = null
	for child: MultiMeshInstance3D in trees.get_children():
		var mm: MultiMesh = child.multimesh
		var another: MultiMesh = (other.get_node(NodePath(child.name)) as MultiMeshInstance3D).multimesh
		check("independent field resources", mm != another and mm.mesh != another.mesh and mm.mesh.surface_get_material(0) != another.mesh.surface_get_material(0))
		check("same stable buffers", mm.buffer == another.buffer)
		check("one surface, no shadows or updates", mm.mesh.get_surface_count() == 1 and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not child.is_processing())
		check("shared mesh within field", mesh == null or mesh == mm.mesh)
		mesh = mm.mesh
		var arrays: Array = mesh.surface_get_arrays(0)
		check("six triangles per tree", arrays[Mesh.ARRAY_INDEX].size() == 18)
		var points: Array = []
		for p: Array in loaded.field.objects[0].positions:
			if child.name == "Sector%d" % Trees.sector(p[0], p[1]):
				points.append(p)
		check("sector count matches committed positions", points.size() == mm.instance_count)
		for index: int in mm.instance_count:
			count += 1
			var point: Array = points[index]
			var transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(point[1], -point[2], -point[0]))
			var packed: Color = Trees.packed_position(point[0], point[1])
			if DisplayServer.get_name() != "headless":
				check("GPU transform matches placement", mm.get_instance_transform(index) == transform)
				check("GPU preserves packed coordinate bytes", mm.get_instance_custom_data(index) == packed)
			var coordinates: Vector2 = Trees.unpacked_position(packed)
			var data: Color = Color(coordinates.x, coordinates.y, 0, 0)
			check("identity is exactly the translation", data.r == -transform.origin.z and data.g == transform.origin.x and transform.basis == Basis.IDENTITY)
			check("sector assignment", child.name == "Sector%d" % Trees.sector(data.r, data.g))
			var shape: Dictionary = Trees.identity(data.r, data.g)
			species_count[int(shape.species)] += 1
			check("estimated height range", shape.height >= 12.0 and shape.height <= 25.0)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var transformed: Vector3 = Basis(Vector3.UP, shape.yaw) * vertex * shape.height + transform.origin
				check("shader-displaced vertex inside culling bounds", mm.custom_aabb.has_point(transformed))
			# Verify whole 15m crown envelope preserves both intentional angular gaps.
			var angle: float = fposmod(rad_to_deg(atan2(data.g, data.r)), 360.0)
			var margin: float = rad_to_deg(asin(15.0 / Vector2(data.r, data.g).length()))
			for gap: Vector2 in [Vector2(30.0, 8.0), Vector2(210.0, 10.0)]:
				check("deliberate gap survives crown width", absf(fposmod(angle - gap.x + 180.0, 360.0) - 180.0) > gap.y + margin)
	check("480 committed trees", count == 480)
	check("three species have useful representation", species_count.min() > 100)
	check("no collision shapes or scene simulation", field.find_children("*", "CollisionObject3D", true, false).is_empty() and field.find_children("*", "CollisionShape3D", true, false).is_empty())
	field.free()
	second.free()
	await transition()
	print("L6b runtime: %d checks, %d failed; species %s" % [checks, failed, species_count])
	quit(1 if failed else 0)

func signature(grove: Node3D) -> Array:
	var values: Array = []
	for node: MultiMeshInstance3D in grove.get_children():
		values.append([node.name, node.multimesh.buffer, node.multimesh.custom_aabb])
	return values

func transition() -> void:
	var ui: RefCounted = preload("res://tests/ui_driver.gd").new(self)
	var prefs: Script = preload("res://app_state/preferences.gd")
	var path: String = "user://test_treeline_preferences.cfg"
	var settings: Dictionary = prefs.DEFAULTS.duplicate(true)
	settings.first_flight_hint_seen = true
	check("isolated preferences saved", prefs.save_to(path, settings) == OK)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", path)
	root.add_child(app)
	await ui.settle()
	var home: Node = app.get("home_scene")
	var grove: Node3D = home.get_node("Field/treeline")
	var expected: Array = signature(grove)
	var old_id: int = grove.get_child(0).multimesh.get_instance_id()
	await ui.tap(KEY_ENTER)
	var flight: Node = app.get("flight")
	check("real Fly route creates flight", flight != null)
	if flight != null:
		var active: Node3D = flight.get_node("Field/treeline")
		check("Home and flight use identical identities, positions and bounds", signature(active) == expected)
		check("transition owns a fresh multimesh", active.get_child(0).multimesh.get_instance_id() != old_id)
	app.queue_free()
	await ui.settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
