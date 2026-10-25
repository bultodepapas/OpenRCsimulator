# CAM-14: fly-by view (docs/plans/camera-views.md §5.4). A spectator camera waits ahead of the aircraft, watches it
# pass and re-places itself once the aircraft is well past. Placement follows FlightGear's fly-by law
# (fgdata Nasal/view.nas): ahead along the course by 0.8 × (3.5 s × speed), deviated 0.7–1.2 × D around the track,
# to the side when the aircraft flies lower than D, never below the terrain + 2 m. We add one rule: the side with the
# sun behind the camera, so the aircraft is lit. The camera itself never moves between placements; it turns and zooms
# like a photographer. Presentation only: its random draws use its own fixed-seed generator, never the simulation's.
extends RefCounted

const CameraMath := preload("res://render/camera/camera_math.gd")

const DISTANCE_M := 25.0 # D, FlightGear's default chase distance
const LEAD_S := 3.5
const LEAD_SHARE := 0.8
const RADIUS_MIN := 0.7
const RADIUS_MAX := 1.2
const REPLACE_PAST := 1.7 # re-place once the aircraft is this many D past the camera, moving away
const MIN_HEIGHT_M := 2.0
## Below this speed (m/s) there is no course to wait on: the camera stands D to the side of the nose.
const MIN_SPEED := 2.0
## A pose jump beyond this speed (m/s) is a reset or teleport: re-place at once.
const TELEPORT_SPEED := 200.0
## The aircraft's span covers this share of the frame height, like a photographer zooming; FOV kept in a lens range.
const FRAME_SHARE := 0.12
const MIN_FOV_DEG := 3.0
const MAX_FOV_DEG := 50.0
const SEED := 20261025

var position := Vector3.ZERO
var zoom := 1.0 # framing multiplier (+/−, wheel): > 1 frames the aircraft larger
var _span := 1.5
var _placed := false
var _last_target := Vector3.ZERO
var _track := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = SEED


func configure(span: float) -> void:
	_span = maxf(span, 0.3)


## Forget the placement: the next update places the camera ahead of the aircraft.
func reset() -> void:
	_placed = false
	_rng.seed = SEED


## target: the aircraft's CG (render); body: its basis; velocity: its velocity (render, m/s) or INF to estimate it;
## ground_y: Callable(x, z) → terrain height; light: direction toward the sun (render), ZERO when unknown.
## Returns { position, basis, fov }.
func update(target: Vector3, body: Basis, velocity: Vector3, dt: float, paused: bool, ground_y: Callable,
		light := Vector3.ZERO) -> Dictionary:
	if velocity.is_finite():
		_track = velocity
	elif _placed and not paused and dt > 0.0:
		_track = CameraMath.damp_v3(_track, (target - _last_target) / dt, dt, 0.08)
	if _placed and not paused and dt > 0.0 and (target - _last_target).length() > TELEPORT_SPEED * dt:
		_placed = false
	if not _placed or (not paused and _passed(target)):
		_place(target, body, ground_y, light)
	_last_target = target
	var away := maxf(position.distance_to(target), 0.1)
	var fov := clampf(rad_to_deg(2.0 * atan(_span / (2.0 * away * FRAME_SHARE * zoom))), MIN_FOV_DEG, MAX_FOV_DEG)
	return { position = position, basis = CameraMath.look_basis(position, target), fov = fov }


## The aircraft has gone REPLACE_PAST × D beyond the camera along its course.
func _passed(target: Vector3) -> bool:
	if _track.length() < MIN_SPEED:
		return false
	return (target - position).dot(_track.normalized()) > REPLACE_PAST * DISTANCE_M


func _place(target: Vector3, body: Basis, ground_y: Callable, light: Vector3) -> void:
	var speed := _track.length()
	var course := _track / speed if speed >= MIN_SPEED else CameraMath.dir_of_heading(CameraMath.heading_of(_nose(body)))
	var lead := course * LEAD_SHARE * LEAD_S * speed + Vector3.UP * 0.5 * _track.y * LEAD_S if speed >= MIN_SPEED else Vector3.ZERO
	var radius := DISTANCE_M * _rng.randf_range(RADIUS_MIN, RADIUS_MAX)
	var right := course.cross(Vector3.UP)
	right = right.normalized() if right.length() > 1e-3 else Vector3.RIGHT
	var up := right.cross(course).normalized()
	var height := target.y - _ground(ground_y, target)
	# FlightGear: any angle around the track when high, to the side (±90° ± 0.15π) when low.
	var angle := _rng.randf_range(-PI, PI) if height > DISTANCE_M else (PI * 0.5 + _rng.randf_range(-0.15, 0.15) * PI)
	var side := right * sin(angle) + up * cos(angle)
	# Sun behind the camera: of the two mirror sides, keep the one facing the sun.
	if light != Vector3.ZERO and Vector2(side.x, side.z).dot(Vector2(light.x, light.z)) < 0.0:
		side = -right * sin(angle) + up * cos(angle)
	position = target + lead + side * radius
	position.y = maxf(position.y, _ground(ground_y, position) + MIN_HEIGHT_M)
	_placed = true


static func _nose(body: Basis) -> Vector3:
	var nose := CameraMath.horizontal_dir(-body.z, 0.05)
	return nose if nose != Vector3.ZERO else Vector3.FORWARD


static func _ground(ground_y: Callable, at: Vector3) -> float:
	if not ground_y.is_valid():
		return 0.0
	var y: float = ground_y.call(at.x, at.z)
	return y if is_finite(y) else 0.0
