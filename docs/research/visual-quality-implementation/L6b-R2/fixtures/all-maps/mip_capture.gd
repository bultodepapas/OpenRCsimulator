## Fixed imported-source mipmap probe. Run against an already-imported app with native Compatibility.
## This is a rendering diagnostic only; it does not construct new geometry or simulate flight.
extends SceneTree

const Library = preload("res://scenery/imported_vegetation.gd")
const ASSET_IDS := [
	"common_tree_1", "common_tree_2", "common_tree_3", "common_tree_4",
	"pine_1", "pine_2", "pine_3", "bush_common_flowers",
]
const DISTANCES_M := [16.0, 48.0, 128.0]
const VIEW_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const PHASE_COUNT := 8
const FOV_DEGREES := 50.0
const BACKGROUND := Color(0.035, 0.19, 0.84, 1.0)

var args: Dictionary = {}
var output_dir := ""
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var report: Dictionary = {
	"format": "openrc-tree-mipmap-sweep v1",
	"complete": false,
	"assets": {},
	"textures": {},
	"captures": [],
}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	if args.has("check-only"):
		print("MIP CAPTURE SCRIPT PARSED")
		quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	output_dir = str(args.get("out", ""))
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		_fail("--out and a native Compatibility framebuffer are required")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Compatibility rendering is required")
		return
	if DirAccess.dir_exists_absolute(output_dir):
		var files := DirAccess.get_files_at(output_dir)
		var directories := DirAccess.get_directories_at(output_dir)
		if not files.is_empty() or not directories.is_empty():
			_fail("output must be new or empty")
			return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("cannot create output directory")
		return

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	RenderingServer.render_loop_enabled = false
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZES[0]
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	_build_lighting()
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 512.0
	camera.fov = FOV_DEGREES
	stage.add_child(camera)
	camera.current = true

	var identity_paths := [
		"res://project.godot",
		"res://scenery/imported_vegetation.gd",
		"res://scenery/imported_vegetation_wind.gdshader",
		Library.CATALOG_PATH,
	]
	var identity := {}
	for path in identity_paths:
		identity[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	report["identity"] = identity
	report["godot"] = Engine.get_version_info().string
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["fixture"] = {
		"asset_ids": ASSET_IDS,
		"distances_m": DISTANCES_M,
		"view_sizes": [[1280, 720], [1920, 1080]],
		"fov_degrees": FOV_DEGREES,
		"phase_count": PHASE_COUNT,
		"phase_offsets_pixels": [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875],
		"background_rgba": [BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, BACKGROUND.a],
		"msaa": "4x",
		"wind_enabled": false,
		"wind_clock_seconds": 0.0,
		"wind_vector_mps": [0.0, 0.0, 0.0],
		"shadow_enabled": false,
		"capture_process_mode": "disabled",
		"interpretation": "Subpixel camera translations probe raster coverage sensitivity for fixed geometry. Adjacent-mask changes are a sampling-instability proxy, not real-time shimmer or flight evidence.",
	}

	for asset_id in ASSET_IDS:
		print("MIP CAPTURE ASSET: ", asset_id)
		var asset: Dictionary = Library.get_asset(asset_id)
		var parts: Array[Dictionary] = Library.get_parts(asset_id)
		if asset.is_empty() or parts.is_empty():
			_fail("missing imported source asset or parts: " + asset_id)
			return
		var asset_record := _asset_record(asset_id, asset, parts)
		if asset_record.scene_sha256 == "missing":
			_fail("source scene file is missing for " + asset_id)
			return
		report.assets[asset_id] = asset_record
		_record_textures(asset_id, parts)
		var batches: Dictionary = {}
		if Library.queue(batches, asset_id, Transform3D.IDENTITY, 101, asset_id).is_empty():
			_fail("failed to queue imported source asset: " + asset_id)
			return
		var vegetation: Node3D = Library.build(batches)
		vegetation.process_mode = Node.PROCESS_MODE_DISABLED
		stage.add_child(vegetation)
		if not await _capture_asset(asset_id, float(asset.source_bounds_m.height)):
			return
		stage.remove_child(vegetation)
		vegetation.free()

	report.complete = true
	var manifest := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	if manifest == null:
		_fail("cannot write report.json")
		return
	manifest.store_string(JSON.stringify(report, "\t", true) + "\n")
	manifest.close()
	print("MIP CAPTURE COMPLETE: ", output_dir)
	quit(0)


func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.37, 0.4, 1.0)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = false
	environment.fog_enabled = false
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.98, 0.94, 1.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	stage.add_child(sun)


func _asset_record(asset_id: String, asset: Dictionary, parts: Array[Dictionary]) -> Dictionary:
	var scene_path := str(asset.get("scene", ""))
	var surfaces: Array[Dictionary] = []
	var triangle_total := 0
	for part_index in range(parts.size()):
		var part: Dictionary = parts[part_index]
		triangle_total += int(part.get("source_triangles", 0))
		var materials: Array = part.get("materials", [])
		for surface_index in range(materials.size()):
			var material: Material = materials[surface_index]
			surfaces.append({
				"part_index": part_index,
				"surface_index": surface_index,
				"material_class": material.get_class() if material != null else "null",
				"material_resource": material.resource_path if material != null else "",
				"albedo_texture": _material_texture_path(material, "albedo_texture"),
				"normal_texture": _material_texture_path(material, "normal_texture"),
				"transparency": _material_property(material, "transparency", -1),
				"alpha_scissor_threshold": _material_property(material, "alpha_scissor_threshold", -1.0),
				"cull_mode": _material_property(material, "cull_mode", -1),
			})
	return {
		"scene": scene_path,
		"scene_sha256": FileAccess.get_sha256(scene_path) if not scene_path.is_empty() and FileAccess.file_exists(scene_path) else "missing",
		"catalog_source_sha256": str(asset.get("source_sha256", "")),
		"role": str(asset.get("role", "")),
		"height_m": float(asset.get("source_bounds_m", {}).get("height", 0.0)),
		"parts": parts.size(),
		"surfaces": surfaces,
		"triangles": triangle_total,
	}


func _record_textures(asset_id: String, parts: Array[Dictionary]) -> void:
	for part in parts:
		var materials: Array = part.get("materials", [])
		for material in materials:
			if material == null:
				continue
			for property_info in material.get_property_list():
				var property_name := str(property_info.get("name", ""))
				var value: Variant = material.get(property_name)
				if value is Texture2D and not value.resource_path.is_empty():
					_register_texture(asset_id, value as Texture2D)


func _register_texture(asset_id: String, texture: Texture2D) -> void:
	var path := texture.resource_path
	if not report.textures.has(path):
		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			_fail("texture image data is unavailable: " + path)
			return
		var image_hash := HashingContext.new()
		image_hash.start(HashingContext.HASH_SHA256)
		image_hash.update(image.get_data())
		var import_path := path + ".import"
		var import_text := ""
		if FileAccess.file_exists(import_path):
			var import_file := FileAccess.open(import_path, FileAccess.READ)
			if import_file != null:
				import_text = import_file.get_as_text()
				import_file.close()
		if import_text.is_empty() or not FileAccess.file_exists(path):
			_fail("source texture or full importer configuration is missing: " + path)
			return
		report.textures[path] = {
			"basename": path.get_file(),
			"source_png_sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing",
			"import_path": import_path,
			"import_sha256": FileAccess.get_sha256(import_path) if FileAccess.file_exists(import_path) else "missing",
			"import_config_text": import_text,
			"texture_class": texture.get_class(),
			"image_size": [image.get_width(), image.get_height()],
			"image_format": image.get_format(),
			"decoded_image_has_mipmaps": image.has_mipmaps(),
			"decoded_image_mipmap_count": image.get_mipmap_count(),
			"decoded_image_data_bytes": image.get_data().size(),
			"decoded_image_data_sha256": image_hash.finish().hex_encode(),
			"used_by": [],
		}
	var consumers: Array = report.textures[path].used_by
	if not consumers.has(asset_id):
		consumers.append(asset_id)


func _material_texture_path(material: Material, property_name: String) -> String:
	if material == null:
		return ""
	var value: Variant = material.get(property_name)
	return value.resource_path if value is Texture2D else ""


func _material_property(material: Material, property_name: String, fallback: Variant) -> Variant:
	if material == null:
		return fallback
	for property_info in material.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return material.get(property_name)
	return fallback


func _capture_asset(asset_id: String, height_m: float) -> bool:
	for size in VIEW_SIZES:
		viewport.size = size
		for _resize_frame in 2:
			await _frame()
		for distance_value in DISTANCES_M:
			var distance_m: float = float(distance_value)
			var world_units_per_pixel: float = 2.0 * distance_m * tan(deg_to_rad(FOV_DEGREES * 0.5)) / float(size.y)
			for phase_index in range(PHASE_COUNT):
				var phase: float = float(phase_index) / float(PHASE_COUNT)
				var horizontal_offset: float = phase * world_units_per_pixel
				var view_center: Vector3 = Vector3(horizontal_offset, height_m * 0.5, 0.0)
				camera.look_at_from_position(
					view_center + Vector3(0.0, 0.0, distance_m),
					view_center,
					Vector3.UP
				)
				for _warmup_frame in 3:
					await _frame()
				var file_name: String = "%s__d%03d__%dx%d__p%02d.png" % [
					asset_id, int(distance_m), size.x, size.y, phase_index,
				]
				var absolute_path: String = output_dir.path_join(file_name)
				var image: Image = viewport.get_texture().get_image()
				if image == null or image.is_empty() or image.save_png(absolute_path) != OK:
					_fail("empty or failed frame capture: " + file_name)
					return false
				report.captures.append({
					"asset_id": asset_id,
					"distance_m": distance_m,
					"width": size.x,
					"height": size.y,
					"phase_index": phase_index,
					"subpixel_offset_x_px": phase,
					"world_offset_x_m": horizontal_offset,
					"filename": file_name,
					"sha256": FileAccess.get_sha256(absolute_path),
				})
	return true


func _frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
