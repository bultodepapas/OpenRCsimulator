## L15b fixed production-field wind captures and an exact-include geometry readback.
## Run through check_wind.py with a real Compatibility renderer.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const TreeLine := preload("res://render/treeline.gd")
const TreeAssets := preload("res://render/tree_assets.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const FORMAT: String = "openrc-l15b-wind-capture v1"
const WIDTH: int = 1280
const HEIGHT: int = 720
const WIDE_FOV_DEG: float = 50.0
const ZOOM_FOV_DEG: float = 10.0
const FAR_M: float = 21000.0
const SETTLE_FRAMES: int = 3
const TREE_SHADER_PATH: String = "res://render/treeline.gdshader"
const WIND_INCLUDE_PATH: String = "res://render/tree_wind.gdshaderinc"
const PROBE_CELL_PX: int = 4
const ZERO_WIND: Vector3 = Vector3.ZERO
const EAST_WIND: Vector3 = Vector3(10.0, 0.0, 0.0)
const WEST_WIND: Vector3 = Vector3(-10.0, 0.0, 0.0)
const NORTH_WIND: Vector3 = Vector3(0.0, 0.0, -10.0)
const SOUTH_WIND: Vector3 = Vector3(0.0, 0.0, 10.0)
const PROBE_SHADER: String = """
shader_type canvas_item;
#include "res://render/tree_wind.gdshaderinc"

uniform vec3 probe_point = vec3(0.0);
uniform vec2 probe_wind = vec2(0.0);
uniform float probe_height = 12.0;
uniform int probe_hash = 0;
uniform float probe_clock = 0.0;
uniform float probe_reference_clock = -1.0;
uniform float probe_encoding_range_m = 0.8;

void fragment() {
	vec3 bent = tree_bend(probe_point, probe_wind, probe_height, uint(probe_hash), probe_clock);
	vec3 displacement = bent - probe_point;
	if (probe_reference_clock >= 0.0) {
		vec3 reference = tree_bend(probe_point, probe_wind, probe_height, uint(probe_hash), probe_reference_clock);
		displacement = bent - reference;
	}
	COLOR = vec4(clamp(displacement / probe_encoding_range_m + vec3(0.5), vec3(0.0), vec3(1.0)), 1.0);
}
"""

var _args: Dictionary = {}
var _out_dir: String = ""
var _mode: String = "candidate"
var _smoke: bool = false
var _field_data: Dictionary = {}
var _world: Node3D
var _field_node: Node3D
var _tree_node: Node3D
var _near_grass: Node3D
var _camera: Camera3D
var _environment: Environment
var _tree_materials: Array[ShaderMaterial] = []
var _views: Array[Dictionary] = []
var _cases: Array[Dictionary] = []
var _zoom_targets: Array[Dictionary] = []
var _probe_report: Dictionary = {}


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
	if not ["candidate", "baseline"].has(_mode):
		_fail("--mode must be candidate or baseline")
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output: DirAccess = DirAccess.open(_out_dir)
	if output == null or not output.get_files().is_empty() or not output.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return
	if root.get_viewport().size != Vector2i(WIDTH, HEIGHT):
		_fail("capture viewport must be %d×%d; received %s" % [WIDTH, HEIGHT, root.get_viewport().size])
		return

	OS.set_environment("OPENRC_SCENERY", "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(0.0, ZERO_WIND)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default field failed validation: " + str(loaded.get("errors", [])))
		return
	_field_data = loaded.get("field", {})
	if not _build_world():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	if not _inspect_field():
		_world.queue_free()
		return
	_views = _make_views()
	if _smoke:
		_views = [_views[1]] # Zoomed north-facing production view for a short visible-wind smoke.

	if _mode == "candidate":
		_probe_report = await _run_geometry_probe()
		if _probe_report.is_empty():
			_world.queue_free()
			return
		if not await _capture_backgrounds():
			_world.queue_free()
			return
		if not await _capture_candidate_cases():
			_world.queue_free()
			return
		if not await _capture_time_strip():
			_world.queue_free()
			return
	else:
		if not await _capture_baseline_cases():
			_world.queue_free()
			return

	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"smoke": _smoke,
		"field": FieldLoader.DEFAULT_PATH,
		"field_id": str(_field_data.get("id", "")),
		"viewport": {"width": WIDTH, "height": HEIGHT},
		"renderer": RenderingServer.get_video_adapter_name(),
		"renderer_api": RenderingServer.get_video_adapter_api_version(),
		"godot": Engine.get_version_info().string,
		"scenery_on": false,
		"near_grass_visible": false,
		"cloud_clock_s": 0.0,
		"tree_wind_include_sha256": FileAccess.get_sha256(WIND_INCLUDE_PATH) if _mode == "candidate" else "",
		"tree": _tree_report(),
		"views": _views,
		"zoom_targets": _zoom_targets,
		"geometry_probe": _probe_report,
		"cases": _cases,
	}
	var manifest_file: FileAccess = FileAccess.open(_out_dir.path_join("capture-manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("could not write capture manifest")
		_world.queue_free()
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
	manifest_file.close()
	print("L15b WIND CAPTURE ", _mode, " ", _cases.size(), " images -> ", _out_dir)
	_world.queue_free()
	quit(0)


func _build_world() -> bool:
	_world = Node3D.new()
	_world.name = "TreeWindCaptureWorld"
	root.add_child(_world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	_environment = Atmosphere.environment()
	environment_node.environment = _environment
	_world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field_data)
	_world.add_child(_field_node)
	Atmosphere.create_sun(_world)
	_camera = Camera3D.new()
	_camera.name = "TreeWindCaptureCamera"
	_camera.near = 0.1
	_camera.far = FAR_M
	_world.add_child(_camera)
	_camera.current = true
	_near_grass = _field_node.get_node_or_null("NearGrass") as Node3D
	if _near_grass != null:
		_near_grass.visible = false
	_tree_node = _field_node.get_node_or_null("treeline") as Node3D
	return true


func _inspect_field() -> bool:
	if _tree_node == null:
		_fail("production Field is missing its treeline child")
		return false
	if _near_grass != null and _near_grass.visible:
		_fail("NearGrass must be hidden for the tree-only wind capture")
		return false
	var chunks: Array[Node] = _tree_node.find_children("*", "MultiMeshInstance3D", true, false)
	if chunks.size() != 8:
		_fail("production treeline must retain eight azimuth-sector MultiMeshes; found %d" % chunks.size())
		return false
	_tree_materials.clear()
	var seen: Dictionary = {}
	var instance_count: int = 0
	for child: Node in chunks:
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance.multimesh == null or instance.multimesh.mesh == null:
			_fail("treeline sector has no MultiMesh or tree-card mesh: " + str(child.name))
			return false
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("production tree sector must not cast shadows: " + str(child.name))
			return false
		instance_count += instance.multimesh.instance_count
		for surface_index: int in instance.multimesh.mesh.get_surface_count():
			var material: ShaderMaterial = instance.multimesh.mesh.surface_get_material(surface_index) as ShaderMaterial
			if material == null or material.shader == null or material.shader.resource_path != TREE_SHADER_PATH:
				_fail("tree-card mesh must use the production treeline ShaderMaterial")
				return false
			var resource_id: int = material.get_instance_id()
			if not seen.has(resource_id):
				seen[resource_id] = true
				_tree_materials.append(material)
	if instance_count <= 0:
		_fail("production Field has no tree instances")
		return false
	if _mode == "candidate":
		if not FileAccess.file_exists(WIND_INCLUDE_PATH):
			_fail("candidate app is missing the production tree-wind include")
			return false
		if _tree_materials.size() != 1:
			_fail("expected one shared production tree material; found %d" % _tree_materials.size())
			return false
		var tree_shader_text: String = FileAccess.get_file_as_string(TREE_SHADER_PATH)
		if not tree_shader_text.contains("uniform bool wind_enabled = true") \
				or not tree_shader_text.contains("tree_bend(VERTEX") \
				or not tree_shader_text.contains("tree_bend(crown"):
			_fail("production treeline shader does not expose the expected L15b wind path")
			return false
	return true


func _tree_report() -> Dictionary:
	var count: int = 0
	var shadow_nodes: Array[String] = []
	var chunks: Array[Dictionary] = []
	for child: Node in _tree_node.find_children("*", "MultiMeshInstance3D", true, false):
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		count += instance.multimesh.instance_count
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_nodes.append(str(child.name))
		chunks.append({"name": str(child.name), "instances": instance.multimesh.instance_count})
	return {
		"visible": true,
		"chunks": chunks,
		"chunk_count": chunks.size(),
		"tree_instances": count,
		"casts_shadows": not shadow_nodes.is_empty(),
		"shadow_nodes": shadow_nodes,
		"unique_materials": _tree_materials.size(),
		"near_grass_hidden": _near_grass == null or not _near_grass.visible,
	}


func _make_views() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pilot: Dictionary = _field_data.get("pilot", {})
	var pilot_n: float = float(pilot.get("north", 0.0))
	var pilot_e: float = float(pilot.get("east", 0.0))
	var pilot_down: float = float(pilot.get("down", 0.0))
	var eye_height: float = float(pilot.get("eye_height", 1.7))
	_zoom_targets.clear()
	for azimuth: float in [0.0, 90.0, 180.0, 270.0]:
		result.append({
			"id": "wide-az%03d" % int(azimuth),
			"kind": "pilot-wide",
			"nominal_azimuth_deg": azimuth,
			"azimuth_deg": azimuth,
			"elevation_deg": 0.0,
			"fov_deg": WIDE_FOV_DEG,
			"camera_north_m": pilot_n,
			"camera_east_m": pilot_e,
			"camera_height_m": eye_height,
			"target_north_m": pilot_n + cos(deg_to_rad(azimuth)) * 1000.0,
			"target_east_m": pilot_e + sin(deg_to_rad(azimuth)) * 1000.0,
			"target_height_m": eye_height,
		})
		var target: Dictionary = _find_zoom_target(azimuth)
		if target.is_empty():
			_fail("could not find a production tree within 350–450 m on azimuth %d" % int(azimuth))
			return []
		var tree_identity: Dictionary = TreeLine.identity(float(target["north"]), float(target["east"]))
		var species: int = int(tree_identity["species"])
		var crown_fractions: Array[float] = [0.71, 0.67, 0.63]
		var crown_height: float = float(tree_identity["height"]) * crown_fractions[species]
		var target_record: Dictionary = {
			"nominal_azimuth_deg": azimuth,
			"north_m": float(target["north"]),
			"east_m": float(target["east"]),
			"radius_m": float(target["radius"]),
			"cross_track_m": float(target["cross_track"]),
			"tree_height_m": float(tree_identity["height"]),
			"tree_hash": _tree_hash(float(target["north"]), float(target["east"]))
		}
		_zoom_targets.append(target_record)
		var camera_azimuth: float = rad_to_deg(atan2(float(target["east"]) - pilot_e, float(target["north"]) - pilot_n))
		result.append({
			"id": "zoom-az%03d" % int(azimuth),
			"kind": "production-tree-zoom",
			"nominal_azimuth_deg": azimuth,
			"azimuth_deg": fposmod(camera_azimuth, 360.0),
			"elevation_deg": rad_to_deg(atan2(crown_height - eye_height, float(target["radius"]))),
			"fov_deg": ZOOM_FOV_DEG,
			"camera_north_m": pilot_n,
			"camera_east_m": pilot_e,
			"camera_height_m": eye_height,
			"target_north_m": float(target["north"]),
			"target_east_m": float(target["east"]),
			"target_height_m": crown_height,
			"tree_height_m": float(tree_identity["height"]),
		})
	return result


func _find_zoom_target(azimuth_deg: float) -> Dictionary:
	var tree_object: Dictionary = {}
	for object_data: Dictionary in _field_data.get("objects", []):
		if str(object_data.get("id", "")) == "treeline":
			tree_object = object_data
	if tree_object.is_empty():
		return {}
	var azimuth: float = deg_to_rad(azimuth_deg)
	var direction_n: float = cos(azimuth)
	var direction_e: float = sin(azimuth)
	var best: Dictionary = {}
	var best_score: float = INF
	for point: Array in tree_object.get("positions", []):
		var north: float = float(point[0])
		var east: float = float(point[1])
		var radius: float = Vector2(north, east).length()
		var along: float = north * direction_n + east * direction_e
		if radius < 350.0 or radius > 450.0 or along <= 0.0:
			continue
		var cross_track: float = absf(north * direction_e - east * direction_n)
		var score: float = absf(radius - 400.0) + cross_track * 2.0
		if score < best_score:
			best_score = score
			best = {"north": north, "east": east, "radius": radius, "cross_track": cross_track}
	return best


func _capture_backgrounds() -> bool:
	_tree_node.visible = false
	for view: Dictionary in _views:
		if _smoke and str(view["id"]) != "zoom-az000":
			continue
		var captured: Dictionary = await _capture("background-%s" % str(view["id"]), "background", view,
			ZERO_WIND, 0.0, true, false)
		if captured.is_empty():
			return false
		_cases.append(captured)
	_tree_node.visible = true
	return true


func _capture_baseline_cases() -> bool:
	for view: Dictionary in _views:
		var captured: Dictionary = await _capture("calm-t0--%s" % str(view["id"]), "calm-t0", view,
			ZERO_WIND, 0.0, true, true)
		if captured.is_empty():
			return false
		_cases.append(captured)
	return true


func _capture_candidate_cases() -> bool:
	var conditions: Array[Dictionary] = [
		{"id": "calm-t0", "time": 0.0, "wind": ZERO_WIND, "enabled": true},
		{"id": "calm-t1", "time": 1.0, "wind": ZERO_WIND, "enabled": true},
		{"id": "east-t0", "time": 0.0, "wind": EAST_WIND, "enabled": true},
		{"id": "east-t1", "time": 1.0, "wind": EAST_WIND, "enabled": true},
		{"id": "east-t1024", "time": 1024.0, "wind": EAST_WIND, "enabled": true},
		{"id": "west-t0", "time": 0.0, "wind": WEST_WIND, "enabled": true},
		{"id": "west-t1", "time": 1.0, "wind": WEST_WIND, "enabled": true},
		{"id": "west-t1024", "time": 1024.0, "wind": WEST_WIND, "enabled": true},
		{"id": "east-same-input-t1", "time": 1.0, "wind": EAST_WIND, "enabled": true},
		{"id": "east-replay-t0", "time": 0.0, "wind": EAST_WIND, "enabled": true},
		{"id": "east-disabled-t1", "time": 1.0, "wind": EAST_WIND, "enabled": false},
	]
	if _smoke:
		conditions = [conditions[0], conditions[2], conditions[3], conditions[4], conditions[10]]
	for condition: Dictionary in conditions:
		_set_tree_wind_enabled(bool(condition["enabled"]))
		for view: Dictionary in _views:
			var label: String = "%s--%s" % [str(condition["id"]), str(view["id"])]
			var captured: Dictionary = await _capture(label, str(condition["id"]), view,
				condition["wind"], float(condition["time"]), bool(condition["enabled"]), true)
			if captured.is_empty():
				return false
			_cases.append(captured)
		# Captures are render-only. Leave the clock fixed at the requested sample and let the next explicit condition
		# choose its own time; no physics or wall-clock accumulator participates.
	return true


func _capture_time_strip() -> bool:
	if _smoke:
		return true
	var view: Dictionary = {}
	for candidate: Dictionary in _views:
		if str(candidate["id"]) == "zoom-az000":
			view = candidate
	if view.is_empty():
		_fail("fixed 10° north zoom is missing for the L15b time strip")
		return false
	_set_tree_wind_enabled(true)
	for frame_index: int in 8:
		var sim_time: float = float(frame_index) * 0.25
		var label: String = "time-strip-east-%02d" % frame_index
		var captured: Dictionary = await _capture(label, "time-strip-east", view, EAST_WIND, sim_time, true, true)
		if captured.is_empty():
			return false
		captured["time_strip_frame"] = frame_index
		_cases.append(captured)
	return _write_time_strip_html()


func _write_time_strip_html() -> bool:
	var html: String = """<!doctype html>
<meta charset="utf-8">
<title>L15b tree wind time strip</title>
<style>
body{margin:0;background:#17202a;color:#eaf2f8;font:16px system-ui,sans-serif;display:grid;place-items:center;min-height:100vh}
main{width:min(96vw,1280px)}img{width:100%;display:block;image-rendering:auto}p{margin:.6rem 0;color:#c9d6df}
</style>
<main><img id="frame" alt="Fixed 10 degree view of the production tree at approximately 400 metres"><p id="caption"></p><button id="replay">Replay time strip</button></main>
<script>
const frames = ["time-strip-east-00","time-strip-east-01","time-strip-east-02","time-strip-east-03","time-strip-east-04","time-strip-east-05","time-strip-east-06","time-strip-east-07"];
let index = 0;
let timer = null;
function show(){document.getElementById("frame").src = frames[index] + ".png";document.getElementById("caption").textContent = "East wind 10 m/s · t = " + (index * 0.25).toFixed(2) + " s";index += 1;if(index < frames.length){timer = setTimeout(show, 250);}}
document.getElementById("replay").addEventListener("click", function(){if(timer !== null){clearTimeout(timer);}index = 0;show();});
show();
</script>
"""
	var file: FileAccess = FileAccess.open(_out_dir.path_join("time-strip.html"), FileAccess.WRITE)
	if file == null:
		_fail("could not write the L15b time-strip HTML")
		return false
	file.store_string(html)
	file.close()
	return true


func _capture(case_id: String, condition: String, view: Dictionary, wind: Vector3, sim_time: float,
		wind_enabled: bool, trees_visible: bool) -> Dictionary:
	ShaderClock.update(sim_time, wind)
	Atmosphere.update_clouds(_environment, 0.0)
	if _mode == "candidate":
		_set_tree_wind_enabled(wind_enabled)
	_tree_node.visible = trees_visible
	_set_camera(view)
	for _frame: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
		_fail("root viewport returned an empty or incorrectly sized image for " + case_id)
		return {}
	var image_name: String = "%s.png" % case_id
	var image_path: String = _out_dir.path_join(image_name)
	if image.save_png(image_path) != OK:
		_fail("failed to save capture " + image_path)
		return {}
	var result: Dictionary = {
		"id": case_id,
		"image": image_name,
		"condition": condition,
		"view_id": str(view["id"]),
		"view_kind": str(view["kind"]),
		"tree_visible": trees_visible,
		"wind_enabled": wind_enabled,
		"wind_vec": [wind.x, wind.y, wind.z],
		"wind_speed_mps": wind.length(),
		"sim_time_s": sim_time,
		"sim_clock": ShaderClock.last_clock,
		"camera_fov_deg": float(view["fov_deg"]),
		"camera_north_m": float(view["camera_north_m"]),
		"camera_east_m": float(view["camera_east_m"]),
		"camera_height_m": float(view["camera_height_m"]),
		"target_north_m": float(view["target_north_m"]),
		"target_east_m": float(view["target_east_m"]),
		"target_height_m": float(view["target_height_m"]),
		"azimuth_deg": float(view["azimuth_deg"]),
		"elevation_deg": float(view["elevation_deg"]),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"shadow_draw_calls": int(RenderingServer.viewport_get_render_info(root.get_viewport().get_viewport_rid(),
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)),
	}
	result["sha256"] = FileAccess.get_sha256(image_path)
	return result


func _set_camera(view: Dictionary) -> void:
	_camera.fov = float(view["fov_deg"])
	var camera_position: Vector3 = Frames.ned_to_render([
		float(view["camera_north_m"]), float(view["camera_east_m"]), float(_field_data.pilot.down) - float(view["camera_height_m"]),
	])
	var target_position: Vector3 = Frames.ned_to_render([
		float(view["target_north_m"]), float(view["target_east_m"]), -float(view["target_height_m"]),
	])
	_camera.position = camera_position
	_camera.look_at(target_position, Vector3.UP)


func _set_tree_wind_enabled(enabled: bool) -> void:
	for material: ShaderMaterial in _tree_materials:
		material.set_shader_parameter("wind_enabled", enabled)


func _run_geometry_probe() -> Dictionary:
	var samples: Array[Dictionary] = _geometry_samples()
	if samples.is_empty():
		_fail("could not derive geometry samples from the production tree card mesh")
		return {}
	var probe_view: SubViewport = SubViewport.new()
	probe_view.name = "TreeWindGeometryProbe"
	probe_view.size = Vector2i(samples.size() * PROBE_CELL_PX, PROBE_CELL_PX)
	probe_view.transparent_bg = false
	probe_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	probe_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(probe_view)
	var canvas: Control = Control.new()
	canvas.size = Vector2(probe_view.size)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	probe_view.add_child(canvas)
	var shader: Shader = Shader.new()
	shader.code = PROBE_SHADER
	for index: int in samples.size():
		var sample: Dictionary = samples[index]
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("probe_point", sample["point"])
		material.set_shader_parameter("probe_wind", sample["wind"])
		material.set_shader_parameter("probe_height", float(sample["height"]))
		material.set_shader_parameter("probe_hash", int(sample["hash"]))
		material.set_shader_parameter("probe_clock", float(sample["clock"]))
		material.set_shader_parameter("probe_reference_clock", float(sample.get("reference_clock", -1.0)))
		material.set_shader_parameter("probe_encoding_range_m", float(sample.get("encoding_range_m", 0.8)))
		var rect: ColorRect = ColorRect.new()
		rect.name = "Sample%d" % index
		rect.position = Vector2(float(index * PROBE_CELL_PX), 0.0)
		rect.size = Vector2(PROBE_CELL_PX, PROBE_CELL_PX)
		rect.color = Color.WHITE
		rect.material = material
		canvas.add_child(rect)
	for _frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = probe_view.get_texture().get_image()
	if picture == null or picture.is_empty() or picture.get_width() != samples.size() * PROBE_CELL_PX:
		probe_view.queue_free()
		_fail("GPU geometry probe returned an empty or malformed texture")
		return {}
	var png_path: String = _out_dir.path_join("geometry-probe.png")
	if picture.save_png(png_path) != OK:
		probe_view.queue_free()
		_fail("could not save the GPU geometry probe image")
		return {}
	for index: int in samples.size():
		var pixel: Color = picture.get_pixel(index * PROBE_CELL_PX + PROBE_CELL_PX / 2, PROBE_CELL_PX / 2)
		samples[index]["rgb8"] = [roundi(pixel.r * 255.0), roundi(pixel.g * 255.0), roundi(pixel.b * 255.0)]
		# Keep precise source values beside the readback so the Python checker can independently evaluate geometry.
		samples[index]["point"] = [float(samples[index]["point"].x), float(samples[index]["point"].y), float(samples[index]["point"].z)]
		samples[index]["wind"] = [float(samples[index]["wind"].x), float(samples[index]["wind"].y)]
	var report: Dictionary = {
		"format": "openrc-l15b-tree-wind-gpu-probe v1",
		"complete": true,
		"shader_include": WIND_INCLUDE_PATH,
		"shader_include_sha256": FileAccess.get_sha256(WIND_INCLUDE_PATH),
		"encoding": {"default_range_m": [-0.4, 0.4], "per_sample_range_m": true,
			"channels": "RGB stores displacement xyz; 0.5 means zero displacement"},
		"production_mesh": _probe_mesh_metadata(),
		"selected_trees": _probe_tree_metadata(),
		"samples": samples,
		"png": "geometry-probe.png",
		"png_sha256": FileAccess.get_sha256(png_path),
	}
	probe_view.queue_free()
	var report_file: FileAccess = FileAccess.open(_out_dir.path_join("geometry-probe.json"), FileAccess.WRITE)
	if report_file == null:
		_fail("could not write GPU geometry probe report")
		return {}
	report_file.store_string(JSON.stringify(report, "\t", true) + "\n")
	report_file.close()
	return report


func _geometry_samples() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tree_identity_samples: Array[Dictionary] = _representative_trees()
	if tree_identity_samples.size() != 3:
		return result
	var root_height: float = float(tree_identity_samples[0]["height"])
	var root_hash: int = int(tree_identity_samples[0]["hash"])
	_add_probe(result, "root-zero-wind", "root", Vector3.ZERO, root_height, root_hash, Vector2.ZERO, 0.0)

	var cardinal_winds: Array[Dictionary] = [
		{"name": "east", "wind": Vector2(10.0, 0.0)},
		{"name": "west", "wind": Vector2(-10.0, 0.0)},
		{"name": "north", "wind": Vector2(0.0, -10.0)},
		{"name": "south", "wind": Vector2(0.0, 10.0)},
	]
	for tree_data: Dictionary in tree_identity_samples:
		for wind_data: Dictionary in cardinal_winds:
			_add_probe(result, "root-%s-%s-t0" % [str(tree_data["band"]), str(wind_data["name"])], "root", Vector3.ZERO,
				float(tree_data["height"]), int(tree_data["hash"]), wind_data["wind"], 0.0)
		_add_probe(result, "root-%s-east-t1" % str(tree_data["band"]), "root", Vector3.ZERO, float(tree_data["height"]),
			int(tree_data["hash"]), Vector2(10.0, 0.0), 1.0)
		var points: Array[Dictionary] = _card_points_for_tree(tree_data)
		for point_data: Dictionary in points:
			for wind_data: Dictionary in cardinal_winds:
				var label: String = "%s-v%d-%s-t0" % [str(tree_data["band"]),
					int(point_data["vertex_index"]), str(wind_data["name"])]
				_add_probe(result, label, "cardinal", point_data["point"], float(tree_data["height"]),
					int(tree_data["hash"]), wind_data["wind"], 0.0, {
						"source": "production card mesh vertex",
						"tree_position_north_m": float(tree_data["north"]),
						"tree_position_east_m": float(tree_data["east"]),
						"species": int(tree_data["species"]),
						"mesh_vertex": int(point_data["vertex_index"]),
						"wind_name": str(wind_data["name"]),
					})
			if point_data["vertex_index"] == 2 or point_data["vertex_index"] == 3:
				_add_probe(result, "wrap-%s-v%d-t1024" % [str(tree_data["band"]), int(point_data["vertex_index"])],
					"clock-wrap", point_data["point"], float(tree_data["height"]), int(tree_data["hash"]),
					Vector2(10.0, 0.0), 1024.0, {
						"requested_time_s": 1024.0,
						"source": "production card mesh vertex",
						"tree_position_north_m": float(tree_data["north"]),
						"tree_position_east_m": float(tree_data["east"]),
						"species": int(tree_data["species"]),
						"mesh_vertex": int(point_data["vertex_index"]),
					})
				_add_probe(result, "prewrap-%s-v%d" % [str(tree_data["band"]), int(point_data["vertex_index"])],
					"clock-prewrap", point_data["point"], float(tree_data["height"]), int(tree_data["hash"]),
					Vector2(10.0, 0.0), 1024.0 - 1.0 / 1024.0, {
						"reference_clock": 0.0,
						"encoding_range_m": 0.002,
						"requested_time_s": 1024.0 - 1.0 / 1024.0,
						"source": "production card mesh vertex",
						"tree_position_north_m": float(tree_data["north"]),
						"tree_position_east_m": float(tree_data["east"]),
						"species": int(tree_data["species"]),
						"mesh_vertex": int(point_data["vertex_index"]),
					})
				_add_probe(result, "wrap-%s-v%d-t0" % [str(tree_data["band"]), int(point_data["vertex_index"])],
					"clock-wrap", point_data["point"], float(tree_data["height"]), int(tree_data["hash"]),
					Vector2(10.0, 0.0), ShaderClock.value(0.0), {
						"requested_time_s": 0.0,
						"source": "production card mesh vertex",
						"tree_position_north_m": float(tree_data["north"]),
						"tree_position_east_m": float(tree_data["east"]),
						"species": int(tree_data["species"]),
						"mesh_vertex": int(point_data["vertex_index"]),
					})

	var middle: Dictionary = tree_identity_samples[1]
	var test_point: Vector3 = Vector3(0.0, float(middle["height"]), 0.0)
	for hash_value: int in [0, 5460, 10920, 16380, 21840, 27300, 32760, 38220, 43680, 49140, 54600, 60060]:
		_add_probe(result, "phase-h%d" % hash_value, "hash-phase", test_point, float(middle["height"]),
			hash_value, Vector2(10.0, 0.0), 0.0)
	_add_probe(result, "time-east-t0", "clock-change", test_point, float(middle["height"]),
		int(middle["hash"]), Vector2(10.0, 0.0), 0.0)
	_add_probe(result, "time-east-t1", "clock-change", test_point, float(middle["height"]),
		int(middle["hash"]), Vector2(10.0, 0.0), 1.0)
	for speed: float in [5.0, 10.0, 20.0]:
		_add_probe(result, "speed-%02d" % int(speed), "speed-scale", test_point,
			float(middle["height"]), int(middle["hash"]), Vector2(speed, 0.0), 0.0,
			{"speed_mps": speed})
	_add_probe(result, "calm-t0", "calm", test_point, float(middle["height"]), int(middle["hash"]), Vector2.ZERO, 0.0)
	_add_probe(result, "calm-t1", "calm", test_point, float(middle["height"]), int(middle["hash"]), Vector2.ZERO, 1.0)
	for wind_data: Dictionary in cardinal_winds:
		_add_probe(result, "direction-%s" % str(wind_data["name"]), "direction", test_point,
			float(middle["height"]), int(middle["hash"]), wind_data["wind"], 0.0)
	return result


func _representative_trees() -> Array[Dictionary]:
	var positions: Array = []
	for object_data: Dictionary in _field_data.get("objects", []):
		if str(object_data.get("id", "")) == "treeline":
			positions = object_data.get("positions", [])
	if positions.is_empty():
		return []
	var targets: Array[float] = [12.0, 18.5, 25.0]
	var bands: Array[String] = ["low", "middle", "high"]
	var result: Array[Dictionary] = []
	var used: Dictionary = {}
	for band_index: int in targets.size():
		var best: Dictionary = {}
		var best_error: float = INF
		for point: Array in positions:
			var north: float = float(point[0])
			var east: float = float(point[1])
			var identity: Dictionary = TreeLine.identity(north, east)
			var height: float = float(identity["height"])
			var error: float = absf(height - targets[band_index])
			var position_key: String = "%0.2f,%0.2f" % [north, east]
			if used.has(position_key) or error >= best_error:
				continue
			best_error = error
			best = {
				"north": north,
				"east": east,
				"height": height,
				"yaw": float(identity["yaw"]),
				"species": int(identity["species"]),
				"hash": _tree_hash(north, east),
				"band": bands[band_index],
			}
		if best.is_empty():
			return []
		used["%0.2f,%0.2f" % [float(best["north"]), float(best["east"])]] = true
		result.append(best)
	return result


func _card_points_for_tree(tree_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sectors: Array[Node] = _tree_node.find_children("*", "MultiMeshInstance3D", true, false)
	if sectors.is_empty():
		return result
	var mesh: Mesh = (sectors[0] as MultiMeshInstance3D).multimesh.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var catalog: Dictionary = TreeAssets.catalog()
	if not bool(catalog.get("ok", false)):
		return result
	var species_sizes: Array[float] = []
	for entry: Dictionary in catalog["catalog"].get("species", []):
		species_sizes.append(float(entry["frame_size_m"]))
	var species: int = int(tree_data["species"])
	var ratio: float = species_sizes[species] / species_sizes[0]
	var spin: Basis = Basis(Vector3.UP, float(tree_data["yaw"]))
	for vertex_index: int in vertices.size():
		if vertex_index >= 12:
			break
		var point: Vector3 = vertices[vertex_index]
		point.x *= ratio
		point.z *= ratio
		point.y = (point.y - 0.5) * ratio + 0.5
		point = spin * point * float(tree_data["height"])
		result.append({"vertex_index": vertex_index, "point": point})
	return result


func _probe_mesh_metadata() -> Dictionary:
	var sectors: Array[Node] = _tree_node.find_children("*", "MultiMeshInstance3D", true, false)
	if sectors.is_empty():
		return {}
	var mesh: Mesh = (sectors[0] as MultiMeshInstance3D).multimesh.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_local_radius: float = 0.0
	for vertex: Vector3 in vertices:
		max_local_radius = maxf(max_local_radius, vertex.length())
	return {
		"source": "production treeline MultiMesh card mesh surface 0",
		"surface_count": mesh.get_surface_count(),
		"vertex_count": vertices.size(),
		"max_unscaled_vertex_radius_m": max_local_radius,
	}


func _probe_tree_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tree_data: Dictionary in _representative_trees():
		result.append({
			"band": tree_data["band"],
			"north_m": tree_data["north"],
			"east_m": tree_data["east"],
			"height_m": tree_data["height"],
			"yaw_rad": tree_data["yaw"],
			"species": tree_data["species"],
			"hash": tree_data["hash"],
		})
	return result


func _add_probe(samples: Array[Dictionary], sample_id: String, purpose: String, point: Vector3, height: float,
		hash_value: int, wind: Vector2, clock: float, extra: Dictionary = {}) -> void:
	var sample: Dictionary = {
		"id": sample_id,
		"purpose": purpose,
		"point": point,
		"height": height,
		"hash": hash_value,
		"wind": wind,
		"clock": clock,
	}
	sample.merge(extra, true)
	samples.append(sample)


func _tree_hash(north: float, east: float) -> int:
	var qn: int = roundi(north * 4.0)
	var qe: int = roundi(east * 4.0)
	var hash_offset: int = 8192 if qn < -2400 or qe < -2400 else 2400
	var hash_north: int = qn + hash_offset
	var hash_east: int = qe + hash_offset
	var h: int = (hash_north * 7381 + hash_east * 19391 + 6113) % 65521
	return (h * 25173 + 13849) % 65521


func _is_on(key: String) -> bool:
	return ["on", "true", "1", "yes"].has(str(_args.get(key, "off")).to_lower())


func _fail(message: String) -> void:
	printerr("L15b WIND CAPTURE ERROR: " + message)
	quit(1)
