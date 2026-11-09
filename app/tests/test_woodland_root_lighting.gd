## Native regression for the production woodland-card root lightening.
## Headless runs explicitly skip readback. Supply -- --out=<new absolute JSON> to retain metrics.
extends SceneTree

const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
const SHADER_PATH := "res://scenery/woodland_cards.gdshader"
const SIZE := 128
const CARD_SIZE := 1.6
const CAMERA_SIZE := 2.0
const ERROR := 2.0 / 255.0
const TEXTURES := ["plain_atlas", "impostor_atlas", "fern_atlas", "short_grass_atlas"]
const SPECIES := ["grass_common_tall", "bush_common_flowers", "fern_1", "grass_common_short"]

# Independent source-sampling oracle: no root treatment and no view-selection logic.
# It samples a caller-selected frame and uses the same normal/lighting as the card.
const SOURCE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float frame_number;
void fragment() {
    vec2 size = vec2(textureSize(atlas, 0));
    float frame_width = size.x / 4.0;
    vec2 uv = vec2((frame_number + clamp(UV.x, 0.5 / frame_width, 1.0 - 0.5 / frame_width)) / 4.0,
                   clamp(UV.y, 0.5 / size.y, 1.0 - 0.5 / size.y));
    vec4 sample_color = texture(atlas, uv);
    ALBEDO = sample_color.rgb;
    NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    ALPHA = sample_color.a;
    ALPHA_SCISSOR_THRESHOLD = 0.32;
}
"""

var _viewport: SubViewport
var _camera: Camera3D
var _actual: MultiMeshInstance3D
var _reference: MeshInstance3D
var _reference_material: ShaderMaterial
var _checks := 0
var _pixel_checks := 0
var _failures := 0
var _results: Array[Dictionary] = []
var _out := ""
var _fractions := Vector2.ZERO
var _default_lift := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, metrics: Dictionary = {}, pixel_check: bool = true) -> void:
	_checks += 1
	if pixel_check:
		_pixel_checks += 1
	_results.append({"label": label, "passed": passed, "metrics": metrics})
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, str(metrics)])


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_empty() and (not _out.is_absolute_path() or FileAccess.file_exists(_out)
			or DirAccess.dir_exists_absolute(_out) or not DirAccess.dir_exists_absolute(_out.get_base_dir())):
		printerr("--out must be a new absolute JSON path in an existing directory")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("skip woodland root lighting pixels: the headless renderer draws nothing")
		_finish("skipped")
		return

	var tall := WoodlandEdges._species_manifest(SPECIES[0])
	var short := WoodlandEdges._species_manifest(SPECIES[3])
	_fractions = Vector2(float(tall.source_height_m) / float(tall.frame_world_size_m[0]),
		float(short.source_height_m) / float(short.frame_world_size_m[0]))
	var material := WoodlandEdges._material().duplicate() as ShaderMaterial
	var installed_fraction: Variant = material.get_shader_parameter("grass_height_fractions")
	_check("production grass fractions follow both source manifests",
		installed_fraction is Vector2 and (installed_fraction as Vector2).distance_to(_fractions) < 0.00001,
		{"installed": str(installed_fraction), "expected": str(_fractions)}, false)
	_default_lift = float(RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "root_lift"))
	_check("production root correction is enabled and bounded", _default_lift > 0.0 and _default_lift <= 1.0,
		{strength = _default_lift}, false)
	_setup()
	await _test_real_atlases(material)
	await _test_synthetic_atlas(material)
	_viewport.free()
	await process_frame
	_finish("failed" if _failures > 0 else "passed")


func _setup() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-90, 0, 0)
	sun.light_energy = 0.35
	sun.shadow_enabled = false
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.01
	_camera.far = 10.0
	_viewport.add_child(_camera)
	_camera.current = true
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_SIZE, CARD_SIZE)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = 1
	multi.set_instance_transform(0, Transform3D.IDENTITY)
	multi.set_instance_color(0, Color.WHITE)
	_actual = MultiMeshInstance3D.new()
	_actual.multimesh = multi
	_actual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_actual)
	_reference = MeshInstance3D.new()
	_reference.mesh = quad
	_reference.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reference_material = ShaderMaterial.new()
	var source_shader := Shader.new()
	source_shader.code = SOURCE_SHADER
	_reference_material.shader = source_shader
	_reference.material_override = _reference_material
	_viewport.add_child(_reference)


func _point_camera(frame: int) -> void:
	var angle := float(frame) * PI * 0.5
	_camera.look_at_from_position(Vector3(cos(angle), 0, -sin(angle)) * 3.0, Vector3.ZERO)
	_reference.look_at(_camera.position, Vector3.UP, true)


func _capture(material: ShaderMaterial, species: int, source_reference: bool,
		texture: Texture2D, frame: int) -> Image:
	_actual.visible = not source_reference
	_reference.visible = source_reference
	_actual.material_override = material
	_actual.multimesh.set_instance_custom_data(0, Color(0.0, float(species), 0.0, 1.0))
	_reference_material.set_shader_parameter("atlas", texture)
	_reference_material.set_shader_parameter("frame_number", float(frame))
	_point_camera(frame)
	for _index in 3:
		await process_frame
		RenderingServer.force_draw(false)
	return _viewport.get_texture().get_image()


func _test_real_atlases(material: ShaderMaterial) -> void:
	for species in 4:
		var texture := material.get_shader_parameter(TEXTURES[species]) as Texture2D
		if texture == null:
			_check("%s source atlas exists" % SPECIES[species], false, {}, false)
			continue
		# The original effective default is checked before explicit strengths are installed.
		var default_material := WoodlandEdges._material().duplicate() as ShaderMaterial
		var candidate := await _capture(default_material, species, false, texture, 3)
		material.set_shader_parameter("root_lift", 0.0)
		var baseline := await _capture(material, species, false, texture, 3)
		var source := await _capture(material, species, true, texture, 3)
		var source_comparison := _compare(baseline, source, INF)
		_check("%s zero-strength rendering matches source color and alpha" % SPECIES[species],
			bool(source_comparison.valid) and int(source_comparison.changed) == 0
			and int(source_comparison.alpha_changed) == 0, source_comparison)
		var full_comparison := _compare(baseline, candidate, INF)
		_check("%s root strength preserves silhouette and alpha" % SPECIES[species],
			bool(full_comparison.valid) and int(full_comparison.alpha_changed) == 0, full_comparison)
		if species == 0 or species == 3:
			var fraction := _fractions.x if species == 0 else _fractions.y
			var upper_uv := 0.5 + 0.2 * fraction
			var upper := _compare(baseline, candidate, upper_uv)
			var roots := _root_metrics(baseline, candidate, candidate, fraction, 0.30)
			_check("%s upper 70%% stays unchanged" % SPECIES[species],
				bool(upper.valid) and int(upper.changed) == 0 and int(upper.alpha_changed) == 0, upper)
			_check("%s source roots gain color" % SPECIES[species],
				int(roots.samples) > 0 and int(roots.changed) > 0, roots)
		else:
			_check("%s is unchanged at production root strength" % SPECIES[species],
				int(full_comparison.changed) == 0 and int(full_comparison.alpha_changed) == 0, full_comparison)


func _test_synthetic_atlas(production_material: ShaderMaterial) -> void:
	var texture := _synthetic_texture()
	var material := production_material.duplicate() as ShaderMaterial
	for uniform_name: String in TEXTURES:
		material.set_shader_parameter(uniform_name, texture)
	for frame in 4:
		material.set_shader_parameter("root_lift", 0.0)
		var baseline := await _capture(material, 0, false, texture, frame)
		var source := await _capture(material, 0, true, texture, frame)
		material.set_shader_parameter("root_lift", _default_lift)
		var candidate := await _capture(material, 0, false, texture, frame)
		var source_comparison := _compare(baseline, source, INF)
		var silhouette := _compare(baseline, candidate, INF)
		var hole_alpha := baseline.get_pixel(SIZE / 2, SIZE / 2).a
		var leaf_alpha := baseline.get_pixel(SIZE / 2 - 20, SIZE / 2).a
		_check("synthetic view %d selects its source frame and nonuniform alpha" % frame,
			bool(source_comparison.valid) and int(source_comparison.changed) == 0
			and int(source_comparison.alpha_changed) == 0 and hole_alpha < 0.1 and leaf_alpha > 0.5,
			{"comparison": source_comparison, "hole_alpha": hole_alpha, "leaf_alpha": leaf_alpha})
		_check("synthetic view %d retains alpha at default strength" % frame,
			bool(silhouette.valid) and int(silhouette.alpha_changed) == 0, silhouette)
		if frame == 3:
			material.set_shader_parameter("root_lift", 1.0)
			var full := await _capture(material, 0, false, texture, frame)
			var roots := _root_metrics(baseline, candidate, full, _fractions.x, 0.08)
			var full_silhouette := _compare(baseline, full, INF)
			_check("dark roots gain restrained green color at the default strength",
				int(roots.samples) > 20 and int(roots.changed) > 20
				and float(roots.candidate_mean) > 0.01
				and float(roots.candidate_mean) > float(roots.full_mean) * 0.2
				and float(roots.candidate_mean) < float(roots.full_mean) * 0.9
				and int(roots.darker_channels) == 0 and int(roots.above_full_channels) == 0
				and float(roots.green_mean) > float(roots.red_mean)
				and float(roots.red_mean) > float(roots.blue_mean)
				and int(full_silhouette.alpha_changed) == 0,
				{"root": roots, "full_strength": full_silhouette})


func _synthetic_texture() -> ImageTexture:
	var colors: Array[Color] = [Color(0.18, 0.04, 0.03), Color(0.03, 0.18, 0.04),
		Color(0.04, 0.03, 0.18), Color(0.14, 0.14, 0.02)]
	var image := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	for frame in 4:
		for y in 64:
			for x in 64:
				var color := colors[frame]
				# Clear surround, an internal hole, and sub-cutoff/above-cutoff strips.
				color.a = 1.0
				if x < 8 or x > 55 or y < 3 or y > 60 or (x >= 27 and x <= 36 and y >= 16 and y <= 54):
					color.a = 0.0
				elif x == 8:
					color.a = 0.2
				elif x == 9:
					color.a = 0.6
				image.set_pixel(frame * 64 + x, y, color)
	return ImageTexture.create_from_image(image)


# Card projection is orthographic and fills CARD_SIZE / CAMERA_SIZE of the image.
func _uv_y(y: int) -> float:
	var extent := SIZE * CARD_SIZE / CAMERA_SIZE
	return (float(y) + 0.5 - (SIZE - extent) * 0.5) / extent


func _compare(a: Image, b: Image, max_uv_y: float) -> Dictionary:
	var changed := 0
	var alpha_changed := 0
	var foreground := 0
	var background := 0
	var max_rgb := 0.0
	var max_alpha := 0.0
	for y in SIZE:
		if _uv_y(y) > max_uv_y:
			continue
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			var alpha_delta := absf(ca.a - cb.a)
			max_alpha = maxf(max_alpha, alpha_delta)
			if alpha_delta > 0.0:
				alpha_changed += 1
			if ca.a > 0.5:
				foreground += 1
			elif ca.a < 0.1:
				background += 1
			if ca.a > 0.02 or cb.a > 0.02:
				max_rgb = maxf(max_rgb, delta)
				if delta > ERROR:
					changed += 1
	return {"valid": foreground > 20 and background > 20, "foreground": foreground,
		"background": background, "changed": changed, "alpha_changed": alpha_changed,
		"max_rgb_delta": max_rgb, "max_alpha_delta": max_alpha}


func _root_metrics(base: Image, half: Image, full: Image, fraction: float, max_height: float) -> Dictionary:
	var samples := 0
	var changed := 0
	var darker := 0
	var above_full := 0
	var half_sum := 0.0
	var full_sum := 0.0
	var color_sum := Vector3.ZERO
	for y in SIZE:
		var relative_height := (0.5 - _uv_y(y)) / fraction + 0.5
		if relative_height < 0.0 or relative_height > max_height:
			continue
		for x in SIZE:
			var a := base.get_pixel(x, y)
			var b := half.get_pixel(x, y)
			var c := full.get_pixel(x, y)
			if a.a <= 0.5 or b.a <= 0.5 or c.a <= 0.5:
				continue
			var difference := Vector3(b.r - a.r, b.g - a.g, b.b - a.b)
			var full_difference := Vector3(c.r - a.r, c.g - a.g, c.b - a.b)
			samples += 1
			half_sum += (difference.x + difference.y + difference.z) / 3.0
			full_sum += (full_difference.x + full_difference.y + full_difference.z) / 3.0
			color_sum += Vector3(b.r, b.g, b.b)
			if maxf(difference.x, maxf(difference.y, difference.z)) > ERROR:
				changed += 1
			for channel in 3:
				if difference[channel] < -ERROR:
					darker += 1
				if difference[channel] - full_difference[channel] > ERROR:
					above_full += 1
	var divisor := float(maxi(samples, 1))
	return {"samples": samples, "changed": changed, "candidate_mean": half_sum / divisor,
		"full_mean": full_sum / divisor, "darker_channels": darker, "above_full_channels": above_full,
		"red_mean": color_sum.x / divisor, "green_mean": color_sum.y / divisor,
		"blue_mean": color_sum.z / divisor}


func _finish(status: String) -> void:
	var output_ok := true
	if not _out.is_empty():
		var file := FileAccess.open(_out, FileAccess.WRITE)
		if file == null:
			printerr("Could not create report at %s" % _out)
			output_ok = false
		else:
			var source_hashes := {SHADER_PATH: FileAccess.get_sha256(SHADER_PATH)}
			var material_path := "res://scenery/woodland_edge_habitat.gd"
			source_hashes[material_path] = FileAccess.get_sha256(material_path)
			for species: String in SPECIES:
				var path := "res://assets/landscape/vegetation/impostors/%s_4view.png" % species
				source_hashes[path] = FileAccess.get_sha256(path)
				var manifest_path := "res://assets/landscape/vegetation/impostors/%s_4view.json" % species
				source_hashes[manifest_path] = FileAccess.get_sha256(manifest_path)
			file.store_string(JSON.stringify({"status": status, "checks": _checks, "pixel_checks": _pixel_checks,
				"failures": _failures, "viewport": [SIZE, SIZE], "engine": Engine.get_version_info(),
				"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
				"adapter": RenderingServer.get_video_adapter_name(), "sources_sha256": source_hashes,
				"cases": _results}, "\t"))
			file.close()
	print("woodland root lighting: %s, %d checks, %d failures" % [status, _checks, _failures])
	quit(1 if _failures > 0 or not output_ok else 0)
