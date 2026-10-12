# VQ-04a-F1 regression: field cue and nearby scenery projected-shadow integration.
# Run with the pinned Godot console binary and --headless --path app --script res://tests/test_field_projected_shadows.gd
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FieldShadows := preload("res://render/field_projected_shadows.gd")
const Projected := preload("res://render/projected_shadow.gd")
const Scenery := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Spec := preload("res://spec.gd")
const OPTS := {audio = false, birds = false, theme = "", quality = "high"}

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _test_root_mesh_and_flat_ground() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-2, 0, -1), Vector3(-1, 0, -1), Vector3(-2, 0, 0), # flat ground
		Vector3(2, 0.08, 0), Vector3(3, 0.2, 0), Vector3(2, 0.1, 1), # raised surface
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var root_mesh := MeshInstance3D.new()
	root_mesh.mesh = mesh
	var shape: Dictionary = Projected.collect(root_mesh, 0.04)
	_check("root MeshInstance is collected and flat ground triangles are skipped",
		not shape.is_empty() and int(shape.triangles) == 1
			and shape.bounds.position.x >= 1.99 and shape.bounds.position.y >= 0.079
			and shape.bounds.size.x <= 1.01,
		str(shape.get("bounds", AABB())) if not shape.is_empty() else "empty shape")
	root_mesh.free()


func _test_target_budget_rejection() -> void:
	var manager := FieldShadows.new() as Node
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(25, 1, 0), Vector3(0, 2, 25),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var caster := MeshInstance3D.new()
	caster.mesh = mesh
	var initial_budget := FieldShadows.MAX_TARGET_PIXELS - 1024 * 1024 + 1
	manager.set("target_pixels", initial_budget)
	var accepted: bool = manager.call("add_caster", caster)
	_check("1024² caster exceeding MAX_TARGET_PIXELS is rejected", not accepted)
	_check("budget rejection preserves allocation counters and creates no children",
		int(manager.get("target_pixels")) == initial_budget
			and (manager.get("projectors") as Array).is_empty()
			and manager.get_child_count() == 0,
		"pixels=%d children=%d" % [int(manager.get("target_pixels")), manager.get_child_count()])
	manager.free()
	caster.free()


func _test_incomplete_cue_fallback(field: Dictionary, lighting: Dictionary) -> void:
	var fixture := FieldBuilder.build(field, lighting)
	var old_manager := fixture.get_node_or_null("ProjectedFieldShadows")
	if old_manager != null:
		fixture.remove_child(old_manager)
		old_manager.free()
	var legacy := fixture.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if legacy != null:
		legacy.visible = true
	var eligible_survivors := 0
	for i in field.flight_cues.size() - 1:
		var source := fixture.get_node_or_null(NodePath(str(field.flight_cues[i].id))) as Node3D
		if source != null and not Projected.collect(source, 0.04).is_empty():
			eligible_survivors += 1
	_check("fallback fixture has two otherwise valid cue casters", eligible_survivors == 2,
		"valid=%d" % eligible_survivors)
	var missing_id := str(field.flight_cues.back().id)
	var missing := fixture.get_node_or_null(NodePath(missing_id))
	if missing != null:
		fixture.remove_child(missing)
		missing.free()
	FieldShadows.attach(fixture, field, lighting)
	var manager := fixture.get_node_or_null("ProjectedFieldShadows")
	var projectors: Array = manager.get("projectors") if manager != null else []
	_check("incomplete cue set keeps the complete legacy cue shadow visible",
		legacy != null and legacy.visible)
	_check("incomplete cue set rolls back all partial projected maps",
		manager == null or (projectors.is_empty() and manager.get_child_count() == 0),
		"projectors=%d children=%d" % [projectors.size(), manager.get_child_count() if manager != null else -1])
	fixture.free()


func _test_flowing_lighting(manager: Node, projectors: Array, lighting: Dictionary) -> void:
	var saved_state := Atmosphere.state.duplicate(true)
	var dir_a := Vector3(0.18, 0.96, -0.22).normalized()
	Atmosphere.state = {light_dir = dir_a, light_energy = Spec.ATMOSPHERE.sun_energy * 0.7}
	FieldShadows.apply_lighting(manager.get_parent() as Node3D, {})
	var processing := manager.is_processing()
	var dir_b := Vector3(-0.53, 0.82, 0.21).normalized()
	Atmosphere.state = {light_dir = dir_b, light_energy = Spec.ATMOSPHERE.sun_energy * 0.35}
	var state_before_process := Atmosphere.state.duplicate(true)
	var clock_before := ShaderClock.last_clock
	var wind_before := ShaderClock.last_wind
	manager.call("_process", 0.016)
	var expected_direction := Atmosphere.shadow_direction()
	var expected_opacity := 0.40 * clampf(Atmosphere.light_energy() / float(Spec.ATMOSPHERE.sun_energy), 0.0, 1.0)
	var refreshed := true
	for projector: Node in projectors:
		var mask := projector.get("mask_material") as ShaderMaterial
		var receiver := projector.get("receiver") as MeshInstance3D
		var receiver_mat := receiver.material_override as ShaderMaterial
		refreshed = refreshed and mask.get_shader_parameter("light_direction").is_equal_approx(expected_direction)
		refreshed = refreshed and is_equal_approx(float(receiver_mat.get_shader_parameter("opacity")), expected_opacity)
	_check("flowing field manager processes lighting snapshots", processing)
	_check("_process refreshes direction and energy-scaled opacity without mutating state or shader clock",
		refreshed and Atmosphere.state == state_before_process
			and ShaderClock.last_clock == clock_before and ShaderClock.last_wind == wind_before)
	Atmosphere.state = saved_state
	FieldShadows.apply_lighting(manager.get_parent() as Node3D, lighting)


func _test_field_integration() -> void:
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.ok:
		return
	var field: Dictionary = loaded.field
	var daylight: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	daylight.shadow_strength = 1.0
	daylight.sun_azimuth_deg = 230.0
	_test_incomplete_cue_fallback(field, daylight)
	var field_node := FieldBuilder.build(field, daylight)
	# FieldBuilder attaches cues before optional scenery. Rebuild its manager after
	# inserting the deterministic default scenery so one manager sees both sources.
	var first_manager := field_node.get_node_or_null("ProjectedFieldShadows")
	if first_manager != null:
		field_node.remove_child(first_manager)
		first_manager.free()
	var scenery_data := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("default scenery loads", bool(scenery_data.get("ok", false)), str(scenery_data.get("errors", [])))
	if not scenery_data.ok:
		field_node.free()
		return
	var scenery_root := Scenery.build(field, scenery_data.scenery, OPTS, daylight)
	field_node.add_child(scenery_root)
	FieldShadows.attach(field_node, field, daylight)
	root.add_child(field_node)
	await process_frame

	var manager := field_node.get_node_or_null("ProjectedFieldShadows")	 as Node
	_check("field manager is attached", manager != null)
	if manager == null:
		field_node.free()
		return
	var projectors: Array = manager.get("projectors")
	var cue_projectors := 0
	for cue: Dictionary in field.flight_cues:
		var source := field_node.get_node_or_null(NodePath(str(cue.id))) as Node3D
		var projected := false
		for projector: Node in projectors:
			projected = projected or projector.get("source") == source
		cue_projectors += 1 if source != null and projected else 0
	_check("all three default field cues have projected maps", field.flight_cues.size() == 3 and cue_projectors == 3,
		"cues=%d projected=%d" % [field.flight_cues.size(), cue_projectors])
	var legacy_cues := field_node.get_node_or_null("FlightCueShadows") as MeshInstance3D
	_check("matching legacy cue contact mesh is hidden", legacy_cues != null and not legacy_cues.visible)

	var cell_projectors := 0
	var matched_legacy := 0
	var pilot_hits := [false, false]
	var population_placements := 0
	var population_triangles := 0
	var max_resolution := 0
	var pixel_sum := 0
	var pilot_xz := Vector2(float(field.pilot.east), -float(field.pilot.north))
	var population := scenery_root.get_node_or_null("Population") as Node3D
	var projected_cells: Array[MeshInstance3D] = []
	for projector: Node in projectors:
		var projected_source := projector.get("source") as Node3D
		if projected_source != null and str(projected_source.name).begins_with("cell_"):
			projected_cells.append(projected_source as MeshInstance3D)
	var population_owners := FieldShadows.population_cell_owners(projected_cells, population, pilot_xz)
	for projector: Node in projectors:
		var source := projector.get("source") as Node3D
		var viewport := projector.get("viewport") as SubViewport
		if viewport == null:
			continue
		max_resolution = maxi(max_resolution, maxi(viewport.size.x, viewport.size.y))
		pixel_sum += viewport.size.x * viewport.size.y
		if source == null or not str(source.name).begins_with("cell_"):
			continue
		cell_projectors += 1
		var suffix := str(source.name).trim_prefix("cell_")
		var legacy := scenery_root.get_node_or_null(NodePath("shadows_" + suffix)) as MeshInstance3D
		if legacy != null:
			matched_legacy += 1
			_check("near %s legacy shadow batch is hidden" % suffix, not legacy.visible)
		var shape: Dictionary = FieldShadows.collect_cell_shape(source, population, pilot_xz,
			FieldShadows.MAX_SCENERY_RANGE, 0.04, population_owners)
		if shape.is_empty():
			continue
		population_placements += int(shape.get("population_placements", 0))
		population_triangles += int(shape.get("population_triangles", 0))
		_check("projected caster uses the merged cell and population shape",
			int(projector.get("triangle_count")) == int(shape.triangles)
				and int(projector.get_meta("population_placements", 0)) == int(shape.get("population_placements", 0)))
		var vertices: PackedVector3Array = shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in vertices:
			if v.y < 1.45:
				continue
			if Vector2(v.x + 13.0, v.z).length() < 0.55:
				pilot_hits[0] = true
			if Vector2(v.x - 16.0, v.z - 0.5).length() < 0.55:
				pilot_hits[1] = true
	_check("near scenery cells are projected", cell_projectors > 0)
	_check("pilot and people geometry survives cell collection", pilot_hits[0] and pilot_hits[1],
		"hits=%s population_placements=%d triangles=%d" % [str(pilot_hits), population_placements, population_triangles])
	_check("nearby human faces are merged without new projector maps",
		population_placements >= 2 and population_triangles > 0
			and projectors.size() == cue_projectors + cell_projectors)
	_check("near projected cells hide matching legacy batches", matched_legacy > 0,
		"matched=%d cells=%d" % [matched_legacy, cell_projectors])
	_check("map count and each 256/512/1024 target stay bounded",
		projectors.size() <= 16 and max_resolution <= 1024 and max_resolution > 0,
		"maps=%d max=%d" % [projectors.size(), max_resolution])
	_check("aggregate viewport allocation respects MAX_TARGET_PIXELS",
		pixel_sum == int(manager.get("target_pixels")) and pixel_sum <= FieldShadows.MAX_TARGET_PIXELS,
		"pixels=%d budget=%d reported=%d" % [pixel_sum, FieldShadows.MAX_TARGET_PIXELS, int(manager.get("target_pixels"))])

	var population_contacts := scenery_root.get_node_or_null("PopulationContacts") as MeshInstance3D
	var population_groups: Array = scenery_root.get_meta("directional_population_shadow_groups", [])
	var groups: Dictionary = scenery_root.get_meta("directional_shadow_groups")
	var separate_groups := not population_groups.is_empty()
	var vehicle_groups := 0
	var legacy_population_groups := 0
	for source_group: Dictionary in population_groups:
		vehicle_groups += 1 if str(source_group.mode) == "vehicle" else 0
	for key: Vector2i in groups:
		for source_group: Dictionary in groups[key]:
			legacy_population_groups += 1 if str(source_group.mode) in ["person", "vehicle"] else 0
	var veranda_patch := false
	if population_contacts != null and population_contacts.mesh != null and population_contacts.mesh.get_surface_count() > 0:
		var contact_vertices: PackedVector3Array = population_contacts.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in contact_vertices:
			if absf(vertex.y - 0.154) < 0.001 and Vector2(vertex.x + 2.5, vertex.z - 17.5).length() < 0.01:
				veranda_patch = true
		_check("population contact batch preserves the raised veranda foot patch and uses shared shade material",
			population_contacts != null and population_contacts.mesh != null
				and population_contacts.mesh.get_surface_count() > 0 and veranda_patch
				and population_contacts.mesh.surface_get_material(0) == scenery_root.get_meta("directional_shadow_material"))
	_check("people and cars use a separate compact shadow batch outside legacy cell groups",
		separate_groups and vehicle_groups > 0 and legacy_population_groups == 0,
		"population=%d vehicles=%d legacy=%d" % [population_groups.size(), vehicle_groups, legacy_population_groups])

	# The old batches for casters beyond the projected near-field radius must remain visible.
	var far_legacy := 0
	for key: Vector2i in groups:
		var name := "shadows_%d_%d" % [key.x, key.y]
		var batch := scenery_root.get_node_or_null(NodePath(name)) as MeshInstance3D
		for placement: Dictionary in groups[key]:
			var pos: Vector3 = placement.transform.origin
			if Vector2(pos.x, pos.z).distance_to(pilot_xz) > 100.0:
				if batch != null:
					far_legacy += 1
					_check("far legacy shadow batch remains visible", batch.visible, name)
				break
	_check("at least one far legacy shadow batch is preserved", far_legacy > 0,
		"far batches=%d" % far_legacy)

	# Reapplying one explicit snapshot must not reschedule a mask draw.
	var before_modes: Array[int] = []
	var before_signatures: Array = []
	for projector: Node in projectors:
		before_modes.append((projector.get("viewport") as SubViewport).render_target_update_mode)
		before_signatures.append(projector.get("_last_signature").duplicate(true))
	FieldShadows.apply_lighting(field_node, daylight)
	var same_unchanged := true
	for i in projectors.size():
		same_unchanged = same_unchanged and (projectors[i].get("viewport") as SubViewport).render_target_update_mode == before_modes[i]
		same_unchanged = same_unchanged and projectors[i].get("_last_signature") == before_signatures[i]
	_check("identical lighting snapshot schedules no new mask redraw", same_unchanged)

	var low_sun := daylight.duplicate(true)
	low_sun.sun_elevation_deg = 2.0
	FieldShadows.apply_lighting(field_node, low_sun)
	var bounded_direction := Atmosphere.shadow_direction(low_sun)
	var low_sun_matches := true
	for projector: Node in projectors:
		var mask := projector.get("mask_material") as ShaderMaterial
		low_sun_matches = low_sun_matches and mask.get_shader_parameter("light_direction").is_equal_approx(bounded_direction)
	_check("explicit low-sun projection uses the shared 12-degree shadow direction",
		bounded_direction.y >= sin(deg_to_rad(12.0)) - 0.000001
			and bounded_direction != Atmosphere.sun_direction(low_sun) and low_sun_matches)
	FieldShadows.apply_lighting(field_node, daylight)

	var cell_projector: Node
	for projector: Node in projectors:
		var source := projector.get("source") as Node3D
		if source != null and str(source.name).begins_with("cell_"):
			cell_projector = projector
			break
	if cell_projector == null:
		_check("visibility lifecycle has a projected scenery cell", false)
	else:
		var cell_source := cell_projector.get("source") as Node3D
		var cell_receiver := cell_projector.get("receiver") as MeshInstance3D
		var cell_viewport := cell_projector.get("viewport") as SubViewport
		cell_source.visible = false
		_check("hiding a source hides its receiver and disables redraw",
			not cell_receiver.visible and cell_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
		cell_source.visible = true
		_check("showing a source restores its receiver and refreshes its map",
			cell_receiver.visible and cell_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
		scenery_root.visible = false
		_check("hiding the Scenery ancestor hides the projected receiver",
			not cell_receiver.visible and cell_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
		scenery_root.visible = true
		_check("showing the Scenery ancestor restores the projected receiver and map",
			cell_receiver.visible and cell_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)

	_test_flowing_lighting(manager, projectors, daylight)

	var dark := daylight.duplicate(true)
	dark.sun_azimuth_deg = 35.0
	dark.shadow_strength = 0.0
	FieldShadows.apply_lighting(field_node, dark)
	var all_disabled := true
	for projector: Node in projectors:
		all_disabled = all_disabled and not (projector.get("receiver") as MeshInstance3D).visible
		all_disabled = all_disabled and (projector.get("viewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED
	_check("zero-strength explicit snapshot hides maps and disables redraw", all_disabled)

	var restored := dark.duplicate(true)
	restored.sun_azimuth_deg = 140.0
	restored.shadow_strength = 1.0
	_check("restored snapshot changes sun direction", Atmosphere.sun_direction(restored) != Atmosphere.sun_direction(dark))
	FieldShadows.apply_lighting(field_node, restored)
	var all_restored := true
	for projector: Node in projectors:
		all_restored = all_restored and (projector.get("receiver") as MeshInstance3D).visible
		all_restored = all_restored and (projector.get("viewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_ONCE
	_check("positive strength re-enables receivers and schedules fresh maps", all_restored)
	var population_mesh_before := population_contacts.mesh if population_contacts != null else null
	var shifted_sun := daylight.duplicate(true)
	shifted_sun.sun_azimuth_deg = float(daylight.sun_azimuth_deg) + 70.0
	var population_prepare := Scenery.prepare_lighting(field_node, shifted_sun)
	var population_batch_present := false
	for replacement: Dictionary in population_prepare.get("batches", []):
		population_batch_present = population_batch_present or replacement.get("node") == population_contacts
	_check("population contact geometry joins the scenery lighting transaction",
		population_contacts != null and population_batch_present and bool(population_prepare.get("geometry_changed", false)))
	var population_commit := Scenery.commit_lighting(field_node, population_prepare)
	_check("committing a new sun replaces population car shadows while retaining the contact batch",
		population_commit and population_contacts != null and population_contacts.mesh != population_mesh_before)
	field_node.free()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_scenery_setting: String = OS.get_environment("OPENRC_SCENERY")
	OS.set_environment("OPENRC_SCENERY", "off")
	_test_root_mesh_and_flat_ground()
	_test_target_budget_rejection()
	await _test_field_integration()
	OS.set_environment("OPENRC_SCENERY", previous_scenery_setting)
	print("Field projected-shadow regression: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
