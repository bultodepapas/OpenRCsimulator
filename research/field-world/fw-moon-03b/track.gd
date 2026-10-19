## FW-MOON-03b: the moon's disc tracked frame by frame in production renders, with time flowing ×20 (4.5 s of flight
## = three 30 s sky steps), through a fixed 6° camera (the pilot's auto-zoom floor). Mode "stepped" applies only the
## stepped sky (World.flow_to, the behaviour before FW-MOON-03b); "per_frame" adds World.flow_frame. Per frame: the
## brightness-weighted centroid of the disc in a crop around it. Writes track.json and a few crops for a strip.
## Run from the repository root (Compatibility needs a renderer; under xvfb-run on a machine without a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-03b/track.gd" -- --out=/abs/dir
##   python3 -I research/field-world/fw-moon-03b/analyze.py /abs/dir
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")

const VIEW_SIZE := Vector2i(1280, 720)
const FOV_DEG := 6.0
const FPS := 60.0
const SECONDS := 4.5
## Full moon 25° up in the east-north-east at the reference field (FW-MOON-00 survey); clear sky.
const ARGS := ["--date=2026-10-25", "--time=21:00", "--time_scale=20"]
const CROP := 240
## Frames saved as PNG crops (around the step at 1.5 s and mid-step).
const SAVED := [84, 88, 89, 90, 91, 135]

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
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	if not Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset("clear")):
		printerr("clear sky preset did not validate")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var result := {format = "openrc-moon-track v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), arguments = ARGS, fov_deg = FOV_DEG, size = [VIEW_SIZE.x, VIEW_SIZE.y],
		fps = FPS, time_scale = 20.0, modes = {}}
	for mode: String in ["stepped", "per_frame"]:
		var scene_root := Node3D.new()
		viewport.add_child(scene_root)
		var built: Dictionary = WorldBuilder.build(scene_root, field, Callable(), Conditions.resolve(PackedStringArray(ARGS)), {},
			{field_lighting = "off", campfire = false})
		var camera := Camera3D.new()
		camera.current = true
		camera.fov = FOV_DEG
		camera.far = 45000.0
		var eye := Frames.ned_to_render([0.0, 0.0, -1.7])
		camera.position = eye
		scene_root.add_child(camera)
		# Aim a little ahead of the moon's start, so the 0.35° it moves stays near the image centre.
		var toward: Vector3 = Atmosphere.state.moon_dir
		camera.look_at(eye + toward * 1000.0, Vector3.UP)
		var centre := camera.unproject_position(eye + toward * 1000.0)
		var crop := Rect2i(Vector2i(int(centre.x) - CROP / 2, int(centre.y) - CROP / 2), Vector2i(CROP, CROP))
		var frames := []
		for i in int(SECONDS * FPS) + 1:
			var t := float(i) / FPS
			WorldBuilder.flow_to(t)
			if mode == "per_frame":
				WorldBuilder.flow_frame(t)
			await process_frame
			RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image().get_region(crop)
			if i in SAVED:
				image.save_png(_out.path_join("%s-%03d.png" % [mode, i]))
			var c := _centroid(image)
			frames.append({i = i, t = t, x = c.x + crop.position.x, y = c.y + crop.position.y, weight = c.z,
				step = WorldBuilder.flow_hour()})
		result.modes[mode] = {crop = [crop.position.x, crop.position.y, CROP, CROP], frames = frames}
		scene_root.queue_free()
		await process_frame
	var f := FileAccess.open(_out.path_join("track.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " ") + "\n")
	f.close()
	print("track written: " + _out.path_join("track.json"))
	quit(0)


## Brightness-weighted centroid of the pixels brighter than half the crop's peak (the disc), in crop pixels; z = weight.
static func _centroid(image: Image) -> Vector3:
	image.convert(Image.FORMAT_RGB8)
	var data := image.get_data()
	var w := image.get_width()
	var peak := 0
	var lum := PackedInt32Array()
	lum.resize(data.size() / 3)
	for p in lum.size():
		var v := (2126 * data[3 * p] + 7152 * data[3 * p + 1] + 722 * data[3 * p + 2]) / 10000
		lum[p] = v
		peak = maxi(peak, v)
	var threshold := peak / 2
	var sx := 0.0
	var sy := 0.0
	var sw := 0.0
	for p in lum.size():
		var v := lum[p] - threshold
		if v > 0:
			sx += float(v) * float(p % w)
			sy += float(v) * float(p / w)
			sw += float(v)
	return Vector3(sx / maxf(sw, 1.0), sy / maxf(sw, 1.0), sw)
