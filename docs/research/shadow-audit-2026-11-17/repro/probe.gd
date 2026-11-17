extends SceneTree
## Audit reproduction against unchanged production modules. Headless state/geometry evidence only.

const Settings := preload("res://render/shadow_settings.gd")
const Projected := preload("res://render/projected_shadow.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Clouds := preload("res://render/cloud_shadow_map.gd")
const RenderProbe := preload("res://debug/render_probe.gd")

var checks := 0
var failures := 0
var observations: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _bytes(shape: Dictionary) -> PackedByteArray:
	return (shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array()

func _run() -> void:
	var matrix: Array = []
	for renderer: String in ["gl_compatibility", "mobile", "forward_plus"]:
		for technique: String in Settings.TECHNIQUES:
			var row := Settings.resolve({shadow_technique = technique}, renderer, renderer == "forward_plus")
			matrix.append(row.effective)
			_check("mode ownership " + renderer + "/" + technique,
				bool(row.effective.native) == (technique in ["auto", "native"])
				and bool(row.effective.projected) == (technique in ["auto", "projected"]))
	observations.mode_matrix = matrix

	var holder := Node3D.new()
	root.add_child(holder)
	var model := Node3D.new()
	model.position.y = 2.0
	holder.add_child(model)
	var hinge := Node3D.new()
	model.add_child(hinge)
	var wing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.1, 0.5)
	wing.mesh = box
	hinge.add_child(wing)
	var initial := Projected.collect(model)
	var initial_bytes := _bytes(initial)
	var projector := Projected.new()
	holder.add_child(projector)
	projector.setup(model, initial)
	projector.refresh(2.0, Vector3.UP, 0.5, true)
	var first_redraw := projector.redraw_count
	hinge.rotation.z = deg_to_rad(35.0)
	var animated := Projected.collect(model)
	projector.refresh(2.0, Vector3.UP, 0.5, true)
	_check("control motion changes freshly collected geometry", _bytes(animated) != initial_bytes)
	_check("installed silhouette remains a bind-time snapshot", _bytes(initial) == initial_bytes)
	var installed_mesh: MeshInstance3D
	for child in projector.viewport.get_children():
		if child is MeshInstance3D:
			installed_mesh = child
	_check("actual installed proxy retains the captured vertices", installed_mesh != null
		and _bytes({mesh = installed_mesh.mesh}) == initial_bytes)
	_check("root-only cache does not redraw for local hinge motion", projector.redraw_count == first_redraw)
	observations.animation_snapshot = {local_rotation_deg = 35, new_geometry_differs = _bytes(animated) != initial_bytes,
		redraw_before = first_redraw, redraw_after = projector.redraw_count}

	hinge.rotation = Vector3.ZERO
	var opaque := Projected.collect(model)
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent.albedo_color.a = 0.0
	wing.material_override = transparent
	var transparent_shape := Projected.collect(model)
	_check("fully transparent material has identical collected coverage geometry", _bytes(opaque) == _bytes(transparent_shape))
	observations.material_coverage = {opaque_triangles = opaque.triangles, transparent_triangles = transparent_shape.triangles,
		geometry_equal = _bytes(opaque) == _bytes(transparent_shape), mask_replaces_material = projector.mask_material.shader == Projected.MaskShader}

	var initial_receiver_y := projector.receiver.global_position.y
	model.position.y = 12.0
	projector.refresh(12.0, Vector3.UP, 0.5, true)
	_check("projected receiver remains on the fixed world plane", projector.receiver.global_position.y == initial_receiver_y)
	observations.receiver_plane = {first_model_y = 2.0, second_model_y = 12.0,
		first_receiver_y = initial_receiver_y, second_receiver_y = projector.receiver.global_position.y,
		terrain_query = "none in production refresh"}

	var low_lighting := {sun_elevation_deg = 2.0, sun_azimuth_deg = 90.0}
	var raw := Atmosphere.sun_direction(low_lighting)
	var bounded := Atmosphere.shadow_direction(low_lighting)
	var raw_projection := Projected.project(Vector3(0.0, 1.0, 0.0), raw)
	var bounded_projection := Projected.project(Vector3(0.0, 1.0, 0.0), bounded)
	_check("snapshot raw and bounded field light differ below twelve degrees", raw_projection.distance_to(bounded_projection) > 15.0)
	observations.low_sun = {sun_elevation_deg = 2, raw_offset_m_per_height_m = raw_projection.length(),
		bounded_offset_m_per_height_m = bounded_projection.length(),
		offset_ratio = raw_projection.length() / bounded_projection.length()}

	var small_rotation := Basis(Vector3.RIGHT, deg_to_rad(0.2))
	var grazing := Vector3(cos(deg_to_rad(12.0)), sin(deg_to_rad(12.0)), 0.0)
	var tip := Vector3(0.0, 0.0, 3.0)
	var error_m := Projected.project(small_rotation * tip, grazing).distance_to(Projected.project(tip, grazing))
	var accepted := Projected.same_within(Basis.IDENTITY, small_rotation, Projected.REUSE_COS)
	_check("angular cache accepts the 0.2-degree pose", accepted)
	_check("accepted projected displacement exceeds minimum blur", error_m > 0.018)
	var long_model := Node3D.new()
	holder.add_child(long_model)
	var long_mesh := MeshInstance3D.new()
	var long_box := BoxMesh.new()
	long_box.size = Vector3(0.1, 0.04, 6.0)
	long_mesh.mesh = long_box
	long_model.add_child(long_mesh)
	var long_shape := Projected.collect(long_model)
	var cached_projector := Projected.new()
	holder.add_child(cached_projector)
	cached_projector.setup(long_model, long_shape)
	cached_projector.refresh(0.0, grazing, 0.5, true)
	var cached_draws := cached_projector.redraw_count
	long_model.basis = small_rotation
	cached_projector.refresh(0.0, grazing, 0.5, true)
	_check("production refresh reuses the synthetic long-model mask at 0.2 degrees", cached_projector.redraw_count == cached_draws)
	long_model.basis = Basis(Vector3.RIGHT, deg_to_rad(0.3))
	cached_projector.refresh(0.0, grazing, 0.5, true)
	_check("positive control redraws after the angular threshold", cached_projector.redraw_count == cached_draws + 1)
	observations.cache_error = {radius_m = 3.0, sun_elevation_deg = 12.0, rotation_deg = 0.2,
		cache_accepts = accepted, point_displacement_m = error_m, minimum_blur_m = 0.018,
		refresh_reuse_at_0_2_deg = true, refresh_redraw_at_0_3_deg = true, synthetic_box_size_m = [0.1, 0.04, 6.0],
		limit = "synthetic geometry/cache counterexample at minimum blur; no displayed-pixel or clipping claim"}

	Settings.apply({shadow_technique = "native", shadow_quality = "ultra"})
	var diagnostics := RenderProbe.new(root).config()
	var receipt := Settings.describe()
	_check("debug atlas field differs from selected owner configuration", diagnostics.directional_shadow_size != receipt.effective.atlas_size)
	var sun := DirectionalLight3D.new()
	holder.add_child(sun)
	Settings.apply_sun(sun, false)
	_check("effective native capability can coexist with an inactive light", receipt.effective.native and not sun.shadow_enabled)
	observations.diagnostics = {selected_atlas = receipt.effective.atlas_size,
		debug_reported_atlas = diagnostics.directional_shadow_size, effective_native = receipt.effective.native,
		actual_sun_shadow_enabled = sun.shadow_enabled, rendering_available = receipt.rendering_available,
		limit = "headless owner/configuration mismatch; no GPU allocation measurement"}

	OS.set_environment(Clouds.ENVIRONMENT_KEY, "1")
	OS.set_environment(Clouds.GROUND_ENVIRONMENT_KEY, "1")
	OS.set_environment(Clouds.SKY_ENVIRONMENT_KEY, "0")
	var consumer := ShaderMaterial.new()
	consumer.shader = Atmosphere.GROUND_SHADER
	var seed_statuses: Array = []
	for seed in range(101, 106):
		Clouds.apply(consumer, seed)
		var d := Clouds.diagnostics()
		seed_statuses.append({requested_seed = seed, status = d.effective.ground, retained_tiles = d.seeds.size(),
			live_required_seeds = d.required_seeds.ground.duplicate()})
	var cache := Clouds.diagnostics()
	_check("fifth distinct seed reaches capacity with one live consumer", cache.effective.ground == "capacity" and cache.consumers.ground.size() == 1)
	_check("four obsolete seeds remain while current seed is absent", not Clouds._tiles.has(105) and Clouds._tiles.size() == 4 and cache.required_seeds.ground == [105])
	Clouds.apply(consumer, 105)
	_check("retry of current seed remains at capacity", Clouds.diagnostics().effective.ground == "capacity")
	observations.cloud_cache = {sequence = seed_statuses, final = cache,
		limit = "cache admission/state only; tiles are pending, no graphical bake claimed"}
	Clouds.clear_ground(consumer)
	_check("last-consumer removal releases the retained cache", Clouds._tiles.is_empty())
	consumer = null
	OS.set_environment(Clouds.ENVIRONMENT_KEY, "0")
	Settings.apply({})
	holder.free()
	await process_frame
	await process_frame
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty():
		printerr("An explicit fresh --out= path is required")
		quit(2)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({engine = Engine.get_version_info(), display = DisplayServer.get_name(),
		renderer = RenderingServer.get_current_rendering_method(), checks = checks, failures = failures,
		observations = observations}, "\t") + "\n")
	file.close()
	print("Shadow audit reproduction: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
