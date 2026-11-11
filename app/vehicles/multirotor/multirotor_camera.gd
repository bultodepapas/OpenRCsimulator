## DR-31: FPV quad cameras. Static, renderer-free math for the rigid FPV mount (FPV/04 §1) plus a small view
## controller for the activity's single Camera3D. The activity computes ONE interpolated pose per frame and hands the
## same pose to the visual and to update(); this node never interpolates on its own (top-level, engine physics
## interpolation off). Views: "fpv" (rigid mount, full body roll, no stabilisation, smoothing or added latency),
## "chase" and "pilot" (line of sight from the field's pilot station) for inspection. Presentation only.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const CameraMath = preload("res://render/camera/camera_math.gd")

const VIEWS := ["fpv", "chase", "pilot"]
const TILT_MIN_DEG := 0.0
const TILT_MAX_DEG := 60.0
const HFOV_MIN_DEG := 90.0
const HFOV_MAX_DEG := 150.0
const TILT_STEP_DEG := 5.0
const HFOV_STEP_DEG := 5.0
## Near plane (m). The FPV mount sits 6 cm ahead of the CG; at 0° tilt the nearest visible surfaces in view are the
## front propeller discs about 3 to 8 cm away and slightly below the lens. 1.5 cm keeps them unclipped at every tilt
## while the reverse-Z depth buffer keeps far terrain stable; the inspection views use the same plane.
const NEAR_M := 0.015
## Chase framing (inspection view, its own lens, not the FPV one): 1.3 m behind and 0.35 m above the CG along the
## smoothed heading, a 62° vertical FOV, aimed 0.12 m above the CG so the 0.3 m airframe and its props fill about a
## fifth of the picture height in the lower half and the horizon stays in view.
const CHASE_BACK_M := 1.3
const CHASE_UP_M := 0.35
const CHASE_AIM_UP_M := 0.12
const CHASE_VFOV_DEG := 62.0
## Minimum eye clearance above the terrain in the inspection views (m).
const EYE_CLEARANCE_M := 0.15
## Pilot (line of sight) zoom: the vertical FOV keeps PILOT_FRAME_M of scene height across the picture at the quad's
## distance (the 0.3 m airframe spans about 15 % of the picture height), within the lens limits below; beyond about
## 29 m the 4° limit lets it shrink slowly (11 % at 40 m).
const PILOT_FRAME_M := 2.0
const PILOT_VFOV_MIN_DEG := 4.0
const PILOT_VFOV_MAX_DEG := 70.0

var camera: Camera3D
var view := 0
var tilt_deg := 40.0
var hfov_deg := 120.0
var pilot_eye := Vector3.ZERO
var _chase_heading := 0.0
var _snap := true


## Rigid FPV camera: p = C(p_N + R_NB r_B); forward C R_NB (cos θ, 0, −sin θ); up C R_NB (−sin θ, 0, −cos θ).
## position_ned: CG (m, NED); attitude: body-to-NED quaternion [w, x, y, z]; mount_frd: CG-to-lens offset (m, FRD);
## tilt_rad: positive uptilt. Camera −Z looks forward and +Y is up; the basis is orthonormal.
static func fpv_transform(position_ned: PackedFloat64Array, attitude: PackedFloat64Array, mount_frd: PackedFloat64Array,
		tilt_rad: float) -> Transform3D:
	var c := cos(tilt_rad)
	var s := sin(tilt_rad)
	var offset := rotate(attitude, mount_frd)
	var p := Frames.ned_to_render([position_ned[0] + offset[0], position_ned[1] + offset[1], position_ned[2] + offset[2]])
	var f := rotate(attitude, PackedFloat64Array([c, 0.0, -s]))
	var u := rotate(attitude, PackedFloat64Array([-s, 0.0, -c]))
	var forward := Frames.ned_to_render([f[0], f[1], f[2]]).normalized()
	var up := Frames.ned_to_render([u[0], u[1], u[2]])
	up = (up - forward * up.dot(forward)).normalized()
	var z := -forward
	var x := up.cross(z).normalized()
	return Transform3D(Basis(x, up, z), p)


## v rotated by the unit quaternion q = [w, x, y, z] (body to NED), in 64-bit floats.
static func rotate(q: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	var n := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	var w := q[0] / n
	var x := q[1] / n
	var y := q[2] / n
	var z := q[3] / n
	var r00 := 1.0 - 2.0 * (y * y + z * z)
	var r01 := 2.0 * (x * y - w * z)
	var r02 := 2.0 * (x * z + w * y)
	var r10 := 2.0 * (x * y + w * z)
	var r11 := 1.0 - 2.0 * (x * x + z * z)
	var r12 := 2.0 * (y * z - w * x)
	var r20 := 2.0 * (x * z - w * y)
	var r21 := 2.0 * (y * z + w * x)
	var r22 := 1.0 - 2.0 * (x * x + y * y)
	return PackedFloat64Array([r00 * v[0] + r01 * v[1] + r02 * v[2], r10 * v[0] + r11 * v[1] + r12 * v[2],
		r20 * v[0] + r21 * v[1] + r22 * v[2]])


## Artificial-horizon line of the rigid FPV camera (the OSD "AH"): where the true horizon plane through the lens
## (directions with no world vertical component) crosses the picture. Screen coordinates are normalized by the half
## picture height: a = right, b = UP, the centre is (0, 0), the visible picture spans |a| <= aspect and |b| <= 1, and
## pixel = centre + (a, -b) * height / 2 for a pinhole of vertical FOV `vfov_rad` (Godot KEEP_HEIGHT).
## With g = world down in camera axes (x right, y up, z forward) and T = tan(vfov / 2), a direction (aT, bT, 1) is
## level when g_x a + g_y b = -g_z / T. Returns {valid (false when the camera looks straight up or down), point
## (Vector2 a, b of the line point nearest the centre), angle (rad, counter-clockwise in a-b axes, chosen so the sky
## lies to the left of the direction: 0 for a level craft, +30° for a 30° right roll, 180° inverted), visible (the
## line crosses the picture)}. Level craft with uptilt θ: point (0, -tan θ / T), i.e. tan θ / T below the centre.
static func horizon_line(attitude: PackedFloat64Array, tilt_rad: float, vfov_rad: float, aspect: float) -> Dictionary:
	var n := sqrt(attitude[0] * attitude[0] + attitude[1] * attitude[1] + attitude[2] * attitude[2] + attitude[3] * attitude[3])
	var w := attitude[0] / n
	var x := attitude[1] / n
	var y := attitude[2] / n
	var z := attitude[3] / n
	# World down (NED +D) in body FRD axes: the third row of the body-to-NED rotation.
	var d0 := 2.0 * (x * z - w * y)
	var d1 := 2.0 * (y * z + w * x)
	var d2 := 1.0 - 2.0 * (x * x + y * y)
	var c := cos(tilt_rad)
	var s := sin(tilt_rad)
	var gx := d1
	var gy := -s * d0 - c * d2
	var gz := c * d0 - s * d2
	var length := sqrt(gx * gx + gy * gy)
	var t := tan(0.5 * vfov_rad)
	if length < 1.0e-6 or not is_finite(t) or t <= 0.0:
		return {valid = false, point = Vector2.ZERO, angle = 0.0, visible = false}
	var k := -gz / (t * length * length)
	var point := Vector2(gx * k, gy * k)
	# Sky normal s = -(gx, gy) / |n|; the direction e has s on its left: e = (s_y, -s_x).
	var angle := atan2(gx / length, -gy / length)
	var half := Vector2(aspect, 1.0)
	var sides := 0
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		sides |= 1 if gx * corner.x + gy * corner.y + gz / t >= 0.0 else 2
	return {valid = true, point = point, angle = angle, visible = sides == 3}


## Vertical FOV (deg) that gives `hfov_deg` horizontally at `aspect` (width / height): 2·atan(tan(hfov/2)/aspect).
static func vertical_fov_deg(horizontal_deg: float, aspect: float) -> float:
	return CameraMath.vertical_fov(horizontal_deg, aspect)


## The one camera of the activity: top-level and excluded from engine physics interpolation.
func build(parent: Node, far: float) -> Camera3D:
	camera = Camera3D.new()
	camera.name = "MultirotorCamera"
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = NEAR_M
	camera.far = far
	parent.add_child(camera)
	camera.make_current()
	return camera


func view_name() -> String:
	return VIEWS[view]


func cycle_view() -> void:
	view = (view + 1) % VIEWS.size()
	_snap = true


## Returns true when the value changed (the OSD then shows it).
func adjust_tilt(steps: int) -> bool:
	var next := clampf(tilt_deg + TILT_STEP_DEG * steps, TILT_MIN_DEG, TILT_MAX_DEG)
	var changed := next != tilt_deg
	tilt_deg = next
	return changed


func adjust_fov(steps: int) -> bool:
	var next := clampf(hfov_deg + HFOV_STEP_DEG * steps, HFOV_MIN_DEG, HFOV_MAX_DEG)
	var changed := next != hfov_deg
	hfov_deg = next
	return changed


## The next update() places the view without carrying any history (pad reset, view change, first frame).
func snap() -> void:
	_snap = true


## Aspect of the content the camera renders into (the viewport's visible rectangle).
func aspect() -> float:
	if camera == null or not camera.is_inside_tree():
		return 16.0 / 9.0
	var size := camera.get_viewport().get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0


## Place the camera for one drawn pose. `pose` is the activity's single interpolated 13-value body; `mount_frd` the
## prepared camera mount; `ground` (render x, z) -> render height keeps inspection eyes above the terrain.
func update(pose: PackedFloat64Array, mount_frd: PackedFloat64Array, delta: float, ground: Callable) -> void:
	if camera == null:
		return
	var position := PackedFloat64Array([pose[0], pose[1], pose[2]])
	var attitude := pose.slice(6, 10)
	var target := Frames.ned_to_render([pose[0], pose[1], pose[2]])
	match VIEWS[view]:
		"fpv":
			camera.global_transform = fpv_transform(position, attitude, mount_frd, deg_to_rad(tilt_deg))
			camera.fov = vertical_fov_deg(hfov_deg, aspect())
		"chase":
			var nose := -Frames.quat_to_render(attitude).z
			var heading := atan2(nose.x, -nose.z) if Vector2(nose.x, nose.z).length() > 0.05 else _chase_heading
			_chase_heading = heading if _snap else lerp_angle(_chase_heading, heading, clampf(delta * 3.0, 0.0, 1.0))
			var placed := chase_placement(target, _chase_heading)
			var eye: Vector3 = placed.eye
			eye.y = maxf(eye.y, _ground_at(ground, eye) + EYE_CLEARANCE_M)
			camera.global_position = eye
			camera.look_at(placed.aim, Vector3.UP)
			camera.fov = CHASE_VFOV_DEG
		_:
			var eye := pilot_eye
			camera.global_position = eye
			var line := target - eye
			if line.length() > 0.01 and absf(line.normalized().dot(Vector3.UP)) < 0.999:
				camera.look_at(target, Vector3.UP)
			camera.fov = pilot_vfov_deg(eye.distance_to(target))
	_snap = false


## Chase eye and aim point for a CG at `target` (render) and a heading (rad, render yaw of the nose): the eye sits
## CHASE_BACK_M behind along the heading and CHASE_UP_M above; the aim is CHASE_AIM_UP_M above the CG. The caller
## clamps the eye above the terrain.
static func chase_placement(target: Vector3, heading: float) -> Dictionary:
	var back := Vector3(-sin(heading), 0.0, cos(heading))
	return {eye = target + back * CHASE_BACK_M + Vector3.UP * CHASE_UP_M, aim = target + Vector3.UP * CHASE_AIM_UP_M}


## Pilot-view vertical FOV (deg) for the quad at `distance_m`: PILOT_FRAME_M of scene height across the picture.
static func pilot_vfov_deg(distance_m: float) -> float:
	var distance := maxf(distance_m, 0.5)
	return clampf(rad_to_deg(2.0 * atan(0.5 * PILOT_FRAME_M / distance)), PILOT_VFOV_MIN_DEG, PILOT_VFOV_MAX_DEG)


static func _ground_at(ground: Callable, at: Vector3) -> float:
	return float(ground.call(at.x, at.z)) if ground.is_valid() else -INF
