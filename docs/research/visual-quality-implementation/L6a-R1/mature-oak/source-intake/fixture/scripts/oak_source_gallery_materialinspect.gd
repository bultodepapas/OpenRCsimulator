## Offline source geometry/material inspection and optional neutral comparison captures.
## Run against an isolated project; this script does not depend on or modify app/.
extends SceneTree

const REPORT_FORMAT := "openrc-tree-source-gallery v1"
const VARIANT_NAMES: Array[String] = [
	"Quercus_A_LOD0",
]

var args: Dictionary = {}
var output_path: String = ""
var capture_enabled: bool = false
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var report: Dictionary = {
	"format": REPORT_FORMAT,
	"complete": false,
	"variants": [],
	"captures": [],
}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	call_deferred("_run")


func _run() -> void:
	var source_path := str(args.get("source", ""))
	output_path = str(args.get("out", ""))
	var capture_mode := str(args.get("capture", "off")).to_lower()
	if source_path.is_empty() or output_path.is_empty():
		_fail("--source=<absolute glTF path> and --out=<new folder> are required")
		return
	if not source_path.is_absolute_path() or not output_path.is_absolute_path():
		_fail("--source and --out must be absolute paths")
		return
	if not FileAccess.file_exists(source_path):
		_fail("source glTF does not exist: " + source_path)
		return
	if capture_mode != "off" and capture_mode != "on":
		_fail("--capture must be off or on")
		return
	capture_enabled = capture_mode == "on"
	if DirAccess.dir_exists_absolute(output_path) and not DirAccess.get_files_at(output_path).is_empty():
		_fail("output must be new or empty: " + output_path)
		return
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		_fail("could not create output folder: " + output_path)
		return

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var flags: int = GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION
	var source_directory := source_path.get_base_dir()
	var load_error: Error = document.append_from_file(source_path, state, flags, source_directory)
	if load_error != OK:
		_fail("GLTFDocument.append_from_file failed with error %d" % load_error)
		return
	var source_scene := document.generate_scene(state) as Node3D
	if source_scene == null:
		_fail("GLTFDocument did not generate a Node3D scene")
		return

	if capture_enabled:
		if not _setup_capture():
			source_scene.free()
			return
		stage.add_child(source_scene)
	else:
		root.add_child(source_scene)
		source_scene.visible = false

	var source_record := _source_identity(source_path)
	report["source"] = source_record
	report["asset"] = {
		"title": "Oak Tree (Quercus robur)",
		"asset_url": "https://opengameart.org/content/oak-tree",
		"download_url": "https://opengameart.org/sites/default/files/quercus_A_packed_v1_0.zip",
		"authors": ["lauris71"],
		"download_date": "2026-10-18",
		"license": "CC BY-SA 3.0",
		"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
		"notice_path": "assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/LICENSE_OAK.txt",
		"source_archive_sha256": "496f250c29eb1f56e391e55989530028e156ae43a3d1eb9f52ab09aa1bccbebf",
		"source_blend_sha256": "3b32573acd4e8eb5b7e0a96aa363932ec785a854d6e8c71f56f29b10f5abd37c",
	}
	report["godot"] = Engine.get_version_info().string
	report["capture_settings"] = {
		"requested": capture_enabled,
		"renderer": RenderingServer.get_current_rendering_method() if capture_enabled else "not_initialized",
		"width": int(args.get("width", "1280")) if capture_enabled else null,
		"height": int(args.get("height", "1280")) if capture_enabled else null,
		"msaa": "4x" if capture_enabled else null,
		"orthographic_frame_height_m": float(args.get("frame_height_m", "14.0")) if capture_enabled else null,
		"source_materials_mutated": false,
		"mesh_decimation": false,
	}

	var variants: Array[Dictionary] = []
	for variant_name: String in VARIANT_NAMES:
		var variant_node := _find_named(source_scene, variant_name)
		if variant_node == null:
			_fail("missing complete source node: " + variant_name)
			source_scene.queue_free()
			return
		var variant_record := _describe_variant(source_scene, variant_node, variant_name)
		if variant_record.is_empty():
			_fail("source node has no mesh geometry: " + variant_name)
			source_scene.queue_free()
			return
		variants.append(variant_record)
	report["variants"] = variants

	if capture_enabled:
		if not await _capture_variants(source_scene):
			source_scene.queue_free()
			return
		report["capture_settings"]["adapter"] = RenderingServer.get_video_adapter_name()
		report["capture_settings"]["api"] = RenderingServer.get_video_adapter_api_version()
	else:
		report["capture_settings"]["status"] = "metadata_only; no viewport or renderer capture was requested"

	report["complete"] = true
	var report_file := FileAccess.open(output_path.path_join("source_gallery.json"), FileAccess.WRITE)
	if report_file == null:
		_fail("could not write source_gallery.json")
		source_scene.queue_free()
		return
	report_file.store_string(JSON.stringify(report, "\t", true) + "\n")
	var report_error: Error = report_file.get_error()
	report_file.close()
	source_scene.queue_free()
	if report_error != OK:
		_fail("failed while writing source_gallery.json")
		return
	print("TREE SOURCE GALLERY COMPLETE: ", output_path)
	quit(0)


func _setup_capture() -> bool:
	if DisplayServer.get_name() == "headless":
		_fail("--capture=on requires a real Compatibility framebuffer; use --capture=off for headless inspection")
		return false
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("source comparison capture requires the Compatibility renderer")
		return false
	var width := int(args.get("width", "1280"))
	var height := int(args.get("height", "1280"))
	if width < 128 or height < 128:
		_fail("capture width and height must each be at least 128 pixels")
		return false
	var frame_height := float(args.get("frame_height_m", "14.0"))
	if frame_height <= 0.0:
		_fail("--frame_height_m must be greater than zero")
		return false

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	viewport = SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.mesh_lod_threshold = 0.0
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.24, 0.25, 0.26, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	stage.add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.name = "Neutral_Key_Light"
	key_light.rotation_degrees = Vector3(-32.0, -28.0, 0.0)
	key_light.light_color = Color.WHITE
	key_light.light_energy = 1.0
	key_light.shadow_enabled = false
	stage.add_child(key_light)
	camera = Camera3D.new()
	camera.name = "Orthographic_Source_Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 100.0
	camera.size = frame_height
	stage.add_child(camera)
	camera.current = true
	return true


func _capture_variants(source_scene: Node3D) -> bool:
	source_scene.visible = false
	for variant_name: String in VARIANT_NAMES:
		var variant_node := _find_named(source_scene, variant_name)
		if variant_node == null:
			_fail("source node disappeared before capture: " + variant_name)
			return false
		variant_node.reparent(stage, true)
		variant_node.visible = true
		var bounds := _bounds_for_node(variant_node)
		if bounds.size.length_squared() <= 0.0:
			_fail("source node has empty bounds: " + variant_name)
			variant_node.reparent(source_scene, true)
			return false
		var center := bounds.get_center()
		var requested_views := str(args.get("views", "front,back,underside,overhead")).split(",", false)
		for view_name: String in requested_views:
			if not await _capture_view(variant_name, view_name, center, bounds.size.y):
				variant_node.reparent(source_scene, true)
				return false
		variant_node.reparent(source_scene, true)
	return true


func _capture_view(variant_name: String, view_name: String, target: Vector3, object_height: float) -> bool:
	var distance := maxf(object_height * 2.5, 2.0)
	var eye: Vector3
	var up := Vector3.UP
	match view_name:
		"front":
			eye = target + Vector3(0.0, 0.0, distance)
		"back":
			eye = target + Vector3(0.0, 0.0, -distance)
		"underside":
			eye = target + Vector3(0.0, -distance, 0.0)
			up = Vector3.FORWARD
		"overhead":
			eye = target + Vector3(0.0, distance, 0.0)
			up = Vector3.FORWARD
		_:
			_fail("unknown view: " + view_name)
			return false
	camera.look_at_from_position(eye, target, up)
	for frame: int in range(4):
		await process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		_fail("renderer returned an empty image for %s %s" % [variant_name, view_name])
		return false
	image.convert(Image.FORMAT_RGBA8)
	var filename := "oak-lod0-%s.png" % view_name
	var image_path := output_path.path_join(filename)
	var save_error: Error = image.save_png(image_path)
	if save_error != OK:
		_fail("failed to save capture: " + image_path)
		return false
	report["captures"].append({
		"variant": variant_name,
		"view": view_name,
		"path": filename,
		"sha256": FileAccess.get_sha256(image_path),
		"size_px": [image.get_width(), image.get_height()],
		"camera_projection": "orthographic",
		"camera_frame_height_m": float(args.get("frame_height_m", "14.0")),
		"target_world_m": _vec3(target),
		"eye_world_m": _vec3(eye),
		"up_world": _vec3(up),
		"source_scale_preserved": true,
	})
	return true


func _source_identity(source_path: String) -> Dictionary:
	var file := FileAccess.open(source_path, FileAccess.READ)
	var byte_size := file.get_length() if file != null else -1
	if file != null:
		file.close()
	var record: Dictionary = {
		"path": source_path,
		"format": "glTF 2.0",
		"bytes": byte_size,
		"sha256": FileAccess.get_sha256(source_path),
		"dependencies": [],
	}
	var manifest_path := source_path.get_base_dir().path_join("download-manifest.json")
	if not FileAccess.file_exists(manifest_path):
		record["manifest"] = null
		return record
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Array:
		record["manifest"] = {"path": manifest_path, "error": "not a JSON array"}
		return record
	record["manifest"] = {"path": manifest_path, "sha256": FileAccess.get_sha256(manifest_path)}
	var dependencies: Array[Dictionary] = []
	for entry: Variant in parsed:
		if not entry is Dictionary or not entry.has("path"):
			continue
		var relative_path := str(entry.get("path", ""))
		var dependency_path := source_path.get_base_dir().path_join(relative_path).simplify_path()
		var exists := FileAccess.file_exists(dependency_path)
		var actual_bytes := _file_size(dependency_path) if exists else -1
		var actual_sha256 := FileAccess.get_sha256(dependency_path) if exists else ""
		dependencies.append({
			"path": relative_path,
			"url": str(entry.get("url", "")),
			"api_md5": str(entry.get("api_md5", "")),
			"expected_bytes": int(entry.get("size_bytes", -1)),
			"expected_sha256": str(entry.get("sha256", "")),
			"actual_bytes": actual_bytes,
			"actual_sha256": actual_sha256,
			"verified_against_manifest": exists
				and actual_bytes == int(entry.get("size_bytes", -2))
				and actual_sha256 == str(entry.get("sha256", "")),
		})
	record["dependencies"] = dependencies
	return record


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


func _describe_variant(source_scene: Node3D, variant_node: Node3D, variant_name: String) -> Dictionary:
	var mesh_nodes := _mesh_nodes(variant_node)
	if mesh_nodes.is_empty():
		return {}
	var surface_records: Array[Dictionary] = []
	var triangle_count := 0
	for mesh_node: MeshInstance3D in mesh_nodes:
		if mesh_node.mesh == null:
			continue
		for surface_index: int in range(mesh_node.mesh.get_surface_count()):
			var surface_arrays: Array = mesh_node.mesh.surface_get_arrays(surface_index)
			if surface_arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if surface_arrays.size() > Mesh.ARRAY_INDEX:
				indices = surface_arrays[Mesh.ARRAY_INDEX]
			var primitive_type: int = mesh_node.mesh.surface_get_primitive_type(surface_index)
			var surface_triangles := 0
			if primitive_type == Mesh.PRIMITIVE_TRIANGLES:
				surface_triangles = int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
			triangle_count += surface_triangles
			var material := mesh_node.get_active_material(surface_index)
			if material == null:
				material = mesh_node.mesh.surface_get_material(surface_index)
			surface_records.append({
				"node": str(source_scene.get_path_to(mesh_node)),
				"mesh": str(mesh_node.mesh.resource_name),
				"surface_index": surface_index,
				"surface_name": mesh_node.mesh.surface_get_name(surface_index),
				"primitive_type": primitive_type,
				"vertex_count": vertices.size(),
				"index_count": indices.size(),
				"triangle_count": surface_triangles,
				"material": _material_record(material),
			})
	if surface_records.is_empty():
		return {}
	var local_transform := variant_node.transform
	return {
		"id": variant_name,
		"node_path": str(source_scene.get_path_to(variant_node)),
		"node_class": variant_node.get_class(),
		"source_node_translation_m": _vec3(local_transform.origin),
		"source_node_scale": _vec3(local_transform.basis.get_scale()),
		"source_node_basis_columns": [
			_vec3(local_transform.basis.x),
			_vec3(local_transform.basis.y),
			_vec3(local_transform.basis.z),
		],
		"world_bounds_m": _aabb_record(_bounds_for_node(variant_node)),
		"mesh_instance_count": mesh_nodes.size(),
		"surfaces": surface_records,
		"triangle_count": triangle_count,
		"lod": {"present": false, "basis": "Original glTF node and mesh inventory; no LOD generation or mesh_lod_threshold substitution."},
	}


func _material_record(material: Material) -> Dictionary:
	if material == null:
		return {"class": "null"}
	var result: Dictionary = {
		"class": material.get_class(),
		"name": material.resource_name,
		"resource_path": material.resource_path,
	}
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		result["properties"] = {
			"albedo_color": _property_value(base, "albedo_color"),
			"albedo_texture": _property_value(base, "albedo_texture"),
			"normal_texture": _property_value(base, "normal_texture"),
			"metallic_texture": _property_value(base, "metallic_texture"),
			"roughness_texture": _property_value(base, "roughness_texture"),
			"ao_texture": _property_value(base, "ao_texture"),
			"transparency": _property_value(base, "transparency"),
			"alpha_scissor_threshold": _property_value(base, "alpha_scissor_threshold"),
			"cull_mode": _property_value(base, "cull_mode"),
			"shading_mode": _property_value(base, "shading_mode"),
			"metallic": _property_value(base, "metallic"),
			"metallic_specular": _property_value(base, "metallic_specular"),
			"roughness": _property_value(base, "roughness"),
		}
	return result


func _property_value(object: Object, property_name: String) -> Variant:
	for descriptor: Dictionary in object.get_property_list():
		if str(descriptor.get("name", "")) == property_name:
			var value: Variant = object.get(property_name)
			if value is Color:
				return _color(value)
			if value is Texture2D:
				return _texture_record(value)
			return value
	return null


func _texture_record(value: Variant) -> Variant:
	if not value is Texture2D:
		return null
	var texture := value as Texture2D
	return {
		"class": texture.get_class(),
		"name": texture.resource_name,
		"resource_path": texture.resource_path,
		"size_px": [texture.get_width(), texture.get_height()],
	}


func _find_named(node: Node, target_name: String) -> Node3D:
	if node is Node3D and str(node.name).to_lower() == target_name.to_lower():
		return node as Node3D
	for child: Node in node.get_children():
		var found := _find_named(child, target_name)
		if found != null:
			return found
	return null


func _mesh_nodes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_mesh_nodes(child))
	return found


func _bounds_for_node(node: Node) -> AABB:
	var bounds := AABB()
	var has_vertex := false
	for mesh_node: MeshInstance3D in _mesh_nodes(node):
		if mesh_node.mesh == null:
			continue
		for surface_index: int in range(mesh_node.mesh.get_surface_count()):
			var surface_arrays: Array = mesh_node.mesh.surface_get_arrays(surface_index)
			if surface_arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point: Vector3 = mesh_node.global_transform * vertex
				if not has_vertex:
					bounds = AABB(point, Vector3.ZERO)
					has_vertex = true
				else:
					bounds = bounds.expand(point)
	return bounds


func _aabb_record(bounds: AABB) -> Dictionary:
	return {
		"position": _vec3(bounds.position),
		"size": _vec3(bounds.size),
		"center": _vec3(bounds.get_center()),
	}


func _vec3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _color(value: Color) -> Array[float]:
	return [value.r, value.g, value.b, value.a]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
