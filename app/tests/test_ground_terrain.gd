# GP-01 draft: deterministic per-surface soil relief, gradients, fail-closed table validation and renderer mapping.
# Run: godot --headless --path . --script res://tests/test_ground_terrain.gd
extends SceneTree

const Terrain := preload("res://physics/ground_terrain.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FieldBuilder := preload("res://render/field.gd")
const Ground := preload("res://render/ground.gd")

var _count: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_empty_fixture_and_bad_inputs()
	_test_default_field_and_smooth_edge()
	_test_nested_surface_precedence()
	_test_renderer_uses_field_rectangles()
	_test_shader_cpu_formula_agreement()
	_test_shader_normal_orientation()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_empty_fixture_and_bad_inputs() -> void:
	_check("empty table is the explicit flat terrain fixture", Terrain.sample(10.0, -2.0, PackedFloat64Array()) == PackedFloat64Array([0.0, 0.0, 0.0])
		and Terrain.max_height(PackedFloat64Array()) == 0.0)
	var malformed: Array[PackedFloat64Array] = [
		PackedFloat64Array([1.0, 2.0, 3.0]),
		PackedFloat64Array([0.0, 1.0, 0.0, 1.0, 0.8, 2.5]),
		PackedFloat64Array([0.0, 1.0, 0.0, 1.0, 0.8, 2.5, 0.0, 1.0, 0.0, 1.0, 0.7, 7.5]),
		PackedFloat64Array([-INF, INF, -INF, INF, 0.8, NAN]),
	]
	var all_rejected := true
	for table: PackedFloat64Array in malformed:
		var got: PackedFloat64Array = Terrain.sample(0.0, 0.0, table)
		all_rejected = all_rejected and got.size() == 3 and is_nan(got[0]) and is_nan(got[1]) and is_nan(got[2])
		all_rejected = all_rejected and is_nan(Terrain.max_height(table))
	_check("malformed tables fail closed with NAN, not silent flat terrain", all_rejected)
	var valid := _surface_table()
	_check("validated fast path agrees with the fail-closed wrapper",
		Terrain.is_valid_surface_table(valid)
		and Terrain.sample_validated(9.75, 0.0, valid) == Terrain.sample(9.75, 0.0, valid)
		and Terrain.max_height_validated(valid) == 0.007)
	var bad_coordinate: PackedFloat64Array = Terrain.sample(NAN, 0.0, valid)
	_check("non-finite query coordinates fail closed", is_nan(bad_coordinate[0]) and is_nan(bad_coordinate[1]) and is_nan(bad_coordinate[2]))


func _test_default_field_and_smooth_edge() -> void:
	var table: Dictionary = GroundSurfaces.load_table()
	var field: Dictionary = FieldLoader.load_from()
	_check("source friction table and default field load", bool(table.get("ok", false)) and bool(field.get("ok", false)),
		"surface=%s field=%s" % [table.get("errors", []), field.get("errors", [])])
	if not bool(table.get("ok", false)) or not bool(field.get("ok", false)):
		return
	var built: Dictionary = GroundSurfaces.build(table.table, field.field)
	_check("default physics surface table builds", bool(built.get("ok", false)), str(built.get("errors", [])))
	if not bool(built.get("ok", false)):
		return
	var surfaces: PackedFloat64Array = built.rects
	_check("outside rough envelope reaches 7 mm", absf(Terrain.max_height(surfaces) - 0.007) < 1e-12, str(Terrain.max_height(surfaces)))
	var runway: PackedFloat64Array = Terrain.sample(15.0, 0.0, surfaces)
	var rough: PackedFloat64Array = Terrain.sample(0.0, 0.0, surfaces)
	_check("runway relief remains within 1 mm and rough relief within 7 mm",
		absf(runway[0]) <= 0.001 + 1e-12 and absf(rough[0]) <= 0.007 + 1e-12,
		"runway=%s rough=%s" % [runway, rough])
	_check("terrain is deterministic at a repeated wheel query", runway == Terrain.sample(15.0, 0.0, surfaces))
	var left: PackedFloat64Array = Terrain.sample(21.0 - 1e-6, 0.0, surfaces)
	var right: PackedFloat64Array = Terrain.sample(21.0 + 1e-6, 0.0, surfaces)
	_check("runway edge height is continuous", absf(left[0] - right[0]) < 1e-8, "left=%s right=%s" % [left, right])
	_check_gradient("runway edge feather", 20.75, 0.0, surfaces)


func _test_nested_surface_precedence() -> void:
	var surfaces: PackedFloat64Array = _surface_table()
	var runway: PackedFloat64Array = Terrain.sample(0.0, 0.0, surfaces)
	var mown_only: PackedFloat64Array = Terrain.sample(20.0, 0.0, surfaces)
	var rough_only: PackedFloat64Array = Terrain.sample(50.0, 0.0, surfaces)
	_check("runway, mown and rough regions produce finite relief", _finite_sample(runway) and _finite_sample(mown_only) and _finite_sample(rough_only))
	_check_gradient("runway feather", 9.75, 0.0, surfaces)
	_check_gradient("mown east feather", 20.0, 39.75, surfaces)
	_check_gradient("rough interior", 60.0, -70.0, surfaces)
	var runway_edge_a: PackedFloat64Array = Terrain.sample(10.0 - 1e-6, 0.0, surfaces)
	var runway_edge_b: PackedFloat64Array = Terrain.sample(10.0 + 1e-6, 0.0, surfaces)
	_check("nested runway/mown height stays continuous", absf(runway_edge_a[0] - runway_edge_b[0]) < 1e-8)


func _test_renderer_uses_field_rectangles() -> void:
	var field: Dictionary = FieldLoader.load_from()
	if not bool(field.get("ok", false)):
		_check("default field available to renderer test", false, str(field.get("errors", [])))
		return
	var node: Node3D = FieldBuilder.build(field.field)
	var rough: MeshInstance3D = node.get_node_or_null("rough") as MeshInstance3D
	var material: ShaderMaterial = rough.material_override as ShaderMaterial if rough != null else null
	_check("ground shader terrain hook receives the same default runway rectangle",
		material != null
		and material.get_shader_parameter("terrain_relief_enabled") == true
		and material.get_shader_parameter("terrain_surface_count") == 1
		and _terrain_rect_at(material, 0) == Vector4(0.0, -15.0, 50.0, 6.0)
		and _terrain_kind_at(material, 0) == 2,
		str(material.get_shader_parameter("terrain_surface_rects")) if material != null else "no ground material")
	_check("renderer terrain profile matches physics estimates",
		material != null
		and is_equal_approx(float(material.get_shader_parameter("terrain_runway_amplitude_m")), 0.001)
		and is_equal_approx(float(material.get_shader_parameter("terrain_mown_amplitude_m")), 0.004)
		and is_equal_approx(float(material.get_shader_parameter("terrain_rough_amplitude_m")), 0.007)
		and is_equal_approx(float(material.get_shader_parameter("terrain_edge_blend_m")), 0.5)
		and is_equal_approx(float(material.get_shader_parameter("terrain_relief_start_m")), 20.0)
		and is_equal_approx(float(material.get_shader_parameter("terrain_relief_end_m")), 80.0)
		and is_equal_approx(float(material.get_shader_parameter("terrain_footprint_start_m")), 0.08)
		and is_equal_approx(float(material.get_shader_parameter("terrain_footprint_end_m")), 0.41))
	# Uncontained layouts use legacy planes. Failure must leave the supplied material byte-for-byte untouched.
	var fallback_material: ShaderMaterial = Ground.grass_material()
	var fallback_surfaces: Array[Dictionary] = [
		{"type": "rough", "center_north": 0.0, "center_east": 0.0, "length_east_west": 100.0, "width_north_south": 100.0},
		{"type": "runway", "center_north": 0.0, "center_east": 300.0, "length_east_west": 10.0, "width_north_south": 4.0},
	]
	var before_terrain_enabled: Variant = fallback_material.get_shader_parameter("terrain_relief_enabled")
	var before_terrain_count: Variant = fallback_material.get_shader_parameter("terrain_surface_count")
	var before_surface_count: Variant = fallback_material.get_shader_parameter("surface_count")
	var fallback_result: bool = Ground.configure_surfaces(fallback_material, fallback_surfaces)
	_check("failed renderer consolidation leaves terrain surface uniforms unchanged",
		not fallback_result
		and fallback_material.get_shader_parameter("terrain_relief_enabled") == before_terrain_enabled
		and fallback_material.get_shader_parameter("terrain_surface_count") == before_terrain_count
		and fallback_material.get_shader_parameter("surface_count") == before_surface_count,
		"before=%s after=%s" % [str([before_terrain_enabled, before_terrain_count, before_surface_count]), str([
			fallback_material.get_shader_parameter("terrain_relief_enabled"),
			fallback_material.get_shader_parameter("terrain_surface_count"),
			fallback_material.get_shader_parameter("surface_count")])])
	node.free()


func _test_shader_normal_orientation() -> void:
	var sample: PackedFloat64Array = Terrain.sample(9.75, 0.0, _surface_table())
	var shader_source: String = FileAccess.get_file_as_string("res://render/ground.gdshader")
	# World axes are east=+x, up=+y, south=+z; north slope therefore tilts the normal toward +z.
	var from_height_gradient := Vector3(-sample[2], 1.0, sample[1]).normalized()
	var east_view := Vector3.RIGHT
	var north_view := Vector3(0.0, 0.0, -1.0)
	var shader_cpu_mirror := (Vector3.UP - sample[2] * east_view - sample[1] * north_view).normalized()
	_check("shader normal perturbation agrees with the terrain-gradient surface normal",
		from_height_gradient.distance_to(shader_cpu_mirror) < 1e-12
		and shader_source.contains("vec3 perturbation = -relief.z * east_view - relief.y * north_view;")
		and shader_source.contains("terrain_height(vec2(-world_pos.z, world_pos.x))"),
		"gradient=%s normal=%s" % [str(sample), str(shader_cpu_mirror)])


func _test_shader_cpu_formula_agreement() -> void:
	var surfaces: PackedFloat64Array = _surface_table()
	var shader_source: String = FileAccess.get_file_as_string("res://render/ground.gdshader")
	var points: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(9.75, 0.0), Vector2(20.0, 39.75), Vector2(60.0, -70.0)]
	var matches := true
	var worst_error := 0.0
	var worst_point := Vector2.ZERO
	var worst_component := 0
	var worst_physics := PackedFloat64Array()
	var worst_renderer := PackedFloat64Array()
	for point: Vector2 in points:
		var physics_sample: PackedFloat64Array = Terrain.sample(point.x, point.y, surfaces)
		var renderer_sample: PackedFloat64Array = _shader_cpu_sample(point.x, point.y, surfaces)
		for component in 3:
			var error: float = absf(physics_sample[component] - renderer_sample[component])
			if error > worst_error:
				worst_error = error
				worst_point = point
				worst_component = component
				worst_physics = physics_sample
				worst_renderer = renderer_sample
			matches = matches and error < 1e-9
	matches = matches and shader_source.contains("0.45 * sin(6.283185307179586") \
		and shader_source.contains("0.35 * sin(6.283185307179586") \
		and shader_source.contains("0.20 * sin(6.283185307179586")
	_check("CPU mirror of shader masks, waves and NED slopes matches GroundTerrain", matches,
		"worst error=%s component=%d at north/east=%s; physics=%s renderer=%s" % [str(worst_error), worst_component, str(worst_point), str(worst_physics), str(worst_renderer)])


func _shader_cpu_sample(north: float, east: float, surfaces: PackedFloat64Array) -> PackedFloat64Array:
	# Keep this minimal CPU mirror aligned with terrain_rect_mask/terrain_amplitude/terrain_height in ground.gdshader.
	var rows: int = surfaces.size() / Terrain.SURFACE_STRIDE
	var outside: int = (rows - 1) * Terrain.SURFACE_STRIDE
	var amplitude: float = Terrain.amplitude_for_rolling_factor(surfaces[outside + 5])
	var gradient_p := Vector2.ZERO # renderer coordinates are east, -north
	var point := Vector2(east, -north)
	for row in range(rows - 2, -1, -1):
		var i: int = row * Terrain.SURFACE_STRIDE
		var nmin: float = surfaces[i]
		var nmax: float = surfaces[i + 1]
		var emin: float = surfaces[i + 2]
		var emax: float = surfaces[i + 3]
		var rect := Vector4((emin + emax) / 2.0, -(nmin + nmax) / 2.0,
			(emax - emin) / 2.0, (nmax - nmin) / 2.0)
		var low_x: PackedFloat64Array = _shader_edge(point.x - (rect.x - rect.z))
		var high_x: PackedFloat64Array = _shader_edge((rect.x + rect.z) - point.x)
		var low_y: PackedFloat64Array = _shader_edge(point.y - (rect.y - rect.w))
		var high_y: PackedFloat64Array = _shader_edge((rect.y + rect.w) - point.y)
		var mask_x: float = low_x[0] * high_x[0]
		var mask_y: float = low_y[0] * high_y[0]
		var mask: float = mask_x * mask_y
		var mask_gradient := Vector2(
			(low_x[1] * high_x[0] - low_x[0] * high_x[1]) * mask_y,
			(low_y[1] * high_y[0] - low_y[0] * high_y[1]) * mask_x)
		var target: float = Terrain.amplitude_for_rolling_factor(surfaces[i + 5])
		var difference: float = target - amplitude
		gradient_p = gradient_p * (1.0 - mask) + difference * mask_gradient
		amplitude += difference * mask
	var phase_1: float = TAU * (0.8 * north + 0.6 * east) / 1.2 + 0.17
	var phase_2: float = TAU * (-0.35 * north + 0.9367496998 * east) / 0.73 + 2.11
	var phase_3: float = TAU * (0.6 * north - 0.8 * east) / 0.41 + 4.73
	var wave: float = 0.45 * sin(phase_1) + 0.35 * sin(phase_2) + 0.20 * sin(phase_3)
	var wave_north: float = 0.45 * TAU / 1.2 * 0.8 * cos(phase_1) \
		+ 0.35 * TAU / 0.73 * -0.35 * cos(phase_2) + 0.20 * TAU / 0.41 * 0.6 * cos(phase_3)
	var wave_east: float = 0.45 * TAU / 1.2 * 0.6 * cos(phase_1) \
		+ 0.35 * TAU / 0.73 * 0.9367496998 * cos(phase_2) - 0.20 * TAU / 0.41 * 0.8 * cos(phase_3)
	var amplitude_north: float = -gradient_p.y
	var amplitude_east: float = gradient_p.x
	return PackedFloat64Array([
		amplitude * wave,
		amplitude_north * wave + amplitude * wave_north,
		amplitude_east * wave + amplitude * wave_east,
	])


func _shader_edge(distance_m: float) -> PackedFloat64Array:
	const blend := 0.5
	if distance_m <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	if distance_m >= blend:
		return PackedFloat64Array([1.0, 0.0])
	var t: float = distance_m / blend
	return PackedFloat64Array([t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t) / blend])


func _check_gradient(label: String, north: float, east: float, surfaces: PackedFloat64Array) -> void:
	var step := 1e-4
	var center: PackedFloat64Array = Terrain.sample(north, east, surfaces)
	var plus_n: PackedFloat64Array = Terrain.sample(north + step, east, surfaces)
	var minus_n: PackedFloat64Array = Terrain.sample(north - step, east, surfaces)
	var plus_e: PackedFloat64Array = Terrain.sample(north, east + step, surfaces)
	var minus_e: PackedFloat64Array = Terrain.sample(north, east - step, surfaces)
	var fd_n: float = (plus_n[0] - minus_n[0]) / (2.0 * step)
	var fd_e: float = (plus_e[0] - minus_e[0]) / (2.0 * step)
	var ok: bool = _finite_sample(center) and absf(center[1] - fd_n) < 1e-6 and absf(center[2] - fd_e) < 1e-6
	_check(label + " analytic gradient agrees with central differences", ok,
		"reported=%s finite-difference=%s" % [str([center[1], center[2]]), str([fd_n, fd_e])])


func _surface_table() -> PackedFloat64Array:
	# Surface precedence mirrors GroundSurfaces: runway first, then mown, then rough, then outside rough.
	return PackedFloat64Array([
		-10.0, 10.0, -20.0, 20.0, 0.8, 2.5,
		-30.0, 30.0, -40.0, 40.0, 0.7, 5.0,
		-100.0, 100.0, -100.0, 100.0, 0.7, 7.5,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])


func _finite_sample(sample: PackedFloat64Array) -> bool:
	return sample.size() == 3 and is_finite(sample[0]) and is_finite(sample[1]) and is_finite(sample[2])


func _terrain_rect_at(material: ShaderMaterial, index: int) -> Vector4:
	var rectangles: PackedVector4Array = material.get_shader_parameter("terrain_surface_rects")
	return rectangles[index] if index < rectangles.size() else Vector4(INF, INF, INF, INF)


func _terrain_kind_at(material: ShaderMaterial, index: int) -> int:
	var kinds: PackedInt32Array = material.get_shader_parameter("terrain_surface_kinds")
	return kinds[index] if index < kinds.size() else -1


func _check(name: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + name + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1
