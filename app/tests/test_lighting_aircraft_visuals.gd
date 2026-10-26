extends SceneTree

# Functional checks exercise the real WorkshopPreview and its actual Ugly Stik builder.
# Headless functional checks:
# python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_lighting_aircraft_visuals.gd
# Native 1920x1080 captures (PowerShell, output under ignored tmp/):
# $capture = Join-Path (Resolve-Path .\tmp).Path ("lighting-aircraft-" + [guid]::NewGuid())
# python tools/godot/run_checked.py --timeout 240 -- .tools/Godot_v4.8-beta1_win64_console.exe --path app --script res://tests/test_lighting_aircraft_visuals.gd -- "--capture-lighting-aircraft=$capture"
const WorkshopPreview := preload("res://ui/workshop_preview.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const CAPTURE_SIZE := Vector2i(1920, 1080)

var _checks := 0
var _failures := 0
var _capture_directory := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	_capture_directory = _capture_directory_from_args()
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
	_check("Neon RGB enables per-instance film emission on all six actual targets",
		_enabled_skin_count(surface_records) == 6 and _skin_budget_targets(preview) == 6,
		"enabled=%d budget=%d" % [_enabled_skin_count(surface_records), _skin_budget_targets(preview)])
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


func _enabled_skin_count(records: Array[Dictionary]) -> int:
	var count := 0
	for record: Dictionary in records:
		var mesh := record.get("mesh") as MeshInstance3D
		var surface := int(record.get("surface", -1))
		if not is_instance_valid(mesh) or surface < 0 or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
			continue
		var material := mesh.get_active_material(surface) as StandardMaterial3D
		if material != null and material != record.get("source") and material.emission_enabled \
				and material.emission_texture != null and material.emission_energy_multiplier > 0.0:
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
		if material != record.get("source") and material.emission_energy_multiplier > 0.000001:
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
		if source == null or clone == null or clone == source or mesh.get_surface_override_material(surface) != clone:
			return false
		if clone.albedo_texture != source.albedo_texture or not clone.albedo_color.is_equal_approx(source.albedo_color):
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
		and material.emission_enabled == bool(snapshot.get("emission_enabled", true)) \
		and material.emission_texture == snapshot.get("emission_texture") \
		and material.emission.is_equal_approx(snapshot.get("emission", Color.BLACK)) \
		and is_equal_approx(material.emission_energy_multiplier, float(snapshot.get("emission_energy", NAN)))


func _capture_directory_from_args() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-lighting-aircraft="):
			continue
		var raw_path := argument.trim_prefix("--capture-lighting-aircraft=").strip_edges()
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
