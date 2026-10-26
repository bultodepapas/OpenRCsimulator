extends SceneTree

const Skins := preload("res://render/lighting/lighting_skins.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check("plan ribs and spars stay dark while film bays transmit", _test_mask())
	var aircraft := Node3D.new()
	aircraft.name = "aircraft"
	root.add_child(aircraft)
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.8, 0.3, 0.15, 1.0)
	source.albedo_texture = _texture(Color.WHITE, 16)
	source.normal_enabled = true
	source.normal_texture = _texture(Color(0.5, 0.5, 1.0), 4)
	source.normal_scale = 0.45
	source.roughness = 0.22
	source.roughness_texture = _texture(Color(0.7, 0.7, 0.7), 4)
	var plane := QuadMesh.new()
	plane.material = source
	var panel_a := _mesh_instance("panel_a", plane, aircraft)
	var panel_b := _mesh_instance("panel_b", plane, aircraft)
	var unrelated_panel := _mesh_instance("unrelated_panel", plane, aircraft)
	var companion := _companion(["panel_a", "panel_b"])
	var json_companion: Variant = JSON.parse_string(JSON.stringify(companion))
	var projection: Dictionary = Skins.project_bindings(aircraft, json_companion)
	var projected_rows: Array = projection.get("bindings", [])
	var projection_warnings: Array = projection.get("warnings", [])
	_check("projection resolves only paint target IDs and reports a missing ID",
		projected_rows.size() == 1 and projected_rows[0].targets.size() == 2 \
		and projected_rows[0].targets[0].mesh == panel_a \
		and projected_rows[0].targets[1].mesh == panel_b and not projection_warnings.is_empty())
	aircraft.set_meta("lighting_skin_bindings", projected_rows)
	var old_reduced_flashes := LightingPolicy.reduced_flashes
	LightingPolicy.reduced_flashes = false
	var helper = Skins.new()
	var configured: Dictionary = helper.configure(aircraft, _profile())
	_check("supported covering materials configure without warnings",
		configured.get("ok", false) and configured.get("warnings", []).is_empty(), str(configured))
	var clone_a := panel_a.get_active_material(0) as StandardMaterial3D
	var clone_b := panel_b.get_active_material(0) as StandardMaterial3D
	_check("per-instance clones retain paint and surface maps",
		clone_a != null and clone_a != source and clone_b != null and clone_b != source \
		and clone_a.albedo_color.is_equal_approx(source.albedo_color) \
		and clone_a.albedo_texture == source.albedo_texture \
		and clone_a.normal_texture == source.normal_texture \
		and clone_a.roughness_texture == source.roughness_texture \
		and is_equal_approx(clone_a.roughness, source.roughness) \
		and unrelated_panel.get_active_material(0) == source)
	_check("the paint-tinted transmission map keeps bay paint color",
		clone_a != null and _transmitted_color_is_preserved(clone_a))
	var budget: Dictionary = helper.budget_info()
	_check("composed atlas textures are shared within this aircraft and bounded",
		budget.get("targets", 0) == 2 and budget.get("max_targets", 0) == 12 \
		and budget.get("composed_textures", 0) == 1 \
		and budget.get("composed_texture_pixel_bytes", 0) == 512 * 512 * 4 \
		and budget.get("composed_texture_mipped_bytes", 0) <= 1400000)
	var advanced: Dictionary = helper.advance(0.0, {"exposure": 1.0, "throttle": 0.0}, "all", 1.0)
	_check("profile emission uses the adapted cap", advanced.get("writes", 0) > 0 \
		and clone_a.emission_enabled and is_equal_approx(clone_a.emission_energy_multiplier, 0.15))
	helper.advance(0.1, {"exposure": 100.0, "throttle": 0.0}, "all", 1.0)
	_check("high exposure lowers emission to the exposure cap",
		is_equal_approx(clone_a.emission_energy_multiplier, 0.012))
	LightingPolicy.reduced_flashes = true
	helper.advance(0.0, {"exposure": 1.0, "throttle": 1.0}, "all", 1.0)
	var reduced_color := clone_a.emission
	var reduced_energy := clone_a.emission_energy_multiplier
	helper.advance(0.4, {"exposure": 1.0, "throttle": 1.0}, "all", 1.0)
	_check("reduced flashes use a stable base pattern and unit reaction gain",
		clone_a.emission.is_equal_approx(reduced_color) \
		and is_equal_approx(clone_a.emission_energy_multiplier, reduced_energy))
	LightingPolicy.reduced_flashes = old_reduced_flashes
	helper.advance(0.5, {"exposure": 1.0}, "nav", 1.0)
	_check("nav mode hides skin emission", not clone_a.emission_enabled \
		and is_equal_approx(clone_a.emission_energy_multiplier, 0.0))
	helper.advance(0.6, {"exposure": 1.0}, "all", 0.0)
	_check("zero night gain hides skin emission", not clone_a.emission_enabled)
	var external_override := StandardMaterial3D.new()
	panel_a.set_surface_override_material(0, external_override)
	helper.dispose()
	_check("dispose leaves a later external override alone and restores owned siblings",
		panel_a.get_surface_override_material(0) == external_override \
		and panel_b.get_surface_override_material(0) == null \
		and panel_b.get_active_material(0) == source \
		and source.emission_texture == null and not source.emission_enabled)
	var unsupported := Node3D.new()
	unsupported.name = "unsupported_root"
	root.add_child(unsupported)
	var override_primitive := QuadMesh.new()
	override_primitive.material = StandardMaterial3D.new()
	var override_mesh := _mesh_instance("material_override", override_primitive, unsupported)
	override_mesh.material_override = StandardMaterial3D.new()
	var uv_material := StandardMaterial3D.new()
	uv_material.uv1_scale = Vector3(2.0, 1.0, 1.0)
	var uv_primitive := QuadMesh.new()
	uv_primitive.material = uv_material
	var uv_mesh := _mesh_instance("uv_transform", uv_primitive, unsupported)
	var emissive_material := StandardMaterial3D.new()
	emissive_material.emission_enabled = true
	var emissive_primitive := QuadMesh.new()
	emissive_primitive.material = emissive_material
	var emissive_mesh := _mesh_instance("emissive", emissive_primitive, unsupported)
	var shader := ShaderMaterial.new()
	var unsupported_primitive := QuadMesh.new()
	unsupported_primitive.material = shader
	var unsupported_mesh := _mesh_instance("shader", unsupported_primitive, unsupported)
	var unsupported_projection: Dictionary = Skins.project_bindings(unsupported,
		_companion(["material_override", "uv_transform", "emissive", "shader"]))
	unsupported.set_meta("lighting_skin_bindings", unsupported_projection.get("bindings", []))
	var fallback = Skins.new()
	var fallback_result: Dictionary = fallback.configure(unsupported, _profile())
	_check("unsupported surfaces warn and retain their original override/material",
		fallback_result.get("warnings", []).size() >= 4 \
		and override_mesh.get_surface_override_material(0) == null \
		and override_mesh.get_active_material(0) == override_mesh.material_override \
		and uv_mesh.get_surface_override_material(0) == null and uv_mesh.get_active_material(0) == uv_material \
		and emissive_mesh.get_surface_override_material(0) == null and emissive_mesh.get_active_material(0) == emissive_material \
		and unsupported_mesh.get_surface_override_material(0) == null \
		and unsupported_mesh.get_active_material(0) == shader)
	fallback.dispose()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_mask() -> bool:
	var rib_center := Skins.mask_value(0.2294, 0.5)
	var open_bay := Skins.mask_value(0.275, 0.5)
	var main_spar := Skins.mask_value(0.275, 0.301)
	var false_rib := Skins.mask_value(0.18415, 0.07)
	var false_rib_bay := Skins.mask_value(0.18415, 0.4)
	var solid_tip := Skins.mask_value(0.70, 0.5)
	var mask := Skins._structural_mask_image()
	var wing: Dictionary = Geometry.DATA.wing
	var expected_u := 0.275 / float(wing.span) + 0.5
	var expected_v := (16.0 + 224.0 * 0.5) / 1024.0
	var uv_sample := mask.get_pixel(int(expected_u * mask.get_width()), int(expected_v * mask.get_height())).r
	return rib_center < 0.05 and open_bay > 0.95 and main_spar < 0.05 \
		and false_rib < 0.05 and false_rib_bay > 0.95 and solid_tip < 0.05 and uv_sample > 0.95


func _transmitted_color_is_preserved(material: StandardMaterial3D) -> bool:
	var texture := material.emission_texture as Texture2D
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var wing: Dictionary = Geometry.DATA.wing
	var uv := Finish.uv(Vector3(0.275, 0.0, 0.5 * float(wing.chord)), "wing")
	var pixel := image.get_pixel(int(uv.x * image.get_width()), int(uv.y * image.get_height()))
	return pixel.r > 0.65 and pixel.g > 0.2 and pixel.g < 0.4 and pixel.b > 0.05 and pixel.b < 0.25


func _mesh_instance(id: String, mesh_resource: Mesh, parent: Node3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = id
	result.mesh = mesh_resource
	parent.add_child(result)
	return result


func _texture(color: Color, size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _companion(paths: Array[String]) -> Dictionary:
	var targets: Array[Dictionary] = []
	var target_ids: Array[String] = []
	for index in paths.size():
		var id := "skin_panel_%d" % index
		target_ids.append(id)
		targets.append({"target_id": id, "node_path": paths[index], "surface": 0.0, "kind": "standard_albedo"})
	return {
		"visual_family": "jensen-das-ugly-stik-60",
		"paint_slots": [{"id": "wing", "targets": targets}],
		"lighting_layout": {"version": 2, "skins": [{
			"zone_id": "strip_left", "paint_slot_id": "wing",
			"target_ids": target_ids + ["missing_skin_target"],
			"mask_profile_id": "jensen_stik_film_bays_v1",
			"node_path": "../untrusted_path",
		}]},
	}


func _profile() -> Dictionary:
	return {
		"selection": "custom",
		"brightness": 1.0,
		"sequence": [],
		"zones": [{
			"id": "strip_left",
			"enabled": true,
			"brightness": 1.0,
			"pattern": {"id": "pulse", "palette": ["#FF0000", "#0000FF"], "period_ticks": 60,
				"floor": 0.0, "duty": 0.5},
			"reactive": {"source": "throttle", "gain": 1.0},
		}],
	}


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		print("PASS ", label)
	else:
		_failures += 1
		push_error("FAIL " + label + (": " + detail if not detail.is_empty() else ""))
