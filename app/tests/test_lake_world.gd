## LU-28: the default field attaches matching lake masks and baked basin/water meshes.
## Run: godot --headless --path app --script res://tests/test_lake_world.gd
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Ground := preload("res://render/ground.gd")
const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0
var _saved_lake_environment := ""
var _saved_environment_recorded := false


func _initialize() -> void:
	_saved_lake_environment = OS.get_environment("OPENRC_LAKE")
	_saved_environment_recorded = true
	call_deferred("_run")


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("default field and normalized lake definitions load",
		bool(field_result.get("ok", false)) and bool(lake_result.get("ok", false)),
		"field=%s lake=%s" % [str(field_result.get("errors", [])), str(lake_result.get("errors", []))])
	if not field_result.ok or not lake_result.ok:
		_finish()
		return
	var field: Dictionary = field_result.field
	var lake: Dictionary = lake_result.lake

	OS.unset_environment("OPENRC_LAKE")
	var default_options: Dictionary = LakeWorld.options()
	var default_resolution: Dictionary = LakeWorld.resolve(field, {enabled = true, file_explicit = false})
	_check("lake defaults on for the exact default field", bool(default_options.enabled)
		and bool(default_resolution.ok) and bool(default_resolution.enabled)
		and default_resolution.lake.identity == lake.identity)
	_check_disabled_hazard("default lake-off switch", field, "off")

	var custom_field: Dictionary = field.duplicate(true)
	custom_field["id"] = "custom_fixture"
	OS.unset_environment("OPENRC_LAKE")
	var custom_resolution: Dictionary = LakeWorld.resolve(custom_field, {enabled = true, file_explicit = false})
	_check("custom fields receive no lake scene context", bool(custom_resolution.ok)
		and not bool(custom_resolution.enabled) and custom_resolution.lake.is_empty())
	_check_disabled_scene("custom field", custom_resolution.lake)
	_check_no_lake_hazard("custom field", custom_resolution.lake)
	var explicit_scenery_file: Dictionary = LakeWorld.resolve(field,
		{enabled = true, file_explicit = true})
	_check("an explicitly selected scenery layout receives no default lake", bool(explicit_scenery_file.ok)
		and not bool(explicit_scenery_file.enabled) and explicit_scenery_file.lake.is_empty())
	_check_disabled_scene("explicit scenery layout", explicit_scenery_file.lake)
	_check_no_lake_hazard("explicit scenery layout", explicit_scenery_file.lake)

	_test_attached_scene(field, lake)
	_finish()


func _check_disabled_hazard(label: String, field: Dictionary, setting: String) -> void:
	OS.set_environment("OPENRC_LAKE", setting)
	var resolution: Dictionary = LakeWorld.resolve(field, {enabled = true, file_explicit = false})
	_check("%s resolves without a lake" % label, bool(resolution.get("ok", false))
		and not bool(resolution.get("enabled", true)) and resolution.get("lake", {}).is_empty())
	_check_disabled_scene(label, resolution.get("lake", {}))
	_check_no_lake_hazard(label, resolution.get("lake", {}))


func _check_disabled_scene(label: String, lake: Dictionary) -> void:
	var field_node := Node3D.new()
	var attached: Node3D = LakeWorld.attach(field_node, {}, null, lake, {}, false)
	_check("%s scene has no Lake node or context metadata" % label, attached == null
		and field_node.get_node_or_null("Lake") == null and not field_node.has_meta("lake_context")
		and not field_node.has_meta("lake_identity"))
	field_node.free()


func _check_no_lake_hazard(label: String, lake: Dictionary) -> void:
	var session := Session.new()
	var accepted := session.set_lake_context(lake)
	var previous: PackedFloat64Array = RB.make_state(PackedFloat64Array([110.0, 125.0, -1.0]),
		PackedFloat64Array([0.0, 0.0, 12.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var candidate: PackedFloat64Array = RB.make_state(PackedFloat64Array([110.0, 125.0, 1.0]),
		PackedFloat64Array([0.0, 0.0, 12.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var event := LakeCollision.first_hit(session.lake_context(), previous, candidate,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 1, 1.0 / 240.0, 1.0,
		PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))
	_check("%s context cannot create a water hazard" % label, accepted and session.lake_context().is_empty()
		and event == null and session.last_lake_event() == null)
	session.free()


func _test_attached_scene(field: Dictionary, lake: Dictionary) -> void:
	var table_result: Dictionary = GroundSurfaces.load_table()
	var surface_result: Dictionary = GroundSurfaces.build(table_result.table, field) if table_result.ok else {}
	_check("default field produces the matching physical surface table",
		bool(table_result.get("ok", false)) and bool(surface_result.get("ok", false)))
	if not surface_result.get("ok", false):
		return
	var ground_material: ShaderMaterial = Ground.grass_material({})
	var field_node := Node3D.new()
	field_node.name = "LakeWorldContractField"
	root.add_child(field_node)
	var lake_node: Node3D = LakeWorld.attach(field_node, field, ground_material, lake, {}, false)
	_check("production lake attach creates one identity-matched scene child", lake_node != null
		and lake_node.get_parent() == field_node and lake_node.name == "Lake"
		and str(lake_node.get_meta("identity", "")) == str(lake.identity)
		and str(field_node.get_meta("lake_identity", "")) == str(lake.identity)
		and field_node.get_meta("lake_context", {}).identity == lake.identity)
	if lake_node == null:
		field_node.free()
		return
	var basin: MeshInstance3D = lake_node.get_node_or_null("Basin") as MeshInstance3D
	var water: MeshInstance3D = lake_node.get_node_or_null("Water") as MeshInstance3D
	_check("lake scene contains real basin and shoreline water meshes",
		basin != null and basin.mesh != null and water != null and water.mesh != null
		and basin.mesh.get_surface_count() == 1 and water.mesh.get_surface_count() == 1)
	if basin == null or water == null:
		field_node.free()
		return
	_test_matching_mask(ground_material, basin.material_override as ShaderMaterial, lake)
	_test_mesh_bounds_and_normals(basin, water, lake)
	_test_baked_depth_and_shelf(basin, lake, surface_result.rects)
	field_node.free()


func _test_matching_mask(ground_material: ShaderMaterial, basin_material: ShaderMaterial,
		lake: Dictionary) -> void:
	var bank: PackedFloat64Array = lake.bank_ne_m
	var expected_count: int = bank.size() / 2
	var ground_count := int(ground_material.get_shader_parameter("lake_bank_count"))
	var basin_count := int(basin_material.get_shader_parameter("lake_bank_count"))
	var ground_points: PackedVector2Array = ground_material.get_shader_parameter("lake_bank_points")
	var basin_points: PackedVector2Array = basin_material.get_shader_parameter("lake_bank_points")
	var expected_bounds := Vector4(INF, INF, -INF, -INF)
	var points_match := ground_points.size() >= expected_count and basin_points.size() >= expected_count
	for index: int in expected_count:
		var expected := Vector2(bank[index * 2 + 1], -bank[index * 2])
		points_match = points_match and ground_points[index].distance_to(expected) < 1.0e-6 \
			and basin_points[index].distance_to(expected) < 1.0e-6
		expected_bounds.x = minf(expected_bounds.x, expected.x)
		expected_bounds.y = minf(expected_bounds.y, expected.y)
		expected_bounds.z = maxf(expected_bounds.z, expected.x)
		expected_bounds.w = maxf(expected_bounds.w, expected.y)
	_check("ground cutout and basin bank shader share the canonical NED mask",
		int(ground_material.get_shader_parameter("lake_mask_mode")) == 1
		and ground_count == expected_count and basin_count == expected_count and points_match
		and ground_material.get_shader_parameter("lake_bank_bounds") == expected_bounds
		and basin_material.get_shader_parameter("lake_bank_bounds") == expected_bounds)


func _test_mesh_bounds_and_normals(basin: MeshInstance3D, water: MeshInstance3D,
		lake: Dictionary) -> void:
	var basin_arrays: Array = basin.mesh.surface_get_arrays(0)
	var basin_vertices: PackedVector3Array = basin_arrays[Mesh.ARRAY_VERTEX]
	var basin_normals: PackedVector3Array = basin_arrays[Mesh.ARRAY_NORMAL]
	var basin_uv: PackedVector2Array = basin_arrays[Mesh.ARRAY_TEX_UV]
	var basin_bounds: AABB = basin.mesh.get_aabb()
	var water_arrays: Array = water.mesh.surface_get_arrays(0)
	var water_vertices: PackedVector3Array = water_arrays[Mesh.ARRAY_VERTEX]
	var water_normals: PackedVector3Array = water_arrays[Mesh.ARRAY_NORMAL]
	var water_shore_uv: PackedVector2Array = water_arrays[Mesh.ARRAY_TEX_UV2]
	var water_bounds: AABB = water.mesh.get_aabb()
	var bank: PackedFloat64Array = lake.bank_ne_m
	var shore: PackedFloat64Array = lake.shoreline_ne_m
	var bank_min_n := INF
	var bank_max_n := -INF
	var bank_min_e := INF
	var bank_max_e := -INF
	for index: int in range(0, bank.size(), 2):
		bank_min_n = minf(bank_min_n, bank[index])
		bank_max_n = maxf(bank_max_n, bank[index])
		bank_min_e = minf(bank_min_e, bank[index + 1])
		bank_max_e = maxf(bank_max_e, bank[index + 1])
	var shore_min_n := INF
	var shore_max_n := -INF
	var shore_min_e := INF
	var shore_max_e := -INF
	for index: int in range(0, shore.size(), 2):
		shore_min_n = minf(shore_min_n, shore[index])
		shore_max_n = maxf(shore_max_n, shore[index])
		shore_min_e = minf(shore_min_e, shore[index + 1])
		shore_max_e = maxf(shore_max_e, shore[index + 1])
	var bank_bounds_cover := -basin_bounds.end.z <= bank_min_n + 1.0e-5 \
		and -basin_bounds.position.z >= bank_max_n - 1.0e-5 \
		and basin_bounds.position.x <= bank_min_e + 1.0e-5 \
		and basin_bounds.end.x >= bank_max_e - 1.0e-5
	var shore_bounds_match := absf(water_bounds.position.x - shore_min_e) < 1.0e-5 \
		and absf(water_bounds.end.x - shore_max_e) < 1.0e-5 \
		and absf(-water_bounds.end.z - shore_min_n) < 1.0e-5 \
		and absf(-water_bounds.position.z - shore_max_n) < 1.0e-5
	var basin_normals_ok := basin_vertices.size() > 1000 and basin_normals.size() == basin_vertices.size() \
		and basin_uv.size() == basin_vertices.size()
	for normal: Vector3 in basin_normals:
		basin_normals_ok = basin_normals_ok and normal.is_finite() and absf(normal.length() - 1.0) < 1.0e-5 \
			and normal.y > 0.0
	var water_normals_ok := water_vertices.size() > 100 and water_normals.size() == water_vertices.size() \
		and water_shore_uv.size() == water_vertices.size()
	for index: int in water_vertices.size():
		water_normals_ok = water_normals_ok and water_vertices[index].is_finite() \
			and water_normals[index].is_finite() and absf(water_normals[index].length() - 1.0) < 1.0e-4 \
			and water_normals[index].y > 0.9999 \
			and is_finite(water_shore_uv[index].x) and water_shore_uv[index].x >= 0.0
	_check("basin mesh bounds cover the whole bounded bank region", bank_bounds_cover
		and basin_bounds.size.x > 90.0 and basin_bounds.size.z > 65.0)
	_check("water mesh follows shoreline bounds at the shared mean-down level", shore_bounds_match
		and absf(water.position.y + float(lake.water_level_down_m)) < 1.0e-6
		and absf(water_bounds.position.y) < 2.0e-5 and absf(water_bounds.end.y) < 2.0e-5,
		"bounds=%s shoreline NE=[%.3f,%.3f]x[%.3f,%.3f] position=%s" % [str(water_bounds),
			shore_min_n, shore_max_n, shore_min_e, shore_max_e, str(water.position)])
	_check("baked basin has normalized upward finite normals and scalar bed/shore UVs", basin_normals_ok)
	_check("water mesh has upward normals and nonnegative shoreline fade coordinates", water_normals_ok,
		"vertices=%d normals=%d uv2=%d first_normal=%s first_uv2=%s" % [water_vertices.size(),
			water_normals.size(), water_shore_uv.size(), str(water_normals[0]) if not water_normals.is_empty() else "empty",
			str(water_shore_uv[0]) if not water_shore_uv.is_empty() else "empty"])


func _test_baked_depth_and_shelf(basin: MeshInstance3D, lake: Dictionary,
		surfaces: PackedFloat64Array) -> void:
	var arrays: Array = basin.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var center_index := -1
	var center_distance := INF
	var shelf_index := -1
	var shelf_distance := INF
	for index: int in vertices.size():
		var north: float = -vertices[index].z
		var east: float = vertices[index].x
		var distance_to_center := (north - 110.0) * (north - 110.0) + (east - 125.0) * (east - 125.0)
		if distance_to_center < center_distance:
			center_distance = distance_to_center
			center_index = index
		var distance_to_shelf := absf(uv[index].x - 5.5)
		if distance_to_shelf < shelf_distance:
			shelf_distance = distance_to_shelf
			shelf_index = index
	if center_index < 0 or shelf_index < 0:
		_check("basin geometry contains a deep sample and shelf transition", false)
		return
	var center_vertex: Vector3 = vertices[center_index]
	var center_north := -center_vertex.z
	var center_east := center_vertex.x
	var flat_center: PackedFloat64Array = GroundTerrain.sample_validated(center_north, center_east, surfaces)
	var coupled_center: PackedFloat64Array = GroundTerrain.sample_validated(center_north, center_east, surfaces, lake)
	var shelf_vertex: Vector3 = vertices[shelf_index]
	var center_depth: float = uv[center_index].y
	var shelf_depth: float = uv[shelf_index].y
	_check("basin vertices bake the five-metre bed below the unchanged field datum",
		center_distance < 0.3 and center_depth > 4.99 and center_depth < 5.01
		and absf(center_vertex.y - coupled_center[0]) < 1.0e-6
		and absf((center_vertex.y - flat_center[0]) + 5.45) < 0.02,
		"center=%s uv=%s flat=%s coupled=%s" % [str(center_vertex), str(uv[center_index]),
			str(flat_center), str(coupled_center)])
	_check("baked inner shelf follows the authored 5.5 m inset and 0.8 m depth",
		shelf_distance < 0.55 and shelf_depth >= 0.79 and shelf_depth <= 0.95
		and absf(shelf_vertex.y + float(lake.water_level_down_m) + shelf_depth) < 1.0e-6,
		"shore_distance=%.6f depth=%.6f vertex=%s" % [uv[shelf_index].x, shelf_depth, str(shelf_vertex)])
	var scalar_sample: Dictionary = LakeSurface.sample_terrain_validated(lake,
		float(-shelf_vertex.z), float(shelf_vertex.x))
	_check("renderer mesh and float64 sampler agree on the shelf region", scalar_sample.region == "bed"
		and absf(float(scalar_sample.depth_m) - shelf_depth) < 1.0e-6)


func _finish() -> void:
	if _saved_environment_recorded:
		if _saved_lake_environment.is_empty():
			OS.unset_environment("OPENRC_LAKE")
		else:
			OS.set_environment("OPENRC_LAKE", _saved_lake_environment)
	print("%d lake world checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1
