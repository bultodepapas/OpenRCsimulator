## FW-MOON-03/05 (docs/plans/moon.md): production-rendered moon views. For each case it builds the real World for a
## date, time and place, then renders a close-up aimed at the moon's centre (narrow field of view, so the disc fills a
## good part of the frame) and a wide pilot-height view toward it. Writes PNGs plus manifest.json with the Lunar state.
## Run without --headless (Compatibility needs a renderer); on a machine without a display, under xvfb-run:
##   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
##     --script "$PWD/tools/world/moon_capture.gd" -- --out=/abs/dir [--cases=full_high,crescent] [--views=close,wide]
##     [--close-fov=1.2]
## A composition fixture: no aircraft, no flight; llvmpipe images compare only with the same machine.
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Lunar := preload("res://render/world/lunar.gd")

const VIEW_SIZE := Vector2i(1280, 720)
## Reference field (Conditions.REFERENCE: 40° N, 3.7° W, UTC+2) unless a case says otherwise.
const CASES := {
	full_high = ["--date=2026-12-24", "--time=00:00"],
	harvest_rise = ["--date=2026-09-26", "--time=20:10"],
	harvest_low = ["--date=2026-09-26", "--time=20:25"],
	harvest_high = ["--date=2026-09-26", "--time=23:30"],
	quarter = ["--date=2026-06-23", "--time=00:30"],
	crescent = ["--date=2026-06-18", "--time=23:15"],
	night_preset = ["--time_of_day=night"],
	moonrise_preset = ["--time_of_day=moonrise"], # FW-MOON-11: the solved Moonrise moment
	southern_full = ["--date=2026-08-27", "--time=23:50", "--lat=-34.6037", "--lon=-58.3816", "--utc_offset=-3"],
}
## FW-MOON-05 overlay cases (--cases=svs): whole UT hours with the moon above 25° at night, rendered with celestial
## north up like NASA SVS 5587 frame `frame` (moon.NNNN.jpg, hour of 2026 + 1), for
## research/field-world/fw-moon-05/overlay_svs.py. Six phases at the reference field, two from Buenos Aires.
const SVS_CASES := {
	svs_waxing_crescent = {frame = 548, args = ["--date=2026-01-23", "--time=19:00", "--utc_offset=0"]},
	svs_first_quarter = {frame = 596, args = ["--date=2026-01-25", "--time=19:00", "--utc_offset=0"]},
	svs_waxing_gibbous = {frame = 668, args = ["--date=2026-01-28", "--time=19:00", "--utc_offset=0"]},
	svs_full = {frame = 44, args = ["--date=2026-01-02", "--time=19:00", "--utc_offset=0"]},
	svs_waning_gibbous = {frame = 145, args = ["--date=2026-01-07", "--time=00:00", "--utc_offset=0"]},
	svs_last_quarter = {frame = 220, args = ["--date=2026-01-10", "--time=03:00", "--utc_offset=0"]},
	svs_south_crescent = {frame = 4055, args = ["--date=2026-06-18", "--time=22:00", "--utc_offset=0", "--lat=-34.6037", "--lon=-58.3816"]},
	svs_south_full = {frame = 52, args = ["--date=2026-01-03", "--time=03:00", "--utc_offset=0", "--lat=-34.6037", "--lon=-58.3816"]},
}

## FW-MOON-10 (--cases=eclipse): the total lunar eclipse of 2028-12-31 (greatest 16:52 UT, umbral magnitude 1.246).
## Phases seen from 30° N 90° E, where the moon is high; the moonrise over the reference field at dusk.
const ECLIPSE_CASES := {
	eclipse_a_penumbral = ["--date=2028-12-31", "--time=14:40", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_b_partial = ["--date=2028-12-31", "--time=15:30", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_c_deep_partial = ["--date=2028-12-31", "--time=16:05", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_d_total_start = ["--date=2028-12-31", "--time=16:20", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_e_greatest = ["--date=2028-12-31", "--time=16:52", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_f_partial_out = ["--date=2028-12-31", "--time=17:50", "--utc_offset=0", "--lat=30", "--lon=90"],
	eclipse_moonrise = ["--date=2028-12-31", "--time=17:20", "--utc_offset=0"],
	# The next total eclipse in front of the pilot in full darkness at the reference field (FW-MOON-10 scan).
	eclipse_field_2032 = ["--date=2032-10-18", "--time=19:00", "--utc_offset=0"],
}

var _args: Dictionary = {}
var _viewport: SubViewport
var _field: Dictionary
var _manifest: Array = []
var _failures := 0


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
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.get("ok", false):
		printerr("default field did not validate")
		quit(1)
		return
	_field = loaded.field
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)
	var names: Array = CASES.keys() if not _args.has("cases") else Array(str(_args.cases).split(","))
	if names.has("svs"):
		names.erase("svs")
		names.append_array(SVS_CASES.keys())
	if names.has("eclipse"):
		names.erase("eclipse")
		names.append_array(ECLIPSE_CASES.keys())
	for case_id: String in names:
		if not CASES.has(case_id) and not SVS_CASES.has(case_id) and not ECLIPSE_CASES.has(case_id):
			printerr("unknown case " + case_id)
			_failures += 1
			continue
		await _capture_case(case_id, out)
	var f := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({format = "openrc-moon-capture v1", engine = Engine.get_version_info().string,
		adapter = RenderingServer.get_video_adapter_name(), cases = _manifest}, " ") + "\n")
	f.close()
	quit(1 if _failures > 0 else 0)


func _capture_case(case_id: String, out: String) -> void:
	var svs: Dictionary = SVS_CASES.get(case_id, {})
	var arguments: Array = svs.args if not svs.is_empty() else (ECLIPSE_CASES[case_id] if ECLIPSE_CASES.has(case_id) else CASES[case_id])
	var conditions := Conditions.resolve(PackedStringArray(arguments))
	if not conditions.get("time_of_day", false):
		printerr("conditions did not resolve for " + case_id)
		_failures += 1
		return
	var lunar := Lunar.state(conditions.when)
	var views: Array = []
	for view: Dictionary in [{id = "close", fov = float(_args.get("close-fov", "1.2"))}, {id = "wide", fov = 60.0}]:
		if not _args.has("views") or view.id in str(_args.views).split(","):
			views.append(view)
	for view: Dictionary in views:
		var scene_root := Node3D.new()
		_viewport.add_child(scene_root)
		var built: Dictionary = WorldBuilder.build(scene_root, _field, Callable(), conditions, {}, {field_lighting = "off", campfire = false})
		var env: Environment = built.environment
		var camera := Camera3D.new()
		camera.current = true
		camera.fov = float(view.fov)
		camera.near = 0.1
		camera.far = 45000.0
		var eye := Frames.ned_to_render([0.0, 0.0, -1.7])
		camera.position = eye
		scene_root.add_child(camera)
		var az := deg_to_rad(float(lunar.azimuth_deg))
		var el := deg_to_rad(float(lunar.elevation_deg))
		var toward := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()
		# Overlay cases put celestial north up (the pole's direction at this latitude), as NASA's frames do.
		var lat := deg_to_rad(float(conditions.when.latitude_deg))
		var up := Frames.ned_to_render([cos(lat), 0.0, -sin(lat)]).normalized() if not svs.is_empty() else Vector3.UP
		camera.look_at(eye + toward * 1000.0, up)
		WorldBuilder.update(env, 0.0, Vector3.ZERO)
		for i in 6:
			await process_frame
			RenderingServer.force_draw(false)
		var image := _viewport.get_texture().get_image()
		var file_name := "%s-%s.png" % [case_id, view.id]
		if image == null or image.is_empty() or image.save_png(out.path_join(file_name)) != OK:
			printerr("could not capture " + file_name)
			_failures += 1
		else:
			print("captured " + file_name)
		_manifest.append({case_id = case_id, view = view.id, file = file_name, fov_deg = view.fov,
			arguments = arguments, svs_frame = svs.get("frame", 0), north_up = not svs.is_empty(), when = conditions.when, exposure = env.tonemap_exposure,
			light_source = Atmosphere.state.get("light_source", ""), shadow_strength = Atmosphere.state.get("shadow_strength", 1.0),
			moon = {azimuth_deg = lunar.azimuth_deg, elevation_deg = lunar.elevation_deg, illuminated = lunar.illuminated,
				phase_angle_deg = lunar.phase_angle_deg, distance_km = lunar.distance_km, radius_deg = lunar.radius_deg,
				bright_limb_deg = lunar.bright_limb_deg, parallactic_deg = lunar.parallactic_deg,
				libration_lon_deg = lunar.libration_lon_deg, libration_lat_deg = lunar.libration_lat_deg,
				earthshine = lunar.earthshine, umbral_magnitude = lunar.eclipse.umbral_magnitude}})
		scene_root.queue_free()
		await process_frame
