# FW-MOON-01 render-path bench (research only). One case per process; see ../run.sh for the exact commands.
# User args (after --):
#   --mode=bench|parity|lights   bench: frame timing (default); parity: sky disc vs mesh disc captures;
#                                lights: second DirectionalLight3D captures and draw calls
#   --case=<name>                one of CASES (bench mode)
#   --warmup=120 --frames=600    frames skipped, frames measured
#   --burn=200                   loop iterations added to the sky shader ONLY when AT_CUBEMAP_PASS (burn_* cases)
#   --out=<file.json>            results; --shots=<dir> PNG captures (parity/lights)
# The environment reproduces app/render/atmosphere.gd in field-world (FW) mode: Sky.PROCESS_MODE_QUALITY, default
# radiance size, background SKY, ambient COLOR, reflections DISABLED, glow off, AgX, exponential fog, one shadowed
# DirectionalLight3D (PSSM 2 splits, 300 m) and MSAA 2x from project.godot.
extends Node3D

const SKY_SHADER := preload("res://render/sky.gdshader")
const MOON_DISC_SHADER := preload("res://moon_disc.gdshader")

const CASES := {
	"static": {},
	"uniform": {animate = true},
	"uniform_incremental": {animate = true, process_mode = Sky.PROCESS_MODE_INCREMENTAL},
	"uniform_realtime256": {animate = true, process_mode = Sky.PROCESS_MODE_REALTIME, radiance = Sky.RADIANCE_SIZE_256},
	"uniform_realtime32": {animate = true, process_mode = Sky.PROCESS_MODE_REALTIME, radiance = Sky.RADIANCE_SIZE_32},
	"sky_ambient_static": {ambient = "sky"},
	"sky_ambient_uniform": {ambient = "sky", animate = true},
	"sky_ambient_uniform_rt32": {ambient = "sky", animate = true, process_mode = Sky.PROCESS_MODE_REALTIME,
		radiance = Sky.RADIANCE_SIZE_32},
	"burn_color_static": {burn = true},
	"burn_color_uniform": {burn = true, animate = true},
	"burn_sky_static": {burn = true, ambient = "sky"},
	"burn_sky_uniform": {burn = true, ambient = "sky", animate = true},
	"mesh_disc": {mesh = true, animate = true},
	"light2": {light2 = "noshadow"},
	"light2_shadow": {light2 = "shadow"},
}

const MOON_AZ_DEG := 90.0
const MOON_EL_DEG := 25.0
const STEP_DEG_PER_FRAME := 0.01

var args := {}
var cfg := {}
var env: Environment
var sky_mat: ShaderMaterial
var disc_mat: ShaderMaterial
var disc: MeshInstance3D
var cam: Camera3D
var moon_light: DirectionalLight3D
var light2: DirectionalLight3D
var frame := 0
var last_us := 0
var wall_ms := PackedFloat64Array()
var cpu_ms := PackedFloat64Array()
var gpu_ms := PackedFloat64Array()
var draw_calls := PackedInt64Array()
var moon_az := MOON_AZ_DEG
var moon_el := MOON_EL_DEG


static func dir_from(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)) # north = -Z, east = +X


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mode: String = args.get("mode", "bench")
	cfg = CASES.get(args.get("case", "static"), {}) if mode == "bench" else {}
	_build_scene()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if mode == "parity":
		_run_parity.call_deferred()
	elif mode == "lights":
		_run_lights.call_deferred()


func _sky_shader() -> Shader:
	if not cfg.get("burn", false):
		return SKY_SHADER
	# A cost amplifier that only the radiance cubemap pass executes: if a re-render happens, it cannot hide in noise.
	var code: String = SKY_SHADER.code
	code = code.replace("uniform float cloud_relief_strength", "uniform int burn_iterations = 0;\nuniform float cloud_relief_strength")
	code = code.replace("\tCOLOR = encode_for_engine(col);",
		"\tif (AT_CUBEMAP_PASS) {\n\t\tfloat acc = 0.0;\n\t\tfor (int i = 0; i < burn_iterations; i++) {\n" +
		"\t\t\tacc += sin(float(i) * EYEDIR.x + acc) * 1e-9;\n\t\t}\n\t\tcol += vec3(acc);\n\t}\n" +
		"\tCOLOR = encode_for_engine(col);")
	assert(code.contains("burn_iterations; i++"))
	var s := Shader.new()
	s.code = code
	return s


func _set_cloud_uniforms(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cloud_coverage", 0.35)
	m.set_shader_parameter("cloud_scale", 6.0)
	m.set_shader_parameter("cloud_seed", 1253)
	m.set_shader_parameter("cluster_strength", 0.35)
	m.set_shader_parameter("cirrus_strength", 0.12)
	m.set_shader_parameter("cloud_offset", Vector2.ZERO)


func _build_scene() -> void:
	var moon_dir := dir_from(moon_az, moon_el)
	var sun_dir := Vector3(-0.9, -0.25, 0.35).normalized() # below the horizon, waxing-gibbous terminator
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = _sky_shader()
	sky_mat.set_shader_parameter("zenith_lin", Vector3(0.004, 0.006, 0.012))
	sky_mat.set_shader_parameter("haze_lin", Vector3(0.008, 0.010, 0.012))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_lin", Vector3.ZERO)
	sky_mat.set_shader_parameter("sun_scatter", 0.0)
	sky_mat.set_shader_parameter("sun_disc", 0.0)
	sky_mat.set_shader_parameter("disc_dir", sun_dir)
	sky_mat.set_shader_parameter("cloud_lin", Vector3(0.020, 0.022, 0.025))
	sky_mat.set_shader_parameter("silver_strength", 0.18)
	_set_cloud_uniforms(sky_mat)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("moon_sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_lin", Vector3.ZERO if cfg.get("mesh", false) else Vector3(0.6, 0.6, 0.58))
	if cfg.get("burn", false):
		sky_mat.set_shader_parameter("burn_iterations", int(args.get("burn", "200")))

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = cfg.get("process_mode", Sky.PROCESS_MODE_QUALITY)
	if cfg.has("radiance"):
		sky.radiance_size = cfg.radiance
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 3.912 / 23000.0
	env.fog_light_color = Color(0.008, 0.010, 0.012).linear_to_srgb()
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_height_density = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	if cfg.get("ambient", "color") == "sky":
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color("#b4c8ff")
	moon_light.light_energy = 0.4
	moon_light.shadow_enabled = true
	moon_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon_light.directional_shadow_max_distance = 300.0
	add_child(moon_light)
	moon_light.transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), moon_dir * 100.0)
	if cfg.has("light2"):
		_add_light2(cfg.light2 == "shadow")

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.33, 0.18)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.7, 0.7, 0.7)
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	for i in 25: # boxes ahead of the pilot (east), 15–200 m, for shadows and depth
		var b := MeshInstance3D.new()
		b.mesh = box
		b.material_override = bm
		var r := 15.0 + 185.0 * float(i) / 24.0
		var a := deg_to_rad(60.0 + float((i * 37) % 60))
		b.position = Vector3(r * sin(a), 1.5, -r * cos(a))
		add_child(b)

	disc_mat = ShaderMaterial.new()
	disc_mat.shader = MOON_DISC_SHADER
	disc_mat.set_shader_parameter("moon_dir", moon_dir)
	disc_mat.set_shader_parameter("moon_sun_dir", sun_dir)
	disc_mat.set_shader_parameter("moon_lin", Vector3(0.6, 0.6, 0.58))
	_set_cloud_uniforms(disc_mat)
	disc = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	disc.mesh = quad
	disc.material_override = disc_mat
	disc.custom_aabb = AABB(Vector3(-30000.0, -30000.0, -30000.0), Vector3(60000.0, 60000.0, 60000.0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = cfg.get("mesh", false)
	add_child(disc)

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 21000.0
	add_child(cam)
	cam.position = Vector3(0.0, 1.7, 0.0)
	cam.look_at(cam.position + dir_from(MOON_AZ_DEG + 3.0, 12.0), Vector3.UP)
	cam.make_current()


func _add_light2(with_shadow: bool) -> void:
	light2 = DirectionalLight3D.new()
	light2.light_color = Color(1.0, 0.75, 0.55)
	light2.light_energy = 0.3
	light2.shadow_enabled = with_shadow
	light2.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light2.directional_shadow_max_distance = 300.0
	add_child(light2)
	var d := dir_from(270.0, 8.0) # a low western source (twilight sun) opposite the eastern moon
	light2.transform = Transform3D(Basis.looking_at(-d, Vector3.UP), d * 100.0)


func _process(_delta: float) -> void:
	if args.get("mode", "bench") != "bench":
		return
	var now := Time.get_ticks_usec()
	var warmup := int(args.get("warmup", "120"))
	var frames := int(args.get("frames", "600"))
	if cfg.get("animate", false):
		moon_az += STEP_DEG_PER_FRAME
		var d := dir_from(moon_az, moon_el)
		if cfg.get("mesh", false):
			disc_mat.set_shader_parameter("moon_dir", d)
		else:
			sky_mat.set_shader_parameter("moon_dir", d)
	if frame > warmup and frame <= warmup + frames:
		var vp := get_viewport().get_viewport_rid()
		wall_ms.append(float(now - last_us) / 1000.0)
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	last_us = now
	frame += 1
	if frame > warmup + frames + 1:
		_write({wall_ms = wall_ms, cpu_ms = cpu_ms, gpu_ms = gpu_ms, draw_calls = draw_calls})
		get_tree().quit()


func _write(extra: Dictionary) -> void:
	var out: Dictionary = {
		format = "fw-moon-01-bench v1",
		mode = args.get("mode", "bench"),
		case = args.get("case", ""),
		config = var_to_str(cfg),
		size = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(),
		method = RenderingServer.get_current_rendering_method(),
		radiance_size = env.sky.radiance_size,
		sky_process_mode = env.sky.process_mode,
		ambient_source = env.ambient_light_source,
		reflection_source = env.reflected_light_source,
		msaa_3d = get_viewport().msaa_3d,
		godot = Engine.get_version_info().string,
	}
	out.merge(extra)
	var f := FileAccess.open(args.get("out", "user://bench.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _capture(name: String) -> Image:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	if args.get("shots", "") != "":
		img.save_png(String(args.shots).path_join(name + ".png"))
	return img


# Candidate A (sky disc) vs candidate B (mesh disc) at a 2° FOV, so the disc spans ~190 px of 720.
# Part 1 (game look, AgX): integrated disc signal and colour. Part 2 (cloud mask, LINEAR tonemap, brighter clouds):
# per-pixel cloud transmission t = moon signal with clouds / moon signal with coverage 0, for A and for B.
# Compatibility blends after its sRGB encode, so B's signal is decode(B - C) while A's is decode(A) - decode(C).
func _run_parity() -> void:
	await _frames(30) # shader compilation
	cam.fov = 2.0
	var look := []
	for p: Array in [[90.0, 25.0], [132.0, 25.0], [60.0, 41.0]]:
		_aim(p)
		var tag := "az%03d_el%02d" % [int(p[0]), int(p[1])]
		var img := await _abc("look_" + tag, true)
		look.append(_compare_look(tag, img[0], img[1], img[2]))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sky_mat.set_shader_parameter("cloud_lin", Vector3(0.08, 0.085, 0.09))
	var mask := []
	var t_all := PackedFloat64Array()
	for el in [22.0, 30.0, 38.0, 46.0]:
		for i in 8:
			var p := [60.0 + 15.0 * i + el * 0.37, el]
			_aim(p)
			var tag := "az%03d_el%02d" % [int(p[0]), int(p[1])]
			var cloudy := await _abc("mask_" + tag, int(i) == 0)
			_set_coverage(0.0)
			var clear := await _abc("mask_" + tag + "_clear", false)
			_set_coverage(0.35)
			var row := _compare_mask(tag, cloudy, clear, t_all)
			mask.append(row)
	t_all.sort()
	_write({parity_look = look, parity_mask = mask,
		mask_abs_dt_p50 = t_all[int(0.50 * (t_all.size() - 1))] if t_all.size() else -1.0,
		mask_abs_dt_p99 = t_all[int(0.99 * (t_all.size() - 1))] if t_all.size() else -1.0,
		mask_abs_dt_max = t_all[t_all.size() - 1] if t_all.size() else -1.0, mask_pixels = t_all.size()})
	get_tree().quit()


func _aim(p: Array) -> void:
	var d := dir_from(p[0], p[1])
	sky_mat.set_shader_parameter("moon_dir", d)
	disc_mat.set_shader_parameter("moon_dir", d)
	cam.look_at(cam.position + d, Vector3.UP)


func _set_coverage(c: float) -> void:
	sky_mat.set_shader_parameter("cloud_coverage", c)
	disc_mat.set_shader_parameter("cloud_coverage", c)


# A: sky disc; B: mesh disc (sky disc off); C: no disc.
func _abc(tag: String, save: bool) -> Array:
	var saved: String = args.get("shots", "")
	if not save:
		args.erase("shots")
	sky_mat.set_shader_parameter("moon_lin", Vector3(0.6, 0.6, 0.58))
	disc.visible = false
	var a := await _capture(tag + "_A_sky")
	sky_mat.set_shader_parameter("moon_lin", Vector3.ZERO)
	disc.visible = true
	var b := await _capture(tag + "_B_mesh")
	disc.visible = false
	var c := await _capture(tag + "_C_none")
	if saved != "":
		args["shots"] = saved
	return [a, b, c]


static func _dec(v: float) -> float: # inverse of the engine's linear_to_srgb (1.055 x^(1/2.4) - 0.055)
	return pow((maxf(v, 0.0) + 0.055) / 1.055, 2.4)


func _compare_look(tag: String, a: Image, b: Image, c: Image) -> Dictionary:
	var sum_a := Vector3.ZERO
	var sum_b := Vector3.ZERO
	var n := 0
	var cx := a.get_width() / 2
	var cy := a.get_height() / 2
	for y in range(cy - 110, cy + 110):
		for x in range(cx - 110, cx + 110):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var cc := c.get_pixel(x, y)
			if (ca.r + ca.g + ca.b - cc.r - cc.g - cc.b) / 3.0 > 2.0 / 255.0:
				n += 1
				sum_a += Vector3(ca.r - cc.r, ca.g - cc.g, ca.b - cc.b)
				sum_b += Vector3(cb.r - cc.r, cb.g - cc.g, cb.b - cc.b)
	var centre_a := a.get_pixel(cx, cy)
	var centre_b := b.get_pixel(cx, cy)
	return {tag = tag, disc_px = n, signal_ratio_b_over_a_8bit = (sum_b.x + sum_b.y + sum_b.z) / maxf(sum_a.x + sum_a.y + sum_a.z, 1e-9),
		centre_a_8bit = [roundi(centre_a.r * 255), roundi(centre_a.g * 255), roundi(centre_a.b * 255)],
		centre_b_8bit = [roundi(centre_b.r * 255), roundi(centre_b.g * 255), roundi(centre_b.b * 255)]}


func _compare_mask(tag: String, cloudy: Array, clear: Array, t_all: PackedFloat64Array) -> Dictionary:
	var a: Image = cloudy[0]
	var b: Image = cloudy[1]
	var c: Image = cloudy[2]
	var a0: Image = clear[0]
	var b0: Image = clear[1]
	var c0: Image = clear[2]
	var cx := a.get_width() / 2
	var cy := a.get_height() / 2
	var n := 0
	var sum_ta := 0.0
	var sum_tb := 0.0
	var max_dt := 0.0
	for y in range(cy - 100, cy + 100, 2):
		for x in range(cx - 100, cx + 100, 2):
			var s_a0 := _dec(a0.get_pixel(x, y).g) - _dec(c0.get_pixel(x, y).g)
			var s_b0 := _dec(b0.get_pixel(x, y).g - c0.get_pixel(x, y).g)
			if s_a0 < 0.2 or s_b0 < 0.2: # bright, fully inside the disc edge
				continue
			var ta := (_dec(a.get_pixel(x, y).g) - _dec(c.get_pixel(x, y).g)) / s_a0
			var tb := _dec(b.get_pixel(x, y).g - c.get_pixel(x, y).g) / s_b0
			n += 1
			sum_ta += ta
			sum_tb += tb
			max_dt = maxf(max_dt, absf(ta - tb))
			t_all.append(absf(ta - tb))
	return {tag = tag, pixels = n, mean_t_a = sum_ta / maxf(n, 1), mean_t_b = sum_tb / maxf(n, 1), max_abs_dt = max_dt}


func _mean_luma(img: Image, y0: float, y1: float) -> float:
	var s := 0.0
	var n := 0
	for y in range(int(img.get_height() * y0), int(img.get_height() * y1), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / maxf(n, 1)


# Does Compatibility draw a second directional light next to the shadowed one? Captures + draw calls per frame.
func _run_lights() -> void:
	await _frames(30)
	cam.look_at(cam.position + dir_from(MOON_AZ_DEG + 3.0, -12.0), Vector3.UP) # look down at the boxes' shadows
	var rows := []
	var configs := [["moon_shadowed_only", true, ""], ["moon_plus_light2_noshadow", true, "noshadow"],
		["moon_plus_light2_shadow", true, "shadow"], ["light2_noshadow_only", false, "noshadow"],
		["no_direct_light", false, ""]]
	for c: Array in configs:
		moon_light.visible = c[1]
		if light2 != null:
			light2.queue_free()
			light2 = null
			await _frames(1)
		if c[2] != "":
			_add_light2(c[2] == "shadow")
		var img := await _capture("lights_" + String(c[0]))
		rows.append({config = c[0], ground_luma = _mean_luma(img, 0.55, 1.0),
			draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
	_write({lights = rows})
	get_tree().quit()
