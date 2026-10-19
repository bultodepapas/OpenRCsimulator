## FW-MOON-08: the moon's glare on a model, captured like SUN-02's sun cases so tools/landscape/glare_contrast.py
## measures it unchanged. Builds the real world on a field-world sky (default: the Night preset, clear), aims the
## pilot's eye at the aircraft 60 m away, `deg` beside the moon, and renders four images per angle:
## glare_offset_<deg> (glare on), _off (glare off), _hidden (aircraft removed) and _hidden_off. A fifth, _hidden_full,
## saturates the veil (alpha → 1), so the display shows the veil's colour; with _hidden_off it gives the display-space
## kappa (background over veil colour around the aircraft), reported beside the kappa the code uses.
## Also renders the pilot's 60° view of the moon with and without glare (moon-view-on/off.png).
## Run from the repository root (Compatibility needs a renderer; under xvfb-run on a machine without a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-08/moon_glare_capture.gd" -- --out=/abs/dir \
##     [--angles=1,2,3,5,8,12,20] [--sky_args=--date=2026-10-25,--time=23:59]
##   "$(app/tests/visual-env.sh)" tools/landscape/glare_contrast.py /abs/dir
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Airplane := preload("res://render/airplane.gd")

const VIEW_SIZE := Vector2i(1280, 720)
const ARGS := ["--time_of_day=night"]
const ANGLES := "1,2,3,5,8,12,20"
## The veil saturates (alpha ≈ 1 within 45° of the moon) at this strength.
const FULL_STRENGTH := 1.0e6

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
	root.size = VIEW_SIZE
	var sky_args: Array = Array(str(_args.sky_args).split(",")) if _args.has("sky_args") else ARGS
	Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset("clear"))
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var built: Dictionary = WorldBuilder.build(scene_root, field, Callable(), Conditions.resolve(PackedStringArray(sky_args)), {},
		{field_lighting = "off", campfire = false})
	var env: Environment = built.environment
	var sky := env.sky.sky_material as ShaderMaterial
	var flare: MeshInstance3D = scene_root.get_node_or_null("SunGlare")
	if flare == null:
		printerr("no glare node (landscape upgrade off?)")
		quit(1)
		return
	var camera := Camera3D.new()
	camera.far = 21000.0
	camera.near = 0.1
	scene_root.add_child(camera)
	camera.current = true
	camera.position = Frames.ned_to_render([0.0, 0.0, -1.7])
	var aircraft: Dictionary = Airplane.build()
	scene_root.add_child(aircraft.root)
	var moon: Vector3 = (sky.get_shader_parameter("moon_dir") as Vector3).normalized()
	var report := {format = "openrc-moon-glare-capture v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), arguments = sky_args, size = [VIEW_SIZE.x, VIEW_SIZE.y],
		moon = {azimuth_deg = Atmosphere.state.get("moon_azimuth_deg", 0.0), elevation_deg = Atmosphere.state.get("moon_elevation_deg", 0.0)},
		cases = {}}
	for angle: String in str(_args.get("angles", ANGLES)).split(","):
		var tag := "glare_offset_" + angle
		var images := {}
		for suffix: String in ["", "_off", "_hidden", "_hidden_off", "_hidden_full"]:
			camera.fov = 30.0
			aircraft.root.visible = not "hidden" in suffix
			flare.intensity = 0.0 if suffix.ends_with("_off") else FULL_STRENGTH if suffix == "_hidden_full" else 1.0
			_follow_aircraft(camera, aircraft.root, moon, float(angle))
			var image := await _capture()
			image.save_png(out.path_join(tag + suffix + ".png"))
			images[suffix] = image
			if suffix == "":
				report.cases[tag] = {glare_strength = flare.get_meta("strength", 0.0), glare_aureole_coeff = flare.get_meta("aureole_coeff", 0.0),
					glare_background_scale = flare.get_meta("background_scale", 0.0), glare_afterimage = flare.get_meta("afterimage", 0.0),
					kappa = flare.get_meta("kappa", 0.0), exposure = env.tonemap_exposure, glare_visible = flare.visible}
		report.cases[tag].kappa_display_measured = _display_kappa(images, aircraft, camera)
	# The pilot's 60° view of the moon, with and without glare.
	aircraft.root.visible = false
	camera.fov = 60.0
	camera.look_at(camera.position + moon)
	for pair: Array in [["moon-view-on", 1.0], ["moon-view-off", 0.0]]:
		flare.intensity = pair[1]
		(await _capture()).save_png(out.path_join(str(pair[0]) + ".png"))
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " ") + "\n")
	f.close()
	print("moon glare capture written to ", out)
	quit(0)


func _capture() -> Image:
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## Display-space kappa around the aircraft: the background's luma without glare over the saturated veil's, in the
## sRGB code values the overlay blends in, over a ring just outside the aircraft (where the contrast is measured).
func _display_kappa(images: Dictionary, aircraft: Dictionary, camera: Camera3D) -> float:
	var off: Image = images["_hidden_off"]
	var full: Image = images["_hidden_full"]
	var centre := camera.unproject_position(aircraft.root.position)
	var b := 0.0
	var c := 0.0
	var n := 0
	for k in 64:
		var a := TAU * k / 64.0
		var p := Vector2i(centre + Vector2(cos(a), sin(a)) * 40.0)
		if p.x < 0 or p.y < 0 or p.x >= VIEW_SIZE.x or p.y >= VIEW_SIZE.y:
			continue
		b += _luma(off.get_pixelv(p))
		c += _luma(full.get_pixelv(p))
		n += 1
	return b / c if n > 0 and c > 0.0 else -1.0


static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## SUN-02's geometry (app/tests/capture_landscape_upgrade.gd): the aircraft 60 m away, `offset_deg` from the source
## across its azimuth, belly toward the eye, the view centred on it.
static func _follow_aircraft(camera: Camera3D, aircraft: Node3D, source: Vector3, offset_deg: float) -> void:
	var offset_rad := deg_to_rad(offset_deg)
	var across := source.cross(Vector3.UP).normalized()
	aircraft.position = camera.position + (source * cos(offset_rad) + across * sin(offset_rad)).normalized() * 60.0
	camera.look_at(aircraft.position)
	aircraft.basis = camera.basis * Basis(Vector3.RIGHT, PI / 2.0)
