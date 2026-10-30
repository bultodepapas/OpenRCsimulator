# TRA-10. Cinematic macro of the advanced HX-700 head: the inspection mechanism (servos, swash, nine rods,
# grips) driven by a scripted collective/cyclic/tail demand, canopy hidden, with a camera that pushes in
# and orbits the head. Presentation only: inspection kinematics, not the flight session.
#   <godot> --path tmp/trailer/runtime/app --windowed --resolution 1920x1080 --fixed-fps 60 \
#     --write-movie <abs.avi> --script <abs>/capture_hx700_mechanism.gd -- --out-dir=<abs> [--seconds=4.5]
extends SceneTree

const View := preload("res://render/rotor/hx700_mechanics_view.gd")
const FPS := 60

var view: Node3D
var seconds := 4.5
var output_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--out-dir="):
			output_dir = arg.trim_prefix("--out-dir=")
	if output_dir.is_empty() or Engine.get_write_movie_path().is_empty():
		push_error("Expected --out-dir=<abs> and Movie Maker (--write-movie <abs.avi> --fixed-fps 60).")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_4X
	view = View.new()
	root.add_child(view)
	await process_frame
	view.set_process(false) # this script owns the clock: one 1/60 s step per rendered frame
	view._canvas.visible = false
	view._technical_materials(false) # imported materials, not the inspection colours
	view._show_canopy(false) # the canopy (top y 0.291 m) covers the servos and fixed swash
	view._show_main_blades(true)
	view.camera.h_offset = 0.0
	view.camera.fov = 34.0
	view.motion.set_smooth(true)
	view._speed_changed(12.0) # the inspector's top presentation speed; real head speed is far higher
	var frames := roundi(seconds * FPS)
	var records := []
	var rejected := 0
	for frame: int in frames:
		var t := float(frame) / FPS
		view.motion.set_controls(_demand(t))
		var before: PackedFloat64Array = view.inputs.duplicate()
		view._advance(1.0 / FPS)
		if view.paused:
			rejected += 1
			view._set_paused(false)
		_place_camera(t)
		if frame % 15 == 0:
			records.append({frame = frame, demand = Array(_demand(t)), inputs = Array(view.inputs),
				moved = view.inputs != before})
		await process_frame
	var manifest := {
		format = "openrc-trailer-hx700-mechanism v1",
		classification = "presentation: advanced HX-700 inspection mechanism, scripted demand; not flight physics",
		frames = frames, fps = FPS, seconds = seconds, rejected_steps = rejected,
		engine = Engine.get_version_info().string, movie = Engine.get_write_movie_path(),
		rotor_rpm = 12.0, records = records,
	}
	var file := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("HX700_MECHANISM_OK frames=%d rejected=%d" % [frames, rejected])
	quit(0 if rejected == 0 else 1)


## Mechanical degrees [collective, roll cyclic, pitch cyclic, tail]: collective rises, the cyclic sweeps
## a circle inside the 10° ring (the swash wobbles), then the tail pitch kicks both ways.
func _demand(t: float) -> PackedFloat64Array:
	var collective := 8.0 * smoothstep(0.0, 1.0, t / 1.0) - 3.0 * smoothstep(3.2, 4.2, t)
	var ring := 7.0 * smoothstep(0.8, 1.4, t) * (1.0 - smoothstep(3.0, 3.6, t))
	var angle := TAU * (t - 0.8) / 1.1
	var tail := 15.0 * sin(PI * clampf((t - 2.6) / 1.6, 0.0, 1.0) * 2.0)
	return PackedFloat64Array([collective, ring * sin(angle), ring * cos(angle), tail])


## Macro push on the exposed head (servos y 0.21 m, swash 0.27 m, grips 0.345 m) while orbiting it.
func _place_camera(t: float) -> void:
	var orbit := smoothstep(0.0, seconds, t)
	var focus := Vector3(0.0, 0.275, 0.0)
	var distance: float = lerpf(0.36, 0.24, orbit)
	var yaw: float = lerpf(0.45, 1.65, orbit)
	# Stay under the blade plane (grips from y 0.325 m): a higher eye let a blade sweep through the lens.
	var elevation: float = lerpf(0.04, 0.12, orbit)
	view.camera.position = focus + distance * Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	view.camera.look_at(focus)
