## L11a production-field captures for opaque near grass. The camera, environment and field are the production builders;
## only NearGrass visibility and the shader clock inputs vary between matched images.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")

const FORMAT: String = "openrc-l11a-grass-capture v2"
const WIDTH: int = 1280
const HEIGHT: int = 720
const FOV_DEG: float = 50.0
const FAR_M: float = 21000.0
const SETTLE_FRAMES: int = 3
const GRASS_SHADER_PATH: String = "res://render/near_grass.gdshader"
const IMPORTED_GRASS_SHADER_PATH: String = "res://scenery/imported_grass.gdshader"
const GRASS_DATA_PATH: String = "res://data/fields/grass.json"
const WIND: Vector3 = Vector3(5.0, 0.0, 0.0)
const IMPORTED_GRASS_IDS: Array[String] = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]
const IMPORTED_FLOWER_IDS: Array[String] = ["clover_1", "flower_3_group", "flower_4_group"]
const STATIC_IMPORTED_GRASS_COUNTS: Dictionary = {
	"grass_common_short": 67,
	"grass_common_tall": 42,
	"grass_wispy_tall": 41,
}
const ENHANCED_IMPORTED_GRASS_COUNTS: Dictionary = {
	"grass_common_short": 100,
	"grass_common_tall": 30,
	"grass_wispy_tall": 20,
}
const IMPORTED_GRASS_TOTAL: int = 150
const ENHANCED_IMPORTED_GRASS_TRIANGLES: int = 37720
const IMPORTED_GRASS_TRIANGLE_BUDGET: int = 50000

var _args: Dictionary = {}
var _out_dir: String = ""
var _mode: String = ""
var _smoke: bool = false
var _cases: Array[Dictionary] = []
var _field_data: Dictionary = {}
var _field_node: Node3D
var _near_grass: Node3D
var _camera: Camera3D
var _world: Node3D
var _environment: Environment
var _grass_report: Dictionary = {}
var _flower_report: Dictionary = {"count": 0, "names": []}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_out_dir = str(_args.get("out", ""))
	_mode = str(_args.get("mode", "candidate"))
	_smoke = _is_on("smoke")
	if _out_dir.is_empty():
		_fail("--out is required")
		return
	if not ["candidate", "baseline", "scenery"].has(_mode):
		_fail("--mode must be candidate, baseline, or scenery")
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output_dir: DirAccess = DirAccess.open(_out_dir)
	if output_dir == null or not output_dir.get_files().is_empty() or not output_dir.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return

	var scenery_on: bool = _mode == "scenery"
	OS.set_environment("OPENRC_SCENERY", "on" if scenery_on else "off")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	# Register both global shader uniforms before any production field material is built or compiled.
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default field failed validation: " + str(loaded.get("errors", [])))
		return
	_field_data = loaded.get("field", {})
	var world_data: Dictionary = _build_world()
	if world_data.is_empty():
		return
	_world = world_data["world"] as Node3D
	_field_node = world_data["field"] as Node3D
	_near_grass = _field_node.get_node_or_null("NearGrass") as Node3D
	_camera = world_data["camera"] as Camera3D
	_environment = world_data["environment"] as Environment
	# Material defaults are available from the RenderingServer only after the field's shader has entered the tree.
	await process_frame
	if _mode != "baseline" and _near_grass == null:
		_fail("production Field is missing its NearGrass child")
		_world.queue_free()
		return
	if _mode == "baseline" and _near_grass != null:
		_near_grass.visible = false
	if _near_grass != null:
		_near_grass.visible = false
	if _mode != "baseline":
		_grass_report = _inspect_grass(_near_grass)
		if _grass_report.is_empty():
			_world.queue_free()
			return
	if scenery_on:
		_flower_report = _inspect_flowers(_field_node)
		if int(_flower_report.get("count", 0)) <= 0:
			_fail("--scenery=on produced no SC-16 flowers")
			_world.queue_free()
			return
	if not _validate_scenery_contract(scenery_on):
		_world.queue_free()
		return

	# Keep clouds and all ground materials frozen at production time zero. Only ShaderClock changes in the wind probe.
	Atmosphere.update_clouds(_environment, 0.0)
	var scenarios: Array[Dictionary] = _scenarios()
	if _smoke and _mode != "scenery":
		scenarios = [scenarios[0]]
	for scenario: Dictionary in scenarios:
		if _mode == "baseline":
			var baseline_case: Dictionary = await _capture(scenario, "off", 0.0, Vector3.ZERO)
			if baseline_case.is_empty():
				_world.queue_free()
				return
			_cases.append(baseline_case)
		else:
			_near_grass.visible = false
			var off_case: Dictionary = await _capture(scenario, "off", 0.0, Vector3.ZERO)
			if off_case.is_empty():
				_world.queue_free()
				return
			_cases.append(off_case)
			_near_grass.visible = true
			var on_case: Dictionary = await _capture(scenario, "on", 0.0, Vector3.ZERO)
			if on_case.is_empty():
				_world.queue_free()
				return
			_cases.append(on_case)

	if not _smoke and (_mode == "candidate" or \
			(_mode == "scenery" and _grass_report.get("material_mode", "") == "qualified_wind")):
		var wind_scenario: Dictionary = _scenarios()[0]
		var wind_ok: bool = await _capture_wind_probes(wind_scenario)
		if not wind_ok:
			_world.queue_free()
			return

	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"smoke": _smoke,
		"field": FieldLoader.DEFAULT_PATH,
		"field_id": str(_field_data.get("id", "")),
		"viewport": {"width": root.get_viewport().size.x, "height": root.get_viewport().size.y},
		"renderer": RenderingServer.get_video_adapter_name(),
		"scenery_on": scenery_on,
		"near_grass_material_mode": str(_grass_report.get("material_mode", "not_present")),
		"environment": "Atmosphere.environment() + Atmosphere.create_sun()",
		"clock_policy": "clouds/ground frozen at t=0; ShaderClock varies only in emitted wind-probe cases",
		"grass": _grass_report if _mode != "baseline" else {"present": false},
		"flowers": _flower_report,
		"cases": _cases,
	}
	var manifest_path: String = _out_dir.path_join("capture-manifest.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write manifest: " + manifest_path)
		_world.queue_free()
		return
	file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	file.close()
	print("L11a GRASS CAPTURE ", _mode, " ", _cases.size(), " cases -> ", _out_dir)
	_world.queue_free()
	quit(0)


func _capture_wind_probes(wind_scenario: Dictionary) -> bool:
	_near_grass.visible = true
	for wind_case: Dictionary in [
		{"id": "windless-t1", "time": 1.0, "wind": Vector3.ZERO},
		{"id": "wind-on-t0", "time": 0.0, "wind": WIND},
		{"id": "wind-on-t1", "time": 1.0, "wind": WIND},
		{"id": "wind-on-t1024", "time": 1024.0, "wind": WIND},
	]:
		var captured: Dictionary = await _capture(wind_scenario, str(wind_case.id),
			float(wind_case.time), wind_case.wind)
		if captured.is_empty():
			return false
		_cases.append(captured)
	return true


func _build_world() -> Dictionary:
	var world: Node3D = Node3D.new()
	world.name = "GrassCaptureWorld"
	root.add_child(world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	_environment = Atmosphere.environment()
	environment_node.environment = _environment
	world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field_data)
	_field_node.process_mode = Node.PROCESS_MODE_DISABLED
	_freeze_other_vegetation(_field_node)
	# This probe varies grass wind only; L15b has a separate tree-wind capture.
	# Permit older baseline shaders without the ablation uniform.
	var grove: Node3D = _field_node.get_node_or_null("treeline") as Node3D
	if grove != null:
		for child: MultiMeshInstance3D in grove.get_children():
			var tree_material: ShaderMaterial = child.multimesh.mesh.surface_get_material(0) as ShaderMaterial
			for parameter: Dictionary in tree_material.shader.get_shader_uniform_list():
				if parameter.name == "wind_enabled":
					tree_material.set_shader_parameter("wind_enabled", false)
	world.add_child(_field_node)
	Atmosphere.create_sun(world)
	var camera: Camera3D = Camera3D.new()
	camera.name = "GrassCaptureCamera"
	camera.fov = FOV_DEG
	camera.near = 0.1
	camera.far = FAR_M
	world.add_child(camera)
	camera.current = true
	return {"world": world, "field": _field_node, "environment": _environment, "camera": camera}


## Attribute this fixture's moving pixels to grass. Other vegetation has its own wind proof.
## Duplicate overrides so cached source materials and other scenes are never mutated.
func _freeze_other_vegetation(node: Node) -> void:
	if node.name == "NearGrass":
		return
	if node is MultiMeshInstance3D:
		var instance := node as MultiMeshInstance3D
		var mesh := instance.multimesh.mesh
		for index: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(index) as ShaderMaterial
			if material == null:
				continue
			var frozen := material.duplicate() as ShaderMaterial
			var changed := false
			for parameter: Dictionary in RenderingServer.get_shader_parameter_list(material.shader.get_rid()):
				var name := str(parameter.name)
				if name == "wind_enabled":
					frozen.set_shader_parameter(name, false)
					instance.set_instance_shader_parameter(name, false)
					changed = true
				elif name == "wind_strength":
					frozen.set_shader_parameter(name, 0.0)
					instance.set_instance_shader_parameter(name, 0.0)
					changed = true
			if changed:
				mesh.surface_set_material(index, frozen)
	for child: Node in node.get_children():
		_freeze_other_vegetation(child)


func _scenarios() -> Array[Dictionary]:
	var pilot: Dictionary = _field_data.get("pilot", {})
	var n: float = float(pilot.get("north", 0.0))
	var e: float = float(pilot.get("east", 0.0))
	var result: Array[Dictionary] = []
	if _mode == "scenery":
		# The camera stays within the pilot grass disk while showing the runway edge and SC-16 field flowers.
		return [{"id": "scenery-runway-edge", "north": n + 6.0, "east": e, "height": 1.7,
			"azimuth": 45.0, "elevation": -10.0, "scope": "scenery-runway-edge"}]
	for elevation: float in [-10.0, -25.0]:
		for azimuth: float in [0.0, 90.0, 180.0, 270.0]:
			result.append({"id": "pilot-az%03d-el%02d" % [int(azimuth), int(absf(elevation))],
				"north": n, "east": e, "height": float(pilot.get("eye_height", 1.7)),
				"azimuth": azimuth, "elevation": elevation, "scope": "pilot"})
	result.append({"id": "raised-low-pass", "north": n, "east": e, "height": 3.0,
		"azimuth": 0.0, "elevation": -8.0, "scope": "raised-low-pass"})
	result.append({"id": "near-runway", "north": n + 6.0, "east": e, "height": 1.7,
		"azimuth": 45.0, "elevation": -10.0, "scope": "near-runway"})
	result.append({"id": "band-25-35m", "north": n, "east": e, "height": 3.0,
		"azimuth": 0.0, "elevation": -3.0, "scope": "projected-ground-band"})
	result.append({"id": "fade-camera-35m", "north": n, "east": e, "height": 35.0,
		"azimuth": 0.0, "elevation": -60.0, "scope": "camera-distance-fade-collapse"})
	return result


func _capture(scenario: Dictionary, grass_state: String, shader_time: float, wind: Vector3) -> Dictionary:
	if grass_state == "off":
		if _near_grass != null:
			_near_grass.visible = false
	elif _near_grass != null:
		_near_grass.visible = true
	ShaderClock.update(shader_time, wind)
	var camera_position: Vector3 = Frames.ned_to_render([
		float(scenario.north), float(scenario.east), float(_field_data.pilot.down) - float(scenario.height),
	])
	var azimuth: float = deg_to_rad(float(scenario.azimuth))
	var elevation: float = deg_to_rad(float(scenario.elevation))
	var direction: Vector3 = Frames.ned_to_render([
		cos(azimuth) * cos(elevation), sin(azimuth) * cos(elevation), -sin(elevation),
	])
	_camera.position = camera_position
	_camera.look_at(camera_position + direction * 1000.0, Vector3.UP)
	for _frame: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport returned an empty image for " + str(scenario.id))
		return {}
	var state_tag: String = "grass-" + grass_state if grass_state == "on" or grass_state == "off" else grass_state
	var case_id: String = str(scenario.id) + "-" + state_tag
	if grass_state.begins_with("wind"):
		case_id = grass_state
	var image_name: String = "capture-%s.png" % case_id
	var image_path: String = _out_dir.path_join(image_name)
	if image.save_png(image_path) != OK:
		_fail("failed to save capture " + image_path)
		return {}
	return {
		"id": case_id,
		"image": image_name,
		"scenario_id": str(scenario.id),
		"grass": grass_state if grass_state == "on" or grass_state == "off" else "on",
		"shader_time_s": shader_time,
		"shader_clock": ShaderClock.last_clock,
		"wind_vec": [wind.x, wind.y, wind.z],
		"camera_north_m": float(scenario.north),
		"camera_east_m": float(scenario.east),
		"camera_height_m": float(scenario.height),
		"azimuth_deg": float(scenario.azimuth),
		"elevation_deg": float(scenario.elevation),
		"camera_fov_deg": FOV_DEG,
		"visual_scope": str(scenario.scope),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"flower_count": int(_flower_report.get("count", 0)),
	}


func _inspect_grass(grass: Node3D) -> Dictionary:
	if grass == null:
		_fail("cannot inspect missing NearGrass")
		return {}
	var chunks: Array[Node] = grass.find_children("*", "MultiMeshInstance3D", true, false)
	var imported: bool = bool(grass.get_meta("imported", false))
	if chunks.is_empty() or (imported and chunks.size() != IMPORTED_GRASS_IDS.size()) or (not imported and chunks.size() > 4):
		_fail("NearGrass has an invalid MultiMesh count for its implementation: %d" % chunks.size())
		return {}
	var pilot: Dictionary = _field_data.pilot
	var pilot_n: float = float(pilot.north)
	var pilot_e: float = float(pilot.east)
	var total_clumps: int = 0
	var total_triangles: int = 0
	var max_radius: float = 0.0
	var min_radius: float = INF
	var shadow_nodes: Array[String] = []
	var actual_fade_start: float = NAN
	var actual_fade_end: float = NAN
	var actual_fade_source: String = ""
	var runway: Dictionary = {}
	for surface: Dictionary in _field_data.surfaces:
		if surface.id == str(_field_data.runway):
			runway = surface
	if runway.is_empty():
		_fail("default field does not contain its declared runway surface")
		return {}
	if (_mode == "scenery") != imported:
		_fail("capture mode received the wrong near-grass implementation")
		return {}
	if imported:
		return _inspect_imported_grass(grass, chunks, pilot_n, pilot_e, runway)
	for child: Node in chunks:
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance.multimesh == null:
			_fail("NearGrass has a MultiMesh child with no MultiMesh: " + str(instance.get_path()))
			return {}
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_nodes.append(str(instance.name))
		var mesh: Mesh = instance.multimesh.mesh
		if mesh == null:
			_fail("NearGrass MultiMesh has no blade mesh")
			return {}
		var triangle_count: int = 0
		for surface_index: int in mesh.get_surface_count():
			var material: ShaderMaterial = mesh.surface_get_material(surface_index) as ShaderMaterial
			if material == null or material.shader == null or material.shader.resource_path != GRASS_SHADER_PATH:
				_fail("grass clump mesh must use the production near-grass ShaderMaterial")
				return {}
			var fade_start_value: Variant = material.get_shader_parameter("fade_start_m")
			var fade_end_value: Variant = material.get_shader_parameter("fade_end_m")
			var fade_start_from_default: bool = fade_start_value == null
			var fade_end_from_default: bool = fade_end_value == null
			if fade_start_from_default:
				fade_start_value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), &"fade_start_m")
			if fade_end_from_default:
				fade_end_value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), &"fade_end_m")
			if fade_start_value == null or fade_end_value == null:
				_fail("compiled near-grass shader does not expose its 22–30 m parameter defaults")
				return {}
			var fade_source: String = "material overrides"
			if fade_start_from_default and fade_end_from_default:
				fade_source = "compiled ShaderMaterial parameter defaults"
			elif fade_start_from_default or fade_end_from_default:
				fade_source = "material overrides with compiled defaults"
			actual_fade_start = float(fade_start_value)
			actual_fade_end = float(fade_end_value)
			if actual_fade_source.is_empty():
				actual_fade_source = fade_source
			elif actual_fade_source != fade_source:
				_fail("grass materials disagree about fade parameter sources")
				return {}
			if absf(actual_fade_start - 22.0) > 1e-6 or absf(actual_fade_end - 30.0) > 1e-6:
				_fail("grass material fade parameters are %.6f–%.6f m; expected 22–30 m" % [actual_fade_start, actual_fade_end])
				return {}
			if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				_fail("grass clumps must use triangle primitives")
				return {}
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if vertices.size() != uvs.size() or vertices.size() % 3 != 0:
				_fail("grass mesh vertex/UV arrays are malformed")
				return {}
			for vertex_index: int in vertices.size():
				if absf(vertices[vertex_index].y) <= 1e-6:
					if absf(uvs[vertex_index].y) > 1e-6:
						_fail("grass root vertices must have UV.y=0 for fixed-root sway")
						return {}
				elif uvs[vertex_index].y < 0.99:
					_fail("grass blade tips must have UV.y=1 for wind displacement")
					return {}
			triangle_count += vertices.size() / 3
		if triangle_count != 7:
			_fail("expected seven opaque grass triangles per clump; found %d" % triangle_count)
			return {}
		total_triangles += triangle_count * instance.multimesh.instance_count
		for i: int in instance.multimesh.instance_count:
			var point: Vector3 = instance.global_transform * instance.multimesh.get_instance_transform(i).origin
			var east: float = point.x
			var north: float = -point.z
			var radius: float = Vector2(north - pilot_n, east - pilot_e).length()
			max_radius = maxf(max_radius, radius)
			min_radius = minf(min_radius, radius)
			if radius > 30.001:
				_fail("grass clump at %.3f m exceeds the 30 m pilot radius" % radius)
				return {}
			var inside_runway: bool = absf(north - float(runway.center_north)) <= float(runway.width_north_south) * 0.5 \
				and absf(east - float(runway.center_east)) <= float(runway.length_east_west) * 0.5
			if inside_runway:
				_fail("grass clump lies on the runway at north=%.3f east=%.3f" % [north, east])
				return {}
			total_clumps += 1
	if total_clumps <= 0 or total_clumps > 6000:
		_fail("grass clump count must be in 1–6000; found %d" % total_clumps)
		return {}
	if not shadow_nodes.is_empty():
		_fail("NearGrass must not cast shadows: " + str(shadow_nodes))
		return {}
	var shader_text: String = FileAccess.get_file_as_string(GRASS_SHADER_PATH)
	var fixed_root_contract: bool = shader_text.contains("world_vertex_coords") \
		and shader_text.contains("offset.xz += direction * sway * UV.y * UV.y;") \
		and shader_text.contains("VERTEX = origin + offset * shrink;") \
		and not RegEx.create_from_string("\\bTIME\\b").search(shader_text)
	if not fixed_root_contract:
		_fail("near-grass shader must use fixed-root UV-weighted sway and must not read TIME")
		return {}
	var distance_fade_contract: bool = actual_fade_start == 22.0 and actual_fade_end == 30.0 \
		and shader_text.contains("max(distance(origin.xz, pilot_xz), distance(origin, CAMERA_POSITION_WORLD))") \
		and shader_text.contains("1.0 - smoothstep(fade_start_m, fade_end_m, d)")
	if not distance_fade_contract:
		_fail("near-grass shader must fade from 22 m to 30 m by the farther of pilot and camera")
		return {}
	if RegEx.create_from_string("\\bALPHA\\b").search(shader_text) != null:
		_fail("near-grass shader must remain opaque")
		return {}
	var shader: Shader = load(GRASS_SHADER_PATH) as Shader
	return {
		"present": true,
		"implementation": "legacy_shader_material",
		"material_mode": "legacy_procedural",
		"node_count": 1,
		"multimesh_chunks": chunks.size(),
		"clumps": total_clumps,
		"triangles_per_clump": 7,
		"triangles": total_triangles,
		"pilot_radius_m": 30.0,
		"observed_radius_m": {"min": min_radius, "max": max_radius},
		"runway_clumps": 0,
		"casts_shadows": false,
		"fixed_root_geometry_and_shader_contract": fixed_root_contract,
		"opaque": true,
		"fade": {"start_m": actual_fade_start, "end_m": actual_fade_end, "source": actual_fade_source,
			"uses_camera_and_pilot": distance_fade_contract},
		"shader_sha256": shader_text.sha256_text(),
		"shader_resource_path": GRASS_SHADER_PATH if shader != null else "",
		"placement_path": GRASS_DATA_PATH,
	}


func _inspect_imported_grass(grass: Node3D, chunks: Array[Node], pilot_n: float, pilot_e: float,
		runway: Dictionary) -> Dictionary:
	var qualified_wind: bool = bool(grass.get_meta("grass_wind", false))
	var material_mode: String = "qualified_wind" if qualified_wind else "static_baseline"
	var qualified_shader: Shader
	var shader_sha256: String = ""
	var expected_counts: Dictionary = STATIC_IMPORTED_GRASS_COUNTS
	if qualified_wind:
		expected_counts = ENHANCED_IMPORTED_GRASS_COUNTS
		qualified_shader = load(IMPORTED_GRASS_SHADER_PATH) as Shader
		if qualified_shader == null or qualified_shader.resource_path != IMPORTED_GRASS_SHADER_PATH \
				or not _qualified_grass_shader_is_opaque_and_lit(qualified_shader):
			_fail("winded imported grass must use the exact opaque, per-pixel qualified shader path")
			return {}
		shader_sha256 = qualified_shader.code.sha256_text()
	var expected_ids: Array[String] = IMPORTED_GRASS_IDS.duplicate()
	expected_ids.sort()
	var raw_ids: Variant = grass.get_meta("source_assets", null)
	if not raw_ids is Array:
		_fail("imported NearGrass must report its source asset IDs")
		return {}
	var source_ids: Array[String] = []
	for raw_id: Variant in raw_ids:
		if typeof(raw_id) != TYPE_STRING:
			_fail("imported NearGrass source IDs must be strings")
			return {}
		source_ids.append(str(raw_id))
	source_ids.sort()
	if source_ids != expected_ids:
		_fail("imported NearGrass source IDs differ from the three accepted grass assets: " + str(source_ids))
		return {}
	if int(grass.get_meta("asset_batches", -1)) != IMPORTED_GRASS_IDS.size() \
			or int(grass.get_meta("batches", -1)) != IMPORTED_GRASS_IDS.size():
		_fail("imported NearGrass must retain one batch for each source asset")
		return {}

	var batch_counts: Dictionary = {}
	var source_triangles: int = 0
	var textured_surfaces: int = 0
	var lit_surfaces: int = 0
	var matched_material_surfaces: int = 0
	var total_clumps: int = 0
	var max_radius: float = 0.0
	var min_radius: float = INF
	var shadow_nodes: Array[String] = []
	for child: Node in chunks:
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance == null or instance.multimesh == null:
			_fail("imported NearGrass has a batch without a MultiMesh: " + str(child.name))
			return {}
		var child_name: String = str(child.name)
		var part_marker: int = child_name.find("_Part_")
		if part_marker <= 0 or child_name.substr(part_marker + 6) != "00":
			_fail("imported NearGrass must retain one named source part per batch: " + child_name)
			return {}
		var asset_id: String = child_name.substr(0, part_marker)
		if not expected_counts.has(asset_id) or batch_counts.has(asset_id):
			_fail("imported NearGrass has an unknown or duplicate source batch: " + child_name)
			return {}
		var part_index: int = child_name.substr(part_marker + 6).to_int()
		var source_parts: Array[Dictionary] = ImportedVegetation.get_parts(asset_id)
		if part_index < 0 or part_index >= source_parts.size():
			_fail("imported NearGrass batch does not resolve to its source mesh: " + child_name)
			return {}
		var expected_count: int = int(expected_counts[asset_id])
		if instance.multimesh.instance_count != expected_count:
			_fail("imported grass %s has %d clumps; expected %d" % [asset_id, instance.multimesh.instance_count, expected_count])
			return {}
		batch_counts[asset_id] = instance.multimesh.instance_count
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_nodes.append(child_name)
		var mesh: Mesh = instance.multimesh.mesh
		var source_mesh: Mesh = source_parts[part_index].get("mesh")
		if mesh == null or source_mesh == null or mesh.get_surface_count() <= 0 \
				or mesh.get_surface_count() != source_mesh.get_surface_count():
			_fail("imported grass batch has no source mesh surfaces: " + child_name)
			return {}
		var triangles_per_clump: int = 0
		for surface_index: int in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				_fail("imported grass source surfaces must remain triangle meshes")
				return {}
			var source_material: StandardMaterial3D = source_mesh.surface_get_material(surface_index) as StandardMaterial3D
			var material: Material = mesh.surface_get_material(surface_index)
			if source_material == null or source_material.albedo_texture == null:
				_fail("imported grass source surface must retain its textured StandardMaterial3D")
				return {}
			if source_material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
					or source_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or source_material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY \
					or source_material.alpha_antialiasing_mode != BaseMaterial3D.ALPHA_ANTIALIASING_OFF \
					or source_material.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY \
					or source_material.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX \
					or source_material.cull_mode != BaseMaterial3D.CULL_DISABLED:
				_fail("imported grass source must remain opaque, double-sided and per-pixel lit")
				return {}
			if qualified_wind:
				var wind_material: ShaderMaterial = material as ShaderMaterial
				if wind_material == null or wind_material.shader != qualified_shader \
						or not _qualified_material_matches_source(wind_material, source_material):
					_fail("qualified grass material must match source albedo, UV, vertex-color, roughness and specular parameters: " + asset_id)
					return {}
			else:
				if material != source_material:
					_fail("static imported baseline must retain its exact StandardMaterial3D source material: " + asset_id)
					return {}
			matched_material_surfaces += 1
			textured_surfaces += 1
			lit_surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var source_arrays: Array = source_mesh.surface_get_arrays(surface_index)
			if not _same_surface_geometry(arrays, source_arrays):
				_fail("imported grass source mesh geometry arrays were changed: " + asset_id)
				return {}
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_indices: int = indices.size() if not indices.is_empty() else vertices.size()
			if triangle_indices <= 0 or triangle_indices % 3 != 0:
				_fail("imported grass source surface has malformed triangle arrays")
				return {}
			triangles_per_clump += triangle_indices / 3
		source_triangles += triangles_per_clump * instance.multimesh.instance_count
		for index: int in instance.multimesh.instance_count:
			var point: Vector3 = instance.global_transform * instance.multimesh.get_instance_transform(index).origin
			var east: float = point.x
			var north: float = -point.z
			var radius: float = Vector2(north - pilot_n, east - pilot_e).length()
			max_radius = maxf(max_radius, radius)
			min_radius = minf(min_radius, radius)
			if radius > 30.001:
				_fail("imported grass clump at %.3f m exceeds the 30 m pilot radius" % radius)
				return {}
			var inside_runway: bool = absf(north - float(runway.center_north)) <= float(runway.width_north_south) * 0.5 \
				and absf(east - float(runway.center_east)) <= float(runway.length_east_west) * 0.5
			if inside_runway:
				_fail("imported grass clump lies on the runway at north=%.3f east=%.3f" % [north, east])
				return {}
			total_clumps += 1

	var reported_triangles: int = int(grass.get_meta("source_triangles", -1))
	if batch_counts.size() != IMPORTED_GRASS_IDS.size() or total_clumps != IMPORTED_GRASS_TOTAL \
			or int(grass.get_meta("clumps", -1)) != total_clumps:
		_fail("imported NearGrass clump inventory does not match the selected 150-clump profile")
		return {}
	var triangle_profile_matches: bool = false
	if qualified_wind:
		triangle_profile_matches = source_triangles == ENHANCED_IMPORTED_GRASS_TRIANGLES
	else:
		triangle_profile_matches = source_triangles > 0 and source_triangles <= IMPORTED_GRASS_TRIANGLE_BUDGET
	if source_triangles != reported_triangles or not triangle_profile_matches:
		_fail("imported grass triangle readback disagrees with its metadata or selected material profile budget")
		return {}
	if not shadow_nodes.is_empty():
		_fail("imported NearGrass must not cast shadows: " + str(shadow_nodes))
		return {}
	return {
		"present": true,
		"implementation": "imported_source_meshes",
		"node_count": 1,
		"multimesh_chunks": chunks.size(),
		"source_ids": source_ids,
		"source_batches": batch_counts,
		"clumps": total_clumps,
		"source_triangles": source_triangles,
		"source_geometry_preserved": true,
		"source_material_parameters_matched": matched_material_surfaces == textured_surfaces,
		"textured_surfaces": textured_surfaces,
		"per_pixel_lit_surfaces": lit_surfaces,
		"material_mode": material_mode,
		"material_shader_path": IMPORTED_GRASS_SHADER_PATH if qualified_wind else "",
		"material_shader_sha256": shader_sha256,
		"material_contract": "qualified imported grass shader; source albedo, UV, vertex-color, roughness, metallic and specular parameters matched" \
			if qualified_wind else "static baseline: exact textured per-pixel-lit StandardMaterial3D source surfaces",
		"pilot_radius_m": 30.0,
		"observed_radius_m": {"min": min_radius, "max": max_radius},
		"runway_clumps": 0,
		"casts_shadows": false,
		"placement_path": GRASS_DATA_PATH,
		"wind_animation": "qualified imported shader; ShaderClock wind probes are captured" \
			if qualified_wind else "static baseline source materials; no imported-grass wind adapter",
		"wind_probe_cases": qualified_wind,
	}


func _qualified_grass_shader_is_opaque_and_lit(shader: Shader) -> bool:
	var source: String = shader.code
	var alpha_match: RegExMatch = RegEx.create_from_string("\\bALPHA\\b").search(source)
	return source.contains("render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;") \
		and source.find("vertex_lighting") < 0 and source.find("unshaded") < 0 and alpha_match == null


func _qualified_material_matches_source(material: ShaderMaterial, source: StandardMaterial3D) -> bool:
	var texture_value: Variant = material.get_shader_parameter("albedo_texture")
	var color_value: Variant = material.get_shader_parameter("albedo_color")
	var uv_scale_value: Variant = material.get_shader_parameter("uv1_scale")
	var uv_offset_value: Variant = material.get_shader_parameter("uv1_offset")
	var vertex_color_value: Variant = material.get_shader_parameter("use_vertex_color")
	var roughness_value: Variant = material.get_shader_parameter("roughness")
	var metallic_value: Variant = material.get_shader_parameter("metallic")
	var specular_value: Variant = material.get_shader_parameter("specular")
	if texture_value != source.albedo_texture or color_value != source.albedo_color:
		return false
	if uv_scale_value != Vector2(source.uv1_scale.x, source.uv1_scale.y) \
			or uv_offset_value != Vector2(source.uv1_offset.x, source.uv1_offset.y):
		return false
	if typeof(vertex_color_value) != TYPE_BOOL or bool(vertex_color_value) != source.vertex_color_use_as_albedo:
		return false
	if source.vertex_color_use_as_albedo and source.vertex_color_is_srgb:
		return false
	return typeof(roughness_value) == TYPE_FLOAT and is_equal_approx(float(roughness_value), source.roughness) \
		and typeof(metallic_value) == TYPE_FLOAT and is_equal_approx(float(metallic_value), source.metallic) \
		and typeof(specular_value) == TYPE_FLOAT and is_equal_approx(float(specular_value), source.metallic_specular)


func _same_surface_geometry(arrays: Array, source_arrays: Array) -> bool:
	if arrays.size() != source_arrays.size():
		return false
	for array_index: int in arrays.size():
		if arrays[array_index] != source_arrays[array_index]:
			return false
	return true


func _inspect_flowers(field_node: Node3D) -> Dictionary:
	var scenery: Node = field_node.get_node_or_null("Scenery")
	var habitats: Node = scenery.get_node_or_null("BotanicalHabitats") if scenery != null else null
	if habitats == null:
		_fail("scenery-on capture is missing the production BotanicalHabitats node")
		return {}
	var placement_value: Variant = habitats.get_meta("plants", null)
	if not placement_value is Array:
		_fail("BotanicalHabitats must expose its current downloaded placement records")
		return {}
	var asset_counts: Dictionary = {}
	for asset_id: String in IMPORTED_FLOWER_IDS:
		asset_counts[asset_id] = 0
	for placement_value_item: Variant in placement_value:
		if not placement_value_item is Dictionary:
			_fail("BotanicalHabitats contains a malformed placement record")
			return {}
		var asset_id: String = str(placement_value_item.get("asset_id", ""))
		if asset_counts.has(asset_id):
			asset_counts[asset_id] = int(asset_counts[asset_id]) + 1
	var names: Array[String] = []
	var source_ids: Array[String] = []
	for child: Node in habitats.get_children():
		if not child is MultiMeshInstance3D:
			_fail("BotanicalHabitats must keep imported plants in MultiMesh batches")
			return {}
		var child_name: String = str(child.name)
		var part_marker: int = child_name.find("_Part_")
		if part_marker <= 0:
			_fail("BotanicalHabitats has a batch without a source asset identity: " + child_name)
			return {}
		var asset_id: String = child_name.substr(0, part_marker)
		if asset_counts.has(asset_id):
			names.append(child_name)
			if not source_ids.has(asset_id):
				source_ids.append(asset_id)
	var expected_ids: Array[String] = IMPORTED_FLOWER_IDS.duplicate()
	expected_ids.sort()
	source_ids.sort()
	var total: int = 0
	for asset_id: String in IMPORTED_FLOWER_IDS:
		if int(asset_counts[asset_id]) <= 0:
			_fail("BotanicalHabitats is missing downloaded flower placements for " + asset_id)
			return {}
		total += int(asset_counts[asset_id])
	if source_ids != expected_ids or total <= 0:
		_fail("BotanicalHabitats source flower IDs differ from the accepted downloaded set")
		return {}
	var unique: Dictionary = {}
	for name: String in names:
		unique[name] = true
	if unique.size() != names.size():
		_fail("duplicate downloaded flower MultiMesh node names detected")
	return {"count": total, "asset_counts": asset_counts, "source_ids": source_ids,
		"names": names, "unique_names": unique.size() == names.size()}


func _validate_scenery_contract(scenery_on: bool) -> bool:
	var found_grass_nodes: int = 0
	for child: Node in _field_node.find_children("*", "Node3D", true, false):
		if child.name == "NearGrass":
			found_grass_nodes += 1
	if _mode != "baseline" and found_grass_nodes != 1:
		_fail("expected exactly one Field/NearGrass node, found %d" % found_grass_nodes)
		return false
	if scenery_on:
		if _field_node.get_node_or_null("Scenery") == null:
			_fail("--scenery=on did not attach the production Scenery child")
			return false
		if not bool(_flower_report.get("unique_names", false)):
			_fail("downloaded botanical flower batches are missing or duplicated")
			return false
	else:
		if _field_node.get_node_or_null("Scenery") != null:
			_fail("scenery-off capture unexpectedly contains a Scenery child")
	return true


func _is_on(key: String) -> bool:
	return ["on", "true", "1", "yes"].has(str(_args.get(key, "off")).to_lower())


func _fail(message: String) -> void:
	printerr("L11a GRASS CAPTURE ERROR: " + message)
	quit(1)
