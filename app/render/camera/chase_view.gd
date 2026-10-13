# CAM-08: horizon-locked chase view (docs/plans/camera-views.md §5.2). The camera trails the airplane along its
# flight path (track heading; body heading when slow, sliding backwards or on a vertical line), keeps world up (no
# roll: a horizon fixed to the earth is the comfortable reference), and never goes below the terrain. Read-only.
extends RefCounted

const CameraMath := preload("res://render/camera/camera_math.gd")

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

var distance := 5.0
var height := 1.75
var zoom := 1.0 # boom multiplier (+/−, wheel)
var position := Vector3.ZERO
var _offset := Vector3.ZERO # camera − airplane
var _offset_rate := Vector3.ZERO # spring velocity of the offset
var _heading := 0.0
var _track := Vector3.ZERO # estimated airplane velocity (render, m/s)
var _last_target := Vector3.ZERO
var _primed := false


func configure(span: float) -> void:
	distance = DISTANCE_SPANS * maxf(span, 0.3)
	height = HEIGHT_OF_DISTANCE * distance


## Forget the history: the next update snaps to the settled pose.
func reset() -> void:
	_primed = false


## The heading the boom aligns with: the horizontal track when the airplane moves forward fast enough, else its body
## heading; `held` when neither is defined (vertical line, hover).
static func alignment_heading(track: Vector3, body: Basis, held: float) -> float:
	var nose := CameraMath.horizontal_dir(-body.z, 0.05)
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


## target: airplane CG (render); body: its basis; ground_y: Callable(x, z) → terrain height (render y).
## Returns { position, basis, fov }.
func update(target: Vector3, body: Basis, dt: float, paused: bool, ground_y: Callable) -> Dictionary:
	if _primed and not paused and dt > 0.0:
		var raw := (target - _last_target) / dt
		if raw.length() > TELEPORT_SPEED:
			_primed = false
		else:
			_track = CameraMath.damp_v3(_track, raw, dt, VELOCITY_HALF_LIFE)
	var boom := distance * zoom
	if not _primed:
		_track = Vector3.ZERO
		_heading = alignment_heading(_track, body, 0.0)
		_offset = _goal(target, boom, ground_y) - target
		_offset_rate = Vector3.ZERO
		_primed = true
	elif not paused:
		_heading = CameraMath.damp_angle(_heading, alignment_heading(_track, body, _heading), dt, HEADING_HALF_LIFE)
		var goal := _goal(target, boom, ground_y) - target
		var moved: Array = CameraMath.spring(_offset, _offset_rate, goal, dt, POSITION_HALF_LIFE)
		_offset = moved[0]
		_offset_rate = moved[1]
		# Lag cap: never more than one boom length away from where the camera should be.
		var lag := _offset - goal
		if lag.length() > boom:
			_offset = goal + lag.normalized() * boom
	_last_target = target
	position = target + _offset
	position.y = maxf(position.y, _ground(ground_y, position) + CLEARANCE_M)
	var ahead := Vector3(_track.x, 0.0, _track.z) * LOOK_AHEAD_S
	if ahead.length() > 0.6 * boom:
		ahead = ahead.normalized() * 0.6 * boom
	return { position = position, basis = CameraMath.look_basis(position, target + ahead), fov = FOV_DEG }


func _goal(target: Vector3, boom: float, ground_y: Callable) -> Vector3:
	var goal := target - CameraMath.dir_of_heading(_heading) * boom + Vector3.UP * height * zoom
	goal.y = maxf(goal.y, _ground(ground_y, goal) + CLEARANCE_M)
	return goal


static func _ground(ground_y: Callable, at: Vector3) -> float:
	if not ground_y.is_valid():
		return 0.0
	var y: float = ground_y.call(at.x, at.z)
	return y if is_finite(y) else 0.0
