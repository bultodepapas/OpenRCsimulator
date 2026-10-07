## Rasterize the production cloud-density include into one small diagnostic atlas.
## Run with Godot --path <app> --script <this file> -- --out=<empty directory>.
extends SceneTree

const FORMAT: String = "openrc-cloud-density-probe v1"
const PANEL_SIZE: int = 256
const SUN_Y_VALUE: float = 0.7071067811865476
const PANEL_IDS: Array[String] = [
	"base",
	"plus-64-x",
	"plus-64-y",
	"negative",
	"negative-plus-64-x",
	"negative-plus-64-y",
	"projection-ground",
	"projection-sky",
	"projection-wrong-sign",
	"drift-before-wrap",
	"drift-after-wrap",
	"zero-coverage",
]
const PROBE_SHADER: String = """
shader_type canvas_item;
#include "res://render/cloud_field.gdshaderinc"

uniform int probe_mode = 0;
uniform vec2 cells_offset = vec2(0.0);
uniform float drift_cells = 0.0;
uniform float coverage = 0.55;
uniform float cluster_strength = 0.65;
uniform uint cloud_seed = 1253u;
const float DECK_M = 1500.0;
const float CLOUD_SCALE = 6.0;
const float SUN_Y = 0.7071067811865476;
const vec2 SUN_XZ = vec2(-0.5, 0.5);

void fragment() {
	vec2 cells = cells_offset + UV * float(CLOUD_FIELD_PERIOD) + vec2(drift_cells, 0.0);
	if (probe_mode >= 1 && probe_mode <= 3) {
		// Pilot-origin projection: a ground point and its corresponding ray both hit the same deck point.
		vec2 ground_xz = (UV - vec2(0.5)) * 3000.0;
		float ground_y = UV.x * 100.0;
		vec2 sun_slope = SUN_XZ / SUN_Y;
		vec2 deck_xz = ground_xz + (DECK_M - ground_y) * sun_slope;
		if (probe_mode == 1) {
			cells = deck_xz * (CLOUD_SCALE / DECK_M);
		} else if (probe_mode == 2) {
			vec2 ray_slope = ground_xz / DECK_M + ((DECK_M - ground_y) / DECK_M) * sun_slope;
			cells = ray_slope * CLOUD_SCALE;
		} else {
			vec2 wrong_deck_xz = ground_xz - (DECK_M - ground_y) * sun_slope;
			cells = wrong_deck_xz * (CLOUD_SCALE / DECK_M);
		}
	}
	float density = cloud_density(cells, cloud_seed, coverage, cluster_strength);
	float in_bounds = (density >= 0.0 && density <= 1.0) ? 1.0 : 0.0;
	// Green is an explicit finite/range sentinel; red/blue carry the quantized density sample.
	COLOR = vec4(density, in_bounds, density, 1.0);
}
"""

var _out_dir: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts[0] == "out" and parts.size() == 2:
			_out_dir = parts[1]
	if _out_dir.is_empty():
		_fail("--out=<empty directory> is required")
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output: DirAccess = DirAccess.open(_out_dir)
	if output == null or not output.get_files().is_empty() or not output.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return
	if not FileAccess.file_exists("res://render/cloud_field.gdshaderinc"):
		_fail("the candidate app is missing res://render/cloud_field.gdshaderinc")
		return

	var panel_width: int = PANEL_IDS.size() * PANEL_SIZE
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "CloudDensityProbeViewport"
	viewport.size = Vector2i(panel_width, PANEL_SIZE)
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas: Control = Control.new()
	canvas.size = Vector2(panel_width, PANEL_SIZE)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(canvas)

	var shader: Shader = Shader.new()
	shader.code = PROBE_SHADER
	var panel_specs: Array[Dictionary] = [
		{"id": "base", "offset": Vector2(0.0, 0.0), "mode": 0},
		{"id": "plus-64-x", "offset": Vector2(64.0, 0.0), "mode": 0},
		{"id": "plus-64-y", "offset": Vector2(0.0, 64.0), "mode": 0},
		{"id": "negative", "offset": Vector2(-64.0, -64.0), "mode": 0},
		{"id": "negative-plus-64-x", "offset": Vector2(0.0, -64.0), "mode": 0},
		{"id": "negative-plus-64-y", "offset": Vector2(-64.0, 0.0), "mode": 0},
		{"id": "projection-ground", "offset": Vector2.ZERO, "mode": 1},
		{"id": "projection-sky", "offset": Vector2.ZERO, "mode": 2},
		{"id": "projection-wrong-sign", "offset": Vector2.ZERO, "mode": 3},
		{"id": "drift-before-wrap", "offset": Vector2(13.75, -8.25), "mode": 0, "drift": 63.999},
		{"id": "drift-after-wrap", "offset": Vector2(13.75, -8.25), "mode": 0, "drift": 0.001},
		{"id": "zero-coverage", "offset": Vector2.ZERO, "mode": 0, "coverage": 0.0},
	]
	for index: int in panel_specs.size():
		var spec: Dictionary = panel_specs[index]
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("probe_mode", int(spec["mode"]))
		material.set_shader_parameter("cells_offset", spec["offset"])
		material.set_shader_parameter("drift_cells", float(spec.get("drift", 0.0)))
		material.set_shader_parameter("coverage", float(spec.get("coverage", 0.55)))
		material.set_shader_parameter("cluster_strength", 0.65)
		material.set_shader_parameter("cloud_seed", 1253)
		var rect: ColorRect = ColorRect.new()
		rect.name = str(spec["id"])
		rect.position = Vector2(float(index * PANEL_SIZE), 0.0)
		rect.size = Vector2(PANEL_SIZE, PANEL_SIZE)
		rect.color = Color.WHITE
		rect.material = material
		canvas.add_child(rect)

	for _frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	var image_path: String = _out_dir.path_join("cloud-probe.png")
	if picture == null or picture.save_png(image_path) != OK:
		viewport.queue_free()
		_fail("could not save rendered atlas: " + image_path)
		return
	var report: Dictionary = {
		"format": FORMAT,
		"complete": true,
		"width": panel_width,
		"height": PANEL_SIZE,
		"panel_size": PANEL_SIZE,
		"panels": PANEL_IDS,
		"density": {"seed": 1253, "coverage": 0.55, "cluster_strength": 0.65, "cloud_scale": 6.0, "deck_m": 1500.0},
		"sun_render_xz": [-0.5, 0.5],
		"sun_render_y": SUN_Y_VALUE,
		"renderer": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"godot": Engine.get_version_info().string,
		"cloud_include_sha256": FileAccess.get_sha256("res://render/cloud_field.gdshaderinc"),
		"png_sha256": FileAccess.get_sha256(image_path),
	}
	var report_file: FileAccess = FileAccess.open(_out_dir.path_join("probe.json"), FileAccess.WRITE)
	if report_file == null:
		viewport.queue_free()
		_fail("could not write probe metadata")
		return
	report_file.store_string(JSON.stringify(report, "\t", true) + "\n")
	report_file.close()
	viewport.queue_free()
	print("Cloud density GPU atlas complete: ", image_path)
	quit(0)


func _fail(message: String) -> void:
	printerr("CLOUD PROBE ERROR: " + message)
	quit(1)
