## FW-MOON-06d: production renders frame by frame (60 fps of flight at ×20) across two 30 s sky steps, as World.update
## does in flight: mode "stepped" applies only World.flow_to (the behaviour before FW-MOON-06d), "per_frame" adds
## World.flow_frame. Records the mean linear luminance of the sky (top 55 %) and the ground (bottom 30 %) per frame
## and saves the frames around the first step. Windows: nautical twilight looking west (sun about −6°) and the low
## afternoon sun looking east over cloud shadows (sun about 10°), both on the Moonrise evening under "broken".
## Run from the repository root (Compatibility needs a renderer; under xvfb-run on a machine without a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-06/frame_track.gd" -- --out=/abs/dir
##   python3 -I research/field-world/fw-moon-06/analyze_frames.py /abs/dir
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")

const VIEW_SIZE := Vector2i(480, 270)
const FPS := 60.0
const ARGS := ["--date=2026-09-26", "--time=19:00", "--time_scale=20"]
## [id, flight clock at the start (s; ×20, so sky minutes = clock / 3), azimuth, pitch (degrees), seconds]
const WINDOWS := [["nautical_west", 270.75, 268.0, 8.0, 3.0], ["low_sun_east", 6.75, 88.0, -6.0, 3.0]]

var _out := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	if _out.is_empty() or not _out.is_absolute_path():
		printerr("--out=<absolute directory> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset("broken"))
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var result := {format = "openrc-frame-track v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), arguments = ARGS, fps = FPS, size = [VIEW_SIZE.x, VIEW_SIZE.y], runs = []}
	for window: Array in WINDOWS:
		for mode: String in ["stepped", "per_frame"]:
			var scene_root := Node3D.new()
			viewport.add_child(scene_root)
			WorldBuilder.build(scene_root, field, Callable(), Conditions.resolve(PackedStringArray(ARGS)), {},
				{field_lighting = "off", campfire = false})
			var camera := Camera3D.new()
			camera.current = true
			camera.fov = 70.0
			camera.far = 45000.0
			scene_root.add_child(camera)
			var eye := Frames.ned_to_render([0.0, 0.0, -1.7])
			var az := deg_to_rad(float(window[2]))
			var el := deg_to_rad(float(window[3]))
			camera.transform = Transform3D(Basis.looking_at(Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized(),
				Vector3.UP), eye)
			var frames := []
			for i in int(float(window[4]) * FPS) + 1:
				var t := float(window[1]) + float(i) / FPS
				WorldBuilder.flow_to(t)
				if mode == "per_frame":
					WorldBuilder.flow_frame(t)
				await process_frame
				RenderingServer.force_draw(false)
				var image := viewport.get_texture().get_image()
				if i >= 40 and i <= 50:
					image.save_png(_out.path_join("%s-%s-%03d.png" % [window[0], mode, i]))
				var lum := _regions(image)
				frames.append({i = i, t = t, sky = lum.x, ground = lum.y, sun_elevation_deg = Atmosphere.state.sun_elevation_deg})
			result.runs.append({window = window[0], mode = mode, frames = frames})
			scene_root.queue_free()
			await process_frame
	var f := FileAccess.open(_out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " ") + "\n")
	f.close()
	print("frames written: " + _out.path_join("frames.json"))
	quit(0)


## Mean linear luminance of the top 55 % (x) and bottom 30 % (y) of the image (the engine's sRGB decode), on a
## 4 × 2 pixel sampling grid.
static func _regions(image: Image) -> Vector2:
	image.convert(Image.FORMAT_RGB8)
	var data := image.get_data()
	var w := image.get_width()
	var h := image.get_height()
	var sky := 0.0
	var ground := 0.0
	var ns := 0
	var ng := 0
	for y in range(0, h, 2):
		var region := 0 if y < int(0.55 * h) else (1 if y >= int(0.70 * h) else -1)
		if region < 0:
			continue
		for x in range(0, w, 4):
			var p := 3 * (y * w + x)
			var l := 0.2126 * _decode(data[p]) + 0.7152 * _decode(data[p + 1]) + 0.0722 * _decode(data[p + 2])
			if region == 0:
				sky += l
				ns += 1
			else:
				ground += l
				ng += 1
	return Vector2(sky / maxf(ns, 1), ground / maxf(ng, 1))


static func _decode(v: int) -> float:
	var c := v / 255.0
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
