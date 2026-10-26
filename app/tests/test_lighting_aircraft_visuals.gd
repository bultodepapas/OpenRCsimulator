extends SceneTree

# Functional checks exercise the real WorkshopPreview and its actual Ugly Stik builder.
# Headless functional checks:
# python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_lighting_aircraft_visuals.gd
# Native 1920x1080 captures (PowerShell, output under ignored tmp/):
# $capture = Join-Path (Resolve-Path .\tmp).Path ("lighting-aircraft-" + [guid]::NewGuid())
# python tools/godot/run_checked.py --timeout 240 -- .tools/Godot_v4.8-beta1_win64_console.exe --path app --script res://tests/test_lighting_aircraft_visuals.gd -- "--capture-lighting-aircraft=$capture"
# Optional seven-family × six-preset visual inspection (42 frames and manifest):
# $capture = Join-Path (Resolve-Path .\tmp).Path ("lighting-fleet-" + [guid]::NewGuid())
# python tools/godot/run_checked.py --timeout 900 -- .tools/Godot_v4.8-beta1_win64_console.exe --path app --script res://tests/test_lighting_aircraft_visuals.gd -- "--capture-lighting-fleet=$capture"
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WorkshopPreview := preload("res://ui/workshop_preview.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const SkinShader := preload("res://render/lighting/rgb_skin.gdshader")
const ViewportColor := preload("res://render/viewport_color.gd")

const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const FLEET_VIEWS: Array[String] = ["overview", "upper", "lower", "front", "rear", "left", "right"]

var _checks := 0
var _failures := 0
var _capture_directory := ""
var _fleet_capture_directory := ""
var _fleet_view := "overview"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	_capture_directory = _capture_directory_from_args()
	_fleet_capture_directory = _capture_directory_from_args("--capture-lighting-fleet=")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lighting-fleet-view="):
			_fleet_view = argument.trim_prefix("--lighting-fleet-view=")
	if not FLEET_VIEWS.has(_fleet_view):
		_check("fleet view is one of the declared inspection views", false, _fleet_view)
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var preview := WorkshopPreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	await _settle(4)
	preview.set_aircraft(AIRCRAFT_ID, 1.0)
	await _settle(5)

	var aircraft_root := preview.get("_airplane_root") as Node3D
	var airplane_value: Variant = preview.get("_airplane")
	var airplane: Dictionary = airplane_value if airplane_value is Dictionary else {}
	_check("WorkshopPreview builds the requested Ugly Stik", is_instance_valid(aircraft_root)
		and not airplane.is_empty() and str(aircraft_root.get_meta("aircraft_id", "")) == AIRCRAFT_ID)
	if not is_instance_valid(aircraft_root) or airplane.is_empty():
		await _finish(preview)
		return

	var surface_records := _collect_skin_surfaces(aircraft_root)
	var layout: Variant = aircraft_root.get_meta("lighting_layout", {})
	var raw_skins: Variant = layout.get("skins", []) if layout is Dictionary else []
	var projected: Variant = aircraft_root.get_meta("lighting_skin_bindings", [])
	var warnings: Variant = aircraft_root.get_meta("lighting_skin_warnings", [])
	var zones: Dictionary = {}
	var raw_target_count := 0
	if raw_skins is Array:
		for row_value: Variant in raw_skins:
			if row_value is Dictionary:
				zones[str(row_value.get("zone_id", ""))] = true
				var target_ids: Variant = row_value.get("target_ids", [])
				if target_ids is Array:
					raw_target_count += target_ids.size()
	_check("actual aircraft metadata maps two film strips to six unique wing targets",
		raw_skins is Array and raw_skins.size() == 2 and raw_target_count == 6
		and zones.has("strip_left") and zones.has("strip_right")
		and projected is Array and projected.size() == 2 and surface_records.size() == 6
		and warnings is Array and warnings.is_empty(),
		"raw rows=%d raw targets=%d projected targets=%d warnings=%s" % [
			raw_skins.size() if raw_skins is Array else -1,
			raw_target_count,
			surface_records.size(),
			str(warnings),
		])
	_check("all six projected targets are live descendant surfaces with independent paint sources",
		_surface_records_are_valid(aircraft_root, surface_records))

	var bindings: Variant = airplane.get("customization_bindings", {})
	var base_presentation := Presentation.defaults(bindings if bindings is Dictionary else {})
	var neon := LightingProfile.preset("neon_rgb")
	var neon_presentation := _with_lighting(base_presentation, neon)
	preview.set_presentation(neon_presentation)
	preview.reset_playback()
	await _settle(3)
	var lighting_report: Dictionary = preview.get_lighting_capability_report()
	_check("the preview configures RGB lighting on the actual aircraft",
		lighting_report.get("state", "") == "configured"
		and is_instance_valid(preview.get("_lighting_rig")), str(lighting_report))
	_check("Neon RGB enables an additive film pass on all six actual targets",
		_enabled_skin_count(surface_records) == 6 and _skin_budget_targets(preview) == 6,
		"enabled=%d budget=%d" % [_enabled_skin_count(surface_records), _skin_budget_targets(preview)])
	_check("active additive-pass budget matches the six film surfaces",
		_skin_budget_active_passes(preview) == 6,
		"active passes=%d" % _skin_budget_active_passes(preview))
	_check("film emission clones preserve the original paint and leave shared materials unchanged",
		_active_skin_clones_are_isolated(surface_records))

	var classic_presentation := _with_lighting(base_presentation, LightingProfile.preset("classic_rc"))
	preview.set_presentation(classic_presentation)
	preview.reset_playback()
	await _settle(2)
	_check("Classic RC leaves the authored film skin disabled and restores every source surface",
		_skin_budget_targets(preview) == 0 and _all_skin_surfaces_off(surface_records)
		and _surfaces_match_originals(surface_records),
		"skin budget=%d" % _skin_budget_targets(preview))

	preview.set_presentation(neon_presentation)
	preview.reset_playback()
	var rig := preview.get("_lighting_rig") as Node3D
	if is_instance_valid(rig):
		rig.call("set_mode", "off", 0.0)
	await _settle(1)
	_check("OFF mode clears emission from all actual film targets", _all_skin_surfaces_off(surface_records))
	if is_instance_valid(rig):
		rig.call("set_mode", "nav", 1.0)
	await _settle(1)
	_check("NAV mode clears RGB film emission while keeping the profile configured",
		_all_skin_surfaces_off(surface_records)
		and preview.get_lighting_capability_report().get("state", "") == "configured")
	if is_instance_valid(rig):
		rig.call("set_mode", "all", 1.0)
	await _settle(1)

	preview.set_preview_night(false)
	preview.set_view_mode("compare")
	preview.set_comparison_original(true)
	await _settle(2)
	_check("Original suspends the draft skin without changing its accepted profile",
		preview.get_lighting_capability_report().get("state", "") == "original"
		and preview.get("_profile") == neon_presentation
		and _all_skin_surfaces_off(surface_records)
		and _surfaces_match_originals(surface_records))
	preview.set_comparison_original(false)
	await _settle(2)
	_check("Draft restores the configured profile and all six film skins",
		preview.get_lighting_capability_report().get("state", "") == "configured"
		and _enabled_skin_count(surface_records) == 6 and _skin_budget_targets(preview) == 6)
	preview.set_view_mode("inspect")

	var disabled := LightingProfile.defaults()
	disabled.selection = "disabled"
	preview.set_presentation(_with_lighting(base_presentation, disabled))
	await _settle(2)
	_check("disabling the profile restores all original shared material references and values",
		_surfaces_match_originals(surface_records) and _source_materials_match_snapshots(surface_records))

	if not _capture_directory.is_empty():
		await _capture_native(preview, base_presentation, surface_records)
	if not _fleet_capture_directory.is_empty():
		await _capture_fleet(preview)
	await _finish(preview)


func _collect_skin_surfaces(aircraft_root: Node3D) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var rows: Variant = aircraft_root.get_meta("lighting_skin_bindings", [])
	if not (rows is Array):
		return records
	for row_value: Variant in rows:
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value
		var targets: Variant = row.get("targets", [])
		if not (targets is Array):
			continue
		for target_value: Variant in targets:
			if not (target_value is Dictionary):
				continue
			var target: Dictionary = target_value
			var mesh := target.get("mesh") as MeshInstance3D
			var surface := int(target.get("surface", -1))
			if not is_instance_valid(mesh) or mesh.mesh == null or surface < 0 or surface >= mesh.mesh.get_surface_count():
				continue
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			records.append({
				"zone_id": str(row.get("zone_id", "")),
				"target_id": str(target.get("target_id", "")),
				"mesh": mesh,
				"surface": surface,
				"original_override": mesh.get_surface_override_material(surface),
				"original_active": mesh.get_active_material(surface),
				"source": source,
				"source_snapshot": _material_snapshot(source),
				"mesh_override": mesh.material_override,
			})
	return records


func _surface_records_are_valid(aircraft_root: Node3D, records: Array[Dictionary]) -> bool:
	if records.size() != 6:
		return false
	var seen: Dictionary = {}
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var target_id := str(record.get("target_id", ""))
		var source := record.get("source") as StandardMaterial3D
		if target_id.is_empty() or seen.has(target_id) or not is_instance_valid(mesh):
			return false
		if mesh != aircraft_root and not aircraft_root.is_ancestor_of(mesh):
			return false
		if source == null or mesh.material_override != null:
			return false
		seen[target_id] = true
	return true


func _with_lighting(base: Dictionary, lighting: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	result["lighting"] = lighting.duplicate(true)
	return result


func _skin_budget_targets(preview: Control) -> int:
	var rig := preview.get("_lighting_rig") as Node3D
	if not is_instance_valid(rig):
		return 0
	var budget: Variant = rig.call("budget_info")
	var skins: Variant = budget.get("skins", {}) if budget is Dictionary else {}
	return int(skins.get("targets", 0)) if skins is Dictionary else 0


func _skin_budget_active_passes(preview: Control) -> int:
	var rig := preview.get("_lighting_rig") as Node3D
	if not is_instance_valid(rig):
		return 0
	var budget: Variant = rig.call("budget_info")
	var skins: Variant = budget.get("skins", {}) if budget is Dictionary else {}
	return int(skins.get("active_emission_passes", 0)) if skins is Dictionary else 0


func _enabled_skin_count(records: Array[Dictionary]) -> int:
	var count := 0
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var surface := int(record.get("surface", -1))
		if not is_instance_valid(mesh) or surface < 0 or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
			continue
		var material := mesh.get_active_material(surface) as StandardMaterial3D
		if material == null or material == record.get("source"):
			continue
		var overlay := material.next_pass as ShaderMaterial
		if overlay != null and overlay.shader == SkinShader \
				and float(overlay.get_shader_parameter("energy")) > 0.0:
			count += 1
	return count


func _all_skin_surfaces_off(records: Array[Dictionary]) -> bool:
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var surface := int(record.get("surface", -1))
		if not is_instance_valid(mesh) or surface < 0 or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
			return false
		var material := mesh.get_active_material(surface) as StandardMaterial3D
		if material == null or material.emission_enabled:
			return false
		if material != record.get("source") and material.next_pass != null:
			return false
	return true


func _active_skin_clones_are_isolated(records: Array[Dictionary]) -> bool:
	if records.size() != 6:
		return false
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var surface := int(record.get("surface", -1))
		var source := record.get("source") as StandardMaterial3D
		var clone := mesh.get_active_material(surface) as StandardMaterial3D if is_instance_valid(mesh) else null
		var overlay := clone.next_pass as ShaderMaterial if clone != null else null
		if source == null or clone == null or clone == source or mesh.get_surface_override_material(surface) != clone:
			return false
		if overlay == null or overlay.shader != SkinShader:
			return false
		if clone.albedo_texture != source.albedo_texture or not clone.albedo_color.is_equal_approx(source.albedo_color) \
				or clone.normal_texture != source.normal_texture or clone.roughness_texture != source.roughness_texture \
				or not is_equal_approx(clone.roughness, source.roughness) \
				or clone.emission_enabled != source.emission_enabled \
				or clone.emission_texture != source.emission_texture \
				or clone.next_pass == source.next_pass:
			return false
		if not _material_matches_snapshot(source, record.get("source_snapshot", {})):
			return false
		if mesh.material_override != record.get("mesh_override"):
			return false
	return true


func _surfaces_match_originals(records: Array[Dictionary]) -> bool:
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var surface := int(record.get("surface", -1))
		if not is_instance_valid(mesh) or surface < 0 or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
			return false
		if mesh.get_surface_override_material(surface) != record.get("original_override"):
			return false
		if mesh.get_active_material(surface) != record.get("original_active"):
			return false
		if mesh.material_override != record.get("mesh_override"):
			return false
	return true


func _source_materials_match_snapshots(records: Array[Dictionary]) -> bool:
	for record: Dictionary in records:
		var source := record.get("source") as StandardMaterial3D
		if source == null or not _material_matches_snapshot(source, record.get("source_snapshot", {})):
			return false
	return true


func _material_snapshot(material: StandardMaterial3D) -> Dictionary:
	if material == null:
		return {}
	return {
		"albedo_color": material.albedo_color,
		"albedo_texture": material.albedo_texture,
		"normal_texture": material.normal_texture,
		"roughness_texture": material.roughness_texture,
		"roughness": material.roughness,
		"metallic": material.metallic,
		"transparency": material.transparency,
		"cull_mode": material.cull_mode,
		"vertex_color_use_as_albedo": material.vertex_color_use_as_albedo,
		"next_pass": material.next_pass,
		"emission_enabled": material.emission_enabled,
		"emission_texture": material.emission_texture,
		"emission": material.emission,
		"emission_energy": material.emission_energy_multiplier,
	}


func _material_matches_snapshot(material: StandardMaterial3D, snapshot: Dictionary) -> bool:
	return not snapshot.is_empty() \
		and material.albedo_color.is_equal_approx(snapshot.get("albedo_color", Color.BLACK)) \
		and material.albedo_texture == snapshot.get("albedo_texture") \
		and material.normal_texture == snapshot.get("normal_texture") \
		and material.roughness_texture == snapshot.get("roughness_texture") \
		and is_equal_approx(material.roughness, float(snapshot.get("roughness", NAN))) \
		and is_equal_approx(material.metallic, float(snapshot.get("metallic", NAN))) \
		and material.transparency == int(snapshot.get("transparency", -1)) \
		and material.cull_mode == int(snapshot.get("cull_mode", -1)) \
		and material.vertex_color_use_as_albedo == bool(snapshot.get("vertex_color_use_as_albedo", true)) \
		and material.next_pass == snapshot.get("next_pass") \
		and material.emission_enabled == bool(snapshot.get("emission_enabled", true)) \
		and material.emission_texture == snapshot.get("emission_texture") \
		and material.emission.is_equal_approx(snapshot.get("emission", Color.BLACK)) \
		and is_equal_approx(material.emission_energy_multiplier, float(snapshot.get("emission_energy", NAN)))


func _fleet_representatives() -> Array[Dictionary]:
	var families: PackedStringArray = Catalog.airplane_visual_families()
	_check("aircraft catalog exposes seven supported airplane visual families", families.size() == 7,
		str(families))
	var representatives_by_family: Dictionary = {}
	for aircraft_id: String in Catalog.ids():
		if Catalog.is_rotorcraft(aircraft_id):
			continue
		var entry: Dictionary = Catalog.entry(aircraft_id)
		var family := str(entry.get("visual_family", ""))
		if family.is_empty() or representatives_by_family.has(family):
			continue
		representatives_by_family[family] = {"aircraft_id": aircraft_id, "catalog_entry": entry}
	var result: Array[Dictionary] = []
	for family: String in families:
		var representative: Dictionary = representatives_by_family.get(family, {})
		_check("catalog has an airplane representative for %s" % family, not representative.is_empty())
		if representative.is_empty():
			continue
		representative["visual_family"] = family
		result.append(representative)
	return result


func _set_fleet_view(preview: Control, view_id: String) -> Dictionary:
	preview.call("reset_view")
	# Preserve the original fleet overview; every other view uses the same framing API.
	preview.call("orbit_by", 32.0, -24.0)
	var state := preview.call("get_view_state") as Dictionary
	match view_id:
		"upper": state["pitch_deg"] = 62.0
		"lower": state["pitch_deg"] = -62.0
		"front":
			preview.call("set_standard_view", "front")
			return preview.call("get_view_state") as Dictionary
		"rear":
			state["yaw_deg"] = 0.0
			state["pitch_deg"] = 0.0
		"left", "right":
			state["yaw_deg"] = 270.0 if view_id == "left" else 90.0
			state["pitch_deg"] = 0.0
	preview.call("restore_view_state", state)
	return preview.call("get_view_state") as Dictionary


func _fleet_camera_evidence(preview: Control, view_id: String) -> Dictionary:
	var camera := preview.get("_camera") as Camera3D
	var model_root := preview.get("_airplane_root") as Node3D
	var bounds: AABB = preview.get("_model_bounds")
	if not is_instance_valid(camera) or not is_instance_valid(model_root) or not bounds.is_finite():
		return {"valid": false}
	var position := camera.position
	var direction_valid := position.is_finite() and position.length() > 0.0
	match view_id:
		"upper": direction_valid = direction_valid and position.y > 0.0
		"lower": direction_valid = direction_valid and position.y < 0.0
		"front": direction_valid = direction_valid and position.z < 0.0
		"rear": direction_valid = direction_valid and position.z > 0.0
		"left": direction_valid = direction_valid and position.x < 0.0
		"right": direction_valid = direction_valid and position.x > 0.0
	var corners_in_view := 0
	var projected_corners: Array = []
	for index in 8:
		var point := model_root.global_transform * bounds.get_endpoint(index)
		var pixel := camera.unproject_position(point)
		var depth := -camera.to_local(point).z
		if pixel.is_finite() and depth >= camera.near and depth <= camera.far \
				and pixel.x >= 0.0 and pixel.y >= 0.0 and pixel.x <= CAPTURE_SIZE.x and pixel.y <= CAPTURE_SIZE.y:
			corners_in_view += 1
		projected_corners.append([pixel.x, pixel.y])
	return {"valid": direction_valid and corners_in_view == 8,
		"bounds_corners_in_view": corners_in_view, "projected_bounds_corners_px": projected_corners,
		"position_m": [position.x, position.y, position.z],
		"fov_deg": camera.fov, "near_m": camera.near, "far_m": camera.far,
		"viewport_hdr_2d": camera.get_viewport().use_hdr_2d}


func _fleet_placement_vector(value: Variant) -> Variant:
	if typeof(value) != TYPE_VECTOR3:
		return null
	var point: Vector3 = value
	return [float(point.x), float(point.y), float(point.z)]


func _fleet_tip_layout(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var tip: Dictionary = value
	return {
		"centre_m": _fleet_placement_vector(tip.get("centre")),
		"trailing_m": _fleet_placement_vector(tip.get("trailing")),
		"leading_z_m": float(tip.get("leading_z", 0.0)),
	}


func _fleet_placement_evidence(aircraft_root: Node3D) -> Dictionary:
	var kit := aircraft_root.get_node_or_null("NightKit") as Node3D
	var evidence := {
		"night_kit_present": is_instance_valid(kit),
		"node_positions_root_local_m": {},
		"geometry_layout_root_local_m": {},
	}
	if not is_instance_valid(kit):
		return evidence

	var node_positions: Dictionary = {}
	for node_name: String in ["nav_left", "nav_right", "nav_tail", "strobe_left", "strobe_right", "strobe_dorsal", "strobe_ventral"]:
		var node := kit.get_node_or_null(node_name) as Node3D
		node_positions[node_name] = _fleet_placement_vector(aircraft_root.to_local(node.global_position)) \
			if is_instance_valid(node) else null
	evidence["node_positions_root_local_m"] = node_positions

	var layout_value: Variant = kit.get_meta("geometry_layout", {})
	if typeof(layout_value) != TYPE_DICTIONARY:
		return evidence
	var layout: Dictionary = layout_value
	var bounds_value: Variant = layout.get("bounds")
	if typeof(bounds_value) != TYPE_AABB:
		return evidence
	var bounds: AABB = bounds_value
	evidence["geometry_layout_root_local_m"] = {
		"bounds": {
			"position_m": _fleet_placement_vector(bounds.position),
			"size_m": _fleet_placement_vector(bounds.size),
			"end_m": _fleet_placement_vector(bounds.end),
		},
		"left": _fleet_tip_layout(layout.get("left")),
		"right": _fleet_tip_layout(layout.get("right")),
	}
	return evidence


func _capture_fleet(preview: Control) -> void:
	if DisplayServer.get_name() == "headless":
		_check("native fleet capture has a display session", false)
		return
	root.size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
	await _settle(3)
	var container := preview.get("_viewport_container") as SubViewportContainer
	var viewport := preview.get("_viewport") as SubViewport
	if not is_instance_valid(container) or not is_instance_valid(viewport):
		_check("WorkshopPreview exposes its real SubViewport for fleet capture", false)
		return
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle(2)
	container.stretch = false
	viewport.size = CAPTURE_SIZE
	_check("fleet capture uses exact 1920x1080 root and aircraft viewports",
		root.size == CAPTURE_SIZE and viewport.size == CAPTURE_SIZE,
		"root=%s subviewport=%s" % [root.size, viewport.size])

	var representatives := _fleet_representatives()
	var family_ids: Array[String] = []
	for family: String in Catalog.airplane_visual_families():
		family_ids.append(family)
	var renderer_identity := {
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"engine": Engine.get_version_info(),
	}
	var captures: Array[Dictionary] = []
	var preview_exposure := 8.0
	var fixture_clock := {"tick": 1925, "frequency_hz": 240, "seconds": 1925.0 / 240.0}
	var preview_environment := preview.get("_preview_environment") as Environment
	if not is_instance_valid(preview_environment):
		_check("WorkshopPreview exposes its local environment for fleet capture", false)
		return
	preview.call("set_preview_night", true)
	preview_environment.tonemap_exposure = preview_exposure

	for representative: Dictionary in representatives:
		var aircraft_id := str(representative.get("aircraft_id", ""))
		var family := str(representative.get("visual_family", ""))
		var catalog_entry: Dictionary = representative.get("catalog_entry", {})
		preview.call("set_aircraft", aircraft_id, 1.0)
		await _settle(5)
		var root_node := preview.get("_airplane_root") as Node3D
		var airplane_value: Variant = preview.get("_airplane")
		var airplane: Dictionary = airplane_value if airplane_value is Dictionary else {}
		_check("fleet preview builds catalog aircraft %s" % aircraft_id,
			is_instance_valid(root_node) and not airplane.is_empty()
			and str(airplane.get("aircraft_id", "")) == aircraft_id
			and str(airplane.get("visual_family", "")) == family
			and str(root_node.get_meta("aircraft_id", "")) == aircraft_id,
			"family=%s build_keys=%s" % [family, str(airplane.keys())])
		if not is_instance_valid(root_node) or airplane.is_empty():
			continue

		var bindings_value: Variant = airplane.get("customization_bindings", {})
		var bindings: Dictionary = bindings_value if bindings_value is Dictionary else {}
		var base_presentation := Presentation.defaults(bindings)
		var model_manifest_value: Variant = airplane.get("model_manifest", {})
		var model_manifest: Dictionary = model_manifest_value if model_manifest_value is Dictionary else {}
		var builder_value: Variant = model_manifest.get("builder", {})
		var builder: Dictionary = builder_value if builder_value is Dictionary else {}
		var source_identities := {
			"catalog_script": "res://app_state/aircraft_catalog.gd",
			"catalog_data": str(catalog_entry.get("data", "")),
			"visual_family": family,
			"model_manifest": "res://data/aircraft_models/%s.json" % family,
			"model_manifest_sha256": str(airplane.get("model_manifest_sha256", "")),
			"model_manifest_dependencies": model_manifest.get("dependencies", []),
			"builder_script": str(builder.get("script", "")),
			"customization_slots_sha256": str(airplane.get("customization_slots_sha256", "")),
			"presentation_sources": bindings.get("presentation_sources", []),
		}
		_check("fleet presentation uses the model's validated customization bindings for %s" % aircraft_id,
			str(bindings.get("visual_family", "")) == family
			and not str(source_identities.model_manifest_sha256).is_empty()
			and not str(source_identities.customization_slots_sha256).is_empty(), str(source_identities))

		var fixed_view := _set_fleet_view(preview, _fleet_view)
		for preset_id: String in LightingProfile.PRESET_IDS:
			var profile := LightingProfile.preset(preset_id)
			if profile.is_empty():
				_check("fleet preset %s loads" % preset_id, false)
				continue
			preview.call("set_presentation", _with_lighting(base_presentation, profile))
			preview.call("reset_playback")
			preview.call("restore_view_state", fixed_view)
			preview.call("set_preview_night", true)
			preview_environment.tonemap_exposure = preview_exposure
			_set_fixture_clock(preview)
			await _settle_capture()

			var capability: Dictionary = preview.call("get_lighting_capability_report")
			var rig_budget: Dictionary = _lighting_rig_budget(preview)
			var image_name := "%s__%s.png" % [aircraft_id, preset_id]
			var capture_path := _fleet_capture_directory.path_join(image_name)
			var saved := await _save_capture(viewport, capture_path)
			var same_view: bool = preview.call("get_view_state") == fixed_view
			var camera_evidence := _fleet_camera_evidence(preview, _fleet_view)
			var placement_evidence := _fleet_placement_evidence(root_node)
			var at_fixture_clock: bool = int(preview.get("_playhead_tick")) == 1925 \
				and is_equal_approx(float(preview.get("_playhead_seconds")), 1925.0 / 240.0) \
				and not bool(preview.get("_playing"))
			_check("fleet frame %s / %s holds preview clock, local exposure and camera" % [aircraft_id, preset_id],
				same_view and bool(camera_evidence.get("valid", false)) and at_fixture_clock
				and is_equal_approx(preview_environment.tonemap_exposure, preview_exposure),
			"view=%s tick=%s exposure=%s" % [same_view, preview.get("_playhead_tick"), preview_environment.tonemap_exposure])
			captures.append({
				"aircraft_id": aircraft_id,
				"visual_family": family,
				"preset_id": preset_id,
				"preset_revision": int(profile.get("preset_revision", 0)),
				"file": image_name,
				"saved": saved,
				"dimensions": {"width": CAPTURE_SIZE.x, "height": CAPTURE_SIZE.y},
				"renderer": renderer_identity,
				"preview_exposure": preview_exposure,
				"exposure_context": "WorkshopPreview local night preview; not real-flight exposure",
				"fixture_clock": fixture_clock,
				"camera": fixed_view,
				"view_id": _fleet_view,
				"camera_evidence": camera_evidence,
				"placement_evidence": placement_evidence,
				"capability_report": capability,
				"rig_budget": rig_budget,
				"source_identities": source_identities,
			})

	var expected_capture_count := representatives.size() * LightingProfile.PRESET_IDS.size()
	_check("fleet preset capture covers all seven airplane families and six presets",
		families_match(family_ids, representatives) and captures.size() == expected_capture_count
		and expected_capture_count == 42,
		"families=%s representatives=%d captures=%d expected=%d" % [family_ids, representatives.size(), captures.size(), expected_capture_count])
	var manifest := {
		"format": "openrc-lighting-fleet-capture",
		"version": 1,
		"scope": "visual preset inspection; no RGB support claim is made for unsupported aircraft",
		"representative_rule": "first non-rotorcraft catalog ID in each Catalog.airplane_visual_families() family",
		"aircraft_visual_families": family_ids,
		"preset_ids": LightingProfile.PRESET_IDS,
		"view_id": _fleet_view,
		"capture_dimensions": {"width": CAPTURE_SIZE.x, "height": CAPTURE_SIZE.y},
		"renderer": renderer_identity,
		"preview_exposure": preview_exposure,
		"exposure_context": "WorkshopPreview local night preview; not real-flight exposure",
		"fixture_clock": fixture_clock,
		"captures": captures,
	}
	var manifest_path := _fleet_capture_directory.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		_check("fleet capture writes its JSON manifest", false,
			"%s (%s)" % [manifest_path, error_string(FileAccess.get_open_error())])
	else:
		manifest_file.store_string(JSON.stringify(manifest, "  ", true, true))
		manifest_file.flush()
		manifest_file.close()
		_check("fleet capture writes its JSON manifest", FileAccess.file_exists(manifest_path), manifest_path)


func families_match(families: Array[String], representatives: Array[Dictionary]) -> bool:
	if families.size() != 7 or representatives.size() != families.size():
		return false
	var seen: Dictionary = {}
	for representative: Dictionary in representatives:
		var family := str(representative.get("visual_family", ""))
		if not families.has(family) or seen.has(family):
			return false
		seen[family] = true
	return seen.size() == families.size()


func _lighting_rig_budget(preview: Control) -> Dictionary:
	var rig := preview.get("_lighting_rig") as Node3D
	if not is_instance_valid(rig):
		return {}
	var budget: Variant = rig.call("budget_info")
	return budget if budget is Dictionary else {}


func _capture_directory_from_args(argument_prefix := "--capture-lighting-aircraft=") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with(argument_prefix):
			continue
		var raw_path := argument.trim_prefix(argument_prefix).strip_edges()
		var normalized := raw_path.replace("\\", "/").simplify_path()
		var repository := ProjectSettings.globalize_path("res://..").replace("\\", "/").trim_suffix("/").to_lower()
		var ignored_tmp := repository.path_join("tmp")
		var normalized_lower := normalized.to_lower()
		var inside_repository := normalized_lower == repository or normalized_lower.begins_with(repository + "/")
		var inside_ignored_tmp := normalized_lower == ignored_tmp or normalized_lower.begins_with(ignored_tmp + "/")
		if not raw_path.is_absolute_path() or (inside_repository and not inside_ignored_tmp):
			_check("capture path is absolute and either outside the repository or under ignored tmp/", false, raw_path)
			return ""
		if DisplayServer.get_name() == "headless":
			_check("native lighting captures require a display session", false)
			return ""
		var error := DirAccess.make_dir_recursive_absolute(normalized)
		if error != OK:
			_check("capture directory can be created", false, "%s (%s)" % [normalized, error_string(error)])
			return ""
		return normalized
	return ""


func _capture_native(preview: Control, base_presentation: Dictionary, records: Array[Dictionary]) -> void:
	if DisplayServer.get_name() == "headless":
		_check("native lighting capture has a display session", false)
		return
	root.size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
	await _settle(3)
	var container := preview.get("_viewport_container") as SubViewportContainer
	var viewport := preview.get("_viewport") as SubViewport
	if not is_instance_valid(container) or not is_instance_valid(viewport):
		_check("WorkshopPreview exposes its real SubViewport for native capture", false)
		return
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle(2)
	container.stretch = false
	viewport.size = CAPTURE_SIZE
	preview.call("reset_view")
	preview.call("orbit_by", 32.0, -24.0)
	var fixed_view := preview.call("get_view_state") as Dictionary
	var neon_presentation := _with_lighting(base_presentation, LightingProfile.preset("neon_rgb"))
	preview.call("set_preview_night", true)
	preview.call("_refresh_camera")
	preview.call("_request_redraw")

	_check("native lighting capture uses exact 1920x1080 root and aircraft viewports",
		root.size == CAPTURE_SIZE and viewport.size == CAPTURE_SIZE,
		"root=%s subviewport=%s" % [root.size, viewport.size])
	for preset_id: String in LightingProfile.PRESET_IDS:
		var profile := LightingProfile.preset(preset_id)
		if profile.is_empty():
			_check("preset %s loads for capture" % preset_id, false)
			continue
		preview.call("set_presentation", _with_lighting(base_presentation, profile))
		preview.call("reset_playback")
		preview.call("restore_view_state", fixed_view)
		_set_fixture_clock(preview)
		await _settle_capture()
		var same_view: bool = preview.call("get_view_state") == fixed_view
		var at_same_clock: bool = int(preview.get("_playhead_tick")) == 1925 \
			and is_equal_approx(float(preview.get("_playhead_seconds")), 1925.0 / 240.0) \
			and not bool(preview.get("_playing"))
		_check("%s capture uses the shared camera and held 8.0208-second fixture clock" % preset_id,
			same_view and at_same_clock)
		_check("%s capture is a full 1920x1080 rendered frame" % preset_id,
			await _save_capture(viewport, _capture_directory.path_join("%s-night.png" % preset_id)))

	var disabled := LightingProfile.defaults()
	disabled.selection = "disabled"
	for view: Dictionary in [
		{"name": "upper", "pitch": 62.0},
		{"name": "lower", "pitch": -62.0},
	]:
		var view_state := fixed_view.duplicate(true)
		view_state["pitch_deg"] = float(view.pitch)
		view_state["standard_view"] = "custom"
		preview.call("restore_view_state", view_state)
		preview.call("set_presentation", _with_lighting(base_presentation, disabled))
		preview.call("reset_playback")
		preview.call("set_preview_night", false)
		_set_fixture_clock(preview)
		await _settle_capture()
		_check("%s daytime unlit film shows the opaque source surfaces" % view.name,
			_all_skin_surfaces_off(records) and _surfaces_match_originals(records))
		_check("%s daytime unlit film comparison saves at 1920x1080" % view.name,
			await _save_capture(viewport, _capture_directory.path_join("film-%s-unlit-day.png" % view.name)))
		preview.call("set_preview_night", true)
		_set_fixture_clock(preview)
		await _settle_capture()
		_check("%s nighttime unlit film comparison saves at 1920x1080" % view.name,
			await _save_capture(viewport, _capture_directory.path_join("film-%s-unlit-night.png" % view.name)))

		preview.call("set_presentation", neon_presentation)
		preview.call("reset_playback")
		preview.call("restore_view_state", view_state)
		preview.call("set_preview_night", false)
		_set_fixture_clock(preview)
		await _settle_capture()
		_check("%s daytime lit film enables all six real skins" % view.name,
			_enabled_skin_count(records) == 6 and int(preview.get("_playhead_tick")) == 1925)
		_check("%s daytime lit film comparison saves at 1920x1080" % view.name,
			await _save_capture(viewport, _capture_directory.path_join("film-%s-lit-day.png" % view.name)))
		preview.call("set_preview_night", true)
		_set_fixture_clock(preview)
		await _settle_capture()
		_check("%s nighttime lit film comparison saves at 1920x1080" % view.name,
			await _save_capture(viewport, _capture_directory.path_join("film-%s-lit-night.png" % view.name)))

	await _check_skin_exposure_parity(preview, base_presentation, fixed_view, viewport)


func _check_skin_exposure_parity(
	preview: Control,
	base_presentation: Dictionary,
	fixed_view: Dictionary,
	viewport: SubViewport
) -> void:
	var environment := preview.get("_preview_environment") as Environment
	var aircraft_root := preview.get("_airplane_root") as Node3D
	var kit := aircraft_root.get_node_or_null("NightKit") as Node3D if is_instance_valid(aircraft_root) else null
	if not is_instance_valid(environment) or not is_instance_valid(kit):
		_check("exposure parity fixture has the preview environment and aircraft kit", false)
		return
	var profile := LightingProfile.preset("night_radian")
	profile["selection"] = "custom"
	profile["brightness"] = 1.0
	var zones: Array = profile.get("zones", []).duplicate(true)
	for index in zones.size():
		var zone: Dictionary = zones[index].duplicate(true)
		var zone_id := str(zone.get("id", ""))
		if zone_id in ["strip_left", "strip_right"]:
			zone["enabled"] = true
			zone["brightness"] = 1.0
			var pattern: Dictionary = zone.get("pattern", {}).duplicate(true)
			pattern["id"] = "steady"
			pattern["palette"] = ["#FFFFFF"]
			pattern["floor"] = 1.0
			pattern["duty"] = 0.5
			zone["pattern"] = pattern
		else:
			zone["enabled"] = false
		zones[index] = zone
	profile["zones"] = zones
	profile["effects"] = []
	preview.call("set_presentation", _with_lighting(base_presentation, profile))
	preview.call("reset_playback")
	preview.call("restore_view_state", fixed_view)
	preview.call("set_preview_night", true)
	_set_fixture_clock(preview)

	var key_light := preview.get("_preview_key_light") as DirectionalLight3D
	var fill_light := preview.get("_preview_fill_light") as DirectionalLight3D
	var original_background_mode := environment.background_mode
	var original_background := environment.background_color
	var original_ambient_color := environment.ambient_light_color
	var original_ambient := environment.ambient_light_energy
	var original_key_energy := key_light.light_energy if is_instance_valid(key_light) else 0.0
	var original_fill_energy := fill_light.light_energy if is_instance_valid(fill_light) else 0.0
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_energy = 0.0
	if is_instance_valid(key_light):
		key_light.light_energy = 0.0
	if is_instance_valid(fill_light):
		fill_light.light_energy = 0.0

	var child_visibility: Array[Dictionary] = []
	for child in kit.get_children():
		if child is Node3D:
			child_visibility.append({"node": child, "visible": child.visible})
			child.visible = false
	var signals: Array[float] = []
	for exposure in [8.0, 12157.033203125]:
		environment.tonemap_exposure = exposure
		preview.call("_advance_lighting", false)
		for child in kit.get_children():
			if child is Node3D:
				child.visible = false
		await _settle_capture()
		signals.append(_skin_glow_mean(viewport.get_texture().get_image()))

	var reference_signal := signals[0] if signals.size() > 0 else 0.0
	var flight_signal := signals[1] if signals.size() > 1 else 0.0
	var relative_error := absf(reference_signal - flight_signal) / maxf(maxf(reference_signal, flight_signal), 0.000001)
	print("Skin emission signal at exposure 8 and 12157: %.6f / %.6f" % [reference_signal, flight_signal])
	_check("skin additive signal is exposure-invariant from preview 8 to captured flight exposure",
		reference_signal > 0.001 and flight_signal > 0.001 and relative_error <= 0.15,
		"signal8=%.6f signal12157=%.6f relative_error=%.4f" % [
			reference_signal, flight_signal, relative_error,
		])

	for state: Dictionary in child_visibility:
		var child := state.get("node") as Node3D
		if is_instance_valid(child):
			child.visible = bool(state.get("visible", true))
	environment.background_mode = original_background_mode
	environment.background_color = original_background
	environment.ambient_light_color = original_ambient_color
	environment.ambient_light_energy = original_ambient
	environment.tonemap_exposure = 8.0
	if is_instance_valid(key_light):
		key_light.light_energy = original_key_energy
	if is_instance_valid(fill_light):
		fill_light.light_energy = original_fill_energy


func _skin_glow_mean(image: Image) -> float:
	if image == null or image.is_empty():
		return 0.0
	var x0 := image.get_width() / 4
	var x1 := image.get_width() * 3 / 4
	var y0 := image.get_height() / 4
	var y1 := image.get_height() * 3 / 4
	var total := 0.0
	var samples := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var color := image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			samples += 1
	return total / float(samples) if samples > 0 else 0.0


func _set_fixture_clock(preview: Control) -> void:
	preview.set("_playing", false)
	preview.set("_playhead_tick", 1925)
	preview.set("_playhead_seconds", 1925.0 / 240.0)
	preview.call("_advance_lighting", true)
	preview.call("_advance_lighting", true)
	preview.call("_request_redraw")


func _save_capture(viewport: SubViewport, path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image = ViewportColor.display_image(image, viewport.use_hdr_2d)
	if image == null or image.get_size() != CAPTURE_SIZE:
		_check("capture frame has exact 1920x1080 dimensions", false,
			"%s: %s" % [path, image.get_size() if image != null else Vector2i.ZERO])
		return false
	var error := image.save_png(path)
	_check("capture saved outside the repository", error == OK, "%s (%s)" % [path, error_string(error)])
	return error == OK


func _settle_capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await process_frame


func _finish(preview: Control) -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	await process_frame
	print("Lighting aircraft visuals: %d checks, %d failures" % [_checks, _failures])
	quit(_failures)


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		print("PASS ", label)
	else:
		_failures += 1
		push_error("FAIL " + label + (": " + detail if not detail.is_empty() else ""))
