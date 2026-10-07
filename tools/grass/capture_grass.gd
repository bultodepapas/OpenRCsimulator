## L11a production-field captures for opaque near grass. The camera, environment and field are the production builders;
## only NearGrass visibility and the shader clock inputs vary between matched images.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const FORMAT: String = "openrc-l11a-grass-capture v1"
const WIDTH: int = 1280
const HEIGHT: int = 720
const FOV_DEG: float = 50.0
const FAR_M: float = 21000.0
const SETTLE_FRAMES: int = 3
const GRASS_SHADER_PATH: String = "res://render/near_grass.gdshader"
const GRASS_DATA_PATH: String = "res://data/fields/grass.json"
const WIND: Vector3 = Vector3(5.0, 0.0, 0.0)

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

	if _mode == "candidate" and not _smoke:
		var wind_scenario: Dictionary = _scenarios()[0]
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
				_world.queue_free()
				return
			_cases.append(captured)

	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"smoke": _smoke,
		"field": FieldLoader.DEFAULT_PATH,
		"field_id": str(_field_data.get("id", "")),
		"viewport": {"width": root.get_viewport().size.x, "height": root.get_viewport().size.y},
		"renderer": RenderingServer.get_video_adapter_name(),
		"scenery_on": scenery_on,
		"environment": "Atmosphere.environment() + Atmosphere.create_sun()",
		"clock_policy": "clouds/ground frozen at t=0; ShaderClock drives grass wind probes",
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


func _build_world() -> Dictionary:
	var world: Node3D = Node3D.new()
	world.name = "GrassCaptureWorld"
	root.add_child(world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	_environment = Atmosphere.environment()
	environment_node.environment = _environment
	world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field_data)
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
	if chunks.is_empty() or chunks.size() > 4:
		_fail("NearGrass must have 1–4 MultiMesh children; found %d" % chunks.size())
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


func _inspect_flowers(field_node: Node3D) -> Dictionary:
	var names: Array[String] = []
	for child: Node in field_node.find_children("*", "MultiMeshInstance3D", true, false):
		if str(child.name).begins_with("flowers_"):
			names.append(str(child.name))
	var unique: Dictionary = {}
	for name: String in names:
		unique[name] = true
	if unique.size() != names.size():
		_fail("duplicate SC-16 flower MultiMesh node names detected")
	return {"count": names.size(), "names": names, "unique_names": unique.size() == names.size()}


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
			_fail("SC-16 flower nodes are missing or duplicated")
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
