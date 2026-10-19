## FW-MOON-08a: measures the rendered aureole against its model. Builds the real world on the Night preset (clear
## sky), aims a 70° camera at the moon, and renders with the aureole as computed and with it set to zero, using a
## linear tonemap at a raised exposure so the ratio survives 8-bit storage. Along the row and column through the
## moon it compares the rendered brightening (decode(on) − decode(off)) with the model's prediction for that pixel
## (the radiance-to-display scale measured on a calibration frame of uniform known sky radiance):
## background × ((1 + aureole / background)^γ − 1), the aureole from the same KS91 shape and path term. Also saves
## AgX views (as played) for each weather preset. Writes profile.json and PNGs.
## Run from the repository root (Compatibility needs a renderer; under xvfb-run on a machine without a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-08/aureole_profile.gd" -- --out=/abs/dir [--gallery]
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")

const VIEW_SIZE := Vector2i(960, 540)
const FOV_DEG := 70.0
const ARGS := ["--time_of_day=night"]
const MEASURE_GAIN := 10.0 # exposure multiplier for the linear measurement (the night sky would sit in the lowest levels)
const GALLERY := ["clear", "classic", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"]

var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var out := str(_args.get("out", ""))
	if out.is_empty() or not out.is_absolute_path():
		printerr("--out=<absolute directory> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var result := {format = "openrc-aureole-profile v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), arguments = ARGS, size = [VIEW_SIZE.x, VIEW_SIZE.y], fov_deg = FOV_DEG}
	var presets: Array = ["clear"] + (GALLERY if _args.has("gallery") else [])
	for preset: String in presets:
		Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset(preset))
		var scene_root := Node3D.new()
		viewport.add_child(scene_root)
		var built: Dictionary = WorldBuilder.build(scene_root, field, Callable(), Conditions.resolve(PackedStringArray(ARGS)), {},
			{field_lighting = "off", campfire = false})
		var env: Environment = built.environment
		var mat := env.sky.sky_material as ShaderMaterial
		var camera := Camera3D.new()
		camera.current = true
		camera.fov = FOV_DEG
		camera.far = 45000.0
		scene_root.add_child(camera)
		var eye := Frames.ned_to_render([0.0, 0.0, -1.7])
		var moon: Vector3 = Atmosphere.state.moon_dir
		camera.transform = Transform3D(Basis.looking_at(moon, Vector3.UP), eye)
		var aureole: Vector3 = mat.get_shader_parameter("moon_aureole_lin")
		if preset == "clear" and not result.has("profile"):
			var exposure := env.tonemap_exposure
			var tonemap := env.tonemap_mode
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = exposure * MEASURE_GAIN
			var on := await _capture(viewport)
			mat.set_shader_parameter("moon_aureole_lin", Vector3.ZERO)
			var off := await _capture(viewport)
			# Calibration: a uniform sky of known radiance gives the actual radiance-to-display scale of the sky pass.
			var keep := {}
			for key: String in ["zenith_lin", "haze_lin", "lobe_lin", "lobe2_lin", "moon_lin"]:
				keep[key] = mat.get_shader_parameter(key)
			var level := 0.3 / env.tonemap_exposure # about 30 % of the display if the sky pass used the tonemap exposure
			var reference := Vector3.ONE * level
			for key: String in ["zenith_lin", "haze_lin"]:
				mat.set_shader_parameter(key, reference)
			for key: String in ["lobe_lin", "lobe2_lin", "moon_lin"]:
				mat.set_shader_parameter(key, Vector3.ZERO)
			var flat := await _capture(viewport)
			for key: String in keep:
				mat.set_shader_parameter(key, keep[key])
			mat.set_shader_parameter("moon_aureole_lin", aureole)
			var scale := _decode(flat.get_pixel(VIEW_SIZE.x / 2, VIEW_SIZE.y / 4)) / level
			on.save_png(out.path_join("linear-on.png"))
			off.save_png(out.path_join("linear-off.png"))
			result.calibration = {reference = level, scale = scale, tonemap_exposure = env.tonemap_exposure,
				flat_level = _decode(flat.get_pixel(VIEW_SIZE.x / 2, VIEW_SIZE.y / 4))}
			result.profile = _profile(on, off, camera, moon, aureole, float(mat.get_shader_parameter("moon_display_gamma")),
				float(mat.get_shader_parameter("moon_radius")), scale)
			result.moon = {azimuth_deg = Atmosphere.state.moon_azimuth_deg, elevation_deg = Atmosphere.state.moon_elevation_deg,
				aureole_lin = [aureole.x, aureole.y, aureole.z], gamma = mat.get_shader_parameter("moon_display_gamma"),
				aerosol_factor = Atmosphere.aureole_aerosol_factor()}
			env.tonemap_mode = tonemap
			env.tonemap_exposure = exposure
		if _args.has("gallery"):
			var shown := await _capture(viewport)
			shown.save_png(out.path_join("gallery-%s-on.png" % preset))
			mat.set_shader_parameter("moon_aureole_lin", Vector3.ZERO)
			var hidden := await _capture(viewport)
			hidden.save_png(out.path_join("gallery-%s-off.png" % preset))
			mat.set_shader_parameter("moon_aureole_lin", aureole)
		scene_root.queue_free()
		await process_frame
	var f := FileAccess.open(out.path_join("profile.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " ") + "\n")
	f.close()
	print("profile written")
	quit(0)


func _capture(viewport: SubViewport) -> Image:
	for i in 3:
		await process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## Rendered vs predicted brightening along the row and the column through the moon (luminance, display linear).
## `scale` is the measured sky radiance-to-display factor.
func _profile(on: Image, off: Image, camera: Camera3D, moon: Vector3, aureole: Vector3, gamma: float, radius: float,
		scale: float) -> Array:
	var rows := []
	var c := camera.unproject_position(camera.position + moon * 1000.0)
	var cx := int(roundf(c.x))
	var cy := int(roundf(c.y))
	for axis: String in ["row", "column"]:
		var n := VIEW_SIZE.x if axis == "row" else VIEW_SIZE.y
		for i in range(0, n, 4):
			var px := Vector2i(i, cy) if axis == "row" else Vector2i(cx, i)
			var d := camera.project_ray_normal(Vector2(px))
			var rho := rad_to_deg(acos(clampf(d.dot(moon), -1.0, 1.0)))
			if rho < rad_to_deg(radius) * 3.0 or d.y < 0.02:
				continue # the disc and the ground
			if _clipped(on.get_pixelv(px)) or _clipped(off.get_pixelv(px)):
				continue # any channel at the top of the range (the bluish sky saturates its blue channel first)
			var a := _decode(on.get_pixelv(px))
			var b := _decode(off.get_pixelv(px))
			var far := pow(10.0, -rho / 40.0)
			var shape := ((maxf(43.80 / (rho * rho), far) if rho < 30.0 else far) - 0.07499) if rho < 45.0 else 0.0
			var sin_z := minf(Vector2(d.x, d.z).length(), 1.0)
			var airmass := 1.0 / sqrt(1.0 - 0.96 * sin_z * sin_z)
			var path := (1.0 - pow(10.0, -0.4 * 0.2 * airmass)) / (1.0 - pow(10.0, -0.4 * 0.2))
			var la := (0.2126 * aureole.x + 0.7152 * aureole.y + 0.0722 * aureole.z) * shape * path * scale
			var predicted := b * (pow(1.0 + la / maxf(b, 1e-9), gamma) - 1.0)
			rows.append({axis = axis, px = i, rho_deg = rho, background = b, rendered = a - b, predicted = predicted})
	return rows


static func _clipped(c: Color) -> bool:
	return maxf(maxf(c.r, c.g), c.b) >= 250.0 / 255.0


## Linear luminance of an 8-bit sRGB pixel.
static func _decode(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
