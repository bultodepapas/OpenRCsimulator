## FW-MOON-06: production renders of a flowing twilight, one frame per 30 s sky step (World.flow_to, as in flight at
## any time scale), looking west (the setting sun) and east (the rising moon) from the pilot's eye. The exposure is
## the state's own (no view target), so frames compare step to step. Writes PNGs and manifest.json for
## analyze_strip.py. Default: the Moonrise preset's evening (2026-09-26 from 19:00, 3 h) under the "broken" sky.
## Run from the repository root (Compatibility needs a renderer; under xvfb-run on a machine without a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-06/twilight_strip.gd" -- --out=/abs/dir [--sky=broken]
##     [--date=2026-09-26 --time=19:00 --hours=3]
##   python3 -I research/field-world/fw-moon-06/analyze_strip.py /abs/dir
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")

const VIEW_SIZE := Vector2i(480, 270)
const FOV_DEG := 70.0
const STEP_S := 30.0
## Azimuth and pitch of each view (degrees): toward the sunset and toward the moonrise of the default evening.
const VIEWS := {west = [268.0, 8.0], east = [88.0, 8.0]}

var _args := {"sky": "broken", "date": "2026-09-26", "time": "19:00", "hours": "3"}


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
	if not Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset(str(_args.sky))):
		printerr("unknown sky preset " + str(_args.sky))
		quit(1)
		return
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var arguments := ["--date=" + str(_args.date), "--time=" + str(_args.time), "--time_scale=20"]
	var scene_root := Node3D.new()
	viewport.add_child(scene_root)
	WorldBuilder.build(scene_root, field, Callable(), Conditions.resolve(PackedStringArray(arguments)), {},
		{field_lighting = "off", campfire = false})
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = FOV_DEG
	camera.far = 45000.0
	scene_root.add_child(camera)
	var eye := Frames.ned_to_render([0.0, 0.0, -1.7])
	var steps := int(float(_args.hours) * 3600.0 / STEP_S)
	var frames := []
	for k in steps + 1:
		WorldBuilder.flow_to(k * STEP_S / 20.0)
		var st: Dictionary = Atmosphere.state
		var row := {step = k, minutes = k * STEP_S / 60.0, sun_elevation_deg = st.sun_elevation_deg,
			moon_elevation_deg = st.moon_elevation_deg, light_source = st.light_source, shadow = st.shadow_strength,
			exposure = st.exposure, cloud_light2_share = st.get("cloud_light2_share", -1.0)}
		for view: String in VIEWS:
			var az := deg_to_rad(float(VIEWS[view][0]))
			var el := deg_to_rad(float(VIEWS[view][1]))
			var toward := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()
			camera.transform = Transform3D(Basis.looking_at(toward, Vector3.UP), eye)
			await process_frame
			RenderingServer.force_draw(false)
			var file_name := "%s-%03d.png" % [view, k]
			viewport.get_texture().get_image().save_png(out.path_join(file_name))
			row[view] = file_name
		frames.append(row)
	var f := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({format = "openrc-twilight-strip v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), arguments = arguments, sky = _args.sky, fov_deg = FOV_DEG,
		size = [VIEW_SIZE.x, VIEW_SIZE.y], views = VIEWS, frames = frames}, " ") + "\n")
	f.close()
	print("strip written: %d steps" % frames.size())
	quit(0)
