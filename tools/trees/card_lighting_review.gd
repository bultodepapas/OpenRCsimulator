## Native, matched card/source lighting comparison. Images are diagnostics, not a performance gate.
## --out=<new absolute folder> [--shader-source=<absolute or res:// shader>]
## [--variants=production|all] [--neutral-backlight=<0..1, exclusive of zero>]
extends SceneTree

const Treeline := preload("res://render/treeline.gd")
const TreeAssets := preload("res://render/tree_assets.gd")
const Library := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")
const SHADER_PATH := "res://render/treeline.gdshader"
const SIZE := Vector2i(1920, 1080)
const BACKLIGHT_LINE := "BACKLIGHT = backlight * ALBEDO;"
const LIGHTS := {
	"front": Vector3(0.0, 0.5, 1.0),
	"side": Vector3(1.0, 0.5, 0.0),
	"rear": Vector3(0.0, 0.5, -1.0),
	"ambient": Vector3(0.0, 0.5, 1.0),
}
const UNIFORMS := ["atlas", "foliage_mask", "frame_sizes", "wind_enabled", "up_bias", "underside",
	"backlight", "base_dark", "leaf_saturation", "leaf_gain", "bark_gain"]

var args := {}
var output := ""
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var report := {format = "openrc-tree-card-lighting v1", complete = false, captures = [], species = []}
var shaders := {}
var source_paths: Array[String] = []
var neutral_backlight := 0.10


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			_fail("Arguments must be --name=value")
			return
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair[0] not in ["out", "shader-source", "variants", "neutral-backlight"] or pair[1].is_empty() or args.has(pair[0]):
			_fail("Unknown, duplicate or empty argument: " + argument)
			return
		args[pair[0]] = pair[1]
	_run.call_deferred()


func _run() -> void:
	output = str(args.get("out", ""))
	var shader_path := str(args.get("shader-source", SHADER_PATH))
	var mode := str(args.get("variants", "production"))
	var neutral_text := str(args.get("neutral-backlight", "0.1"))
	if not neutral_text.is_valid_float():
		_fail("neutral-backlight must be a finite number greater than zero and at most one")
		return
	neutral_backlight = float(neutral_text)
	if not is_finite(neutral_backlight) or neutral_backlight <= 0.0 or neutral_backlight > 1.0:
		_fail("neutral-backlight must be a finite number greater than zero and at most one")
		return
	if output.is_empty() or not output.is_absolute_path() or DisplayServer.get_name() == "headless" \
			or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("A native Compatibility display and --out=<absolute folder> are required")
		return
	if mode not in ["all", "production"] or not (shader_path.begins_with("res://") or shader_path.is_absolute_path()) \
			or not FileAccess.file_exists(shader_path):
		_fail("Invalid variants or unreadable shader source")
		return
	if FileAccess.file_exists(output) or (DirAccess.dir_exists_absolute(output) \
			and (not DirAccess.get_files_at(output).is_empty() or not DirAccess.get_directories_at(output).is_empty())):
		_fail("Output must be new or empty")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create output folder")
		return
	var shader_code := FileAccess.get_file_as_string(shader_path)
	if shader_code.is_empty() or (mode == "all" and shader_code.count(BACKLIGHT_LINE) != 1):
		_fail("The shader is empty or lacks one unambiguous baseline backlight expression")
		return
	var variants := ["production"] if mode == "production" else ["baseline", "mask_only", "neutral_leaf"]
	for variant: String in variants:
		var code := shader_code
		if variant == "mask_only":
			code = code.replace(BACKLIGHT_LINE, "BACKLIGHT = backlight * ALBEDO * foliage;")
		elif variant == "neutral_leaf":
			code = code.replace(BACKLIGHT_LINE, "BACKLIGHT = vec3(backlight) * foliage;")
		var shader := Shader.new()
		shader.code = code
		shaders[variant] = shader
	var catalog := TreeAssets.catalog()
	if not bool(catalog.get("ok", false)):
		_fail("Tree card catalog is invalid: " + str(catalog.get("errors", [])))
		return
	source_paths.assign([SHADER_PATH, shader_path, "res://render/treeline.gd", "res://render/tree_assets.gd",
		"res://render/field_tree_detail.gd", "res://render/tree_identity.gdshaderinc", "res://render/tree_wind.gdshaderinc",
		"res://render/shader_clock.gd", "res://scenery/imported_vegetation.gd", TreeAssets.CATALOG_PATH,
		Library.CATALOG_PATH, str(catalog.catalog.atlas), str(catalog.catalog.foliage_mask), str(get_script().resource_path)])
	for asset_id: String in Treeline.DETAIL_ASSETS:
		var asset := Library.get_asset(asset_id)
		if asset.is_empty() or not asset.has("scene"):
			_fail("Missing source asset " + asset_id)
			return
		if FileAccess.get_sha256(str(asset.scene)) != str(asset.get("source_sha256", "")):
			_fail("Source asset does not match its catalog: " + asset_id)
			return
		source_paths.append(str(asset.scene))
		if asset.has("source_entry"):
			source_paths.append(ProjectSettings.globalize_path("res://../" + str(asset.source_entry)))
	var identities := _source_hashes()
	if identities.size() != _unique_path_count():
		_fail("A required source, catalog, atlas or mask cannot be hashed")
		return
	_setup_scene()
	report["source_sha256"] = identities
	report["shader_source"] = shader_path
	report["arguments"] = args
	report["neutral_backlight"] = neutral_backlight
	report["neutral_backlight_applied"] = mode == "all"
	report["variant_shader_sha256"] = {}
	for variant: String in variants:
		report.variant_shader_sha256[variant] = (shaders[variant] as Shader).code.sha256_text()
	report["variants"] = variants
	for slot in Treeline.DETAIL_ASSETS.size():
		if not await _capture_species(slot, variants):
			return
	var expected := Treeline.DETAIL_ASSETS.size() * (variants.size() + 1) * LIGHTS.size()
	var seen := {}
	for capture: Dictionary in report.captures:
		seen[capture.id] = true
	if report.captures.size() != expected or seen.size() != expected or _source_hashes() != identities:
		_fail("Capture matrix incomplete, duplicated, or source files changed during capture")
		return
	report["expected_images"] = expected
	report["viewport"] = [viewport.size.x, viewport.size.y]
	report["engine"] = Engine.get_version_info()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["lighting"] = {ambient_color = [1, 1, 1], ambient_energy = 0.2, background = [0.06, 0.06, 0.06],
		reflections = "disabled", shadows = false, tone_mapper = "linear", msaa = "4x", clock = 0.0, wind = [0, 0, 0]}
	report["scope"] = "Matched source mesh/card diagnostic; not physical, performance, or flight qualification."
	report.complete = true
	var temporary := output.path_join("report.json.tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_fail("Cannot create report")
		return
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, output.path_join("report.json")) != OK:
		_fail("Cannot finish report")
		return
	viewport.free()
	print("TREE CARD LIGHTING COMPLETE: %d images" % expected)
	quit(0)


func _setup_scene() -> void:
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	RenderingServer.render_loop_enabled = false
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.2
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	sun = DirectionalLight3D.new()
	sun.light_color = Color.WHITE
	sun.shadow_enabled = false
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 500.0
	camera.fov = 36.0
	stage.add_child(camera)
	camera.current = true


func _capture_species(slot: int, variants: Array) -> bool:
	var point := _point_for_slot(slot)
	if point.is_empty():
		_fail("Could not find a CPU identity for slot %d" % slot)
		return false
	var identity := Treeline.identity(point[0], point[1])
	var height := float(identity.height)
	var asset_id: String = Treeline.DETAIL_ASSETS[slot]
	var card := Treeline.build({id = "card", positions = [point]}, {north = -point[0], east = -point[1], down = 0.0})
	if card.get_child_count() != 1 or not card.get_child(0) is MultiMeshInstance3D:
		_fail("Production card did not build a single instance")
		return false
	var card_batch := card.get_child(0) as MultiMeshInstance3D
	var card_material := card_batch.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	if card_material == null or card_batch.multimesh.instance_count != 1:
		_fail("Production card material or instance is missing")
		return false
	var card_origin := card.position + card_batch.multimesh.get_instance_transform(0).origin
	if card_origin.length_squared() > 0.000001:
		_fail("Pilot translation did not center the card")
		return false
	stage.add_child(card)
	var batches := {}
	var placement := Transform3D(Basis(Vector3.UP, -float(identity.yaw)), Vector3.ZERO)
	Library.queue(batches, asset_id, Library.fit_to_height(asset_id, height, placement), 0)
	var mesh_tree := Library.build(batches, false)
	if mesh_tree.get_child_count() == 0:
		_fail("Source tree did not build: " + asset_id)
		return false
	stage.add_child(mesh_tree)
	for child: Node in mesh_tree.get_children():
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eye := Vector3(0.0, height * 0.55, height * 2.0)
	var at := Vector3(0.0, height * 0.5, 0.0)
	camera.look_at_from_position(eye, at)
	var card_geometry := _geometry(card)
	var source_geometry := _geometry(mesh_tree)
	if card_geometry.is_empty() or source_geometry.is_empty():
		_fail("Missing source or card geometry")
		return false
	var asset := Library.get_asset(asset_id)
	var species_record := {slot = slot, asset_id = asset_id, point_ne = point, identity = identity,
		pilot_ne = [-point[0], -point[1]], camera_eye = _vector(eye), camera_at = _vector(at), fov = camera.fov,
		card_world_origin = _vector(card_origin), source_scene = asset.scene,
		catalog_source_triangles = asset.source_triangles, catalog_source_surfaces = asset.source_surfaces,
		catalog_source_materials = asset.source_materials, card = card_geometry, source = source_geometry, variant_uniforms = {}}
	for variant: String in ["mesh"] + variants:
		mesh_tree.visible = variant == "mesh"
		card.visible = variant != "mesh"
		if variant != "mesh":
			var material := card_material.duplicate() as ShaderMaterial
			material.shader = shaders[variant]
			for parameter: String in UNIFORMS:
				var value: Variant = card_material.get_shader_parameter(parameter)
				if value != null:
					material.set_shader_parameter(parameter, value)
			for parameter: String in ["atlas", "foliage_mask", "frame_sizes"]:
				if material.get_shader_parameter(parameter) != card_material.get_shader_parameter(parameter):
					_fail("Variant failed to retain production parameter " + parameter)
					return false
			if variant == "neutral_leaf":
				material.set_shader_parameter("backlight", neutral_backlight)
			card_batch.material_override = material
		for light: String in LIGHTS:
			sun.look_at_from_position(at + (LIGHTS[light] as Vector3) * height, at)
			sun.light_energy = 0.0 if light == "ambient" else 1.0
			if not await _capture("%d_%s_%s" % [slot, variant, light], slot, variant, light):
				return false
		if variant != "mesh":
			species_record.variant_uniforms[variant] = _uniforms(card_batch.material_override as ShaderMaterial)
	report.species.append(species_record)
	card.free()
	mesh_tree.free()
	return true


func _point_for_slot(slot: int) -> Array:
	for quarter in range(1, 1025):
		var north := float(quarter) * 0.25
		if int(Treeline.identity(north, 0.0).species) == slot:
			return [north, 0.0, 0.0]
	return []


func _capture(id: String, slot: int, variant: String, light: String) -> bool:
	for _frame in 4:
		await process_frame
		RenderingServer.force_draw(false)
	var path := output.path_join(id + ".png")
	var image := viewport.get_texture().get_image()
	if FileAccess.file_exists(path) or image == null or image.is_empty() or image.get_size() != SIZE or image.save_png(path) != OK:
		_fail("Capture failed or has the wrong dimensions: " + id)
		return false
	var digest := FileAccess.get_sha256(path)
	if digest.length() != 64:
		_fail("Cannot hash capture: " + id)
		return false
	report.captures.append({id = id, slot = slot, variant = variant, light = light, file = id + ".png",
		sha256 = digest, size = [image.get_width(), image.get_height()], light_energy = sun.light_energy,
		light_position = _vector(sun.position), light_direction = _vector(-sun.global_basis.z),
		light_basis = [_vector(sun.global_basis.x), _vector(sun.global_basis.y), _vector(sun.global_basis.z)]})
	return true


func _geometry(node: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node in node.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var batch := child as MultiMeshInstance3D
		var mesh := batch.multimesh.mesh as ArrayMesh
		if mesh == null:
			return []
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var vertices := mesh.surface_get_array_len(surface)
			var indices := mesh.surface_get_array_index_len(surface)
			var info := {batch = batch.name, surface = surface, instances = batch.multimesh.instance_count,
				vertices = vertices, indices = indices, triangles = (indices if indices > 0 else vertices) / 3,
				material_class = material.get_class() if material != null else "missing",
				material_name = material.resource_name if material != null else ""}
			if material is BaseMaterial3D:
				var base := material as BaseMaterial3D
				info["material"] = {albedo_texture = base.albedo_texture.resource_path if base.albedo_texture != null else "",
					transparency = base.transparency, roughness = base.roughness, metallic = base.metallic,
					backlight_enabled = base.backlight_enabled, backlight = [base.backlight.r, base.backlight.g, base.backlight.b]}
			result.append(info)
	return result


func _uniforms(material: ShaderMaterial) -> Dictionary:
	var result := {}
	for parameter: String in UNIFORMS:
		var value: Variant = material.get_shader_parameter(parameter)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), parameter)
		if value is Texture2D:
			result[parameter] = value.resource_path
		elif value is Vector3:
			result[parameter] = _vector(value)
		else:
			result[parameter] = value
	return result


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in source_paths:
		var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if digest.length() == 64:
			result[path] = digest
	return result


func _unique_path_count() -> int:
	var paths := {}
	for path: String in source_paths:
		paths[path] = true
	return paths.size()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
