# DR-31 (VIS-01…04 math): the rigid FPV camera of FPV/04 §1 through the render conversion. Known answers: at level
# attitude and 40° uptilt the camera looks along body (0.7660, 0, −0.6428) with up (−0.6428, 0, −0.7660); a 90° roll
# rolls the picture with the craft (no horizon lock); an inverted craft inverts it; a mount offset moves the origin by
# C(R r); the basis is orthonormal; tilt 0 looks along the nose. Horizontal FOV 120° gives 88.507155° vertical at
# 16:9 and 104.821821° at 4:3. Renderer-free: real 1080p projection and clipping need a native capture.
extends SceneTree

const Cam := preload("res://vehicles/multirotor/multirotor_camera.gd")
const Frames := preload("res://render/frames.gd")

const EPS := 1.0e-4

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


## Body FRD vector in render axes for a level craft heading north (C applied to the body vector).
static func _render(frd: Array) -> Vector3:
	return Frames.ned_to_render(frd)


static func _near(a: Vector3, b: Vector3, eps := EPS) -> bool:
	return a.distance_to(b) <= eps


static func _quat_axis(axis_frd: Array, angle: float) -> PackedFloat64Array:
	var s := sin(0.5 * angle)
	return PackedFloat64Array([cos(0.5 * angle), axis_frd[0] * s, axis_frd[1] * s, axis_frd[2] * s])


func _orthonormal(t: Transform3D) -> bool:
	var b := t.basis
	return absf(b.x.length() - 1.0) < EPS and absf(b.y.length() - 1.0) < EPS and absf(b.z.length() - 1.0) < EPS \
		and absf(b.x.dot(b.y)) < EPS and absf(b.y.dot(b.z)) < EPS and absf(b.z.dot(b.x)) < EPS \
		and absf(b.determinant() - 1.0) < EPS


## Chase framing: its own 62° lens, 1.2–1.8 m from the CG, above it, the 0.3 m airframe at least a sixth of the
## picture height; terrain clamp; pilot zoom keeps the quad readable at 20–40 m.
func _inspection_views(view: RefCounted, pose: PackedFloat64Array, mount: PackedFloat64Array) -> void:
	var target := Vector3(3.0, 2.0, -5.0)
	var placed: Dictionary = Cam.chase_placement(target, 0.7)
	var eye: Vector3 = placed.eye
	var distance := eye.distance_to(target)
	_check("chase eye 1.2–1.8 m from the CG and above it", distance >= 1.2 and distance <= 1.8 and eye.y > target.y + 0.2,
		"distance %.3f height %.3f" % [distance, eye.y - target.y])
	var behind := Vector2(eye.x - target.x, eye.z - target.z).normalized()
	_check("chase eye behind the heading", behind.distance_to(Vector2(-sin(0.7), cos(0.7))) < 1.0e-5)
	_check("chase lens 60–70° vertical", Cam.CHASE_VFOV_DEG >= 60.0 and Cam.CHASE_VFOV_DEG <= 70.0)
	var share := rad_to_deg(2.0 * atan(0.15 / distance)) / Cam.CHASE_VFOV_DEG
	_check("the 0.3 m airframe spans at least a sixth of the chase picture height", share >= 1.0 / 6.0, "%.3f" % share)
	view.view = 1
	view.update(pose, mount, 0.016, func(_x: float, _z: float) -> float: return 50.0)
	_check("chase uses its own lens, not the FPV one", is_equal_approx(view.camera.fov, Cam.CHASE_VFOV_DEG))
	_check("chase eye is clamped above the terrain", view.camera.global_position.y >= 50.0 + Cam.EYE_CLEARANCE_M - 1.0e-4,
		str(view.camera.global_position))
	view.view = 0
	for d: float in [20.0, 30.0, 40.0]:
		var vfov := Cam.pilot_vfov_deg(d)
		var quad_share := rad_to_deg(2.0 * atan(0.15 / d)) / vfov
		_check("pilot view at %d m: the airframe spans %.0f%% of the picture height (>= 10%%)" % [int(d), 100.0 * quad_share],
			quad_share >= 0.10 and vfov >= Cam.PILOT_VFOV_MIN_DEG)


## The OSD artificial horizon through the camera in use (normalized half-height units, b up).
func _horizon() -> void:
	var level := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	for case: Array in [[40.0, 88.507155], [40.0, 60.0], [0.0, 70.0], [25.0, 100.0]]:
		var tilt := deg_to_rad(case[0])
		var vfov := deg_to_rad(case[1])
		var h := Cam.horizon_line(level, tilt, vfov, 16.0 / 9.0)
		var expected := -tan(tilt) / tan(0.5 * vfov)
		_check("level, tilt %d°, vertical FOV %.1f°: horizon tan θ / tan(f/2) = %.4f below the centre" % [int(case[0]), case[1], -expected],
			bool(h.valid) and absf(h.point.y - expected) < 1.0e-5 and absf(h.point.x) < 1.0e-6 and absf(h.angle) < 1.0e-6,
			str(h))
		_check("  visible exactly when inside the picture", bool(h.visible) == (absf(expected) < 1.0), str(h.visible))
	var roll := Cam.horizon_line(_quat_axis([1.0, 0.0, 0.0], deg_to_rad(30.0)), 0.0, deg_to_rad(70.0), 16.0 / 9.0)
	_check("a 30° right roll rotates the horizon by +30° (right side up) through the centre",
		absf(roll.angle - deg_to_rad(30.0)) < 1.0e-6 and roll.point.length() < 1.0e-6, str(roll))
	var inverted := Cam.horizon_line(_quat_axis([1.0, 0.0, 0.0], PI), 0.0, deg_to_rad(70.0), 16.0 / 9.0)
	_check("inverted flips it: angle 180° (sky below the line)", absf(absf(inverted.angle) - PI) < 1.0e-6 and inverted.point.length() < 1.0e-6,
		str(inverted))
	var inverted_tilt := Cam.horizon_line(_quat_axis([1.0, 0.0, 0.0], PI), deg_to_rad(40.0), deg_to_rad(88.507155), 16.0 / 9.0)
	_check("inverted with uptilt: the line stays tan θ / T below the centre, flipped",
		absf(inverted_tilt.point.y + tan(deg_to_rad(40.0)) / tan(deg_to_rad(44.2535775))) < 1.0e-5 and absf(absf(inverted_tilt.angle) - PI) < 1.0e-6,
		str(inverted_tilt))
	var nose_down := Cam.horizon_line(_quat_axis([0.0, 1.0, 0.0], deg_to_rad(-40.0)), deg_to_rad(40.0), deg_to_rad(70.0), 16.0 / 9.0)
	_check("40° nose-down pitch cancels a 40° uptilt: the horizon crosses the centre", absf(nose_down.point.y) < 1.0e-6
		and bool(nose_down.visible), str(nose_down))
	var yawed := Cam.horizon_line(_quat_axis([0.0, 0.0, 1.0], 1.3), deg_to_rad(40.0), deg_to_rad(70.0), 16.0 / 9.0)
	_check("heading does not move the horizon", absf(yawed.point.y + tan(deg_to_rad(40.0)) / tan(deg_to_rad(35.0))) < 1.0e-5)
	var straight_up := Cam.horizon_line(_quat_axis([0.0, 1.0, 0.0], deg_to_rad(50.0)), deg_to_rad(40.0), deg_to_rad(70.0), 16.0 / 9.0)
	_check("a camera looking straight up has no horizon line", not bool(straight_up.valid))
	# Cross-check with the camera transform: a level world direction projects onto the returned line.
	var q := PackedFloat64Array([0.93, 0.21, -0.17, 0.25])
	var t := Cam.fpv_transform(PackedFloat64Array([0.0, 0.0, 0.0]), q, PackedFloat64Array([0.0, 0.0, 0.0]), deg_to_rad(35.0))
	var vfov_x := deg_to_rad(80.0)
	var h_x := Cam.horizon_line(q, deg_to_rad(35.0), vfov_x, 16.0 / 9.0)
	var forward := -t.basis.z
	var level_dir := Vector3(forward.x, 0.0, forward.z).normalized().rotated(Vector3.UP, 0.2)
	var local := t.basis.inverse() * level_dir
	var a := local.x / (-local.z * tan(0.5 * vfov_x))
	var b := local.y / (-local.z * tan(0.5 * vfov_x))
	var along := Vector2(cos(h_x.angle), sin(h_x.angle))
	var offset := Vector2(a, b) - (h_x.point as Vector2)
	_check("an arbitrary attitude: a level direction projects onto the horizon line", absf(offset.cross(along)) < 1.0e-4,
		"%.6f" % offset.cross(along))


func _run() -> void:
	var origin := PackedFloat64Array([0.0, 0.0, 0.0])
	var level := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var no_mount := PackedFloat64Array([0.0, 0.0, 0.0])
	var tilt := deg_to_rad(40.0)
	var t := Cam.fpv_transform(origin, level, no_mount, tilt)
	var forward := -t.basis.z
	var up := t.basis.y
	_check("40° tilt forward = C(0.7660, 0, -0.6428)", _near(forward, _render([0.7660444, 0.0, -0.6427876])), str(forward))
	_check("40° tilt up = C(-0.6428, 0, -0.7660)", _near(up, _render([-0.6427876, 0.0, -0.7660444])), str(up))
	_check("positive tilt looks up in the render frame", forward.y > 0.6 and forward.z < -0.7, str(forward))
	_check("level basis orthonormal and right-handed", _orthonormal(t))
	var t0 := Cam.fpv_transform(origin, level, no_mount, 0.0)
	_check("tilt 0 looks along the nose (render -Z) with body up", _near(-t0.basis.z, Vector3(0, 0, -1)) and _near(t0.basis.y, Vector3.UP))
	# 90° right roll about body x (right side down): the craft's top, and the camera's up, now point east = render +X.
	var rolled := Cam.fpv_transform(origin, _quat_axis([1.0, 0.0, 0.0], PI / 2.0), no_mount, 0.0)
	_check("90° right roll rolls the camera with the craft", _near(rolled.basis.y, Vector3(1, 0, 0)) and _near(-rolled.basis.z, Vector3(0, 0, -1)),
		str(rolled.basis))
	var rolled_tilt := Cam.fpv_transform(origin, _quat_axis([1.0, 0.0, 0.0], PI / 2.0), no_mount, tilt)
	var expected_forward := Vector3(sin(tilt), 0.0, -cos(tilt)) # the uptilt now leans toward the craft's top = render +X
	_check("90° roll carries the uptilt sideways (no horizon lock)", _near(-rolled_tilt.basis.z, expected_forward), str(-rolled_tilt.basis.z))
	var inverted := Cam.fpv_transform(origin, _quat_axis([1.0, 0.0, 0.0], PI), no_mount, tilt)
	_check("inverted craft: camera up points down", inverted.basis.y.y < -0.7, str(inverted.basis.y))
	_check("inverted craft: uptilt looks toward the ground", (-inverted.basis.z).y < -0.6, str(-inverted.basis.z))
	_check("inverted basis orthonormal", _orthonormal(inverted))
	# Mount offset: origin moves by C(R r). Heading 90° (east) yaw about body z; r = 0.06 forward, 0.011 up.
	var yaw := _quat_axis([0.0, 0.0, 1.0], PI / 2.0)
	var position := PackedFloat64Array([10.0, -4.0, -2.5])
	var mount := PackedFloat64Array([0.06, 0.0, -0.011])
	var mounted := Cam.fpv_transform(position, yaw, mount, tilt)
	var expected_origin := Frames.ned_to_render([10.0, -4.0 + 0.06, -2.5 - 0.011])
	_check("mount offset moves the origin by C(R r)", _near(mounted.origin, expected_origin, 1.0e-5), "%s vs %s" % [mounted.origin, expected_origin])
	var yaw_forward := -mounted.basis.z
	_check("heading east: tilted forward points to render +X and up", _near(yaw_forward, Vector3(cos(tilt), sin(tilt), 0.0)), str(yaw_forward))
	_check("yawed basis orthonormal", _orthonormal(mounted))
	var arbitrary := PackedFloat64Array([0.7, 0.2, -0.4, 0.55])
	_check("arbitrary attitude (unnormalized quaternion) gives an orthonormal basis", _orthonormal(Cam.fpv_transform(position, arbitrary, mount, tilt)))
	var v169 := Cam.vertical_fov_deg(120.0, 16.0 / 9.0)
	var v43 := Cam.vertical_fov_deg(120.0, 4.0 / 3.0)
	_check("vertical FOV 120° at 16:9 = 88.507155°", absf(v169 - 88.507155) < 1.0e-5, "%.6f" % v169)
	_check("vertical FOV 120° at 4:3 = 104.821821°", absf(v43 - 104.821821) < 1.0e-5, "%.6f" % v43)
	# The view controller: one top-level, non-interpolated camera; tilt/FOV bounds.
	var holder := Node3D.new()
	root.add_child(holder)
	var view := Cam.new()
	var camera: Camera3D = view.build(holder, 21000.0)
	_check("camera is top-level and excluded from engine physics interpolation",
		camera.top_level and camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and not physics_interpolation,
		"tree interpolation %s" % physics_interpolation)
	_check("near plane %.3f m" % Cam.NEAR_M, is_equal_approx(camera.near, Cam.NEAR_M))
	view.tilt_deg = 55.0
	view.adjust_tilt(2)
	_check("tilt clamps at 60°", view.tilt_deg == 60.0)
	view.hfov_deg = 95.0
	view.adjust_fov(-3)
	_check("FOV clamps at 90°", view.hfov_deg == 90.0)
	view.hfov_deg = 120.0
	view.tilt_deg = 40.0
	var pose := PackedFloat64Array([0.0, 0.0, -2.0, 0, 0, 0, 1.0, 0.0, 0.0, 0.0, 0, 0, 0])
	view.update(pose, mount, 0.016, Callable())
	var aspect: float = view.aspect()
	_check("FPV camera FOV follows the content aspect", absf(camera.fov - Cam.vertical_fov_deg(120.0, aspect)) < 1.0e-3,
		"fov %.4f aspect %.4f" % [camera.fov, aspect])
	var direct := Cam.fpv_transform(PackedFloat64Array([0.0, 0.0, -2.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), mount, deg_to_rad(40.0))
	_check("FPV view places the camera exactly at the rigid mount (no smoothing)", camera.global_transform.is_equal_approx(direct))
	_inspection_views(view, pose, mount)
	holder.free()
	_horizon()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
