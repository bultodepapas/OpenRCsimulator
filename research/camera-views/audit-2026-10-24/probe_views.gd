# CAM-AUD-2026-10-24 probe: behaviour of the production camera classes that the unit tests do not cover (chase
# manoeuvres, frame-rate independence, pilot overhead pass, auto-zoom by resolution). Read-only; synthetic render-space
# trajectories (x east, y up, -z north). Run from the repository root:
#   godot --headless --path app --script "$PWD/research/camera-views/audit-2026-10-24/probe_views.gd"
extends SceneTree

const CameraMath := preload("res://render/camera/camera_math.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const Spec := preload("res://spec.gd")

const G := 9.81


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_autozoom_table()
	_chase_case("straight+loop R15 v20", _loop_pose, 9.0)
	_chase_case("hammerhead", _hammer_pose, 10.0)
	_chase_case("60deg turn v20", _turn_pose, 10.0)
	_chase_case("snap heading: knife-edge crab", _crab_pose, 6.0)
	_chase_fps_independence()
	_pilot_pass("overhead pass e=0.5 m h=20 v=25", 0.5, 20.0, 25.0)
	_pilot_pass("overhead pass e=2 m h=20 v=25", 2.0, 20.0, 25.0)
	_pilot_pass("overhead pass e=5 m h=20 v=25", 5.0, 20.0, 25.0)
	_pilot_pass("low pass e=8 m h=3 v=30", 8.0, 1.5, 30.0)
	_cost()
	quit(0)


# ---------- trajectories: { pos, basis, vel } ----------

static func _basis(forward: Vector3, up_hint: Vector3) -> Basis:
	var z := -forward.normalized()
	var x := up_hint.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _loop_pose(t: float) -> Dictionary:
	var v := 20.0
	var r := 15.0
	var h := 30.0
	var t0 := 2.0
	var loop_t := TAU * r / v
	if t < t0:
		return { pos = Vector3(0, h, -v * t), basis = _basis(Vector3(0, 0, -1), Vector3.UP), vel = Vector3(0, 0, -v) }
	if t < t0 + loop_t:
		var th := v * (t - t0) / r
		var c := Vector3(0, h + r, -v * t0)
		var p := c + r * Vector3(0, -cos(th), -sin(th))
		var fwd := Vector3(0, sin(th), -cos(th))
		return { pos = p, basis = _basis(fwd, (c - p).normalized()), vel = fwd * v }
	var t2 := t - t0 - loop_t
	return { pos = Vector3(0, h, -v * t0 - v * t2), basis = _basis(Vector3(0, 0, -1), Vector3.UP), vel = Vector3(0, 0, -v) }


func _hammer_pose(t: float) -> Dictionary:
	# 2 s north at 20 m/s, quarter loop R10 up, 1.5 s vertical decelerating 20→2 m/s, 1 s pivot (nose up → down
	# through east), 2 s vertical down accelerating 2→20, quarter loop R10 out heading south.
	var v := 20.0
	var r := 10.0
	var h := 20.0
	var q := (PI * 0.5) * r / v
	var p0 := Vector3(0, h, -v * 2.0)
	if t < 2.0:
		return { pos = Vector3(0, h, -v * t), basis = _basis(Vector3(0, 0, -1), Vector3.UP), vel = Vector3(0, 0, -v) }
	t -= 2.0
	if t < q:
		var th := v * t / r
		var c := p0 + Vector3(0, r, 0)
		var p := c + r * Vector3(0, -cos(th), -sin(th))
		var fwd := Vector3(0, sin(th), -cos(th))
		return { pos = p, basis = _basis(fwd, (c - p).normalized()), vel = fwd * v }
	t -= q
	var p1 := p0 + Vector3(0, r, -r)
	var climb := 1.5
	if t < climb:
		var a := (2.0 - v) / climb
		var y := v * t + 0.5 * a * t * t
		return { pos = p1 + Vector3(0, y, 0), basis = _basis(Vector3.UP, Vector3(0, 0, 1)), vel = Vector3(0, v + a * t, 0) }
	var p2 := p1 + Vector3(0, v * climb + 0.5 * ((2.0 - v) / climb) * climb * climb, 0)
	t -= climb
	if t < 1.0:
		var ang := PI * t # nose from up (0) to down (π) through east
		var fwd := Vector3(sin(ang), cos(ang), 0)
		return { pos = p2, basis = _basis(fwd, Vector3(0, 0, 1)), vel = Vector3(0, 0.0, 0) }
	t -= 1.0
	var down := 2.0
	if t < down:
		var a2 := (v - 2.0) / down
		var y2 := 2.0 * t + 0.5 * a2 * t * t
		return { pos = p2 - Vector3(0, y2, 0), basis = _basis(Vector3.DOWN, Vector3(0, 0, 1)), vel = Vector3(0, -(2.0 + a2 * t), 0) }
	var p3 := p2 - Vector3(0, 2.0 * down + 0.5 * ((v - 2.0) / down) * down * down, 0)
	t -= down
	if t < q:
		var th2 := v * t / r
		var c2 := p3 + Vector3(0, 0, r)
		var p := c2 + r * Vector3(0, -sin(th2), -cos(th2))
		var fwd := Vector3(0, -cos(th2), sin(th2))
		return { pos = p, basis = _basis(fwd, Vector3(0, 0, 1)), vel = fwd * v }
	t -= q
	var p4 := p3 + Vector3(0, -r, r)
	return { pos = p4 + Vector3(0, 0, v * t), basis = _basis(Vector3(0, 0, 1), Vector3.UP), vel = Vector3(0, 0, v) }


func _turn_pose(t: float) -> Dictionary:
	var v := 20.0
	var bank := deg_to_rad(60.0)
	var r := v * v / (G * tan(bank))
	var w := v / r
	var th := w * t
	var c := Vector3(r, 30.0, 0)
	var p := c + r * Vector3(-cos(th), 0, -sin(th))
	var fwd := Vector3(sin(th), 0, -cos(th))
	var inward := (c - p).normalized()
	var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
	return { pos = p, basis = _basis(fwd, up), vel = fwd * v }


func _crab_pose(t: float) -> Dictionary:
	# Straight north at 18 m/s; between 2 and 4 s the nose yaws 60° right while the track stays north (crab in a
	# crosswind landing / knife-edge with rudder): the camera follows the track, not the nose.
	var yaw := 0.0
	if t > 2.0:
		yaw = deg_to_rad(60.0) * clampf((t - 2.0) / 0.5, 0.0, 1.0)
	return { pos = Vector3(0, 5, -18.0 * t), basis = _basis(Vector3(sin(yaw), 0, -cos(yaw)), Vector3.UP), vel = Vector3(0, 0, -18) }


# ---------- chase metrics ----------

## Angle (deg) of a target in the camera frame: x right, y up.
static func _screen_angles(cam_pos: Vector3, cam_basis: Basis, target: Vector3) -> Vector2:
	var local := cam_basis.inverse() * (target - cam_pos)
	return Vector2(rad_to_deg(atan2(local.x, -local.z)), rad_to_deg(atan2(local.y, -local.z)))


func _chase_case(label: String, pose: Callable, duration: float) -> void:
	var chase := ChaseView.new()
	chase.configure(1.5)
	var dt := 1.0 / 60.0
	var n := int(duration / dt)
	var worst_off := 0.0
	var worst_yaw_rate := 0.0
	var worst_cam_rate := 0.0
	var min_d := INF
	var max_d := 0.0
	var cap_frames := 0
	var prev_yaw := NAN
	var prev_fwd := Vector3.ZERO
	var screen: Array[Vector2] = []
	var outside := 0
	var hfov_half := CameraMath.horizontal_fov(ChaseView.FOV_DEG, 16.0 / 9.0) * 0.5
	var vfov_half := ChaseView.FOV_DEG * 0.5
	for i in n:
		var t := i * dt
		var s: Dictionary = pose.call(t)
		var placed := chase.update(s.pos, s.basis, dt, false, Callable())
		var cam_pos: Vector3 = placed.position
		var b: Basis = placed.basis
		var fwd := -b.z
		var a := _screen_angles(cam_pos, b, s.pos)
		screen.append(a)
		worst_off = maxf(worst_off, a.length())
		if absf(a.x) > hfov_half or absf(a.y) > vfov_half:
			outside += 1
		var d := cam_pos.distance_to(s.pos)
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
		var boom := chase.distance * chase.zoom
		var goal := (s.pos as Vector3) - CameraMath.dir_of_heading(chase._heading) * boom + Vector3.UP * chase.height * chase.zoom
		if (cam_pos - goal).length() >= 0.98 * boom:
			cap_frames += 1
		var yaw := CameraMath.heading_of(CameraMath.horizontal_dir(fwd)) if CameraMath.horizontal_dir(fwd) != Vector3.ZERO else NAN
		if not is_nan(yaw) and not is_nan(prev_yaw):
			worst_yaw_rate = maxf(worst_yaw_rate, absf(rad_to_deg(angle_difference(prev_yaw, yaw))) / dt)
		if prev_fwd != Vector3.ZERO:
			worst_cam_rate = maxf(worst_cam_rate, rad_to_deg(prev_fwd.angle_to(fwd)) / dt)
		prev_yaw = yaw
		prev_fwd = fwd
	# Jitter: RMS of the second difference of the target's screen angle, in 1080p pixels at the chase FOV.
	var px_per_deg := 1080.0 / (2.0 * tan(deg_to_rad(ChaseView.FOV_DEG) * 0.5)) * deg_to_rad(1.0)
	var sum := 0.0
	var worst_dd := 0.0
	for i in range(2, screen.size()):
		var dd := (screen[i] - 2.0 * screen[i - 1] + screen[i - 2]).length() * px_per_deg
		sum += dd * dd
		worst_dd = maxf(worst_dd, dd)
	var rms := sqrt(sum / maxf(1.0, screen.size() - 2))
	var worst_late := 0.0
	var worst_at := 0
	var worst_v := 0.0
	for i in range(2, screen.size()):
		var dd2 := (screen[i] - 2.0 * screen[i - 1] + screen[i - 2]).length() * px_per_deg
		if dd2 > worst_late and i > 30:
			worst_late = dd2
			worst_at = i
		worst_v = maxf(worst_v, absf(screen[i].y))
	var early := 0.0
	for i in range(2, mini(30, screen.size())):
		early = maxf(early, (screen[i] - 2.0 * screen[i - 1] + screen[i - 2]).length() * px_per_deg)
	print("CHASE %-32s off-centre max %5.1f°  outside-frame %3d/%d  cam yaw-rate max %6.1f°/s  cam turn-rate max %6.1f°/s  dist %.1f–%.1f m (boom %.2f)  lag-cap frames %d  screen 2nd-diff rms %.2f px max %.1f px (1080p)" % [
		label, worst_off, outside, n, worst_yaw_rate, worst_cam_rate, min_d, max_d, chase.distance, cap_frames, rms, worst_dd])
	print("      first 0.5 s 2nd-diff max %.1f px; after 0.5 s max %.1f px at t=%.2f s; vertical off-centre max %.1f° (half vfov %.1f°); start screen angle %s → after 0.5 s %s" % [early, worst_late, worst_at / 60.0, worst_v, vfov_half, screen[1], screen[30]])


func _chase_fps_independence() -> void:
	# Same 60° turn at 30, 60, 144 fps and with jittered frame times; compare positions at matched times.
	var results := {}
	for fps: float in [30.0, 60.0, 144.0]:
		var chase := ChaseView.new()
		chase.configure(1.5)
		var t := 0.0
		var dt := 1.0 / fps
		var samples := {}
		while t < 6.0 - 1e-9:
			t += dt
			var s := _turn_pose(t)
			var placed := chase.update(s.pos, s.basis, dt, false, Callable())
			for mark: float in [2.0, 4.0, 6.0]:
				if absf(t - mark) < dt * 0.5:
					samples[mark] = placed.position
		results[fps] = samples
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var chase_j := ChaseView.new()
	chase_j.configure(1.5)
	var tj := 0.0
	var sj := {}
	var marks := [2.0, 4.0, 6.0]
	var next_mark := 0
	while next_mark < marks.size():
		var step: float = rng.randf_range(1.0 / 144.0, 1.0 / 30.0)
		if tj + step > marks[next_mark]:
			step = marks[next_mark] - tj
		tj += step
		var s := _turn_pose(tj)
		var placed := chase_j.update(s.pos, s.basis, step, false, Callable())
		if absf(tj - marks[next_mark]) < 1e-9:
			sj[marks[next_mark]] = placed.position
			next_mark += 1
	for mark: float in [2.0, 4.0, 6.0]:
		var a: Vector3 = results[30.0].get(mark, Vector3.INF)
		var b: Vector3 = results[60.0].get(mark, Vector3.INF)
		var c: Vector3 = results[144.0].get(mark, Vector3.INF)
		print("CHASE fps-independence 60° turn t=%.0f s: |30−144| %.3f m  |60−144| %.3f m  |jitter−144| %.3f m" % [mark, a.distance_to(c), b.distance_to(c), (sj[mark] as Vector3).distance_to(c)])


# ---------- pilot view ----------

func _pilot_pass(label: String, lateral: float, height: float, speed: float) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.set_meta("pilot_station", [0.0, 0.0, 0.0])
	cam.set_meta("pilot_eye_height", 1.7)
	var dt := 1.0 / 60.0
	var prev_fwd := Vector3.ZERO
	var prev_right := Vector3.ZERO
	var worst_fwd := 0.0
	var worst_right := 0.0
	var t := -3.0
	while t < 3.0:
		var target := Vector3(lateral, height, -speed * t)
		PilotCamera.aim(cam, target, Transform3D(Basis.IDENTITY, target), false, 0.0)
		var fwd := -cam.global_basis.z
		var right := cam.global_basis.x
		if prev_fwd != Vector3.ZERO:
			worst_fwd = maxf(worst_fwd, rad_to_deg(prev_fwd.angle_to(fwd)) / dt)
			worst_right = maxf(worst_right, rad_to_deg(prev_right.angle_to(right)) / dt)
		prev_fwd = fwd
		prev_right = right
		t += dt
	cam.queue_free()
	print("PILOT %-34s gaze rate max %7.1f°/s   screen-right (horizon) rotation max %7.1f°/s  (per 60 fps frame %.1f°)" % [label, worst_fwd, worst_right, worst_right * dt])


func _autozoom_table() -> void:
	var span := 1.5
	print("AUTOZOOM span %.1f m, target %d px, FOV clamp %.0f–%.0f°" % [span, Spec.AUTO_ZOOM.target_px, Spec.AUTO_ZOOM.min_fov_deg, Spec.CAMERA.fov_deg])
	# Physical screen: 27-inch 16:9 (height 33.6 cm) seen from 60 cm.
	var screen_h_cm := 27.0 * 2.54 * 9.0 / sqrt(16.0 * 16.0 + 9.0 * 9.0)
	for h: float in [720.0, 1080.0, 1440.0, 2160.0]:
		var line := "  %4dp:" % int(h)
		for d: float in [25.0, 50.0, 100.0, 200.0, 300.0, 500.0, 800.0]:
			var fov := PilotCamera.auto_fov(span, d, h)
			var px := PilotCamera.projected_px(span, d, fov, h)
			var on_screen_arcmin := rad_to_deg(2.0 * atan(px / h * screen_h_cm * 0.5 / 60.0)) * 60.0
			var real_arcmin := rad_to_deg(2.0 * atan(span * 0.5 / d)) * 60.0
			line += "  %3dm %4.1f° %4.0fpx ×%.1f" % [int(d), fov, px, on_screen_arcmin / real_arcmin]
		print(line)
	print("  (×N = on-screen angular size / real angular size, 27-inch 16:9 at 60 cm)")
	var natural := rad_to_deg(2.0 * atan(screen_h_cm * 0.5 / 60.0))
	print("  natural (orthoscopic) vertical FOV for that screen: %.1f°" % natural)


func _cost() -> void:
	var chase := ChaseView.new()
	chase.configure(1.5)
	var started := Time.get_ticks_usec()
	var n := 20000
	for i in n:
		var s := _turn_pose(i / 60.0)
		chase.update(s.pos, s.basis, 1.0 / 60.0, false, Callable())
	var per := float(Time.get_ticks_usec() - started) / n
	print("COST chase.update incl. trajectory: %.1f µs/frame (VM, headless)" % per)
