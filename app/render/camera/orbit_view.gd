# CAM-10: orbit view (docs/plans/camera-views.md §5.5). A camera on a sphere around the airplane's CG, turned with
# the right mouse button and moved in or out with the wheel or +/−; world up, no roll. It works while the flight is
# paused. It starts from wherever the previous view was, so switching into it never jumps. Read-only.
extends RefCounted

const CameraMath := preload("res://render/camera/camera_math.gd")
const CameraCollision := preload("res://render/camera/camera_collision.gd")

const FOV_DEG := 45.0
const DEGREES_PER_PIXEL := 0.3
const MIN_ELEVATION_DEG := -20.0
const MAX_ELEVATION_DEG := 85.0
## Distance limits as multiples of the span; the default framing is about two spans away.
const MIN_SPANS := 0.6
const MAX_SPANS := 20.0
const DEFAULT_SPANS := 2.0
const CLEARANCE_M := 0.3
## CAM-29: the camera eases toward the dragged azimuth, elevation and distance (half-life, s): a wheel notch or a jerky
## mouse no longer jumps the picture, and 94 % of a flick shows within 0.2 s.
const EASE_HALF_LIFE := 0.05

## Goals set by drag, wheel and keys; the camera shows _azimuth, _elevation and _distance as they ease toward them.
var azimuth_deg := 0.0 # where the camera sits, seen from the CG: 0 = north of it, 90 = east
var elevation_deg := 20.0
var distance := 3.0
## CAM-17 player settings: turn rate multiplier and vertical drag direction.
var sensitivity := 1.0
var invert_y := false
var _azimuth := 0.0
var _elevation := 20.0
var _distance := 3.0
var _span := 1.5
var _guard := CameraCollision.BoomGuard.new()


func configure(span: float) -> void:
	_span = maxf(span, 0.3)
	distance = DEFAULT_SPANS * _span
	snap()


## The shown pose takes the goals at once (view entry, reset).
func snap() -> void:
	_guard.reset()
	_azimuth = azimuth_deg
	_elevation = elevation_deg
	_distance = distance


## Starts the orbit in the direction of an existing camera (continuity when switching views); from farther than
## the orbit reaches (the pilot station) it keeps the direction at the default distance.
func start_from(eye: Vector3, target: Vector3) -> void:
	var offset := eye - target
	if offset.length() < 1e-3:
		return
	distance = offset.length() if offset.length() <= MAX_SPANS * _span else DEFAULT_SPANS * _span
	distance = maxf(distance, MIN_SPANS * _span)
	elevation_deg = clampf(rad_to_deg(asin(clampf(offset.y / offset.length(), -1.0, 1.0))), MIN_ELEVATION_DEG, MAX_ELEVATION_DEG)
	var flat := CameraMath.horizontal_dir(offset)
	if flat != Vector3.ZERO:
		azimuth_deg = rad_to_deg(CameraMath.heading_of(flat))
	snap()


## Starts behind and to the left of the airplane's nose, slightly above (a flight that begins in this view).
func start_behind(body: Basis) -> void:
	reset()
	var nose := CameraMath.horizontal_dir(-body.z, 0.05)
	azimuth_deg = wrapf(rad_to_deg(CameraMath.heading_of(nose)) + 180.0 + 35.0 if nose != Vector3.ZERO else 0.0, -180.0, 180.0)
	snap()


func rotate(pixels: Vector2) -> void:
	var rate := DEGREES_PER_PIXEL * sensitivity
	azimuth_deg = wrapf(azimuth_deg - pixels.x * rate, -180.0, 180.0)
	elevation_deg = clampf(elevation_deg + pixels.y * rate * (-1.0 if invert_y else 1.0), MIN_ELEVATION_DEG, MAX_ELEVATION_DEG)


## The distance on screen while it eases toward `distance`.
func shown_distance() -> float:
	return _distance


## factor < 1 moves in, > 1 moves out.
func dolly(factor: float) -> void:
	distance = clampf(distance * factor, MIN_SPANS * _span, MAX_SPANS * _span)


func reset() -> void:
	azimuth_deg = 0.0
	elevation_deg = 20.0
	distance = DEFAULT_SPANS * _span
	snap()


## ground_y: Callable(x, z) → terrain height (render y); dt: frame time the shown pose eases by (INF snaps to the
## goals, 0 holds); obstacles: Callable(from, to) → share of that boom clear of scenery (CAM-09).
## Returns { position, basis, fov }.
func update(target: Vector3, ground_y: Callable, dt := INF, obstacles := Callable()) -> Dictionary:
	if is_inf(dt):
		snap()
	elif dt > 0.0:
		var f := CameraMath.damp_factor(dt, EASE_HALF_LIFE)
		_azimuth = wrapf(_azimuth + angle_difference(deg_to_rad(_azimuth), deg_to_rad(azimuth_deg)) * f * 180.0 / PI, -180.0, 180.0)
		_elevation = lerpf(_elevation, elevation_deg, f)
		_distance = lerpf(_distance, distance, f)
	var el := deg_to_rad(_elevation)
	var dir := CameraMath.dir_of_heading(deg_to_rad(_azimuth)) * cos(el) + Vector3.UP * sin(el)
	var eye := target + dir * _distance
	if obstacles.is_valid():
		# CAM-09: turned into a hangar or a tree, the orbit comes in front of it instead of looking from inside.
		var clear := maxf(float(obstacles.call(target, eye)) * _distance, MIN_SPANS * _span * 0.5)
		var length := _guard.update(clear, _distance, 0.0 if is_inf(dt) else dt)
		if length < _distance:
			eye = target + dir * length
	var floor_y := 0.0
	if ground_y.is_valid():
		var y: float = ground_y.call(eye.x, eye.z)
		floor_y = y if is_finite(y) else 0.0
	eye.y = maxf(eye.y, floor_y + CLEARANCE_M)
	return { position = eye, basis = CameraMath.look_basis(eye, target), fov = FOV_DEG }
