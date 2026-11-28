## CAM-FPV-02a. Default stock Stik paint: startup, and the four look stops with the prop fading or at speed.
extends SceneTree

const Flight := preload("res://main.gd")
const Gimbal := preload("res://render/camera/fpv_gimbal.gd")
const Mounts := preload("res://render/camera/fpv_stock_mounts.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")
const SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://fpv-nose")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if not out.is_absolute_path() or DisplayServer.get_name() == "headless":
		_fail("requires a renderer and an absolute output directory")
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot create output directory")
		return
	if root.size != SIZE:
		root.size = SIZE
		await process_frame
	if root.size != SIZE or Vector2i(root.get_visible_rect().size) != SIZE or not is_equal_approx(root.scaling_3d_scale, 1.0):
		_fail("requires a native 1920x1080 viewport at 1:1 render scale")
		return

	var flight := Flight.new()
	# Normal flight startup owns both the model and camera. Shadows are separate world cues.
	flight.set_user_args(PackedStringArray(["--view=fpv", "--shadow=off", "--engine_shadows=off",
			"--physics-backend=gdscript_reference", "--soundscape=off", "--smoke=off"]))
	root.add_child(flight)
	if not flight.startup_complete or not flight.startup_error.is_empty() or not is_instance_valid(flight.session) \
			or not flight.session.is_flyable() or flight._rig == null or flight._rig.view != "fpv":
		_fail("stock flight did not start in FPV: " + flight.startup_error)
		return
	var camera := flight._camera
	var model: Node3D = flight._airplane.root
	var front := Mounts.front(flight._airplane)
	if front.is_empty() or not model.is_visible_in_tree() or root.get_camera_3d() != camera \
			or flight.session.sim.tick != 0:
		_fail("the first frame requires the admitted, visible Stik and its current nose camera at tick zero")
		return
	var optical: Transform3D = model.global_transform * front.mount
	if not camera.global_transform.is_equal_approx(optical) or not is_equal_approx(camera.near, front.near_m):
		_fail("camera startup pose or near plane differs from the installed nose")
		return
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	flight.set_overlays_visible(false)
	var blur := flight.get_node_or_null("PropellerBlur") as PropellerBlur
	if blur == null or not blur.is_visible_in_tree() or blur._disc == null \
			or blur._disc.mesh == null or blur._disc.mesh.get_surface_count() == 0:
		_fail("the installed propeller must supply a drawable blur disc")
		return
	if not await _clear_frame(model, blur, "startup", out):
		return

	# Positive control: look at the same Stik from outside. A hidden, absent or unrendered
	# model would otherwise produce an identical pair at the nose and pass the comparison.
	camera.global_position = model.to_global(Vector3(0, 0.45, 2.1))
	camera.look_at(model.global_position, model.global_basis.y)
	var exterior_hidden := await _without_aircraft(model, blur)
	var exterior_visible := await _grab()
	if not _full_size(exterior_hidden) or not _full_size(exterior_visible):
		_fail("missing full-size exterior control readback")
		return
	var changed := 0
	for y in range(SIZE.y / 4, SIZE.y * 3 / 4, 8):
		for x in range(SIZE.x / 4, SIZE.x * 3 / 4, 8):
			var difference := exterior_visible.get_pixel(x, y) - exterior_hidden.get_pixel(x, y)
			if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.04:
				changed += 1
	if changed < 64 or flight.session.sim.tick != 0:
		_fail("exterior visibility control or frozen tick failed (changed samples: %d)" % changed)
		return

	var sim: Node = flight.session.sim
	flight.session.input_enabled = false
	sim.set_paused(false)
	var travel: Vector2 = front.look_limits_deg
	if not flight._rig.can_drag_fpv() or travel.x <= 0.0 or travel.y <= 0.0:
		_fail("the installed gimbal must have yaw and pitch travel")
		return
	# Allow enough accepted ticks to reach the opposite stops from any previous corner.
	var steps := ceili(2.0 * maxf(travel.x, travel.y) / (Gimbal.RATE_DEG_S * sim.dt())) + 1
	var midpoint_rpm := (PropellerBlur.BLUR_START_HZ + PropellerBlur.BLUR_FULL_HZ) * 30.0 / float(blur.measured.blades)
	for yaw: float in [-travel.x, travel.x]:
		for pitch: float in [-travel.y, travel.y]:
			var tick: int = sim.tick
			flight._rig.drag(Vector2(yaw, pitch if flight._rig.orbit.invert_y else -pitch) * 1000.0)
			flight._rig.seal_fpv_input_after(tick)
			for i in steps:
				sim.step()
			# Exercise the installed sibling observer and its meshes at controlled presentation RPM.
			for rpm: float in [midpoint_rpm, 6000.0]:
				var phase := fposmod(TAU * rpm / 60.0 * sim.time(), TAU)
				flight._render_pose(flight._pose_of(sim.state), flight.session.surfaces(), phase)
				var at_stop: Transform3D = model.global_transform * front.mount
				at_stop.basis *= Basis(Vector3.DOWN, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
				if sim.tick != tick + steps or not camera.global_transform.is_equal_approx(at_stop):
					_fail("rendered lens did not reach yaw %s pitch %s" % [yaw, pitch])
					return
				blur.update(rpm)
				var fading := rpm == midpoint_rpm
				if not blur._disc.is_visible_in_tree() or not is_equal_approx(blur.blur, 0.5 if fading else 1.0) \
						or not blur.global_transform.is_equal_approx(flight._airplane.propeller.global_transform) \
						or blur._blade_copies.is_empty() or blur._blade_copies[0].is_visible_in_tree() != fading:
					_fail("blur disc and blade copies did not reach the expected state at %.0f RPM" % rpm)
					return
				if not await _clear_frame(model, blur, "yaw %s pitch %s at %.0f RPM" % [yaw, pitch, rpm]):
					return
	print("FPV nose pixels passed at 1920x1080")
	quit()


func _clear_frame(model: Node3D, blur: Node3D, label: String, out := "") -> bool:
	var visible := await _grab()
	var repeated := await _grab()
	var hidden := await _without_aircraft(model, blur)
	if not _full_size(visible) or not _full_size(repeated) or not _full_size(hidden) or not _has_contrast(hidden):
		_fail(label + ": missing 1920x1080 field image with contrast")
		return false
	if not out.is_empty() and (visible.save_png(out.path_join("visible.png")) != OK \
			or repeated.save_png(out.path_join("visible-repeat.png")) != OK \
			or hidden.save_png(out.path_join("hidden.png")) != OK):
		_fail("failed to save nose readbacks")
		return false
	var reference := visible.get_data()
	return _compare_pixels(reference, repeated.get_data(), label + " visible/repeat") \
			and _compare_pixels(reference, hidden.get_data(), label + " visible/hidden")


## Frozen RTX 3090 Compatibility readbacks can differ by one 8-bit RGB level.
## Apply the same bound to every pixel of the unchanged control and the aircraft comparison.
func _compare_pixels(reference: PackedByteArray, candidate: PackedByteArray, label: String) -> bool:
	var changed := 0
	if reference != candidate:
		for offset in range(0, reference.size(), 4):
			if reference.decode_u32(offset) == candidate.decode_u32(offset):
				continue
			changed += 1
			if reference[offset + 3] != candidate[offset + 3] \
					or absi(reference[offset] - candidate[offset]) > 1 \
					or absi(reference[offset + 1] - candidate[offset + 1]) > 1 \
					or absi(reference[offset + 2] - candidate[offset + 2]) > 1:
				var pixel := offset / 4
				_fail("%s: pixel (%d, %d) RGBA %s → %s" % [label, pixel % SIZE.x, pixel / SIZE.x,
						reference.slice(offset, offset + 4), candidate.slice(offset, offset + 4)])
				return false
	print("%s: %d pixels differed by one RGB level, alpha matched" % [label, changed])
	return true


## The rotor observer is a sibling of the aircraft. Hide both roots without changing the
## disc, hub or fading blades selected for this RPM, then restore the same configuration.
func _without_aircraft(model: Node3D, blur: Node3D) -> Image:
	model.hide()
	blur.hide()
	var background := await _grab()
	blur.show()
	model.show()
	return background


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null and image.get_format() == Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _full_size(frame: Image) -> bool:
	return frame != null and not frame.is_empty() and frame.get_size() == SIZE and frame.get_format() == Image.FORMAT_RGBA8


func _has_contrast(frame: Image) -> bool:
	var darkest := 1.0
	var brightest := 0.0
	for y in range(32, SIZE.y, 64):
		for x in range(32, SIZE.x, 64):
			var luminance := frame.get_pixel(x, y).get_luminance()
			darkest = minf(darkest, luminance)
			brightest = maxf(brightest, luminance)
	return brightest - darkest > 0.08


func _fail(message: String) -> void:
	printerr("FPV nose pixels failed: ", message)
	quit(1)
