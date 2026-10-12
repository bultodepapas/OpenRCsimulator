extends SceneTree

const AirfieldLighting := preload("res://render/landscape_upgrade/airfield_lighting.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Exposure := preload("res://render/world/exposure.gd")

const MARKER_SHADER_PATH := "res://render/landscape_upgrade/runway_marker.gdshader"
const EDGE_ROW := "runway_edge_stakes"
const THRESHOLD_ROW := "threshold_stakes"
const EXPECTED_ROW_SPRITES := 6 # 3 flood heads, 2 runway rows, 1 station lamp.

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("LU-09 runway marker optics: " + label + (": " + detail if not detail.is_empty() else ""))


static func _marker_display_value(authored_radiance: float, core_gain: float, display_cap: float,
		exposure: float, factor: float, range_fade: float) -> float:
	var radiance := authored_radiance * factor
	var exposure_cap := display_cap * factor / maxf(exposure, 0.001)
	return minf(radiance * core_gain, exposure_cap) * range_fade * exposure


func _initialize() -> void:
	var field_result := FieldLoader.load_from()
	var light_result := FieldLights.load_from()
	_check("field loads", field_result.ok, "; ".join(field_result.errors))
	_check("existing fixture data validates", light_result.ok, "; ".join(light_result.errors))
	if not field_result.ok or not light_result.ok:
		quit(1)
		return

	var field_lights := FieldLights.build(light_result.lights)
	var edge_node := field_lights.get_node(EDGE_ROW) as MultiMeshInstance3D
	var threshold_node := field_lights.get_node(THRESHOLD_ROW) as MultiMeshInstance3D
	var station_node := field_lights.get_node("pilot_station_lamp") as MultiMeshInstance3D
	var edge_multimesh := edge_node.multimesh
	var threshold_multimesh := threshold_node.multimesh
	var station_multimesh := station_node.multimesh
	var edge_mesh := edge_multimesh.mesh
	var threshold_mesh := threshold_multimesh.mesh
	var child_count := field_lights.get_child_count()
	var original_edge_material := edge_mesh.surface_get_material(0) as ShaderMaterial
	var original_threshold_material := threshold_mesh.surface_get_material(0) as ShaderMaterial
	var station_material := station_multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var flood_material := (field_lights.get_node("flood_west_lamp") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial

	var helper: Variant = AirfieldLighting.build(field_result.field, light_result.lights, {})
	var environment := Atmosphere.environment()
	Exposure.set_value(environment.tonemap_exposure)
	helper.bind_environment(environment, field_lights)

	_check("edge row keeps its node, MultiMesh and instance count",
		field_lights.get_node(EDGE_ROW) == edge_node and edge_node.multimesh == edge_multimesh
		and edge_multimesh.instance_count == 12)
	_check("threshold row keeps its node, MultiMesh and instance count",
		field_lights.get_node(THRESHOLD_ROW) == threshold_node and threshold_node.multimesh == threshold_multimesh
		and threshold_multimesh.instance_count == 6)
	_check("the two existing rows share the new batched shader", 
		(edge_multimesh.mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path == MARKER_SHADER_PATH
		and (threshold_multimesh.mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path == MARKER_SHADER_PATH)
	_check("other sprite materials remain unchanged",
		station_multimesh.mesh.surface_get_material(0) == station_material
		and flood_material.shader.resource_path == "res://render/world/light_sprite.gdshader")
	_check("binding adds no FieldLights nodes or physical lights",
		field_lights.get_child_count() == child_count
		and field_lights.find_children("*", "SpotLight3D", true, false).size() == 3
		and helper.find_children("*", "SpotLight3D", true, false).is_empty()
		and helper.find_children("*", "OmniLight3D", true, false).is_empty())
	_check("existing runway material references are replaced only once",
		(edge_multimesh.mesh.surface_get_material(0) as ShaderMaterial) != original_edge_material
		and (threshold_multimesh.mesh.surface_get_material(0) as ShaderMaterial) != original_threshold_material)
	_check("one shared material is used per row, with six existing sprite bindings",
		helper.get_meta("bound_sprite_materials") == EXPECTED_ROW_SPRITES)

	var edge_material := edge_multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var threshold_material := threshold_multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var shader_code := edge_material.shader.code
	_check("edge optics keep the existing 50 mm lens with restrained screen-size estimates",
		is_equal_approx(float(edge_material.get_shader_parameter("size_m")), 0.05)
		and is_equal_approx(float(edge_material.get_shader_parameter("core_min_px")), 2.5)
		and is_equal_approx(float(edge_material.get_shader_parameter("halo_min_px")), 6.5)
		and float(edge_material.get_shader_parameter("display_cap")) <= 1.0
		and is_equal_approx(float(edge_material.get_shader_parameter("readability_gain_floor")), 0.0025)
		and is_equal_approx(float(edge_material.get_shader_parameter("distance_fade_start_m")), 300.0)
		and is_equal_approx(float(edge_material.get_shader_parameter("distance_fade_end_m")), 600.0))
	_check("marker size follows the active projection and viewport", 
		shader_code.contains("VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1])")
		and shader_code.contains("view_depth = max(-center.z, 0.001)")
		and shader_code.contains("units_per_pixel = (2.0 * view_depth) / projected_pixels"))
	var cap_position := shader_code.find("float emission = min(")
	var fade_position := shader_code.find("* distance_fade;")
	_check("night cap tracks dusk and range fade is applied after the cap",
		shader_code.contains("display_cap * night_factor / max(world_exposure, 0.001)")
		and shader_code.contains("varying float distance_fade;")
		and shader_code.contains("distance_fade = 1.0 - smoothstep(distance_fade_start_m, distance_fade_end_m, distance_to_camera);")
		and cap_position >= 0 and fade_position > cap_position)
	var night_display_at_300 := _marker_display_value(100.0, 1.0, 1.0, 10.0, 1.0, 1.0)
	var night_display_at_450 := _marker_display_value(100.0, 1.0, 1.0, 10.0, 1.0, 0.5)
	var dusk_display_at_300 := _marker_display_value(100.0, 1.0, 1.0, 10.0, 0.5, 1.0)
	_check("300–600 m fade remains visible after a saturated exposure cap",
		is_equal_approx(night_display_at_450, night_display_at_300 * 0.5))
	_check("half-night dusk output remains half of night at the same exposure",
		is_equal_approx(dusk_display_at_300, night_display_at_300 * 0.5))
	_check("threshold shader uses per-instance east position and camera direction",
		bool(threshold_material.get_shader_parameter("threshold_mode"))
		and shader_code.contains("INV_VIEW_MATRIX * vec4(center, 1.0)")
		and shader_code.contains("CAMERA_POSITION_WORLD.x"))
	_check("optical quads remain depth-tested and move slightly ahead of the physical lens",
		shader_code.contains("depth_draw_never") and not shader_code.contains("depth_test_disabled")
		and float(edge_material.get_shader_parameter("camera_offset_m")) >= 0.07
		and float(edge_material.get_shader_parameter("camera_offset_m")) <= 0.08)

	# Evaluate the shader's east-axis direction rule against the committed point data at both ends, near and far.
	# `marker_east` is world X because the field's NED-to-render map puts east on X.
	var edge_fixture: Dictionary = light_result.lights.fixtures[3]
	var threshold_fixture: Dictionary = light_result.lights.fixtures[4]
	var expected_edge_points := [[9.0, -50.0], [9.0, -30.0], [9.0, -10.0], [9.0, 10.0], [9.0, 30.0], [9.0, 50.0],
		[21.0, -50.0], [21.0, -30.0], [21.0, -10.0], [21.0, 10.0], [21.0, 30.0], [21.0, 50.0]]
	var threshold_points: Array = threshold_fixture.points
	_check("existing runway point sets and sizes remain exact",
		edge_fixture.points == expected_edge_points and float(edge_fixture.size) == 0.05
		and threshold_points == [[11.0, -51.0], [15.0, -51.0], [19.0, -51.0],
			[11.0, 51.0], [15.0, 51.0], [19.0, 51.0]])
	var endpoint_indices: Array[int] = [0, 3]
	var view_samples := [
		{"label": "near outward", "offset": 8.0, "green": true},
		{"label": "far outward", "offset": 300.0, "green": true},
		{"label": "near inward", "offset": -8.0, "green": false},
		{"label": "far inward", "offset": -300.0, "green": false},
	]
	var endpoint_east_values: Array[float] = []
	for start_index in endpoint_indices:
		var point: Array = threshold_points[start_index]
		var threshold_east := Frames.ned_to_render([float(point[0]), float(point[1]), -float(threshold_fixture.height)]).x
		endpoint_east_values.append(threshold_east)
		for sample: Dictionary in view_samples:
			var camera_east := threshold_east + signf(threshold_east) * float(sample.offset)
			var outward := signf(threshold_east) * (camera_east - threshold_east) > 0.0
			_check("%s end %s resolves %s view to %s" % [
				"west" if threshold_east < 0.0 else "east", sample.label,
				"outward" if sample.green else "inward", "green" if outward else "red"],
				outward == bool(sample.green), "east=%.1f camera=%.1f" % [threshold_east, camera_east])
	_check("threshold point data remains on both east-west endpoints",
		endpoint_east_values[0] < -50.0 and endpoint_east_values[1] > 50.0)

	_check("daylight keeps optical radiance and cap off", is_zero_approx(float(edge_material.get_shader_parameter("radiance")))
		and is_zero_approx(float(threshold_material.get_shader_parameter("radiance")))
		and is_zero_approx(float(edge_material.get_shader_parameter("night_factor")))
		and is_zero_approx(float(threshold_material.get_shader_parameter("night_factor"))))
	helper.apply_lighting({"sun_elevation_deg": -0.5})
	var dusk_factor := float(helper.get_meta("night_factor"))
	_check("dusk fades both rows continuously", dusk_factor > 0.45 and dusk_factor < 0.55
		and float(edge_material.get_shader_parameter("radiance")) > 0.0
		and float(threshold_material.get_shader_parameter("radiance")) > 0.0
		and is_equal_approx(float(edge_material.get_shader_parameter("night_factor")), dusk_factor)
		and is_equal_approx(float(threshold_material.get_shader_parameter("night_factor")), dusk_factor))
	var base_radiance := float(edge_material.get_meta("lu03_base_radiance"))
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("night restores the existing edge light radiance", is_equal_approx(
		float(edge_material.get_shader_parameter("radiance")), base_radiance)
		and is_equal_approx(float(edge_material.get_shader_parameter("night_factor")), 1.0))

	environment.tonemap_exposure = 10000.0
	Exposure.set_value(10000.0)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("night keeps authored radiance until the shader applies size gain and exposure cap",
		is_equal_approx(float(edge_material.get_shader_parameter("radiance")), base_radiance)
		and is_equal_approx(float(threshold_material.get_shader_parameter("radiance")), base_radiance)
		and is_equal_approx(float(edge_material.get_shader_parameter("night_factor")), 1.0)
		and shader_code.contains("min(radiance * core_gain, exposure_cap) * distance_fade"))

	# Explicit TOD remains SDR. The scene-local gain raises the authored source, while the view cap stays fixed.
	environment.tonemap_exposure = 0.6
	Exposure.set_value(0.6)
	helper.bind_environment(environment, field_lights, 1000.0)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("TOD SDR gain reaches the shader before size gain and display capping", is_equal_approx(
		float(edge_material.get_shader_parameter("radiance")), base_radiance * 1000.0)
		and is_equal_approx(float(edge_material.get_shader_parameter("night_factor")), 1.0))
	var edge_material_id := edge_material.get_instance_id()
	var threshold_material_id := threshold_material.get_instance_id()
	helper.bind_environment(environment, field_lights, 1000.0)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("rebind reuses the same two materials and does not grow bindings",
		edge_material.get_instance_id() == edge_material_id
		and threshold_material.get_instance_id() == threshold_material_id
		and edge_multimesh.mesh.surface_get_material(0) == edge_material
		and threshold_multimesh.mesh.surface_get_material(0) == threshold_material
		and helper.get_meta("bound_sprite_materials") == EXPECTED_ROW_SPRITES)

	print("LU-09: %d checks, %d failed" % [_checks, _failures])
	helper.free()
	field_lights.free()
	quit(1 if _failures > 0 else 0)
