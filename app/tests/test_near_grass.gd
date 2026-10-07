# L11a: committed grass data, geometry, field clipping and the scenery hook.
# Run: godot --headless --path app --script res://tests/test_near_grass.gd
extends SceneTree

const NearGrass = preload("res://render/near_grass.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const Ground = preload("res://render/ground.gd")
const Frames = preload("res://render/frames.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")

const GRASS_DATA_PATH: String = "res://data/fields/grass.json"
const GRASS_COUNT: int = 6000
const GRASS_RADIUS_MM: int = 30000
const BLADES_PER_CLUMP: int = 7
const WIND_SWAY_M: float = 0.035

var _failures: int = 0
var _checks: int = 0
var _raw_grass: Dictionary
var _rows: Array
var _field: Dictionary


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_test_committed_data_and_validation()
	_test_blade_mesh()
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads for grass checks", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		_field = loaded.field
		_test_standalone_build()
		_test_default_chunks_and_clearance()
		_test_deterministic_placements()
		_test_translated_pilot_and_small_field()
		_test_field_builder_and_scenery_hook()
	print("%d near-grass checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_committed_data_and_validation() -> void:
	var text: String = FileAccess.get_file_as_string(GRASS_DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_check("committed grass JSON parses", parsed is Dictionary)
	if not parsed is Dictionary:
		return
	_raw_grass = parsed
	_rows = NearGrass.validated_rows(_raw_grass)
	_check("committed data validates to exactly 6,000 rows", _rows.size() == GRASS_COUNT, str(_rows.size()))
	_check("data records the v1 disk, fixed seed and checksum", _raw_grass.get("format") == "openrc-grass v1"
		and _raw_grass.get("seed") == 610707 and _raw_grass.get("radius_mm") == GRASS_RADIUS_MM
		and _raw_grass.get("rows_sha256") == _canonical_digest(_rows))
	if _rows.size() != GRASS_COUNT:
		return
	var centers: Dictionary = {}
	var bounded: bool = true
	var encoded: bool = true
	for row_value: Variant in _rows:
		var row: Array = row_value
		var north: int = int(row[0])
		var east: int = int(row[1])
		var key: Vector2i = Vector2i(north, east)
		if centers.has(key):
			centers[key] = false
		else:
			centers[key] = true
		bounded = bounded and north * north + east * east <= GRASS_RADIUS_MM * GRASS_RADIUS_MM
		encoded = encoded and row.size() == 4 and row[2] >= 0 and row[2] <= 65535 and row[3] >= 0 and row[3] <= 255
	_check("all committed offsets are unique and inside the 30 m disk", bounded and centers.size() == GRASS_COUNT
		and not centers.values().has(false))
	_check("yaw and size bytes fit their renderer ranges", encoded)

	var damaged: Dictionary = _raw_grass.duplicate(true)
	var damaged_rows: Array = damaged["rows"]
	var damaged_first: Array = damaged_rows[0]
	damaged_first[2] = (int(damaged_first[2]) + 1) % 65536
	_check_invalid("stale digest detects row corruption", damaged)

	var fractional: Dictionary = _raw_grass.duplicate(true)
	var fractional_rows: Array = fractional["rows"]
	var fractional_first: Array = fractional_rows[0]
	fractional_first[0] = float(fractional_first[0]) + 0.5
	_rehash(fractional)
	_check_invalid("fractional offsets are rejected", fractional)

	var duplicate: Dictionary = _raw_grass.duplicate(true)
	var duplicate_rows: Array = duplicate["rows"]
	var duplicate_first: Array = duplicate_rows[0]
	var duplicate_second: Array = duplicate_rows[1]
	duplicate_second[0] = duplicate_first[0]
	duplicate_second[1] = duplicate_first[1]
	_rehash(duplicate)
	_check_invalid("duplicate centers are rejected", duplicate)

	var outside: Dictionary = _raw_grass.duplicate(true)
	var outside_rows: Array = outside["rows"]
	var outside_first: Array = outside_rows[0]
	outside_first[0] = GRASS_RADIUS_MM
	outside_first[1] = 1
	_rehash(outside)
	_check_invalid("offsets outside the disk are rejected", outside)

	var truncated: Dictionary = _raw_grass.duplicate(true)
	var truncated_rows: Array = truncated["rows"]
	truncated_rows.pop_back()
	_rehash(truncated)
	_check_invalid("truncated placement is rejected", truncated)


func _test_blade_mesh() -> void:
	var mesh: ArrayMesh = NearGrass.clump_mesh()
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var box: AABB = mesh.get_aabb()
	_check("clump contains seven opaque single-triangle blades", vertices.size() == BLADES_PER_CLUMP * 3
		and mesh.get_surface_count() == 1 and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)
	_check("blade roots sit at y=0 and tips reach UV.y=1", _blade_uv_contract(vertices, uvs))
	_check("blade geometry stays within the estimated 0.2 m footprint and 0.10–0.18 m height",
		box.position.y == 0.0 and box.size.y >= 0.10 and box.size.y <= 0.1801
		and box.size.x < 0.2 and box.size.z < 0.2, str(box))
	_check("0.4 m exclusion margin exceeds max-scale clump plus full sway footprint",
		_max_wind_footprint(mesh) < NearGrass.CLEARANCE_M,
		"footprint %.4f m, clearance %.3f m" % [_max_wind_footprint(mesh), NearGrass.CLEARANCE_M])


func _test_standalone_build() -> void:
	var globals_before: Array = RenderingServer.global_shader_parameter_get_list()
	var grass: Node3D = NearGrass.build(_field, Ground.grass_material())
	var globals_after: Array = RenderingServer.global_shader_parameter_get_list()
	_check("standalone grass build registers sim_clock and wind_vec once",
		globals_after.count(&"sim_clock") == 1 and globals_after.count(&"wind_vec") == 1
		and globals_after.count(&"sim_clock") >= globals_before.count(&"sim_clock"))
	_check("standalone build has no physics or simulation nodes", _count_colliders(grass) == 0)
	grass.free()


func _test_default_chunks_and_clearance() -> void:
	var grass: Node3D = NearGrass.build(_field, Ground.grass_material())
	var chunks: Array[MultiMeshInstance3D] = _chunks(grass)
	var primitive_count: int = _primitive_count(chunks)
	_check("default build clips data into at most four MultiMesh chunks", chunks.size() <= 4 and not chunks.is_empty(), str(chunks.size()))
	_check("default build stays within 42,000 blade triangles", primitive_count <= GRASS_COUNT * BLADES_PER_CLUMP, str(primitive_count))
	_check("all grass chunks disable shadow casting", _shadows_off(chunks))
	_check("default build contains exactly the accepted field centers", _build_matches_field(grass, _field), str(grass.get_meta("clumps", -1)))
	_check("every default clump and wind footprint clears runway and mown rectangles",
		_build_has_surface_clearance(grass, _field, NearGrass.clump_mesh()), "minimum renderer clearance is 0.4 m")
	_check("default grass build creates no collision objects", _count_colliders(grass) == 0)
	grass.free()


func _test_deterministic_placements() -> void:
	var first: Node3D = NearGrass.build(_field, Ground.grass_material())
	var second: Node3D = NearGrass.build(_field, Ground.grass_material())
	var first_layout: Array = NearGrass.clipped_chunks(_field, _rows)
	var second_layout: Array = NearGrass.clipped_chunks(_field, _rows)
	_check("rebuilds preserve every world center, yaw and size input", JSON.stringify(first_layout) == JSON.stringify(second_layout)
		and _grass_signature(first) == _grass_signature(second))
	first.free()
	second.free()


func _test_translated_pilot_and_small_field() -> void:
	var translated: Dictionary = _field_variant(func(raw: Dictionary) -> void:
		(raw["pilot"] as Dictionary)["north"]["value"] = 12.5
		(raw["pilot"] as Dictionary)["east"]["value"] = -7.25
	)
	if not translated.is_empty():
		var translated_grass: Node3D = NearGrass.build(translated, Ground.grass_material())
		_check("translated-pilot build uses pilot-relative offsets and current runway clipping",
			_build_matches_field(translated_grass, translated) and _build_has_surface_clearance(translated_grass, translated, NearGrass.clump_mesh()))
		translated_grass.free()

	var small: Dictionary = _field_variant(func(raw: Dictionary) -> void:
		(raw["pilot"] as Dictionary)["north"]["value"] = 18.0
		(raw["pilot"] as Dictionary)["east"]["value"] = -9.0
		var surfaces: Array = raw["surfaces"]
		var rough: Dictionary = surfaces[0]
		_set_quantity(rough, "center_north", 18.0)
		_set_quantity(rough, "center_east", -9.0)
		_set_quantity(rough, "length_east_west", 30.0)
		_set_quantity(rough, "width_north_south", 26.0)
		var runway: Dictionary = surfaces[1]
		_set_quantity(runway, "center_north", 25.0)
		_set_quantity(runway, "center_east", -9.0)
		_set_quantity(runway, "length_east_west", 8.0)
		_set_quantity(runway, "width_north_south", 4.0)
		surfaces.append(_surface("mown-apron", "mown", 11.0, -9.0, 6.0, 3.0))
	)
	if not small.is_empty():
		var small_grass: Node3D = NearGrass.build(small, Ground.grass_material())
		var accepted: int = int(small_grass.get_meta("clumps", -1))
		_check("translated pilot, moved runway, mown apron and small rough field validate", not small.is_empty())
		_check("small rough rectangle clips grass while retaining interior clumps", accepted > 0 and accepted < GRASS_COUNT
			and _build_matches_field(small_grass, small), str(accepted))
		_check("every small-field center and full clump footprint remains on rough and clear of strips",
			_build_has_surface_clearance(small_grass, small, NearGrass.clump_mesh()))
		small_grass.free()


func _test_field_builder_and_scenery_hook() -> void:
	var previous_scenery: String = OS.get_environment("OPENRC_SCENERY")
	var previous_audio: String = OS.get_environment("OPENRC_SCENERY_AUDIO")
	OS.set_environment("OPENRC_SCENERY", "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	var plain: Node3D = FieldBuilder.build(_field)
	_check("field builder attaches exactly one near-grass system when scenery is off",
		_count_named(plain, "NearGrass") == 1 and plain.get_node_or_null("Scenery") == null)
	_check("field and default grass tree contain no physical colliders", _count_colliders(plain) == 0)
	plain.free()

	var validated_scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, _field)
	_check("default SC-16/SC-17 data validates", bool(validated_scenery.get("ok", false)), str(validated_scenery.get("errors", [])))
	if bool(validated_scenery.get("ok", false)):
		var counts: Dictionary = _scenery_ornament_counts(validated_scenery.scenery)
		_check("validated scenery has 2,970 SC-16 cushions and six SC-17 bushes",
			counts.flowers == 2970 and counts.bushes == 6, str(counts))

	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	var with_scenery: Node3D = FieldBuilder.build(_field)
	var scenery_node: Node = with_scenery.get_node_or_null("Scenery")
	_check("opt-in field hook attaches Scenery beside the single near-grass system",
		scenery_node != null and _count_named(with_scenery, "NearGrass") == 1)
	_check("opt-in field build retains the SC-16 flower cushions", scenery_node != null
		and int((scenery_node.get_meta("stats") as Dictionary).get("flowers", -1)) == 2970)
	_check("opt-in scenery and grass remain visual-only", _count_colliders(with_scenery) == 0)
	with_scenery.free()
	OS.set_environment("OPENRC_SCENERY", previous_scenery)
	OS.set_environment("OPENRC_SCENERY_AUDIO", previous_audio)


func _canonical_digest(rows: Array) -> String:
	var canonical: String = ""
	for row_value: Variant in rows:
		var row: Array = row_value
		canonical += "%d,%d,%d,%d\n" % [int(row[0]), int(row[1]), int(row[2]), int(row[3])]
	return canonical.sha256_text()


func _rehash(data: Dictionary) -> void:
	data["rows_sha256"] = _canonical_digest(data["rows"])


func _check_invalid(label: String, data: Dictionary) -> void:
	_check(label, NearGrass.validated_rows(data).is_empty())


func _blade_uv_contract(vertices: PackedVector3Array, uvs: PackedVector2Array) -> bool:
	if vertices.size() != BLADES_PER_CLUMP * 3 or uvs.size() != vertices.size():
		return false
	for triangle: int in BLADES_PER_CLUMP:
		var roots: int = 0
		var tips: int = 0
		for corner: int in 3:
			var index: int = triangle * 3 + corner
			if is_equal_approx(vertices[index].y, 0.0):
				roots += 1
				if not is_equal_approx(uvs[index].y, 0.0):
					return false
			else:
				tips += 1
				if not is_equal_approx(uvs[index].y, 1.0):
					return false
		if roots != 2 or tips != 1:
			return false
	return true


func _max_wind_footprint(mesh: ArrayMesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var max_radius: float = 0.0
	for index: int in vertices.size():
		var radius: float = Vector2(vertices[index].x, vertices[index].z).length() * 1.25
		radius += WIND_SWAY_M * uvs[index].y * uvs[index].y
		max_radius = maxf(max_radius, radius)
	return max_radius


func _chunks(grass: Node3D) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for child: Node in grass.get_children():
		if child is MultiMeshInstance3D:
			result.append(child as MultiMeshInstance3D)
	return result


func _primitive_count(chunks: Array[MultiMeshInstance3D]) -> int:
	var total: int = 0
	for chunk: MultiMeshInstance3D in chunks:
		var mm: MultiMesh = chunk.multimesh
		total += mm.instance_count * mm.mesh.surface_get_array_len(0) / 3
	return total


func _shadows_off(chunks: Array[MultiMeshInstance3D]) -> bool:
	for chunk: MultiMeshInstance3D in chunks:
		if chunk.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
	return true


func _build_matches_field(grass: Node3D, field: Dictionary) -> bool:
	var layout: Array = NearGrass.clipped_chunks(field, _rows)
	var expected_nonempty: int = 0
	var total: int = 0
	for index: int in 4:
		var points: Array = layout[index]
		total += points.size()
		var node: Node = grass.get_node_or_null("grass_%d" % index)
		if points.is_empty():
			if node != null:
				return false
			continue
		expected_nonempty += 1
		if not node is MultiMeshInstance3D or (node as MultiMeshInstance3D).multimesh.instance_count != points.size():
			return false
	return expected_nonempty == _chunks(grass).size() and total == int(grass.get_meta("clumps", -1))


func _build_has_surface_clearance(grass: Node3D, field: Dictionary, mesh: ArrayMesh) -> bool:
	var envelope: float = _max_wind_footprint(mesh)
	if envelope > NearGrass.CLEARANCE_M:
		return false
	var layout: Array = NearGrass.clipped_chunks(field, _rows)
	for chunk: Array in layout:
		for point: Array in chunk:
			var north: float = float(point[0])
			var east: float = float(point[1])
			if not _inside_rough_clearance(north, east, field):
				printerr("grass clipped point outside rough fixture: %.6f,%.6f" % [north, east])
				return false
			if not _outside_strip_clearance(north, east, field, envelope):
				printerr("grass clipped point breaches strip clearance: %.6f,%.6f" % [north, east])
				return false
			var dn: float = north - float(field.pilot.north)
			var de: float = east - float(field.pilot.east)
			if dn * dn + de * de > (NearGrass.RADIUS_M + 0.001) * (NearGrass.RADIUS_M + 0.001):
				return false
	return true


func _inside_rough_clearance(north: float, east: float, field: Dictionary) -> bool:
	for surface: Dictionary in field.surfaces:
		if surface.type != "rough":
			continue
		var dn: float = absf(north - float(surface.center_north))
		var de: float = absf(east - float(surface.center_east))
		if dn <= float(surface.width_north_south) * 0.5 - NearGrass.CLEARANCE_M \
			and de <= float(surface.length_east_west) * 0.5 - NearGrass.CLEARANCE_M:
			return true
	return false


func _outside_strip_clearance(north: float, east: float, field: Dictionary, footprint: float) -> bool:
	for surface: Dictionary in field.surfaces:
		if surface.type != "runway" and surface.type != "mown":
			continue
		var half_n: float = float(surface.width_north_south) * 0.5
		var half_e: float = float(surface.length_east_west) * 0.5
		var offset_n: float = absf(north - float(surface.center_north))
		var offset_e: float = absf(east - float(surface.center_east))
		var dn: float = maxf(offset_n - half_n, 0.0)
		var de: float = maxf(offset_e - half_e, 0.0)
		var gap: float = Vector2(dn, de).length()
		var in_clearance_rectangle: bool = offset_n <= half_n + NearGrass.CLEARANCE_M \
			and offset_e <= half_e + NearGrass.CLEARANCE_M
		if gap < footprint or in_clearance_rectangle:
			return false
	return true


func _grass_signature(grass: Node3D) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	for chunk: MultiMeshInstance3D in _chunks(grass):
		bytes.append_array(str(chunk.name).to_utf8_buffer())
		var points: Array = NearGrass.clipped_chunks(_field, _rows)[int(chunk.name.get_slice("_", 1))]
		for point: Array in points:
			bytes.append_array((PackedFloat32Array([
				float(point[0]), float(point[1]), float(point[2]), float(point[3]),
			])).to_byte_array())
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _count_named(node: Node, target: String) -> int:
	var result: int = 1 if node.name == target else 0
	for child: Node in node.get_children():
		result += _count_named(child, target)
	return result


func _count_colliders(node: Node) -> int:
	var result: int = 1 if node is CollisionObject3D else 0
	for child: Node in node.get_children():
		result += _count_colliders(child)
	return result


func _field_variant(mutate: Callable) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	if not raw is Dictionary:
		return {}
	var copy: Dictionary = raw.duplicate(true)
	copy["objects"] = [] # Tree placement is unrelated to these grass surface cases.
	mutate.call(copy)
	var result: Dictionary = FieldLoader.validate(copy)
	_check("grass field variant validates", bool(result.get("ok", false)), str(result.get("errors", [])))
	return result.field if bool(result.get("ok", false)) else {}


func _set_quantity(surface: Dictionary, key: String, value: float) -> void:
	(surface[key] as Dictionary)["value"] = value


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity(north),
		"center_east": _quantity(east),
		"length_east_west": _quantity(length),
		"width_north_south": _quantity(width),
	}


func _quantity(value: float) -> Dictionary:
	return {"value": value, "unit": "m", "kind": "estimated", "source": "L11a test fixture estimate; not surveyed."}


func _scenery_ornament_counts(scenery: Dictionary) -> Dictionary:
	var flowers: int = 0
	var bushes: int = 0
	for group: Dictionary in scenery.groups:
		if group.type == "flowers":
			flowers += group.positions.size()
		elif group.type == "instances":
			for placement: Dictionary in group.placements:
				if placement.prefab == "bush":
					bushes += 1
	return {"flowers": flowers, "bushes": bushes}
