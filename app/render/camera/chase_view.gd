# CAM-08: horizon-locked chase view (docs/plans/camera-views.md §5.2). The camera trails the airplane along its
# flight path (track heading; body heading when slow, sliding backwards or on a vertical line), keeps world up (no
# roll: a horizon fixed to the earth is the comfortable reference), and never goes below the terrain. Read-only.
extends RefCounted

const CameraMath := preload("res://render/camera/camera_math.gd")
const CameraCollision := preload("res://render/camera/camera_collision.gd")

## Boom length and height as multiples of the span and of the boom (estimated; owner review in CAM-22).
const DISTANCE_SPANS := 3.5
const HEIGHT_OF_DISTANCE := 0.35
const FOV_DEG := 55.0
## Half-lives (s): boom offset, heading, and the velocity estimate taken from successive render poses. The spring acts
## on the offset from the airplane, not on a world position: a spring chasing a moving point lags by 2v/ω (≈ 7 m at
## 20 m/s here), so straight flight would drag the camera far behind. In the airplane's frame it has no lag.
const POSITION_HALF_LIFE := 0.25
const HEADING_HALF_LIFE := 0.35
const VELOCITY_HALF_LIFE := 0.08
## Below TRACK_MIN_SPEED (m/s horizontal) the body heading leads; full track heading TRACK_BLEND above it.
const TRACK_MIN_SPEED := 2.0
const TRACK_BLEND := 1.0
const LOOK_AHEAD_S := 0.15
const CLEARANCE_M := 0.6
## A pose jump beyond this speed (m/s) is a reset or teleport: snap instead of chasing it across the field.
const TELEPORT_SPEED := 200.0
## CAM-24: the filters advance in fixed steps of at most this length (s), with the target, attitude and velocity
## interpolated inside the frame. The spring is exact only for a goal that holds still during its step; a goal that
## moves within a long frame made 30 and 144 fps differ by 11 cm in a 60° bank (CAM-AUD-2026-10-24).
const SUBSTEP_S := 1.0 / 240.0
## A stalled frame (the RC truck passes its raw delta) costs at most this many sub-steps; longer ones step coarser.
const MAX_SUBSTEPS := 24
## CAM-09: an obstacle may shorten the boom to this share of its length (about half a span), never less.
const MIN_BOOM_SHARE := 0.15
## CAM-09 3D follow (plan §5.2): the boom rides a copy of the airplane's attitude damped with this half-life (s), and
## the picture's up leans this share from world up toward the airplane's up (Cinemachine's "lock to target" between
## no roll, 0, and full roll, 1). Loops and rolls then look like an on-rails chase without a rigid mount's nausea.
const STYLES: Array[String] = ["horizon", "follow3d"]
const ATTITUDE_HALF_LIFE := 0.2
const ROLL_FOLLOW := 0.3

var distance := 5.0
var height := 1.75
var zoom := 1.0 # boom multiplier (+/−, wheel)
var style := "horizon" # STYLES: horizon-locked follow (default) or 3D follow
var position := Vector3.ZERO
var _offset := Vector3.ZERO # camera − airplane
var _offset_rate := Vector3.ZERO # spring velocity of the offset
var _heading := 0.0
var _track := Vector3.ZERO # airplane velocity (render, m/s): measured, or estimated from successive targets
var _last_target := Vector3.ZERO
var _last_nose := Vector3.FORWARD
var _attitude := Quaternion.IDENTITY # 3D follow: the damped airplane attitude
var _last_attitude := Quaternion.IDENTITY
var _last_velocity := Vector3.ZERO
var _primed := false
var _guard := CameraCollision.BoomGuard.new()


func configure(span: float) -> void:
	distance = DISTANCE_SPANS * maxf(span, 0.3)
	height = HEIGHT_OF_DISTANCE * distance


## Forget the history: the next update snaps to the settled pose.
func reset() -> void:
	_primed = false
	_guard.reset()


## The heading the boom aligns with: the horizontal track when the airplane moves forward fast enough, else its body
## heading; `held` when neither is defined (vertical line, hover).
static func alignment_heading(track: Vector3, body: Basis, held: float) -> float:
	return _alignment(track, -body.z, held)


## alignment_heading from the nose direction alone (all it uses of the attitude), which interpolates inside a frame
## without needing an orthonormal basis.
static func _alignment(track: Vector3, forward: Vector3, held: float) -> float:
	var nose := CameraMath.horizontal_dir(forward, 0.05)
	var along := CameraMath.horizontal_dir(track, 1e-3)
	var speed := Vector3(track.x, 0.0, track.z).length()
	var nose_heading := CameraMath.heading_of(nose) if nose != Vector3.ZERO else held
	if along == Vector3.ZERO or (nose != Vector3.ZERO and along.dot(nose) < 0.0):
		return nose_heading # still, or sliding backwards: follow the nose
	var track_heading := CameraMath.heading_of(along)
	if nose == Vector3.ZERO:
		return track_heading
	var w := clampf((speed - TRACK_MIN_SPEED) / TRACK_BLEND, 0.0, 1.0)
	return wrapf(nose_heading + angle_difference(nose_heading, track_heading) * w, -PI, PI)


## target: airplane CG (render); body: its basis; ground_y: Callable(x, z) → terrain height (render y); velocity:
## the airplane's velocity (render, m/s) from the simulation state, or INF to estimate it from successive targets;
## obstacles: Callable(from, to) → share of that boom clear of scenery (CAM-09), or empty for open ground.
## Either way the look-ahead follows it through the VELOCITY_HALF_LIFE damper, so a hard touchdown does not jerk the
## aim; a measured velocity also settles that damper on entry, so nothing slides. Returns { position, basis, fov }.
func update(target: Vector3, body: Basis, dt: float, paused: bool, ground_y: Callable, velocity := Vector3.INF,
		obstacles := Callable()) -> Dictionary:
	var measured := velocity.is_finite()
	if _primed and not paused and dt > 0.0 and (target - _last_target).length() > TELEPORT_SPEED * dt:
		_primed = false
	var boom := distance * zoom
	if not _primed:
		# Settled at once. With a measured velocity the look-ahead is settled too, so nothing slides after entry.
		_track = velocity if measured else Vector3.ZERO
		_heading = alignment_heading(_track, body, 0.0)
		_attitude = Quaternion(body.orthonormalized())
		_offset = _goal(target, boom, _floor(ground_y, target, boom)) - target
		_offset_rate = Vector3.ZERO
		_primed = true
	elif not paused and dt > 0.0:
		var raw := velocity if measured else (target - _last_target) / dt
		var floor_y := _floor(ground_y, target, boom)
		var steps := clampi(ceili(dt / SUBSTEP_S - 1e-6), 1, MAX_SUBSTEPS)
		var nose := -body.z
		var attitude := Quaternion(body.orthonormalized())
		for i in steps:
			var f := float(i + 1) / steps
			var at := _last_target.lerp(target, f)
			var v := _last_velocity.lerp(raw, f) if measured else raw
			if style == "follow3d":
				_step_follow(at, _last_attitude.slerp(attitude, f), v, dt / steps, boom, floor_y)
			else:
				_step(at, _last_nose.slerp(nose, f), v, dt / steps, boom, floor_y)
	_last_target = target
	_last_nose = -body.z
	_last_attitude = Quaternion(body.orthonormalized())
	_last_velocity = velocity if measured else _track
	position = target + _offset
	var shortened := 1.0
	if obstacles.is_valid():
		# CAM-09: a building, trunk, crown or the barrier between the airplane and the camera pulls the camera in.
		var wanted := _offset.length()
		var clear := maxf(float(obstacles.call(target, position)) * wanted, MIN_BOOM_SHARE * boom)
		var length := _guard.update(clear, wanted, 0.0 if paused else dt)
		if length < wanted:
			shortened = length / wanted
			position = target + _offset * shortened
	position.y = maxf(position.y, _ground(ground_y, position) + CLEARANCE_M)
	# The look-ahead scales with a shortened boom, so a camera pulled in by a wall still frames the airplane.
	var ahead := (_track if style == "follow3d" else Vector3(_track.x, 0.0, _track.z)) * LOOK_AHEAD_S
	if ahead.length() > 0.6 * boom * shortened:
		ahead = ahead.normalized() * 0.6 * boom * shortened
	if style == "follow3d":
		return { position = position, basis = _follow_basis(position, target + ahead), fov = FOV_DEG }
	return { position = position, basis = CameraMath.look_basis(position, target + ahead), fov = FOV_DEG }


## 3D follow: the boom hangs behind and above the damped attitude, rigidly (the attitude damping is the smoothing,
## so a loop adds no second lag); terrain still lifts it.
func _step_follow(target: Vector3, attitude: Quaternion, velocity: Vector3, h: float, boom: float, floor_y: float) -> void:
	_track = CameraMath.damp_v3(_track, velocity, h, VELOCITY_HALF_LIFE)
	_attitude = _attitude.slerp(attitude, CameraMath.damp_factor(h, ATTITUDE_HALF_LIFE)).normalized()
	_offset = Basis(_attitude) * Vector3(0.0, height * zoom, boom)
	_offset.y = maxf(_offset.y, floor_y + CLEARANCE_M - target.y)
	_offset_rate = Vector3.ZERO


## Look at `point` with the up leaning ROLL_FOLLOW toward the damped airplane's up; when that up runs along the view
## (a vertical line seen from below), the airplane's own up keeps the picture defined.
func _follow_basis(eye: Vector3, point: Vector3) -> Basis:
	var forward := point - eye
	if forward.length() < 1e-6:
		return Basis(_attitude)
	forward = forward.normalized()
	var airplane_up := Basis(_attitude).y
	var up := (Vector3.UP * (1.0 - ROLL_FOLLOW) + airplane_up * ROLL_FOLLOW).normalized()
	if absf(forward.dot(up)) > 0.995:
		up = airplane_up if absf(forward.dot(airplane_up)) < 0.995 else Basis(_attitude).z
	return Basis.looking_at(forward, up)


func _step(target: Vector3, nose: Vector3, velocity: Vector3, h: float, boom: float, floor_y: float) -> void:
	_track = CameraMath.damp_v3(_track, velocity, h, VELOCITY_HALF_LIFE)
	_heading = CameraMath.damp_angle(_heading, _alignment(_track, nose, _heading), h, HEADING_HALF_LIFE)
	var goal := _goal(target, boom, floor_y) - target
	var moved: Array = CameraMath.spring(_offset, _offset_rate, goal, h, POSITION_HALF_LIFE)
	_offset = moved[0]
	_offset_rate = moved[1]
	# Lag cap: never more than one boom length away from where the camera should be.
	var lag := _offset - goal
	if lag.length() > boom:
		_offset = goal + lag.normalized() * boom


func _goal(target: Vector3, boom: float, floor_y: float) -> Vector3:
	var goal := target - CameraMath.dir_of_heading(_heading) * boom + Vector3.UP * height * zoom
	goal.y = maxf(goal.y, floor_y + CLEARANCE_M)
	return goal


## Terrain height under the boom, sampled once per frame for the sub-steps; the final position samples it again.
func _floor(ground_y: Callable, target: Vector3, boom: float) -> float:
	return _ground(ground_y, target - CameraMath.dir_of_heading(_heading) * boom)


static func _ground(ground_y: Callable, at: Vector3) -> float:
	if not ground_y.is_valid():
		return 0.0
	var y: float = ground_y.call(at.x, at.z)
	return y if is_finite(y) else 0.0
