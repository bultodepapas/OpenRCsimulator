# VQ-05 evidence: studio renders of one catalog propeller aircraft across rotor speeds, with self-checks.
# Needs a renderer (run under Xvfb, see docs/TOOLS.md):
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path app --resolution 1920x1080 --rendering-driver opengl3 --audio-driver Dummy \
#     --script res://tests/capture_propeller_blur.gd -- --out=/abs/dir [--aircraft=<catalog id>] \
#     [--rpm=0,300,600,1200,2400,6000] [--view=quarter|front|side|rear] [--angle=<blade angle, deg>]
# Writes <out>/<aircraft>-<view>-rpm<n>.png, pristine and no-propeller references, and <out>/<aircraft>-<view>.json
# (hashes, blur fractions, pixel statistics and checks); exits 1 when a check fails. Checks: attaching the blur and
# updating it at 0 rpm leaves the picture byte-identical; the blade change against the no-propeller reference falls
# as the speed rises while the disc changes pixels outside the blade silhouette; a repeated frame is byte-identical.
# Software rendering proves pixels and repeatability, not GPU cost or how the disc reads on the pilot's monitor.
# Use a new absolute output directory. Repeat-a/b images retain strict-equality failures for diagnosis.
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const Blur := preload("res://render/propeller_blur.gd")
const Frames := preload("res://render/frames.gd")
const Spec := preload("res://spec.gd")

## Camera azimuth from the nose (deg, positive toward the right wing) and elevation above the propeller axis (deg).
const VIEWS := {front = Vector2(8.0, 6.0), quarter = Vector2(40.0, 15.0), side = Vector2(90.0, 10.0), rear = Vector2(140.0, 20.0)}
const DISTANCE_RADII := 4.5
const FOV_DEG := 35.0
## Per-channel change that counts as a changed pixel.
const DIFF := 0.04
const MARGIN_PX := 8

var _out := ""
var _aircraft: String = AirplaneBuilder.STIK_ID
var _rpms := PackedFloat64Array([0.0, 300.0, 600.0, 1200.0, 2400.0, 6000.0])
var _view := "quarter"
var _angle_deg := 25.0
var _checks: Array = []


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String) -> void:
	_checks.append({check = label, ok = ok, detail = detail})
	print("%s %s: %s" % ["ok  " if ok else "FAIL", label, detail])


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("propeller capture requires a native renderer")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--aircraft="):
			_aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--rpm="):
			_rpms = PackedFloat64Array()
			for value in arg.trim_prefix("--rpm=").split(","):
				_rpms.append(float(value))
		elif arg.begins_with("--view="):
			_view = arg.trim_prefix("--view=")
		elif arg.begins_with("--angle="):
			_angle_deg = float(arg.trim_prefix("--angle="))
	if _out.is_empty() or not _out.is_absolute_path() or DirAccess.dir_exists_absolute(_out) or FileAccess.file_exists(_out) or not VIEWS.has(_view) or _rpms.is_empty():
		printerr("usage: --out=<new absolute directory> [--aircraft=<id>] [--rpm=a,b,c] [--view=%s] [--angle=deg]" % ",".join(VIEWS.keys()))
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("could not create capture directory: " + _out)
		quit(2)
		return
	await process_frame
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Spec.SKY
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Spec.SKY
	environment.environment.ambient_light_energy = 0.6
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	var az := deg_to_rad(float(Spec.ATMOSPHERE.sun_azimuth_deg))
	var el := deg_to_rad(float(Spec.ATMOSPHERE.sun_elevation_deg))
	var toward_sun: Vector3 = Frames.ned_to_render([cos(el) * cos(az), cos(el) * sin(az), -sin(el)])
	sun.look_at_from_position(toward_sun * 10.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Spec.ATMOSPHERE.sun_color
	root.add_child(sun)
	var airplane: Dictionary = AirplaneBuilder.build(_aircraft)
	if airplane.is_empty() or not airplane.get("has_propeller", true):
		printerr("no propeller aircraft: " + _aircraft)
		quit(2)
		return
	root.add_child(airplane.root)
	airplane.propeller.rotation.z = deg_to_rad(_angle_deg)
	var measured: Dictionary = Blur.profile(airplane.propeller, airplane.root)
	var radius: float = measured.radius
	var prop_pose: Transform3D = Blur.relative(airplane.root, airplane.propeller)
	var center: Vector3 = prop_pose.origin
	var view: Vector2 = VIEWS[_view]
	var vaz := deg_to_rad(view.x)
	var vel := deg_to_rad(view.y)
	var camera := Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 0.01
	camera.position = center + Vector3(sin(vaz) * cos(vel), sin(vel), -cos(vaz) * cos(vel)) * DISTANCE_RADII * radius
	root.add_child(camera)
	camera.look_at(center, Vector3.UP)
	camera.current = true
	# Region of interest: the disc's projected circle plus a margin.
	var rect := Rect2(camera.unproject_position(center), Vector2.ZERO)
	for i in 24:
		var t := TAU * i / 24.0
		rect = rect.expand(camera.unproject_position(center + prop_pose.basis * Vector3(cos(t) * radius, sin(t) * radius, 0.0)))
	rect = rect.grow(MARGIN_PX)
	var prefix := "%s/%s-%s" % [_out, _aircraft, _view]
	var pristine := await _grab()
	pristine.save_png(prefix + "-pristine.png")
	var node: Node3D = Blur.attach(airplane, null, root)
	node.update(0.0)
	var at_zero := await _grab()
	at_zero.save_png(prefix + "-rpm0-attached.png")
	_check("attached at 0 rpm is byte-identical", at_zero.get_data() == pristine.get_data(), "pristine vs attached+update(0)")
	airplane.propeller.visible = false
	node.update(_rpms[-1])
	var without := await _grab()
	without.save_png(prefix + "-noprop.png")
	_check("hidden propeller hides the disc", not node._disc.visible and node.blur == 0.0, "disc visible=%s blur=%.2f" % [node._disc.visible, node.blur])
	airplane.propeller.visible = true
	var mask: PackedByteArray = _changed(at_zero, without, rect)
	var mask_count := 0
	for v in mask:
		mask_count += v
	var images: Array = []
	var previous_mad := INF
	var monotone := true
	var last_outside := 0
	for rpm in _rpms:
		node.update(rpm)
		var image := await _grab()
		var path := "%s-rpm%d.png" % [prefix, int(rpm)]
		image.save_png(path)
		var stats := _stats(image, without, rect, mask)
		images.append({image = path.get_file(), rpm = rpm, blur = node.blur, sha256 = FileAccess.get_sha256(path),
			mask_pixels = mask_count, mean_change_on_blades = stats.mad, changed_outside_blades = stats.outside})
		print("rpm %6.0f blur %.3f  mean change on blade pixels %.4f  changed pixels outside blades %d" % [rpm, node.blur, stats.mad, stats.outside])
		if stats.mad > previous_mad + 1e-6:
			monotone = false
		previous_mad = stats.mad
		last_outside = stats.outside
	var first_mad: float = images[0].mean_change_on_blades
	var last_mad: float = images[-1].mean_change_on_blades
	_check("blade change falls with speed", monotone and last_mad < first_mad, "%.4f at %d rpm -> %.4f at %d rpm" % [first_mad, int(_rpms[0]), last_mad, int(_rpms[-1])])
	_check("disc changes pixels outside the blade silhouette", last_outside > 0, "%d pixels at %d rpm" % [last_outside, int(_rpms[-1])])
	# A retained observer must not leave solid blades over its active disc.
	var before_reattach := await _grab()
	root.remove_child(node)
	root.add_child(node)
	node.update(_rpms[-1])
	var after_reattach := await _grab()
	var restored_visibility := true
	for original: MeshInstance3D in node._originals:
		restored_visibility = restored_visibility and original.visible == (node.blur <= 0.0)
	_check("reattachment reapplies blade visibility", restored_visibility, "same RPM after detach/reattach")
	if before_reattach.save_png(prefix + "-before-reattach.png") != OK or after_reattach.save_png(prefix + "-after-reattach.png") != OK:
		printerr("could not retain reattachment evidence")
		quit(2)
		return
	var repeat := await _grab()
	var repeated := await _grab()
	var repeat_a := prefix + "-repeat-a.png"
	var repeat_b := prefix + "-repeat-b.png"
	var saved_a := repeat.save_png(repeat_a)
	var saved_b := repeated.save_png(repeat_b)
	if saved_a != OK or saved_b != OK:
		printerr("could not retain repeated-frame evidence")
		quit(2)
		return
	_check("repeated frame is byte-identical", repeat.get_data() == repeated.get_data(), "two frames at %d rpm; retained repeat-a/b PNGs" % int(_rpms[-1]))
	var summary := {format = "openrc-propeller-blur-capture v1", aircraft = _aircraft, view = _view, blade_angle_deg = _angle_deg,
		viewport = [repeat.get_width(), repeat.get_height()],
		msaa_3d = root.msaa_3d,
		process_id = OS.get_process_id(), captured_utc = Time.get_datetime_string_from_system(true),
		source_sha256 = {capture = FileAccess.get_sha256(get_script().resource_path),
			blur = FileAccess.get_sha256("res://render/propeller_blur.gd")},
		repeat_images = [{image = repeat_a.get_file(), sha256 = FileAccess.get_sha256(repeat_a)},
			{image = repeat_b.get_file(), sha256 = FileAccess.get_sha256(repeat_b)}],
		renderer = {driver = RenderingServer.get_current_rendering_driver_name(), method = RenderingServer.get_current_rendering_method(),
			adapter = RenderingServer.get_video_adapter_name(), api = RenderingServer.get_video_adapter_api_version(), godot = Engine.get_version_info().string},
		profile = {radius_m = measured.radius, hub_radius_m = measured.hub_radius, inner_radius_m = measured.inner_radius, blades = measured.blades,
			plane_z_m = measured.plane_z, coverage = Array(measured.coverage)},
		region_px = [rect.position.x, rect.position.y, rect.size.x, rect.size.y], images = images, checks = _checks}
	var ok := true
	for c in _checks:
		ok = ok and bool(c.ok)
	summary.ok = ok
	var file := FileAccess.open(prefix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "  ") + "\n")
	file.close()
	print("%s: %s" % [prefix + ".json", "all checks passed" if ok else "CHECKS FAILED"])
	quit(0 if ok else 1)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## 1 where `a` and `b` differ by more than DIFF in a channel, over the region (row-major, region size).
func _changed(a: Image, b: Image, rect: Rect2) -> PackedByteArray:
	var out := PackedByteArray()
	var x0 := maxi(int(rect.position.x), 0)
	var y0 := maxi(int(rect.position.y), 0)
	var x1 := mini(int(rect.end.x), a.get_width() - 1)
	var y1 := mini(int(rect.end.y), a.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(1 if _differs(a.get_pixel(x, y), b.get_pixel(x, y)) else 0)
	return out


static func _differs(p: Color, q: Color) -> bool:
	return absf(p.r - q.r) > DIFF or absf(p.g - q.g) > DIFF or absf(p.b - q.b) > DIFF


## Mean absolute change on mask pixels and the count of changed pixels outside the mask, against `reference`.
func _stats(image: Image, reference: Image, rect: Rect2, mask: PackedByteArray) -> Dictionary:
	var x0 := maxi(int(rect.position.x), 0)
	var y0 := maxi(int(rect.position.y), 0)
	var x1 := mini(int(rect.end.x), image.get_width() - 1)
	var y1 := mini(int(rect.end.y), image.get_height() - 1)
	var sum := 0.0
	var on := 0
	var outside := 0
	var i := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := image.get_pixel(x, y)
			var q := reference.get_pixel(x, y)
			if mask[i] != 0:
				sum += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
				on += 1
			elif _differs(p, q):
				outside += 1
			i += 1
	return {mad = sum / maxi(on, 1), outside = outside}
