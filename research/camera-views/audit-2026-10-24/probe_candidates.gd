# CAM-AUD-2026-10-24 probe: candidate camera laws compared with production on the same trajectories (fixed sub-steps,
# state velocity, heading feed-forward, pilot screen-roll rate cap). Not production code. Run from the repository root:
#   godot --headless --path app --script "$PWD/research/camera-views/audit-2026-10-24/probe_candidates.gd"
extends SceneTree

const CameraMath := preload("res://render/camera/camera_math.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")

const G := 9.81
var bank_deg := 60.0


## Production chase with two optional changes: fixed sub-steps (target interpolated inside the frame) and
## heading feed-forward (the damped heading aims ahead by rate × time constant, cancelling the steady turn lag).
class CandidateChase extends "res://render/camera/chase_view.gd":
	var substep := 0.0 # s; 0 = off
	var feed_forward := false
	var true_velocity := false # prime and drive _track from the given velocity instead of finite differences
	var _prev_target := Vector3.ZERO
	var _prev_body := Basis.IDENTITY
	var _have_prev := false
	var _prev_goal_heading := NAN

	var production := false
	var _prev_velocity := Vector3.ZERO

	func step(target: Vector3, body: Basis, velocity: Vector3, dt: float) -> Dictionary:
		if production:
			return update(target, body, dt, false, Callable())
		if substep <= 0.0 or not _have_prev:
			_have_prev = true
			_prev_target = target
			_prev_body = body
			_prev_velocity = velocity
			return _one(target, body, velocity, dt)
		var n := maxi(1, ceili(dt / substep - 1e-9))
		var out := {}
		for i in n:
			var f := float(i + 1) / n
			out = _one(_prev_target.lerp(target, f), _prev_body.slerp(body, f), _prev_velocity.lerp(velocity, f), dt / n)
		_prev_target = target
		_prev_body = body
		_prev_velocity = velocity
		return out

	func _one(target: Vector3, body: Basis, velocity: Vector3, dt: float) -> Dictionary:
		# Feed-forward: same as update(), but the heading damper chases goal + rate·τ.
		if _primed and dt > 0.0:
			if true_velocity:
				_track = velocity
			else:
				_track = CameraMath.damp_v3(_track, (target - _last_target) / dt, dt, VELOCITY_HALF_LIFE)
		var boom := distance * zoom
		if not _primed:
			if not true_velocity:
				_track = Vector3.ZERO
			else:
				_track = velocity
			_heading = alignment_heading(_track, body, 0.0)
			_offset = _goal(target, boom, Callable()) - target
			_offset_rate = Vector3.ZERO
			_prev_goal_heading = _heading
			_primed = true
		else:
			var goal_heading := alignment_heading(_track, body, _heading)
			var rate := angle_difference(_prev_goal_heading, goal_heading) / dt if not is_nan(_prev_goal_heading) else 0.0
			_prev_goal_heading = goal_heading
			var tau := HEADING_HALF_LIFE / log(2.0)
			# A bounded lead: a sudden flip (tail slide) must not be amplified.
			var lead := clampf(rate * tau, -0.6, 0.6) if feed_forward else 0.0
			_heading = CameraMath.damp_angle(_heading, wrapf(goal_heading + lead, -PI, PI), dt, HEADING_HALF_LIFE)
			var goal := _goal(target, boom, Callable()) - target
			var moved: Array = CameraMath.spring(_offset, _offset_rate, goal, dt, POSITION_HALF_LIFE)
			_offset = moved[0]
			_offset_rate = moved[1]
		_last_target = target
		position = target + _offset
		var ahead := Vector3(_track.x, 0.0, _track.z) * LOOK_AHEAD_S
		if ahead.length() > 0.6 * boom:
			ahead = ahead.normalized() * 0.6 * boom
		return { position = position, basis = CameraMath.look_basis(position, target + ahead), fov = FOV_DEG }


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for b: float in [60.0, rad_to_deg(atan(400.0 / (G * 60.0)))]:
		bank_deg = b
		print("--- steady turn v=20 m/s bank %.1f° radius %.1f m" % [b, 400.0 / (G * tan(deg_to_rad(b)))])
		_chase_rows()
	for cap: float in [0.0, 180.0, 90.0]:
		for e: float in [0.5, 2.0]:
			_pilot_roll_limit(e, cap)
	quit(0)


func _chase_rows() -> void:
	for cfg: Dictionary in [
			{ name = "production", substep = 0.0, ff = false, tv = false },
			{ name = "reimplemented (no change)", substep = 0.0, ff = false, tv = false },
			{ name = "true velocity", substep = 0.0, ff = false, tv = true },
			{ name = "substep 1/240", substep = 1.0 / 240.0, ff = false, tv = false },
			{ name = "substep + true velocity", substep = 1.0 / 240.0, ff = false, tv = true },
			{ name = "feed-forward heading", substep = 0.0, ff = true, tv = false },
			{ name = "ff + substep + true velocity", substep = 1.0 / 240.0, ff = true, tv = true }]:
		_chase_eval(cfg)


func _turn_pose(t: float) -> Dictionary:
	var v := 20.0
	var bank := deg_to_rad(bank_deg)
	var r := v * v / (G * tan(bank))
	var w := v / r
	var th := w * t
	var c := Vector3(r, 30.0, 0)
	var p := c + r * Vector3(-cos(th), 0, -sin(th))
	var fwd := Vector3(sin(th), 0, -cos(th))
	var inward := (c - p).normalized()
	var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
	var z := -fwd
	var x := up.cross(z).normalized()
	return { pos = p, basis = Basis(x, z.cross(x), z), vel = fwd * v }


func _straight_pose(t: float) -> Dictionary:
	return { pos = Vector3(0, 30, -20.0 * t), basis = Basis.IDENTITY, vel = Vector3(0, 0, -20) }


func _make(cfg: Dictionary) -> CandidateChase:
	var c := CandidateChase.new()
	c.configure(1.5)
	c.substep = cfg.substep
	c.feed_forward = cfg.ff
	c.true_velocity = cfg.tv
	c.production = cfg.name == "production"
	return c


static func _off_centre(placed: Dictionary, target: Vector3) -> float:
	var b: Basis = placed.basis
	return rad_to_deg((-b.z).angle_to(target - (placed.position as Vector3)))


func _chase_eval(cfg: Dictionary) -> void:
	# 1) Steady 60° turn: off-centre angle after 4 s. 2) Matched-time position difference 30 vs 144 fps.
	# 3) Entry transient in straight flight: largest frame-to-frame change of the target's screen angle (°).
	var at := {}
	var off_turn := 0.0
	for fps: float in [30.0, 144.0]:
		var c := _make(cfg)
		var dt := 1.0 / fps
		var t := 0.0
		while t < 6.0 - 1e-9:
			t += dt
			var s := _turn_pose(t)
			var placed := c.step(s.pos, s.basis, s.vel, dt)
			if absf(t - 6.0) < dt * 0.5:
				at[fps] = placed.position
				off_turn = _off_centre(placed, s.pos)
	var c2 := _make(cfg)
	var worst_step := 0.0
	var prev := NAN
	for i in 60:
		var s := _straight_pose(i / 60.0)
		var placed := c2.step(s.pos, s.basis, s.vel, 1.0 / 60.0)
		var a := _off_centre(placed, s.pos)
		if not is_nan(prev):
			worst_step = maxf(worst_step, absf(a - prev))
		prev = a
	print("CANDIDATE chase %-30s turn off-centre %5.1f°   |30−144 fps| %.3f m   entry transient max %.2f°/frame" % [
		cfg.name, off_turn, (at[30.0] as Vector3).distance_to(at[144.0]), worst_step])


## Pilot view with the screen-up vector allowed to turn at most `cap` °/s (0 = production world-up look_at).
func _pilot_roll_limit(lateral: float, cap: float) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.set_meta("pilot_station", [0.0, 0.0, 0.0])
	cam.set_meta("pilot_eye_height", 1.7)
	var dt := 1.0 / 60.0
	var up := Vector3.UP
	var prev_right := Vector3.ZERO
	var worst_right := 0.0
	var worst_aim := 0.0
	var worst_tilt := 0.0
	var t := -3.0
	while t < 3.0:
		var target := Vector3(lateral, 20.0, -25.0 * t)
		PilotCamera.aim(cam, target, Transform3D(Basis.IDENTITY, target), false, 0.0)
		if cap > 0.0:
			var fwd := (target - cam.position).normalized()
			# Desired up: world up projected on the view plane; when undefined keep the previous one.
			var want := (Vector3.UP - fwd * fwd.dot(Vector3.UP))
			want = want.normalized() if want.length() > 1e-3 else up
			var cur := (up - fwd * fwd.dot(up))
			cur = cur.normalized() if cur.length() > 1e-6 else want
			var ang := cur.angle_to(want)
			var max_step := deg_to_rad(cap) * dt
			if ang > max_step:
				var axis := cur.cross(want)
				axis = axis.normalized() if axis.length() > 1e-9 else fwd
				cur = cur.rotated(axis, max_step)
			else:
				cur = want
			up = cur
			cam.basis = Basis.looking_at(fwd, up)
			worst_tilt = maxf(worst_tilt, rad_to_deg(asin(clampf(absf(cam.basis.x.y), 0.0, 1.0))))
		worst_aim = maxf(worst_aim, rad_to_deg((-cam.basis.z).angle_to(target - cam.position)))
		var right := cam.basis.x
		if prev_right != Vector3.ZERO:
			worst_right = maxf(worst_right, rad_to_deg(prev_right.angle_to(right)) / dt)
		prev_right = right
		t += dt
	cam.queue_free()
	print("CANDIDATE pilot overhead e=%.1f m roll cap %s: horizon rotation max %7.1f°/s, aim error max %.4f°, horizon tilt max %.1f°" % [
		lateral, ("%.0f°/s" % cap) if cap > 0.0 else "off (production)", worst_right, worst_aim, worst_tilt])
